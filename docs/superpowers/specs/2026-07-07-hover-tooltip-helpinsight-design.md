# Hover Tooltip -- Help-Insight Restyle + Returns Mining

Date: 2026-07-07
Status: Design approved (brainstorming), ready for implementation plan
Topic thread: #2 (post-v0.94 queue)

## 1. Goal

Restyle the drag-lint IDE hover popup so it reads like Delphi's native Help
Insight tooltip, and add data the current popup lacks. Concretely:

1. **One-line clickable header** = the full signature + `unit.pas Line N`, the
   whole line navigating to the definition on click.
2. **Colored, selectable rendering** using the user's *configured IDE font*
   (whatever they set -- Consolas, Times New Roman, anything), not hardcoded
   Consolas.
3. **Parameters** list keeps `const`/`var`/`out` modifiers, one per line, with
   the types aligned in a column (name column padded to just past the longest
   name).
4. **Returns** section mines the routine body for the actual
   `Result := <expr>` / `Exit(<expr>)` right-hand sides (no LLM), listing every
   distinct RHS in source order, capped at 10 with `... and NN more`.
5. **Called from** section shows the caller count and caps the list at
   **15 -> show all; otherwise show 10 + "and NN more"**.
6. A **contrast guard**: every syntax color is checked against the *live* popup
   background (after IDE theming) via the WCAG relative-luminance ratio and
   auto-adjusted if it would be unreadable -- text is never invisible on any
   theme.

### Already shipped (NOT in scope to rebuild)

The current popup (`DragLint.Plugin.HoverForm.pas` + `Editor.pas`) already does:
theme-follow (`ApplyIdeTheme`), a callers grid (`TListView`, double-click ->
navigate, sourced from `query find-callers --json`), one-param-per-line
rendering (`RenderSignatureParamsMarkdown`), single-click navigation on memo
definition rows, hand-cursor feedback, and the no-steal-focus / dwell-dismiss
behavior. This design *reuses* those; it does not replace them.

## 2. What changes, unit by unit

### 2.1 New unit: `DRagLint.Hover.Contrast` (CLI/plugin shared, RTL-only)

Self-contained, zero dependencies, pure arithmetic. Testable in isolation.

```pascal
/// <summary>WCAG 2.x relative-luminance contrast ratio between two colors.</summary>
/// <returns>Ratio in [1.0, 21.0]; 1.0 = identical, 21.0 = black-on-white.</returns>
/// <remarks>Deterministic; no VCL theming state. Uses TColor RGB channels.</remarks>
function ContrastRatio(AForeground, ABackground: TColor): Double;

/// <summary>Return AForeground unchanged if it already meets AMinRatio against
/// ABackground; otherwise nudge its lightness toward the opposite luminance end
/// until it does (or clamp at black/white).</summary>
/// <param name="AMinRatio">WCAG floor: 4.5 for body text, 3.0 for large/bold.</param>
/// <returns>A color guaranteed to clear AMinRatio against ABackground.</returns>
function EnsureReadable(AForeground, ABackground: TColor; AMinRatio: Double = 4.5): TColor;
```

Implementation notes:
- Relative luminance L = 0.2126*R' + 0.7152*G' + 0.0722*B', with each channel
  linearized via the sRGB transfer function (the `<=0.03928 ? c/12.92 :
  ((c+0.055)/1.055)^2.4` piecewise). Channels normalized 0..1 from TColor's
  0..255 bytes (`GetRValue`/`GetGValue`/`GetBValue` after `ColorToRGB`).
- `ContrastRatio = (Lmax + 0.05) / (Lmin + 0.05)`.
- `EnsureReadable`: convert to HSL, step Lightness away from the background's
  luminance (down if BG is light, up if BG is dark) in small increments,
  re-checking the ratio, until it passes or hits 0/1. Keeps hue/saturation so
  the color stays recognizably "the keyword blue", just readable.

Consumed at paint time by the IDE renderer (below). The CLI markdown output
does not need it (markdown carries no colors), but the unit lives in a
CLI-buildable location so its tests run in the normal console harness.

### 2.2 `DRagLint.Hover.Renderer` (CLI + LSP) -- Returns mining + structured model

Today this unit emits plain/markdown/json strings. It grows two things:

**(a) A structured hover model** so the IDE renderer can color parts
individually instead of re-parsing a flat string. Add:

```pascal
type
  TParamPart = record
    Modifier : string;   // 'const' / 'var' / 'out' / '' (none)
    Name     : string;   // 'A1'
    TypeText : string;   // 'integer'
  end;

  TReturnFact = record
    Expr : string;   // the RHS text, e.g. 'S2.Length > 0' or 'ERROR_OK'
  end;

  THoverModel = record
    QualifiedName : string;              // BASICF.SomeFunction
    Kind          : string;              // function / procedure / property / ...
    Signature     : string;              // full signature as indexed
    UnitFile      : string;              // BASICF.pas
    DefLine       : Integer;             // 123
    Params        : TArray<TParamPart>;  // Modifier ('const'/'var'/''), Name, TypeText
    ReturnType    : string;              // 'boolean'
    Returns       : TArray<TReturnFact>; // distinct RHS, source order, <=10 (+more flagged)
    ReturnsMore   : Integer;             // count beyond the 10 shown (0 if none)
    Doc           : TParsedDoc;          // existing summary/remarks/params/since/deprecated fields, unchanged
  end;
```

