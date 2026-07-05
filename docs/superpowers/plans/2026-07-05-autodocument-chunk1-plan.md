# AutoDocument Chunk 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and repair a DocInsight doc-comment for a single public Delphi declaration from index-grounded facts, via sentinel-fenced managed regions, exposed as a `document` CLI verb and an IDE "Document it" menu; publish v0.90.0-alpha.

**Architecture:** Three new focused units under `src/doc/`: `DRagLint.Doc.Facts` (index queries -> a `TDocFacts` record; no text), `DRagLint.Doc.Regions` (sentinel-fenced managed-region text manipulation -> comment string; no index), and `DRagLint.Doc.Document` (orchestrator: resolve symbol, read existing comment, merge, return `TArray<TTextEdit>`). The CLI `document` verb and IDE menu both call the orchestrator. Reuses `TDocStubGenerator` signature helpers, `TDocCommentScanner`/`TDocCommentParser`, `TTextEditApplier`, and `ISymbolStore`.

**Tech Stack:** Delphi 13 (RAD Studio 37), Object Pascal, tree-sitter, SQLite index, PowerShell test harnesses, delphi-build skill.

## Global Constraints

- **Encoding:** all `.pas` source and fixtures are strict 7-bit ASCII, CRLF, no BOM. Never Unicode/LF. **Never put a literal `{` or `}` inside a Pascal `{ }` comment** -- it breaks the comment and the compile (a lesson from AutoFix Chunk 2). The self-lint error-count in the PostToolUse hook is a canary, but the delphi-build result is the authoritative gate.
- **DocInsight:** every new public function/type gets a `///` `<summary>`; keep comment + test + code in agreement.
- **Never fabricate prose.** Generated `<summary>` and `<param>` bodies are always the literal `TODO: describe.`. Every emitted `<remarks>` fact is index/AST-derived.
- **Build:** use the `delphi-build` skill. Recipe here: run `build\build_draglint_win64.bat` via PowerShell `Start-Process cmd.exe -ArgumentList "/c","<bat>" -RedirectStandardOutput <log> -NoNewWindow -Wait -PassThru`; require exit 0, no `[dcc64 Error]`/`E2xxx`/`Fatal` in the log; it stages `src\cli\Win64\Debug\drag-lint.exe` -> `third_party\dll-win64\drag-lint.exe`. Do NOT use the MCP build tool; do NOT `cmd /c build.bat` from the Bash tool.
- **New unit = TWO edits:** add the `.pas` to `src\cli\drag-lint.dproj` as a `<DCCReference Include="..\doc\DRagLint.Doc.X.pas"/>` (after line 140, the DocStub reference) AND add it to the `uses` clause of the consuming unit. Editing an existing unit needs neither.
- **Test CWD:** run PowerShell harnesses from a NEUTRAL CWD (`C:\TEMP`) so no ambient `drag-lint-lint.json` is picked up. Fixtures' `unit` name must match the filename (keeps `unit-name-matches-file` quiet).
- **Guardrail (green after every task):** lint 154/154 (`tests\lint\run_lint_tests.ps1`), store 16/16 (`tests\lint-store\run_store_tests.ps1`), autofix 9 suites (`tests\autofix\*.ps1`).

**Key existing locations (verified 2026-07-05):**
- `TDocStubGenerator.Generate(store, qname, format): string` + helpers `ExtractParamList(sig)`, `ParseParamNames(list): TArray<string>`, `SignatureHasReturn(sig): Boolean`, `ReadSourceLine(path, line): string` -- `src/refactor/DRagLint.Refactor.DocStub.pas`. (Helpers are in the `implementation` section -- to reuse, either move them to the `interface` or copy the small ones; see Task 2.)
- `TDocCommentScanner.Scan(source): TList<TDocCommentRegion>`; `FindDocRegionAbove(regions, symStartLine, allowGap, captureLoose): TDocCommentRegion` (`src/core/DRagLint.Core.Indexer.pas:148`); `TDocCommentParser.Dispatch(region): TParsedDoc` -- `src/parser/DRagLint.Parser.DocComments.pas`.
- `TParsedDoc` (`src/core/DRagLint.Core.Model.pas:220`): `Summary, Remarks, ReturnsText, Params: TArray<TDocParam>{Name,Desc}, StartLine, EndLine, HasContent`. `TDocParam` = `{Name, Desc}` (Model.pas:189). `TDocException` = `{TypeName, Desc}` (Model.pas:194).
- `ISymbolStore` (`src/core/DRagLint.Core.Interfaces.pas`): `FindSymbolsByQualifiedName(q): TArray<TSymbol>`, `FindCallersByName(callee): TArray<TReference>`, `GetSymbolById(id): TSymbol` (:135), `GetFilePath(fileId): string`, `GetSymbolSlice(qname): TArray<TSliceChunk>`.
- `TReference` (Model.pas:84): `FileId, NameText, StartLine, EnclosingSymbolId`. `TSymbol`: `Id, FileId, Kind, Signature, StartLine, EndLine, ImplStartLine, ImplEndLine, QName/Name`.
- `TTextEdit` + `TTextEditApplier.Apply(edits, backup): Integer` / `RenderDryRun(edits): string`; kinds `tekInsertLines` (insert Text after 1-based Line; 0 = top), `tekDeleteLines` (Line..EndLine) -- `src/refactor/DRagLint.Refactor.TextEdit.pas`.
- CLI: `TArgs` has `QName, InFile, Name, Apply, NoBackup, AsJson, Format, DbPath` (all parsed already; `--qname` at CLI.pas:466). `DoFindUnit` (CLI.pas:6149) = the verb template. Command dispatch at CLI.pas:10248+. `DoGenerateDocs` (CLI.pas:6116) is the legacy print-only stub -- LEAVE IT.

