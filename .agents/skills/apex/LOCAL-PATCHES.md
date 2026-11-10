# Correctifs locaux du paquet `apexlang`

`apexlang/` est le paquet d'Oracle ([oracle/skills](https://github.com/oracle/skills),
`apex/apexlang`). Une mise à jour **remplace tout le répertoire** : les correctifs
ci-dessous disparaissent, il faut les réappliquer. Ce fichier vit hors de
`apexlang/` précisément pour survivre à ça.

Version en place : **oracle/skills `1b08cca`** (sortie APEXlang de septembre 2026,
dernier commit sur `apex/` : `f4a5065`). Métadonnées compilateur livrées en
**26.1.0+3102**, ré-estampillées localement en **26.2.0+3479** (correctif 7).

| Composant | Version | Source |
|---|---|---|
| SQLcl du PATH | 26.3.1 | `D:\Oracle\sqlcl` (l'ancien, 26.1, est gardé en `D:\Oracle\--sqlcl`) |
| Compilateur APEXLang (`apex validate`, `apex import`, audit) | 26.2.0+3479 | `lib/ext/apexlang-compiler.jar` du SQLcl |
| Instances APEX DEV et DEMO | 26.1.0 | `apex_release` |

Chaque correctif porte la mention `LOCAL PATCH (dbinventory, …)` :

```bash
grep -rn "LOCAL PATCH" .agents/skills/apex/apexlang/tools/     # attendu : 8 occurrences pour 6 correctifs
grep -c  "LOCAL PATCH" .agents/skills/apex/apexlang/assets/component-attributes.json   # attendu : 1 (correctif 7)
```

**Pourquoi pas la version d'octobre d'Oracle.** `oracle/skills` `03ee10d`
(2026-10-06) découpe le paquet en `apexlang/26.1/` et `apexlang/26.2/`. Mais
l'outillage (`apexctl.mjs`, l'audit, `component-attributes.json`) n'existe que
dans `26.1/apexlang-generation`, à l'octet près identique au nôtre. Le paquet
26.2, lui, ne contient que deux scripts shell, un inventaire et des exemples. Rien
n'y aurait réglé l'audit, et `validate.sh` aurait dû changer de chemin.

## Les correctifs

Tous portent sur l'audit hors ligne (`compiler-truth audit`), que
`validate.sh` lance après `apex validate`. Sans eux, l'audit échoue près de
700 fois sur une application que le compilateur accepte.

| # | Fichier | Fonction | Ce qu'il corrige |
|---|---|---|---|
| 1 | `tools/compiler-truth-audit.mjs` | `auditApxText` | Un bloc ```` ```sql ````/```` ```plsql ```` est une **valeur**, pas du source APEXLang : on le saute. Sinon `into :P91_X` devient une propriété `into`, et les parenthèses du SQL dépilent le composant. |
| 2 | `tools/compiler-truth-audit.mjs` | `validateProperty` + `COMPILER_METADATA_SNAPSHOT_GAPS` | `region.advanced.savedReportMappingIdentifier`, accepté par le compilateur mais absent des métadonnées, est admis. Le supprimer détacherait les rapports enregistrés. |
| 3 | `tools/query-valid-props-semantics.mjs` | `resolveAuditComponentRecord` | APEXLang aplatit le niveau `attributes` du compilateur. Les colonnes de rapport interactif, les séries et les axes sont donc cherchés aussi à travers lui. Une correspondance exacte (`type EQUALS`) l'emporte sur une correspondance par `FEATURES` (colonne de classic report : 7320 contre 7710). |
| 4 | `tools/query-valid-props-semantics.mjs` | `resolveAuditConditionValue` | Une condition qui désigne sa propriété par identifiant n'est jamais résolue par le **nom**. `type` existe au niveau région, `source`, `serverSideCondition`, graphique : le premier rencontré répondait à la place des autres. |
| 5 | `tools/query-valid-props-semantics.mjs` | `resolveAuditProperty` | Quand un groupe porte plusieurs propriétés du même nom (trois `serverSideCondition.value`, deux `formatMask`), on prend celle dont la condition tient, pas la première listée. |
| 6 | `tools/compiler-truth-audit.mjs` | `normalizePropertySemanticValue`, `isUntranslatedPluginValue` | Correspondance exacte avant la comparaison sans ponctuation, qui confondait `item=value` et `item!=value`. Une valeur de type greffon que la table d'alias ne sait pas traduire (`list`, `plainText` d'une colonne de rapport interactif) reste inconnue au lieu d'être jugée fausse. |

| 7 | `assets/component-attributes.json` | `compilerProvenance` | Oracle ne livre ce fichier que pour 26.1.0+3102. L'audit le déclare périmé (`COMPONENT_ATTRIBUTES_STALE`) dès que le compilateur change. Après comparaison des deux compilateurs (voir plus bas), seuls `buildID`, `metadataHash` et `verifiedAt` sont passés à 26.2.0+3479 ; le contenu est inchangé. |

