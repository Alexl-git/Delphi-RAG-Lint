# R1 -- Linter Robustness & Visibility (v0.64) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `lint-all` fast (parse each file once), visible (streamed progress in CLI + IDE), and lower false-positive (fix the `{$IFEND}` syntax-error FP and add uncertainty guards to the noisiest rules).

**Architecture:** (1) A per-file parse cache so the ~36 `TAstChecker.CheckXxx` methods reuse one `TTSTree` instead of each re-reading + re-parsing the file. (2) `lint-all` streams per-file progress to stderr; the IDE plugin reads the child pipe incrementally and posts throttled progress. (3) `syntax-error` suppresses ERROR/MISSING nodes near unbalanced conditional-compilation directives; a fortification audit guards the known-noisy rules.

**Tech Stack:** Delphi 13 (Studio 37), tree-sitter-delphi13, Win64/Win32, PowerShell test harness (`tests/lint/run_lint_tests.ps1`).

## Global Constraints

- `.pas` files: strict 7-bit ASCII, CRLF, no BOM. DocInsight `///` on every new public declaration.
- Built-ins need a Win64 rebuild via the delphi-build skill (3-line wrapper + `Start-Process -Wait`); deploy `src/cli/Win64/Debug/drag-lint.exe` -> `third_party/dll-win64/drag-lint.exe`.
- The TDD harness `tests/lint/run_lint_tests.ps1` must stay 100% green (currently 75/75) after every task.
- A new unit must be added to BOTH `src/cli/drag-lint.dpr` `uses ... in '..'` AND `src/cli/drag-lint.dproj` `<DCCReference>`.
- Behavior-preserving refactor (Task 1-2): the SAME findings at the SAME lines before and after.

---

## File structure

- Create: `src/diagnostics/DRagLint.Diagnostics.ParseCache.pas` -- the per-file parse cache (one responsibility: parse-once + memoize + free).
- Modify: `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` -- each `CheckXxx` consults the cache instead of parsing inline.
- Modify: `src/cli/DRagLint.CLI.pas` -- `lint-all` progress + `--quiet`; clear the cache per file.
- Modify: `src/delphi-plugin/DragLint.Plugin.ProcRun.pas` (+ the Run Lint All caller in `DragLint.Plugin.Editor.pas`) -- incremental progress reader.
- Modify: `src/cli/drag-lint.dpr`, `src/cli/drag-lint.dproj` -- register the new unit.
- Tests: `tests/lint/syntax-error-ifend.pas` + `.expected`; reuse the full harness for regression.

---

## Task 1: Per-file parse cache unit

**Files:**
- Create: `src/diagnostics/DRagLint.Diagnostics.ParseCache.pas`
- Modify: `src/cli/drag-lint.dpr` (uses clause), `src/cli/drag-lint.dproj` (`<DCCReference>`)
- Test: `tests/lint/` harness (indirect, after Task 2) + a direct CLI smoke

**Interfaces:**
- Produces:
  - `TParsedFile = record Src: TBytes; Tree: TTSTree; end;`
  - `class function TAstParseCache.Get(const AFile: string): TParsedFile;` -- parses `AFile` once, memoizes by normalized path; returns `Tree=nil` if the file is missing/unreadable. The cache OWNS the `TTSTree` (callers must NOT free it).
  - `class procedure TAstParseCache.Clear;` -- frees all cached trees; call between files in a batch and at end of a single-file lint.

- [ ] **Step 1: Write the cache unit**