---

## Task 1: Scaffolding -- `src/doc/` units compile empty + wired into the build

**Files:**
- Create: `src/doc/DRagLint.Doc.Facts.pas`, `src/doc/DRagLint.Doc.Regions.pas`, `src/doc/DRagLint.Doc.Document.pas` (interface skeletons only)
- Modify: `src/cli/drag-lint.dproj` (3 `<DCCReference>` after line 140)

**Interfaces:**
- Produces: the three unit names + their public type stubs (filled in Tasks 2-4). This task only proves they compile and link.

- [ ] **Step 1: Create the three skeleton units**

`src/doc/DRagLint.Doc.Facts.pas`:

```pascal
unit DRagLint.Doc.Facts;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TDocFactRef = record
    Display : string;   { e.g. 'Unit1.DoThing' }
    Location: string;   { e.g. 'U1.pas:42' }
  end;

  /// <summary>Index-grounded facts about one symbol, for the managed
  /// DocInsight remarks block. All lists are capped for display; the *Total
  /// fields carry the true count so the renderer can add '(+N more)'.</summary>
  TDocFacts = record
    CalledFrom     : TArray<TDocFactRef>;
    Calls          : TArray<string>     ;
    UsedInUnits    : TArray<string>     ;
    Raises         : TArray<string>     ;
    ReturnType     : string             ;
    CalledFromTotal: Integer            ;
    CallsTotal     : Integer            ;
    UsedInTotal    : Integer            ;
  end;

  TDocFactsBuilder = class
  public
    /// <summary>Builds the grounded facts for ASym from the index.</summary>
    class function Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
  end;

implementation

class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
begin
  Result:= Default(TDocFacts);
end;

end.
```

`src/doc/DRagLint.Doc.Regions.pas`:

```pascal
unit DRagLint.Doc.Regions;

interface

uses
  System.SysUtils, System.Classes,
  DRagLint.Core.Model, DRagLint.Doc.Facts;

const
  AUTO_BEGIN = '<!-- drag-lint:auto BEGIN -->';
  AUTO_END   = '<!-- drag-lint:auto END -->';
  AUTO_PARAM = '<!-- drag-lint:auto param -->';

type
  TDocRegions = class
  public
    /// <summary>Renders the fenced facts-block body lines (each prefixed
    /// APrefix), from AFacts. Empty sections omitted; '' when no facts.</summary>
    class function RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
    /// <summary>Produces the full merged comment text: preserved prose +
    /// regenerated managed facts block + managed param tags.</summary>
    class function MergeComment(const AExisting: TParsedDoc;
      const ASigParams: TArray<string>; const AFacts: TDocFacts;
      AHasReturn: Boolean; const APrefix: string): string;
  end;

implementation

class function TDocRegions.RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
begin
  Result:= '';
end;

class function TDocRegions.MergeComment(const AExisting: TParsedDoc;
  const ASigParams: TArray<string>; const AFacts: TDocFacts;
  AHasReturn: Boolean; const APrefix: string): string;
begin
  Result:= '';
end;

end.
```

`src/doc/DRagLint.Doc.Document.pas`:

```pascal
unit DRagLint.Doc.Document;

interface

uses
  System.SysUtils,
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Refactor.TextEdit;

type
  TDocumentAction = (daCreated, daExtended, daUnchanged, daNotFound);

  TDocumentResult = record
    Action  : TDocumentAction   ;
    QName   : string            ;
    FilePath: string            ;
    Line    : Integer           ;
    Edits   : TArray<TTextEdit> ;
  end;

  TDocumenter = class
  public
    /// <summary>Resolves AQName and computes the doc-comment edits.</summary>
    class function BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
  end;

implementation

class function TDocumenter.BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
begin
  Result:= Default(TDocumentResult);
  Result.Action:= daNotFound;
  Result.QName := AQName;
end;

end.
```

- [ ] **Step 2: Wire into the .dproj**

In `src/cli/drag-lint.dproj`, after line 140 (`<DCCReference Include="..\refactor\DRagLint.Refactor.DocStub.pas"/>`), add:

```xml
        <DCCReference Include="..\doc\DRagLint.Doc.Facts.pas"/>
        <DCCReference Include="..\doc\DRagLint.Doc.Regions.pas"/>
        <DCCReference Include="..\doc\DRagLint.Doc.Document.pas"/>
```

- [ ] **Step 3: Reference the units so the linker keeps them**

The units aren't consumed yet; to force a link (and catch F2613), add them to the CLI `uses` now. In `src/cli/DRagLint.CLI.pas`, find the `implementation` `uses` clause (search for `DRagLint.Refactor.DocStub` in a `uses`) and append `, DRagLint.Doc.Facts, DRagLint.Doc.Regions, DRagLint.Doc.Document`. If DocStub is not in a CLI uses clause, add the three to the main implementation `uses` list.

- [ ] **Step 4: Build to verify it compiles + links**

Build via delphi-build (`build\build_draglint_win64.bat`). Expected: exit 0, no `[dcc64 Error]`, `OK: staged`. A `F2613 Unit ... not found` means the `.dproj` DCCReference path is wrong; `[H2077]`/hints are fine.

- [ ] **Step 5: Commit**

