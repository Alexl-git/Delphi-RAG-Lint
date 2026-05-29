# v0.18 Context Bundles + Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development

**Goal:** `drag-lint context --task "verb qname"` returns the minimum AI-ready slice; `drag-lint bench-context` benchmarks reduction ratio on real Micronite corpus.

**Architecture:** Composition layer over v0.17's surface/slice/impact/callers + v0.16's docs. No new schema. New `DRagLint.Context.Bundler` module orchestrates.

**Spec:** [docs/superpowers/specs/2026-05-28-v018-context-bundles-design.md](../specs/2026-05-28-v018-context-bundles-design.md)

---

## Task 1: Bundler module + TContextBundle record

**Files:**
- Create: `src/context/DRagLint.Context.Bundler.pas`
- Modify: `src/core/DRagLint.Core.Model.pas` — add TContextBundle record
- Modify: `src/cli/drag-lint.dpr` (uses), `src/cli/drag-lint.dproj` (DCCReference)

- [ ] **Step 1:** Add to Core.Model.pas:
```pascal
TContextBundle = record
  Task:          string;
  Verb:          string;
  QName:         string;
  GeneratedAt:   TDateTime;
  TokenEstimate: Integer;
  Doc:           TParsedDoc;
  HasDoc:        Boolean;
  ClassSurface:  TArray<TSurfaceLine>;
  ImplSlice:     TArray<TSliceChunk>;
  Callers:       TArray<TReference>;
  ImpactSummary: TArray<TImpactLevel>;
end;
```

