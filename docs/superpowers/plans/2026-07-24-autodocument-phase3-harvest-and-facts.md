# Auto-Document Phase 3 -- Provenance, Comment Harvesting, Output Quality, Four New Facts

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every doc tag drag-lint emits self-identifying (so it can be refreshed or stripped exactly), promote existing hand-written `//` prose into DocInsight `<summary>` tags, fix four output-quality defects the YADF rollout exposed, and add four new index-time analysis facts (schema v18 -> v19).

**Architecture:** Unchanged from Phase 2 in shape. Index-time analyses materialize into `symbol_facts`; one shared formatter (`TDocRegions.FormatPhase2FactLines`) renders them for both `document` and `hover`; the document writer only ever rewrites inside a doc region. Phase 3 adds two things to that shape: (1) a single uniform provenance marker `<!-- drag-lint:auto -->` emitted immediately after every opening tag the engine writes, which replaces three inconsistent ownership mechanisms and enables a new exact `document --strip`; and (2) a *document-time* (not index-time) comment harvester in `DRagLint.Doc.Facts` that reads the source file, finds the human `//` block adjacent to a declaration or its implementation, and feeds its text into the merge as a managed `<summary>`.

**Tech Stack:** Delphi 13 (Studio 37), Win64 CLI, SQLite via `DRagLint.Storage.SQLite`, tree-sitter parse via `TAstParseCache`. Tests are PowerShell 7 runners under `tests/autodoc/` driving the built exe.

**Spec:** `docs/superpowers/specs/2026-07-24-autodocument-phase3-harvest-and-facts-design.md` (APPROVED). Section references below (§3.4.1, §4a, ...) point into it.

## Global Constraints

- All `.pas`/`.dfm`: **strict 7-bit ASCII, CRLF, no BOM**. DocInsight (`///`) spec-comments required on every new public declaration. A `{ }` comment must not contain `{`, `}` or `...`.
- **Deterministic, no AI, idempotent.** Running `document --apply` twice must produce a zero-byte diff. **Absence over wrong** -- omit a fact rather than emit one that might be false.
- **Copy, never move.** Outside the doc region it rewrites, the engine never deletes a source line -- not code, not an ordinary comment.
- Build: `build/build_draglint_win64.bat` run from **PowerShell `Start-Process -Wait`** with output redirected to a log; then read the log and confirm `BUILD_EXITCODE=0` and no `[dcc] Error`. Never `cmd.exe /c build.bat` from the Bash tool (hangs). Never the MCP build tool (no `rsvars`). Kill orphan `drag-lint.exe` / `bds.exe` first -- a file lock makes the deploy copy fail **silently** and you then test a stale exe.
- The built exe deploys to `third_party/dll-win64/drag-lint.exe`; every test runner takes `-Exe` defaulting to that path.
- **Index-time facts require a reindex.** Any test asserting a `symbol_facts`-derived line must rebuild the exe *and* re-run `index` on its fixture.
- No `sqlite3` on PATH -- inspect DBs with `C:\Python314\python` (stdlib `sqlite3`, open with `?mode=ro`).
- **The battery is EVERY `run_*.ps1` under `tests/`, recursively -- NOT just `autodoc` + `autotest`.** Run it with `pwsh -File tests\run_battery.ps1`; it enumerates dynamically and **prints its own denominator**, which is the only statement of the count that cannot go stale -- do not quote a number here. See `tests/README.md`. This line used to read "autodoc + hover, 31 tests", and that understatement is exactly how six tasks in a row reported green while eight runners outside those two suites were red -- one of them broken by this phase's own Task 3.
  - **Green bar, from T3e until T3i lands:** the two `tests/callresolve` runners (`run_ambiguous_calls`, `run_calledfrom_resolved`) are the **only** tolerated failures. They are register item **E1** -- `member-access` refs counted as unresolved call sites, pre-existing since `9d7e641` (2026-07-10) and owned by the inserted task **T3i**. **Any other non-pass blocks the commit.**
  - **After T3i lands: the whole battery must pass, with no exceptions.** T3i fixes caller RESOLUTION; T4 then fixes caller RENDERING. Delete this sub-bullet when T3i is done.
- Uncertainty convention: ` ?` suffix; lists capped with ` (+N more)`.
- The tree-sitter self-lint PostToolUse hook reports FALSE errors on generic-heavy `.pas` -- trust `dcc64`, not the hook.

---

## File structure

**Modified:**

- `src/doc/DRagLint.Doc.Regions.pas` -- the centre of gravity. Gains `AUTO_MARK` constant; `EmitTagged` learns to inject the marker; `IsManagedDesc` becomes marker-based; the `StartsText('Observed:')` sniff is deleted; empty tags are suppressed; `JoinRefs` gets the mixed-only `?` rule; `RenderFactsBlock` selects `Called from:` vs `Used by:` by symbol kind; `FormatPhase2FactLines` grows four new lines; `MergeComment` accepts the harvested summary.
- `src/doc/DRagLint.Doc.Facts.pas` -- `TDocFacts` gains `HarvestedSummary`, `HarvestedRemarks`, `MutatesParams`, `UiAffinity`, `Touches`, `Wiring`, `SymbolKind`; `TDocFactsBuilder.Build` reads the four new columns and calls the harvester.
- `src/doc/DRagLint.Doc.Harvest.pas` -- **new unit** (see below); the spec puts harvesting "in `DRagLint.Doc.Facts`", but that unit is already 59 KB / ~1600 lines and the harvester is a self-contained text-scanner with a large test surface. Splitting by responsibility keeps both files reviewable; `Doc.Facts` `uses` it, exactly as it already `uses DRagLint.Doc.SymbolFacts`.
- `src/doc/DRagLint.Doc.SymbolFacts.pas` -- four new index-time analyses + the curated name lists; `AnalyzeReturnsOwner` investigated (§4d).
- `src/doc/DRagLint.Doc.Strip.pas` -- **new unit**: the `--strip` engine (marker-keyed tag + facts-region removal producing `TTextEdit`s).
- `src/doc/DRagLint.Doc.Batch.pas` -- `TDocBatchOptions.Strip`; batch modes route to the strip engine.
- `src/core/DRagLint.Core.Model.pas` -- `TSymbolFacts` gains four fields.
- `src/storage/DRagLint.Storage.Schema.pas` -- `SCHEMA_VERSION` 18 -> 19; four columns on the `symbol_facts` DDL.
- `src/storage/DRagLint.Storage.SQLite.pas` -- `Migrate` ALTERs; `FQPutSymbolFacts` / `FQGetSymbolFacts` extended by four columns.
- `src/cli/DRagLint.CLI.pas` -- `--strip` flag + routing; `selftest harvest` subverb; `--help` text; `VERSION` bump.

**Created (tests):** `tests/autodoc/run_doc_p3_*.ps1` + fixtures under `tests/autodoc/fixtures/docp3/`.

**Read before implementing:** `src/doc/DRagLint.Doc.Regions.pas` in full (602 lines -- it is the file most tasks touch), `TSymbolFactsAnalyzer.Analyze` (`DRagLint.Doc.SymbolFacts.pas:1932`), `AnalyzeReadsWrites` (`:574`) as the template for a new AST analysis, and `tests/autodoc/run_doc_p2_complexity.ps1` as the template for a runner.

---

## Task 1: Uniform provenance marker; delete the content sniff

**Files:**
- Modify: `src/doc/DRagLint.Doc.Regions.pas` (constants, `IsManagedDesc`, `EmitTagged`, `MergeComment`)
- Test: `tests/autodoc/run_doc_p3_provenance.ps1`, fixture `tests/autodoc/fixtures/docp3/provenance.pas`

**Interfaces:**
- Produces: `AUTO_MARK = '<!-- drag-lint:auto -->'` (exported from `DRagLint.Doc.Regions`); `TDocRegions.IsManagedText(const S: string): Boolean` -- True when `S` begins with `AUTO_MARK` after trimming; `TDocRegions.StripMark(const S: string): string` -- removes a leading `AUTO_MARK`. Tasks 2, 3 and 7 all key off these.
- Consumes: nothing.

Existing state to change (read `DRagLint.Doc.Regions.pas` first):
`AUTO_PARAM` is a *trailing* marker on `<param>` lines that the doc parser strips, so it does not survive a round-trip; `IsManagedDesc` re-derives "managed" from content (empty or `'TODO: describe.'`); `<returns>` is additionally sniffed with `StartsText('Observed:', ...)` at `:488` and `:564`; `<summary>` has no marker at all.

New rule: the marker goes **immediately after the opening tag**, so it survives as the first characters of the tag's text content and the parser preserves it.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_provenance.ps1`.

Fixture `tests/autodoc/fixtures/docp3/provenance.pas`:

```pascal
unit provenance;

interface

function Marked(const AText: string): Integer;

/// <summary>Hand-written and must survive verbatim.</summary>
/// <returns>Observed: this is hand-written prose that merely starts with the word.</returns>
function HandWritten: Integer;

implementation

function Marked(const AText: string): Integer;
begin
  Result := Length(AText);
end;

function HandWritten: Integer;
begin
  Result := 1;
end;

end.
```

Runner asserts, after `index` then `document --unit --apply`:
1. `Marked`'s emitted `<param name="AText">` line contains exactly one `<!-- drag-lint:auto -->`, positioned immediately after `<param name="AText">`.
2. `Marked`'s emitted `<returns>` line contains exactly one `<!-- drag-lint:auto -->` immediately after `<returns>`.
3. `HandWritten`'s `<summary>` and `<returns>` are **byte-identical to the fixture** -- no marker added, and the `Observed:`-prefixed hand-written returns is NOT adopted, rewritten, or duplicated into a `Returns:` fact line.
4. Idempotency: reindex + a second `--apply` leaves the file byte-identical.
5. Every emitted `///` line is 7-bit ASCII.

Use `Get-DocBlockAbove` from `run_doc_p2_complexity.ps1` verbatim (copy the function; the runners are standalone by convention).

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_provenance.ps1`
Expected: assertions 1-3 FAIL (no marker emitted anywhere; `HandWritten`'s `<returns>` is rewritten to empty because `StartsText('Observed:')` classifies it as managed).

- [ ] **Step 3: Implement.**

In the `const` block of `DRagLint.Doc.Regions.pas`:

```pascal
const
  AUTO_BEGIN = '<!-- drag-lint:auto BEGIN -->';
  AUTO_END   = '<!-- drag-lint:auto END -->';
  /// Uniform provenance marker (v(ADP3 T1)). Emitted immediately after the
  /// OPENING tag of every <summary>/<param>/<returns> the engine writes, so the
  /// marker becomes the first characters of the tag's text content and survives
  /// the doc parser's round-trip (unlike the legacy trailing AUTO_PARAM, which
  /// the parser stripped). It is an HTML comment, so DocInsight tooltips do not
  /// render it. A tag WITHOUT this marker is hand-written, full stop -- there is
  /// no content-based fallback (the pre-v(ADP3) StartsText('Observed:') sniff is
  /// deleted, see MergeComment).
  AUTO_MARK  = '<!-- drag-lint:auto -->';
  /// Legacy trailing param marker. Still RECOGNIZED when reading an old
  /// comment so a pre-v(ADP3) file self-heals on the next run; never EMITTED.
  AUTO_PARAM = '<!-- drag-lint:auto param -->';
```

Add to `TDocRegions`' public section, with DocInsight comments:

```pascal
    /// <summary>True when S is engine-emitted (managed) tag content: its text
    /// begins with AUTO_MARK. This is the ONLY managed test as of v(ADP3 T1) --
    /// ownership is marker-keyed, never content-keyed, so a human whose prose
    /// happens to start with 'Observed:' or read 'TODO: describe.' is no longer
    /// silently adopted.</summary>
    class function IsManagedText(const S: string): Boolean;
    /// <summary>Returns S with a leading AUTO_MARK (and any whitespace before
    /// it) removed; S unchanged when it carries no marker. Used to recover the
    /// previously-emitted text for a drift comparison.</summary>
    class function StripMark(const S: string): string;
```

Implementations:

```pascal
class function TDocRegions.IsManagedText(const S: string): Boolean;
begin
  Result:= StartsStr(AUTO_MARK, TrimLeft(S));
end;

class function TDocRegions.StripMark(const S: string): string;
begin
  Result:= TrimLeft(S);
  if StartsStr(AUTO_MARK, Result) then
    Result:= Copy(Result, Length(AUTO_MARK) + 1, MaxInt);
end;
```

Change `IsManagedDesc` to recognize BOTH the new marker and the two legacy forms, and add a comment saying the legacy arms exist only for self-healing pre-v(ADP3) files:

```pascal
function IsManagedDesc(const S: string): Boolean;
begin
  // v(ADP3 T1): marker-keyed. The two legacy arms (empty text, and the
  // 'TODO: describe.' sentinel older builds emitted) are retained ONLY so a
  // file written by a pre-v(ADP3) build self-heals on its next run; new output
  // always carries AUTO_MARK. A whitespace-only tag with NO marker is treated
  // as managed here for backward compatibility, but Task 3 keeps it in the file
  // rather than deleting it -- see the empty-tag rules there.
  Result:= TDocRegions.IsManagedText(S) or (Trim(S) = '')
        or SameText(Trim(S), 'TODO: describe.');
