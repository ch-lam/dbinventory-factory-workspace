#!/bin/bash
# =============================================================================
# get_info_sqlserver — collecte inventaire MSSQL (infra)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=get_info_mssql_common
source "${SCRIPT_DIR}/get_info_mssql_common.sh"

init_temps mssql_hosts mssql_databases mssql_backup mssql_files \
           mssql_logins mssql_users mssql_loginwoperm mssql_validatelogin
rm -f "${LIST_DIR}/error_db.lst"

# ── Collecte par instance ─────────────────────────────────────────────────────
while IFS=';' read -r env license server; do
    # Le filtre en fin de boucle a déjà écarté commentaires et lignes vides : une
    # 3e colonne absente ici ne peut venir que d'une ligne mal formée (un
    # séparateur autre que ';'). L'ignorer en silence, c'est ne jamais collecter
    # la cible et ne jamais l'apprendre — c'est ce qui est arrivé à GINRHU.
    if [[ -z "${server:-}" ]]; then
        log_err "ligne de périmètre mal formée, attendu ENV;LICENCE;HOTE:PORT : ${env}${license:+;${license}}"
        continue
    fi
    host="${server%%:*}"
    # Une entrée sans ':port' ferait renvoyer le hostname par ${server##*:} ; on
    # retombe sur le port par défaut, celui-là même que porte mssql_collect_list.
    if [[ "${server}" == *:* ]]; then port="${server##*:}"; else port=1433; fi
    target="${host},${port}"
    log "Connexion : ${target} [${env}/${license}]"

    status_check "${target}" || { log_err "${target}"; continue; }

    # Préfixes positionnels ajoutés à chaque ligne renvoyée par sqlcmd. Les tables
    # de collecte commencent toutes par collect_id + collect_target ; mssql_hosts et
    # mssql_databases portent en plus le périmètre (port/env/licence), comme le font
    # oracle_hosts et oracle_databases. Sans cela l'environnement et le type de
    # licence sont perdus dès la collecte : ils ne figurent nulle part dans ce que
    # renvoie sqlcmd, et l'ETL ne peut plus que les deviner.
    prefix="\"${collect_id}\",\"${host}\","
    prefix_scope="\"${collect_id}\",\"${host}\",\"${port}\",\"${env}\",\"${license}\","

    sqlcmd_run "${target}" "${SQL_DIR}/mssql_getinstanceinfo.sql" \
        | sed "/^[[:space:]]*\$/! s/^/${prefix_scope}/" \
        >> "${LIST_DIR}/mssql_hosts_temp.csv" || log_err "${target}"

    sqlcmd_run "${target}" "${SQL_DIR}/mssql_getdbinfo.sql" \
        | sed "/^[[:space:]]*\$/! s/^/${prefix_scope}/" \
        >> "${LIST_DIR}/mssql_databases_temp.csv" || log_err "${target}"

    sqlcmd_run "${target}" "${SQL_DIR}/mssql_getbackupinfo.sql" \
        | sed "/^[[:space:]]*\$/! s/^/${prefix}/" \
        >> "${LIST_DIR}/mssql_backup_temp.csv" || log_err "${target}"

    sqlcmd_run "${target}" "${SQL_DIR}/mssql_getfileinfo.sql" \
        | sed "/^[[:space:]]*\$/! s/^/${prefix}/" \
        >> "${LIST_DIR}/mssql_files_temp.csv" || log_err "${target}"

    sqlcmd_run "${target}" "${SQL_DIR}/mssql_getloginsinfo.sql" \
        | sed "/^[[:space:]]*\$/! s/^/${prefix}/" \
        >> "${LIST_DIR}/mssql_logins_temp.csv" || log_err "${target}"

    sqlcmd_run "${target}" "${SQL_DIR}/mssql_getuserinfo.sql" \
        | sed "/^[[:space:]]*\$/! s/^/${prefix}/" \
        >> "${LIST_DIR}/mssql_users_temp.csv" || log_err "${target}"

    sqlcmd_run "${target}" "${SQL_DIR}/mssql_loginwithoutperm.sql" \
        | sed "/^[[:space:]]*\$/! s/^/${prefix}/" \
        >> "${LIST_DIR}/mssql_loginwoperm_temp.csv" || log_err "${target}"

    sqlcmd_run "${target}" "${SQL_DIR}/mssql_validatelogin.sql" \
        | sed "/^[[:space:]]*\$/! s/^/${prefix}/" \
        >> "${LIST_DIR}/mssql_validatelogin_temp.csv" || log_err "${target}"

done < <(grep -v '^\s*#' "${LIST_FILE}" | grep -v '^\s*$' | sort -u)

# ── Finalisation ──────────────────────────────────────────────────────────────
log "Finalisation..."
finalize_lst "${LIST_DIR}/mssql_hosts_temp.csv"         "${LIST_DIR}/mssql_hosts.csv"
finalize_lst "${LIST_DIR}/mssql_databases_temp.csv"     "${LIST_DIR}/mssql_databases.csv"
finalize_lst "${LIST_DIR}/mssql_backup_temp.csv"        "${LIST_DIR}/mssql_backup.csv"
finalize_lst "${LIST_DIR}/mssql_files_temp.csv"         "${LIST_DIR}/mssql_files.csv"
finalize_lst "${LIST_DIR}/mssql_logins_temp.csv"        "${LIST_DIR}/mssql_logins.csv"
finalize_lst "${LIST_DIR}/mssql_users_temp.csv"         "${LIST_DIR}/mssql_users.csv"
finalize_lst "${LIST_DIR}/mssql_loginwoperm_temp.csv"   "${LIST_DIR}/mssql_loginwoperm.csv"
finalize_lst "${LIST_DIR}/mssql_validatelogin_temp.csv" "${LIST_DIR}/mssql_validatelogin.csv"

report_errors "MSSQL inventory (infra): erreurs de connexion"
log "Terminé."
