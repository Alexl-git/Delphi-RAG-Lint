# Hover Tooltip Help-Insight Restyle -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the drag-lint IDE hover popup to read like Delphi Help Insight -- one-line clickable signature header, colored + selectable TRichEdit body in the configured IDE font, aligned params, mined `Result :=` returns, a 15/10 caller cap, and a contrast guard so no color is ever invisible on any theme.

**Architecture:** Three new pure units carry the logic (contrast math, returns-mining, a structured hover model) and are testable in isolation via the CLI. The CLI `hover --json` verb is extended to emit the model. The IDE plugin form (`DragLint.Plugin.HoverForm`) is rebuilt around a `TRichEdit` body (colored, selectable) + the existing `TListView` callers grid, consuming the model and the contrast unit. No SQLite schema change -- returns-mining reuses the `impl_start_line`/`impl_end_line` body span the index already stores.

**Tech Stack:** Delphi 13 (RAD Studio 37), Object Pascal, stock VCL (`Vcl.ComCtrls` TRichEdit/TListView, `Vcl.Graphics` TColor), ToolsAPI (IDE theming + editor-font option), SQLite index (read-only), PowerShell test harness (`tests/autotest/run_*.ps1`).

## Global Constraints

- **Encoding:** all `.pas` edits strict 7-bit ASCII, no BOM, CRLF line endings. Never introduce Unicode or LF.
- **DocInsight:** every public/published type + function gets a `///` DocInsight spec-comment (`<summary>`/`<param>`/`<returns>`/`<remarks>`). The doc-comment and its test must agree.
- **No new dependencies:** open-source project. Stock RTL/VCL + ToolsAPI only. No DevExpress, no third-party HTML/markdown control.
- **Build:** CLI + plugin BPL build via the `delphi-build` skill recipe (rsvars + msbuild via `Start-Process -Wait`, read log for `BUILD_EXITCODE=0` / no `[dcc] Error`). Never the MCP build tool; never `cmd.exe /c build.bat` from Bash.
- **Reindex after symbol-changing builds:** reindex the self-index incrementally so later queries reflect new code.
- **Source line reads:** always `TFile.ReadAllLines(Path, TEncoding.ANSI)` (source files are strict ANSI), matching `DRagLint.Doc.Facts`.
- **Platform:** plugin is Win32 BPL (IDE is 32-bit); CLI canonical exe is Win64 (`third_party/dll-win64/drag-lint.exe`).

---

## File Structure

**New files:**
- `src/core/DRagLint.Hover.Contrast.pas` -- pure WCAG contrast math (`ContrastRatio`, `EnsureReadable`). No VCL forms.
- `src/cli/DRagLint.Hover.Returns.pas` -- pure returns-miner (`MineReturnExpressions`). No I/O.
- `tests/autotest/run_hover_contrast.ps1` -- drives contrast self-test verb.
- `tests/autotest/run_hover_returns.ps1` -- drives `hover --json` returns assertions.

**Modified files:**
- `src/cli/DRagLint.Hover.Renderer.pas` -- add `THoverModel`/`TParamPart`/`TReturnFact`, `BuildHoverModel`, `ParseSignatureParams`; refactor markdown/plain to build from parts (additive; existing signatures preserved).
- `src/cli/DRagLint.CLI.pas` -- `DoHover` reads body span + mines returns; `--json` emits the model; add hidden `contrast-selftest` verb (test hook).
- `src/delphi-plugin/DragLint.Plugin.HoverForm.pas` -- swap body `TMemo` -> `TRichEdit`; colored runs; IDE-font; clickable header; 15/10 caller cap; contrast guard.
- `src/delphi-plugin/DragLint.Plugin.Editor.pas` -- fetch `hover --json` model; pass structured parts to the form.
- `src/delphi-plugin/DragLint.Plugin.Fonts.pas` (new small unit) -- `GetIdeEditorFont(out AName: string; out ASize: Integer): Boolean` via ToolsAPI.

---

## Task 1: Contrast unit (pure WCAG math)

**Files:**
- Create: `src/core/DRagLint.Hover.Contrast.pas`
- Create: `tests/autotest/run_hover_contrast.ps1`
- Modify: `src/cli/DRagLint.CLI.pas` (add hidden `contrast-selftest` verb that prints ratios so the .ps1 can assert)

**Interfaces:**
- Produces: `function ContrastRatio(AForeground, ABackground: TColor): Double;` and `function EnsureReadable(AForeground, ABackground: TColor; AMinRatio: Double = 4.5): TColor;` in unit `DRagLint.Hover.Contrast`.

- [ ] **Step 1: Write the unit with DocInsight comments and implementation**

Create `src/core/DRagLint.Hover.Contrast.pas` (ASCII/CRLF):

