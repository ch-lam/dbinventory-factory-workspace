# Jeu de données de démonstration et de non-régression

Un parc fictif complet — le **Groupe Hospitalier Meridian**, `ghm.lan` — produit sous
forme de CSV de collecte, chargé par la chaîne de production sans la contourner.

Il sert trois usages qui n'en font qu'un :

1. **Démontrer l'application** sans exposer le parc du CHL.
2. **Vérifier que la collecte reste alignée sur les structures.** Le chargement SQLcl est
   positionnel et sans en-tête : une colonne déplacée ne produit aucune erreur, elle décale
   tout ce qui suit. C'est arrivé, et personne ne l'a vu pendant des mois.
3. **Servir d'oracle de non-régression** quand une règle de conformité change.

---

## Utilisation

```bash
# Génération seule (aucune base requise)
node fixtures/generate.mjs

# Génération + chargement + ETL, sur la base de démonstration
./fixtures/load_fixtures.sh DEMO_DBINVENTORY_dbinventory

# Comparaison au fichier de référence
./fixtures/check_baseline.sh DEMO_DBINVENTORY_dbinventory

# Après un changement de règle VOULU : on recapture, puis on relit le diff git
./fixtures/check_baseline.sh DEMO_DBINVENTORY_dbinventory --capture

# La promotion depuis la discovery — s'annule, ne déplace aucune mesure
sql -S -name DEMO_DBINVENTORY_dbinventory @database/dbinventory/T_004_discovery_promotion.sql

# La chaîne elle-même : les .lst régénérés DEPUIS LA BASE
DBINVENTORY_CONN_NAME=DEMO_DBINVENTORY_dbinventory \
  ./setup/inventory/dbInventory/bin/gen_collect_lists.sh /tmp/gen
```

`load_fixtures.sh` refuse de tourner ailleurs que sur une base de démonstration, et il le
vérifie deux fois : sur le nom de la connexion, puis sur `v_environment_identity` lue dans
la base elle-même. Le premier contrôle est déclaratif, le second ne l'est pas. Le
chargement commence par `TRUNCATE` sur tout le staging, et la donnée du dev n'est pas
rejouable depuis cette machine.

---

## Organisation

| Fichier | Rôle |
|---|---|
| `world.json` | Le parc : graine, dates figées, effectifs, **matrice de défauts** |
| `generate.mjs` | Point d'entrée : produit 56 CSV + 3 `.lst` |
| `lib/contract.mjs` | **L'ordre des colonnes, table par table** — la pièce maîtresse |
| `lib/csv.mjs` | Écriture CSV : quoting, longueurs, refus de ce qui ne charge pas |
| `lib/rng.mjs` | Tirage à graine (mulberry32), pour la reproductibilité |
| `lib/estate.mjs` | Construction du parc : hôtes, instances, bases |
| `lib/emit_*.mjs` | Un émetteur par moteur |
| `sqlcl.sh` | Appel de SQLcl jouable depuis Git Bash — voir ci-dessous |
| `expected/baseline.csv` | Les chiffres attendus, **capturés et non prédits** |

### Pourquoi `sqlcl.sh` existe

Sur un poste Windows, SQLcl lancé sans TTY répond
`java.io.IOException: Fonction incorrecte` **à la place du résultat de la requête**, et
rend 0 — le garde-fou d'identité lisait donc ce message comme un nom de service. Il faut
lui donner stdin depuis un vrai fichier et `-Dorg.jline.terminal.provider=dumb`, et lui
passer des chemins Windows : `/g/...` est lu comme `C:\g\...`. Ce sont exactement les
prérequis de `apex/dbinventory/bin/_sqlcl_env.sh`, d'où le helper commun plutôt qu'une troisième copie.
Sur le serveur de production, ces réglages sont sans effet.

Le générateur n'a **aucune dépendance npm**, comme le test navigateur de l'application (`apex/dbinventory/applications/dbinventory/tests/apex_page_test.mjs`).

---

## Le contrat de chargement

`LOAD <table> ../collect/<table>.csv` : **le nom du fichier est le nom de la table**, sans
exception. Aucun en-tête, chargement positionnel, `TRUNCATE` avant chaque chargement.

| Loader | COLUMN_NAMES | Séparateur | Enclosures | TIMESTAMP_FORMAT |
|---|---|---|---|---|
| `load_info_oracle.sh` | OFF | `,` | `"` | `YYYY-MM-DD HH24:MI:SS` |
| `load_info_mssql.sh` | OFF | `,` | *aucune déclarée* | non défini |
| `load_info_postgres.sh` | OFF | `,` | `"` | non défini |