- [ ] **Step 2:** Create `src/context/DRagLint.Context.Bundler.pas`:
```pascal
unit DRagLint.Context.Bundler;

interface

uses
  System.SysUtils, System.Classes, System.DateUtils, System.StrUtils,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TContextBundler = class
  public
    class function Build(const AStore: ISymbolStore;
      const AVerb, AQName: string;
      ACallerContext, AMaxCallers: Integer;
      AIncludeDocs, AIncludeSurface, AIncludeImpl: Boolean): TContextBundle;
    class function EstimateTokens(const AText: string): Integer;
    class function RenderMarkdown(const ABundle: TContextBundle): string;
    class function RenderJson(const ABundle: TContextBundle): string;
    class function RenderRaw(const ABundle: TContextBundle): string;
  end;

implementation

class function TContextBundler.EstimateTokens(const AText: string): Integer;
begin
  Result := Round(Length(AText) / 3.7);
end;

class function TContextBundler.Build(const AStore: ISymbolStore;
  const AVerb, AQName: string;
  ACallerContext, AMaxCallers: Integer;
  AIncludeDocs, AIncludeSurface, AIncludeImpl: Boolean): TContextBundle;
var
  Syms: TArray<TSymbol>;
  Sym: TSymbol;
  ParentQName: string;
  CallerName: string;
  AllCallers: TArray<TReference>;
  Total: Integer;
  SB: TStringBuilder;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Verb := AVerb;
  Result.QName := AQName;
  Result.GeneratedAt := Now;

  Syms := AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym := Syms[0];

  // Doc
  if AIncludeDocs then
  begin
    Result.Doc := AStore.GetSymbolDoc(Sym.Id);
    Result.HasDoc := Result.Doc.HasContent;
  end;

  // Class surface — parent qname is everything before the last '.'
  if AIncludeSurface then
  begin
    ParentQName := AQName;
    if LastDelimiter('.', ParentQName) > 0 then
      ParentQName := Copy(ParentQName, 1, LastDelimiter('.', ParentQName) - 1);
    if ParentQName <> AQName then
      Result.ClassSurface := AStore.GetClassSurface(ParentQName, False, False);
  end;

  // Impl slice — for methods, use parent class qname for slice
  if AIncludeImpl then
  begin
    if ParentQName <> '' then
      Result.ImplSlice := AStore.GetSymbolSlice(ParentQName)
    else
      Result.ImplSlice := AStore.GetSymbolSlice(AQName);
  end;

  // Callers (truncated)
  CallerName := AQName;
  if LastDelimiter('.', CallerName) > 0 then
    CallerName := Copy(CallerName, LastDelimiter('.', CallerName) + 1, MaxInt);
  AllCallers := AStore.FindCallersByNameWithContext(CallerName, ACallerContext);
  if Length(AllCallers) > AMaxCallers then
    SetLength(AllCallers, AMaxCallers);
  Result.Callers := AllCallers;

  // Impact summary (for refactor/delete)
  if SameText(AVerb, 'refactor') or SameText(AVerb, 'delete') then
    Result.ImpactSummary := AStore.FindTransitiveCallers(CallerName, 2);

  // Compute token estimate
  SB := TStringBuilder.Create;
  try
    if Result.HasDoc then SB.Append(Result.Doc.RawBlock);
    SB.AppendLine; SB.AppendLine;
    // (For estimate, just sum the major text contributions — rough is fine.)
    Total := EstimateTokens(SB.ToString);
    if Length(Result.ClassSurface) > 0 then
      for var L in Result.ClassSurface do
        Inc(Total, EstimateTokens(L.Text));
    if Length(Result.ImplSlice) > 0 then
      for var C in Result.ImplSlice do
        Inc(Total, EstimateTokens(C.Text));
    if Length(Result.Callers) > 0 then
      for var R in Result.Callers do
        Inc(Total, EstimateTokens(R.ContextText));
    Result.TokenEstimate := Total;
  finally
    SB.Free;
  end;
end;

class function TContextBundler.RenderMarkdown(const ABundle: TContextBundle): string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Context bundle: ' + ABundle.Verb + ' ' + ABundle.QName);
    SB.AppendLine;
    SB.AppendLine(Format('> Generated by drag-lint v0.18 at %s',
      [FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', ABundle.GeneratedAt)]));
    SB.AppendLine(Format('> Token count (estimated): %d', [ABundle.TokenEstimate]));
    SB.AppendLine;

    if ABundle.HasDoc then
    begin
      SB.AppendLine('## Doc');
      if ABundle.Doc.Summary <> '' then
        SB.AppendLine('**Summary:** ' + ABundle.Doc.Summary);
      if ABundle.Doc.ReturnsText <> '' then
        SB.AppendLine('**Returns:** ' + ABundle.Doc.ReturnsText);
      if ABundle.Doc.Remarks <> '' then
        SB.AppendLine('**Remarks:** ' + ABundle.Doc.Remarks);
      SB.AppendLine;
    end;

    if Length(ABundle.ClassSurface) > 0 then
    begin
      SB.AppendLine('## Class surface');
      SB.AppendLine('```pascal');
      for var L in ABundle.ClassSurface do
        SB.AppendLine(L.Text);
      SB.AppendLine('```');
      SB.AppendLine;
    end;

    if Length(ABundle.ImplSlice) > 0 then
    begin
      SB.AppendLine('## Impl slice');
      SB.AppendLine('```pascal');
      for var C in ABundle.ImplSlice do
      begin
        SB.AppendLine('// --- ' + C.Kind + ' ---');
        SB.AppendLine(C.Text);
      end;
      SB.AppendLine('```');
      SB.AppendLine;
    end;

    if Length(ABundle.Callers) > 0 then
    begin
      SB.AppendLine(Format('## Callers (%d)', [Length(ABundle.Callers)]));
      for var R in ABundle.Callers do
      begin
        SB.AppendLine(Format('- %s:%d:%d', [R.FilePath, R.StartLine, R.StartCol]));
        if R.ContextText <> '' then
        begin
          SB.AppendLine('  ```');
          SB.AppendLine(R.ContextText);
          SB.AppendLine('  ```');
        end;
      end;
    end;

    if Length(ABundle.ImpactSummary) > 0 then
    begin
      SB.AppendLine('## Impact summary');
      for var L in ABundle.ImpactSummary do
        SB.AppendLine(Format('- Depth %d: %d callers in %d units',
          [L.Depth, L.CallerCount, L.UnitCount]));
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TContextBundler.RenderRaw(const ABundle: TContextBundle): string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    if ABundle.HasDoc then begin SB.AppendLine(ABundle.Doc.RawBlock); SB.AppendLine; end;
    for var L in ABundle.ClassSurface do SB.AppendLine(L.Text);
    SB.AppendLine;
    for var C in ABundle.ImplSlice do SB.AppendLine(C.Text);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TContextBundler.RenderJson(const ABundle: TContextBundle): string;
