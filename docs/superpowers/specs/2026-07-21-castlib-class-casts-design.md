# Design: DSL-definable class casts (`.castlib`)

**Date:** 2026-07-21. **Status:** approved design (pre-plan).
**Branch:** `feat/converter-editor` (editor half); engine half is a handoff to `main`.

## 1. Problem

The conversion editor maps a source (From) property to a target (To) property and
`convert-apply` realizes it. Casts today are **scalar-only**: a fixed `TCastFn` enum
(`IntToStr`, `StrToFloat`, `BoolToStr`, ...) emitted as the `: Cast` suffix on
`#link` ([ConvRules.Casts.pas](../../../src/tools/convrules-editor/ConvRules.Casts.pas)).
Class-to-class conversions cannot be expressed. Concretely: a legacy control's
`Glyph: TBitmap` / `Picture: TPicture` must map to a DevExpress `TdxSmartGlyph`
(`dxGDIPlusClasses.TdxSmartGlyph`). These are unrelated classes -- `dst := src` won't
compile -- but `TdxSmartGlyph` inherits `Assign` from `TdxCustomSmartImage`, so
`dst.Assign(src)` transfers the content. `IsCastable('TPicture','TdxSmartGlyph')`
returns False today, so the editor blocks the link.

There will be **more such casts over different type families**, so the mechanism must
be data-driven and extensible, not a hardcoded table.

## 2. Goals / non-goals

**Goals**
- Casts are **definable in a data file** (a shipped `.castlib`), not baked into the
  `TCastFn` enum.
- A cast can be **realized on both surfaces**: reshape the property in the **DFM** and
  insert a statement into the **.pas**.
- Class casts join the **castability list** so the editor offers and emits them.
- Ship a **small fixed built-in library** now (the graphic/image family), with the
  schema ready for more.

**Non-goals (YAGNI)**
- No plugin/DLL provider system. A shipped, editable data file is enough.
- No inline `#castdef` in individual `.rules` files (central library only, for now).
- No binary image transcoding inside the DFM re-emit (see the content strategy).
- No speculative catalog -- ship ONE real, tested cast (`AssignGraphic`).

## 3. Architecture -- shared file, two consumers

The `.castlib` file is the single **contract**. Two independent readers:

| Consumer | When | Reads for | Where |
|---|---|---|---|
| **Editor** (this branch, now) | author-time | castability, Auto-Match, emit `: CastName` | new pure `ConvRules.CastLib.pas` |
| **Engine `convert-apply`** (handoff to `main`) | apply-time | realization (DFM / pas / TODO) | engine reader (engine team) |

Rationale: the editor is a thin authoring client; parsing a simple data file directly
keeps it unblocked and shipping immediately, while realization follows on the engine
side (same split as the proptree/2 work). Two small readers of one simple format is an
accepted, low cost; the format is the durable contract.

Rejected alternative: engine owns parsing and the editor consumes a
`convert-casts --json` verb. Thinner editor, but blocks ALL editor progress on an
engine change. Not worth it for a small format.

## 4. The `.castlib` schema

A shipped ASCII file (e.g. `docs/examples/convrules/casts.castlib`, or a path the
engine + editor both resolve). One or more `cast … end` blocks. DSL-flavored to match
the `.rules` feel; strict 7-bit ASCII, CRLF.

```
cast AssignGraphic
  accepts TPicture, TBitmap, TGraphic, TPngImage, TIcon   # SET of accepted From types
  yields  TdxSmartGlyph                                    # one or more To types
  dfm     keep-bytes-if-compatible                         # DFM strategy (enum, below)
  compat  png, bmp                                         # formats byte-carry may keep
  pas     '{dst}.Assign({src});'                           # statement when DFM can't carry
  todo    'transfer image from {src} by hand'             # last-resort marker text
end
```

**Field semantics**
- `name` (block header): identifier used in `#link To <- From : name`. Unique across
  the library and NOT colliding with a scalar `TCastFn` name.
- `accepts`: comma-separated bare From type names. Membership is case-insensitive,
  exact-name (no ancestry walk in v1 -- list the concrete types).
- `yields`: comma-separated bare To type names (usually one).
- `dfm`: one of `keep-bytes-if-compatible` | `rename` | `drop` | `none`. Governs what
  the DFM re-emit does with the source property block. (Engine-consumed.)
- `compat`: optional format tokens the byte-carry may safely keep (engine-consumed;
  editor ignores). Absent => byte-carry never applies -> pas/TODO.
- `pas`: optional statement template inserted when the DFM cannot carry the value.
  Placeholders: `{dst}` (target property access path), `{src}` (source expression).
  (Engine-consumed for realization; editor stores it verbatim.)
- `todo`: optional fallback text for a `// TODO[convert]` marker when neither DFM nor
  pas can realize the value.

Unknown keys are tolerated (skipped) so the engine can add realization hints the
editor need not understand -- forward-compatible.

## 5. Castability + authoring (editor -- this branch)

New pure unit `ConvRules.CastLib.pas`:
- `TCastDef = record Name: string; Accepts, Yields: TArray<string>; Dfm, Compat,
  PasTemplate, Todo: string; end;`
