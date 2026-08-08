---
name: apex-field-notes
description: Hard-won operational knowledge for Oracle APEX / APEXlang development — environment prerequisites, the validation chain, syntax traps the compiler rejects, and database setup. Read before writing or debugging any .apx artifact.
---

# APEX Field Notes

What the vendor documentation does not tell you, learned by hitting it.

This package is **not** a substitute for the APEXlang vendor skill. That one tells
you what the language offers; this one tells you what actually fails, why, and how
it was diagnosed. Everything here is backed by an observation, not a recollection.
Where something was never resolved, it says so.

## Why this exists

Producing two APEX pages took seven validation passes. Almost none of that time
went into writing them. It went into discovering four APEXlang constructs that are
rejected, an undeclared Python prerequisite, a JVM environment variable without
which 21 phantom problems appear, and a workspace name that must never be guessed.

None of it is written down anywhere else.

## Read this first, before anything else

Four rules that would have saved most of those seven passes.

1. **Copy a component that already validates. Do not interpret the error message.**
   The validator names the symptom, not the cause. `Invalid property: target`
   actually meant *the column is missing `type: link` two lines above*. Every trap
   in `references/apexlang-syntax.md` was solved by comparison with a working
   component; none by reading the message.

2. **Set `JDK_JAVA_OPTIONS` before running anything.** Without it you get 21
   problems that have nothing to do with your code. See `references/environment.md`.

3. **Never guess the APEX workspace name.** Read it from `apex_applications`.
   See `references/database-and-workspace.md`.

4. **A `fail` verdict does not mean your code is wrong.** Read `problem_count` and
   the transcript separately from the aggregate status. See
   `references/validation-chain.md`.

## Routing

| You are... | Read |
| --- | --- |
| Setting up a machine, or a command fails before touching your code | `references/environment.md` |
| Resolving the app, the workspace, or needing a grant | `references/database-and-workspace.md` |
| Running the validation chain, or reading a verdict | `references/validation-chain.md` |
| Writing or fixing `.apx` — regions, items, links, LOVs, modals | `references/apexlang-syntax.md` |
| Facing a specific error message | `references/troubleshooting.md` |

## Scope

APEX only, deliberately. Nothing here is specific to the project it was learned
in, so the directory can be copied whole into any repository doing APEX work. It
depends on no file outside itself; it refers to the vendor package by path only.

Observations were made against SQLcl 26.2, APEXlang compiler build 26.1.0+3102,
Oracle 23ai, on Windows. Version-sensitive facts are flagged in place.
