#!/bin/bash
# =============================================================================
# get_info_oracle_all — lance tous les scripts de collecte Oracle en séquence
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

log "=== Démarrage collecte Oracle complète ==="

log "--- Inventaire (infra + capacité) ---"
"${SCRIPT_DIR}/get_info_oracle.sh"

log "--- Sécurité ---"
"${SCRIPT_DIR}/get_info_oracle_security.sh"

log "--- LMS (feature usage) ---"
"${SCRIPT_DIR}/get_info_oracle_lms.sh"

log "--- Versions clients ---"
"${SCRIPT_DIR}/get_info_oracle_client_version.sh"

log "=== Collecte Oracle terminée ==="
