#!/bin/bash
# =============================================================================
# export_ref_data.sh  –  Exporte ce qui est SAISI dans dbInventory (et non
#   collecté) vers un fichier JSON, réimportable par import_ref_data.sh dans
#   une autre base : test -> prod, ou avant une réinstallation.
#
# Prérequis : SQLcl 22+, base64 ; pkg_dbinv_transfer installé (V__012).
#
# Usage : export_ref_data.sh [-t test|prod] [-a CODE1,CODE2] [-o fichier.json]
#   -t  base source (défaut : DBINVENTORY_TARGET, donc prod) ; ignoré si
#       DBINVENTORY_CONN_NAME est défini
#   -a  codes applicatifs à exporter, séparés par des virgules (défaut : toutes
#       les applications actives)
#   -o  fichier produit (défaut : ./dbinventory_applications_<cible>_<date>.json)
#
# Exemple, de test vers prod :
#   ./export_ref_data.sh -t test -o /tmp/apps.json
#   ./import_ref_data.sh -t prod /tmp/apps.json            # simulation
#   ./import_ref_data.sh -t prod --apply /tmp/apps.json    # import réel
#
# Contenu : registre applicatif (applications actives, groupes, contacts,
# rattachements, documents fichier compris, sources). Aucun identifiant
# technique : les rattachements partent sous forme de noms (plateforme, hôte,
# instance, base) et sont résolus à nouveau dans la base cible. Le détail est en
# tête de database/dbinventory/V__012_create_transfer_api.sql.
#
# Le fichier contient des noms, des adresses et des documents : à traiter comme
# une donnée interne, à ne pas laisser traîner, à ne jamais versionner.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '9,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

APPS=""
OUT=""
while getopts "t:a:o:h" opt; do
    case "${opt}" in
        t) export DBINVENTORY_TARGET="${OPTARG}" ;;
        a) APPS="${OPTARG}" ;;
        o) OUT="${OPTARG}" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || usage

# Les codes partent dans un littéral SQL : on n'accepte que ce qu'un app_code
# peut contenir.
if [[ -n "${APPS}" && ! "${APPS}" =~ ^[A-Za-z0-9_,\ -]+$ ]]; then
    echo "ERREUR: -a « ${APPS} » : lettres, chiffres, _ et - seulement, séparés par des virgules." >&2
    exit 2
fi

source "${SCRIPT_DIR}/_dbinventory_env.sh"
dbinv_sqlcl_args

OUT="${OUT:-./dbinventory_applications_${DBINVENTORY_TARGET}_$(date '+%Y%m%d_%H%M%S').json}"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

cat > "${WORK}/export.sql" <<SQL
set echo off feedback off heading off pagesize 0 verify off
set linesize 32767 trimspool on long 100000000
set serveroutput on size unlimited format wrapped
whenever sqlerror exit failure
begin
   pkg_dbinv_transfer.print_export(p_app_codes => '${APPS}');
end;
/
exit
SQL

log "Export depuis ${DBINVENTORY_CONN_NAME:-${DBINVENTORY_TARGET}}..."
SQL_RC=0
sql "${SQLCL_ARGS[@]}" < "${WORK}/export.sql" > "${WORK}/out.txt" 2>&1 || SQL_RC=$?
tr -d '\r' < "${WORK}/out.txt" > "${WORK}/out.lf"

# Le document voyage en base64 (lignes B64:), le bilan en clair (lignes MSG:).
# Tout le reste est du bruit SQLcl, ou une erreur.
if [[ "${SQL_RC}" -ne 0 ]] || grep -qE '(ORA|PLS|SP2)-[0-9]+' "${WORK}/out.lf"; then
    grep -v '^B64:' "${WORK}/out.lf" >&2
    echo "ERREUR: export en échec (code SQLcl ${SQL_RC}). Aucun fichier écrit." >&2
    exit 1
fi

grep '^B64:' "${WORK}/out.lf" | cut -c5- > "${WORK}/doc.b64"
if [[ ! -s "${WORK}/doc.b64" ]] || ! base64 -d "${WORK}/doc.b64" > "${WORK}/doc.json" 2>/dev/null; then
    cat "${WORK}/out.lf" >&2
    echo "ERREUR: la sortie de SQLcl ne contient pas de document lisible. Aucun fichier écrit." >&2
    exit 1
fi
if [[ "$(head -c 1 "${WORK}/doc.json")" != "{" ]]; then
    echo "ERREUR: le document décodé n'est pas du JSON. Aucun fichier écrit." >&2
    exit 1
fi

mv "${WORK}/doc.json" "${OUT}"
chmod 600 "${OUT}" 2>/dev/null || true
grep '^MSG:' "${WORK}/out.lf" | cut -c5- >&2
log "Fichier écrit : ${OUT} ($(wc -c < "${OUT}") octets)"
