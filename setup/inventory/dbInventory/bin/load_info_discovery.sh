#!/bin/bash
# =============================================================================
# load_info_discovery  –  Charge les sorties de discovery dans Oracle via SQLcl
#
# Prérequis : SQLcl 22.x+  (commande : sql)
#
# Entrées attendues dans ../collect/ (déposées par les scripts de discovery,
# lancés une fois par semaine) :
#   discovery_mssql.csv  – produit par discovery/windows/discovery_MSSQL.ps1
#   discovery_linux.csv  – concaténation des lignes de detect_db_engines.sh
#
# Les deux fichiers sont optionnels : on charge ce qui est présent. Un moteur
# sans fichier ne produit pas de run, plutôt qu'un run vide qui ressemblerait à
# une discovery n'ayant rien trouvé.
#
# Contrairement au reste de la pipeline, le CSV MSSQL est chargé PAR NOM DE
# COLONNE (COLUMN_NAMES ON) : il porte un en-tête, et un chargement positionnel
# décale silencieusement tous les champs quand le producteur change sa liste de
# colonnes — c'est exactement le bug corrigé sur oracle_backup (6 colonnes pour
# une table à 7).
#
# Usage : load_info_discovery.sh [YYYY-MM-DD]
#         La date est celle du run de discovery (défaut : aujourd'hui).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT_DIR="${SCRIPT_DIR}/../collect"

# ── Connexion Oracle ──────────────────────────────────────────────────────────
DBINVENTORY_USER="dbinventory"
DBINVENTORY_PASS="Change:ME:001"
DBINVENTORY_DSN="ORA-DEV:1521/DBINVENTORY_TST"
MAIL_TO="lambert.christophe@chl.lu"

# Même branche que les trois loaders moteur : sans elle, ce script ne sait
# viser que la base codée en dur ci-dessus, et fixtures/load_fixtures.sh ne
# peut pas le détourner vers la base de démonstration. Il chargerait alors la
# discovery de démo dans la base de développement, que les garde-fous de
# load_fixtures.sh existent précisément pour protéger.
if [[ -n "${DBINVENTORY_CONN_NAME:-}" ]]; then
    SQLCL_ARGS=( -S -name "${DBINVENTORY_CONN_NAME}" )
else
    SQLCL_ARGS=( -S "${DBINVENTORY_USER}/${DBINVENTORY_PASS}@${DBINVENTORY_DSN}" )
fi