```pascal
unit DRagLint.Hover.Contrast;

/// <summary>WCAG 2.x relative-luminance contrast math for the hover popup, so a
/// syntax color is never rendered unreadable against the active theme
/// background. Pure arithmetic -- no VCL forms, no theming state.</summary>

interface

uses
  Vcl.Graphics; // TColor

/// <summary>WCAG relative-luminance contrast ratio between two colors.</summary>
/// <param name="AForeground">Text color (system colors are resolved via ColorToRGB).</param>
/// <param name="ABackground">Background color behind the text.</param>
/// <returns>Ratio in [1.0, 21.0]: 1.0 identical, 21.0 black-on-white.</returns>
/// <remarks>Order-independent (lighter/darker sorted internally).</remarks>
function ContrastRatio(AForeground, ABackground: TColor): Double;

/// <summary>Return AForeground if it already clears AMinRatio against
/// ABackground; otherwise nudge its lightness away from the background until it
/// does (clamped at black/white).</summary>
/// <param name="AMinRatio">WCAG floor: 4.5 body text, 3.0 large/bold.</param>
/// <returns>A color guaranteed to meet AMinRatio against ABackground.</returns>
/// <remarks>Hue is preserved where possible so "keyword blue" stays blue.</remarks>
function EnsureReadable(AForeground, ABackground: TColor; AMinRatio: Double = 4.5): TColor;

implementation

uses
  System.Math, Winapi.Windows; // GetRValue etc.

function Linearize(AChannel: Byte): Double;
var
  C: Double;
begin
  C:= AChannel / 255.0;
  if C <= 0.03928 then Result:= C / 12.92
  else Result:= Power((C + 0.055) / 1.055, 2.4);
end;

function RelLuminance(AColor: TColor): Double;
var
  RGB: TColorRef;
begin
  RGB:= ColorToRGB(AColor);
  Result:= 0.2126 * Linearize(GetRValue(RGB))
         + 0.7152 * Linearize(GetGValue(RGB))
         + 0.0722 * Linearize(GetBValue(RGB));
end;

function ContrastRatio(AForeground, ABackground: TColor): Double;
var
  L1, L2, Hi, Lo: Double;
begin
  L1:= RelLuminance(AForeground);
  L2:= RelLuminance(ABackground);
  if L1 >= L2 then begin Hi:= L1; Lo:= L2; end else begin Hi:= L2; Lo:= L1; end;
  Result:= (Hi + 0.05) / (Lo + 0.05);
end;

function EnsureReadable(AForeground, ABackground: TColor; AMinRatio: Double): TColor;
var
  RGB   : TColorRef;
  R,G,B : Double   ;
  BgLum : Double   ;
  Step  : Double   ;
  Target: TColor   ;
  I     : Integer  ;
begin
  Result:= AForeground;
  if ContrastRatio(AForeground, ABackground) >= AMinRatio then Exit;

  RGB:= ColorToRGB(AForeground);
  R:= GetRValue(RGB); G:= GetGValue(RGB); B:= GetBValue(RGB);
  BgLum:= RelLuminance(ABackground);
  { push toward white on a dark bg, toward black on a light bg }
  if BgLum < 0.5 then Step:= 12 else Step:= -12;

  for I:= 1 to 24 do
  begin
    R:= EnsureRange(R + Step, 0, 255);
    G:= EnsureRange(G + Step, 0, 255);
    B:= EnsureRange(B + Step, 0, 255);
    Target:= RGB2TColor(Round(R), Round(G), Round(B));
    if ContrastRatio(Target, ABackground) >= AMinRatio then Exit(Target);
  end;
  { fell through -- clamp to the maximally-contrasting extreme }
  if BgLum < 0.5 then Result:= clWhite else Result:= clBlack;
end;

end.
```

Note: `RGB2TColor` is in `Vcl.Graphics`; add to the uses if the compiler flags it. If absent, use `TColor(RGB(...))`.

- [ ] **Step 2: Add a hidden `contrast-selftest` verb to the CLI**

In `src/cli/DRagLint.CLI.pas`, add `DRagLint.Hover.Contrast` to the implementation `uses`, and a small function called from the verb dispatch (find where verbs like `hover` are dispatched and add a case for `'contrast-selftest'`). It prints deterministic lines the .ps1 asserts:

```pascal
function DoContrastSelfTest: Integer;
begin
  // Known-answer lines: NAME=<ratio to 2dp> and READABLE=<hex of EnsureReadable>.
  Writeln(Format('BLACK_ON_WHITE=%.2f', [ContrastRatio(clBlack, clWhite)]));      // 21.00
  Writeln(Format('SAME=%.2f',           [ContrastRatio(clRed, clRed)]));          // 1.00
  // #0B57D0 keyword-blue on a dark (#1E1E1E) bg fails 4.5; EnsureReadable fixes it.
  Writeln(Format('DARKFAIL=%.2f',       [ContrastRatio($00D0570B, $001E1E1E)]));  // < 4.5
  Writeln(Format('FIXED=%.2f',
    [ContrastRatio(EnsureReadable($00D0570B, $001E1E1E, 4.5), $001E1E1E)]));       // >= 4.5
  Result:= 0;
end;
```

(TColor hex is `$00BBGGRR`: `#0B57D0` -> `$00D0570B`; `#1E1E1E` -> `$001E1E1E`.)

- [ ] **Step 3: Write the failing test**

Create `tests/autotest/run_hover_contrast.ps1` (model the structure on `run_typeat_scope.ps1`):

```powershell
[CmdletBinding()]
param([string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check([string]$Name,[bool]$Ok,[string]$Detail=''){
  $s = if($Ok){'PASS'}else{'FAIL'}; $c = if($Ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$Name,$Detail) -ForegroundColor $c
  if(-not $Ok){$script:Failed=$true}
}
if(-not(Test-Path $Exe)){Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2}

$out = (& $Exe contrast-selftest 2>&1) -join "`n"
Check 'black-on-white = 21.00' ($out -match 'BLACK_ON_WHITE=21\.00') $out
Check 'same color = 1.00'      ($out -match 'SAME=1\.00') $out
$dark = if($out -match 'DARKFAIL=([\d.]+)'){[double]$Matches[1]}else{99}
Check 'keyword-blue on dark FAILS 4.5' ($dark -lt 4.5) "ratio=$dark"
$fixed = if($out -match 'FIXED=([\d.]+)'){[double]$Matches[1]}else{0}
Check 'EnsureReadable clears 4.5' ($fixed -ge 4.5) "ratio=$fixed"