- `function LoadCastLib(const APath: string): TArray<TCastDef>;` -- tolerant parser
  (skips blanks/comments/unknown keys); pure + unit-tested against inline fixtures.
- `function ClassCastFor(const ADefs; const AFrom, ATo: string): string;` -- returns
  the cast NAME whose `accepts ∋ from` and `yields ∋ to` (case-insensitive), else ''.

Integration in the editor:
- `ConvRules.Casts.IsCastable` stays pure/scalar; a NEW higher layer in the form (or a
  thin `CastLibResolve` helper) treats a pair as castable when the scalar classifier
  says so OR `ClassCastFor` returns a name. The editor loads the `.castlib` once at
  startup. **Path resolution** mirrors `ResolveDragLintExe` (ConvRulesEditor.dpr): (1)
  `casts.castlib` next to the editor exe (co-deployed to `third_party/dll-win64`),
  else (2) the repo default `docs/examples/convrules/casts.castlib`, else (3) empty
  library (class casts simply unavailable -- degrade to today's scalar-only behavior,
  never an error). A `GEditorCastLib: string` global (set in the `.dpr`) carries the
  resolved path, matching the existing `GEditorExe`/`GEditorLibDir` pattern.
- `AssignLink` (MainForm): for a class pair, set `Link.Cast` to the class-cast NAME
  (the `Cast` field is already a free string, so the DSL `#link … : AssignGraphic`
  round-trips through the existing model with NO grammar change).
- `RefreshPool` / `DoAssign`: a To leaf typed to a castdef's `yields` is a valid target
  for a From leaf in that castdef's `accepts`; the pool shows it, Assign creates the
  `: CastName` link.
- **Auto-Match:** class casts are lossy -- only propose one on an exact leaf-NAME match
  whose types line up with a castdef (never on a name-only or type-only guess). Same
  conservative bar as today's scalar Auto-Match.

No engine round-trip is required for any of the above.

## 6. Realization (engine handoff -- `main`)

`convert-apply` gains: when a `#link To <- From : CastName` names a library class cast
(not a scalar `TCastFn`), look up the castdef and apply the **layered** content
strategy (chosen 2026-07-21):
1. **DFM byte-carry** if `dfm = keep-bytes-if-compatible` AND the source graphic's
   format is in `compat` AND the target property accepts it -> the re-emit carries the
   blob into the new property. Zero code.
2. else **pas insert**: emit the `pas` template (resolving `{dst}` = the converted
   control's target property access, `{src}` = the source value) at the construct site
   (surface #3/#4 already exist in `convert-apply`).
3. else **TODO**: emit `todo` as a `// TODO[convert]` marker (existing machinery).

**Open engine question (their design):** where `{src}` comes from at runtime when the
DFM value is dropped -- preserve the original bytes as a generated const/resource, keep
a hidden holder, or read from the original DFM. Same shape as the proptree extraction
handoff: the engine team owns it. This is documented for them, not decided here.

## 7. Initial fixed library

Ship exactly one cast: `AssignGraphic` (§4), covering the DevExpress glyph-migration
case (`TPicture`/`TBitmap`/`TGraphic`/`TPngImage`/`TIcon` -> `TdxSmartGlyph`). Adding
more casts later = more `cast … end` blocks; no code change on the editor side.

## 8. Testing

Editor (this branch), pure where possible:
- `LoadCastLib`: parses a well-formed block; multi-type `accepts`; tolerates unknown
  keys / blank lines / comments; ignores a malformed block without aborting the file.
- `ClassCastFor`: `TPicture -> TdxSmartGlyph` = `AssignGraphic`;
  `TBitmap -> TdxSmartGlyph` = `AssignGraphic`; `TPicture -> TStrings` = '' (blocked);
  case-insensitive.
- Castability: the editor treats `TPicture -> TdxSmartGlyph` as castable and emits
  `#link … : AssignGraphic`; a non-listed class pair stays blocked.
- Round-trip: a `.rules` containing `#link Glyph <- Glyph : AssignGraphic` loads and
  re-emits byte-faithfully (the `: Cast` slot already round-trips).

Engine (handoff): realization tests are the engine team's, per their spec.

## 9. Sequencing

1. **This branch, now:** `.castlib` file + `ConvRules.CastLib.pas` + castability /
   Auto-Match / emit wiring + editor pool integration + tests. Editor authors
   `AssignGraphic` links immediately (they just won't be *realized* until the engine
   half lands -- authoring and apply are separate phases).
2. **Engine handoff (`main`):** a spec (mirroring the proptree handoffs) for
   `convert-apply` realization + the `{src}` sourcing decision.

## 10. Risks / notes
- **Two readers of one format** can drift. Mitigation: the format is deliberately tiny;
  the editor ignores realization-only fields (`dfm`/`compat`/`pas`/`todo`) and only
  needs `name`/`accepts`/`yields`. Drift risk is confined to fields only one side uses.
- **Lossy casts authored but not realized** until the engine half ships: acceptable --
  the editor is an authoring tool; a `: AssignGraphic` link is a correct instruction
  even before `convert-apply` can execute it. `convert-validate` should accept a known
  library cast name (a small engine-side allowance, noted in the handoff).
- **ASCII/CRLF** applies to the `.castlib` and all new `.pas`.
