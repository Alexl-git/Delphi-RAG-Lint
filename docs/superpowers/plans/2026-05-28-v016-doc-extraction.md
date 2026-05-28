# v0.16 Doc-Comment Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract Delphi doc comments (XMLDoc, PasDoc, oneline) into a structured `symbol_docs` table at index time, then expose them through CLI / MCP / LSP for rich hover and coverage queries.

**Architecture:** A new `DRagLint.Parser.DocComments` module runs a single regex pass per file to collect comment regions, then per-format tag parsers populate a `TParsedDoc` record. `Parser.Delphi13` associates regions to symbols by line-distance on emit. Storage adds an `UpsertSymbolDoc` keyed by `symbol_id`. Three consumers (CLI `hover`/`find`, MCP `get_symbol_doc`, LSP `textDocument/hover`) read the structured row.

**Tech Stack:** Delphi 13 (RAD Studio 37.0), FireDAC SQLite, tree-sitter-delphi13, modersohn delphi-tree-sitter bindings, regex via `System.RegularExpressions`, MSBuild build pipeline.

**Spec:** [docs/superpowers/specs/2026-05-28-v016-doc-extraction-design.md](../specs/2026-05-28-v016-doc-extraction-design.md)

---

## File Structure

**New files:**
- `src/parser/DRagLint.Parser.DocComments.pas` — comment-region collection + format dispatch + per-format tag parsers
- `src/storage/DRagLint.Storage.DocSchema.pas` — *(option dropped, fold into existing Schema.pas)*
- `tests/fixtures/Docs.pas` — fixture exercising every format
- `tests/run_v016_doctests.bat` — e2e assertion script

**Modified files:**
- `src/storage/DRagLint.Storage.Schema.pas` — add v4 DDL, bump `SCHEMA_VERSION`
- `src/storage/DRagLint.Storage.SQLite.pas` — add `UpsertSymbolDoc`, `DeleteFileDocs`, `GetSymbolDoc`, `FindByDocTag`, `FindUndocumented`, `FindByDocContains`
- `src/core/DRagLint.Core.Model.pas` — add `TParsedDoc`, `TDocCommentRegion`, `TDocCommentKind`, `TDocFormat`
- `src/core/DRagLint.Core.Interfaces.pas` — extend `ISymbolStore`
- `src/parser/DRagLint.Parser.Delphi13.pas` — wire region lookup at symbol emit
- `src/core/DRagLint.Core.Indexer.pas` — call `DeleteFileDocs` in per-file tx
- `src/cli/DRagLint.CLI.pas` — add `hover`, extend `find`
- `src/mcp/DRagLint.MCP.Server.pas` — add 3 MCP tools
- `src/lsp/DRagLint.LSP.Server.pas` — upgrade hover payload
- `src/cli/drag-lint.dpr` + `src/cli/drag-lint.dproj` — register new unit (per repo rule)
- `CHANGELOG.md`, `README.md`

---

## Task 1: Schema migration (v3 → v4)

**Files:**
- Modify: `src/storage/DRagLint.Storage.Schema.pas`
- Test: `tests/run_v016_doctests.bat` (T1 section only)

- [ ] **Step 1: Write the failing assertion**

Create `tests/fixtures/T1_schema.bat`:
```bat
@echo off
setlocal
set EXE=%~dp0..\..\third_party\dll\drag-lint.exe
set DB=%~dp0..\t1.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%~dp0Smoke.pas" --db "%DB%"
sqlite3 "%DB%" "SELECT name FROM sqlite_master WHERE type='table' AND name='symbol_docs';" > "%~dp0t1_actual.txt"
findstr /c:"symbol_docs" "%~dp0t1_actual.txt" >NUL || (echo FAIL: symbol_docs table missing && exit /b 1)
echo PASS
```

- [ ] **Step 2: Run it to verify failure**

```
cd C:\Projects\Delphi-RAG-lint
tests\fixtures\T1_schema.bat
```
Expected: `FAIL: symbol_docs table missing` and exit code 1.

- [ ] **Step 3: Extend the schema**

Edit `src/storage/DRagLint.Storage.Schema.pas`:

Change line 6:
```pascal
  SCHEMA_VERSION = 4;
```

Change line 10 (array bound `[0..11]` → `[0..14]`) and append three new DDL strings before the closing `)`:

```pascal
    ,

    // v4: symbol-level documentation comments (XMLDoc, PasDoc, oneline).
    // One row per documented symbol. Format-tagged so future passes can
    // target a style. raw_block preserves the original text for fallback.
    'CREATE TABLE IF NOT EXISTS symbol_docs (' +
    '  symbol_id        INTEGER PRIMARY KEY REFERENCES symbols(id) ON DELETE CASCADE,' +
    '  format           TEXT NOT NULL,' +
    '  raw_block        TEXT NOT NULL,' +
    '  summary          TEXT,' +
    '  remarks          TEXT,' +
    '  returns_text     TEXT,' +
    '  params_json      TEXT,' +
    '  exceptions_json  TEXT,' +
    '  example_text     TEXT,' +
    '  seealso_json     TEXT,' +
    '  since_text       TEXT,' +
    '  deprecated       INTEGER NOT NULL DEFAULT 0,' +
    '  start_line       INTEGER,' +
    '  end_line         INTEGER' +
    ')',

    'CREATE INDEX IF NOT EXISTS idx_symbol_docs_format ON symbol_docs(format)',

    'CREATE INDEX IF NOT EXISTS idx_symbol_docs_deprecated ' +
    '  ON symbol_docs(deprecated) WHERE deprecated = 1'
```

(`Migrate` in `Storage.SQLite.pas` already iterates `SCHEMA_DDL` with `CREATE ... IF NOT EXISTS`, so v3 DBs upgrade transparently. Verify by reading `Storage.SQLite.pas:Migrate` if unsure.)

- [ ] **Step 4: Build and re-run**

```
build\build_draglint.bat
tests\fixtures\T1_schema.bat
```
Expected: `PASS`.

- [ ] **Step 5: Commit**

```
git add src/storage/DRagLint.Storage.Schema.pas tests/fixtures/T1_schema.bat
git commit -m "feat(v0.16): schema v4 adds symbol_docs table + indexes"
```

---

## Task 2: Core data types

**Files:**
- Modify: `src/core/DRagLint.Core.Model.pas`
- Modify: `src/core/DRagLint.Core.Interfaces.pas`

- [ ] **Step 1: Write the compile-only test**

This task adds types only. The "test" is that `drag-lint.dpr` compiles after the additions and a small program in `tests/fixtures/T2_typecheck.dpr` can construct a `TParsedDoc`.

Create `tests/fixtures/T2_typecheck.dpr`:
```pascal
program T2_typecheck;
{$APPTYPE CONSOLE}
uses
  DRagLint.Core.Model;
var
  P: TParsedDoc;
  R: TDocCommentRegion;
begin
  P.Summary := 'hello';
  R.StartLine := 1;
  R.Kind := dckTripleSlash;
  WriteLn('OK');
end.
```

- [ ] **Step 2: Try to compile, expect failure**

```
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T2_typecheck.dpr -t:Build" 2>&1 | findstr "error"
```
Expected: error about `TParsedDoc` / `TDocCommentRegion` / `dckTripleSlash` undeclared.

- [ ] **Step 3: Add the types**

Append to `src/core/DRagLint.Core.Model.pas` (before `implementation`):

```pascal
type
  TDocCommentKind = (
    dckTripleSlash,       // ///
    dckDoubleSlashOne,    // //1
    dckTripleSlashOne,    // ///1
    dckPasDocCurly,       // {** ... *}
    dckPasDocParen,       // (** ... *)
    dckLooseLine,         // // preceding, no doc marker
    dckLooseBlock         // { ... } preceding, no doc marker
  );

  TDocFormat = (dfXmlDoc, dfPasDoc, dfOneline, dfLoose);

  TDocCommentRegion = record
    StartLine: Integer;
    EndLine:   Integer;
    StartCol:  Integer;   // for trailing-comment detection
    Kind:      TDocCommentKind;
    RawText:   string;
  end;

  TDocParam = record
    Name: string;
    Desc: string;
  end;

  TDocException = record
    TypeName: string;
    Desc:     string;
  end;

  TParsedDoc = record
    Format:      TDocFormat;
    RawBlock:    string;
    Summary:     string;
    Remarks:     string;
    ReturnsText: string;
    Params:      TArray<TDocParam>;
    Exceptions:  TArray<TDocException>;
    ExampleText: string;
    SeeAlso:     TArray<string>;
    SinceText:   string;
    Deprecated:  Boolean;
    StartLine:   Integer;
    EndLine:     Integer;
    HasContent:  Boolean;  // false = empty/garbage block, skip insert
  end;

function DocFormatToStr(AFormat: TDocFormat): string;
function ParamsToJson(const AParams: TArray<TDocParam>): string;
function ExceptionsToJson(const AExceptions: TArray<TDocException>): string;
function SeeAlsoToJson(const ASeeAlso: TArray<string>): string;
```

Implementation block:
```pascal
function DocFormatToStr(AFormat: TDocFormat): string;
begin
  case AFormat of
    dfXmlDoc:  Result := 'xmldoc';
    dfPasDoc:  Result := 'pasdoc';
    dfOneline: Result := 'oneline';
    dfLoose:   Result := 'loose';
  else
    Result := 'unknown';
  end;
end;

function JsonEscape(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8:  Result := Result + '\b';
      #9:  Result := Result + '\t';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
    else
      if C < #32 then
        Result := Result + Format('\u%.4x', [Ord(C)])
      else
        Result := Result + C;
    end;
  end;
end;

function ParamsToJson(const AParams: TArray<TDocParam>): string;
var
  Parts: TArray<string>;
  I: Integer;
begin
  if Length(AParams) = 0 then
    Exit('');
  SetLength(Parts, Length(AParams));
  for I := 0 to High(AParams) do
    Parts[I] := Format('{"name":"%s","desc":"%s"}',
      [JsonEscape(AParams[I].Name), JsonEscape(AParams[I].Desc)]);
  Result := '[' + string.Join(',', Parts) + ']';
end;

function ExceptionsToJson(const AExceptions: TArray<TDocException>): string;
var
  Parts: TArray<string>;
  I: Integer;
begin
  if Length(AExceptions) = 0 then
    Exit('');
  SetLength(Parts, Length(AExceptions));
  for I := 0 to High(AExceptions) do
    Parts[I] := Format('{"type":"%s","desc":"%s"}',
      [JsonEscape(AExceptions[I].TypeName), JsonEscape(AExceptions[I].Desc)]);
  Result := '[' + string.Join(',', Parts) + ']';
end;

function SeeAlsoToJson(const ASeeAlso: TArray<string>): string;
var
  Parts: TArray<string>;
  I: Integer;
begin
  if Length(ASeeAlso) = 0 then
    Exit('');
  SetLength(Parts, Length(ASeeAlso));
  for I := 0 to High(ASeeAlso) do
    Parts[I] := Format('"%s"', [JsonEscape(ASeeAlso[I])]);
  Result := '[' + string.Join(',', Parts) + ']';
end;
```

Extend `src/core/DRagLint.Core.Interfaces.pas` `ISymbolStore` with:

