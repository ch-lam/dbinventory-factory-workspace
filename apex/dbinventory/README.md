# Workspace APEX `DBINVENTORY`

Un répertoire sous `apex/` = un workspace APEX. Celui-ci porte :

| | Quoi | Où |
|---|---|---|
| Schéma | `DBINVENTORY` (schéma principal du workspace) | [`database/dbinventory/`](../../database/dbinventory/) |
| Application | `DB-INV`, id 100 | [`applications/db-inv/`](applications/db-inv/) |

## Les trois niveaux, et où chacun vit

```
instance APEX (1 par PDB)   apexins, SMTP, ACL             setup/pdb_dbinventory/
  └ workspace               schémas assignés, comptes      apex/<workspace>/workspace/
      ├ schémas             V__ / T_ / X_                  database/<schéma>/
      └ applications        APEXLang                       apex/<workspace>/applications/<alias>/
```

Un workspace peut porter plusieurs schémas et plusieurs applications. Une
application dépend d'un schéma, jamais l'inverse.

## Installer, dans cet ordre

```bash
# 1. Instance APEX et schéma vide : setup/pdb_dbinventory/000_install_pdb_inventory.md

# 2. Le workspace (en SYS sur la PDB ; les mots de passe sont demandés)
sql sys@<pdb> as sysdba @apex/dbinventory/workspace/001_create_workspace.sql

# 3. Les objets du schéma
cd database/dbinventory
sql -S -name <conn> @X_000_reinstall_all.sql      # ou X_001 pour repartir de zéro
cd ../..
./fixtures/load_fixtures.sh <conn_demo>           # jeu de démonstration, si besoin

# 4. Chaque application : voir son DEPLOY.md
#    applications/db-inv/DEPLOY.md
```

Lancer les scripts `X_` **depuis `database/dbinventory/`** : leurs `@` sont
relatifs.

## Outillage commun — `bin/`

Les scripts prennent **le répertoire d'une application** en premier argument :

```bash
cd apex/dbinventory/bin
./validate.sh    ../applications/db-inv [conn]   # apex validate + audit hors ligne
./post_import.sh ../applications/db-inv [conn]   # T_001 de l'appli, après import
```

Les prérequis SQLcl (JDK 17+, terminal JLine `dumb`, stdin depuis un vrai
fichier) sont expliqués et gérés dans `bin/_sqlcl_env.sh`.

## Les règles qui gardent cette structure tenable

1. **Une application ne référence rien hors de son répertoire**, sauf
   `apex/<workspace>/bin/` et le skill sous `.agents/`. Elle connaît le schéma
   **par la base**, jamais par un chemin de fichier. C'est ce qui permettra d'en
   sortir une dans son propre dépôt le jour où elle aura son propre rythme :
   `git subtree split --prefix=apex/dbinventory/applications/<alias>`, puis
   raccrochage en submodule au même chemin.
2. **Le schéma s'installe par ses `V__`, jamais par les supporting objects d'une
   application.** Deux applications qui partagent un schéma ne peuvent pas
   chacune l'installer.
3. **Les tests suivent ce qu'ils testent.** Ce qui lit une application (son id,
   ses pages) vit dans `applications/<alias>/tests/` ; ce qui teste le schéma
   reste dans `database/<schéma>/` en `T_`.
4. **Une application est nommée par son alias**, pas par son id : l'id peut
   changer d'un environnement à l'autre, l'alias est porté par le source. Le
   skill APEXlang, lui, attend `applications/` **à la racine du dépôt** (un seul
   workspace) : il trouve nos applications, mais les dit « non standard » et
   demande confirmation du répertoire. C'est attendu ; lui passer le chemin.
5. **Contrat application → schéma** : `ref_app_release.version` porte la version
   du schéma installé. Le jour où une application évolue séparément de son
   schéma, elle déclare la version minimale qu'elle exige et `post_import.sh` la
   vérifie. Pas avant : tant qu'ils bougent dans le même commit, ce serait une
   vérification de plus sans rien à attraper.

## Ajouter une application au workspace

1. `apex/dbinventory/applications/<alias>/` avec la structure APEXLang standard ;
   `deployments/default.json` porte `workspace.name: DBINVENTORY` et l'id.
2. Un `DEPLOY.md` pour ce qui lui est propre, un `tests/` pour ses tests.
3. Une ligne dans le tableau en tête de ce fichier.