```pascal
unit DRagLint.Diagnostics.ParseCache;

interface

uses
  System.SysUtils, System.Generics.Collections, TreeSitter, TreeSitterLib;

type
  /// <summary>One parsed source file: raw bytes + the tree-sitter tree. The owning
  /// TAstParseCache frees Tree; consumers must not.</summary>
  TParsedFile = record
    Src : TBytes;
    Tree: TTSTree;
  end;

  /// <summary>Process-wide parse-once cache so the many TAstChecker rules reuse one
  /// TTSTree per file instead of each re-reading and re-parsing it.</summary>
  /// <remarks>Not thread-safe; the lint pipeline is single-threaded per process.
  /// Call Clear between files in a batch to bound memory.</remarks>
  TAstParseCache = class
  strict private
    class var FMap: TDictionary<string, TParsedFile>;
  public
    class function Get(const AFile: string): TParsedFile;
    class procedure Clear;
  end;

function tree_sitter_delphi13: PTSLanguage; cdecl; external 'tree-sitter-delphi13';

implementation

uses
  System.IOUtils;

class function TAstParseCache.Get(const AFile: string): TParsedFile;
var
  Key   : string;
  Parser: TTSParser;
  PF    : TParsedFile;
begin
  Key:= LowerCase(TPath.GetFullPath(AFile));
  if FMap = nil then FMap:= TDictionary<string, TParsedFile>.Create;
  if FMap.TryGetValue(Key, Result) then Exit;

  PF.Src := nil;
  PF.Tree:= nil;
  if TFile.Exists(AFile) then
  begin
    PF.Src:= TFile.ReadAllBytes(AFile);
    Parser:= TTSParser.Create;
    try
      Parser.Language:= tree_sitter_delphi13;
      PF.Tree:= Parser.Parse(
        function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
        var Remaining: Integer;
        begin
          Remaining:= Length(PF.Src) - Integer(AByteIndex);
          if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
          SetLength(Result, Remaining);
          Move(PF.Src[AByteIndex], Result[0], Remaining);
          ABytesRead:= Remaining;
        end, TTSInputEncoding.TSInputEncodingUTF8);
    finally
      Parser.Free; { the tree outlives the parser }
    end;
  end;
  FMap.Add(Key, PF);
  Result:= PF;
end;

class procedure TAstParseCache.Clear;
var PF: TParsedFile;
begin
  if FMap = nil then Exit;
  for PF in FMap.Values do PF.Tree.Free;
  FMap.Clear;
end;

end.
```

- [ ] **Step 2: Register the unit** in `src/cli/drag-lint.dpr` `uses` (`DRagLint.Diagnostics.ParseCache in '..\diagnostics\DRagLint.Diagnostics.ParseCache.pas',`) and add a matching `<DCCReference Include="..\diagnostics\DRagLint.Diagnostics.ParseCache.pas"/>` in `src/cli/drag-lint.dproj`.

- [ ] **Step 3: Build Win64** (delphi-build skill). Expected: `BUILD_EXITCODE=0`, no `[dcc64 Error]`.

- [ ] **Step 4: Commit**

```bash
git add src/diagnostics/DRagLint.Diagnostics.ParseCache.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj
git commit -m "feat(lint): per-file parse cache (parse-once substrate)"
```

---

## Task 2: Convert CheckXxx methods to the cache (behavior-preserving)

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` (every `CheckXxx` that parses)
- Modify: `src/cli/DRagLint.CLI.pas` -- call `TAstParseCache.Clear` per file in `DoLintAll` (after the per-file `try..except`, ~line 5127) and once after a single-file `DoLint`.

**Interfaces:**
- Consumes: `TAstParseCache.Get`, `TAstParseCache.Clear` from Task 1.

**Conversion pattern (apply to each method).** Each method today has this shape:

```pascal
  Src:= TFile.ReadAllBytes(AFile);
  ...
  Parser:= TTSParser.Create;
  Parser.Language:= tree_sitter_delphi13;
  Tree:= Parser.Parse( ... anonymous reader ... );
  if Tree <> nil then Visit(Tree.RootNode);
  ...
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
```

Replace with:

```pascal
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;   // missing/unreadable -> no findings
  Src:= PF.Src;                 // keep the local name the rest of the method uses
  ...
  Visit(PF.Tree.RootNode);
  ...
  finally
    Findings.Free;              // DO NOT free Tree/Parser -- the cache owns the tree
  end;
