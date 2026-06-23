# Text-Constant Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `drag-lint query --text "<phrase>"` — an FTS5 index over string content (Delphi literals, DFM component text, SQL EXCEPTION messages) so message/caption search replaces grep and returns only text occurrences, never identifiers.

**Architecture:** A new `string_literals` table holds one row per indexed literal (with its enclosing symbol resolved at index time via the existing `FindContainingSymbol`). Two external-content FTS5 indexes over its `text` column — `unicode61` (phrase / any-order) and `trigram` (substring) — are kept in sync by triggers. Each parser harvests literals onto `TParseResult.Literals`; the indexer persists them; the CLI queries FTS5.

**Tech Stack:** Delphi 13 (Studio 37), FireDAC + static SQLite (FTS5 confirmed: `-DSQLITE_ENABLE_FTS5=1`), tree-sitter. Build via the `delphi-build` skill (rsvars wrapper → PowerShell `Start-Process`). Tests via `tests/...` PowerShell harnesses driving the Win64 exe.

## Global Constraints

- Source files are strict 7-bit ASCII, CRLF. Never introduce Unicode or LF into `.pas`/`.dfm`.
- DocInsight `///` spec-comments on every new public type/method; failing-test-first (TDD); `try-finally` for resources.
- Canonical exe: `third_party\dll-win64\drag-lint.exe` (Win64 Debug). After each build, stage `src\cli\Win64\Debug\drag-lint.exe` → there.
- New units (none expected here) would need BOTH `.dpr uses` and a `.dproj <DCCReference>`. This plan only modifies existing units.
- Default search = exact phrase, in order, case-insensitive; `--any-order` = all words any order; `--substring` = grep-like mid-word. Index every **non-empty** literal (format strings kept).
- Version after this feature: **v0.58.0-alpha**.

---

### Task 0: FTS5 / trigram availability spike

**Files:**
- Test: `tests/textindex/fts5_spike.ps1` (Create)

**Interfaces:**
- Produces: a go/no-go fact. If trigram is unavailable, STOP — revisit `--substring` via `LIKE` (spec §3/§9) before continuing.

- [ ] **Step 1: Write a spike that builds + queries a trigram FTS5 table through the real exe path.** The drag-lint exe has no raw-SQL command, so probe via an indexed DB instead: build a throwaway DB and assert the storage opens with FTS5 present. Simplest reliable probe — add a hidden CLI self-check. Create `tests/textindex/fts5_spike.ps1`:

```powershell
$exe = "third_party\dll-win64\drag-lint.exe"
# --selftest-fts5 is added in Step 3; it returns exit 0 and prints OK when
# CREATE VIRTUAL TABLE ... USING fts5(x, tokenize='trigram') + a substring MATCH work.
& $exe --selftest-fts5
if ($LASTEXITCODE -ne 0) { Write-Error "FTS5/trigram NOT available — STOP, revisit --substring"; exit 1 }
"FTS5 + trigram OK"
```

- [ ] **Step 2: Run it — expect FAIL** (`--selftest-fts5` unknown yet).

Run: `pwsh -File tests\textindex\fts5_spike.ps1`
Expected: nonzero exit / unknown-arg error.

- [ ] **Step 3: Add the self-check to the CLI.** In `src/cli/DRagLint.CLI.pas`, in the early bare-flag dispatch (near where `--flow`/`--selftest` style flags are handled), add a branch for `--selftest-fts5` that opens an in-memory FireDAC SQLite connection and runs:

```pascal
// --selftest-fts5: prove FTS5 + trigram tokenizer are compiled in.
function DoSelfTestFts5: Integer;
var
  Conn: TFDConnection;
  Q   : TFDQuery;
begin
  Result:= 1;
  Conn:= TFDConnection.Create(nil);
  try
    Conn.DriverName:= 'SQLite';
    Conn.Params.Values['Database']:= ':memory:';
    Conn.Connected:= True;
    Conn.ExecSQL('CREATE VIRTUAL TABLE t USING fts5(x, tokenize=''trigram'')');
    Conn.ExecSQL('INSERT INTO t(rowid, x) VALUES (1, ''Folder not found'')');
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= Conn;
      Q.SQL.Text:= 'SELECT rowid FROM t WHERE t MATCH ''older''';  // substring
      Q.Open;
      if (not Q.Eof) and (Q.FieldByName('rowid').AsInteger = 1) then
      begin
        Writeln('FTS5+trigram OK');
        Result:= 0;
      end
      else Writeln('FTS5 present but trigram match failed');
    finally
      Q.Free;
    end;
  except
    on E: Exception do Writeln('FTS5 unavailable: ', E.Message);
  end;
  Conn.Free;
end;
```

Wire `if (ParamStr(1) = '--selftest-fts5') then Exit(DoSelfTestFts5);` into the flag dispatch. Ensure `FireDAC.Comp.Client` is in the CLI uses (it already is via the storage path; add if the compiler complains).

- [ ] **Step 4: Build + stage, run spike — expect PASS.**

