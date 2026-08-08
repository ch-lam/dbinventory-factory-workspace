# Troubleshooting

Symptom → cause → fix. Every entry was hit for real.

## Before touching your code

| Symptom | Cause | Fix |
| --- | --- | --- |
| `APEXLANG_LOCAL_CHECK_FAILED`, preceded by *"Python was not found; run without arguments to install from the Microsoft Store"* | `python.exe` resolves to the Microsoft Store stub. Python is an undeclared prerequisite of the local check. | Install a real Python 3, or disable the alias in Settings → Apps → App execution aliases. Or skip the local check: live validation goes through SQLcl. |
| `node: command not found` right after installing Node | The running process kept the old `PATH`. | Restart the CLI process, not just the conversation. Meanwhile call by absolute path. |
| **A pile of problems, every one a `WARNING`** about JLine, restricted methods or final field mutation — 21 in the observed case | SQLcl 26.2 on a recent JDK emits 7 warning lines per invocation during validation (× 3 invocations = 21); the parser counts any line matching `/\bwarning\b/i`; `warnings_as_errors` makes them blocking. | Set `JDK_JAVA_OPTIONS=--enable-native-access=ALL-UNNAMED --enable-final-field-mutation=ALL-UNNAMED`. Note `JAVA_OPTS` is ignored by `sql.exe` on Windows. |
| Command killed at exactly 2 minutes | `runtime validate` legitimately takes longer. | Run it detached / with a longer timeout. |

## Resolving the app and workspace

| Symptom | Cause | Fix |
| --- | --- | --- |
| `workspace probe` → `status: unresolved`, `app_context.status: missing` | No `applications/` directory; the app lives elsewhere. | Pass `--app-path <absolute path>`. Not an error — a Missing Input. |
| `db_context.workspace.name: ""`, `source: unresolved` | The workspace name is never auto-bound, and guessing it is forbidden. | `select workspace, workspace_id from apex_applications where application_id = :id;` |

## Compilation

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Invalid property: staticValues` + `Invalid LOV required parameter: source - type` | There is no static-values construct for LOVs. | Use `source { type: sqlQuery }` with `union all ... from dual`, plus `columnMapping`. |
| `Invalid property: target` **and** `Invalid property: linkText` on a report column | The column is missing `type: link`. The message names neither. | Add `type: link` to the column. |
| `Minimum number of children of type "column" not reached. Minimum 1, found 0.` | A `classicReport` region declares no `column`. | Declare at least one column block. |
| `Missing required parameter (411): componentAppearance - template (string)` | Region missing its `componentAppearance` block. | Add `componentAppearance { template: @/standard ... }`. |
| `Invalid Slot value: layout - slot (STRING) : body` on a modal page | Modal pages have no `body` slot. | `slot: contentBody`. Reported as a *warning* — silently misplaces the region if warnings are not blocking. |
| Report headings suddenly show the wrong data after adding a column | `reportColumnQueryId` is positional; inserting mid-`select` renumbers everything after it. | Append new columns at the end of the `select`. |
| A page item type is rejected and compiler truth cannot confirm it | `pageItem.type` uses `lovType=PLUGINS`; values come from the APEX instance, not the metadata. | Check `templates/items/<family>/` for the sanctioned shape, or the instance. Do not invent. |

## Reading the report

| Symptom | Cause | Fix |
| --- | --- | --- |
| Problem entries have `file: ""` and tiny line numbers | Lines are relative to a normalised stream, not your source. | Locate by message + count, not coordinates. |
| `validation_status: fail` but `problem_count: 0` and the transcript says `Validation successful.` | The inner capability probe resolved `build_root_unresolved` / `apex_root_missing` and failed the run before the validation that then succeeded. | **Unresolved.** `--apex-root <SQLcl home>` is not accepted — it wants an unpacked APEX distribution. Workaround: import manually from the builder. Do not force past the gate. |

## Database

| Symptom | Cause | Fix |
| --- | --- | --- |
| `PLS-00201: identifier 'STANDARD_HASH' must be declared` | It is a SQL function, not PL/SQL. | Call it via `select ... into ... from dual` — though for BLOBs see the next row. |
| `ORA-00902: invalid datatype` from `STANDARD_HASH` on a BLOB | It does not accept BLOB. | Use `DBMS_CRYPTO`. |
| `PLS-00201: identifier 'DBMS_CRYPTO' must be declared` | No grant; `all_objects` shows nothing. | `grant execute on sys.dbms_crypto to <schema>;` Reach it through dynamic SQL so packages still compile without the grant. |
| A checksum computed by your API can be forged by a direct insert | The API computes it, but nothing stops a caller supplying their own. | Recompute unconditionally in a `before insert` trigger, so it holds for every writer. |
