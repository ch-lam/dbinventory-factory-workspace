#!/bin/bash
#
# detect_db_engines.sh
# --------------------------------------------------------------------------
# Détecte la présence d'un moteur PostgreSQL / Oracle / MySQL-MariaDB
# sur une machine Linux, via 3 approches complémentaires :
#   1) Paquets / binaires installés (rpm + chemins connus)
#   2) Processus en cours d'exécution (pmon, postgres, mysqld/mariadbd)
#   3) Ports en écoute (mappés au processus quand possible, sinon ports standards)
#
# Prévu pour être poussé par SALT (donc exécuté en root) sur toutes les
# machines Linux. Sortie : une seule ligne ';' à colonnes fixes.
#
# Colonnes de sortie :
#   HOSTN ; PG_PKG ; PG_PROC ; PG_PORT ; ORA_PKG ; ORA_PROC ; ORA_SIDS ; ORA_PORT ; MY_PKG ; MY_PROC ; MY_PORT
#     *_PKG   = Y / N   (installé)
#     *_PROC  = nombre de processus détectés (0 = aucun)
#     *_PORT  = liste des ports en écoute (séparés par ',') ou '-'
#     ORA_SIDS= liste des SID Oracle (pmon) ou '-'
# --------------------------------------------------------------------------

# Champ vide par défaut (jamais de ';' à l'intérieur d'un champ)
EMPTY="-"

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

# ports_for <regex_processus> : liste (',') des ports TCP LISTEN dont le
# processus matche la regex. Nécessite root pour la colonne "users:" (SALT=root).
# Retourne EMPTY si rien trouvé.
ports_for() {
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
# Ports : mapping processus 'postgres', fallback port standard 5432
PG_PORT=$(ports_for 'postgres')
if [ "$PG_PORT" = "$EMPTY" ] && [ "$(std_port_listen 5432)" = "Y" ]; then PG_PORT="5432?"; fi

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
ORA_PORT=$(ports_for 'tnslsnr')
if [ "$ORA_PORT" = "$EMPTY" ] && [ "$(std_port_listen 1521)" = "Y" ]; then ORA_PORT="1521?"; fi

# --------------------------------------------------------------------------
# 3) MySQL / MariaDB
# --------------------------------------------------------------------------
# SLES fournit MariaDB ; le daemon s'appelle 'mariadbd' (>=10.5) ou 'mysqld'
MY_PKG=$(has_rpm 'mariadb|mysql-community-server|mysql-server')
if [ "$MY_PKG" = "N" ] && [ "$(has_bin mysqld mariadbd)" = "Y" ]; then MY_PKG="Y"; fi
MY_PROC=$(pgrep -xc 'mysqld|mariadbd' 2>/dev/null); [ -z "$MY_PROC" ] && MY_PROC=0
MY_PORT=$(ports_for 'mysqld|mariadbd')
if [ "$MY_PORT" = "$EMPTY" ] && [ "$(std_port_listen 3306)" = "Y" ]; then MY_PORT="3306?"; fi

# --------------------------------------------------------------------------
# Sortie
# --------------------------------------------------------------------------
echo "$HOSTN;$PG_PKG;$PG_PROC;$PG_PORT;$ORA_PKG;$ORA_PROC;$ORA_SIDS;$ORA_PORT;$MY_PKG;$MY_PROC;$MY_PORT"
