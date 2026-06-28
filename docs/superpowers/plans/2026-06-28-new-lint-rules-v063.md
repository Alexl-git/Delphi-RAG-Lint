# New Lint Rules v0.63 (Phase 2) -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.63.0-alpha: the IDE "Run Lint All" menu command plus 11 new Pascal built-in lint rules (5 "T2" + 6 "T3"), each with a TDD fixture, then a staged release whose public publish is gated on a manual IDE test.

**Architecture:** Every new rule is a pure-Pascal `class function TAstChecker.CheckXxx(const AFile: string): TArray<TLintFinding>` in `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` that builds its own tree-sitter parse and walks the AST (there is NO `.scm`+post-filter seam in this codebase -- the spec's "T2" label still means a pure-Pascal `TAstChecker` method). Each rule is wired into three CLI dispatch chains + the allow-list guard + the help string in `src/cli/DRagLint.CLI.pas`, needs NO `rules/<id>.json`, and requires a Win64 exe rebuild to go green. The IDE menu command is a new `TMenuItem` + handler in the `dclDragLintWizard` BPL plugin, mirroring the existing async `InvokeReindexProject` pattern.

**Tech Stack:** Delphi 13 / RAD Studio 37 (Object Pascal), tree-sitter-delphi13 grammar, DUnitX-free PowerShell fixture harness, OTAPI (ToolsAPI) for the IDE plugin.

**Execution order (decided 2026-06-28): C -> A -> B -> D.** C (IDE menu) first so it is ready for the user's hands-on RAD Studio test as early as possible; then A (T2 rules), B (T3 rules), D (staged release).

---

## Global Constraints

- **Encoding (verbatim):** `.pas`/`.scm` files are strict 7-bit ASCII, CRLF line endings -- never UTF-8, never LF. `.md` files (CHANGELOG/README) are UTF-8 and DO contain em-dashes -- never rewrite a `.md` with ASCII encoding (it corrupts `--` em-dashes to `?`). After writing any file with the Write tool (which emits LF on Windows), normalize line endings: for `.pas`/`.scm` use `ASCIIEncoding`; for `.md` use `UTF8Encoding($false)`.
- **DocInsight required:** every new public `TAstChecker` method gets a `///` `<summary>`/`<param>`/`<returns>`/`<remarks>` doc-comment (project CLAUDE.md rule). ASCII only.
- **Verify node kinds before writing match logic:** `C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse tests\lint\<id>.pas`. Never trust an assumed node kind or field name -- confirm against the parse output (Phase 1 caught off-by-ones and wrong field names this way).
- **Rebuild is mandatory per Pascal rule.** Unlike Phase 1's runtime-loaded `.scm`, a built-in cannot pass its fixture until `drag-lint.exe` (Win64) is rebuilt and redeployed. Build recipe: invoke the **delphi-build skill** (3-line `rsvars`+`msbuild` wrapper run via PowerShell `Start-Process -Wait`, then read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`). The CLI project is `src/cli/drag-lint.dproj`, Config=Release (or Debug for speed), Platform=Win64. After build, copy `src\cli\Win64\Release\drag-lint.exe` (or `Win64\Debug\`) to `third_party\dll-win64\drag-lint.exe` (the harness + IDE use that path). A clean Win64 build is ~5s.
- **Test harness:** `pwsh -File tests\lint\run_lint_tests.ps1 [-Filter <id>]`. It syncs `rules\` next to the exe and runs `drag-lint lint <file> --json`, matching findings by `rule:start_line`. `.expected` directives: `<rule-id> <line>` = a finding MUST exist there; `!<rule-id> <line>` = that exact (rule,line) MUST be absent; `!<rule-id>` = rule must not fire anywhere; `none` = file must be clean; `#` = comment. All existing fixtures (64 after Phase 1) must stay green.
- **`TLintFinding` record** (in `src/core/DRagLint.Core.Model.pas`): set only `RuleId`, `Severity` (`'error'|'warning'|'info'|'hint'`), `Message`, `FilePath`, `StartLine`, `StartCol`, `EndLine`, `EndCol`. Leave `Id`/`FileId` at default.
- **Built-in rules need NO `rules/<id>.json`.** Severity + message are hardcoded inside the `CheckXxx` method. (You may add a documentation row to `rules/README.md` at release time, but it is not loaded.)
- **Tree-sitter is 0-based; findings are 1-based:** `F.StartLine := Integer(P.Row) + 1; F.StartCol := Integer(P.Column) + 1;` where `P := N.StartPoint;`.

### Shared `TAstChecker.CheckXxx` skeleton (template T -- referenced by every rule task)

Every new method follows this exact skeleton. Each task gives only the rule-specific `Visit`/match body; wrap it in template T. Copy the local `NodeStr` closure verbatim (house style is per-method duplication -- do NOT extract a shared helper).

```pascal
class function TAstChecker.CheckXxx(const AFile: string): TArray<TLintFinding>;
var
  Src     : TBytes             ;
  Parser  : TTSParser          ;
  Tree    : TTSTree            ;
  Findings: TList<TLintFinding>;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  // ... rule-specific helpers + a recursive Visit(N) that fills Findings ...

begin
  Result:= nil;
  if not TFile.Exists(AFile) then Exit;
  Src:= TFile.ReadAllBytes(AFile);
  Findings:= TList<TLintFinding>.Create;
  Parser:= nil;
  Tree  := nil;
  try
    Parser:= TTSParser.Create;
    Parser.Language:= tree_sitter_delphi13;
    Tree:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      var
        Remaining: Integer;
      begin
        Remaining:= Length(Src) - Integer(AByteIndex);
        if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
    if Tree <> nil then Visit(Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Tree.Free;
    Parser.Free;
    Findings.Free;
  end;
end;
```

The emit idiom inside a match (`P: TTSPoint; F: TLintFinding;`):
```pascal
P:= N.StartPoint;
F:= Default(TLintFinding);
F.RuleId  := '<rule-id>';
F.Severity:= '<error|warning|info>';
F.Message := '<text>';            // Format(...) when interpolating
F.FilePath:= AFile;
F.StartLine:= Integer(P.Row) + 1;
F.StartCol := Integer(P.Column) + 1;
F.EndLine:= F.StartLine;
F.EndCol := F.StartCol + 1;
Findings.Add(F);
```
Cap output per file with `if N.IsNull or (Findings.Count >= 200) then Exit;` at the top of `Visit`.

### Tree-sitter node/field API (confirmed in `DRagLint.Diagnostics.AstChecks.pas`)

`TTSNode` members: `IsNull: Boolean`, `NodeType: string` (kind), `ChildCount: Integer`, `Child(I): TTSNode` (all children incl. keyword tokens), `NamedChildCount: Integer`, `NamedChild(I): TTSNode` (named only), `ChildByField('field'): TTSNode`, `StartByte`/`EndByte: UInt32`, `StartPoint`/`EndPoint: TTSPoint` (`.Row`/`.Column` 0-based).

Confirmed node kinds: `defProc` (routine; has fields `header`, `body`, `local`), `if`, `ifElse`, `while`, `for`, `repeat`, `case`, `with`, `try`, `kFinally`/`kExcept`/`kThen`/`kElse` (k-prefixed = keyword tokens), `raise`, `assignment` (`lhs`/`operator`/`rhs`), `exprBinary` (`lhs`/`operator`/`rhs`), `exprCall` (`entity`/`args`), `exprDot` (`lhs`/`rhs`), `exprArgs`, `identifier`, `literalString`, `literalNumber`, `statement`, `statements`, `block`, `declArg`, `declVar`, `declField`, `kAdd`, `kSub`, `kEq`, `kNeq`, `kLt`, `kGt`. Operator/keyword node kinds NOT yet confirmed (verify per task): `kAnd`/`kOr` (cyclomatic), the `except` clause node kind, the `constructor` routine marker, the `case` branch/label node kind.

### Per-rule wiring recipe (5 edit points in `src/cli/DRagLint.CLI.pas`, 1 in AstChecks)

For each new built-in rule id `<id>` with method `CheckXxx`:
1. **Declare** `CheckXxx` in the `TAstChecker` `public` section of `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` (after `CheckGlobalFormVars`, ~line 129) with a DocInsight `///` block; implement it in the `implementation` section.
2. **Allow-list guard** (`DoLint`, ~lines 4196-4203): add `and (AArgs.Rule <> '<id>')` to the boolean chain so `--rule <id>` is accepted.
3. **Help string** (~line 4206): append `<id>` to the human-readable "known: ..." list.
4. **`DoLint` per-file dispatch** (~lines 4241-4277, inside the `.pas`/`.inc` block): add
   `if (AArgs.Rule = '') or (AArgs.Rule = '<id>') then Findings:= Findings + DRagLint.Diagnostics.AstChecks.TAstChecker.CheckXxx(AArgs.Path);`
   (For a method emitting multiple ids, use the `for F in CheckXxx(AArgs.Path) do if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then Findings:= Findings + [F];` form.)
5. **`DoLintAll` dispatch** (~lines 5075-5091): add the unconditional `Findings:= Findings + ...CheckXxx(PasPath);` line.
6. **Project-lint dispatch** (~lines 708-723): add the same unconditional line so `lint-project` runs it.

Exact line numbers drift as code is added -- locate by the surrounding text (e.g. the `global-form-variable` lines) each time rather than trusting the number.

### Build / test / commit cycle (per rule)

1. Verify node kinds: `tree-sitter.exe parse tests\lint\<id>.pas`.
2. Write `tests\lint\<id>.pas` + `tests\lint\<id>.expected`; normalize to CRLF/ASCII.
3. (Optional) run harness filtered -> FAIL (rule unknown / no findings).
4. Implement `CheckXxx` + the 5 wiring edits.
5. Rebuild Win64 (delphi-build skill); deploy exe to `third_party\dll-win64\drag-lint.exe`.
6. `pwsh -File tests\lint\run_lint_tests.ps1 -Filter <id>` -> PASS; then full harness -> all green.
7. Commit the 2 source files + 2 fixture files.

---

## Group C -- IDE "Run Lint All" menu command

### Task C1: Add the "Run Lint All (Full Report)" menu item to the wizard BPL

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (interface forward-decl ~line 95; new handler `InvokeLintAll`; one `AddWrappedItem` line in `RegisterDragLintMenu` ~line 3357 "Diagnostics && Tests" block)
- Build: `src/delphi-plugin/dclDragLintWizard.dproj` (Win32 design-only BPL)

**Interfaces consumed (all already in `Editor.pas`):**
- `GetActiveProjectFile: string` (~1030), `GetActiveProjectDb: string` (~1048), `DLExe: string` (~2468), `DLOpenInEditor(const AFilePath: string)` (~2475).
- `RunAndCaptureStdout(const ACmd: string; out AOut: string; ATimeoutMs: Integer): Integer` (~965).
- `IOTAModuleServices.SaveAll`, `IOTAMessageServices.AddTitleMessage`, `IOTAActionServices.OpenFile`.
- `lint-all` CLI contract: `drag-lint lint-all --db <db> --project <dproj> --out <report.txt>`; exit codes **0 = no findings, 1 = findings (both success), 2 = usage/no-index error**; stdout last line: `lint-all: N finding(s) -- E error(s), W warning(s) -- F file(s) -- report: <path>`.

- [ ] **Step 1: Forward-declare the handler**

In the `interface` section of `DragLint.Plugin.Editor.pas`, near the other `Invoke*` forward declarations (~line 95), add:
```pascal
procedure InvokeLintAll(Sender: TObject);
```

- [ ] **Step 2: Implement the handler** (in the `implementation` section, near `InvokeReindexProject` ~line 3216)

```pascal
procedure InvokeLintAll(Sender: TObject);
var
  Proj   : string            ;
  Db     : string            ;
  OutPath: string            ;
  Cmd    : string            ;
  MS     : IOTAModuleServices;
begin
  Proj:= GetActiveProjectFile;
  Db  := GetActiveProjectDb;
  if (Proj = '') or (Db = '') then
  begin
    ShowMessage('drag-lint: no active project or index found.');
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;

  OutPath:= TPath.Combine(ExtractFilePath(Proj),
            'lint-report-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.txt');
  Cmd:= Format('"%s" lint-all --db "%s" --project "%s" --out "%s"', [DLExe, Db, Proj, OutPath]);
  DLT('menu', 'run(async): ' + Cmd);

  TThread.CreateAnonymousThread(
    procedure
    var
      Output  : string ;
      ExitCode: Integer;
      Summary : string ;
    begin
      Output:= '';
      ExitCode:= 2;
      try
        ExitCode:= RunAndCaptureStdout(Cmd, Output, 600000);
      except
        on E: Exception do Output:= 'drag-lint: lint-all failed: ' + E.ClassName + ': ' + E.Message;
      end;
      // last non-empty stdout line is the "lint-all: ..." summary
      Summary:= Trim(Output);
      if Summary <> '' then
        Summary:= Trim(Copy(Summary, LastDelimiter(#10, Summary) + 1, MaxInt));
      TThread.Queue(nil,
        procedure
        var
          MsgSvc: IOTAMessageServices;
        begin
          if ExitCode = 2 then
          begin
            ShowMessage('drag-lint: lint-all failed (no index?). See plugin log.');
            Exit;
          end;
          if FileExists(OutPath) then DLOpenInEditor(OutPath);
          if Supports(BorlandIDEServices, IOTAMessageServices, MsgSvc) then
            MsgSvc.AddTitleMessage('drag-lint ' + Summary);
        end);
    end).Start;
end;
```

Notes: `RunAndCaptureStdout` returns the child exit code; `lint-all` returns 1 when findings exist (NOT a failure) -- only `2` is an error. `DLT` is the plugin's log helper (already in unit). `TPath`/`FormatDateTime`/`LastDelimiter` need `System.IOUtils`, `System.SysUtils` in the uses (verify they're already there; `TPath` is used elsewhere in the unit).

