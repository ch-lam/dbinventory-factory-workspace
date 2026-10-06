# Correctifs locaux du paquet `apexlang`

`apexlang/` est le paquet d'Oracle ([oracle/skills](https://github.com/oracle/skills),
`apex/apexlang`). Une mise à jour **remplace tout le répertoire** : les correctifs
ci-dessous disparaissent, il faut les réappliquer. Ce fichier vit hors de
`apexlang/` précisément pour survivre à ça.

Version en place : **oracle/skills `1b08cca`** (sortie APEXlang de septembre 2026,
dernier commit sur `apex/` : `f4a5065`), métadonnées compilateur **26.1.0+3102**.

Chaque correctif porte la mention `LOCAL PATCH (dbinventory, …)` dans le code :

```bash
grep -rn "LOCAL PATCH" .agents/skills/apex/apexlang/tools/     # attendu : 8 occurrences pour 6 correctifs
```

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

Les correctifs 1 et 2 datent du 2026-07-31 (`fe46aa1`). Les correctifs 3 à 6
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
