#!/bin/bash
# =============================================================================
# load_fixtures  –  Génère le jeu de démonstration, le charge, et lance l'ETL
#
# Prérequis : node 18+, SQLcl 22+, une connexion SQLcl nommée vers la base cible
#
# Enchaîne exactement la chaîne de production :
#
#   generate.mjs  ->  collect/*.csv  ->  load_info_*.sh  ->  staging
#                                              -> pkg_dbinv_inventory.load_all
#                                              -> pkg_dbinv_scoring.load_all
#
# Les loaders ne sont PAS contournés : c'est le seul moyen de vérifier que les
# CSV produits ont bien la forme que le chargement positionnel attend. Un
# générateur validé contre sa propre idée du format ne prouverait rien.
#
# DANGER : le chargement commence par TRUNCATE sur toutes les tables de staging.
# Sur le dev, cela effacerait des collectes que cette machine ne sait pas
# rejouer. D'où les deux garde-fous ci-dessous, dont un qui interroge la base
# elle-même plutôt que de croire le nom de la connexion.
#
# Usage : load_fixtures.sh [connexion_sqlcl] [--force]
#         Défaut : DEMO_DBINVENTORY_dbinventory
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_DIR="${REPO_DIR}/setup/inventory/dbInventory/bin"
COLLECT_DIR="${REPO_DIR}/setup/inventory/dbInventory/collect"

# Appels SQLcl : stdin depuis un vrai fichier, JLine en mode dumb, chemins
# convertis. Sans ce helper, SQLcl repond « java.io.IOException: Fonction
# incorrecte » a la place du resultat, et rend 0.
source "${SCRIPT_DIR}/sqlcl.sh"

DB_CONN="DEMO_DBINVENTORY_dbinventory"
FORCE=0
for arg in "$@"; do
    case "${arg}" in
        --force) FORCE=1 ;;
        -*)      echo "ERREUR: option inconnue : ${arg}" >&2; exit 2 ;;
        *)       DB_CONN="${arg}" ;;
    esac
done

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

# ── Garde-fou 1 : le nom de la connexion ─────────────────────────────────────
if [[ "${DB_CONN}" != *DEMO* && "${FORCE}" -ne 1 ]]; then
    echo "ERREUR: « ${DB_CONN} » ne ressemble pas à une connexion de démonstration." >&2
    echo "  Ce script fait TRUNCATE sur toutes les tables de staging avant de charger." >&2
    echo "  Relancez avec --force si c'est réellement l'intention." >&2
    exit 2
fi

# ── Garde-fou 2 : ce que dit la base, pas ce que dit le nom ──────────────────
# Le nom d'une connexion SQLcl est déclaratif : rien ne garantit qu'il pointe
# où il prétend. v_environment_identity, elle, est lue dans la base cible.
log "Vérification de l'identité de la base cible..."
IDENT_SQL="$(mktemp)"
trap 'rm -f "${IDENT_SQL}"' EXIT
cat > "${IDENT_SQL}" <<'SQL'
set feedback off
set heading off
set pagesize 0
set termout on
select value from v_environment_identity where name = 'Service name';
exit
SQL
SERVICE="$(sqlcl_run "${DB_CONN}" "${IDENT_SQL}" \
           | tr -d '\r' | grep -v '^[[:space:]]*$' | head -1 || true)"
# SQLcl remplit la ligne jusqu'au linesize : sans ce rognage, le nom du service
# traîne une vingtaine d'espaces et les messages d'erreur deviennent illisibles.
SERVICE="$(echo "${SERVICE}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

if [[ -z "${SERVICE}" ]]; then
    echo "ERREUR: impossible de lire v_environment_identity sur « ${DB_CONN} »." >&2
    echo "  Le modèle est-il installé ? (database/dbinventory/migrate.sh <conn>)" >&2
    exit 1
fi
log "Base cible : ${SERVICE}"
# Comparaison en majuscules : le service se nomme « pdbd_demoinventory », et un
# garde-fou qui laisse passer selon la casse ne garde rien.
if [[ "${SERVICE^^}" != *DEMO* && "${FORCE}" -ne 1 ]]; then
    echo "ERREUR: le service « ${SERVICE} » n'est pas une base de démonstration." >&2
    echo "  La connexion « ${DB_CONN} » ne pointe pas où son nom le laisse croire." >&2
    exit 2
fi

# ── Génération ───────────────────────────────────────────────────────────────
log "Génération des CSV..."
node "${SCRIPT_DIR}/generate.mjs" "${SCRIPT_DIR}/out"

# Le require se fait depuis SCRIPT_DIR, en chemin relatif : sous Git Bash, node
# est un binaire Windows et ne resout pas « /g/... ». Le sous-shell garde le
# repertoire courant du script intact.
SNAPSHOT="$(cd "${SCRIPT_DIR}" && node -e "process.stdout.write(require('./world.json').snapshotDate)")"
log "Date de snapshot : ${SNAPSHOT}"

