# The validation chain

How to run it, and — more importantly — how to read what it says. The aggregate
verdict and the state of your code are two different things.

## Order

```bash
node tools/apexctl.mjs workspace probe --db-connection-name <conn>
node tools/apexctl.mjs runtime preflight --app-path <app> --db-connection-name <conn>
node tools/apexctl.mjs apexlang validate --app-path <app>                    # local, needs Python
node tools/apexctl.mjs apexlang compiler-truth audit --app-path <app> --verify-component-attributes
node tools/apexctl.mjs runtime validate --app-path <app> --db-connection-name <conn> \
     --report-path <report.json>
```

All commands are relative to the packaged skill root; run them from there or give
`apexctl.mjs` by absolute path.

**Run `runtime validate` detached.** It exceeds two minutes — SQLcl start-up,
connection, and several passes. A two-minute command timeout kills it mid-flight.

## Reading the verdict

The report has several fields that are easy to conflate. They mean different
things:

| Field | What it tells you |
| --- | --- |
| `problem_count` / `unresolved_count` | How many issues the parser collected. **This is the one about your code.** |
| `validation_sources.compiler_truth.status` | The mandated audit. `pass` + `APEXLANG_COMPILER_TRUTH_AUDIT_OK` means your components match compiler metadata. |
| `validation_sources.live_validator.status` | Whether the tool believes it obtained live evidence. Not the same as whether APEX accepted the app. |
| `validation_status` | Aggregate. Fails if *any* source failed. |
| `import_eligibility` | `blocked` unless everything above lines up. |

**Also read the transcript.** Its path is in
`artifacts.validation_transcript_path`. It contains APEX's own answer, verbatim:

```
## roundtrip_sql_name_alias
SQLcl: Release 26.2 Production ...
Connecté à : Oracle AI Database 26ai ...
Validation successful.
```

`Validation successful.` is APEX validating your application. It can appear while
the aggregate verdict says `fail` — see the known failure below.

## Known failure: `build_root_unresolved` blocks a passing app

Symptom, all at once:

```
problem_count: 0
compiler_truth: pass  (APEXLANG_COMPILER_TRUTH_AUDIT_OK)
transcript:     "Validation successful."
validation_status: fail
import_eligibility: blocked
blocking_reasons: ["Live APEX validation did not pass or did not produce pass evidence."]
```

Cause: two capability probes disagree within one run. The standalone `preflight`
reports `capability_state: path_sqlcl_apex_validate_import` with
`apex_validate_available: true`. The probe *inside* the roundtrip reports
`apex_validate_available: false`, `capability_state: build_root_unresolved`, note
`apex_root_missing` — and the run is marked failed on that basis, before the
validation that then succeeds.

`resolved_apex_build_root` stays empty. Passing `--apex-root <SQLcl home>` does
**not** satisfy it: the tool wants an unpacked APEX distribution directory, not
the SQLcl installation.

**Status: unresolved.** No tested fix. Options, best first:

1. Obtain an APEX distribution matching the installed version and pass it as
   `--apex-root`. Untested here, but it is the gap the tool names.
2. Import the pages manually from the APEX builder. The code is validated by the
   database's own APEX; you lose the roundtrip's traceability.
3. Disabling `warnings_as_errors` does **not** help — the problem count is already
   zero — and it costs you real signal (see below).

Do not force the import past the gate. It exists to stop an application being
changed on incomplete evidence, and it earned its keep: it caught four syntax
errors that would otherwise have shipped.

## Keep `warnings_as_errors: true`

It is what surfaced `Invalid Slot value: layout - slot : body` — a *warning*, not
an error. That would not have failed the import. It would have silently placed
four regions in the wrong part of the page, which is worse than a clean failure.

## Reading `problems.json`

Two traps in the report format:

- Entries carry **`file: ""`** — the file is not attributed.
- **`line` numbers are relative to a normalised stream**, not to your source file.
  Small numbers like 11–20 do not mean line 11 of anything you wrote.

So you cannot locate a problem from its coordinates. Match by **message and
count** instead: if the report shows exactly two `Invalid property: target` and
you have exactly two `target` blocks, you know which ones.

Filter the JVM noise before counting anything, or set `JDK_JAVA_OPTIONS` and be
rid of it — see `environment.md`.

## Convergence in practice

For reference, what a real session looked like — the count that matters is
*real problems*, after excluding JVM warnings:

| Pass | Real problems | What it revealed |
| --- | --- | --- |
| 1 | 57 | invented LOV syntax; regions missing columns and `componentAppearance` |
| 2 | 8 | column link missing `type: link` |
| 3 | 8 | `slot: body` on a modal page |
| 4 | 0 | only JVM noise left, still blocking |
| 5 | 0 | noise silenced; `build_root_unresolved` remains |

Each cause was found by comparing against a component that already validates, not
by interpreting the message.
