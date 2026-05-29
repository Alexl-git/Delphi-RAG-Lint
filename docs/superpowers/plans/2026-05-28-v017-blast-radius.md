# v0.17 Blast-Radius Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add `impact`, `surface`, `slice` CLI commands + `find-callers --context N` flag, plus matching MCP tools. Read-only over existing schema.

**Architecture:** Recursive SQL CTE for transitive callers; line-range slicing over source files for surface/slice; reuse of existing v0.16 storage patterns.

**Tech Stack:** Delphi 13, FireDAC SQLite (WITH RECURSIVE), existing CLI/MCP dispatchers.

**Spec:** [docs/superpowers/specs/2026-05-28-v017-blast-radius-design.md](../specs/2026-05-28-v017-blast-radius-design.md)

---

## File Structure

**Modified:**
- `src/core/DRagLint.Core.Model.pas` — add TImpactLevel, TSurfaceLine, TSliceChunk records
- `src/core/DRagLint.Core.Interfaces.pas` — extend ISymbolStore with 3 methods + signature change for FindCallersByName
- `src/storage/DRagLint.Storage.SQLite.pas` — implement 3 finders + FindCallersByName context support
- `src/cli/DRagLint.CLI.pas` — add impact, surface, slice subcommands + --context arg
- `src/mcp/DRagLint.MCP.Server.pas` — add 3 MCP tools + extend find_callers tool
- `CHANGELOG.md`, `README.md`

**New tests:**
- `tests/fixtures/T14_impact.bat`
- `tests/fixtures/T15_surface.bat`
- `tests/fixtures/T16_slice.bat`
- `tests/fixtures/T17_callers_context.bat`
- `tests/fixtures/T18_mcp_v017.json` + `.bat`

---

## Task 1: Core records + ISymbolStore extensions (stubs)

**Files:**
- Modify: `src/core/DRagLint.Core.Model.pas`
- Modify: `src/core/DRagLint.Core.Interfaces.pas`
- Modify: `src/storage/DRagLint.Storage.SQLite.pas`

- [ ] **Step 1:** Add records to Core.Model.pas:
```pascal
TImpactLevel = record
  Depth, CallerCount, UnitCount: Integer;
  Categories: TArray<string>;
end;

TSurfaceLine = record
  Kind, Text: string;
  StartLine, EndLine: Integer;
end;

TSliceChunk = record
  Kind, Text: string;
  StartLine, EndLine: Integer;
end;
```

- [ ] **Step 2:** Add to ISymbolStore in Core.Interfaces.pas:
```pascal
function FindTransitiveCallers(const ASymbolName: string;
  ADepth: Integer): TArray<TImpactLevel>;
function GetClassSurface(const AQName: string;
  AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine>;
function GetSymbolSlice(const AQName: string): TArray<TSliceChunk>;
function FindCallersByNameWithContext(const ACalleeName: string;
  AContextLines: Integer): TArray<TReference>;
```

- [ ] **Step 3:** Add stub implementations in TSQLiteSymbolStore raising `ENotImplemented` with 'pending Task N' message.

- [ ] **Step 4:** Build drag-lint.exe to confirm clean compile.

- [ ] **Step 5:** Commit:
```
git add src/core/DRagLint.Core.Model.pas src/core/DRagLint.Core.Interfaces.pas src/storage/DRagLint.Storage.SQLite.pas
git commit -m "feat(v0.17): scaffold blast-radius records + ISymbolStore stubs"
```

---

## Task 2: FindTransitiveCallers (impact backend)

**Files:**
- Modify: `src/storage/DRagLint.Storage.SQLite.pas`
- New: `tests/fixtures/T14_impact.bat`

