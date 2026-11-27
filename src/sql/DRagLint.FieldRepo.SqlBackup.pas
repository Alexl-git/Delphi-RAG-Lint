unit DRagLint.FieldRepo.SqlBackup;

{ drag-lint 1.56 -- lane BK-Q: `repo backup --format sql` (DDL + INSERT statements) and its restore.
  The --format dispatch lives in DRagLint.CLI.RepoBackup (lane BK-Z), which calls the two routines
  below. Text (DRagLint.FieldRepo.TextBackup) stays the default format.

  File shape (7-bit ASCII, CRLF, one statement per line, so it diffs and stays valid SQLite SQL):
    -- DLREPO-SQL <schema version>
    CREATE TABLE ... ;                              (one per table, the DDL of that schema version)
    INSERT INTO "T" ("A", "B") VALUES (1, 'x');     (one per row, every column, primary-key order)
    -- end T <row count>                            (one trailer per table)
  Strings are '...' segments (quote doubled) joined by || with char(<code point>, ...) for every
  character outside 0x20..0x7E. A restore parses and validates the WHOLE file first
  (ERepoBackupFormatError with the line number), then replaces the rows in ONE transaction. It
  never executes text from the file: only INSERT lines of this exact shape are understood, and the
  CREATE TABLE lines are skipped (the target repository already has its schema). }

interface

uses
  FireDAC.Comp.Client;

/// <summary>Writes the repository as an SQL script: the DDL of every table, then one INSERT per row.</summary>
/// <param name="pConnection">An open repository connection; not nil. The caller owns it.</param>
/// <param name="pFileName">The script file to write; an existing file is replaced.</param>
/// <exception cref="ERepoError">A character above 0x7F survived escaping (a bug).</exception>
/// <remarks>Reads the repository only. Deterministic: the same rows give the same bytes. The file is ASCII,
/// CRLF, written beside the target and renamed over it. Not thread-safe.</remarks>
procedure BackupRepositorySql(pConnection: TFDConnection; const pFileName: string);

/// <summary>Restores a repository from a script written by BackupRepositorySql.</summary>
/// <param name="pConnection">An open, writable repository connection; not nil. The caller owns it.</param>
/// <param name="pFileName">The script file; must exist.</param>
/// <param name="pReplace">True = existing rows are replaced; False = a non-empty repository is refused.</param>
/// <exception cref="ERepoBackupFormatError">The file is malformed; nothing was changed.</exception>
/// <exception cref="ERepoError">The repository is not empty and pReplace is False, or the script is of a newer schema.</exception>
/// <remarks>An older script restored into a newer repository gets the data steps of `repo migrate`. Not thread-safe.</remarks>
procedure RestoreRepositorySql(pConnection: TFDConnection; const pFileName: string; pReplace: Boolean);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Character,
  System.StrUtils,
  Data.DB,
  FireDAC.Stan.Param,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.TextBackup;

const
  SQL_MAGIC = '-- DLREPO-SQL ';
  SQL_END = '-- end ';
  SQL_CREATE = 'CREATE TABLE ';
  SQL_INSERT = 'INSERT INTO ';
  SQL_CHAR_FN = 'char(';
  SQL_CONCAT = ' || ';
  CHAR_FIRST = ' ';
  CHAR_LAST = '~';
  ASCII_LIMIT = $80;
  LF_BYTE = 10;
  HEX_BYTE_DIGITS = 2;
  SURR_HIGH_FIRST = $D800;
  SURR_LOW_FIRST = $DC00;
  SURR_LAST = $DFFF;
  SURR_BASE = $10000;
  SURR_SHIFT = 10;
  CODE_POINT_MAX = $10FFFF;
  NULL_LEN = 4;

type
  TLitMode = (lmNone, lmQuote, lmChar);

  TSqlCell = record
    IsNull: Boolean;
    IsStr: Boolean;
    Str: string;
    Int: Int64;
  end;

  TSqlRow = record
    TableIdx: Integer;
    ColIdx: TArray<Integer>;
    Cells: TArray<TSqlCell>;
  end;

{ ---- backup ---------------------------------------------------------------- }

