unit DRagLint.FieldRepo.ConstGen;

{ drag-lint 1.53 -- lane FR-CONSTGEN: `repo gen-const`, the registry-constant generator
  (docs\superpowers\specs\2026-11-22-field-repository-v2-design.md section 7, FR-1).
  Reads an open repository and returns the source of ONE unit, shared by SERVER and CLIENT,
  that carries every row of the chosen tables as constant record arrays (the read-only
  replacement for the FIB$ tables) and, with --memtable, a Fill<Table> procedure per table
  that loads the rows into a TFDMemTable under the FIB$ field names. The tables and their
  columns come from RepoTablesFor(schema version of the repository), so v1 and v2 both work. }

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client;

type
  /// <summary>Raised for a bad option: an unknown or refused table, or a unit name that is not an identifier.</summary>
  EConstGenError = class(Exception);

  /// <summary>What to generate.</summary>
  TConstGenOptions = record
    /// <summary>Name of the generated unit; must be a Pascal identifier.</summary>
    UnitName: string;
    /// <summary>Base name of the source repository, written into the header comment.</summary>
    SourceName: string;
    /// <summary>Tables to emit (e.g. DL_ENUMVALUES); empty means the four registry tables DL_FIELDS_INFO, DL_DATASETS_INFO, DL_ENUMVALUES, DL_ERROR_MESSAGES.</summary>
    Tables: TArray<string>;
    /// <summary>True adds a Fill&lt;Table&gt; procedure per table (uses FireDAC.Comp.Client).</summary>
    MemTable: Boolean;
  end;

  /// <summary>Row count of one table to be generated (the --dry-run report).</summary>
  TConstGenCount = record
    /// <summary>Repository table name.</summary>
    Table: string;
    /// <summary>Number of rows the generated array holds.</summary>
    Rows: Integer;
  end;

/// <summary>Renders a string as a Pascal expression: apostrophes doubled, characters below 0x20
/// or above 0x7E as #nnn (CRLF is #13#10), long text split into pieces joined by " +" and a line break.</summary>
/// <param name="pText">Any string; may be empty.</param>
/// <param name="pContIndent">Prefix of every continuation line (default none).</param>
/// <returns>A literal, 7-bit ASCII, CRLF between pieces, every piece at most 200 characters; '' for the empty string.</returns>
/// <remarks>Pure; thread-safe.</remarks>
function PasStringLiteral(const pText: string; const pContIndent: string = ''): string;

/// <summary>True when pName is a Pascal identifier (letter or underscore, then letters, digits, underscores; 7-bit ASCII).</summary>
/// <param name="pName">Candidate unit name.</param>
/// <returns>True for an identifier.</returns>
function IsPasIdent(const pName: string): Boolean;

/// <summary>Counts the rows each selected table would contribute, without generating anything.</summary>
/// <param name="pConn">Open repository connection (read only).</param>
/// <param name="pOptions">Selection; UnitName is not used.</param>
/// <returns>One entry per selected table, in generation order.</returns>
/// <exception cref="EConstGenError">A table is unknown for the repository's schema version or is never generated
/// (DL_META, DL_EXCEPTIONS, DL_LAYOUT_EVENTS, DL_DOMAINS, DL_CONSTRAINTS, DL_CONSTRAINT_COLUMNS, DL_GENERATORS).</exception>
function CountConstRows(pConn: TFDConnection; const pOptions: TConstGenOptions): TArray<TConstGenCount>;

/// <summary>Generates the registry unit.</summary>
/// <param name="pConn">Open repository connection (read only); never modified.</param>
/// <param name="pOptions">Unit name, source name, table selection, memtable switch.</param>
/// <returns>The unit source: 7-bit ASCII, CRLF, identical bytes for identical repository content.</returns>
/// <exception cref="EConstGenError">UnitName is not an identifier, or a table is unknown or refused.</exception>
/// <remarks>Pure over the connection. Rows are in primary-key order; a column that holds a NULL in the data gets a
/// companion field &lt;Col&gt;IsNull; a table with no rows gets only &lt;TABLE&gt;_ROW_COUNT = 0 (Delphi has no empty constant array).
/// Not thread-safe over one connection.</remarks>
function GenRepoConstUnit(pConn: TFDConnection; const pOptions: TConstGenOptions): string;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.Math,
  Data.DB,
  DRagLint.FieldRepo.Schema;

