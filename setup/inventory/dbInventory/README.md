# dbInventory — scripts de collecte, de chargement et de calcul

Ce dossier est déployé tel quel sur le serveur de collecte, sous `/inventory/dbInventory/`.

```
dbInventory/
├── .env            secrets et réglages, NON versionné (modèle : .env.example)
├── bin/            scripts
├── collect/        .lst du périmètre, CSV de la dernière collecte, archives datées
└── data/           extraits réels de collecte conservés (voir data/README.md)
```

## Configuration : le `.env`

Aucun mot de passe n'est écrit dans les scripts. Ils sont lus dans `../.env` par
`bin/_dbinventory_env.sh` :

```bash
cp .env.example .env && chmod 600 .env    # puis renseigner les valeurs
```

Le `.gitignore` exclut tout `.env` : un script poussé depuis le serveur n'emporte
plus de secret avec lui.

| Variable | Rôle |
|---|---|
| `DBINVENTORY_{PROD,TEST}_{PASS,DSN}` | base dbInventory des loaders, du calcul et de `gen_collect_lists.sh` |
| `MONITORING_{ORACLE,MSSQL,POSTGRES}_PASS` | compte `monitoring` sur les cibles collectées |
| `DBINV_GEN_COLLECT_LISTS` | `1` : `get_info_all.sh` régénère les `.lst` depuis la base ; `0` (défaut) : `.lst` tenus à la main |

Variables d'exécution, hors `.env` :

- `DBINVENTORY_TARGET` (`prod` par défaut, ou `test`) choisit la base ;
- `DBINVENTORY_CONN_NAME` passe par une connexion SQLcl nommée à la place du `.env`. C'est la voie du poste de développement et de `fixtures/load_fixtures.sh` ;
- `DBINVENTORY_ARCHIVE=0` saute l'archive datée des CSV après chargement.

## Les deux entrées de la crontab

| Script | Fait |
|---|---|
| `bin/dbInventory_all.sh` | collecte, puis chargement, puis calcul, en **production** |
| `bin/dbInventory_load_test.sh` | recharge la même collecte dans la base de **test** et y recalcule les scores ; à planifier après le précédent |

Les deux sourcent `bin/_cron_env.sh`, qui apporte `ORACLE_HOME`, SQLcl et `sqlcmd`, car cron ne lit pas le `.profile`.

La règle d'arrêt est la même dans les deux :
- une collecte incomplète n'arrête pas la chaîne ;
- un chargement en échec, y compris des lignes rejetées, annule le calcul, et les scores de la veille restent en place.

Pour un lancement manuel d'une seule étape en test, il existe `load_info_{oracle,mssql,postgres}_test.sh` et `compute_info_all_test.sh`. Ce sont les scripts de production avec `DBINVENTORY_TARGET=test`.
