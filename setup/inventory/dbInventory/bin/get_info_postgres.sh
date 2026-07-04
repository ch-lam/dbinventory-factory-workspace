#!/bin/bash
# =============================================================================
# get_info_postgres — collecte inventaire PostgreSQL (infra + capacite)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=get_info_postgres_common.sh
source "${SCRIPT_DIR}/get_info_postgres_common.sh"

init_temps postgres_hosts postgres_databases postgres_replication \
           postgres_backup postgres_extensions
rm -f "${LIST_DIR}/error_db.lst"

# ── Collecte par instance ─────────────────────────────────────────────────────
while IFS=';' read -r env lic server; do
    [[ -z "${server:-}" ]] && continue
    host="${server%%:*}"
    port="${server##*:}"
    log "Connexion : ${host}:${port} [${env}/${lic}]"

    status=$(status_check "${host}" "${port}") || { log_err "${host}:${port}"; continue; }
    [[ -z "${status}" ]] && { log_err "${host}:${port}"; continue; }
    IFS=',' read -r role ver_num <<< "${status}"
    log "  role=${role} version=${ver_num}"

    # -- Hosts (infos instance) -------------------------------------------------
    psql_run "${host}" "${port}" "${DEFAULT_DB}" "
        SELECT '${host}','${env}','${lic}',
               current_setting('server_version'),
               current_setting('port'),
               current_setting('data_directory'),
               to_char(pg_postmaster_start_time(),'YYYY-MM-DD HH24:MI:SS'),
               current_setting('max_connections'),
               round(pg_size_bytes(current_setting('shared_buffers'))/1024/1024),
               current_setting('wal_level'),
               current_setting('archive_mode'),
               '${role}'" \
        >> "${LIST_DIR}/postgres_hosts_temp.csv" || log_err "${host}:${port}"

    # -- Databases + taille -------------------------------------------------------
    psql_run "${host}" "${port}" "${DEFAULT_DB}" "
        SELECT '${host}','${env}', d.datname,
               pg_get_userbyid(d.datdba),
               pg_encoding_to_char(d.encoding),
               d.datcollate,
               round(pg_database_size(d.datname)/1024/1024),
               d.datconnlimit,
               CASE WHEN d.datistemplate THEN 'YES' ELSE 'NO' END,
               t.spcname
        FROM   pg_database d
        JOIN   pg_tablespace t ON t.oid = d.dattablespace
        WHERE  d.datname NOT IN ('template0','template1')
        ORDER BY 1" \
        >> "${LIST_DIR}/postgres_databases_temp.csv" || log_err "${host}:${port}"

    # -- Backup / archivage WAL ----------------------------------------------------
    psql_run "${host}" "${port}" "${DEFAULT_DB}" "
        SELECT '${host}', current_setting('archive_mode'),
               COALESCE(archived_count,0), COALESCE(last_archived_wal,'NA'),
               COALESCE(to_char(last_archived_time,'YYYY-MM-DD HH24:MI:SS'),'NA'),
               COALESCE(failed_count,0), COALESCE(last_failed_wal,'NA'),
               COALESCE(to_char(last_failed_time,'YYYY-MM-DD HH24:MI:SS'),'NA')
        FROM   pg_stat_archiver" \
        >> "${LIST_DIR}/postgres_backup_temp.csv" || log_err "${host}:${port}"

    # -- Replication (cote primaire ou standby) ------------------------------------
    if [[ "${role}" == "PRIMARY" ]]; then
        psql_run "${host}" "${port}" "${DEFAULT_DB}" "
            SELECT '${host}','PRIMARY', COALESCE(client_addr::text,'local'),
                   state, sync_state, COALESCE(EXTRACT(EPOCH FROM replay_lag)::int,-1)
            FROM   pg_stat_replication" \
            >> "${LIST_DIR}/postgres_replication_temp.csv" || log_err "${host}:${port}"
    else
        psql_run "${host}" "${port}" "${DEFAULT_DB}" "
            SELECT '${host}','STANDBY', COALESCE(sender_host,'unknown'),
                   status, 'NA', COALESCE(EXTRACT(EPOCH FROM (now()-last_msg_receipt_time))::int,-1)
            FROM   pg_stat_wal_receiver" \
            >> "${LIST_DIR}/postgres_replication_temp.csv" || log_err "${host}:${port}"
    fi

    # -- Extensions (catalogue local, par base) ------------------------------------
    dblist=$(psql_list "${host}" "${port}" "${DEFAULT_DB}" \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn ORDER BY 1")
    while IFS= read -r dbname; do
        [[ -z "${dbname}" ]] && continue
        psql_run "${host}" "${port}" "${dbname}" "
            SELECT '${host}','${dbname}', extname, extversion FROM pg_extension ORDER BY 1" \
            >> "${LIST_DIR}/postgres_extensions_temp.csv" || log_err "${host}:${port}/${dbname}"
    done <<< "${dblist}"

done < <(grep -v '^\s*#' "${LIST_FILE}" | grep -v '^\s*$' | sort -u)

# ── Finalisation ──────────────────────────────────────────────────────────────
log "Finalisation..."
finalize_lst "${LIST_DIR}/postgres_hosts_temp.csv"       "${LIST_DIR}/postgres_hosts.csv"
finalize_lst "${LIST_DIR}/postgres_databases_temp.csv"   "${LIST_DIR}/postgres_databases.csv"
finalize_lst "${LIST_DIR}/postgres_replication_temp.csv" "${LIST_DIR}/postgres_replication.csv"
finalize_lst "${LIST_DIR}/postgres_backup_temp.csv"      "${LIST_DIR}/postgres_backup.csv"
finalize_lst "${LIST_DIR}/postgres_extensions_temp.csv"  "${LIST_DIR}/postgres_extensions.csv"

report_errors "PostgreSQL inventory (infra): erreurs de connexion"
log "Termine."