Write-Host ''
if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red; exit 1}else{Write-Host 'PASS' -ForegroundColor Green; exit 0}
```

- [ ] **Step 4: Build the CLI, run the test, verify PASS**

Build the CLI via the `delphi-build` skill (Win64 exe). Then:

Run: `pwsh -File tests/autotest/run_hover_contrast.ps1`
Expected: all four PASS, final `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/core/DRagLint.Hover.Contrast.pas src/cli/DRagLint.CLI.pas tests/autotest/run_hover_contrast.ps1
git commit -m "feat(hover): WCAG contrast unit + contrast-selftest verb"
```

---

## Task 2: Returns-mining unit (pure text -> distinct RHS)

**Files:**
- Create: `src/cli/DRagLint.Hover.Returns.pas`
- Test: behavior is verified in Task 4 via `hover --json` against a real fixture symbol (`run_hover_returns.ps1`). This task ships + compiles the pure function only; there is no throwaway test scaffolding.

**Interfaces:**
- Consumes: nothing (pure).
- Produces: `function MineReturnExpressions(const ABodyLines: TArray<string>): TArray<string>;` in unit `DRagLint.Hover.Returns` -- distinct RHS of `Result :=` and value-form `Exit(...)`, source order, dedup'd (case-sensitive on RHS text), no cap applied here (caller caps at 10).

- [ ] **Step 1: Write the unit with DocInsight + implementation**

Create `src/cli/DRagLint.Hover.Returns.pas` (ASCII/CRLF):

```pascal
unit DRagLint.Hover.Returns;

/// <summary>Mine a routine body for the distinct expressions it returns, so the
/// hover "Returns" section can show real Result:= / Exit(...) values without an
/// LLM. Pure text: the caller supplies the routine's own body lines.</summary>

interface

/// <summary>Distinct right-hand sides of `Result := <rhs>` and value-form
/// `Exit(<rhs>)` in ABodyLines, in first-seen source order.</summary>
/// <param name="ABodyLines">The routine's implementation body lines
///   (impl_start_line..impl_end_line), one string per source line.</param>
/// <returns>Distinct RHS strings, trimmed, dedup'd. Empty when none found.</returns>
/// <remarks>Best-effort, single-line RHS captured up to the terminating ';'.
///   Skips `//` line comments. Does not descend into nested routines (caller
///   passes only this routine's span). Not authoritative -- a display aid.</remarks>
function MineReturnExpressions(const ABodyLines: TArray<string>): TArray<string>;

implementation

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections;

function StripLineComment(const S: string): string;
var
  P: Integer;
begin
  P:= Pos('//', S);
  if P > 0 then Result:= Copy(S, 1, P - 1) else Result:= S;
end;

// Extract '<rhs>' from 'Result := <rhs> ;' (drops trailing ';'), or '' if the
// line is not a Result assignment.
function ResultRhs(const ALine: string): string;
var
  T, Low: string;
  P, SemiP: Integer;
begin
  Result:= '';
  T:= Trim(StripLineComment(ALine));
  Low:= LowerCase(T);
  if not StartsStr('result', Low) then Exit;
  // require ':=' after 'result' (tolerate spaces)
  P:= Pos(':=', T);
  if P = 0 then Exit;
  if Trim(Copy(T, 1, P - 1)).ToLower <> 'result' then Exit; // not a bare Result
  T:= Trim(Copy(T, P + 2, MaxInt));
  SemiP:= Pos(';', T);
  if SemiP > 0 then T:= Copy(T, 1, SemiP - 1);
  Result:= Trim(T);
end;

// Extract '<rhs>' from 'Exit(<rhs>)', or '' if not a value-form Exit.
function ExitRhs(const ALine: string): string;
var
  T, Low: string;
  P, Depth, i, StartI: Integer;
