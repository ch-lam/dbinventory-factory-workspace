# Testing an APEX application

How to prove a page actually works, and the traps that make a test lie to you.

The premise: **APEXlang validation proves the `.apx` compiles; it never opens a
page.** A page here passed five clean validations and died on first render. So a
test suite needs two legs, and neither replaces the other.

| Leg | Proves | Needs |
| --- | --- | --- |
| Database-side smoke test | region SQL parses, plugin attributes are sane, LOV references resolve | SQLcl |
| Browser page test | the pages render for a user | a Chromium browser + the app reachable |

Reference implementations live in `tests/` and
`database/dbinventory/T_001_apex_page_smoke.sql` of the dbInventory project.

---

## Driving the browser

### Log in with a browser, not with HTTP

Raw HTTP login does not work. APEX protects submission with `pSalt`, a single-use
`p_page_submission_id` and `protected` values assembled in JavaScript. Three
conventions were tried against APEX 26.1 — legacy `p_t01`/`p_t02`, direct item
names, modern `p_json` with the extracted salt — all returned the login page with
no error message.

Drive a real browser and let APEX assemble its own payload:

```js
document.getElementById('P9999_USERNAME').value = user;
document.getElementById('P9999_PASSWORD').value = password;
apex.page.submit('LOGIN');
```

`apex.page.submit` is the point: it is APEX's own submission path, so it stays
correct across upgrades instead of re-implementing a protocol that moves.

### No npm required

Node's built-in `WebSocket` speaks the Chrome DevTools Protocol directly. Launch
any Chromium build with `--headless=new --remote-debugging-port=N
--user-data-dir=<temp>`, poll `http://127.0.0.1:N/json/version` until it answers,
then `PUT /json/new` and connect to `webSocketDebuggerUrl`.

Edge works and is usually already installed on Windows. Add
`--ignore-certificate-errors` for internal hosts with self-signed certificates.

### Wait on `document.readyState`, not on a load event

APEX finishes rendering after the load event fires. Poll for `complete`, then give
it a short extra pause, or you read the page too early and see a half-built DOM.

---

## Four traps that make a test lie

Each of these produced a wrong verdict before being found. They are the reason a
test must be **seen failing for the right reason** before it is trusted.

### 1. An empty session slot silently logs you out

`f?p=APP:PAGE` with nothing in the third position starts a **new, unauthenticated**
session. Every page bounces to the login screen. The first run of the page test
reported eight broken pages; none were broken.

Carry the session: `f?p=APP:PAGE:SESSION`. Read the id from `?session=` on a
friendly URL, from the third position of an `f?p=` URL, or from
`apex.env.APP_SESSION`.

Detect the bounce explicitly — a page that came back to the login screen must be a
failure, not a pass:

```js
if (document.getElementById('P9999_USERNAME')) { /* session lost */ }
```

### 2. A modal page cannot be opened by URL

Navigating straight to a modal page gives *"Dialog page N cannot be rendered
successfully. Ensure the page template in use is of template type Dialog page"* —
whatever the page actually does. That message masked the real error on the page it
was hiding.

Reach it the way a user does: open the parent, then click the link.

### 3. A dialog link is not an `f?p=` URL

In a friendly-URL application the link is an action:

```
#action$a-dialog-open?url=…&appId=100&pageId=71&tmpl=modal-dialog&…
```

Matching on `:71:` finds nothing. Match on `pageId=71` as well.

### 4. Modal content lives in an iframe

The dialog renders into a same-origin iframe, so the parent's `innerText` does not
contain it. Read both, or **a broken dialog looks perfectly clean** — a false
negative, worse than the false positives above.

```js
var out = document.body.innerText;
for (var f of document.querySelectorAll('iframe')) {
  try { out += '\n' + f.contentDocument.body.innerText; } catch (e) { /* cross-origin */ }
}
```

---

## Reporting

### Separate "not deployed" from "broken"

A page that exists in source but was never imported answers
`Application "100" Page "10002" not found.` Reporting that as a rendering error
means the suite cries wolf after every source change, and a test people learn to
ignore protects nothing. Detect it and say `import it first`.

### Have a third state for "could not test"

A modal page needs a row in its parent report to have a link to follow. With no
data there is no link, so the page is **unreachable, not working**. Fold it into
the passes and you are lying by omission; report it as a failure and the suite
turns noisy. Use a distinct `skip`, count it, and say plainly in the summary that a
skipped page is not known to work.

### Report the specific line, not the first match

APEX shows a precise cause next to a generic *"Contact your application
administrator."* Matching the generic one first tells the reader nothing. Prefer
any matching line that is **not** generic.

---

## Configuration

Put the base URL and credentials in a gitignored `.env` with a versioned
`.env.example`, and key credentials **per profile** rather than a single pair:

```
APEX_USER_ADMIN=…      APEX_PASS_ADMIN=…
APEX_USER_RSSI=…       APEX_PASS_RSSI=…
```

This is not premature: any workflow with segregation of duties — a request that
cannot be approved by its author — needs two accounts to be testable at all.

Add `.env` to `.gitignore` **before** creating it, and check `git status` does not
offer it afterwards.

---

## Knowing which environment you are on

The single most valuable thing to build early. The web URL and the SQLcl
connection are configured independently, so nothing guarantees a browser test and
a database test look at the same place. Two environments look alike until one
misleads you — an instance *named* `BJ1` was once mistaken for a different
environment than one holding `instance_id = 1`, and they were the same row.

Build a view the application, SQLcl and a pipeline all read, shaped as
**name/value pairs** so a page renders it trivially and a pipeline pulls one value
by name:

```sql
select value from v_environment_identity where name = 'Service name';
```

The database already knows most of it without any new table:
`sys_context('USERENV', …)` gives `DB_NAME`, `CON_NAME`, `SERVICE_NAME`,
`DB_UNIQUE_NAME`, `SERVER_HOST`, `CURRENT_SCHEMA`. A service name like
`DBINVENTORY_DEV_ALL` identifies the environment on its own.

What it does *not* know is the schema version and deployment date. An append-only
release table written by the install script supplies both, and its sequence shows
**how** two environments diverged rather than merely that they did.

One caution when assembling such a view: `product_component_version` lists the
product as *"Oracle AI Database 26ai Enterprise Edition"*, so a filter of
`product like 'Oracle Database%'` returns nothing — and an empty field reads like
a missing privilege rather than a bad pattern.
