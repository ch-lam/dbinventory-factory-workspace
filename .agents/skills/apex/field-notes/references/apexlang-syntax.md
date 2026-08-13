# APEXlang syntax

Confirmed vocabulary, and the constructs the compiler rejects. Every trap below
cost at least one validation pass.

## Method first — this matters more than any rule here

**Copy a component that already validates. Do not interpret the error message.**

The validator names the symptom, not the cause. `Invalid property: target` and
`Invalid property: linkText` both meant *the column is missing `type: link`* — a
property two lines above, which the message never mentions. Reading the message
harder would never have found it; diffing against a working column found it in
seconds.

Concretely, when something is rejected:

1. Find a component of the same family that already exists and validates.
2. Diff yours against it, attribute by attribute.
3. Only then consider what the message says.

Supporting tools, in order of authority:

```bash
node tools/query-valid-props.mjs --list                          # semantic names + type ids
node tools/query-valid-props.mjs --component pageItem --group identification
```

`templates/items/<family>/` in the vendor package holds sanctioned output
templates — `*.minimal.md` and `*.explicit-defaults.md` give the exact shape.
These outrank prose documentation.

**Where compiler truth stops:** `pageItem.type` has `lovType=PLUGINS`. The
compiler metadata does not enumerate item types — they come from the APEX
instance. Any item type not already used in your app must be confirmed against
`templates/items/` or the instance itself. Do not invent one.

## Component identifiers

Children of `page`:

| Id | Name |
| --- | --- |
| 5110 | `region` |
| 5120 | `pageItem` |
| 5130 | `button` |
| 5140 | `dynamicAction` |
| 5510 | `validation` |
| 5520 | `computation` |
| 5530 | `process` |
| 5540 | `branch` |

Region types seen in the vocabulary: `form`, `classicReport`, `interactiveReport`,
`staticContent`.

Item types confirmed in use: `selectList`, `displayOnly`, `hidden`, `checkbox`,
`textField`, `textarea`, `radioGroup`, `password`. Sanctioned templates also exist
for `datePicker` and `fileUpload`, among others.

## Traps

### Lists of values have no `staticValues`

There is no static-values construct. Every LOV is a query.

```apexlang
lov my-lov (
    name: MY_LOV
    source {
        type: sqlQuery
        sqlQuery:
            ```sql
            select 'Label' d, 'VALUE' r, 1 o from dual
            union all select 'Other', 'OTHER', 2 from dual
             order by 3
            ```
    }
    columnMapping {
        return: R
        display: D
    }
)
```

Symptom when wrong: `Invalid property: staticValues` plus
`Invalid LOV required parameter: source - type (string)`.

**Put LOVs in shared components, never at page level.** Page-level list-of-values
definitions have caused `ORA-20987` at runtime.

### A column carrying a link needs `type: link`

Without it, the entire `link` block is rejected — `target` and `linkText` are both
reported as invalid properties, with no mention of the actual cause.

```apexlang
column MY_ID (
    reportColumnQueryId: 1
    derivedColumn: N
    type: link
    heading { heading: Id }
    layout { sequence: 10 }
    link {
        target: {
            page: 71
            items: {
                P71_EXCEPTION_ID: #MY_ID#
            }
            clearCache: 71
        }
        linkText: #MY_ID#
    }
)
```

Note the item syntax: `items: { P71_X: #COLUMN# }`. Not `itemNames`/`itemValues`,
and `#COLUMN#` not `&COLUMN.`.

### Buttons redirect with `redirectThisApp`

`redirectToPage` is not valid.

```apexlang
behavior {
    action: redirectThisApp
    target: {
        page: 71
        clearCache: 71
    }
    warnOnUnsavedChanges: doNotCheck
}
```

### `classicReport` regions need columns and `componentAppearance`

Two separate requirements, both mandatory:

- at least one `column` child — `Minimum number of children of type "column" not
  reached. Minimum 1, found 0.`
- a `componentAppearance { template: ... }` block — `Missing required parameter
  (411): componentAppearance - template (string)`

### Modal pages have no `body` slot

Regions on a modal live in `contentBody`.

```apexlang
appearance {
    pageMode: modalDialog
    dialogTemplate: @/modal-dialog
}
...
region my-region (
    layout {
        sequence: 10
        slot: contentBody      // NOT body
    }
)
```

