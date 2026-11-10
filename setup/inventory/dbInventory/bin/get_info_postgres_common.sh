#!/bin/bash
# =============================================================================
# get_info_postgres_common — bibliotheque commune aux scripts de collecte PostgreSQL
# A sourcer, ne pas executer directement.
# =============================================================================

MONITORING_USER="monitoring"
MAIL_TO="lambert.christophe@chl.lu"

# Base de connexion par defaut pour les requetes cluster-wide (pg_database,
# pg_settings, pg_stat_replication, pg_hba_file_rules, ...).
DEFAULT_DB="postgres"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mot de passe du compte de collecte : MONITORING_POSTGRES_PASS, lu dans le .env
# (voir _dbinventory_env.sh et ../.env.example). Jamais dans le dépôt.
source "${SCRIPT_DIR}/_dbinventory_env.sh"
dbinv_monitoring_pass postgres

LIST_DIR="${SCRIPT_DIR}/../collect"
LIST_FILE="${SCRIPT_DIR}/../collect/postgres_database_lists.lst"

# Identifiant de la collecte, au même format que côté Oracle et MSSQL
# (get_info_oracle_common.sh, get_info_mssql_common.sh). Il porte la date de
# collecte : c'est lui qui permet de dater la donnée derrière un score
# (v_entity_collect_date). finalize_lst le préfixe à chaque ligne produite.
collect_id="COLL_ID_$(date +%Y%m%d)"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
log_err() { log "ERROR: $*" >&2; printf '%s\n' "$*" >> "${LIST_DIR}/error_db.lst"; }

# Execute une requete SQL contre une instance PostgreSQL cible et retourne le
# resultat au format CSV (RFC4180, sans en-tete) pret pour LOAD SQLcl.
# Usage : psql_run host port dbname "SELECT ..."
#psql_run() {
#    local host="$1" port="$2" dbname="$3" sql="$4"
#    PGPASSWORD="${MONITORING_PASS}" psql -h "${host}" -p "${port}" -U "${MONITORING_USER}" -d "${dbname}" \
#        --csv -t -c "${sql}" # 2>/dev/null
#}
psql_run() {
    local host="$1" port="$2" dbname="$3" sql="$4"
    PGPASSWORD="${MONITORING_PASS}" psql -h "${host}" -p "${port}" -U "${MONITORING_USER}" -d "${dbname}" \
        -X -q -c "COPY (${sql}) TO STDOUT WITH (FORMAT csv, FORCE_QUOTE *)"
}

# Execute une requete SQL et retourne une simple liste de valeurs (une par ligne).
# Usage : psql_list host port dbname "SELECT datname FROM ..."
psql_list() {
    local host="$1" port="$2" dbname="$3" sql="$4"
    PGPASSWORD="${MONITORING_PASS}" psql -h "${host}" -p "${port}" -U "${MONITORING_USER}" -d "${dbname}" \
        -t -A -c "${sql}" # 2>/dev/null
}

# Verifie la disponibilite d'une instance et retourne "PRIMARY,<version_num>"
# ou "STANDBY,<version_num>".
status_check() {
    local host="$1" port="$2"
    PGPASSWORD="${MONITORING_PASS}" psql -h "${host}" -p "${port}" -U "${MONITORING_USER}" -d "${DEFAULT_DB}" \
        -t -A -c "SELECT CASE WHEN pg_is_in_recovery() THEN 'STANDBY' ELSE 'PRIMARY' END || ',' || current_setting('server_version_num')" \
        # 2>/dev/null
}

# Trie, deduplique, filtre les lignes vides, puis prefixe l'identifiant de
# collecte.
#
# Le prefixe, et non le suffixe, pour la meme raison que cote Oracle : le
# chargement SQLcl est positionnel sans en-tete, et collect_id est la premiere
# colonne des tables postgres_*. Les lignes vides sont ecartees avant, donc aucun
# prefixe orphelin.
#
# Usage : finalize_lst src_temp.csv dst.lst
finalize_lst() {
    local src="$1" dst="$2"
    [[ -f "${src}" ]] || return 0
    sort -u "${src}" \
        | grep -v '^\s*$' \
        | sed "s/^/\"${collect_id}\",/" \
        > "${dst}" || true
    rm -f "${src}"
}

# Initialise (vide) les fichiers temporaires.
# Usage : init_temps tag1 tag2 ...  → cree ${LIST_DIR}/tag1_temp.csv …
init_temps() {
    mkdir -p "${LIST_DIR}"
    local f
    for f in "$@"; do : > "${LIST_DIR}/${f}_temp.csv"; done
}

# Envoie un email d'erreur et quitte avec code 1 si error_db.lst existe.
report_errors() {
    local subject="${1:-PostgreSQL inventory: erreurs de connexion}"
    if [[ -f "${LIST_DIR}/error_db.lst" ]]; then
        mailx -s "${subject}" "${MAIL_TO}" \
            < <(printf 'Collecte impossible pour :\n'; cat "${LIST_DIR}/error_db.lst")
        exit 1
    fi
}
