# The convert-apply REMAINDER contract -- schema `apply/1`

**Status: PROPOSED.** The `kind` vocabulary below is a compatibility surface, and
it is not frozen until the converter side agrees it. Adding a kind is additive
and stays `apply/1`; RENAMING one is breaking and needs `apply/2`.

*Engine side, 2026-09-04 (session 68). Implements
`INBOX-URGENT-conversion-remainder-must-be-machine-readable.md`.*

## What this is for

A conversion is only trustworthy if you can tell what it did **not** do. Before
this, that information existed but was unusable:

* Two of the six report surfaces -- `CreatorSites` and `ReemitNotes` -- were
  computed and then **silently discarded** by both copies of the print block.
  The engine wrote *"verify the creator manually"* into a void.
* What did print was prose. Dispatching on it meant matching English.

`--format json` now emits every surface, plus a typed `items[]`.

## The document

```
drag-lint convert-apply --unit F.pas --rules R --db D --format json
```

```jsonc
{
  "schema": "apply/1",
  "mode": "dry-run",          // or "apply"
  "unit": "...", "dfm": "...", "rules_file": "...",
  "ok": true,
  "error": "",
  "rule_errors": [ { "line": 6, "message": "..." } ],
  "edits_count": 8,
  "freshness": { "fresh": true, "reasons": [] },

  "converted":     [ "Edit1: TOldEdit -> TNewEdit" ],
  "access_sites":  [ ... ],
  "creator_sites": [ ... ],
  "todos":         [ ... ],
  "reemit_notes":  [ ... ],
  "warnings":      [ ... ],

  "items": [
    { "kind": "creator-verify", "field": "todos",
      "instance": "Edit1", "from_type": "TOldEdit", "to_type": "TNewEdit",
      "file": "MyForm.pas", "path": "", "text": "{ TODO: ... }",
      "line": 24, "rule_line": 0 }
  ]
}
```

`--json` is accepted as a synonym for `--format json`.

### Two invariants you can rely on

1. **`items.length` == the sum of the lengths of the six arrays.** Every reported
   line appears exactly once in each representation. This is held structurally --
   a single `Emit` writes to one array and to `items` -- not by convention.
2. **The REMAINDER is exactly the items whose `field` is `todos`,
   `reemit_notes` or `warnings`.** The other three fields describe work that WAS
   done.

### Failure paths are JSON too

`ok:false` documents are emitted for rule-validation failure (with
`rule_errors` populated), for a plan that could not be built, and for an
`--apply` refused by the freshness guard (with `freshness.reasons`). You never
get prose on stdout under `--format json`, so a parse failure is a real defect,
not an expected mode.

## The `kind` vocabulary

| kind | field | means |
|---|---|---|
| `field-retyped` | converted | the `.pas` published field declaration was retyped |
| `access-site-rewritten` | access_sites | `obj.Old` -> `obj.New` at a `.pas` access site |
| `creator-retyped` | creator_sites | `FromType.Create` -> `ToType.Create` |
| `dfm-path-created` | reemit_notes | an intermediate target sub-object was synthesized (info) |
| `creator-verify` | todos | the marker left at a rewritten creator -- ctor args are never fixed up |
| `creator-unverified` | reemit_notes | the target has no indexed generic `Create(AOwner)` |
| `unmapped-property` | reemit_notes | a source property with a non-default value was dropped |
| `binary-type-mismatch` | reemit_notes | a binary/complex value whose F/T types differ; not copied |
| `owned-part-unconverted` | reemit_notes | a nested owned part needs its own `#convert` |
| `link-stub-unfilled` | reemit_notes | a `#link` target still spelled `???` |
| `collection-relocated` | reemit_notes | a collection moved verbatim to a new path (info) |
| `defaults-may-diverge` | reemit_notes | F/T differ, so absent values adopt the T default |
| `cast-not-applied` | warnings | a `#link` carrying `: Cast`, refused on the `.pas` side |
| `instance-skipped` | warnings | the whole instance was skipped before any edit |
| `field-decl-not-retyped` | warnings | a shared multi-declarator line was not retyped |
| `uses-unit-unresolved` | warnings | no unit found declaring the target type |
| `mapping-source-absent` | reemit_notes | an applied `#mapping`'s source path is not in this block |
| `mapping-not-applied` | warnings | an applied `#mapping` matched nothing |

`ApplyItemKindName` is the single source of these spellings; nothing emits a
literal.

### `mapping-source-absent` is an addition beyond the original table

It is **not** in PLAN-SESSION-68's proposed vocabulary and needs your sign-off.
It exists because there was nowhere truthful to put "the applied mapping's
source property is not in this block": folding it into the general notes array
would have stamped it `defaults-may-diverge`, which is simply false. It is
informational, not remainder.

### `dropped-dfm-property` is RESERVED and not emitted

A property removed by an explicit `#remove`, or acknowledged by `#ignore`, is
silent by design. **Whether a deliberate removal counts as remainder at all is
your call, and we have not made it.** If you want these surfaced, say so and it
becomes an additive kind.

## Anchoring: what `line` means

`line` is a 1-based line in `file`, or `0` when unknown. Two things to know:

* `.pas`-derived items (`field-retyped`, `creator-*`, `access-site-rewritten`)
  anchor at the exact source line.
* **`.dfm`-derived items can only anchor at the instance's `object` block header
  line.** `TDfmNode` carries no line number, so a per-property line does not
  exist to report. If you need per-property anchoring in the DFM, that is a
  change to the re-emit parser and worth its own request.

`rule_line` is the 1-based line **in the rules file** that produced the item, or
`0`. For `mapping-not-applied` it is the `#apply` line -- the line that requested
the work that did not happen -- not the mapping's own declaration.

## `#mapping` / `#apply` semantics, as implemented

* Three flat sibling line forms, tied together only by the mapping's name.
* First matching `#when` wins; branches are evaluated in source order.
* A consumed source property is **not** also re-emitted raw.
* `#else` fires only when the source property is PRESENT. An absent source
  yields `mapping-source-absent`; firing `#else` there would invent a target
  value from a property the form never set.
* `#apply` scope is the nearest PRECEDING `#convert` by line number, matched on
  its bare From type. An `#apply` with no preceding `#convert` is file-scope.
* A source property that is present but matches no branch, with no `#else`, is
  reported as BOTH `unmapped-property` (the re-emit dropped it) and
  `mapping-not-applied` (the mapping you asked for did nothing). That is
  deliberate: they are different facts about the same property, and suppressing
  either would hide something true.

## Open questions we are NOT deciding for you

From `docs\INBOX-split-merge-value-conversion-scope.md`:

1. What a split/merge means when the source value does not parse into the
   expected parts.
2. Whether a partially-applied split may write a PARTIAL target.
3. How a split/merge is spelled in the DSL.
4. Whether a deliberate `#remove` / `#ignore` is remainder (above).

## Not yet built

* **The `.castlib` reader and the enum cast.** `#link To <- From : CastName`
  parses and the cast is captured, but it is NOT performed: `convert-apply`
  refuses such a rename and warns (`cast-not-applied`) rather than renaming a
  property while silently dropping its value conversion.
