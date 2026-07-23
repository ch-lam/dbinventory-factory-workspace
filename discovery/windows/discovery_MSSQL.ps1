<#
.SYNOPSIS
    Inventorie les instances Microsoft SQL Server (y compris SQL Express / Developer /
    Evaluation) présentes sur les machines Windows d'un domaine Active Directory.

.DESCRIPTION
    1. Enumere les ordinateurs depuis l'AD (filtrable par OU et par systeme d'exploitation).
    2. Pour chaque machine joignable, ouvre une session CIM (WinRM, avec repli DCOM/WMI).
    3. Detecte les instances SQL Server via la base de registre (StdRegProv), ce qui capture
       aussi les instances *arretees* et fournit l'edition exacte.
    4. Croise avec Win32_Service pour connaitre l'etat du service (Running/Stopped, demarrage auto/manuel).
    5. Exporte le tout en CSV et affiche un recapitulatif en mettant en evidence
       les editions gratuites (souvent non supervisees).

.NOTES
    Prerequis :
      - Module RSAT ActiveDirectory (Import-Module ActiveDirectory) OU parametre -ComputerName.
      - Acces distant : WinRM (5985/5986) OU WMI/DCOM (135 + plage RPC). Droits admin local
        sur les cibles (compte courant ou -Credential).
      - Le pare-feu des cibles doit autoriser au moins un de ces canaux.

.EXAMPLE
    .\Get-MSSQLInventory.ps1 -Verbose

.EXAMPLE
    .\Get-MSSQLInventory.ps1 -SearchBase "OU=Serveurs,DC=chl,DC=lu" -OperatingSystemFilter "*Server*"

.EXAMPLE
    .\Get-MSSQLInventory.ps1 -ComputerName SRV01,SRV02 -Credential (Get-Credential)
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    # Racine LDAP de recherche (ex: "OU=Serveurs,DC=chl,DC=lu"). Vide = tout le domaine.
    [string]$SearchBase,

    # Filtre sur l'OS AD. "*Server*" par defaut ; mettre "*" pour inclure les postes de travail.
    [string]$OperatingSystemFilter = '*Server*',

    # Liste explicite de machines (court-circuite l'interrogation AD).
    [string[]]$ComputerName,

    # Identifiants pour l'acces distant (par defaut : contexte de l'utilisateur courant).
    [pscredential]$Credential,

    # Delai du test de connectivite (ping) en millisecondes.
    [int]$PingTimeoutMs = 1000,

    # Delai des operations CIM en secondes (evite de bloquer sur une cible lente).
    [int]$OperationTimeoutSec = 20,

    # Ports TCP a sonder en repli quand WMI est inaccessible (detection "suspicion SQL").
    # 1433 = instance par defaut. Ajoutez d'autres ports si vos instances nommees sont fixes.
    [int[]]$SqlPorts = @(1433),

    # Delai du test de port TCP en millisecondes.
    [int]$PortTimeoutMs = 2000,

    # Chemin du CSV de sortie.
    [string]$OutputCsv = ".\Inventaire_MSSQL_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# --------------------------------------------------------------------------------------
# Fonctions utilitaires
# --------------------------------------------------------------------------------------

