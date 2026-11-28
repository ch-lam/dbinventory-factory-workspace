# Extraits réels de collecte CHL

Données **réelles** du parc CHL, conservées pour développer et vérifier sur de vraies valeurs, à côté du jeu fictif de `fixtures/`. Dépôt privé : ne pas les recopier ailleurs.

Ces archives ne contiennent **que des CSV de collecte** (`collect/*.csv`), jamais de script ni de mot de passe.

| Archive | Collecte | Contenu |
|---|---|---|
| `chl_collect_20261110.tgz` | 2026-11-10, serveur de collecte | 56 CSV Oracle, MSSQL et PostgreSQL, au format `collect_id` (`COLL_ID_20261110` en 1re colonne) |

Le périmètre de cette collecte, c'est-à-dire les trois `.lst` du serveur à la même date, est versionné en clair dans `../collect/CHL/`.

## Charger un extrait dans la base de développement

Le chargement commence par un `TRUNCATE` de tout le staging de la base visée.

```bash
cd setup/inventory/dbInventory
tar -xzf data/chl_collect_20261110.tgz      # écrit collect/*.csv, ignorés par git

cd bin
export DBINVENTORY_CONN_NAME=DEV_DBINVENTORY_dbinventory
export DBINVENTORY_ARCHIVE=0                # pas d'archive datée des CSV
./load_info_all.sh && ./compute_info_all.sh
```

L'archive ne contient pas de `.lst` : l'extraction ne touche aucun fichier versionné.
