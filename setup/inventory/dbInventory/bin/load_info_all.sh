#!/bin/bash
# =============================================================================
# load_info_all.sh — lance tous les scripts de chargement de dbInventory (pour cron)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chaque moteur est charge meme si le precedent a echoue : ses tables de staging
# sont independantes. Mais l'echec de l'un d'eux doit remonter, sinon
# dbInventory_all.sh calculerait les scores sur un staging vide -- chaque loader
# commence par TRUNCATE. Sans ce cumul, seul le code du dernier loader sortait.
failed=0

"${SCRIPT_DIR}/load_info_oracle.sh"   || failed=1

"${SCRIPT_DIR}/load_info_mssql.sh"    || failed=1

"${SCRIPT_DIR}/load_info_postgres.sh" || failed=1

exit "${failed}"