begin
  // Use a minimal hand-rolled JSON; the schema mirrors the spec.
  Result := Format(
    '{"task":"%s","verb":"%s","qname":"%s","token_estimate":%d,' +
    '"has_doc":%s,"caller_count":%d,"surface_lines":%d,"slice_chunks":%d}',
    [ABundle.Verb + ' ' + ABundle.QName, ABundle.Verb, ABundle.QName,
     ABundle.TokenEstimate,
     IfThen(ABundle.HasDoc, 'true', 'false'),
     Length(ABundle.Callers),
     Length(ABundle.ClassSurface),
     Length(ABundle.ImplSlice)]);
end;

end.
```

- [ ] **Step 3:** Register the new unit in drag-lint.dpr (uses) AND drag-lint.dproj (DCCReference).
- [ ] **Step 4:** Build drag-lint.exe — must compile.
- [ ] **Step 5:** Commit.

---

## Task 2: CLI `drag-lint context`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` — add DoContext, args, dispatch
- New: `tests/fixtures/T19_context.bat`

- [ ] **Step 1:** Add `Task`, `Verb`, `MaxCallers`, `IncludeClassSurface` fields to TArgs. Default verb 'modify', MaxCallers 5, CallerContext 3.

- [ ] **Step 2:** Parse `--task "verb qname"` or `--task "qname"` (default verb = modify). Recognize verbs: modify, inspect, refactor, delete, extend.

- [ ] **Step 3:** Implement DoContext: open store, call TContextBundler.Build, render per --format.

- [ ] **Step 4:** Create T19_context.bat:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" context --task "modify Docs.TDocDemo.GetBaz" --db "%DB%" > "%HERE%t19_out.txt"
type "%HERE%t19_out.txt"
findstr /c:"Token count" "%HERE%t19_out.txt" >NUL || (echo FAIL: no token estimate && exit /b 1)
findstr /c:"GetBaz" "%HERE%t19_out.txt" >NUL || (echo FAIL: target symbol missing && exit /b 1)
echo PASS
exit /b 0
```

- [ ] **Step 5:** Build, T19 PASS, commit.

---

## Task 3: `drag-lint bench-context`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` — add DoBenchContext
- New: `tests/fixtures/T20_bench.bat`

- [ ] **Step 1:** Implement DoBenchContext:
  1. List all documented methods in the DB (FindByDocContains('') or similar).
  2. Pick first N (or random if `--n` given).
  3. For each: build bundle (modify verb), compute bundle token count, compute baseline (read entire source file's char count / 3.7).
  4. Print averages and reduction ratio.

- [ ] **Step 2:** T20_bench.bat:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" bench-context --db "%DB%" --n 3 > "%HERE%t20_out.txt"
type "%HERE%t20_out.txt"
findstr /c:"Reduction" "%HERE%t20_out.txt" >NUL || (echo FAIL: no reduction line && exit /b 1)
echo PASS
exit /b 0
```

- [ ] **Step 3:** Build, T20 PASS, commit.

---

## Task 4: MCP `get_context_bundle` tool

**Files:**
- Modify: `src/mcp/DRagLint.MCP.Server.pas`
- New: `tests/fixtures/T21_mcp_context.json` + `.bat`

- [ ] **Step 1:** Add tool descriptor for `get_context_bundle` with args `{task, qname, db?, format?, caller_context?, max_callers?}`.
- [ ] **Step 2:** Add dispatch branch calling `TContextBundler.Build` + JSON render.
- [ ] **Step 3:** Test fixture invokes tools/call with `get_context_bundle`, asserts JSON contains `token_estimate`.
- [ ] **Step 4:** Build, T21 PASS, commit.

---

## Task 5: Stitcher + CHANGELOG + README + tag v0.18.0-alpha

- [ ] **Step 1:** Create `tests/run_v018_doctests.bat` extending v0.17 with T19-T21.
- [ ] **Step 2:** Bump VERSION constant.
- [ ] **Step 3:** Update CHANGELOG with v0.18 entry. Include benchmark example.
- [ ] **Step 4:** Update README "Token reduction" section.
- [ ] **Step 5:** Run stitcher, expect `*** ALL v0.18 TESTS PASS ***`.
- [ ] **Step 6:** Commit and tag locally `v0.18.0-alpha`. DO NOT PUSH.

---

## Stop criteria

1. `drag-lint context --task "modify Docs.TDocDemo.GetBaz"` returns Markdown with doc, surface, slice, token estimate.
2. `drag-lint context --task "refactor X"` includes impact summary.
3. `drag-lint bench-context --n 3` prints a reduction ratio (any value > 0).
4. MCP `get_context_bundle` works.
5. All v0.16-v0.17 tests still pass.
