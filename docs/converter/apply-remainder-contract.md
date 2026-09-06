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
| `defaults-may-diverge` | reemit_notes | a rule-referenced source is absent AND has no `default` clause, so the T default applies (NARROWED -- see below) |
| `cast-not-applied` | warnings | a `#link` carrying `: Cast`, refused on the `.pas` side |
| `instance-skipped` | warnings | the whole instance was skipped before any edit |
| `field-decl-not-retyped` | warnings | a shared multi-declarator line was not retyped |
| `uses-unit-unresolved` | warnings | no unit found declaring the target type |
| `mapping-source-absent` | reemit_notes | an applied `#mapping`'s source path is not in this block AND has no `default` clause (NARROWED -- see below) |
| `mapping-not-applied` | warnings | an applied `#mapping` matched nothing |
| `default-superseded` | warnings | a `#default` did not fire -- a `#link`/`#mapping` already carried that path |
| `default-resolved` | reemit_notes | a source property absent because it sits at its declared `default`; its value was resolved and carried explicitly |

`ApplyItemKindName` is the single source of these spellings; nothing emits a
literal.

### `default-superseded` is an addition beyond the original table

Also not in PLAN-SESSION-68's vocabulary, and it also needs your sign-off.

`#default` is documented on both sides as a FALLBACK -- "set a target property
to a value **when no source maps**". The implementation tested neither claim: it
looped every `#default` and wrote unconditionally, *after* the leaf loop and
after `#mapping`, so last-writer-wins made `#default` beat everything. A rule
book stating both `#link HeaderColor <- HeaderColor` and
`#default HeaderColor = clGreen` -- the natural way to write "use the source
value, or green if there isn't one" -- **silently discarded the form's real
value**, exit 0 and no warning. Measured: `.dfm` says `clRed`, output said
`clGreen`.

The code now matches the docs: a `#default` whose target path is already carried
does not fire. We report the skipped rule rather than dropping it in silence,
because the operator wrote a rule that did nothing and only they can say which
of the two they meant -- the same reasoning that produced `mapping-not-applied`.
It carries `path`, `rule_line`, the value the `#default` asked for, and the
value that won, so the rule book can be fixed without the `.dfm` to hand.

Nothing is lost in this case -- the source value is the one that survives -- so
if you would rather have it in `reemit_notes` than `warnings`, say so; that is a
field change, not a rename, and does not break `apply/1`.

The `convert-reemit` JSON gained a matching additive `report.defaultsSuperseded`
array (`path`, `value`, `existing`, `ruleLine`). Existing keys are unchanged.

### `mapping-source-absent` is an addition beyond the original table

It is **not** in PLAN-SESSION-68's proposed vocabulary and needs your sign-off.
It exists because there was nowhere truthful to put "the applied mapping's
source property is not in this block": folding it into the general notes array
would have stamped it `defaults-may-diverge`, which is simply false. It is
informational, not remainder.

### A `.dfm` is SPARSE -- and that changed three kinds at once

This is the largest semantic change in this document, so it is stated plainly.

Delphi does not stream a published property whose value equals the `default`
declared on it. **An absent property is therefore an UNREAD value, not a missing
one.** The engine used to read absence as "nothing to map", which meant the F
value was dropped and the T side quietly adopted **T's own** default -- a
different value that merely shares a property name.

The property tree now resolves each declaration's `default` clause (at query
time, from the declaring source line -- it is deliberately not indexed, because
storing it would force a `DRAGLINT_EXTRACTOR_VERSION` bump and re-parse every
database). Three outcomes, not two:

| declaration | resolved default |
|---|---|
| `property P: T ... default <X>;` | `<X>` |
| `property P: T ... default [a, b];` | the whole set literal, brackets included |
| `property P;` (bare redeclaration) | whatever the **ancestor** declared -- pervasive in the VCL |
| `nodefault`, a bare `default;` (the default-ARRAY-PROPERTY directive), or no clause | **none** -- the property is ALWAYS streamed, so its absence is genuinely unknown |
| **anything with `stored <expr>` other than `stored True`** | **none** -- see below |

### `stored` is a veto, and it is why this is not just "read the default"

The premise "absent ⇒ the value equals the declared default" holds only for a
property that is streamed **unconditionally**. The VCL's own `Color` is the case
that matters -- `Vcl.Controls.pas:1996`:

```pascal
property Color: TColor read FColor write SetColor
  stored IsColorStored default clWindow;
```

With `ParentColor` set, `IsColorStored` is False and `Color` is omitted
**regardless of its value**. Reading that absence as `clWindow` and carrying it
across would be wrong twice over: the value may differ, and `TControl.SetColor`
clears `FParentColor`, so the converted control silently stops inheriting its
parent's colour. DevExpress carries many `stored IsXStored` pairs too.

So a `stored` clause that is not literally `stored True` yields **no usable
default**, and the property is reported as unresolved rather than guessed at.

Consequences you will see in `apply/1`:

* **`mapping-source-absent` NARROWED.** A `#when` now matches a resolved default
  exactly as it matches a streamed value, so a mapping over an enum finally
  fires on that enum's own default. The kind is now reserved for the third row
  above -- absent *and* no clause to resolve it to -- which is the only case
  where nothing can honestly be said. `#else` is still gated on that, because
  firing it there would invent a target value out of nothing.
* **`default-resolved` is NEW.** When a `#link`'s source is absent-because-
  default, the resolved value is carried and written into the target block
  **explicitly**, even when it may equal T's own default. Verbosity is safe --
  Delphi trims a redundant default the next time it saves the form -- whereas
  leaving the property absent silently adopts a value nobody chose. The item is
  informational: it exists so an operator diffing input against output has an
  account of a value that appears in one and not the other.
* **`defaults-may-diverge` NARROWED.** It used to fire on every F/T conversion,
  on the stated grounds that the indexer had no default values. That premise is
  gone. It now fires only when a rule-referenced source is absent with no
  `default` clause, and it **names the properties** instead of gesturing at the
  class pair. A warning that fires when nothing is wrong teaches the reader to
  skim, which is the failure this project can least afford.

**Scope: rule-referenced properties only,** and the reason is consistency rather
than diff size. An F property that is PRESENT but named by no rule is already
dropped and reported as `unmapped-property` -- the rule book decides what
carries over. An F property that is ABSENT and named by no rule must behave the
same way. Emitting unreferenced properties would invent policy the rule book
never stated.

`default-resolved` needs your sign-off like the two kinds above it.

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
the work that did not happen -- not the mapping's own declaration. For
`default-superseded` it is the `#default` line, for the same reason: it is the
line to delete or rethink.

## `#mapping` / `#apply` semantics, as implemented

* Three flat sibling line forms, tied together only by the mapping's name.
* First matching `#when` wins; branches are evaluated in source order.
* A consumed source property is **not** also re-emitted raw.
* `#else` fires when the source property is PRESENT **or resolves to its
  declared default**. Only a source that is absent AND has no usable default
  yields `mapping-source-absent`; firing `#else` there would invent a target
  value out of nothing. **This reverses what we told you on 2026-09-04** (`#else`
  fires only when PRESENT) -- the sparse-DFM ruling changed it, and an absent
  property at its declared default is a value that was always there to be read.
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
