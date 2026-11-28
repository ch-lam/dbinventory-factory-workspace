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
- Schéma : les `V__` portent les tables et les données, les `R__` le code (packages, vues,
  triggers), un objet par fichier, dans l'ordre de `R__order.txt`. Corriger un package, c'est
  éditer son `R__`, jamais ajouter un `V__` qui le recopie.
- Les `T__` de `database/dbinventory/` ne contiennent que des contrôles indépendants des
  données (`T__000` objets invalides, `T__001` options payantes) ; les contrôles qui ont
  besoin des fixtures sont dans `fixtures/checks/`.
- **`X_000_reinstall_all.sql` et `X_001_cleanup_and_reinstall_all.sql` restent** : ils
  installent le schéma en une passe SQLcl dans un environnement temporaire (test, PDB
  jetable, poste du responsable), sans `migrate.sh`. Ils ne servent jamais sur DEV ou DEMO
  de la factory : `X_001` refuse un schéma qui porte `SCHEMA_MIGRATIONS`. Tout `V__`, `R__`
  ou `T__` ajouté va aussi dans `X_000`, dans l'ordre de `migrate.sh` ; `migrate.sh` (donc le
  pipeline, par `--dry-run`) échoue sinon. Ne pas les supprimer.
- Les fixtures se chargent en DEMO seulement (`fixtures/load_fixtures.sh`), jamais en DEV.
- Les envois de fichiers (pages 71 et 85) exigent `EXECUTE ON SYS.DBMS_CRYPTO` pour le schéma.
- Après chaque import, lancer `apex/dbinventory/bin/post_import.sh` : `apex validate` ne
  prouve pas que l'import a gardé le bloc `storage` des items de téléversement.

## Outillage portable Windows et Linux : ne pas le réduire à Linux

`database/dbinventory/migrate.sh`, `apex/dbinventory/bin/*.sh`, `fixtures/*.sh` et
`fixtures/sqlcl.sh` doivent tourner **sur l'hôte Linux de la factory et sous Git Bash
Windows** (poste du responsable : environnements temporaires, tests). C'est un choix du
responsable, pas un reste à nettoyer.

Ne pas retirer, même si Linux n'en a pas besoin :
- la conversion de chemins `to_win` / `cygpath -m` (sans cygpath, elle ne fait rien) ;
- `java.exe` et `C:/Program Files/Java` dans la recherche du JDK ;
- le stdin de SQLcl depuis un vrai fichier vide, jamais un pipe, un heredoc ou `/dev/null` ;
- `-Dorg.jline.terminal.provider=dumb` dans `JAVA_TOOL_OPTIONS`.

Sans eux, SQLcl sous Windows écrit `java.io.IOException` à la place du résultat et **rend
0** : un script qui n'a rien fait annonce un succès. `migrate.sh` compte en plus une
`IOException` comme un échec, et calcule ses sommes de contrôle sans les retours chariot,
pour qu'un checkout CRLF et un checkout LF donnent la même. Une évolution de l'outillage
se teste sur les deux. Réduire à un seul système demande une validation écrite du
responsable.

## Options et packs Oracle payants : interdits sans validation explicite

Aucune option ni aucun pack Oracle soumis à licence ne doit être utilisé, que ce soit dans
le schéma dbInventory, dans les scripts de collecte ou de supervision, ou dans un script
posé sur une base cible, **sans une validation claire et écrite du responsable des
licences**. Une suggestion, une habitude ou « c'est disponible sur la base » ne valent
pas validation.

Oracle ne refuse pas une option non licenciée : il l'exécute et **enregistre l'usage**
(`DBA_FEATURE_USAGE_STATISTICS`), que l'audit LMS lira. Une vue lisible ou une clause
acceptée n'est pas une licence. Le parc compte des Standard Edition 2, où aucune de ces
options n'est licenciable.

Exemples, liste non exhaustive :

| Option / pack | Ce qui la déclenche |
|---|---|
| Advanced Compression | `COMPRESS` / `DEDUPLICATE` sur un LOB SecureFile, `ROW STORE COMPRESS ADVANCED`, `COMPRESS ADVANCED` sur un index, compression RMAN LOW/MEDIUM/HIGH, Data Pump `COMPRESSION=ALL` ou `DATA_ONLY` |
| Diagnostics / Tuning Pack | `DBA_HIST_*`, `V$ACTIVE_SESSION_HISTORY`, `V$SQL_MONITOR`, rapports AWR/ASH/ADDM, SQL Tuning Advisor, profils SQL |
| Partitioning | `PARTITION BY RANGE/LIST/HASH` sur une table ou un index |
| Advanced Security | TDE (colonne ou tablespace), `ENCRYPT` sur un LOB, Data Redaction |
| Database In-Memory | `INMEMORY` |
| Autres options EE | Active Data Guard, RAC, Database Vault, Label Security, OLAP, Real Application Testing, Multitenant au-delà de 3 PDB |

Et en SE2, rien de ce qui est réservé à l'Enterprise Edition : compression de base,
`ALTER TABLE ... MOVE ONLINE`, parallélisme, index bitmap, etc.

**Conduite à tenir** : en cas de doute sur une clause, une vue ou un paramètre, s'arrêter
et demander avant de l'écrire. Pour une requête de collecte qui doit lire une vue
d'un pack, passer par `fct_has_diag_pack` (voir `setup/inventory/dbMonitoring/bin/check_oracle.sh`).

**Garde-fou** : `database/dbinventory/T__001_no_licensed_options.sql`, lancé par
`migrate.sh` et par `X_000`, échoue si le schéma utilise une de ces options. Une option validée se traduit par une
modification de ce test, jamais par son contournement.

Historique : en 2026-11, deux LOB de documents (`ref_exception_document`,
`ref_application_document`) avaient été créés en `securefile ( compress )` (Advanced
Compression). Les bases concernées ont dû être reconstruites pour effacer la trace
d'utilisation.