begin
  Result:= '';
  T:= Trim(StripLineComment(ALine));
  Low:= LowerCase(T);
  if not StartsStr('exit', Low) then Exit;
  P:= Pos('(', T);
  if P = 0 then Exit; // bare Exit; -- no value
  // capture balanced parens content
  Depth:= 0; StartI:= P + 1;
  for i:= P to Length(T) do
  begin
    if T[i] = '(' then Inc(Depth)
    else if T[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(Trim(Copy(T, StartI, i - StartI)));
    end;
  end;
end;

function MineReturnExpressions(const ABodyLines: TArray<string>): TArray<string>;
var
  Seen: TDictionary<string, Boolean>;
  Ordered: TList<string>;
  Line, Rhs: string;
begin
  Seen:= TDictionary<string, Boolean>.Create;
  Ordered:= TList<string>.Create;
  try
    for Line in ABodyLines do
    begin
      Rhs:= ResultRhs(Line);
      if Rhs = '' then Rhs:= ExitRhs(Line);
      if (Rhs <> '') and not Seen.ContainsKey(Rhs) then
      begin
        Seen.Add(Rhs, True);
        Ordered.Add(Rhs);
      end;
    end;
    Result:= Ordered.ToArray;
  finally
    Ordered.Free;
    Seen.Free;
  end;
end;

end.
```

- [ ] **Step 2: Build the CLI to verify it compiles**

Build the CLI via the `delphi-build` skill (add `DRagLint.Hover.Returns` to the CLI project + `DoHover`'s uses in Task 3; for now just add the unit to the `.dproj` and confirm a clean build).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 3: Commit**

```bash
git add src/cli/DRagLint.Hover.Returns.pas src/cli/drag-lint.dproj
git commit -m "feat(hover): pure Result:= / Exit() returns-miner unit"
```

---

## Task 3: Hover model + signature-param parsing in the renderer

**Files:**
- Modify: `src/cli/DRagLint.Hover.Renderer.pas`

**Interfaces:**
- Consumes: `TSymbol`, `TParsedDoc` (from `DRagLint.Core.Model`); `MineReturnExpressions` (Task 2).
- Produces (in `DRagLint.Hover.Renderer`):
  - `TParamPart = record Modifier, Name, TypeText: string; end;`
  - `TReturnFact = record Expr: string; end;`
  - `THoverModel = record QualifiedName, Kind, Signature, UnitFile: string; DefLine: Integer; Params: TArray<TParamPart>; ReturnType: string; Returns: TArray<TReturnFact>; ReturnsMore: Integer; Doc: TParsedDoc; end;`
  - `function ParseSignatureParams(const ASignature: string): TArray<TParamPart>;`
  - `function BuildHoverModel(const ASym: TSymbol; const ADoc: TParsedDoc; const AUnitFile: string; const AReturnRhs: TArray<string>): THoverModel;`

- [ ] **Step 1: Add the types + `ParseSignatureParams` (reuses existing top-level split helpers)**

In the `interface` of `src/cli/DRagLint.Hover.Renderer.pas`, add the records above and the two function decls. In `implementation`, add `ParseSignatureParams` reusing the file's existing `SplitTopLevel` / `LastTopLevelColon`:

```pascal
function ParseSignatureParams(const ASignature: string): TArray<TParamPart>;
var
  Sig, ParamsPart: string;
  OpenParen, CloseParen, Depth, i, ColonPos: Integer;
  Seg, Names, Typ, ModWord, MW, Nm: string;
  Parts: TList<TParamPart>;
  PP: TParamPart;
begin
  Parts:= TList<TParamPart>.Create;
  try
    Sig:= Trim(ASignature);
    OpenParen:= Pos('(', Sig);
    if OpenParen > 0 then
    begin
      Depth:= 0; CloseParen:= 0;
      for i:= OpenParen to Length(Sig) do
      begin
        if Sig[i] = '(' then Inc(Depth)
        else if Sig[i] = ')' then begin Dec(Depth); if Depth = 0 then begin CloseParen:= i; Break; end; end;
      end;
      if CloseParen > 0 then
      begin
        ParamsPart:= Trim(Copy(Sig, OpenParen + 1, CloseParen - OpenParen - 1));
        for Seg in SplitTopLevel(ParamsPart, ';') do
        begin
          if Trim(Seg) = '' then Continue;
          ColonPos:= LastTopLevelColon(Seg);
          if ColonPos > 0 then
          begin Names:= Trim(Copy(Seg, 1, ColonPos - 1)); Typ:= Trim(Copy(Seg, ColonPos + 1, MaxInt)); end
          else begin Names:= Trim(Seg); Typ:= ''; end;
          ModWord:= '';
          for MW in ['const ', 'var ', 'out '] do
            if StartsText(MW, Names) then
            begin ModWord:= Trim(MW); Names:= Trim(Copy(Names, Length(MW) + 1, MaxInt)); Break; end;
          for Nm in SplitTopLevel(Names, ',') do
            if Trim(Nm) <> '' then
            begin
              PP.Modifier:= ModWord; PP.Name:= Trim(Nm); PP.TypeText:= Typ;
              Parts.Add(PP);
            end;
        end;
      end;
    end;
    Result:= Parts.ToArray;
  finally
    Parts.Free;
  end;
end;
```

- [ ] **Step 2: Add `BuildHoverModel` (return type via Doc.Facts.ParseReturnType pattern; cap returns at 10)**

Add `System.Generics.Collections` to the implementation uses if not present. Return type: reuse the return-type extraction already used elsewhere. Since `DRagLint.Doc.Facts.ParseReturnType` is `private`, inline the same one-liner here (parse the trailing `): <Type>;` from the signature):

```pascal
function ReturnTypeFromSig(const ASig: string): string;
var
  CloseParen, ColonP, SemiP: Integer;
  Tail: string;
begin
  Result:= '';
  CloseParen:= LastDelimiter(')', ASig);
  if CloseParen = 0 then Exit;
  Tail:= Copy(ASig, CloseParen + 1, MaxInt);
  ColonP:= Pos(':', Tail);
  if ColonP = 0 then Exit;
  Tail:= Trim(Copy(Tail, ColonP + 1, MaxInt));
  SemiP:= Pos(';', Tail);
  if SemiP > 0 then Tail:= Copy(Tail, 1, SemiP - 1);
  Result:= Trim(Tail);
end;

function BuildHoverModel(const ASym: TSymbol; const ADoc: TParsedDoc;
  const AUnitFile: string; const AReturnRhs: TArray<string>): THoverModel;
var
  i: Integer;
  Cap: Integer;
