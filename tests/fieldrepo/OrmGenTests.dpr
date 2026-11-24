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
                                     differ, and a check that every byte outside the regions is kept }

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
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
    Check('L4 region 7 NAME accessor is GetZNAME', Pos('function TmcORDERS.GetZNAME: string;'#13#10'begin'#13#10 +
      '  result:= fNAME;'#13#10'end;'#13#10' '#13#10'procedure TmcORDERS.SetZNAME(const Value: string);'#13#10 +
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

  function Updated(const pText: string): string;
  begin
    try
      Result := vGen.UpdateRegions(pText, 'ORDERS', False, vCount);
    except
      on E: Exception do
        Result := E.ClassName + ': ' + E.Message;
    end;
  end;

  procedure Refused(const pName, pText, pReason: string);
  begin
    vOut := Updated(pText);
    Check(pName, vOut.StartsWith('EOrmRegionError: ') and vOut.Contains(pReason), vOut);
  end;

  procedure CheckText(const pName, pGot, pWant: string);
  begin
    Check(pName, pGot = pWant, pGot);
  end;

begin
  vGen := TOrmGenerator.Create(pRepo);
  try
    { LF-only lines, a tab, trailing blanks and no final line end outside the regions }
    vText := 'unit uORDERS;'#10'  x := 1;  '#9#10 + '  {$REGION ''DB-RAD 4''}'#10'stale'#10 +
      '  {$ENDREGION ''DB-RAD 4''}'#10'end.';
    vOut := vGen.UpdateRegions(vText, 'ORDERS', False, vCount);
    Check('B1 outside bytes kept (LF, tab, blanks, no final EOL)', vOut =
      'unit uORDERS;'#10'  x := 1;  '#9#10'  {$REGION ''DB-RAD 4''}'#10 +
      '      fID' + Sp(23) + ':= ID' + Sp(23) + ';'#13#10 +
      '      fNAME' + Sp(21) + ':= NAME' + Sp(21) + ';'#13#10 +
      '      fSTATUS' + Sp(19) + ':= STATUS' + Sp(19) + ';'#13#10 +
      '  {$ENDREGION ''DB-RAD 4''}'#10'end.', vOut);
    { positive control: a text without regions comes back byte for byte }
    vText := 'a'#13'b'#10'c'#13#10'd';
    Check('B2 text without regions unchanged', vGen.UpdateRegions(vText, 'ORDERS', False, vCount) = vText);
    Check('B3 no region counted', vCount = 0);
    { the regions TableTools emptied or ran past: the unit is refused }
    Refused('B4 unknown region id', Region('99', 'keep?'#13#10), 'unknown region id: DB-RAD 99');
    Refused('B4b a hand region named DB-RAD', Region('notes', 'keep'#13#10), 'unknown region id: DB-RAD notes');
    Refused('B4c an id with text behind it', Region('2 mine', 'keep'#13#10), 'unknown region id: DB-RAD 2 mine');
    Refused('B5 start without end', '{$REGION ''DB-RAD 15''}'#13#10'tail'#13#10, 'without an end marker: DB-RAD 15');
    Refused('B7 an unnamed end', '{$REGION ''DB-RAD 1''}'#13#10'x'#13#10'{$ENDREGION}'#13#10'hand'#13#10 + Region('3', ''), 'the end marker of "DB-RAD 1" is "');
    Refused('B8 the end of another id', '{$REGION ''DB-RAD 1''}'#13#10'x'#13#10'{$ENDREGION ''DB-RAD 2''}'#13#10, 'the end marker of "DB-RAD 1" is "DB-RAD 2"');
    Refused('B9 no end, then another region', '{$REGION ''DB-RAD 1''}'#13#10'x'#13#10'hand'#13#10 + Region('3', ''), 'without an end marker');
    Refused('B10 a region inside a region', '{$REGION ''DB-RAD 1''}'#13#10 + Region('3', 'x'#13#10) + '{$ENDREGION ''DB-RAD 1''}'#13#10, 'holds the region');
    Refused('B11 the end in a comment', '{$REGION ''DB-RAD 1''}'#13#10'x'#13#10'// {$ENDREGION ''DB-RAD 1''}'#13#10'hand'#13#10, 'without an end marker');
    Refused('B12 the end of a hand region names an id', '{$REGION ''mine''}'#13#10'x'#13#10'{$ENDREGION ''DB-RAD 1''}'#13#10, 'the end marker of "mine" is "DB-RAD 1"');
    Refused('B13 code before the end marker', '{$REGION ''DB-RAD 1''}'#13#10'x'#13#10'hand; {$ENDREGION ''DB-RAD 1''}'#13#10, 'alone on its line');
    Refused('B13b code before the start marker', 'hand; {$REGION ''DB-RAD 1''}'#13#10'x'#13#10'{$ENDREGION ''DB-RAD 1''}'#13#10, 'alone on its line');
    Refused('B13c code behind the start marker', '{$REGION ''DB-RAD 1''} hand;'#13#10'x'#13#10'{$ENDREGION ''DB-RAD 1''}'#13#10, 'alone on its line');
    Refused('B14 a conditional ends inside', '{$IFDEF X}'#13#10'{$REGION ''DB-RAD 1''}'#13#10'x'#13#10'{$ENDIF}'#13#10'{$ENDREGION ''DB-RAD 1''}'#13#10, 'conditional');
    Refused('B14b an $ELSE inside', '{$IFDEF X}'#13#10'{$REGION ''DB-RAD 1''}'#13#10'x'#13#10'{$ELSE}'#13#10'{$ENDREGION ''DB-RAD 1''}'#13#10'{$ENDIF}'#13#10, 'conditional');
    Refused('B15 a comment left open', Region('1', '') + '{ x', 'has no end');
    vText := '{$IFDEF X}'#13#10 + Region('15', '{$IFDEF Y}a{$ELSE}b{$ENDIF}'#13#10) + '{$ENDIF}'#13#10;
    CheckText('B14c a whole conditional inside, and around (control)', Updated(vText), '{$IFDEF X}'#13#10 + Region('15', '') + '{$ENDIF}'#13#10);
    { copies that are not regions }
    vText := '(*'#13#10 + Region('1', 'old'#13#10) + '*)'#13#10;
    CheckText('B16 a region in a block comment is text', Updated(vText), vText);
    vText := 's := '''''''#13#10 + Region('1', 'old'#13#10) + '  '''''';'#13#10;
    CheckText('B17 a region in a multi-line string is text', Updated(vText), vText);
    vText := '{$REGION ''DB-RAD 15''}'#13#10'(*'#13#10'{$ENDREGION ''DB-RAD 15''}'#13#10'*)'#13#10'x'#13#10'{$ENDREGION ''DB-RAD 15''}'#13#10'hand'#13#10;
    CheckText('B18 the end in a comment is not the end', Updated(vText), '{$REGION ''DB-RAD 15''}'#13#10'{$ENDREGION ''DB-RAD 15''}'#13#10'hand'#13#10);
    vText := '{$REGION ''DB-RAD''}'#13#10'hand'#13#10'{$ENDREGION}'#13#10'{$REGION ''DB-RADIUS''}'#13#10'hand'#13#10'{$ENDREGION ''DB-RADIUS''}'#13#10;
    CheckText('B19 DB-RAD without an id, another word: hand regions', Updated(vText), vText);
    CheckText('B22 mixed spellings of the ends are fine', Updated('{$REGION ''DB-RADa 15''}'#13#10'x'#13#10'{$ENDREGION ''DB-RAD 15''}'#13#10), '{$REGION ''DB-RADa 15''}'#13#10'{$ENDREGION ''DB-RAD 15''}'#13#10);
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
    { a unit with a hand region DB-RAD notes: refused, named, not planned; the other units of the table are }
    vText := TFile.ReadAllText(TPath.Combine(vCode, 'uORDERS.PAS'));
    TFile.WriteAllText(TPath.Combine(vCode, 'uORDERS.PAS'), vText.Replace('end.', Region('notes', 'hand'#13#10) + 'end.'));
    vSkipped.Clear;
    vPlan := PlanUpdateOrm(pRepo, vCode, '', '', ['ORDERS'], vSkipped);
    Check('P18 a refused unit is named and not planned, the other one is', (Length(vPlan) = 1) and vPlan[0].FileName.EndsWith('iORDERS.PAS') and (vSkipped.Count = 1) and
      vSkipped[0].Contains('uORDERS.PAS: REFUSED') and vSkipped[0].Contains('DB-RAD notes'), KindsOf(vPlan) + vSkipped.Text);
    TFile.WriteAllText(TPath.Combine(vCode, 'uORDERS.PAS'), vText);
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

function DifferingRegions(const pOld, pNew: string; out pLevel: Integer): string;
var
  vLines: TArray<string>;
  vId: string;
  I: Integer;
  vIds: TList<string>;
  vO, vN: string;
begin
  { level: 0 byte-identical, 1 same ignoring blanks, 2 same ignoring blanks + case, 3 different }
  Result := '';
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
      else
      begin
        pLevel := 3;
        Result := Result + vId + ' ';
      end;
    end;
  finally
    vIds.Free;
  end;
  Result := Result.Trim;
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

procedure TestGoldenDetectors;var
  vLevel: Integer;
  vA: string;
begin
  vA := 'x'#13#10 + Region('1', 'a b'#13#10);
  { positive controls: the golden's detectors must be able to fire }
  Check('G1 outside change is detected', OutsideRegions(vA) <> OutsideRegions('y'#13#10 + Region('1', 'a b'#13#10)));
  Check('G2 region-only change is not an outside change', OutsideRegions(vA) = OutsideRegions('x'#13#10 + Region('1', 'zzz'#13#10)));
  Check('G3 blank-only difference = level 1', (DifferingRegions(vA, 'x'#13#10 + Region('1', 'ab'#13#10), vLevel) = '') and (vLevel = 1), IntToStr(vLevel));
  Check('G4 case-only difference = level 2', (DifferingRegions(vA, 'x'#13#10 + Region('1', 'A B'#13#10), vLevel) = '') and (vLevel = 2), IntToStr(vLevel));
  Check('G5 real difference = level 3 with the id', (DifferingRegions(vA, 'x'#13#10 + Region('1', 'c'#13#10), vLevel) = '1') and (vLevel = 3), IntToStr(vLevel));
  Check('G6 identical = level 0', (DifferingRegions(vA, vA, vLevel) = '') and (vLevel = 0), IntToStr(vLevel));
end;

function RunGolden(const pRepo, pObjects, pServer, pClient, pReport: string): Integer;
const
  LEVEL_NAME: array [0 .. 3] of string = ('BYTE-IDENTICAL', 'SAME-IGNORING-BLANKS', 'SAME-IGNORING-BLANKS-AND-CASE', 'DIFFERENT');
var
  vConn: TFDConnection;
  vPlan: TArray<TOrmFileChange>;
  vSkipped, vOut: TStringList;
  C: TOrmFileChange;
  vLevel, vOutsideBad: Integer;
  vCounts: array [0 .. 3] of Integer;
  vIds, vNoRegion: string;
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
      vIds := DifferingRegions(C.OldText, C.NewText, vLevel);
      Inc(vCounts[vLevel]);
      vNoRegion := '';
      if OutsideRegions(C.OldText) <> OutsideRegions(C.NewText) then
      begin
        Inc(vOutsideBad);
        vNoRegion := ' OUTSIDE-CHANGED';
      end;
      if not C.OldText.Contains('DB-RAD') then
        vNoRegion := vNoRegion + ' NO-REGIONS';
      vOut.Add(Format('UNIT %s %s%s%s', [ExtractFileName(C.FileName), LEVEL_NAME[vLevel],
        if vIds <> '' then ' regions=' + vIds else '', vNoRegion]));
    end;
    { regenerate INTO the folders given (the runner passes a COPY of ORM3) for side-by-side diffs }
    ApplyOrmChanges(vPlan, False);
    for vIds in vSkipped do
      vOut.Add('SKIPPED ' + vIds);
    vOut.Add(Format('GOLDEN units=%d byte_identical=%d same_ignoring_blanks=%d same_ignoring_blanks_and_case=%d different=%d outside_changed=%d skipped=%d',
      [Length(vPlan), vCounts[0], vCounts[1], vCounts[2], vCounts[3], vOutsideBad, vSkipped.Count]));
    vOut.SaveToFile(pReport, TEncoding.ASCII);
    Writeln(vOut[vOut.Count - 1]);
    Result := if vOutsideBad = 0 then 0 else 1;
  finally
    vOut.Free;
    vSkipped.Free;
    vConn.Free;
  end;
end;

var
  vRepo: TFDConnection;
begin
  try
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
