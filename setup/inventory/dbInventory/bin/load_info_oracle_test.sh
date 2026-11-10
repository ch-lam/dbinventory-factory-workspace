#!/bin/bash
# =============================================================================
# load_info_oracle_test.sh — Charge les CSV Oracle dans la base de TEST
#
# Même script que la production, load_info_oracle.sh, sur la base désignée par
# DBINVENTORY_TEST_PASS / DBINVENTORY_TEST_DSN du .env (voir _dbinventory_env.sh).
# Pas de seconde archive des CSV : la production les a déjà archivés.
# Pour toute la chaîne de test, voir dbInventory_load_test.sh.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DBINVENTORY_TARGET=test
export DBINVENTORY_ARCHIVE=0

exec "${SCRIPT_DIR}/load_info_oracle.sh" "$@"