begin
  Result.QualifiedName:= ASym.QualifiedName;
  Result.Signature    := ASym.Signature;
  Result.UnitFile     := AUnitFile;
  Result.DefLine      := ASym.StartLine;
  Result.Params       := ParseSignatureParams(ASym.Signature);
  Result.ReturnType   := ReturnTypeFromSig(ASym.Signature);
  Result.Doc          := ADoc;
  Result.Kind         := ''; // filled by caller from ASym.Kind if desired
  Cap:= Length(AReturnRhs);
  if Cap > 10 then begin Result.ReturnsMore:= Cap - 10; Cap:= 10; end
  else Result.ReturnsMore:= 0;
  SetLength(Result.Returns, Cap);
  for i:= 0 to Cap - 1 do Result.Returns[i].Expr:= AReturnRhs[i];
end;
```

- [ ] **Step 3: Build the CLI, verify clean compile**

Build via `delphi-build` skill.
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 4: Commit**

```bash
git add src/cli/DRagLint.Hover.Renderer.pas
git commit -m "feat(hover): THoverModel + ParseSignatureParams + BuildHoverModel"
```

---

## Task 4: `hover --json` emits the model + returns-mining wired end-to-end

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (`DoHover`, `RenderHoverJson` call site)
- Modify: `src/cli/DRagLint.Hover.Renderer.pas` (`RenderHoverJson` grows fields)
- Create: `tests/autotest/run_hover_returns.ps1`

**Interfaces:**
- Consumes: `BuildHoverModel`, `MineReturnExpressions`, `TSQLiteSymbolStore.GetFilePath`.
- Produces: `hover --qname X --format json` output containing `returns` (array of strings), `returns_more` (int), and `params` (array of `{modifier,name,type}`), plus existing fields.

- [ ] **Step 1: Wire body-read + mining into `DoHover`**

In `src/cli/DRagLint.CLI.pas`, add `DRagLint.Hover.Returns`, `System.IOUtils` to uses. Replace the body of `DoHover` after `Doc:= Store.GetSymbolDoc(...)` to read the body span and mine returns:

```pascal
  // v0.95: mine Result:= / Exit() RHS from the routine body span (if any).
  var Rhs: TArray<string>;
  SetLength(Rhs, 0);
  if (Syms[0].ImplStartLine > 0) and (Syms[0].ImplEndLine >= Syms[0].ImplStartLine) then
  begin
    var Path: string:= Store.GetFilePath(Syms[0].FileId);
    if (Path <> '') and TFile.Exists(Path) then
    begin
      var AllLines: TArray<string>:= TFile.ReadAllLines(Path, TEncoding.ANSI);
      var Lo: Integer:= Syms[0].ImplStartLine - 1; // 1-based -> 0-based
      var Hi: Integer:= Syms[0].ImplEndLine   - 1;
      if Lo < 0 then Lo:= 0;
      if Hi > High(AllLines) then Hi:= High(AllLines);
      var Body: TArray<string>;
      SetLength(Body, Hi - Lo + 1);
      for var k:= Lo to Hi do Body[k - Lo]:= AllLines[k];
      Rhs:= MineReturnExpressions(Body);
    end;
  end;

  var UnitFile: string:= ExtractFileName(Store.GetFilePath(Syms[0].FileId));
  var Model: THoverModel:= BuildHoverModel(Syms[0], Doc, UnitFile, Rhs);
```

- [ ] **Step 2: Extend `RenderHoverJson` to take + emit the model**

In `DRagLint.Hover.Renderer.pas`, add an overload `RenderHoverJson(const AModel: THoverModel): string` (keep the old one for compatibility) that emits the new fields:

```pascal
function RenderHoverJson(const AModel: THoverModel): string;
var
  SB: TStringBuilder;
  i: Integer;
begin
  SB:= TStringBuilder.Create;
  try
    SB.Append('{');
    SB.Append(Format('"qname":"%s",', [JsonEscape(AModel.QualifiedName)]));
    SB.Append(Format('"unit":"%s","def_line":%d,', [JsonEscape(AModel.UnitFile), AModel.DefLine]));
    SB.Append(Format('"return_type":"%s",', [JsonEscape(AModel.ReturnType)]));
    SB.Append('"params":[');
    for i:= 0 to High(AModel.Params) do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(Format('{"modifier":"%s","name":"%s","type":"%s"}',
        [JsonEscape(AModel.Params[i].Modifier), JsonEscape(AModel.Params[i].Name), JsonEscape(AModel.Params[i].TypeText)]));
    end;
    SB.Append('],"returns":[');
    for i:= 0 to High(AModel.Returns) do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(Format('"%s"', [JsonEscape(AModel.Returns[i].Expr)]));
    end;
    SB.Append(Format('],"returns_more":%d,', [AModel.ReturnsMore]));
    SB.Append(Format('"summary":"%s"}', [JsonEscape(AModel.Doc.Summary)]));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;
