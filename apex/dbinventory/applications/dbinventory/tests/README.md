# Tests of the DBINVENTORY application

Two tests, covering two different failure modes. They are complementary: neither
replaces the other, and neither replaces APEXlang validation.

| | What it proves | Needs |
| --- | --- | --- |
| `T_001_apex_page_smoke.sql` | The database side of the application is coherent | SQLcl + a connection |
| `apex_page_test.mjs` | The pages actually render for a user | A Chromium browser + the deployed app reachable |

## Why they exist

APEXlang validation proves the `.apx` compiles. **It never opens a page.** Page 71
passed five clean validations and still died on first render, because an attribute
the `.apx` cannot express fell back to a default that breaks at runtime.

So a green validation is necessary, not sufficient.

## Setup

```bash
# at the repository root
cp .env.example .env      # then fill in the passwords
```

`.env` is gitignored. Never commit it. The browser test reads the nearest `.env`
above it, so the one at the repository root is found from here.

## Running them

From the application directory, `apex/dbinventory/applications/dbinventory`.

```bash
# database side -- after every schema change or import
sql -S -name DEV_DBINVENTORY_dbinventory @tests/T_001_apex_page_smoke.sql

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
- **After an import**: both. An import sets every attribute the `.apx` leaves out
  to its default, so a page that worked before an import can be broken by it —
  the `fileUpload` items `P71_UPLOAD` and `P85_UPLOAD` were, until their storage
  block could be written in the `.apx` (see `DEPLOY.md`).

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

## After every import — the upload items

Both `fileUpload` items carry their storage type in the `.apx`:

```
storage {
    type: appTempFiles
}
```

That block needs the APEXLang compiler 26.2 (SQLcl 26.3). Until then it could
not be written, and every import left both items on `DB_COLUMN` until someone
set *Storage Type* back to `APEX_APPLICATION_TEMP_FILES` in the builder. The
first import with the block, on 2026-11-10, held without that step.

**Still check it after every import — ask the database:**

```bash
sql -S -name "$APEX_DB_CONN" @tests/T_001_apex_page_smoke.sql
```

Check 2 lists every upload item left on `DB_COLUMN`, on the environment in front
of you: one written without the block, or an import made with an older SQLcl.

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