Run (delphi-build skill): build Win64 Debug, copy exe to `third_party\dll-win64\`. Then `pwsh -File tests\textindex\fts5_spike.ps1`
Expected: `FTS5 + trigram OK`.

- [ ] **Step 5: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas tests/textindex/fts5_spike.ps1
git commit -m "test(textindex): FTS5+trigram availability spike (--selftest-fts5)"
```

---

### Task 1: Model — `TStringLiteral` + `TParseResult.Literals`

**Files:**
- Modify: `src/core/DRagLint.Core.Model.pas` (add record near `TReference`)
- Modify: `src/core/DRagLint.Core.Interfaces.pas:134-144` (`TParseResult`)

**Interfaces:**
- Produces: `TStringLiteral` (consumed by every parser + the store) and `TParseResult.Literals`.

- [ ] **Step 1: Add the record** to `DRagLint.Core.Model.pas` after `TReference` (line ~62):

```pascal
  /// <summary>One indexed string-literal occurrence (a message, caption, or
  /// exception text). SymbolId is the enclosing routine/component, resolved by
  /// the indexer post-parse (0 in parser output). Text is the DECODED logical
  /// string (escapes/`#nn`/continuations resolved); never empty.</summary>
  TStringLiteral = record
    Id       : Int64  ;
    FileId   : Int64  ;
    SymbolId : Int64  ; // enclosing symbol; 0 until indexer resolves it
    Source   : string ; // 'pas' | 'dfm' | 'sql'
    Kind     : string ; // 'literal'|'const'|'resourcestring'|'format'|'dfm-prop'|'sql-exception'
    OwnerName: string ; // const name / DFM property / exception name; '' if n/a
    Text     : string ;
    StartLine: Integer;
    StartCol : Integer;
    EndLine  : Integer;
    EndCol   : Integer;
  end;

  /// <summary>A text-search hit returned by ISymbolStore.SearchText: a
  /// TStringLiteral enriched with the file path and enclosing qualified name.</summary>
  TStringLitMatch = record
    FilePath      : string ;
    Source        : string ;
    Kind          : string ;
    OwnerName     : string ;
    Text          : string ;
    EnclosingQName: string ;
    StartLine     : Integer;
    StartCol      : Integer;
    EndLine       : Integer;
    EndCol        : Integer;
  end;
```

- [ ] **Step 2: Add `Literals` to `TParseResult`** in `DRagLint.Core.Interfaces.pas` (after `DiBindings`, line 143):

```pascal
    DiBindings : TArray<TDiBindingRow>; // v8: Spring4D DI registrations
    Literals   : TArray<TStringLiteral>; // v10: indexed string content (text search)
