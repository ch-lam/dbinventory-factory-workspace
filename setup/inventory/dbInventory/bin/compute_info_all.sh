#!/bin/bash
# =============================================================================
# compute_info_all.sh  –  via SQLcl execute les procedures stockees pour charger
#   les metriques/dimensions et les scores a partir des donnees brutes.
#
# Prérequis : SQLcl 22.x+  (commande : sql)
#
# A lancer APRES un chargement reussi du staging (load_info_all.sh) : les
# loaders commencent par TRUNCATE, un staging dont le chargement a echoue est
# vide ou partiel, et les scores calcules dessus seraient faux.
# dbInventory_all.sh fait respecter cet ordre.
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
# nommee a la place, comme dans les load_info_*.sh.
if [[ -n "${DBINVENTORY_CONN_NAME:-}" ]]; then
    SQLCL_ARGS=( -S -name "${DBINVENTORY_CONN_NAME}" )
else
    SQLCL_ARGS=( -S "${DBINVENTORY_USER}/${DBINVENTORY_PASS}@${DBINVENTORY_DSN}" )
fi
MAIL_TO="lambert.christophe@chl.lu"

# ── Log ───────────────────────────────────────────────────────────────────────
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/compute_$(date '+%Y%m%d_%H%M%S').log"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

send_error_mail() {
    local subject="$1" body="$2"
    mailx -s "${subject}" "${MAIL_TO}" <<EOF
${body}

Log complet : ${LOG_FILE}
EOF
}

# =============================================================================
# Session SQLcl unique : ETL inventaire puis scoring
# =============================================================================
log "ETL inventaire puis scoring..."
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
# Deux verifications plutot qu'une : SQLcl peut rendre 0 malgre une erreur
# signalee dans sa sortie. Un appel de procedure ne produit aucune des lignes de
# synthese d'un LOAD (« rows in error », « Processed with errors ») : on cherche
# donc les erreurs Oracle elles-memes, pas un bilan de chargement.
log "Analyse du log..."

if [[ "${SQLCL_EXIT}" -ne 0 ]] || grep -qE '(ORA|PLS|SP2)-[0-9]+' "${LOG_FILE}"; then
    log "ERREUR : ETL / scoring en echec (code SQLcl ${SQLCL_EXIT}) — voir ${LOG_FILE}"
    send_error_mail "dbInventory calcul — ETL / scoring en echec (code ${SQLCL_EXIT})" \
        "$(grep -E '(ORA|PLS|SP2)-[0-9]+|Error report' "${LOG_FILE}" | head -20)"
    exit 1
fi

log "ETL et scoring termines."
