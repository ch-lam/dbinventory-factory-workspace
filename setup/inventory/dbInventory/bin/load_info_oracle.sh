#!/bin/bash
# =============================================================================
# load_info_oracle  –  Charge les fichiers .csv Oracle dans Oracle via SQLcl
#
# Prérequis : SQLcl 22.x+  (commande : sql)
#
# Les fichiers .csv sont produits par get_info avec les colonnes dans l'ordre
# des tables Oracle (chargement positionnel, sans header).
# Format configuré une fois via SET LOADFORMAT ; commandes LOAD simples ensuite.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Cible SQLcl ───────────────────────────────────────────────────────────────
# Base visée : DBINVENTORY_TARGET (prod par defaut, ou test) avec les secrets du
# .env, ou DBINVENTORY_CONN_NAME pour une connexion SQLcl nommee. C'est ce qui
# permet de charger un jeu de donnees de demonstration dans une autre base sans
# toucher au staging du dev, que cette machine ne peut pas recollecter -- le
# chargement commence par TRUNCATE. Voir _dbinventory_env.sh.
source "${SCRIPT_DIR}/_dbinventory_env.sh"
dbinv_sqlcl_args

# Les LOAD lisent ../collect en chemin RELATIF, que SQLcl resout depuis son
# repertoire courant. Sous cron ce n'est pas bin/ : on s'y place. Un chemin
# absolu ne conviendrait pas sous Git Bash, ou SQLcl est un binaire Windows qui
# ne sait pas lire /g/...
cd "${SCRIPT_DIR}"

MAIL_TO="lambert.christophe@chl.lu"


# ── Log ───────────────────────────────────────────────────────────────────────
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/load_oracle_$(date '+%Y%m%d_%H%M%S').log"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# Parse le log SQLcl et reporte les erreurs par fichier CSV.
# Utilise les lignes de synthèse SQLcl (WARNING / #INFO rows in error / ORA-).
# Retourne 1 si au moins une erreur détectée.
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
        log "Chargement OK — aucune erreur détectée."
    fi
}

# =============================================================================
# Session SQLcl unique : TRUNCATE + LOAD
# =============================================================================
log "Chargement des fichiers .csv Oracle dans Oracle..."
log "Log : ${LOG_FILE}"

# oracle_sec_net_enc_audit.csv n'est produit que depuis le 2026-11-11. Une
# collecte plus ancienne (archive de data/, ou serveur pas encore à jour) ne le
# porte pas, et le LOAD manquant arrêterait tout le chargement. Le fichier
# absent vaut « aucune base en REQUESTED » : on le crée vide, en le disant.
# Ce garde-fou ne vaut que pour ce fichier : l'absence de tout autre CSV reste
# une collecte cassée.
if [[ ! -f ../collect/oracle_sec_net_enc_audit.csv ]]; then
    log "  oracle_sec_net_enc_audit.csv absent (collecte antérieure au 2026-11-11) : chargé vide"
    : > ../collect/oracle_sec_net_enc_audit.csv
fi

SQLCL_EXIT=0
sql "${SQLCL_ARGS[@]}" <<'SQLCL_SESSION' 2>&1 | tee "${LOG_FILE}" || SQLCL_EXIT="${PIPESTATUS[0]}"
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET FEEDBACK OFF
SET ECHO     OFF

ALTER SESSION SET NLS_DATE_FORMAT      = 'YYYY-MM-DD HH24:MI:SS';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF';

-- ===========================================================================
-- TRUNCATE des tables de staging  (DDL – auto-commit Oracle)
-- ===========================================================================
TRUNCATE TABLE oracle_hosts;
TRUNCATE TABLE oracle_users;
TRUNCATE TABLE oracle_services;
TRUNCATE TABLE oracle_pdbs;
TRUNCATE TABLE oracle_databases;
TRUNCATE TABLE oracle_dataguard;
TRUNCATE TABLE oracle_psu;
TRUNCATE TABLE oracle_lms;
TRUNCATE TABLE oracle_client_version;
TRUNCATE TABLE oracle_backup;
TRUNCATE TABLE oracle_sec_admin_high_privs;
TRUNCATE TABLE oracle_security_audit_enable;
TRUNCATE TABLE oracle_sec_default_profile;
TRUNCATE TABLE oracle_sec_default_user_pwd;
TRUNCATE TABLE oracle_sec_high_role_privs;
TRUNCATE TABLE oracle_sec_high_sys_privs;
TRUNCATE TABLE oracle_sec_high_tab_privs;
TRUNCATE TABLE oracle_sec_network_encryption;
TRUNCATE TABLE oracle_sec_net_enc_audit;
TRUNCATE TABLE oracle_security_parameter;
TRUNCATE TABLE oracle_security_profile;
TRUNCATE TABLE oracle_security_tablespace;
TRUNCATE TABLE oracle_sec_usermig_tbl_exist;
TRUNCATE TABLE oracle_metrics_cpu_memory;
TRUNCATE TABLE oracle_metrics_cpu_service;
TRUNCATE TABLE oracle_size_usage;
TRUNCATE TABLE oracle_size_usage_seg;

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
-- oracle_backup.start_time/end_time sont des TIMESTAMP : sans ce format, SQLcl
-- retombe sur NLS_TIMESTAMP_FORMAT (…SS.FF) et rejette les valeurs sans fraction
-- de seconde (GDK-05040). Aucune autre table Oracle ne charge de timestamp
-- depuis le CSV (leur date_value est en dernière position, avec un DEFAULT).
SET LOAD TIMESTAMP_FORMAT YYYY-MM-DD HH24:MI:SS

-- ===========================================================================
-- ORACLE – Inventaire
-- ===========================================================================

