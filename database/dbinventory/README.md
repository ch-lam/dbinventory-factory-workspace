# Schema `DBINVENTORY`

The data model and the database code shared by the applications of workspace
`DBINVENTORY`. The schema itself is created by the factory.

| File | What | When it runs |
|---|---|---|
| `V__NNN_<what>.sql` | a versioned migration: tables, constraints, data | once, in name order, recorded in `SCHEMA_MIGRATIONS` |
| `R__<object>.sql` | rerunnable code: `create or replace` view, function, package | on every run, in the order of `R__order.txt` |
| `T__NNN_<what>.sql` | a check that fails the run | last, on every run |
| `migrate.sh` | applies all of the above | see below |
| `X_000_reinstall_all.sql` | the same install in one SQLcl run, for a temporary environment | by hand, in an empty schema |
| `X_001_cleanup_and_reinstall_all.sql` | drops everything, then runs `X_000` | by hand; refuses a schema managed by `migrate.sh` |

```bash
database/dbinventory/migrate.sh <connection> --dry-run   # what is pending
database/dbinventory/migrate.sh <connection>             # apply it

# temporary environment only (never DEV or DEMO of the factory)
cd database/dbinventory && sql -S -name <connection> @X_001_cleanup_and_reinstall_all.sql
```

Rules:
- Never edit a `V__` file once it is applied somewhere: `migrate.sh` refuses a changed
  checksum. Add the next `V__` file instead.
- A `V__` file must be correct on the first run: it is not replayed.
- Name objects without the schema prefix; the connection decides the schema.
- One object per `R__` file, its package body in `R__<NAME>_BODY.sql`, and every `R__` file
  listed in `R__order.txt`.
- `X_000_reinstall_all.sql` lists every `V__` in name order, then every `R__` in the order
  of `R__order.txt`, then every `T__`. `migrate.sh` checks it on every run, `--dry-run`
  included, so a file added without it fails the pipeline.
- `migrate.sh` runs on Linux and under Git Bash on Windows, and must stay that way: see
  `AGENTS.md`, "Outillage portable". Its checksums ignore carriage returns.
- Checks that need the demonstration data live in `fixtures/checks/`, not here: DEV has none.