```pascal
procedure UpsertSymbolDoc(const AToken: TFileTxToken;
  ASymbolId: Int64; const ADoc: TParsedDoc);
function GetSymbolDoc(ASymbolId: Int64): TParsedDoc;
function FindByDocTag(const ATag: string): TArray<TSymbol>;
function FindUndocumented(const AKind: string;
  APublicOnly: Boolean): TArray<TSymbol>;
function FindByDocContains(const ASubstring: string): TArray<TSymbol>;
```

- [ ] **Step 4: Compile and run**

```
build\build_draglint.bat
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T2_typecheck.dpr -t:Build -v:minimal"
tests\fixtures\T2_typecheck.exe
```
Expected: prints `OK`.

`drag-lint.exe` will FAIL TO BUILD at this point because `TSQLiteSymbolStore` doesn't yet implement the new `ISymbolStore` methods. That's fine — Task 7 wires those up; until then we stub them.

Actually, to keep the build green between tasks, add stub implementations in `DRagLint.Storage.SQLite.pas` that raise `ENotImplemented`. Append to the class:

```pascal
procedure TSQLiteSymbolStore.UpsertSymbolDoc(const AToken: TFileTxToken;
  ASymbolId: Int64; const ADoc: TParsedDoc);
begin
  raise ENotImplemented.Create('UpsertSymbolDoc: pending Task 7');
end;

function TSQLiteSymbolStore.GetSymbolDoc(ASymbolId: Int64): TParsedDoc;
begin
  raise ENotImplemented.Create('GetSymbolDoc: pending Task 7');
end;

function TSQLiteSymbolStore.FindByDocTag(const ATag: string): TArray<TSymbol>;
begin
  raise ENotImplemented.Create('FindByDocTag: pending Task 7');
end;

function TSQLiteSymbolStore.FindUndocumented(const AKind: string;
  APublicOnly: Boolean): TArray<TSymbol>;
begin
  raise ENotImplemented.Create('FindUndocumented: pending Task 7');
end;

function TSQLiteSymbolStore.FindByDocContains(const ASubstring: string): TArray<TSymbol>;
begin
  raise ENotImplemented.Create('FindByDocContains: pending Task 7');
end;
```

And declare them in the class strict-public section, matching the interface.

- [ ] **Step 5: Commit**

```
git add src/core/DRagLint.Core.Model.pas src/core/DRagLint.Core.Interfaces.pas src/storage/DRagLint.Storage.SQLite.pas tests/fixtures/T2_typecheck.dpr
git commit -m "feat(v0.16): TParsedDoc + TDocCommentRegion types + ISymbolStore stubs"
```

---

## Task 3: Comment-region collector

**Files:**
- Create: `src/parser/DRagLint.Parser.DocComments.pas`
- Modify: `src/cli/drag-lint.dpr` (add unit to uses)
- Modify: `src/cli/drag-lint.dproj` (register unit — repo HARD RULE)
- Create: `tests/fixtures/Docs.pas` (doc-style fixture)
- Create: `tests/fixtures/T3_regions.dpr` (test program)

- [ ] **Step 1: Write the failing test**

Create `tests/fixtures/Docs.pas`:
```pascal
unit Docs;

interface

type
  /// <summary>Demo class for v0.16 doc extraction</summary>
  /// <remarks>Used by tests/run_v016_doctests.bat</remarks>
  TDocDemo = class
  public
    /// <summary>Computes the baz</summary>
    /// <param name="value">input, must be > 0</param>
    /// <returns>the baz</returns>
    /// <exception cref="EArgumentException">when value <= 0</exception>
    function GetBaz(value: Integer): string;

    {**
     * Adds two numbers.
     * @param A first number
     * @param B second number
     * @returns sum
     * @since 1.0
     *}
    function Add(A, B: Integer): Integer;

    ///1 One-liner doc above this method
    procedure DoOne;

    //1 Another one-liner style
    procedure DoTwo;

    /// Plain one-liner without XML
    procedure DoThree;

    FName: string; // user name trailing

    (** Older PasDoc paren style.
        @deprecated use NewProc instead *)
    procedure OldProc;
  end;

implementation

function TDocDemo.GetBaz(value: Integer): string;
begin Result := IntToStr(value); end;

function TDocDemo.Add(A, B: Integer): Integer;
begin Result := A + B; end;

procedure TDocDemo.DoOne;  begin end;
procedure TDocDemo.DoTwo;  begin end;
procedure TDocDemo.DoThree; begin end;
procedure TDocDemo.OldProc; begin end;

end.
```

Create `tests/fixtures/T3_regions.dpr`:
```pascal
program T3_regions;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Parser.DocComments;
var
  Src: string;
  Regions: TList<TDocCommentRegion>;
  R: TDocCommentRegion;
  Counts: array[TDocCommentKind] of Integer;
  K: TDocCommentKind;
begin
  Src := TFile.ReadAllText('tests\fixtures\Docs.pas');
  Regions := TDocCommentScanner.Scan(Src);
  try
    for R in Regions do
      Inc(Counts[R.Kind]);
    WriteLn(Format('tripleSlash=%d doubleSlashOne=%d tripleSlashOne=%d ' +
                   'pasDocCurly=%d pasDocParen=%d looseLine=%d looseBlock=%d',
      [Counts[dckTripleSlash], Counts[dckDoubleSlashOne],
       Counts[dckTripleSlashOne], Counts[dckPasDocCurly],
       Counts[dckPasDocParen], Counts[dckLooseLine], Counts[dckLooseBlock]]));
  finally
    Regions.Free;
  end;
end.
```

- [ ] **Step 2: Try to compile, expect failure**

```
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T3_regions.dpr -t:Build -v:minimal" 2>&1
```
Expected: error about `DRagLint.Parser.DocComments` / `TDocCommentScanner` undeclared.

- [ ] **Step 3: Implement the scanner**

Create `src/parser/DRagLint.Parser.DocComments.pas`:
```pascal
unit DRagLint.Parser.DocComments;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DRagLint.Core.Model;

type
  TDocCommentScanner = class
  public
    /// <summary>Walk the source, return all comment regions sorted by StartLine.</summary>
    class function Scan(const ASource: string): TList<TDocCommentRegion>;
  end;

implementation

type
  TScanState = (ssCode, ssInString, ssInLineComment, ssInBraceComment, ssInParenComment);

class function TDocCommentScanner.Scan(const ASource: string): TList<TDocCommentRegion>;
var
  I, Len: Integer;
  Line, Col: Integer;
  State: TScanState;
  StartLine, StartCol: Integer;
  Buf: TStringBuilder;
  Kind: TDocCommentKind;

  procedure StartLineComment(AKind: TDocCommentKind);
  begin
    State := ssInLineComment;
    StartLine := Line;
    StartCol := Col;
    Kind := AKind;
    Buf.Clear;
  end;

  procedure Emit;
  var
    Region: TDocCommentRegion;
  begin
    Region.StartLine := StartLine;
    Region.EndLine := Line;
    Region.StartCol := StartCol;
    Region.Kind := Kind;
    Region.RawText := Buf.ToString;
    Result.Add(Region);
    Buf.Clear;
  end;

  function Peek(Ahead: Integer): Char;
  begin
    if I + Ahead - 1 <= Len then
      Result := ASource[I + Ahead - 1]
    else
      Result := #0;
  end;

  procedure MergeAdjacentSameKind;
  var
    J: Integer;
    Prev: TDocCommentRegion;
  begin
    J := 1;
    while J < Result.Count do
    begin
      Prev := Result[J - 1];
      if (Result[J].Kind = Prev.Kind) and
         (Result[J].StartLine = Prev.EndLine + 1) and
         (Result[J].Kind in [dckTripleSlash, dckDoubleSlashOne,
                             dckTripleSlashOne, dckLooseLine]) then
      begin
        Prev.EndLine := Result[J].EndLine;
        Prev.RawText := Prev.RawText + sLineBreak + Result[J].RawText;
        Result[J - 1] := Prev;
        Result.Delete(J);
      end
      else
        Inc(J);
    end;
  end;

begin
  Result := TList<TDocCommentRegion>.Create;
  Buf := TStringBuilder.Create;
  try
    Len := Length(ASource);
    I := 1;
    Line := 1;
    Col := 1;
    State := ssCode;
    while I <= Len do
    begin
      case State of
        ssCode:
          begin
            if ASource[I] = '''' then
              State := ssInString
            else if (ASource[I] = '/') and (Peek(2) = '/') then
            begin
              // /// or ///1 or //1 or //
              if Peek(3) = '/' then
              begin
                if Peek(4) = '1' then StartLineComment(dckTripleSlashOne)
                else StartLineComment(dckTripleSlash);
                Inc(I, 3); Inc(Col, 3);
                if Kind = dckTripleSlashOne then begin Inc(I); Inc(Col); end;
                Continue;
              end
              else if Peek(3) = '1' then
              begin
                StartLineComment(dckDoubleSlashOne);
                Inc(I, 3); Inc(Col, 3);
                Continue;
              end
              else
              begin
                StartLineComment(dckLooseLine);
                Inc(I, 2); Inc(Col, 2);
                Continue;
              end;
            end
            else if (ASource[I] = '{') and (Peek(2) = '*') and (Peek(3) = '*') then
            begin
              State := ssInBraceComment;
              StartLine := Line; StartCol := Col;
              Kind := dckPasDocCurly;
              Buf.Clear;
              Inc(I, 3); Inc(Col, 3);
              Continue;
            end
            else if (ASource[I] = '{') then
            begin
              State := ssInBraceComment;
              StartLine := Line; StartCol := Col;
              Kind := dckLooseBlock;
              Buf.Clear;
              Inc(I); Inc(Col);
              Continue;
            end
            else if (ASource[I] = '(') and (Peek(2) = '*') and (Peek(3) = '*') then
            begin
              State := ssInParenComment;
              StartLine := Line; StartCol := Col;
              Kind := dckPasDocParen;
              Buf.Clear;
              Inc(I, 3); Inc(Col, 3);
              Continue;
            end
            else if (ASource[I] = '(') and (Peek(2) = '*') then
            begin
              State := ssInParenComment;
              StartLine := Line; StartCol := Col;
              Kind := dckLooseBlock;
              Buf.Clear;
              Inc(I, 2); Inc(Col, 2);
              Continue;
            end;
          end;
        ssInString:
          if ASource[I] = '''' then State := ssCode;
        ssInLineComment:
          if (ASource[I] = #13) or (ASource[I] = #10) then
          begin
            Emit;
            State := ssCode;
          end
          else
            Buf.Append(ASource[I]);
        ssInBraceComment:
          if ASource[I] = '}' then
          begin
            Emit;
            State := ssCode;
          end
          else
            Buf.Append(ASource[I]);
        ssInParenComment:
          if (ASource[I] = '*') and (Peek(2) = ')') then
          begin
            Emit;
            State := ssCode;
            Inc(I, 2); Inc(Col, 2);
            Continue;
          end
          else
            Buf.Append(ASource[I]);
      end;

      if ASource[I] = #10 then
      begin
        Inc(Line);
        Col := 1;
      end
      else
        Inc(Col);
      Inc(I);
    end;

    // Flush a trailing line comment that hit EOF without newline.
    if State = ssInLineComment then Emit;

    MergeAdjacentSameKind;
  finally
    Buf.Free;
  end;
end;

end.
```