PROMPT -- LOADING: ../collect/oracle_hosts.csv
LOAD oracle_hosts ../collect/oracle_hosts.csv
PROMPT -- LOADING: ../collect/oracle_users.csv
LOAD oracle_users ../collect/oracle_users.csv
PROMPT -- LOADING: ../collect/oracle_services.csv
LOAD oracle_services ../collect/oracle_services.csv
PROMPT -- LOADING: ../collect/oracle_pdbs.csv
LOAD oracle_pdbs ../collect/oracle_pdbs.csv
PROMPT -- LOADING: ../collect/oracle_databases.csv
LOAD oracle_databases ../collect/oracle_databases.csv
PROMPT -- LOADING: ../collect/oracle_dataguard.csv
LOAD oracle_dataguard ../collect/oracle_dataguard.csv
PROMPT -- LOADING: ../collect/oracle_psu.csv
LOAD oracle_psu ../collect/oracle_psu.csv
PROMPT -- LOADING: ../collect/oracle_lms.csv
LOAD oracle_lms ../collect/oracle_lms.csv
PROMPT -- LOADING: ../collect/oracle_client_version.csv
LOAD oracle_client_version ../collect/oracle_client_version.csv
PROMPT -- LOADING: ../collect/oracle_backup.csv
LOAD oracle_backup ../collect/oracle_backup.csv

-- ===========================================================================
-- ORACLE – Sécurité
-- ===========================================================================

PROMPT -- LOADING: ../collect/oracle_sec_admin_high_privs.csv
LOAD oracle_sec_admin_high_privs ../collect/oracle_sec_admin_high_privs.csv
PROMPT -- LOADING: ../collect/oracle_sec_default_user_pwd.csv
LOAD oracle_sec_default_user_pwd ../collect/oracle_sec_default_user_pwd.csv
PROMPT -- LOADING: ../collect/oracle_sec_high_role_privs.csv
LOAD oracle_sec_high_role_privs ../collect/oracle_sec_high_role_privs.csv
PROMPT -- LOADING: ../collect/oracle_sec_high_sys_privs.csv
LOAD oracle_sec_high_sys_privs ../collect/oracle_sec_high_sys_privs.csv
PROMPT -- LOADING: ../collect/oracle_sec_high_tab_privs.csv
LOAD oracle_sec_high_tab_privs ../collect/oracle_sec_high_tab_privs.csv
PROMPT -- LOADING: ../collect/oracle_security_profile.csv
LOAD oracle_security_profile ../collect/oracle_security_profile.csv
PROMPT -- LOADING: ../collect/oracle_sec_default_profile.csv
LOAD oracle_sec_default_profile ../collect/oracle_sec_default_profile.csv
PROMPT -- LOADING: ../collect/oracle_security_parameter.csv
LOAD oracle_security_parameter ../collect/oracle_security_parameter.csv
PROMPT -- LOADING: ../collect/oracle_security_audit_enable.csv
LOAD oracle_security_audit_enable ../collect/oracle_security_audit_enable.csv
PROMPT -- LOADING: ../collect/oracle_security_tablespace.csv
LOAD oracle_security_tablespace ../collect/oracle_security_tablespace.csv
PROMPT -- LOADING: ../collect/oracle_sec_usermig_tbl_exist.csv
LOAD oracle_sec_usermig_tbl_exist ../collect/oracle_sec_usermig_tbl_exist.csv
PROMPT -- LOADING: ../collect/oracle_sec_network_encryption.csv
LOAD oracle_sec_network_encryption ../collect/oracle_sec_network_encryption.csv
PROMPT -- LOADING: ../collect/oracle_sec_net_enc_audit.csv
LOAD oracle_sec_net_enc_audit ../collect/oracle_sec_net_enc_audit.csv

-- ===========================================================================
-- ORACLE – Capacity Planning
-- ===========================================================================

PROMPT -- LOADING: ../collect/oracle_size_usage.csv
LOAD oracle_size_usage ../collect/oracle_size_usage.csv
PROMPT -- LOADING: ../collect/oracle_size_usage_seg.csv
LOAD oracle_size_usage_seg ../collect/oracle_size_usage_seg.csv
PROMPT -- LOADING: ../collect/oracle_metrics_cpu_memory.csv
LOAD oracle_metrics_cpu_memory ../collect/oracle_metrics_cpu_memory.csv
PROMPT -- LOADING: ../collect/oracle_metrics_cpu_service.csv
LOAD oracle_metrics_cpu_service ../collect/oracle_metrics_cpu_service.csv

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
    log "SQLcl a terminé avec une erreur (code ${SQLCL_EXIT}) — voir ${LOG_FILE}"
    send_error_mail "dbInventory Oracle — erreur SQLcl (code ${SQLCL_EXIT})" \
        "$(grep -E 'ORA-[0-9]+|Error report' "${LOG_FILE}" | head -20)"
    exit 1
fi

parse_load_log "${LOG_FILE}" || {
    send_error_mail "dbInventory Oracle — erreurs de chargement" \
        "$(grep -E '^-- LOADING:|WARNING:|#INFO Number of rows in error' "${LOG_FILE}" | grep -A1 'WARNING')"
    exit 1
}

# =============================================================================
# Archivage des fichiers .csv Oracle
# =============================================================================
# Desactive (DBINVENTORY_ARCHIVE=0) par les chargements de test : ils relisent
# les CSV que le chargement de production a deja archives.
if [[ "${DBINVENTORY_ARCHIVE:-1}" == "1" ]]; then
    DIR_TIME=$(date '+%y%m%d%H%M%S')
    mkdir -p "../collect/${DIR_TIME}"
    cp ../collect/oracle_*.csv "../collect/${DIR_TIME}/"
    log "Fichiers archivés dans ../collect/${DIR_TIME}/"
fi
log "Chargement terminé."
