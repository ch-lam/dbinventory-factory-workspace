# Database and workspace

Resolving *which* application, in *which* workspace, and the grants APEX work
tends to need.

## The workspace name must be read, never guessed

The APEXlang contract is explicit: generating `deployments/default.json` is
blocked until the exact workspace name is known, and it must not be inferred from
the app name, the parsing schema, the scaffold seed, or any nearby identifier.

`workspace probe` will not resolve it on its own. It returns:

```json
"db_context": { "workspace": { "name": "", "source": "unresolved" } },
"required_live_inputs": [ "db_connection_name", "db_context.workspace.name" ],
"auto_bind_single_saved_connection": false
```

The authoritative source is the database itself:

```sql
select workspace, workspace_id, application_id, application_name
  from apex_applications
 where application_id = :app_id;
```

Reading it from `apex_applications` is not guessing — it is the live dictionary.
Record the result (app id, workspace name, workspace id) somewhere durable so the
next session does not repeat the lookup.

## Applications outside `applications/`

The toolchain expects apps under `applications/<app>/`, identified by
`application.apx` plus `.apex/`, `pages/`, `shared-components/`.

When that root is absent, `workspace probe` returns:

```json
"app_context": {
  "status": "missing",
  "prompt_required": true,
  "prompt": "No applications/ directory was found. Specify the exact APEX app directory, or provide a bounded directory to scan."
}
```

This is a **Missing Input, not an error**. Pass `--app-path <absolute path>` to
the commands that accept it; `runtime preflight` and `runtime validate` both do,
and both accept a non-standard location without complaint. Do not relocate the app
to satisfy the tool.

The policy for a non-standard candidate is to confirm the exact directory with a
human before app-scoped edits — worth honouring the first time, then recording.

## Grants: fingerprinting a BLOB

Any APEX feature storing uploaded files usually wants a checksum. On a fresh
schema this fails, and the failure modes are misleading.

```sql
grant execute on sys.dbms_crypto to <schema>;
```

Two dead ends to skip:

- **`STANDARD_HASH` does not accept a BLOB.** `ORA-00902: invalid datatype`. It
  handles `VARCHAR2`, `RAW`, `CLOB`, but not `BLOB`.
- **`STANDARD_HASH` is a SQL function, not PL/SQL.** Calling it directly in a
  PL/SQL block raises `PLS-00201: identifier 'STANDARD_HASH' must be declared`.
  It has to go through `select ... into ... from dual`, which then hits the
  datatype problem anyway.

So `DBMS_CRYPTO` is the only route for a BLOB, and it needs an explicit grant —
`all_objects` returns nothing for it without one.

### Keep the package installable without the grant

Calling `sys.dbms_crypto.hash` directly means the package will not compile where
the grant is missing, so the *whole* API becomes uninstallable over one feature.
Reaching it through dynamic SQL keeps everything compilable and moves the failure
to the moment it matters, with a message that names the fix:

```plsql
function fingerprint ( p_content blob ) return varchar2 is
   l_hash raw(32);
begin
   execute immediate
      'begin :h := sys.dbms_crypto.hash(:c, 4); end;'   -- 4 = HASH_SH256
      using out l_hash, in p_content;
   return lower(rawtohex(l_hash));
exception
   when others then
      raise_application_error(-20022,
         'Cannot fingerprint: EXECUTE on SYS.DBMS_CRYPTO is required '
         || '(grant execute on sys.dbms_crypto to ' || user || ').');
end;
```

Verify the grant against a known value rather than just checking it compiles —
SHA-256 of `hello` is
`2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824`.

### Enforce in the table, not only in the API

If a screen writes rows with APEX's own DML, it bypasses any API procedure. Put
integrity rules in a `before insert` trigger on the table instead: they then hold
for every writer — the screen, the package, a script.

It also closes a hole an API-only design leaves open: an API that *computes* a
checksum does not stop a direct insert from *supplying* one. A trigger that
recomputes unconditionally does. An attachment whose fingerprint can be chosen by
whoever uploads it proves nothing.
