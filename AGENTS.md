# Repository contract

This repository is the APEX workspace `DBINVENTORY`: every application of the workspace,
and the schema `DBINVENTORY` they share. The factory itself (services, DEV and DEMO, the
connections, the tools) is described by the `factory` skill; this file only says how the
repository works.

## Layout
- `workspace.yml`: the applications, their aliases, sources and ids. The pipeline reads only
  this file to know what to deploy.
- `apex/dbinventory/applications/<alias>/`: one APEXlang application per folder. The folder name
  IS the application alias: SQLcl's `apex export` and `apex import` rely on it.
- `database/dbinventory/`: the schema as `V__` migrations, `R__` code and `T__` checks,
  applied by `migrate.sh` (see its README).

## Rules
- Work on a branch, never on `main`. A change reaches DEV through a merge request merged by a
  human, then the pipeline.
- On every branch, the pipeline validates every application declared in `workspace.yml` and runs
  `migrate.sh --dry-run` against DEV.
- Only `main` deploys to DEV: it applies `database/dbinventory/` first, then imports the
  applications.
- A schema change is a new `V__` file, or an edit of an `R__` file. Never edit a `V__` file that
  has already been applied.
- Try every change on DEMO first:
  - `database/dbinventory/migrate.sh <DEMO connection>`;
  - then `apex validate` and `apex import` of the changed application.
- One application per folder, declared in `workspace.yml` with a fixed id outside 3000-8999. Its
  row goes in the table of `README.md`.
- No secret in the repository: connections are saved in SQLcl, and the pipeline's credentials
  are GitLab variables.

## Ce dépôt
- L'application `DBINVENTORY` a l'id 110, en DEV comme en DEMO.
- Les `T__` de `database/dbinventory/` ne contiennent que des contrôles indépendants des
  données ; les contrôles qui ont besoin des fixtures sont dans `fixtures/checks/`.
- Les fixtures se chargent en DEMO seulement (`fixtures/load_fixtures.sh`), jamais en DEV.
- Les envois de fichiers (pages 71 et 85) exigent `EXECUTE ON SYS.DBMS_CRYPTO` pour le schéma.
- Après chaque import, lancer `apex/dbinventory/bin/post_import.sh` : `apex validate` ne
  prouve pas que l'import a gardé le bloc `storage` des items de téléversement.
