# Environment

What must be installed and configured before the APEXlang toolchain does anything
useful. Two of the four items below are not documented by the vendor package.

## `JDK_JAVA_OPTIONS` — set this first

```
JDK_JAVA_OPTIONS=--enable-native-access=ALL-UNNAMED --enable-final-field-mutation=ALL-UNNAMED
```

**Without it, validation reports 21 problems that have nothing to do with your
code, and blocks the import.**

Three things combine to produce that:

- SQLcl 26.2 running on a recent JDK (24 here) emits JVM warnings — JLine native
  access, restricted methods, final field mutation. During a validation run it
  emitted **7 warning lines per SQLcl invocation** (4 from the native-access
  family, 3 from final-field-mutation).
- The skill's output parser classifies **any line containing "warning"** as a
  problem: `WARNING_PATTERN = /\bwarning\b/i` in `runtime/runtime.bundle.mjs`.
  There is no known-noise filter.
- `warnings_as_errors: true` makes them blocking.

7 lines × 3 SQLcl invocations = 21 phantom problems that read exactly like a
regression in your `.apx` files.

How many appear depends on which code paths run: a bare `sql -S /nolog` with only
`exit` emits just the 3 final-field lines, because it never loads the JLine native
library. Do not calibrate on a bare invocation — measure inside a real validation
run, or simply set the variable and check the count is zero.

Two traps when fixing it:

- **`JAVA_OPTS` does not work on Windows.** Only the `sql` shell script reads it;
  `sql.exe` ignores it. Verified: same seven warnings with and without.
- **`JAVA_TOOL_OPTIONS` would also work** but prints `Picked up JAVA_TOOL_OPTIONS:`
  — harmless here since it contains no "warning", but `JDK_JAVA_OPTIONS` is
  cleaner. Its own `NOTE: Picked up JDK_JAVA_OPTIONS:` line is likewise ignored by
  the parser.

Verify — with the variable set the count must be **0**; without it, non-zero
(3 on a bare invocation, 7 inside a validation run):

```bash
export JDK_JAVA_OPTIONS="--enable-native-access=ALL-UNNAMED --enable-final-field-mutation=ALL-UNNAMED"
echo exit | sql -S /nolog 2>&1 | grep -ciE '\bwarning\b'    # expect 0
```

Mirror the parser's own regex, `\bwarning\b` case-insensitive. The word boundary
matters: SQLcl also prints a benign `extension-loading warnings.` line, and the
plural does **not** match `\bwarning\b`, so it is never counted as a problem. A
looser `grep -i warning` returns 1 and makes a clean run look dirty.

## Node.js

Any modern version. Verified about the toolchain itself:

- No `package.json`, no `package-lock.json`, no `node_modules`.
- The tools import **only Node built-ins** — `node:fs`, `node:crypto`,
  `node:path`, `node:child_process`, `node:os`, `node:url`, `node:zlib`.

So there is **no `npm install` and no access to the npm registry required**. This
matters on an air-gapped or restricted server: Node alone is enough.

The tools use top-level `await` and optional chaining, so anything from Node 18
upwards is safe. LTS is the sensible choice.

## Python 3 — an undeclared prerequisite

The local check step (`apexctl.mjs apexlang validate`) shells out to `python3`
then `python`, and runs `runtime/internal/python/validate_apexlang.py`.

**The vendor README does not list Python.** It lists SQLcl and Java only. You
discover the dependency when the command fails with `APEXLANG_LOCAL_CHECK_FAILED`.

The validator imports only the standard library (`argparse`, `dataclasses`,
`json`, `os`, `re`, `sys`, `pathlib`) — so no `pip install`, any Python 3 works.

**Windows trap:** `python.exe` frequently resolves to
`%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe`, the Microsoft Store stub. It
prints *"Python was not found; run without arguments to install from the Microsoft
Store"* and exits — so the command appears to exist but never runs. Either install
a real Python and make sure it precedes the stub on `PATH`, or disable the alias
in **Settings → Apps → Advanced app settings → App execution aliases**.

Whether you need Python at all depends on your route: the *local* check needs it,
the *live* validation does not — it goes through SQLcl. The skill treats live
validation as authoritative and local checks as syntax hygiene, so a live-only
route is legitimate.

## SQLcl and Java

The only prerequisites the vendor actually documents: **SQLcl 26.1.2 or newer**,
and **Java 17 or 21** for it.

A saved SQLcl connection name is required for anything touching the database. The
toolchain resolves `sql` from `PATH` when no APEX build root is configured — it
reports `execution_mode: path` with the note `apex_root_missing`. That is enough
for validation; see `validation-chain.md` for what it is *not* enough for.

## PATH after installing

Installing Node or Python updates the machine `PATH`, but **already-running
processes keep the old one**. Restarting the conversation or the agent session is
not enough — the CLI process itself must restart, or its parent shell.

Until then, calling by absolute path works normally:
`& "C:\Program Files\nodejs\node.exe" --version`.

## Quick check

```bash
node --version                       # any 18+
python3 --version                    # real Python, not the Store stub
sql -v                               # SQLcl 26.1.2+
echo $JDK_JAVA_OPTIONS               # must be set
```
