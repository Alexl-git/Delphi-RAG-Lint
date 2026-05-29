# v0.19 Type-At-Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development

**Goal:** `drag-lint typeat file:line:col` resolves identifier at position to a symbol from the index (when tractable). Foundation for v0.20 LSP completion and v0.21 OTAPI.

**Architecture:** New `DRagLint.Resolver.TypeAt` module orchestrates SQL queries against the existing symbol index. No new schema.

**Spec:** [docs/superpowers/specs/2026-05-28-v019-type-at-position-design.md](../specs/2026-05-28-v019-type-at-position-design.md)

---

## Task 1: Storage helpers

**Files:**
- Modify: `src/core/DRagLint.Core.Interfaces.pas`
- Modify: `src/storage/DRagLint.Storage.SQLite.pas`

Add to ISymbolStore:
```pascal
function FindContainingSymbol(AFileId: Int64; ALine: Integer): TSymbol;
function FindFileIdByPath(const APath: string): Int64;
function FindSymbolByExactNameAnywhere(const AName: string): TSymbol;
function FindChildSymbolByName(AParentId: Int64;
  const AName: string): TSymbol;
```

`FindContainingSymbol` SQL: `SELECT * FROM symbols WHERE file_id = :fid AND start_line <= :line AND end_line >= :line ORDER BY start_line DESC LIMIT 1`. Returns zero-valued TSymbol if no match.

`FindFileIdByPath`: `SELECT id FROM files WHERE path = :path OR path LIKE :pathLike LIMIT 1`. Returns -1 if not found.

`FindSymbolByExactNameAnywhere`: reuses existing FindSymbolsByExactName, returns first match.

`FindChildSymbolByName`: `SELECT * FROM symbols WHERE parent_id = :pid AND name = :name LIMIT 1`.

Test stubs in CLI to verify methods compile and behave: nothing user-facing, just regression that build works.

Commit: `feat(v0.19): storage helpers for type-at-position`.

---

## Task 2: Resolver module

**Files:**
- Create: `src/resolver/DRagLint.Resolver.TypeAt.pas`
- Modify: `src/cli/drag-lint.dpr` (uses), `src/cli/drag-lint.dproj` (DCCReference)

```pascal
unit DRagLint.Resolver.TypeAt;

interface

uses
  System.SysUtils, System.IOUtils, System.Classes,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TTypeAtResult = record
    File:        string;
    Line:        Integer;
    Col:         Integer;
    Token:       string;
    Containing:  TSymbol;
    HasContain:  Boolean;
    Resolved:    TSymbol;
    HasResolved: Boolean;
    Doc:         TParsedDoc;
    HasDoc:      Boolean;
    Note:        string; // explanation if unresolved
  end;

  TTypeAtResolver = class
  public
    class function Resolve(const AStore: ISymbolStore;
      const AFile: string; ALine, ACol: Integer): TTypeAtResult;
    class function ExtractTokenAt(const ALine: string;
      ACol: Integer; out APrecedingDot: Boolean;
      out ALhs: string): string;
    class function RenderText(const AResult: TTypeAtResult): string;
    class function RenderJson(const AResult: TTypeAtResult): string;
  end;

implementation

class function TTypeAtResolver.ExtractTokenAt(const ALine: string;
  ACol: Integer; out APrecedingDot: Boolean; out ALhs: string): string;
var
  I, Start, EndIdx: Integer;
  Ch: Char;
begin
  Result := '';
  APrecedingDot := False;
  ALhs := '';
  if (ACol < 1) or (ACol > Length(ALine)) then Exit;

  // Walk to start
  Start := ACol;
  while (Start > 1) and CharInSet(ALine[Start - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Dec(Start);

  // Walk to end
  EndIdx := ACol;
  while (EndIdx <= Length(ALine)) and CharInSet(ALine[EndIdx], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(EndIdx);

  if EndIdx > Start then
    Result := Copy(ALine, Start, EndIdx - Start);

  // Check char before token start
  if (Start > 1) and (ALine[Start - 1] = '.') then
  begin
    APrecedingDot := True;
    // Extract LHS identifier (walk left across more identifier chars)
    I := Start - 2;
    while (I >= 1) and CharInSet(ALine[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
      Dec(I);
    ALhs := Copy(ALine, I + 1, Start - 2 - I);
  end;
end;

class function TTypeAtResolver.Resolve(const AStore: ISymbolStore;
  const AFile: string; ALine, ACol: Integer): TTypeAtResult;
var
  Lines: TArray<string>;
  LineText: string;
  PrecedingDot: Boolean;
  LhsText: string;
  FileId: Int64;
  LhsSym: TSymbol;
  ResolvedSym: TSymbol;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.File := AFile;
  Result.Line := ALine;
  Result.Col := ACol;
  Result.Note := '';

  if not FileExists(AFile) then
  begin
    Result.Note := 'File not found.';
    Exit;
  end;
  Lines := TFile.ReadAllLines(AFile, TEncoding.ANSI);
  if (ALine < 1) or (ALine > Length(Lines)) then
  begin
    Result.Note := 'Line out of range.';
    Exit;
  end;
  LineText := Lines[ALine - 1];
  Result.Token := ExtractTokenAt(LineText, ACol, PrecedingDot, LhsText);

  FileId := AStore.FindFileIdByPath(AFile);
  if FileId > 0 then
  begin
    Result.Containing := AStore.FindContainingSymbol(FileId, ALine);
    Result.HasContain := Result.Containing.Id > 0;
  end;

  if Result.Token = '' then
  begin
    Result.Note := 'No identifier at position.';
    Exit;
  end;

  if PrecedingDot and (LhsText <> '') then
  begin
    LhsSym := AStore.FindSymbolByExactNameAnywhere(LhsText);
    if LhsSym.Id > 0 then
    begin
      ResolvedSym := AStore.FindChildSymbolByName(LhsSym.Id, Result.Token);
      if ResolvedSym.Id > 0 then
      begin
        Result.Resolved := ResolvedSym;
        Result.HasResolved := True;
      end
      else
        Result.Note := 'Member ' + Result.Token + ' not found on ' + LhsText + '.';
    end
    else
      Result.Note := 'LHS ' + LhsText + ' unresolved.';
  end
  else
  begin
    ResolvedSym := AStore.FindSymbolByExactNameAnywhere(Result.Token);
    if ResolvedSym.Id > 0 then
    begin
      Result.Resolved := ResolvedSym;
      Result.HasResolved := True;
    end
    else
      Result.Note := 'unresolved (likely a local variable; v0.19 does not infer)';
  end;

  if Result.HasResolved then
  begin
    Result.Doc := AStore.GetSymbolDoc(Result.Resolved.Id);
    Result.HasDoc := Result.Doc.HasContent;
  end;
end;

class function TTypeAtResolver.RenderText(const AResult: TTypeAtResult): string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('File:         ' + AResult.File);
    SB.AppendLine(Format('Position:     line %d, col %d', [AResult.Line, AResult.Col]));
    if AResult.HasContain then
      SB.AppendLine('Containing:   ' + AResult.Containing.QualifiedName);
    if AResult.Token <> '' then
      SB.AppendLine('Token:        ' + AResult.Token);
    if AResult.HasResolved then
    begin
      SB.AppendLine('Resolved:     ' + AResult.Resolved.QualifiedName);
      if AResult.Resolved.Signature <> '' then
        SB.AppendLine('Signature:    ' + AResult.Resolved.Signature);
    end
    else if AResult.Note <> '' then
      SB.AppendLine('Resolved:     ' + AResult.Note);
    if AResult.HasDoc and (AResult.Doc.Summary <> '') then
      SB.AppendLine('Doc:          ' + AResult.Doc.Summary);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TTypeAtResolver.RenderJson(const AResult: TTypeAtResult): string;
begin
  Result := Format(
    '{"file":"%s","line":%d,"col":%d,"token":"%s",' +
    '"containing":"%s","resolved":"%s","signature":"%s","note":"%s"}',
    [StringReplace(AResult.File, '\', '/', [rfReplaceAll]),
     AResult.Line, AResult.Col, AResult.Token,
     AResult.Containing.QualifiedName,
     AResult.Resolved.QualifiedName,
     AResult.Resolved.Signature,
     AResult.Note]);
end;

end.
```

