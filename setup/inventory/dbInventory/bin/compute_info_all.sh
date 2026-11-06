#!/bin/bash
# =============================================================================
# compute_info_all.sh  –  via SQLcl execute les procedures stockees pour charger
#   les metriques/dimensions et les scores a partir des donnees brutes.
#
# Prérequis : SQLcl 22.x+  (commande : sql)
#
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Connexion Oracle ──────────────────────────────────────────────────────────
DBINVENTORY_USER="dbinventory"
DBINVENTORY_PASS="Change:ME:001"
DBINVENTORY_DSN="ORA-DEV:1521/DBINVENTORY_TST"

# ── Cible SQLcl ───────────────────────────────────────────────────────────────
# Par defaut, le triplet ci-dessus : le comportement de production ne change pas.
# Si DBINVENTORY_CONN_NAME est positionnee, on passe par une connexion SQLcl
# nommee a la place. C'est ce qui permet de charger un jeu de donnees de
# demonstration dans une autre base sans toucher au staging du dev, que cette
# machine ne peut pas recollecter -- le chargement commence par TRUNCATE.
if [[ -n "${DBINVENTORY_CONN_NAME:-}" ]]; then
    SQLCL_ARGS=( -S -name "${DBINVENTORY_CONN_NAME}" )
else
    SQLCL_ARGS=( -S "${DBINVENTORY_USER}/${DBINVENTORY_PASS}@${DBINVENTORY_DSN}" )
fi
MAIL_TO="lambert.christophe@chl.lu"

# sqlcl dbinventory/Change:ME:001@ORA-DEV:1521/DBINVENTORY_TST

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
# Session SQLcl unique : Execute INVENTORY Load + Scoring
# =============================================================================
log "Execution des procedures stockees ..."
log "Log : ${LOG_FILE}"

SQLCL_EXIT=0
sql "${SQLCL_ARGS[@]}" <<'SQLCL_SESSION' 2>&1 | tee "${LOG_FILE}" || SQLCL_EXIT="${PIPESTATUS[0]}"
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET FEEDBACK ON
SET ECHO     ON

ALTER SESSION SET NLS_DATE_FORMAT      = 'YYYY-MM-DD HH24:MI:SS';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF';

Begin
  pkg_dbinv_inventory.load_all;
  pkg_dbinv_scoring.load_all;
End;
/
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
    send_error_mail "dbInventory Oracle — erreurs de procedures stockees de chargement ..." \
        "$(grep -E '^-- LOADING:|WARNING:|#INFO Number of rows in error' "${LOG_FILE}" | grep -A1 'WARNING')"
    exit 1
}

log "Chargement terminé."