Les deux configurations d'enclosure se comportent pareil à l'usage : les valeurs se
chargent sans guillemets résiduels dans les deux cas. Le générateur émet donc la même
forme que les collecteurs réels — **toute valeur non vide entre guillemets, y compris les
nombres, et une valeur vide écrite sans rien** (`,,`, jamais `""`).

`contract.mjs` a été **dérivé du DDL de la base et d'une collecte réelle archivée**, pas
écrit à la main. Les nombres de champs viennent des 56 fichiers d'un vrai run ; cinq
fichiers étant vides en production, leur contrat est déduit des scripts de collecte et
marqué `source: "déduit des scripts"`.

---

## Les pièges qui font échouer une génération naïve

**Les colonnes à DEFAULT en fin de table ne sont pas dans le CSV**, et leur nombre varie :
0 pour `mssql_hosts` et `oracle_databases`, 1 pour `oracle_size_usage` (`date_value`), 2 pour
la plupart des tables de sécurité (`compliance_score`, `date_value`), 3 pour
`oracle_security_tablespace`. Un champ de trop met un nom d'hôte dans `date_value` et la ligne est
rejetée. `csv.mjs` refuse d'écrire un champ hors contrat.

**Oracle n'émet que les déviations.** `oracle_sec_high_sys_privs` est vide sur une base
saine. Les verdicts conformes sont produits par anti-jointure contre deux **témoins** de
collecte réussie : `oracle_security_parameter` par instance, `oracle_security_profile` par
base. Une base absente de son témoin ne produit **aucun** constat — voulu : une collecte
ratée ne doit pas être notée conforme. MSSQL fait l'inverse et émet des lignes sentinelles
(`NoOrphanedUser`, `nogroup`, `no_permission`).

**`pdb_name` n'a pas la même valeur selon la table.** Les tables de sécurité portent
`NON CONTAINER` pour une base non-CDB, que l'ETL retraduit en `db_name` ; `oracle_size_usage`
et les métriques portent le nom que `dim_database` utilisera. D'où les deux champs de
`dbEntities` dans `estate.mjs` : `pdbName` pour la sécurité, `dimName` pour le reste.

**Côté MSSQL, `collect_target` et `hostname` sont deux chaînes différentes** dont l'ETL
dépend : `dim_host.hostname` vient du FQDN (`collect_target`), `dim_instance.instance_name`
vient de `@@SERVERNAME` (`hostname`), de forme `MACHINE/INSTANCE`. Le collecteur réécrit
tous les antislashs en slash.

**`collect_id` vaut exactement `COLL_ID_YYYYMMDD`** — 16 caractères, la largeur de la
colonne.

---

## Le déterminisme, et pourquoi les dates sont figées

Une graine donnée produit toujours les mêmes octets. Sans cela, le fichier de référence ne
voudrait rien dire.

Les dates de `world.json` sont **figées et non calculées depuis aujourd'hui**, et
`load_fixtures.sh` passe `snapshotDate` explicitement à l'ETL. Avec le défaut
`trunc(sysdate)`, la fraîcheur des sauvegardes, les fins de support et `data_age_days`
dériveraient d'un jour à l'autre : le fichier de référence serait faux le lendemain de sa
capture.

Réserve connue : `v_discovery_status.days_since_last_seen` et `is_stale` utilisent
`sysdate` sans paramètre. La référence ne porte donc pas l'ancienneté de la discovery.

Chaque moteur a **son propre flux aléatoire** dérivé de la graine. Avec un flux unique,
ajouter une ligne dans l'émetteur Oracle décalait tous les tirages MSSQL en aval et
réécrivait la totalité des fichiers : le diff devenait illisible.

Le même principe vaut pour ce qui arrive après coup. La discovery (`seed + 404`), l'usage des options Oracle (`+ 505`) et le suivi des clients non chiffrés (`+ 606`) ont chacun leur flux. Un sujet ajouté ne décale ainsi aucun tirage des fichiers existants.

Le suivi des clients non chiffrés (`oracle_sec_net_enc_audit`) n'est pas piloté par la matrice de défauts. Il pose quatre cas fixes sur quatre bases dont la session est chiffrée :
- des clients récents ;
- un client récent et un client de plus de 30 jours ;
- des clients anciens seulement ;
- une table vide.

