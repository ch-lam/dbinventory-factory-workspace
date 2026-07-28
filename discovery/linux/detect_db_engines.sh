#!/bin/bash
#
# detect_db_engines.sh  (v2)
# --------------------------------------------------------------------------
# Détecte la présence d'un moteur PostgreSQL / Oracle / MySQL-MariaDB
# sur une machine Linux, via 3 approches complémentaires :
#   1) Paquets / binaires installés (rpm + chemins connus)
#   2) Processus en cours d'exécution (pmon, postgres, mysqld/mariadbd)
#   3) Ports en écoute : mapping par PID, secours par nom, sinon port standard
#
# Prévu pour être poussé par SALT (donc exécuté en root) sur toutes les
# machines Linux. Sortie : une seule ligne ';' à colonnes fixes.
#
# Changements v1 -> v2 :
#   - Le mapping port<->processus se fait d'abord par PID (pgrep + ss),
#     ce qui immunise contre les variantes de nommage (mysqld_safe,
#     chemin complet, wrapper systemd...). Le match par nom reste en secours.
#   - Le suffixe '?' sur les ports déduits est supprimé : les colonnes
#     *_PORT restent numériques et l'incertitude passe dans une colonne
#     dédiée *_PORT_GUESS (Y = port déduit du port standard, sans preuve
#     de rattachement à un processus).
#   - Option --header pour émettre la ligne d'en-tête (utile pour SQLcl LOAD).
#
# Colonnes de sortie (14) :
#   HOSTN ;
#   PG_PKG  ; PG_PROC  ; PG_PORT  ; PG_PORT_GUESS  ;
#   ORA_PKG ; ORA_PROC ; ORA_SIDS ; ORA_PORT ; ORA_PORT_GUESS ;
#   MY_PKG  ; MY_PROC  ; MY_PORT  ; MY_PORT_GUESS
#     *_PKG        = Y / N   (installé)
#     *_PROC       = nombre de processus détectés (0 = aucun)
#     *_PORT       = liste des ports en écoute (séparés par ',') ou '-'
#     *_PORT_GUESS = Y (port déduit) / N (port confirmé) / '-' (pas de port)
#     ORA_SIDS     = liste des SID Oracle (pmon) ou '-'
# --------------------------------------------------------------------------

# Champ vide par défaut (jamais de ';' à l'intérieur d'un champ)
EMPTY="-"

HEADER="HOSTN;PG_PKG;PG_PROC;PG_PORT;PG_PORT_GUESS;ORA_PKG;ORA_PROC;ORA_SIDS;ORA_PORT;ORA_PORT_GUESS;MY_PKG;MY_PROC;MY_PORT;MY_PORT_GUESS"

case "$1" in
    -h|--header) echo "$HEADER"; exit 0 ;;
esac

# Hostname : hostname
HOSTN=$(hostname)

# --------------------------------------------------------------------------
# Fonctions utilitaires
# --------------------------------------------------------------------------

# has_rpm <regex> : Y si un paquet rpm matche, N sinon
has_rpm() {
    rpm -qa 2>/dev/null | grep -iqE "$1" && echo "Y" || echo "N"
}

# has_bin <bin1> <bin2> ... : Y si un des binaires est dans le PATH, N sinon
has_bin() {
    for b in "$@"; do
        command -v "$b" >/dev/null 2>&1 && { echo "Y"; return; }
    done
    echo "N"
}

# ports_by_pid <regex_noms_processus> : liste (',') des ports TCP LISTEN
# appartenant aux PID dont le nom de processus matche exactement la regex.
# Plus robuste que le match textuel : indépendant du nom affiché par ss.
# Nécessite root pour la colonne "users:" (SALT=root). EMPTY si rien trouvé.
ports_by_pid() {
    local pids out
    pids=$(pgrep -x -d'|' "$1" 2>/dev/null)
    [ -z "$pids" ] && { echo "$EMPTY"; return; }
    out=$(ss -Hltnp 2>/dev/null \
        | grep -E "pid=($pids)," \
        | awk '{ n=split($4,a,":"); print a[n] }' \
        | sort -un | paste -sd, -)
    [ -n "$out" ] && echo "$out" || echo "$EMPTY"
}

# ports_by_name <regex_processus> : ancien comportement, conservé en secours
# (cas où le PID n'est pas exploitable mais où le nom apparaît dans ss).
ports_by_name() {
    local re="$1" out
    out=$(ss -Hltnp 2>/dev/null \
        | awk -v re="$re" '$0 ~ re { n=split($4,a,":"); print a[n] }' \
        | sort -un | paste -sd, -)
    [ -n "$out" ] && echo "$out" || echo "$EMPTY"
}

# std_port_listen <port> : Y si le port standard est en écoute (fallback si
# le mapping processus n'est pas disponible), N sinon.
std_port_listen() {
    ss -Hltn 2>/dev/null \
        | awk -v want="$1" '{ n=split($4,a,":"); if (a[n]==want) f=1 } END { exit !f }' \
        && echo "Y" || echo "N"
}