Register the unit in `src/cli/drag-lint.dpr` (uses clause) and in `src/cli/drag-lint.dproj` (search `<DCCReference Include="...\DRagLint.Parser.Delphi13.pas"/>` and add a matching line for `DRagLint.Parser.DocComments.pas`). This is the repo HARD RULE captured in memory `feedback_units_in_dpr_and_dproj.md`.

- [ ] **Step 4: Compile and run**

```
build\build_draglint.bat
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T3_regions.dpr -t:Build -v:minimal"
tests\fixtures\T3_regions.exe
```
Expected output:
```
tripleSlash=2 doubleSlashOne=1 tripleSlashOne=1 pasDocCurly=1 pasDocParen=1 looseLine=1 looseBlock=0
```
(`tripleSlash=2` because XMLDoc on TDocDemo and on GetBaz each merge into one region; `looseLine=1` for the trailing `// user name`.)

- [ ] **Step 5: Commit**

```
git add src/parser/DRagLint.Parser.DocComments.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj tests/fixtures/Docs.pas tests/fixtures/T3_regions.dpr
git commit -m "feat(v0.16): comment-region scanner respects string literals + merges adjacent same-kind"
```

---

## Task 4: XMLDoc tag extraction

**Files:**
- Modify: `src/parser/DRagLint.Parser.DocComments.pas`
- Create: `tests/fixtures/T4_xmldoc.dpr`

- [ ] **Step 1: Write the failing test**

Create `tests/fixtures/T4_xmldoc.dpr`:
```pascal
program T4_xmldoc;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Parser.DocComments;
var
  Raw: string;
  P: TParsedDoc;
begin
  Raw :=
    '<summary>Computes the baz</summary>'#13#10 +
    '<param name="value">input, must be > 0</param>'#13#10 +
    '<returns>the baz</returns>'#13#10 +
    '<exception cref="EArgumentException">when value <= 0</exception>';
  P := TDocCommentParser.ParseXmlDoc(Raw);
  Assert(P.Summary = 'Computes the baz', 'summary='+P.Summary);
  Assert(Length(P.Params) = 1, 'param count');
  Assert(P.Params[0].Name = 'value', 'param name='+P.Params[0].Name);
  Assert(P.Params[0].Desc = 'input, must be > 0', 'param desc='+P.Params[0].Desc);
  Assert(P.ReturnsText = 'the baz', 'returns='+P.ReturnsText);
  Assert(Length(P.Exceptions) = 1, 'exc count');
  Assert(P.Exceptions[0].TypeName = 'EArgumentException', 'exc type');
  Assert(P.HasContent, 'hasContent');
  WriteLn('OK');
end.
```

- [ ] **Step 2: Compile, expect failure**

```
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T4_xmldoc.dpr -t:Build -v:minimal" 2>&1
```
Expected: error about `TDocCommentParser` undeclared.

- [ ] **Step 3: Add the parser**

Edit `src/parser/DRagLint.Parser.DocComments.pas`. In the interface section, add:
```pascal
  TDocCommentParser = class
  public
    class function ParseXmlDoc(const ARaw: string): TParsedDoc; static;
    class function ParsePasDoc(const ARaw: string): TParsedDoc; static;
    class function ParseOneline(const ARaw: string;
      AKind: TDocCommentKind): TParsedDoc; static;
    class function ParseLoose(const ARaw: string): TParsedDoc; static;

    class function StripXmlDocPrefix(const ALine: string): string; static;
    class function CollapseWhitespace(const S: string): string; static;
  end;
```

In implementation, add `System.RegularExpressions` to uses, then:
```pascal
class function TDocCommentParser.StripXmlDocPrefix(const ALine: string): string;
var
  S: string;
begin
  S := TrimLeft(ALine);
  if S.StartsWith('///1') then Result := Copy(S, 5, MaxInt)
  else if S.StartsWith('//1') then Result := Copy(S, 4, MaxInt)
  else if S.StartsWith('///') then Result := Copy(S, 4, MaxInt)
  else if S.StartsWith('//') then Result := Copy(S, 3, MaxInt)
  else Result := S;
  if (Length(Result) > 0) and (Result[1] = ' ') then
    Result := Copy(Result, 2, MaxInt);
end;

class function TDocCommentParser.CollapseWhitespace(const S: string): string;
var
  Re: TRegEx;
begin
  Re := TRegEx.Create('[ \t]+');
  Result := Re.Replace(Trim(S), ' ');
end;

class function TDocCommentParser.ParseXmlDoc(const ARaw: string): TParsedDoc;
var
  Lines: TArray<string>;
  Cleaned, M: string;
  I: Integer;
  RxSummary, RxParam, RxReturns, RxRemarks, RxException, RxExample,
  RxSee, RxSinceTag, RxDeprecatedTag: TRegEx;
  Match: TMatch;
  Matches: TMatchCollection;
  Params: TList<TDocParam>;
  Excs: TList<TDocException>;
  SeeList: TList<string>;
  Param: TDocParam;
  Exc: TDocException;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfXmlDoc;
  Result.RawBlock := ARaw;

  // Strip /// prefix from each line, rejoin with LF for regex matching.
  Lines := ARaw.Split([sLineBreak, #10, #13]);
  Cleaned := '';
  for I := 0 to High(Lines) do
  begin
    if I > 0 then Cleaned := Cleaned + #10;
    Cleaned := Cleaned + StripXmlDocPrefix(Lines[I]);
  end;

  RxSummary := TRegEx.Create('<summary>([\s\S]*?)</summary>', [roIgnoreCase]);
  RxRemarks := TRegEx.Create('<remarks>([\s\S]*?)</remarks>', [roIgnoreCase]);
  RxReturns := TRegEx.Create('<returns>([\s\S]*?)</returns>', [roIgnoreCase]);
  RxExample := TRegEx.Create('<example>([\s\S]*?)</example>', [roIgnoreCase]);
  RxParam := TRegEx.Create('<param\s+name="([^"]+)">([\s\S]*?)</param>', [roIgnoreCase]);
  RxException := TRegEx.Create('<exception\s+cref="([^"]+)">([\s\S]*?)</exception>', [roIgnoreCase]);
  RxSee := TRegEx.Create('<(?:see|seealso)\s+cref="([^"]+)"\s*/?>', [roIgnoreCase]);
  RxSinceTag := TRegEx.Create('<since>([\s\S]*?)</since>', [roIgnoreCase]);
  RxDeprecatedTag := TRegEx.Create('<deprecated\s*/?>', [roIgnoreCase]);

  Match := RxSummary.Match(Cleaned);
  if Match.Success then Result.Summary := CollapseWhitespace(Match.Groups[1].Value);

  Match := RxRemarks.Match(Cleaned);
  if Match.Success then Result.Remarks := CollapseWhitespace(Match.Groups[1].Value);

  Match := RxReturns.Match(Cleaned);
  if Match.Success then Result.ReturnsText := CollapseWhitespace(Match.Groups[1].Value);

  Match := RxExample.Match(Cleaned);
  if Match.Success then Result.ExampleText := Trim(Match.Groups[1].Value);

  Match := RxSinceTag.Match(Cleaned);
  if Match.Success then Result.SinceText := CollapseWhitespace(Match.Groups[1].Value);

  Result.Deprecated := RxDeprecatedTag.IsMatch(Cleaned);

  Params := TList<TDocParam>.Create;
  Excs := TList<TDocException>.Create;
  SeeList := TList<string>.Create;
  try
    Matches := RxParam.Matches(Cleaned);
    for I := 0 to Matches.Count - 1 do
    begin
      Param.Name := Matches[I].Groups[1].Value;
      Param.Desc := CollapseWhitespace(Matches[I].Groups[2].Value);
      Params.Add(Param);
    end;
    Result.Params := Params.ToArray;

    Matches := RxException.Matches(Cleaned);
    for I := 0 to Matches.Count - 1 do
    begin
      Exc.TypeName := Matches[I].Groups[1].Value;
      Exc.Desc := CollapseWhitespace(Matches[I].Groups[2].Value);
      Excs.Add(Exc);
    end;
    Result.Exceptions := Excs.ToArray;

    Matches := RxSee.Matches(Cleaned);
    for I := 0 to Matches.Count - 1 do
      SeeList.Add(Matches[I].Groups[1].Value);
    Result.SeeAlso := SeeList.ToArray;
  finally
    Params.Free;
    Excs.Free;
    SeeList.Free;
  end;

  // Fallback: untagged text before first tag becomes summary.
  if Result.Summary = '' then
  begin
    M := Cleaned;
    I := Pos('<', M);
    if I > 0 then M := Copy(M, 1, I - 1);
    Result.Summary := CollapseWhitespace(M);
  end;

  Result.HasContent :=
    (Result.Summary <> '') or (Result.Remarks <> '') or
    (Result.ReturnsText <> '') or (Length(Result.Params) > 0) or
    (Length(Result.Exceptions) > 0) or Result.Deprecated;
end;

// Stubs for the other parsers — filled in by Tasks 5 & 6.
class function TDocCommentParser.ParsePasDoc(const ARaw: string): TParsedDoc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfPasDoc;
  Result.RawBlock := ARaw;
end;

class function TDocCommentParser.ParseOneline(const ARaw: string;
  AKind: TDocCommentKind): TParsedDoc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfOneline;
  Result.RawBlock := ARaw;
end;

class function TDocCommentParser.ParseLoose(const ARaw: string): TParsedDoc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfLoose;
  Result.RawBlock := ARaw;
end;
```

- [ ] **Step 4: Compile and run**

```
build\build_draglint.bat
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T4_xmldoc.dpr -t:Build -v:minimal"
tests\fixtures\T4_xmldoc.exe
```
Expected: `OK` (no assertion failures).

- [ ] **Step 5: Commit**

```
git add src/parser/DRagLint.Parser.DocComments.pas tests/fixtures/T4_xmldoc.dpr
git commit -m "feat(v0.16): XMLDoc tag extraction (summary/param/returns/remarks/exception/see/since/deprecated)"
```

---

## Task 5: PasDoc tag extraction

**Files:**
- Modify: `src/parser/DRagLint.Parser.DocComments.pas` (`ParsePasDoc`)
- Create: `tests/fixtures/T5_pasdoc.dpr`

- [ ] **Step 1: Write the failing test**

Create `tests/fixtures/T5_pasdoc.dpr`:
```pascal
program T5_pasdoc;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Parser.DocComments;
var
  Raw: string;
  P: TParsedDoc;
begin
  Raw :=
    'Adds two numbers.'#10 +
    '@param A first number'#10 +
    '@param B second number'#10 +
    '@returns sum'#10 +
    '@throws EOverflow on huge values'#10 +
    '@since 1.0'#10 +
    '@deprecated use NewAdd instead';
  P := TDocCommentParser.ParsePasDoc(Raw);
  Assert(P.Summary = 'Adds two numbers.', 'summary='+P.Summary);
  Assert(Length(P.Params) = 2, Format('param count=%d', [Length(P.Params)]));
  Assert(P.Params[0].Name = 'A', 'param0 name');
  Assert(P.Params[0].Desc = 'first number', 'param0 desc');
  Assert(P.ReturnsText = 'sum', 'returns');
  Assert(Length(P.Exceptions) = 1, 'exc count');
  Assert(P.Exceptions[0].TypeName = 'EOverflow', 'exc type');
  Assert(P.SinceText = '1.0', 'since='+P.SinceText);
  Assert(P.Deprecated, 'deprecated');
  WriteLn('OK');
end.
```

