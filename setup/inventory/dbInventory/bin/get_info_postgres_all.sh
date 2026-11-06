#!/bin/bash
# =============================================================================
# get_info_postgres_all.sh — lance tous les scripts de collecte POSTGRES en séquence
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# Chaque collecteur sort en 1 dès qu'une instance est injoignable
# (report_errors), après avoir écrit ses CSV et envoyé son mail. Sous set -e,
# cette sortie arrêtait la séquence : une seule instance injoignable à
# l'inventaire privait TOUTES les instances de leur collecte sécurité, dont les
# CSV restaient ceux du passage précédent. Chacun tourne donc quoi qu'il
# arrive, et l'échec remonte à la fin. Même correction que get_info_oracle_all.sh.
failed=0

log "=== Démarrage collecte POSTGRES complète ==="

log "--- Inventaire (infra + capacité) ---"
"${SCRIPT_DIR}/get_info_postgres.sh"          || failed=1

log "--- Sécurité ---"
"${SCRIPT_DIR}/get_info_postgres_security.sh" || failed=1

log "=== Collecte POSTGRES terminée ==="
exit "${failed}"
