#!/bin/bash
# =============================================================================
# get_info_postgres_security — collecte securite PostgreSQL
# -----------------------------------------------------------------------------
# Deux limites assumees, qui se lisent dans les constats produits en aval par
# pkg_dbinv_scoring.load_findings_postgres_sec :
#
#   * Les STANDBY sont ignores (garde plus bas). Leur configuration de securite
#     est heritee du primaire par la replication physique : la collecter serait
#     dupliquer le verdict du primaire sous une autre instance. Consequence
#     assumee : une instance STANDBY n'a AUCUN constat du domaine SECURITY.
#
#   * pg_hba_file_rules n'est lisible integralement par un role non superuser
#     qu'a partir de PG15 ; avant, les colonnes sensibles sont masquees et la
#     regle PG_HBA_NO_TRUST peut donc conclure a tort a l'absence de trust.
#     Cf. database/targets/postgres/POSTGRES_create_monitoring_user.sql.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=get_info_postgres_common.sh
source "${SCRIPT_DIR}/get_info_postgres_common.sh"

init_temps postgres_security_parameter postgres_security_roles \
           postgres_security_role_memberships postgres_security_hba_rules \
           postgres_security_database_privileges
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

    # Standby : configuration heritee du primaire, pas de collecte securite
    [[ "${role}" == "STANDBY" ]] && continue

    # ── Parametres de securite ────────────────────────────────────────────────
    psql_run "${host}" "${port}" "${DEFAULT_DB}" "
        SELECT '${host}', name, setting
        FROM   pg_settings
        WHERE  name IN ('ssl','password_encryption','log_connections','log_disconnections',
                         'log_statement','log_min_duration_statement','log_hostname',
                         'ssl_min_protocol_version','shared_preload_libraries')
        ORDER BY 1" \
        >> "${LIST_DIR}/postgres_security_parameter_temp.csv" || log_err "${host}:${port}"

    # ── Roles (superuser, createrole, createdb, login, replication, RLS) ────────
    psql_run "${host}" "${port}" "${DEFAULT_DB}" "
        SELECT '${host}', rolname,
               CASE WHEN rolsuper THEN 'Y' ELSE 'N' END,
               CASE WHEN rolcreaterole THEN 'Y' ELSE 'N' END,
               CASE WHEN rolcreatedb THEN 'Y' ELSE 'N' END,
               CASE WHEN rolcanlogin THEN 'Y' ELSE 'N' END,
               CASE WHEN rolreplication THEN 'Y' ELSE 'N' END,
               CASE WHEN rolbypassrls THEN 'Y' ELSE 'N' END,
               rolconnlimit,
               COALESCE(to_char(rolvaliduntil,'YYYY-MM-DD HH24:MI:SS'),'NEVER')
        FROM   pg_roles
        ORDER BY 1" \
        >> "${LIST_DIR}/postgres_security_roles_temp.csv" || log_err "${host}:${port}"

    # ── Appartenance aux roles predefinis sensibles ──────────────────────────────
    psql_run "${host}" "${port}" "${DEFAULT_DB}" "
        SELECT '${host}', m.rolname, r.rolname
        FROM   pg_auth_members am
        JOIN   pg_roles r ON r.oid = am.roleid
        JOIN   pg_roles m ON m.oid = am.member
        WHERE  r.rolname IN ('pg_read_all_data','pg_write_all_data','pg_execute_server_program',
                              'pg_read_server_files','pg_write_server_files','pg_monitor',
                              'pg_signal_backend')
        ORDER BY 1" \
        >> "${LIST_DIR}/postgres_security_role_memberships_temp.csv" || log_err "${host}:${port}"

    # ── Regles pg_hba.conf (methodes d'authentification faibles : trust/md5) ────
    psql_run "${host}" "${port}" "${DEFAULT_DB}" "
        SELECT '${host}', line_number, type,
               array_to_string(database,'/'), array_to_string(user_name,'/'),
               COALESCE(address,'NA'), auth_method
        FROM   pg_hba_file_rules
        ORDER BY line_number" \
        >> "${LIST_DIR}/postgres_security_hba_rules_temp.csv" || log_err "${host}:${port}"

    # ── Droits PUBLIC sur les bases (CONNECT/CREATE) ─────────────────────────────
    psql_run "${host}" "${port}" "${DEFAULT_DB}" "
        SELECT '${host}', d.datname, 'PUBLIC', a.privilege_type
        FROM   pg_database d, aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a
        WHERE  d.datname NOT IN ('template0','template1') AND a.grantee = 0
        ORDER BY 1" \
        >> "${LIST_DIR}/postgres_security_database_privileges_temp.csv" || log_err "${host}:${port}"

done < <(grep -v '^\s*#' "${LIST_FILE}" | grep -v '^\s*$' | sort -u)

# ── Finalisation ──────────────────────────────────────────────────────────────
log "Finalisation..."
finalize_lst "${LIST_DIR}/postgres_security_parameter_temp.csv"           "${LIST_DIR}/postgres_security_parameter.csv"
finalize_lst "${LIST_DIR}/postgres_security_roles_temp.csv"               "${LIST_DIR}/postgres_security_roles.csv"
finalize_lst "${LIST_DIR}/postgres_security_role_memberships_temp.csv"    "${LIST_DIR}/postgres_sec_role_members.csv"
finalize_lst "${LIST_DIR}/postgres_security_hba_rules_temp.csv"           "${LIST_DIR}/postgres_security_hba_rules.csv"
finalize_lst "${LIST_DIR}/postgres_security_database_privileges_temp.csv" "${LIST_DIR}/postgres_sec_db_privs.csv"

report_errors "PostgreSQL inventory (securite): erreurs de connexion"
log "Termine."