- [ ] **Step 3: Register the menu item**

In `RegisterDragLintMenu`, in the `{ ---- Diagnostics & Tests (alpha) ---- }` block (~line 3357, alongside `AddWrappedItem(RootMenu, 'Run AST Checks', InvokeRunAstChecks);`), add:
```pascal
  AddWrappedItem(RootMenu, 'Run Lint All (Full Report)', InvokeLintAll);
```

- [ ] **Step 4: Build the BPL** (delphi-build skill, Win32, design-only package)

Write a wrapper bat (do NOT commit it -- it matches the gitignored `build*.bat`):
```bat
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild /t:Build /p:Config=Debug /p:Platform=Win32 /v:normal "C:\Projects\Delphi-RAG-lint\src\delphi-plugin\dclDragLintWizard.dproj"
echo BUILD_EXITCODE=%ERRORLEVEL%
```
Run via PowerShell `Start-Process -Wait` with output redirected to a log; confirm `BUILD_EXITCODE=0` and no `[dcc] Error`. If the BPL is locked ("used by another process"), RAD Studio has it loaded -- the user must close the IDE or unload the package first. The build deploys/stages the BPL to `third_party\dll-win32\dclDragLintWizard.bpl`.

- [ ] **Step 5: Commit (code only -- the in-IDE behaviour is user-tested later)**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas third_party/dll-win32/dclDragLintWizard.bpl third_party/dll-win32/dclDragLintWizard.dcp
git commit -m "feat(ide): Run Lint All (Full Report) menu command in the wizard BPL"
```

**Manual verification (USER, when they return):** In RAD Studio with a project open, click **drag-lint > Run Lint All (Full Report)**; confirm it does not freeze the IDE, a `lint-report-<timestamp>.txt` opens in the editor, and a `drag-lint lint-all: ...` summary line appears in the Messages view. This is the v0.63 release gate (Group D holds the public publish until the user confirms this).

---

## Group A -- "T2" rules (pure-Pascal `TAstChecker` methods)

All five use template T + the wiring recipe. Each task: verify nodes -> fixture+expected -> method -> 5 wiring edits -> rebuild Win64 -> harness -> commit.

### Task A1: `unsanitized-shellexecute` (error) -- non-literal command to a process launcher

**Detects:** `WinExec`, `ShellExecute`, or `CreateProcess` where the command/executable argument is not a `literalString` (a runtime-built command can be injected). Method `CheckShellExec`. Per-callee command-arg index: `WinExec` -> 0, `ShellExecute` -> 2 (lpFile), `CreateProcess` -> 1 (lpCommandLine).

- [ ] **Step 1: Fixture** `tests/lint/unsafe-shellexecute.pas`
```pascal
unit UnsafeShellExecute;

