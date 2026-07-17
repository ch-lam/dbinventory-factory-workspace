#!/bin/bash
# =============================================================================
# load_info_all.sh — lance tous les scripts de chargement de dbInventory (pour cron)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/load_info_oracle.sh"

"${SCRIPT_DIR}/load_info_mssql.sh"

"${SCRIPT_DIR}/load_info_postgres.sh"