```

In `DoHover`, change the json branch to: `if Fmt = 'json' then Write(RenderHoverJson(Model))`.

- [ ] **Step 2b: Build the CLI**

Build via `delphi-build` skill. Expected: `BUILD_EXITCODE=0`.

- [ ] **Step 3: Write the failing test (`run_hover_returns.ps1`)**

Create `tests/autotest/run_hover_returns.ps1`. Index a fixture with three functions: a boolean single-return, an integer multi-code return, and a procedure (no returns). Assert the JSON.

```powershell
[CmdletBinding()]
param([string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string] $WorkDir = "$env:TEMP\drag-lint-hover-returns")
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check([string]$Name,[bool]$Ok,[string]$Detail=''){
  $s = if($Ok){'PASS'}else{'FAIL'}; $c = if($Ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$Name,$Detail) -ForegroundColor $c
  if(-not $Ok){$script:Failed=$true}
}
if(-not(Test-Path $Exe)){Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2}
if(Test-Path $WorkDir){Remove-Item -Recurse -Force $WorkDir}
New-Item -ItemType Directory $WorkDir | Out-Null
$src = "$WorkDir\src"; New-Item -ItemType Directory $src | Out-Null
@'
unit RetFixture;
interface
function IsPos(const S2: string): boolean;
function Authy(const AUser: string): Integer;
procedure DoStuff;
implementation
const ERROR_OK = 0; ERROR_NO_USER = 1; ERROR_BAD = 2;
function IsPos(const S2: string): boolean;
begin
  Result := S2.Length > 0;
end;
function Authy(const AUser: string): Integer;
begin
  Result := ERROR_OK;
  if AUser = '' then Result := ERROR_NO_USER;
  if AUser = 'x' then Result := ERROR_BAD;
  Result := ERROR_OK; // duplicate -- must dedup
end;
procedure DoStuff;
begin
  Beep;
end;
end.
'@ | Set-Content "$src\RetFixture.pas" -Encoding ascii

$db = "$WorkDir\ret.sqlite"
& $Exe index $src --db $db | Out-Null
Check 'db created' (Test-Path $db)

$boolJson = (& $Exe hover --qname RetFixture.IsPos --db $db --format json 2>&1) -join "`n"
Check 'bool: mined Result := S2.Length > 0' ($boolJson -match '"returns":\["S2\.Length > 0"\]') $boolJson
Check 'bool: return_type boolean' ($boolJson -match '"return_type":"boolean"') $boolJson

$intJson = (& $Exe hover --qname RetFixture.Authy --db $db --format json 2>&1) -join "`n"
Check 'int: ERROR_OK present' ($intJson -match 'ERROR_OK') $intJson
Check 'int: ERROR_NO_USER present' ($intJson -match 'ERROR_NO_USER') $intJson
Check 'int: ERROR_BAD present' ($intJson -match 'ERROR_BAD') $intJson
# dedup: ERROR_OK appears once in the returns array
$okCount = ([regex]::Matches($intJson, 'ERROR_OK')).Count
Check 'int: ERROR_OK dedup (1 occurrence)' ($okCount -eq 1) "count=$okCount"

$procJson = (& $Exe hover --qname RetFixture.DoStuff --db $db --format json 2>&1) -join "`n"
Check 'proc: empty returns' ($procJson -match '"returns":\[\]') $procJson

# params structured
Check 'params carry name+type' ($boolJson -match '"name":"S2","type":"string"') $boolJson

Write-Host ''
if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red; exit 1}else{Write-Host 'PASS' -ForegroundColor Green; exit 0}
```

- [ ] **Step 4: Run the test, verify PASS**

Run: `pwsh -File tests/autotest/run_hover_returns.ps1`
Expected: all PASS, exit 0. (If `return_type` shows `boolean` vs `Boolean` casing differs, relax the regex to `(?i)boolean`.)

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas src/cli/DRagLint.Hover.Renderer.pas tests/autotest/run_hover_returns.ps1
git commit -m "feat(hover): hover --json emits model (params/returns/return_type); returns test"
```

---

## Task 5: IDE editor-font reader

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.Fonts.pas`
- Modify: `src/delphi-plugin/dclDragLintWizard.dpk` (add the unit)

**Interfaces:**
- Produces: `function GetIdeEditorFont(out AName: string; out ASize: Integer): Boolean;` in `DragLint.Plugin.Fonts` -- True when the IDE's configured editor font was read; on False the caller keeps its default.

- [ ] **Step 1: Write the unit (ToolsAPI editor-font option, guarded)**

Create `src/delphi-plugin/DragLint.Plugin.Fonts.pas` (ASCII/CRLF). The IDE exposes editor options via `IOTAEditOptions` (from `IOTAEditorServices.GetEditOptions` / `EditOptions`); the font is `IOTAEditOptions.GetOptionValue('EditorFontName')` / `('EditorFontSize')` (option names are the buffer-option keys). Guard the whole thing:

```pascal
unit DragLint.Plugin.Fonts;

/// <summary>Read the IDE's configured editor font so drag-lint popups render in
/// the same typeface the user picked (Consolas, Courier, whatever). Guarded --
/// returns False on any failure so callers keep their own default.</summary>

interface

/// <summary>The IDE editor font name + size from Tools > Options > Editor.</summary>
/// <param name="AName">Receives the font family name on success.</param>
/// <param name="ASize">Receives the point size on success.</param>
/// <returns>True if read from the IDE; False if unavailable (caller defaults).</returns>
function GetIdeEditorFont(out AName: string; out ASize: Integer): Boolean;

implementation

uses
  System.SysUtils, System.Variants, ToolsAPI;

function GetIdeEditorFont(out AName: string; out ASize: Integer): Boolean;
var
  EdSvc : IOTAEditorServices;
  Opts  : IOTAEditOptions   ;
  VName : Variant           ;
  VSize : Variant           ;