The existing string renderers (`RenderHoverPlain/Markdown/Json`) are kept for
the CLI text/LSP-markdown paths and are refactored to build from `THoverModel`.
LSP hover continues to send markdown (unchanged wire format); the *IDE* reads
the same model via a new machine-readable channel (see 2.4).

**(b) Returns mining.** New function:

```pascal
/// <summary>Scan a routine body for distinct Result:= / Exit(...) RHS
/// expressions and return them in source order.</summary>
/// <param name="ABodyLines">The routine's implementation body (impl_start_line
///   .. impl_end_line from the index), one string per source line.</param>
/// <returns>Distinct RHS expression strings (dedup'd, order-preserving).</returns>
/// <remarks>No LLM. Single-line RHS only; a RHS spanning lines is captured up to
///   the terminating ';'. Assignments to Result inside nested routines are
///   excluded by the caller (it passes only this routine's own body span).</remarks>
function MineReturnExpressions(const ABodyLines: TArray<string>): TArray<string>;
```

Rules (approved: "all distinct RHS, cap 10"):
- Match `Result := <rhs> ;` (case-insensitive `Result`, tolerant of spacing)
  and `Exit ( <rhs> )` for value-returning `Exit`.
- Capture `<rhs>` verbatim, trimmed.
- **Distinct**: dedup by exact RHS text, preserving first-seen order.
- Cap at 10; set `ReturnsMore := DistinctCount - 10` when exceeded.
- Skip lines inside comments / strings (reuse the parser's existing
  comment-strip helper; a lightweight line-level skip is acceptable for v1 --
  a `Result :=` inside a `//` comment or a string literal is rare and the miner
  is best-effort, never authoritative).
- If the routine is a `procedure` (no return type) the section is omitted.

**Body-source access.** The index stores `impl_start_line` / `impl_end_line`
per symbol and the owning `file_id` -> absolute path. The renderer's caller
(LSP server / CLI `hover`) reads those lines from the source file and passes
them to `MineReturnExpressions`. This is the same body-span the autodoc
`document` feature already uses; no schema change, no reindex.

### 2.3 `DRagLint.CLI` -- `hover` verb gains the model

The CLI `hover` command already renders text/markdown/json. It gains the
Returns section in all three (mining as above). `--json` output grows the
`returns` array + `returns_more` int and the structured `params` array so the
IDE can consume it directly (see 2.4). Existing fields unchanged (additive).

### 2.4 IDE data path -- how the plugin gets the model

The plugin currently fetches two things: LSP `textDocument/hover` markdown
(header + params + docs) and `query find-callers --json` (callers). It parses
the markdown back into pieces (`ExtractHoverHeader`, `StripFirstHeaderLine`).

Change: the plugin instead calls the CLI **`hover --json`** for the symbol under
the cursor to get the full `THoverModel` (qname, kind, signature, params w/
modifiers+types, return type, mined returns + more-count, def unit+line, doc
fields), and keeps the separate `find-callers --json` call for callers. This
removes the brittle markdown re-parsing. (The LSP markdown path stays for
non-IDE LSP clients; the IDE prefers the richer JSON.)

Rationale: the IDE already shells out to the exe for callers; one more
`hover --json` call is consistent, avoids re-parsing markdown, and gives the
renderer typed parts to color.

### 2.5 `DragLint.Plugin.HoverForm` -- TRichEdit body + contrast + font + caps

**Control choice: `TRichEdit`** (stock `Vcl.ComCtrls`, already in `uses`).
Rejected alternatives and why:
- *Owner-drawn TPaintBox*: no text model -> **no selection / Ctrl+C**. User
  requires copyable text. Rejected.
- *DevExpress / HTML control*: **open-source project** -- consumers may not have
  DevExpress; no reliable stock VCL HTML control. Rejected.

`TRichEdit` gives colored runs (`SelStart`/`SelLength` + `SelAttributes.Color`
/`.Style`/`.Name`), mixed fonts, native selection + clipboard, and themes.

Layout (top -> bottom):
1. **Header band (TRichEdit, top region or its own line)**: the full colored
   signature as one line; a right-aligned `unit.pas Line N`. The whole header
   line is a click target -> navigate to `DefLine` in `UnitFile` (reuse
   `GOnNavigateToQname` / `OpenSourceAt`). Hand cursor over it.
2. **Parameters** (in the same TRichEdit): `<modifier> <name> : <type>`, one per
   line, name column padded to `MaxNameLen + 1` so types align. Modifier in
   keyword color; name in param color; type in type color.
3. **Returns** (same TRichEdit): `ReturnType : Result := <expr>` for a single
   RHS, or a list of `Result := <expr>` lines for several, plus a muted
   `... and NN more` when `ReturnsMore > 0`. Omitted for procedures.
