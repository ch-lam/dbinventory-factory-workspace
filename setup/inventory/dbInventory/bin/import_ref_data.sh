#!/bin/bash
# =============================================================================
# import_ref_data.sh  –  Importe dans une base dbInventory un fichier produit
#   par export_ref_data.sh.
#
# Prérequis : SQLcl 22+, base64 ; pkg_dbinv_transfer installé (V__012).
#
# Usage : import_ref_data.sh [-t test|prod] [--apply] fichier.json
#   -t       base cible (défaut : DBINVENTORY_TARGET, donc prod) ; ignoré si
#            DBINVENTORY_CONN_NAME est défini
#   --apply  importe réellement. Sans lui : SIMULATION. Tout est exécuté puis
#            annulé, le rapport est donc exactement celui d'un import réel.
#
# Règles (détail en tête de database/dbinventory/V__012_create_transfer_api.sql) :
#   - une application est reconnue par son code (app_code), jamais par son nom
#     ni par un identifiant technique ;
#   - ce que le fichier porte est créé ou mis à jour ; rien n'est retiré de la
#     cible ;
#   - un rattachement dont l'hôte, l'instance ou la base n'existe pas dans la
#     cible est ignoré et listé ;
#   - tout ou rien : si une application échoue, rien n'est écrit ;
#   - réimporter le même fichier ne change plus rien.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '8,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

APPLY=0
FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t)      [[ $# -ge 2 ]] || usage; export DBINVENTORY_TARGET="$2"; shift 2 ;;
        --apply) APPLY=1; shift ;;
        -h|--help) usage ;;
        -*)      echo "ERREUR: option inconnue : $1" >&2; usage ;;
        *)       [[ -z "${FILE}" ]] || usage; FILE="$1"; shift ;;
    esac
done
[[ -n "${FILE}" ]] || usage
if [[ ! -s "${FILE}" ]]; then
    echo "ERREUR: fichier introuvable ou vide : ${FILE}" >&2
    exit 2
fi

source "${SCRIPT_DIR}/_dbinventory_env.sh"
dbinv_sqlcl_args

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/import_ref_data_$(date '+%Y%m%d_%H%M%S').log"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Le nom du fichier part dans le journal de la base : sans apostrophe.
FILE_NAME="$(basename "${FILE}" | tr -d "'")"

# Le fichier voyage en base64, par lignes de 3000 caractères (multiple de 4 :
# chaque ligne se décode seule), regroupées par blocs PL/SQL de 10 appels.
# Le base64 ne contient ni apostrophe ni esperluette : rien à échapper.
{
    echo "set echo off feedback off heading off pagesize 0 verify off define off"
    echo "set linesize 32767 trimspool on"
    echo "set serveroutput on size unlimited format wrapped"
    echo "whenever sqlerror exit failure rollback"
    echo "exec pkg_dbinv_transfer.import_begin"
    base64 -w 3000 "${FILE}" | awk '
        NR % 10 == 1 { print "begin" }
        { print "pkg_dbinv_transfer.import_chunk(\x27" $0 "\x27);" }
        NR % 10 == 0 { print "end;"; print "/" }
        END { if (NR % 10 != 0) { print "end;"; print "/" } }'
    echo "begin"
    echo "   pkg_dbinv_transfer.import_run(p_apply => ${APPLY}, p_file_name => '${FILE_NAME}');"
    echo "end;"
    echo "/"
    echo "exit"
} > "${WORK}/import.sql"

if [[ "${APPLY}" -eq 1 ]]; then
    log "IMPORT RÉEL de ${FILE} vers ${DBINVENTORY_CONN_NAME:-${DBINVENTORY_TARGET}}"
else
    log "Simulation d'import de ${FILE} vers ${DBINVENTORY_CONN_NAME:-${DBINVENTORY_TARGET}}"
fi

SQL_RC=0
sql "${SQLCL_ARGS[@]}" < "${WORK}/import.sql" 2>&1 | tr -d '\r' | tee "${LOG_FILE}" || SQL_RC="${PIPESTATUS[0]}"

if [[ "${SQL_RC}" -ne 0 ]] || grep -qE '(ORA|PLS|SP2)-[0-9]+' "${LOG_FILE}"; then
    log "ERREUR : import en échec (code SQLcl ${SQL_RC}), rien n'a été écrit — voir ${LOG_FILE}"
    exit 1
fi
log "Terminé — journal : ${LOG_FILE}"
