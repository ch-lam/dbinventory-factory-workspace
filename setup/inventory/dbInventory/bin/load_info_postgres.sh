#!/bin/bash
# =============================================================================
# load_info_postgres  –  Charge les fichiers .csv PostgreSQL dans Oracle via SQLcl
#
# Prerequis : SQLcl 22.x+  (commande : sql)
#
# Les fichiers .csv sont produits par get_info avec les colonnes dans l'ordre
# des tables Oracle (chargement positionnel, sans header).
# Format configure une fois via SET LOADFORMAT ; commandes LOAD simples ensuite.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Connexion Oracle ──────────────────────────────────────────────────────────
DBINVENTORY_USER="dbinventory"
DBINVENTORY_PASS="uEjAYCnXhgbw3IputZCJbeMFKwGBvi"
DBINVENTORY_DSN="ORA-DEV:1521/DBINVENTORY_TST"
MAIL_TO="lambert.christophe@chl.lu"

# ── Log ───────────────────────────────────────────────────────────────────────
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/load_postgres_$(date '+%Y%m%d_%H%M%S').log"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# Parse le log SQLcl et reporte les erreurs par fichier CSV.
# Utilise les lignes de synthese SQLcl (WARNING / #INFO rows in error / ORA-).
# Retourne 1 si au moins une erreur detectee.
parse_load_log() {
    local log="$1"
    local current_csv="" rows_in_error="" ora_error="" files_in_error=0

    while IFS= read -r line; do
        case "${line}" in
            "-- LOADING: "*)
                current_csv="${line#-- LOADING: }"
                rows_in_error=""
                ora_error=""
                ;;
            "#INFO Number of rows in error: "*)
                rows_in_error="${line#*: }"
                ;;
            "#ERROR ORA-"*)
                [[ -z "${ora_error}" ]] && ora_error="${line#"#ERROR "}"
                ;;
            "WARNING: Processed with errors")
                log "  [ERREUR] ${current_csv} — ${rows_in_error} ligne(s) en erreur"
                [[ -n "${ora_error}" ]] && log "           ${ora_error}"
                (( files_in_error++ )) || true
                ;;
        esac
    done < "${log}"

    if [[ "${files_in_error}" -gt 0 ]]; then
        log "Total : ${files_in_error} fichier(s) en erreur — voir ${log}"
        return 1
    else
        log "Chargement OK — aucune erreur detectee."
    fi
}

# =============================================================================
# Session SQLcl unique : TRUNCATE + LOAD
# =============================================================================
log "Chargement des fichiers .csv PostgreSQL dans Oracle..."
log "Log : ${LOG_FILE}"

SQLCL_EXIT=0
sql -S "${DBINVENTORY_USER}/${DBINVENTORY_PASS}@${DBINVENTORY_DSN}" <<'SQLCL_SESSION' 2>&1 | tee "${LOG_FILE}" || SQLCL_EXIT="${PIPESTATUS[0]}"
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET FEEDBACK OFF
SET ECHO     OFF

ALTER SESSION SET NLS_DATE_FORMAT      = 'YYYY-MM-DD HH24:MI:SS';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF';

-- ===========================================================================
-- TRUNCATE des tables de staging  (DDL – auto-commit Oracle)
-- ===========================================================================
TRUNCATE TABLE postgres_hosts;
TRUNCATE TABLE postgres_databases;
TRUNCATE TABLE postgres_replication;
TRUNCATE TABLE postgres_backup;
TRUNCATE TABLE postgres_extensions;
TRUNCATE TABLE postgres_security_parameter;
TRUNCATE TABLE postgres_security_roles;
TRUNCATE TABLE postgres_sec_role_members;
TRUNCATE TABLE postgres_security_hba_rules;
TRUNCATE TABLE postgres_sec_db_privs;

-- ===========================================================================
-- SQLcl : configuration du format de chargement
-- ===========================================================================
SET LOADFORMAT CSV
SET LOADFORMAT COLUMN_NAMES OFF
SET LOADFORMAT DELIMITER ,
SET LOADFORMAT ENCLOSURES "
SET LOAD SCAN_ROWS 0
SET LOAD ERRORS UNLIMITED
SET LOAD BATCHES_PER_COMMIT 0
SET LOAD COMMIT OFF

-- ===========================================================================
-- PostgreSQL – Inventaire
-- ===========================================================================

PROMPT -- LOADING: ../collect/postgres_hosts.csv
LOAD postgres_hosts       ../collect/postgres_hosts.csv
PROMPT -- LOADING: ../collect/postgres_databases.csv
LOAD postgres_databases   ../collect/postgres_databases.csv
PROMPT -- LOADING: ../collect/postgres_replication.csv
LOAD postgres_replication ../collect/postgres_replication.csv
PROMPT -- LOADING: ../collect/postgres_backup.csv
LOAD postgres_backup      ../collect/postgres_backup.csv
PROMPT -- LOADING: ../collect/postgres_extensions.csv
LOAD postgres_extensions  ../collect/postgres_extensions.csv

-- ===========================================================================
-- PostgreSQL – Securite
-- ===========================================================================

PROMPT -- LOADING: ../collect/postgres_security_parameter.csv
LOAD postgres_security_parameter           ../collect/postgres_security_parameter.csv
PROMPT -- LOADING: ../collect/postgres_security_roles.csv
LOAD postgres_security_roles               ../collect/postgres_security_roles.csv
PROMPT -- LOADING: ../collect/postgres_sec_role_members.csv
LOAD postgres_sec_role_members             ../collect/postgres_sec_role_members.csv
PROMPT -- LOADING: ../collect/postgres_security_hba_rules.csv
LOAD postgres_security_hba_rules           ../collect/postgres_security_hba_rules.csv
PROMPT -- LOADING: ../collect/postgres_sec_db_privs.csv
LOAD postgres_sec_db_privs                 ../collect/postgres_sec_db_privs.csv

-- Commit final pour valider tous les chargements
COMMIT;
EXIT;
SQLCL_SESSION


# =============================================================================
# Analyse du log
# =============================================================================
log "Analyse du log de chargement..."

send_error_mail() {
    local subject="$1" body="$2"
    mailx -s "${subject}" "${MAIL_TO}" <<EOF
${body}

Log complet : ${LOG_FILE}
EOF
}

if [[ "${SQLCL_EXIT}" -ne 0 ]]; then
    log "SQLcl a termine avec une erreur (code ${SQLCL_EXIT}) — voir ${LOG_FILE}"
    send_error_mail "dbInventory PostgreSQL — erreur SQLcl (code ${SQLCL_EXIT})" \
        "$(grep -E 'ORA-[0-9]+|Error report' "${LOG_FILE}" | head -20)"
    exit 1
fi

parse_load_log "${LOG_FILE}" || {
    send_error_mail "dbInventory PostgreSQL — erreurs de chargement" \
        "$(grep -E '^-- LOADING:|WARNING:|#INFO Number of rows in error' "${LOG_FILE}" | grep -A1 'WARNING')"
    exit 1
}

# =============================================================================
# Archivage des fichiers .csv PostgreSQL
# =============================================================================
DIR_TIME=$(date '+%y%m%d%H%M%S')
mkdir -p "../collect/${DIR_TIME}"
cp ../collect/postgres*.csv "../collect/${DIR_TIME}/"

log "Fichiers archives dans ../collect/${DIR_TIME}/"
log "Chargement termine."