interface

implementation

uses Windows, ShellAPI;

procedure Bad(const Cmd: string);
begin
  WinExec(PAnsiChar(AnsiString(Cmd)), SW_SHOW);
  ShellExecute(0, 'open', PChar(Cmd), nil, nil, SW_SHOW);
end;

procedure Good;
begin
  WinExec('notepad.exe', SW_SHOW);
  ShellExecute(0, 'open', 'C:\Windows\notepad.exe', nil, nil, SW_SHOW);
end;

end.
```

- [ ] **Step 2: Verify nodes** -- `tree-sitter.exe parse tests\lint\unsafe-shellexecute.pas`. Confirm: each call is `exprCall` with `entity: (identifier)` and `args: (exprArgs ...)`; `exprArgs.NamedChild(i)` is the i-th argument; the literal cases are `literalString`; the bad cases are `exprCall` (the `PChar(...)` / `PAnsiChar(...)` typecast). Note actual lines of the two Bad calls for the `.expected`.

- [ ] **Step 3: Expected** `tests/lint/unsafe-shellexecute.expected` (adjust line numbers to the parse)
```
# WinExec + ShellExecute with non-literal command; Good proc clean
unsafe-shellexecute 11
unsafe-shellexecute 12
!unsafe-shellexecute 18
!unsafe-shellexecute 19
```

- [ ] **Step 4: Method `CheckShellExec`** (rule-specific body inside template T)
```pascal
  function CmdArgIndex(const ACallee: string; out AIdx: Integer): Boolean;
  begin
    Result:= True;
    if SameText(ACallee, 'WinExec') then AIdx:= 0
    else if SameText(ACallee, 'ShellExecute') then AIdx:= 2
    else if SameText(ACallee, 'CreateProcess') then AIdx:= 1
    else Result:= False;
  end;

  procedure Visit(const N: TTSNode);
  var
    I, Idx : Integer;
    Ent, Args, A: TTSNode;
    P: TTSPoint; F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and CmdArgIndex(NodeStr(Ent), Idx) then
      begin
        Args:= N.ChildByField('args');
        if (not Args.IsNull) and (Args.NamedChildCount > Idx) then
        begin
          A:= Args.NamedChild(Idx);
          if A.NodeType <> 'literalString' then
          begin
            P:= Ent.StartPoint;
            F:= Default(TLintFinding);
            F.RuleId  := 'unsafe-shellexecute';
            F.Severity:= 'error';
            F.Message := Format('%s called with a non-literal command argument -- a runtime-built command path is an injection risk (CWE-78). Validate or use a fixed literal.', [NodeStr(Ent)]);
            F.FilePath:= AFile;
            F.StartLine:= Integer(P.Row) + 1;
            F.StartCol := Integer(P.Column) + 1;
            F.EndLine:= F.StartLine;
            F.EndCol := F.StartCol + 1;
            Findings.Add(F);
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;
```

- [ ] **Step 5: Wire** (recipe edit points 1-6) for id `unsafe-shellexecute` / method `CheckShellExec`. **Step 6: Rebuild Win64 + deploy. Step 7: Harness `-Filter unsafe-shellexecute` then full. Step 8: Commit.**
```bash
git add src/diagnostics/DRagLint.Diagnostics.AstChecks.pas src/cli/DRagLint.CLI.pas tests/lint/unsafe-shellexecute.pas tests/lint/unsafe-shellexecute.expected
git commit -m "feat(lint): unsafe-shellexecute -- non-literal command to WinExec/ShellExecute/CreateProcess"
```

---

### Task A2: `path-traversal` (warning) -- concatenated path to a file API

**Detects:** `AssignFile`, `FileOpen`, `CreateFile`, or `TFile.Open` where the path argument is a string-concatenation (`exprBinary` with `kAdd` operator) -- a user-controlled segment may escape the directory. Method `CheckPathTraversal`. Path-arg index: `AssignFile` -> 1, `FileOpen`/`CreateFile` -> 0, and `exprDot` callee whose `rhs` is `Open` -> 0.

- [ ] **Step 1: Fixture** `tests/lint/path-traversal.pas`
```pascal
unit PathTraversal;

interface

implementation

uses System.SysUtils;

procedure Bad(const Name: string);
var
  F: TextFile;