# resolve_ports <regex_pgrep> <regex_ss> <port_standard>
# Renvoie "<ports>|<guess>" :
#   ports confirmés (PID ou nom)          -> "5432|N"
#   port standard en écoute sans preuve   -> "5432|Y"
#   rien                                  -> "-|-"
resolve_ports() {
    local p
    p=$(ports_by_pid "$1")
    [ "$p" = "$EMPTY" ] && p=$(ports_by_name "$2")
    if [ "$p" != "$EMPTY" ]; then
        echo "$p|N"
    elif [ "$(std_port_listen "$3")" = "Y" ]; then
        echo "$3|Y"
    else
        echo "$EMPTY|$EMPTY"
    fi
}

# --------------------------------------------------------------------------
# 1) PostgreSQL
# --------------------------------------------------------------------------
# Paquets : postgresql*-server (SLES/community) ; sinon binaire (source, EDB, /opt...)
PG_PKG=$(has_rpm 'postgresql[0-9]*-server|postgresql-server|edb-as[0-9]*-server')
if [ "$PG_PKG" = "N" ]; then
    # Installs hors rpm : /usr/pgsql-*/bin, /opt/..., binaire dans le PATH
    if [ "$(has_bin postgres postmaster)" = "Y" ] || ls /usr/pgsql-*/bin/postgres >/dev/null 2>&1; then
        PG_PKG="Y"
    fi
fi
# Processus : le postmaster s'appelle 'postgres' (ou 'postmaster' sur anciennes versions)
PG_PROC=$(pgrep -xc 'postgres|postmaster' 2>/dev/null); [ -z "$PG_PROC" ] && PG_PROC=0
# Ports : PID -> nom -> port standard 5432
IFS='|' read -r PG_PORT PG_PORT_GUESS <<< "$(resolve_ports 'postgres|postmaster' 'postgres' 5432)"

# --------------------------------------------------------------------------
# 2) Oracle
# --------------------------------------------------------------------------
# "Installé" : Oracle n'est quasiment jamais un rpm (installeur OUI).
# On se base sur /etc/oratab, l'inventaire, puis rpm en dernier recours.
ORA_PKG="N"
if { [ -s /etc/oratab ] && grep -qE '^[^#+*].*:.*:' /etc/oratab; } \
   || [ -f /etc/oraInst.loc ] \
   || [ "$(has_rpm 'oracle-database|oracle-instantclient|oracle-ee')" = "Y" ]; then
    ORA_PKG="Y"
fi
# Processus : une instance = un ora_pmon_<SID>.
# On capture d'abord la sortie ps dans une variable : sinon, dans un pipeline,
# ps tournant en parallèle capture la ligne du 'sed s/ora_pmon_//' et s'auto-matche.
PSOUT=$(ps -eo args= 2>/dev/null)
ORA_SIDS=$(printf '%s\n' "$PSOUT" | grep -oE 'ora_pmon_[^ ]+' | sed 's/ora_pmon_//' | sort -u | paste -sd, -)
ORA_PROC=$(printf '%s' "$ORA_SIDS" | awk -F, 'NF{print NF}'); [ -z "$ORA_PROC" ] && ORA_PROC=0
[ -z "$ORA_SIDS" ] && ORA_SIDS="$EMPTY"
# Ports : le listener tourne sous 'tnslsnr' (port par défaut 1521, souvent modifié)
IFS='|' read -r ORA_PORT ORA_PORT_GUESS <<< "$(resolve_ports 'tnslsnr' 'tnslsnr' 1521)"

# --------------------------------------------------------------------------
# 3) MySQL / MariaDB
# --------------------------------------------------------------------------
# SLES fournit MariaDB ; le daemon s'appelle 'mariadbd' (>=10.5) ou 'mysqld'
MY_PKG=$(has_rpm 'mariadb|mysql-community-server|mysql-server')
if [ "$MY_PKG" = "N" ] && [ "$(has_bin mysqld mariadbd)" = "Y" ]; then MY_PKG="Y"; fi
MY_PROC=$(pgrep -xc 'mysqld|mariadbd' 2>/dev/null); [ -z "$MY_PROC" ] && MY_PROC=0
IFS='|' read -r MY_PORT MY_PORT_GUESS <<< "$(resolve_ports 'mysqld|mariadbd' 'mysqld|mariadbd' 3306)"

# --------------------------------------------------------------------------
# Sortie
# --------------------------------------------------------------------------
echo "$HOSTN;$PG_PKG;$PG_PROC;$PG_PORT;$PG_PORT_GUESS;$ORA_PKG;$ORA_PROC;$ORA_SIDS;$ORA_PORT;$ORA_PORT_GUESS;$MY_PKG;$MY_PROC;$MY_PORT;$MY_PORT_GUESS"