```

Declare `PF: TParsedFile;` in each method's `var`; delete the method's `Parser`/`Tree` locals and the inline `TFile.ReadAllBytes`. Add `DRagLint.Diagnostics.ParseCache` to the unit `uses`.

**Methods to convert** (the parsing ones): `CheckUnbalancedBeginEnd`, `CheckSyntaxErrors`, `CheckUnusedLocals`, `CheckRaiseInFinally`, `CheckCodeAfterExit`, `CheckMissingInherited`, `CheckControlFlowInFinally`, `CheckRoutineMetrics`, `CheckTypeAware`, `CheckFireDacSqlMismatch`, `CheckUnprotectedFree`, `CheckUseAfterFree`, `CheckUiThread`, `CheckGlobalFormVars`, `CheckShellExec`, `CheckPathTraversal`, `CheckLoopAtMostOnce`, `CheckFormatCall`, `CheckSwallowedExcept`, `CheckDatasetOpen`, `CheckCriticalSection`, `CheckTooManyExitPoints`, `CheckCyclomaticComplexity`, `CheckVirtualInConstructor`. (`CheckInterfaceCycles` takes a file LIST -- convert its per-file loop to `TAstParseCache.Get` too. `CheckUndeclared` reads text only, no tree -- switch its `TFile.ReadAllBytes` to `TAstParseCache.Get(AFile).Src`.)

- [ ] **Step 1: Convert one method first (`CheckSyntaxErrors`)** using the pattern above.
- [ ] **Step 2: Build Win64 + run the harness** filtered to a syntax fixture. Run: `pwsh -File tests\lint\run_lint_tests.ps1 -Filter "*"`. Expected: still 75/75 (the converted method behaves identically).
- [ ] **Step 3: Convert the remaining methods** (batch them; rebuild once at the end).
- [ ] **Step 4: Wire `TAstParseCache.Clear`** -- in `DoLintAll`'s per-file loop add `TAstParseCache.Clear;` inside the loop body after the checks (so each file's tree is freed before the next), and add one `TAstParseCache.Clear;` at the end of `DoLint`. In the LSP/`check-ast` path, call `Clear` after `TAstChecker.Check` returns.
- [ ] **Step 5: Build Win64, deploy exe, run full harness.** Run: `pwsh -File tests\lint\run_lint_tests.ps1`. Expected: **75 pass / 0 fail**.
- [ ] **Step 6: Verify the speedup** -- time `lint-all` on a medium DB before/after (informal). Expected: materially faster (one parse vs ~24 per file).
- [ ] **Step 7: Commit**

```bash
git add src/diagnostics/DRagLint.Diagnostics.AstChecks.pas src/cli/DRagLint.CLI.pas
git commit -m "refactor(lint): parse each file once -- all CheckXxx share the parse cache"
```

---

## Task 3: lint-all CLI progress + --quiet

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- the `DoLintAll` per-file loop (~line 5092) and the args parser for `--quiet`.

**Interfaces:**
- Consumes: `AArgs.Quiet: Boolean` (new arg field).

- [ ] **Step 1: Add `--quiet`** -- add `Quiet: Boolean` to `TArgs`; parse `--quiet` in the arg loop; default False.
- [ ] **Step 2: Stream progress to stderr** in the `DoLintAll` file loop. Before the loop keep the existing `lint-all: scanning N` line. Inside the loop, after computing the 1-based index `i`, emit a throttled line to `ErrOutput` (stderr keeps stdout/report clean):

```pascal
if (not AArgs.Quiet) then
begin
  var Pct := (i * 100) div Max(1, Length(FilePaths));
  if (i = 1) or (i = Length(FilePaths)) or (Pct <> LastPct) then
  begin
    Writeln(ErrOutput, Format('lint-all: [%d/%d] %d%% %s',
      [i, Length(FilePaths), Pct, ExtractFileName(PasPath)]));
    Flush(ErrOutput);
    LastPct := Pct;
  end;
end;
```

(Declare `i`, `LastPct: Integer` outside the loop; `LastPct := -1` before it; `Inc(i)` per iteration.)

- [ ] **Step 3: Build Win64, deploy.** Manual check: `drag-lint lint-all --db <db> 2>progress.txt >report.txt` shows percentage lines in `progress.txt`, clean report in `report.txt`; `--quiet` suppresses them.
- [ ] **Step 4: Confirm harness still green** (lint-all progress does not affect per-file `lint`). Run: `pwsh -File tests\lint\run_lint_tests.ps1`. Expected: 75/75.
- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas
git commit -m "feat(lint): lint-all streams per-file progress to stderr (+ --quiet)"
```

---

## Task 4: IDE incremental progress reader

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.ProcRun.pas` -- add a streaming variant.
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` -- the Run Lint All caller uses it and posts progress.