```

- [ ] **Step 3: Build** (delphi-build skill). Expected: compiles clean (no consumers yet).

- [ ] **Step 4: Commit.**

```bash
git add src/core/DRagLint.Core.Model.pas src/core/DRagLint.Core.Interfaces.pas
git commit -m "feat(model): TStringLiteral/TStringLitMatch + TParseResult.Literals"
```

---

### Task 2: Schema v10 — `string_literals` + FTS5 + triggers

**Files:**
- Modify: `src/storage/DRagLint.Storage.Schema.pas` (bump `SCHEMA_VERSION`, extend `SCHEMA_DDL` array)
- Test: `tests/textindex/schema_v10.ps1` (Create)

**Interfaces:**
- Produces: tables `string_literals`, `string_fts`, `string_fts_tri`, plus sync triggers. Created on next store open (Migrate runs the idempotent `IF NOT EXISTS` DDL loop).

- [ ] **Step 1: Write the schema test** `tests/textindex/schema_v10.ps1`:

```powershell
$exe = "third_party\dll-win64\drag-lint.exe"
$sb  = "$env:TEMP\dl_schema_v10"; Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $sb | Out-Null
Set-Content "$sb\a.pas" "unit A; interface implementation const C = 'hello world'; end."
& $exe index $sb --db "$sb\idx.sqlite" | Out-Null
# --selftest-schema (added below) prints the table names that exist.
$out = & $exe --selftest-schema --db "$sb\idx.sqlite"
foreach ($t in 'string_literals','string_fts','string_fts_tri') {
  if ($out -notmatch $t) { Write-Error "missing table $t"; exit 1 }
}
"schema v10 OK"
```

- [ ] **Step 2: Run — expect FAIL** (tables/flag missing).

Run: `pwsh -File tests\textindex\schema_v10.ps1`
Expected: error (missing table or unknown flag).

- [ ] **Step 3: Bump version + add DDL.** In `DRagLint.Storage.Schema.pas`: change `SCHEMA_VERSION = 9;` → `= 10;`, and change the array bound `array[0..42]` to fit the new elements (count them; add 6: table + 3 indexes + 2 FTS vtabs + 3 triggers = adjust the upper bound accordingly, e.g. `[0..50]`). Append before the closing `)`:

```pascal
    , // v10: string-content index (text search) -----------------------------
    'CREATE TABLE IF NOT EXISTS string_literals (' + '  id         INTEGER PRIMARY KEY,' +
    '  file_id    INTEGER NOT NULL REFERENCES files(id)  ON DELETE CASCADE,' +
    '  symbol_id  INTEGER          REFERENCES symbols(id) ON DELETE SET NULL,' +
    '  source     TEXT NOT NULL,' + '  kind       TEXT NOT NULL,' + '  owner_name TEXT,' +
    '  text       TEXT NOT NULL,' + '  start_line INTEGER NOT NULL,' + '  start_col INTEGER NOT NULL,' +
    '  end_line   INTEGER NOT NULL,' + '  end_col   INTEGER NOT NULL' + ')',
    'CREATE INDEX IF NOT EXISTS idx_string_literals_file   ON string_literals(file_id)',
    'CREATE INDEX IF NOT EXISTS idx_string_literals_symbol ON string_literals(symbol_id)',
    'CREATE INDEX IF NOT EXISTS idx_string_literals_source ON string_literals(source)',
    'CREATE VIRTUAL TABLE IF NOT EXISTS string_fts USING fts5(' +
    '  text, content=''string_literals'', content_rowid=''id'', tokenize=''unicode61'')',
    'CREATE VIRTUAL TABLE IF NOT EXISTS string_fts_tri USING fts5(' +
    '  text, content=''string_literals'', content_rowid=''id'', tokenize=''trigram'')',
    'CREATE TRIGGER IF NOT EXISTS string_literals_ai AFTER INSERT ON string_literals BEGIN' +
    '  INSERT INTO string_fts(rowid, text) VALUES (new.id, new.text);' +
    '  INSERT INTO string_fts_tri(rowid, text) VALUES (new.id, new.text); END',
    'CREATE TRIGGER IF NOT EXISTS string_literals_ad AFTER DELETE ON string_literals BEGIN' +
    '  INSERT INTO string_fts(string_fts, rowid, text) VALUES (''delete'', old.id, old.text);' +
    '  INSERT INTO string_fts_tri(string_fts_tri, rowid, text) VALUES (''delete'', old.id, old.text); END',
    'CREATE TRIGGER IF NOT EXISTS string_literals_au AFTER UPDATE ON string_literals BEGIN' +
    '  INSERT INTO string_fts(string_fts, rowid, text) VALUES (''delete'', old.id, old.text);' +
    '  INSERT INTO string_fts_tri(string_fts_tri, rowid, text) VALUES (''delete'', old.id, old.text);' +
    '  INSERT INTO string_fts(rowid, text) VALUES (new.id, new.text);' +
    '  INSERT INTO string_fts_tri(rowid, text) VALUES (new.id, new.text); END'
```

(`FConn.ExecSQL` runs each array element as one statement — verified at `DRagLint.Storage.SQLite.pas:321` — so the trigger bodies' internal `;` are fine.)

- [ ] **Step 4: Add `--selftest-schema`** to the CLI (temporary helper used only by tests): open the `--db`, `SELECT name FROM sqlite_master WHERE type IN ('table','view')`, `Writeln` each. (Keep it; harmless and useful.)

- [ ] **Step 5: Build + stage; run — expect PASS.**

Run: `pwsh -File tests\textindex\schema_v10.ps1` → `schema v10 OK`.

- [ ] **Step 6: Commit.**

```bash
git add src/storage/DRagLint.Storage.Schema.pas src/cli/DRagLint.CLI.pas tests/textindex/schema_v10.ps1
git commit -m "feat(storage): schema v10 — string_literals + FTS5 (unicode61+trigram) + triggers"
```

---

### Task 3: Storage — upsert / delete / search

**Files:**
- Modify: `src/core/DRagLint.Core.Interfaces.pas` (`ISymbolStore`: 3 new methods)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (prepared queries, methods, destructor frees)
- Test: `tests/textindex/store_search.ps1` (via the CLI in Task 8; this task’s test is the schema round-trip in Step 5)

**Interfaces:**
- Consumes: `TStringLiteral`, `TStringLitMatch`, `TFileTxToken`.
- Produces:
  - `procedure UpsertStringLiteral(const AToken: TFileTxToken; const ALit: TStringLiteral);`
  - `procedure DeleteStringLiteralsForFile(AFileId: Int64);`
  - `function SearchText(const AQuery: string; AMode: string; const ASource: string; ALimit: Integer): TArray<TStringLitMatch>;` — `AMode` ∈ `'phrase'|'anyorder'|'substring'`; `ASource` `''` = all.

- [ ] **Step 1: Declare in `ISymbolStore`** (after the DI methods, ~line 127):

```pascal
    // v10: string-content (text) index.
    procedure UpsertStringLiteral(const AToken: TFileTxToken; const ALit: TStringLiteral);
    procedure DeleteStringLiteralsForFile(AFileId: Int64);
    function SearchText(const AQuery: string; AMode: string; const ASource: string; ALimit: Integer): TArray<TStringLitMatch>;
