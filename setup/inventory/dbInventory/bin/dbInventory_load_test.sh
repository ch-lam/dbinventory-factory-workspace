#!/bin/bash
# =============================================================================
# dbInventory_load_test.sh — recharge dans la base de TEST la collecte du jour,
#   puis y recalcule les scores (pour cron)
#
# Ne collecte rien : relit les CSV de ../collect, ceux que dbInventory_all.sh
# vient de collecter et de charger en production. À planifier après lui.
#
# Mêmes scripts que la production, seule la cible change :
#   DBINVENTORY_TARGET=test  -> DBINVENTORY_TEST_PASS / _DSN du .env
#   DBINVENTORY_ARCHIVE=0    -> pas de seconde archive des CSV, la production
#                               les a déjà archivés
# Et même règle d'arrêt : un chargement en échec annule le calcul.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_cron_env.sh"

export DBINVENTORY_TARGET=test
export DBINVENTORY_ARCHIVE=0

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

log "=== Chargement (base de test) ==="
if ! "${SCRIPT_DIR}/load_info_all.sh"; then
    log "ERREUR : chargement en echec, calcul annule. Les scores precedents restent en place."
    exit 1
fi

log "=== Calcul (base de test) ==="
"${SCRIPT_DIR}/compute_info_all.sh" || exit 1

log "=== dbInventory test termine ==="
