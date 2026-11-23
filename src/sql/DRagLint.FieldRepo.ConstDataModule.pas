unit DRagLint.FieldRepo.ConstDataModule;

{ drag-lint 1.53 -- lane FR-PRELOAD: `repo gen-const --datamodule <Name>` (spec
  2026-11-22-field-repository-v2-design.md section 7). Returns the source of ONE unit (.pas + text .dfm) that
  declares a data module with one read-only TFDMemTable per generated table. The rows travel in the FireDAC binary
  Content property of the form (TFDDataSet.DefineProperties), so creating the module opens the tables filled, with
  no fill code. The repository is the master: when FireDAC changes its stream format the unit is regenerated. }

interface

uses
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.ConstGen;

type
  /// <summary>The two texts of a generated data module unit.</summary>
  TConstDataModuleSource = record
    /// <summary>The unit source (7-bit ASCII, CRLF).</summary>
    Pas: string;
    /// <summary>The text form (7-bit ASCII, CRLF); it belongs beside the unit under the same base name.</summary>
    Dfm: string;
  end;

/// <summary>Name of the TFDMemTable component that holds a table: DL_FIELDS_INFO gives mtDlFieldsInfo.</summary>
/// <param name="pTableName">Repository table name.</param>
/// <returns>The component name.</returns>
/// <remarks>Pure; thread-safe.</remarks>
function ConstMemTableName(const pTableName: string): string;  // dl:ok unused-public-symbol -- REVIEWED 2026-11-23 FR-PRELOAD: the naming rule a reader of the generated module needs; used by the compiled probe ConstProbe.dpr

/// <summary>Generates the pre-filled data module.</summary>
/// <param name="pConn">Open repository connection (read only); never modified.</param>
/// <param name="pOptions">Unit name, source name and table selection.</param>
/// <param name="pModuleName">Name of the data module; its class is T + pModuleName. Must be a Pascal identifier.</param>
/// <returns>Unit and form source; identical bytes for identical repository content and the same FireDAC version.</returns>
/// <exception cref="EConstGenError">A name is not an identifier, the module and the unit have the same class / unit
/// name, or a table is unknown or refused.</exception>
/// <remarks>Rows are in primary-key order under the FIB$ field names, types and sizes; NULL stays NULL. The generated
/// tables are read only (EnableInsert / EnableUpdate / EnableDelete off). Not thread-safe over one connection.</remarks>
function GenRepoDataModule(pConn: TFDConnection; const pOptions: TConstGenOptions;
  const pModuleName: string): TConstDataModuleSource;

implementation

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.StorageBin,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ConstMark;

const
  CRLF = #13#10;
  INDENT1 = '  ';
  INDENT2 = '    ';
  INDENT3 = '      ';
  INDENT4 = '        ';
  HEX_LINE = 64;  // hex digits per line, as the IDE writes a binary property
  HEX_PER_BYTE = 2;
  { TFDBinStorageHeader = magic (4 bytes), version (2), alignment padding (2), dictionary offset (4). FireDAC writes the
    record from an uninitialised local, so the padding is whatever was on the stack: zeroed for deterministic bytes. }
  PAD_FIRST = 6;
  PAD_LAST = 7;
  DESIGN_STEP = 64;
  DESIGN_LEFT = 48;
  DESIGN_WIDTH = 240;
  TABLE_PREFIX = 'mt';
  { property lines every generated table carries: opened from Content, silent, read only }
  TABLE_PROPS: array[0..10] of string = (
    'IndexDefs = <>',
    'FetchOptions.AssignedValues = [evMode]',
    'FetchOptions.Mode = fmAll',
    'ResourceOptions.AssignedValues = [rvPersistent, rvSilentMode]',
    'ResourceOptions.Persistent = True',
    'ResourceOptions.SilentMode = True',
    'UpdateOptions.AssignedValues = [uvEDelete, uvEInsert, uvEUpdate]',
    'UpdateOptions.EnableDelete = False',
    'UpdateOptions.EnableInsert = False',
    'UpdateOptions.EnableUpdate = False',
    'StoreDefs = True');
  INTERFACE_UNITS: array[0..11] of string = ('System.SysUtils', 'System.Classes', 'Data.DB', 'FireDAC.Stan.Intf',
    'FireDAC.Stan.Option', 'FireDAC.Stan.Param', 'FireDAC.Stan.Error', 'FireDAC.Stan.StorageBin', 'FireDAC.DatS',
    'FireDAC.Phys.Intf', 'FireDAC.DApt.Intf', 'FireDAC.Comp.DataSet');

function ConstMemTableName(const pTableName: string): string;
var
  VPart: string;
begin
  Result := TABLE_PREFIX;
  for VPart in pTableName.Split(['_']) do
    Result := Result + UpperCase(Copy(VPart, 1, 1)) + LowerCase(Copy(VPart, 2, MaxInt));
end;