- [ ] **Step 1:** Write failing test. Create `tests/fixtures/T14_impact.bat`:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" impact --qname Docs.TDocDemo.GetBaz --db "%DB%" --depth 2 > "%HERE%t14_out.txt"
type "%HERE%t14_out.txt"
findstr /c:"Depth 1:" "%HERE%t14_out.txt" >NUL || (echo FAIL: no depth 1 output && exit /b 1)
echo PASS
```

- [ ] **Step 2:** Run, expect FAIL (impact command not implemented).

- [ ] **Step 3:** Implement `FindTransitiveCallers` in TSQLiteSymbolStore:
```pascal
function TSQLiteSymbolStore.FindTransitiveCallers(const ASymbolName: string;
  ADepth: Integer): TArray<TImpactLevel>;
const
  CTE_SQL =
    'WITH RECURSIVE caller_walk(level, caller_id, caller_name, file_id) AS (' +
    '  SELECT 1, s2.id, s2.name, s2.file_id ' +
    '    FROM refs r INNER JOIN symbols s2 ON s2.file_id = r.file_id ' +
    '      AND r.start_line BETWEEN s2.start_line AND s2.end_line ' +
    '    WHERE r.name_text = :targetName ' +
    '  UNION ' +
    '  SELECT cw.level + 1, s3.id, s3.name, s3.file_id ' +
    '    FROM caller_walk cw ' +
    '    INNER JOIN refs r2 ON r2.name_text = cw.caller_name ' +
    '    INNER JOIN symbols s3 ON s3.file_id = r2.file_id ' +
    '      AND r2.start_line BETWEEN s3.start_line AND s3.end_line ' +
    '    WHERE cw.level < :maxDepth' +
    ') ' +
    'SELECT level, COUNT(DISTINCT caller_id), COUNT(DISTINCT file_id) ' +
    '  FROM caller_walk GROUP BY level ORDER BY level';
var
  Q: TFDQuery;
  Levels: TList<TImpactLevel>;
  Lvl: TImpactLevel;
begin
  Q := TFDQuery.Create(nil);
  Levels := TList<TImpactLevel>.Create;
  try
    Q.Connection := FConn;
    Q.SQL.Text := CTE_SQL;
    Q.ParamByName('targetName').AsString := ASymbolName;
    Q.ParamByName('maxDepth').AsInteger := ADepth;
    Q.Open;
    while not Q.Eof do
    begin
      Lvl.Depth := Q.Fields[0].AsInteger;
      Lvl.CallerCount := Q.Fields[1].AsInteger;
      Lvl.UnitCount := Q.Fields[2].AsInteger;
      Lvl.Categories := nil;  // populated per-call by categorize helper if needed
      Levels.Add(Lvl);
      Q.Next;
    end;
    Result := Levels.ToArray;
  finally
    Q.Free;
    Levels.Free;
  end;
