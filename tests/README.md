# Tests

Two tests, covering two different failure modes. They are complementary: neither
replaces the other, and neither replaces APEXlang validation.

| | What it proves | Needs |
| --- | --- | --- |
| `../database/dbinventory/T_001_apex_page_smoke.sql` | The database side of the application is coherent | SQLcl + a connection |
| `apex_page_test.mjs` | The pages actually render for a user | A Chromium browser + the deployed app reachable |

## Why they exist

APEXlang validation proves the `.apx` compiles. **It never opens a page.** Page 71
passed five clean validations and still died on first render, because an attribute
the `.apx` cannot express fell back to a default that breaks at runtime.

So a green validation is necessary, not sufficient.

## Setup

```bash
cp .env.example .env      # then fill in the passwords
```

`.env` is gitignored. Never commit it.

## Running them

```bash
# database side -- after every schema change or import
sql -S -name DEV_DBINVENTORY_dbinventory @database/dbinventory/T_001_apex_page_smoke.sql

# rendering -- after every import, or on the pages whose components changed
node tests/apex_page_test.mjs
node tests/apex_page_test.mjs --pages 70,71
node tests/apex_page_test.mjs --profile RSSI
node tests/apex_page_test.mjs --head            # watch the browser work
```

Both exit non-zero on failure, so they can gate a deployment script.

## When to run which

- **Schema changed** (a column renamed, a view rewritten): `T_001` first. It parses
  every region query against the live schema, which is how a back-end change that
  silently breaks a page gets caught.
- **A page or a component changed**: `apex_page_test.mjs --pages <ids>`.
- **After an import**: both. An import resets attributes that cannot be expressed
  in the `.apx`, so a page that worked before an import can be broken by it —
  today `P71_UPLOAD`, which must be set back to `APEX_APPLICATION_TEMP_FILES` in
  the builder every time.

## First: are both tests looking at the same database?

They are configured **independently** — one by `APEX_BASE_URL` in `.env`, the other
by a SQLcl connection name — so nothing guarantees they target the same
environment. Two environments look alike until one of them misleads you.

Ask the application itself. The About page (10002) and the query below read the
same view, so they cannot disagree:

```sql
select value from v_environment_identity where name = 'Service name';
-- DBINVENTORY_DEV_ALL
```

Open the About page in the browser and compare. Same service name, same schema
version, same deployment date means the two tests are comparable; anything else
means their verdicts say nothing about each other.

This is not hypothetical: an instance *named* `BJ1` was once mistaken for a
different environment than one holding `instance_id = 1`, and the two were the
same row. The view exists so nobody has to infer it again.

## Reading a failure

`T_001` tells you *why* — a query that no longer parses, an item on a bad default.
`apex_page_test.mjs` tells you *that* the user sees an error, with the message.
When both point at the same page, the first explains the second.

## Test profiles

`.env` holds one credential pair per role, and `--profile` picks one. This is not
over-engineering: the derogation model forbids a request and its approval coming
from the same person, so exercising that path needs two accounts.

## Known limitation

`apex_page_test.mjs` drives a real browser because logging in over raw HTTP does
not work — APEX protects submission with a salt, a single-use submission id and
protected values assembled in JavaScript. Three curl conventions were tried; all
came back to the login page. Driving a browser also means the test stays correct
across APEX upgrades instead of re-implementing a protocol that moves.

It uses Node's built-in `WebSocket` over the Chrome DevTools Protocol, so there is
**no npm dependency**: no install step, no lockfile, and nothing to reinstall when
the test is copied into another repository. It needs a Node exposing a global
`WebSocket`, stable since Node 22 (this machine runs v24.19.0).

An earlier version of this note justified that choice by claiming the machine had
no npm registry access. Re-tested on 2026-08-15: `npm ping` and a tarball lookup
both succeed against `https://registry.npmjs.org/`, with no proxy configured. The
claim was wrong; the design stands on its own merits.

## After every import — the manual step, and why it is a list now

An import resets attributes that the `.apx` cannot express. Today two items are
affected, both `fileUpload`:

| Page | Item | Set Storage Type to |
| --- | --- | --- |
| 71 | `P71_UPLOAD` | `APEX_APPLICATION_TEMP_FILES` |
| 85 | `P85_UPLOAD` | `APEX_APPLICATION_TEMP_FILES` |

**Do not maintain that table by hand — ask the database:**

```bash
sql -S -name "$APEX_DB_CONN" @database/dbinventory/T_001_apex_page_smoke.sql
```

Check 2 lists exactly the items that need the step, on the environment in front
of you. A table in a README drifts; the check does not.

Why it is manual at all, and what would end it, is proven in T1 of the field
notes: the compiler has no property for the storage type, and no API sets it.

### The browser test cannot replace it here

Two items, identical metadata, opposite symptoms — the difference is the region
they sit in:

- `P71_UPLOAD` is in a **report** region: APEX tries to bind the BLOB to a column
  and the page dies loudly at render, so the browser test catches it.
- `P85_UPLOAD` is in a **static content** region: it renders a plain file input
  and says nothing. The page looks perfect, the file goes nowhere, and the save
  process finds an empty cursor in `apex_application_temp_files`.

The silent one is the dangerous one. **A green browser run says nothing about
upload items.** Run `T_001` after every import, without exception.
