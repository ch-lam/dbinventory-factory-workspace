#!/bin/bash
# =============================================================================
# get_info__all.sh — lance tous les scripts de collecte de dbInventory (pour cron)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Le périmètre de collecte est tenu dans les tables *_collect_list, où écrit
# l'application. Les .lst en sont un rendu régénéré à chaque passage : sans
# cette étape, une instance ajoutée depuis l'application ne serait jamais
# collectée. En cas d'échec on s'arrête, plutôt que de collecter sur un
# périmètre périmé sans le savoir.
"${SCRIPT_DIR}/gen_collect_lists.sh" || {
    echo "ERREUR: génération des listes de collecte impossible — collecte annulée." >&2
    exit 1
}

"${SCRIPT_DIR}/get_info_oracle_all.sh"

"${SCRIPT_DIR}/get_info_mssql_all.sh"

"${SCRIPT_DIR}/get_info_postgres_all.sh"