4. **Called from (TListView, existing)**: label shows `Called from (N)`; the
   grid lists callers with the **15/10 cap**: if `N <= 15` show all; else show
   the first 10 and append a non-clickable `... and (N-10) more` row (or a muted
   label under the grid). Existing double-click -> navigate is unchanged.

**Fonts.** New helper reads the IDE's configured editor font name + size via
ToolsAPI (the environment editor-font option) and applies it to the TRichEdit's
base `SelAttributes.Name/Size` and to the callers `TListView.Font`. Fallback to
Consolas 9 if the API is unavailable (older IDE / service missing). Replaces the
four hardcoded `'Consolas'` assignments in this form.

**Contrast.** After `ApplyIdeTheme(Self)` runs (so the real background `Color`
is known), every syntax color pushed into the TRichEdit is passed through
`EnsureReadable(color, ActualBackground, 4.5)` (3.0 for the bold header name).
This is the single guarantee that no run is invisible on any theme.

**Behavior preserved.** No-steal-focus show, dwell vs. menu dismissal, ESC /
click-outside, the 200-row hard cap on fetched callers (the 15/10 *display* cap
is layered on top), singleton `GCurrentHover`. None of the dismiss/focus logic
changes.

## 3. Component boundaries (isolation)

- `DRagLint.Hover.Contrast` -- pure color math. Input: two colors + ratio.
  Output: a color. No VCL forms, no theming, no I/O. Unit-tested standalone.
- `MineReturnExpressions` -- pure text -> `TArray<string>`. Input: body lines.
  Output: distinct RHS. No I/O (caller supplies the lines). Unit-tested
  standalone with fixture bodies.
- `THoverModel` + string renderers -- pure model -> string. No I/O.
- CLI/LSP callers -- own the I/O (read source lines for the body span, query
  callers). Thin glue.
- `DragLint.Plugin.HoverForm` -- owns only presentation (TRichEdit/TListView
  layout, color application, click wiring). Consumes the model + contrast unit.

Each is understandable and testable without the others.

## 4. Testing (TDD + CDD)

Each new unit gets a DocInsight spec-comment and a failing test first.

- **Contrast** (`run_hover_contrast.ps1` or DUnitX): known pairs ->
  known ratios (black/white = 21.0; identical = 1.0; a mid-gray pair to a
  hand-computed value within tolerance). `EnsureReadable`: a failing pair
  returns a color whose ratio >= the floor; an already-passing pair returns
  the input unchanged.
- **Returns mining** (`run_hover_returns.ps1`): fixture bodies ->
  * single `Result := S2.Length > 0` -> one fact.
  * multiple distinct `Result := ERROR_*` -> all, in order, dedup'd.
  * repeated identical RHS -> collapsed to one.
  * `Exit(X)` value form -> captured.
  * `procedure` body -> empty (section omitted).
  * >10 distinct -> 10 + `ReturnsMore` correct.
- **CLI `hover --json`** (extend existing hover suite): asserts the new
  `returns` / `returns_more` / structured `params` fields on a known symbol.
- **Caller cap**: a symbol with >15 callers -> IDE shows 10 + "NN more"
  (unit-level test on the cap function; the form wiring is smoke-tested live).
- **IDE live smoke** (user, deferred): hover a known function in RAD Studio,
  confirm colored signature in the IDE font, aligned params, mined Returns,
  clickable header, capped callers, dark-theme readability.

The doc-comment and the test must agree (project CDD rule): e.g. the
`MineReturnExpressions` remark says "distinct, source order, single-line RHS" and
the test encodes exactly that.

## 5. Encoding / build constraints

- All `.pas` edits: strict 7-bit ASCII, CRLF, DocInsight `///` comments on
  public surface (project rule).
- Plugin BPL builds via the `delphi-build` skill recipe; CLI via the same.
- After a build that changes indexed symbols, reindex incrementally (the
  self-index) so subsequent queries reflect the new code.

## 6. Out of scope / deferred

- Markdown-native rendering of doc prose (bold/links) in the body -- the
  TRichEdit shows doc summary/remarks as styled text, but a full markdown engine
  is not built. Doc fields render as plain runs.
- Multi-line / complex RHS pretty-printing -- v1 captures up to the `;`; it does
  not reflow. If a RHS is very long it is shown truncated with an ellipsis.
- Colorizing the callers `Code` column tokens -- shown in the base editor font,
  not syntax-colored (the grid is a TListView, not the TRichEdit).
- Any change to the callers *fetch* (still `find-callers --json`, 200-row hard
  cap); only the *display* cap (15/10 + NN more) is new.

## 7. Acceptance

1. Hovering a function in the IDE shows: colored one-line signature header in
   the configured IDE font, right-aligned `unit.pas Line N`, clickable ->
   definition.
2. Parameters listed one per line with modifiers, types aligned.
3. Returns shows the mined `Result :=` RHS value(s), <=10 + "NN more".
4. Called-from shows count + 15/10 + "NN more".
5. Text is selectable and Ctrl+C copies it.
6. On dark theme, every element is readable (contrast guard verified).
7. CLI `hover --json` carries the new fields; all existing hover/returns tests
   green; self-index reindexed.