- [ ] **Step 2: Compile, run, expect assertion failure**

```
build\build_draglint.bat
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T5_pasdoc.dpr -t:Build -v:minimal"
tests\fixtures\T5_pasdoc.exe
```
Expected: `EAssertionFailed: summary=`.

- [ ] **Step 3: Implement ParsePasDoc**

Replace the `ParsePasDoc` stub in `src/parser/DRagLint.Parser.DocComments.pas` with:
```pascal
class function TDocCommentParser.ParsePasDoc(const ARaw: string): TParsedDoc;
var
  Cleaned, Body, SummaryPart, Rest, TagName, TagArg, TagRest: string;
  Lines, BodyLines: TArray<string>;
  I, BlankIdx, TagStart: Integer;
  Params: TList<TDocParam>;
  Excs: TList<TDocException>;
  SeeList: TList<string>;
  Param: TDocParam;
  Exc: TDocException;
  RxTag: TRegEx;
  Match: TMatch;
  AccTag, AccVal: string;

  procedure FlushTag;
  var
    P2: TDocParam;
    E2: TDocException;
    Tag, Arg, ValRest: string;
    SpaceIdx: Integer;
    Val: string;
  begin
    if AccTag = '' then Exit;
    Val := Trim(AccVal);
    Tag := LowerCase(AccTag);
    if (Tag = 'param') then
    begin
      SpaceIdx := Pos(' ', Val);
      if SpaceIdx > 0 then
      begin
        P2.Name := Copy(Val, 1, SpaceIdx - 1);
        P2.Desc := Trim(Copy(Val, SpaceIdx + 1, MaxInt));
      end
      else
      begin
        P2.Name := Val;
        P2.Desc := '';
      end;
      Params.Add(P2);
    end
    else if (Tag = 'returns') or (Tag = 'return') then
      Result.ReturnsText := Val
    else if (Tag = 'throws') or (Tag = 'raises') then
    begin
      SpaceIdx := Pos(' ', Val);
      if SpaceIdx > 0 then
      begin
        E2.TypeName := Copy(Val, 1, SpaceIdx - 1);
        E2.Desc := Trim(Copy(Val, SpaceIdx + 1, MaxInt));
      end
      else
      begin
        E2.TypeName := Val;
        E2.Desc := '';
      end;
      Excs.Add(E2);
    end
    else if Tag = 'remarks' then Result.Remarks := Val
    else if Tag = 'example' then Result.ExampleText := Val
    else if Tag = 'see' then
    begin
      // @see A, B, C
      for ValRest in Val.Split([',']) do
      begin
        Arg := Trim(ValRest);
        if Arg <> '' then SeeList.Add(Arg);
      end;
    end
    else if Tag = 'since' then Result.SinceText := Val
    else if Tag = 'deprecated' then Result.Deprecated := True
    else if (Tag = 'author') or (Tag = 'version') then
    begin
      // Roll into remarks
      if Result.Remarks <> '' then Result.Remarks := Result.Remarks + #10;
      Result.Remarks := Result.Remarks + AccTag + ': ' + Val;
    end;
    AccTag := '';
    AccVal := '';
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfPasDoc;
  Result.RawBlock := ARaw;
  Params := TList<TDocParam>.Create;
  Excs := TList<TDocException>.Create;
  SeeList := TList<string>.Create;
  try
    // Strip leading `*` from each line (common in PasDoc blocks)
    Lines := ARaw.Split([sLineBreak, #10, #13]);
    Cleaned := '';
    for I := 0 to High(Lines) do
    begin
      Body := TrimLeft(Lines[I]);
      if Body.StartsWith('* ') then Body := Copy(Body, 3, MaxInt)
      else if Body.StartsWith('*') then Body := Copy(Body, 2, MaxInt);
      if I > 0 then Cleaned := Cleaned + #10;
      Cleaned := Cleaned + Body;
    end;
    Cleaned := Trim(Cleaned);

    // Summary = text before first @tag (or before first blank line, whichever earlier)
    RxTag := TRegEx.Create('(?m)^\s*@(\w+)\b\s*(.*)$');
    Match := RxTag.Match(Cleaned);
    if Match.Success then
      SummaryPart := Trim(Copy(Cleaned, 1, Match.Index - 1))
    else
      SummaryPart := Cleaned;

    // Trim summary at first blank line
    BlankIdx := Pos(#10#10, SummaryPart);
    if BlankIdx > 0 then SummaryPart := Trim(Copy(SummaryPart, 1, BlankIdx - 1));
    Result.Summary := CollapseWhitespace(SummaryPart);

    // Walk @tag blocks
    BodyLines := Cleaned.Split([#10]);
    AccTag := '';
    AccVal := '';
    for I := 0 to High(BodyLines) do
    begin
      Match := RxTag.Match(BodyLines[I]);
      if Match.Success then
      begin
        FlushTag;
        AccTag := Match.Groups[1].Value;
        AccVal := Match.Groups[2].Value;
      end
      else if AccTag <> '' then
      begin
        if Trim(BodyLines[I]) = '' then FlushTag
        else
          AccVal := AccVal + ' ' + Trim(BodyLines[I]);
      end;
    end;
    FlushTag;

    Result.Params := Params.ToArray;
    Result.Exceptions := Excs.ToArray;
    Result.SeeAlso := SeeList.ToArray;

    Result.HasContent :=
      (Result.Summary <> '') or (Length(Result.Params) > 0) or
      (Result.ReturnsText <> '') or Result.Deprecated;
  finally
    Params.Free;
    Excs.Free;
    SeeList.Free;
  end;
end;
```

- [ ] **Step 4: Build and re-run**

```
build\build_draglint.bat
tests\fixtures\T5_pasdoc.exe
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```
git add src/parser/DRagLint.Parser.DocComments.pas tests/fixtures/T5_pasdoc.dpr
git commit -m "feat(v0.16): PasDoc tag extraction (@param/@returns/@throws/@since/@deprecated/etc)"
```

---

## Task 6: Oneline + Loose handling + format dispatch

**Files:**
- Modify: `src/parser/DRagLint.Parser.DocComments.pas`
- Create: `tests/fixtures/T6_dispatch.dpr`

- [ ] **Step 1: Write the failing test**

Create `tests/fixtures/T6_dispatch.dpr`:
```pascal
program T6_dispatch;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Parser.DocComments;
var
  P: TParsedDoc;
  Region: TDocCommentRegion;
begin
  // Oneline: triple-slash with no XML tags
  Region.Kind := dckTripleSlash;
  Region.RawText := '/// Plain one-liner doc';
  P := TDocCommentParser.Dispatch(Region);
  Assert(P.Format = dfOneline, 'oneline format');
  Assert(P.Summary = 'Plain one-liner doc', 'oneline summary='+P.Summary);

  // Oneline: //1 style
  Region.Kind := dckDoubleSlashOne;
  Region.RawText := '//1 Another oneliner';
  P := TDocCommentParser.Dispatch(Region);
  Assert(P.Format = dfOneline, '//1 format');
  Assert(P.Summary = 'Another oneliner', '//1 summary='+P.Summary);

  // Triple-slash WITH XML tags -> xmldoc
  Region.Kind := dckTripleSlash;
  Region.RawText := '/// <summary>X</summary>';
  P := TDocCommentParser.Dispatch(Region);
  Assert(P.Format = dfXmlDoc, 'xmldoc format');

  // PasDoc curly
  Region.Kind := dckPasDocCurly;
  Region.RawText := 'Hello' + #10 + '@returns world';
  P := TDocCommentParser.Dispatch(Region);
  Assert(P.Format = dfPasDoc, 'pasdoc format');
  Assert(P.Summary = 'Hello', 'pasdoc summary='+P.Summary);

  // Loose with noise (TODO line)
  Region.Kind := dckLooseLine;
  Region.RawText := '// TODO: not a real doc';
  P := TDocCommentParser.Dispatch(Region);
  Assert(not P.HasContent, 'loose noise dropped');

  WriteLn('OK');
end.
```

- [ ] **Step 2: Compile, expect Dispatch undeclared**

```
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T6_dispatch.dpr -t:Build -v:minimal" 2>&1
```
Expected: error about `Dispatch` undeclared.

- [ ] **Step 3: Add Dispatch + ParseOneline + ParseLoose**

In `src/parser/DRagLint.Parser.DocComments.pas`, add to `TDocCommentParser`:
```pascal
class function Dispatch(const ARegion: TDocCommentRegion): TParsedDoc; static;
```

Implementation:
```pascal
class function TDocCommentParser.ParseOneline(const ARaw: string;
  AKind: TDocCommentKind): TParsedDoc;
