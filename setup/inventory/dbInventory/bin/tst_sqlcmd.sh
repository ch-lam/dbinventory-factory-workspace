#!/bin/bash
# =============================================================================
# tst_sqlcmd.sh  — teste le sqlcmd en exécutant un .sql avec le user de monitoring
# # =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/get_info_mssql_common.sh"

sqlcmd_run "$1" "$2" 

