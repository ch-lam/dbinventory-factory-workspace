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

## Transférer les données saisies (test → prod)

La collecte se recharge chaque nuit, mais ce qui est saisi dans l'application ne se recharge pas. Pour l'instant, cela concerne le registre applicatif. `export_ref_data.sh` et `import_ref_data.sh` font passer ces saisies d'une base à l'autre au moyen d'un fichier JSON. Le package `pkg_dbinv_transfer` (`V__015`) doit être installé dans les deux bases.

```bash
cd bin
./export_ref_data.sh -t test -o /tmp/apps.json             # toutes les applications actives
./export_ref_data.sh -t test -a DPI,PACS -o /tmp/apps.json  # ou une sélection de codes
./import_ref_data.sh -t prod /tmp/apps.json                # SIMULATION : rapport, rien d'écrit
./import_ref_data.sh -t prod --apply /tmp/apps.json        # import réel
rm /tmp/apps.json
```

Règles :
- une application est reconnue par son **code**, jamais par son nom ni par un identifiant technique ;
- les rattachements sont transmis par leurs **noms** (plateforme, serveur, instance, base). Si l'élément existe dans la cible, il est rattaché ; sinon il est ignoré et listé dans le rapport ;
- ce que porte le fichier est créé ou mis à jour, et **rien n'est retiré** de la cible. Seules les lignes actives sont exportées ;
- **tout ou rien** : si une application est en erreur, rien n'est écrit ;
- réimporter le même fichier ne change plus rien. Le journal de chaque application note l'import, sa provenance et sa date.

Le fichier contient des noms, des adresses et les documents eux-mêmes. Supprimez-le après l'import, et ne le versionnez jamais.