function Get-SqlServerInstances {
    <#
        Enumere les instances SQL via StdRegProv, en balayant LES DEUX vues du registre :
          - Native 64 bits : SOFTWARE\Microsoft\Microsoft SQL Server
          - WOW6432Node    : SOFTWARE\Wow6432Node\Microsoft\Microsoft SQL Server
        Indispensable sur OS 64 bits (Windows 2008 R2 typiquement) ou une instance SQL
        32 bits n'apparait QUE sous Wow6432Node, invisible dans la vue native lue par WMI.
        Recupere ensuite edition/version/patch dans la cle Setup correspondante.
        Fonctionne aussi bien via WinRM que via DCOM.
    #>
    param([Microsoft.Management.Infrastructure.CimSession]$Session)

    $HKLM = [uint32]2147483650   # constante HKEY_LOCAL_MACHINE
    $reg  = @{ Namespace = 'root\default'; ClassName = 'StdRegProv'; CimSession = $Session; ErrorAction = 'Stop' }

    # Racines a balayer, avec l'etiquette de bitness associee.
    $roots = @(
        @{ Base = 'SOFTWARE\Microsoft\Microsoft SQL Server';            Bitness = '64-bit' }
        @{ Base = 'SOFTWARE\Wow6432Node\Microsoft\Microsoft SQL Server'; Bitness = '32-bit' }
    )

    $seen = @{}   # dedoublonnage par nom d'instance

    foreach ($root in $roots) {
        $instKey = "$($root.Base)\Instance Names\SQL"

        $enum = Invoke-CimMethod @reg -MethodName EnumValues -Arguments @{ hDefKey = $HKLM; sSubKeyName = $instKey }
        if (-not $enum.sNames) { continue }   # pas d'instance dans cette vue

        foreach ($instance in $enum.sNames) {
            if ($seen.ContainsKey($instance)) { continue }
            $seen[$instance] = $true

            # Nom interne du repertoire d'instance, ex: MSSQL15.SQLEXPRESS
            $internalId = (Invoke-CimMethod @reg -MethodName GetStringValue -Arguments @{
                hDefKey = $HKLM; sSubKeyName = $instKey; sValueName = $instance }).sValue

            $setupKey = "$($root.Base)\$internalId\Setup"

            $edition = (Invoke-CimMethod @reg -MethodName GetStringValue -Arguments @{
                hDefKey = $HKLM; sSubKeyName = $setupKey; sValueName = 'Edition' }).sValue
            $version = (Invoke-CimMethod @reg -MethodName GetStringValue -Arguments @{
                hDefKey = $HKLM; sSubKeyName = $setupKey; sValueName = 'Version' }).sValue
            $patch   = (Invoke-CimMethod @reg -MethodName GetStringValue -Arguments @{
                hDefKey = $HKLM; sSubKeyName = $setupKey; sValueName = 'PatchLevel' }).sValue

            [pscustomobject]@{
                Instance    = $instance
                InternalId  = $internalId
                Edition     = $edition
                Version     = $version
                PatchLevel  = $patch
                Bitness     = $root.Bitness
            }
        }
    }
}

