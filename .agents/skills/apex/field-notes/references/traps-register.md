# Traps register

Things that are wrong or unreliable **in the tooling**, not in your code. They are
recorded rather than fixed because the tooling will move: each entry carries what
was observed, on which versions, and how to re-test it.

**Review this file whenever SQLcl, the APEXlang package, the VS Code extension or
APEX itself is upgraded.** An entry that has silently been fixed upstream is worse
than one that is still true: it makes you work around a problem you no longer have.

Observed on: SQLcl 26.2.1.0 (build 26.2.1.222.1617) · APEXlang compiler metadata
26.1.0+3102 · APEX 26.1.0 · Oracle 23.26.1.0.0 · Windows.

---

## T1 — Plugin attributes are not expressible for page items

**Impact: breaks a page at runtime.** A `pageItem` has no property group for plugin
attributes, so a `fileUpload` cannot carry its storage type. It inherits
`storage_type = DB_COLUMN` and the page dies with `NO_VALID_BLOB_SOURCE`.

Workaround: set it in the builder after every import.

Re-test: `node tools/query-valid-props.mjs --component pageItem` and look for a
`settings` group. If one appears, T1 is gone and the `.apx` can own the attribute.

## T2 — Vendor templates contradict the compiler

`templates/items/file-upload/file-upload._common.md` documents `settings.storageType`,
`allowMultipleFiles` and others; the compiler rejects them. The same file documents
`source.formRegion` / `column` / `dataType`, **unverified**.

Consequence: no template can be trusted on its own. Confront it with
`query-valid-props.mjs`, or with a component that already validates, before use.

Re-test: emit a `settings` block and see whether it still fails.

## T3 — Compiler truth comes from the VS Code extension, not from your APEX

Reports show `source: vscode_extension`, `oracleHome` pointing at
`oracle.sql-developer-26.2.1`. The deployment target here is APEX 26.1.0, and two
extension versions were installed side by side.

So the language is validated against one generation and deployed onto another. This
is the most likely root of T2, though it is not proven.

Re-test: read `compilerTruth.oracleHome` in any `query-valid-props --json` output
and compare with `select version_no from apex_release`. `--compiler-oracle-home`
forces which extension answers.

## T4 — JVM warnings are counted as validation problems

The parser flags any line matching `/\bwarning\b/i` (`runtime/runtime.bundle.mjs`)
with no known-noise filter, and `warnings_as_errors: true` makes them blocking.
SQLcl emits several per invocation.

Still true after the 26.2.0 → 26.2.1 upgrade, and the count changed: 3 lines on a
bare invocation before, 7 after, including a new `MemorySegment::reinterpret` one.
**Never calibrate on a count — check it is zero.**

Workaround: `JDK_JAVA_OPTIONS=--enable-native-access=ALL-UNNAMED --enable-final-field-mutation=ALL-UNNAMED`.
`JAVA_OPTS` is ignored by `sql.exe` on Windows.

Re-test: `echo exit | sql -S /nolog 2>&1 | grep -ciE '\bwarning\b'` without the
variable. Zero means T4 is gone.

## T5 — The local check needs Python, undeclared

`apexlang validate` shells out to `python3`/`python`. The README lists only SQLcl
and Java. On Windows the Store stub masquerades as `python.exe`.

Only the live route matters anyway; the skill treats local checks as syntax
hygiene.

## T6 — `apex_root_missing` is a red herring

Reported as the cause when live validation fails to produce pass evidence, but the
same source passed later with the build root still empty. See
`validation-chain.md`. **Mechanism unknown** — recorded so nobody spends a day
installing an APEX distribution for it.

---

## The rule this register exists to enforce

**A clean validation says the `.apx` compiles. It says nothing about whether the
page runs.**

So: any change to a page carrying a component whose behaviour depends on an
attribute the `.apx` cannot express — today that means anything with a
`fileUpload`, and more generally any native item type not already proven in the
application — **requires opening the page after import, not just a green
validation**.

Concretely, before calling such a change done:

1. Import.
2. Open the page in a browser.
3. For each item whose type is new to this application, read back what it actually
   got: `select attributes from apex_application_page_items where application_id = :a and page_id = :p and item_name = :i;`
4. Apply the manual settings listed in the `.apx` comments, then re-open.

Pages currently under this rule in this project: **71** (`P71_UPLOAD`).