function FieldTypeOf(pKind: TRepoColKind): TFieldType;
begin
  case pKind of
    rckString: Result := ftWideString;
    rckInteger: Result := ftInteger;
    rckSmallint, rckByte: Result := ftSmallint;
    rckBoolean: Result := ftBoolean;
  else
    Result := ftWideMemo;
  end;
end;

function FieldTypeText(pKind: TRepoColKind): string;
begin
  case pKind of
    rckString: Result := 'ftWideString';
    rckInteger: Result := 'ftInteger';
    rckSmallint, rckByte: Result := 'ftSmallint';
    rckBoolean: Result := 'ftBoolean';
  else
    Result := 'ftWideMemo';
  end;
end;

procedure CopyField(pFrom, pTo: TField; pKind: TRepoColKind);
begin
  if pFrom.IsNull then
    Exit;
  case pKind of
    rckInteger, rckSmallint, rckByte: pTo.AsInteger := pFrom.AsInteger;
    rckBoolean: pTo.AsBoolean := pFrom.AsBoolean;
  else
    pTo.AsString := pFrom.AsString;
  end;
end;

{ Creates the dataset of pMem under the FIB$ names / types / sizes and appends every row of the table. }
procedure LoadTable(pConn: TFDConnection; const pTable: TRepoTable; pMem: TFDMemTable);
var
  VQ: TFDQuery;
  VFrom: TArray<TField>;
  VCol: TRepoColumn;
  VI: Integer;
begin
  for VCol in pTable.Columns do
    pMem.FieldDefs.Add(VCol.Name, FieldTypeOf(VCol.Kind), VCol.MaxLen);
  pMem.CreateDataSet;
  VQ := NewConstQuery(pConn, pTable);
  try
    VQ.Open;
    VFrom := ConstColumnFields(VQ, pTable);
    while not VQ.Eof do
    begin
      pMem.Append;
      for VI := 0 to High(VFrom) do
        CopyField(VFrom[VI], pMem.Fields[VI], pTable.Columns[VI].Kind);
      pMem.Post;
      VQ.Next;
    end;
  finally
    VQ.Free;
  end;
end;

{ The table as a FireDAC binary stream (structure + rows, no change log). }
function TableContent(pConn: TFDConnection; const pTable: TRepoTable): TBytes;
var
  VMem: TFDMemTable;
  VStream: TBytesStream;
  VI: Integer;
begin
  VMem := TFDMemTable.Create(nil);
  try
    VMem.Name := ConstMemTableName(pTable.Name);
    VMem.FormatOptions.StrsTrim := False;
    VMem.FormatOptions.StrsEmpty2Null := False;
    LoadTable(pConn, pTable, VMem);
    VMem.First;
    VMem.ResourceOptions.StoreItems := [siMeta, siData];
    VStream := TBytesStream.Create;
    try
      VMem.SaveToStream(VStream, sfBinary);
      Result := Copy(VStream.Bytes, 0, VStream.Size);
    finally
      VStream.Free;
    end;
  finally
    VMem.Free;
  end;
  for VI := PAD_FIRST to PAD_LAST do
    Result[VI] := 0;
end;

procedure EmitContent(pSb: TStringBuilder; const pBytes: TBytes);
var
  VHex: string;
  VPos: Integer;
begin
  SetLength(VHex, Length(pBytes) * HEX_PER_BYTE);
  BinToHex(Pointer(pBytes), PChar(VHex), Length(pBytes));
  pSb.Append(INDENT2).Append('Content = {');
  VPos := 0;
  while VPos < Length(VHex) do
  begin
    pSb.Append(CRLF).Append(INDENT3).Append(VHex.Substring(VPos, HEX_LINE));
    Inc(VPos, HEX_LINE);
  end;
  pSb.Append('}').Append(CRLF);
end;

procedure EmitTableObject(pSb: TStringBuilder; pConn: TFDConnection; const pTable: TRepoTable; pIndex: Integer);
var
  VCol: TRepoColumn;
  VProp: string;
