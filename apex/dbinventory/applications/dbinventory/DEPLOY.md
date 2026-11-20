# Déployer l'application DBINVENTORY (id 110)

Ce qui est propre à cette application. L'ordre général — instance, workspace,
schéma, puis applications — est dans [`../../README.md`](../../README.md).

Trois étapes, dans cet ordre, et la troisième n'est pas optionnelle.

```bash
cd apex/dbinventory/bin

# 1. Le .apx compile-t-il ?
./validate.sh ../applications/dbinventory     # /nolog, comme le job validate du pipeline

# 2. Import en DEMO (le merger) ; DEV est importée par le pipeline de main.
#    Import — dans la MÊME session SQLcl authentifiée que la validation.
#    (voir .agents/skills/apex/apexlang/references/ops/runtime-gates/)
#    Session lancée à la main : JAVA_HOME doit pointer un JDK 17+, comme pour
#    validate.sh (qui le trouve seul). Sinon `apex import` échoue sur
#    UnsupportedClassVersionError. Voir bin/_sqlcl_env.sh (find_jdk).

# 3. Ce que la compilation ne prouve pas.
./post_import.sh ../applications/dbinventory DEMO_DBINVENTORY_dbinventory
```

## Ce que l'étape 3 rattrape

`apex validate` prouve qu'un fichier compile. Il n'ouvre jamais une page — la
page 71 a passé cinq validations vertes avant de mourir au premier rendu.
`post_import.sh` lance `tests/T_001_apex_page_smoke.sql`, qui inspecte ce qu'APEX
détient réellement après l'import : le SQL de chaque région est analysé contre le
schéma vivant, les listes de valeurs partagées sont vérifiées, et les attributs
de greffon des items sont relus.

Un passage propre est **nécessaire, pas suffisant**. Rien ici ne rend une page :
ni template, ni action dynamique, ni comportement client.

## Les items de téléversement : le bloc `storage`

Un `fileUpload` importé sans indication de stockage tombe sur `DB_COLUMN`, une
colonne BLOB dont l'item n'a aucune source. Les deux items de l'application
portent donc dans le `.apx` :

```
storage {
    type: appTempFiles
}
```

| Page | Item |
|---|---|
| 71 — Dérogation | `P71_UPLOAD` |
| 85 — Document d'application | `P85_UPLOAD` |

*Pour mémoire :* jusqu'au 2026-11-10, on croyait ce réglage impossible à écrire
dans le `.apx`, et on le refaisait dans le builder (*Settings > Storage Type =
Table APEX_APPLICATION_TEMP_FILES*) après chaque import. C'était faux : le bloc
est accepté et appliqué par les compilateurs 26.1.0+3102 (SQLcl 26.2.2) et
26.2.0+3479 (SQLcl 26.3.1). Le diagnostic s'était fié aux métadonnées du
compilateur, qui ne listent pas ce groupe, et seul un bloc `settings` avait été
essayé.

Les deux items ne se trompent pas de la même façon quand le bloc manque, et
c'est pourquoi `post_import.sh` le vérifie encore après chaque import :

- `P71_UPLOAD` est dans une région de type rapport. La page **meurt bruyamment**,
  sur `WWV_FLOW_NATIVE_ITEM.NO_VALID_BLOB_SOURCE`.
- `P85_UPLOAD` est dans une région `staticContent`. La page s'affiche **sans rien
  dire**, le fichier téléversé n'atterrit nulle part, et le processus
  d'enregistrement ne trouve rien dans `apex_application_temp_files`. Aucun test
  de navigateur ne voit ça.

**Un nouvel item de téléversement** doit porter le même bloc. `T_001` le
contrôle tout seul : il balaie tous les items dont le type d'affichage contient
« file ».

## Ordre vis-à-vis de la base

Le schéma d'abord (`database/dbinventory/migrate.sh <conn>`), l'application ensuite : `T_001` analyse le SQL des régions
contre le schéma vivant, et échouerait sur une colonne qui n'existe pas encore.
Voir [`../../README.md`](../../README.md).
