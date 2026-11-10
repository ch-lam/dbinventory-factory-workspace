#!/bin/bash
# =============================================================================
# _cron_env.sh — environnement des outils clients pour les lancements par cron
# À sourcer (dbInventory_all.sh, dbInventory_load_test.sh), ne pas exécuter.
#
# cron ne lit pas le .profile : sans ces variables, sqlplus, sql (SQLcl) et
# sqlcmd sont introuvables. Les valeurs sont celles du serveur de collecte ;
# chacune peut être surchargée par l'environnement appelant.
# Si le .profile du serveur change, reporter le changement ici.
# =============================================================================

export ORACLE_HOME="${ORACLE_HOME:-/inventory/OracleClient/instantclient_23_9}"
export TNS_ADMIN="${TNS_ADMIN:-${ORACLE_HOME}/network}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-${ORACLE_HOME}}"

SQLCL_BIN="${SQLCL_BIN:-/inventory/OracleClient/sqlcl/bin}"
MSSQL_TOOLS_BIN="${MSSQL_TOOLS_BIN:-/opt/mssql-tools18/bin}"
export PATH="${PATH}:${ORACLE_HOME}:${SQLCL_BIN}:${MSSQL_TOOLS_BIN}"