Ces quatre cas exercent les deux polarités des deux règles ainsi que la fenêtre de 30 jours. T_003 (assertions 32 et 33) le vérifie.

---

## La matrice de défauts

`world.json` déclare, **règle par règle**, la part de la population évaluée qui doit être en
écart. Une valeur strictement entre 0 et 1 garantit les deux polarités, et `markShare`
marque un nombre **exact** d'éléments plutôt qu'un tirage indépendant : un test qui compare
des comptes ne tolère pas « à peu près 30 % ».

67 des 69 règles actives y figurent. Les deux autres, `MSSQL_ENGINE_SUPPORTED` et
`MSSQL_ENGINE_PATCH_CURRENT`, sont pilotées par le mélange de versions, calé sur les dates
de `product_support` pour produire les trois états : sous support, sous support étendu
(`is_norm_exception = 1`) et hors support.

---

## Le fichier de référence : capturé, pas prédit

Le générateur **ne recalcule pas** les verdicts. Ce serait réimplémenter
`pkg_dbinv_scoring`, et un test qui réimplémente son sujet ne prouve que sa propre
cohérence.

```
charger  ->  ETL  ->  check_baseline.sh --capture  ->  expected/baseline.csv
```

`T_003_fixture_expectations.sql` produit l'empreinte chiffrée (cardinalités, constats par
règle et par verdict, conformité, scoring, volumétrie du staging) et joue en plus des
**assertions structurelles** qui, elles, échouent bruyamment : poids sommant à 100, tout
`rule_code` émis présent au catalogue, aucun constat sans entité, scores dans leurs bornes,
aucune règle muette, et surtout **chaque règle active couvrant les deux polarités**.

Cette dernière est celle qui a le plus de valeur. Une règle qui ne rend qu'un seul verdict
passe tous les autres contrôles sans avoir jamais été mise à l'épreuve — c'était le cas de
la saturation de stockage, verte sur 1034 constats parce qu'elle ne pouvait pas rougir.

**Le jeu vieillit.** Les états de revue (applications et documents) sont posés
relativement au jour du chargement, et les vues les évaluent contre `sysdate`. Le
document « due soon » passe en retard 20 jours après le chargement, et l'état « Due within
30 days » disparaît de la démo. Passé ce délai, un état daté manquant ne fait plus
échouer T_003 : il sort en `ATTENTION:`, et `check_baseline.sh` reste vert en le
signalant. **Pour lever l'avertissement, on recharge la démo.** Avant 20 jours, le même
manque reste un échec, puisque c'est alors le générateur qui est en cause. Ces états ne
figurent pas dans la référence chiffrée.

**Le bouton « Recompute Scoring » de la page 70 a le même effet, en plus net.** Il
rejoue l'ETL et le scoring à la date du jour, donc il crée un snapshot daté d'aujourd'hui
à côté de celui du jeu. Les dérogations saisies pendant une démo s'appliquent alors. En
revanche, l'assertion 11 de T_003 (discovery datée du snapshot) et la référence échouent
jusqu'au prochain rechargement. Sur DEMO, le bouton demande une confirmation qui le dit.

---

## La discovery, et pourquoi elle est ici

La discovery n'est pas de la collecte : elle répond à « qu'est-ce qui tourne
réellement ? », quand la collecte répond à « comment va ce qu'on gère ? ». Le jeu
la couvre depuis le 2026-09-06, et pas par souci d'exhaustivité — sans elle, la
chaîne `discovery → promotion → *_collect_list → .lst` n'était **vérifiable
nulle part**. Le périmètre de production du CHL est tenu à la main, il n'existe
pas de lab assez large pour l'exercer, et `gen_collect_lists.sh` n'avait jamais
tourné.

Le bloc `discovery` de `world.json` déclare trois populations, et il en faut
trois pour que `v_discovery_status` rende ses quatre statuts :

| population | comment | statut obtenu |
|---|---|---|
| le parc redécouvert | tout ce qui n'est pas dans `withheldHostIndexes` | `COLLECTED` |
| le parc omis | les indices d'hôtes listés là | `NOT_SEEN` |
| les installations sauvages | `wild`, hors périmètre | `NEW` |
| les sauvages tranchées | `ignored`, via `set_triage` | `IGNORED` |

Les hôtes omis sont désignés **par indice et non tirés** : ce choix porte une
intention, et il doit rester relisible dans le diff. Les indices retenus sont
ceux d'hôtes ne portant qu'une entité, et aucun ne porte l'entrée commentée du
`.lst` — qu'une omission rendrait invisible au lieu de la montrer `IGNORED`.

