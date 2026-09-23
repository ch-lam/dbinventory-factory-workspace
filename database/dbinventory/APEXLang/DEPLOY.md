# Déployer l'application APEX

Trois étapes, dans cet ordre, et la troisième n'est pas optionnelle.

```bash
cd database/dbinventory/APEXLang

# 1. Le .apx compile-t-il ?
./validate.sh DEV_DBINVENTORY_dbinventory

# 2. Import — dans la MÊME session SQLcl authentifiée que la validation.
#    (voir .agents/skills/apex/apexlang/references/ops/runtime-gates/)

# 3. Ce que la compilation ne prouve pas.
./post_import.sh DEV_DBINVENTORY_dbinventory
```

## Ce que l'étape 3 rattrape

`apex validate` prouve qu'un fichier compile. Il n'ouvre jamais une page — la
page 71 a passé cinq validations vertes avant de mourir au premier rendu.
`post_import.sh` lance `T_001_apex_page_smoke.sql`, qui inspecte ce qu'APEX
détient réellement après l'import : le SQL de chaque région est analysé contre le
schéma vivant, les listes de valeurs partagées sont vérifiées, et les attributs
de greffon des items sont relus.

Un passage propre est **nécessaire, pas suffisant**. Rien ici ne rend une page :
ni template, ni action dynamique, ni comportement client.

## L'étape manuelle, et pourquoi elle le reste

APEXlang n'a pas de groupe de propriétés pour les attributs de greffon d'un item
de page. Le **Storage Type** d'un `fileUpload` n'est donc pas exprimable dans le
`.apx`, et **chaque import le remet à `DB_COLUMN`** — une colonne BLOB dont
l'item n'a aucune source.

Après chaque import, dans le builder :

| Page | Item | Réglage |
|---|---|---|
| 71 — Dérogation | `P71_UPLOAD` | Settings > Storage Type = **Table APEX_APPLICATION_TEMP_FILES** |
| 85 — Document d'application | `P85_UPLOAD` | idem |

Les deux items ne se trompent pas de la même façon, et c'est ce qui rend cette
liste nécessaire :

- `P71_UPLOAD` est dans une région de type rapport. La page **meurt bruyamment**,
  sur `WWV_FLOW_NATIVE_ITEM.NO_VALID_BLOB_SOURCE`. On ne peut pas l'oublier.
- `P85_UPLOAD` est dans une région `staticContent`. Les mêmes métadonnées s'y
  affichent **sans rien dire**. La page paraît juste, le fichier téléversé
  n'atterrit nulle part, et le processus d'enregistrement ne trouve rien dans
  `apex_application_temp_files`. Aucun test de navigateur ne voit ça.

C'est le cas silencieux qui justifie `post_import.sh` : l'étape reste manuelle,
mais l'oublier arrête désormais le déploiement au lieu de livrer un formulaire
qui perd les fichiers sans le dire.

**Si un troisième item de téléversement apparaît**, l'ajouter au tableau
ci-dessus. `T_001` le détectera tout seul — il balaie tous les items dont le type
d'affichage contient « file » — mais le message d'aide de `post_import.sh` cite
les deux connus, et un troisième non cité enverrait son lecteur chercher.

## Ordre vis-à-vis de la base

Le modèle d'abord, l'application ensuite : `T_001` analyse le SQL des régions
contre le schéma vivant, et échouerait sur une colonne qui n'existe pas encore.

```bash
sql -S -name <conn> @database/dbinventory/X_000_reinstall_all.sql   # ou X_001 pour repartir de zéro
./fixtures/load_fixtures.sh <conn_demo>                             # jeu de démonstration
```