{ One character outside 0x20..0x7E as a code point; a valid surrogate pair is combined. pIdx advances past the pair. }
function CodePointAt(const pValue: string; var pIdx: Integer): Integer;
begin
  Result := Ord(pValue[pIdx]);
  if (Result >= SURR_HIGH_FIRST) and (Result < SURR_LOW_FIRST) and (pIdx < Length(pValue))
    and (Ord(pValue[pIdx + 1]) >= SURR_LOW_FIRST) and (Ord(pValue[pIdx + 1]) <= SURR_LAST) then
  begin
    Result := SURR_BASE + ((Result - SURR_HIGH_FIRST) shl SURR_SHIFT) + (Ord(pValue[pIdx + 1]) - SURR_LOW_FIRST);
    Inc(pIdx);
  end;
end;

function SqlStringLiteral(const pValue: string): string;
var
  VSb: TStringBuilder;
  VMode: TLitMode;
  VI: Integer;
begin
  if pValue = '' then
    Exit('''''');
  VSb := TStringBuilder.Create;
  try
    VMode := lmNone;
    VI := 1;
    while VI <= Length(pValue) do
    begin
      if (pValue[VI] >= CHAR_FIRST) and (pValue[VI] <= CHAR_LAST) then
      begin
        if VMode <> lmQuote then
        begin
          if VMode = lmChar then
            VSb.Append(')' + SQL_CONCAT);
          VSb.Append('''');
          VMode := lmQuote;
        end;
        VSb.Append(if pValue[VI] = '''' then '''''' else string(pValue[VI]));
      end
      else
      begin
        if VMode = lmChar then
          VSb.Append(', ')
        else
        begin
          if VMode = lmQuote then
            VSb.Append('''' + SQL_CONCAT);
          VSb.Append(SQL_CHAR_FN);
          VMode := lmChar;
        end;
        VSb.Append(CodePointAt(pValue, VI));
      end;
      Inc(VI);
    end;
    VSb.Append(if VMode = lmQuote then '''' else ')');
    Result := VSb.ToString;
  finally
    VSb.Free;
  end;
end;

function CellLiteral(pField: TField; const pCol: TRepoColumn): string;
begin
  if pField.IsNull then
    Exit('NULL');
  case pCol.Kind of
    rckString, rckText: Result := SqlStringLiteral(pField.AsString);
    rckBoolean: Result := if pField.AsBoolean then '1' else '0';
  else
    Result := IntToStr(pField.AsLargeInt);
  end;
end;

function OneLine(const pDdl: string): string;
begin
  Result := StringReplace(StringReplace(pDdl, sLineBreak + '  ', ' ', [rfReplaceAll]), sLineBreak, ' ', [rfReplaceAll]);
end;

function OrderBy(const pTable: TRepoTable): string;
var
  VKey: TRepoColumn;
begin
  Result := '';
  for VKey in pTable.PkColumns do
    Result := Result + IfThen(Result = '', '', ', ') + QuoteRepoIdent(VKey.Name);
  if Result = '' then
    Result := '1';
end;

procedure AddTableRows(pConnection: TFDConnection; const pTable: TRepoTable; pLines: TStrings);
var
  VQuery: TFDQuery;
  VCol: TRepoColumn;
  VHead, VVals: string;
  VCount: Integer;
begin
  VHead := '';
  for VCol in pTable.Columns do
    VHead := VHead + IfThen(VHead = '', '', ', ') + QuoteRepoIdent(VCol.Name);
  VHead := SQL_INSERT + QuoteRepoIdent(pTable.Name) + ' (' + VHead + ') VALUES (';
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pConnection;
    VQuery.FormatOptions.StrsTrim := False;
    VQuery.FormatOptions.StrsEmpty2Null := False;
    VQuery.SQL.Text := 'SELECT * FROM ' + QuoteRepoIdent(pTable.Name) + ' ORDER BY ' + OrderBy(pTable);
    VQuery.Open;
    VCount := 0;
    while not VQuery.Eof do
    begin
      VVals := '';
      for VCol in pTable.Columns do
        VVals := VVals + IfThen(VVals = '', '', ', ') + CellLiteral(VQuery.FieldByName(VCol.Name), VCol);  // dl:ok field-by-name-in-loop -- REVIEWED BK-Q 2026-11-27: columns are the loop; one lookup per cell -- REVIEWED BK-Q 2026-11-27: one row's few columns
      pLines.Add(VHead + VVals + ');');
      Inc(VCount);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
  pLines.Add(SQL_END + pTable.Name + ' ' + IntToStr(VCount));
end;

procedure BackupRepositorySql(pConnection: TFDConnection; const pFileName: string);
var
  VLines: TStringList;
  VTable: TRepoTable;
  VVersion, VI: Integer;
  VText, VTmp: string;
begin
  VLines := TStringList.Create;
  try
    VVersion := RepoSchemaVersion(pConnection);
    VLines.Add(SQL_MAGIC + IntToStr(VVersion));
    for VTable in RepoTablesFor(VVersion) do
      VLines.Add(OneLine(RepoTableDdl(VTable)) + ';');
    for VTable in RepoTablesFor(VVersion) do
      AddTableRows(pConnection, VTable, VLines);
    VLines.LineBreak := #13#10;
    VText := VLines.Text;
  finally
    VLines.Free;
  end;
  for VI := 1 to Length(VText) do
    if Ord(VText[VI]) >= ASCII_LIMIT then
      raise ERepoError.Create('SQL backup produced a non-ASCII character (bug)');
  VTmp := pFileName + '.tmp';
  TFile.WriteAllBytes(VTmp, TEncoding.ASCII.GetBytes(VText));
  try
    if TFile.Exists(pFileName) then
      TFile.Delete(pFileName);  // dl:ok stat-gated-destructive -- REVIEWED BK-Q 2026-11-27: the file is our own backup target and TFile.Move needs the name free; a failed stat only skips the delete and the move then raises
    TFile.Move(VTmp, pFileName);
  except
    if TFile.Exists(VTmp) then
      TFile.Delete(VTmp);
    raise;
  end;
end;

{ ---- restore: parse -------------------------------------------------------- }

type
  TSqlParser = class
  private
    FLines: TStrings;
    FNo: Integer;
    FLine: string;
    FPos: Integer;
    FTables: TArray<TRepoTable>;
    FCounts: TArray<Integer>;
    FEnded: TArray<Boolean>;
    procedure Fail(const pMessage: string);
    procedure SkipWs;
    function Peek: Char;
    procedure Expect(const pText: string);
    function Ident: string;
    function Number: Int64;
    function Literal: TSqlCell;
    function StringExpr: string;
    function TableIndex(const pName: string): Integer;
    procedure ParseInsert;
    procedure ParseTrailer;
  public
    Version: Integer;
    Rows: TArray<TSqlRow>;
    constructor Create(pLines: TStrings);
    procedure Parse;
    property Tables: TArray<TRepoTable> read FTables;
  end;

constructor TSqlParser.Create(pLines: TStrings);
begin
  inherited Create;
  FLines := pLines;
end;

procedure TSqlParser.Fail(const pMessage: string);
begin
  raise ERepoBackupFormatError.CreateAt(FNo, pMessage);
end;

function TSqlParser.Peek: Char;
begin
  Result := if FPos <= Length(FLine) then FLine[FPos] else #0;
end;

procedure TSqlParser.SkipWs;
begin
  while Peek = ' ' do
    Inc(FPos);
end;

procedure TSqlParser.Expect(const pText: string);
begin
  SkipWs;
  if Copy(FLine, FPos, Length(pText)) <> pText then
    Fail('expected ' + pText);
  Inc(FPos, Length(pText));
end;

function TSqlParser.Ident: string;
var
  VEnd: Integer;
begin
  Expect('"');
  VEnd := PosEx('"', FLine, FPos);
  if VEnd = 0 then
    Fail('unterminated identifier');
  Result := Copy(FLine, FPos, VEnd - FPos);
  FPos := VEnd + 1;
end;

function TSqlParser.Number: Int64;
var
  VStart: Integer;
begin
  SkipWs;
  VStart := FPos;
  if Peek = '-' then
    Inc(FPos);
  while CharInSet(Peek, ['0'..'9']) do
    Inc(FPos);
  if not TryStrToInt64(Copy(FLine, VStart, FPos - VStart), Result) then
    Fail('bad number');
end;

function TSqlParser.StringExpr: string;
var
  VEnd: Integer;
  VCp: Int64;
begin
  Result := '';
  repeat
    SkipWs;
    if Peek = '''' then
    begin
      Inc(FPos);
      repeat
        VEnd := PosEx('''', FLine, FPos);
        if VEnd = 0 then
          Fail('unterminated string');
        Result := Result + Copy(FLine, FPos, VEnd - FPos);  // dl:ok concat-in-loop -- REVIEWED BK-Q 2026-11-27: one line of a script
        FPos := VEnd + 1;
        if Peek <> '''' then
          Break;
        Result := Result + '''';  // dl:ok concat-in-loop -- REVIEWED BK-Q 2026-11-27: one line of a script
        Inc(FPos);
      until False;
    end
    else if SameText(Copy(FLine, FPos, Length(SQL_CHAR_FN)), SQL_CHAR_FN) then
    begin
      Inc(FPos, Length(SQL_CHAR_FN));
      repeat
        VCp := Number;
        if (VCp < 0) or (VCp > CODE_POINT_MAX) then
          Fail('bad code point');
        if (VCp >= SURR_HIGH_FIRST) and (VCp <= SURR_LAST) then
          Result := Result + Char(Word(VCp))  // dl:ok concat-in-loop -- REVIEWED BK-Q 2026-11-27: one line of a script
        else
          Result := Result + TCharacter.ConvertFromUtf32(Integer(VCp));  // dl:ok concat-in-loop -- REVIEWED BK-Q 2026-11-27: one line of a script
        SkipWs;
        if Peek <> ',' then
          Break;
        Inc(FPos);
      until False;
      Expect(')');
    end
    else
      Fail('bad string expression');
    SkipWs;
    if Copy(FLine, FPos, 2) <> '||' then
      Break;
    Inc(FPos, 2);
  until False;
end;

function TSqlParser.Literal: TSqlCell;
begin
  Result := Default(TSqlCell);
  SkipWs;
  if SameText(Copy(FLine, FPos, NULL_LEN), 'NULL') then
  begin
    Inc(FPos, NULL_LEN);
    Result.IsNull := True;
  end
  else if (Peek = '''') or SameText(Copy(FLine, FPos, Length(SQL_CHAR_FN)), SQL_CHAR_FN) then
  begin
    Result.IsStr := True;
    Result.Str := StringExpr;
  end
  else
    Result.Int := Number;
end;

function TSqlParser.TableIndex(const pName: string): Integer;
var
  VI: Integer;
begin
  for VI := 0 to High(FTables) do
    if FTables[VI].Name = pName then
      Exit(VI);
  Fail('unknown table ' + pName);
  Result := -1;
end;

procedure TSqlParser.ParseInsert;
var
  VRow: TSqlRow;
  VTable: TRepoTable;
  VName: string;
  VCol: TRepoColumn;
  VCell: TSqlCell;
  VN, VK: Integer;
begin
  FPos := Length(SQL_INSERT) + 1;
  VRow := Default(TSqlRow);
  VRow.TableIdx := TableIndex(Ident);
  VTable := FTables[VRow.TableIdx];
  Expect('(');
  repeat
    VName := Ident;
    if not VTable.FindColumn(VName, VCol) then
      Fail('unknown column ' + VName);
    VN := Length(VRow.ColIdx);
    SetLength(VRow.ColIdx, VN + 1);
    for VK := 0 to High(VTable.Columns) do
      if VTable.Columns[VK].Name = VName then
        VRow.ColIdx[VN] := VK;
    SkipWs;
    if Peek <> ',' then
      Break;
    Inc(FPos);
  until False;
  Expect(') VALUES (');
  for VN := 0 to High(VRow.ColIdx) do
  begin
    if VN > 0 then
      Expect(',');
    VCell := Literal;
    VCol := VTable.Columns[VRow.ColIdx[VN]];
    if VCell.IsNull then
    begin
      if VCol.PkOrder > 0 then
        Fail('NULL in key column ' + VCol.Name);
    end
    else
    begin
      if (VCol.Kind in [rckString, rckText]) <> VCell.IsStr then
        Fail('value type does not fit column ' + VCol.Name);
      if (VCol.Kind = rckBoolean) and ((VCell.Int < 0) or (VCell.Int > 1)) then
        Fail('boolean column ' + VCol.Name + ' needs 0 or 1');
    end;
    VRow.Cells := VRow.Cells + [VCell];
  end;
  Expect(');');
  SkipWs;
  if FPos <= Length(FLine) then
    Fail('text after the statement');
  Inc(FCounts[VRow.TableIdx]);
  Rows := Rows + [VRow];
end;

procedure TSqlParser.ParseTrailer;
var
  VRest: string;
  VSp, VIdx, VWant: Integer;
begin
  VRest := Copy(FLine, Length(SQL_END) + 1, MaxInt);
  VSp := LastDelimiter(' ', VRest);
  if (VSp = 0) or not TryStrToInt(Copy(VRest, VSp + 1, MaxInt), VWant) then
    Fail('bad trailer');
  VIdx := TableIndex(Copy(VRest, 1, VSp - 1));
  if FEnded[VIdx] then
    Fail('duplicate trailer');
  if FCounts[VIdx] <> VWant then
    Fail('trailer says ' + IntToStr(VWant) + ' rows, found ' + IntToStr(FCounts[VIdx]));
  FEnded[VIdx] := True;
end;

procedure TSqlParser.Parse;
var
  VI: Integer;
begin
  FNo := 1;
  if (FLines.Count = 0) or not StartsStr(SQL_MAGIC, FLines[0]) then
    Fail('not a drag-lint SQL backup (first line must be ' + Trim(SQL_MAGIC) + ' <n>)');
  if not TryStrToInt(Copy(FLines[0], Length(SQL_MAGIC) + 1, MaxInt), Version)
    or (Version < REPO_SCHEMA_MIN_VERSION) or (Version > REPO_SCHEMA_VERSION) then
    Fail('unsupported schema version');
  FTables := RepoTablesFor(Version);
  SetLength(FCounts, Length(FTables));
  SetLength(FEnded, Length(FTables));
  for VI := 1 to FLines.Count - 1 do
  begin
    FNo := VI + 1;
    FLine := FLines[VI];
    FPos := 1;
    if FLine = '' then
      Continue;
    if StartsStr(SQL_INSERT, FLine) then
      ParseInsert
    else if StartsStr(SQL_END, FLine) then
      ParseTrailer
    else if not (StartsStr(SQL_CREATE, FLine) and EndsStr(';', FLine)) then
      Fail('line is not part of the SQL backup grammar');
  end;
  FNo := FLines.Count + 1;
  for VI := 0 to High(FEnded) do
    if not FEnded[VI] then
      Fail('truncated: no trailer for ' + FTables[VI].Name);
end;

{ ---- restore: write -------------------------------------------------------- }

function ParamType(pKind: TRepoColKind): TFieldType;
begin
  case pKind of
    rckString, rckText: Result := ftWideString;
    rckBoolean: Result := ftBoolean;
    rckInteger: Result := ftLargeint;
  else
    Result := ftSmallint;
  end;
end;

procedure BindCell(pParam: TFDParam; const pCol: TRepoColumn; const pCell: TSqlCell);
begin
  pParam.ParamType := ptInput;
  pParam.DataType := ParamType(pCol.Kind);
  if pCell.IsNull then
    pParam.Clear
  else
    case pCol.Kind of
      rckString, rckText: pParam.AsWideString := pCell.Str;
      rckBoolean: pParam.AsBoolean := pCell.Int = 1;
      rckInteger: pParam.AsLargeInt := pCell.Int;
    else
      pParam.AsSmallInt := pCell.Int;
    end;
end;

procedure InsertRows(pConnection: TFDConnection; pParser: TSqlParser);
var
  VRow: TSqlRow;
  VTable: TRepoTable;
  VQuery: TFDQuery;
  VCols, VVals: string;
  VN: Integer;
begin
  for VTable in RepoTablesFor(RepoSchemaVersion(pConnection)) do
    pConnection.ExecSQL('DELETE FROM ' + QuoteRepoIdent(VTable.Name));
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pConnection;
    VQuery.FormatOptions.StrsTrim := False;
    VQuery.FormatOptions.StrsEmpty2Null := False;
    for VRow in pParser.Rows do
    begin
      VTable := pParser.Tables[VRow.TableIdx];
      VCols := '';
      VVals := '';
      for VN := 0 to High(VRow.ColIdx) do
      begin
        VCols := VCols + IfThen(VN = 0, '', ', ') + QuoteRepoIdent(VTable.Columns[VRow.ColIdx[VN]].Name);  // dl:ok concat-in-loop -- REVIEWED BK-Q 2026-11-27: one row's few columns
        VVals := VVals + IfThen(VN = 0, '', ', ') + ':p' + IntToStr(VN);  // dl:ok concat-in-loop -- REVIEWED BK-Q 2026-11-27: one row's few columns
      end;
      VQuery.SQL.Text := 'INSERT INTO ' + QuoteRepoIdent(VTable.Name) + ' (' + VCols + ') VALUES (' + VVals + ')';
      for VN := 0 to High(VRow.ColIdx) do
        BindCell(VQuery.Params[VN], VTable.Columns[VRow.ColIdx[VN]], VRow.Cells[VN]);
      VQuery.ExecSQL;
    end;
  finally
    VQuery.Free;
  end;
end;

function AnyTableHasRows(pConnection: TFDConnection): Boolean;
var
  VTable: TRepoTable;
begin
  for VTable in RepoTablesFor(RepoSchemaVersion(pConnection)) do
    if (VTable.Name <> REPO_META_TABLE) and (RepoRowCount(pConnection, VTable.Name) > 0) then
      Exit(True);
  Result := False;
end;

procedure SplitLines(const pBytes: TBytes; pLines: TStrings);
var
  VI, VLineNo, VStart, VPos: Integer;
  VText, VLine: string;
begin
  VLineNo := 1;
  for VI := 0 to High(pBytes) do
  begin
    if pBytes[VI] >= ASCII_LIMIT then
      raise ERepoBackupFormatError.CreateAt(VLineNo, 'non-ASCII byte 0x' + IntToHex(pBytes[VI], HEX_BYTE_DIGITS));
    if pBytes[VI] = LF_BYTE then
      Inc(VLineNo);
  end;
  VText := TEncoding.ASCII.GetString(pBytes);
  VStart := 1;
  while VStart <= Length(VText) do
  begin
    VPos := PosEx(#10, VText, VStart);
    if VPos = 0 then
      VPos := Length(VText) + 1;
    VLine := Copy(VText, VStart, VPos - VStart);
    if EndsStr(#13, VLine) then
      SetLength(VLine, Length(VLine) - 1);
    pLines.Add(VLine);
    VStart := VPos + 1;
  end;
end;

procedure RestoreRepositorySql(pConnection: TFDConnection; const pFileName: string; pReplace: Boolean);
var
  VLines: TStringList;
  VParser: TSqlParser;
begin
  VLines := TStringList.Create;
  try
    SplitLines(TFile.ReadAllBytes(pFileName), VLines);
    VParser := TSqlParser.Create(VLines);
    try
      VParser.Parse;
      if VParser.Version > RepoSchemaVersion(pConnection) then
        raise ERepoError.CreateFmt('backup schema %d does not match repository schema %d: migrate first (repo migrate --apply)',
          [VParser.Version, RepoSchemaVersion(pConnection)]);
      if (not pReplace) and AnyTableHasRows(pConnection) then
        raise ERepoError.Create('the repository already holds rows; restore needs replace');
      pConnection.StartTransaction;
      try
        InsertRows(pConnection, VParser);
        if VParser.Version < RepoSchemaVersion(pConnection) then
          MigrateRepoRows(pConnection, VParser.Version, RepoSchemaVersion(pConnection));
        pConnection.Commit;
      except
        on Exception do
        begin
          pConnection.Rollback;
          raise;
        end;
      end;
    finally
      VParser.Free;
    end;
  finally
    VLines.Free;
  end;
end;

end.
