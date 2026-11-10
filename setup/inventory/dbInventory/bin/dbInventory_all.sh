#!/bin/bash
# =============================================================================
# dbInventory_all.sh — collecte, chargement puis calcul de dbInventory (pour cron)
#
# Les trois etapes ne s'arretent pas sur le meme critere :
#
#   collecte  -> un echec N'ARRETE PAS la chaine. Une cible injoignable est le
#                cas courant, et chaque collecteur envoie deja son mail. Les CSV
#                d'un moteur qui n'a pas pu etre collecte sont ceux du passage
#                precedent (les loaders les copient sans les deplacer) : ils
#                portent leur propre collect_id, donc leur date, et la fraicheur
#                des scores (fact_scoring.data_as_of) le montre.
#   chargement -> un echec ARRETE la chaine. Chaque loader commence par TRUNCATE :
#                apres un echec, le staging du moteur est vide ou partiel, et
#                les scores calcules dessus seraient faux. On garde ceux de la
#                veille plutot.
#   calcul    -> compute_info_all.sh envoie son propre mail en cas d'echec.
#
# Base visee : DBINVENTORY_TARGET, prod par defaut (voir _dbinventory_env.sh).
# Le rechargement de la meme collecte dans la base de test est l'affaire de
# dbInventory_load_test.sh, a planifier apres celui-ci.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_cron_env.sh"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

log "=== Collecte ==="
"${SCRIPT_DIR}/get_info_all.sh" \
    || log "Collecte incomplete (code $?) : on charge ce qui a ete collecte."

log "=== Chargement ==="
if ! "${SCRIPT_DIR}/load_info_all.sh"; then
    log "ERREUR : chargement en echec, calcul annule. Les scores precedents restent en place."
    exit 1
fi

log "=== Calcul ==="
"${SCRIPT_DIR}/compute_info_all.sh" || exit 1

log "=== dbInventory termine ==="
