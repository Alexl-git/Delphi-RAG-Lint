# Rule-book and Catalog Curation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the ConvRulesEditor a modal curation form that loads several rule-book / catalog files as a working set and can split, copy, delete, merge and compose their blocks without ever reformatting a block it merely moved.

**Architecture:** Three pure, headless units (`ConvRules.BlockFile`, `ConvRules.BlockOps`, `ConvRules.WorkingSet`) plus one thin VCL modal (`ConvRules.CurationForm`), matching the existing pure-core / thin-VCL split of `ConvRules.Casts` and `ConvRules.CastLib`. A file is split into an ordered list of blocks each holding its **raw text**; every operation moves raw text and nothing is re-emitted from a parsed model. Merge and Compose share one code path: Compose folds the working set top-to-bottom with the same merge semantics, auto-resolving link collisions in favour of the earlier file.

**Tech Stack:** Delphi 13 Florence (RAD Studio 37.0), `dcc64`, plain VCL (no DevExpress, no `.dfm` -- forms are built in code), `System.Generics.Collections`. Tests are the existing self-contained console runner `ConvRulesModelTests.dpr` (no DUnitX).

Spec: `docs/superpowers/specs/2026-07-27-rulebook-curation-design.md` (approved 2026-07-27).
Worktree: `C:\Projects\Delphi-RAG-lint-converter`, branch `feat/converter-editor`.

## Global Constraints

- **Encoding:** every `.pas` file is strict 7-bit ASCII with CRLF line endings. No Unicode, no BOM, no LF-only.
- **DocInsight:** every public type, function and method gets a `///` XML doc-comment (`<summary>`, `<param>`, `<returns>`, `<remarks>`). Private helpers only when an invariant is non-obvious. The doc-comment and the test must agree.
- **TDD:** write the failing test first, run it, see it fail, then implement. Every task ends green.
- **Verbatim slices:** curation writes MUST NOT route through `TRuleBook.SaveToString` / `SaveCompleteToString`. Those re-emit canonical DSL; a block that was merely moved would come back reformatted. `ConvRules.Model` may be used to **parse** (read `LinkTo`/`LinkFrom`/`Cast`), never to emit.
- **Line endings of data files:** `.rules` and `.castlib` are written back with the terminators they were read with. Blocks carry their own terminators inside `RawText`, so a join reproduces them; no normalisation anywhere.
- **No schema change:** this plan touches no SQLite database and no engine source. Editor + tests only.
- **Test runner:** all new tests live in `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` and use its existing `Check(name, cond, detail)` / `Skip(name, reason)` helpers. Exactly one test procedure per EARS acceptance criterion.
- **Build:** `dcc64` via `rsvars.bat`, run from PowerShell `Start-Process -Wait` with output redirected to a log; a build is good when the log shows `BUILD_EXITCODE=0` and no `Error:` lines. Never run `cmd.exe /c "build.bat"` from the Bash tool -- it hangs until timeout.
- **Commits:** one commit per task, on `feat/converter-editor`. Do NOT push -- the user holds push.
- **Do not touch** `docs/examples/convrules/sample.rules`: it holds the user's live `TabcToggleBtn -> TcxButton` test data. Tests read it as a fixture, read-only.

## Phases, effort and milestones

The eight tasks group into four phases. Each phase boundary is a natural review checkpoint; each task inside a phase is independently reviewable and independently committed.

| Phase | Tasks | Deliverable | Effort |
|---|---|---|---|
| 1 -- Foundation | 1, 2, 3 | Pure block parsing with byte-faithful round-trip, plus split/copy/delete. Criteria 1, 2, 3, 4, 12, 13. | 6-8 h |
| 2 -- Merge and compose | 4, 5 | Link-level merge semantics with conflict detection, apply, and precedence composition. Criteria 5, 6, 7, 8, 9. | 4-5 h |
| 3 -- Files and engine | 6, 7 | Working set, rotating-backup writes shared with the main form, composed output accepted by `convert-validate`. Criteria 10, 11, 14. | 3-4 h |
| 4 -- UI | 8 | Modal curation form and the main-form entry point; manual verification checklist. | 5-7 h |

**Total: ~18-24 hours.**

Milestone checks -- run these at each phase boundary before moving on:

- **M1 (after Task 3):** `SplitRulesBlocks`/`SplitCastLibBlocks` parse the real `sample.rules` and `casts.castlib`, `JoinBlocks` reproduces both byte-for-byte, and every phase-1 test passes headlessly -- no VCL, no engine spawn, no file system.
- **M2 (after Task 5):** a synthetic three-file working set composes with the earlier file winning every collision, and the report names each one.
- **M3 (after Task 7):** the composed file passes `convert-validate --rules <file>` with exit 0; backup rotation produces `.bak`, `.bak.2` ... without ever overwriting; a failed backup leaves every file untouched.
- **M4 (after Task 8):** both exes build clean, the whole suite is green, and the manual checklist in Task 8 Step 5 passes end to end.

## Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Round-trip fidelity silently breaks | HIGH | Criterion 1 is tested in Task 1 against the REAL `sample.rules`, not only synthetic input, before any operation exists. There is no re-emit path to regress to. |
| A merge drops content the spec did not describe | HIGH | Design decision 3: non-`#link` lines are appended, never dropped. Task 3's criterion-2 test asserts comments, blanks and unknown directives survive a move. |
| Conflict prompts explode on large books | MEDIUM | Compose auto-resolves by precedence and reports; interactive prompting exists only on the explicit `Merge from...` command. One prompt per conflict, not per link. |
| Blocks run together when appended | MEDIUM | `EnsureTrailingEol` guards every append path; Task 7 proves the result through the real `convert-validate`. |
| Composed file rejected by the engine | MEDIUM | Task 7 is a mandatory integration test, not a manual check. It reports the CLI's own error line plus the offending text. |
| Backup rotation overflows or clobbers | LOW | Reuses the main form's proven rotation, now shared rather than duplicated; criterion 11 asserts the FIRST backup still holds the original after a second write. |
| Read-only or locked target file | LOW | Criterion 14: the backup failure aborts before any write, and the UI half reports it in the status bar. |
| Two writers for one file (curation vs the main form's canonical Save) | MEDIUM | `DoCurate` prompts to save before opening the modal, and the main form reloads the file afterwards. Documented under Known follow-ups. |

## File Structure

| File | Responsibility |
|---|---|
| `src/tools/convrules-editor/ConvRules.BlockFile.pas` (new, pure) | Raw-line splitting that preserves terminators; split a `.rules` / `.castlib` text into `TRuleBlock` records holding verbatim text; rejoin byte-for-byte; grid label for a block. |
| `src/tools/convrules-editor/ConvRules.BlockOps.pas` (new, pure) | Block selection, split-out, copy-out, delete; link-level merge planning with conflict detection; merge application; compose with precedence. No file system. |
| `src/tools/convrules-editor/ConvRules.WorkingSet.pas` (new, pure, no VCL) | Ordered list of loaded files with their blocks (order = composition precedence); rotating-backup file writes; the one place that touches disk. |
| `src/tools/convrules-editor/ConvRules.CurationForm.pas` (new, VCL) | Modal curation window: working-set list, block grid with checkboxes, toolbar, conflict-resolution dialog. |
| `src/tools/convrules-editor/ConvRules.MainForm.pas` (modify) | Add a `Curate...` button; drop the private `BackupPath` and use the shared one. |
| `src/tools/convrules-editor/ConvRulesEditor.dpr` (modify) | Add the four new units to `uses`. |
| `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr` (modify) | 14 new test procedures, one per acceptance criterion. |
| `build/_build_convrules_editor_local.bat`, `build/_build_convrules_tests_local.bat` (new) | Checkout-relative build wrappers (`%~dp0`), so the worktree builds its OWN source instead of the hardcoded main checkout. |

## Design decisions the spec left open

Record these in the unit header comments as you implement them.

1. **Block header matching** is `SameText(Trim(HeaderA), Trim(HeaderB))` -- exact after trimming. `#convert A -> B, SomeUnit` and `#convert A -> B` therefore do NOT match, and the incoming one is appended as a new block. Deliberate: the units list changes what the rule does.
2. **Duplicate link** = same target AND same source AND same cast -> skip. Same target, same source, **different cast** -> conflict, because the generated assignment differs. This is the natural extension of the spec's row-2 rule.
3. **Non-`#link` lines in a matched incoming block** (`#default`, `#ignore`, `#note`, comments, unknown directives) are appended when no identical trimmed line already exists in the target block; blank lines are never appended. The spec only defines link merging, and silently dropping the rest would contradict its "nothing is orphaned" principle.
4. **Appends land at the end of the block**, after any trailing blank lines. Verbatim beats cosmetic.
5. **Line endings are carried, not detected.** An earlier draft of this plan proposed detecting each file's terminator on load and rewriting every `\n` to it on save. Do NOT do that: it is a whole-file normalisation, so a file with mixed terminators (or a stray lone `\r`) would come back changed even where curation touched nothing, which contradicts spec section 12 and would break criterion 1. Because `TRawLine` keeps each line's ACTUAL terminator inside `RawText`, terminators survive with no detection step and no write-side transformation at all. The only place a terminator is ever synthesised is when appending a new line to a block, and `BlockEol` takes it from that block's own first line.
6. **`MergeFrom` (spec section 5.2) is implemented as two functions**, `PlanMerge` then `ApplyMerge`. Criterion 6 requires that a conflict be reported and neither link written until it is resolved -- a single call cannot both report and write. Planning is pure and produces no text; applying takes the resolutions. Compose calls the same pair with an all-keep-earlier resolution set, which is how "composition and merge share one code path" (spec section 7) is honoured.

---

### Task 1: Block splitter for `.rules` + byte-faithful rejoin

Covers acceptance criterion 1 (`.rules` half).

**Files:**
- Create: `src/tools/convrules-editor/ConvRules.BlockFile.pas`
- Create: `build/_build_convrules_tests_local.bat`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `TRawLine`, `SplitRawLines`, `TRuleBlockKind`, `TRuleBlock`, `TRuleBlocks`, `SplitRulesBlocks`, `JoinBlocks`, `BlockEol`, `FirstToken` -- every later task builds on these exact names.

- [ ] **Step 1: Record the current test baseline**

Before changing anything, build and run the suite so you know what "no new failures" means.

Create `build/_build_convrules_tests_local.bat` (checkout-relative -- the existing `_build_convrules_tests.bat` hardcodes `C:\Projects\Delphi-RAG-lint` and would build the WRONG checkout):

```bat
@echo off
REM Build the ConvRulesEditor console test runner (Win64) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\convrules-editor\tests"
dcc64 -B -NSSystem;Vcl;Winapi;System.Win ConvRulesModelTests.dpr
echo BUILD_EXITCODE=%errorlevel%
```

Run it and the resulting exe from PowerShell:

```powershell
Start-Process -Wait -NoNewWindow -FilePath "C:\Projects\Delphi-RAG-lint-converter\build\_build_convrules_tests_local.bat" -RedirectStandardOutput "$env:TEMP\ct-build.log"
Get-Content "$env:TEMP\ct-build.log" -Tail 5
& "C:\Projects\Delphi-RAG-lint-converter\src\tools\convrules-editor\tests\ConvRulesModelTests.exe" | Select-Object -Last 3
```

Expected: `BUILD_EXITCODE=0` and a final line `model-tests: N pass / 0 fail / S skip / T total`. Write that N/S down -- it is the baseline. If `0 fail` is not already true, STOP and report; do not start on a red suite.

- [ ] **Step 2: Write the failing test**

Add to `ConvRulesModelTests.dpr`, above the final `begin`:

```pascal
{ Criterion 1a: splitting a .rules text into blocks and rejoining them in order
  reproduces the original byte-for-byte -- including its exact line terminators,
  its blank lines, and a missing final EOL. Tested on synthetic input AND on the
  real shipped sample.rules. }
procedure TestBlockSplitRulesRoundTrip;
const
  SRC =
    '// preamble comment'#13#10 +
    ''#13#10 +
    '#convert A.TFrom -> B.TTo'#13#10 +
    '#link Text <- Text'#13#10 +
    '; semicolon comment'#13#10 +
    ''#13#10 +
    '#convert C.TX -> D.TY, D'#13#10 +
    '#link Color <- Color';            // NOTE: no trailing EOL on purpose
var
  Blocks: TRuleBlocks;
  P     : string;
  Text  : string;
begin
  Blocks := SplitRulesBlocks(SRC);
  Check('blockfile.rules.count', Length(Blocks) = 3, IntToStr(Length(Blocks)));
  Check('blockfile.rules.kind0', Blocks[0].Kind = rbkPreamble, 'block 0 must be the preamble');
  Check('blockfile.rules.kind1', Blocks[1].Kind = rbkConvert, 'block 1 must be a #convert');
  Check('blockfile.rules.header1',
    Blocks[1].Header = '#convert A.TFrom -> B.TTo', Blocks[1].Header);
  Check('blockfile.rules.startline1', Blocks[1].StartLine = 3, IntToStr(Blocks[1].StartLine));
  Check('blockfile.rules.roundtrip', JoinBlocks(Blocks) = SRC,
    Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(SRC)]));

  // Edge cases: LF-only input keeps LF (terminators are carried, never detected or
  // rewritten), and empty input yields no blocks rather than one empty one.
  Blocks := SplitRulesBlocks('#convert A.T -> B.T'#10 + '#link P <- Q'#10);
  Check('blockfile.rules.lf.roundtrip',
    JoinBlocks(Blocks) = '#convert A.T -> B.T'#10 + '#link P <- Q'#10,
    'an LF-only file must come back LF-only');
  Check('blockfile.rules.lf.eol', BlockEol(Blocks[0]) = #10, 'BlockEol must report LF');
  Check('blockfile.rules.empty', Length(SplitRulesBlocks('')) = 0, 'empty text = no blocks');
  Check('blockfile.rules.empty.join', JoinBlocks(nil) = '', 'joining nothing yields ''''');

  // ...and against the real file (spec section 11: not only synthetic input).
  P := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\..\docs\examples\convrules\sample.rules'));
  if not TFile.Exists(P) then
  begin
    Skip('blockfile.rules.roundtrip.file', 'sample.rules not found: ' + P);
    Exit;
  end;
  Text := TFile.ReadAllText(P, TEncoding.ASCII);
  Blocks := SplitRulesBlocks(Text);
  Check('blockfile.rules.roundtrip.file', JoinBlocks(Blocks) = Text,
    Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(Text)]));
  Check('blockfile.rules.roundtrip.file.blocks', Length(Blocks) >= 3,
    'sample.rules has 3 #convert blocks + preamble');
end;
```

Register it in the main `begin` block, first in the list of new tests:

```pascal
    TestBlockSplitRulesRoundTrip;
```

Add the unit to the runner's `uses`, after `ConvRules.CastLib`:

```pascal
  ConvRules.BlockFile in '..\ConvRules.BlockFile.pas',
```

- [ ] **Step 3: Run the test to verify it fails**

Run: the build command from Step 1.
Expected: FAIL at compile time -- `F2613 Unit 'ConvRules.BlockFile' not found`. That is the correct first failure.

- [ ] **Step 4: Write the implementation**

Create `src/tools/convrules-editor/ConvRules.BlockFile.pas`:

```pascal
unit ConvRules.BlockFile;

{ Pure block splitter for the curation form.

  A rule-book (.rules) or catalog (.castlib) file is split into an ORDERED list of
  blocks, each holding its RAW TEXT verbatim -- header line, body, comments,
  blank lines, unknown directives and the file's own line terminators. Every
  curation operation moves raw text; nothing is ever re-emitted from a parsed
  model, because:

    - sample.rules asserts that '//' and ';' hand comments survive round-trip;
    - LoadCastLibText deliberately tolerates unknown keys so newer files stay
      readable by older builds -- re-emitting would silently delete them.

  So the load-bearing guarantee of this unit is: JoinBlocks(SplitXxxBlocks(T)) = T,
  byte for byte, for any T.

  Pure + headless (no VCL, no file system, no process spawn) so it is unit-tested
  against inline fixtures and the real shipped files. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  /// <summary>One source line plus the exact terminator that followed it.</summary>
  /// <remarks>Eol is '' for a final line with no terminator, otherwise the bytes
  /// actually found (#13#10, #10 or #13). Text+Eol concatenated over all lines
  /// reproduces the source exactly -- this is why the unit does not use
  /// TStringList, whose Text property normalises terminators.</remarks>
  TRawLine = record
    Text: string;
    Eol : string;
  end;

  /// <summary>What a block is.</summary>
  TRuleBlockKind = (
    rbkPreamble,   // content before the first real block (file header comments)
    rbkConvert,    // .rules: '#convert From -> To [, unit ...]'
    rbkCast,       // .castlib: 'cast <Name> ... end'
    rbkEnum        // .castlib: 'enum <Name> ... end'
  );

  /// <summary>One block of a rule-book or catalog file, carrying its verbatim text.</summary>
  /// <remarks>RawText includes the header line and every terminator inside the
  /// block, so blocks concatenate back into the original file. StartLine/EndLine
  /// are 1-based line numbers in the source, for display only.</remarks>
  TRuleBlock = record
    Kind     : TRuleBlockKind;
    Header   : string;    // the header line verbatim (no terminator); '' for a preamble
    RawText  : string;    // the whole block including its header, verbatim
    StartLine: Integer;
    EndLine  : Integer;
  end;

  TRuleBlocks = TArray<TRuleBlock>;

/// <summary>PURE: split text into lines, keeping each line's exact terminator.</summary>
/// <param name="AText">Any text; '' yields an empty array.</param>
/// <returns>Lines in order; concatenating Text+Eol reproduces AText byte for byte.</returns>
function SplitRawLines(const AText: string): TArray<TRawLine>;

/// <summary>PURE: the first whitespace-delimited token of a line, '' when blank.</summary>
function FirstToken(const ALine: string): string;

/// <summary>PURE: the second whitespace-delimited token of a line, '' when absent.</summary>
function SecondToken(const ALine: string): string;

/// <summary>PURE: split a .rules text into blocks. A block starts at a line whose
/// first token is '#convert' and runs to the line before the next '#convert', or
/// to end of file. Anything before the first '#convert' is one rbkPreamble block.</summary>
function SplitRulesBlocks(const AText: string): TRuleBlocks;

/// <summary>PURE: rejoin blocks in order. JoinBlocks(SplitRulesBlocks(T)) = T.</summary>
function JoinBlocks(const ABlocks: TRuleBlocks): string;

/// <summary>PURE: the line terminator this block uses (its first line's), or CRLF
/// when the block has none (a single unterminated line).</summary>
function BlockEol(const ABlock: TRuleBlock): string;

implementation

function SplitRawLines(const AText: string): TArray<TRawLine>;
var
  List : TList<TRawLine>;
  i, St: Integer;
  L    : TRawLine;
begin
  List := TList<TRawLine>.Create;
  try
    i := 1;
    St := 1;
    while i <= Length(AText) do
    begin
      if CharInSet(AText[i], [#13, #10]) then
      begin
        L.Text := Copy(AText, St, i - St);
        if (AText[i] = #13) and (i < Length(AText)) and (AText[i + 1] = #10) then
        begin
          L.Eol := #13#10;
          Inc(i, 2);
        end
        else
        begin
          L.Eol := AText[i];
          Inc(i);
        end;
        List.Add(L);
        St := i;
      end
      else
        Inc(i);
    end;
    if St <= Length(AText) then
    begin
      L.Text := Copy(AText, St, MaxInt);
      L.Eol  := '';
      List.Add(L);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function FirstToken(const ALine: string): string;
var
  S: string;
  p: Integer;
begin
  S := TrimLeft(ALine);
  p := 1;
  while (p <= Length(S)) and (S[p] > ' ') do Inc(p);
  Result := Copy(S, 1, p - 1);
end;

function SecondToken(const ALine: string): string;
var
  S: string;
begin
  S := TrimLeft(ALine);
  S := TrimLeft(Copy(S, Length(FirstToken(S)) + 1, MaxInt));
  Result := FirstToken(S);
end;

function SplitRulesBlocks(const AText: string): TRuleBlocks;
var
  Lines : TArray<TRawLine>;
  Blocks: TList<TRuleBlock>;
  Cur   : TRuleBlock;
  Have  : Boolean;
  i     : Integer;
begin
  Lines  := SplitRawLines(AText);
  Blocks := TList<TRuleBlock>.Create;
  try
    Have := False;
    Cur  := Default(TRuleBlock);
    for i := 0 to High(Lines) do
    begin
      if SameText(FirstToken(Lines[i].Text), '#convert') then
      begin
        if Have then Blocks.Add(Cur);
        Cur := Default(TRuleBlock);
        Cur.Kind      := rbkConvert;
        Cur.Header    := Lines[i].Text;
        Cur.StartLine := i + 1;
        Have := True;
      end
      else if not Have then
      begin
        Cur := Default(TRuleBlock);
        Cur.Kind      := rbkPreamble;
        Cur.Header    := '';
        Cur.StartLine := i + 1;
        Have := True;
      end;
      Cur.RawText := Cur.RawText + Lines[i].Text + Lines[i].Eol;
      Cur.EndLine := i + 1;
    end;
    if Have then Blocks.Add(Cur);
    Result := Blocks.ToArray;
  finally
    Blocks.Free;
  end;
end;

function JoinBlocks(const ABlocks: TRuleBlocks): string;
var
  B: TRuleBlock;
begin
  Result := '';
  for B in ABlocks do
    Result := Result + B.RawText;
end;

function BlockEol(const ABlock: TRuleBlock): string;
var
  Lines: TArray<TRawLine>;
begin
  Lines := SplitRawLines(ABlock.RawText);
  if (Length(Lines) > 0) and (Lines[0].Eol <> '') then
    Result := Lines[0].Eol
  else
    Result := #13#10;
end;

end.
```

- [ ] **Step 5: Run the test to verify it passes**

Run: the build command from Step 1, then the exe.
Expected: `BUILD_EXITCODE=0`, the six `blockfile.rules.*` checks PASS, and total pass count = baseline + 7 (six synthetic + one file check pair counts as two -- read the actual PASS lines, do not guess), `0 fail`.

- [ ] **Step 6: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.BlockFile.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr build/_build_convrules_tests_local.bat
git commit -m "feat(convrules): verbatim block splitter for .rules files"
```

---

### Task 2: `.castlib` blocks + grid labels

Covers acceptance criteria 1 (`.castlib` half) and 13.

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.BlockFile.pas`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `TRuleBlock`, `TRuleBlocks`, `SplitRawLines`, `FirstToken`, `SecondToken`, `JoinBlocks` (Task 1).
- Produces: `SplitCastLibBlocks(const AText: string): TRuleBlocks`, `SplitBlocksFor(const APath, AText: string): TRuleBlocks`, `BlockLabel(const ABlock: TRuleBlock): string`.

- [ ] **Step 1: Write the failing tests**

```pascal
{ Criterion 1b: the same byte-faithful round-trip for .castlib, whose blocks are
  'cast <Name> ... end' / 'enum <Name> ... end'. Content before the first block is
  a preamble; content BETWEEN blocks attaches to the preceding block so nothing is
  orphaned. }
procedure TestBlockSplitCastLibRoundTrip;
const
  SRC =
    '# file header'#13#10 +
    ''#13#10 +
    'cast AssignGraphic'#13#10 +
    '  accepts TPicture, TBitmap'#13#10 +
    '  yields  TdxSmartGlyph'#13#10 +
    'end'#13#10 +
    ''#13#10 +
    'enum ButtonLayout'#13#10 +
    '  ablGlyphLeft -> blGlyphLeft'#13#10 +
    'end'#13#10;
var
  Blocks: TRuleBlocks;
  P, Txt: string;
begin
  Blocks := SplitCastLibBlocks(SRC);
  Check('blockfile.castlib.count', Length(Blocks) = 3, IntToStr(Length(Blocks)));
  Check('blockfile.castlib.kind0', Blocks[0].Kind = rbkPreamble, 'block 0 preamble');
  Check('blockfile.castlib.kind1', Blocks[1].Kind = rbkCast, 'block 1 cast');
  Check('blockfile.castlib.kind2', Blocks[2].Kind = rbkEnum, 'block 2 enum');
  Check('blockfile.castlib.trailing',
    Blocks[1].RawText.EndsWith('end'#13#10 + ''#13#10),
    'the blank line after "end" must attach to the preceding block');
  Check('blockfile.castlib.roundtrip', JoinBlocks(Blocks) = SRC,
    Format('got %d bytes, want %d', [Length(JoinBlocks(Blocks)), Length(SRC)]));

  P := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\..\..\docs\examples\convrules\casts.castlib'));
  if not TFile.Exists(P) then
  begin
    Skip('blockfile.castlib.roundtrip.file', 'casts.castlib not found: ' + P);
    Exit;
  end;
  Txt := TFile.ReadAllText(P, TEncoding.ASCII);
  Check('blockfile.castlib.roundtrip.file',
    JoinBlocks(SplitCastLibBlocks(Txt)) = Txt, 'shipped casts.castlib must round-trip');
end;

{ Criterion 13: WHERE the open file is a .castlib the grid shows cast/enum block
  NAMES in place of #convert type pairs. BlockLabel is what the grid displays. }
procedure TestBlockLabel;
const
  RULES = '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont, Vcl.Graphics'#13#10 +
          '#link Color <- Color'#13#10;
  LIB   = '# header'#13#10 +
          'cast AssignGraphic'#13#10 + 'end'#13#10 +
          'enum ButtonLayout'#13#10 + 'end'#13#10;
var
  R, L: TRuleBlocks;
begin
  R := SplitRulesBlocks(RULES);
  L := SplitCastLibBlocks(LIB);
  Check('blocklabel.convert',
    BlockLabel(R[0]) = 'Vcl.Graphics.TFont -> Vcl.Graphics.TFont, Vcl.Graphics',
    BlockLabel(R[0]));
  Check('blocklabel.cast', BlockLabel(L[1]) = 'AssignGraphic', BlockLabel(L[1]));
  Check('blocklabel.enum', BlockLabel(L[2]) = 'ButtonLayout', BlockLabel(L[2]));
  Check('blocklabel.preamble', BlockLabel(L[0]) = '(file header)', BlockLabel(L[0]));
  // extension chosen by file extension, not by sniffing content
  Check('blockfile.byext.castlib',
    Length(SplitBlocksFor('x.castlib', LIB)) = 3, 'castlib grammar by extension');
  Check('blockfile.byext.rules',
    Length(SplitBlocksFor('x.rules', RULES)) = 1, 'rules grammar by extension');
  // Edge case: a file with nothing but a preamble is one preamble block, not zero
  // and not a malformed convert block.
  var Only: TRuleBlocks := SplitRulesBlocks('// just a header'#13#10 + '; nothing else'#13#10);
  Check('blockfile.preamble.only', Length(Only) = 1, IntToStr(Length(Only)));
  Check('blockfile.preamble.only.kind', Only[0].Kind = rbkPreamble, 'must be a preamble');
  Check('blockfile.preamble.only.roundtrip',
    JoinBlocks(Only) = '// just a header'#13#10 + '; nothing else'#13#10, 'must round-trip');
end;
```

Register both in the main `begin` block after `TestBlockSplitRulesRoundTrip`.

- [ ] **Step 2: Run to verify they fail**

Run: the build from Task 1 Step 1.
Expected: FAIL at compile time -- `E2003 Undeclared identifier: 'SplitCastLibBlocks'`.

- [ ] **Step 3: Implement**

Add to the `interface` of `ConvRules.BlockFile.pas`, after `SplitRulesBlocks`:

```pascal
/// <summary>PURE: split a .castlib text into blocks. A block starts at a line whose
/// first token is 'cast' or 'enum'. Content before the first block becomes an
/// rbkPreamble block; content between blocks (including the 'end' line and any
/// trailing blanks) attaches to the PRECEDING block, so nothing is orphaned.</summary>
function SplitCastLibBlocks(const AText: string): TRuleBlocks;

/// <summary>PURE: pick the grammar from APath's extension -- '.castlib' uses the
/// catalog grammar, anything else (.rules and reFind files) uses the DSL grammar.</summary>
function SplitBlocksFor(const APath, AText: string): TRuleBlocks;

/// <summary>PURE: what the curation grid shows for a block: the type pair for a
/// #convert, the bare NAME for a cast/enum, '(file header)' for a preamble.</summary>
function BlockLabel(const ABlock: TRuleBlock): string;
```

And to the `implementation` -- note `SplitRulesBlocks` and `SplitCastLibBlocks` share one loop through a header-test callback, so the round-trip guarantee is implemented exactly once:

```pascal
type
  { Decides whether a line starts a new block, and of what kind. A plain function
    pointer (not "of object") so the two grammars stay unit-level and closure-free. }
  THeaderTest = function(const ALine: string; out AKind: TRuleBlockKind): Boolean;

function RulesHeaderTest(const ALine: string; out AKind: TRuleBlockKind): Boolean;
begin
  AKind := rbkConvert;
  Result := SameText(FirstToken(ALine), '#convert');
end;

function CastLibHeaderTest(const ALine: string; out AKind: TRuleBlockKind): Boolean;
var
  Tok: string;
begin
  Tok := FirstToken(ALine);
  if SameText(Tok, 'cast') then      begin AKind := rbkCast; Exit(True); end;
  if SameText(Tok, 'enum') then      begin AKind := rbkEnum; Exit(True); end;
  AKind := rbkPreamble;
  Result := False;
end;

{ The one splitting loop. Lines that do not start a block accumulate into the
  current block; before the first header they accumulate into a preamble block. }
function SplitOnHeaders(const AText: string; ATest: THeaderTest): TRuleBlocks;
var
  Lines : TArray<TRawLine>;
  Blocks: TList<TRuleBlock>;
  Cur   : TRuleBlock;
  Have  : Boolean;
  i     : Integer;
  Kind  : TRuleBlockKind;
begin
  Lines  := SplitRawLines(AText);
  Blocks := TList<TRuleBlock>.Create;
  try
    Have := False;
    Cur  := Default(TRuleBlock);
    for i := 0 to High(Lines) do
    begin
      if ATest(Lines[i].Text, Kind) then
      begin
        if Have then Blocks.Add(Cur);
        Cur := Default(TRuleBlock);
        Cur.Kind      := Kind;
        Cur.Header    := Lines[i].Text;
        Cur.StartLine := i + 1;
        Have := True;
      end
      else if not Have then
      begin
        Cur := Default(TRuleBlock);
        Cur.Kind      := rbkPreamble;
        Cur.Header    := '';
        Cur.StartLine := i + 1;
        Have := True;
      end;
      Cur.RawText := Cur.RawText + Lines[i].Text + Lines[i].Eol;
      Cur.EndLine := i + 1;
    end;
    if Have then Blocks.Add(Cur);
    Result := Blocks.ToArray;
  finally
    Blocks.Free;
  end;
end;

function SplitCastLibBlocks(const AText: string): TRuleBlocks;
begin
  Result := SplitOnHeaders(AText, CastLibHeaderTest);
end;

function SplitBlocksFor(const APath, AText: string): TRuleBlocks;
begin
  if SameText(ExtractFileExt(APath), '.castlib') then
    Result := SplitCastLibBlocks(AText)
  else
    Result := SplitRulesBlocks(AText);
end;

function BlockLabel(const ABlock: TRuleBlock): string;
begin
  case ABlock.Kind of
    rbkConvert:
      Result := Trim(Copy(TrimLeft(ABlock.Header), Length('#convert') + 1, MaxInt));
    rbkCast, rbkEnum:
      Result := SecondToken(ABlock.Header);
  else
    Result := '(file header)';
  end;
end;
```

Replace the body of `SplitRulesBlocks` with the shared loop (delete its duplicated implementation from Task 1):

```pascal
function SplitRulesBlocks(const AText: string): TRuleBlocks;
begin
  Result := SplitOnHeaders(AText, RulesHeaderTest);
end;
```

- [ ] **Step 4: Run to verify they pass**

Run: build + exe.
Expected: all `blockfile.castlib.*` and `blocklabel.*` checks PASS, `0 fail`, and the Task 1 round-trip checks still PASS (the shared loop must not have changed `.rules` behaviour).

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.BlockFile.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): .castlib block grammar + grid labels"
```

---

### Task 3: Split-out / copy-out / delete

Covers acceptance criteria 2, 3, 4 and 12.

**Files:**
- Create: `src/tools/convrules-editor/ConvRules.BlockOps.pas`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `TRuleBlock`, `TRuleBlocks`, `JoinBlocks`, `SplitRulesBlocks` (Tasks 1-2).
- Produces:
  - `function SelectBlocks(const ABlocks: TRuleBlocks; const AIndexes: TArray<Integer>): TRuleBlocks;`
  - `function DeleteBlocks(const ABlocks: TRuleBlocks; const AIndexes: TArray<Integer>): TRuleBlocks;`
  - `procedure SplitOut(const ASource: TRuleBlocks; const AIndexes: TArray<Integer>; out ARemaining, AMoved: TRuleBlocks);`
  - `function CopyOut(const ASource: TRuleBlocks; const AIndexes: TArray<Integer>): TRuleBlocks;`
  - `function CanOperateOn(const ASelected: TArray<Integer>): Boolean;`

- [ ] **Step 1: Write the failing tests**

```pascal
{ Criteria 3 + 4 + 2: split-out REMOVES the selected blocks from the source and
  writes them to the target in their original relative order; copy-out writes them
  and leaves the source unchanged; a moved block keeps its comments, blank lines
  and unrecognised directives verbatim. }