```bash
git add src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas src/doc/DRagLint.Doc.Document.pas src/cli/drag-lint.dproj src/cli/DRagLint.CLI.pas
git commit -m "scaffold(autodoc): DRagLint.Doc.Facts/.Regions/.Document units + dproj wiring"
```

---

## Task 2: `DRagLint.Doc.Facts` -- Called-from + Returns + the cap rule

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas`
- Create: `tests/autodoc/fixtures/callers/` (a fixture project: one documented target + several callers), `tests/autodoc/run_doc_facts.ps1` (drives via the `document` verb once Task 5 lands -- for THIS task, test the cap logic through a small helper). See Step 1.

**Interfaces:**
- Consumes: `ISymbolStore.FindCallersByName`, `GetSymbolById`, `GetFilePath`; `TReference`, `TSymbol`; `SignatureHasReturn`/return-type parse.
- Produces: `TDocFactsBuilder.Build(store, sym): TDocFacts` filling `CalledFrom` (+`CalledFromTotal`), `ReturnType`. (Calls/UsedIn/Raises come in Task 3.)

- [ ] **Step 1: Write the failing test (cap helper, unit-level)**

The cap rule is the highest-risk logic and is testable in isolation. Expose it as a public class function and test it via a tiny console assertion embedded in the harness is not possible (no Pascal test host here), so instead make the cap a pure function and assert it through the end-to-end `document` output in Task 5's `run_doc_cap.ps1`. FOR THIS TASK, write the cap as a documented public helper and rely on a build + a manual spot-check; the behavioural lock is `run_doc_cap.ps1` (Task 6).

Add to `DRagLint.Doc.Facts` interface:

```pascal
  /// <summary>Applies the display cap: a list of ATotal items shows all of them
  /// UNLESS ATotal > 15, in which case only the first 10 are kept and the caller
  /// appends '(+N more)' with N = ATotal - 10. Returns how many to display.</summary>
  function DocDisplayCount(ATotal: Integer): Integer;
```

- [ ] **Step 2: Implement the cap + Called-from + Returns**

Replace the `implementation` of `DRagLint.Doc.Facts.pas`:

```pascal
implementation

uses
  DRagLint.Refactor.DocStub;  { for SignatureHasReturn if exported; else see note }

function DocDisplayCount(ATotal: Integer): Integer;
begin
  if ATotal > 15 then Result:= 10 else Result:= ATotal;
end;

function LastSeg(const S: string): string;
var P: Integer;
begin
  P:= S.LastDelimiter('.');
  if P >= 0 then Result:= Copy(S, P + 2, MaxInt) else Result:= S;
end;

{ Parses the return type from a signature: the text after the LAST ':' that is
  outside the parameter parentheses. '' when none (a procedure). }
function ParseReturnType(const ASig: string): string;
var OpenP, CloseP, Colon: Integer;
begin
  Result:= '';
  CloseP:= ASig.LastDelimiter(')');
  Colon := ASig.LastDelimiter(':');
  if (Colon > CloseP) and (Colon >= 0) then
    Result:= Trim(Copy(ASig, Colon + 2, MaxInt)).TrimRight([';']);
end;

class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
var
  Refs   : TArray<TReference>;
  R      : TReference        ;
  Encl   : TSymbol           ;
  FR     : TDocFactRef       ;
  Acc    : TList<TDocFactRef>;
  Shown  : Integer           ;
  I      : Integer           ;
begin
  Result:= Default(TDocFacts);

  { Called from: name-based caller refs -> display 'EnclosingQName (file:line)'. }
  Refs:= AStore.FindCallersByName(LastSeg(ASym.QName));
  Result.CalledFromTotal:= Length(Refs);
  Shown:= DocDisplayCount(Length(Refs));
  Acc:= TList<TDocFactRef>.Create;
  try
    for I:= 0 to Shown - 1 do
    begin
      R:= Refs[I];
      FR:= Default(TDocFactRef);
      if R.EnclosingSymbolId > 0 then
      begin
        Encl:= AStore.GetSymbolById(R.EnclosingSymbolId);
        FR.Display:= Encl.QName;
      end;
      if FR.Display = '' then FR.Display:= LastSeg(ASym.QName) + ' caller';
      FR.Location:= ExtractFileName(AStore.GetFilePath(R.FileId)) + ':' + IntToStr(R.StartLine);
      Acc.Add(FR);
    end;
    Result.CalledFrom:= Acc.ToArray;
  finally
    Acc.Free;
  end;

  { Returns: type from the signature, else '' (procedures). }
  Result.ReturnType:= ParseReturnType(ASym.Signature);
end;
```

**NOTE on `SignatureHasReturn`/helpers:** they live in the `implementation` of `DRagLint.Refactor.DocStub` (not exported). Do NOT add a `uses` you can't call. For Facts, `ParseReturnType` above is self-contained (no DocStub dependency needed) -- remove the DocStub `uses` if unused. The param-name helpers ARE needed later (Task 4); Task 4 handles exporting them.

- [ ] **Step 3: Build**

delphi-build -> exit 0, no errors. (Behavioural verification is deferred to Task 6's `run_doc_cap.ps1` once the `document` verb exists; this task is a compile gate + the isolated cap function.)

- [ ] **Step 4: Commit**

```bash
git add src/doc/DRagLint.Doc.Facts.pas
git commit -m "feat(autodoc): Doc.Facts -- Called-from + Returns + 10/+N-more cap rule"
```

---

## Task 3: `DRagLint.Doc.Facts` -- Calls (outgoing), Used-in, Raises

**RISK-FIRST: the "Calls (outgoing)" query is the flagged uncertainty. Verify it BEFORE coding the branch.**

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas`

