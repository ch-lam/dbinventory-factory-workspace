#!/bin/bash
# =============================================================================
# gen_collect_lists  –  Régénère les fichiers .lst depuis la base
#
# Prérequis : SQLcl 22.x+  (commande : sql)
#
# Le périmètre de collecte est tenu dans les tables *_collect_list : c'est là
# qu'écrit l'application quand on prend une instance découverte en collecte.
# Les scripts get_info_* lisent, eux, des fichiers .lst. Ce script fait le pont,
# et doit tourner AVANT la collecte (get_info_all.sh l'appelle en tête).
#
# Formats produits, identiques à ceux attendus par get_info_* :
#   mssql    : ENVIRONMENT;LICENCE_TYPE;hostname:port
#   postgres : ENVIRONMENT;LICENCE_TYPE;hostname:port
#   oracle   : ENVIRONMENT;LICENCE_TYPE;easy_connect_tns   (host:port/service)
#
# Les entrées inactives (active = 0) sont écrites COMMENTÉES plutôt qu'omises :
# une ligne commentée porte une décision — « on connaît cette instance et on ne
# la collecte volontairement pas » — qu'une simple absence perdrait. C'est aussi
# ce qui distingue, à la relecture, un hôte écarté d'un hôte jamais vu.
#
# Usage : gen_collect_lists.sh [dossier_de_sortie]
#         Défaut : ../collect (le dossier que lisent les scripts de collecte).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-${SCRIPT_DIR}/../collect}"

# ── Connexion Oracle ──────────────────────────────────────────────────────────
DBINVENTORY_USER="dbinventory"
DBINVENTORY_PASS="uEjAYCnXhgbw3IputZCJbeMFKwGBvi"
DBINVENTORY_DSN="ORA-DEV:1521/DBINVENTORY_TST"

# Même branche que les load_info_*.sh. Sans elle ce script ne sait viser que
# la base codée en dur ci-dessus, donc il ne peut être exercé ni sur la base
# de démonstration ni ailleurs — et c'est pourtant lui qui décide, chaque
# nuit, du périmètre que la collecte va lire.
if [[ -n "${DBINVENTORY_CONN_NAME:-}" ]]; then
    SQLCL_ARGS=( -S -name "${DBINVENTORY_CONN_NAME}" )
else
    SQLCL_ARGS=( -S "${DBINVENTORY_USER}/${DBINVENTORY_PASS}@${DBINVENTORY_DSN}" )
fi

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

if [[ ! -d "${OUT_DIR}" ]]; then
    echo "ERREUR: dossier de sortie introuvable : ${OUT_DIR}" >&2
    exit 2
fi

# Les .lst sont régénérés dans un fichier temporaire puis déplacés : une session
# SQLcl qui échoue à mi-course ne doit pas laisser un périmètre tronqué derrière
# elle, que la collecte suivante prendrait pour argent comptant.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# SPOOL est exécuté par SQLcl, pas par le shell : sous Git Bash il faut lui
# donner un chemin qu'un binaire Windows sait résoudre, sinon il écrit dans
# C:\tmp\... et les contrôles ci-dessous ne trouvent aucun fichier. Sans
# effet sur le serveur Linux, où cygpath n'existe pas.
if command -v cygpath >/dev/null 2>&1; then
    SPOOL_DIR="$(cygpath -m "${TMP_DIR}")"
else
    SPOOL_DIR="${TMP_DIR}"
fi

log "Génération des listes de collecte depuis la base..."

sql "${SQLCL_ARGS[@]}" <<SQLCL_SESSION
WHENEVER SQLERROR EXIT FAILURE
SET FEEDBACK OFF
SET ECHO OFF
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 500
SET TRIMSPOOL ON
SET TERMOUT OFF

SPOOL ${SPOOL_DIR}/mssql_database_lists.lst
SELECT CASE WHEN active = 1 THEN '' ELSE '#' END
       || environment || ';' || license_type || ';' || hostname || ':' || port
  FROM mssql_collect_list
 ORDER BY upper(hostname), port;
SPOOL OFF

SPOOL ${SPOOL_DIR}/oracle_database_lists.lst
SELECT CASE WHEN active = 1 THEN '' ELSE '#' END
       || environment || ';' || license_type || ';' || easy_connect_tns
  FROM oracle_collect_list
 ORDER BY upper(collect_name);
SPOOL OFF

SPOOL ${SPOOL_DIR}/postgres_database_lists.lst
SELECT CASE WHEN active = 1 THEN '' ELSE '#' END
       || environment || ';' || license_type || ';' || hostname || ':' || port
  FROM postgres_collect_list
 ORDER BY upper(collect_name);
SPOOL OFF

EXIT;
SQLCL_SESSION

# =============================================================================
# Contrôles avant remplacement
# =============================================================================
# Un périmètre vide est presque toujours un incident (table non alimentée,
# session coupée) plutôt qu'une intention. On refuse alors d'écraser le fichier
# en place, qui reste la dernière version connue bonne.
for engine in mssql oracle postgres; do
    src="${TMP_DIR}/${engine}_database_lists.lst"

    if [[ ! -f "${src}" ]]; then
        echo "ERREUR: ${engine} — aucun fichier généré, listes inchangées." >&2
        exit 1
    fi

    # SQLcl laisse des lignes vides en fin de spool ; on les retire.
    sed -i '/^[[:space:]]*$/d' "${src}"

    actives=$(grep -cve '^[[:space:]]*$' -e '^#' "${src}" || true)
    if [[ "${actives}" -eq 0 ]]; then
        echo "ERREUR: ${engine} — 0 entrée active générée, listes inchangées." >&2
        exit 1
    fi

    total=$(wc -l < "${src}")
    mv "${src}" "${OUT_DIR}/${engine}_database_lists.lst"
    log "${engine} : ${actives} active(s) / ${total} ligne(s) -> ${OUT_DIR}/${engine}_database_lists.lst"
done

log "Terminé."