const
  CRLF = #13#10;
  PIECE_MAX = 200;
  PRINT_FIRST = #32;
  PRINT_LAST = #126;
  INDENT1 = '  ';
  INDENT2 = '    ';
  INDENT3 = '      ';
  INDENT4 = '        ';
  FIELD_PIECE_INDENT = INDENT4;
  REFUSED_TABLES: array[0..6] of string = ('DL_META', 'DL_EXCEPTIONS', 'DL_LAYOUT_EVENTS', 'DL_DOMAINS',
    'DL_CONSTRAINTS', 'DL_CONSTRAINT_COLUMNS', 'DL_GENERATORS');

type
  TTableData = record
    Table: TRepoTable;
    NullCols: TArray<Boolean>;
    Rows: Integer;
  end;

function IsPrintAscii(pC: Char): Boolean;
begin
  Result := InRange(Ord(pC), Ord(PRINT_FIRST), Ord(PRINT_LAST));
end;

function IsIdentChar(pC: Char; pFirst: Boolean): Boolean;
begin
  Result := CharInSet(pC, ['A'..'Z', 'a'..'z', '_']) or ((not pFirst) and CharInSet(pC, ['0'..'9']));
end;

function IsPasIdent(const pName: string): Boolean;
var
  VI: Integer;
begin
  Result := pName <> '';
  for VI := 1 to Length(pName) do
    if not IsIdentChar(pName[VI], VI = 1) then
      Exit(False);
end;

function DefaultConstTables: TArray<string>;
begin
  Result := ['DL_FIELDS_INFO', 'DL_DATASETS_INFO', 'DL_ENUMVALUES', 'DL_ERROR_MESSAGES'];
end;

