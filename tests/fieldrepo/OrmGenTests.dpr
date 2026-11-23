program OrmGenTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.52 lane TTGEN -- console tests for DRagLint.FieldRepo.OrmGen and
  DRagLint.FieldRepo.DataServiceGen (TableTools GenerateORMSource / UpdateORMSource /
  GenerateDataServiceUnits ported onto the field repository).

  Default run: unit checks on a repository built in %TEMP%; one PASS / FAIL line per check,
  then "SUMMARY pass=N fail=M"; exit code 0 only when fail=0. Contract: the DocInsight
  comments of TOrmGenerator.UpdateRegions / LoadTable, PlanUpdateOrm, PlanGenOrm,
  ApplyOrmChanges, OrmChangeDiff and PlanGenDataService.

  Tool modes used by tests\autotest\run_fieldrepo_ormgen_golden.ps1:
    --import <connection> <repo>     create <repo> and import the FIB$ registry (Firebird READ only)
    --golden <repo> <objects> <server> <client> <report>
                                     update-orm over the given folders (a COPY: the regenerated units are written there);
                                     per unit: byte-identical / identical-ignoring-blanks /
                                     identical-ignoring-blanks-and-case / different, region ids that
                                     differ, and a check that every byte outside the regions is kept
    --emit-fixture <dir>             the units tests\autotest\run_fieldrepo_ormgen_run.ps1 compiles and runs }

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
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
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema in '..\..\src\sql\DRagLint.FieldRepo.Schema.pas',
  DRagLint.FieldRepo.FbImport in '..\..\src\sql\DRagLint.FieldRepo.FbImport.pas',
  DRagLint.FieldRepo.OrmGen in '..\..\src\sql\DRagLint.FieldRepo.OrmGen.pas',
  DRagLint.FieldRepo.OrmHeaders in '..\..\src\sql\DRagLint.FieldRepo.OrmHeaders.pas',
  DRagLint.FieldRepo.DataServiceGen in '..\..\src\sql\DRagLint.FieldRepo.DataServiceGen.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

function Sp(pCount: Integer): string;
begin
  Result := StringOfChar(' ', pCount);
end;

function FixedGuid: TGUID;
begin
  Result := StringToGUID('{11111111-2222-3333-4444-555555555555}');
end;

procedure AddRow(pConn: TFDConnection; const pTable, pField, pVarType, pAsType: string;
  pPk: Boolean; const pSeq: string; pIsEnum: Boolean = False; const pEnumType: string = '';
  pCalc: Boolean = False; pKind: Integer = 1; const pDocSummary: string = '';
  const pDefault: string = '');
begin
  pConn.ExecSQL('INSERT INTO DL_FIELDS_INFO (TABLE_NAME, FIELD_NAME, VAR_TYPE, FIELD_AS_TYPE, ' +
    'PRIMARY_KEY, SEQUENCE_NAME, ISENUM, ENUMTYPE, ISCALCULATED, FIELD_KIND, DOC_SUMMARY, ' +
    'DOC_REMARKS, DEFAULTVAL) VALUES (:a, :b, :c, :d, :e, :f, :g, :h, :i, :j, :k, :l, :m)',
    [pTable, pField, pVarType, pAsType, Ord(pPk), pSeq, Ord(pIsEnum), pEnumType, Ord(pCalc),
     pKind, pDocSummary, '', pDefault]);
end;

function NewFixtureRepo: TFDConnection;
var
  vFile: string;
begin
  vFile := TPath.Combine(GDir, 'fixture.dlrepo');
  if TFile.Exists(vFile) then
    TFile.Delete(vFile);
  CreateRepository(vFile);
  Result := OpenRepository(vFile, False);
  AddRow(Result, 'ORDERS', 'ID', 'Int64', 'AsLargeInt', True, 'GEN_ORDERS_ID');
  AddRow(Result, 'ORDERS', 'NAME', 'string', 'AsString', False, '', False, '', False, 1, 'The name');
  AddRow(Result, 'ORDERS', 'CALC', 'string', 'AsString', False, '', False, '', True);
  AddRow(Result, 'ORDERS', 'STATUS', 'Byte', 'AsByte', False, '', True, 'TOrderStatus');
  AddRow(Result, 'ORDERS', 'GHOST', 'string', 'AsString', False, '', False, '', False, 0);
  AddRow(Result, 'LINE$ITEM', 'ORDER_ID', 'Int64', 'AsLargeInt', True, '');
  AddRow(Result, 'LINE$ITEM', 'LINE_NO', 'Integer', 'AsInteger', True, '');
  AddRow(Result, 'LINE$ITEM', 'MEMO', 'TStringList', 'AsString', False, '', False, '', False, 1,
    'Line one'#13#10'Line two');
end;

function Region(const pId: string; const pBody: string): string;
begin
  Result := '  {$REGION ''DB-RAD ' + pId + '''}'#13#10 + pBody + '  {$ENDREGION ''DB-RAD ' + pId + '''}'#13#10;
end;

function RegionBody(const pText, pId: string): string;
var
  vLines: TArray<string>;
  vId: string;
  I: Integer;
  vIn: Boolean;
begin
  Result := '';
  vIn := False;
  vLines := OrmSplitLines(pText);
  for I := 0 to High(vLines) do
  begin
    if vIn and IsOrmRegionEnd(vLines[I]) then
      Exit;
    if vIn then
      Result := Result + vLines[I] + #13#10
    else if IsOrmRegionStart(vLines[I], vId) and (vId = pId) then
      vIn := True;
  end;
end;

procedure TestRegionMarkers;
var
  vId: string;
begin
  Check('R1 start DB-RAD 2', IsOrmRegionStart('    {$REGION ''DB-RAD 2''}', vId) and (vId = '2'), vId);
  Check('R2 start DB-RAD 1A', IsOrmRegionStart('{$REGION ''DB-RAD 1A''}', vId) and (vId = '1A'), vId);
  Check('R3 start lower case cl-key', IsOrmRegionStart('{$region ''db-rad cl-key''}', vId) and (vId = 'CL-KEY'), vId);
  Check('R4 Documentation region is not DB-RAD', not IsOrmRegionStart('{$REGION ''Documentation''}', vId) and (vId = ''));
  Check('R5 end with DB-RAD', IsOrmRegionEnd('  {$ENDREGION ''DB-RAD 2''}'));
  Check('R6 bare ENDREGION is not a DB-RAD end', not IsOrmRegionEnd('{$ENDREGION}'));
  { ORM3 uFOLDERS.PAS:276: a hand-written region that merely MENTIONS DB-RAD (TableTools emptied it) }
  Check('R7 name mentioning DB-RAD is not a DB-RAD region', not IsOrmRegionStart('{$REGION ''MicStream prototype -- hand-written, not DB-RAD''}', vId), vId);
  Check('R8 its end is not a DB-RAD end', not IsOrmRegionEnd('{$ENDREGION ''MicStream prototype -- hand-written, not DB-RAD''}'));
  Check('R9 DB-RAD without an id is not a region', not IsOrmRegionStart('{$REGION ''DB-RAD''}', vId), vId);
end;

procedure TestLoadAndSections(pRepo: TFDConnection);
var
  vGen: TOrmGenerator;
  vText, vOut, vBody: string;
  vCount: Integer;
  vNames: TArray<string>;