begin
  AssignFile(F, 'C:\data\' + Name);
  FileOpen('C:\logs\' + Name, fmOpenRead);
end;

procedure Good;
var
  F: TextFile;
begin
  AssignFile(F, 'C:\data\fixed.txt');
end;

end.
```

- [ ] **Step 2: Verify nodes** -- parse; confirm `'C:\data\' + Name` is `exprBinary` with `operator: (kAdd)`; the literal-only `AssignFile` arg1 is `literalString`. Note the two Bad lines.

- [ ] **Step 3: Expected** `tests/lint/path-traversal.expected`
```
path-traversal 12
path-traversal 13
!path-traversal 20
```

- [ ] **Step 4: Method `CheckPathTraversal`** (body inside template T)
```pascal
  function PathArgIndex(const N: TTSNode; out AIdx: Integer): Boolean;
  var
    Ent, R: TTSNode;
    Nm: string;
  begin
    Result:= False;
    Ent:= N.ChildByField('entity');
    if Ent.IsNull then Exit;
    if Ent.NodeType = 'identifier' then
    begin
      Nm:= NodeStr(Ent);
      if SameText(Nm, 'AssignFile') then begin AIdx:= 1; Exit(True); end;
      if SameText(Nm, 'FileOpen') or SameText(Nm, 'CreateFile') then begin AIdx:= 0; Exit(True); end;
    end
    else if Ent.NodeType = 'exprDot' then
    begin
      R:= Ent.ChildByField('rhs');
      if (not R.IsNull) and (R.NodeType = 'identifier') and SameText(NodeStr(R), 'Open') then begin AIdx:= 0; Exit(True); end;
    end;
  end;

  procedure Visit(const N: TTSNode);
  var
    I, Idx: Integer;
    Args, A, Op: TTSNode;
    P: TTSPoint; F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if (N.NodeType = 'exprCall') and PathArgIndex(N, Idx) then
    begin
      Args:= N.ChildByField('args');
      if (not Args.IsNull) and (Args.NamedChildCount > Idx) then
      begin
        A:= Args.NamedChild(Idx);
        if A.NodeType = 'exprBinary' then
        begin
          Op:= A.ChildByField('operator');
          if (not Op.IsNull) and (Op.NodeType = 'kAdd') then
          begin
            P:= A.StartPoint;
            F:= Default(TLintFinding);
            F.RuleId  := 'path-traversal';
            F.Severity:= 'warning';
            F.Message := 'Concatenated file path -- a user-controlled segment can escape the intended directory (path traversal, CWE-22). Validate or canonicalize the path.';
            F.FilePath:= AFile;
            F.StartLine:= Integer(P.Row) + 1;
            F.StartCol := Integer(P.Column) + 1;
            F.EndLine:= F.StartLine;
            F.EndCol := F.StartCol + 1;
            Findings.Add(F);
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;
```

- [ ] **Steps 5-8:** wire (`path-traversal`/`CheckPathTraversal`), rebuild, harness, commit (`feat(lint): path-traversal -- concatenated path to AssignFile/FileOpen/CreateFile/TFile.Open`).

---

### Task A3: `loop-executes-at-most-once` (warning) -- Exit/Break/raise as the first loop statement

**Detects:** `Exit`, `Break`, or `raise` as the FIRST statement of a `for`/`while`/`repeat` body (not nested in a conditional). The loop body never reaches a second iteration. Method `CheckLoopAtMostOnce`. The "not nested" condition is automatic: only the direct first statement is inspected, so an `Exit` inside an `if` is the `if` node, not an exit.

- [ ] **Step 1: Fixture** `tests/lint/loop-executes-at-most-once.pas`
```pascal
unit LoopAtMostOnce;

interface

implementation

procedure Bad;
var
  I: Integer;
begin
  for I := 1 to 10 do
  begin
    Exit;
    Writeln(I);
  end;
  while I > 0 do
    Break;
end;

procedure Good;
var
  I: Integer;
begin
  for I := 1 to 10 do
  begin
    if I = 5 then Exit;
    Writeln(I);
  end;
end;

end.
```

- [ ] **Step 2: Verify nodes (CRITICAL)** -- parse the fixture and determine: (a) the `body:` field/child of `for`/`while`/`repeat`; (b) when the body is a `begin..end`, its node kind (`statements`/`block`) and how to get the first statement (first named child); (c) the node kind of a bare `Exit;`/`Break;` statement (identifier? `exprCall`? a `statement` wrapper around one?) and of `raise`. Record the exact shapes; the helper below assumes: loop has a `body` field; a compound body is `statements` whose first `NamedChild(0)` is the first statement; a single-statement body is the statement itself; `Exit`/`Break` are an `identifier` or `exprCall` with that text; `raise` is node kind `raise`. **Adjust the helper to match the actual parse.**

- [ ] **Step 3: Expected** `tests/lint/loop-executes-at-most-once.expected`
```
# Exit first in for-body (line 13), Break single-stmt while-body (line 17); nested-if Exit (line 26) NOT flagged
loop-executes-at-most-once 13
loop-executes-at-most-once 17
!loop-executes-at-most-once 26
```

- [ ] **Step 4: Method `CheckLoopAtMostOnce`** (body inside template T; refine per Step 2)
```pascal
  function FirstStmt(const ABody: TTSNode): TTSNode;
  begin
    Result:= ABody;
    if Result.IsNull then Exit;
    // unwrap a 'statement' wrapper
    if (Result.NodeType = 'statement') and (Result.NamedChildCount >= 1) then Result:= Result.NamedChild(0);
    if (Result.NodeType = 'statements') or (Result.NodeType = 'block') then
    begin
      if Result.NamedChildCount >= 1 then Result:= Result.NamedChild(0) else Exit(Default(TTSNode));
      if (Result.NodeType = 'statement') and (Result.NamedChildCount >= 1) then Result:= Result.NamedChild(0);
    end;
  end;

  function IsAtMostOnceExit(const N: TTSNode): Boolean;
  var
    T: string;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'raise' then Exit(True);
    if (N.NodeType = 'identifier') or (N.NodeType = 'exprCall') then
    begin
      T:= NodeStr(N);
      if (N.NodeType = 'exprCall') then T:= NodeStr(N.ChildByField('entity'));
      Result:= SameText(T, 'Exit') or SameText(T, 'Break');
    end;
  end;

  procedure Visit(const N: TTSNode);
  var
    I: Integer;
    Body, Fs: TTSNode;
    P: TTSPoint; F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if (N.NodeType = 'for') or (N.NodeType = 'while') or (N.NodeType = 'repeat') then
    begin
      Body:= N.ChildByField('body');
      Fs:= FirstStmt(Body);
      if IsAtMostOnceExit(Fs) then
      begin
        P:= Fs.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'loop-executes-at-most-once';
        F.Severity:= 'warning';
        F.Message := 'Loop body begins with Exit/Break/raise -- the loop runs at most once. Move the statement before the loop, or fix the loop logic.';
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + 1;
        Findings.Add(F);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;
```
Note `repeat`'s body field may differ (its statements sit between `repeat` and `until`); if `repeat` has no `body` field, handle it by taking the first `statements`/statement child after the `kRepeat` token (verify in Step 2; drop `repeat` from the match if its shape is awkward and there is no fixture case for it -- the fixture only tests `for` and `while`).

- [ ] **Steps 5-8:** wire, rebuild, harness, commit (`feat(lint): loop-executes-at-most-once -- Exit/Break/raise as first loop statement`).

---

### Task A4: `format-argument-count` (error) -- %-specifier count != array element count

**Detects:** `Format('literal', [args])` where the number of conversion specifiers in the literal does not equal the number of array elements. Requires BOTH a `literalString` first arg and an array-constructor second arg (skip silently otherwise -- a variable format string can't be checked). Method `CheckFormatCall` (A5 extends the SAME method).

- [ ] **Step 1: Fixture** `tests/lint/format-argument-count.pas`
```pascal
unit FormatArgCount;

interface

implementation

uses System.SysUtils;

procedure Bad;
var
  S: string;
begin
  S := Format('%s = %d', ['only-one']);
  S := Format('%d', [1, 2, 3]);
end;

procedure Good;
var
  S: string;
  V: Integer;
begin
  S := Format('%s = %d', ['x', 42]);
  S := Format('%d%%', [V]);
end;

end.
```

- [ ] **Step 2: Verify nodes (CRITICAL)** -- parse; determine the node kind of the array constructor `[ ... ]` (candidates: `set`, `exprSet`, `array`, `setLiteral`) and how to count its elements (`NamedChildCount`, or named children minus the brackets). Confirm the format string is `literalString` and `NodeStr` returns it WITH surrounding quotes (strip them). Record the node kind as `<SET_KIND>` and use it below. Note the two Bad lines and that `'%d%%'` in Good has ONE real specifier (the `%%` is an escaped percent, not a conversion).

- [ ] **Step 3: Expected** `tests/lint/format-argument-count.expected`
```
# '%s = %d' with 1 arg (line 12); '%d' with 3 args (line 13); Good calls match
format-argument-count 12
format-argument-count 13
!format-argument-count 19
!format-argument-count 20
```

- [ ] **Step 4: Method `CheckFormatCall`** (count check; A5 adds the type check to this same method)
```pascal
  // Count conversion specifiers in a Format literal, excluding %% escapes.
  // Returns the ordered list of conversion chars (lowercased) via AKinds.
  function SpecKinds(const ALit: string; out AKinds: TArray<Char>): Integer;
  var
    M: TMatch;
    Kinds: TList<Char>;
    Body, Conv: string;
  begin
    // strip surrounding quotes, collapse '' escapes is not needed for spec counting
    Body:= ALit;
    if (Length(Body) >= 2) and (Body[1] = '''') then Body:= Copy(Body, 2, Length(Body) - 2);
    Body:= StringReplace(Body, '%%', '', [rfReplaceAll]); // drop escaped percents
    Kinds:= TList<Char>.Create;
    try
      for M in TRegEx.Matches(Body, '%[-+ 0#]*(\d+|\*)?(\.(\d+|\*))?([a-zA-Z])') do
      begin
        Conv:= M.Groups[4].Value;
        if Conv <> '' then Kinds.Add(LowerCase(Conv)[1]);
      end;
      AKinds:= Kinds.ToArray;
      Result:= Length(AKinds);
    finally
      Kinds.Free;
    end;
  end;

  procedure Visit(const N: TTSNode);
  var
    I, NSpec: Integer;
    Ent, Args, Fmt, Arr: TTSNode;
    Kinds: TArray<Char>;
    P: TTSPoint; F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and SameText(NodeStr(Ent), 'Format') then
      begin
        Args:= N.ChildByField('args');
        if (not Args.IsNull) and (Args.NamedChildCount >= 2) then
        begin
          Fmt:= Args.NamedChild(0);
          Arr:= Args.NamedChild(1);
          if (Fmt.NodeType = 'literalString') and (Arr.NodeType = '<SET_KIND>') then
          begin
            NSpec:= SpecKinds(NodeStr(Fmt), Kinds);
            if NSpec <> Arr.NamedChildCount then
            begin
              P:= Ent.StartPoint;
              F:= Default(TLintFinding);
              F.RuleId  := 'format-argument-count';
              F.Severity:= 'error';
              F.Message := Format('Format string has %d specifier(s) but %d argument(s) were supplied.', [NSpec, Arr.NamedChildCount]);
              F.FilePath:= AFile;
              F.StartLine:= Integer(P.Row) + 1;
              F.StartCol := Integer(P.Column) + 1;
              F.EndLine:= F.StartLine;
              F.EndCol := F.StartCol + 1;
              Findings.Add(F);
            end;
            // A5 type-check loop is inserted HERE (same Fmt/Arr/Kinds).
          end;
        end;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;
```
Add `System.RegularExpressions` to the unit uses if not present (it is -- see uses clause). Replace `<SET_KIND>` with the verified node kind.

- [ ] **Steps 5-8:** wire (`format-argument-count`/`CheckFormatCall`), rebuild, harness, commit (`feat(lint): format-argument-count -- Format specifier/argument count mismatch`).

---

### Task A5: `format-specifier-type-mismatch` (error) -- literal arg type vs specifier family

**Detects:** within the SAME `Format('literal', [literals...])`, a literal argument whose type is incompatible with its positional specifier family: `%d/%u/%x/%i` require an integer literal (a string literal is an error); `%f/%g/%e/%n` require a numeric literal; `%s` accepts any literal; variables/expressions are skipped. Extends `CheckFormatCall` (A4) -- one method, two wired rule ids.

- [ ] **Step 1: Fixture** `tests/lint/format-specifier-type-mismatch.pas`
```pascal
unit FormatTypeMismatch;

interface

implementation

uses System.SysUtils;

procedure Bad;
var
  S: string;
begin
  S := Format('%d', ['notanumber']);
  S := Format('%f', ['x']);
end;

procedure Good;
var
  S: string;
  V: Integer;
begin
  S := Format('%d', [42]);
  S := Format('%s', ['text']);
  S := Format('%d', [V]);
end;

end.
```

- [ ] **Step 2: Verify nodes** -- confirm integer vs float literal both parse as `literalNumber` and are told apart by a `.` in `NodeStr` (e.g. `42` vs `4.2`); `'text'` is `literalString`. Note the two Bad lines.

- [ ] **Step 3: Expected** `tests/lint/format-specifier-type-mismatch.expected`
```
# %d with string (line 12), %f with string (line 13); Good calls clean (V is a variable -> skipped)
format-specifier-type-mismatch 12
format-specifier-type-mismatch 13
!format-specifier-type-mismatch 20
!format-specifier-type-mismatch 21
!format-specifier-type-mismatch 22
```

- [ ] **Step 4: Extend `CheckFormatCall`** -- after the count-check block (where the `// A5 type-check loop is inserted HERE` comment sits), add:
```pascal
            // A5: per-argument literal-type vs specifier-family check.
            for I:= 0 to Length(Kinds) - 1 do
            begin
              if I >= Arr.NamedChildCount then Break;
              var Elem: TTSNode:= Arr.NamedChild(I);
              var K: Char:= Kinds[I];
              var IsNum: Boolean:= (K = 'd') or (K = 'u') or (K = 'x') or (K = 'i') or (K = 'f') or (K = 'g') or (K = 'e') or (K = 'n');
              var IsIntOnly: Boolean:= (K = 'd') or (K = 'u') or (K = 'x') or (K = 'i');
              var Bad: Boolean:= False;
              if Elem.NodeType = 'literalString' then
                Bad:= IsNum            // numeric specifier, string literal
              else if Elem.NodeType = 'literalNumber' then
                Bad:= IsIntOnly and (Pos('.', NodeStr(Elem)) > 0); // integer specifier, float literal
              // identifiers / expressions: skip (no type resolver)
              if Bad then
              begin
                var PE: TTSPoint:= Elem.StartPoint;
                var FE: TLintFinding:= Default(TLintFinding);
                FE.RuleId  := 'format-specifier-type-mismatch';
                FE.Severity:= 'error';
                FE.Message := Format('Argument %d is incompatible with format specifier "%%%s".', [I + 1, K]);
                FE.FilePath:= AFile;
                FE.StartLine:= Integer(PE.Row) + 1;
                FE.StartCol := Integer(PE.Column) + 1;
                FE.EndLine:= FE.StartLine;
                FE.EndCol := FE.StartCol + 1;
                Findings.Add(FE);
              end;
            end;
```
(Uses inline `var` decls -- valid in Delphi 13. `I` is the outer loop var; reuse is fine since it is the index here too -- if the compiler objects to reuse, rename to `J`.)

- [ ] **Step 5: Wire the SECOND id.** `CheckFormatCall` now emits two ids. Change the `DoLint`/`DoLintAll`/project-lint dispatch for `CheckFormatCall` to the multi-id `for F in ... do` form and add `format-specifier-type-mismatch` to the allow-list guard + help string. **Steps 6-8:** rebuild, harness (both `format-*` filters), commit (`feat(lint): format-specifier-type-mismatch -- literal argument type vs Format specifier`).

---

## Group B -- "T3" rules (Pascal flow/scope built-ins)

### Task B1: `try-except-swallowed` (warning) -- silent exception swallow

**Detects:** an `except` block whose body contains NONE of: a `raise`, a call to `Application.HandleException`/`Application.ShowException`/`ShowException`, or any identifier whose text contains `Log`/`Logger`/`Report` (logging convention). Method `CheckSwallowedExcept`. Walk each `try`, find the `except` clause (mirror the `kFinally` -> `statements` idiom from `CheckRaiseInFinally`, but for `kExcept`), scan that body.

- [ ] **Step 1: Fixture** `tests/lint/try-except-swallowed.pas`
```pascal
unit TryExceptSwallowed;

interface

implementation

uses System.SysUtils;

procedure Bad;
begin
  try
    Writeln('x');
  except
    // swallowed -- nothing here
  end;
end;

procedure GoodReraise;
begin
  try
    Writeln('x');
  except
    raise;
  end;
end;

procedure GoodLog;
begin
  try
    Writeln('x');
  except
    on E: Exception do
      LogError(E.Message);
  end;
end;

end.
```

- [ ] **Step 2: Verify nodes (CRITICAL)** -- parse; determine the `except` clause shape: the keyword token kind (`kExcept`?) and the node that holds the handler body (`statements`? an `exceptionHandlers`/`on` block?). Mirror `CheckRaiseInFinally`'s `Visit` which iterates `N.Child(I)` of a `try`, flips a flag on the keyword token, then scans the following `statements`. Record the actual `except`-body node kind. Note the `except` line of the Bad proc (the finding pins to the `try` or the `except` keyword -- pick the `except` keyword's line).

- [ ] **Step 3: Expected** `tests/lint/try-except-swallowed.expected`
```
# only the empty/no-handler except (around line 13) fires; reraise + log do not
try-except-swallowed 13
!try-except-swallowed 23
!try-except-swallowed 34
```
(Adjust 13 to the actual `except` keyword line.)

- [ ] **Step 4: Method `CheckSwallowedExcept`** (body inside template T)
```pascal
  function BodyHandlesException(const N: TTSNode): Boolean;
  var
    I: Integer;
    T: string;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'raise' then Exit(True);
    if (N.NodeType = 'identifier') or (N.NodeType = 'exprCall') or (N.NodeType = 'exprDot') then
    begin
      T:= NodeStr(N);
      if (Pos('handleexception', LowerCase(T)) > 0) or (Pos('showexception', LowerCase(T)) > 0)
         or (Pos('log', LowerCase(T)) > 0) or (Pos('logger', LowerCase(T)) > 0) or (Pos('report', LowerCase(T)) > 0) then
        Exit(True);
    end;
    for I:= 0 to N.ChildCount - 1 do
      if BodyHandlesException(N.Child(I)) then Exit(True);
  end;

  procedure Visit(const N: TTSNode);
  var
    I: Integer;
    InExcept: Boolean;
    C, Kw: TTSNode;
    P: TTSPoint; F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 100) then Exit;
    if N.NodeType = 'try' then
    begin
      InExcept:= False;
      Kw:= Default(TTSNode);
      for I:= 0 to N.ChildCount - 1 do
      begin
        C:= N.Child(I);
        if C.NodeType = 'kExcept' then begin InExcept:= True; Kw:= C; end
        else if InExcept and (C.NodeType = 'statements') then
        begin
          if not BodyHandlesException(C) then
          begin
            P:= Kw.StartPoint;
            F:= Default(TLintFinding);
            F.RuleId  := 'try-except-swallowed';
            F.Severity:= 'warning';
            F.Message := 'Exception silently swallowed -- add raise, logging, or Application.HandleException.';
            F.FilePath:= AFile;
            F.StartLine:= Integer(P.Row) + 1;
            F.StartCol := Integer(P.Column) + 1;
            F.EndLine:= F.StartLine;
            F.EndCol := F.StartCol + 6;
            Findings.Add(F);
          end;
        end;
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end;
```
Verify whether the handler body sits in a `statements` node directly under `try` after `kExcept`, or whether `on E: ... do` introduces an `exceptionHandlers`/`on` wrapper -- if so, recurse `BodyHandlesException` over the whole post-`kExcept` region instead of a single `statements` child. The `BodyHandlesException` recursion already handles nesting, so capturing the broadest node after `kExcept` is safest.

- [ ] **Steps 5-8:** wire (`try-except-swallowed`/`CheckSwallowedExcept`), rebuild, harness, commit (`feat(lint): try-except-swallowed -- silent exception swallow`).

---

### Task B2: `dataset-open-without-close` (warning) -- dataset opened, not closed in finally

**Detects:** `X.Open` or `X.Active := True` in a routine with no matching `X.Close` / `X.Active := False` in a `finally` block. Method `CheckDatasetOpen`. Mirror `CheckUnprotectedFree` exactly: per-`defProc`, `WalkBody` carries an `AInFinally` flag; record Open sites; record finally-block Close sites keyed by var; report Opens with no finally-Close.

- [ ] **Step 1: Fixture** `tests/lint/dataset-open-without-close.pas`
```pascal
unit DatasetOpenWithoutClose;

interface

implementation

procedure Bad;
var
  Q: TFDQuery;
begin
  Q.Open;
  Q.First;
end;

procedure Good;
var
  Q: TFDQuery;
begin
  Q.Open;
  try
    Q.First;
  finally
    Q.Close;
  end;
end;

end.
```
(`TFDQuery` need not be declared/usable -- the file only needs to parse, like other fixtures.)

- [ ] **Step 2: Verify nodes** -- parse; confirm `Q.Open` is `exprCall` with `entity: (exprDot lhs:(identifier)=Q rhs:(identifier)=Open)` (or `exprDot` directly when no parens). Confirm `Q.Active := True` is `assignment` with `lhs:(exprDot ... rhs=Active)` and `rhs:(kTrue)`. Note the Open line in Bad (~11).

- [ ] **Step 3: Expected** `tests/lint/dataset-open-without-close.expected`
```
dataset-open-without-close 11
!dataset-open-without-close 20
```

- [ ] **Step 4: Method `CheckDatasetOpen`** -- copy `CheckUnprotectedFree`'s structure verbatim (the `VisitProcs`/`WalkBody`/per-routine dictionary + `AInFinally` flag), replacing the two predicates:
  - `IsOpen(N, out AVar)`: true when `N` is `exprCall`/`exprDot` of form `X.Open` (rhs identifier text `Open`), OR `assignment` whose `lhs` is `X.Active` (exprDot rhs `Active`) and `rhs` is `kTrue`. Return lowercased `X`.
  - `IsClose(N, out AVar)`: same for `X.Close` or `X.Active := False` (`rhs` `kFalse`).
  - In `WalkBody`: record `IsOpen` vars into a per-routine `Opened` dict (store the node's StartPoint for the finding); when `AInFinally` and `IsClose`, mark that var closed; after walking the routine, emit `dataset-open-without-close` (warning) for every opened-but-not-finally-closed var. Message: `Format('Dataset %s is opened without a matching Close in a finally block -- it leaks a server cursor on an exception path.', [V])`.

  Because the finding must be emitted AFTER the whole routine is walked (you only know about a later finally-Close once you've seen it), accumulate `Opened: TDictionary<string, TTSPoint>` and `ClosedInFinally: TDictionary<string, Boolean>` per routine in `VisitProcs`, then loop `Opened` and emit for keys absent from `ClosedInFinally`. (This differs slightly from `CheckUnprotectedFree`, which emits inline; dataset needs the post-pass.)

- [ ] **Steps 5-8:** wire (`dataset-open-without-close`/`CheckDatasetOpen`), rebuild, harness, commit (`feat(lint): dataset-open-without-close -- dataset opened without finally Close`).

---

### Task B3: `criticalsection-not-released` (error) -- lock acquired, not released in finally

**Detects:** `X.Enter` / `X.Acquire` without a matching `X.Leave` / `X.Release` in a `finally` block in the same routine. Method `CheckCriticalSection`. Same flow pattern as B2.

- [ ] **Step 1: Fixture** `tests/lint/criticalsection-not-released.pas`
```pascal
unit CriticalSectionNotReleased;

interface

implementation

procedure Bad;
var
  Lock: TCriticalSection;
begin
  Lock.Enter;
  DoWork;
end;

procedure Good;
var
  Lock: TCriticalSection;
begin
  Lock.Enter;
  try
    DoWork;
  finally
    Lock.Leave;
  end;
end;

end.
```

- [ ] **Step 2: Verify nodes** -- as B2 (`X.Enter`/`X.Acquire` and `X.Leave`/`X.Release` are `exprCall`/`exprDot`). Note the Enter line in Bad (~11).

- [ ] **Step 3: Expected** `tests/lint/criticalsection-not-released.expected`
```
criticalsection-not-released 11
!criticalsection-not-released 20
```

- [ ] **Step 4: Method `CheckCriticalSection`** -- clone B2's structure; predicates: `IsAcquire` = `X.Enter` or `X.Acquire`; `IsRelease` = `X.Leave` or `X.Release`. Severity `error`. Message: `Format('Critical section %s is acquired without a matching Leave/Release in a finally block -- a lock leaked on an exception path deadlocks.', [V])`.

- [ ] **Steps 5-8:** wire (`criticalsection-not-released`/`CheckCriticalSection`), rebuild, harness, commit (`feat(lint): criticalsection-not-released -- lock acquired without finally Leave`).

---

### Task B4: `too-many-exit-points` (info) -- routine with > 5 Exit statements

**Detects:** a routine body containing more than `MAX_EXITS` (const = 5) `Exit` statements. Method `CheckTooManyExitPoints`. Mirror `CheckRoutineMetrics`: per `defProc`, count `Exit` identifier/exprCall nodes in the body, emit at the routine header if over threshold.

- [ ] **Step 1: Fixture** `tests/lint/too-many-exit-points.pas`
```pascal
unit TooManyExitPoints;

interface

implementation

procedure Bad(N: Integer);
begin
  if N = 1 then Exit;
  if N = 2 then Exit;
  if N = 3 then Exit;
  if N = 4 then Exit;
  if N = 5 then Exit;
  if N = 6 then Exit;
end;

procedure Good(N: Integer);
begin
  if N = 1 then Exit;
  Writeln(N);
end;

end.
```

- [ ] **Step 2: Verify nodes** -- confirm `Exit` is `identifier` or `exprCall` with entity text `Exit`. Note the `Bad` header line (~7) -- the finding pins to the routine header.

- [ ] **Step 3: Expected** `tests/lint/too-many-exit-points.expected`
```
# Bad has 6 Exits (> 5) -> fires at the header (line 7); Good has 1 -> clean
too-many-exit-points 7
!too-many-exit-points 18
```

- [ ] **Step 4: Method `CheckTooManyExitPoints`** (body inside template T; `const MAX_EXITS = 5;` at unit or method scope)
```pascal
  function CountExits(const N: TTSNode): Integer;
  var
    I: Integer;
    T: string;
  begin
    Result:= 0;
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then Exit; // nested routine counted separately
    if (N.NodeType = 'identifier') or (N.NodeType = 'exprCall') then
    begin
      if N.NodeType = 'exprCall' then T:= NodeStr(N.ChildByField('entity')) else T:= NodeStr(N);
      if SameText(T, 'Exit') then Inc(Result);
    end;
    for I:= 0 to N.ChildCount - 1 do Result:= Result + CountExits(N.Child(I));
  end;

  procedure Visit(const N: TTSNode);
  var
    I, NExit: Integer;
    Hdr, Body: TTSNode;
    P: TTSPoint; F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      NExit:= CountExits(Body);
      if NExit > 5 then
      begin
        Hdr:= N.ChildByField('header');
        if Hdr.IsNull then Hdr:= N;
        P:= Hdr.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'too-many-exit-points';
        F.Severity:= 'info';
        F.Message := Format('Routine has %d Exit statements (max 5) -- consolidate exits or use guard clauses.', [NExit]);
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + 1;
        Findings.Add(F);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;
```
Note `CountExits` walks ALL children but stops at nested `defProc` so an inner routine's Exits aren't double-counted; the outer `Visit` recurses into nested routines separately.

- [ ] **Steps 5-8:** wire (`too-many-exit-points`/`CheckTooManyExitPoints`), rebuild, harness, commit (`feat(lint): too-many-exit-points -- routine with more than 5 Exit statements`).

---

### Task B5: `cyclomatic-complexity` (info) -- decision points > 15

**Detects:** per routine, decision-point count > `MAX_CC` (const = 15). Count: `if`, `ifElse`, `while`, `for`, `repeat`, each `case` branch label, `kAnd`, `kOr`; base = 1. Method `CheckCyclomaticComplexity`.

- [ ] **Step 1: Verify `kAnd`/`kOr` + case-label node kinds (CRITICAL, BEFORE fixture)** -- the spec explicitly flags this. Parse a sample with `and`/`or`/`case`:
```pascal
procedure P(A, B: Boolean; N: Integer);
begin
  if A and B then ;
  if A or B then ;
  case N of
    1: ;
    2: ;
  end;
end;
```
Run `tree-sitter.exe parse` and record: the node kind of the `and` operator (likely `kAnd`), `or` (likely `kOr`), and how a `case` branch/label is represented (e.g. `caseSelector`/`caseLabel` node, one per `1:`/`2:`). Use the confirmed kinds in Step 4.

- [ ] **Step 2: Fixture** `tests/lint/cyclomatic-complexity.pas` -- one routine wired to exceed 15 (e.g. a chain of `if ... and ... or ...` plus a multi-branch `case`) and one small clean routine. Build it so the complex routine's count is comfortably > 15; keep the simple one < 5.
```pascal
unit CyclomaticComplexity;

interface

implementation

procedure Complex(A, B, C, D: Boolean; N: Integer);
begin
  if A and B or C and D then ;
  if A and B or C and D then ;
  if A and B or C and D then ;
  while A and B do ;
  for N := 1 to 10 do ;
  case N of
    1: ;
    2: ;
    3: ;
    4: ;
  end;
end;

procedure Simple(A: Boolean);
begin
  if A then ;
end;

end.
```

- [ ] **Step 3: Expected** `tests/lint/cyclomatic-complexity.expected` -- compute the count for `Complex` from the confirmed node kinds (base 1 + ifs + and/or + while + for + case labels); confirm > 15; pin to the `Complex` header line.
```
# Complex exceeds 15 -> header (line 7); Simple is well under -> clean
cyclomatic-complexity 7
!cyclomatic-complexity 22
```

- [ ] **Step 4: Method `CheckCyclomaticComplexity`** (body inside template T; `MAX_CC = 15`)
```pascal
  function CountDecisions(const N: TTSNode): Integer;
  var
    I: Integer;
    K: string;
  begin
    Result:= 0;
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then Exit; // nested routine separate
    K:= N.NodeType;
    if (K = 'if') or (K = 'ifElse') or (K = 'while') or (K = 'for') or (K = 'repeat')
       or (K = 'kAnd') or (K = 'kOr') or (K = '<CASE_LABEL_KIND>') then Inc(Result);
    for I:= 0 to N.ChildCount - 1 do Result:= Result + CountDecisions(N.Child(I));
  end;

  procedure Visit(const N: TTSNode);
  var
    I, CC: Integer;
    Hdr, Body: TTSNode;
    P: TTSPoint; F: TLintFinding;
  begin
    if N.IsNull or (Findings.Count >= 200) then Exit;
    if N.NodeType = 'defProc' then
    begin
      Body:= N.ChildByField('body');
      CC:= 1 + CountDecisions(Body);
      if CC > 15 then
      begin
        Hdr:= N.ChildByField('header'); if Hdr.IsNull then Hdr:= N;
        P:= Hdr.StartPoint;
        F:= Default(TLintFinding);
        F.RuleId  := 'cyclomatic-complexity';
        F.Severity:= 'info';
        F.Message := Format('Routine has cyclomatic complexity %d (max 15) -- consider extracting sub-routines.', [CC]);
        F.FilePath:= AFile;
        F.StartLine:= Integer(P.Row) + 1;
        F.StartCol := Integer(P.Column) + 1;
        F.EndLine:= F.StartLine;
        F.EndCol := F.StartCol + 1;
        Findings.Add(F);
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;
```
Replace `<CASE_LABEL_KIND>` with the verified node kind; if case labels are awkward to identify, count `case` once + each `;`-less selector, or drop case from the count and adjust the fixture so the threshold is still exceeded without relying on case labels.

- [ ] **Steps 5-8:** wire (`cyclomatic-complexity`/`CheckCyclomaticComplexity`), rebuild, harness, commit (`feat(lint): cyclomatic-complexity -- decision-point count over 15`).

---

### Task B6: `virtual-method-in-constructor` (warning) -- virtual call from a constructor (needs `--db`)

**Detects:** a call to a `virtual`/`dynamic` method inside a constructor body -- dispatches to a not-yet-initialised descendant override. Method `CheckVirtualInConstructor`. This is the ONE rule needing the index: it queries `ISymbolStore` for the called method's modifiers. Signature takes a store: `class function CheckVirtualInConstructor(const AStore: ISymbolStore; const AFile: string): TArray<TLintFinding>;` (like `CheckUndeclared`). Skips gracefully if `AStore = nil`.

- [ ] **Step 1: Verify the constructor node marker** -- parse a unit with a constructor; confirm how a constructor routine is distinguished from a normal `defProc` (the header's first child token `kConstructor`, or a `constructor` node kind). Record it.

- [ ] **Step 2: Fixture set** -- because this needs a DB, follow `tests/lint-project/` (see its README), not `tests/lint/`. Create a minimal indexed project: a base class with a `virtual` method `Init`, a descendant whose constructor calls `Init`. Index it to a temp `.sqlite`, then `drag-lint lint <descendant.pas> --db <db> --rule virtual-method-in-constructor`. If the `tests/lint-project/` harness is not yet able to assert findings, add the assertion following its existing pattern; if that is too heavy for this pass, implement the rule + do a manual smoke test and note in the commit that an automated DB-fixture test is deferred.

- [ ] **Step 3: Method `CheckVirtualInConstructor`** -- template T plus a store param:
  - Walk to each `defProc` that is a constructor (per Step 1).
  - Within its body, for each `exprCall` whose entity is an `identifier` (unqualified call) or `Self.X`, take the method name and query `AStore` for a method symbol of that name whose `modifiers` contain `virtual` or `dynamic`. (Use the same `ISymbolStore` query idiom as `CheckUndeclared` -- inspect that method for the exact API: how to look up a symbol by name and read its `modifiers`/`kind` columns.)
  - Emit `virtual-method-in-constructor` (warning) at the call site. Message: `'Virtual/dynamic method called in a constructor -- it dispatches to a descendant override whose fields are not yet initialised.'`
  - If `AStore = nil` then `Exit(nil)` (no DB -> skip).

- [ ] **Step 4: Wire** -- this method needs the store, so it is wired where the store is available (the DB-backed lint path, near `CheckUndeclared`'s call site, NOT the no-DB `.pas` block). Add the allow-list id + help string. In `DoLintAll`/project-lint, pass the resolved store if present, else skip. **Step 5: Rebuild, smoke-test with the DB fixture, commit** (`feat(lint): virtual-method-in-constructor -- virtual/dynamic call from a constructor (DB-backed)`).

---

## Group D -- v0.63.0-alpha release (STAGED; public publish gated on the IDE test)

### Task D1: Version bump, docs, build, stage zips -- HOLD the tag + GitHub release

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` line 6 (`VERSION`)
- Modify: `CHANGELOG.md` (UTF-8 -- never ASCII-rewrite)
- Modify: `rules/README.md` (UTF-8)

- [ ] **Step 1: Bump VERSION** in `src/cli/DRagLint.CLI.pas` line 6: `'0.62.0-alpha'` -> `'0.63.0-alpha'`.

- [ ] **Step 2: Prepend CHANGELOG entry** (after the header, before the `## v0.62.0-alpha` block). List the IDE menu command + all 11 rules grouped (Security: `unsafe-shellexecute`, `path-traversal`; Bugs/flow: `loop-executes-at-most-once`, `format-argument-count`, `format-specifier-type-mismatch`, `try-except-swallowed`, `virtual-method-in-constructor`; Resource/lock: `dataset-open-without-close`, `criticalsection-not-released`; Metrics: `too-many-exit-points`, `cyclomatic-complexity`) + "IDE: Run Lint All (Full Report) menu command". Use `--` (em-dash) not `?`; do NOT normalize this file with ASCIIEncoding.

- [ ] **Step 3: Add a `## Shipped rules (v0.63 -- Phase 2, built-ins)` table** to `rules/README.md` (mirror the v0.62 table format). Note these are built-in (no `.scm`/`.json`). UTF-8.

- [ ] **Step 4: Full build + pack** -- `pwsh -File build\pack-lint-release.ps1 -Version 0.63.0-alpha` (builds Release Win64+Win32, redeploys the canonical Win64 exe, writes `C:\TEMP\rel-0.63.0-alpha\drag-lint-v0.63.0-alpha-win64.zip` + `-win32.zip`). Then separately rebuild the **BPL** (Task C1 Step 4 recipe) so `third_party\dll-win32\dclDragLintWizard.bpl` is current. Confirm `drag-lint.exe --version` -> `0.63.0-alpha`.

- [ ] **Step 5: Final full harness** -- `pwsh -File tests\lint\run_lint_tests.ps1`; all fixtures green (64 from v0.62 + the new built-in fixtures).

- [ ] **Step 6: Commit + push (NO tag, NO release yet)**
```bash
git add src/cli/DRagLint.CLI.pas CHANGELOG.md rules/README.md
git commit -m "chore(release): bump version to 0.63.0-alpha + changelog + rules README (staged)"
git push origin main
```

- [ ] **Step 7: RELEASE GATE -- STOP and report.** Do NOT run `git tag` / `gh release create`. Report to the user: v0.63 code is built, committed, and pushed to `main`; zips staged at `C:\TEMP\rel-0.63.0-alpha\`; awaiting their hands-on RAD Studio test of the **Run Lint All** menu (Task C1 manual verification). Once the user confirms the menu works, finish the release:
```bash
git tag v0.63.0-alpha
git push origin main --tags   # note: a stale local v0.60 tag may be rejected; that is harmless
gh release create v0.63.0-alpha --repo Alexl-git/Delphi-RAG-Lint --latest \
  --title "v0.63.0-alpha -- 11 built-in lint rules + IDE Run Lint All menu" \
  --notes "<grouped rule list + IDE menu>" \
  "C:/TEMP/rel-0.63.0-alpha/drag-lint-v0.63.0-alpha-win64.zip" \
  "C:/TEMP/rel-0.63.0-alpha/drag-lint-v0.63.0-alpha-win32.zip"
```

---

## Self-Review

**Spec coverage (every Phase 2 / section item maps to a task):**

| Spec item (design 5.1/5.2/8/10) | Task |
|---|---|
| IDE "Run Lint All" menu command (section 8) | C1 |
| `unsanitized-shellexecute` (5.1) -> id `unsafe-shellexecute` | A1 |
| `path-traversal` (5.1) | A2 |
| `loop-executes-at-most-once` (5.1) | A3 |
| `format-argument-count` (5.1) | A4 |
| `format-specifier-type-mismatch` (5.1) | A5 |
| `try-except-swallowed` (5.2) | B1 |
| `dataset-open-without-close` (5.2) | B2 |
| `criticalsection-not-released` (5.2) | B3 |
| `too-many-exit-points` (5.2) | B4 |
| `cyclomatic-complexity` (5.2) | B5 |
| `virtual-method-in-constructor` (5.2) | B6 |
| v0.63 release + BPL + staged/gated publish (section 10) | D1 |

**Naming note:** the design calls the first rule `unsanitized-shellexecute`; this plan ships it as **`unsafe-shellexecute`** (shorter, consistent with `unsafe-string-api`). Single source of truth = this plan; use `unsafe-shellexecute` in code, allow-list, fixture, and docs.

**Placeholder scan:** the only deliberate `<...>` tokens are node-kind placeholders that MUST be resolved by a tree-sitter verify step within the same task: `<SET_KIND>` (A4 array-constructor kind), `<CASE_LABEL_KIND>` (B5). Each has an explicit "verify nodes" step. No other TBDs.

**Type/contract consistency:** every rule is a `class function CheckXxx(const AFile: string): TArray<TLintFinding>` except B6 (`CheckVirtualInConstructor(const AStore: ISymbolStore; const AFile: string)`), which is wired on the DB-backed path. All findings use the `TLintFinding` field set from Global Constraints. All built-in rules add the same 5 wiring edits; B6's dispatch differs (store-bearing path). A4+A5 share one method `CheckFormatCall` emitting two ids via the multi-id `for F in ...` dispatch.

**Known risk areas (carry extra verification budget):** A3 (loop body shape + Exit/Break node kind), B1 (`except`/`kExcept` body shape), B5 (`kAnd`/`kOr` + case-label kinds), B6 (constructor marker + `ISymbolStore` modifiers query + DB fixture). Each names its verification step explicitly.

**Rebuild discipline:** every Group A/B task rebuilds Win64 before its harness run (built-ins are compiled in). Group C rebuilds the Win32 BPL. Group D rebuilds both via the pack script + the BPL recipe.