> **Note:** OTAPI/UI code has no unit-test harness; this task is build-verified + manual-tested (like the existing Run Lint All menu). No fixture.

**Interfaces:**
- Produces: `function RunCaptureStreaming(const ACmdLine: string; AOnLine: TProc<string>; out AExitCode: Integer): Boolean;` -- spawns CREATE_NO_WINDOW, reads the pipe line-by-line, invokes `AOnLine` per line (caller marshals to the UI thread), returns when the child exits.

- [ ] **Step 1: Add `RunCaptureStreaming`** to ProcRun -- same `CreatePipe`/`CreateProcessW` as `RunCaptureStdout`, but in the read loop split the buffer on newlines and call `AOnLine(line)` per complete line (buffer the partial tail). After the read loop, `WaitForSingleObject` + `GetExitCodeProcess`.
- [ ] **Step 2: Use it in Run Lint All** (Editor.pas) -- spawn the lint-all on the existing background `TThread`; in the per-line callback, `TThread.Queue` a post to the IDE Messages view, but only when the line starts with `lint-all:` and the percentage advanced (parse `%d%%`). Keep the final summary post.
- [ ] **Step 3: Build the BPL** (delphi-build, Win32, `dclDragLintWizard.dproj`) with RAD Studio closed. Expected: `BUILD_EXITCODE=0`.
- [ ] **Step 4: Deploy + manual test** -- `deploy-staged.bat`, restart RAD Studio, run Drag-Lint > Run Lint All; confirm the Messages view shows advancing `Lint-all: NN% (i/N)` lines and a final summary, IDE not frozen.
- [ ] **Step 5: Commit** (source + rebuilt BPL/DCP)

```bash
git add src/delphi-plugin/DragLint.Plugin.ProcRun.pas src/delphi-plugin/DragLint.Plugin.Editor.pas third_party/dll-win32/dclDragLintWizard.bpl third_party/dll-win32/dclDragLintWizard.dcp
git commit -m "feat(ide): Run Lint All streams live progress to the Messages view"
```

---

## Task 5: FP-1 -- syntax-error robust to {$IF}/{$IFEND}

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` -- `CheckSyntaxErrors`.
- Test: `tests/lint/syntax-error-ifend.pas` + `tests/lint/syntax-error-ifend.expected`.

**Interfaces:** none new.

- [ ] **Step 1: Write the failing fixture.** A unit that parses cleanly except for a `{$IF ...} ... {$IFEND}` block (mirror the CLIENT\MStreams.pas pattern that produced 12 false `syntax-error` findings), plus one GENUINE typo elsewhere that MUST still fire.

`tests/lint/syntax-error-ifend.pas` (illustrative; the `{$IFEND}` region must not fire, the real typo must):

```pascal
unit SyntaxErrorIfEnd;
interface
implementation

procedure UsesIfEnd;
begin
  {$IF Defined(MSWINDOWS)}
  Writeln('win');
  {$IFEND}
end;

procedure RealTypo;
begin
  if x > 0 then  // missing 'begin'/stmt is a genuine error region
    ;;;garbage syntax here@@@
end;

