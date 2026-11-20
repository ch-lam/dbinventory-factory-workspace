# Schema `DBINVENTORY`

The data model and the database code shared by the applications of workspace
`DBINVENTORY`. The schema itself is created by the factory.

| File | What | When it runs |
|---|---|---|
| `V__NNN_<what>.sql` | a versioned migration: tables, constraints, data | once, in name order, recorded in `SCHEMA_MIGRATIONS` |
| `R__<object>.sql` | rerunnable code: `create or replace` view, function, package | on every run, in the order of `R__order.txt` |
| `T__NNN_<what>.sql` | a check that fails the run | last, on every run |
| `migrate.sh` | applies all of the above | see below |

```bash
database/dbinventory/migrate.sh <connection> --dry-run   # what is pending
database/dbinventory/migrate.sh <connection>             # apply it
```

Rules:
- Never edit a `V__` file once it is applied somewhere: `migrate.sh` refuses a changed
  checksum. Add the next `V__` file instead.
- A `V__` file must be correct on the first run: it is not replayed.
- Name objects without the schema prefix; the connection decides the schema.
- One object per `R__` file, its package body in `R__<NAME>_BODY.sql`, and every `R__` file
  listed in `R__order.txt`.
