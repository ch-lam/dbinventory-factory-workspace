#!/bin/bash
# =============================================================================
# get_collect_lists.sh  –  recupere les fichiers .lst pour la collecte a partir
#                           de la base dbInventory
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Cible SQLcl ───────────────────────────────────────────────────────────────
source "${SCRIPT_DIR}/_dbinventory_env.sh"
dbinv_sqlcl_args
MAIL_TO="lambert.christophe@chl.lu"

# ── Log ───────────────────────────────────────────────────────────────────────
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/load_mssql_$(date '+%Y%m%d_%H%M%S').log"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

log "Récupération des fichiers .lst terminée"
