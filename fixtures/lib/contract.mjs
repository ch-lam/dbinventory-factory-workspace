// Généré depuis le DDL de la base et depuis une collecte réelle archivée.
// Ne pas éditer à la main sans relire fixtures/README.md.

export const CONTRACT = {
  // ---------------------------------------------------------------- oracle
  oracle_hosts: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "environment", type: "varchar2", len: 80 },
      { name: "license_type", type: "varchar2", len: 200 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "num_cpus", type: "number", prec: 6, scale: 0 },
      { name: "memory_gb", type: "number", prec: 6, scale: 0 },
      { name: "os_type", type: "varchar2", len: 400 },
    ],
    omitted: []
  },
  oracle_users: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "instance_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "username", type: "varchar2", len: 200 },
      { name: "account_status", type: "varchar2", len: 400 },
      { name: "db_name", type: "varchar2", len: 200 },
    ],
    omitted: []
  },
  oracle_services: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "instance_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "service_name", type: "varchar2", len: 400 },
    ],
    omitted: []
  },
  oracle_pdbs: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "instance_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "pdb_state", type: "varchar2", len: 200 },
    ],
    omitted: []
  },
  oracle_databases: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "environment", type: "varchar2", len: 80 },
      { name: "license_type", type: "varchar2", len: 200 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "instance_name", type: "varchar2", len: 200 },
      { name: "db_version", type: "varchar2", len: 200 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "db_log_mode", type: "varchar2", len: 200 },
      { name: "db_role", type: "varchar2", len: 200 },
      { name: "db_unique_name", type: "varchar2", len: 200 },
      { name: "db_charset", type: "varchar2", len: 200 },
      { name: "db_edition", type: "varchar2", len: 200 },
      { name: "rac_state", type: "varchar2", len: 200 },
      { name: "sga", type: "varchar2", len: 200 },
      { name: "pga", type: "varchar2", len: 200 },
      { name: "asm_free", type: "varchar2", len: 200 },
      { name: "asm_total", type: "varchar2", len: 200 },
      { name: "easy_connect_tns", type: "varchar2", len: 400 },
      { name: "database_type", type: "varchar2", len: 200 },
    ],
    omitted: ["count_pdb"]
  },
  oracle_dataguard: {
    engine: "oracle", source: "déduit des scripts",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "primary_db", type: "varchar2", len: 400 },
      { name: "standby_db", type: "varchar2", len: 400 },
      { name: "pdb_list_impacted", type: "varchar2", len: 4000 },
      { name: "service_list_impacted", type: "varchar2", len: 4000 },
      { name: "protection_mode", type: "varchar2", len: 400 },
    ],
    omitted: []
  },
  oracle_psu: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "db_version", type: "varchar2", len: 200 },
      { name: "psu_applied", type: "varchar2", len: 800 },
    ],
    omitted: []
  },
  oracle_lms: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "grouping_id", type: "number", prec: 1, scale: 0 },
      { name: "con_id", type: "number", prec: 5, scale: 0 },
      { name: "db_pdb_name", type: "varchar2", len: 200 },
      { name: "product_name", type: "varchar2", len: 600 },
      { name: "usage_detected", type: "varchar2", len: 400 },
      { name: "last_sample_date", type: "varchar2", len: 80 },
      { name: "first_usage_date", type: "varchar2", len: 400 },
      { name: "last_usage_date", type: "varchar2", len: 400 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "hostname", type: "varchar2", len: 200 },
    ],
    omitted: []
  },
  oracle_client_version: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "db_version", type: "varchar2", len: 200 },
      { name: "environment", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "client_version", type: "varchar2", len: 200 },
      { name: "client_driver", type: "varchar2", len: 400 },
      { name: "username", type: "varchar2", len: 200 },
      { name: "client_host", type: "varchar2", len: 200 },
      { name: "service_name", type: "varchar2", len: 200 },
      { name: "failover_type", type: "varchar2", len: 200 },
      { name: "failover_method", type: "varchar2", len: 200 },
    ],
    omitted: ["check_client"]
  },
  oracle_backup: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "environment", type: "varchar2", len: 80 },
      { name: "backup_type", type: "varchar2", len: 200 },
      { name: "status", type: "varchar2", len: 200 },
      { name: "start_time", type: "timestamp(6)", len: 11 },
      { name: "end_time", type: "timestamp(6)", len: 11 },
      { name: "elapsed_time", type: "varchar2", len: 200 },
    ],
    omitted: []
  },
  oracle_sec_admin_high_privs: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "username", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_sec_default_user_pwd: {
    engine: "oracle", source: "déduit des scripts",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "username", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_sec_high_role_privs: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "username", type: "varchar2", len: 200 },
      { name: "privilege", type: "varchar2", len: 400 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_sec_high_sys_privs: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "username", type: "varchar2", len: 200 },
      { name: "privilege", type: "varchar2", len: 400 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_sec_high_tab_privs: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "username", type: "varchar2", len: 200 },
      { name: "privilege", type: "varchar2", len: 400 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_security_profile: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "profile", type: "varchar2", len: 200 },
      { name: "resource_name", type: "varchar2", len: 400 },
      { name: "limit_value", type: "varchar2", len: 400 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_sec_default_profile: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "username", type: "varchar2", len: 200 },
      { name: "profile", type: "varchar2", len: 200 },
      { name: "oracle_managed", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_security_parameter: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "parameter_value", type: "varchar2", len: 4000 },
      { name: "parameter_name", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_security_audit_enable: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "audit_parameter", type: "varchar2", len: 200 },
      { name: "audit_activated", type: "number", prec: 2, scale: 0 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_security_tablespace: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "tablespace_name", type: "varchar2", len: 400 },
      { name: "encrypted", type: "varchar2", len: 400 },
    ],
    omitted: ["license_type","compliance_score","date_value"]
  },
  oracle_sec_usermig_tbl_exist: {
    engine: "oracle", source: "déduit des scripts",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "owner", type: "varchar2", len: 120 },
      { name: "table_name", type: "varchar2", len: 120 },
    ],
    omitted: []
  },
  oracle_sec_network_encryption: {
    engine: "oracle", source: "déduit des scripts",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "sqlnet_encryption", type: "varchar2", len: 800 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  oracle_sec_net_enc_audit: {
    engine: "oracle", source: "déduit des scripts",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 512 },
      { name: "record_type", type: "varchar2", len: 40 },
      { name: "username", type: "varchar2", len: 512 },
      { name: "machine", type: "varchar2", len: 1024 },
      { name: "program", type: "varchar2", len: 512 },
      { name: "osuser", type: "varchar2", len: 512 },
      { name: "first_seen", type: "varchar2", len: 80 },
      { name: "last_seen", type: "varchar2", len: 80 },
      { name: "logon_count", type: "varchar2", len: 80 },
    ],
    omitted: []
  },
  oracle_size_usage: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "tablespace_name", type: "varchar2", len: 800 },
      { name: "size_mb", type: "number", prec: 10, scale: 0 },
    ],
    omitted: ["environment","sum_segment_mb","date_value"]
  },
  oracle_size_usage_seg: {
    engine: "oracle", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "pdb_name", type: "varchar2", len: 200 },
      { name: "tablespace_name", type: "varchar2", len: 800 },
      { name: "sum_segment_mb", type: "number", prec: 10, scale: 0 },
    ],
    omitted: ["date_value"]
  },
  // ---------------------------------------------------------------- mssql
  mssql_hosts: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "collect_port", type: "number", prec: 5, scale: 0 },
      { name: "environment", type: "varchar2", len: 80 },
      { name: "license_type", type: "varchar2", len: 200 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "mssql_edition", type: "varchar2", len: 400 },
      { name: "mssql_product_version", type: "varchar2", len: 400 },
      { name: "collation", type: "varchar2", len: 400 },
      { name: "is_clustered", type: "number", prec: 5, scale: 0 },
      { name: "activenodename", type: "varchar2", len: 200 },
      { name: "clusternode1", type: "varchar2", len: 200 },
      { name: "clusternode2", type: "varchar2", len: 200 },
      { name: "parallel_threshold", type: "number", prec: 10, scale: 0 },
      { name: "max_dop", type: "number", prec: 10, scale: 0 },
      { name: "min_memory", type: "number", prec: 10, scale: 0 },
      { name: "max_memory", type: "number", prec: 10, scale: 0 },
      { name: "xp_cmdshell_enabled", type: "number", prec: 10, scale: 0 },
      { name: "num_cpus", type: "number", prec: 6, scale: 0 },
      { name: "memory_gb", type: "number", prec: 6, scale: 0 },
      { name: "os_type", type: "varchar2", len: 400 },
      { name: "install_date", type: "varchar2", len: 40 },
      { name: "service_account", type: "varchar2", len: 400 },
      { name: "is_integrated_security_only", type: "number", prec: 1, scale: 0 },
    ],
    omitted: []
  },
  mssql_databases: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "collect_port", type: "number", prec: 5, scale: 0 },
      { name: "environment", type: "varchar2", len: 80 },
      { name: "license_type", type: "varchar2", len: 200 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "database_id", type: "number", prec: 5, scale: 0 },
      { name: "database_name", type: "varchar2", len: 400 },
      { name: "database_state", type: "varchar2", len: 400 },
      { name: "recovery_model", type: "varchar2", len: 400 },
      { name: "compatibility_level", type: "varchar2", len: 400 },
      { name: "collation", type: "varchar2", len: 400 },
      { name: "last_backup_date", type: "varchar2", len: 400 },
      { name: "last_backup_diff_date", type: "varchar2", len: 400 },
      { name: "last_backup_log_date", type: "varchar2", len: 400 },
      { name: "create_date", type: "varchar2", len: 400 },
      { name: "is_mirroring_enabled", type: "number", prec: 6, scale: 0 },
      { name: "owner", type: "varchar2", len: 400 },
      { name: "agtype", type: "varchar2", len: 200 },
      { name: "agname", type: "varchar2", len: 200 },
    ],
    omitted: []
  },
  mssql_files: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "database_name", type: "varchar2", len: 400 },
      { name: "file_id", type: "number", prec: 10, scale: 0 },
      { name: "type_desc", type: "varchar2", len: 80 },
      { name: "name", type: "varchar2", len: 400 },
      { name: "physical_name", type: "varchar2", len: 1020 },
      { name: "size_mb", type: "number", prec: 10, scale: 0 },
      { name: "growth_percent", type: "number", prec: 10, scale: 0 },
      { name: "growth_mb", type: "number", prec: 10, scale: 0 },
      { name: "max_size", type: "number", prec: 10, scale: 0 },
    ],
    omitted: []
  },
  mssql_logins: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "instance_name", type: "varchar2", len: 160 },
      { name: "loginname", type: "varchar2", len: 400 },
      { name: "accountcreationdate", type: "varchar2", len: 120 },
      { name: "lasttimeaccountmodified", type: "varchar2", len: 120 },
      { name: "passwordlastsettime", type: "varchar2", len: 120 },
      { name: "defaultdatabase", type: "varchar2", len: 400 },
      { name: "defaultlanguage", type: "varchar2", len: 200 },
      { name: "isdisabledchecked", type: "varchar2", len: 120 },
      { name: "ispolicychecked", type: "varchar2", len: 120 },
      { name: "isexpirationchecked", type: "varchar2", len: 120 },
      { name: "isexpired", type: "varchar2", len: 120 },
      { name: "daysuntilexpiration", type: "varchar2", len: 120 },
      { name: "islocked", type: "varchar2", len: 120 },
      { name: "ismustchange", type: "varchar2", len: 120 },
      { name: "lockouttime", type: "varchar2", len: 120 },
      { name: "badpasswordcount", type: "varchar2", len: 120 },
      { name: "badpasswordtime", type: "varchar2", len: 120 },
      { name: "historylength", type: "varchar2", len: 120 },
      { name: "loginsid", type: "varchar2", len: 800 },
      { name: "logintype", type: "varchar2", len: 40 },
      { name: "hasserverrole", type: "varchar2", len: 400 },
    ],
    omitted: []
  },
  mssql_users: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "instance_name", type: "varchar2", len: 200 },
      { name: "database_name", type: "varchar2", len: 400 },
      { name: "name", type: "varchar2", len: 400 },
      { name: "groupname", type: "varchar2", len: 400 },
      { name: "loginname", type: "varchar2", len: 400 },
      { name: "defaultdbname", type: "varchar2", len: 400 },
      { name: "defaultschemaname", type: "varchar2", len: 400 },
      { name: "principalid", type: "number", prec: 10, scale: 0 },
      { name: "sid", type: "varchar2", len: 400 },
    ],
    omitted: []
  },
  mssql_loginwoperm: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "instance_name", type: "varchar2", len: 200 },
      { name: "loginname", type: "varchar2", len: 600 },
      { name: "type_desc", type: "varchar2", len: 200 },
      { name: "is_disabled", type: "number", prec: 1, scale: 0 },
      { name: "db_perms", type: "varchar2", len: 600 },
      { name: "srv_perms", type: "varchar2", len: 600 },
      { name: "modify_date", type: "date", len: 7 },
      { name: "scandate", type: "date", len: 7 },
    ],
    omitted: []
  },
  mssql_validatelogin: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 600 },
      { name: "sid", type: "varchar2", len: 800 },
      { name: "login", type: "varchar2", len: 600 },
      { name: "is_disabled", type: "number", prec: 1, scale: 0 },
      { name: "modify_date", type: "date", len: 7 },
      { name: "scandate", type: "date", len: 7 },
    ],
    omitted: []
  },
  mssql_backup: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "hostname", type: "varchar2", len: 200 },
      { name: "database_name", type: "varchar2", len: 400 },
      { name: "backup_start_date", type: "date", len: 7 },
      { name: "backup_finish_date", type: "date", len: 7 },
      { name: "backup_type", type: "varchar2", len: 80 },
      { name: "backup_size", type: "number", prec: 19, scale: 0 },
    ],
    omitted: []
  },
  mssql_security_auditlevel: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "auditlevel", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_configoptions: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "name", type: "varchar2", len: 800 },
      { name: "config_value", type: "number", prec: 10, scale: 0 },
      { name: "run_value", type: "number", prec: 10, scale: 0 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_dbproperties: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "is_auto_close_on", type: "number", prec: 10, scale: 0 },
      { name: "is_trustworthy_on", type: "number", prec: 10, scale: 0 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_encryption: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "key_type", type: "varchar2", len: 200 },
      { name: "key_name", type: "varchar2", len: 400 },
      { name: "algorithm_desc", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_groups: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "localgroupname", type: "varchar2", len: 200 },
      { name: "permission_name", type: "varchar2", len: 400 },
      { name: "state_desc", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_guestconnect: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "permission_name", type: "varchar2", len: 200 },
      { name: "state_desc", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_logins: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "login_name", type: "varchar2", len: 400 },
      { name: "principal_id", type: "varchar2", len: 400 },
      { name: "is_sysadmin", type: "number", prec: 2, scale: 0 },
      { name: "is_policy_checked", type: "number", prec: 2, scale: 0 },
      { name: "access_method", type: "varchar2", len: 200 },
      { name: "is_expiration_checked", type: "number", prec: 2, scale: 0 },
      { name: "is_disabled", type: "number", prec: 2, scale: 0 },
      { name: "create_date", type: "date", len: 7 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_orphanedusers: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "user_name", type: "varchar2", len: 400 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_sec_pubperm: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "db_name", type: "varchar2", len: 200 },
      { name: "username", type: "varchar2", len: 400 },
      { name: "permission_name", type: "varchar2", len: 400 },
      { name: "state_desc", type: "varchar2", len: 200 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_registryinfo: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "name", type: "varchar2", len: 400 },
      { name: "value", type: "number", prec: 10, scale: 0 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_sa: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "login_name", type: "varchar2", len: 512 },
      { name: "is_disabled", type: "number", prec: 1, scale: 0 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  mssql_security_sqlserveraudit: {
    engine: "mssql", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "collect_target", type: "varchar2", len: 200 },
      { name: "servername", type: "varchar2", len: 200 },
      { name: "auditname", type: "varchar2", len: 200 },
      { name: "auditenabled", type: "number", prec: 2, scale: 0 },
      { name: "writelocation", type: "varchar2", len: 200 },
      { name: "auditspecificationname", type: "varchar2", len: 400 },
      { name: "auditspecificationenabled", type: "number", prec: 2, scale: 0 },
      { name: "auditactionname", type: "varchar2", len: 400 },
      { name: "audited_result", type: "varchar2", len: 120 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  // ---------------------------------------------------------------- postgres
  postgres_hosts: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "environment", type: "varchar2", len: 80 },
      { name: "license_type", type: "varchar2", len: 200 },
      { name: "pg_version", type: "varchar2", len: 200 },
      { name: "port", type: "number", prec: 5, scale: 0 },
      { name: "data_directory", type: "varchar2", len: 1020 },
      { name: "start_time", type: "varchar2", len: 120 },
      { name: "max_connections", type: "number", prec: 10, scale: 0 },
      { name: "shared_buffers_mb", type: "number", prec: 10, scale: 0 },
      { name: "wal_level", type: "varchar2", len: 80 },
      { name: "archive_mode", type: "varchar2", len: 80 },
      { name: "db_role", type: "varchar2", len: 80 },
    ],
    omitted: []
  },
  postgres_databases: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "environment", type: "varchar2", len: 80 },
      { name: "datname", type: "varchar2", len: 400 },
      { name: "owner", type: "varchar2", len: 400 },
      { name: "encoding", type: "varchar2", len: 80 },
      { name: "collation", type: "varchar2", len: 200 },
      { name: "size_mb", type: "number", prec: 15, scale: 0 },
      { name: "datconnlimit", type: "number", prec: 10, scale: 0 },
      { name: "is_template", type: "varchar2", len: 12 },
      { name: "tablespace", type: "varchar2", len: 400 },
      { name: "xid_age", type: "number", prec: 12, scale: 0 },
    ],
    omitted: ["date_value"]
  },
  postgres_replication: {
    engine: "postgres", source: "déduit des scripts",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "db_role", type: "varchar2", len: 80 },
      { name: "peer_addr", type: "varchar2", len: 400 },
      { name: "state", type: "varchar2", len: 120 },
      { name: "sync_state", type: "varchar2", len: 80 },
      { name: "lag_seconds", type: "number", prec: 10, scale: 0 },
    ],
    omitted: []
  },
  postgres_backup: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "archive_mode", type: "varchar2", len: 80 },
      { name: "archived_count", type: "number", prec: 15, scale: 0 },
      { name: "last_archived_wal", type: "varchar2", len: 200 },
      { name: "last_archived_time", type: "varchar2", len: 120 },
      { name: "failed_count", type: "number", prec: 15, scale: 0 },
      { name: "last_failed_wal", type: "varchar2", len: 200 },
      { name: "last_failed_time", type: "varchar2", len: 120 },
    ],
    omitted: []
  },
  postgres_extensions: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "datname", type: "varchar2", len: 400 },
      { name: "extname", type: "varchar2", len: 400 },
      { name: "extversion", type: "varchar2", len: 80 },
    ],
    omitted: []
  },
  postgres_security_parameter: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "parameter_name", type: "varchar2", len: 400 },
      { name: "parameter_value", type: "varchar2", len: 2000 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  postgres_security_roles: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "rolname", type: "varchar2", len: 400 },
      { name: "rolsuper", type: "varchar2", len: 4 },
      { name: "rolcreaterole", type: "varchar2", len: 4 },
      { name: "rolcreatedb", type: "varchar2", len: 4 },
      { name: "rolcanlogin", type: "varchar2", len: 4 },
      { name: "rolreplication", type: "varchar2", len: 4 },
      { name: "rolbypassrls", type: "varchar2", len: 4 },
      { name: "rolconnlimit", type: "number", prec: 10, scale: 0 },
      { name: "rolvaliduntil", type: "varchar2", len: 120 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  postgres_sec_role_members: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "role_name", type: "varchar2", len: 400 },
      { name: "member_of", type: "varchar2", len: 400 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  postgres_security_hba_rules: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "line_number", type: "number", prec: 10, scale: 0 },
      { name: "rule_type", type: "varchar2", len: 80 },
      { name: "database", type: "varchar2", len: 800 },
      { name: "user_name", type: "varchar2", len: 800 },
      { name: "address", type: "varchar2", len: 400 },
      { name: "auth_method", type: "varchar2", len: 120 },
    ],
    omitted: ["compliance_score","date_value"]
  },
  postgres_sec_db_privs: {
    engine: "postgres", source: "collecte réelle",
    fields: [
      { name: "collect_id", type: "varchar2", len: 16 },
      { name: "hostname", type: "varchar2", len: 400 },
      { name: "datname", type: "varchar2", len: 400 },
      { name: "grantee", type: "varchar2", len: 400 },
      { name: "privilege_type", type: "varchar2", len: 120 },
    ],
    omitted: ["compliance_score","date_value"]
  },

   // ------------------------------------------------------------------ discovery
   // Deux fichiers qui ne viennent pas de la collecte et n'en ont pas le format.
   //
   // Le NOM DE FICHIER differe du nom de table : load_info_discovery.sh attend
   // discovery_mssql.csv pour discovery_mssql_inst. C'est un contrat de
   // production, on le porte explicitement plutot que de plier l'un des deux.
   discovery_mssql_inst: {
      engine: 'discovery',
      source: 'discovery/windows/discovery_MSSQL.ps1',
      fileName: 'discovery_mssql.csv',
      // Charge PAR NOM (COLUMN_NAMES ON) : l'en-tete est obligatoire, et
      // l'ordre ci-dessous est celui de l'objet PowerShell, pas celui de la
      // table -- tcpport y est en 13e position et non en 17e. C'est
      // volontaire : c'est la seule chose qui prouve que le chargement par nom
      // fait bien son travail.
      format: { delimiter: ',', quoted: true, header: true },
      fields: [
         { name: 'serveur', type: 'varchar2', len: 150 },
         { name: 'instance', type: 'varchar2', len: 128 },
         { name: 'service', type: 'varchar2', len: 128 },
         { name: 'edition', type: 'varchar2', len: 100 },
         { name: 'version', type: 'varchar2', len: 50 },
         { name: 'patch', type: 'varchar2', len: 50 },
         { name: 'etatservice', type: 'varchar2', len: 30 },
         { name: 'demarrage', type: 'varchar2', len: 30 },
         { name: 'compteservice', type: 'varchar2', len: 150 },
         { name: 'bitness', type: 'varchar2', len: 10 },
         { name: 'editiongratuite', type: 'varchar2', len: 10 },
         { name: 'portsql', type: 'varchar2', len: 10 },
         { name: 'tcpport', type: 'varchar2', len: 20 },
         { name: 'acceswmi', type: 'varchar2', len: 30 },
         { name: 'protocole', type: 'varchar2', len: 20 },
         { name: 'statut', type: 'varchar2', len: 100 },
         { name: 'detail', type: 'varchar2', len: 1000 }
      ],
      omitted: []
   },

   // Charge POSITIONNELLEMENT, sans en-tete, en ';' et sans guillemets : ici
   // l'ordre des colonnes EST le contrat. Le separateur est ';' et non ',' pour
   // que ora_sids puisse lister plusieurs SID separes par des virgules.
   // Le producteur n'ecrit jamais de champ vide : il ecrit '-'.
   discovery_linux_engines: {
      engine: 'discovery',
      source: 'discovery/linux/detect_db_engines.sh (v2)',
      fileName: 'discovery_linux.csv',
      format: { delimiter: ';', quoted: false, header: false },
      fields: [
         { name: 'hostn', type: 'varchar2', len: 150 },
         { name: 'pg_pkg', type: 'varchar2', len: 1 },
         { name: 'pg_proc', type: 'varchar2', len: 10 },
         { name: 'pg_port', type: 'varchar2', len: 100 },
         { name: 'pg_port_guess', type: 'varchar2', len: 1 },
         { name: 'ora_pkg', type: 'varchar2', len: 1 },
         { name: 'ora_proc', type: 'varchar2', len: 10 },
         { name: 'ora_sids', type: 'varchar2', len: 400 },
         { name: 'ora_port', type: 'varchar2', len: 100 },
         { name: 'ora_port_guess', type: 'varchar2', len: 1 },
         { name: 'my_pkg', type: 'varchar2', len: 1 },
         { name: 'my_proc', type: 'varchar2', len: 10 },
         { name: 'my_port', type: 'varchar2', len: 100 },
         { name: 'my_port_guess', type: 'varchar2', len: 1 }
      ],
      omitted: []
   }
};