Les correctifs 1 et 2 datent du 2026-07-31 (`fe46aa1`). Le correctif 7 date du
2026-11-10, passage de SQLcl à 26.3.1. Les correctifs 3 à 6
sont apparus avec la version de septembre 2026, qui contrôle beaucoup plus de
composants (19 au lieu de 9 : colonnes, séries, axes…) et vérifie désormais
qu'une propriété est **active** dans son contexte.

## Après une mise à jour : la procédure

1. Remplacer `apexlang/` par la nouvelle version. **Ne pas toucher** à ce
   fichier ni à `SKILL.md`, qui sont les nôtres.
2. Lancer l'audit **avant** de réappliquer quoi que ce soit, et noter le compte :
   ```bash
   cd .agents/skills/apex/apexlang
   node tools/apexctl.mjs apexlang compiler-truth audit \
      --app-path <app_dir> --verify-component-attributes
   ```
   Si Oracle a corrigé un problème, le correctif correspondant devient inutile :
   ne pas le réappliquer, et le retirer de ce tableau.
3. Réappliquer les autres, en gardant la mention `LOCAL PATCH`.
4. **Prouver que l'audit voit encore les vraies fautes.** Un audit vert peut
   aussi être un audit aveugle. Sur une copie de l'application, injecter :
   - une propriété inventée dans une colonne de classic report ;
   - une propriété inventée dans une série de graphique ;
   - une propriété inventée juste après un bloc ```` ```plsql ```` de process ;
   - `type: hidden` + `appearance { formatMask: 999 }` sur une colonne.

   Attendu : les deux premières en `PROP_UNKNOWN`, la troisième en
   `PROP_UNKNOWN process.source.…` (bien attribuée au process et non à la page),
   la quatrième en `PROP_INACTIVE`. C'est le jeu qui a validé la version actuelle.
5. `apex validate` reste la porte qui fait foi. L'audit hors ligne n'est qu'un
   diagnostic.

## Après une mise à jour de SQLcl : un nouveau compilateur

Le compilateur APEXLang vient avec SQLcl. Quand il change, l'audit échoue sur
`COMPILER_TRUTH_COMPONENT_ATTRIBUTES_STALE`, même si l'application est saine.

1. **Garder l'ancien SQLcl**, renommé, le temps de la comparaison.
2. Comparer les deux compilateurs :
   ```bash
   node .agents/skills/apex/compare-compiler-metadata.cjs \
      --old 'D:/Oracle/--sqlcl/lib/ext/apexlang-compiler.jar' \
      --new 'D:/Oracle/sqlcl/lib/ext/apexlang-compiler.jar'
   ```
   Le script répond à trois questions :
   - **Régressions du fichier sélectionné.** Une propriété ou une valeur dont il
     dépend a-t-elle disparu ? Si oui, il sort en 1 : ne pas ré-estampiller.
   - **Défauts modifiés.** Une propriété omise dans le `.apx` prend le défaut du
     compilateur. Pour chacun, vérifier que l'application la pose explicitement,
     ou que l'instance a gardé l'ancienne valeur après import (dictionnaire APEX).
   - **Ajouts.** Ce que le nouveau compilateur accepte, une instance APEX plus
     ancienne peut l'ignorer. Ne pas s'en servir tant que l'instance est en retard.
3. Sans régression, reporter `buildID` et `metadataHash` du nouveau compilateur
   dans `compilerProvenance`, avec la date. La note `LOCAL PATCH` reste.
4. `validate.sh`, puis le test d'injection des 4 fautes ci-dessus.

**Passage 26.1.0+3102 → 26.2.0+3479 (2026-11-10)** : 0 régression (341
propriétés, 204 valeurs), 10 défauts modifiés, 24 ajouts.
- Défauts modifiés touchant l'application :
  - `page.security.pageAccessProtection` passe de N à C, mais les 36 pages le posent explicitement ;
  - `pagination.type` des rapports passe de null à NEXT_PREVIOUS_LINKS, et 29 rapports ne le posent pas ;
  - `allowToExclude` des facettes passe de N à Y, et l'application ne le pose jamais ;
  - `cursorFocus` passe à NO_FIRST_ITEM, et la page de connexion ne le pose pas.

  Après réimport sur DEV, l'instance 26.1 a **gardé** les anciennes valeurs dans les quatre cas : pagination nulle, exclusion « No », focus sur le premier champ de la page de connexion. Rien n'a changé à l'écran.
- `mmdVersion` reste à `26.1.0+3102` dans `.apex/apexlang.json` de l'application.
  C'est la version des instances cibles. La voie `apexctl runtime` ne la compare
  qu'à la signature d'un build APEX interne d'Oracle ; avec le SQLcl du PATH, cette
  signature est nulle, et le contrôle ne s'applique pas.
- Ajouts à ne pas utiliser tant que les instances restent en APEX 26.1 :
  - pagination `showAll` ;
  - thème `ut-26.2` ;
  - `security.allowBotAccess` ;
  - les nouveaux fournisseurs d'IA générative.