begin
  pSb.Append(INDENT1).Append('object ').Append(ConstMemTableName(pTable.Name)).Append(': TFDMemTable').Append(CRLF);
  pSb.Append(INDENT2).Append('Active = True').Append(CRLF);
  pSb.Append(INDENT2).Append('FieldDefs = <');
  for VCol in pTable.Columns do
  begin
    pSb.Append(CRLF).Append(INDENT3).Append('item').Append(CRLF);
    pSb.Append(INDENT4).Append('Name = ''').Append(VCol.Name).Append('''').Append(CRLF);
    pSb.Append(INDENT4).Append('DataType = ').Append(FieldTypeText(VCol.Kind)).Append(CRLF);
    if VCol.Kind = rckString then
      pSb.Append(INDENT4).Append('Size = ').Append(IntToStr(VCol.MaxLen)).Append(CRLF);
    pSb.Append(INDENT3).Append('end');
  end;
  pSb.Append('>').Append(CRLF);
  for VProp in TABLE_PROPS do
    pSb.Append(INDENT2).Append(VProp).Append(CRLF);
  pSb.Append(INDENT2).Append('Left = ').Append(IntToStr(DESIGN_LEFT)).Append(CRLF);
  pSb.Append(INDENT2).Append('Top = ').Append(IntToStr(pIndex * DESIGN_STEP + DESIGN_LEFT)).Append(CRLF);
  EmitContent(pSb, TableContent(pConn, pTable));
  pSb.Append(INDENT1).Append('end').Append(CRLF);
end;

function FormText(pConn: TFDConnection; const pTables: TArray<TRepoTable>; const pModuleName: string): string;
var
  VSb: TStringBuilder;
  VI: Integer;
begin
  VSb := TStringBuilder.Create;
  try
    VSb.Append('object ').Append(pModuleName).Append(': T').Append(pModuleName).Append(CRLF);
    VSb.Append(INDENT1).Append('Height = ').Append(IntToStr((Length(pTables) + 1) * DESIGN_STEP)).Append(CRLF);
    VSb.Append(INDENT1).Append('Width = ').Append(IntToStr(DESIGN_WIDTH)).Append(CRLF);
    for VI := 0 to High(pTables) do
      EmitTableObject(VSb, pConn, pTables[VI], VI);
    VSb.Append('end').Append(CRLF);
    Result := VSb.ToString;
  finally
    VSb.Free;
  end;
end;

function UnitText(const pOptions: TConstGenOptions; const pTables: TArray<TRepoTable>;
  const pMarks: TArray<TConstTableMark>; const pModuleName, pFormHash: string): string;
var
  VSb: TStringBuilder;
  VTab: TRepoTable;
  VUnit: string;
begin
  VSb := TStringBuilder.Create;
  try
    VSb.Append('unit ').Append(pOptions.UnitName).Append(';').Append(CRLF).Append(CRLF);
    VSb.Append(ConstHeaderComment(pOptions.SourceName, pMarks, pFormHash)).Append(CRLF);
    VSb.Append('interface').Append(CRLF).Append(CRLF).Append('uses').Append(CRLF);
    for VUnit in INTERFACE_UNITS do
      VSb.Append(INDENT1).Append(VUnit).Append(',').Append(CRLF);
    VSb.Append(INDENT1).Append('FireDAC.Comp.Client;').Append(CRLF).Append(CRLF);
    VSb.Append('type').Append(CRLF);
    VSb.Append(INDENT1).Append('/// <summary>The registry tables as read-only mem tables, open and filled when the module is created.</summary>')
      .Append(CRLF);
    VSb.Append(INDENT1).Append('T').Append(pModuleName).Append(' = class(TDataModule)').Append(CRLF);
    for VTab in pTables do
      VSb.Append(INDENT2).Append(ConstMemTableName(VTab.Name)).Append(': TFDMemTable;').Append(CRLF);
    VSb.Append(INDENT1).Append('public').Append(CRLF).Append(INDENT2).Append('const').Append(CRLF);
    VSb.Append(INDENT3).Append('/// <summary>Content hash of the repository tables this module was generated from.</summary>').Append(CRLF);
    VSb.Append(INDENT3).Append(CONST_MARK_NAME).Append(' = ''').Append(ConstMarkHash(pMarks)).Append(''';').Append(CRLF);
    VSb.Append(INDENT1).Append('end;').Append(CRLF).Append(CRLF);
    VSb.Append('implementation').Append(CRLF).Append(CRLF);
    VSb.Append('{%CLASSGROUP ''System.Classes.TPersistent''}').Append(CRLF).Append(CRLF);
    VSb.Append('{$R *.dfm}').Append(CRLF).Append(CRLF);
    VSb.Append('end.').Append(CRLF);
    Result := VSb.ToString;
  finally
    VSb.Free;
  end;
end;

function GenRepoDataModule(pConn: TFDConnection; const pOptions: TConstGenOptions;
  const pModuleName: string): TConstDataModuleSource;
var
  VTabs: TArray<TRepoTable>;
begin
  if not IsPasIdent(pOptions.UnitName) then
    raise EConstGenError.Create('unit name "' + pOptions.UnitName + '" is not an identifier');
  if not IsPasIdent(pModuleName) then
    raise EConstGenError.Create('data module name "' + pModuleName + '" is not an identifier');
  if SameText('T' + pModuleName, pOptions.UnitName) then
    raise EConstGenError.Create('the class T' + pModuleName + ' has the name of its unit');
  VTabs := SelectConstTables(pConn, pOptions);
  Result.Dfm := FormText(pConn, VTabs, pModuleName);
  Result.Pas := UnitText(pOptions, VTabs, ConstTableMarks(pConn, VTabs), pModuleName, FormTextHash(Result.Dfm));
end;

end.