begin
  Result:= False;
  AName:= ''; ASize:= 0;
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, EdSvc) then Exit;
    Opts:= EdSvc.GetEditOptions('');    // '' = the default/active editor buffer options
    if Opts = nil then Exit;
    VName:= Opts.GetOptionValue('EditorFontName');
    VSize:= Opts.GetOptionValue('EditorFontSize');
    if not VarIsNull(VName) then AName:= VarToStr(VName);
    if not VarIsNull(VSize) then ASize:= VSize;
    Result:= (AName <> '') and (ASize > 0);
  except
    Result:= False; // any ToolsAPI surprise -> caller default
  end;
end;

end.
```

Note: exact option-key strings (`'EditorFontName'`/`'EditorFontSize'`) must be confirmed against the installed ToolsAPI during implementation. If `GetEditOptions('')` needs a non-empty buffer type, pass the Pascal source key the IDE uses; the executor confirms via the ToolsAPI unit source under `Studio\37.0\source\ToolsAPI`. The guard means a wrong key degrades to the Consolas fallback, never a crash.

- [ ] **Step 2: Build the plugin BPL, verify clean compile**

Build the plugin via `delphi-build` skill (Win32 BPL).
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 3: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Fonts.pas src/delphi-plugin/dclDragLintWizard.dpk
git commit -m "feat(hover): IDE editor-font reader (ToolsAPI, guarded)"
```

---

## Task 6: HoverForm -- TRichEdit body, colored + selectable, IDE font, contrast guard

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.HoverForm.pas`

**Interfaces:**
- Consumes: `EnsureReadable` (Task 1), `GetIdeEditorFont` (Task 5), the structured model parts (Task 4, passed by the Editor in Task 8).
- Produces: `ShowAt` overload that accepts a structured payload (qname, signature, unit, def-line, params array, return-type, returns array + more-count, callers array). The header + params + returns render into a `TRichEdit`; callers stay in the `TListView`.

- [ ] **Step 1: Swap the body `TMemo` for a `TRichEdit` and add a colored-run writer**

Change `FMemo: TMemo` to `FBody: TRichEdit` (uses already has `Vcl.ComCtrls`). Add a helper that appends a colored run honoring the contrast guard against the form's actual `Color`:

```pascal
procedure TDragLintHoverForm.Emit(const AText: string; AColor: TColor; ABold: Boolean);
var
  Safe: TColor;
begin
  Safe:= EnsureReadable(AColor, Self.Color, 4.5);
  FBody.SelStart := FBody.GetTextLen;
  FBody.SelLength:= 0;
  FBody.SelAttributes.Color:= Safe;
  if ABold then FBody.SelAttributes.Style:= [fsBold] else FBody.SelAttributes.Style:= [];
  FBody.SelText:= AText;
end;
```

Set `FBody.ReadOnly := True; FBody.BorderStyle := bsNone; FBody.ScrollBars := ssVertical;` and (after `ApplyIdeTheme`) `FBody.Color := Self.Color;`.

- [ ] **Step 2: Apply the IDE font (fallback Consolas 9)**

In the constructor, after creating `FBody` and `FCallers`:

```pascal
var FN: string; var FS: Integer;
if GetIdeEditorFont(FN, FS) then
begin
  FBody.Font.Name:= FN;    FBody.Font.Size:= FS;
  FCallers.Font.Name:= FN; FCallers.Font.Size:= FS;
end
else
begin
  FBody.Font.Name:= 'Consolas';    FBody.Font.Size:= 9;
  FCallers.Font.Name:= 'Consolas'; FCallers.Font.Size:= 9;
end;
```

Remove the two old hardcoded `FMemo.Font`/`FCallers.Font` Consolas lines.

- [ ] **Step 3: Add a structured render method + a color palette**

Define a small palette constant set (light-theme base colors -- the contrast guard adapts them per background):

```pascal
const
  CL_KEYWORD = TColor($00D0570B); // #0B57D0 blue
  CL_TYPE    = TColor($003C7A21); // #217A3C green
  CL_NAME    = TColor($00DB561A); // #1A56DB
  CL_PARAM   = TColor($00C1426F); // #6F42C1
  CL_OP      = TColor($00333333);
  CL_LIT     = TColor($001515A3); // #A31515
  CL_MUT     = TColor($008A8A8A);
```

Add `RenderModel(...)` that clears `FBody` and emits, in order: the colored signature header line (whole line click-navigates -- see Step 4), `Parameters` label + one aligned `modifier name : type` line per param (pad `Name` to `MaxNameLen`), `Returns` label + either `type : Result := expr` (single) or a list of `Result := expr` lines + `... and N more` when more-count > 0.

Alignment: compute `MaxNameLen := Max over params of Length(Name)`; emit `Name` padded with spaces to `MaxNameLen + 1` before the `:`.

- [ ] **Step 4: Make the header line click-navigate to the definition**

Keep the existing `GOnNavigateToQname` hook. On `FBody` click, if the caret is on line 0 (the header), call `GOnNavigateToQname(FModelQName, FModelDefLine)`. Store `FModelQName`/`FModelDefLine` when rendering. Show the hand cursor when the mouse is over line 0 (reuse the existing `EM_CHARFROMPOS` mouse-move handler, simplified: clickable when `LineIdx = 0`).

- [ ] **Step 5: Build the plugin BPL, verify clean compile**

Build via `delphi-build` skill.
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 6: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.HoverForm.pas
git commit -m "feat(hover): TRichEdit body -- colored+selectable, IDE font, contrast guard, clickable header"
```

---