**Interfaces:**
- Consumes: same store; `GetSymbolSlice` or a refs-by-enclosing query; body text for Raises.
- Produces: `TDocFacts.Calls/CallsTotal`, `UsedInUnits/UsedInTotal`, `Raises` filled.

- [ ] **Step 1: Verify the outgoing-calls source (spike, no commit)**

Run against the self-index to see what's available for "refs whose EnclosingSymbolId = a given symbol":
```
drag-lint dump-refs --qname <some.known.Method> --db Delphi-RAG-lint.sqlite   (if such a verb exists)
```
Check `src/cli/DRagLint.CLI.pas` for a store method returning refs by enclosing symbol (grep `Enclosing`), and `GetSymbolSlice`. DECISION:
- If a clean "refs by enclosing symbol id" store method exists -> use it: each such ref's `NameText` is an outgoing call target.
- ELSE fall back to a bounded body text-scan: read the symbol's impl body lines (`ASym.ImplStartLine..ImplEndLine` via `GetFilePath`+source), lexer-skip strings/comments, collect `Identifier(` call sites at statement level, dedupe. Label the section 'Calls' regardless.

Record the choice in a code comment.

- [ ] **Step 2: Implement Calls + Used-in + Raises**

Append to `TDocFactsBuilder.Build` (before the final `end;`):

```pascal
  { Calls (outgoing): per Step-1 decision -- refs enclosed by ASym, or a bounded
    body scan. Dedupe, cap. (Body-scan fallback shown; swap for the store method
    if one was found.) }
  var CallSet: TStringList:= TStringList.Create;
  try
    CallSet.Sorted:= True; CallSet.Duplicates:= dupIgnore;
    if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
    begin
      var Src: TArray<string>;
      try Src:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI); except Src:= nil; end;
      for var Ln:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(Src)) do
        CollectCallIdents(Src[Ln - 1], CallSet);  { helper: scan 'Ident(' outside strings }
    end;
    Result.CallsTotal:= CallSet.Count;
    var ShownC: Integer:= DocDisplayCount(CallSet.Count);
    SetLength(Result.Calls, ShownC);
    for var J:= 0 to ShownC - 1 do Result.Calls[J]:= CallSet[J];
  finally
    CallSet.Free;
  end;

  { Used in units: only for type-like kinds. Distinct owning units of refs to the
    type name. }
  if ASym.Kind in [skClass, skInterface, skRecord] then
  begin
    var URefs: TArray<TReference>:= AStore.FindCallersByName(LastSeg(ASym.QName));
    var UnitSet: TStringList:= TStringList.Create;
    try
      UnitSet.Sorted:= True; UnitSet.Duplicates:= dupIgnore;
      for var UR in URefs do
        UnitSet.Add(ChangeFileExt(ExtractFileName(AStore.GetFilePath(UR.FileId)), ''));
      Result.UsedInTotal:= UnitSet.Count;
      var ShownU: Integer:= DocDisplayCount(UnitSet.Count);
      SetLength(Result.UsedInUnits, ShownU);
      for var K:= 0 to ShownU - 1 do Result.UsedInUnits[K]:= UnitSet[K];
    finally
      UnitSet.Free;
    end;
  end;

  { Raises: 'raise <Ident>' class names in the body, deduped. }
  var RaiseSet: TStringList:= TStringList.Create;
  try
    RaiseSet.Sorted:= True; RaiseSet.Duplicates:= dupIgnore;
    if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
    begin
      var Src2: TArray<string>;
      try Src2:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI); except Src2:= nil; end;
      for var Ln2:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(Src2)) do
        CollectRaiseClass(Src2[Ln2 - 1], RaiseSet);  { helper: 'raise <Ident>' -> Ident }
    end;
    Result.Raises:= RaiseSet.ToStringArray;
  finally
    RaiseSet.Free;
  end;
```

Add the two private helpers `CollectCallIdents(const ALine: string; AAcc: TStringList)` and `CollectRaiseClass(const ALine: string; AAcc: TStringList)` (simple char-scan: skip `'...'` string literals and `//`/`{...}` comments; for calls, capture an identifier immediately followed by `(`; for raises, after a whole-word `raise` capture the next identifier). Add `System.IOUtils`, `System.Math` to the `uses`.

- [ ] **Step 3: Build -> exit 0.**

- [ ] **Step 4: Commit**

```bash
git add src/doc/DRagLint.Doc.Facts.pas
git commit -m "feat(autodoc): Doc.Facts -- Calls (outgoing), Used-in units, Raises"
```

---

## Task 4: `DRagLint.Doc.Regions` -- render facts block + MergeComment

**Files:**
- Modify: `src/doc/DRagLint.Doc.Regions.pas`; `src/refactor/DRagLint.Refactor.DocStub.pas` (export the param helpers to the interface so Regions/Document can reuse them)

**Interfaces:**
- Consumes: `TParsedDoc`, `TDocParam`, `TDocFacts`, the sentinel consts; `ParseParamNames` (exported from DocStub in Step 1).
- Produces: `TDocRegions.RenderFactsBlock`, `TDocRegions.MergeComment` (returns the full comment text, `///`-prefixed lines joined by CRLF).

- [ ] **Step 1: Export the DocStub param helpers**

In `src/refactor/DRagLint.Refactor.DocStub.pas`, move the declarations of `ExtractParamList`, `ParseParamNames`, `SignatureHasReturn` into the `interface` section (leave bodies in `implementation`). Add to the `interface`:

