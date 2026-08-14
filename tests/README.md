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
**no npm dependency** — which matters here, since the machine has no npm registry
access.