Deux entrées existent uniquement pour des branches qui, sinon, ne seraient
jamais atteintes. Un hôte Linux portant **deux moteurs** : le parc de démo sépare
les hôtes Oracle des hôtes PostgreSQL, donc le repliement du fichier — une ligne
par machine, couvrant trois moteurs — ne serait jamais exercé. Et des hôtes
**MySQL**, qui n'ont aucune table de périmètre et dont la promotion doit refuser
proprement : c'est le genre de branche qu'on n'écrit jamais faute de données pour
la déclencher.

### Deux formats, une seule machinerie

Les deux fichiers produits ne sont pas des CSV de collecte :

| fichier | séparateur | guillemets | en-tête | chargement |
|---|---|---|---|---|
| `discovery_mssql.csv` | `,` | oui | **oui** | **par nom** |
| `discovery_linux.csv` | `;` | non | non | **positionnel** |

Ils passent quand même par `writeCsv` et par le contrat. Les écrire à côté aurait
été plus court, et aurait retiré au chargement positionnel la seule protection
qu'il a. Le contrat refuse donc, dans un fichier sans guillemets, un champ vide
(le producteur écrit `-`) et une valeur contenant le séparateur — c'est
exactement pourquoi le fichier Linux sépare en `;` : `ora_sids` y liste des SID
séparés par des virgules.

Le **nom de fichier diffère du nom de table** (`discovery_mssql.csv` pour
`discovery_mssql_inst`), parce que c'est `load_info_discovery.sh` qui le décide.
C'est un contrat de production, pas à un jeu de test de le plier.

### Ce que la référence mesure, et ce qu'elle ne mesurera jamais

`effective_status` entre dans l'empreinte : il ne dépend que de `triage_status`
et du périmètre. `days_since_last_seen` et `is_stale` n'y entrent pas, ni aucune
mesure qui en dérive — ils descendent de `sysdate` nu, et vaudraient autre chose
le lendemain de la capture. La date de run, elle, est mesurée **en clair** :
`pkg_dbinv_discovery.load_all` a pour défaut `trunc(sysdate)`, et sans cette
mesure une chaîne qui daterait le run d'aujourd'hui passerait inaperçue.

### Le périmètre fait partie du jeu

`load_fixtures.sh` amorce les trois `*_collect_list` depuis les `.lst` générés,
par `bootstrap_collect_lists.sh`. Ce n'est pas une commodité : ces tables sont
**vides sur une base neuve** — aucune migration ne les alimente, c'est la
discovery qui les remplit une fois qu'un humain a tranché. Sans elles,
`NOT_SEEN` est structurellement vide et la moitié de ce que ce jeu démontre
n'existe pas.

À ne pas coder en dur : trois paires d'instances MSSQL partagent hôte et port
1433, donc **une seule ligne de périmètre pour deux instances**. Le modèle ne
sait pas les distinguer — le parc réel en compte onze cas — et c'est la ligne
`perimetre|mssql/1` de la référence qui fait foi, pas le compte d'instances.

## Ce que ce jeu de données ne couvre pas

- **MySQL** : la page 50 reste vide. Elle ne contient aucune requête SQL, et il n'existe ni
  table de staging ni contrôle pour ce moteur. C'est l'état réel du produit, et l'entrée de
  menu est un jalon assumé.
- **Le second millésime de collecte** (l'historique des faits, donc `collect_id` généralisé
  au modèle) : toujours à faire. Le jeu ne porte qu'un seul instantané.
- **Le vieillissement de la discovery** : `days_since_last_seen` et `is_stale` descendent de
  `sysdate` nu, donc aucune mesure de la référence n'en dérive. Les rendre mesurables
  supposerait de les faire descendre du dernier `disc_run` plutôt que de l'horloge — ce qui
  serait d'ailleurs plus juste : « pas revu au dernier run » veut dire quelque chose, « pas
  revu depuis 30 jours » beaucoup moins quand la discovery tourne une fois par semaine.

La **discovery** ne figure plus dans cette liste : elle a été livrée le 2026-09-06, avec la
promotion vers les trois périmètres. MongoDB non plus : il est **sorti du périmètre** le
2026-09-05, page et entrée de menu supprimées. Et la conformité PostgreSQL n'y figure plus non plus — elle a été
livrée depuis : PostgreSQL est jugé sur les quatre domaines de score, et les CSV de ce jeu de
données produisent bien des constats.