```pascal
function ExtractParamList(const ASig: string): string;
function ParseParamNames(const AParamList: string): TArray<string>;
function SignatureHasReturn(const ASig: string): Boolean;
```

Build -> exit 0 (no behaviour change; guardrail: `generate-docs` still works).

- [ ] **Step 2: Write the failing test (via the verb, deferred) -- implement RenderFactsBlock**

`RenderFactsBlock` is behaviourally locked by `run_doc_generate.ps1` (Task 6). Implement it:

```pascal
class function TDocRegions.RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
var
  Sb: TStringBuilder;
  function MoreSuffix(AShown, ATotal: Integer): string;
  begin
    if ATotal > AShown then Result:= Format(' (+%d more)', [ATotal - AShown]) else Result:= '';
  end;
  function JoinRefs(const A: TArray<TDocFactRef>): string;
  var i: Integer;
  begin
    Result:= '';
    for i:= 0 to High(A) do
    begin
      if i > 0 then Result:= Result + ', ';
      Result:= Result + A[i].Display + ' (' + A[i].Location + ')';
    end;
  end;
begin
  Sb:= TStringBuilder.Create;
  try
    if Length(AFacts.CalledFrom) > 0 then
      Sb.AppendLine(APrefix + 'Called from: ' + JoinRefs(AFacts.CalledFrom) + MoreSuffix(Length(AFacts.CalledFrom), AFacts.CalledFromTotal));
    if Length(AFacts.Calls) > 0 then
      Sb.AppendLine(APrefix + 'Calls: ' + string.Join(', ', AFacts.Calls) + MoreSuffix(Length(AFacts.Calls), AFacts.CallsTotal));
    if Length(AFacts.UsedInUnits) > 0 then
      Sb.AppendLine(APrefix + 'Used in units: ' + string.Join(', ', AFacts.UsedInUnits) + MoreSuffix(Length(AFacts.UsedInUnits), AFacts.UsedInTotal));
    if Length(AFacts.Raises) > 0 then
      Sb.AppendLine(APrefix + 'Raises: ' + string.Join(', ', AFacts.Raises));
    Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;
```

Add `System.SysUtils` (Format), keep `System.Classes` (TStringBuilder).

- [ ] **Step 3: Implement MergeComment**

The full merge. `APrefix` is the `///` + indentation (e.g. `'/// '`). Rules per the spec Design 3. Fresh comment (no `AExisting.HasContent`):

```pascal
class function TDocRegions.MergeComment(const AExisting: TParsedDoc;
  const ASigParams: TArray<string>; const AFacts: TDocFacts;
  AHasReturn: Boolean; const APrefix: string): string;
var
  Sb   : TStringBuilder;
  P    : string        ;
  Facts: string        ;
begin
  Sb:= TStringBuilder.Create;
  try
    Facts:= RenderFactsBlock(AFacts, APrefix);
    if not AExisting.HasContent then
    begin
      Sb.AppendLine(APrefix + '<summary>TODO: describe.</summary>');
      for P in ASigParams do
        Sb.AppendLine(APrefix + '<param name="' + P + '">TODO: describe.</param>' + AUTO_PARAM);
      if AHasReturn then
        Sb.AppendLine(APrefix + '<returns>TODO: describe.</returns>');
      if Facts <> '' then
      begin
        Sb.AppendLine(APrefix + '<remarks>');
        Sb.AppendLine(APrefix + AUTO_BEGIN);
        Sb.AppendLine(Facts);
        Sb.AppendLine(APrefix + AUTO_END);
        Sb.AppendLine(APrefix + '</remarks>');
      end;
      Result:= Sb.ToString.TrimRight([#13, #10]);
      Exit;
    end;

    { Existing comment: preserve prose, regenerate managed regions. Rebuild from
      the parsed model: keep Summary (or TODO), keep hand-typed params + descs,
      add AUTO_PARAM tags for missing sig params, drop AUTO_PARAM tags for params
      no longer in the signature, flag hand-typed stale params, then the returns
      tag, then a fresh <remarks> managed block. }
    var SummaryText: string:= AExisting.Summary;
    if Trim(SummaryText) = '' then SummaryText:= 'TODO: describe.';
    Sb.AppendLine(APrefix + '<summary>' + SummaryText + '</summary>');

    { existing params first, in signature order where possible }
    for P in ASigParams do
    begin
      var Found: Boolean:= False;
      for var EP in AExisting.Params do
        if SameText(EP.Name, P) then
        begin
          var Desc: string:= EP.Desc; if Trim(Desc) = '' then Desc:= 'TODO: describe.';
          { hand-typed (had a non-TODO desc) => no AUTO_PARAM marker; else marker }
          if SameText(Trim(EP.Desc), '') or SameText(Trim(EP.Desc), 'TODO: describe.') then
            Sb.AppendLine(APrefix + '<param name="' + P + '">' + Desc + '</param>' + AUTO_PARAM)
          else
            Sb.AppendLine(APrefix + '<param name="' + P + '">' + Desc + '</param>');
          Found:= True; Break;
        end;
      if not Found then
        Sb.AppendLine(APrefix + '<param name="' + P + '">TODO: describe.</param>' + AUTO_PARAM);
    end;
    { stale hand-typed params: in the comment but not the signature -> flag, keep }
    for var EP in AExisting.Params do
    begin
      var StillThere: Boolean:= False;
      for P in ASigParams do if SameText(EP.Name, P) then begin StillThere:= True; Break; end;
      if (not StillThere) and (Trim(EP.Desc) <> '') and (not SameText(Trim(EP.Desc), 'TODO: describe.')) then
        Sb.AppendLine(APrefix + '<param name="' + EP.Name + '">' + EP.Desc + '</param> <!-- drag-lint: param no longer exists -->');
    end;

    if AHasReturn then
    begin
      var Ret: string:= AExisting.ReturnsText; if Trim(Ret) = '' then Ret:= 'TODO: describe.';
      Sb.AppendLine(APrefix + '<returns>' + Ret + '</returns>');
    end;

    { remarks: keep hand prose (AExisting.Remarks) OUTSIDE the fence, then a fresh
      managed block. AExisting.Remarks from the parser excludes our fenced content
      only if the parser captured it verbatim; to be safe, strip any old fenced
      block from the prose before re-emitting. }
    var Prose: string:= StripManagedBlock(AExisting.Remarks);
    if (Trim(Prose) <> '') or (Facts <> '') then
    begin
      Sb.AppendLine(APrefix + '<remarks>');
      if Trim(Prose) <> '' then Sb.AppendLine(APrefix + Trim(Prose));
      if Facts <> '' then
      begin
        Sb.AppendLine(APrefix + AUTO_BEGIN);
        Sb.AppendLine(Facts);
        Sb.AppendLine(APrefix + AUTO_END);
      end;
      Sb.AppendLine(APrefix + '</remarks>');
    end;
    Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;
```

