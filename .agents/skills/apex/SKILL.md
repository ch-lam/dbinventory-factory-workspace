---
name: apex
description: Oracle APEX skills for Oracle APEX application development.
---

# APEXLang Skills

This domain contains Oracle APEX skills for Oracle APEX application development.

## How to Use This Domain

1. Start with the routing table below.
2. Read only the specific file or category you need.

## Directory Structure

```text
apex/
├── apexlang/      ← vendor package, versioned; do not write here, an upgrade wipes it
└── field-notes/   ← ours: what the vendor docs do not say
```

## Category Routing


| Topic                                     | Directory          |
| ----------------------------------------- | ------------------ |
| Generate APEX applications using APEXlang | `apex/apexlang`    |
| Compilation traps, environment prerequisites, validation diagnosis | `apex/field-notes` |


## Key Starting Points

- `apex/field-notes/SKILL.md` — read this before writing or debugging any `.apx`
- `apex/apexlang/references/workflows/apex-generation.md`
- `apex/apexlang/references/domains/README.md`