function Resolve-ServiceName {
    <# Deduit le nom du service Windows a partir du nom d'instance. #>
    param([string]$InstanceName)
    if ($InstanceName -eq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$InstanceName" }
}

function Test-TcpPort {
    <#
        Teste l'ouverture d'un port TCP avec un vrai timeout (TcpClient.Connect n'en a pas).
        Utilise BeginConnect/WaitOne -> compatible PowerShell 5.1 ET 7+.
    #>
    param(
        [string]$Computer,
        [int]$Port,
        [int]$TimeoutMs = 2000
    )
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async  = $client.BeginConnect($Computer, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    }
    catch { return $false }
    finally { if ($client) { $client.Close() } }
}

# --------------------------------------------------------------------------------------
# 1. Constitution de la liste des machines
# --------------------------------------------------------------------------------------

if (-not $ComputerName) {
    Write-Verbose "Interrogation de l'Active Directory..."
    try   { Import-Module ActiveDirectory -ErrorAction Stop }
    catch { throw "Module ActiveDirectory introuvable. Installez RSAT ou utilisez -ComputerName." }

    $adParams = @{
        Filter     = "OperatingSystem -like '$OperatingSystemFilter'"
        Properties = 'OperatingSystem', 'LastLogonDate', 'DNSHostName'
    }
    if ($SearchBase) { $adParams.SearchBase = $SearchBase }

    $ComputerName = Get-ADComputer @adParams |
        Where-Object { $_.Enabled } |
        Select-Object -ExpandProperty DNSHostName |
        Where-Object { $_ }   # ecarte les objets sans DNSHostName
}

$total = $ComputerName.Count
Write-Verbose "$total machine(s) a analyser."

# --------------------------------------------------------------------------------------
# 2. Boucle de decouverte
# --------------------------------------------------------------------------------------

$results = New-Object System.Collections.Generic.List[object]
$errors  = New-Object System.Collections.Generic.List[object]
$i = 0

foreach ($computer in $ComputerName) {
    $i++
    Write-Progress -Activity 'Inventaire MSSQL' -Status "$computer ($i/$total)" `
                   -PercentComplete ([int](($i / [math]::Max($total,1)) * 100))

    # -- 1. Sonde du/des port(s) SQL. Fonctionne MEME si ICMP et WMI sont bloques :
    #       c'est ce qui permet de reperer un SQL sur lequel on n'a pas la main.
    $sqlPortOpen = $false
    $openPort    = $null
    foreach ($p in $SqlPorts) {
        if (Test-TcpPort -Computer $computer -Port $p -TimeoutMs $PortTimeoutMs) {
            $sqlPortOpen = $true; $openPort = $p; break
        }
    }

    # -- 2. Ping ICMP (informatif : certains serveurs SQL durcis le bloquent).
    $pingOk = $false
    $ping   = $null
    try {
        $ping  = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($computer, $PingTimeoutMs)
        $pingOk = ($reply.Status -eq 'Success')
    }
    catch {
        # Une PingException enveloppe generalement une erreur de resolution DNS.
        $dnsMsg = $_.Exception.InnerException.Message
        if ($dnsMsg -match 'host|resolu|resolv|inconnu|known') {
            $errors.Add([pscustomobject]@{ ComputerName = $computer; Status = "Resolution DNS echouee : $dnsMsg" })
            continue
        }
    }
    finally {
        if ($ping) { $ping.Dispose() }
    }

    # -- 3. Ni ICMP ni port SQL ne repondent -> hors ligne ou aucun SQL sur port connu.
    if (-not $sqlPortOpen -and -not $pingOk) {
        $errors.Add([pscustomobject]@{ ComputerName = $computer; Status = 'Injoignable (ni ICMP ni port SQL)' })
        continue
    }

    # -- 4. Tentative de detection complete via WMI/registre.
    #       Repli AU NIVEAU DE LA REQUETE (pas seulement a la creation de session) :
    #       DCOM d'abord (fiable pour les classes WMI classiques non-DMTF), puis WSMan.
    #       Corrige le cas ou WinRM cree la session mais rejette StdRegProv/Win32_Service
    #       ("A DMTF resource URI was used to access a non-DMTF class").
    $instances = @()
    $svc       = $null
    $wmiAccess = 'N/A'
    $wmiError  = $null
    $usedProto = $null

    foreach ($proto in @('Dcom', 'Wsman')) {
        $session = $null
        try {
            $opt = New-CimSessionOption -Protocol $proto
            $sp  = @{
                ComputerName        = $computer
                OperationTimeoutSec = $OperationTimeoutSec
                SessionOption       = $opt
                ErrorAction         = 'Stop'
            }
            if ($Credential) { $sp.Credential = $Credential }

            $session   = New-CimSession @sp
            $instances = @(Get-SqlServerInstances -Session $session)
            $svc       = Get-CimInstance -CimSession $session -ClassName Win32_Service `
                            -Filter "Name LIKE 'MSSQL%'" -ErrorAction SilentlyContinue

            $wmiAccess = 'OK'
            $usedProto = $proto
            break   # succes -> inutile d'essayer l'autre protocole
        }
        catch {
            $wmiError = $_.Exception.Message
            if ($wmiError -match 'denied|refus|0x80070005') {
                # Echec d'authentification : changer de protocole ne servira a rien.
                $wmiAccess = 'Refuse'
                break
            }
            # Autre erreur (DMTF/WSMan casse, RPC, timeout...) -> on tente le protocole suivant.
            $wmiAccess = 'Indisponible'
        }
        finally {
            if ($session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
        }
    }

    # -- 5a. Acces WMI complet avec instances trouvees -> detail exhaustif.
    if ($wmiAccess -eq 'OK' -and $instances.Count -gt 0) {
        foreach ($inst in $instances) {
            $svcName = Resolve-ServiceName -InstanceName $inst.Instance
            $service = $svc | Where-Object { $_.Name -eq $svcName } | Select-Object -First 1
            $isFree  = $inst.Edition -match 'Express|Developer|Evaluation'

            $results.Add([pscustomobject]@{
                Serveur         = $computer
                Instance        = $inst.Instance
                Service         = $svcName
                Edition         = $inst.Edition
                Version         = $inst.Version
                Patch           = $inst.PatchLevel
                EtatService     = if ($service) { $service.State }     else { 'Service absent' }
                Demarrage       = if ($service) { $service.StartMode } else { $null }
                CompteService   = if ($service) { $service.StartName } else { $null }
                Bitness         = $inst.Bitness
                EditionGratuite = [bool]$isFree
                PortSQL         = $sqlPortOpen
                AccesWMI        = 'OK'
                Protocole       = $usedProto
                Statut          = 'Detecte (acces complet)'
                Detail          = $null
            })
        }
    }
    # -- 5b. Port SQL ouvert mais WMI n'a rien donne d'exploitable -> SUSPICION.
    #        C'est le trou de perimetre : SQL probable, mais compte adm sans acces.
    elseif ($sqlPortOpen) {
        if ($wmiAccess -eq 'OK') {
            $statut   = "A verifier (port $openPort ouvert, rien en registre)"
            $accLabel = 'OK (0 instance)'
        } else {
            $statut   = "Suspecte (port $openPort ouvert, WMI $wmiAccess)"
            $accLabel = $wmiAccess
        }
        $results.Add([pscustomobject]@{
            Serveur         = $computer
            Instance        = $null
            Service         = $null
            Edition         = '(inconnue)'
            Version         = $null
            Patch           = $null
            EtatService     = $null
            Demarrage       = $null
            CompteService   = $null
            Bitness         = $null
            EditionGratuite = $null
            PortSQL         = $true
            AccesWMI        = $accLabel
            Protocole       = $null
            Statut          = $statut
            Detail          = $wmiError
        })
    }
    # -- 5c. Pas de port SQL : soit WMI OK sans instance, soit erreur WMI a tracer.
    else {
        if ($wmiAccess -eq 'OK') {
            $errors.Add([pscustomobject]@{ ComputerName = $computer; Status = 'Aucune instance SQL' })
        } else {
            $errors.Add([pscustomobject]@{ ComputerName = $computer; Status = "Erreur WMI ($wmiAccess) : $wmiError" })
        }
    }
}

Write-Progress -Activity 'Inventaire MSSQL' -Completed

# --------------------------------------------------------------------------------------
# 3. Restitution
# --------------------------------------------------------------------------------------

if ($results.Count -gt 0) {
    try {
        # Cree l'arborescence de destination si elle n'existe pas
        # (Export-Csv ne cree PAS les dossiers intermediaires et echoue sinon).
        $outDir = Split-Path -Path $OutputCsv -Parent
        if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            Write-Verbose "Dossier cree : $outDir"
        }

        $results |
            Sort-Object @{ Expression = 'EditionGratuite'; Descending = $true }, Serveur, Instance |
            Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

        Write-Host "`nCSV genere : $OutputCsv" -ForegroundColor Green
    }
    catch {
        Write-Warning "Echec de l'ecriture du CSV '$OutputCsv' : $($_.Exception.Message)"
    }
}
else {
    Write-Host "`nAucune instance SQL detectee : pas de CSV genere." -ForegroundColor DarkYellow
}

