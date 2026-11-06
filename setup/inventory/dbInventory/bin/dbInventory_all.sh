#!/bin/bash
# =============================================================================
# dbInventory_all.sh — lance tous les scripts de chargement de dbInventory (pour cron)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/get_info_all.sh"

"${SCRIPT_DIR}/load_info_all.sh"

"${SCRIPT_DIR}/compute_info_all.sh"