Add private helper `StripManagedBlock(const S: string): string` -- removes any text from `AUTO_BEGIN` to `AUTO_END` inclusive (so re-runs don't nest blocks). Add `System.StrUtils` if needed for `ContainsText`.

- [ ] **Step 4: Build -> exit 0.**

- [ ] **Step 5: Commit**

```bash
git add src/doc/DRagLint.Doc.Regions.pas src/refactor/DRagLint.Refactor.DocStub.pas
git commit -m "feat(autodoc): Doc.Regions -- managed facts block + MergeComment (preserve prose)"
```

---

## Task 5: `DRagLint.Doc.Document` orchestrator + `document` CLI verb

**Files:**
- Modify: `src/doc/DRagLint.Doc.Document.pas`; `src/cli/DRagLint.CLI.pas` (new `DoDocument` + dispatch + usage line)

**Interfaces:**
- Consumes: `TDocFactsBuilder.Build`, `TDocRegions.MergeComment`, `TDocCommentScanner.Scan`+`FindDocRegionAbove`+`TDocCommentParser.Dispatch`, `ExtractParamList`/`ParseParamNames`/`SignatureHasReturn`, `TTextEditApplier`.
- Produces: `TDocumenter.BuildFor(store, qname): TDocumentResult`; CLI verb `document`.

- [ ] **Step 1: Implement the orchestrator**

Replace `TDocumenter.BuildFor` in `DRagLint.Doc.Document.pas`:

```pascal
uses
  System.Classes, System.IOUtils, System.Generics.Collections,
  DRagLint.Doc.Facts, DRagLint.Doc.Regions,
  DRagLint.Parser.DocComments, DRagLint.Refactor.DocStub;

class function TDocumenter.BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
var
  Syms  : TArray<TSymbol>;
  Sym   : TSymbol        ;
  Path  : string         ;
  Src   : string         ;
  Regions: System.Generics.Collections.TList<TDocCommentRegion>;
  Region : TDocCommentRegion;
  Existing: TParsedDoc   ;
  SigParams: TArray<string>;
  HasRet : Boolean       ;
  Facts  : TDocFacts     ;
  Merged : string        ;
  Prefix : string        ;
  E      : TTextEdit     ;
begin
  Result:= Default(TDocumentResult);
  Result.QName:= AQName; Result.Action:= daNotFound;
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym:= Syms[0];
  Path:= AStore.GetFilePath(Sym.FileId);
  Result.FilePath:= Path; Result.Line:= Sym.StartLine;
  if (Path = '') or (not TFile.Exists(Path)) then Exit;
  Src:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(Path));

  { existing comment above the decl }
  Existing:= Default(TParsedDoc);
  Regions:= TDocCommentScanner.Scan(Src);
  try
    Region:= FindDocRegionAbove(Regions, Sym.StartLine, 1, False);
    if Region.EndLine > 0 then Existing:= TDocCommentParser.Dispatch(Region);
  finally
    Regions.Free;
  end;

  { signature-derived params + return }
  var Sig: string:= Trim(Sym.Signature);
  if Sig = '' then Sig:= '';  { ReadSourceLine fallback handled inside DocStub if needed }
  SigParams:= ParseParamNames(ExtractParamList(Sig));
  HasRet   := SignatureHasReturn(Sig) or (Sym.Kind in [skFunction, skConstructor]);

  Facts := TDocFactsBuilder.Build(AStore, Sym);
  Prefix:= '/// ';
  Merged:= TDocRegions.MergeComment(Existing, SigParams, Facts, HasRet, Prefix);

  { decide action + edits }
  if Existing.HasContent then
  begin
    { unchanged? compare merged to the existing raw block, normalized }
    if SameText(Trim(Existing.RawBlock), Trim(Merged)) then
    begin Result.Action:= daUnchanged; Exit; end;
    { replace the old comment span, then insert the merged one above the decl }
    E:= Default(TTextEdit); E.FilePath:= Path; E.Kind:= tekDeleteLines;
    E.Line:= Existing.StartLine; E.EndLine:= Existing.EndLine;
    Result.Edits:= Result.Edits + [E];
    E:= Default(TTextEdit); E.FilePath:= Path; E.Kind:= tekInsertLines;
    E.Line:= Existing.StartLine - 1; E.Text:= Merged;  { insert AFTER (StartLine-1) => at StartLine }
    Result.Edits:= Result.Edits + [E];
    Result.Action:= daExtended;
  end
  else
  begin
    E:= Default(TTextEdit); E.FilePath:= Path; E.Kind:= tekInsertLines;
    E.Line:= Sym.StartLine - 1; E.Text:= Merged;  { insert above the declaration }
    Result.Edits:= Result.Edits + [E];
    Result.Action:= daCreated;
  end;
end;
```

- [ ] **Step 2: Add the `document` CLI verb**

In `src/cli/DRagLint.CLI.pas`, after `DoGenerateDocs` (ends ~line 6144), add `DoDocument` (template = `DoFindUnit`):

```pascal
// AutoDocument Chunk 1: drag-lint document --qname X [--apply|--json|--no-backup] [--db PATH]
// Generates or repairs a DocInsight comment for the symbol. Dry-run unless --apply.
function DoDocument(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore; Res: DRagLint.Doc.Document.TDocumentResult;
begin
  if AArgs.QName = '' then
  begin Writeln('Usage: drag-lint document --qname X [--apply|--json|--no-backup] [--db PATH]'); Exit(2); end;
  if not FileExists(AArgs.DbPath) then
  begin Writeln(Format('Database not found: %s', [AArgs.DbPath])); Exit(2); end;
  Store:= TSQLiteSymbolStore.Create(AArgs.DbPath); Store.Migrate;
  Res:= DRagLint.Doc.Document.TDocumenter.BuildFor(Store, AArgs.QName);

  if Res.Action = daNotFound then
  begin Writeln(Format('symbol not found: %s', [AArgs.QName])); Exit(1); end;

  if AArgs.Apply and (Length(Res.Edits) > 0) then
    TTextEditApplier.Apply(Res.Edits, not AArgs.NoBackup);

  if AArgs.AsJson then
  begin
    var O: TJSONObject:= TJSONObject.Create;
    try
      O.AddPair('qname', Res.QName);
      O.AddPair('file', Res.FilePath);
      O.AddPair('line', TJSONNumber.Create(Res.Line));
      case Res.Action of
        daCreated  : O.AddPair('action', 'created');
        daExtended : O.AddPair('action', 'extended');
        daUnchanged: O.AddPair('action', 'unchanged');
      else           O.AddPair('action', 'not_found'); end;
      O.AddPair('edits', TJSONNumber.Create(Length(Res.Edits)));
      O.AddPair('applied', TJSONBool.Create(AArgs.Apply and (Length(Res.Edits) > 0)));
      Writeln(O.ToJSON);
    finally O.Free; end;
    Exit(0);
  end;

  if Res.Action = daUnchanged then Writeln('doc: up to date (no change)')
  else if not AArgs.Apply then
  begin
    Writeln(TTextEditApplier.RenderDryRun(Res.Edits));
    Writeln(Format('doc: %d edit(s) -- pass --apply to write', [Length(Res.Edits)]));
  end
  else
    Writeln(Format('doc: %s -- %d edit(s) applied%s',
      [BoolToStr(Res.Action = daCreated, 'created', 'extended'), Length(Res.Edits),
       IfThen(AArgs.NoBackup, '', ' (.bak written)')]));
  Result:= 0;
end;
```

(Adjust `BoolToStr` -- Delphi's takes True/False strings via overload; simplest: `if Res.Action = daCreated then 'created' else 'extended'`.) Add `DRagLint.Doc.Document` to the CLI `uses`.

- [ ] **Step 3: Wire dispatch + usage**

At CLI.pas:10248+ dispatch chain, after the `generate-docs` line, add:
```pascal
    else if Args.Command = 'document'          then Result:= DoDocument       (Args)
```
And add a usage line near CLI.pas:284:
```pascal
  Writeln('  drag-lint document --qname <Foo.TBar.Baz> [--apply|--json|--no-backup] [--db PATH]');
```

- [ ] **Step 4: Build -> exit 0.**

- [ ] **Step 5: Smoke it manually**

From `C:\TEMP`, run `drag-lint document --qname <a known symbol> --db Delphi-RAG-lint.sqlite` and eyeball the dry-run comment. Then commit.

```bash
git add src/doc/DRagLint.Doc.Document.pas src/cli/DRagLint.CLI.pas
git commit -m "feat(autodoc): Doc.Document orchestrator + 'document' CLI verb (--json/--apply)"
```

---

## Task 6: Fixture tests (tests/autodoc)

**Files:**
- Create: `tests/autodoc/fixtures/*.pas` + `tests/autodoc/run_doc_*.ps1` (6 harnesses)

**Interfaces:**
- Consumes: the `document` verb; the staged Win64 exe.

- [ ] **Step 1: Write `run_doc_generate.ps1` + fixture**

Fixture `tests/autodoc/fixtures/doc_generate.pas` (ASCII/CRLF): a unit with a public function `function Add(A, B: Integer): Integer;` (no comment) + a caller. Index it into a scratch db, run `document --qname doc_generate.Add --apply`, assert the inserted comment contains `<summary>TODO: describe.</summary>`, `<param name="A">`, `<param name="B">`, `<returns>`, and (if a caller was indexed) the `<remarks>` fenced block with `Called from:`. Harness shape mirrors `tests/autofix/run_fix_single.ps1` (copy fixture to C:\TEMP scratch, `drag-lint index <dir> --db scratch.sqlite`, run verb, read lines). Watch the PowerShell `"$tag:"` -> `"${tag}:"` gotcha.

- [ ] **Step 2: `run_doc_idempotent.ps1`** -- run `document --apply` twice; assert the file bytes are identical after run 2 (managed regions stable). RED first if `StripManagedBlock` is wrong (double block) -> fix.

- [ ] **Step 3: `run_doc_extend.ps1`** -- fixture with a hand-written `/// <summary>Real prose.</summary>` + a filled `<param>`; after `document --apply`, assert the prose is byte-preserved, a missing `<param>` sentinel was added, and the facts block inserted.

- [ ] **Step 4: `run_doc_stale_param.ps1`** -- fixture whose comment has an `AUTO_PARAM`-marked `<param name="Old">` not in the signature; after regen assert that line is gone; a hand-typed stale param gets the `param no longer exists` flag and is kept.

- [ ] **Step 5: `run_doc_cap.ps1`** -- a fixture project with 16+ callers of one function; assert the `Called from:` line shows 10 refs + `(+6 more)`.

- [ ] **Step 6: `run_doc_verb.ps1`** -- assert `--json` `action` is `created` then `unchanged` on a second run; dry-run (no `--apply`) does not modify the file; `--apply` writes a `.bak`.

- [ ] **Step 7: Run all six -> PASS; commit**

```bash
git add tests/autodoc/
git commit -m "test(autodoc): generate/idempotent/extend/stale-param/cap/verb harnesses"
```

---

## Task 7: IDE "Document it" menu (live-smoke; cut last if oversized)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` (context menu on a symbol node) + the exe-spawn path (shared `DragLintExe` resolver) + reload via `ForceQueue`/`IOTAModule.Refresh` (mirror the "Fix it" wiring from AutoFix Chunk 1).

- [ ] **Step 1** Add a "Document it" item to the structure-tree popup, enabled on a symbol node with a resolvable qname.
- [ ] **Step 2** On click, spawn `document --qname <q> --apply` against the project db (staged Win64 exe); reload the buffer with the deferred `ForceQueue` + `IOTAModule.Refresh` pattern.
- [ ] **Step 3** Build the BPL (RAD Studio CLOSED), deploy via `deploy-staged.bat`, **LIVE SMOKE**: right-click a symbol -> Document it -> the comment appears in the editor.
- [ ] **Step 4** Commit as a SEPARATE `build(plugin):` commit (BPL/DCP not in the release commit).

---

## Task 8: Full battery + publish v0.90.0-alpha

- [ ] **Step 1** Full battery: lint 154/154, store 16/16, autofix 9 suites, all `tests\autodoc\run_doc_*.ps1`.
- [ ] **Step 2** Final whole-branch opus review (superpowers:requesting-code-review) over the diff since the spec commit; fix Critical/Important.
- [ ] **Step 3** Bump `DRagLint.CLI.pas:6` VERSION -> `0.90.0-alpha`; CHANGELOG entry (new units, `document` verb, managed regions, facts sections, IDE menu); BACKLOG resume entry (AutoDocument Chunk 1 shipped; NEXT = Chunk 2 widen to unit/project + gather more doc sources).
- [ ] **Step 4** Rebuild CLI, reindex self (incrementally, the changed files), pack win64+win32 CLI zips (`build\pack-lint-release.ps1 -Version 0.90.0-alpha`).
- [ ] **Step 5** Release commit (CLI.pas + CHANGELOG + BACKLOG only) -> `git tag v0.90.0-alpha` -> push main + tag -> `gh release create v0.90.0-alpha ... --latest` (isPrerelease=false) with the two zips. BPL (if rebuilt) in a SEPARATE `build(plugin):` commit; ZIP is CLI-only.
- [ ] **Step 6** Update auto-memory RESUME + MEMORY.md.

---

## Self-review notes (author)

- **Spec coverage:** managed regions (T4) + facts sections Called-from/Returns (T2) + Calls/Used-in/Raises (T3) + orchestrator/merge (T4/T5) + `document` verb (T5) + tests incl. cap + idempotency + extend + stale (T6) + IDE (T7) + publish (T8). All spec sections mapped.
- **Type consistency:** `TDocFacts`/`TDocFactRef` (T1) used by Facts (T2/T3) and Regions (T4). `TDocumentResult`/`TDocumentAction` (T1) used by orchestrator (T5) and CLI (T5). `MergeComment(AExisting, ASigParams, AFacts, AHasReturn, APrefix)` signature identical in T1 skeleton, T4 impl, T5 call. `DocDisplayCount` (T2) reused in T3. Sentinel consts (`AUTO_BEGIN/END/PARAM`) defined once in Regions (T1).
- **Flagged soft spots (inline):** (1) T3 outgoing-Calls query is verified FIRST with a body-scan fallback -- the section is omittable if unreliable. (2) T5 `Existing.RawBlock` vs `Merged` "unchanged" comparison is normalized-trim; if it proves flaky (whitespace), the idempotency test (T6/S2) will catch it -- switch to comparing only the managed-region content. (3) `ParseReturnType` handles the common `: T` case; generic return types with `:` inside `< >` are rare in this codebase -- acceptable for Chunk 1. (4) DocStub helper export (T4/S1) must not change `generate-docs` behaviour -- it's a visibility move only.
- **Build gotchas encoded:** new-unit dproj + uses (Global Constraints); no literal braces in `{ }` comments; delphi-build recipe; neutral test CWD; `${tag}:` PowerShell escaping.