# Separation : instances pleinement detectees vs simplement suspectees (acces WMI KO).
$detected  = @($results | Where-Object { $_.Statut -like 'Detecte*' })
$suspected = @($results | Where-Object { $_.Statut -like 'Suspecte*' -or $_.Statut -like 'A verifier*' })
$free      = @($results | Where-Object EditionGratuite)

Write-Host "`n===== RECAPITULATIF =====" -ForegroundColor Cyan
Write-Host ("Machines analysees          : {0}" -f $total)
Write-Host ("Instances detectees (WMI)   : {0}" -f $detected.Count)   -ForegroundColor Green
Write-Host ("  dont editions gratuites   : {0}" -f $free.Count)       -ForegroundColor Yellow
Write-Host ("Serveurs SUSPECTES (sans acces) : {0}" -f $suspected.Count) -ForegroundColor Red

# --- LE trou de perimetre : port SQL ouvert mais compte adm sans acces WMI ---
if ($suspected.Count -gt 0) {
    Write-Host "`n--- Serveurs suspectes : SQL probable, acces adm A OBTENIR ---" -ForegroundColor Red
    $suspected | Sort-Object Serveur |
        Format-Table Serveur, AccesWMI, Statut, Detail -AutoSize -Wrap
}

if ($detected.Count -gt 0) {
    # Ventilation par edition (sur les instances reellement identifiees).
    Write-Host "--- Repartition par edition ---" -ForegroundColor Cyan
    $detected | Group-Object Edition | Sort-Object Count -Descending | ForEach-Object {
        [pscustomobject]@{
            Edition  = if ($_.Name) { $_.Name } else { '(inconnue)' }
            Nombre   = $_.Count
            Gratuite = [bool]($_.Group[0].EditionGratuite)
        }
    } | Format-Table Edition, Nombre, Gratuite -AutoSize

    # Detail complet des instances identifiees, gratuites en premier.
    Write-Host "--- Detail des instances identifiees ---" -ForegroundColor Cyan
    $detected |
        Sort-Object @{ Expression = 'EditionGratuite'; Descending = $true }, Serveur, Instance |
        Format-Table Serveur, Instance, Edition, Version, EtatService, EditionGratuite -AutoSize
}

if ($free.Count -gt 0) {
    Write-Host "--- Instances gratuites (a mettre sous suivi) ---" -ForegroundColor Yellow
    $free | Sort-Object Serveur, Instance |
        Format-Table Serveur, Instance, Edition, Version, EtatService -AutoSize
}

if ($errors.Count -gt 0) {
    Write-Host "--- Machines sans resultat / en erreur ($($errors.Count)) ---" -ForegroundColor DarkGray
    $errors | Group-Object Status | Sort-Object Count -Descending |
        Format-Table Count, Name -AutoSize
}

# Objets renvoyes au pipeline pour reutilisation eventuelle.
$results