```

- [ ] **Step 2: Add prepared-query fields + decls** in `TSQLiteSymbolStore` (mirror `FQUpsertDiBinding`): `FQUpsertStringLiteral`, `FQDeleteFileStringLiterals: TFDQuery;` and the three method headers in the class.

- [ ] **Step 3: Prepare the queries** in the setup proc (next to `FQUpsertDiBinding:= NewQuery(...)`, ~line 365):

```pascal
  FQUpsertStringLiteral:= NewQuery(
    'INSERT INTO string_literals(file_id, symbol_id, source, kind, owner_name, text, ' +
    '  start_line, start_col, end_line, end_col) ' +
    'VALUES (:fid, :sid, :src, :kind, :owner, :txt, :sl, :sc, :el, :ec)');
  FQDeleteFileStringLiterals:= NewQuery('DELETE FROM string_literals WHERE file_id = :fid');
```

Free both in the destructor next to `FQUpsertDiBinding.Free;`.

- [ ] **Step 4: Implement the methods** (place after `DeleteDiBindingsForFile`, ~line 652). Upsert mirrors `UpsertReference`’s nullable-`sid` idiom:

```pascal
procedure TSQLiteSymbolStore.UpsertStringLiteral(const AToken: TFileTxToken; const ALit: TStringLiteral);
begin
  FQUpsertStringLiteral.ParamByName('fid').AsLargeInt:= AToken.FileId;
  FQUpsertStringLiteral.ParamByName('sid').DataType:= ftLargeint;
  if ALit.SymbolId > 0 then FQUpsertStringLiteral.ParamByName('sid').AsLargeInt:= ALit.SymbolId
  else FQUpsertStringLiteral.ParamByName('sid').Clear;
  FQUpsertStringLiteral.ParamByName('src'  ).AsString  := ALit.Source;
  FQUpsertStringLiteral.ParamByName('kind' ).AsString  := ALit.Kind;
  FQUpsertStringLiteral.ParamByName('owner').AsString  := ALit.OwnerName;
  FQUpsertStringLiteral.ParamByName('txt'  ).AsString  := ALit.Text;
  FQUpsertStringLiteral.ParamByName('sl').AsInteger := ALit.StartLine;
  FQUpsertStringLiteral.ParamByName('sc').AsInteger := ALit.StartCol;
  FQUpsertStringLiteral.ParamByName('el').AsInteger := ALit.EndLine;
  FQUpsertStringLiteral.ParamByName('ec').AsInteger := ALit.EndCol;
  FQUpsertStringLiteral.ExecSQL;
end;

procedure TSQLiteSymbolStore.DeleteStringLiteralsForFile(AFileId: Int64);
begin
  FQDeleteFileStringLiterals.ParamByName('fid').AsLargeInt:= AFileId;
  FQDeleteFileStringLiterals.ExecSQL;  // triggers cascade the FTS 'delete'
end;

function TSQLiteSymbolStore.SearchText(const AQuery: string; AMode: string; const ASource: string; ALimit: Integer): TArray<TStringLitMatch>;
var
  Q   : TFDQuery              ;
  List: TList<TStringLitMatch>;
  M   : TStringLitMatch       ;
  FtsTable, MatchExpr, Sql: string;

  function QuotePhrase(const S: string): string;
  begin // FTS5: wrap in double quotes, doubling embedded quotes -> phrase match
    Result:= '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
  end;

begin
  List:= TList<TStringLitMatch>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FConn;
    if SameText(AMode, 'substring') then
    begin
      FtsTable := 'string_fts_tri';
      MatchExpr:= QuotePhrase(AQuery); // trigram: phrase-quote -> substring match
    end
    else if SameText(AMode, 'anyorder') then
    begin
      FtsTable := 'string_fts';
      MatchExpr:= AQuery; // bare terms -> implicit AND (all words, any order)
    end
    else
    begin
      FtsTable := 'string_fts';
      MatchExpr:= QuotePhrase(AQuery); // default: exact phrase, in order
    end;
    Sql:=
      'SELECT sl.text AS txt, sl.source AS src, sl.kind AS kind, sl.owner_name AS owner, ' +
      '  sl.start_line AS sl_, sl.start_col AS sc_, sl.end_line AS el_, sl.end_col AS ec_, ' +
      '  f.path AS fpath, s.qualified_name AS encl ' +
      'FROM ' + FtsTable + ' ft ' +
      'JOIN string_literals sl ON sl.id = ft.rowid ' +
      'JOIN files f ON f.id = sl.file_id ' +
      'LEFT JOIN symbols s ON s.id = sl.symbol_id ' +
      'WHERE ' + FtsTable + ' MATCH :q ';
    if ASource <> '' then Sql:= Sql + 'AND sl.source = :src ';
    Sql:= Sql + 'ORDER BY f.path, sl.start_line LIMIT :lim';
    Q.SQL.Text:= Sql;
    Q.ParamByName('q').AsString:= MatchExpr;
    if ASource <> '' then Q.ParamByName('src').AsString:= ASource;
    Q.ParamByName('lim').AsInteger:= ALimit;
    Q.Open;
    while not Q.Eof do
    begin
      M:= Default(TStringLitMatch);
      M.Text          := Q.FieldByName('txt'  ).AsString;
      M.Source        := Q.FieldByName('src'  ).AsString;
      M.Kind          := Q.FieldByName('kind' ).AsString;
      M.OwnerName     := Q.FieldByName('owner').AsString;
      M.FilePath      := Q.FieldByName('fpath').AsString;
      M.EnclosingQName:= Q.FieldByName('encl' ).AsString;
      M.StartLine:= Q.FieldByName('sl_').AsInteger; M.StartCol:= Q.FieldByName('sc_').AsInteger;
      M.EndLine  := Q.FieldByName('el_').AsInteger; M.EndCol  := Q.FieldByName('ec_').AsInteger;
      List.Add(M);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    List.Free;
  end;