{ Rendered length of one character given whether a quote is open. }
function CharCost(pC: Char; pInQuote: Boolean): Integer;
begin
  Result := if IsPrintAscii(pC) then
    (if pInQuote then 0 else 1) + (if pC = '''' then 2 else 1)
  else
    (if pInQuote then 1 else 0) + 1 + Length(IntToStr(Ord(pC)));
end;

function PasStringLiteral(const pText: string; const pContIndent: string): string;
var
  VSb, VPiece: TStringBuilder;
  VI: Integer;
  VC: Char;
  VInQuote: Boolean;
begin
  if pText = '' then
    Exit('''''');
  VSb := TStringBuilder.Create;
  VPiece := TStringBuilder.Create;
  try
    VInQuote := False;
    for VI := 1 to Length(pText) do
    begin
      VC := pText[VI];
      if (VPiece.Length > 0) and (VPiece.Length + CharCost(VC, VInQuote) + 1 > PIECE_MAX) then
      begin
        if VInQuote then
          VPiece.Append('''');
        if VSb.Length > 0 then
          VSb.Append(' +').Append(CRLF).Append(pContIndent);
        VSb.Append(VPiece.ToString);
        VPiece.Clear;
        VInQuote := False;
      end;
      if IsPrintAscii(VC) then
      begin
        if not VInQuote then
          VPiece.Append('''');
        VInQuote := True;
        if VC = '''' then
          VPiece.Append('''''')
        else
          VPiece.Append(VC);
      end
      else
      begin
        if VInQuote then
          VPiece.Append('''');
        VInQuote := False;
        VPiece.Append('#').Append(IntToStr(Ord(VC)));
      end;
    end;
    if VInQuote then
      VPiece.Append('''');
    if VSb.Length > 0 then
      VSb.Append(' +').Append(CRLF).Append(pContIndent);
    VSb.Append(VPiece.ToString);
    Result := VSb.ToString;
  finally
    VPiece.Free;
    VSb.Free;
  end;
end;

function IsRefused(const pName: string): Boolean;
var
  VR: string;
begin
  Result := False;
  for VR in REFUSED_TABLES do
    if SameText(VR, pName) then
      Exit(True);
end;

{ Resolves the requested names to table descriptions of the repository's schema version. }
function SelectTables(pConn: TFDConnection; const pOptions: TConstGenOptions): TArray<TRepoTable>;
var
  VNames: TArray<string>;
  VName: string;
  VAll: TArray<TRepoTable>;
  VTab: TRepoTable;
  VFound: Boolean;
begin
  VNames := pOptions.Tables;
  if Length(VNames) = 0 then
    VNames := DefaultConstTables;
  VAll := RepoTablesFor(RepoSchemaVersion(pConn));
  Result := nil;
  for VName in VNames do
  begin
    if IsRefused(VName) then
      raise EConstGenError.Create('table ' + VName + ' is never generated');
    VFound := False;
    for VTab in VAll do
      if SameText(VTab.Name, VName) then
      begin
        Result := Result + [VTab];
        VFound := True;
        Break;
      end;
    if not VFound then
      raise EConstGenError.Create('unknown table ' + VName + ' for this repository schema');
  end;
end;

function OrderBy(const pTable: TRepoTable): string;
var
  VKey: TRepoColumn;
begin
  Result := '';
  for VKey in pTable.PkColumns do
    Result := Result + IfThen(Result = '', '', ', ') + QuoteRepoIdent(VKey.Name);
end;

{ A closed query over the whole table in primary-key order; the caller opens it inside its try-finally. }
function NewQuery(pConn: TFDConnection; const pTable: TRepoTable): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := pConn;
  Result.FormatOptions.StrsTrim := False;
  Result.FormatOptions.StrsEmpty2Null := False;
  Result.SQL.Text := 'SELECT * FROM ' + QuoteRepoIdent(pTable.Name) + ' ORDER BY ' + OrderBy(pTable);
end;

{ The query's fields in the table's column order, resolved once. }
function ColumnFields(pQuery: TFDQuery; const pTable: TRepoTable): TArray<TField>;
var
  VI: Integer;
begin
  SetLength(Result, Length(pTable.Columns));
  for VI := 0 to High(pTable.Columns) do
  begin
    Result[VI] := pQuery.FindField(pTable.Columns[VI].Name);
    if Result[VI] = nil then
      raise EConstGenError.Create('table ' + pTable.Name + ' has no column ' + pTable.Columns[VI].Name);
  end;
end;

{ One pass over the table: row count and which columns hold a NULL. }
function ScanTable(pConn: TFDConnection; const pTable: TRepoTable): TTableData;
var
  VQ: TFDQuery;
  VFields: TArray<TField>;
  VI: Integer;
begin
  Result.Table := pTable;
  Result.Rows := 0;
  SetLength(Result.NullCols, Length(pTable.Columns));
  VQ := NewQuery(pConn, pTable);
  try
    VQ.Open;
    VFields := ColumnFields(VQ, pTable);
    while not VQ.Eof do
    begin
      Inc(Result.Rows);
      for VI := 0 to High(VFields) do
        if VFields[VI].IsNull then
          Result.NullCols[VI] := True;
      VQ.Next;
    end;
  finally
    VQ.Free;
  end;
end;

function CountConstRows(pConn: TFDConnection; const pOptions: TConstGenOptions): TArray<TConstGenCount>;
var
  VTabs: TArray<TRepoTable>;
  VI: Integer;
begin
  VTabs := SelectTables(pConn, pOptions);
  SetLength(Result, Length(VTabs));
  for VI := 0 to High(VTabs) do
  begin
    Result[VI].Table := VTabs[VI].Name;
    Result[VI].Rows := RepoRowCount(pConn, VTabs[VI].Name);
  end;
end;

{ ---- emission ------------------------------------------------------------ }

function PasType(pKind: TRepoColKind): string;
begin
  case pKind of
    rckInteger: Result := 'Integer';
    rckSmallint: Result := 'SmallInt';
    rckBoolean: Result := 'Boolean';
    rckByte: Result := 'Byte';
  else
    Result := 'string';
  end;
end;

function EmptyValue(pKind: TRepoColKind): string;
begin
  case pKind of
    rckInteger, rckSmallint, rckByte: Result := '0';
    rckBoolean: Result := 'False';
  else
    Result := '''''';
  end;
end;

function ValueLiteral(pField: TField; pKind: TRepoColKind; const pIndent: string): string;
begin
  case pKind of
    rckInteger, rckSmallint, rckByte: Result := IntToStr(pField.AsLargeInt);
    rckBoolean: Result := if pField.AsBoolean then 'True' else 'False';
  else
    Result := PasStringLiteral(pField.AsString, pIndent);
  end;
end;

function RecordName(const pTable: TRepoTable): string;
begin
  Result := 'T' + pTable.Name + 'Row';
end;

function FieldDefLine(const pCol: TRepoColumn): string;
begin
  case pCol.Kind of
    rckInteger: Result := 'ftInteger';
    rckSmallint, rckByte: Result := 'ftSmallint';
    rckBoolean: Result := 'ftBoolean';
  else
    Result := 'ftWideMemo';
  end;
end;

function AccessorName(pKind: TRepoColKind): string;
begin
  case pKind of
    rckInteger, rckSmallint, rckByte: Result := 'AsInteger';
    rckBoolean: Result := 'AsBoolean';
  else
    Result := 'AsString';
  end;
end;

procedure EmitRecordType(pSb: TStringBuilder; const pData: TTableData);
var
  VI: Integer;
  VCol: TRepoColumn;
begin
  pSb.Append(INDENT1).Append('/// <summary>One row of ').Append(pData.Table.Name).Append('.</summary>').Append(CRLF);
  pSb.Append(INDENT1).Append(RecordName(pData.Table)).Append(' = record').Append(CRLF);
  for VI := 0 to High(pData.Table.Columns) do
  begin
    VCol := pData.Table.Columns[VI];
    pSb.Append(INDENT2).Append(VCol.Name).Append(': ').Append(PasType(VCol.Kind)).Append(';').Append(CRLF);
    if pData.NullCols[VI] then
      pSb.Append(INDENT2).Append(VCol.Name).Append('IsNull: Boolean;').Append(CRLF);
  end;
  pSb.Append(INDENT1).Append('end;').Append(CRLF).Append(CRLF);
end;

procedure EmitRow(pSb: TStringBuilder; const pFields: TArray<TField>; const pData: TTableData; pLast: Boolean);
var
  VI: Integer;
  VCol: TRepoColumn;
  VField: TField;
  VIsLastCol: Boolean;
  VText, VSep: string;
begin
  pSb.Append(INDENT2).Append('(').Append(CRLF);
  for VI := 0 to High(pData.Table.Columns) do
  begin
    VCol := pData.Table.Columns[VI];
    VField := pFields[VI];
    VIsLastCol := VI = High(pData.Table.Columns);
    VSep := if VIsLastCol then '' else ';';
    VText := if VField.IsNull then EmptyValue(VCol.Kind) else ValueLiteral(VField, VCol.Kind, FIELD_PIECE_INDENT);
    if pData.NullCols[VI] then
    begin
      pSb.Append(INDENT3).Append(VCol.Name).Append(': ').Append(VText).Append(';').Append(CRLF);
      pSb.Append(INDENT3).Append(VCol.Name).Append('IsNull: ').Append(if VField.IsNull then 'True' else 'False')
        .Append(VSep).Append(CRLF);
    end
    else
      pSb.Append(INDENT3).Append(VCol.Name).Append(': ').Append(VText).Append(VSep).Append(CRLF);
  end;
  pSb.Append(INDENT2).Append(')').Append(if pLast then '' else ',').Append(CRLF);
end;

procedure EmitConsts(pSb: TStringBuilder; pConn: TFDConnection; const pData: TTableData);
var
  VQ: TFDQuery;
  VFields: TArray<TField>;
  VN: Integer;
begin
  pSb.Append(INDENT1).Append('/// <summary>Number of rows in ').Append(pData.Table.Name).Append('.</summary>').Append(CRLF);
  pSb.Append(INDENT1).Append(pData.Table.Name).Append('_ROW_COUNT = ').Append(IntToStr(pData.Rows)).Append(';')
    .Append(CRLF).Append(CRLF);
  if pData.Table.SourceName <> '' then
  begin
    pSb.Append(INDENT1).Append('/// <summary>Name of the Firebird table ').Append(pData.Table.Name)
      .Append(' replaces.</summary>').Append(CRLF);
    pSb.Append(INDENT1).Append(pData.Table.Name).Append('_FIB_NAME = ''').Append(pData.Table.SourceName).Append(''';')
      .Append(CRLF).Append(CRLF);
  end;
  if pData.Rows = 0 then
  begin
    pSb.Append(INDENT1).Append('// ').Append(pData.Table.Name).Append(' holds no rows: no array is emitted.')
      .Append(CRLF).Append(CRLF);
    Exit;
  end;
  pSb.Append(INDENT1).Append('/// <summary>Every row of ').Append(pData.Table.Name).Append(' in primary-key order.</summary>')
    .Append(CRLF);
  pSb.Append(INDENT1).Append(pData.Table.Name).Append('_ROWS: array[0..').Append(IntToStr(pData.Rows - 1)).Append('] of ')
    .Append(RecordName(pData.Table)).Append(' = (').Append(CRLF);
  VQ := NewQuery(pConn, pData.Table);
  try
    VQ.Open;
    VFields := ColumnFields(VQ, pData.Table);
    VN := 0;
    while not VQ.Eof do
    begin
      Inc(VN);
      EmitRow(pSb, VFields, pData, VN = pData.Rows);
      VQ.Next;
    end;
  finally
    VQ.Free;
  end;
  pSb.Append(INDENT1).Append(');').Append(CRLF).Append(CRLF);
end;

{ DL_FIELDS_INFO -> DlFieldsInfo: the PascalCase form the routine names use. }
function PascalName(const pTableName: string): string;
var
  VParts: TArray<string>;
  VI: Integer;
begin
  VParts := pTableName.Split(['_']);
  for VI := 0 to High(VParts) do
    VParts[VI] := UpperCase(Copy(VParts[VI], 1, 1)) + LowerCase(Copy(VParts[VI], 2, MaxInt));
  Result := string.Join('', VParts);
end;

function SizeConstName(const pTable: TRepoTable; const pCol: TRepoColumn): string;
begin
  Result := pTable.Name + '_' + pCol.Name + '_SIZE';
end;

procedure EmitFillDecl(pSb: TStringBuilder; const pTable: TRepoTable);
begin
  pSb.Append('/// <summary>Loads ').Append(pTable.Name).Append(' into pTable: creates the field definitions of the FIB$ table')
    .Append(' (same names, types, sizes) and appends every generated row; NULL columns stay NULL.</summary>').Append(CRLF);
  pSb.Append('/// <param name="pTable">Memory table to fill; closed and its field definitions replaced. Caller owns it.</param>')
    .Append(CRLF);
  pSb.Append('procedure Fill').Append(PascalName(pTable.Name)).Append('(pTable: TFDMemTable);').Append(CRLF).Append(CRLF);
end;

{ Implementation-section constants: the FIB$ string sizes the field definitions use. }
procedure EmitSizeConsts(pSb: TStringBuilder; const pTable: TRepoTable);
var
  VCol: TRepoColumn;
begin
  for VCol in pTable.Columns do
    if VCol.Kind = rckString then
      pSb.Append(INDENT1).Append(SizeConstName(pTable, VCol)).Append(' = ').Append(IntToStr(VCol.MaxLen)).Append(';').Append(CRLF);
end;

procedure EmitAddRow(pSb: TStringBuilder; const pData: TTableData);
var
  VI: Integer;
  VCol: TRepoColumn;
  VAssign, VSrc: string;
begin
  pSb.Append('procedure Add').Append(PascalName(pData.Table.Name)).Append('Row(pTable: TFDMemTable; const pRow: ')
    .Append(RecordName(pData.Table)).Append(');').Append(CRLF);
  pSb.Append('begin').Append(CRLF);
  pSb.Append(INDENT1).Append('pTable.Append;').Append(CRLF);
  for VI := 0 to High(pData.Table.Columns) do
  begin
    VCol := pData.Table.Columns[VI];
    VSrc := 'pRow.' + VCol.Name;
    VAssign := 'pTable.FieldByName(''' + VCol.Name + ''').' + AccessorName(VCol.Kind) + ' := ' + VSrc + ';';
    if pData.NullCols[VI] then
      pSb.Append(INDENT1).Append('if not ').Append(VSrc).Append('IsNull then').Append(CRLF)
        .Append(INDENT2).Append(VAssign).Append(CRLF)
    else
      pSb.Append(INDENT1).Append(VAssign).Append(CRLF);
  end;
  pSb.Append(INDENT1).Append('pTable.Post;').Append(CRLF);
  pSb.Append('end;').Append(CRLF).Append(CRLF);
end;

procedure EmitFillBody(pSb: TStringBuilder; const pData: TTableData);
var
  VCol: TRepoColumn;
  VDefs: string;
begin
  if pData.Rows > 0 then
    EmitAddRow(pSb, pData);
  pSb.Append('procedure Fill').Append(PascalName(pData.Table.Name)).Append('(pTable: TFDMemTable);').Append(CRLF);
  if pData.Rows > 0 then
    pSb.Append('var').Append(CRLF).Append(INDENT1).Append('I: Integer;').Append(CRLF);
  pSb.Append('begin').Append(CRLF);
  pSb.Append(INDENT1).Append('pTable.Close;').Append(CRLF);
  pSb.Append(INDENT1).Append('pTable.FieldDefs.Clear;').Append(CRLF);
  for VCol in pData.Table.Columns do
  begin
    VDefs := if VCol.Kind = rckString then 'ftWideString, ' + SizeConstName(pData.Table, VCol) else FieldDefLine(VCol);
    pSb.Append(INDENT1).Append('pTable.FieldDefs.Add(''').Append(VCol.Name).Append(''', ').Append(VDefs).Append(');').Append(CRLF);
  end;
  pSb.Append(INDENT1).Append('pTable.CreateDataSet;').Append(CRLF);
  if pData.Rows > 0 then
  begin
    pSb.Append(INDENT1).Append('for I := Low(').Append(pData.Table.Name).Append('_ROWS) to High(')
      .Append(pData.Table.Name).Append('_ROWS) do').Append(CRLF);
    pSb.Append(INDENT2).Append('Add').Append(PascalName(pData.Table.Name)).Append('Row(pTable, ')
      .Append(pData.Table.Name).Append('_ROWS[I]);').Append(CRLF);
  end;
  pSb.Append('end;').Append(CRLF).Append(CRLF);
end;


function HeaderComment(const pOptions: TConstGenOptions; const pData: TArray<TTableData>): string;
var
  VSb: TStringBuilder;
  VD: TTableData;
  VC: Char;
begin
  VSb := TStringBuilder.Create;
  try
    VSb.Append('// Generated by drag-lint repo gen-const -- do not edit.').Append(CRLF);
    VSb.Append('// Source repository: ');
    for VC in pOptions.SourceName do
      VSb.Append(if IsPrintAscii(VC) then VC else '?');
    VSb.Append(CRLF);
    for VD in pData do
      VSb.Append('//   ').Append(VD.Table.Name).Append(': ').Append(IntToStr(VD.Rows)).Append(' rows').Append(CRLF);
    Result := VSb.ToString;
  finally
    VSb.Free;
  end;
end;

function GenRepoConstUnit(pConn: TFDConnection; const pOptions: TConstGenOptions): string;
var
  VTabs: TArray<TRepoTable>;
  VData: TArray<TTableData>;
  VSb: TStringBuilder;
  VI: Integer;
begin
  if not IsPasIdent(pOptions.UnitName) then
    raise EConstGenError.Create('unit name "' + pOptions.UnitName + '" is not an identifier');
  VTabs := SelectTables(pConn, pOptions);
  SetLength(VData, Length(VTabs));
  for VI := 0 to High(VTabs) do
    VData[VI] := ScanTable(pConn, VTabs[VI]);
  VSb := TStringBuilder.Create;
  try
    VSb.Append('unit ').Append(pOptions.UnitName).Append(';').Append(CRLF).Append(CRLF);
    VSb.Append(HeaderComment(pOptions, VData)).Append(CRLF);
    VSb.Append('interface').Append(CRLF).Append(CRLF);
    if pOptions.MemTable then
      VSb.Append('uses').Append(CRLF).Append(INDENT1).Append('Data.DB,').Append(CRLF)
        .Append(INDENT1).Append('FireDAC.Comp.Client;').Append(CRLF).Append(CRLF);
    VSb.Append('type').Append(CRLF);
    for VI := 0 to High(VData) do
      EmitRecordType(VSb, VData[VI]);
    VSb.Append('const').Append(CRLF);
    for VI := 0 to High(VData) do
      EmitConsts(VSb, pConn, VData[VI]);
    if pOptions.MemTable then
      for VI := 0 to High(VData) do
        EmitFillDecl(VSb, VData[VI].Table);
    VSb.Append('implementation').Append(CRLF).Append(CRLF);
    if pOptions.MemTable then
    begin
      VSb.Append('const').Append(CRLF);
      for VI := 0 to High(VData) do
        EmitSizeConsts(VSb, VData[VI].Table);
      VSb.Append(CRLF);
      for VI := 0 to High(VData) do
        EmitFillBody(VSb, VData[VI]);
    end;
    VSb.Append('end.').Append(CRLF);
    Result := VSb.ToString;
  finally
    VSb.Free;
  end;
end;

end.