end;
```

- [ ] **Step 4:** Implement `CmdImpact` in `DRagLint.CLI.pas`:
```pascal
function DoImpact(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Levels: TArray<TImpactLevel>;
  L: TImpactLevel;
  Prev: Integer;
begin
  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  // Pass the short callee name (last segment of qname)
  Levels := Store.FindTransitiveCallers(
    LastSegment(AArgs.QName), AArgs.Depth);
  Writeln(AArgs.QName);
  Prev := 0;
  for L in Levels do
  begin
    if Prev > 0 then
      Writeln(Format('  Depth %d: %3d callers in %d units (+%d)',
        [L.Depth, L.CallerCount, L.UnitCount, L.CallerCount - Prev]))
    else
      Writeln(Format('  Depth %d: %3d callers in %d units',
        [L.Depth, L.CallerCount, L.UnitCount]));
    Prev := L.CallerCount;
  end;
  if Length(Levels) = 0 then
  begin
    Writeln('  (no callers)');
    Exit(1);
  end;
  Result := 0;
end;
```

Add `impact` dispatch in `Run`. Add `Depth` to TArgs with default 3, parse `--depth N`.

Helper `LastSegment`: split qname on '.', return last segment.

- [ ] **Step 5:** Build, re-run T14, expect PASS, commit:
```
git add ...
git commit -m "feat(v0.17): drag-lint impact (transitive callers via WITH RECURSIVE)"
```

---

## Task 3: GetClassSurface (surface backend + CLI)

**Files:**
- Modify: `src/storage/DRagLint.Storage.SQLite.pas`
- Modify: `src/cli/DRagLint.CLI.pas`
- New: `tests/fixtures/T15_surface.bat`

- [ ] **Step 1:** Write failing T15:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" surface --qname Docs.TDocDemo --db "%DB%" > "%HERE%t15_out.txt"
type "%HERE%t15_out.txt"
findstr /c:"TDocDemo = class" "%HERE%t15_out.txt" >NUL || (echo FAIL: class decl missing && exit /b 1)
findstr /c:"function GetBaz" "%HERE%t15_out.txt" >NUL || (echo FAIL: method sig missing && exit /b 1)
findstr /c:"begin Result :=" "%HERE%t15_out.txt" >NUL && (echo FAIL: impl leaked into surface && exit /b 1)
echo PASS
```

- [ ] **Step 2:** Run, expect FAIL.

- [ ] **Step 3:** Implement GetClassSurface:

The simplest correct approach: find the class symbol by qname, get its start_line/end_line, read those lines from the source file. The class body in the interface section is already what we want (Delphi convention: class declaration in interface, bodies in implementation). So GetClassSurface just slices `start_line..end_line` from the file.

```pascal
function TSQLiteSymbolStore.GetClassSurface(const AQName: string;
  AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine>;
var
  Syms: TArray<TSymbol>;
  Sym: TSymbol;
  Lines: TArray<string>;
  I: Integer;
  Line: TSurfaceLine;
  Result_: TList<TSurfaceLine>;
  FilePath: string;
begin
  Syms := FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit(nil);
  Sym := Syms[0];
  if not (Sym.Kind in [skClass, skRecord, skInterface]) then Exit(nil);
  FilePath := GetFilePath(Sym.FileId);
  if not FileExists(FilePath) then Exit(nil);

  Lines := TFile.ReadAllLines(FilePath);
  Result_ := TList<TSurfaceLine>.Create;
  try
    for I := Sym.StartLine to Sym.EndLine do
    begin
      if (I - 1 >= 0) and (I - 1 < Length(Lines)) then
      begin
        Line.Kind := 'source';
        Line.Text := Lines[I - 1];
        Line.StartLine := I;
        Line.EndLine := I;
        // Skip private/protected sections unless AAllVisibility set
        if (not AAllVisibility) and (Pos('private', LowerCase(Trim(Line.Text))) = 1) then
          Continue;
        Result_.Add(Line);
      end;
    end;
    Result := Result_.ToArray;
  finally
    Result_.Free;
  end;
end;
```

(The "skip private" heuristic is naive — proper implementation walks child symbols and filters by their `modifiers` field. For v0.17 the simple line-grep is acceptable; document the limitation.)

- [ ] **Step 4:** Add CLI `DoSurface`. Prints `Text` lines verbatim. Dispatch on `surface` in Run.

- [ ] **Step 5:** Build, T15 PASS, commit:
```
git commit -m "feat(v0.17): drag-lint surface (class interface slice)"
```

---

## Task 4: GetSymbolSlice (slice backend + CLI)

**Files:**
- Modify: `src/storage/DRagLint.Storage.SQLite.pas`
- Modify: `src/cli/DRagLint.CLI.pas`
- New: `tests/fixtures/T16_slice.bat`

- [ ] **Step 1:** Write failing T16:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" slice --qname Docs.TDocDemo --db "%DB%" > "%HERE%t16_out.txt"
type "%HERE%t16_out.txt"
findstr /c:"unit Docs" "%HERE%t16_out.txt" >NUL || (echo FAIL: unit header missing && exit /b 1)
findstr /c:"TDocDemo = class" "%HERE%t16_out.txt" >NUL || (echo FAIL: class decl missing && exit /b 1)
findstr /c:"function TDocDemo.GetBaz" "%HERE%t16_out.txt" >NUL || (echo FAIL: impl method missing && exit /b 1)
echo PASS
```

- [ ] **Step 2:** Run, expect FAIL.

- [ ] **Step 3:** Implement GetSymbolSlice. Strategy:
1. Find class symbol by qname.
2. Read source file.
3. Emit chunks:
   - Unit header: lines 1 through start of `interface` section
   - Class declaration: class symbol's start_line..end_line
   - For each child symbol with parent_id = class.id, emit its impl body if it has one. Find impl body by name match (e.g. `procedure TDocDemo.DoOne`) and emit until next top-level decl or end of file.
   - Unit trailer: `end.` line

```pascal
function TSQLiteSymbolStore.GetSymbolSlice(const AQName: string): TArray<TSliceChunk>;
var
  ClassSym: TSymbol;
  Syms: TArray<TSymbol>;
  Lines: TArray<string>;
  FilePath: string;
  Chunks: TList<TSliceChunk>;
  Chunk: TSliceChunk;
  I, InterfaceStart, ImplStart: Integer;
  Children: TArray<TSymbol>;
  Child: TSymbol;
  ImplPattern: string;
  ImplLine: Integer;
begin
  Syms := FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit(nil);
  ClassSym := Syms[0];
  FilePath := GetFilePath(ClassSym.FileId);
  Lines := TFile.ReadAllLines(FilePath);
  Chunks := TList<TSliceChunk>.Create;
  try
    // Unit header: from line 1 to the line containing 'interface'
    InterfaceStart := 0;
    for I := 0 to High(Lines) do
      if SameText(Trim(Lines[I]), 'interface') then
      begin InterfaceStart := I; Break; end;
    Chunk.Kind := 'unit-header';
    Chunk.StartLine := 1;
    Chunk.EndLine := InterfaceStart + 1;
    Chunk.Text := string.Join(sLineBreak, Lines, 0, InterfaceStart + 1);
    Chunks.Add(Chunk);

    // Class declaration: ClassSym.StartLine..EndLine
    Chunk.Kind := 'class-decl';
    Chunk.StartLine := ClassSym.StartLine;
    Chunk.EndLine := ClassSym.EndLine;
    Chunk.Text := string.Join(sLineBreak, Lines,
      ClassSym.StartLine - 1, ClassSym.EndLine - ClassSym.StartLine + 1);
    Chunks.Add(Chunk);

    // For each child method, find its impl by regex
    Children := FindChildSymbols(ClassSym.Id);
    for Child in Children do
    begin
      if not (Child.Kind in [skMethod, skProcedure, skFunction,
        skConstructor, skDestructor]) then Continue;
      ImplPattern := Format('%s.%s', [ClassSym.Name, Child.Name]);
      ImplLine := FindImplLine(Lines, ImplPattern);
      if ImplLine >= 0 then
      begin
        // Find end of impl (next top-level procedure/function/end. line)
        Chunk.Kind := 'impl-method';
        Chunk.StartLine := ImplLine + 1;
        Chunk.EndLine := FindImplEnd(Lines, ImplLine);
        Chunk.Text := string.Join(sLineBreak, Lines,
          ImplLine, Chunk.EndLine - Chunk.StartLine + 1);
        Chunks.Add(Chunk);
      end;
    end;

    // Unit trailer
    Chunk.Kind := 'unit-trailer';
    Chunk.StartLine := Length(Lines);
    Chunk.EndLine := Length(Lines);
    Chunk.Text := 'end.';
    Chunks.Add(Chunk);

    Result := Chunks.ToArray;
  finally
    Chunks.Free;
  end;
end;
```

Helpers `FindChildSymbols`, `FindImplLine`, `FindImplEnd` — implement as simple linear scans.

- [ ] **Step 4:** Add `DoSlice` CLI handler, prints chunks separated by `--- <kind> ---` lines.

- [ ] **Step 5:** Build, T16 PASS, commit:
```
git commit -m "feat(v0.17): drag-lint slice (symbol-relevant unit chunks)"
```

---

## Task 5: find-callers --context N

**Files:**
- Modify: `src/storage/DRagLint.Storage.SQLite.pas`
- Modify: `src/cli/DRagLint.CLI.pas`
- New: `tests/fixtures/T17_callers_context.bat`

- [ ] **Step 1:** Write failing T17:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" query find-callers --name GetBaz --context 2 --db "%DB%" > "%HERE%t17_out.txt"
type "%HERE%t17_out.txt"
findstr /c:":" "%HERE%t17_out.txt" >NUL || (echo FAIL: callers not listed && exit /b 1)
echo PASS
```

(Note: Docs.pas doesn't actually call GetBaz; this test may need a different fixture. Adapt or create a small fixture that does call it.)

For real verification, use Calls.pas which already has find-callers tests in run_phase1_e2e.bat. Adapt T17 to:
```bat
set DB=%HERE%calls.sqlite
"%EXE%" index "%HERE%Calls.pas" --db "%DB%"
"%EXE%" query find-callers --name Compute --context 2 --db "%DB%" > "%HERE%t17_out.txt"
findstr /c:"Compute" "%HERE%t17_out.txt" >NUL || (echo FAIL: no callers && exit /b 1)
echo PASS
```

- [ ] **Step 2:** Run, expect FAIL.

- [ ] **Step 3:** Extend `FindCallersByName` to optionally include surrounding context. Add a new method `FindCallersByNameWithContext(ACalleeName: string; AContextLines: Integer): TArray<TReference>`. The TReference record may need a `ContextText: string` field added.

- [ ] **Step 4:** Update CLI to parse `--context N` and call the new variant when > 0.

- [ ] **Step 5:** Build, T17 PASS, commit.

---

## Task 6: MCP tools (get_impact / get_surface / get_slice / extended find_callers)

**Files:**
- Modify: `src/mcp/DRagLint.MCP.Server.pas`
- New: `tests/fixtures/T18_mcp_v017.json`, `tests/fixtures/T18_mcp_v017.bat`

- [ ] **Step 1:** Write failing test.
- [ ] **Step 2:** Run, expect FAIL.
- [ ] **Step 3:** Add 3 new tool descriptors + dispatch branches. Extend find_callers with `context` arg.
- [ ] **Step 4:** Build, T18 PASS.
- [ ] **Step 5:** Commit.

---

## Task 7: Update stitcher, CHANGELOG, README, tag v0.17.0-alpha

**Files:**
- Modify: `tests/run_v016_doctests.bat` → `tests/run_v017_doctests.bat` (copy + extend)
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1:** Create `tests/run_v017_doctests.bat` based on the v0.16 stitcher, adding T14-T18.
- [ ] **Step 2:** Update CHANGELOG with v0.17 entry.
- [ ] **Step 3:** Update README with new commands.
- [ ] **Step 4:** Run the full stitcher, expect ALL PASS.
- [ ] **Step 5:** Commit and tag locally `v0.17.0-alpha`.

```
git tag -a v0.17.0-alpha -m "v0.17.0-alpha - blast-radius pack (impact + surface + slice + callers context)"
```

DO NOT push the tag or branch.

---

## Stop criteria for v0.17

1. `drag-lint impact --qname Docs.TDocDemo.GetBaz --depth 2` returns a depth-level summary.
2. `drag-lint surface --qname Docs.TDocDemo` returns the class declaration without impl bodies.
3. `drag-lint slice --qname Docs.TDocDemo` returns unit header + class + only TDocDemo impl methods.
4. `drag-lint query find-callers --name X --context 3` includes 3 lines of context per row.
5. MCP advertises 3 new tools, all callable.
6. v0.16 tests (T1-T13) still pass.
7. All new tests (T14-T18) pass.
