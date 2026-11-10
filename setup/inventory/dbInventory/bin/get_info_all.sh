#!/bin/bash
# =============================================================================
# get_info_all.sh — lance tous les scripts de collecte de dbInventory (pour cron)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_dbinventory_env.sh"

# Le périmètre de collecte peut être tenu de deux façons, au choix du .env :
#
#   DBINV_GEN_COLLECT_LISTS=1  les tables *_collect_list, où écrit l'application,
#       font foi. Les .lst en sont un rendu régénéré à chaque passage : sans
#       cette étape, une instance ajoutée depuis l'application ne serait jamais
#       collectée. En cas d'échec on s'arrête, plutôt que de collecter sur un
#       périmètre périmé sans le savoir.
#   DBINV_GEN_COLLECT_LISTS=0  (défaut) les .lst de collect/ sont tenus à la
#       main. C'est le fonctionnement actuel du serveur de collecte.
if [[ "${DBINV_GEN_COLLECT_LISTS:-0}" == "1" ]]; then
    "${SCRIPT_DIR}/gen_collect_lists.sh" || {
        echo "ERREUR: génération des listes de collecte impossible — collecte annulée." >&2
        exit 1
    }
fi

# Chaque moteur est collecté même si le précédent a échoué, et l'échec de l'un
# d'eux remonte à la fin : dbInventory_all.sh le journalise sans s'arrêter.
failed=0

"${SCRIPT_DIR}/get_info_oracle_all.sh"   || failed=1

"${SCRIPT_DIR}/get_info_mssql_all.sh"    || failed=1

"${SCRIPT_DIR}/get_info_postgres_all.sh" || failed=1

exit "${failed}"
