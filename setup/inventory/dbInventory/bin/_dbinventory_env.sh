#!/bin/bash
# =============================================================================
# _dbinventory_env.sh — configuration et secrets des scripts dbInventory
# À sourcer après avoir positionné SCRIPT_DIR, ne pas exécuter directement.
#
# Aucun mot de passe n'est écrit dans le dépôt. Ils vivent dans un fichier .env
# non versionné (le .gitignore exclut tout .env), par défaut à la racine de
# dbInventory, à côté de bin/ et de collect/ :
#
#     /inventory/dbInventory/.env          (serveur de collecte)
#
# Le modèle versionné est ../.env.example. Un script poussé depuis le serveur ne
# peut donc plus emporter un mot de passe avec lui.
#
# Variables d'environnement reconnues :
#   DBINVENTORY_ENV_FILE   chemin du .env (défaut : ${SCRIPT_DIR}/../.env)
#   DBINVENTORY_TARGET     prod (défaut) | test : base dbInventory visée par les
#                          loaders, le calcul et la génération des listes
#   DBINVENTORY_CONN_NAME  connexion SQLcl nommée. Prioritaire sur le .env :
#                          c'est la voie du poste de développement et de la base
#                          de démonstration (fixtures/load_fixtures.sh)
# =============================================================================

DBINVENTORY_ENV_FILE="${DBINVENTORY_ENV_FILE:-${SCRIPT_DIR}/../.env}"
if [[ -f "${DBINVENTORY_ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${DBINVENTORY_ENV_FILE}"
fi

DBINVENTORY_USER="${DBINVENTORY_USER:-dbinventory}"
DBINVENTORY_TARGET="${DBINVENTORY_TARGET:-prod}"

# Remplit le tableau SQLCL_ARGS pour viser la base dbInventory, ou sort en 2.
# Un secret absent arrête le script avec un message qui dit quoi renseigner :
# mieux qu'une connexion refusée sur un mot de passe de substitution.
dbinv_sqlcl_args() {
    if [[ -n "${DBINVENTORY_CONN_NAME:-}" ]]; then
        SQLCL_ARGS=( -S -name "${DBINVENTORY_CONN_NAME}" )
        return 0
    fi

    local pass dsn tag
    case "${DBINVENTORY_TARGET}" in
        prod) pass="${DBINVENTORY_PROD_PASS:-}"; dsn="${DBINVENTORY_PROD_DSN:-}"; tag="PROD" ;;
        test) pass="${DBINVENTORY_TEST_PASS:-}"; dsn="${DBINVENTORY_TEST_DSN:-}"; tag="TEST" ;;
        *)
            echo "ERREUR: DBINVENTORY_TARGET='${DBINVENTORY_TARGET}' — prod ou test attendu." >&2
            exit 2
            ;;
    esac

    if [[ -z "${pass}" || -z "${dsn}" ]]; then
        echo "ERREUR: DBINVENTORY_${tag}_PASS et DBINVENTORY_${tag}_DSN doivent être définis" >&2
        echo "  dans ${DBINVENTORY_ENV_FILE} (modèle : .env.example)," >&2
        echo "  ou DBINVENTORY_CONN_NAME pour passer par une connexion SQLcl nommée." >&2
        exit 2
    fi

    SQLCL_ARGS=( -S "${DBINVENTORY_USER}/${pass}@${dsn}" )
}

# Positionne MONITORING_PASS pour le moteur donné (oracle | mssql | postgres),
# depuis MONITORING_<MOTEUR>_PASS, ou sort en 2.
dbinv_monitoring_pass() {
    local var
    var="MONITORING_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')_PASS"
    if [[ -z "${!var:-}" ]]; then
        echo "ERREUR: ${var} doit être défini dans ${DBINVENTORY_ENV_FILE} (modèle : .env.example)." >&2
        exit 2
    fi
    MONITORING_PASS="${!var}"
}
