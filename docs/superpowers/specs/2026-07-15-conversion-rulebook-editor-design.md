# Design: Component Conversion Rule-Book Editor (v1)

Date: 2026-07-15. Status: **approved, implementing.**

## 1. Purpose & non-goals

A **standalone plain-VCL Windows exe** (`ConvRulesEditor.exe`) that **authors and
edits `conversion.rules` DSL files** -- the same files `drag-lint convert-apply`
consumes. It is a visual **front-end to the existing conversion engine**, not a new
engine.

**Non-goals (explicit):**
- It does **NOT** perform conversion. Execution stays in `convert-apply`, to be
  callable later from AI (API) and from the IDE by the user.
- It does **NOT** parse DFMs or property trees itself -- it shells `drag-lint`
  (`proptree --json`, `convert-scaffold`, `convert-validate`) for all semantic
  knowledge.
- The **DSL file is the single source of truth**; the editor keeps no hidden
  state. After Save, the file runs the conversion plainly via the engine.

**Hard requirement:** the editor must expose and **edit every DSL feature** --
nothing is preserve-only. Full grammar inventory in section 4.

## 2. Architecture -- three bounded units

```
ConvRulesEditor.exe (VCL, no DevExpress)
  UI layer  <-->  TRuleBook DSL model (pure, headless)  <-->  engine adapter (shells drag-lint)
                          |
                          v
              conversion.rules  (+ .bak backup)  -- canonical ASCII/CRLF
```

1. **`TRuleBook` DSL model** (`ConvRules.Model.pas`) -- pure, headless. Parses a
   `.rules` file into an ordered, **loss-less** list of typed nodes (one per line);
   re-emits byte-faithfully except where edited. The single piece that MUST be
   exhaustively DUnitX-tested. No UI, no I/O beyond string in/out.
2. **Engine adapter** (`ConvRules.Engine.pas`) -- shells `drag-lint`; parses
   `proptree/1` JSON into flat property lists; runs `convert-scaffold` (seed a new
   pair) and `convert-validate` (live check). The only external-process boundary;
   fixture-tested.
3. **Cast classifier** (`ConvRules.Casts.pas`) -- pure function
   `(FromLeafType, ToLeafType) -> set of valid CastFn`. Tested by a type-pair
   table.
4. **UI layer** (`ConvRules.MainForm.pas` + helpers) -- holds no truth; every edit
   goes through the model.

**Dependency / honest gap:** the tool is only as good as the index -- both F and T
types must be indexed with full property trees, and the library DB must be at the
**current schema version** (see the 2026-07-15 v15/v16 regression: a stale-schema
DB returns zero results). The adapter surfaces a clear "type not indexed / stale
DB" message rather than an empty grid.

## 3. Screen layout

Three stacked regions in one window:

- **A. DFM Inventory** (top-left, on-demand): components in a chosen `.dfm`,
  filtered by an editable **ignore list** (globs, e.g. `Tdx*`, `Tcx*`). Each row:
  name : type + "has rule?". **"-> Add as From"** copies the type into the editor
  as F; you then **pick a To type** from the master class list. Owned
  sub-components (TTable's TField/TFieldDef) appear as indented child rows, each
  promotable to its own F.
- **B. Rules Library** (top-right): every `#convert F -> T` block, each with a
  **% complete** column (section 5). **Alternative rules** (same F, different T)
  are separate rows. Owned-sub-component rules nest under their parent.
  "New rule...", "Delete", "Duplicate as alt".
- **C. 3-column mapping grid** (bottom): the active F->T pair.

Selecting a library row -- or adding from inventory -- loads the grid.

### The 3-column grid
- **Col 1 FROM**: flattened F property tree (from `proptree --json`), one leaf/row,
  read-only.
- **Col 2 TO (assigned)**: aligned to col 1; the T property `#link`ed to that F
  leaf, or blank. Editable mapping. Shows a **cast dropdown** when F/T leaf types
  differ (section 6).
- **Col 3 TO (unassigned pool)**: T leaves not yet linked. **Searchable** (type
  "font" -> jump to `Style.Font.*`) -- the antidote to deep-tree explosion.

**Gestures:** drag col-3 -> col-2 cell to assign (and back to unassign); or
select + "Assign >" / "< Unassign" buttons. Each assignment writes/updates a
`#link ToPath <- FromPath` in the model live.

**To-type picker:** master list of all indexed `TComponent`-rooted classes
(`drag-lint query`), searchable. Only indexed types offered.

**Initial population:** existing rule -> load its `#link`s (resume prior work);
brand-new pair -> run `convert-scaffold`, parse it (`#link` confident -> col 2;
`???` ambiguous -> blank + `#note candidates:` hint; `DROPPED` -> flagged; orphan
T -> col 3).

## 4. Complete DSL inventory (every feature is editable)

Directive tabs under the grid expose the whole grammar:

| Tab | Directives |
|---|---|
| Links | `#link <ToPath> <- <FromPath> [: CastFn]` (mirrors the grid) |
| Defaults | `#default <ToPath> = <value>` |
| Ignores | `#ignore <FromPath>` |
| Remove / Unuse | `#remove <prop>`, `#remove DFM: <prop>`, `#unuse <unit>` |
| Migrate / PCRE | `#migrate [Class:][obj.]<old> -> <new> [, unit ...]`, raw `<pcre> -> <pcre>` |
| Notes / Comments | `#note <text>`, `//` and `;` comment lines |
| Header | `#convert <From> -> <To> [, unit ...]` |

A **raw-DSL view** (edit as text, re-parsed on switch-back) is the escape hatch.
Blank lines preserved. Unknown directives are captured as editable "unknown" nodes,
never silently dropped.

## 5. % complete

Per `F -> T` rule:
```
% = (F leaves with a concrete #link OR an explicit #ignore) / (total F leaves)
```
100% = every source property is mapped or explicitly acknowledged-unmapped. `???`
stubs and un-addressed F leaves count as incomplete. Denominator uses the active
ancestor-cutoff F tree (section 7) so `TComponent` noise doesn't sink every score.

## 6. Type-cast on #link (v1)

Because the tool knows both F and T leaf types, it **auto-classifies castability**
and offers only valid casts:

| F leaf -> T leaf | verdict | emitted |
|---|---|---|
| same type | identity | `#link T <- F` (no suffix) |
| Integer -> Double/Single | widening | `#link T <- F : IntToFloat` |
| Double -> Integer | narrowing | `#link T <- F : Round` (or `Trunc`) |
| numeric -> string | format | `: IntToStr` / `: FloatToStr` |
| string -> numeric | parse | `: StrToIntDef` / `: StrToFloatDef` |
| Boolean -> string | format | `: BoolToStr` |
| enum/class/no-cast | **blocked** | flagged red, no `#link` until resolved |

Cast dropdown offers only casts valid for that pair. This is a **new DSL token**
(`: CastFn` suffix). See the parallel engine workstream (section 9) for
tolerate+apply support; the editor emits the syntax regardless.

## 7. Deferred to v2 (designed, not built)

- **DFM-usage tint**: parse one or several selected `.dfm` files, collect F
  properties/events actually set, green-tint those col-1 rows to focus attention.
  Additive; does not change v1 architecture.
- **Ancestor cutoff engine flag**: stop the flatten at `TComponent`/`TControl`/
  `TWinControl`. v1 filters client-side via each property's `declared_in` (already
  in `proptree/1` JSON) -- no engine change; a proper engine flag is v2.
- **Multiple rule books**: switchable independent rules files. v1 edits one file.

## 8. Save behavior

1. Write a timestamped **backup** (`<name>.rules.bak`, keep a short history) before
   overwrite -- so the user can revert.
2. Re-emit the whole `TRuleBook` model as canonical **ASCII / CRLF** DSL.
3. Run **`convert-validate`**; show `OK` or the first `line N:` error in the title
   bar. The saved file is always known-good (or known-bad) for `convert-apply`.

## 9. Parallel engine workstream: `#link ... : CastFn`

Independent of the editor (different files). Scope (grounded on-disk):

- **Parser** `src/report/DRagLint.Convert.Rules.pas`: `TConversionRule` record
  (~L70-76) gains `Cast: string` (''=identity); `#link` arm (~L347-363) strips an
  optional `: CastFn` tail with a single-alnum-token guard (backward-compatible --
  cast-less lines and PCRE `:` untouched).
- **Validate** (same unit ~L473-481): catalog-membership + type-appropriateness
  using the property trees; tree-less mode tolerates the suffix.
- **Apply -- DFM value emit** `src/report/DRagLint.Convert.DfmReemit.pas`
  `RemapLeaf` (~L547): wrap/re-quote `ValueText` per catalog (IntToStr of a DFM
  integer must emit a **quoted** string literal). **Ship DFM-cast first.**
- **Apply -- .pas access-site** `src/report/DRagLint.Convert.Apply.pas` surface #4
  (~L1087): wrap the access expression; needs a wider edit span (follow-up).
- **Docs**: grammar table + catalog in `docs/CONVERSION-RULES.md`.

TDD: fixtures under `tests/autotest/` (`run_convert_rules.ps1`, `run_dfm_reemit.ps1`).

## 10. Testing & build

- `TRuleBook` model -- DUnitX: every directive round-trips (load->emit
  byte-faithful), each edit op, `: CastFn` suffix, malformed-line tolerance.
- Cast classifier -- DUnitX type-pair table.
- Engine adapter -- parse fixtures of real `proptree/1` + `convert-scaffold`.
- UI -- manual smoke; all logic sits in the tested units.
- **Build:** `src/tools/convrules-editor/`, plain VCL (no DevExpress), Win32, via
  the `delphi-build` recipe; deploy `ConvRulesEditor.exe` to `third_party/dll-win64/`
  (alongside the CLI). A sample `.rules` + a couple of sample DFMs under
  `docs/examples/convrules/` so it opens with something to show.