end.
```

`tests/lint/syntax-error-ifend.expected`:

```
# {$IF}/{$IFEND} must NOT produce syntax-error findings (grammar gap, FP-1)
!syntax-error 8
!syntax-error 9
!syntax-error 10
# but a genuine malformed line still fires somewhere in RealTypo
syntax-error 16
```

- [ ] **Step 2: Run harness -> RED.** Run: `pwsh -File tests\lint\run_lint_tests.ps1 -Filter syntax-error-ifend`. Expected: FAIL -- `syntax-error` fires on the `{$IFEND}` lines (the FP), confirming the bug. (If the genuine-typo line number differs once parsed, adjust the `.expected` to the observed real-error line via `tree-sitter.exe parse`.)
- [ ] **Step 3: Implement the guard** in `CheckSyntaxErrors`. Before adding an ERROR/MISSING finding, suppress it when the error span sits within (or adjacent to) a conditional-compilation region the grammar can't balance: scan `Src` for `{$IF` ... `{$IFEND}` (and `{$IF}`/`{$ELSEIF}` without a matching `{$ENDIF}`) and build a set of line ranges; if the finding's line falls in such a range, skip it. Keep firing for errors outside any directive range. (Comment the heuristic; FP policy: when unsure, do not report.)
- [ ] **Step 4: Run harness -> GREEN.** Run: `pwsh -File tests\lint\run_lint_tests.ps1 -Filter syntax-error-ifend`. Expected: PASS.
- [ ] **Step 5: Full harness + ORM3 spot check.** Run the full harness (75+1 green) and `lint --rule syntax-error CLIENT\MStreams.pas` -> the 12 FPs are gone.
- [ ] **Step 6: Commit**

```bash
git add src/diagnostics/DRagLint.Diagnostics.AstChecks.pas tests/lint/syntax-error-ifend.pas tests/lint/syntax-error-ifend.expected
git commit -m "fix(lint): syntax-error -- suppress findings inside {\$IF}/{\$IFEND} grammar-gap regions (FP-1)"
```

---

## Task 6: Fortification audit (uncertainty guards on noisy rules)

**Files:**
- Modify: the `.scm`/built-in for each rule the audit flags (start with `string-equality-comparison`, `large-magic-number`).
- Test: a negative fixture per guard added.

**Interfaces:** none new.

- [ ] **Step 1: Re-run lint-all on ORM3**, sort findings by rule-id count (the report already shows `large-magic-number` ~20.9k, `string-equality-comparison` ~2.9k). Pick the top noisy/low-value rules.
- [ ] **Step 2: Per rule, add a negative fixture** capturing the ambiguous case that should NOT fire, confirm RED, then add the guard (skip ambiguous cases / raise the threshold), confirm GREEN. Examples: `large-magic-number` -- exempt common non-magic constants (0,1,-1,2, powers of 2 used as flags, array/string indices); `string-equality-comparison` -- only fire when both operands are clearly string-typed literals/identifiers, else skip (FP policy).
- [ ] **Step 3: Full harness green** after each guard.
- [ ] **Step 4: Commit** each guard separately (`fix(lint): <rule> -- guard <ambiguous case>`).

---

## Task 7: Release v0.64.0-alpha

**Files:** `src/cli/DRagLint.CLI.pas` (VERSION const), `CHANGELOG.md`, `rules/README.md`.

- [ ] **Step 1: Bump** VERSION to `0.64.0-alpha`; add the CHANGELOG entry (parse-once speedup, lint-all progress, FP-1 fix + fortification, IDE live progress); update rules/README if any rule text changed.
- [ ] **Step 2: Full harness green.** Run: `pwsh -File tests\lint\run_lint_tests.ps1`. Expected: all green.
- [ ] **Step 3: Pack** -- `build/pack-lint-release.ps1 -Version 0.64.0-alpha`; re-run harness against the Release exe.
- [ ] **Step 4: Commit, push, tag, release**

```bash
git add -A && git commit -m "chore(release): v0.64.0-alpha -- parse-once, lint-all progress, FP-1 + fortification"
git push origin main
git tag -a v0.64.0-alpha -m "drag-lint v0.64.0-alpha -- R1 robustness & visibility"
git push origin v0.64.0-alpha
gh release create v0.64.0-alpha --repo Alexl-git/Delphi-RAG-Lint --latest --title "drag-lint v0.64.0-alpha" --notes-file <notes> <win64-zip> <win32-zip>
```

---

## Self-review notes

- **Spec coverage:** R1 spec items 4 (Task 3+4), 2 (Task 1+2), 1 (Task 5 FP-1 + Task 6 fortification) all have tasks. Release = Task 7.
- **Behavior-preserving:** Tasks 1-2 are guarded by the existing 75-fixture harness staying green; no `.expected` changes there.
- **Type consistency:** `TAstParseCache.Get`/`Clear` and `TParsedFile{Src,Tree}` are used identically in Task 2. `RunCaptureStreaming` signature in Task 4 matches its caller.
- **Known soft spots to resolve at execution time:** exact real-error line in the Task 5 fixture (verify with `tree-sitter.exe parse`); the precise method list in Task 2 (grep `Parser:= TTSParser.Create` to confirm none are missed).
