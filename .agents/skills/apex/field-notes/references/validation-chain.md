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

## `apex_root_missing` is a red herring

You may see this, all at once:

```
problem_count: 0
compiler_truth: pass  (APEXLANG_COMPILER_TRUTH_AUDIT_OK)
transcript:     "Validation successful."
validation_status: fail
import_eligibility: blocked
blocking_reasons: ["Live APEX validation did not pass or did not produce pass evidence."]
```

The report blames `apex_root_missing`: two capability probes disagree in one run,
the standalone `preflight` reporting `capability_state:
path_sqlcl_apex_validate_import` while the probe inside the roundtrip reports
`build_root_unresolved`.

**Do not chase the build root.** Two runs of the same source on the same machine:

| | fail | pass |
| --- | --- | --- |
| `execution_mode_used` | `path` | `path` |
| `resolved_apex_build_root` | `""` | `""` |
| `live_check_status` | fail | **pass** |

The build root is still empty on the passing run, and `--apex-root <SQLcl home>`
is not accepted anyway. So the missing root is not what blocks.

What changed between the two: the **target application had since been deployed and
contained the pages**. That is the observation. **The mechanism is not
established** — do not build a procedure on it. If you hit this, the useful move is
to check whether the target already holds the artefacts before spending time on
`--apex-root`.

Do not force the import past the gate whatever the cause. It exists to stop an
application being changed on incomplete evidence, and it earned its keep: it caught
six real errors that would otherwise have shipped.

## Validation does not mean the page works

The most expensive lesson of all, and the one that limits everything above.

A `fileUpload` item passed **five** validation passes — `problem_count: 0`,
compiler-truth audit green, APEX answering `Validation successful.` — and then
died on first render with
`WWV_FLOW_NATIVE_ITEM.NO_VALID_BLOB_SOURCE`. Its `settings` block was absent, so
it silently inherited a default storage type that is invalid without a source.

The chain checks that the `.apx` **compiles**. It does not exercise the page. An
omitted property whose default is wrong in context passes every gate.

Practical consequences:

- Treat a clean validation as *necessary, not sufficient*. The page still has to
  be opened.
- Be suspicious of properties you left out because you could not confirm their
  values. Absence is a decision, and its default may not be the one you want.
- A rendering error names its component (`component.name: P71_UPLOAD`) and an
  `apex_error_code`. Both are precise; take them to the deployed metadata rather
  than back to the validator, which already said yes.

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
