#!/bin/bash
# =============================================================================
# check_baseline  –  Compare les chiffres de la base au fichier de référence
#
# Prérequis : SQLcl 22+, une connexion nommée vers la base de démonstration
#             déjà chargée par load_fixtures.sh
#
# Usage : check_baseline.sh [connexion_sqlcl] [--capture]
#         Défaut : DEMO_DBINVENTORY_dbinventory
#
#   sans --capture : joue T_003 et compare son empreinte à
#                    expected/baseline.csv. Sortie non nulle si ça diffère.
#   avec --capture : écrase expected/baseline.csv par les chiffres actuels.
#
# QUAND CAPTURER. Après un changement de règle VOULU, ou une évolution du jeu
# de données. Jamais pour faire taire un écart qu'on n'a pas expliqué : la
# valeur du fichier tient entièrement à ce qu'on refuse de le regénérer sans
# comprendre. Le diff dit exactement quels contrôles ont bougé et de combien --
# c'est la revue, le fichier n'est que le support.
#
# Le fichier est trié en SQL, pas par le shell : un tri shell dépend de la
# locale et ferait apparaître des différences qui n'existent pas.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASELINE="${SCRIPT_DIR}/expected/baseline.csv"
T003="$(cd "${SCRIPT_DIR}/checks" && pwd)/T_003_fixture_expectations.sql"

# Appels SQLcl : stdin depuis un vrai fichier, JLine en mode dumb, chemins
# convertis. Sans ce helper, SQLcl repond « java.io.IOException: Fonction
# incorrecte » a la place du resultat, et rend 0.
source "${SCRIPT_DIR}/sqlcl.sh"

DB_CONN="DEMO_DBINVENTORY_dbinventory"
CAPTURE=0
for arg in "$@"; do
    case "${arg}" in
        --capture) CAPTURE=1 ;;
        -*)        echo "ERREUR: option inconnue : ${arg}" >&2; exit 2 ;;
        *)         DB_CONN="${arg}" ;;
    esac
done

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

mkdir -p "${SCRIPT_DIR}/expected"
ACTUAL="$(mktemp)"
OUT_LOG="$(mktemp)"
trap 'rm -f "${ACTUAL}" "${OUT_LOG}"' EXIT

log "Exécution de T_003 sur ${DB_CONN}..."
sqlcl_run "${DB_CONN}" "${T003}" "${ACTUAL}" | tee "${OUT_LOG}"
SQL_RC="${PIPESTATUS[0]}"

# Deux vérifications plutôt qu'une : SQLcl rend parfois 0 malgré une erreur
# signalée dans sa sortie -- c'est le même constat qui a conduit validate.sh à
# se fier au texte du compilateur plutôt qu'au code retour.
if grep -q 'ECHEC:' "${OUT_LOG}" || [[ "${SQL_RC}" -ne 0 ]]; then
    echo "ERREUR: les assertions structurelles de T_003 ont échoué (code ${SQL_RC})." >&2
    exit 1
fi

if [[ ! -s "${ACTUAL}" ]]; then
    echo "ERREUR: T_003 n'a produit aucune empreinte. La base est-elle chargée ?" >&2
    exit 1
fi

# SQLcl écrit en CRLF sous Windows ; le fichier versionné reste en LF.
tr -d '\r' < "${ACTUAL}" | grep -v '^[[:space:]]*$' > "${ACTUAL}.clean"
mv "${ACTUAL}.clean" "${ACTUAL}"

if [[ "${CAPTURE}" -eq 1 ]]; then
    cp "${ACTUAL}" "${BASELINE}"
    log "Référence écrite : ${BASELINE} ($(wc -l < "${BASELINE}") lignes)"
    log "Relisez le diff git avant de committer : c'est la revue, pas une formalité."
    exit 0
fi

if [[ ! -f "${BASELINE}" ]]; then
    echo "ERREUR: aucun fichier de référence. Créez-le : $0 ${DB_CONN} --capture" >&2
    exit 1
fi

if diff -u "${BASELINE}" "${ACTUAL}" > /dev/null; then
    log "Conforme : $(wc -l < "${BASELINE}") mesures identiques à la référence."
    # Un avertissement ne bloque pas : le jeu a vieilli, il n'est pas cassé.
    WARNED=$(grep -c 'ATTENTION:' "${OUT_LOG}" || true)
    if [[ "${WARNED}" -gt 0 ]]; then
        log "${WARNED} avertissement(s) : le jeu a vieilli. Recharger la démo pour les lever."
    fi
    exit 0
fi

echo
echo "ÉCART avec ${BASELINE} :"
echo "  (- attendu, + observé)"
diff -u "${BASELINE}" "${ACTUAL}" | tail -n +3
echo
echo "Si le changement est voulu : $0 ${DB_CONN} --capture, puis relisez le diff git." >&2
exit 1