end;
```

- [ ] **Step 5: Build.** Expected: compiles. (End-to-end search is exercised in Task 8/9.)

- [ ] **Step 6: Commit.**

```bash
git add src/core/DRagLint.Core.Interfaces.pas src/storage/DRagLint.Storage.SQLite.pas
git commit -m "feat(storage): UpsertStringLiteral/DeleteStringLiteralsForFile/SearchText (FTS5)"
```

---

### Task 4: Delphi parser harvest

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (add `HarvestStringLiterals`, call it in `Parse`, fill `Result.Literals`)
- Test: `tests/textindex/harvest_pas.ps1` (asserts via `query --text` after Task 8; here, a unit smoke build)

**Interfaces:**
- Consumes: `TStringLiteral`. Produces: `Result.Literals` populated for `.pas`.

- [ ] **Step 1: Add the harvester.** A full-tree visit collecting `literalString` nodes (the node type already used at `DRagLint.Parser.Delphi13.pas:263`). Classify `kind`; leave `SymbolId=0` (indexer resolves it). Decode `''` → `'`. Skip empty.

```pascal
// v10: collect every non-empty string literal for the text index.
// kind: 'resourcestring' if under a resourcestring section; 'const' if RHS of a
// const decl; 'format' if it carries a % specifier or is arg0 of a Format-family
// call; else 'literal'. SymbolId left 0 (indexer resolves enclosing symbol).
function HarvestStringLiterals(const ARoot: TTSNode; const ASource: TBytes): TArray<TStringLiteral>;
var
  Acc: TList<TStringLiteral>;

  function DecodeLiteral(const ARaw: string): string;
  begin // strip outer quotes, unescape doubled quotes; leave #nn out of scope here
    Result:= ARaw;
    if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
      Result:= Copy(Result, 2, Length(Result) - 2);
    Result:= StringReplace(Result, '''''', '''', [rfReplaceAll]);
  end;

  function ClassifyKind(const N: TTSNode; const ADecoded: string): string;
  var Anc: TTSNode; AncT: string;
  begin
    Result:= 'literal';
    if Pos('%', ADecoded) > 0 then Result:= 'format';
    Anc:= N.Parent;
    while not Anc.IsNull do
    begin
      AncT:= Anc.NodeType;
      if AncT = 'declResourceString' then Exit('resourcestring');     // verify node name in grammar
      if (AncT = 'declConst') or (AncT = 'constDeclaration') then Exit('const');
      Anc:= Anc.Parent;
    end;
  end;

  procedure Visit(const N: TTSNode);
  var I: Integer; Lit: TStringLiteral; Raw, Dec: string; P: TTSPoint;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'literalString' then
    begin
      Raw:= NodeText(N, ASource);            // existing helper in this unit
      Dec:= DecodeLiteral(Raw);
      if Dec <> '' then
      begin
        Lit:= Default(TStringLiteral);
        Lit.Source:= 'pas';
        Lit.Kind  := ClassifyKind(N, Dec);
        Lit.Text  := Dec;
        P:= N.StartPoint; Lit.StartLine:= Integer(P.Row)+1; Lit.StartCol:= Integer(P.Column)+1;
        P:= N.EndPoint;   Lit.EndLine  := Integer(P.Row)+1; Lit.EndCol  := Integer(P.Column)+1;
        Acc.Add(Lit);
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  end;

begin
  Acc:= TList<TStringLiteral>.Create;
  try
    Visit(ARoot);
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;
```

In `TDelphi13Parser.Parse`, after the tree is built and symbols collected, set `Result.Literals:= HarvestStringLiterals(Tree.RootNode, Source);`. **Verify the exact grammar node names** for resourcestring/const during implementation (grep the grammar / a parsed `--ast` dump); adjust `ClassifyKind` accordingly — the `'literal'`/`'format'` paths work regardless.

- [ ] **Step 2: Build.** Expected: compiles.

- [ ] **Step 3: Commit.**

```bash
git add src/parser/DRagLint.Parser.Delphi13.pas
git commit -m "feat(parser): harvest .pas string literals (const/resourcestring/format) for text index"
```

---

### Task 5: DFM parser harvest