# ── Date du run ───────────────────────────────────────────────────────────────
RUN_DATE="${1:-$(date '+%Y-%m-%d')}"
if ! [[ "${RUN_DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "ERREUR: date de run invalide '${RUN_DATE}' (attendu YYYY-MM-DD)" >&2
    exit 2
fi

# ── Log ───────────────────────────────────────────────────────────────────────
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/load_discovery_$(date '+%Y%m%d_%H%M%S').log"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# =============================================================================
# Normalisation des fichiers d'entrée
# =============================================================================
# Export-Csv de PowerShell 5.1 écrit un BOM UTF-8 en tête de fichier. Laissé en
# place, il se retrouve collé au premier nom de colonne de l'en-tête, et le
# chargement par nom ne reconnaît plus la première colonne.
# Le fichier normalisé est écrit à côté, l'original n'est jamais modifié.
strip_bom() {
    local src="$1" dst="$2"
    sed '1s/^\xEF\xBB\xBF//' "${src}" > "${dst}"
}

SRC_MSSQL="${COLLECT_DIR}/discovery_mssql.csv"
SRC_LINUX="${COLLECT_DIR}/discovery_linux.csv"
LOAD_MSSQL="${COLLECT_DIR}/discovery_mssql.load.csv"
LOAD_LINUX="${COLLECT_DIR}/discovery_linux.load.csv"

# Les commandes LOAD, elles, reçoivent un chemin RELATIF, comme dans les trois
# loaders moteur. SQLcl est un binaire Windows : un chemin Git Bash absolu
# (/g/Developpement/...) lui est illisible, il le lit comme C:\g\...
# Le prix est que ce script doit tourner depuis bin/, ce que fait la chaîne.
REL_MSSQL="../collect/discovery_mssql.load.csv"
REL_LINUX="../collect/discovery_linux.load.csv"

HAS_MSSQL=0
HAS_LINUX=0

if [[ -s "${SRC_MSSQL}" ]]; then
    strip_bom "${SRC_MSSQL}" "${LOAD_MSSQL}"
    HAS_MSSQL=1
    log "Discovery MSSQL  : $(( $(wc -l < "${LOAD_MSSQL}") - 1 )) ligne(s)"
else
    log "Discovery MSSQL  : aucun fichier (${SRC_MSSQL})"
fi

if [[ -s "${SRC_LINUX}" ]]; then
    strip_bom "${SRC_LINUX}" "${LOAD_LINUX}"
    HAS_LINUX=1
    log "Discovery Linux  : $(wc -l < "${LOAD_LINUX}") ligne(s)"
else
    log "Discovery Linux  : aucun fichier (${SRC_LINUX})"
fi

if [[ "${HAS_MSSQL}" -eq 0 && "${HAS_LINUX}" -eq 0 ]]; then
    log "Rien à charger — arrêt."
    exit 0
fi

# =============================================================================
# Construction du script SQLcl
# =============================================================================
# Le script est assemblé plutôt qu'écrit en dur : les blocs LOAD dépendent des
# fichiers réellement présents, et les deux sources n'ont pas le même format
# (l'une a un en-tête et des virgules, l'autre ni en-tête ni virgules).
SQL_SCRIPT="$(mktemp)"
trap 'rm -f "${SQL_SCRIPT}"' EXIT

{
    echo "WHENEVER SQLERROR EXIT FAILURE ROLLBACK"
    echo "SET FEEDBACK OFF"
    echo "SET ECHO     OFF"
    echo
    echo "ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';"
    echo

    if [[ "${HAS_MSSQL}" -eq 1 ]]; then
        cat <<SQL_MSSQL
TRUNCATE TABLE discovery_mssql_inst;

-- Chargement PAR NOM : l'en-tête du CSV porte les noms de colonnes.
SET LOADFORMAT CSV
SET LOADFORMAT COLUMN_NAMES ON
SET LOADFORMAT DELIMITER ,
SET LOADFORMAT ENCLOSURES ""
SET LOAD SCAN_ROWS 0
SET LOAD ERRORS UNLIMITED
SET LOAD BATCHES_PER_COMMIT 0
SET LOAD COMMIT OFF

PROMPT -- LOADING: ${REL_MSSQL}
LOAD discovery_mssql_inst ${REL_MSSQL}
SQL_MSSQL
    fi

    if [[ "${HAS_LINUX}" -eq 1 ]]; then
        cat <<SQL_LINUX
TRUNCATE TABLE discovery_linux_engines;

-- Chargement POSITIONNEL : le script Linux émet une ligne ';' sans en-tête,
-- sur un contrat de 14 colonnes documenté dans son propre cartouche.
SET LOADFORMAT CSV
SET LOADFORMAT COLUMN_NAMES OFF
SET LOADFORMAT DELIMITER ;
SET LOADFORMAT ENCLOSURES ""
SET LOAD SCAN_ROWS 0
SET LOAD ERRORS UNLIMITED
SET LOAD BATCHES_PER_COMMIT 0
SET LOAD COMMIT OFF

PROMPT -- LOADING: ${REL_LINUX}
LOAD discovery_linux_engines ${REL_LINUX}
SQL_LINUX
    fi

    cat <<SQL_ETL

COMMIT;

-- ===========================================================================
-- Staging -> modèle de discovery
-- ===========================================================================
PROMPT -- ETL: pkg_dbinv_discovery.load_all(${RUN_DATE})
BEGIN
   pkg_dbinv_discovery.load_all(to_date('${RUN_DATE}', 'YYYY-MM-DD'));
END;
/

SET FEEDBACK ON
PROMPT -- Etat courant de la discovery :
SELECT source,
       to_char(run_date, 'YYYY-MM-DD') AS run_date,
       host_count,
       finding_count
  FROM disc_run
 WHERE run_date = to_date('${RUN_DATE}', 'YYYY-MM-DD')
 ORDER BY source;

EXIT;
SQL_ETL
} > "${SQL_SCRIPT}"

# =============================================================================
# Session SQLcl
# =============================================================================
log "Chargement de la discovery dans Oracle (run du ${RUN_DATE})..."
log "Log : ${LOG_FILE}"

SQLCL_EXIT=0
# stdin depuis un vrai fichier, et JLine en mode dumb : sans ça, sous Git Bash,
# SQLcl écrit "java.io.IOException: Fonction incorrecte" à la place du résultat
# et rend 0 — le log paraîtrait propre. Sans effet sur le serveur Linux.
SQLCL_STDIN="$(mktemp)"
JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Duser.language=en} -Dorg.jline.terminal.provider=dumb" \
sql "${SQLCL_ARGS[@]}" @"${SQL_SCRIPT}" < "${SQLCL_STDIN}" 2>&1 \
    | tee "${LOG_FILE}" || SQLCL_EXIT="${PIPESTATUS[0]}"
rm -f "${SQLCL_STDIN}"

# =============================================================================
# Analyse du log
# =============================================================================
send_error_mail() {
    local subject="$1" body="$2"
    # Pas de mailx sur un poste de développement : l'absence de l'alerte ne
    # doit ni masquer l'erreur qu'elle annonçait, ni faire échouer le script.
    if ! command -v mailx >/dev/null 2>&1; then
        log "mailx absent — alerte non envoyée : ${subject}"
        return 0
    fi
    mailx -s "${subject}" "${MAIL_TO}" <<EOF
${body}

Log complet : ${LOG_FILE}
EOF
}

if [[ "${SQLCL_EXIT}" -ne 0 ]]; then
    log "SQLcl a terminé avec une erreur (code ${SQLCL_EXIT}) — voir ${LOG_FILE}"
    send_error_mail "dbInventory discovery — erreur SQLcl (code ${SQLCL_EXIT})" \
        "$(grep -E 'ORA-[0-9]+|Error report' "${LOG_FILE}" | head -20)"
    exit 1
fi

if grep -qE '#INFO Number of rows in error: [1-9]' "${LOG_FILE}"; then
    log "Des lignes ont été rejetées — voir ${LOG_FILE}"
    send_error_mail "dbInventory discovery — lignes rejetées" \
        "$(grep -E '^-- LOADING:|#INFO Number of rows in error' "${LOG_FILE}")"
    exit 1
fi

rm -f "${LOAD_MSSQL}" "${LOAD_LINUX}"
log "Chargement terminé."
