#!/bin/bash
# =============================================================================
# get_info__all.sh — lance tous les scripts de collecte de dbInventory (pour cron)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

"${SCRIPT_DIR}/get_info_oracle_all.sh"

"${SCRIPT_DIR}/get_info_mssql_all.sh"

"${SCRIPT_DIR}/get_info_postgres_all.sh"