**Files:**
- Modify: `src/parser/DRagLint.Parser.DFM.pas` (extend `WalkProperty`/`WalkObject` to emit string property values onto a literals list; add `Literals` to the returned `TParseResult`)

**Interfaces:**
- Produces: `Result.Literals` for `.dfm` (kind `'dfm-prop'`, `OwnerName` = property name).

- [ ] **Step 1:** In `TDfmState`, add `Literals: TList<TStringLiteral>;` (create/free alongside `Symbols`). In `WalkProperty` (`DRagLint.Parser.DFM.pas:112`), when `ValueNode` is a string value, emit a literal:

```pascal
// after PropName is known, before the event-binding check:
if (not ValueNode.IsNull) and (ValueNode.NodeType = 'string_value') then  // verify node name
begin
  var Lit: TStringLiteral; Lit:= Default(TStringLiteral);
  Lit.Source:= 'dfm'; Lit.Kind:= 'dfm-prop'; Lit.OwnerName:= PropName;
  Lit.Text:= DfmDecode(NodeText(ValueNode, AState.Source)); // strip quotes; join 'a'+'b'; decode #nn
  if Lit.Text <> '' then
  begin
    Lit.StartLine:= Integer(ValueNode.StartPoint.row)+1; Lit.StartCol:= Integer(ValueNode.StartPoint.column)+1;
    Lit.EndLine  := Integer(ValueNode.EndPoint.row)+1;   Lit.EndCol  := Integer(ValueNode.EndPoint.column)+1;
    AState.Literals.Add(Lit);
  end;
end;
```

Add a `DfmDecode` helper (strip `'…'`, join `'a' 'b'`/`+` continuations, convert `#13#10` etc. to spaces). In `TDFMParser.Parse`, set `Result.Literals:= State.Literals.ToArray;`. **Verify** the grammar's string-value node name against a parsed DFM (`dfm-valid.dfm` from the prior fix is a handy sample).

- [ ] **Step 2: Build.** Expected: compiles.

- [ ] **Step 3: Commit.**

```bash
git add src/parser/DRagLint.Parser.DFM.pas
git commit -m "feat(parser): harvest DFM string property text for text index"
```

---

### Task 6: SQL parser harvest (EXCEPTION messages)

**Files:**
- Modify: `src/parser/DRagLint.Parser.Sql.pas` (emit the message text of `CREATE EXCEPTION name 'msg'` and PSQL `EXCEPTION name 'msg'`)

**Interfaces:**
- Produces: `Result.Literals` for `.sql` (kind `'sql-exception'`, `OwnerName` = exception name).

- [ ] **Step 1:** The SQL parser already recognizes exceptions (`skSqlException` exists). Locate where exception statements are walked; capture the trailing string-literal argument as the message and emit a `TStringLiteral` (Source `'sql'`, Kind `'sql-exception'`, OwnerName = exception name, Text = decoded `'…'`). If the grammar doesn’t expose the message node distinctly, add a targeted match: for a node whose first token is `EXCEPTION` (or `CREATE EXCEPTION`), take the name token and the following string literal. Skip if no string follows (a bare re-raise).

- [ ] **Step 2: Build.** Expected: compiles.

- [ ] **Step 3: Commit.**

```bash
git add src/parser/DRagLint.Parser.Sql.pas
git commit -m "feat(parser): harvest SQL EXCEPTION messages for text index"
```

---

### Task 7: Indexer wiring (persist + resolve enclosing symbol)

**Files:**
- Modify: `src/core/DRagLint.Core.Indexer.pas` (persist `Result.Literals` in the per-file tx)

**Interfaces:**
- Consumes: `ISymbolStore.UpsertStringLiteral/DeleteStringLiteralsForFile/FindContainingSymbol`, `TParseResult.Literals`.

- [ ] **Step 1:** In the per-file index path (where `UpsertReference`/`UpsertDiBinding` are called within the open file tx, after symbols are upserted so their IDs/ranges exist), add:

```pascal
// v10: text-content index. Resolve each literal's enclosing symbol by line,
// then persist. Per-file delete keeps re-index idempotent (FTS cascades via triggers).
Store.DeleteStringLiteralsForFile(Token.FileId);
for var Lit in ParseResult.Literals do
begin
  var L: TStringLiteral:= Lit;
  L.FileId:= Token.FileId;
  var Encl: TSymbol:= Store.FindContainingSymbol(Token.FileId, L.StartLine);
  if Encl.Id > 0 then L.SymbolId:= Encl.Id;
  Store.UpsertStringLiteral(Token, L);
end;
```

Match the surrounding style/var names in `Core.Indexer.pas` (the loop variable types and the existing `Token`/`Store`/`ParseResult` identifiers — adjust names to the actual ones in that method).

- [ ] **Step 2: Build + stage.**

- [ ] **Step 3: Smoke test:** index the `tests/textindex` fixtures dir (created in Task 9) and confirm via `--selftest-schema`-style count that `string_literals` is non-empty. (Full assertions in Task 9.)

