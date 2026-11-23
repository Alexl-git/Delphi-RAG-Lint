program ConstProbe;

{$APPTYPE CONSOLE}

{ drag-lint 1.53 lanes FR-CONSTGEN / FR-PRELOAD -- the compile + round-trip probe of the registry generator.
  It uses the GENERATED units uFieldRegistry (constants) and uRegistryDm (data module dmRegistry, pre-filled
  TFDMemTables), both generated from one repository. It requires that both carry the same repository mark, that each
  mem table is open, read only and without a change log after Create alone, that its first row equals the constant
  array's, and prints the rows of the mem tables in the `repo backup` text form (#DLREPO records and
  the "#end TABLE n" trailers) so the runner can compare the output with the backup of the same repository.
  Argument 1: the repository schema version (1 or 2), which selects the column lists.
  Not part of the product; built only by tests\autotest\run_fieldrepo_constgen.ps1. }

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.TextBackup,
  DRagLint.FieldRepo.ConstDataModule,
  uFieldRegistry,
  uRegistryDm;

const
  TABLES: array[0..3] of string = ('DL_FIELDS_INFO', 'DL_DATASETS_INFO', 'DL_ENUMVALUES', 'DL_ERROR_MESSAGES');

var
  GModule: TdmRegistry;

procedure Need(pCond: Boolean; const pWhat: string);
begin
  if not pCond then
    raise Exception.Create(pWhat);
end;

{ The state a reader finds right after the module was created. }
procedure CheckModule;
begin
  Need(TdmRegistry.REPO_CONTENT_HASH = uFieldRegistry.REPO_CONTENT_HASH, 'the two units carry different marks');
  Need(GModule.mtDlFieldsInfo.RecordCount = DL_FIELDS_INFO_ROW_COUNT, 'row count differs from the constant unit');
  Need(GModule.mtDlFieldsInfo.RecNo = 1, 'the first row is not current');
  Need(GModule.mtDlFieldsInfo.FieldByName('FIELD_NAME').AsString = DL_FIELDS_INFO_ROWS[0].FIELD_NAME, 'first row differs');
end;

function MemByName(const pName: string): TFDMemTable;
begin
  Result := GModule.FindComponent(ConstMemTableName(pName)) as TFDMemTable;
  Need(Result.Active, pName + ' is not open');
  Need(not Result.CanModify, pName + ' can be modified');
  Need((not Result.CachedUpdates) and (Result.ChangeCount = 0), pName + ' has a change log');
end;

function KeyText(pTable: TFDMemTable; const pTab: TRepoTable): string;
var
  vKey: TRepoColumn;
  vField: TField;
begin
  Result := '';
  for vKey in pTab.PkColumns do
  begin
    vField := pTable.FieldByName(vKey.Name);
    if Result <> '' then
      Result := Result + '|';
    if vKey.Kind = rckString then
      Result := Result + EscapeRepoValue(vField.AsString, True)
    else
      Result := Result + IntToStr(vField.AsLargeInt);
  end;
end;

procedure PrintText(const pName, pValue: string);
var
  vStart, vPos: Integer;
  vSeg: string;
begin
  Writeln(pName, ':');
  vStart := 1;
  repeat
    vPos := PosEx(#10, pValue, vStart);
    vSeg := if vPos = 0 then Copy(pValue, vStart, MaxInt) else Copy(pValue, vStart, vPos - vStart);
    Writeln(' |', EscapeRepoValue(vSeg, False));
    vStart := vPos + 1;
  until vPos = 0;
end;

procedure PrintRecord(pTable: TFDMemTable; const pTab: TRepoTable);
var
  vCol: TRepoColumn;
  vField: TField;
begin
  Writeln('[', pTab.Name, ' ', KeyText(pTable, pTab), ']');
  for vCol in pTab.Columns do
  begin
    if vCol.PkOrder > 0 then
      Continue;
    vField := pTable.FieldByName(vCol.Name);
    if vField.IsNull then
      Continue;
    case vCol.Kind of
      rckText: PrintText(vCol.Name, vField.AsString);
      rckString: Writeln(vCol.Name, '=', EscapeRepoValue(vField.AsString, False));
      rckBoolean: Writeln(vCol.Name, '=', if vField.AsBoolean then 'true' else 'false');
    else
      Writeln(vCol.Name, '=', IntToStr(vField.AsLargeInt));
    end;
  end;
  Writeln('');
end;

procedure PrintTable(const pTab: TRepoTable);
var
  vMem: TFDMemTable;
  vCount: Integer;
begin
  vMem := MemByName(pTab.Name);
  vCount := 0;
  vMem.First;
  while not vMem.Eof do
  begin
    PrintRecord(vMem, pTab);
    Inc(vCount);
    vMem.Next;
  end;
  Writeln('#end ', pTab.Name, ' ', vCount);
end;

var
  vTab: TRepoTable;
  vName: string;
begin
  try
    GModule := TdmRegistry.Create(nil);
    try
      CheckModule;
      for vTab in RepoTablesFor(StrToInt(ParamStr(1))) do
        for vName in TABLES do
          if vTab.Name = vName then
            PrintTable(vTab);
    finally
      GModule.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('PROBE-ERROR ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