end;
```

In `MergeComment`:
- **Delete** `and (not StartsText('Observed:', Trim(AExisting.ReturnsText)))` from the `IncludeReturns` expression (line ~488) and delete `or StartsText('Observed:', Trim(Ret))` from the returns-fill condition (line ~564). Replace the block comment above `IncludeReturns` -- it documents the sniff -- with an explanation that ownership is now marker-keyed.
- Every engine-emitted tag gains the marker. Fresh path (`not AExisting.HasContent`):

```pascal
      Sb.AppendLine(APrefix + '<summary>' + AUTO_MARK + '</summary>');
      for P in ASigParams do
        Sb.AppendLine(APrefix + '<param name="' + P + '">' + AUTO_MARK + '</param>');
      if AHasReturn then
        Sb.AppendLine(APrefix + '<returns>' + AUTO_MARK + Trim(ObservedSuffix(AFacts.ReturnCases)) + '</returns>');
```

(Note the trailing `AUTO_PARAM` is gone -- the marker now lives inside the tag.)

- Repair path: where a managed `<param>`/`<returns>`/`<summary>` is re-emitted, emit `AUTO_MARK` as the leading content; where a hand-typed value is preserved, emit it unchanged with no marker. For `<summary>`, replace

```pascal
    var SummaryText: string:= AExisting.Summary;
    if IsManagedDesc(SummaryText) then SummaryText:= '';
    Sb.AppendLine(EmitTagged('<summary>', SummaryText, '</summary>'));
```

with

```pascal
    var SummaryText: string:= AExisting.Summary;
    var SummaryManaged: Boolean:= IsManagedDesc(SummaryText);
    if SummaryManaged then SummaryText:= AUTO_MARK;
    Sb.AppendLine(EmitTagged('<summary>', SummaryText, '</summary>'));
```

and for `<param>` replace both managed emissions with `'<param name="' + P + '">' + AUTO_MARK + '</param>'` (dropping the trailing `AUTO_PARAM`), and for `<returns>` set `Ret := AUTO_MARK + Trim(ObservedSuffix(AFacts.ReturnCases))` when `IsManagedDesc(Ret)`.

Note `EmitTagged` splits `AValue` on newlines and re-prefixes each line with `APrefix`; the marker is on the first line only, which is what `IsManagedText` expects.

Update the DocInsight comment on `MergeComment` to describe the marker contract and the removal of the sniff.

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_provenance.ps1`
Expected: all assertions PASS.

Then the regression gate: `pwsh -File tests\autodoc\run_doc_idempotent.ps1`, `run_doc_generate.ps1`, `run_doc_extend.ps1`, `run_doc_stale_param.ps1`, `run_doc_returns_merge.ps1`, `run_doc_multiline.ps1`. These pin the exact emitted text and **will** need their expected strings updated to include `AUTO_MARK`; that is expected churn from this task, not a regression -- update the expectation, never the engine, and note each change in the commit message.

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.Regions.pas tests/autodoc/run_doc_p3_provenance.ps1 tests/autodoc/fixtures/docp3/provenance.pas tests/autodoc/run_doc_*.ps1
git commit -m "feat(doc): uniform <!-- drag-lint:auto --> provenance marker; delete the Observed: content sniff (Phase 3 T1)"
```

---

## Task 2: `document --strip`

**Files:**
- Create: `src/doc/DRagLint.Doc.Strip.pas`
- Modify: `src/doc/DRagLint.Doc.Batch.pas` (`TDocBatchOptions.Strip` + routing), `src/cli/DRagLint.CLI.pas` (`--strip` parse at ~line 755, routing in `DoDocumentUnit`/`DoDocumentProject`/`DoDocumentAll`/`DoDocument`, `--help` at ~line 422-426)
- Test: `tests/autodoc/run_doc_p3_strip.ps1`, fixture `tests/autodoc/fixtures/docp3/strip.pas`

**Interfaces:**
- Consumes: Task 1's `AUTO_MARK`, `TDocRegions.IsManagedText`, and the existing `AUTO_BEGIN`/`AUTO_END`.
- Produces:

```pascal
type
  TStripResult = record
    FilePath   : string;
    TagsRemoved: Integer;  // marked <summary>/<param>/<returns> lines dropped
    BlocksRemoved: Integer; // AUTO_BEGIN..AUTO_END regions dropped
    Edits      : TArray<TTextEdit>;
  end;

  TDocStripper = class
  public
    class function StripFile(const AFilePath: string): TStripResult;
  end;
```

Task 9 (harvest round-trip) and the rollout (Task 17) both call `--strip`.

`StripFile` works on **raw source lines**, not the parsed doc model -- it must be exact and must not depend on a symbol being in the index.

Removal rules, applied only to lines whose trimmed form starts with `///`:
1. A line containing `AUTO_MARK` inside a `<summary>`/`<param ...>`/`<returns>` tag: drop the line, and any following `///` continuation lines up to and including the one carrying the matching close tag (a marked tag can span lines via `EmitTagged`).
2. A line containing `AUTO_BEGIN`: drop it through the line containing `AUTO_END` inclusive.
3. Legacy: a line whose trimmed form ends with `AUTO_PARAM` -- drop it (pre-v(ADP3) managed param).
4. If dropping leaves a `<remarks>`/`</remarks>` pair with nothing between them, drop that pair too.
5. If dropping leaves the doc region with no `///` lines at all, drop the whole (now empty) region including its blank remainder, leaving no stray blank line.

Everything else -- unmarked tags, prose, code, ordinary `//` and `{ }` comments -- is byte-identical afterwards.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_strip.ps1`.

Fixture `tests/autodoc/fixtures/docp3/strip.pas`:

```pascal
unit strip;

interface

// An ordinary implementation-style comment that must survive untouched.
/// <summary>Hand-written summary; must survive.</summary>
/// <param name="AValue">Hand-written param desc; must survive.</param>
/// <remarks>Hand-written remarks prose; must survive.</remarks>
function Mixed(AValue: Integer): Integer;

function Plain(AValue: Integer): Integer;

implementation