- [ ] **Step 4: Commit.**

```bash
git add src/core/DRagLint.Core.Indexer.pas
git commit -m "feat(indexer): persist string literals + resolve enclosing symbol"
```

---

### Task 8: CLI `query --text`

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (args: `--text`, `--any-order`, `--substring`, `--source`, `--limit`; `DoQueryText`; usage line; dispatch)

**Interfaces:**
- Consumes: `ISymbolStore.SearchText`. Produces: the `query --text` command (text + `--json` output).

- [ ] **Step 1:** Add args to `TArgs` (`TextQuery: string; TextAnyOrder, TextSubstring: Boolean; TextSource: string; Limit: Integer`) and parse them in the arg loop (mirror `--name`). Default `Limit` = 200.

- [ ] **Step 2:** Implement `DoQueryText`:

```pascal
function DoQueryText(const AArgs: TArgs): Integer;
var
  Store  : ISymbolStore;
  Mode   : string;
  Matches: TArray<TStringLitMatch>;
  M      : TStringLitMatch;
  JArr   : TJSONArray; JObj: TJSONObject;
begin
  if AArgs.TextQuery = '' then begin Writeln('ERROR: query --text requires a phrase'); Exit(2); end;
  if AArgs.TextSubstring then Mode:= 'substring'
  else if AArgs.TextAnyOrder then Mode:= 'anyorder'
  else Mode:= 'phrase';
  Store:= OpenStoreForArgs(AArgs);   // reuse the existing multi-db store opener used by query --name
  Matches:= Store.SearchText(AArgs.TextQuery, Mode, AArgs.TextSource, AArgs.Limit);
  if AArgs.AsJson then
  begin
    JArr:= TJSONArray.Create;
    try
      for M in Matches do
      begin
        JObj:= TJSONObject.Create;
        JObj.AddPair('file_path', M.FilePath);
        JObj.AddPair('start_line', TJSONNumber.Create(M.StartLine));
        JObj.AddPair('start_col',  TJSONNumber.Create(M.StartCol));
        JObj.AddPair('source', M.Source); JObj.AddPair('kind', M.Kind);
        JObj.AddPair('owner_name', M.OwnerName); JObj.AddPair('text', M.Text);
        JObj.AddPair('enclosing', M.EnclosingQName);
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally JArr.Free; end;
  end
  else
  begin
    for M in Matches do
      Writeln(Format('%s:%d:%d  [%s/%s]  %s%s', [M.FilePath, M.StartLine, M.StartCol,
        M.Source, M.Kind, M.Text, IfThen(M.EnclosingQName <> '', '  -> ' + M.EnclosingQName, '')]));
    Writeln(Format('%d match(es)', [Length(Matches)]));
  end;
  Result:= IfThen(Length(Matches) > 0, 0, 1);
end;
```

(Use the exact store-opener helper that `query --name` uses for `--db`/manifest selection; `IfThen` from `System.StrUtils`/`System.Math` as already imported.)

- [ ] **Step 3:** Dispatch: in the `query` subcommand handler, if `--text` present route to `DoQueryText`; add a usage line near `DRagLint.CLI.pas:200`:
`Writeln('  drag-lint query --text "<phrase>" [--any-order|--substring] [--source pas|dfm|sql] [--limit N] [--db ...] [--json]');`

- [ ] **Step 4: Build + stage.**

- [ ] **Step 5: Commit.**

```bash
git add src/cli/DRagLint.CLI.pas
git commit -m "feat(cli): query --text (phrase/--any-order/--substring/--source) over the text index"
```

---

### Task 9: End-to-end harness + fixtures

**Files:**
- Create: `tests/textindex/messages.pas`, `captions.dfm`, `exceptions.sql`, `run_textindex_tests.ps1`

**Interfaces:**
- Consumes: the full `index` + `query --text` pipeline.

- [ ] **Step 1: Fixtures** (CRLF). `messages.pas`:

```pascal
unit Messages;
interface
resourcestring
  SFolderNotFound = 'Folder not found';
implementation
const
  CCap = 'Save As';
procedure P;
var Folder: Integer;        // identifier — must NOT match
begin
  Folder := 1;
  WriteLn(Format('%d folders in %s', [Folder, 'root']));
end;
procedure OpenFolder;       // identifier — must NOT match
begin end;
end.
```

`captions.dfm`:

```
object FErr: TFErr
  Caption = 'Folder not found'
  object Lbl: TLabel
    Hint = 'Pick a folder'
  end
end
```

`exceptions.sql`:

```sql
CREATE EXCEPTION e_no_folder 'Folder not found';
```

- [ ] **Step 2: Harness** `run_textindex_tests.ps1` — index the fixtures, then assert each mode via `--json`:

```powershell
$exe = "third_party\dll-win64\drag-lint.exe"
$sb  = "$env:TEMP\dl_textindex"; Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "tests\textindex" $sb -Recurse
$db = "$sb\idx.sqlite"
& $exe index $sb --db $db | Out-Null
function J($args){ ($args | & $exe @args --db $db --json | ConvertFrom-Json) }
$fail = 0
function Check($name,$cond){ if($cond){"PASS $name"} else {"FAIL $name"; $script:fail++} }

$phrase = & $exe query --text "folder not found" --db $db --json | ConvertFrom-Json
Check "phrase finds .pas resourcestring" ($phrase.kind -contains 'resourcestring')
Check "phrase finds .dfm caption"        (($phrase | ? { $_.source -eq 'dfm' }).Count -ge 1)
Check "phrase finds .sql exception"      (($phrase | ? { $_.source -eq 'sql' }).Count -ge 1)
Check "R8: no identifier hits"           (($phrase | ? { $_.text -match '^\s*$' }).Count -eq 0)

$any = & $exe query --text "folder found" --any-order --db $db --json | ConvertFrom-Json
Check "any-order matches" ($any.Count -ge 1)

$sub = & $exe query --text "older" --substring --db $db --json | ConvertFrom-Json
Check "substring 'older' matches 'Folder'" ($sub.Count -ge 1)

$dfm = & $exe query --text "folder" --source dfm --db $db --json | ConvertFrom-Json
Check "source filter dfm" (($dfm | ? { $_.source -ne 'dfm' }).Count -eq 0)

# negative: the *.pas variable/method named Folder must never appear as a hit
$allFolder = & $exe query --text "folder" --substring --db $db --json | ConvertFrom-Json
Check "no var/method 'Folder' as a hit" (($allFolder | ? { $_.text -eq 'Folder' }).Count -eq 0)

if ($fail -gt 0) { Write-Error "$fail textindex test(s) failed"; exit 1 } else { "textindex: all pass" }
```

- [ ] **Step 3: Run — expect FAIL first** if any harvest/query gap remains; fix the responsible task; re-run to green.

Run: `pwsh -File tests\textindex\run_textindex_tests.ps1`
Expected (final): `textindex: all pass`.

- [ ] **Step 4: Commit.**

```bash
git add tests/textindex
git commit -m "test(textindex): end-to-end fixtures + harness (phrase/any-order/substring/source/R8)"
```

---

### Task 10: Docs, rule flip, version bump

**Files:**
- Modify: `CHANGELOG.md`, `README.md`, `src/cli/DRagLint.CLI.pas` (VERSION), `C:\Projects\CLAUDE.md` (flip search rule live)

- [ ] **Step 1: Version** — `DRagLint.CLI.pas`: `VERSION = '0.57.0-alpha';` → `'0.58.0-alpha';`.
- [ ] **Step 2: CHANGELOG** — add a `## v0.58.0-alpha` block: the text-constant index + `query --text` (phrase/any-order/substring), sources pas/dfm/sql(EXCEPTION), FTS5 unicode61+trigram, schema v10.
- [ ] **Step 3: README** — document `query --text` in the query section.
- [ ] **Step 4: Flip the CLAUDE.md rule live** — in `C:\Projects\CLAUDE.md` search rule, change the `query --text` bullet from "_Status: in development … Until it ships, Grep remains the text fallback._" to active wording: text/message/caption search **is** a `query --text` job, not Grep.
- [ ] **Step 5: Remove the temporary `--selftest-schema`** flag if it shouldn't ship (keep `--selftest-fts5`; it's a useful diagnostic), or document both under self-diagnostics.
- [ ] **Step 6: Build + stage; run BOTH harnesses** (`run_lint_tests.ps1` must still be green; `run_textindex_tests.ps1` green).
- [ ] **Step 7: Commit.**

```bash
git add CHANGELOG.md README.md src/cli/DRagLint.CLI.pas
git commit -m "docs+release: text-constant index / query --text (v0.58.0-alpha)"
```

---

## Self-Review

- **Spec coverage:** R1 (Task 4, incl. format via `%`), R2 (Task 5), R3 (Task 6), R4 default phrase + R5 any-order + R6 substring (Task 3 SearchText modes; Task 8 flags), R7 all-locations + enclosing symbol (Task 3 join; Task 7 resolution), R8 text-only negative test (Task 9). Engine FTS5 unicode61+trigram (Tasks 2-3). Migration/reindex (Task 2 + spec §7, surfaced in CHANGELOG). ✓
- **Placeholder scan:** the two "verify the grammar node name" notes (Tasks 4-6) are genuine spikes against the live grammar, not hand-waves — each has a concrete verification path (parse a sample, grep the grammar) and a working fallback (`literal`/`format` classification, or a token-based EXCEPTION match). No TBD/TODO code.
- **Type consistency:** `TStringLiteral`/`TStringLitMatch` fields and the three `ISymbolStore` signatures are used identically across Tasks 1, 3, 7, 8. `SearchText(query, mode, source, limit)` mode strings `'phrase'|'anyorder'|'substring'` match between Task 3 and Task 8.
- **Risk:** trigram index storage on the whole-tree DB — measure after Task 9; if heavy, make `string_fts_tri` opt-in (`index --with-substring`) per spec §4. Noted, not blocking.