begin
  vGen := TOrmGenerator.Create(pRepo);
  try
    vNames := vGen.TableNames;
    Check('L1 table names ordered', (Length(vNames) = 2) and (vNames[0] = 'LINE$ITEM') and (vNames[1] = 'ORDERS'),
      string.Join(',', vNames));
    vText := 'unit uORDERS;'#13#10 + Region('1', '    junk'#13#10) + Region('7', '') + Region('9', 'old'#13#10);
    vOut := vGen.UpdateRegions(vText, 'ORDERS', False, vCount);
    Check('L2 three regions found', vCount = 3, IntToStr(vCount));
    { field list: FIELD_KIND 1 only, calculated left out, ordered by FIELD_NAME: ID, NAME, STATUS }
    vBody := RegionBody(vOut, '1');
    Check('L3 region 1 = ID, NAME, STATUS (no CALC, no GHOST)', vBody =
      '    fID' + Sp(23) + ': Int64' + Sp(5) + ';'#13#10 +
      '    fNAME' + Sp(21) + ': string' + Sp(4) + ';'#13#10 +
      '    fSTATUS' + Sp(19) + ': TOrderStatus;'#13#10, vBody);
    vBody := RegionBody(vOut, '7');
    Check('L4 region 7 NAME accessor is GetNAME', Pos('function TmcORDERS.GetNAME: string;'#13#10'begin'#13#10 +
      '  result:= fNAME;'#13#10'end;'#13#10' '#13#10'procedure TmcORDERS.SetNAME(const Value: string);'#13#10 +
      'begin'#13#10'  fNAME:= Value;'#13#10'  fModified:= True;'#13#10'end;'#13#10' '#13#10, vBody) > 0, vBody);
    vBody := RegionBody(vOut, '9');
    Check('L5 region 9 generator key gets NextID', vBody.StartsWith(
      '      if Obj.ID <= 0 then'#13#10'        Obj.ID:= NextID;'#13#10 +
      '      QRYSave.Params[0].AsLargeInt:= Obj.ID ;'#13#10), vBody);
    { B33 (1.52 BK-TTFINISH): the plain parameter binding uses the FIELD_AS_TYPE accessor, the
      form the ORM3 units were generated with, not .Value }
    Check('L5b region 9 plain param uses FIELD_AS_TYPE (old .AsString form)',
      (Pos('      QRYSave.Params[1].AsString:= Obj.NAME ;', vBody) > 0) and (Pos('.Value:=', vBody) = 0), vBody);
    Check('L6 region 9 enum param is AsByte (legacy form)', Pos('      QRYSave.Params[2].AsByte:= Obj.STATUS.ToByte ;', vBody) > 0, vBody);
    { --save-form current: the TableTools 2026-05-19 forms }
    vGen.SaveForm := osfCurrent;
    vBody := RegionBody(vGen.UpdateRegions(vText, 'ORDERS', False, vCount), '9');
    vGen.SaveForm := osfLegacy;
    Check('L6b current form: .Value and Set1Byte',
      (Pos('      QRYSave.Params[1].Value:= Obj.NAME ;', vBody) > 0) and
      (Pos('      Set1Byte(QRYSave.Params[2], Obj.STATUS.ToByte);', vBody) > 0), vBody);
    { composite key without generator, '$' table }
    vText := Region('CL-NEXTID', '') + Region('9', '') + Region('2', '');
    vOut := vGen.UpdateRegions(vText, 'LINE$ITEM', True, vCount);
    vBody := RegionBody(vOut, 'CL-NEXTID');
    Check('L7 CL-NEXTID without generator', Pos('  // LINE_ITEM uses a composite key without a Firebird generator.', vBody) > 0, vBody);
    vBody := RegionBody(vOut, '9');
    Check('L8 region 9 non-generator keys validated', Pos('Cannot Save to LINE$ITEM', vBody) > 0, vBody);
    Check('L8b TStringList param is AsString (legacy form)', Pos('].AsString:= Obj.MEMO.Text;', vBody) > 0, vBody);
    vGen.SaveForm := osfCurrent;
    vBody := RegionBody(vGen.UpdateRegions(vText, 'LINE$ITEM', True, vCount), '9');
    vGen.SaveForm := osfLegacy;
    Check('L8c TStringList param is AsWideMemo (current form)', Pos('].AsWideMemo:= Obj.MEMO.Text;', vBody) > 0, vBody);
    vBody := RegionBody(vOut, '2');
    Check('L9 region 2 interface form with DOC_SUMMARY lines', Pos('/// Line one'#13#10'/// Line two'#13#10, vBody) > 0, vBody);
    { the accessor of NAME hides TComponent.SetName: reintroduce in the class, not in the interface }
    vBody := RegionBody(vGen.UpdateRegions(Region('1A', ''), 'ORDERS', False, vCount), '1A');
    Check('L4b region 1A: SetNAME is reintroduced, no other setter is', vBody.Contains('    procedure SetNAME(const Value: string); reintroduce;'#13#10) and
      vBody.Contains('    procedure SetID(const Value: Int64);'#13#10), vBody);
    vBody := RegionBody(vGen.UpdateRegions(Region('2', ''), 'ORDERS', True, vCount), '2');
    Check('L4c interface form has no directive', vBody.Contains('    procedure SetNAME(const Value: string);'#13#10), vBody);
    { summaries: the author's text stays, a placeholder or an empty one becomes what the row says }
    Check('S1 DOC_SUMMARY of the row is kept', vBody.Contains('/// The name'#13#10), vBody);
    Check('S2 empty DOC_SUMMARY: column and key', vBody.Contains('/// <summary>              '#13#10'/// Column ORDERS.ID, part of the primary key.'#13#10'/// </summary>'), vBody);
    Check('S3 empty DOC_REMARKS: no remarks block', not vBody.Contains('<remarks>'), vBody);
    pRepo.ExecSQL('INSERT INTO DL_FIELDS_INFO (TABLE_NAME, FIELD_NAME, VAR_TYPE, FIELD_AS_TYPE, FIELD_KIND, DISPLAY_LABEL, DOC_SUMMARY, DOC_REMARKS, DOCUMENTATION) ' +
      'VALUES (''DOCT'', ''AFIELD'', ''string'', ''AsString'', 1, ''A <b> & c'', ''Summary here'', ''Remarks here'', NULL), ' +
      '(''DOCT'', ''BFIELD'', ''string'', ''AsString'', 1, ''B'', '' summary HERE '', ''Keep me'', ''From the documentation column'')');
    try
      vBody := RegionBody(vGen.UpdateRegions(Region('2', ''), 'DOCT', False, vCount), '2');
      Check('S4 placeholder: label in XML-safe form, placeholder remarks dropped', vBody.Contains('/// Column DOCT.AFIELD ("A &lt;b&gt; &amp; c").'#13#10) and
        not vBody.Contains('Remarks here'), vBody);
      Check('S5 DOCUMENTATION wins over the built text, real remarks kept', vBody.Contains('/// From the documentation column'#13#10) and vBody.Contains('/// Keep me'#13#10), vBody);
    finally
      pRepo.ExecSQL('DELETE FROM DL_FIELDS_INFO WHERE TABLE_NAME = ''DOCT''');
    end;
    { regions 4 / 6: both objects named; nothing for a table without stored columns }
    Check('C1 region 6', RegionBody(vGen.UpdateRegions(Region('6', ''), 'LINE$ITEM', False, vCount), '6').StartsWith(
      '      var LDest:= TmcLINE_ITEM(Dest);'#13#10'      LDest.LINE_NO' + Sp(18) + ':= Self.fLINE_NO' + Sp(18) + ';'#13#10));
    { a column the generator creates (region 14) and frees (region 15) is copied by content, any other class column by reference }
    vBody := RegionBody(vGen.UpdateRegions(Region('4', ''), 'LINE$ITEM', False, vCount), '4');
    Check('C4 region 4: the owned list is assigned, nil source clears, nil destination and self-assignment are skipped',
      vBody.Contains('      if (Self.fMEMO <> nil) and (LSource <> Self) then'#13#10'        if LSource.MEMO <> nil then'#13#10 +
        '          Self.fMEMO.Assign(LSource.MEMO)'#13#10'        else'#13#10'          Self.fMEMO.Clear;'#13#10) and not vBody.Contains('Self.fMEMO:='), vBody);
    vBody := RegionBody(vGen.UpdateRegions(Region('6', ''), 'LINE$ITEM', False, vCount), '6');
    Check('C5 region 6: same for AssignTo, then Modified (an owned column has no setter call)',
      vBody.Contains('      if (LDest.MEMO <> nil) and (LDest <> Self) then'#13#10'        if Self.fMEMO <> nil then'#13#10 +
        '          LDest.MEMO.Assign(Self.fMEMO)'#13#10'        else'#13#10'          LDest.MEMO.Clear;'#13#10) and vBody.EndsWith('      LDest.Modified:= True;'#13#10) and not vBody.Contains('LDest.MEMO:='), vBody);
    vBody := RegionBody(vGen.UpdateRegions(Region('5', ''), 'LINE$ITEM', False, vCount), '5');
    Check('C7 region 5 (AssignI): the content is copied, the alias test is by instance, the getter is read once',
      vBody.Contains('    var LMEMO:= Value.MEMO;'#13#10'    if (Self.fMEMO <> nil) and (Self.fMEMO <> LMEMO) then'#13#10 +
        '      if LMEMO <> nil then'#13#10'        Self.fMEMO.Assign(LMEMO)'#13#10'      else'#13#10'        Self.fMEMO.Clear;'#13#10) and
      not vBody.Contains('fMEMO' + Sp(20) + ':=') and not vBody.Contains('Self <>'), vBody);
    Check('C6 the owned test is the one regions 14 / 15 use',
      RegionBody(vGen.UpdateRegions(Region('14', ''), 'LINE$ITEM', False, vCount), '14').Contains('fMEMO:= TStringList.Create;') and
      RegionBody(vGen.UpdateRegions(Region('15', ''), 'LINE$ITEM', False, vCount), '15').Contains('fMEMO.Free;') and
      not RegionBody(vGen.UpdateRegions(Region('6', ''), 'ORDERS', False, vCount), '6').Contains('Modified'));
    Check('C2 region 11 declares its enumeration local only when needed',
      RegionBody(vGen.UpdateRegions(Region('11', ''), 'ORDERS', False, vCount), '11').StartsWith('  var EnumByte: Byte;'#13#10) and
      not RegionBody(vGen.UpdateRegions(Region('11', ''), 'LINE$ITEM', False, vCount), '11').Contains('var '));
    pRepo.ExecSQL('INSERT INTO DL_FIELDS_INFO (TABLE_NAME, FIELD_NAME, VAR_TYPE, FIELD_AS_TYPE, FIELD_KIND, ISCALCULATED) VALUES (''NOCOL'', ''C'', ''string'', ''AsString'', 1, 1)');
    try
      vOut := vGen.UpdateRegions(Region('4', 'x'#13#10) + Region('6', 'x'#13#10) + Region('11', 'x'#13#10), 'NOCOL', False, vCount);
      Check('C3 no stored column: empty regions, no unused local', vOut = Region('4', '') + Region('6', '') + Region('11', ''), vOut);
    finally
      pRepo.ExecSQL('DELETE FROM DL_FIELDS_INFO WHERE TABLE_NAME = ''NOCOL''');
    end;
    Check('L10 unknown table raises EOrmGenError', (function: Boolean
      begin
        Result := False;
        try
          vGen.LoadTable('NOPE');
        except
          on E: EOrmGenError do
            Result := True;
        end;
      end)());
  finally
    vGen.Free;
  end;
end;

procedure TestBytesOutsideRegions(pRepo: TFDConnection);
var
  vGen: TOrmGenerator;
  vText, vOut: string;
  vCount: Integer;
begin
  vGen := TOrmGenerator.Create(pRepo);
  try
    { LF-only lines, a tab, trailing blanks and no final line end outside the regions }
    vText := 'unit uORDERS;'#10'  x := 1;  '#9#10 + '  {$REGION ''DB-RAD 4''}'#10'stale'#10 +
      '  {$ENDREGION ''DB-RAD 4''}'#10'end.';
    vOut := vGen.UpdateRegions(vText, 'ORDERS', False, vCount);
    Check('B1 outside bytes kept (LF, tab, blanks, no final EOL)', vOut =
      'unit uORDERS;'#10'  x := 1;  '#9#10'  {$REGION ''DB-RAD 4''}'#10 +
      '      var LSource:= TmcORDERS(Source);'#13#10 +
      '      Self.fID' + Sp(23) + ':= LSource.ID' + Sp(23) + ';'#13#10 +
      '      Self.fNAME' + Sp(21) + ':= LSource.NAME' + Sp(21) + ';'#13#10 +
      '      Self.fSTATUS' + Sp(19) + ':= LSource.STATUS' + Sp(19) + ';'#13#10 +
      '  {$ENDREGION ''DB-RAD 4''}'#10'end.', vOut);
    { positive control: a text without regions comes back byte for byte }
    vText := 'a'#13'b'#10'c'#13#10'd';
    Check('B2 text without regions unchanged', vGen.UpdateRegions(vText, 'ORDERS', False, vCount) = vText);
    Check('B3 no region counted', vCount = 0);
    { unknown id empties the region (TableTools) }
    vOut := vGen.UpdateRegions(Region('99', 'keep?'#13#10), 'ORDERS', False, vCount);
    Check('B4 unknown region id empties it', vOut = Region('99', ''), vOut);
    { start without end: generated lines, then the rest of the file stays }
    vOut := vGen.UpdateRegions('{$REGION ''DB-RAD 15''}'#13#10'tail'#13#10, 'ORDERS', False, vCount);
    Check('B5 start without end keeps the tail', vOut = '{$REGION ''DB-RAD 15''}'#13#10'tail'#13#10, vOut);
    vText := '{$REGION ''MicStream prototype -- hand-written, not DB-RAD''}'#13#10'hand code'#13#10 +
      '{$ENDREGION ''MicStream prototype -- hand-written, not DB-RAD''}'#13#10;
    Check('B6 hand-written region mentioning DB-RAD is kept', vGen.UpdateRegions(vText, 'ORDERS', False, vCount) = vText);
  finally
    vGen.Free;
  end;
end;

function KindsOf(const pPlan: TArray<TOrmFileChange>): string;
var
  C: TOrmFileChange;
begin
  Result := '';
  for C in pPlan do
    Result := Result + ExtractFileName(C.FileName) + '=' + IntToStr(Ord(C.Kind)) + ' ';
end;

function AllUnchanged(const pPlan: TArray<TOrmFileChange>): Boolean;
var
  C: TOrmFileChange;
begin
  Result := Length(pPlan) > 0;
  for C in pPlan do
    if C.Kind <> ockUnchanged then
      Result := False;
end;

procedure TestPlans(pRepo: TFDConnection);
var
  vCode, vSrv, vCli: string;
  vPlan: TArray<TOrmFileChange>;
  vSkipped: TStringList;
  vWritten: Integer;
  vDiff, vText: string;
begin
  vCode := TPath.Combine(GDir, 'OBJECTS');
  vSrv := TPath.Combine(GDir, 'SERVER');
  vCli := TPath.Combine(GDir, 'CLIENT');
  for vText in [vCode, vSrv, vCli] do
    if TDirectory.Exists(vText) then
      TDirectory.Delete(vText, True);
  { gen-orm into an empty folder: 4 new files }
  vPlan := PlanGenOrm(pRepo, vCode, [], FixedGuid);
  Check('P1 gen-orm plans 4 new files', (Length(vPlan) = 4) and (vPlan[0].Kind = ockNew), KindsOf(vPlan));
  Check('P2 interface unit header', (Length(vPlan) = 4) and vPlan[2].NewText.StartsWith('unit iORDERS;'), Copy(vPlan[2].NewText, 1, 40));
  Check('P3 pinned GUID in interface', (Length(vPlan) = 4) and (Pos('[''{11111111-2222-3333-4444-555555555555}'']', vPlan[2].NewText) > 0));
  Check('P4 dry-run diff of a new file is all +', OrmChangeDiff(vPlan[0]).Contains('@@ new file,'));
  vWritten := ApplyOrmChanges(vPlan, True);
  Check('P5 apply writes 4', vWritten = 4, IntToStr(vWritten));
  Check('P6 written text is the planned text', TFile.ReadAllText(vPlan[0].FileName) = vPlan[0].NewText);
  { gen-dataservice: 2 tables x (server, client) + 2 DI units }
  vPlan := PlanGenDataService(pRepo, vSrv, vCli, []);
  Check('P7 gen-dataservice plans 6 files', Length(vPlan) = 6, KindsOf(vPlan));
  Check('P8 server DI lists uORDERS_SERVER', (Length(vPlan) = 6) and vPlan[4].NewText.Contains('  uORDERS_SERVER,'));
  Check('P9 client DI names LINE_ITEM', (Length(vPlan) = 6) and vPlan[5].NewText.Contains('  uLINE_ITEM_CLIENT,'));
  ApplyOrmChanges(vPlan, True);
  { update-orm right after generation must change nothing (regions of new units = region generators) }
  vSkipped := TStringList.Create;
  try
    vPlan := PlanUpdateOrm(pRepo, vCode, vSrv, vCli, [], vSkipped);
    Check('P10 update-orm finds 8 units, skips none', (Length(vPlan) = 8) and (vSkipped.Count = 0), KindsOf(vPlan) + vSkipped.Text);
    Check('P11 update-orm after gen-orm/gen-dataservice changes nothing', AllUnchanged(vPlan), KindsOf(vPlan));
    { a table whose rows all have FIELD_KIND <> 1: skipped, never emptied }
    AddRow(pRepo, 'NOKIND', 'X', 'string', 'AsString', False, '', False, '', False, 2);
    vSkipped.Clear;
    vPlan := PlanUpdateOrm(pRepo, vCode, '', '', ['NOKIND'], vSkipped);
    Check('P11b table without FIELD_KIND 1 rows is skipped', (Length(vPlan) = 0) and (vSkipped.Count = 1) and
      vSkipped[0].Contains('FIELD_KIND = 1'), vSkipped.Text);
    vSkipped.Clear;
    { change the repository: a new column shows up as a changed region, nothing else }
    AddRow(pRepo, 'ORDERS', 'AMOUNT', 'Double', 'AsFloat', False, '');
    vPlan := PlanUpdateOrm(pRepo, vCode, '', '', ['ORDERS'], vSkipped);
    Check('P12 new column -> both ORDERS units changed', (Length(vPlan) = 2) and (vPlan[0].Kind = ockChanged) and (vPlan[1].Kind = ockChanged), KindsOf(vPlan));
    vDiff := if Length(vPlan) = 2 then OrmChangeDiff(vPlan[1]) else '';
    Check('P13 diff shows the new field line', vDiff.Contains('+    fAMOUNT') and vDiff.StartsWith('--- '), vDiff);
    Check('P14 diff has no - line for an unchanged field', not vDiff.Contains('-    fNAME'), vDiff);
    vWritten := ApplyOrmChanges(vPlan, True);
    Check('P15 backup .BCK1 written', (vWritten = 2) and TFile.Exists(vPlan[1].FileName + '.BCK1'));
    TFile.Delete(TPath.Combine(vCli, 'uORDERS_CLIENT.PAS'));
    vSkipped.Clear;
    vPlan := PlanUpdateOrm(pRepo, vCode, vSrv, vCli, ['ORDERS'], vSkipped);
    Check('P16 missing client file is skipped and named', (vSkipped.Count = 1) and vSkipped[0].Contains('uORDERS_CLIENT.PAS'), vSkipped.Text);
    Check('P17 unknown table in a plan raises', (function: Boolean
      begin
        Result := False;
        try
          PlanUpdateOrm(pRepo, vCode, '', '', ['NOPE'], vSkipped);
        except
          on E: EOrmGenError do
            Result := True;
        end;
      end)());
  finally
    vSkipped.Free;
  end;
end;

function ReadOld(const pFile: string): string;
begin
  Result := TFile.ReadAllText(pFile);
end;

{ the shapes ORM3 units carry: generated, re-formatted (YADF), hand-edited }
procedure TestHeaderUpgrade(pRepo: TFDConnection; const pRepoFile: string);
const
  RGN4 = '      {$REGION ''DB-RAD 4''}'#13#10'      x'#13#10'      {$ENDREGION ''DB-RAD 4''}'#13#10;
  RGN6 = '      {$REGION ''DB-RAD 6''}'#13#10'      y'#13#10'      {$ENDREGION ''DB-RAD 6''}'#13#10;
  OLD4 = 'procedure TmcORDERS.Assign(Source: TPersistent);'#13#10'begin'#13#10'  if not (Source is TmcORDERS) then inherited'#13#10 +
    '  else'#13#10'    with Source as TmcORDERS do'#13#10'    begin'#13#10 + RGN4 + '    end;'#13#10#13#10'end; // procedure'#13#10;
  OLD6 = 'procedure TmcORDERS.AssignTo(Dest: TPersistent);'#13#10'begin'#13#10'  if not (Dest is TmcORDERS) then'#13#10'    inherited'#13#10 +
    '  else'#13#10'    WITH Dest AS TmcORDERS DO'#13#10'    begin'#13#10 + RGN6 + '    end;'#13#10' '#13#10'end;'#13#10;
  NEW4 = 'procedure TmcORDERS.Assign(Source: TPersistent);'#13#10'begin'#13#10'  if Source is not TmcORDERS then'#13#10'    inherited'#13#10 +
    '  else'#13#10'  begin'#13#10 + RGN4 + '    end;'#13#10#13#10'end; // procedure'#13#10;
  NEW6 = 'procedure TmcORDERS.AssignTo(Dest: TPersistent);'#13#10'begin'#13#10'  if Dest is not TmcORDERS then'#13#10'    inherited'#13#10 +
    '  else'#13#10'  begin'#13#10 + RGN6 + '    end;'#13#10' '#13#10'end;'#13#10;
  READ_HEAD = 'function TmcORDERS.Reader(AStream:TABZMemoryStream): boolean;'#13#10;
  READ_VARS = 'var'#13#10'  StreamSize: integer;'#13#10'  ByteTemp  : Byte   ;'#13#10;
  READ_BODY = 'begin'#13#10'  result:= True;'#13#10'end;'#13#10#13#10;
  FOREIGN = 'procedure TmcOTHER.Assign(Source: TPersistent);'#13#10'begin'#13#10'  with Source as TmcORDERS do Foo;'#13#10'end;'#13#10;
var
  vNotes, vOut: TStringList;
  vGot, vDir, vFile, vHand, vBefore: string;
  vOpt: TOrmVerbOptions;
begin
  vNotes := TStringList.Create;
  vOut := TStringList.Create;
  try
    vGot := UpgradeOrmHeaderText('head'#13#10 + READ_HEAD + READ_VARS + READ_BODY + OLD4 + OLD6 + FOREIGN, 'ORDERS', vNotes);
    Check('H1 generated and re-formatted headers are upgraded, the rest kept byte for byte',
      (vGot = 'head'#13#10 + READ_HEAD + READ_BODY + NEW4 + NEW6 + FOREIGN) and (vNotes.Count = 0), vNotes.Text + vGot);
    Check('H2 a second run changes nothing and reports nothing', (UpgradeOrmHeaderText(vGot, 'ORDERS', vNotes) = vGot) and (vNotes.Count = 0), vNotes.Text);
    { hand-edited: a statement before the region, one after it, a comment in the header }
    vHand := OLD4.Replace('    begin'#13#10, '    begin'#13#10'      Foo;'#13#10);
    vGot := UpgradeOrmHeaderText(vHand + OLD6, 'ORDERS', vNotes);
    Check('H3 hand-edited Assign is left alone and listed, AssignTo is still upgraded', (vGot = vHand + NEW6) and (vNotes.Count = 1) and
      vNotes[0].StartsWith('Assign '), vNotes.Text + vGot);
    vNotes.Clear;
    vHand := OLD6.Replace('    end;'#13#10' ', '    end;'#13#10'  Foo;'#13#10);
    Check('H4 a statement after the region: left alone and listed', (UpgradeOrmHeaderText(NEW4 + vHand, 'ORDERS', vNotes) = NEW4 + vHand) and (vNotes.Count = 1), vNotes.Text);
    vNotes.Clear;
    vHand := OLD4.Replace('then inherited', 'then inherited // keep');
    Check('H5 a comment in the header: left alone and listed', (UpgradeOrmHeaderText(vHand + NEW6, 'ORDERS', vNotes) = vHand + NEW6) and (vNotes.Count = 1), vNotes.Text);
    vNotes.Clear;
    vHand := READ_HEAD + READ_VARS + 'begin'#13#10'  AStream.Read(ByteTemp);'#13#10'end;'#13#10;
    Check('H6 Reader locals still used: left alone and listed', (UpgradeOrmHeaderText(vHand + NEW4 + NEW6, 'ORDERS', vNotes) = vHand + NEW4 + NEW6) and
      (vNotes.Count = 1) and vNotes[0].StartsWith('Reader '), vNotes.Text);
    vNotes.Clear;
    vHand := READ_HEAD + 'var'#13#10'  StreamSize: integer;'#13#10'  Mine: Byte;'#13#10'  ByteTemp: Byte;'#13#10 + READ_BODY;
    Check('H7 Reader var block with another local: left alone and listed', (UpgradeOrmHeaderText(vHand + NEW4 + NEW6, 'ORDERS', vNotes) = vHand + NEW4 + NEW6) and (vNotes.Count = 1), vNotes.Text);
    vNotes.Clear;
    vNotes.Clear;
    Check('H7b the formatter comment // else behind the block is not an edit', (UpgradeOrmHeaderText(OLD4.Replace('    end;'#13#10, '    end; // else'#13#10) + NEW6, 'ORDERS', vNotes) =
      NEW4.Replace('    end;'#13#10, '    end; // else'#13#10) + NEW6) and (vNotes.Count = 0), vNotes.Text);
    vHand := OLD4.Replace('    end;'#13#10, '    end; // else keep me'#13#10);
    Check('H7c any other comment there is', (UpgradeOrmHeaderText(vHand + NEW6, 'ORDERS', vNotes) = vHand + NEW6) and (vNotes.Count = 1), vNotes.Text);
    vNotes.Clear;
    Check('H8 LF-only unit keeps LF', UpgradeOrmHeaderText((OLD4 + OLD6).Replace(#13#10, #10), 'ORDERS', vNotes) = (NEW4 + NEW6).Replace(#13#10, #10));

    { the verb: dry run by default, --apply writes with a backup }
    vDir := TPath.Combine(GDir, 'HDR');
    ForceDirectories(vDir);
    vFile := TPath.Combine(vDir, 'uORDERS.PAS');
    vBefore := 'unit uORDERS;'#13#10 + OLD4 + OLD6.Replace('    begin'#13#10, '    begin'#13#10'      Foo;'#13#10) + 'end.'#13#10;
    TFile.WriteAllText(vFile, vBefore, TEncoding.ASCII);
    vOpt := Default(TOrmVerbOptions);
    vOpt.Sub := 'upgrade-orm-headers';
    vOpt.RepoPath := pRepoFile;
    vOpt.CodeDir := vDir;
    vOpt.Tables := 'ORDERS';
    vOpt.Backup := True;
    Check('H9 verb dry run: diff, the hand-edited header listed, nothing written', (RunOrmGenVerb(vOpt, vOut) = 0) and
      vOut.Text.Contains('+  if Source is not TmcORDERS then') and vOut.Text.Contains('uORDERS.PAS: AssignTo is not in the generated form') and
      vOut[vOut.Count - 1].EndsWith('repo upgrade-orm-headers: 0 new, 1 changed, 0 unchanged, 1 skipped; dry run') and (ReadOld(vFile) = vBefore), vOut.Text);
    vOut.Clear;
    vOpt.Apply := True;
    Check('H10 verb apply writes the unit and a .BCK1', (RunOrmGenVerb(vOpt, vOut) = 0) and ReadOld(vFile).Contains(NEW4) and
      ReadOld(vFile).Contains('with Dest as TmcORDERS do'.Replace('with', 'WITH').Replace(' as ', ' AS ').Replace(' do', ' DO')) and
      (ReadOld(vFile + '.BCK1') = vBefore), vOut.Text);
    vOut.Clear;
    vOpt.CodeDir := '';
    Check('H11 missing --code-dir -> 1', (RunOrmGenVerb(vOpt, vOut) = 1) and vOut.Text.Contains('--code-dir'), vOut.Text);

    { a column SOURCE hides the parameter inside the old 'with': update-orm refuses that unit }
    AddRow(pRepo, 'TRAP', 'SOURCE', 'Integer', 'AsInteger', False, '');
    try
      vFile := TPath.Combine(vDir, 'uTRAP.PAS');
      vBefore := 'unit uTRAP;'#13#10 + OLD4.Replace('ORDERS', 'TRAP') + 'end.'#13#10;
      TFile.WriteAllText(vFile, vBefore, TEncoding.ASCII);
      TFile.WriteAllText(TPath.Combine(vDir, 'iTRAP.PAS'), 'unit iTRAP;'#13#10, TEncoding.ASCII);
      vNotes.Clear;
      Check('W1 column SOURCE under the old header: unit skipped and named', (Length(PlanUpdateOrm(pRepo, vDir, '', '', ['TRAP'], vNotes)) = 1) and
        (vNotes.Count = 1) and vNotes[0].Contains('upgrade-orm-headers'), vNotes.Text);
      TFile.WriteAllText(vFile, vBefore.Replace('if not (Source is TmcTRAP) then inherited', 'if Source is not TmcTRAP then inherited').Replace('with Source as TmcTRAP do', ''), TEncoding.ASCII);
      vNotes.Clear;
      Check('W2 under the new header it is regenerated', (Length(PlanUpdateOrm(pRepo, vDir, '', '', ['TRAP'], vNotes)) = 2) and (vNotes.Count = 0), vNotes.Text);
    finally
      pRepo.ExecSQL('DELETE FROM DL_FIELDS_INFO WHERE TABLE_NAME = ''TRAP''');
    end;
  finally
    vOut.Free;
    vNotes.Free;
  end;
end;

{ AssignI -> Assign overload: the i / u pair }
procedure TestAssignUpgrade(const pRepoFile: string);
const
  I_OLD = 'unit iORDERS;'#13#10'interface'#13#10'type'#13#10'  ImcORDERS = interface(IMicObject)'#13#10'    procedure AssignI(const IValue: ImcORDERS);'#13#10'  end;'#13#10'end.'#13#10;
  I_NEW = 'unit iORDERS;'#13#10'interface'#13#10'type'#13#10'  ImcORDERS = interface(IMicObject)'#13#10'    procedure Assign(const IValue: ImcORDERS);'#13#10'  end;'#13#10'end.'#13#10;
  U_HEAD = 'unit uORDERS;'#13#10'interface'#13#10'type'#13#10'  TmcORDERS = class(TMicObjectBase<ImcORDERS>, ImcORDERS)'#13#10'  published'#13#10;
  U_DECL_OLD = '     procedure Assign(Source: TPersistent); override;'#13#10'     procedure Initialize; override;'#13#10'     procedure AssignI(const Value: ImcORDERS);'#13#10;
  U_DECL_NEW = '     procedure Assign(Source: TPersistent); overload; override;'#13#10'     procedure Initialize; override;'#13#10'  public'#13#10'     procedure Assign(const Value: ImcORDERS); reintroduce; overload;'#13#10'  published'#13#10;
  U_IMPL_OLD = '  end;'#13#10'implementation'#13#10'procedure TmcORDERS.AssignI(const Value: ImcORDERS);'#13#10'begin'#13#10'{$REGION ''DB-RAD 5''}'#13#10'  x'#13#10'{$ENDREGION ''DB-RAD 5''}'#13#10'end;'#13#10'end.'#13#10;
  U_IMPL_NEW = '  end;'#13#10'implementation'#13#10'procedure TmcORDERS.Assign(const Value: ImcORDERS);'#13#10'begin'#13#10'{$REGION ''DB-RAD 5''}'#13#10'  x'#13#10'{$ENDREGION ''DB-RAD 5''}'#13#10'end;'#13#10'end.'#13#10;
var
  vNotes, vOut: TStringList;
  vI, vU, vDir, vCaller: string;
  vOpt: TOrmVerbOptions;
  vCalls: TArray<Integer>;
begin
  vNotes := TStringList.Create;
  vOut := TStringList.Create;
  try
    UpgradeOrmAssignPair(I_OLD, U_HEAD + U_DECL_OLD + U_IMPL_OLD, 'ORDERS', True, vNotes, vI, vU);
    Check('AI1 generated pair: AssignI becomes the overloaded Assign on both sides, the rest byte for byte',
      (vI = I_NEW) and (vU = U_HEAD + U_DECL_NEW + U_IMPL_NEW) and (vNotes.Count = 0), vNotes.Text + vI + vU);
    UpgradeOrmAssignPair(I_NEW, U_HEAD + U_DECL_NEW + U_IMPL_NEW, 'ORDERS', True, vNotes, vI, vU);
    Check('AI2 second run: nothing changes, no note', (vI = I_NEW) and (vU = U_HEAD + U_DECL_NEW + U_IMPL_NEW) and (vNotes.Count = 0), vNotes.Text);
    { the pair rule: a hand-edited side keeps BOTH as they are }
    UpgradeOrmAssignPair(I_OLD.Replace('IValue', 'IV'), U_HEAD + U_DECL_OLD + U_IMPL_OLD, 'ORDERS', True, vNotes, vI, vU);
    Check('AI3 hand-edited i unit (parameter renamed): u stays too, one note', (vI = I_OLD.Replace('IValue', 'IV')) and (vU = U_HEAD + U_DECL_OLD + U_IMPL_OLD) and (vNotes.Count = 1), vNotes.Text);
    vNotes.Clear;
    UpgradeOrmAssignPair(I_OLD, U_HEAD + U_DECL_OLD + U_IMPL_OLD.Replace('begin'#13#10'{$REGION', 'begin'#13#10'  Foo;'#13#10'{$REGION'), 'ORDERS', True, vNotes, vI, vU);
    Check('AI4 hand-edited u body header: i stays too, one note', (vI = I_OLD) and (vU = U_HEAD + U_DECL_OLD + U_IMPL_OLD.Replace('begin'#13#10'{$REGION', 'begin'#13#10'  Foo;'#13#10'{$REGION')) and (vNotes.Count = 1), vNotes.Text);
    vNotes.Clear;
    UpgradeOrmAssignPair(I_OLD, U_HEAD + U_DECL_OLD + U_IMPL_OLD.Replace('end;'#13#10'end.', '  // AssignI is gone'#13#10'end;'#13#10'end.'), 'ORDERS', True, vNotes, vI, vU);
    Check('AI4b a comment naming AssignI in the body is not code: converted, the comment kept', (vI = I_NEW) and (vNotes.Count = 0) and vU.Contains('// AssignI is gone') and
      vU.Contains('procedure TmcORDERS.Assign(const Value'), vNotes.Text + vI + vU);
    vNotes.Clear;
    UpgradeOrmAssignPair(I_OLD.Replace('    procedure', '    /// <seealso cref="iORDERS.AssignI"/>'#13#10'    procedure'), U_HEAD + U_DECL_OLD.Replace('     procedure AssignI', '     /// AssignI of the autodoc block'#13#10'     procedure AssignI') + U_IMPL_OLD, 'ORDERS', True, vNotes, vI, vU);
    Check('AI4c doc comments naming AssignI (autodoc) are not code: converted, the comments kept', (vNotes.Count = 0) and vI.Contains('cref="iORDERS.AssignI"') and vI.Contains('procedure Assign(const IValue') and
      vU.Contains('/// AssignI of the autodoc block') and vU.Contains('procedure TmcORDERS.Assign(const Value'), vNotes.Text + vI + vU);
    vNotes.Clear;
    UpgradeOrmAssignPair(I_OLD, U_HEAD + U_DECL_OLD + U_IMPL_OLD + '  Typed.AssignI(Base);'#13#10, 'ORDERS', True, vNotes, vI, vU);
    Check('AI4d a call of AssignI in the u unit itself is hand code: the pair is converted, the call stays', (vNotes.Count = 0) and (vI = I_NEW) and
      (vU = U_HEAD + U_DECL_NEW + U_IMPL_NEW + '  Typed.AssignI(Base);'#13#10), vNotes.Text + vU);
    vNotes.Clear;
    { a commented-out declaration above the real one: editing the comment would leave a pair that does not compile }
    UpgradeOrmAssignPair(I_OLD.Replace('    procedure', '    // procedure AssignI(const IValue: ImcORDERS);'#13#10'    procedure'), U_HEAD + U_DECL_OLD + U_IMPL_OLD, 'ORDERS', True, vNotes, vI, vU);
    Check('AI4e commented-out declaration in i: both left unchanged, one note', (vNotes.Count = 1) and (vU = U_HEAD + U_DECL_OLD + U_IMPL_OLD) and
      (vI = I_OLD.Replace('    procedure', '    // procedure AssignI(const IValue: ImcORDERS);'#13#10'    procedure')), vNotes.Text + vI + vU);
    vNotes.Clear;
    UpgradeOrmAssignPair(I_OLD, U_HEAD + '     // procedure Assign(Source: TPersistent); override;'#13#10 + U_DECL_OLD + U_IMPL_OLD, 'ORDERS', True, vNotes, vI, vU);
    Check('AI4f commented-out Assign(Source) in u: both left unchanged, one note', (vNotes.Count = 1) and (vI = I_OLD) and
      (vU = U_HEAD + '     // procedure Assign(Source: TPersistent); override;'#13#10 + U_DECL_OLD + U_IMPL_OLD), vNotes.Text + vI + vU);
    vNotes.Clear;
    UpgradeOrmAssignPair('', U_HEAD + U_DECL_OLD + U_IMPL_OLD, 'ORDERS', False, vNotes, vI, vU);
    Check('AI5 i unit missing: u stays, one note', (vU = U_HEAD + U_DECL_OLD + U_IMPL_OLD) and (vNotes.Count = 1), vNotes.Text);
    vNotes.Clear;
    UpgradeOrmAssignPair(I_OLD, U_HEAD + U_DECL_NEW + U_IMPL_NEW, 'ORDERS', True, vNotes, vI, vU);
    Check('AI6 u already converted, i not: i is completed (a half pair does not compile)', (vI = I_NEW) and (vU = U_HEAD + U_DECL_NEW + U_IMPL_NEW) and (vNotes.Count = 0), vNotes.Text);
    UpgradeOrmAssignPair('unit iORDERS;'#13#10, 'unit uORDERS;'#13#10, 'ORDERS', True, vNotes, vI, vU);
    Check('AI7 units without AssignI: untouched, silent', (vI = 'unit iORDERS;'#13#10) and (vU = 'unit uORDERS;'#13#10) and (vNotes.Count = 0), vNotes.Text);
    UpgradeOrmAssignPair((I_OLD + U_HEAD).Replace(#13#10, #10), (U_DECL_OLD + U_IMPL_OLD).Replace(#13#10, #10), 'ORDERS', True, vNotes, vI, vU);
    Check('AI7b LF-only text: converted, LF kept', (vNotes.Count = 0) and not vU.Contains(#13) and vU.Contains('procedure Assign(const Value: ImcORDERS); reintroduce; overload;'), vNotes.Text);
    vCalls := FindAssignICalls('x'#13#10'  Typed.AssignI(Base);'#13#10'  // Typed.AssignI(Base);'#13#10'    procedure AssignI(const Value: ImcX);'#13#10'procedure TmcX.AssignI(const Value: ImcX);'#13#10'  AssignI(B);'#13#10);
    Check('AI8 calls found, a declaration / implementation header / comment is not a call', (Length(vCalls) = 2) and (vCalls[0] = 2) and (vCalls[1] = 6));

    { the verb: dry run lists the calls and writes nothing; apply converts the pair; a second apply changes nothing }
    vDir := TPath.Combine(GDir, 'ASSIGNI');
    ForceDirectories(vDir);
    TFile.WriteAllText(TPath.Combine(vDir, 'iORDERS.PAS'), I_OLD, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(vDir, 'uORDERS.PAS'), U_HEAD + U_DECL_OLD + U_IMPL_OLD, TEncoding.ASCII);
    vCaller := 'unit uCALLER;'#13#10'implementation'#13#10'begin'#13#10'  Typed.AssignI(Base);'#13#10'end.'#13#10;
    TFile.WriteAllText(TPath.Combine(vDir, 'uCALLER.PAS'), vCaller, TEncoding.ASCII);
    vOpt := Default(TOrmVerbOptions);
    vOpt.Sub := 'upgrade-orm-headers';
    vOpt.RepoPath := pRepoFile;
    vOpt.CodeDir := vDir;
    vOpt.Tables := 'ORDERS';
    vOpt.Backup := True;
    Check('AI9 verb dry run: both units shown, the call listed with file(line), nothing written',
      (RunOrmGenVerb(vOpt, vOut) = 0) and vOut.Text.Contains('+    procedure Assign(const IValue: ImcORDERS);') and
      vOut.Text.Contains('uCALLER.PAS(4): a call of AssignI stays') and vOut[vOut.Count - 1].EndsWith('2 changed, 0 unchanged, 3 skipped; dry run') and
      (ReadOld(TPath.Combine(vDir, 'iORDERS.PAS')) = I_OLD) and (ReadOld(TPath.Combine(vDir, 'uORDERS.PAS')) = U_HEAD + U_DECL_OLD + U_IMPL_OLD), vOut.Text);
    vOut.Clear;
    vOpt.Apply := True;
    Check('AI10 verb apply: i and u converted, the caller is not edited',
      (RunOrmGenVerb(vOpt, vOut) = 0) and (ReadOld(TPath.Combine(vDir, 'iORDERS.PAS')) = I_NEW) and
      (ReadOld(TPath.Combine(vDir, 'uORDERS.PAS')) = U_HEAD + U_DECL_NEW + U_IMPL_NEW) and (ReadOld(TPath.Combine(vDir, 'uCALLER.PAS')) = vCaller), vOut.Text);
    vOut.Clear;
    Check('AI11 second apply changes nothing', (RunOrmGenVerb(vOpt, vOut) = 0) and vOut.Text.Contains('0 changed') and
      (ReadOld(TPath.Combine(vDir, 'iORDERS.PAS')) = I_NEW), vOut.Text);
  finally
    vOut.Free;
    vNotes.Free;
  end;
end;

procedure TestVerb(const pRepoFile: string);
var
  vOpt: TOrmVerbOptions;
  vOut: TStringList;
  vCode: string;
  vBefore: string;
begin
  vCode := TPath.Combine(GDir, 'OBJECTS');
  vBefore := TFile.ReadAllText(TPath.Combine(vCode, 'uORDERS.PAS'));
  vOut := TStringList.Create;
  try
    vOpt := Default(TOrmVerbOptions);
    vOpt.Sub := 'update-orm';
    vOpt.RepoPath := pRepoFile;
    vOpt.CodeDir := vCode;
    vOpt.Tables := 'ORDERS';
    vOpt.Backup := True;
    Check('V1 dry run exit 0', RunOrmGenVerb(vOpt, vOut) = 0, vOut.Text);
    Check('V2 dry run summary and diff', vOut[vOut.Count - 1].EndsWith(': 0 new, 2 changed, 0 unchanged, 0 skipped; dry run') and vOut.Text.Contains('+    fBMOUNT'), vOut.Text);
    Check('V3 dry run wrote nothing', TFile.ReadAllText(TPath.Combine(vCode, 'uORDERS.PAS')) = vBefore);
    vOut.Clear;
    vOpt.CodeDir := '';
    Check('V4 missing --code-dir -> 1 with a message', (RunOrmGenVerb(vOpt, vOut) = 1) and vOut.Text.Contains('--code-dir'), vOut.Text);
    vOut.Clear;
    vOpt.CodeDir := vCode;
    vOpt.Tables := 'NOPE';
    Check('V5 unknown table -> 1 with a message', (RunOrmGenVerb(vOpt, vOut) = 1) and vOut.Text.Contains('NOPE'), vOut.Text);
    vOut.Clear;
    vOpt.Sub := 'gen-something';
    Check('V6 unknown sub-verb -> 1', RunOrmGenVerb(vOpt, vOut) = 1, vOut.Text);
  finally
    vOut.Free;
  end;
end;

{ ---- tool modes ---- }
function RunImport(const pConn, pRepo: string): Integer;
var
  vConn: TFDConnection;
begin
  if TFile.Exists(pRepo) then
    TFile.Delete(pRepo);
  CreateRepository(pRepo);
  vConn := OpenRepository(pRepo, False);
  try
    ImportFromFirebird(pConn, vConn, False);
    Writeln('IMPORTED DL_FIELDS_INFO rows=', RepoRowCount(vConn, 'DL_FIELDS_INFO'));
  finally
    vConn.Free;
  end;
  Result := 0;
end;

function Squash(const pText: string; pIgnoreCase: Boolean): string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create;
  try
    for C in pText do
      if not CharInSet(C, [' ', #9, #10, #13]) then
        SB.Append(C);
    Result := if pIgnoreCase then SB.ToString.ToUpper else SB.ToString;
  finally
    SB.Free;
  end;
end;

{ every byte outside the regions: the text with the region bodies cut out }
function OutsideRegions(const pText: string): string;
var
  vLines: TArray<string>;
  vId: string;
  I: Integer;
  vIn: Boolean;
begin
  Result := '';
  vIn := False;
  vLines := OrmSplitLines(pText);
  for I := 0 to High(vLines) do
  begin
    if vIn and IsOrmRegionEnd(vLines[I]) then
      vIn := False;
    if not vIn then
      Result := Result + vLines[I] + #10;
    if (not vIn) and IsOrmRegionStart(vLines[I], vId) then
      vIn := True;
  end;
end;

{ The 1.54 generator differs from TableTools on purpose (owner rulings 2026-11-23). This turns a
  region the generator wrote back into what TableTools wrote, one named change at a time, so a unit
  that differs ONLY by those changes is DELIBERATE-DRIFT and any other difference is DIFFERENT. }
function LegacyForm(const pId: string; pBody: string): string;
var
  vLine, vT: string;
  vSynth: Boolean;

  function OldAccessor(const pText: string): string;
  begin
    Result := TRegEx.Replace(pText, '\b(Get|Set)NAME\b', '$1ZNAME');
  end;

begin
  Result := '';
  vSynth := False;
  if pId = '4' then
    pBody := TRegEx.Replace(pBody, '(?m)^      if \(Self\.f(\w+) <> nil\) and \(LSource <> Self\) then\r?\n(?:(?:        [^\r\n]*|      begin|      end;)\r?\n)+', '      f$1:= $1;'#13#10)
  else if pId = '5' then
    pBody := TRegEx.Replace(pBody, '(?m)^    var (\w+):= Value\.(\w+);\r?\n    if \(Self\.f\2 <> nil\)[^\r\n]*\r?\n(?:(?:      [^\r\n]*|    begin|    end;)\r?\n)+', '    f$2:= Value.$2;'#13#10)
  else if pId = '6' then
  begin
    pBody := TRegEx.Replace(pBody, '(?m)^      if \(LDest\.(\w+) <> nil\) and \(LDest <> Self\) then\r?\n(?:(?:        [^\r\n]*|      begin|      end;)\r?\n)+', '      $1:= f$1;'#13#10);
    pBody := pBody.Replace('      LDest.Modified:= True;'#13#10, '');
  end;
  for vLine in OrmSplitLines(pBody) do
  begin
    vT := vLine;
    if pId = '4' then
    begin
      if vT.Trim.StartsWith('var LSource:= Tmc') and vT.EndsWith('(Source);') then
        Continue;
      vT := TRegEx.Replace(vT, '^      Self\.f(\w+)(\s*):= LSource\.', '      f$1$2:= ');
    end
    else if pId = '6' then
    begin
      if vT.Trim.StartsWith('var LDest:= Tmc') and vT.EndsWith('(Dest);') then
        Continue;
      vT := TRegEx.Replace(vT, '^      LDest\.(\w+)(\s*):= Self\.f', '      $1$2:= f');
    end
    else if pId = '11' then
    begin
      if (vT = '  var EnumByte: Byte;') or (vT = '  var StreamLen: Integer;') then
        Continue;
      vT := vT.Replace('(EnumByte)', '(ByteTemp)').Replace(', StreamLen)', ', StreamSize)');
    end
    else if pId = '2' then
    begin
      if vT.StartsWith('/// Column ') then
      begin
        vT := '/// Summary here';
        vSynth := True;
      end
      else if vSynth and vT.StartsWith('/// </summary>') then
      begin
        vT := vT + #13#10'/// <remarks>'#13#10'/// Remarks here'#13#10'/// </remarks>';
        vSynth := False;
      end;
      vT := OldAccessor(vT);
    end
    else if pId = '1A' then
      vT := OldAccessor(vT).Replace('const Value: string); reintroduce;', 'const Value: string);')
    else if pId = '7' then
      vT := OldAccessor(vT);
    Result := Result + vT + #13#10;
  end;
end;

const
  LEVEL_DELIBERATE = 3;
  LEVEL_DIFFERENT = 4;

{ level: 0 byte-identical, 1 same ignoring blanks, 2 same ignoring blanks + case,
  3 only deliberate drift (ids in pDeliberate), 4 different (ids in the result) }
function DifferingRegions(const pOld, pNew: string; out pLevel: Integer; out pDeliberate: string): string;
var
  vLines: TArray<string>;
  vId: string;
  I: Integer;
  vIds: TList<string>;
  vO, vN: string;
begin
  Result := '';
  pDeliberate := '';
  pLevel := 0;
  vIds := TList<string>.Create;
  try
    vLines := OrmSplitLines(pOld);
    for I := 0 to High(vLines) do
      if IsOrmRegionStart(vLines[I], vId) and not vIds.Contains(vId) then
        vIds.Add(vId);
    for vId in vIds do
    begin
      vO := RegionBody(pOld, vId);
      vN := RegionBody(pNew, vId);
      if vO = vN then
        Continue;
      if Squash(vO, False) = Squash(vN, False) then
        pLevel := if pLevel < 1 then 1 else pLevel
      else if Squash(vO, True) = Squash(vN, True) then
        pLevel := if pLevel < 2 then 2 else pLevel
      else if Squash(vO, True) = Squash(LegacyForm(vId, vN), True) then
      begin
        pLevel := if pLevel < LEVEL_DELIBERATE then LEVEL_DELIBERATE else pLevel;
        pDeliberate := pDeliberate + vId + ' ';
      end
      else
      begin
        pLevel := LEVEL_DIFFERENT;
        Result := Result + vId + ' ';
      end;
    end;
  finally
    vIds.Free;
  end;
  Result := Result.Trim;
  pDeliberate := pDeliberate.Trim;
end;

function Chg(const pOld, pNew: string): TOrmFileChange;
begin
  Result.FileName := 'X.PAS';
  Result.OldText := pOld;
  Result.NewText := pNew;
  Result.Kind := if pOld = pNew then ockUnchanged else ockChanged;
end;

procedure TestDiff;
var
  vD: string;
begin
  vD := OrmChangeDiff(Chg('a'#13#10'b'#13#10, 'a'#13#10'c'#13#10));
  Check('D1 outside-region change gets a hunk', vD.Contains('@@ line 2 @@'#13#10'-b'#13#10'+c'#13#10), vD);
  vD := OrmChangeDiff(Chg('{$ENDREGION ''DB-RAD 1''}'#13#10'z'#13#10, '{$ENDREGION ''DB-RAD 2''}'#13#10'z'#13#10));
  Check('D2 two different region-end lines: walk moves on', vD.Contains('-{$ENDREGION ''DB-RAD 1''}'#13#10'+{$ENDREGION ''DB-RAD 2''}'#13#10) and not vD.Contains('-z'), vD);
  vD := OrmChangeDiff(Chg('a'#10, 'a'#13#10));
  Check('D3 line ends only', vD.Contains('@@ line ends only @@'), vD);
  Check('D4 unchanged = empty diff', OrmChangeDiff(Chg('a', 'a')) = '');
  vD := OrmChangeDiff(Chg('a'#13#10, 'a'#13#10'b'#13#10'c'#13#10));
  Check('D5 lines added at the end', vD.Contains('+b'#13#10'+c'#13#10), vD);
end;

procedure TestGoldenDetectors;
var
  vLevel: Integer;
  vA, vDel, vNew: string;
begin
  vA := 'x'#13#10 + Region('1', 'a b'#13#10);
  { positive controls: the golden's detectors must be able to fire }
  Check('G1 outside change is detected', OutsideRegions(vA) <> OutsideRegions('y'#13#10 + Region('1', 'a b'#13#10)));
  Check('G2 region-only change is not an outside change', OutsideRegions(vA) = OutsideRegions('x'#13#10 + Region('1', 'zzz'#13#10)));
  Check('G3 blank-only difference = level 1', (DifferingRegions(vA, 'x'#13#10 + Region('1', 'ab'#13#10), vLevel, vDel) = '') and (vLevel = 1), IntToStr(vLevel));
  Check('G4 case-only difference = level 2', (DifferingRegions(vA, 'x'#13#10 + Region('1', 'A B'#13#10), vLevel, vDel) = '') and (vLevel = 2), IntToStr(vLevel));
  Check('G5 real difference = level 4 with the id', (DifferingRegions(vA, 'x'#13#10 + Region('1', 'c'#13#10), vLevel, vDel) = '1') and (vLevel = LEVEL_DIFFERENT), IntToStr(vLevel));
  { deliberate drift: exactly the named change passes, the same change plus anything else does not }
  vNew := '      var LSource:= TmcT(Source);'#13#10'      Self.fA   := LSource.A   ;'#13#10;
  Check('G7 region 4 deliberate form', (DifferingRegions(Region('4', 'fA:=A;'#13#10), Region('4', vNew), vLevel, vDel) = '') and
    (vLevel = LEVEL_DELIBERATE) and (vDel = '4'), vDel);
  Check('G8 region 4 with another column is DIFFERENT', (DifferingRegions(Region('4', 'fB:=B;'#13#10), Region('4', vNew), vLevel, vDel) = '4') and (vLevel = LEVEL_DIFFERENT), vDel);
  Check('G9 the same text in another region is DIFFERENT', (DifferingRegions(Region('5', 'fA:=A;'#13#10), Region('5', vNew), vLevel, vDel) = '5') and (vLevel = LEVEL_DIFFERENT), vDel);
  Check('G10 a hand-written summary in the unit is DIFFERENT', (DifferingRegions(Region('2', '/// <summary>'#13#10'/// Mine'#13#10'/// </summary>'#13#10),
    Region('2', '/// <summary>'#13#10'/// Column T.A.'#13#10'/// </summary>'#13#10), vLevel, vDel) = '2') and (vLevel = LEVEL_DIFFERENT), vDel);
  Check('G11 a lost column is DIFFERENT', (DifferingRegions(Region('6', 'A:=fA;'#13#10'B:=fB;'#13#10),
    Region('6', '      var LDest:= TmcT(Dest);'#13#10'      LDest.A   := Self.fA   ;'#13#10), vLevel, vDel) = '6') and (vLevel = LEVEL_DIFFERENT), vDel);
  Check('G6 identical = level 0', (DifferingRegions(vA, vA, vLevel, vDel) = '') and (vLevel = 0), IntToStr(vLevel));
end;

function RunGolden(const pRepo, pObjects, pServer, pClient, pReport: string): Integer;
const
  LEVEL_NAME: array [0 .. LEVEL_DIFFERENT] of string = ('BYTE-IDENTICAL', 'SAME-IGNORING-BLANKS',
    'SAME-IGNORING-BLANKS-AND-CASE', 'DELIBERATE-DRIFT', 'DIFFERENT');
var
  vConn: TFDConnection;
  vPlan: TArray<TOrmFileChange>;
  vSkipped, vOut: TStringList;
  C: TOrmFileChange;
  vLevel, vOutsideBad: Integer;
  vCounts: array [0 .. LEVEL_DIFFERENT] of Integer;
  vIds, vNoRegion, vDeliberate: string;
begin
  FillChar(vCounts, SizeOf(vCounts), 0);
  vOutsideBad := 0;
  vConn := OpenRepository(pRepo, True);
  vSkipped := TStringList.Create;
  vOut := TStringList.Create;
  try
    vPlan := PlanUpdateOrm(vConn, pObjects, pServer, pClient, [], vSkipped);
    for C in vPlan do
    begin
      vIds := DifferingRegions(C.OldText, C.NewText, vLevel, vDeliberate);
      Inc(vCounts[vLevel]);
      vNoRegion := '';
      if OutsideRegions(C.OldText) <> OutsideRegions(C.NewText) then
      begin
        Inc(vOutsideBad);
        vNoRegion := ' OUTSIDE-CHANGED';
      end;
      if not C.OldText.Contains('DB-RAD') then
        vNoRegion := vNoRegion + ' NO-REGIONS';
      vOut.Add(Format('UNIT %s %s%s%s%s', [ExtractFileName(C.FileName), LEVEL_NAME[vLevel],
        if vIds <> '' then ' regions=' + vIds else '', vNoRegion,
        if vDeliberate <> '' then ' deliberate=' + vDeliberate else '']));
    end;
    { regenerate INTO the folders given (the runner passes a COPY of ORM3) for side-by-side diffs }
    ApplyOrmChanges(vPlan, False);
    for vIds in vSkipped do
      vOut.Add('SKIPPED ' + vIds);
    vOut.Add(Format('GOLDEN units=%d byte_identical=%d same_ignoring_blanks=%d same_ignoring_blanks_and_case=%d deliberate=%d different=%d outside_changed=%d skipped=%d',
      [Length(vPlan), vCounts[0], vCounts[1], vCounts[2], vCounts[LEVEL_DELIBERATE], vCounts[LEVEL_DIFFERENT], vOutsideBad, vSkipped.Count]));
    vOut.SaveToFile(pReport, TEncoding.ASCII);
    Writeln(vOut[vOut.Count - 1]);
    Result := if vOutsideBad = 0 then 0 else 1;
  finally
    vOut.Free;
    vSkipped.Free;
    vConn.Free;
  end;
end;

{ ---- fixture for tests\fieldrepo\ormgen (run_fieldrepo_ormgen_run.ps1) ---- }

{ The Assign / AssignTo header TableTools wrote around regions 4 and 6, put back into a freshly
  generated unit: the region text must also be right under it. }
function WithOldHeaders(const pText, pIdent: string): string;
begin
  Result := pText.Replace(
    '  if Source is not Tmc' + pIdent + ' then'#13#10'    inherited'#13#10'  else'#13#10'  begin'#13#10,
    '  if not (Source is Tmc' + pIdent + ') then'#13#10'    inherited'#13#10'  else'#13#10'    with Source as Tmc' + pIdent + ' do'#13#10'    begin'#13#10);
  Result := Result.Replace(
    '  if Dest is not Tmc' + pIdent + ' then'#13#10'    inherited'#13#10'  else'#13#10'  begin'#13#10,
    '  if not (Dest is Tmc' + pIdent + ') then'#13#10'    inherited'#13#10'  else'#13#10'    with Dest as Tmc' + pIdent + ' do'#13#10'    begin'#13#10);
end;

{ the AssignI form of the units written before 1.54 (the reverse of UpgradeOrmAssignPair) }
function WithLegacyAssignI(const pText, pIdent: string): string;
begin
  Result := pText.Replace('procedure Assign(const IValue: Imc' + pIdent + ');', 'procedure AssignI(const IValue: Imc' + pIdent + ');');
  Result := Result.Replace('procedure Assign(Source: TPersistent); overload; override;', 'procedure Assign(Source: TPersistent); override;');
  Result := Result.Replace('  public'#13#10'     procedure Assign(const Value: Imc' + pIdent + '); reintroduce; overload;'#13#10'  published'#13#10, '     procedure AssignI(const Value: Imc' + pIdent + ');'#13#10);
  Result := Result.Replace('procedure Tmc' + pIdent + '.Assign(const Value: Imc' + pIdent + ');', 'procedure Tmc' + pIdent + '.AssignI(const Value: Imc' + pIdent + ');');
end;

procedure AddFixtureTables(pRepo: TFDConnection);
begin
  AddRow(pRepo, 'ORMFIX', 'ID', 'Int64', 'AsLargeInt', True, 'GEN_ORMFIX_ID', False, '', False, 1, 'Summary here', '0');
  AddRow(pRepo, 'ORMFIX', 'NAME', 'string', 'AsString', False, '', False, '', False, 1, 'Summary here', '''N/A''');
  AddRow(pRepo, 'ORMFIX', 'ACTIVE', 'Boolean', 'AsBoolean', False, '', False, '', False, 1, 'Summary here', 'FALSE');
  AddRow(pRepo, 'ORMFIX', 'AMOUNT', 'double', 'AsFloat', False, '');
  AddRow(pRepo, 'ORMFIX', 'QTY', 'integer', 'AsInteger', False, '');
  AddRow(pRepo, 'ORMFIX', 'SMALLN', 'smallint', 'AsInteger', False, '');
  AddRow(pRepo, 'ORMFIX', 'FLAG8', 'Byte', 'AsByte', False, '');
  AddRow(pRepo, 'ORMFIX', 'STATUS', 'TOrderStatus', 'AsByte', False, '', True, 'TOrderStatus');
  AddRow(pRepo, 'ORMFIX', 'STAMP', 'TSQLTimeStamp', 'AsSQLTimeStamp', False, '');
  AddRow(pRepo, 'ORMFIX', 'WHENAT', 'TDateTime', 'AsDateTime', False, '', False, '', False, 1, '', '''01/01/2020''');
  AddRow(pRepo, 'ORMFIX', 'RAW', 'TBytes', 'AsBytes', False, '');
  AddRow(pRepo, 'ORMFIX', 'MEMO', 'TStringList', 'AsString', False, '', False, '', False, 1, 'Free text of the row');
  AddRow(pRepo, 'ORMFIX', 'PIC', 'TPicture', 'AsBlob', False, '');
  AddRow(pRepo, 'ORMFIX', 'STRM', 'TABZMemoryStream', 'AsBlob', False, '');
  AddRow(pRepo, 'ORMFIX', 'BCD', 'TBcd', 'AsBCD', False, '');
  AddRow(pRepo, 'ORMFIX', 'CALCF', 'string', 'AsString', False, '', False, '', True);
  AddRow(pRepo, 'ORMFIX', 'INTERNALF', 'string', 'AsString', False, '', False, '', False, 2);
  AddRow(pRepo, 'PLAINFIX', 'CODE', 'string', 'AsString', True, '');
  AddRow(pRepo, 'PLAINFIX', 'LINE_NO', 'integer', 'AsInteger', True, '');
  AddRow(pRepo, 'EMPTYFIX', 'ONLYCALC', 'string', 'AsString', False, '', False, '', True);
end;

{ <dir>\new = the units as generated; <dir>\old = the same units with the old 'with' headers }
function RunEmitFixture(const pDir: string): Integer;
const
  ORM_TABLES: array [0 .. 2] of string = ('ORMFIX', 'PLAINFIX', 'EMPTYFIX');
var
  vConn: TFDConnection;
  vNew, vOld, vFile, vText: string;
  vSkipped: TStringList;
begin
  vNew := TPath.Combine(pDir, 'new');
  vOld := TPath.Combine(pDir, 'old');
  ForceDirectories(vNew);
  ForceDirectories(vOld);
  ForceDirectories(TPath.Combine(pDir, 'legacy'));
  ForceDirectories(TPath.Combine(pDir, 'upgraded'));
  GDir := pDir;
  vFile := TPath.Combine(pDir, 'fixture.dlrepo');
  if TFile.Exists(vFile) then
    TFile.Delete(vFile);
  CreateRepository(vFile);
  vConn := OpenRepository(vFile, False);
  try
    AddFixtureTables(vConn);
    ApplyOrmChanges(PlanGenOrm(vConn, vNew, [ORM_TABLES[0], ORM_TABLES[1], ORM_TABLES[2]], FixedGuid), False);
    ApplyOrmChanges(PlanGenDataService(vConn, vNew, vNew, [ORM_TABLES[0], ORM_TABLES[1]]), False);
  finally
    vConn.Free;
  end;
  for vFile in TDirectory.GetFiles(vNew, '*.pas') do
  begin
    vText := TFile.ReadAllText(vFile);
    vText := WithOldHeaders(vText, TPath.GetFileNameWithoutExtension(vFile).Substring(1));
    TFile.WriteAllText(TPath.Combine(vOld, ExtractFileName(vFile)), vText, TEncoding.ASCII);
    { legacy = old headers + AssignI, then update-orm over it: regions regenerate under the old headers }
    vText := WithLegacyAssignI(vText, TPath.GetFileNameWithoutExtension(vFile).Substring(1));
    TFile.WriteAllText(TPath.Combine(pDir, 'legacy\' + ExtractFileName(vFile)), vText, TEncoding.ASCII);
  end;
  vConn := OpenRepository(TPath.Combine(pDir, 'fixture.dlrepo'), False);
  try
    vSkipped := TStringList.Create;
    try
      ApplyOrmChanges(PlanUpdateOrm(vConn, TPath.Combine(pDir, 'legacy'), '', '', [ORM_TABLES[0], ORM_TABLES[1], ORM_TABLES[2]], vSkipped), False);
      if vSkipped.Count > 0 then
        Writeln('LEGACY SKIPPED ', vSkipped.Text);
      { upgraded = legacy + repo upgrade-orm-headers: must equal the units as generated, byte for byte }
      for vFile in TDirectory.GetFiles(TPath.Combine(pDir, 'legacy'), '*.pas') do
        TFile.Copy(vFile, TPath.Combine(pDir, 'upgraded\' + ExtractFileName(vFile)), True);
      vSkipped.Clear;
      ApplyOrmChanges(PlanUpgradeOrmHeaders(vConn, TPath.Combine(pDir, 'upgraded'), [ORM_TABLES[0], ORM_TABLES[1], ORM_TABLES[2]], vSkipped), False);
      if vSkipped.Count > 0 then
        Writeln('UPGRADE SKIPPED ', vSkipped.Text);
    finally
      vSkipped.Free;
    end;
  finally
    vConn.Free;
  end;
  Writeln('EMITTED ', Length(TDirectory.GetFiles(vNew, '*.pas')));
  Result := 0;
end;

var
  vRepo: TFDConnection;
begin
  try
    if (ParamCount = 2) and (ParamStr(1) = '--emit-fixture') then
      Halt(RunEmitFixture(ParamStr(2)));
    if (ParamCount = 3) and (ParamStr(1) = '--import') then
      Halt(RunImport(ParamStr(2), ParamStr(3)));
    if (ParamCount = 6) and (ParamStr(1) = '--golden') then
      Halt(RunGolden(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5), ParamStr(6)));
    GDir := TPath.Combine(TPath.GetTempPath, 'dl-ormgen-' + IntToStr(GetCurrentProcessId));
    ForceDirectories(GDir);
    TestRegionMarkers;
    TestGoldenDetectors;
    TestDiff;
    vRepo := NewFixtureRepo;
    try
      TestLoadAndSections(vRepo);
      TestBytesOutsideRegions(vRepo);
      TestHeaderUpgrade(vRepo, TPath.Combine(GDir, 'fixture.dlrepo'));
      TestAssignUpgrade(TPath.Combine(GDir, 'fixture.dlrepo'));
      TestPlans(vRepo);
      { a column the units do not have yet, so the verb's dry run has a diff to show }
      AddRow(vRepo, 'ORDERS', 'BMOUNT', 'Double', 'AsFloat', False, '');
    finally
      vRepo.Free;
    end;
    TestVerb(TPath.Combine(GDir, 'fixture.dlrepo'));
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unexpected ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    Halt(1);
end.
