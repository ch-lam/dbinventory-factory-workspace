# Consignes pour les agents — dbInventory

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

**Garde-fou** : `database/dbinventory/T_006_no_licensed_options.sql`, lancé par `X_000`,
échoue si le schéma utilise une de ces options. Une option validée se traduit par une
modification de ce test, jamais par son contournement.

Historique : en 2026-11, deux LOB de documents (`ref_exception_document`,
`ref_application_document`) avaient été créés en `securefile ( compress )` (Advanced
Compression). Les bases concernées ont dû être reconstruites pour effacer la trace
d'utilisation.