# Les loaders lisent ../collect/<table>.csv en relatif depuis bin/. On y dépose
# les fichiers générés plutôt que de modifier les loaders : c'est la chaîne
# réelle qu'on veut exercer, chemins compris.
log "Dépôt des CSV dans ${COLLECT_DIR}..."
mkdir -p "${COLLECT_DIR}"
rm -f "${COLLECT_DIR}"/*.csv
cp "${SCRIPT_DIR}/out"/*.csv "${COLLECT_DIR}/"

# ── Périmètre de collecte ────────────────────────────────────────────────────
# Les *_collect_list sont VIDES sur une base fraîchement installée : aucune
# migration ne les alimente, c'est la discovery qui les remplit une fois qu'un
# humain a tranché. Sans elles, v_discovery_status ne peut rendre que NEW,
# NOT_SEEN est structurellement vide, et gen_collect_lists.sh n'a rien à
# régénérer — donc la moitié de ce que ce jeu doit démontrer n'existe pas.
#
# On les amorce depuis les .lst que generate.mjs vient d'écrire, par le script
# prévu pour ça, plutôt qu'en SQL écrit ici : c'est la chaîne réelle, jouée à
# l'envers. Le TRUNCATE est nécessaire, bootstrap n'émettant que des MERGE :
# une entrée laissée par une génération précédente survivrait au changement de
# parc et se présenterait en NOT_SEEN sans raison.
export DBINVENTORY_CONN_NAME="${DB_CONN}"
log "Amorçage du périmètre depuis les .lst générés..."
PERIM_SQL="$(mktemp)"
{
    echo "whenever sqlerror exit failure rollback"
    echo "truncate table oracle_collect_list;"
    echo "truncate table mssql_collect_list;"
    echo "truncate table postgres_collect_list;"
    "${BIN_DIR}/bootstrap_collect_lists.sh" "${SCRIPT_DIR}/out"
    echo "exit"
} > "${PERIM_SQL}"
PERIM_RC=0
sqlcl_run "${DB_CONN}" "${PERIM_SQL}" > /dev/null || PERIM_RC=$?
rm -f "${PERIM_SQL}"
if [[ "${PERIM_RC}" -ne 0 ]]; then
    echo "ERREUR: amorçage du périmètre impossible (code ${PERIM_RC})." >&2
    exit 1
fi

# ── Chargement ───────────────────────────────────────────────────────────────
cd "${BIN_DIR}"
for engine in oracle mssql postgres; do
    log "Chargement ${engine}..."
    ./load_info_${engine}.sh
done

# La discovery est une chaîne indépendante : aucune table commune avec
# l'inventaire, aucune clé étrangère entre les deux. Sa place ici tient à ce que
# les loaders sont ce qui valide la FORME des fichiers — une régression de
# format doit échouer avant qu'on dépense le temps de l'ETL.
#
# La date de run est celle du snapshot, pas trunc(sysdate) : sinon disc_run
# change de date chaque jour et la référence est fausse le lendemain.
log "Chargement discovery (run du ${SNAPSHOT})..."
./load_info_discovery.sh "${SNAPSHOT}"

# ── ETL ──────────────────────────────────────────────────────────────────────
# La date de snapshot est passée EXPLICITEMENT. Avec le défaut trunc(sysdate),
# la fraîcheur des sauvegardes, les fins de support et data_age_days
# dériveraient chaque jour, et le fichier de résultats attendus serait faux dès
# le lendemain de sa capture.
log "ETL inventaire puis scoring, au ${SNAPSHOT}..."
ETL_SQL="$(mktemp)"
cat > "${ETL_SQL}" <<SQL
whenever sqlerror exit failure rollback
set feedback off
begin
   pkg_dbinv_inventory.load_all(to_date('${SNAPSHOT}', 'YYYY-MM-DD'));
   pkg_dbinv_scoring.load_all(to_date('${SNAPSHOT}', 'YYYY-MM-DD'));
   commit;
end;
/
exit
SQL
ETL_RC=0
sqlcl_run "${DB_CONN}" "${ETL_SQL}" || ETL_RC=$?
rm -f "${ETL_SQL}"
# whenever sqlerror exit failure : un ETL en erreur doit arreter la chaine,
# sinon check_baseline.sh capturerait une reference sur une base a moitie
# chargee.
if [[ "${ETL_RC}" -ne 0 ]]; then
    echo "ERREUR: l ETL a echoue (code ${ETL_RC}). Rien n a ete capture." >&2
    exit 1
fi

# ── Triage ───────────────────────────────────────────────────────────────────
# Les décisions humaines s'appliquent en dernier : elles ont besoin des
# identifiants que le chargement de la discovery vient de créer, et elles
# passent par l'API réelle (set_triage), pas par un UPDATE de circonstance.
# C'est le seul exercice que cette procédure ait jamais eu.
log "Décisions de triage de la discovery..."
TRIAGE_RC=0
sqlcl_run "${DB_CONN}" "${SCRIPT_DIR}/out/discovery_triage.sql" || TRIAGE_RC=$?
if [[ "${TRIAGE_RC}" -ne 0 ]]; then
    echo "ERREUR: les decisions de triage ont echoue (code ${TRIAGE_RC})." >&2
    exit 1
fi

# ── Registre applicatif ──────────────────────────────────────────────────────
# Après l'ETL, parce que le rattachement vise dim_host, dim_instance et
# dim_database : ces identifiants n'existent qu'une fois l'inventaire construit.
# Le script est un no-op si le registre est déjà peuplé — il se saisit, il ne se
# collecte pas, et un rechargement des fixtures n'a pas à écraser une saisie.
log "Registre applicatif de démonstration..."
APPS_RC=0
sqlcl_run "${DB_CONN}" "${SCRIPT_DIR}/out/demo_applications.sql" || APPS_RC=$?
if [[ "${APPS_RC}" -ne 0 ]]; then
    echo "ERREUR: le chargement du registre applicatif a echoue (code ${APPS_RC})." >&2
    exit 1
fi

log "Terminé. Assertions : sql -S -name ${DB_CONN} @fixtures/checks/T_003_fixture_expectations.sql"