## Task 7: Caller list 15/10 + "NN more" display cap

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.HoverForm.pas`

**Interfaces:**
- Consumes: the callers array (already passed to `ShowAt`).
- Produces: display behavior -- when caller count > 15, show the first 10 rows + a non-clickable `... and (N-10) more` trailer row; label reads `Called from (N)`.

- [ ] **Step 1: Add a pure cap helper + test-by-inspection**

Add:

```pascal
/// <summary>How many caller rows to display: all when total <= 15, else 10.</summary>
/// <returns>Row count to render; caller adds a "NN more" trailer when it is < total.</returns>
function DisplayedCallerCount(ATotal: Integer): Integer;
begin
  if ATotal <= 15 then Result:= ATotal else Result:= 10;
end;
```

- [ ] **Step 2: Apply the cap in the callers-fill loop**

In `ShowAt`, replace the `for I:= 0 to High(ACallers)` fill so it stops at `DisplayedCallerCount(Length(ACallers))`; when that is less than `Length(ACallers)`, add a final non-selectable row whose Caption is `... and (Length(ACallers) - shown) more` (leave SubItems empty so `HandleCallerDblClick`'s `SubItems.Count = 0` guard already skips navigation). Set the section label / a header text to `Called from (Length(ACallers))`.

- [ ] **Step 3: Build the plugin BPL, verify clean compile**

Build via `delphi-build` skill.
Expected: `BUILD_EXITCODE=0`.

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.HoverForm.pas
git commit -m "feat(hover): callers 15/10 + 'NN more' display cap with count label"
```

---

## Task 8: Editor wires `hover --json` model into the form

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas`

**Interfaces:**
- Consumes: `hover --qname X --format json` (Task 4); the new `ShowAt` structured overload (Task 6).
- Produces: hover invocation that fetches the JSON model, parses params/returns/return-type/def-line, and calls the structured `ShowAt` (callers still from `FetchHoverCallers`).

- [ ] **Step 1: Add a `FetchHoverModel` function**

Add a function mirroring `FetchHoverCallers` that runs `"%s" hover --qname "%s"%s --format json` (qname from the LSP hover or `IdentifierAtCursor`-resolved qname), parses the JSON into a record the form consumes (qname, unit, def_line, params[], return_type, returns[], returns_more). Keep it guarded (empty -> fall back to the existing markdown path).

- [ ] **Step 2: Call the structured `ShowAt` from `InvokeHover`**

Replace the `ShowDragLintHover(Header, HoverText, Callers, ...)` call with the structured path: fetch the model, then call the structured overload passing model parts + `Callers`. Keep the old string `ShowDragLintHover` for the dwell popup (short LSP-only summary) if it is still used.

- [ ] **Step 3: Build the plugin BPL, verify clean compile**

Build via `delphi-build` skill.
Expected: `BUILD_EXITCODE=0`.

- [ ] **Step 4: Regression: run the full CLI battery**

Run the existing autotest suite that covers hover/typeat plus the two new tests:

Run: `pwsh -File tests/autotest/run_hover_returns.ps1` and `pwsh -File tests/autotest/run_hover_contrast.ps1` and `pwsh -File tests/autotest/run_typeat_scope.ps1`
Expected: all exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas
git commit -m "feat(hover): Editor fetches hover --json model, drives structured popup"
```

---

## Task 9: Reindex, final battery, IDE live-smoke handoff

**Files:** none (verification + docs).

- [ ] **Step 1: Reindex the self-index incrementally**

The new/changed `.pas` units changed indexed symbols. Reindex the drag-lint self-index (`tests/draglint_self.sqlite` or the manifest self DB) incrementally per the CLAUDE.md rule.

- [ ] **Step 2: Run the full autotest battery**

Run the standard suites (lint, store, hover-returns, hover-contrast, typeat-scope). Expected: green.

- [ ] **Step 3: Update BACKLOG + CHANGELOG**

Add a `docs/lint/BACKLOG.md` entry describing the hover restyle shipped and the open IDE live-smoke item. Add a CHANGELOG line.

- [ ] **Step 4: Commit**

```bash
git add docs/lint/BACKLOG.md CHANGELOG.md
git commit -m "docs(hover): backlog + changelog for Help-Insight hover restyle"
```

- [ ] **Step 5: IDE live smoke (USER, deferred)**

Hand off to the user: reopen RAD Studio with the rebuilt BPL, hover a known function, and confirm: colored one-line signature in the IDE font; right-aligned `unit.pas Line N`; clickable header -> definition; aligned params with modifiers; mined Returns; `Called from (N)` with the 15/10 cap; text is selectable + Ctrl+C copies; dark-theme readability (contrast guard). This is the acceptance gate for the IDE surface (matches the pattern for prior IDE features).

---

## Self-Review Notes (author)

- **Spec coverage:** header one-line/clickable (T6 S3-4), IDE font (T5, T6 S2), aligned params (T3 ParseSignatureParams, T6 S3), returns-mining distinct+cap10 (T2, T4), called-from 15/10+NN (T7), contrast guard (T1, T6 S1), TRichEdit selectable (T6), no schema change (T4 reuses ImplStartLine/ImplEndLine), CLI hover --json (T4). All mapped.
- **Deferred (spec sec 6):** markdown prose engine, multi-line RHS reflow, colorized caller Code column, caller-fetch changes -- intentionally not tasked.
- **Known implementation risk flagged inline:** exact ToolsAPI editor-font option keys (T5) + `RGB2TColor` availability (T1) -- both guarded/fallback so a wrong guess degrades gracefully, executor confirms against installed ToolsAPI/VCL source.