procedure TestBlockOpsSplitAndCopy;
const
  SRC =
    '// file header'#13#10 +
    '#convert A.T1 -> B.T1'#13#10 +
    '#link P <- P'#13#10 +
    '#convert A.T2 -> B.T2'#13#10 +
    '// hand comment inside the moved block'#13#10 +
    '; semicolon comment'#13#10 +
    ''#13#10 +
    '#weird unrecognised directive'#13#10 +
    '#link Q <- Q'#13#10 +
    '#convert A.T3 -> B.T3'#13#10 +
    '#link R <- R'#13#10;
var
  Blocks, Rem, Moved, Copied: TRuleBlocks;
begin
  Blocks := SplitRulesBlocks(SRC);          // [preamble, T1, T2, T3]
  Check('blockops.setup', Length(Blocks) = 4, IntToStr(Length(Blocks)));

  // criterion 3 -- split out blocks 2 and 3 (T2, T3)
  SplitOut(Blocks, [2, 3], Rem, Moved);
  Check('blockops.split.remaining', Length(Rem) = 2, IntToStr(Length(Rem)));
  Check('blockops.split.moved', Length(Moved) = 2, IntToStr(Length(Moved)));
  Check('blockops.split.order',
    (Moved[0].Header = '#convert A.T2 -> B.T2') and
    (Moved[1].Header = '#convert A.T3 -> B.T3'), 'original relative order');
  Check('blockops.split.source.lost.t2',
    Pos('A.T2', JoinBlocks(Rem)) = 0, 'T2 must be gone from the source');
  Check('blockops.split.source.kept.t1',
    Pos('A.T1', JoinBlocks(Rem)) > 0, 'T1 must survive in the source');

  // criterion 2 -- everything inside the moved block survives verbatim
  Check('blockops.split.keeps.slashcomment',
    Pos('// hand comment inside the moved block', Moved[0].RawText) > 0, 'lost //');
  Check('blockops.split.keeps.semicomment',
    Pos('; semicolon comment', Moved[0].RawText) > 0, 'lost ;');
  Check('blockops.split.keeps.blankline',
    Pos(#13#10 + #13#10, Moved[0].RawText) > 0, 'lost blank line');
  Check('blockops.split.keeps.unknown',
    Pos('#weird unrecognised directive', Moved[0].RawText) > 0, 'lost unknown directive');

  // criterion 4 -- copy leaves the source alone
  Copied := CopyOut(Blocks, [1]);
  Check('blockops.copy.count', Length(Copied) = 1, IntToStr(Length(Copied)));
  Check('blockops.copy.header', Copied[0].Header = '#convert A.T1 -> B.T1', Copied[0].Header);
  Check('blockops.copy.source.unchanged', JoinBlocks(Blocks) = SRC,
    'CopyOut must not mutate the source blocks');
end;

{ Criterion 12: WHILE no blocks are selected the Split, Copy and Delete commands
  are disabled. CanOperateOn is the single rule the form's enablement uses. }
procedure TestBlockOpsEnablement;
begin
  Check('blockops.enable.none', not CanOperateOn([]), 'empty selection must disable');
  Check('blockops.enable.one', CanOperateOn([0]), 'one selected block must enable');
  Check('blockops.enable.many', CanOperateOn([1, 4]), 'several selected must enable');
end;
```

Register both after `TestBlockLabel`; add `ConvRules.BlockOps in '..\ConvRules.BlockOps.pas',` to the runner's `uses`.

- [ ] **Step 2: Run to verify they fail**

Expected: `F2613 Unit 'ConvRules.BlockOps' not found`.

- [ ] **Step 3: Implement**

Create `src/tools/convrules-editor/ConvRules.BlockOps.pas`:

```pascal
unit ConvRules.BlockOps;

{ Pure curation operations over block lists: select, delete, split out, copy out,
  and (from the next task) link-level merge and compose.

  Every operation moves the blocks' RAW TEXT, so a block that was merely moved is
  byte-identical to what it was in its old file -- comments, blank lines and
  unrecognised directives included. Nothing here touches the file system or VCL, so
  all of it is unit-tested against inline fixtures. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  ConvRules.BlockFile;

/// <summary>PURE: the blocks at AIndexes, in ASCENDING index order regardless of
/// the order AIndexes were given in (the grid may report checks out of order).
/// Out-of-range indexes are ignored.</summary>
function SelectBlocks(const ABlocks: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: ABlocks minus the blocks at AIndexes, order otherwise preserved.</summary>
function DeleteBlocks(const ABlocks: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: move blocks out -- ARemaining is the source without them,
/// AMoved is the blocks themselves in their original relative order.</summary>
procedure SplitOut(const ASource: TRuleBlocks; const AIndexes: TArray<Integer>;
  out ARemaining, AMoved: TRuleBlocks);

/// <summary>PURE: the blocks to write elsewhere; the source is not modified.</summary>
function CopyOut(const ASource: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: the enablement rule for the Split / Copy / Delete commands --
/// they operate on a selection, so an empty selection disables them.</summary>
function CanOperateOn(const ASelected: TArray<Integer>): Boolean;

implementation

uses
  System.Generics.Defaults;

{ Ascending, de-duplicated copy of a selection. }
function NormalizeIndexes(const AIndexes: TArray<Integer>; ACount: Integer): TArray<Integer>;
var
  List: TList<Integer>;
  i   : Integer;
begin
  List := TList<Integer>.Create;
  try
    for i in AIndexes do
      if (i >= 0) and (i < ACount) and (List.IndexOf(i) < 0) then List.Add(i);
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function SelectBlocks(const ABlocks: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;
var
  Idx: TArray<Integer>;
  i  : Integer;
begin
  Idx := NormalizeIndexes(AIndexes, Length(ABlocks));
  SetLength(Result, Length(Idx));
  for i := 0 to High(Idx) do
    Result[i] := ABlocks[Idx[i]];
end;

function DeleteBlocks(const ABlocks: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;
var
  Idx : TArray<Integer>;
  List: TList<TRuleBlock>;
  i   : Integer;

  function Selected(AIndex: Integer): Boolean;
  var
    k: Integer;
  begin
    for k in Idx do
      if k = AIndex then Exit(True);
    Result := False;
  end;

begin
  Idx  := NormalizeIndexes(AIndexes, Length(ABlocks));
  List := TList<TRuleBlock>.Create;
  try
    for i := 0 to High(ABlocks) do
      if not Selected(i) then List.Add(ABlocks[i]);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure SplitOut(const ASource: TRuleBlocks; const AIndexes: TArray<Integer>;
  out ARemaining, AMoved: TRuleBlocks);
begin
  AMoved     := SelectBlocks(ASource, AIndexes);
  ARemaining := DeleteBlocks(ASource, AIndexes);
end;

function CopyOut(const ASource: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;
begin
  Result := SelectBlocks(ASource, AIndexes);
end;

function CanOperateOn(const ASelected: TArray<Integer>): Boolean;
begin
  Result := Length(ASelected) > 0;
end;

end.
```

- [ ] **Step 4: Run to verify they pass**

Expected: every `blockops.split.*`, `blockops.copy.*` and `blockops.enable.*` check PASSes, `0 fail`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.BlockOps.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): split-out / copy-out / delete over verbatim blocks"
```

---

### Task 4: Merge planning -- duplicates, conflicts, fan-out, whole-block append

Covers acceptance criteria 5, 6, 7 and 8.

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.BlockOps.pas`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: everything from Task 3, plus `ConvRules.Model` (`TRuleBook`, `TRuleNode`, `rnkLink`) for PARSING link lines only.
- Produces:
  - `TMergeAction = (maAppendBlock, maMergeLink, maMergeOther, maSkipDuplicate, maConflict);`
  - `TMergeItem` record (fields listed below)
  - `TMergePlan` record with `Target`, `Incoming`, `Items`, and `function ConflictCount: Integer;`
  - `function BlockLinks(const ABlock: TRuleBlock): TArray<TBlockLink>;`
  - `function PlanMerge(const ATarget, AIncoming: TRuleBlocks): TMergePlan;`

- [ ] **Step 1: Write the failing tests**

```pascal
{ Criterion 5: an incoming #link whose target is already linked FROM THE SAME
  source is a duplicate and is skipped. }
procedure TestMergeSkipsDuplicate;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
begin
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.dup.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.dup.action', Plan.Items[0].Action = maSkipDuplicate, 'must be a skip');
  Check('merge.dup.noconflict', Plan.ConflictCount = 0, 'a duplicate is not a conflict');
end;

{ Criterion 6: an incoming #link whose target is already linked from a DIFFERENT
  source is a conflict; planning reports it and writes nothing -- neither link is
  merged until a resolution is supplied. }
procedure TestMergeReportsConflict;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
  k   : Integer;
  Merged: Boolean;
begin
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Z'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.conflict.count', Plan.ConflictCount = 1, IntToStr(Plan.ConflictCount));
  Check('merge.conflict.to', Plan.Items[0].ToPath = 'P', Plan.Items[0].ToPath);
  Check('merge.conflict.existingfrom', Plan.Items[0].ExistingFrom = 'Q',
    Plan.Items[0].ExistingFrom);
  Check('merge.conflict.incomingfrom', Plan.Items[0].IncomingFrom = 'Z',
    Plan.Items[0].IncomingFrom);
  Merged := False;
  for k := 0 to High(Plan.Items) do
    if Plan.Items[k].Action in [maMergeLink, maMergeOther] then Merged := True;
  Check('merge.conflict.nothing.written', not Merged,
    'planning a conflict must not queue either link for writing');
  Check('merge.conflict.target.untouched',
    JoinBlocks(Plan.Target) = '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10,
    'planning must not mutate the target');

  // same target, same source, DIFFERENT cast -> also a conflict (design decision 2)
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q : Round'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.conflict.cast', Plan.ConflictCount = 1,
    'a differing cast changes the generated assignment, so it is a conflict');
end;

{ Criterion 7: an already-used SOURCE feeding a NEW target is legal fan-out and is
  merged, not flagged. }
procedure TestMergeAllowsFanOut;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
begin
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link R <- Q'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.fanout.noconflict', Plan.ConflictCount = 0, 'fan-out is never a conflict');
  Check('merge.fanout.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.fanout.action', Plan.Items[0].Action = maMergeLink, 'must be merged');
  Check('merge.fanout.line', Plan.Items[0].Line = '#link R <- Q', Plan.Items[0].Line);
end;

{ Criterion 8: an incoming block whose header has no counterpart in the target is
  appended WHOLE and verbatim. }
procedure TestMergeAppendsUnmatchedBlock;
var
  Plan: TMergePlan;
  T, I: TRuleBlocks;
begin
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks(
    '#convert X.T -> Y.T'#13#10 +
    '// keep me'#13#10 +
    '#link M <- N'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.append.count', Length(Plan.Items) = 1, IntToStr(Length(Plan.Items)));
  Check('merge.append.action', Plan.Items[0].Action = maAppendBlock, 'must append whole');
  Check('merge.append.idx', Plan.Items[0].IncomingBlockIdx = 0,
    IntToStr(Plan.Items[0].IncomingBlockIdx));
  Check('merge.append.verbatim',
    Plan.Incoming[Plan.Items[0].IncomingBlockIdx].RawText =
      '#convert X.T -> Y.T'#13#10 + '// keep me'#13#10 + '#link M <- N'#13#10,
    'the appended block keeps its comment');
  // a header that differs only by its units list does NOT match
  T := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  I := SplitRulesBlocks('#convert A.T -> B.T, SomeUnit'#13#10 + '#link P <- Q'#13#10);
  Plan := PlanMerge(T, I);
  Check('merge.append.unitsdiffer', Plan.Items[0].Action = maAppendBlock,
    'a differing units list is a different rule, so it is appended not merged');
end;
```

Register all four after `TestBlockOpsEnablement`.

- [ ] **Step 2: Run to verify they fail**

Expected: `E2003 Undeclared identifier: 'PlanMerge'`.

- [ ] **Step 3: Implement**

Add to `ConvRules.BlockOps.pas` -- `interface` `uses` gains `ConvRules.Model`:

```pascal
type
  /// <summary>One #link inside a block, with its verbatim source line.</summary>
  /// <remarks>Parsed with TRuleBook so the DSL grammar lives in exactly one place;
  /// Line is the ORIGINAL text and is what gets written, never a re-emission.</remarks>
  TBlockLink = record
    Line    : string;   // verbatim source line, no terminator
    LinkTo  : string;   // target path (left of '<-')
    LinkFrom: string;   // source path (right of '<-')
    Cast    : string;   // optional cast name ('' = identity)
  end;

  /// <summary>What the merger decided to do with one incoming line or block.</summary>
  TMergeAction = (
    maAppendBlock,    // incoming block has no counterpart -> append it whole
    maMergeLink,      // incoming #link is missing from the target -> append the line
    maMergeOther,     // incoming non-link line not already present -> append the line
    maSkipDuplicate,  // identical link already present -> do nothing
    maConflict        // target already linked from a different source (or cast)
  );

  /// <summary>One planned merge decision.</summary>
  TMergeItem = record
    Action          : TMergeAction;
    TargetBlockIdx  : Integer;   // index into TMergePlan.Target; -1 for maAppendBlock
    IncomingBlockIdx: Integer;   // index into TMergePlan.Incoming
    Line            : string;    // the incoming line, verbatim ('' for maAppendBlock)
    ToPath          : string;    // contested/merged target path ('' when n/a)
    ExistingLine    : string;    // maConflict: the target's current #link line
    ExistingFrom    : string;    // maConflict: its source path
    IncomingFrom    : string;    // maConflict: the incoming source path
  end;

  /// <summary>A merge worked out but NOT applied. Planning is pure and writes
  /// nothing, which is what lets a conflict be reported before either link is
  /// written (acceptance criterion 6).</summary>
  TMergePlan = record
    Target  : TRuleBlocks;
    Incoming: TRuleBlocks;
    Items   : TArray<TMergeItem>;
    /// <summary>How many items need a user decision.</summary>
    function ConflictCount: Integer;
  end;

/// <summary>PURE: the #link lines of one block, parsed via TRuleBook (read-only --
/// the model is never asked to re-emit).</summary>
function BlockLinks(const ABlock: TRuleBlock): TArray<TBlockLink>;

/// <summary>PURE: work out how AIncoming would fold into ATarget. Blocks are matched
/// by trimmed header, case-insensitively. Within a matched pair: an identical link
/// is skipped; a target already linked from a different source (or with a different
/// cast) is a CONFLICT; a new target -- including one fed by an already-used source
/// -- is merged; non-link lines not already present are merged. An incoming block
/// with no counterpart is appended whole.</summary>
/// <returns>A plan; ATarget and AIncoming are copied into it unmodified.</returns>
function PlanMerge(const ATarget, AIncoming: TRuleBlocks): TMergePlan;
```

Implementation:

```pascal
function TMergePlan.ConflictCount: Integer;
var
  It: TMergeItem;
begin
  Result := 0;
  for It in Items do
    if It.Action = maConflict then Inc(Result);
end;

function BlockLinks(const ABlock: TRuleBlock): TArray<TBlockLink>;
var
  Book: TRuleBook;
  List: TList<TBlockLink>;
  i   : Integer;
  L   : TBlockLink;
begin
  List := TList<TBlockLink>.Create;
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(ABlock.RawText);
    for i := 0 to Book.Nodes.Count - 1 do
      if Book.Nodes[i].Kind = rnkLink then
      begin
        L.Line     := Book.Nodes[i].Raw;
        L.LinkTo   := Book.Nodes[i].LinkTo;
        L.LinkFrom := Book.Nodes[i].LinkFrom;
        L.Cast     := Book.Nodes[i].Cast;
        List.Add(L);
      end;
    Result := List.ToArray;
  finally
    Book.Free;
    List.Free;
  end;
end;

{ Every line of a block except its header, its #link lines and its blank lines --
  i.e. #default / #ignore / #note / comments / unknown directives. }
function BlockOtherLines(const ABlock: TRuleBlock): TArray<string>;
var
  Lines: TArray<TRawLine>;
  List : TList<string>;
  i, i0: Integer;
begin
  List  := TList<string>.Create;
  try
    Lines := SplitRawLines(ABlock.RawText);
    if ABlock.Kind = rbkPreamble then i0 := 0 else i0 := 1;   // skip the header line
    for i := i0 to High(Lines) do
      if (Trim(Lines[i].Text) <> '')
         and not SameText(FirstToken(Lines[i].Text), '#link') then
        List.Add(Lines[i].Text);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ Index of the target block whose trimmed header equals AHeader, or -1. }
function IndexOfHeader(const ABlocks: TRuleBlocks; const AHeader: string;
  AKind: TRuleBlockKind): Integer;
var
  i: Integer;
begin
  for i := 0 to High(ABlocks) do
    if (ABlocks[i].Kind = AKind) and SameText(Trim(ABlocks[i].Header), Trim(AHeader)) then
      Exit(i);
  Result := -1;
end;

function PlanMerge(const ATarget, AIncoming: TRuleBlocks): TMergePlan;
var
  Items : TList<TMergeItem>;
  bi, ti: Integer;
  TgtLinks, IncLinks: TArray<TBlockLink>;
  IncOther, TgtOther: TArray<string>;
  Item  : TMergeItem;
  L     : TBlockLink;
  S     : string;

  function FindTargetLink(const AToPath: string; out AFound: TBlockLink): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(TgtLinks) do
      if SameText(TgtLinks[k].LinkTo, AToPath) then
      begin
        AFound := TgtLinks[k];
        Exit(True);
      end;
    Result := False;
  end;

  { Exact-after-trim, case-SENSITIVE on purpose: design decision 3 says non-#link
    content is never dropped, so '// Keep me' and '// keep me' are two distinct
    comments and both survive. Target paths, sources, casts and block headers are
    compared with SameText instead -- those are Pascal identifiers. }
  function TargetHasLine(const ALine: string): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(TgtOther) do
      if Trim(TgtOther[k]) = Trim(ALine) then Exit(True);
    Result := False;
  end;

var
  Existing: TBlockLink;
begin
  Result.Target   := ATarget;
  Result.Incoming := AIncoming;
  Items := TList<TMergeItem>.Create;
  try
    for bi := 0 to High(AIncoming) do
    begin
      ti := IndexOfHeader(ATarget, AIncoming[bi].Header, AIncoming[bi].Kind);
      if ti < 0 then
      begin
        Item := Default(TMergeItem);
        Item.Action           := maAppendBlock;
        Item.TargetBlockIdx   := -1;
        Item.IncomingBlockIdx := bi;
        Items.Add(Item);
        Continue;
      end;

      TgtLinks := BlockLinks(ATarget[ti]);
      TgtOther := BlockOtherLines(ATarget[ti]);
      IncLinks := BlockLinks(AIncoming[bi]);
      IncOther := BlockOtherLines(AIncoming[bi]);

      for L in IncLinks do
      begin
        Item := Default(TMergeItem);
        Item.TargetBlockIdx   := ti;
        Item.IncomingBlockIdx := bi;
        Item.Line             := L.Line;
        Item.ToPath           := L.LinkTo;
        if not FindTargetLink(L.LinkTo, Existing) then
          Item.Action := maMergeLink                       // missing (incl. fan-out)
        else if SameText(Existing.LinkFrom, L.LinkFrom)
                and SameText(Existing.Cast, L.Cast) then
          Item.Action := maSkipDuplicate
        else
        begin
          Item.Action       := maConflict;
          Item.ExistingLine := Existing.Line;
          Item.ExistingFrom := Existing.LinkFrom;
          Item.IncomingFrom := L.LinkFrom;
        end;
        Items.Add(Item);
      end;

      for S in IncOther do
        if not TargetHasLine(S) then
        begin
          Item := Default(TMergeItem);
          Item.Action           := maMergeOther;
          Item.TargetBlockIdx   := ti;
          Item.IncomingBlockIdx := bi;
          Item.Line             := S;
          Items.Add(Item);
        end;
    end;
    Result.Items := Items.ToArray;
  finally
    Items.Free;
  end;
end;
```

- [ ] **Step 4: Run to verify they pass**

Expected: every `merge.dup.*`, `merge.conflict.*`, `merge.fanout.*` and `merge.append.*` check PASSes, `0 fail`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.BlockOps.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): merge planning with target-collision conflicts"
```

---

### Task 5: Applying a merge + composing a working set

Covers acceptance criterion 9.

**Files:**
- Modify: `src/tools/convrules-editor/ConvRules.BlockOps.pas`
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `TMergePlan`, `TMergeItem`, `PlanMerge` (Task 4); `BlockEol`, `SplitRawLines` (Task 1).
- Produces:
  - `TMergeResolution = (mrKeepExisting, mrTakeIncoming);`
  - `function ApplyMerge(const APlan: TMergePlan; const AResolutions: TArray<TMergeResolution>): TRuleBlocks;`
  - `function MergeReportLines(const APlan: TMergePlan; const AResolutions: TArray<TMergeResolution>; const AIncomingName: string): TArray<string>;`
  - `TComposeInput` record (`Path`, `Blocks`), `TComposeReport` record (`Lines`, `ResolvedCount`, `AppendedCount`)
  - `function Compose(const AInputs: TArray<TComposeInput>; out AReport: TComposeReport): string;`

- [ ] **Step 1: Write the failing test**

```pascal
{ Criterion 9: composing a working set resolves link collisions in favour of the
  EARLIER file and lists every resolved collision in its report. Compose and merge
  share one code path, so this also proves ApplyMerge. }
procedure TestComposePrecedence;
var
  Inputs: TArray<TComposeInput>;
  Report: TComposeReport;
  Text  : string;
  i     : Integer;
  Found : Boolean;
begin
  SetLength(Inputs, 2);
  Inputs[0].Path   := 'first.rules';
  Inputs[0].Blocks := SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 +
    '#link P <- Q'#13#10);
  Inputs[1].Path   := 'second.rules';
  Inputs[1].Blocks := SplitRulesBlocks(
    '#convert A.T -> B.T'#13#10 +
    '#link P <- Z'#13#10 +          // collides with first.rules -> earlier wins
    '#link R <- S'#13#10 +          // missing -> merged
    '#convert X.T -> Y.T'#13#10 +   // no counterpart -> appended whole
    '#link M <- N'#13#10);

  Text := Compose(Inputs, Report);

  Check('compose.keeps.earlier', Pos('#link P <- Q', Text) > 0, 'earlier link must survive');
  Check('compose.drops.later', Pos('#link P <- Z', Text) = 0, 'later colliding link must not be written');
  Check('compose.merges.missing', Pos('#link R <- S', Text) > 0, 'missing link must be merged');
  Check('compose.appends.block', Pos('#convert X.T -> Y.T', Text) > 0, 'unmatched block must be appended');
  Check('compose.resolved.count', Report.ResolvedCount = 1, IntToStr(Report.ResolvedCount));
  Check('compose.appended.count', Report.AppendedCount = 1, IntToStr(Report.AppendedCount));

  Found := False;
  for i := 0 to High(Report.Lines) do
    if (Pos('second.rules', Report.Lines[i]) > 0) and (Pos('P', Report.Lines[i]) > 0)
       and (Pos('Z', Report.Lines[i]) > 0) then Found := True;
  Check('compose.report.names.collision', Found,
    'the report must name the file, the target and the losing source');

  // taking the incoming side REPLACES the existing line in place, verbatim
  var Plan: TMergePlan := PlanMerge(Inputs[0].Blocks, Inputs[1].Blocks);
  var Merged: string := JoinBlocks(ApplyMerge(Plan, [mrTakeIncoming]));
  Check('merge.apply.takeincoming', (Pos('#link P <- Z', Merged) > 0)
    and (Pos('#link P <- Q', Merged) = 0), 'mrTakeIncoming must replace the existing link');

  // Edge cases: composing nothing yields nothing; composing ONE file is a no-op that
  // returns it byte-for-byte (there is no second file to merge, so nothing is touched).
  var Empty: TComposeReport;
  Check('compose.empty', Compose(nil, Empty) = '', 'an empty working set composes to ''''');
  var One: TArray<TComposeInput>;
  SetLength(One, 1);
  One[0].Path   := 'solo.rules';
  One[0].Blocks := SplitRulesBlocks('#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10);
  Check('compose.single.identity',
    Compose(One, Empty) = '#convert A.T -> B.T'#13#10 + '#link P <- Q'#13#10,
    'composing one file must return it unchanged');
  Check('compose.single.noreport', Length(Empty.Lines) = 0, 'a single file reports nothing');
end;
```

Register after `TestMergeAppendsUnmatchedBlock`.

- [ ] **Step 2: Run to verify it fails**

Expected: `E2003 Undeclared identifier: 'TComposeInput'`.

- [ ] **Step 3: Implement**

Add to `ConvRules.BlockOps.pas` interface:

```pascal
type
  /// <summary>How one conflict is settled.</summary>
  TMergeResolution = (mrKeepExisting, mrTakeIncoming);

  /// <summary>One file of a working set, in composition order.</summary>
  TComposeInput = record
    Path  : string;
    Blocks: TRuleBlocks;
  end;

  /// <summary>What a composition did: a human-readable line per decision that was
  /// not a plain no-op, plus the two counts the status bar shows.</summary>
  TComposeReport = record
    Lines        : TArray<string>;
    ResolvedCount: Integer;   // collisions auto-resolved by precedence
    AppendedCount: Integer;   // whole blocks appended
  end;

/// <summary>PURE: apply a plan and return the merged block list. AResolutions is
/// indexed by CONFLICT ORDINAL (the i-th maConflict item in plan order); a missing
/// entry means mrKeepExisting. mrTakeIncoming replaces the existing #link line in
/// place, verbatim; every other write appends the incoming line verbatim to the end
/// of the matched block. The target blocks are never re-emitted.</summary>
function ApplyMerge(const APlan: TMergePlan;
  const AResolutions: TArray<TMergeResolution>): TRuleBlocks;

/// <summary>PURE: one report line per non-trivial decision, naming AIncomingName
/// (the file the blocks came from) so a composed report is readable.</summary>
function MergeReportLines(const APlan: TMergePlan;
  const AResolutions: TArray<TMergeResolution>;
  const AIncomingName: string): TArray<string>;

/// <summary>PURE: fold the working set into one file, top to bottom, with the merge
/// semantics above. Earlier files win: every collision is auto-resolved in favour of
/// the earlier file and listed in AReport (composing three large books must not mean
/// answering hundreds of prompts). Returns the composed file text.</summary>
function Compose(const AInputs: TArray<TComposeInput>;
  out AReport: TComposeReport): string;

/// <summary>PURE: the block, guaranteed to end with a line terminator. A file whose
/// last line had no EOL would otherwise glue itself onto whatever is appended after
/// it, producing '#link R <- S#convert X.T -> Y.T'.</summary>
function EnsureTrailingEol(const ABlock: TRuleBlock): TRuleBlock;

/// <summary>PURE: AFirst followed by ASecond, with AFirst's last block terminated so
/// the two never run together. Used when appending split-out blocks to an existing
/// file (a move, not a merge).</summary>
function ConcatBlocks(const AFirst, ASecond: TRuleBlocks): TRuleBlocks;
```

Implementation:

```pascal
{ Append whole lines to the end of a block, using the block's own terminator and
  first making sure the block ends with one. }
function AppendLinesToBlock(const ABlock: TRuleBlock;
  const ALines: TArray<string>): TRuleBlock;
var
  Eol: string;
  S  : string;
begin
  Result := ABlock;
  if Length(ALines) = 0 then Exit;
  Eol := BlockEol(ABlock);
  if (Result.RawText <> '')
     and not (Result.RawText.EndsWith(#10) or Result.RawText.EndsWith(#13)) then
    Result.RawText := Result.RawText + Eol;
  for S in ALines do
  begin
    Result.RawText := Result.RawText + S + Eol;
    Inc(Result.EndLine);
  end;
end;

{ Replace the FIRST line equal to AOld with ANew, keeping every terminator. }
function ReplaceLineInBlock(const ABlock: TRuleBlock;
  const AOld, ANew: string): TRuleBlock;
var
  Lines: TArray<TRawLine>;
  i    : Integer;
  Done : Boolean;
begin
  Result := ABlock;
  Lines  := SplitRawLines(ABlock.RawText);
  Done   := False;
  Result.RawText := '';
  for i := 0 to High(Lines) do
  begin
    if (not Done) and (Lines[i].Text = AOld) then
    begin
      Result.RawText := Result.RawText + ANew + Lines[i].Eol;
      Done := True;
    end
    else
      Result.RawText := Result.RawText + Lines[i].Text + Lines[i].Eol;
  end;
end;

function EnsureTrailingEol(const ABlock: TRuleBlock): TRuleBlock;
begin
  Result := ABlock;
  if (Result.RawText <> '')
     and not (Result.RawText.EndsWith(#10) or Result.RawText.EndsWith(#13)) then
    Result.RawText := Result.RawText + BlockEol(Result);
end;

function ConcatBlocks(const AFirst, ASecond: TRuleBlocks): TRuleBlocks;
var
  i: Integer;
begin
  Result := AFirst;
  if Length(Result) > 0 then
    Result[High(Result)] := EnsureTrailingEol(Result[High(Result)]);
  for i := 0 to High(ASecond) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ASecond[i];
  end;
end;

{ The resolution for the AConflictOrdinal-th conflict (default: keep existing). }
function ResolutionAt(const AResolutions: TArray<TMergeResolution>;
  AConflictOrdinal: Integer): TMergeResolution;
begin
  if (AConflictOrdinal >= 0) and (AConflictOrdinal <= High(AResolutions)) then
    Result := AResolutions[AConflictOrdinal]
  else
    Result := mrKeepExisting;
end;

function ApplyMerge(const APlan: TMergePlan;
  const AResolutions: TArray<TMergeResolution>): TRuleBlocks;
var
  Blocks : TList<TRuleBlock>;
  i, cOrd: Integer;
  It     : TMergeItem;
begin
  Blocks := TList<TRuleBlock>.Create;
  try
    for i := 0 to High(APlan.Target) do Blocks.Add(APlan.Target[i]);
    cOrd := 0;
    for i := 0 to High(APlan.Items) do
    begin
      It := APlan.Items[i];
      case It.Action of
        maAppendBlock:
          begin
            // terminate whatever is currently last, or the two blocks run together
            if Blocks.Count > 0 then
              Blocks[Blocks.Count - 1] := EnsureTrailingEol(Blocks[Blocks.Count - 1]);
            Blocks.Add(APlan.Incoming[It.IncomingBlockIdx]);
          end;
        maMergeLink, maMergeOther:
          Blocks[It.TargetBlockIdx] :=
            AppendLinesToBlock(Blocks[It.TargetBlockIdx], [It.Line]);
        maConflict:
          begin
            if ResolutionAt(AResolutions, cOrd) = mrTakeIncoming then
              Blocks[It.TargetBlockIdx] :=
                ReplaceLineInBlock(Blocks[It.TargetBlockIdx], It.ExistingLine, It.Line);
            Inc(cOrd);
          end;
        maSkipDuplicate: ; // nothing to do
      end;
    end;
    Result := Blocks.ToArray;
  finally
    Blocks.Free;
  end;
end;

function MergeReportLines(const APlan: TMergePlan;
  const AResolutions: TArray<TMergeResolution>;
  const AIncomingName: string): TArray<string>;
var
  List   : TList<string>;
  i, cOrd: Integer;
  It     : TMergeItem;
begin
  List := TList<string>.Create;
  try
    cOrd := 0;
    for i := 0 to High(APlan.Items) do
    begin
      It := APlan.Items[i];
      case It.Action of
        maAppendBlock:
          List.Add(Format('%s: appended block %s',
            [AIncomingName, Trim(APlan.Incoming[It.IncomingBlockIdx].Header)]));
        maMergeLink:
          List.Add(Format('%s: merged %s', [AIncomingName, Trim(It.Line)]));
        maMergeOther:
          List.Add(Format('%s: merged line %s', [AIncomingName, Trim(It.Line)]));
        maConflict:
          begin
            if ResolutionAt(AResolutions, cOrd) = mrTakeIncoming then
              List.Add(Format('%s: conflict on %s -- took incoming (%s <- %s), dropped (%s <- %s)',
                [AIncomingName, It.ToPath, It.ToPath, It.IncomingFrom, It.ToPath, It.ExistingFrom]))
            else
              List.Add(Format('%s: conflict on %s -- kept earlier (%s <- %s), dropped (%s <- %s)',
                [AIncomingName, It.ToPath, It.ToPath, It.ExistingFrom, It.ToPath, It.IncomingFrom]));
            Inc(cOrd);
          end;
        maSkipDuplicate: ; // a duplicate is a no-op, not worth a report line
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function Compose(const AInputs: TArray<TComposeInput>;
  out AReport: TComposeReport): string;
var
  Acc  : TRuleBlocks;
  Plan : TMergePlan;
  Lines: TList<string>;
  i, k : Integer;
  Name : string;
begin
  AReport := Default(TComposeReport);
  if Length(AInputs) = 0 then Exit('');
  Acc   := AInputs[0].Blocks;
  Lines := TList<string>.Create;
  try
    for i := 1 to High(AInputs) do
    begin
      Name := ExtractFileName(AInputs[i].Path);
      Plan := PlanMerge(Acc, AInputs[i].Blocks);
      for k := 0 to High(Plan.Items) do
        case Plan.Items[k].Action of
          maConflict:    Inc(AReport.ResolvedCount);
          maAppendBlock: Inc(AReport.AppendedCount);
        end;
      Lines.AddRange(MergeReportLines(Plan, nil, Name));   // nil = keep earlier
      Acc := ApplyMerge(Plan, nil);
    end;
    AReport.Lines := Lines.ToArray;
    Result := JoinBlocks(Acc);
  finally
    Lines.Free;
  end;
end;
```

- [ ] **Step 4: Run to verify it passes**

Expected: every `compose.*` and `merge.apply.*` check PASSes, `0 fail`.

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.BlockOps.pas src/tools/convrules-editor/tests/ConvRulesModelTests.dpr
git commit -m "feat(convrules): apply-merge + compose a working set by precedence"
```

---

### Task 6: Working set + rotating-backup writes

Covers acceptance criteria 11 and 14.

**Files:**
- Create: `src/tools/convrules-editor/ConvRules.WorkingSet.pas`
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas` (delete the private `BackupPath`, use the shared one)
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `SplitBlocksFor`, `JoinBlocks`, `TRuleBlocks` (Tasks 1-2); `TComposeInput`, `TComposeReport`, `Compose` (Task 5).
- Produces:
  - `function BackupPath(const APath: string): string;`
  - `procedure WriteTextWithBackup(const APath, AText: string; out ABackup: string);`
  - `TWorkingFile` record (`Path`, `Blocks`), `TWorkingSet` class with `AddText`, `AddFile`, `Remove`, `MoveUp`, `MoveDown`, `Count`, `Item`, `SetBlocks`, `IndexOfPath`, `ComposeAll`, `SaveFile`.

- [ ] **Step 1: Write the failing tests**

```pascal
{ Criterion 11: a write makes a rotating backup first and never overwrites one. }
procedure TestBackupRotation;
var
  Dir, P, B1, B2: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'convrules-curation-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    P := TPath.Combine(Dir, 'book.rules');
    TFile.WriteAllText(P, 'v1'#13#10, TEncoding.ASCII);

    WriteTextWithBackup(P, 'v2'#13#10, B1);
    Check('backup.first.name', B1 = P + '.bak', B1);
    Check('backup.first.content', TFile.ReadAllText(B1) = 'v1'#13#10, 'backup must hold v1');
    Check('backup.first.written', TFile.ReadAllText(P) = 'v2'#13#10, 'file must hold v2');

    WriteTextWithBackup(P, 'v3'#13#10, B2);
    Check('backup.second.name', B2 = P + '.bak.2', B2);
    Check('backup.second.content', TFile.ReadAllText(B2) = 'v2'#13#10, 'second backup holds v2');
    Check('backup.first.preserved', TFile.ReadAllText(B1) = 'v1'#13#10,
      'the first backup must NOT be overwritten');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

{ Criterion 14: IF the backup cannot be written THEN the operation aborts and every
  file is left unmodified. An exclusive read lock on the source makes TFile.Copy
  fail deterministically. }
procedure TestBackupFailureAborts;
var
  Dir, P: string;
  Lock  : TFileStream;
  Bak   : string;
  Raised: Boolean;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'convrules-curation-fail-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  try
    P := TPath.Combine(Dir, 'book.rules');
    TFile.WriteAllText(P, 'original'#13#10, TEncoding.ASCII);
    Raised := False;
    Lock := TFileStream.Create(P, fmOpenRead or fmShareExclusive);
    try
      try
        WriteTextWithBackup(P, 'replacement'#13#10, Bak);
      except
        on E: Exception do Raised := True;
      end;
    finally
      Lock.Free;
    end;
    Check('backup.fail.raises', Raised, 'a failed backup must raise, not write');
    Check('backup.fail.file.unmodified', TFile.ReadAllText(P) = 'original'#13#10,
      'the target file must be untouched');
    Check('backup.fail.no.backup', not TFile.Exists(P + '.bak'),
      'no backup file may be left behind');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;
```

`TestBackupFailureAborts` needs `Winapi.Windows` for `GetCurrentProcessId`; add it to the runner's `uses` if it is not already there (`System.SysUtils` alone does not provide it -- use `System.SysUtils.GetCurrentProcessId` is not available, so add `Winapi.Windows`). Register both tests after `TestComposePrecedence`.

- [ ] **Step 2: Run to verify they fail**

Expected: `F2613 Unit 'ConvRules.WorkingSet' not found` (add the unit to the runner's `uses` in this step too:
`ConvRules.WorkingSet in '..\ConvRules.WorkingSet.pas',`).

- [ ] **Step 3: Implement**

Create `src/tools/convrules-editor/ConvRules.WorkingSet.pas`:

```pascal
unit ConvRules.WorkingSet;

{ The ordered set of rule-book / catalog files the curation form has open, plus the
  only file-system writes in the curation path.

  Order IS composition precedence: Compose folds the set top to bottom and the
  EARLIER file wins every link collision, so moving a file up promotes its choices.

  VCL-free, so the ordering and composition logic is unit-tested headlessly; the two
  file helpers (BackupPath / WriteTextWithBackup) are shared with the main form so a
  curation write and a normal Save rotate backups identically. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  ConvRules.BlockFile, ConvRules.BlockOps;

type
  /// <summary>One loaded file: where it came from and its verbatim blocks.</summary>
  TWorkingFile = record
    Path  : string;
    Blocks: TRuleBlocks;
  end;

  /// <summary>Ordered list of loaded files. Position = composition precedence.</summary>
  TWorkingSet = class
  private
    FFiles: TList<TWorkingFile>;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Add already-read text under APath (the grammar follows APath's
    /// extension). Used by the tests and by AddFile.</summary>
    procedure AddText(const APath, AText: string);
    /// <summary>Read APath from disk and add it. Raises if the file is unreadable.</summary>
    procedure AddFile(const APath: string);
    procedure Remove(AIndex: Integer);
    /// <summary>Swap with the previous entry (raise this file's precedence). No-op at 0.</summary>
    procedure MoveUp(AIndex: Integer);
    /// <summary>Swap with the next entry. No-op at the end.</summary>
    procedure MoveDown(AIndex: Integer);

    function  Count: Integer;
    function  Item(AIndex: Integer): TWorkingFile;
    /// <summary>Replace one file's blocks after a curation operation.</summary>
    procedure SetBlocks(AIndex: Integer; const ABlocks: TRuleBlocks);
    /// <summary>Index of the entry whose Path matches (case-insensitive), or -1.</summary>
    function  IndexOfPath(const APath: string): Integer;

    /// <summary>Compose every loaded file, in order, into one .rules text.</summary>
    function  ComposeAll(out AReport: TComposeReport): string;
    /// <summary>Write one entry back to its own path, backing it up first.</summary>
    /// <returns>The backup path written ('' when the file did not exist yet).</returns>
    function  SaveFile(AIndex: Integer): string;
  end;

/// <summary>PURE: the next unused backup name for APath -- '<file>.bak', then
/// '.bak.2', '.bak.3' ... so a short history is kept and nothing is overwritten.
/// Caps at 99 (the 99th name is reused rather than searching forever).</summary>
function BackupPath(const APath: string): string;

/// <summary>Back APath up, then overwrite it with AText as ASCII. Line terminators
/// come from AText itself and are never normalised.</summary>
/// <param name="ABackup">The backup written, or '' when APath did not exist.</param>
/// <exception cref="EInOutError">Raised when the backup copy fails -- APath is then
/// left completely untouched (acceptance criterion 14).</exception>
procedure WriteTextWithBackup(const APath, AText: string; out ABackup: string);

implementation

function BackupPath(const APath: string): string;
var
  n: Integer;
begin
  Result := APath + '.bak';
  n := 2;
  while TFile.Exists(Result) do
  begin
    Result := APath + '.bak.' + IntToStr(n);
    Inc(n);
    if n > 99 then Break; // cap
  end;
end;

procedure WriteTextWithBackup(const APath, AText: string; out ABackup: string);
begin
  ABackup := '';
  if TFile.Exists(APath) then
  begin
    ABackup := BackupPath(APath);
    try
      TFile.Copy(APath, ABackup);
    except
      on E: Exception do
      begin
        ABackup := '';
        raise EInOutError.CreateFmt('backup of %s failed: %s -- nothing was written',
          [APath, E.Message]);
      end;
    end;
  end;
  TFile.WriteAllText(APath, AText, TEncoding.ASCII);
end;

{ TWorkingSet }

constructor TWorkingSet.Create;
begin
  inherited Create;
  FFiles := TList<TWorkingFile>.Create;
end;

destructor TWorkingSet.Destroy;
begin
  FFiles.Free;
  inherited;
end;

procedure TWorkingSet.AddText(const APath, AText: string);
var
  F: TWorkingFile;
begin
  F.Path   := APath;
  F.Blocks := SplitBlocksFor(APath, AText);
  FFiles.Add(F);
end;

procedure TWorkingSet.AddFile(const APath: string);
begin
  AddText(APath, TFile.ReadAllText(APath, TEncoding.ASCII));
end;

procedure TWorkingSet.Remove(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FFiles.Count) then FFiles.Delete(AIndex);
end;

procedure TWorkingSet.MoveUp(AIndex: Integer);
begin
  if (AIndex > 0) and (AIndex < FFiles.Count) then FFiles.Exchange(AIndex, AIndex - 1);
end;

procedure TWorkingSet.MoveDown(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FFiles.Count - 1) then FFiles.Exchange(AIndex, AIndex + 1);
end;

function TWorkingSet.Count: Integer;
begin
  Result := FFiles.Count;
end;

function TWorkingSet.Item(AIndex: Integer): TWorkingFile;
begin
  Result := FFiles[AIndex];
end;

procedure TWorkingSet.SetBlocks(AIndex: Integer; const ABlocks: TRuleBlocks);
var
  F: TWorkingFile;
begin
  F := FFiles[AIndex];
  F.Blocks := ABlocks;
  FFiles[AIndex] := F;
end;

function TWorkingSet.IndexOfPath(const APath: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FFiles.Count - 1 do
    if SameText(FFiles[i].Path, APath) then Exit(i);
  Result := -1;
end;

function TWorkingSet.ComposeAll(out AReport: TComposeReport): string;
var
  Inputs: TArray<TComposeInput>;
  i     : Integer;
begin
  SetLength(Inputs, FFiles.Count);
  for i := 0 to FFiles.Count - 1 do
  begin
    Inputs[i].Path   := FFiles[i].Path;
    Inputs[i].Blocks := FFiles[i].Blocks;
  end;
  Result := Compose(Inputs, AReport);
end;

function TWorkingSet.SaveFile(AIndex: Integer): string;
begin
  WriteTextWithBackup(FFiles[AIndex].Path, JoinBlocks(FFiles[AIndex].Blocks), Result);
end;

end.
```

- [ ] **Step 4: Point the main form at the shared backup helper**

In `ConvRules.MainForm.pas`, DELETE the private `BackupPath` function (implementation section, currently at line 149-162) and add `ConvRules.WorkingSet` to the implementation `uses`:

```pascal
uses
  System.StrUtils, System.Math, ConvRules.Units, ConvRules.WorkingSet;
```

`DoSave` keeps calling `BackupPath(FFilePath)` unchanged -- it now resolves to the shared one, which behaves identically. Do not change `DoSave`'s logic in this task.

- [ ] **Step 5: Run to verify the tests pass**

Run: build + exe.
Expected: `backup.first.*`, `backup.second.*` and `backup.fail.*` all PASS, `0 fail`.

Also rebuild the editor to prove the main-form change compiles. Create `build/_build_convrules_editor_local.bat`:

```bat
@echo off
REM Build ConvRulesEditor.exe (Win64) from THIS checkout, then stage to dll-win64.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\convrules-editor"
dcc64 -B ConvRulesEditor.dpr
echo BUILD_EXITCODE=%errorlevel%
if %errorlevel%==0 copy /Y ConvRulesEditor.exe "%~dp0..\third_party\dll-win64\ConvRulesEditor.exe" >NUL
```

Add the three new units to `ConvRulesEditor.dpr`'s `uses`, before `ConvRules.MainForm`:

```pascal
  ConvRules.BlockFile in 'ConvRules.BlockFile.pas',
  ConvRules.BlockOps in 'ConvRules.BlockOps.pas',
  ConvRules.WorkingSet in 'ConvRules.WorkingSet.pas',
```

Run:

```powershell
Start-Process -Wait -NoNewWindow -FilePath "C:\Projects\Delphi-RAG-lint-converter\build\_build_convrules_editor_local.bat" -RedirectStandardOutput "$env:TEMP\ce-build.log"
Get-Content "$env:TEMP\ce-build.log" -Tail 5
```

Expected: `BUILD_EXITCODE=0`.

- [ ] **Step 6: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.WorkingSet.pas src/tools/convrules-editor/ConvRules.MainForm.pas src/tools/convrules-editor/ConvRulesEditor.dpr src/tools/convrules-editor/tests/ConvRulesModelTests.dpr build/_build_convrules_editor_local.bat
git commit -m "feat(convrules): working set + shared rotating-backup writes"
```

---

### Task 7: Composed output validates against the engine

Covers acceptance criterion 10 -- the one integration test.

**Files:**
- Modify: `src/tools/convrules-editor/tests/ConvRulesModelTests.dpr`

**Interfaces:**
- Consumes: `TWorkingSet.ComposeAll` (Task 6); `TEngineAdapter.ValidateText`, `TValidateResult` (existing `ConvRules.Engine`); the runner's existing `ResolveExe` helper.

- [ ] **Step 1: Write the failing test**

```pascal
{ Criterion 10: the composed output is a valid .rules file -- compose two books,
  hand the text to convert-validate and require OK. Skips (does not fail) when the
  drag-lint exe is absent, matching the suite's environment policy. }
procedure TestComposedFileValidates;
var
  Exe   : string;
  WS    : TWorkingSet;
  Rep   : TComposeReport;
  Text  : string;
  Eng   : TEngineAdapter;
  Res   : TValidateResult;
begin
  Exe := ResolveExe;
  if Exe = '' then
  begin
    Skip('compose.validates', 'drag-lint.exe not found');
    Exit;
  end;
  WS := TWorkingSet.Create;
  try
    WS.AddText('first.rules',
      '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont'#13#10 +
      '#link Color <- Color'#13#10 +
      '#link Height <- Height'#13#10);
    WS.AddText('second.rules',
      '#convert Vcl.Graphics.TFont -> Vcl.Graphics.TFont'#13#10 +
      '#link Color <- Name'#13#10 +          // collides -> earlier wins
      '#link Size <- Size'#13#10 +           // merged
      '#convert Vcl.StdCtrls.TEdit -> Vcl.StdCtrls.TMemo'#13#10 +
      '#link Text <- Text'#13#10);           // appended whole
    Text := WS.ComposeAll(Rep);
    Check('compose.validates.resolved', Rep.ResolvedCount = 1, IntToStr(Rep.ResolvedCount));

    Eng := TEngineAdapter.Create(Exe, []);
    try
      Res := Eng.ValidateText(Text, '', '');
      Check('compose.validates', Res.OK, 'convert-validate rejected the composed file: '
        + Res.FirstError + ' | text=' + StringReplace(Text, #13#10, '\n', [rfReplaceAll]));
    finally
      Eng.Free;
    end;
  finally
    WS.Free;
  end;
end;
```

Register after `TestBackupFailureAborts`.

- [ ] **Step 2: Run to verify it fails**

Expected: on the first run this fails to COMPILE only if a name is wrong; otherwise it may already pass. If it passes immediately, that is acceptable for an integration test over already-implemented code -- but first confirm it can fail.

**Corrected during execution (2026-07-27):** the obvious break does NOT do what this step originally claimed. Changing `#link Color <- Color` to `#link <- Color` leaves `compose.validates` PASSING, because the engine deliberately treats an empty `ToPath` as nothing-to-check (the same path as a `???` stub), and `ValidateText(Text, '', '')` passes no `--from`/`--to`, which disables path checking entirely. That break fails `compose.validates.resolved` instead (the collision disappears, so `ResolvedCount` drops to 0) -- useful, but not the assertion under test.

To prove the MAIN assertion can fail, break the GRAMMAR instead: change `#convert` to `#konvert`, rerun, and see `compose.validates` fail with the CLI's own `line 1: unknown directive: #konvert`. Then restore the line by editing it back -- never with a git command, since the working tree carries another workstream's uncommitted edits.

Know what this test does and does not prove: with no `--from`/`--to` it verifies the composed file is grammatically valid DSL, NOT that every `#link` path resolves against a real property tree. Path-level validation would need the type names plus a library DB passed to the adapter.

- [ ] **Step 3: Make it pass**

If `convert-validate` rejects the composed text, the defect is in the composer, not the test. Read `Res.FirstError` -- it reports `line N: ...`. Terminators between blocks are already guarded (`EnsureTrailingEol` in `ApplyMerge`'s `maAppendBlock` branch and in `AppendLinesToBlock`), so check these next, in order:
1. a merged `#link` line appended AFTER the block's trailing blank lines, landing outside the block the validator thinks it is in;
2. a block appended after a preamble-only file, leaving the preamble's trailing content mid-file;
3. an incoming line indented differently from the target block's convention -- harmless to the validator, but check it is not being mangled.

Fix in `ConvRules.BlockOps`, not in the test.

- [ ] **Step 4: Run to verify it passes**

Expected: `compose.validates.resolved` and `compose.validates` PASS (or the whole test SKIPs on a machine with no exe -- verify on this machine that it RUNS, since the exe is present at `third_party/dll-win64/drag-lint.exe`).

- [ ] **Step 5: Commit**

```bash
git add src/tools/convrules-editor/tests/ConvRulesModelTests.dpr src/tools/convrules-editor/ConvRules.BlockOps.pas
git commit -m "test(convrules): composed rule-book validates against convert-validate"
```

---

### Task 8: The curation form + main-form entry point

Covers acceptance criterion 12's UI half and delivers the feature. No automated test -- this is code-built VCL; verification is a build plus the manual checklist in Step 5.

**Files:**
- Create: `src/tools/convrules-editor/ConvRules.CurationForm.pas`
- Modify: `src/tools/convrules-editor/ConvRules.MainForm.pas` (a `Curate...` button + handler)
- Modify: `src/tools/convrules-editor/ConvRulesEditor.dpr` (`uses`)

**Interfaces:**
- Consumes: `TWorkingSet`, `SaveFile`, `ComposeAll` (Task 6); `SplitOut`, `CopyOut`, `DeleteBlocks`, `CanOperateOn`, `PlanMerge`, `ApplyMerge`, `MergeReportLines`, `TMergeResolution` (Tasks 3-5); `BlockLabel`, `JoinBlocks`, `SplitBlocksFor` (Tasks 1-2).
- Produces: `class function TCurationForm.Execute(AOwner: TComponent; const AInitialPath: string): string;` -- returns the path the caller should reload ('' when nothing the caller has open changed).

- [ ] **Step 1: Create the form**

Create `src/tools/convrules-editor/ConvRules.CurationForm.pas`. Built in code (no `.dfm`), plain VCL, matching `ConvRules.MainForm`:

```pascal
unit ConvRules.CurationForm;

{ Modal rule-book / catalog curation window -- opened on request from the main form,
  not present otherwise.

  Shows a WORKING SET (several files loaded together, because one conversion may need
  several interdependent books) and, below it, every block across the set with a file
  column and a checkbox. The toolbar acts on the checked blocks: split out, copy out,
  delete, merge another file in, or compose the whole set into one file for the engine.

  Every write goes through ConvRules.WorkingSet.WriteTextWithBackup and moves VERBATIM
  block text -- never the main form's canonical re-emitter, so a block that was merely
  moved comes back byte-identical. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  ConvRules.BlockFile, ConvRules.BlockOps, ConvRules.WorkingSet;

type
  /// <summary>The modal curation window.</summary>
  TCurationForm = class(TForm)
  private
    FSet     : TWorkingSet;
    FFiles   : TListBox;      // working set, top to bottom = composition precedence
    FBlocks  : TListView;     // vsReport + Checkboxes: File | Kind | Block | Lines
    FStatus  : TStatusBar;
    FBtnSplit, FBtnCopy, FBtnDelete, FBtnMerge, FBtnCompose: TButton;
    FTouched : TDictionary<string, Boolean>;   // paths this session wrote

    procedure BuildUI;
    procedure RefreshFiles;
    procedure RefreshBlocks;
    procedure UpdateEnabled;
    function  CheckedIndexes(out AFileIdx: Integer): TArray<Integer>;
    procedure BlocksChange(Sender: TObject; Item: TListItem; Change: TItemChange);
    procedure DoAddFile(Sender: TObject);
    procedure DoRemoveFile(Sender: TObject);
    procedure DoMoveUp(Sender: TObject);
    procedure DoMoveDown(Sender: TObject);
    procedure DoSplit(Sender: TObject);
    procedure DoCopy(Sender: TObject);
    procedure DoDelete(Sender: TObject);
    procedure DoMerge(Sender: TObject);
    procedure DoCompose(Sender: TObject);
    function  SaveSet(AIndex: Integer): Boolean;
    function  AskTargetFile(const ADefault: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Show the modal curation window seeded with AInitialPath (may be '').</summary>
    /// <returns>AInitialPath when that file was modified and the caller must reload
    /// it, otherwise ''.</returns>
    class function Execute(AOwner: TComponent; const AInitialPath: string): string;
  end;

implementation
```

The block grid lists the blocks of the **selected** file only, so a row's index in the list view IS its index in that file's block array -- no parallel index bookkeeping, no chance of operating on the wrong block. The "file column" the spec asks for is still there (it shows the selected file's name), and the working-set list above it is what makes several files visible at once. Add `FFilesClick` to the private section alongside the handlers already declared.

Implementation:

```pascal
constructor TCurationForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FSet     := TWorkingSet.Create;
  FTouched := TDictionary<string, Boolean>.Create;
  BuildUI;
end;

destructor TCurationForm.Destroy;
begin
  FTouched.Free;
  FSet.Free;
  inherited;
end;

class function TCurationForm.Execute(AOwner: TComponent;
  const AInitialPath: string): string;
var
  F: TCurationForm;
begin
  Result := '';
  F := TCurationForm.Create(AOwner);
  try
    if (AInitialPath <> '') and TFile.Exists(AInitialPath) then
    begin
      F.FSet.AddFile(AInitialPath);
      F.RefreshFiles;
      if F.FFiles.Items.Count > 0 then F.FFiles.ItemIndex := 0;
      F.RefreshBlocks;
    end;
    F.UpdateEnabled;
    F.ShowModal;
    if (AInitialPath <> '') and F.FTouched.ContainsKey(LowerCase(AInitialPath)) then
      Result := AInitialPath;
  finally
    F.Free;
  end;
end;

procedure TCurationForm.BuildUI;
var
  Top: TPanel;
begin
  Caption     := 'Curate rule-books';
  Width       := 1100;
  Height      := 640;
  Position    := poOwnerFormCenter;
  BorderStyle := bsSizeable;

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  FStatus.SimpleText  := 'Add the rule-books that belong to this conversion.';

  Top := TPanel.Create(Self);
  Top.Parent := Self; Top.Align := alTop; Top.Height := 72; Top.BevelOuter := bvNone;

  // row 1 -- working-set management
  var B: TButton := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(8, 6, 90, 25);
  B.Caption := 'Add file...'; B.OnClick := DoAddFile;
  B := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(104, 6, 80, 25);
  B.Caption := 'Remove'; B.OnClick := DoRemoveFile;
  B := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(190, 6, 80, 25);
  B.Caption := 'Move up'; B.OnClick := DoMoveUp;
  B := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(276, 6, 90, 25);
  B.Caption := 'Move down'; B.OnClick := DoMoveDown;
  var L: TLabel := TLabel.Create(Self);
  L.Parent := Top; L.SetBounds(376, 11, 600, 15);
  L.Caption := 'Order = composition precedence: the file nearest the top wins every '
    + 'link collision.';

  // row 2 -- block operations
  FBtnSplit := TButton.Create(Self);
  FBtnSplit.Parent := Top; FBtnSplit.SetBounds(8, 38, 90, 25);
  FBtnSplit.Caption := 'Split...'; FBtnSplit.OnClick := DoSplit;
  FBtnSplit.Hint := 'Move the checked blocks OUT of this file into another';
  FBtnSplit.ShowHint := True;

  FBtnCopy := TButton.Create(Self);
  FBtnCopy.Parent := Top; FBtnCopy.SetBounds(104, 38, 90, 25);
  FBtnCopy.Caption := 'Copy...'; FBtnCopy.OnClick := DoCopy;
  FBtnCopy.Hint := 'Copy the checked blocks into another file; this file is unchanged';
  FBtnCopy.ShowHint := True;

  FBtnDelete := TButton.Create(Self);
  FBtnDelete.Parent := Top; FBtnDelete.SetBounds(200, 38, 90, 25);
  FBtnDelete.Caption := 'Delete'; FBtnDelete.OnClick := DoDelete;

  FBtnMerge := TButton.Create(Self);
  FBtnMerge.Parent := Top; FBtnMerge.SetBounds(306, 38, 110, 25);
  FBtnMerge.Caption := 'Merge from...'; FBtnMerge.OnClick := DoMerge;

  FBtnCompose := TButton.Create(Self);
  FBtnCompose.Parent := Top; FBtnCompose.SetBounds(422, 38, 110, 25);
  FBtnCompose.Caption := 'Compose...'; FBtnCompose.OnClick := DoCompose;
  FBtnCompose.Hint := 'Fold the whole working set into ONE .rules file for --rules';
  FBtnCompose.ShowHint := True;

  B := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(548, 38, 80, 25);
  B.Caption := 'Close'; B.ModalResult := mrOk;

  FFiles := TListBox.Create(Self);
  FFiles.Parent := Self; FFiles.Align := alTop; FFiles.Height := 96;
  FFiles.OnClick := FFilesClick;

  FBlocks := TListView.Create(Self);
  FBlocks.Parent := Self; FBlocks.Align := alClient;
  FBlocks.ViewStyle  := vsReport;
  FBlocks.Checkboxes := True;
  FBlocks.RowSelect  := True;
  FBlocks.ReadOnly   := True;
  FBlocks.OnChange   := BlocksChange;
  FBlocks.Columns.Add.Caption := 'File';    FBlocks.Columns[0].Width := 200;
  FBlocks.Columns.Add.Caption := 'Kind';    FBlocks.Columns[1].Width := 70;
  FBlocks.Columns.Add.Caption := 'Block';   FBlocks.Columns[2].Width := 620;
  FBlocks.Columns.Add.Caption := 'Lines';   FBlocks.Columns[3].Width := 80;
end;

procedure TCurationForm.RefreshFiles;
var
  i, Keep: Integer;
begin
  Keep := FFiles.ItemIndex;
  FFiles.Items.BeginUpdate;
  try
    FFiles.Items.Clear;
    for i := 0 to FSet.Count - 1 do
      FFiles.Items.Add(Format('%d. %s   [%s]',
        [i + 1, ExtractFileName(FSet.Item(i).Path), FSet.Item(i).Path]));
  finally
    FFiles.Items.EndUpdate;
  end;
  if (Keep >= 0) and (Keep < FFiles.Items.Count) then FFiles.ItemIndex := Keep
  else if FFiles.Items.Count > 0 then FFiles.ItemIndex := 0;
end;

{ The grid shows the SELECTED file's blocks, so row index = block index. }
procedure TCurationForm.RefreshBlocks;
const
  KIND_NAME: array[TRuleBlockKind] of string = ('header', 'convert', 'cast', 'enum');
var
  fi, i: Integer;
  F    : TWorkingFile;
  It   : TListItem;
begin
  FBlocks.Items.BeginUpdate;
  try
    FBlocks.Items.Clear;
    fi := FFiles.ItemIndex;
    // NOTE: no early Exit here -- UpdateEnabled at the end must run on EVERY path,
    // or removing the last file from the working set leaves Split/Copy/Delete
    // enabled against a grid that is now empty (acceptance criterion 12).
    if (fi >= 0) and (fi < FSet.Count) then
    begin
    F := FSet.Item(fi);
    for i := 0 to High(F.Blocks) do
    begin
      It := FBlocks.Items.Add;
      It.Caption := ExtractFileName(F.Path);
      It.SubItems.Add(KIND_NAME[F.Blocks[i].Kind]);
      It.SubItems.Add(BlockLabel(F.Blocks[i]));
      It.SubItems.Add(Format('%d-%d', [F.Blocks[i].StartLine, F.Blocks[i].EndLine]));
    end;
    end;
  finally
    FBlocks.Items.EndUpdate;
  end;
  UpdateEnabled;   // unconditional -- see the note above
end;

function TCurationForm.CheckedIndexes(out AFileIdx: Integer): TArray<Integer>;
var
  List: TList<Integer>;
  i   : Integer;
begin
  AFileIdx := FFiles.ItemIndex;
  List := TList<Integer>.Create;
  try
    for i := 0 to FBlocks.Items.Count - 1 do
      if FBlocks.Items[i].Checked then List.Add(i);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ Acceptance criterion 12: the block commands act on a selection, so an empty
  selection disables them. CanOperateOn is the single shared rule. }
procedure TCurationForm.UpdateEnabled;
var
  fi : Integer;
  Sel: TArray<Integer>;
begin
  Sel := CheckedIndexes(fi);
  FBtnSplit.Enabled   := CanOperateOn(Sel) and (fi >= 0);
  FBtnCopy.Enabled    := FBtnSplit.Enabled;
  FBtnDelete.Enabled  := FBtnSplit.Enabled;
  FBtnMerge.Enabled   := (fi >= 0);
  FBtnCompose.Enabled := FSet.Count > 0;
end;

procedure TCurationForm.BlocksChange(Sender: TObject; Item: TListItem;
  Change: TItemChange);
begin
  if Change = ctState then UpdateEnabled;
end;

procedure TCurationForm.FFilesClick(Sender: TObject);
begin
  RefreshBlocks;
end;

procedure TCurationForm.DoAddFile(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Conversion rules (*.rules)|*.rules|Cast library (*.castlib)|*.castlib|'
      + 'reFind rules (*.txt)|*.txt|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    if FSet.IndexOfPath(Dlg.FileName) >= 0 then
    begin
      FStatus.SimpleText := 'Already in the working set: ' + ExtractFileName(Dlg.FileName);
      Exit;
    end;
    FSet.AddFile(Dlg.FileName);
    RefreshFiles;
    FFiles.ItemIndex := FSet.Count - 1;
    RefreshBlocks;
    FStatus.SimpleText := 'Added ' + ExtractFileName(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TCurationForm.DoRemoveFile(Sender: TObject);
begin
  if FFiles.ItemIndex < 0 then Exit;
  FSet.Remove(FFiles.ItemIndex);   // closes it here; the file on disk is untouched
  RefreshFiles;
  RefreshBlocks;
end;

procedure TCurationForm.DoMoveUp(Sender: TObject);
var
  i: Integer;
begin
  i := FFiles.ItemIndex;
  if i <= 0 then Exit;
  FSet.MoveUp(i);
  RefreshFiles;
  FFiles.ItemIndex := i - 1;
  RefreshBlocks;
end;

procedure TCurationForm.DoMoveDown(Sender: TObject);
var
  i: Integer;
begin
  i := FFiles.ItemIndex;
  if (i < 0) or (i >= FSet.Count - 1) then Exit;
  FSet.MoveDown(i);
  RefreshFiles;
  FFiles.ItemIndex := i + 1;
  RefreshBlocks;
end;

function TCurationForm.AskTargetFile(const ADefault: string): string;
var
  Dlg: TSaveDialog;
begin
  Result := '';
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter     := 'Conversion rules (*.rules)|*.rules|Cast library (*.castlib)|*.castlib';
    Dlg.DefaultExt := Copy(ExtractFileExt(ADefault), 2, MaxInt);
    Dlg.FileName   := ADefault;
    Dlg.Options    := Dlg.Options - [ofOverwritePrompt];  // we back up, never clobber
    if Dlg.Execute then Result := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

{ Write ABlocks into APath, appending when the file already exists. A split/copy is a
  MOVE of verbatim text, not a merge -- no link reconciliation happens here. }
function TCurationForm.WriteBlocksTo(const APath: string;
  const ABlocks: TRuleBlocks; out ABackup: string): Boolean;
var
  Existing: TRuleBlocks;
begin
  Result := False;
  ABackup := '';
  try
    if TFile.Exists(APath) then
      Existing := SplitBlocksFor(APath, TFile.ReadAllText(APath, TEncoding.ASCII))
    else
      Existing := nil;
    WriteTextWithBackup(APath, JoinBlocks(ConcatBlocks(Existing, ABlocks)), ABackup);
    FTouched.AddOrSetValue(LowerCase(APath), True);
    Result := True;
  except
    on E: Exception do
      FStatus.SimpleText := 'Write failed, nothing changed: ' + E.Message;
  end;
end;

function TCurationForm.SaveSet(AIndex: Integer): Boolean;
var
  Bak: string;
begin
  Result := False;
  try
    Bak := FSet.SaveFile(AIndex);
    FTouched.AddOrSetValue(LowerCase(FSet.Item(AIndex).Path), True);
    FStatus.SimpleText := Format('Saved %s (backup %s)',
      [ExtractFileName(FSet.Item(AIndex).Path), ExtractFileName(Bak)]);
    Result := True;
  except
    on E: Exception do
      // The pure layer guarantees nothing was written when the backup failed.
      FStatus.SimpleText := 'Save failed, nothing changed: ' + E.Message;
  end;
end;

procedure TCurationForm.DoSplit(Sender: TObject);
var
  fi      : Integer;
  Sel     : TArray<Integer>;
  Orig, Rem, Mvd: TRuleBlocks;
  Target, Bak: string;
begin
  Sel := CheckedIndexes(fi);
  if not CanOperateOn(Sel) or (fi < 0) then Exit;
  Target := AskTargetFile(ChangeFileExt(FSet.Item(fi).Path, '') + '-split'
    + ExtractFileExt(FSet.Item(fi).Path));
  if Target = '' then Exit;
  if SameText(Target, FSet.Item(fi).Path) then
  begin
    FStatus.SimpleText := 'Split target must be a different file.';
    Exit;
  end;
  Orig := FSet.Item(fi).Blocks;                        // to roll the model back on failure
  SplitOut(Orig, Sel, Rem, Mvd);
  if not WriteBlocksTo(Target, Mvd, Bak) then Exit;    // source untouched on failure
  FSet.SetBlocks(fi, Rem);
  if not SaveSet(fi) then
  begin
    // The target already holds the blocks but the source could not be rewritten, so
    // they now exist in BOTH files. Put the in-memory model back in step with disk
    // and say what actually happened -- never overwrite SaveSet's error with a
    // success message, which would hide a real duplication from the user.
    FSet.SetBlocks(fi, Orig);
    RefreshBlocks;
    FStatus.SimpleText := FStatus.SimpleText + Format(
      ' -- %d block(s) WERE written to %s, so they now exist in BOTH files; %s needs attention.',
      [Length(Mvd), ExtractFileName(Target), ExtractFileName(FSet.Item(fi).Path)]);
    Exit;
  end;
  RefreshBlocks;
  FStatus.SimpleText := Format('Moved %d block(s) to %s',
    [Length(Mvd), ExtractFileName(Target)]);
end;

procedure TCurationForm.DoCopy(Sender: TObject);
var
  fi  : Integer;
  Sel : TArray<Integer>;
  Cpy : TRuleBlocks;
  Target, Bak: string;
begin
  Sel := CheckedIndexes(fi);
  if not CanOperateOn(Sel) or (fi < 0) then Exit;
  Target := AskTargetFile(ChangeFileExt(FSet.Item(fi).Path, '') + '-copy'
    + ExtractFileExt(FSet.Item(fi).Path));
  if Target = '' then Exit;
  Cpy := CopyOut(FSet.Item(fi).Blocks, Sel);
  if not WriteBlocksTo(Target, Cpy, Bak) then Exit;
  // criterion 4: the source file is NOT written
  FStatus.SimpleText := Format('Copied %d block(s) to %s (source unchanged)',
    [Length(Cpy), ExtractFileName(Target)]);
end;

procedure TCurationForm.DoDelete(Sender: TObject);
var
  fi : Integer;
  Sel: TArray<Integer>;
begin
  Sel := CheckedIndexes(fi);
  if not CanOperateOn(Sel) or (fi < 0) then Exit;
  if MessageDlg(Format('Delete %d block(s) from %s?'#13#10
    + 'A backup is written first.', [Length(Sel), ExtractFileName(FSet.Item(fi).Path)]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FSet.SetBlocks(fi, DeleteBlocks(FSet.Item(fi).Blocks, Sel));
  SaveSet(fi);
  RefreshBlocks;
end;

procedure TCurationForm.DoMerge(Sender: TObject);
var
  fi   : Integer;
  Dlg  : TOpenDialog;
  Plan : TMergePlan;
  Res  : TArray<TMergeResolution>;
  InPath: string;
begin
  fi := FFiles.ItemIndex;
  if fi < 0 then Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Conversion rules (*.rules)|*.rules|Cast library (*.castlib)|*.castlib|'
      + 'reFind rules (*.txt)|*.txt|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    InPath := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  Plan := PlanMerge(FSet.Item(fi).Blocks,
    SplitBlocksFor(InPath, TFile.ReadAllText(InPath, TEncoding.ASCII)));

  Res := nil;
  if Plan.ConflictCount > 0 then
    // criterion 6: nothing is written until the conflicts are resolved
    if not AskResolutions(Self, Plan, ExtractFileName(InPath), Res) then
    begin
      FStatus.SimpleText := 'Merge cancelled -- nothing was written.';
      Exit;
    end;

  FSet.SetBlocks(fi, ApplyMerge(Plan, Res));
  SaveSet(fi);
  RefreshBlocks;
  ShowReport(Self, 'Merge report -- ' + ExtractFileName(InPath),
    MergeReportLines(Plan, Res, ExtractFileName(InPath)));
end;

procedure TCurationForm.DoCompose(Sender: TObject);
var
  Rep : TComposeReport;
  Text: string;
  Target, Bak: string;
  Head: TArray<string>;
begin
  if FSet.Count = 0 then Exit;
  Text   := FSet.ComposeAll(Rep);
  Target := AskTargetFile(ChangeFileExt(FSet.Item(0).Path, '') + '.composed.rules');
  if Target = '' then Exit;
  try
    WriteTextWithBackup(Target, Text, Bak);
    FTouched.AddOrSetValue(LowerCase(Target), True);
  except
    on E: Exception do
    begin
      FStatus.SimpleText := 'Compose failed, nothing changed: ' + E.Message;
      Exit;
    end;
  end;
  FStatus.SimpleText := Format('Composed %d file(s) into %s -- %d collision(s) '
    + 'resolved by precedence, %d block(s) appended',
    [FSet.Count, ExtractFileName(Target), Rep.ResolvedCount, Rep.AppendedCount]);
  SetLength(Head, 1);
  Head[0] := Format('%d collision(s) resolved by precedence, %d block(s) appended.'
    + ' Pass this file to --rules.', [Rep.ResolvedCount, Rep.AppendedCount]);
  ShowReport(Self, 'Compose report -- ' + ExtractFileName(Target), Head + Rep.Lines);
end;
```

`ShowReport` is a private unit-level helper -- a `CreateNew` form with a read-only `TMemo` (`Align := alClient`, `ScrollBars := ssBoth`, `WordWrap := False`) filled from the lines, plus a Close button; show it with `ShowModal`. Declare it in the implementation section above `TCurationForm`'s methods:

```pascal
procedure ShowReport(AOwner: TComponent; const ACaption: string;
  const ALines: TArray<string>);
```

Add `WriteBlocksTo` and `FFilesClick` to the class's private section:

```pascal
    procedure FFilesClick(Sender: TObject);
    function  WriteBlocksTo(const APath: string; const ABlocks: TRuleBlocks;
      out ABackup: string): Boolean;
```

- [ ] **Step 2: The conflict dialog**

A private helper inside the same unit -- do not create a second form file:

```pascal
{ Ask which side wins for each conflicting target. One row per conflict; checked =
  take the incoming link, unchecked (default) = keep what the target already has. }
function AskResolutions(AOwner: TComponent; const APlan: TMergePlan;
  const AIncomingName: string; out ARes: TArray<TMergeResolution>): Boolean;
```

Build it as a `TForm` created with `CreateNew`: a `TListView` (`vsReport`, `Checkboxes := True`) with columns `Target` (240), `Keep (existing)` (260), `Take (incoming)` (260), plus OK / Cancel buttons. Fill one row per `maConflict` item using `It.ToPath`, `It.ExistingLine`, `It.Line`. On OK, `SetLength(ARes, n)` and set `ARes[i] := mrTakeIncoming` when row i is checked, else `mrKeepExisting`. Return False on Cancel, and the caller then abandons the merge entirely (criterion 6: nothing is written until it is resolved).

- [ ] **Step 3: Wire the main form**

In `ConvRules.MainForm.pas`:

1. Add to the private section: `procedure DoCurate(Sender: TObject);`
2. In `BuildUI`, after the `Validate` button (which sits at `SetBounds(200, 6, 90, 25)`), add:

```pascal
  var BtnCurate: TButton := TButton.Create(Self);
  BtnCurate.Parent := FPanelTop; BtnCurate.SetBounds(296, 6, 90, 25);
  BtnCurate.Caption := 'Curate...';
  BtnCurate.Hint := 'Split / copy / delete / merge blocks across several rule-books, '
    + 'or compose them into one file for the engine';
  BtnCurate.ShowHint := True;
  BtnCurate.OnClick := DoCurate;
```

and move `FLblStatus`'s left edge from 300 to 392 so it does not sit under the new button:

```pascal
  FLblStatus.SetBounds(392, 11, 688, 15);
```

3. Add the handler next to `DoValidate`:

```pascal
procedure TConvRulesForm.DoCurate(Sender: TObject);
var
  Reload: string;
begin
  // Curation moves VERBATIM block text and deliberately does NOT go through this
  // form's canonical re-emitter, so a block that was merely moved stays byte-
  // identical. It works on the file ON DISK, so unsaved edits here are invisible
  // to it: Yes = save first, No = curate the on-disk version anyway, Cancel = out.
  if (FFilePath <> '') and (FBook.Nodes.Count > 0) then
    case MessageDlg('Curation works on the file on disk. Save your edits first?',
           mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrCancel: Exit;
      mrYes   : DoSave(nil);
    end;

  Reload := TCurationForm.Execute(Self, FFilePath);
  if Reload <> '' then
  begin
    LoadFile(Reload);
    SetStatus('Reloaded ' + ExtractFileName(Reload) + ' after curation.');
  end;
end;
```

4. Add `ConvRules.CurationForm` to the implementation `uses`.
5. Add `ConvRules.CurationForm in 'ConvRules.CurationForm.pas',` to `ConvRulesEditor.dpr`.

- [ ] **Step 4: Build**

```powershell
Start-Process -Wait -NoNewWindow -FilePath "C:\Projects\Delphi-RAG-lint-converter\build\_build_convrules_editor_local.bat" -RedirectStandardOutput "$env:TEMP\ce-build.log"
Get-Content "$env:TEMP\ce-build.log" -Tail 5
Start-Process -Wait -NoNewWindow -FilePath "C:\Projects\Delphi-RAG-lint-converter\build\_build_convrules_tests_local.bat" -RedirectStandardOutput "$env:TEMP\ct-build.log"
& "C:\Projects\Delphi-RAG-lint-converter\src\tools\convrules-editor\tests\ConvRulesModelTests.exe" | Select-Object -Last 3
```

Expected: both `BUILD_EXITCODE=0`; suite still `0 fail`.

- [ ] **Step 5: Manual verification checklist**

Copy `docs/examples/convrules/sample.rules` to a scratch file first -- **never curate the real one**:

```powershell
Copy-Item C:\Projects\Delphi-RAG-lint-converter\docs\examples\convrules\sample.rules "$env:TEMP\curation-test.rules"
& C:\Projects\Delphi-RAG-lint-converter\third_party\dll-win64\ConvRulesEditor.exe "$env:TEMP\curation-test.rules"
```

Walk this list and record the result of each line in the commit message:

1. `Curate...` opens the modal; the working set already lists `curation-test.rules`.
2. With nothing checked, Split / Copy / Delete are DISABLED (criterion 12). Checking one block enables all three.
3. Copy one `#convert` block to a new file -> the new file holds that block, and `curation-test.rules` is unchanged apart from nothing (criterion 4). Diff it against the original copy.
4. Split the same block out -> it disappears from the source, the source's `.bak` holds the pre-split text, and the target file gains it (criterion 3). Confirm the moved block still carries its `//` and `;` comments (criterion 2).
5. Merge the split-out file back in -> the block is appended whole (criterion 8), no conflicts.
6. Hand-edit the split-out file so one `#link` has the same target but a different source, merge again -> the conflict dialog appears listing that target; Cancel writes nothing; re-run and choose `Take incoming` -> only that one line changed.
7. Add a second file, Compose -> the composed file is written, the report names the resolved collisions, and `drag-lint convert-validate --rules <composed>` exits 0.
8. Open a `.castlib` (copy `docs/examples/convrules/casts.castlib` to `$env:TEMP` first) -> the grid shows `AssignGraphic` as the block name (criterion 13).

- [ ] **Step 6: Commit**

```bash
git add src/tools/convrules-editor/ConvRules.CurationForm.pas src/tools/convrules-editor/ConvRules.MainForm.pas src/tools/convrules-editor/ConvRulesEditor.dpr
git commit -m "feat(convrules): modal curation form (split/copy/delete/merge/compose)"
```

- [ ] **Step 7: Update the status doc**

Append to `docs/converter/STATUS.md` under a new `## LATEST` heading: the branch state, which criteria are covered by which tests, the manual-checklist results from Step 5, and the two known follow-ups below. Commit as `docs(converter): record curation feature status`.

---

## Known follow-ups (NOT in this plan)

- The main form's Save still re-emits canonical DSL for the whole file. After curating, pressing Save reformats blocks that curation deliberately left verbatim. Out of scope here; the curation path never routes through it, and `DoCurate` prompts the user to save BEFORE curating so the two writers do not interleave.
- Spec A+B+C (compatibility tiers, alias resolution, target ranking, enum maps) is the next spec.
- Spec D (DSL merge/split of property VALUES) needs an engine grammar change; file it to `docs/INBOX-*.md` when it comes up.

## Acceptance criteria coverage

| # | Criterion | Task | Test |
|---|---|---|---|
| 1 | Rejoin reproduces the file byte-for-byte | 1, 2 | `TestBlockSplitRulesRoundTrip`, `TestBlockSplitCastLibRoundTrip` |
| 2 | Comments / blanks / unknown directives survive a move | 3 | `TestBlockOpsSplitAndCopy` |
| 3 | Split out removes from source, writes to target in order | 3 | `TestBlockOpsSplitAndCopy` |
| 4 | Copy out leaves the source unchanged | 3 | `TestBlockOpsSplitAndCopy` |
| 5 | Duplicate link is skipped | 4 | `TestMergeSkipsDuplicate` |
| 6 | Different source for a linked target = conflict, nothing written | 4 | `TestMergeReportsConflict` |
| 7 | Used source -> new target is merged (fan-out) | 4 | `TestMergeAllowsFanOut` |
| 8 | Unmatched incoming block appended verbatim | 4 | `TestMergeAppendsUnmatchedBlock` |
| 9 | Compose resolves by precedence and reports every collision | 5 | `TestComposePrecedence` |
| 10 | Composed output passes convert-validate | 7 | `TestComposedFileValidates` |
| 11 | Rotating backup before every write, never overwritten | 6 | `TestBackupRotation` |
| 12 | Split/Copy/Delete disabled with no selection | 3 (rule), 8 (UI) | `TestBlockOpsEnablement` + manual step 2 |
| 13 | `.castlib` grid shows cast/enum names | 2 | `TestBlockLabel` |
| 14 | Failed backup aborts, files unmodified | 6 | `TestBackupFailureAborts` |
