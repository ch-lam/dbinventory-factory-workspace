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

    # Chemin du CSV de sortie.
    [string]$OutputCsv = ".\Inventaire_MSSQL_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# --------------------------------------------------------------------------------------
# Fonctions utilitaires
# --------------------------------------------------------------------------------------

function New-DiscoveryCimSession {
    <# Ouvre une session CIM : WinRM d'abord, repli DCOM (WMI historique) si indisponible. #>
    param(
        [string]$Computer,
        [pscredential]$Cred,
        [int]$TimeoutSec
    )
    $common = @{
        ComputerName        = $Computer
        OperationTimeoutSec = $TimeoutSec
        ErrorAction         = 'Stop'
    }
    if ($Cred) { $common.Credential = $Cred }

    try {
        $wsman = New-CimSessionOption -Protocol Wsman
        return New-CimSession @common -SessionOption $wsman
    }
    catch {
        # Beaucoup de machines "prestataires" n'ont pas WinRM active -> on tente DCOM.
        $dcom = New-CimSessionOption -Protocol Dcom
        return New-CimSession @common -SessionOption $dcom
    }
}

function Get-SqlServerInstances {
    <#
        Lit HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL via StdRegProv
        pour enumerer les instances, puis recupere edition/version/patch dans la cle Setup.
        Fonctionne aussi bien via WinRM que via DCOM.
    #>
    param([Microsoft.Management.Infrastructure.CimSession]$Session)

    $HKLM = [uint32]2147483650   # constante HKEY_LOCAL_MACHINE
    $reg  = @{ Namespace = 'root\default'; ClassName = 'StdRegProv'; CimSession = $Session; ErrorAction = 'Stop' }
    $base = 'SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'

    $enum = Invoke-CimMethod @reg -MethodName EnumValues -Arguments @{ hDefKey = $HKLM; sSubKeyName = $base }
    if (-not $enum.sNames) { return }   # aucune instance SQL sur cette machine

    foreach ($instance in $enum.sNames) {
        # Nom interne du repertoire d'instance, ex: MSSQL15.SQLEXPRESS
        $internalId = (Invoke-CimMethod @reg -MethodName GetStringValue -Arguments @{
            hDefKey = $HKLM; sSubKeyName = $base; sValueName = $instance }).sValue

        $setupKey = "SOFTWARE\Microsoft\Microsoft SQL Server\$internalId\Setup"

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
        }
    }
}

function Resolve-ServiceName {
    <# Deduit le nom du service Windows a partir du nom d'instance. #>
    param([string]$InstanceName)
    if ($InstanceName -eq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$InstanceName" }
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

    # Test de connectivite rapide via .NET (compatible PowerShell 5.1 ET 7+).
    # NB : Test-Connection -TimeoutSeconds n'existe qu'a partir de PS 7.4.
    $reachable = $false
    $reason    = 'Injoignable (ping)'
    $ping      = $null
    try {
        $ping  = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($computer, $PingTimeoutMs)   # timeout en millisecondes
        $reachable = ($reply.Status -eq 'Success')
    }
    catch {
        # Une PingException enveloppe generalement une erreur de resolution DNS.
        $reachable = $false
        $msg = $_.Exception.InnerException.Message
        if ($msg -match 'host|resolu|resolv|inconnu|known') { $reason = "Resolution DNS echouee : $msg" }
    }
    finally {
        if ($ping) { $ping.Dispose() }
    }

    if (-not $reachable) {
        $errors.Add([pscustomobject]@{ ComputerName = $computer; Status = $reason })
        continue
    }

    $session = $null
    try {
        $session = New-DiscoveryCimSession -Computer $computer -Cred $Credential -TimeoutSec $OperationTimeoutSec

        # Instances depuis la base de registre (capture aussi les instances arretees).
        $instances = @(Get-SqlServerInstances -Session $session)

        # Services MSSQL* pour connaitre l'etat et le mode de demarrage.
        $svc = Get-CimInstance -CimSession $session -ClassName Win32_Service `
                 -Filter "Name LIKE 'MSSQL%'" -ErrorAction SilentlyContinue

        if (-not $instances) {
            $errors.Add([pscustomobject]@{ ComputerName = $computer; Status = 'Aucune instance SQL' })
            continue
        }

        foreach ($inst in $instances) {
            $svcName = Resolve-ServiceName -InstanceName $inst.Instance
            $service = $svc | Where-Object { $_.Name -eq $svcName } | Select-Object -First 1

            $isFree = $inst.Edition -match 'Express|Developer|Evaluation'

            $results.Add([pscustomobject]@{
                Serveur       = $computer
                Instance      = $inst.Instance
                Service       = $svcName
                Edition       = $inst.Edition
                Version       = $inst.Version
                Patch         = $inst.PatchLevel
                EtatService   = if ($service) { $service.State }     else { 'Service absent' }
                Demarrage     = if ($service) { $service.StartMode } else { $null }
                CompteService = if ($service) { $service.StartName } else { $null }
                EditionGratuite = [bool]$isFree
                NonSupervisee   = [bool]$isFree   # a affiner selon votre outil de supervision
            })
        }
    }
    catch {
        $errors.Add([pscustomobject]@{ ComputerName = $computer; Status = "Erreur : $($_.Exception.Message)" })
    }
    finally {
        if ($session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
    }
}

Write-Progress -Activity 'Inventaire MSSQL' -Completed

# --------------------------------------------------------------------------------------
# 3. Restitution
# --------------------------------------------------------------------------------------

if ($results.Count -gt 0) {
    $results | Sort-Object EditionGratuite -Descending, Serveur, Instance |
        Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
    Write-Host "`nCSV genere : $OutputCsv" -ForegroundColor Green
}

Write-Host "`n===== RECAPITULATIF =====" -ForegroundColor Cyan
Write-Host ("Machines analysees      : {0}" -f $total)
Write-Host ("Instances SQL trouvees  : {0}" -f $results.Count)
$free = $results | Where-Object EditionGratuite
Write-Host ("  dont editions gratuites : {0}" -f $free.Count) -ForegroundColor Yellow

if ($results.Count -gt 0) {
    # Ventilation par edition (toutes editions confondues).
    Write-Host "`n--- Repartition par edition ---" -ForegroundColor Cyan
    $results | Group-Object Edition | Sort-Object Count -Descending | ForEach-Object {
        [pscustomobject]@{
            Edition  = if ($_.Name) { $_.Name } else { '(inconnue)' }
            Nombre   = $_.Count
            Gratuite = [bool]($_.Group[0].EditionGratuite)
        }
    } | Format-Table Edition, Nombre, Gratuite -AutoSize

    # Detail complet de toutes les instances, gratuites listees en premier.
    Write-Host "--- Detail de toutes les instances ---" -ForegroundColor Cyan
    $results |
        Sort-Object @{ Expression = 'EditionGratuite'; Descending = $true }, Serveur, Instance |
        Format-Table Serveur, Instance, Edition, Version, EtatService, EditionGratuite -AutoSize
}

if ($free) {
    Write-Host "--- Instances gratuites (a mettre sous suivi) ---" -ForegroundColor Yellow
    $free | Sort-Object Serveur, Instance |
        Format-Table Serveur, Instance, Edition, Version, EtatService -AutoSize
}

if ($errors.Count -gt 0) {
    Write-Host "`n--- Machines sans resultat / en erreur ($($errors.Count)) ---" -ForegroundColor DarkGray
    $errors | Group-Object Status | Sort-Object Count -Descending |
        Format-Table Count, Name -AutoSize
}

# Objets renvoyes au pipeline pour reutilisation eventuelle.
$results