Symptom: `Invalid Slot value: layout - slot (STRING) : body`. It is reported as a
**warning**, so it only blocks when `warnings_as_errors` is on — otherwise the
region silently lands in the wrong place.

### `reportColumnQueryId` is positional

Columns are addressed by their position in the region's `select`. Adding a column
in the middle renumbers every column after it, silently rebinding headings to the
wrong data.

**Append new columns at the end of the `select`.** Then the new ones get the next
free ids and nothing existing moves.

### `fileUpload` is a page item type — do not confuse the scopes

```apexlang
pageItem P71_UPLOAD (
    type: fileUpload
    label { label: Attach a file }
    layout { sequence: 20  region: @documents  slot: regionBody }
    appearance { template: @/optional-floating }
)
```

`canonicalDslType: fileUpload`, `nativeType: NATIVE_FILE`. Default storage is the
APEX temporary files table, which a process then reads.

**The confusion to avoid:** `component-policies.json` rule `REGION_RULE_014` says
BLOB columns are only allowed in approved region types with `fileUpload` as a
render role, in a `form` region, requiring primary keys. Its scope is
`region.column.blob` — **BLOB columns inside a region**, a different thing from a
page item. Reading that rule as applying to page items leads to the wrong
conclusion that uploads must go through a form region bound to the table. They do
not.

**Its storage type cannot be set from the `.apx`, and that is a hard trap.**

Left unset, the item inherits `storage_type = DB_COLUMN` — a BLOB column it has no
source for — and the page dies at render with
`WWV_FLOW_NATIVE_ITEM.NO_VALID_BLOB_SOURCE`.

And it cannot be set: APEXlang (compiler build 26.1.0+3102) exposes **no property
group for plugin attributes on a `pageItem`**. The groups are `advanced`,
`appearance`, `comments`, `config`, `default`, `help`, `identification`, `label`,
`layout`, `lov`, `security`, `source`, `validation` — no `settings`. Emitting one
is rejected with `Invalid property: storageType`.

`templates/items/file-upload/file-upload._common.md` documents a `settings` block
with `storageType`, `allowMultipleFiles` and more. **That template is stale against
this compiler build.** Do not trust it; the skill's own contract says compiler
truth outranks templates and a conflicting template is defective.

Consequence to plan for: **every import resets the item, and the storage type must
be set again by hand in the builder** (`Storage Type` → `Table
APEX_APPLICATION_TEMP_FILES`). Record it next to the item in the `.apx` as a
comment so the next person knows why.

Internal values are `DB_COLUMN` and `APEX_APPLICATION_TEMP_FILES`.

### Reading the real attribute values from a deployed app

When a plugin-sourced value cannot be resolved offline, the deployed application
is the authority. The whole attribute payload sits in one JSON column:

```sql
select attributes
  from apex_application_page_items
 where application_id = :app and page_id = :page and item_name = :item;
```

which returns, for a file upload item:

```json
{"storage_type":"DB_COLUMN","display_download_link":"Y","content_disposition":"attachment",
 "display_as":"INLINE","allow_copy_paste":"N"}
```

That is the fastest route to a value the metadata will not give you: build the
component once in the builder, read `attributes`, then write it back into the
`.apx`.

## Writing data: the modal + package pattern

APEX automatic row processing is not the only option, and often not the right one.
The pattern that works well:

- a modal page (`pageMode: modalDialog`)
- buttons
- `process` of `type: executeCode` whose PL/SQL calls a package procedure
- `serverSideCondition { whenButtonPressed: @button }` to bind process to button

```apexlang
process approve-record (
    name: Approve Record
    type: executeCode
    source {
        plsqlCode:
            ```plsql
            pkg_my_api.approve( :P71_ID, :P71_NOTE );
            ```
    }
    execution { sequence: 40 }
    serverSideCondition { whenButtonPressed: @approve }
)
```

Why it is worth preferring: business rules and any audit journalling live in one
place instead of being spread over page processes, and the same guarantees apply
to callers that are not the screen.

A caveat found the hard way: **conditional button visibility by status was not
attempted** — no validated example existed to copy. Letting the API refuse an
invalid transition with an explicit error is a safe interim, if a poorer
experience.