function Mixed(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function Plain(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

end.
```

Runner:
1. Snapshot the fixture bytes as `$before`.
2. `index`, then `document --unit --apply` (writes marked tags + facts blocks onto both routines and merges into `Mixed`'s existing region).
3. Assert the file now differs from `$before`.
4. `document --unit <target> --strip --apply`.
5. Assert the file is **byte-identical to `$before`** (this is the round-trip: `pre` -> `apply` -> `strip` == `pre`).
6. Assert a second `--strip --apply` is a no-op (byte-identical, exit 0).
7. Assert `--strip` without `--apply` writes nothing (dry-run) and reports the counts on stdout.
8. Assert the ordinary `//` comment line and both hand-written tags are present in the stripped file.

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_strip.ps1`
Expected: FAIL at step 4 -- `document` rejects the unknown `--strip` flag / ignores it, so the file still carries engine output.

- [ ] **Step 3: Implement.**

Create `src/doc/DRagLint.Doc.Strip.pas` with the interface above. Read the file with the same ANSI reader `DRagLint.Doc.Document` uses (`System.IOUtils` + the existing encoding helper -- match `TDocumenter.BuildForSymbol`'s read so CRLF and ANSI are preserved), compute line-range deletions, and express them as `TTextEdit`s so `TTextEditApplier.Apply` performs the I/O exactly as the `document` path does (backups via `.bak` unless `--no-backup`).

In `DRagLint.Doc.Batch.pas`, add to `TDocBatchOptions`:

```pascal
    /// <summary>v(ADP3 T2): --strip. When True the batch REMOVES engine output
    /// (every AUTO_MARK-carrying tag and every AUTO_BEGIN..AUTO_END region)
    /// instead of generating it. Hand-written tags, code and ordinary comments
    /// are untouched. Mutually exclusive with Stubs.</summary>
    Strip: Boolean;
```

`TDocBatch.DocumentUnit` / `.DocumentProject` / `.DocumentAll`: when `Opts.Strip`, call `TDocStripper.StripFile` per file instead of `TDocumenter.BuildForSymbol` per symbol, and report `stripped: N tags, M blocks in <file>`.

In `DRagLint.CLI.pas`: parse `else if A = '--strip' then Result.DocStrip := True` alongside `--stubs` (~line 755-795); add `DocStrip: Boolean; // document [...] --strip` to `TArgs` next to `DocStubs` (~line 285); set `Opts.Strip := AArgs.DocStrip` in all three `DoDocument*` functions; reject `--strip` combined with `--stubs` with exit 2 and a clear message. Add to `--help`:

```pascal
  Writeln('  drag-lint document --unit <file.pas> --strip [--apply|--no-backup] [--db PATH]   - REMOVE drag-lint-generated doc tags/blocks (marker-keyed; hand-written docs untouched)');
```

Also allow `--strip` on `--qname` (single symbol) by stripping only the doc region above that symbol's declaration line.

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_strip.ps1`
Expected: all assertions PASS, especially the byte-identical round-trip.

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.Strip.pas src/doc/DRagLint.Doc.Batch.pas src/cli/DRagLint.CLI.pas tests/autodoc/run_doc_p3_strip.ps1 tests/autodoc/fixtures/docp3/strip.pas
git commit -m "feat(doc): document --strip -- exact marker-keyed removal of engine output (Phase 3 T2)"
```

---

## Task 3: Omit empty tags

**Files:**
- Modify: `src/doc/DRagLint.Doc.Regions.pas` (`MergeComment`)
- Test: `tests/autodoc/run_doc_p3_emptytags.ps1`, fixture `tests/autodoc/fixtures/docp3/emptytags.pas`

**Interfaces:**
- Consumes: Task 1's `AUTO_MARK` / `IsManagedText`.
- Produces: no new API. Behaviour: `<summary>` / `<param>` / `<returns>` are emitted only with content.

Rules (§4a):
- Emit `<summary>` only when there is content (hand-written, or harvested once Task 7 lands). A managed-and-empty summary is **not emitted at all**.
- Emit `<param name="X">` only when it has a hand-written description. A managed param with no description is not emitted. (Consequence: fresh comments no longer carry a `<param>` skeleton. That is the intent -- §2 rules out `<param>` harvesting, so an empty param tag can never gain content.)
- Emit `<returns>` only when hand-written, or when `ObservedSuffix` yields non-empty mined cases.
- On rewrite, a whitespace-only tag **carrying `AUTO_MARK`** is dropped. A whitespace-only tag **without** the marker is hand-written -- a human holding the slot open -- and is preserved verbatim.
- A tag with content is never removed, whatever its origin.
- If suppression leaves the merged comment with zero lines, `MergeComment` returns `''` and the caller emits no comment at all.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_emptytags.ps1`.

Fixture `tests/autodoc/fixtures/docp3/emptytags.pas`:

```pascal
unit emptytags;

interface

function NoDocs(AValue: Integer): Integer;

/// <summary></summary>
/// <param name="AValue"></param>
function HumanBlanks(AValue: Integer): Integer;

implementation

function NoDocs(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function HumanBlanks(AValue: Integer): Integer;
begin
  Result := AValue;
  NoDocs(AValue);
end;

end.
```

Assertions after `index` + `document --unit --apply`:
1. `NoDocs`'s emitted block contains **no** `<summary>` tag and **no** `<param` tag (nothing to say about either).
2. `NoDocs` DOES get a `<returns>` -- it has mined return cases (`Result := AValue`) -- and it carries `AUTO_MARK`.
3. `NoDocs` still gets its facts block (it is called from `HumanBlanks`, so `Called from:` exists) -- proving suppression removed only the empty tags, not the whole comment.
4. `HumanBlanks`'s hand-written empty `<summary></summary>` and `<param name="AValue"></param>` are **still present and unmarked** -- they carry no marker, so they are human slots and survive.
5. Idempotency: reindex + second `--apply` is byte-identical.

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_emptytags.ps1`
Expected: assertions 1 and 4 FAIL -- today the engine emits `<summary><!-- drag-lint:auto --></summary>` and a marked empty `<param>` for `NoDocs`, and blanks/re-emits `HumanBlanks`' human slots (`IsManagedDesc` classifies empty-without-marker as managed).

- [ ] **Step 3: Implement.**

In `MergeComment`, fresh path: guard each emission.

```pascal
      // v(ADP3 T3): omit-when-empty. A tag with nothing to say is not written
      // at all -- an empty <summary> renders as a BLANK DocInsight tooltip,
      // which is strictly worse than no tooltip. The FRESH path has no
      // hand-written content by definition, so <summary> is emitted only when
      // the harvester (v(ADP3 T7)) supplied text, and <param> never (see the
      // spec's out-of-scope note on <param> harvesting).
      if AFacts.HarvestedSummary <> '' then
        Sb.AppendLine(EmitTagged('<summary>' + AUTO_MARK, AFacts.HarvestedSummary, '</summary>'));
      if AHasReturn then
      begin
        var Obs: string:= Trim(ObservedSuffix(AFacts.ReturnCases));
        if Obs <> '' then
          Sb.AppendLine(APrefix + '<returns>' + AUTO_MARK + Obs + '</returns>');
      end;
```

(`AFacts.HarvestedSummary` is added by Task 7; until then it is always `''`. Add the field as an empty `string` on `TDocFacts` **in this task** so the code compiles and the guard is real -- Task 7 only fills it.)

Repair path: distinguish the three cases per tag.

```pascal
    // v(ADP3 T3): three-way classification per tag.
    //   marked + empty  -> ENGINE's own empty stub: drop it entirely.
    //   unmarked + empty -> a HUMAN holding the slot open: preserve verbatim.
    //   any content      -> preserve (hand-written) or regenerate (marked).
    var SummaryRaw : string := AExisting.Summary;
    var SummaryMark: Boolean:= TDocRegions.IsManagedText(SummaryRaw);
    var SummaryBody: string := Trim(TDocRegions.StripMark(SummaryRaw));
    if SummaryMark then
    begin
      // engine-owned: refresh from the harvest, or drop when the harvest is empty
      if AFacts.HarvestedSummary <> '' then
        Sb.AppendLine(EmitTagged('<summary>' + AUTO_MARK, AFacts.HarvestedSummary, '</summary>'));
    end
    else if SummaryRaw <> '' then      // hand-written, including a deliberate blank slot
      Sb.AppendLine(EmitTagged('<summary>', SummaryRaw, '</summary>'))
    else if AFacts.HarvestedSummary <> '' then
      Sb.AppendLine(EmitTagged('<summary>' + AUTO_MARK, AFacts.HarvestedSummary, '</summary>'));
```

Note the middle arm tests `SummaryRaw <> ''` (the raw parsed text), not `SummaryBody` -- a hand-written `<summary></summary>` parses to `''`, so distinguishing "human wrote an empty tag" from "no tag at all" needs the parser's own presence flag. If `TParsedDoc` does not expose per-tag presence, add `HasSummaryTag: Boolean` to it (`src/core/DRagLint.Core.Model.pas:312`) and set it in `DRagLint.Parser.DocComments`; the same is needed for `<returns>`. **Check this first** -- it may already be derivable, and if it is, use what exists.

Apply the same three-way logic to `<param>` (drop marked-and-empty; preserve unmarked-and-empty; preserve hand-typed) and `<returns>` (marked -> refill from `ObservedSuffix`, dropping when empty; unmarked -> preserve verbatim).

Finally, if `Sb` ends up empty, `Result := ''`. Verify `TDocumenter.BuildForSymbol` treats an empty merge as "no edits" (`daUnchanged`) rather than writing an empty comment; add the guard there if it does not.

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_emptytags.ps1`, then the regression set from Task 1 Step 4 (several pin `<summary></summary>` and will need their expectations updated).

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.Regions.pas src/doc/DRagLint.Doc.Facts.pas src/core/DRagLint.Core.Model.pas src/parser/DRagLint.Parser.DocComments.pas tests/autodoc/run_doc_p3_emptytags.ps1 tests/autodoc/fixtures/docp3/emptytags.pas tests/autodoc/run_doc_*.ps1
git commit -m "feat(doc): omit empty summary/param/returns tags; drop marked stubs, keep human slots (Phase 3 T3)"
```

---

## Task 4: Caller-line render fixes -- mixed-only `?`, and `Used by:` for non-callables

**Files:**
- Modify: `src/doc/DRagLint.Doc.Regions.pas` (`RenderFactsBlock`'s nested `JoinRefs`, and the `Called from:` emission), `src/doc/DRagLint.Doc.Facts.pas` (`TDocFacts.SymbolKind`)
- Test: `tests/autodoc/run_doc_p3_callerline.ps1`, fixture `tests/autodoc/fixtures/docp3/callerline.pas`

**Interfaces:**
- Consumes: the existing `TDocFactRef.Confidence` field (`DRagLint.Doc.Facts.pas:28`).
- Produces: `TDocFacts.SymbolKind: TSymbolKind` -- the documented symbol's own kind, populated by `TDocFactsBuilder.Build` from `ASym.Kind`. The renderer selects the caller-line verb from it.

Rules:
- §4b: emit ` ?` **only when the list is mixed**. All-certain -> no markers (unchanged). All-uncertain -> no markers (**new**). Mixed -> markers on the uncertain entries only (unchanged). Ordering (certain first) is unchanged.
- §4c: for a symbol that is not callable, the label is `Used by:`, not `Called from:`. Callable kinds are `skFunction`, `skProcedure`, `skMethod`, `skConstructor`, `skDestructor`; everything else (`skClass`, `skRecord`, `skInterface`, `skType`, `skConst`, `skVar`, ...) renders `Used by:`. The list contents, cap, `(+N more)` suffix and the §4b `?` rule are all unchanged -- only the label differs.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_callerline.ps1`.

Fixture `tests/autodoc/fixtures/docp3/callerline.pas`:

```pascal
unit callerline;

interface

type
  TPoint2 = record
    X: Integer;
    Y: Integer;
  end;

function MakePoint(AX, AY: Integer): TPoint2;
function SumPoint(const APoint: TPoint2): Integer;

implementation

function MakePoint(AX, AY: Integer): TPoint2;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function SumPoint(const APoint: TPoint2): Integer;
begin
  Result := APoint.X + APoint.Y;
end;

end.
```

Assertions after `index` + `document --unit --apply`:
1. `TPoint2`'s managed block contains `Used by:` and does **not** contain `Called from:`.
2. `MakePoint`'s and `SumPoint`'s blocks (whichever has callers) use `Called from:`, not `Used by:`.
3. **No ` ?` marker appears anywhere in the file** -- in a single-unit fixture every caller resolves the same way, so the list is uniform and §4b suppresses the marker. (This is the direct regression guard for the 49-of-49 saturation.)
4. Mixed case: a second scenario in the same runner writes a scratch unit whose caller set is genuinely mixed -- one caller resolved via a real `call_edges` row and one name-only match from a second unit indexed into the same DB -- and asserts that exactly the unresolved entry carries ` ?` while the resolved one does not. If constructing a genuinely mixed set proves impractical from a fixture, assert instead via `--json` on `document --qname` that the rendered line's marker count equals zero when `Confidence` is uniform and equals the uncertain count when it is not; **do not** delete the mixed assertion -- an all-uncertain-only test cannot distinguish "suppressed correctly" from "marker never emitted".
5. Idempotency: reindex + second `--apply` byte-identical.

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_callerline.ps1`
Expected: assertion 1 FAILs (`TPoint2` renders `Called from:`) and assertion 3 FAILs (` ?` present on every entry).

- [ ] **Step 3: Implement.**

Add to `TDocFacts` in `DRagLint.Doc.Facts.pas`:

```pascal
    /// <summary>v(ADP3 T4): the documented symbol's OWN kind, copied from
    /// ASym.Kind by Build. The renderer selects the caller-line verb from it:
    /// a callable kind reads 'Called from:', everything else (a type, record,
    /// interface, constant) reads 'Used by:' -- those references are usages,
    /// not calls. Nothing else keys off this field.</summary>
    SymbolKind       : TSymbolKind;
```

Set `Result.SymbolKind := ASym.Kind;` early in `TDocFactsBuilder.Build`.

In `RenderFactsBlock`, rewrite the nested `JoinRefs`:

```pascal
  // v(ADP3 T4): the ' ?' uncertainty marker is emitted ONLY when the list is
  // MIXED. A marker present on EVERY entry distinguishes nothing -- on the
  // YADF rollout it fired 49 times out of 49 -- so a uniformly-uncertain list
  // renders plain, exactly like a uniformly-certain one. The information that
  // survives is comparative: within one list, which entries are the weaker
  // ones. (The ROOT cause -- weak call_edges resolution in project DBs -- is
  // the D5 follow-up; this changes only the rendering.) The Facts builder's
  // certain-before-uncertain ordering is retained.
  function JoinRefs(const A: TArray<TDocFactRef>): string;
  var i: Integer; AnyCertain, AnyUncertain, Mixed: Boolean;
  begin
    Result:= '';
    AnyCertain  := False;
    AnyUncertain:= False;
    for i:= 0 to High(A) do
      if (A[i].Confidence = '') or SameText(A[i].Confidence, 'certain') then AnyCertain:= True
      else AnyUncertain:= True;
    Mixed:= AnyCertain and AnyUncertain;
    for i:= 0 to High(A) do
    begin
      if i > 0 then Result:= Result + ', ';
      Result:= Result + EscXml(A[i].Display) + ' (' + EscXml(A[i].Location) + ')';
      if Mixed and not ((A[i].Confidence = '') or SameText(A[i].Confidence, 'certain')) then
        Result:= Result + ' ?';
    end;
  end;
```

And the caller line:

```pascal
    if Length(AFacts.CalledFrom) > 0 then
    begin
      // v(ADP3 T4): 'Called from:' is only correct for a CALLABLE symbol. A
      // type/record/interface/constant is USED, not called -- the YADF rollout
      // rendered 'TToken (a record) ... Called from: ...'. Same list, same cap,
      // same '?' rule; only the label is kind-selected.
      var RefVerb: string;
      if AFacts.SymbolKind in [skFunction, skProcedure, skMethod, skConstructor, skDestructor] then
        RefVerb:= 'Called from: '
      else
        RefVerb:= 'Used by: ';
      Sb.AppendLine(APrefix + RefVerb + JoinRefs(AFacts.CalledFrom) + MoreSuffix(Length(AFacts.CalledFrom), AFacts.CalledFromTotal));
    end;
```

Confirm the exact `TSymbolKind` enumerator names in `src/core/DRagLint.Core.Model.pas` before writing the set -- use what is declared there, not the names above, if they differ.

Update `RenderFactsBlock`'s DocInsight `<summary>` to describe both rules.

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_callerline.ps1`, plus `tests\autotest\run_doc_returns_and_callers.ps1` and `tests\autodoc\run_doc_cap.ps1` (both pin caller-line text).

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.Regions.pas src/doc/DRagLint.Doc.Facts.pas tests/autodoc/run_doc_p3_callerline.ps1 tests/autodoc/fixtures/docp3/callerline.pas
git commit -m "feat(doc): '?' marker only on mixed caller lists; 'Used by:' for non-callable symbols (Phase 3 T4)"
```

---

## Task 5: Ownership-yield investigation (TIMEBOXED)

**Files:**
- Investigate: `src/doc/DRagLint.Doc.SymbolFacts.pas:1842` (`AnalyzeReturnsOwner`), `ClassifyReturnSite`, `WalkReturnsOwnerSites`, `IsReferenceTypeName`, `TRoutineVarTable`
- Modify (only if a genuine bug is found): the same unit
- Create either: `tests/autodoc/run_doc_p3_owner_alias.ps1` + fixture (bug path), OR `docs/lint/2026-07-24-ownership-yield-finding.md` (no-bug path)

**Interfaces:** none new either way.

**REQUIRED SUB-SKILL:** `superpowers:systematic-debugging`.

**This task is timeboxed and must not hold the phase open.** Outcome is exactly one of: (a) a genuine bug -> fix with a regression test; (b) correct conservative behaviour, or a real cause with no cheap fix -> write the finding to `docs/lint/2026-07-24-ownership-yield-finding.md`, add a `Follow-ups` line to the spec, commit that, and move on. **Do not loosen the unanimity gate as part of this task.**

The known reproduction: `YADF.Tokens.LoadTokensFromString` contains `Result := TTokenList.Create` (the mined `Returns:` line proves the site was seen) yet `returns_owner` is empty. `TTokenList = TList<TToken>` -- an aliased generic. Suspect list, in order: `ClassifyReturnSite` returning `unknown` for a constructor call on an aliased generic type name; `IsReferenceTypeName` failing to resolve the alias to a class; the `Disposed` early-exit; the `ResultIdx` lookup in `TRoutineVarTable`.

- [ ] **Step 1: Reproduce in a fixture.**

Create `tests/autodoc/fixtures/docp3/owner_alias.pas`:

```pascal
unit owner_alias;

interface

uses
  System.Generics.Collections;

type
  TThing = class
  end;

  TThingList = TList<TThing>;

function MakeDirect: TObjectList<TThing>;
function MakeAliased: TThingList;

implementation

function MakeDirect: TObjectList<TThing>;
begin
  Result := TObjectList<TThing>.Create;
end;

function MakeAliased: TThingList;
begin
  Result := TThingList.Create;
end;

end.
```

Index it and read `symbol_facts.returns_owner` for both routines with `C:\Python314\python`. Expected observation: `MakeDirect` may yield `new`, `MakeAliased` yields `''`. Record the actual values -- do not assume.

- [ ] **Step 2: Find which gate rejects it.**

Add temporary `Writeln(ErrOutput, ...)` tracing (or step through with the existing `selftest` harness) at each early `Exit` in `AnalyzeReturnsOwner` to identify the exact gate. Read `ClassifyReturnSite` and `IsReferenceTypeName` before concluding.

- [ ] **Step 3: Decide, within the timebox.**

If the cause is a genuine bug with a contained fix (e.g. `IsReferenceTypeName` not following a type alias through `type X = Y;`): fix it, keep the unanimity rule intact, and turn the fixture into `tests/autodoc/run_doc_p3_owner_alias.ps1` asserting `Owns returned: new (caller owns)` on `MakeAliased`.

Otherwise: write `docs/lint/2026-07-24-ownership-yield-finding.md` recording the exact gate, the evidence, why it is correct or why the fix is not cheap, and what a future cycle would need to change. Add a line to §10 of the spec. **Remove the temporary tracing** either way.

- [ ] **Step 4: Verify.**

Bug path -- Run: `pwsh -File tests\autodoc\run_doc_p3_owner_alias.ps1`; Expected: PASS. Then `pwsh -File tests\autodoc\run_doc_p2_owner.ps1`; Expected: still PASS (the unanimity and abstention cases are unchanged).
No-bug path -- Run: `pwsh -File tests\autodoc\run_doc_p2_owner.ps1`; Expected: PASS (nothing changed). Confirm no tracing `Writeln` survives: `git diff src/doc/DRagLint.Doc.SymbolFacts.pas` shows only the intended change (or nothing).

- [ ] **Step 5: Commit.**

Bug path:
```bash
git add src/doc/DRagLint.Doc.SymbolFacts.pas tests/autodoc/run_doc_p3_owner_alias.ps1 tests/autodoc/fixtures/docp3/owner_alias.pas
git commit -m "fix(doc): returns-owner resolves through a type alias to the underlying class (Phase 3 T5)"
```
No-bug path:
```bash
git add docs/lint/2026-07-24-ownership-yield-finding.md docs/superpowers/specs/2026-07-24-autodocument-phase3-harvest-and-facts-design.md
git commit -m "docs(doc): record the returns-owner yield finding; defer the fix (Phase 3 T5, timeboxed)"
```

---

## Task 6: Harvester -- boundary scan and acceptance guards

**Files:**
- Create: `src/doc/DRagLint.Doc.Harvest.pas`
- Modify: `src/cli/DRagLint.CLI.pas` (add a `selftest harvest` subverb)
- Test: `tests/autodoc/run_doc_p3_harvest_scan.ps1`, fixtures `tests/autodoc/fixtures/docp3/harvest_scan.pas`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Tasks 7-9):

```pascal
type
  /// <summary>Why a candidate comment block was rejected, or hrAccepted.</summary>
  THarvestReason = (hrAccepted, hrNone, hrBanner, hrCommentedCode, hrTrailer,
                    hrEmpty, hrNonAscii, hrNestedBrace);

  THarvestResult = record
    Reason   : THarvestReason;
    RawLines : TArray<string>;  // the candidate comment lines, markers still on
    StartLine: Integer;         // 1-based first line of the block, 0 when none
    EndLine  : Integer;         // 1-based last line of the block, 0 when none
  end;

/// <summary>Scans UPWARD from ADeclLine (1-based, the declaration's own line)
/// over ASrcLines, accumulating comment and blank lines, and returns the
/// candidate block with an accept/reject verdict. Pure: no I/O, no index.</summary>
function HarvestScan(const ASrcLines: TArray<string>; ADeclLine: Integer): THarvestResult;
```

Scan rules (§3.4.1): accumulate comment lines (`//` runs, `{ }` and `(* *)` blocks) **and blank lines**, walking up from `ADeclLine - 1`. Stop at the first line of real code. Stop-set: another declaration (`function` / `procedure` / `constructor` / `destructor` / a field or property declaration), `end;` / `end.`, `begin`, a section keyword (`type` / `const` / `var` / `resourcestring` / `threadvar`), a unit-structure keyword (`interface` / `implementation` / `initialization` / `finalization` / `uses`), any other non-comment non-blank line, or start-of-file. Trailing blank lines at the top of the accumulated block are discarded; blank lines *between* comment paragraphs are kept (Task 7 splits on them).

A line that is already a DocInsight `///` comment is **not** a harvest candidate -- stop the scan there and return `hrNone` (the symbol already has engine or human DocInsight; harvesting into it is Task 8's precedence question, not this scan's).

Guards (§3.4):
- `hrBanner` -- every line's content, after stripping comment markers, is only separator punctuation (`-`, `=`, `*`, `_`, `#`, spaces), OR the block is a single line whose sole content is such a rule plus at most a short title. Concretely: reject when **every** line matches `^[\s\-=*_#]*$`, or when the block is 1 line and >= 60% of its non-space characters are in `-=*_#`.
- `hrCommentedCode` -- **any** line's stripped content contains `:=`, or matches `\bbegin\b` or `\bend;`, or ends with `;`.
- `hrTrailer` -- decided by the tie-breaker below, only when the scan stopped at `end;` / `end.`.
- `hrEmpty` -- stripped content is whitespace-only.
- `hrNonAscii` -- any byte >= 128 in the block.
- `hrNestedBrace` -- a `{ }`-sourced block whose promoted text would contain `{` or `}` (Pascal comments do not nest).

Trailer tie-breaker (§3.4.1), applied **only** when the stop line is `end;` / `end.`:

| Layout | Verdict |
| --- | --- |
| comment hugs `end;` (no blank line between them) AND there is a blank line between the comment and the declaration | `hrTrailer` -- reject |
| blank line after `end;` AND the comment is adjacent to the declaration | accept |
| any other combination | accept |

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_harvest_scan.ps1`.

Fixture `tests/autodoc/fixtures/docp3/harvest_scan.pas` -- one case per verdict, each with a comment naming its expected outcome:

```pascal
unit harvest_scan;

interface

// Accepted: a plain adjacent header comment.
function CaseAdjacent: Integer;

// Accepted: separated from the declaration by a blank line.

function CaseBlankGap: Integer;

// -----------------------------------------------------------------
function CaseBanner: Integer;

// Result := ComputeSomething(A, B);
function CaseCommentedCode: Integer;

function CaseNoComment: Integer;

implementation

function CaseAdjacent: Integer;
begin
  Result := 1;
end;

function CaseBlankGap: Integer;
begin
  Result := 2;
end;

function CaseBanner: Integer;
begin
  Result := 3;
end;

function CaseCommentedCode: Integer;
begin
  Result := 4;
end;
// Trailer: this note closes CaseCommentedCode above.

function CaseTrailer: Integer;
begin
  Result := 5;
end;

function CaseNoComment: Integer;
begin
  Result := 6;
end;

end.
```

(`CaseTrailer` is implementation-only on purpose -- the trailer layout the tie-breaker must reject is `end;` + comment hugging it + blank line + declaration.)

Runner drives `& $exe selftest harvest --file <fixture> --line <n>` for each case's declaration line and asserts the printed reason:

| Declaration | Expected reason |
| --- | --- |
| `CaseAdjacent` (interface) | `ACCEPTED` |
| `CaseBlankGap` (interface) | `ACCEPTED` |
| `CaseBanner` (interface) | `BANNER` |
| `CaseCommentedCode` (interface) | `COMMENTEDCODE` |
| `CaseNoComment` (interface) | `NONE` |
| `CaseTrailer` (implementation) | `TRAILER` |

Plus: for `CaseAdjacent`, assert the printed `LINES=` count is 1 and the raw text contains `plain adjacent header`. For a non-ASCII case, the runner writes a scratch copy with a Latin-1 byte in the comment and asserts `NONASCII`.

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_harvest_scan.ps1`
Expected: every case FAILs -- `selftest harvest` is an unknown subcommand (exit 2).

- [ ] **Step 3: Implement.**

Create `src/doc/DRagLint.Doc.Harvest.pas` with the interface above and full DocInsight comments on `THarvestReason`, `THarvestResult` and `HarvestScan`. Implementation is pure string work over `ASrcLines` -- **no tree-sitter parse**: the scan must work on a file that fails to parse, and the stop-set is lexically unambiguous at line granularity. Recognize a `{ }` / `(* *)` block by scanning for its opening delimiter on the accumulated run and requiring the closing delimiter within the same run.

In `DRagLint.CLI.pas`, add the `selftest harvest` subverb next to the existing `selftest` subcommands (~line 12700-12990). It reads `--file` and `--line`, loads the file's lines with the same ANSI reader the doc path uses, calls `HarvestScan`, and prints one line:

```
REASON=<ACCEPTED|NONE|BANNER|COMMENTEDCODE|TRAILER|EMPTY|NONASCII|NESTEDBRACE> LINES=<n> START=<n> END=<n>
```

followed by each raw line prefixed `RAW: `. Exit 0 on success, 2 on a missing/unreadable file.

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_harvest_scan.ps1`
Expected: all cases report their expected reason.

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.Harvest.pas src/cli/DRagLint.CLI.pas tests/autodoc/run_doc_p3_harvest_scan.ps1 tests/autodoc/fixtures/docp3/harvest_scan.pas
git commit -m "feat(doc): comment-harvest boundary scan + acceptance guards, with a selftest harvest probe (Phase 3 T6)"
```

---

## Task 7: Harvester -- text transformation and interface-side wiring

**Files:**
- Modify: `src/doc/DRagLint.Doc.Harvest.pas` (add `HarvestText`), `src/doc/DRagLint.Doc.Facts.pas` (`HarvestedSummary` / `HarvestedRemarks` + call from `Build`), `src/doc/DRagLint.Doc.Regions.pas` (`MergeComment` consumes them)
- Test: `tests/autodoc/run_doc_p3_harvest_text.ps1`, fixture `tests/autodoc/fixtures/docp3/harvest_text.pas`

**Interfaces:**
- Consumes: Task 6's `HarvestScan` / `THarvestResult`; Task 3's `HarvestedSummary` field (declared there, filled here).
- Produces:

```pascal
/// <summary>Transforms an ACCEPTED THarvestResult into DocInsight-ready text:
/// the first paragraph as the summary, the remainder as remarks prose.</summary>
procedure HarvestText(const AResult: THarvestResult; out ASummary, ARemarks: string);
```

and `TDocFacts.HarvestedRemarks: string` alongside the `HarvestedSummary` added in Task 3.

Transformation (§3.5), in order:
1. Strip comment markers (`//`, `{`, `}`, `(*`, `*)`) and normalise leading indentation (remove the common leading-whitespace prefix).
2. Split into paragraphs on blank comment lines.
3. First paragraph -> `ASummary`; remaining paragraphs -> `ARemarks`, paragraphs joined by a blank line.
4. XML-escape with `EscXml` semantics (`&` first, then `<`, `>`). `EscXml` is currently a private function in `DRagLint.Doc.Regions`'s implementation section -- **do not duplicate it**; move it to that unit's interface as `TDocRegions.EscXml` (or a unit-level `function EscXml`) and have `Doc.Harvest` `uses` it. One escaper, one behaviour.
5. Join the lines of a paragraph with a single space (they are a wrapped sentence, not separate statements), collapsing runs of whitespace.
6. Preserve strict 7-bit ASCII (the `hrNonAscii` guard already rejects anything else).

The `///` re-prefixing is **not** done here -- `MergeComment`'s `EmitTagged` already splits on newlines and re-prefixes every continuation line with `APrefix` (this is the `5ebde68` corruption fix). Return plain text with `#10` between paragraphs and let `EmitTagged` do the prefixing; the test asserts the result.

Wiring in `TDocFactsBuilder.Build`: after the symbol's file path is known, read the source lines and call `HarvestScan(Lines, ASym.StartLine)` -- the **interface declaration** line. On `hrAccepted`, call `HarvestText` and store into `Result.HarvestedSummary` / `Result.HarvestedRemarks`. Any other reason leaves both `''`. Implementation-side fallback is Task 8.

`MergeComment` consumes them: `HarvestedSummary` fills the managed `<summary>` (the Task 3 guards already reference it); `HarvestedRemarks`, when non-empty, is emitted inside `<remarks>` **above** the `AUTO_BEGIN` fence, each line carrying `AUTO_MARK` on its first line so `--strip` and the drift check can identify it.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_harvest_text.ps1`.

Fixture `tests/autodoc/fixtures/docp3/harvest_text.pas`:

```pascal
unit harvest_text;

interface

// True for a 7-bit ASCII letter (A-Z / a-z). Shared by the include-directive
// shield and unshield scans; deliberately ASCII-only.
function IsAsciiAlpha(C: Char): Boolean;

// First paragraph becomes the summary.
//
// Second paragraph becomes remarks prose. It mentions A < B & C > D so the
// XML escaping is exercised on real content.
function TwoParagraphs: Integer;

implementation

function IsAsciiAlpha(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

function TwoParagraphs: Integer;
begin
  Result := 0;
end;

end.
```

Assertions after `index` + `document --unit --apply`:
1. `IsAsciiAlpha`'s block has `<summary><!-- drag-lint:auto -->True for a 7-bit ASCII letter (A-Z / a-z). Shared by the include-directive shield and unshield scans; deliberately ASCII-only.</summary>` -- one paragraph, wrapped lines joined with single spaces.
2. **The original `//` comment is still present, unchanged** (copy, never move -- §3.2). Assert both the `//` lines and the new `///` lines exist.
3. `TwoParagraphs`: the summary is exactly the first paragraph; the second paragraph appears inside `<remarks>` and above `<!-- drag-lint:auto BEGIN -->`.
4. `<`, `>` and `&` in the second paragraph are escaped to `&lt;`, `&gt;`, `&amp;` -- and `&` is not double-escaped (no `&amp;lt;`).
5. **Every emitted line begins with `///` after its indentation** -- no interior newline reaches the file unprefixed. Assert by scanning the whole doc region.
6. The file remains strict 7-bit ASCII and CRLF-terminated.
7. Idempotency: reindex + second `--apply` byte-identical.

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_harvest_text.ps1`
Expected: assertions 1, 3, 4 FAIL -- no `<summary>` is emitted at all (Task 3 suppresses the empty one and nothing fills it).

- [ ] **Step 3: Implement.**

Add `HarvestText` to `DRagLint.Doc.Harvest.pas`. Move `EscXml` to `DRagLint.Doc.Regions`' interface (keeping its existing DocInsight comment) and update its call sites in that unit. Add `HarvestedRemarks` to `TDocFacts` with a DocInsight comment. In `TDocFactsBuilder.Build`, read the source file once (reuse whatever ANSI line reader `DRagLint.Doc.Document` uses -- do not add a second reader) and call the harvester; guard with a `try/except` so an unreadable file leaves both fields `''` rather than failing the whole build.

In `MergeComment`, emit the harvested remarks paragraph inside the `<remarks>` element, before `AUTO_BEGIN`:

```pascal
      if AFacts.HarvestedRemarks <> '' then
      begin
        // v(ADP3 T7): harvested prose beyond the first paragraph. Marked so
        // --strip and the drift check (v(ADP3 T9)) can identify it exactly;
        // emitted ABOVE the facts fence so a later run's regenerated fence
        // never swallows it.
        var HRLines: TArray<string> := AFacts.HarvestedRemarks.Replace(#13#10, #10).Split([#10]);
        for var HRi := 0 to High(HRLines) do
          if HRi = 0 then Sb.AppendLine(APrefix + AUTO_MARK + HRLines[HRi])
          else Sb.AppendLine(APrefix + HRLines[HRi]);
      end;
```

Place this inside the existing `<remarks>` emission block, after the preserved hand prose and before `AUTO_BEGIN`, in **both** the fresh and repair paths -- the fresh path currently emits `<remarks>` only when `Facts <> ''`, so widen that condition to `(Facts <> '') or (AFacts.HarvestedRemarks <> '')`.

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_harvest_text.ps1`, then `pwsh -File tests\autodoc\run_doc_p3_harvest_scan.ps1` (still green), `run_doc_p3_emptytags.ps1`, `run_doc_p3_strip.ps1`, `run_doc_multiline.ps1`, `run_doc_xml_escape.ps1`.

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.Harvest.pas src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas tests/autodoc/run_doc_p3_harvest_text.ps1 tests/autodoc/fixtures/docp3/harvest_text.pas
git commit -m "feat(doc): harvest interface-side comments into a managed <summary>/<remarks> (Phase 3 T7)"
```

---

## Task 8: Harvester -- implementation-side fallback, precedence, hand-written-wins

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (`TDocFactsBuilder.Build` -- second scan site)
- Test: `tests/autodoc/run_doc_p3_harvest_impl.ps1`, fixture `tests/autodoc/fixtures/docp3/harvest_impl.pas`

**Interfaces:**
- Consumes: Task 6's `HarvestScan`, Task 7's `HarvestText`.
- Produces: no new API. Behaviour: search order = interface declaration, then implementation definition; first hit wins and the search stops.

This is where the volume is: 120 of YADF's 121 candidates are implementation-side. The declaration is at `ASym.StartLine`; the implementation body starts at `ASym.ImplStartLine` (0 when there is no body). Scan the interface line first; on any reason other than `hrAccepted`, scan `ASym.ImplStartLine` -- but only when `ImplStartLine > 0` and `ImplStartLine <> StartLine` (for an implementation-only routine they coincide, and re-scanning is wasted work, not wrong).

Hand-written-wins: when the symbol already has a hand-written `<summary>` (present, non-empty, **no** `AUTO_MARK`), the harvest must not run into it. The cheapest correct place for that gate is `MergeComment`'s repair path, which already has `AExisting` -- Task 3's three-way classification puts the hand-written summary on the "preserve verbatim" arm and never consults `HarvestedSummary`. Verify that holds; if the harvest can still leak in, add the guard there, not in `Build` (`Build` does not see the existing doc).

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_harvest_impl.ps1`.

Fixture `tests/autodoc/fixtures/docp3/harvest_impl.pas`:

```pascal
unit harvest_impl;

interface

function ImplOnly(AValue: Integer): Integer;

// Interface-side prose wins.
function BothSides(AValue: Integer): Integer;

/// <summary>Hand-written and authoritative.</summary>
function HandWins(AValue: Integer): Integer;

implementation

// Implementation-side prose for ImplOnly.
function ImplOnly(AValue: Integer): Integer;
begin
  Result := AValue;
end;

// Implementation-side prose that must LOSE to the interface side.
function BothSides(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

// Implementation-side prose that must lose to the hand-written summary.
function HandWins(AValue: Integer): Integer;
begin
  Result := AValue + 2;
end;

end.
```

Assertions after `index` + `document --unit --apply`:
1. `ImplOnly`'s **interface declaration** carries `<summary><!-- drag-lint:auto -->Implementation-side prose for ImplOnly.</summary>` -- the comment was found next to the body but promoted onto the declaration.
2. `BothSides`' summary is `Interface-side prose wins.` and does **not** contain `must LOSE`.
3. `HandWins`' summary is exactly `Hand-written and authoritative.`, carries **no** `AUTO_MARK`, and does not contain `must lose`.
4. All three original `//` comments are still present in the implementation section, unchanged.
5. No `<summary>` is written above any *implementation* definition -- only above declarations. (Assert the implementation-section lines are unchanged apart from nothing at all.)
6. Idempotency: reindex + second `--apply` byte-identical.

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_harvest_impl.ps1`
Expected: assertion 1 FAILs (`ImplOnly` gets no summary -- Task 7 scans only the declaration line).

- [ ] **Step 3: Implement.**

In `TDocFactsBuilder.Build`, replace the single scan with the ordered pair, and comment the ordering rationale:

```pascal
  // v(ADP3 T8): search order -- INTERFACE declaration first, then the
  // IMPLEMENTATION definition; first accepted hit wins and the search stops.
  // Interface-side is preferred because a comment there is unambiguously about
  // the declaration. Implementation-side is where the VOLUME is: on the YADF
  // corpus 120 of 121 harvestable comments sit above the body, because authors
  // comment the code they are writing while DocInsight renders the
  // declaration. Promoting onto the declaration is the whole point -- the
  // original comment stays exactly where it is (copy, never move).
  HR:= HarvestScan(SrcLines, ASym.StartLine);
  if (HR.Reason <> hrAccepted) and (ASym.ImplStartLine > 0) and (ASym.ImplStartLine <> ASym.StartLine) then
    HR:= HarvestScan(SrcLines, ASym.ImplStartLine);
  if HR.Reason = hrAccepted then
    HarvestText(HR, Result.HarvestedSummary, Result.HarvestedRemarks);
```

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_harvest_impl.ps1`, then `run_doc_p3_harvest_text.ps1` and `run_doc_p3_harvest_scan.ps1` (still green).

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.Facts.pas tests/autodoc/run_doc_p3_harvest_impl.ps1 tests/autodoc/fixtures/docp3/harvest_impl.pas
git commit -m "feat(doc): implementation-side comment harvest with interface-side precedence (Phase 3 T8)"
```

---

## Task 9: Harvester -- drift protection, idempotency, strip round-trip

**Files:**
- Modify: `src/doc/DRagLint.Doc.Regions.pas` (`MergeComment` refresh rules), `src/doc/DRagLint.Doc.Drift.pas` (report a harvest drift)
- Test: `tests/autodoc/run_doc_p3_harvest_drift.ps1`, fixture `tests/autodoc/fixtures/docp3/harvest_drift.pas`

**Interfaces:**
- Consumes: Tasks 1, 3, 7, 8.
- Produces: no new API.

Refresh rules (§3.3), decided per symbol in `MergeComment` by comparing the existing summary against a freshly-computed harvest:

| Situation | Action |
| --- | --- |
| existing summary is marked, and `StripMark(existing) = HarvestedSummary` | no change (idempotent) |
| existing summary is marked, and they differ (source comment changed) | **refresh** to `HarvestedSummary` |
| existing summary is **not** marked | hand-written -- never touch, never report |
| existing summary is marked and non-empty, `HarvestedSummary` is now `''` (source comment deleted) | **remove** the managed summary and report drift |

"Summary edited by a human while the markers are still present" is indistinguishable from "source comment changed" by string comparison alone, and the spec's own detection mechanism *is* that string comparison -- so both land on **refresh**. That is the documented consequence of the marker contract: text inside a marked tag is engine-owned, and a human who wants to own it removes the marker. Say this explicitly in the code comment and in `docs/AI-USAGE.md` (Task 15). The drift *report* (below) is what makes it visible rather than silent.

Drift reporting: `DRagLint.Doc.Drift` gains a `harvest-drift` finding emitted when a marked summary is refreshed or removed, naming the symbol and both texts. It reports; it does not block.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_harvest_drift.ps1`.

Fixture `tests/autodoc/fixtures/docp3/harvest_drift.pas`:

```pascal
unit harvest_drift;

interface

// Original prose, first version.
function Drifting: Integer;

// Prose that will be deleted.
function Vanishing: Integer;

implementation

function Drifting: Integer;
begin
  Result := 1;
end;

function Vanishing: Integer;
begin
  Result := 2;
end;

end.
```

Runner scenario, all on a scratch copy:
1. `index`; `document --unit --apply`. Assert both summaries are marked and carry their prose.
2. Snapshot bytes. Reindex; `document --unit --apply` again. Assert **byte-identical** (idempotency with a harvested summary present).
3. Edit the source `//` comment for `Drifting` to `// Original prose, SECOND version.`. Reindex; `document --unit --apply`. Assert the marked summary now reads `Original prose, SECOND version.` (refresh) and that `drift` reports it.
4. Delete `Vanishing`'s `//` comment entirely. Reindex; `document --unit --apply`. Assert `Vanishing` now has **no** `<summary>` tag at all and drift reports the removal.
5. Manually remove the `AUTO_MARK` from `Drifting`'s summary and change its text to `Human owns this now.`. Reindex; `document --unit --apply`. Assert the summary is **untouched** -- still `Human owns this now.`, still unmarked.
6. Strip round trip: from the state after step 1, run `document --unit --strip --apply` and assert the file matches the pre-`apply` bytes exactly, including all original `//` comments.

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_harvest_drift.ps1`
Expected: step 4 FAILs (a stale marked summary survives with no source) and step 3's drift report is absent.

- [ ] **Step 3: Implement.**

In `MergeComment`'s repair path, replace Task 3's marked-summary arm with the four-way rule, and add the code comment described above. In `DRagLint.Doc.Drift.pas`, add the `harvest-drift` finding kind alongside the existing kinds (follow whatever pattern that unit already uses for a finding -- read it first) and emit it from the refresh/remove branches. Thread the drift signal out through `TDocumentResult` if `Drift` cannot observe the merge directly; prefer whichever wiring already exists over adding a new channel.

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_harvest_drift.ps1`, then the full harvest set (`run_doc_p3_harvest_scan.ps1`, `_text.ps1`, `_impl.ps1`), plus `run_doc_drift_engine.ps1`, `run_doc_drift_rule.ps1`, `run_doc_idempotent.ps1`, `run_doc_p3_strip.ps1`.

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.Regions.pas src/doc/DRagLint.Doc.Drift.pas tests/autodoc/run_doc_p3_harvest_drift.ps1 tests/autodoc/fixtures/docp3/harvest_drift.pas
git commit -m "feat(doc): harvest refresh/removal rules + drift reporting + strip round-trip (Phase 3 T9)"
```

---

## Task 10: Schema v19 -- four additive columns + storage plumbing

**Files:**
- Modify: `src/storage/DRagLint.Storage.Schema.pas` (`SCHEMA_VERSION`, `symbol_facts` DDL), `src/storage/DRagLint.Storage.SQLite.pas` (`Migrate` ALTERs + `FQPutSymbolFacts` / `FQGetSymbolFacts`), `src/core/DRagLint.Core.Model.pas` (`TSymbolFacts` fields)
- Test: `tests/autodoc/run_doc_p3_store19.ps1`

**Interfaces:**
- Produces: `TSymbolFacts.MutatesParams`, `.UiAffinity`, `.Touches`, `.Wiring` (all `string`), persisted and read back. Tasks 11-14 fill them.

```pascal
  TSymbolFacts = record
    SymbolId    : Int64  ;
    ReadsFields : string ;
    WritesFields: string ;
    ReturnsOwner: string ;
    Cyclomatic  : Integer;
    BodyLoc     : Integer;
    DfmEvent    : string ;
    SqlReads    : string ;
    SqlWrites   : string ;
    CoveredBy   : string ;
    /// <summary>v19 (ADP3 T11): var/out parameters the routine writes to,
    /// display-ready, e.g. 'pReason (out), pList (var)'. '' when none.</summary>
    MutatesParams: string;
    /// <summary>v19 (ADP3 T12): VCL/DevExpress controls or Application/Screen
    /// the routine touches, display-ready, e.g. 'cxGrid1, Application'. ''
    /// when none -- POSITIVE FINDINGS ONLY, never a thread-safety claim.</summary>
    UiAffinity   : string;
    /// <summary>v19 (ADP3 T13): CATEGORIES of external resource touched, plus
    /// transaction verbs, e.g. 'file system, registry|starts, commits'. The
    /// pipe separates the resource list from the transaction list; either side
    /// may be empty. '' when neither.</summary>
    Touches      : string;
    /// <summary>v19 (ADP3 T14): DI/ORM wiring joined from di_bindings /
    /// orm_links / fb_relations, e.g. 'di:IFolderService (singleton)' or
    /// 'ds:qryFolders -&gt; FOLDERS (ID, NAME)'. '' when none.</summary>
    Wiring       : string;
    Present     : Boolean;
  end;
```

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_store19.ps1`.

Runner:
1. Index any small fixture into a fresh scratch DB.
2. With `C:\Python314\python`, read `PRAGMA table_info(symbol_facts)` and assert all four new columns exist with type `TEXT`.
3. Read `schema_meta` and assert `schema_version = 19`.
4. **Migration path:** copy `tests/autodoc/fixtures/docp3/v18.sqlite` (create it once by checking out the current exe's output, or by building a v18 DB before this task's build -- generate it in the runner's setup by running the *previously deployed* exe if available, else skip this sub-assert with an explicit `SKIP` line, never a silent pass) to scratch, run any read verb against it, and assert the ALTERs added the four columns without data loss (row count for `symbol_facts` unchanged, `reads_fields` values preserved).
5. Round-trip: assert `GetSymbolFacts`/`PutSymbolFacts` carry all four values, via the existing `doc-facts-selftest` verb extended to print and accept them.

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_store19.ps1`
Expected: assertions 2 and 3 FAIL (columns absent, version 18).

- [ ] **Step 3: Implement.**

`DRagLint.Storage.Schema.pas`: `SCHEMA_VERSION = 19`. Append to the `symbol_facts` DDL string, keeping the existing comment style and adding a v19 note:

```pascal
      '  covered_by     TEXT,' +
      // v19 (ADP3 T11-T14): four ADDITIVE analysis columns. The table stays
      // WIDE (a narrow key/value fact table was considered and rejected in the
      // Phase 3 design); the accepted consequence is that a future fact kind
      // repeats this migration + full-reindex cycle.
      '  mutates_params TEXT,' +
      '  ui_affinity    TEXT,' +
      '  touches        TEXT,' +
      '  wiring         TEXT)'
```

`SCHEMA_DDL_FTS5_FIRST` is **unchanged** -- no statement is inserted, only one extended. Confirm the `array[0..58]` bound is unchanged too.

`DRagLint.Storage.SQLite.pas` `Migrate`, next to the existing `TryExec('ALTER TABLE ...')` calls (~line 598-626):

```pascal
  // v19 (ADP3): four additive symbol_facts columns. TryExec swallows the
  // "duplicate column name" error on an already-migrated DB, same as every
  // ALTER above it.
  TryExec('ALTER TABLE symbol_facts ADD COLUMN mutates_params TEXT');
  TryExec('ALTER TABLE symbol_facts ADD COLUMN ui_affinity TEXT'   );
  TryExec('ALTER TABLE symbol_facts ADD COLUMN touches TEXT'       );
  TryExec('ALTER TABLE symbol_facts ADD COLUMN wiring TEXT'        );
```

Extend `FQPutSymbolFacts`'s INSERT column list, value list and `Params` declarations (four more `ftWideMemo` params: `mut`, `uia`, `tch`, `wir`) and `FQGetSymbolFacts`'s SELECT list; extend `PutSymbolFacts` / `GetSymbolFacts` bodies accordingly, following the existing null-handling helper at `:2195-2216`.

Extend the `doc-facts-selftest` verb to round-trip the four new fields.

- [ ] **Step 4: Build, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_store19.ps1`, then `pwsh -File tests\autotest\run_migrate_v12.ps1` and `tests\autodoc\run_doc_p2_store.ps1` (migration + storage regressions).

- [ ] **Step 5: Commit.**

```bash
git add src/storage/DRagLint.Storage.Schema.pas src/storage/DRagLint.Storage.SQLite.pas src/core/DRagLint.Core.Model.pas src/cli/DRagLint.CLI.pas tests/autodoc/run_doc_p3_store19.ps1
git commit -m "feat(index): schema v19 -- four additive symbol_facts columns + storage plumbing (Phase 3 T10)"
```

---

## Task 11: `mutates_params` fact + derived `Pure`

**Files:**
- Modify: `src/doc/DRagLint.Doc.SymbolFacts.pas` (new `AnalyzeMutatesParams`, called from `Analyze`), `src/doc/DRagLint.Doc.Facts.pas` (`TDocFacts.MutatesParams` + read), `src/doc/DRagLint.Doc.Regions.pas` (`FormatPhase2FactLines`)
- Test: `tests/autodoc/run_doc_p3_mutates.ps1`, fixture `tests/autodoc/fixtures/docp3/mutates.pas`

**Interfaces:**
- Consumes: Task 10's `TSymbolFacts.MutatesParams`.
- Produces: the `Mutates:` and `Pure` render lines.

Derivation: over the routine's own body AST (the same matched `Proc`/`Body` nodes `AnalyzeReadsWrites` already has -- **no third parse, no second walk**; extend that walk or add a sibling walk over the same node), collect identifiers that are assignment LHS targets or `Inc`/`Dec` arguments **and** resolve to a `var` or `out` parameter of the routine. Render `Mutates: pReason (out), pList (var)`. Read the parameter modifiers from `ASym.Signature` via the existing signature parser (`ParseReturnType`'s neighbours in this unit) or `TRoutineVarTable`, whichever already carries modifier information -- read both before choosing.

`Pure` is **render-time only, not stored** (§5.2): emitted for a routine **with a body** when `WritesFields`, `MutatesParams`, `Touches`, `SqlWrites` and `SqlReads` are all empty. It has no column of its own precisely so it cannot disagree with the facts it is derived from. Note that `Touches` is empty until Task 13 ships, so `Pure` will over-report between Task 11 and Task 13 -- that is acceptable *within the increment* because nothing ships until the end, but the `Pure` render must be added in Task 13, not here. **This task adds `Mutates:` only.** Add `Pure` in Task 13's step 3.

Order in `FormatPhase2FactLines`: append the new lines **after** the existing six, in the order `Mutates:` (T11), `UI thread only` (T12), `Touches:` / `Transaction:` (T13), `Registered as:` / `Dataset:` (T14), then `Pure` last. Fixing the order here keeps the doc/hover consistency lock meaningful and keeps regeneration idempotent.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_mutates.ps1`.

Fixture `tests/autodoc/fixtures/docp3/mutates.pas`:

```pascal
unit mutates;

interface

procedure FillBoth(var AList: TArray<Integer>; out AReason: string; AConst: Integer);
function PureAdd(A, B: Integer): Integer;

implementation

procedure FillBoth(var AList: TArray<Integer>; out AReason: string; AConst: Integer);
begin
  SetLength(AList, AConst);
  AReason := 'filled';
end;

function PureAdd(A, B: Integer): Integer;
begin
  Result := A + B;
end;

end.
```

Assertions after `index` + `document --unit --apply`:
1. `FillBoth`'s block contains `Mutates: ` naming **both** `AReason (out)` and `AList (var)` (order-insensitive assertion).
2. `PureAdd`'s block contains **no** `Mutates:` line.
3. The value-parameter `AConst` never appears in any `Mutates:` line.
4. Reading `symbol_facts.mutates_params` directly with python for `FillBoth` returns a non-empty string; for `PureAdd`, empty or NULL.
5. Idempotency: reindex + second `--apply` byte-identical.

(`SetLength(AList, ...)` mutates `AList` through a `var` param without a literal `:=`. If the AST walk cannot see that as a write, assert only `AReason (out)` in step 1 and add `AList[0] := AConst;` to the fixture body so the `var` case is still covered by a real assignment LHS. Decide from the actual walk behaviour -- do not guess, and do not weaken the assertion silently: whichever form you use, the test must cover one `var` and one `out` parameter.)

- [ ] **Step 2: Run it, verify FAIL.**

Run: `pwsh -File tests\autodoc\run_doc_p3_mutates.ps1`
Expected: assertions 1 and 4 FAIL.

- [ ] **Step 3: Implement.**

Read `AnalyzeReadsWrites` (`src/doc/DRagLint.Doc.SymbolFacts.pas:574`) in full first -- it already classifies assignment-LHS / `Inc`/`Dec` / `var`-argument writes over exactly the nodes needed, and resolves identifiers against `TRoutineVarTable`. Add `AnalyzeMutatesParams(const AProc, ABody: TTSNode; const ASrc: TBytes; const ASym: TSymbol): string` beside it with a full header comment in the house style, and call it from `Analyze` inside the existing `if Integer(Proc.StartPoint.Row) + 1 = ASym.ImplStartLine then` block, next to the `AnalyzeReadsWrites` call. Cap the list at 8 with ` (+N more)`, matching the Reads/Writes cap.

Add `TDocFacts.MutatesParams` with a DocInsight comment; read it in `Build` alongside the other `symbol_facts` fields; render in `FormatPhase2FactLines`:

```pascal
    // v(ADP3 T11): var/out parameters the routine writes through. Closes the
    // Phase-2 T4 deferred gap (that task covered FIELDS only). Display-ready
    // at index time -- passthrough, omit when empty.
    if AFacts.MutatesParams <> '' then
      Lines.Add('Mutates: ' + EscXml(AFacts.MutatesParams));
```

- [ ] **Step 4: Build, REINDEX the fixture, run the test, verify PASS.**

Run: `pwsh -File tests\autodoc\run_doc_p3_mutates.ps1` (the runner must `index` after the new exe is deployed -- this is an index-time fact). Then `run_doc_p2_fields.ps1` and `run_doc_p2_hover.ps1`.

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.SymbolFacts.pas src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas tests/autodoc/run_doc_p3_mutates.ps1 tests/autodoc/fixtures/docp3/mutates.pas
git commit -m "feat(doc): Mutates fact -- var/out parameter writes (Phase 3 T11)"
```

---

## Task 12: `ui_affinity` fact

**Files:**
- Modify: `src/doc/DRagLint.Doc.SymbolFacts.pas` (curated list + `AnalyzeUiAffinity`), `src/doc/DRagLint.Doc.Facts.pas`, `src/doc/DRagLint.Doc.Regions.pas`
- Test: `tests/autodoc/run_doc_p3_ui.ps1`, fixture `tests/autodoc/fixtures/docp3/ui.pas`

**Interfaces:**
- Consumes: Task 10's `TSymbolFacts.UiAffinity`.
- Produces: the `UI thread only -- touches ...` render line.

Derivation (§5.2): over the same matched `Proc`/`Body`, collect identifiers whose resolved type is a VCL/DevExpress control type, plus bare `Application` / `Screen`. **Positive findings only** -- never emit a "thread-safe" claim, which cannot be proven this cheaply. Render `UI thread only -- touches cxGrid1, Application`.

Curated list (§5.4) lives as a constant in this unit, next to the analysis:

```pascal
const
  // v(ADP3 T12): curated UI base types + globals. ENGINE KNOWLEDGE, not user
  // configuration -- it lives here, next to the analysis that consumes it, not
  // in the manifest. A STALE list under-reports (the fact is omitted), it never
  // emits a false claim, so growing it later is safe and non-breaking.
  UI_BASE_TYPES: array[0..9] of string = (
    'TControl', 'TWinControl', 'TForm', 'TFrame', 'TCustomForm',
    'TGraphicControl', 'TcxControl', 'TcxCustomGrid', 'TdxBar', 'TCustomPanel');
  UI_GLOBALS: array[0..1] of string = ('Application', 'Screen');
```

Type resolution: a field/variable resolves to a UI type when its declared type name is in `UI_BASE_TYPES`, **or** when `type_ancestors` places it under one of them. Reuse the existing ancestry walk (`IsReferenceTypeName` in this unit already resolves a type name against the store -- read it and follow the same pattern). When the type cannot be resolved, omit -- absence over wrong.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_ui.ps1`.

Fixture `tests/autodoc/fixtures/docp3/ui.pas` -- self-contained, declaring its own stand-in hierarchy so the test does not depend on the VCL being indexed:

```pascal
unit ui;

interface

type
  TControl = class
  public
    procedure Repaint;
  end;

  TCustomPanel = class(TControl)
  end;

  TForm1 = class
  private
    FPanel: TCustomPanel;
  public
    procedure TouchesUi;
    procedure NoUi;
  end;

implementation

procedure TControl.Repaint;
begin
end;

procedure TForm1.TouchesUi;
begin
  FPanel.Repaint;
end;

procedure TForm1.NoUi;
begin
end;

end.
```

Assertions:
1. `TForm1.TouchesUi`'s block contains `UI thread only` and names `FPanel`.
2. `TForm1.NoUi`'s block contains **no** `UI thread only` line.
3. No block anywhere contains the words `thread-safe` or `thread safe` (the never-claim guard).
4. Idempotency.

If `TCustomPanel` descending from the fixture's own `TControl` does not resolve through `type_ancestors`, the fixture's `FPanel` should be typed `TControl` directly so the direct-name arm is still exercised, and a note added to the runner explaining the ancestry arm is covered by the real-corpus rollout instead.

- [ ] **Step 2: Run it, verify FAIL.** Run: `pwsh -File tests\autodoc\run_doc_p3_ui.ps1`; Expected: assertion 1 FAILs.

- [ ] **Step 3: Implement.** `AnalyzeUiAffinity(const AProc, ABody: TTSNode; const ASrc: TBytes; const ASym: TSymbol; const AStore: ISymbolStore): string`, called from `Analyze` next to `AnalyzeReadsWrites`. Cap at 8 with ` (+N more)`. Render:

```pascal
    // v(ADP3 T12): UI affinity -- POSITIVE FINDINGS ONLY. The absence of this
    // line means "no UI touch was DETECTED", never "this routine is
    // thread-safe": a stale curated list under-reports, and a thread-safety
    // claim cannot be proven by this analysis.
    if AFacts.UiAffinity <> '' then
      Lines.Add('UI thread only -- touches ' + EscXml(AFacts.UiAffinity));
```

- [ ] **Step 4: Build, REINDEX, run, verify PASS.** Run: `pwsh -File tests\autodoc\run_doc_p3_ui.ps1`; then `run_doc_p2_hover.ps1`.

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.SymbolFacts.pas src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas tests/autodoc/run_doc_p3_ui.ps1 tests/autodoc/fixtures/docp3/ui.pas
git commit -m "feat(doc): UI-affinity fact -- positive findings only (Phase 3 T12)"
```

---

## Task 13: `touches` fact + the derived `Pure` line

**Files:**
- Modify: `src/doc/DRagLint.Doc.SymbolFacts.pas` (curated lists + `AnalyzeTouches`), `src/doc/DRagLint.Doc.Facts.pas`, `src/doc/DRagLint.Doc.Regions.pas` (two new lines + `Pure`)
- Test: `tests/autodoc/run_doc_p3_touches.ps1`, fixture `tests/autodoc/fixtures/docp3/touches.pas`

**Interfaces:**
- Consumes: Task 10's `TSymbolFacts.Touches`; Tasks 11-12 for the `Pure` derivation.
- Produces: `Touches:`, `Transaction:` and `Pure` render lines.

Derivation (§5.2): match call targets in the body against curated surface lists and emit **categories, not call sites**. Storage format is `resources|transactions`, e.g. `file system, registry|starts, commits`; either side may be empty; `''` when both are.

```pascal
const
  // v(ADP3 T13): curated external-surface lists. Same discipline as
  // UI_BASE_TYPES (T12): engine knowledge, positive findings only, a stale
  // list under-reports and never lies.
  TOUCH_FILE_CALLS    : array[0..7] of string = ('TFile', 'TDirectory', 'TPath', 'AssignFile',
                                                 'Rewrite', 'Reset', 'CloseFile', 'TStreamWriter');
  TOUCH_REGISTRY_CALLS: array[0..1] of string = ('TRegistry', 'TRegistryIniFile');
  TOUCH_NETWORK_CALLS : array[0..3] of string = ('THTTPClient', 'TIdHTTP', 'TNetHTTPClient', 'TIdTCPClient');
  TOUCH_TXN_START     : array[0..0] of string = ('StartTransaction');
  TOUCH_TXN_COMMIT    : array[0..1] of string = ('Commit', 'CommitRetaining');
  TOUCH_TXN_ROLLBACK  : array[0..1] of string = ('Rollback', 'RollbackRetaining');
```

Categories rendered in fixed order: `file system`, `registry`, `network`. Transaction verbs in fixed order: `starts`, `commits`, `rolls back`.

`Pure` (§5.2) is added here, once all its inputs exist: emit `Pure` for a routine **with a body** (`AFacts.BodyLoc > 0` and the symbol is routine-like) when `WritesFields`, `MutatesParams`, `Touches`, `SqlWrites` and `SqlReads` are **all** empty. Render-time only, no column, emitted **last** in the fact-line order.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_touches.ps1`.

Fixture `tests/autodoc/fixtures/docp3/touches.pas`:

```pascal
unit touches;

interface

uses
  System.IOUtils;

type
  TTxn = class
  public
    procedure StartTransaction;
    procedure Commit;
  end;

function ReadConfig(const APath: string): string;
procedure RunTxn(ATxn: TTxn);
function AddUp(A, B: Integer): Integer;

implementation

procedure TTxn.StartTransaction;
begin
end;

procedure TTxn.Commit;
begin
end;

function ReadConfig(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath);
end;

procedure RunTxn(ATxn: TTxn);
begin
  ATxn.StartTransaction;
  ATxn.Commit;
end;

function AddUp(A, B: Integer): Integer;
begin
  Result := A + B;
end;

end.
```

Assertions:
1. `ReadConfig`'s block contains `Touches: file system` and no `registry` / `network`.
2. `RunTxn`'s block contains `Transaction: starts, commits`.
3. `AddUp`'s block contains `Pure` and no `Touches:` / `Transaction:`.
4. `ReadConfig`'s block does **not** contain `Pure` (it touches the file system).
5. `symbol_facts.touches` for `ReadConfig` reads `file system|` (or `file system` with an empty transaction side -- assert whichever format the implementation writes, and pin it).
6. Idempotency.

- [ ] **Step 2: Run it, verify FAIL.** Run: `pwsh -File tests\autodoc\run_doc_p3_touches.ps1`; Expected: assertions 1-4 FAIL.

- [ ] **Step 3: Implement.** `AnalyzeTouches(const AProc, ABody: TTSNode; const ASrc: TBytes): string` called from `Analyze`. Render:

```pascal
    // v(ADP3 T13): external surfaces touched, as CATEGORIES (not call sites)
    // and transaction verbs. Stored as 'resources|transactions'; either side
    // may be empty, and the whole line pair is omitted when both are.
    if AFacts.Touches <> '' then
    begin
      var TouchParts: TArray<string>:= AFacts.Touches.Split(['|']);
      if (Length(TouchParts) > 0) and (TouchParts[0] <> '') then
        Lines.Add('Touches: ' + EscXml(TouchParts[0]));
      if (Length(TouchParts) > 1) and (TouchParts[1] <> '') then
        Lines.Add('Transaction: ' + EscXml(TouchParts[1]));
    end;
```

and, **last** in the function:

```pascal
    // v(ADP3 T13): 'Pure' is DERIVED at render time from the other facts and has
    // NO column of its own -- so it can never disagree with them. Emitted for a
    // routine WITH A BODY that writes no field, mutates no var/out parameter,
    // touches no external surface and reads/writes no SQL. It is a conclusion,
    // not an observation: it says "none of the effects this engine can detect
    // were detected", which is exactly as strong as the facts beneath it.
    if (AFacts.BodyLoc > 0)
       and (AFacts.WritesFields = '') and (AFacts.MutatesParams = '')
       and (AFacts.Touches = '') and (AFacts.SqlWrites = '') and (AFacts.SqlReads = '') then
      Lines.Add('Pure');
```

- [ ] **Step 4: Build, REINDEX, run, verify PASS.** Run: `pwsh -File tests\autodoc\run_doc_p3_touches.ps1`, `run_doc_p3_mutates.ps1`, `run_doc_p2_sql.ps1`, `run_doc_p2_hover.ps1`.

- [ ] **Step 5: Commit.**

```bash
git add src/doc/DRagLint.Doc.SymbolFacts.pas src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas tests/autodoc/run_doc_p3_touches.ps1 tests/autodoc/fixtures/docp3/touches.pas
git commit -m "feat(doc): Touches/Transaction facts + derived Pure line (Phase 3 T13)"
```

---

## Task 14: `wiring` fact -- a join over already-indexed tables

**Files:**
- Modify: `src/doc/DRagLint.Doc.SymbolFacts.pas` (`AnalyzeWiring`), `src/core/DRagLint.Core.Interfaces.pas` + `src/storage/DRagLint.Storage.SQLite.pas` (a read query if none exists), `src/doc/DRagLint.Doc.Facts.pas`, `src/doc/DRagLint.Doc.Regions.pas`
- Test: `tests/autodoc/run_doc_p3_wiring.ps1`, fixture `tests/autodoc/fixtures/docp3/wiring.pas`

**Interfaces:**
- Consumes: Task 10's `TSymbolFacts.Wiring`; existing tables `di_bindings(file_id, interface_name, impl_name, lifetime, start_line, ...)`, `orm_links(delphi_symbol_id, sql_symbol_id, link_kind, confidence, ...)`, `fb_relations(id, name, ...)`, `fb_columns(relation_id, name, position, ...)`.
- Produces: the `Registered as:` and `Dataset:` render lines.

**No new AST analysis.** This is a pure join (§5.2):
- DI: a `di_bindings` row whose `impl_name` matches the symbol's type name (the symbol itself for a class, `ASym.ParentId`'s name for a method) -> `di:<interface_name> (<lifetime>)`.
- ORM: an `orm_links` row with `delphi_symbol_id = ASym.Id` (or the parent's id), joined to `fb_relations` by `sql_symbol_id`, and the relation's first few `fb_columns` -> `ds:<symbol name> -> <RELATION> (<COL1>, <COL2>)`.

Storage format: the `di:` / `ds:` entries joined by `; `. Render two lines: `Registered as: IFolderService (singleton)` from the `di:` entries and `Dataset: qryFolders -> FOLDERS (ID, NAME)` from the `ds:` entries.

**Add a read method to `ISymbolStore` only if one does not already exist** -- check for existing `di_bindings` / `orm_links` readers first (the deps-report and coherence features use these tables). Reuse before adding.

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p3_wiring.ps1`.

Fixture `tests/autodoc/fixtures/docp3/wiring.pas` -- a Spring4D-shaped registration the DI indexer already recognizes (read `src/` for the di_bindings extractor and copy the exact call shape it matches; if it needs `Spring.Container`, declare a local stand-in with the same call surface):

```pascal
unit wiring;

interface

type
  IFolderService = interface
    ['{2F1B6A1E-6D9C-4C3A-9A55-0B0C1D2E3F40}']
    procedure Refresh;
  end;

  TFolderService = class(TInterfacedObject, IFolderService)
  public
    procedure Refresh;
  end;

procedure RegisterAll;

implementation

uses
  Spring.Container;

procedure TFolderService.Refresh;
begin
end;

procedure RegisterAll;
begin
  GlobalContainer.RegisterType<TFolderService>.Implements<IFolderService>.AsSingleton;
end;

end.
```

Assertions:
1. `di_bindings` has a row for this fixture after `index` (verify with python first -- **if it does not, the DI extractor does not recognize this shape and the fixture is wrong, not the fact**; fix the fixture to match whatever shape the extractor does recognize before writing the rest of the test).
2. `TFolderService`'s block contains `Registered as: IFolderService (singleton)`.
3. A class with no binding has no `Registered as:` line.
4. `symbol_facts.wiring` for `TFolderService` is non-empty.
5. Idempotency.

The `Dataset:` half needs `orm_links` + `fb_relations` rows, which come from a Firebird snapshot, not from source. Assert it against an existing indexed corpus instead: run `document --qname` against a known ORM3 symbol that has an `orm_links` row (find one with python against `C:\Projects\DB\ORM3\drag-lint.sqlite`) and assert the `Dataset:` line renders. If no such symbol exists in any available DB, **say so explicitly in the runner output as a `SKIP` with the reason** -- do not silently drop the assertion.

- [ ] **Step 2: Run it, verify FAIL.** Run: `pwsh -File tests\autodoc\run_doc_p3_wiring.ps1`; Expected: assertions 2 and 4 FAIL.

- [ ] **Step 3: Implement.** `AnalyzeWiring(const ASym: TSymbol; const AStore: ISymbolStore): string`, called from `Analyze` **outside** the `if PF.Tree <> nil` block (like `AnalyzeDfmEvent` -- it needs no AST at all, so a failed parse must not suppress it). Render:

```pascal
    // v(ADP3 T14): DI/ORM wiring -- a JOIN over already-indexed tables
    // (di_bindings / orm_links / fb_relations / fb_columns), NOT a new
    // analysis. Stored as '; '-joined 'di:'/'ds:' entries; split into two
    // display lines here.
    if AFacts.Wiring <> '' then
    begin
      var DiPart: string:= ''; var DsPart: string:= '';
      for var WEntry in AFacts.Wiring.Split(['; ']) do
        if StartsStr('di:', WEntry) then
        begin
          if DiPart <> '' then DiPart:= DiPart + ', ';
          DiPart:= DiPart + Copy(WEntry, 4, MaxInt);
        end
        else if StartsStr('ds:', WEntry) then
        begin
          if DsPart <> '' then DsPart:= DsPart + ', ';
          DsPart:= DsPart + Copy(WEntry, 4, MaxInt);
        end;
      if DiPart <> '' then Lines.Add('Registered as: ' + EscXml(DiPart));
      if DsPart <> '' then Lines.Add('Dataset: ' + EscXml(DsPart));
    end;
```

- [ ] **Step 4: Extend the doc/hover consistency assertion.**

§7 requires that the doc/hover consistency battery cover **at least one** of the four new facts. All four render through the shared `TDocRegions.FormatPhase2FactLines`, so hover gets them for free -- but "for free" is exactly the claim that needs a test.

Modify `tests/autodoc/run_doc_p2_hover.ps1`: after its existing assertions, index `tests/autodoc/fixtures/docp3/mutates.pas`, run `document --unit --apply` **and** `hover` on `FillBoth`, and assert the `Mutates: ` line appears **identically** in both outputs (same text after stripping the doc block's `/// ` prefix and hover's own markdown framing). Add a comment in the runner naming this as the Phase 3 extension of the v(ADP2 T9) consistency lock.

Run: `pwsh -File tests\autodoc\run_doc_p2_hover.ps1`
Expected: PASS, including the new `Mutates:` cross-check.

- [ ] **Step 5: Build, REINDEX, run, verify PASS.** Run: `pwsh -File tests\autodoc\run_doc_p3_wiring.ps1`, then the whole `run_doc_p2_*.ps1` set and `run_doc_p3_*.ps1` set.

- [ ] **Step 6: Commit.**

```bash
git add src/doc/DRagLint.Doc.SymbolFacts.pas src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas src/core/DRagLint.Core.Interfaces.pas src/storage/DRagLint.Storage.SQLite.pas tests/autodoc/run_doc_p3_wiring.ps1 tests/autodoc/fixtures/docp3/wiring.pas tests/autodoc/run_doc_p2_hover.ps1
git commit -m "feat(doc): Wiring fact -- DI bindings + dataset/table links joined from the index (Phase 3 T14)"
```

---

## Task 15: Documentation refresh

**Files:**
- Modify: `docs/INDEX-SCHEMA.md`, `CHANGELOG.md`, `docs/AI-USAGE.md`, `src/cli/DRagLint.CLI.pas` (`--help`), unit banner comments in `DRagLint.Doc.SymbolFacts.pas` / `DRagLint.Doc.Regions.pas` / `DRagLint.Doc.Harvest.pas` / `DRagLint.Doc.Strip.pas`

**Interfaces:** none.

Per §8 step 6, this runs **after** all implementation, so it describes what shipped.

- [ ] **Step 1: `docs/INDEX-SCHEMA.md`.** Change the stated version 18 -> 19 everywhere. In section 2.15 (`symbol_facts`) add the four columns with their exact value formats: `mutates_params` (`'pReason (out), pList (var)'`, capped at 8 with ` (+N more)`), `ui_affinity` (`'cxGrid1, Application'`), `touches` (`'file system, registry|starts, commits'` -- document the `|` separator), `wiring` (`'di:IFolderService (singleton); ds:qryFolders -> FOLDERS (ID, NAME)'`). Refresh the stated table/column counts. Add a schema-history line: `18 -> 19: four additive symbol_facts columns; >= gate unchanged; symbols.id reassigned by the full reindex`.

- [ ] **Step 2: `CHANGELOG.md`.** One Phase 3 entry covering: the uniform `<!-- drag-lint:auto -->` provenance marker and the removal of the `Observed:` content sniff; `document --strip`; comment harvesting (interface- then implementation-side, copy-never-move, drift-reported); the four render fixes (empty tags omitted, `?` only on mixed lists, `Used by:` for non-callables, and the ownership-yield outcome from Task 5); the four new facts + `Pure`; schema v19.

- [ ] **Step 3: `docs/AI-USAGE.md`.** In the `document` verb section, document: the new `--strip` mode and what it removes; the harvesting behaviour and every acceptance guard from §3.4; and **the provenance contract in plain terms** -- text inside a tag carrying `<!-- drag-lint:auto -->` is engine-owned and will be regenerated; remove the marker to take ownership; a tag without the marker is never touched. State explicitly that editing text *inside* a marked tag will be overwritten on the next run (the Task 9 consequence).

- [ ] **Step 4: CLI `--help`.** Confirm the `--strip` line added in Task 2 is present, accurate, and consistent with the other `document` lines; add any other new switch.

- [ ] **Step 5: Unit banners.** `DRagLint.Doc.SymbolFacts` -- describe the four new analyses and the curated lists (and that a stale list under-reports rather than lying). `DRagLint.Doc.Regions` -- state the provenance contract as the unit's governing invariant. `DRagLint.Doc.Harvest` and `DRagLint.Doc.Strip` -- full banner comments if not already written. Verify every new public declaration added across Tasks 1-14 carries DocInsight (grep for `class function`/`function`/`procedure` added in the diff and check each).

- [ ] **Step 6: Verify.**

Run: `git diff --stat main` and confirm every file listed above appears. Run: `& third_party\dll-win64\drag-lint.exe document --help` (or the bare `--help`) and read the `document` lines. Run: `pwsh -File tests\autodoc\run_docs_manifest_roundtrip.ps1` and `tests\autotest\run_doc_no_todo.ps1`.

- [ ] **Step 7: Commit.**

```bash
git add docs/INDEX-SCHEMA.md CHANGELOG.md docs/AI-USAGE.md src/cli/DRagLint.CLI.pas src/doc/*.pas
git commit -m "docs(autodoc): Phase 3 -- schema v19, --strip, harvesting, provenance contract (Phase 3 T15)"
```

---

## Task 16: Converter notification + Obsidian schema page

**Files:**
- Create: `docs/INBOX-index-schema-v19-reindex-for-converter.md`
- Create: `C:/Projects/claude-obsidian/wiki/entities/DragLint_Index_Schema.md`
- Modify: `C:/Projects/claude-obsidian/wiki/index.md`, `C:/Projects/claude-obsidian/wiki/hot.md`, `C:/Projects/claude-obsidian/wiki/entities/DragLint_Linter.md`

**Interfaces:** none.

- [ ] **Step 1: Read the v18 precedent.** Read `docs/INBOX-index-schema-v18-reindex-for-converter.md` and its ack `docs/INBOX-REPLY-converter-v18-ack.md`. Follow that structure exactly.

- [ ] **Step 2: Write the v19 INBOX message.** It MUST state, per §8 step 7:
  - **Schema 19 = 18 + four additive columns** on the existing `symbol_facts` table (`mutates_params`, `ui_affinity`, `touches`, `wiring`). Nothing removed, nothing renamed; the version gate stays a `>=` check. A consumer issuing `SELECT *` against `symbol_facts` now gets four extra columns -- select by name if column position matters.
  - **`symbols.id` is reassigned again** by the full reindex. Re-resolve by `qualified_name`; do not trust cached ids. *This bit the converter last time -- it is the single most important line in the message and belongs near the top.*
  - **Which DBs were rebuilt** to v19, with their `schema_version` -- including `YADF.sqlite` and `YADFOT.sqlite` (the latter was still on v17 before this phase). Fill in the actual list from the Task 17 rollout; if this task runs before Task 17, leave the table and write it after the reindex completes.
  - **`wiring` may be directly useful to the converter** -- it surfaces Spring4D DI bindings and dataset-to-table links the conversion analysis already cares about.
  - **`document --strip` now exists**, plus the provenance-marker contract that makes it exact -- relevant to anyone whose tooling reads or writes DocInsight comments.
  - A short "not relevant to the converter" section, as in the v18 message.

- [ ] **Step 3: Write the Obsidian schema page.**

**REQUIRED SUB-SKILL:** `obsidian-markdown` (frontmatter, `[[wikilinks]]`, `related:`).

Create `C:/Projects/claude-obsidian/wiki/entities/DragLint_Index_Schema.md`. No such page exists today -- this is new. Content: the v19 table inventory, each with purpose and key columns -- `symbols`, `files`, `refs`, `call_edges`, `symbol_docs`, **`symbol_facts` (all 14 columns)**, `type_ancestors`, `type_helpers`, `unit_uses`, `di_bindings`, `orm_links`, `fb_relations` / `fb_columns` / `fb_field_info` / `fb_datasets`, `string_literals` + the `string_fts` / `string_fts_tri` FTS5 shadow tables, `compiler_findings`, `symbol_trigrams`, `schema_meta`. Note the schema-version history (17 -> 18 added `symbol_facts` -> 19 added four columns) and the `>=` gate contract. State that `docs/INDEX-SCHEMA.md` in the repo remains authoritative and link to it; this page is the cross-project view.

- [ ] **Step 4: Link it.** Add `[[DragLint_Index_Schema]]` to `wiki/entities/DragLint_Linter.md`'s `related:` and body, add a line to `wiki/index.md`, and add an entry to `wiki/hot.md`.

- [ ] **Step 5: Verify.** Confirm both new files exist and every `[[wikilink]]` in them resolves to a real page (or is a deliberate forward link). Confirm the INBOX message's DB table matches the actual `schema_version` values read with python from each rebuilt DB.

- [ ] **Step 6: Commit.**

```bash
git add docs/INBOX-index-schema-v19-reindex-for-converter.md
git commit -m "docs(inbox): notify the converter workstream of schema v19 + document --strip (Phase 3 T16)"
```

(The Obsidian vault is a separate repo -- commit it there per its own convention, or leave it uncommitted if that vault is not version-controlled.)

---

## Task 17: Rollout

**Files:** no source changes except the version bump in `src/cli/DRagLint.CLI.pas:6`.

**Interfaces:** none.

This is the §8 rollout, run once everything above is green.

- [ ] **Step 1: Build and deploy the CLI.**

Kill orphan `drag-lint.exe` / `bds.exe` first. Build `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` with a log; confirm `BUILD_EXITCODE=0` and no `[dcc] Error`; confirm the deployed `third_party/dll-win64/drag-lint.exe` timestamp actually moved (a silent lock failure is the classic trap).

- [ ] **Step 2: Full regression battery.**

Run `pwsh -File tests\run_battery.ps1` -- the WHOLE battery, not `tests/autodoc` + `tests/autotest`. **Record the actual pass/fail/timeout counts AND the denominator the driver printed** (do not compare against a number written here -- the driver's printed denominator is the contract; a literal in this document would be wrong the moment a runner is added, and a hardcoded count is the exact defect this line used to carry).

Expected by the time T17 runs: **every enumerated runner passes.** T3i is scheduled before T4 precisely so the `tests/callresolve` pair (register item E1) is green well before this rollout -- if it is not, T17 does not start. If anything else fails, fix it before proceeding; do not reindex on a red battery.

- [ ] **Step 3: Reindex all 9 manifest DBs to v19.**

Run: `drag-lint index --all --config third_party\dll-win64\drag-lint.json --jobs 0`

**`--jobs` must be passed together with `--config`** -- LATEST-62 ran this sequentially at roughly 3h per platform because `--jobs` needs `--config`. Parallelising it is part of this rollout, not a follow-up. Preview first with `--dry-run`. Then verify with python that every DB reports `schema_version = 19` and that `symbol_facts` has non-null values in at least one of the four new columns.

- [ ] **Step 4: Reindex the two YADF DBs.**

Neither is in the manifest. `YADF.sqlite` is at v18, `YADFOT.sqlite` is **still v17**. Index both explicitly with `--db`, then verify both report 19.

- [ ] **Step 5: Reset YADF, then re-apply.**

On branch `experiment/drag-lint-autodoc` in `C:\Projects\YADF` (confirm the branch first; commit or stash anything uncommitted so the diff stays readable):

1. Run `document --strip` over the project to remove the 50 pre-§4.0 managed blocks. Those blocks predate uniform marking, so **verify the result against `HEAD`**: the stripped tree should differ from `HEAD` only by the 2026-07-24 14:54 self-format changes (aligned semicolons, split `var` lines, reindented implementation comments in `YADF.Options.pas` / `YADF.Tokens.pas` / `YadfMain.pas`, plus `.res` / `YADF.Version.inc` / `build_all.bat`). **Any other residue is a `--strip` bug -- fix it before proceeding.**
2. **Keep YADF's hand-written DocInsight.** `YADF.Guard.pas` in particular carries authored `<summary>` / `<param>` / `<returns>` / `<remarks>`; that prose is the control group for hand-written-wins, the merge-into-existing-`<remarks>` path, and the drift detector. Do not delete it.
3. Re-run `document --apply` and review the diff. **Expect:** no blank `<summary></summary>` stubs; no ` ?` markers; `TToken` reading `Used by:`; hand-written summaries untouched and unmarked; and a large share of the 120 implementation-side comments promoted into managed summaries. Verify every touched file is still strict 7-bit ASCII with CRLF, and that declaration counts are byte-identical to the pre-run state (the same corruption check that validated the 2026-07-24 run).
4. Record the actual numbers (blocks written, summaries harvested, drift reports) -- Task 16's INBOX table and the CHANGELOG both want them.

- [ ] **Step 6: Version bump.**

`src/cli/DRagLint.CLI.pas:6` -- bump `VERSION` off `'1.2.1-alpha'`. Rebuild, re-verify `--version`, then run `pack-lint-release.ps1`.

- [ ] **Step 7: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas CHANGELOG.md docs/INBOX-index-schema-v19-reindex-for-converter.md
git commit -m "chore(release): Phase 3 rollout -- version bump, v19 reindex, YADF strip+re-apply (Phase 3 T17)"
```

**Do not push.** The user holds commit and push for this repo (17 commits are already unpushed). Report the state; let them decide.

---

## Notes for the executor

- **Task order matters.** Tasks 1-3 are foundational: the marker (T1) is what makes strip (T2), empty-tag suppression (T3), harvesting (T7-T9) and the drift rule exact. Do not reorder them. Tasks 4 and 5 are independent and can run any time after T1. Tasks 10-14 are independent of 1-9 except that T13's `Pure` needs T11's `MutatesParams`.
- **Every task that asserts a `symbol_facts`-derived line must reindex after building.** Tasks 11-14. A test that only rebuilds will assert against stale rows and pass or fail for the wrong reason.
- **Tasks 1 and 3 will break existing test expectations** that pin exact emitted text. That is expected churn -- update the expectation, never the engine, and list every runner you touched in the commit message.
- **When a plan step and the code disagree, the code wins.** Several steps above say "read X first" or "confirm the enumerator names" -- those are real instructions, not hedges. Signatures quoted here were read from the tree on 2026-07-24; verify before relying on them.