Register in drag-lint.dpr + drag-lint.dproj.

Commit: `feat(v0.19): TTypeAtResolver module`.

---

## Task 3: CLI `drag-lint typeat`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas`
- New: `tests/fixtures/T22_typeat.bat`

Add `Position: string` to TArgs. Parse `<file>:<line>:<col>` from the first positional arg after `typeat`. Call `TTypeAtResolver.Resolve`. Render per `--format`.

`tests/fixtures/T22_typeat.bat`:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t14.sqlite
"%EXE%" typeat %HERE%Calls.pas:17:8 --db "%DB%" > "%HERE%t22_out.txt"
type "%HERE%t22_out.txt"
findstr /c:"Compute" "%HERE%t22_out.txt" >NUL || (echo FAIL: Compute not resolved && exit /b 1)
echo PASS
exit /b 0
```

(t14.sqlite from v0.17 indexes Calls.pas. Verify it exists before running, or have the test index Calls.pas itself.)

Add `typeat` dispatch in Run, PrintHelp.

Commit: `feat(v0.19): drag-lint typeat CLI`.

---

## Task 4: MCP `get_type_at_position` + LSP enrichment

**Files:**
- Modify: `src/mcp/DRagLint.MCP.Server.pas`
- Modify: `src/lsp/DRagLint.LSP.Server.pas`
- New: `tests/fixtures/T23_mcp_typeat.json` + `.bat`

MCP tool descriptor + dispatch.

LSP textDocument/hover: when the symbol at position is found and there's a dotted access pattern, resolve via TTypeAtResolver and include the resolved symbol's info in the hover markdown (under a new "## Type" section).

Commit: `feat(v0.19): MCP get_type_at_position + LSP hover type resolution`.

---

## Task 5: Stitcher + CHANGELOG + README + tag v0.19.0-alpha

- Create `tests/run_v019_doctests.bat` extending v0.18 stitcher with T22-T23.
- Bump VERSION constant to '0.19.0-alpha'.
- CHANGELOG entry.
- README "Type resolution (v0.19)" section.
- Verify, commit, tag locally. DO NOT PUSH.

---

## Stop criteria

1. `drag-lint typeat Calls.pas:17:8` resolves "Compute" to TWidget.Compute (or equivalent unit-qualified name).
2. JSON format returns valid JSON.
3. Containing symbol identified correctly.
4. Unresolved positions return note, not error.
5. v0.16-v0.18 tests still pass.
