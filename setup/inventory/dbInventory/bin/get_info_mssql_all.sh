#!/bin/bash
# =============================================================================
# get_info_mssql_all.sh — lance tous les scripts de collecte MSSQL  en séquence
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

log "=== Démarrage collecte MSSQL complète ==="

log "--- Inventaire (infra + capacité) ---"
"${SCRIPT_DIR}/get_info_mssql.sh"

log "--- Sécurité ---"
"${SCRIPT_DIR}/get_info_mssql_security.sh"

log "=== Collecte MSSQL terminée ==="