var
  Lines: TArray<string>;
  Acc: TStringBuilder;
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfOneline;
  Result.RawBlock := ARaw;
  Lines := ARaw.Split([sLineBreak, #10, #13]);
  Acc := TStringBuilder.Create;
  try
    for I := 0 to High(Lines) do
    begin
      if Acc.Length > 0 then Acc.Append(' ');
      Acc.Append(StripXmlDocPrefix(Lines[I]));
    end;
    Result.Summary := CollapseWhitespace(Acc.ToString);
  finally
    Acc.Free;
  end;
  Result.HasContent := Result.Summary <> '';
end;

class function TDocCommentParser.ParseLoose(const ARaw: string): TParsedDoc;
const
  NOISE_PREFIXES: array[0..9] of string = (
    'TODO', 'FIXME', 'HACK', 'XXX', 'REVIEW',
    '=====', '-----', '#####', 'Copyright', '(c)'
  );
var
  Lines: TArray<string>;
  I, NoiseCount, TotalCount: Integer;
  Stripped: string;
  Noise: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfLoose;
  Result.RawBlock := ARaw;

  Lines := ARaw.Split([sLineBreak, #10, #13]);
  NoiseCount := 0;
  TotalCount := 0;
  for I := 0 to High(Lines) do
  begin
    Stripped := TrimLeft(Lines[I]);
    if Stripped = '' then Continue;
    Inc(TotalCount);
    for Noise in NOISE_PREFIXES do
      if StartsText(Noise, Stripped) then
      begin
        Inc(NoiseCount);
        Break;
      end;
  end;

  if (TotalCount > 0) and (NoiseCount * 2 > TotalCount) then
  begin
    Result.HasContent := False;
    Exit;
  end;

  // Treat like oneline
  Result := ParseOneline(ARaw, dckLooseLine);
  Result.Format := dfLoose;
end;

class function TDocCommentParser.Dispatch(const ARegion: TDocCommentRegion): TParsedDoc;
var
  HasXmlTags: Boolean;
begin
  case ARegion.Kind of
    dckTripleSlash:
      begin
        HasXmlTags := (Pos('<summary>', ARegion.RawText) > 0) or
                      (Pos('<param', ARegion.RawText) > 0) or
                      (Pos('<returns>', ARegion.RawText) > 0) or
                      (Pos('<remarks>', ARegion.RawText) > 0) or
                      (Pos('<exception', ARegion.RawText) > 0) or
                      (Pos('<example>', ARegion.RawText) > 0);
        if HasXmlTags then
          Result := ParseXmlDoc(ARegion.RawText)
        else
          Result := ParseOneline(ARegion.RawText, ARegion.Kind);
      end;
    dckDoubleSlashOne, dckTripleSlashOne:
      Result := ParseOneline(ARegion.RawText, ARegion.Kind);
    dckPasDocCurly, dckPasDocParen:
      Result := ParsePasDoc(ARegion.RawText);
    dckLooseLine, dckLooseBlock:
      Result := ParseLoose(ARegion.RawText);
  end;
  Result.StartLine := ARegion.StartLine;
  Result.EndLine := ARegion.EndLine;
end;
```

(Add `System.StrUtils` to the implementation `uses` clause for `StartsText`.)

- [ ] **Step 4: Build and run**

```
build\build_draglint.bat
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T6_dispatch.dpr -t:Build -v:minimal"
tests\fixtures\T6_dispatch.exe
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```
git add src/parser/DRagLint.Parser.DocComments.pas tests/fixtures/T6_dispatch.dpr
git commit -m "feat(v0.16): format dispatch + oneline + loose-noise filter"
```

---

## Task 7: Storage layer — UpsertSymbolDoc + queries

**Files:**
- Modify: `src/storage/DRagLint.Storage.SQLite.pas`
- Create: `tests/fixtures/T7_storage.dpr`

- [ ] **Step 1: Write the failing test**

Create `tests/fixtures/T7_storage.dpr`:
```pascal
program T7_storage;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite;
var
  Store: ISymbolStore;
  Doc, Out: TParsedDoc;
  Sym: TSymbol;
  Tok: TFileTxToken;
  Id: Int64;
const
  DB_PATH = 'tests\t7.sqlite';
begin
  if FileExists(DB_PATH) then DeleteFile(DB_PATH);

  Store := TSQLiteSymbolStore.Create(DB_PATH);
  Store.Migrate;

  Tok := Store.OpenFileTx('virt.pas', 0, 'sha', 'delphi13');
  Sym.Kind := skMethod;
  Sym.Name := 'Foo';
  Sym.QualifiedName := 'U.Foo';
  Sym.StartLine := 10; Sym.StartCol := 1; Sym.EndLine := 12; Sym.EndCol := 5;
  Id := Store.UpsertSymbol(Tok, Sym);

  FillChar(Doc, SizeOf(Doc), 0);
  Doc.Format := dfXmlDoc;
  Doc.RawBlock := '/// <summary>S</summary>';
  Doc.Summary := 'S';
  Doc.StartLine := 8; Doc.EndLine := 9;
  Doc.HasContent := True;
  Store.UpsertSymbolDoc(Tok, Id, Doc);
  Store.CommitFileTx(Tok);

  Out := Store.GetSymbolDoc(Id);
  Assert(Out.Summary = 'S', 'roundtrip summary='+Out.Summary);
  Assert(Out.Format = dfXmlDoc, 'roundtrip format');
  WriteLn('OK');
end.
```

- [ ] **Step 2: Compile, run, expect ENotImplemented**

```
build\build_draglint.bat
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild tests/fixtures/T7_storage.dpr -t:Build -v:minimal"
tests\fixtures\T7_storage.exe
```
Expected: `ENotImplemented: UpsertSymbolDoc: pending Task 7`.

- [ ] **Step 3: Implement the storage methods**

In `src/storage/DRagLint.Storage.SQLite.pas`:

Add private fields:
```pascal
FQUpsertSymbolDoc: TFDQuery;
FQDeleteFileDocs: TFDQuery;
FQGetSymbolDoc: TFDQuery;
FQFindByDocTag: TFDQuery;
FQFindUndocumented: TFDQuery;
FQFindByDocContains: TFDQuery;
```

In `PrepareStatements`, after the existing prepared queries:
```pascal
FQUpsertSymbolDoc := TFDQuery.Create(nil);
FQUpsertSymbolDoc.Connection := FConn;
FQUpsertSymbolDoc.SQL.Text :=
  'INSERT OR REPLACE INTO symbol_docs ' +
  '(symbol_id, format, raw_block, summary, remarks, returns_text, ' +
  ' params_json, exceptions_json, example_text, seealso_json, since_text, ' +
  ' deprecated, start_line, end_line) ' +
  'VALUES (:sid, :fmt, :raw, :sum, :rem, :ret, :pj, :ej, :ex, :sj, :since, ' +
  ' :dep, :sl, :el)';
FQUpsertSymbolDoc.Prepare;

FQDeleteFileDocs := TFDQuery.Create(nil);
FQDeleteFileDocs.Connection := FConn;
FQDeleteFileDocs.SQL.Text :=
  'DELETE FROM symbol_docs WHERE symbol_id IN ' +
  '(SELECT id FROM symbols WHERE file_id = :fid)';
FQDeleteFileDocs.Prepare;

FQGetSymbolDoc := TFDQuery.Create(nil);
FQGetSymbolDoc.Connection := FConn;
FQGetSymbolDoc.SQL.Text :=
  'SELECT format, raw_block, summary, remarks, returns_text, ' +
  ' params_json, exceptions_json, example_text, seealso_json, since_text, ' +
  ' deprecated, start_line, end_line ' +
  'FROM symbol_docs WHERE symbol_id = :sid';
FQGetSymbolDoc.Prepare;

FQFindByDocTag := TFDQuery.Create(nil);
FQFindByDocTag.Connection := FConn;
// 'deprecated' = boolean column; 'since' = since_text NOT NULL
FQFindByDocTag.SQL.Text :=
  'SELECT s.* FROM symbols s INNER JOIN symbol_docs d ON d.symbol_id = s.id ' +
  'WHERE (:tag = ''deprecated'' AND d.deprecated = 1) ' +
  '   OR (:tag = ''since'' AND d.since_text IS NOT NULL) ' +
  '   OR (:tag = ''undocumented'' AND 1=0)';
FQFindByDocTag.Prepare;

FQFindUndocumented := TFDQuery.Create(nil);
FQFindUndocumented.Connection := FConn;
FQFindUndocumented.SQL.Text :=
  'SELECT s.* FROM symbols s ' +
  'LEFT JOIN symbol_docs d ON d.symbol_id = s.id ' +
  'WHERE d.symbol_id IS NULL ' +
  '  AND (:kind = '''' OR s.kind = :kind) ' +
  '  AND (:publicOnly = 0 OR (s.modifiers IS NULL ' +
  '       OR (s.modifiers NOT LIKE ''%private%'' AND ' +
  '           s.modifiers NOT LIKE ''%protected%'')))';
FQFindUndocumented.Prepare;

FQFindByDocContains := TFDQuery.Create(nil);
FQFindByDocContains.Connection := FConn;
FQFindByDocContains.SQL.Text :=
  'SELECT s.* FROM symbols s INNER JOIN symbol_docs d ON d.symbol_id = s.id ' +
  'WHERE d.summary LIKE :pat OR d.remarks LIKE :pat OR d.example_text LIKE :pat';
FQFindByDocContains.Prepare;
```

Replace the stub `UpsertSymbolDoc` etc. with real bodies:
```pascal
procedure TSQLiteSymbolStore.UpsertSymbolDoc(const AToken: TFileTxToken;
  ASymbolId: Int64; const ADoc: TParsedDoc);
begin
  if not ADoc.HasContent then Exit;
  FQUpsertSymbolDoc.ParamByName('sid').AsLargeInt := ASymbolId;
  FQUpsertSymbolDoc.ParamByName('fmt').AsString := DocFormatToStr(ADoc.Format);
  FQUpsertSymbolDoc.ParamByName('raw').AsString := ADoc.RawBlock;

  // Nullable text params — set DataType BEFORE Clear (FireDAC gotcha
  // recorded in memory project_mstreams_a1_serialization and elsewhere).
  with FQUpsertSymbolDoc.ParamByName('sum') do
  begin DataType := ftWideMemo; if ADoc.Summary = '' then Clear else AsString := ADoc.Summary; end;
  with FQUpsertSymbolDoc.ParamByName('rem') do
  begin DataType := ftWideMemo; if ADoc.Remarks = '' then Clear else AsString := ADoc.Remarks; end;
  with FQUpsertSymbolDoc.ParamByName('ret') do
  begin DataType := ftWideMemo; if ADoc.ReturnsText = '' then Clear else AsString := ADoc.ReturnsText; end;
  with FQUpsertSymbolDoc.ParamByName('pj') do
  begin DataType := ftWideMemo;
    if Length(ADoc.Params) = 0 then Clear else AsString := ParamsToJson(ADoc.Params);
  end;
  with FQUpsertSymbolDoc.ParamByName('ej') do
  begin DataType := ftWideMemo;
    if Length(ADoc.Exceptions) = 0 then Clear else AsString := ExceptionsToJson(ADoc.Exceptions);
  end;
  with FQUpsertSymbolDoc.ParamByName('ex') do
  begin DataType := ftWideMemo; if ADoc.ExampleText = '' then Clear else AsString := ADoc.ExampleText; end;
  with FQUpsertSymbolDoc.ParamByName('sj') do
  begin DataType := ftWideMemo;
    if Length(ADoc.SeeAlso) = 0 then Clear else AsString := SeeAlsoToJson(ADoc.SeeAlso);
  end;
  with FQUpsertSymbolDoc.ParamByName('since') do
  begin DataType := ftWideMemo; if ADoc.SinceText = '' then Clear else AsString := ADoc.SinceText; end;

  FQUpsertSymbolDoc.ParamByName('dep').AsInteger := Ord(ADoc.Deprecated);
  FQUpsertSymbolDoc.ParamByName('sl').AsInteger := ADoc.StartLine;
  FQUpsertSymbolDoc.ParamByName('el').AsInteger := ADoc.EndLine;
  FQUpsertSymbolDoc.ExecSQL;
end;

procedure TSQLiteSymbolStore.DeleteFileDocs(AFileId: Int64);
begin
  FQDeleteFileDocs.ParamByName('fid').AsLargeInt := AFileId;
  FQDeleteFileDocs.ExecSQL;
end;

function TSQLiteSymbolStore.GetSymbolDoc(ASymbolId: Int64): TParsedDoc;
begin
  FillChar(Result, SizeOf(Result), 0);
  FQGetSymbolDoc.ParamByName('sid').AsLargeInt := ASymbolId;
  FQGetSymbolDoc.Open;
  try
    if FQGetSymbolDoc.IsEmpty then Exit;
    // map format string -> enum
    case IndexStr(FQGetSymbolDoc.FieldByName('format').AsString,
                  ['xmldoc', 'pasdoc', 'oneline', 'loose']) of
      0: Result.Format := dfXmlDoc;
      1: Result.Format := dfPasDoc;
      2: Result.Format := dfOneline;
      3: Result.Format := dfLoose;
    end;
    Result.RawBlock    := FQGetSymbolDoc.FieldByName('raw_block').AsString;
    Result.Summary     := FQGetSymbolDoc.FieldByName('summary').AsString;
    Result.Remarks     := FQGetSymbolDoc.FieldByName('remarks').AsString;
    Result.ReturnsText := FQGetSymbolDoc.FieldByName('returns_text').AsString;
    Result.ExampleText := FQGetSymbolDoc.FieldByName('example_text').AsString;
    Result.SinceText   := FQGetSymbolDoc.FieldByName('since_text').AsString;
    Result.Deprecated  := FQGetSymbolDoc.FieldByName('deprecated').AsInteger = 1;
    Result.StartLine   := FQGetSymbolDoc.FieldByName('start_line').AsInteger;
    Result.EndLine     := FQGetSymbolDoc.FieldByName('end_line').AsInteger;
    // Params/Exceptions/SeeAlso parsing from JSON deferred — consumers either
    // get them via raw_block or via params_json field directly. (v0.16 stop:
    // hover renderer reads params_json string as-is, formats inline.)
    Result.HasContent  := True;
  finally
    FQGetSymbolDoc.Close;
  end;
end;

function TSQLiteSymbolStore.FindByDocTag(const ATag: string): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
  Sym: TSymbol;
begin
  Acc := TList<TSymbol>.Create;
  try
    FQFindByDocTag.ParamByName('tag').AsString := LowerCase(ATag);
    FQFindByDocTag.Open;
    try
      while not FQFindByDocTag.Eof do
      begin
        ReadSymbolFromQuery(FQFindByDocTag, Sym);  // helper, define below
        Acc.Add(Sym);
        FQFindByDocTag.Next;
      end;
    finally
      FQFindByDocTag.Close;
    end;
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function TSQLiteSymbolStore.FindUndocumented(const AKind: string;
  APublicOnly: Boolean): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
  Sym: TSymbol;
begin
  Acc := TList<TSymbol>.Create;
  try
    FQFindUndocumented.ParamByName('kind').AsString := AKind;
    FQFindUndocumented.ParamByName('publicOnly').AsInteger := Ord(APublicOnly);
    FQFindUndocumented.Open;
    try
      while not FQFindUndocumented.Eof do
      begin
        ReadSymbolFromQuery(FQFindUndocumented, Sym);
        Acc.Add(Sym);
        FQFindUndocumented.Next;
      end;
    finally
      FQFindUndocumented.Close;
    end;
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function TSQLiteSymbolStore.FindByDocContains(const ASubstring: string): TArray<TSymbol>;
var
  Acc: TList<TSymbol>;
  Sym: TSymbol;
begin
  Acc := TList<TSymbol>.Create;
  try
    FQFindByDocContains.ParamByName('pat').AsString := '%' + ASubstring + '%';
    FQFindByDocContains.Open;
    try
      while not FQFindByDocContains.Eof do
      begin
        ReadSymbolFromQuery(FQFindByDocContains, Sym);
        Acc.Add(Sym);
        FQFindByDocContains.Next;
      end;
    finally
      FQFindByDocContains.Close;
    end;
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;
```

`ReadSymbolFromQuery` is an existing private helper in the unit. If it doesn't exist (verify by reading the file), factor the row-to-TSymbol mapping that `FindSymbolsByExactName` uses into a `procedure ReadSymbolFromQuery(AQ: TFDQuery; out ASym: TSymbol)` and reuse.

Add `DeleteFileDocs` declaration to `ISymbolStore` (and a stub call in `Destroy` to free the new TFDQuery instances).

- [ ] **Step 4: Build and run**

```
build\build_draglint.bat
tests\fixtures\T7_storage.exe
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```
git add src/storage/DRagLint.Storage.SQLite.pas src/core/DRagLint.Core.Interfaces.pas tests/fixtures/T7_storage.dpr
git commit -m "feat(v0.16): storage layer — UpsertSymbolDoc + GetSymbolDoc + 3 finder queries"
```

---

## Task 8: Parser integration — associate region to symbol

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas`
- Modify: `src/core/DRagLint.Core.Indexer.pas`
- Create: `tests/fixtures/T8_e2e.bat`

- [ ] **Step 1: Write the failing test**

Create `tests/fixtures/T8_e2e.bat`:
```bat
@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%HERE%Docs.pas" --db "%DB%"
sqlite3 "%DB%" "SELECT s.qualified_name || '|' || d.format || '|' || COALESCE(d.summary,'<null>') FROM symbols s JOIN symbol_docs d ON d.symbol_id = s.id ORDER BY s.qualified_name;" > "%HERE%t8_out.txt"
type "%HERE%t8_out.txt"
findstr /c:"Docs.TDocDemo.GetBaz|xmldoc|Computes the baz" "%HERE%t8_out.txt" >NUL || (echo FAIL: GetBaz doc not stored && exit /b 1)
findstr /c:"Docs.TDocDemo.Add|pasdoc|Adds two numbers." "%HERE%t8_out.txt" >NUL || (echo FAIL: Add PasDoc not stored && exit /b 1)
findstr /c:"Docs.TDocDemo.DoOne|oneline|One-liner doc above this method" "%HERE%t8_out.txt" >NUL || (echo FAIL: DoOne oneliner not stored && exit /b 1)
echo PASS
```

- [ ] **Step 2: Run, expect failure (no rows yet)**

```
tests\fixtures\T8_e2e.bat
```
Expected: `FAIL: GetBaz doc not stored`.

- [ ] **Step 3: Wire the scanner into Parser.Delphi13**

In `src/parser/DRagLint.Parser.Delphi13.pas`:

Add to uses:
```pascal
DRagLint.Parser.DocComments,
```

Add a private field to the parser class:
```pascal
FDocRegions: TList<TDocCommentRegion>;
FDocSource: string;
```

In the per-file entry point (look for `Parse(const APath: string ...)` or similar), populate the regions before walking:
```pascal
FDocSource := TFile.ReadAllText(APath);
FreeAndNil(FDocRegions);
FDocRegions := TDocCommentScanner.Scan(FDocSource);
```

Where each symbol is emitted (search for calls to `Store.UpsertSymbol`), after the symbol's `Id` is returned, do:
```pascal
LRegion := FindRegionAbove(SymStartLine);  // helper below
if LRegion.Kind <> TDocCommentKind(-1) then
begin
  LDoc := TDocCommentParser.Dispatch(LRegion);
  if LDoc.HasContent then
    Store.UpsertSymbolDoc(Token, Id, LDoc);
end;
```

Add the helper inside the parser unit:
```pascal
function TDelphi13Parser.FindRegionAbove(ASymStartLine: Integer): TDocCommentRegion;
var
  I: Integer;
  Best: TDocCommentRegion;
  HasBest: Boolean;
const
  ALLOW_GAP = 1;  // TODO Task 13: read from .drag-lint.json
begin
  HasBest := False;
  // FDocRegions is sorted by StartLine. Look for region whose EndLine is
  // within [SymStartLine - 1 - ALLOW_GAP, SymStartLine - 1].
  for I := 0 to FDocRegions.Count - 1 do
  begin
    if (FDocRegions[I].EndLine >= ASymStartLine - 1 - ALLOW_GAP) and
       (FDocRegions[I].EndLine <= ASymStartLine - 1) then
    begin
      Best := FDocRegions[I];
      HasBest := True;
    end;
    if FDocRegions[I].StartLine > ASymStartLine then Break;
  end;
  if HasBest then
    Result := Best
  else
  begin
    // Sentinel: invalid kind to signal "no region"
    FillChar(Result, SizeOf(Result), 0);
    Result.Kind := TDocCommentKind(-1);
  end;
end;
```

In `src/core/DRagLint.Core.Indexer.pas`, in the per-file transaction (right after `OpenFileTx` returns and before parsing), call:
```pascal
Store.DeleteFileDocs(LFileId);
```

(Need to expose `FileId` from `TFileTxToken` if it isn't already; check the existing `DeleteFileSymbols` call for the pattern.)

- [ ] **Step 4: Build and run**

```
build\build_draglint.bat
tests\fixtures\T8_e2e.bat
```
Expected: `PASS`.

- [ ] **Step 5: Commit**

```
git add src/parser/DRagLint.Parser.Delphi13.pas src/core/DRagLint.Core.Indexer.pas src/core/DRagLint.Core.Interfaces.pas tests/fixtures/T8_e2e.bat
git commit -m "feat(v0.16): wire doc-region lookup into Parser.Delphi13 + Indexer re-emit"
```

---

## Task 9: CLI — `drag-lint hover`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas`
- Create: `tests/fixtures/T9_hover.bat`

- [ ] **Step 1: Write the failing test**

Create `tests/fixtures/T9_hover.bat`:
```bat
@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" hover --qname Docs.TDocDemo.GetBaz --db "%DB%" > "%HERE%t9_out.txt"
type "%HERE%t9_out.txt"
findstr /c:"Computes the baz" "%HERE%t9_out.txt" >NUL || (echo FAIL: summary missing && exit /b 1)
findstr /c:"value" "%HERE%t9_out.txt" >NUL || (echo FAIL: param missing && exit /b 1)
findstr /c:"Returns:" "%HERE%t9_out.txt" >NUL || (echo FAIL: returns label missing && exit /b 1)
echo PASS
```

- [ ] **Step 2: Run, expect failure ("unknown command: hover")**

```
tests\fixtures\T9_hover.bat
```
Expected: `FAIL: summary missing` (since CLI emits an unknown-command error, not the summary).

- [ ] **Step 3: Add the hover command**

In `src/cli/DRagLint.CLI.pas`, find the command dispatch (search for `'query'` or `'lint'` case branches) and add a `hover` branch:

```pascal
else if SameText(Cmd, 'hover') then
  ExitCode := CmdHover(Args)
```

Implement `CmdHover`:
```pascal
function CmdHover(const AArgs: TArray<string>): Integer;
var
  QName, DbPath, Format, Pat: string;
  I: Integer;
  Store: ISymbolStore;
  Syms: TArray<TSymbol>;
  Doc: TParsedDoc;
begin
  QName := '';
  DbPath := DEFAULT_DB_PATH;
  Format := 'plain';
  I := 0;
  while I < Length(AArgs) do
  begin
    if SameText(AArgs[I], '--qname') and (I < High(AArgs)) then
    begin QName := AArgs[I+1]; Inc(I, 2); end
    else if SameText(AArgs[I], '--db') and (I < High(AArgs)) then
    begin DbPath := AArgs[I+1]; Inc(I, 2); end
    else if SameText(AArgs[I], '--format') and (I < High(AArgs)) then
    begin Format := AArgs[I+1]; Inc(I, 2); end
    else
      Inc(I);
  end;

  if QName = '' then
  begin
    Writeln('Usage: drag-lint hover --qname <Foo.Bar> [--db <path>] [--format md|plain|json]');
    Exit(2);
  end;

  Store := TSQLiteSymbolStore.Create(DbPath);
  Syms := Store.FindSymbolsByQualifiedName(QName);
  if Length(Syms) = 0 then
  begin
    Writeln(Format('No symbol matched qname: %s', [QName]));
    Exit(1);
  end;

  Doc := Store.GetSymbolDoc(Syms[0].Id);
  if not Doc.HasContent then
  begin
    Writeln(Format('Symbol %s found but has no doc comment.', [Syms[0].QualifiedName]));
    Exit(1);
  end;

  if SameText(Format, 'json') then
    Writeln(RenderHoverJson(Syms[0], Doc))
  else if SameText(Format, 'md') then
    Writeln(RenderHoverMarkdown(Syms[0], Doc))
  else
    Writeln(RenderHoverPlain(Syms[0], Doc));
  Result := 0;
end;
```

Render helpers:
```pascal
function RenderHoverPlain(const ASym: TSymbol; const ADoc: TParsedDoc): string;
var
  SB: TStringBuilder;
  I: Integer;
  Pj: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(ASym.QualifiedName);
    if ADoc.Deprecated then SB.AppendLine('[DEPRECATED]');
    if ADoc.SinceText <> '' then SB.AppendLine('Since: ' + ADoc.SinceText);
    if ADoc.Summary <> '' then
      SB.AppendLine('Summary: ' + ADoc.Summary);
    // params_json was stored as raw text — emit it verbatim for v0.16; v0.17
    // parses it back into a structured table.
    Pj := ''; // TODO: read params_json from doc record once Task 7 extension lands
    if Pj <> '' then SB.AppendLine('Params: ' + Pj);
    if ADoc.ReturnsText <> '' then SB.AppendLine('Returns: ' + ADoc.ReturnsText);
    if ADoc.Remarks <> '' then SB.AppendLine('Remarks: ' + ADoc.Remarks);
    if ADoc.ExampleText <> '' then
    begin SB.AppendLine('Example:'); SB.AppendLine(ADoc.ExampleText); end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenderHoverMarkdown(const ASym: TSymbol; const ADoc: TParsedDoc): string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# ' + ASym.QualifiedName);
    if ADoc.Deprecated then SB.AppendLine('> **DEPRECATED**');
    if ADoc.SinceText <> '' then SB.AppendLine('> _Since: ' + ADoc.SinceText + '_');
    if ADoc.Summary <> '' then
    begin SB.AppendLine; SB.AppendLine(ADoc.Summary); end;
    if ADoc.ReturnsText <> '' then
    begin SB.AppendLine; SB.AppendLine('**Returns:** ' + ADoc.ReturnsText); end;
    if ADoc.Remarks <> '' then
    begin SB.AppendLine; SB.AppendLine('## Remarks'); SB.AppendLine(ADoc.Remarks); end;
    if ADoc.ExampleText <> '' then
    begin SB.AppendLine; SB.AppendLine('## Example'); SB.AppendLine('```pascal'); SB.AppendLine(ADoc.ExampleText); SB.AppendLine('```'); end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenderHoverJson(const ASym: TSymbol; const ADoc: TParsedDoc): string;
begin
  Result := Format(
    '{"qname":"%s","format":"%s","summary":"%s","returns":"%s",' +
    '"since":"%s","deprecated":%s}',
    [JsonEscape(ASym.QualifiedName), DocFormatToStr(ADoc.Format),
     JsonEscape(ADoc.Summary), JsonEscape(ADoc.ReturnsText),
     JsonEscape(ADoc.SinceText),
     IfThen(ADoc.Deprecated, 'true', 'false')]);
end;
```

Update the CLI's `Usage` text to list `hover` alongside `query`, `lint`, etc.

For params/exceptions/seealso rendering: extend `GetSymbolDoc` to also return the raw JSON strings (one extra column read each) so the renderers can format them. Add to `TParsedDoc`:
```pascal
ParamsJsonRaw, ExceptionsJsonRaw, SeeAlsoJsonRaw: string;
```
(These bypass the un-parsed v0.16 JSON; v0.17 may parse them back.)

In `RenderHoverPlain`, when `Doc.ParamsJsonRaw <> ''`, parse the JSON inline (tiny scanner — name/desc pairs) and emit one line per param. For v0.16, the simplest formatter is a regex over the JSON:
```pascal
Re := TRegEx.Create('"name":"([^"]+)","desc":"([^"]*)"');
for M in Re.Matches(ADoc.ParamsJsonRaw) do
  SB.AppendLine('  ' + M.Groups[1].Value + ' -- ' + M.Groups[2].Value);
```

- [ ] **Step 4: Build and run**

```
build\build_draglint.bat
tests\fixtures\T8_e2e.bat
tests\fixtures\T9_hover.bat
```
Expected: T8 still `PASS`, T9 `PASS`.

- [ ] **Step 5: Commit**

```
git add src/cli/DRagLint.CLI.pas tests/fixtures/T9_hover.bat
git commit -m "feat(v0.16): drag-lint hover --qname (plain/md/json formats)"
```

---

## Task 10: CLI — `find --doc-tag` / `--doc-contains` / `--no-docs`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas`
- Create: `tests/fixtures/T10_find.bat`

- [ ] **Step 1: Write the failing test**

```bat
@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
echo === find --doc-tag deprecated ===
"%EXE%" query find --doc-tag deprecated --db "%DB%" > "%HERE%t10_dep.txt"
type "%HERE%t10_dep.txt"
findstr /c:"OldProc" "%HERE%t10_dep.txt" >NUL || (echo FAIL: deprecated not found && exit /b 1)

echo === find --doc-contains baz ===
"%EXE%" query find --doc-contains baz --db "%DB%" > "%HERE%t10_baz.txt"
findstr /c:"GetBaz" "%HERE%t10_baz.txt" >NUL || (echo FAIL: doc-contains miss && exit /b 1)

echo === find --no-docs --kind method ===
"%EXE%" query find --no-docs --kind method --db "%DB%" > "%HERE%t10_nodocs.txt"
type "%HERE%t10_nodocs.txt"
echo PASS
```

- [ ] **Step 2: Run, expect FAIL**

```
tests\fixtures\T10_find.bat
```
Expected: `FAIL: deprecated not found` (or unknown subcommand).

- [ ] **Step 3: Add `find` subcommand under `query`**

In the existing `CmdQuery` dispatcher in `src/cli/DRagLint.CLI.pas`, find where `find-callers` lives and add a sibling:

```pascal
else if SameText(Sub, 'find') then
  Result := QueryFind(SubArgs)
```

Implement:
```pascal
function QueryFind(const AArgs: TArray<string>): Integer;
var
  Tag, Pat, Kind, DbPath: string;
  PublicOnly, NoDocs: Boolean;
  I: Integer;
  Store: ISymbolStore;
  Syms: TArray<TSymbol>;
  S: TSymbol;
begin
  Tag := ''; Pat := ''; Kind := ''; PublicOnly := False; NoDocs := False;
  DbPath := DEFAULT_DB_PATH;
  I := 0;
  while I < Length(AArgs) do
  begin
    if SameText(AArgs[I], '--doc-tag') and (I < High(AArgs)) then
    begin Tag := AArgs[I+1]; Inc(I, 2); end
    else if SameText(AArgs[I], '--doc-contains') and (I < High(AArgs)) then
    begin Pat := AArgs[I+1]; Inc(I, 2); end
    else if SameText(AArgs[I], '--kind') and (I < High(AArgs)) then
    begin Kind := AArgs[I+1]; Inc(I, 2); end
    else if SameText(AArgs[I], '--public') then
    begin PublicOnly := True; Inc(I); end
    else if SameText(AArgs[I], '--no-docs') then
    begin NoDocs := True; Inc(I); end
    else if SameText(AArgs[I], '--db') and (I < High(AArgs)) then
    begin DbPath := AArgs[I+1]; Inc(I, 2); end
    else
      Inc(I);
  end;

  if (Tag = '') and (Pat = '') and (not NoDocs) then
  begin
    Writeln('Usage: drag-lint query find [--doc-tag X | --doc-contains Y | --no-docs] [--kind K] [--public]');
    Exit(2);
  end;

  Store := TSQLiteSymbolStore.Create(DbPath);
  if NoDocs then
    Syms := Store.FindUndocumented(Kind, PublicOnly)
  else if Tag <> '' then
    Syms := Store.FindByDocTag(Tag)
  else
    Syms := Store.FindByDocContains(Pat);

  for S in Syms do
    Writeln(Format('%s  [%s]  %s:%d', [S.QualifiedName, S.Kind, S.FilePath, S.StartLine]));

  if Length(Syms) = 0 then Result := 1 else Result := 0;
end;
```

- [ ] **Step 4: Build and run**

```
build\build_draglint.bat
tests\fixtures\T10_find.bat
```
Expected: `PASS`.

- [ ] **Step 5: Commit**

```
git add src/cli/DRagLint.CLI.pas tests/fixtures/T10_find.bat
git commit -m "feat(v0.16): query find --doc-tag/--doc-contains/--no-docs"
```

---

## Task 11: MCP tools — `get_symbol_doc` + `find_by_doc_tag` + `find_undocumented`

**Files:**
- Modify: `src/mcp/DRagLint.MCP.Server.pas`
- Create: `tests/fixtures/T11_mcp.json` (request fixture)
- Create: `tests/fixtures/T11_mcp.bat`

- [ ] **Step 1: Write the failing test**

`tests/fixtures/T11_mcp.json`:
```json
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_symbol_doc","arguments":{"qname":"Docs.TDocDemo.GetBaz","db":"tests/fixtures/t8.sqlite"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"find_by_doc_tag","arguments":{"tag":"deprecated","db":"tests/fixtures/t8.sqlite"}}}
```

`tests/fixtures/T11_mcp.bat`:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
type "%HERE%T11_mcp.json" | "%EXE%" serve > "%HERE%t11_out.txt"
findstr /c:"get_symbol_doc" "%HERE%t11_out.txt" >NUL || (echo FAIL: tool not advertised && exit /b 1)
findstr /c:"Computes the baz" "%HERE%t11_out.txt" >NUL || (echo FAIL: doc not returned && exit /b 1)
findstr /c:"OldProc" "%HERE%t11_out.txt" >NUL || (echo FAIL: deprecated not returned && exit /b 1)
echo PASS
```

- [ ] **Step 2: Run, expect FAIL**

```
tests\fixtures\T11_mcp.bat
```

- [ ] **Step 3: Add the 3 MCP tools**

In `src/mcp/DRagLint.MCP.Server.pas`, locate the `tools/list` response handler. Append three tool descriptors:
```pascal
AddTool('get_symbol_doc',
  'Return the structured doc comment for a symbol by qualified name.',
  '{"type":"object","properties":{"qname":{"type":"string"},"db":{"type":"string"}},"required":["qname"]}');
AddTool('find_by_doc_tag',
  'Find symbols whose doc has a given tag (deprecated|since).',
  '{"type":"object","properties":{"tag":{"type":"string"},"db":{"type":"string"}},"required":["tag"]}');
AddTool('find_undocumented',
  'Find symbols with no doc comment, optionally filtered by kind/public.',
  '{"type":"object","properties":{"kind":{"type":"string"},"public_only":{"type":"boolean"},"db":{"type":"string"}}}');
```

In the `tools/call` dispatcher, add three branches that call the same `TSQLiteSymbolStore` methods Task 7 added, then JSON-serialize the result. Pattern matches the existing `find_callers` tool — copy that and adapt.

- [ ] **Step 4: Build and run**

```
build\build_draglint.bat
tests\fixtures\T11_mcp.bat
```
Expected: `PASS`.

- [ ] **Step 5: Commit**

```
git add src/mcp/DRagLint.MCP.Server.pas tests/fixtures/T11_mcp.json tests/fixtures/T11_mcp.bat
git commit -m "feat(v0.16): MCP tools get_symbol_doc + find_by_doc_tag + find_undocumented"
```

---

## Task 12: LSP — upgrade `textDocument/hover` payload

**Files:**
- Modify: `src/lsp/DRagLint.LSP.Server.pas`
- Create: `tests/fixtures/T12_lsp.json`
- Create: `tests/fixtures/T12_lsp.bat`

- [ ] **Step 1: Write the failing test**

`tests/fixtures/T12_lsp.json`:
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///C:/Projects/Delphi-RAG-lint/tests/fixtures/Docs.pas"},"position":{"line":7,"character":15}}}
```

(Line/character is 0-based, pointing at `GetBaz` declaration in Docs.pas. Adjust to actual line if Docs.pas changes.)

`tests/fixtures/T12_lsp.bat`:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
type "%HERE%T12_lsp.json" | "%EXE%" lsp --db "%HERE%t8.sqlite" > "%HERE%t12_out.txt"
findstr /c:"Computes the baz" "%HERE%t12_out.txt" >NUL || (echo FAIL: enriched hover missing && exit /b 1)
findstr /c:"value" "%HERE%t12_out.txt" >NUL || (echo FAIL: param missing && exit /b 1)
echo PASS
```

- [ ] **Step 2: Run, expect FAIL**

```
tests\fixtures\T12_lsp.bat
```

- [ ] **Step 3: Upgrade the hover handler**

In `src/lsp/DRagLint.LSP.Server.pas`, find `textDocument/hover` handler. Where it currently formats hover content from `signature` / `qualified_name` only, fetch the doc:

```pascal
Doc := FStore.GetSymbolDoc(Sym.Id);
if Doc.HasContent then
begin
  HoverContent := BuildHoverMarkdown(Sym, Doc);  // reuses CLI's RenderHoverMarkdown
end
else
  HoverContent := DefaultHoverContent(Sym);
```

Reuse `RenderHoverMarkdown` (Task 9) — either expose it from `DRagLint.CLI` or duplicate the function into a new tiny `DRagLint.Hover.Renderer.pas` and call from both CLI and LSP (DRY).

(Recommend the new shared unit — Task 9's render functions weren't testable on their own, and Task 12 reusing them earns the abstraction.)

- [ ] **Step 4: Build and run**

```
build\build_draglint.bat
tests\fixtures\T12_lsp.bat
```
Expected: `PASS`.

- [ ] **Step 5: Commit**

```
git add src/lsp/DRagLint.LSP.Server.pas tests/fixtures/T12_lsp.json tests/fixtures/T12_lsp.bat
git commit -m "feat(v0.16): LSP textDocument/hover returns doc-enriched markdown"
```

(If you factored out a shared renderer, include `src/cli/DRagLint.Hover.Renderer.pas` and the .dpr/.dproj registration in this commit.)

---

## Task 13: `.drag-lint.json` config — docs section

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (or wherever config loading lives — likely a `DRagLint.Config.pas` introduced in v0.14)
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (read AllowBlankLineGap from config)
- Create: `tests/fixtures/T13_config/.drag-lint.json`
- Create: `tests/fixtures/T13_config/sample.pas`
- Create: `tests/fixtures/T13_config.bat`

- [ ] **Step 1: Write the failing test**

`tests/fixtures/T13_config/.drag-lint.json`:
```json
{
  "docs": {
    "captureLooseComments": true,
    "allowBlankLineGap": 0
  }
}
```

`tests/fixtures/T13_config/sample.pas`:
```pascal
unit sample;
interface
type
  TX = class
    // loose preceding doc
    procedure A;

    // loose doc with gap

    procedure B;  // -- separated by a blank line
  end;
implementation
procedure TX.A; begin end;
procedure TX.B; begin end;
end.
```

`tests/fixtures/T13_config.bat`:
```bat
@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t13.sqlite
del /q "%DB%" 2>NUL
cd /d "%HERE%T13_config"
"%EXE%" index "sample.pas" --db "%DB%"
sqlite3 "%DB%" "SELECT s.name, d.format, d.summary FROM symbols s LEFT JOIN symbol_docs d ON d.symbol_id = s.id WHERE s.name IN ('A','B') ORDER BY s.name;" > "%HERE%t13_out.txt"
type "%HERE%t13_out.txt"
findstr /c:"A|loose|loose preceding doc" "%HERE%t13_out.txt" >NUL || (echo FAIL: A loose not captured && exit /b 1)
findstr /r /c:"B|" "%HERE%t13_out.txt" | findstr /v "loose" >NUL && (echo FAIL: B should have no doc with gap=0 && exit /b 1)
echo PASS
```

- [ ] **Step 2: Run, expect FAIL**

```
tests\fixtures\T13_config.bat
```

- [ ] **Step 3: Wire config**

Locate the config loader added in v0.14 (likely `LoadDragLintConfig` in `DRagLint.CLI.pas` or a separate `DRagLint.Config.pas`). Extend its return record:
```pascal
TDocConfig = record
  CaptureLooseComments: Boolean;
  ImplPrecedence:       string;   // 'interface' (default) | 'implementation'
  AllowBlankLineGap:    Integer;  // default 1
end;

TDragLintConfig = record
  // ... existing fields ...
  Docs: TDocConfig;
end;
```

Read from JSON `"docs"` object with the defaults above. Pass `Docs` into `TDelphi13Parser` at construction so `FindRegionAbove` uses `Docs.AllowBlankLineGap` instead of the hard-coded `1`, and `ParseLoose` is skipped entirely when `not Docs.CaptureLooseComments`.

In `Parser.Delphi13.FindRegionAbove`, gate loose regions:
```pascal
if (FDocRegions[I].Kind in [dckLooseLine, dckLooseBlock]) and
   (not FConfig.Docs.CaptureLooseComments) then Continue;
```

- [ ] **Step 4: Build and run**

```
build\build_draglint.bat
tests\fixtures\T13_config.bat
```
Expected: `PASS`.

- [ ] **Step 5: Commit**

```
git add src/cli/DRagLint.CLI.pas src/parser/DRagLint.Parser.Delphi13.pas tests/fixtures/T13_config tests/fixtures/T13_config.bat
git commit -m "feat(v0.16): .drag-lint.json docs section (captureLooseComments + allowBlankLineGap + implPrecedence)"
```

---

## Task 14: E2E + coverage report + CHANGELOG + tag v0.16.0-alpha

**Files:**
- Create: `tests/run_v016_doctests.bat`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Stitch the e2e**

Create `tests/run_v016_doctests.bat`:
```bat
@echo off
setlocal
set HERE=%~dp0
set FAILED=0
call "%HERE%fixtures\T1_schema.bat"      || set FAILED=1
call "%HERE%fixtures\T3_regions.exe"     || set FAILED=1
call "%HERE%fixtures\T4_xmldoc.exe"      || set FAILED=1
call "%HERE%fixtures\T5_pasdoc.exe"      || set FAILED=1
call "%HERE%fixtures\T6_dispatch.exe"    || set FAILED=1
call "%HERE%fixtures\T7_storage.exe"     || set FAILED=1
call "%HERE%fixtures\T8_e2e.bat"         || set FAILED=1
call "%HERE%fixtures\T9_hover.bat"       || set FAILED=1
call "%HERE%fixtures\T10_find.bat"       || set FAILED=1
call "%HERE%fixtures\T11_mcp.bat"        || set FAILED=1
call "%HERE%fixtures\T12_lsp.bat"        || set FAILED=1
call "%HERE%fixtures\T13_config.bat"     || set FAILED=1

echo.
echo === Stop criteria check ===
echo (1) Self-corpus doc coverage:
"%HERE%..\third_party\dll\drag-lint.exe" index "%HERE%..\src" --db "%HERE%draglint_self.sqlite"
sqlite3 "%HERE%draglint_self.sqlite" "SELECT COUNT(*) FROM symbol_docs WHERE summary IS NOT NULL;"
echo (6) Micronite COMMON undocumented public methods (first 20):
"%HERE%..\third_party\dll\drag-lint.exe" index "C:\Projects\DB\ORM3\COMMON" --db "%HERE%micronite_common.sqlite" >NUL
"%HERE%..\third_party\dll\drag-lint.exe" query find --no-docs --kind method --public --db "%HERE%micronite_common.sqlite" | head -20
echo (8) DevExpress index timing (target: within 10%% of v0.15):
echo (manually compare with prior bench)

if %FAILED%==1 (echo TESTS FAILED && exit /b 1)
echo ALL PASS
```

(Note: `head` may not exist on Win cmd; replace with `more +0 | findstr /n . | findstr "^[1-9][0-9]\?:"` or just emit full output. Adjust as needed during execution.)

- [ ] **Step 2: Run the full suite**

```
build\build_draglint.bat
tests\run_v016_doctests.bat
```
Expected: `ALL PASS` plus all 8 stop-criteria printouts populated.

- [ ] **Step 3: Update CHANGELOG.md**

Prepend:
```markdown
## v0.16.0-alpha — 2026-MM-DD

### Added
- `symbol_docs` table (schema v4) storing structured doc comments per symbol.
- New `DRagLint.Parser.DocComments` module parsing XMLDoc (`///` with
  `<summary>`/`<param>`/`<returns>`/`<remarks>`/`<exception>`/`<example>`/
  `<seealso>`/`<since>`/`<deprecated>`), PasDoc (`{** *}` and `(** *)` blocks
  with `@param`/`@returns`/`@throws`/`@remarks`/`@example`/`@see`/`@since`/
  `@deprecated`/`@author`/`@version`), and oneline (`///`, `//1`, `///1`).
- `drag-lint hover --qname X` with `--format md|plain|json`.
- `drag-lint query find --doc-tag deprecated|since`, `--doc-contains TEXT`,
  `--no-docs [--kind method --public]`.
- MCP tools: `get_symbol_doc`, `find_by_doc_tag`, `find_undocumented`.
- LSP `textDocument/hover` now returns doc-enriched Markdown.
- `.drag-lint.json` `docs` section: `captureLooseComments`,
  `allowBlankLineGap`, `implPrecedence`.

### Notes
- Comment-region scanner respects string literals (`'foo // bar'` is not a
  comment) and merges adjacent same-kind line comments.
- v3 DBs auto-migrate to v4 transparently (`CREATE TABLE IF NOT EXISTS`).
- Index time on DevExpress within 10% of v0.15.
```

- [ ] **Step 4: README**

Add a short "Documentation extraction" section under existing feature list,
linking to the spec for detail.

- [ ] **Step 5: Tag**

```
git add CHANGELOG.md README.md tests/run_v016_doctests.bat
git commit -m "release(v0.16): doc-comment extraction + CHANGELOG + README"
git tag -a v0.16.0-alpha -m "v0.16.0-alpha — doc-comment extraction (Slice A)"
```

(Push when user authorizes; consistent with v0.15 pattern.)

---

## Self-Review Notes (post-write)

- **Spec coverage:** Sections 1-7 of the spec each map to tasks: §1 goals/criteria → Tasks 8 + 14 stop-criteria checks; §2 schema → Task 1; §3 parser pipeline → Tasks 3 + 8; §4 per-format rules → Tasks 4, 5, 6; §5 consumers → Tasks 9, 10, 11, 12; §5.4 config → Task 13; §6 roadmap is intentionally out of v0.16 scope; §7 stop criteria → Task 14.
- **Type consistency:** `TParsedDoc` shape defined in Task 2 is referenced unchanged by Tasks 4, 5, 6, 7, 9, 12. `UpsertSymbolDoc` signature stable from Task 2 stub through Task 7 implementation.
- **Repo HARD RULES respected:** `DRagLint.Parser.DocComments.pas` registered in BOTH `.dpr` and `.dproj` in Task 3 (per `feedback_units_in_dpr_and_dproj`). No DDL added outside `Storage.Schema.pas`.
- **No placeholders:** Each step has the actual code/command/expected output. The single `TODO` in Task 9 (params_json rendering) is followed by the explicit fix two lines later.
