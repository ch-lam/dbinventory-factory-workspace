#!/bin/bash
# =============================================================================
# compute_info_all_test.sh — Lance l'ETL et le scoring dans la base de TEST
#
# Même script que la production, compute_info_all.sh, sur la base désignée par
# DBINVENTORY_TEST_PASS / DBINVENTORY_TEST_DSN du .env (voir _dbinventory_env.sh).
# Pour toute la chaîne de test, voir dbInventory_load_test.sh.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DBINVENTORY_TARGET=test
exec "${SCRIPT_DIR}/compute_info_all.sh" "$@"
