#!/bin/bash
# =============================================================================
# get_info_oracle_all — lance tous les scripts de collecte Oracle en séquence
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# Chaque collecteur sort en 1 dès qu'une base est injoignable ou qu'une requête
# échoue (report_errors), après avoir écrit ses CSV et envoyé son mail. Sous
# set -e, cette sortie arrêtait la séquence : une seule erreur dans l'inventaire
# privait TOUTES les bases de leur collecte sécurité, LMS et versions clientes.
# Chacun tourne donc quoi qu'il arrive, et l'échec remonte à la fin.
failed=0

log "=== Démarrage collecte Oracle complète ==="

log "--- Inventaire (infra + capacité) ---"
"${SCRIPT_DIR}/get_info_oracle.sh"                || failed=1

log "--- Sécurité ---"
"${SCRIPT_DIR}/get_info_oracle_security.sh"       || failed=1

log "--- LMS (feature usage) ---"
"${SCRIPT_DIR}/get_info_oracle_lms.sh"            || failed=1

log "--- Versions clients ---"
"${SCRIPT_DIR}/get_info_oracle_client_version.sh" || failed=1

log "=== Collecte Oracle terminée ==="
exit "${failed}"
