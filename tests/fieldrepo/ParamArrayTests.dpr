program ParamArrayTests;

{ Self-contained console test runner (no DUnitX) for DRagLint.FieldRepo.ParamArray
  (drag-lint 1.52, lane TTPA, TableTools migration step M9).
  One PASS/FAIL line per case, a summary line, exit code 1 on any failure.
  The golden block was derived from the TableTools assistant's format templates by an
  independent generator (the assistant itself needs a live IDE designer). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , DRagLint.FieldRepo.ParamArray in '..\..\src\sql\DRagLint.FieldRepo.ParamArray.pas'
  , DRagLint.FieldRepo.ParamArray.Prepare in '..\..\src\sql\DRagLint.FieldRepo.ParamArray.Prepare.pas';

const
  GOLDEN: array[0..46] of string = (
    'const',
    '  STEPSIZE = 20000;',
    'const',
    '  parID                     = 0;',
    '  parFOLDER_NAME            = 1;',
    '  parCREATED                = 2;',
    '  parFLAG                   = 3;',
    '  parACTIVE                 = 4;',
    '  parAMOUNT                 = 5;',
    '',
    '  qIns.Params.BindMode := pbByNumber; // More efficient than pbByName for Array DML',
    '  qIns.Params.ArraySize:= STEPSIZE;',
    '  var I := 0;',
    '  var DoneCnt := 0;',
    '',
    '  while not tblFOLDERS.EOF do',
    '  begin',
    '    try',
    '##### TYPE MISMATCH ##### <AsDates> <- <AsFloat>',
    '//      qIns.Params[parAMOUNT                ].AsDates[I]                    :=          tblFOLDERSAMOUNT         .AsFloat        ; // Date            <- Float',
    '      qIns.Params[parCREATED               ].AsSQLTimeStampOffsets[I]      := DateTimeToSQLTimeStampOffset(tblFOLDERSCREATED        .AsDateTime     ); // TimeStampOffset <- DateTime',
    '      qIns.Params[parFLAG                  ].AsBytes[I]                    := byte(ord(tblFOLDERSFLAG           .AsString       [1])); // Byte            <- String',
    '      qIns.Params[parID                    ].AsIntegers[I]                 :=          tblFOLDERSID             .AsInteger      ; // Integer         <- Integer',
    '      qIns.Params[parFOLDER_NAME           ].AsWideStrings[I]              :=          tblFOLDERSNAME           .AsString       ; // String          <- String',
    '// MISSING PARAMS',
    'qIns.Params[parACTIVE                ].AsBooleans[I]                 :=          True; // Boolean',
    '#### MISSING FIELDS ####',
    'NOTES',
    '//',
    '//',
    '',
    '      Inc(DoneCnt);',
    '      if (I >= STEPSIZE - 2) then',
    '      begin',
    '        qIns.Execute(I + 1);',
    '        I:= - 1;',
    '      end;',
    '    except',
    '      on e: Exception do',
    '        Application.HandleException(Self);',
    '    end; // try/except',
    '    Inc(I);',
    '    tblFOLDERS.Next;',
    '  end; // while',
    '  if I > 0 then',
    '    qIns.Execute(I);',
    '  tblFOLDERS.Close;');

  FIXTURE_DFM =
    'object frmX: TForm'#13#10 +
    '  object tblFOLDERS: TTable'#13#10 +
    '    object tblFOLDERSID: TIntegerField'#13#10 +
    '      FieldName = ''ID'''#13#10 +
    '    end'#13#10 +
    '    object tblFOLDERSNAME: TStringField'#13#10 +
    '      FieldName = ''NAME'''#13#10 +
    '    end'#13#10 +
    '    object tblFOLDERSCREATED: TDateTimeField'#13#10 +
    '      FieldName = ''CREATED'''#13#10 +
    '    end'#13#10 +
    '    object tblFOLDERSFLAG: TStringField'#13#10 +
    '      FieldName = ''FLAG'''#13#10 +
    '    end'#13#10 +
    '    object tblFOLDERSNOTES: TMemoField'#13#10 +
    '      FieldName = ''NOTES'''#13#10 +
    '    end'#13#10 +
    '    object tblFOLDERSAMOUNT: TFloatField'#13#10 +
    '      FieldName = ''AMOUNT'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object qIns: TFDQuery'#13#10 +
    '    ParamData = <'#13#10 +
    '      item'#13#10 +
    '        Name = ''ID'''#13#10 +
    '        DataType = ftInteger'#13#10 +
    '        ParamType = ptInput'#13#10 +
    '      end'#13#10 +
    '      item'#13#10 +
    '        Name = ''FOLDER_NAME'''#13#10 +
    '        DataType = ftString'#13#10 +
    '      end'#13#10 +
    '      item'#13#10 +
    '        Name = ''CREATED'''#13#10 +
    '        DataType = ftTimeStampOffset'#13#10 +
    '      end'#13#10 +
    '      item'#13#10 +
    '        Name = ''FLAG'''#13#10 +
    '        DataType = ftByte'#13#10 +
    '      end'#13#10 +
    '      item'#13#10 +
    '        Name = ''ACTIVE'''#13#10 +
    '        DataType = ftBoolean'#13#10 +
    '      end'#13#10 +
    '      item'#13#10 +
    '        Name = ''AMOUNT'''#13#10 +
    '        DataType = ftDate'#13#10 +
    '      end>'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  FIXTURE_PAS =
    'unit uFolders;'#13#10#13#10 +
    'interface'#13#10#13#10 +
    'implementation'#13#10#13#10 +
    'end.'#13#10;

var
  GPass, GFail: Integer;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ' + pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ' + pName + ' ' + pDetail);
  end;
end;

function GoldenText: string;
var
  LIdx: Integer;
  LList: TStringList;
begin
  LList := TStringList.Create;
  try
    for LIdx := Low(GOLDEN) to High(GOLDEN) do
      LList.Add(GOLDEN[LIdx]);
    Result := LList.Text;
  finally
    LList.Free;
  end;
end;

function FirstDiff(const pExpected, pActual: string): string;
var
  LExp, LAct: TStringList;
  LIdx: Integer;
begin
  Result := '';
  LExp := TStringList.Create;
  LAct := TStringList.Create;
  try
    LExp.Text := pExpected;
    LAct.Text := pActual;
    for LIdx := 0 to LExp.Count - 1 do
      if (LIdx >= LAct.Count) or (LExp[LIdx] <> LAct[LIdx]) then
      begin
        Result := Format('line %d expected [%s] actual [%s]',
          [LIdx + 1, LExp[LIdx], if LIdx < LAct.Count then LAct[LIdx] else '<eof>']);
        Exit;
      end;
    if LAct.Count > LExp.Count then
      Result := Format('actual has %d extra lines', [LAct.Count - LExp.Count]);
  finally
    LAct.Free;
    LExp.Free;
  end;
end;

var
  GGateCalls: Integer;
  GGateResult: Boolean;

function CountingGate(const pText: string): Boolean;
begin
  Inc(GGateCalls);
  Result := GGateResult;
end;

procedure RunTests;
var
  LQuery, LTable, LBlock, LErr, LPlan, LNew, LText: string;
  LSrc, LDst, LDst2: TPAColumns;
  LOpts: TPAOptions;
  LStatus: TPAStatus;
  LGate: TPAGate;
  LRes: TPAUnitResults;
  LUnits: array of TPAUnitInput;
  LOk: Boolean;
begin
  { type tables }
  Check('general: Largeint -> Integer family', PAGeneralType(pftLargeint) = pftInteger);
  Check('general: DateTimeOffset -> TimeStamp family', PAGeneralType(pftTimeStampOffset) = pftTimeStamp);
  Check('general: unknown -> Variant', PAGeneralType(pftUnknown) = pftVariant);
  Check('type name: Integer / TimeStamp', (PATypeName(pftInteger) = 'Integer') and (PATypeName(pftTimeStamp) = 'TimeStamp'));
  Check('source accessor: Smallint', PASourceAccessor(pftSmallint) = 'AsInteger');
  Check('param accessor: Time', PAParamArrayAccessor(pftTime) = 'AsSQLTimeIntervals');
  Check('param accessor: Largeint', PAParamArrayAccessor(pftLargeint) = 'AsLargeInts');
  Check('dfm token: class', PATypeFromDfmToken('TIntegerField') = pftInteger);
  Check('dfm token: ft', PATypeFromDfmToken('ftTimeStampOffset') = pftTimeStampOffset);
  Check('dfm token: unknown (control)', PATypeFromDfmToken('TNoSuchField') = pftUnknown);

  { discovery }
  LOk := PADiscoverFromDfm(FIXTURE_DFM, LQuery, LTable, LSrc, LDst);
  Check('discover: found', LOk);
  Check('discover: names', (LQuery = 'qIns') and (LTable = 'tblFOLDERS'), LQuery + '/' + LTable);
  Check('discover: 6 fields 6 params', (Length(LSrc) = 6) and (Length(LDst) = 6),
    IntToStr(Length(LSrc)) + '/' + IntToStr(Length(LDst)));
  Check('discover: field map', (Length(LSrc) = 6) and (LSrc[1].Name = 'tblFOLDERSNAME') and
    (LSrc[1].FieldName = 'NAME') and (LSrc[1].DataType = pftString));
  Check('discover: param map', (Length(LDst) = 6) and (LDst[2].Name = 'CREATED') and
    (LDst[2].DataType = pftTimeStampOffset));
  Check('discover: no query -> False (control)',
    not PADiscoverFromDfm('object f: TForm'#13#10'end'#13#10, LQuery, LTable, LSrc, LDst2));
  PADiscoverFromDfm(FIXTURE_DFM, LQuery, LTable, LSrc, LDst);

  { golden block }
  LOpts := PADefaultOptions;
  LOk := PABuildBlock(LQuery, LTable, LSrc, LDst, LOpts, LBlock, LErr);
  Check('block: built', LOk, LErr);
  Check('block: golden', LBlock = GoldenText, FirstDiff(GoldenText, LBlock));
  Check('block: mismatch marker present', ContainsStr(LBlock, '##### TYPE MISMATCH #####'));
  LDst2 := Concat(LDst);
  LDst2[5].DataType := pftFloat;
  PABuildBlock(LQuery, LTable, LSrc, LDst2, LOpts, LText, LErr);
  Check('block: no mismatch when types agree (positive control)',
    (not ContainsStr(LText, 'TYPE MISMATCH')) and (ContainsStr(LText, 'AsFloats[I]')));
  Check('block: default has no loader-form lines',
    (not ContainsStr(LBlock, 'NRECS')) and (not ContainsStr(LBlock, 'Commit')));
  LOpts.ProgressForm := 'frmLoader2019_Main';
  PABuildBlock(LQuery, LTable, LSrc, LDst, LOpts, LText, LErr);
  Check('block: ProgressForm adds NRECS / progress / Commit',
    (ContainsStr(LText, 'Inc(frmLoader2019_Main.NRECS);')) and
    (ContainsStr(LText, 'frmLoader2019_Main.prbRecords.Position:= DoneCnt;')) and
    (ContainsStr(LText, 'frmLoader2019_Main.IBD.Commit;')));
  LOpts := PADefaultOptions;
  LOpts.StepSize := 500;
  PABuildBlock(LQuery, LTable, LSrc, LDst, LOpts, LText, LErr);
  Check('block: StepSize option', ContainsStr(LText, 'STEPSIZE = 500;'));

  { errors }
  Check('block: no params -> error',
    (not PABuildBlock(LQuery, LTable, LSrc, nil, LOpts, LText, LErr)) and (LErr = 'Query has no parameters.'), LErr);
  Check('block: missing table -> error',
    (not PABuildBlock(LQuery, '', LSrc, LDst, LOpts, LText, LErr)) and (LErr = 'Table and / or Query is missing.'), LErr);

  { plan }
  LPlan := PABuildPlan('uFolders', FIXTURE_PAS, LBlock);
  Check('plan: header', StartsStr('--- a/uFolders.pas'#13#10'+++ b/uFolders.pas'#13#10, LPlan), LPlan);
  Check('plan: hunk at line 7', ContainsStr(LPlan, Format('@@ -7,0 +7,%d @@', [Length(GOLDEN) + 4])), LPlan);
  Check('plan: lines are additions', ContainsStr(LPlan, '+{'#13#10));
  Check('plan: no insertion point -> empty', PABuildPlan('x', 'unit x; interface implementation', LBlock) = '');

  { apply through the gate }
  GGateCalls := 0;
  GGateResult := False;
  LGate := CountingGate;
  LStatus := PAApplyPlan(FIXTURE_PAS, LBlock, LGate, LNew);
  Check('apply: gate refuses -> refused', LStatus = pasRefusedByGate);
  Check('apply: refused leaves source untouched', LNew = FIXTURE_PAS);
  Check('apply: gate called exactly once', GGateCalls = 1, IntToStr(GGateCalls));
  GGateResult := True;
  LStatus := PAApplyPlan(FIXTURE_PAS, LBlock, LGate, LNew);
  Check('apply: gate accepts -> applied', LStatus = pasApplied);
  Check('apply: block inserted before end.',
    (ContainsStr(LNew, '{'#13#10'const')) and (ContainsStr(LNew, #13#10'}'#13#10'end.')) and (LNew <> FIXTURE_PAS));
  Check('apply: unit head preserved', ContainsStr(LNew, 'implementation'#13#10#13#10#13#10'{'), LNew);
  Check('apply: no end. -> no insertion point',
    PAApplyPlan('unit x;', LBlock, LGate, LText) = pasNoInsertPoint);

  { project }
  SetLength(LUnits, 4);
  LUnits[0].UnitName := 'uFolders';
  LUnits[0].Source := FIXTURE_PAS;
  LUnits[0].Dfm := FIXTURE_DFM;
  LUnits[1].UnitName := 'uTestHelper';
  LUnits[1].Source := FIXTURE_PAS;
  LUnits[1].Dfm := FIXTURE_DFM;
  LUnits[2].UnitName := 'frmMain';
  LUnits[2].Source := FIXTURE_PAS;
  LUnits[2].Dfm := FIXTURE_DFM;
  LUnits[3].UnitName := 'uPlain';
  LUnits[3].Source := FIXTURE_PAS;
  LUnits[3].Dfm := 'object f: TForm'#13#10'end'#13#10;
  GGateCalls := 0;
  LRes := PARunProject(LUnits, PADefaultOptions, LGate);
  Check('project: eligible unit applied', LRes[0].Status = pasApplied);
  Check('project: excluded unit skipped', LRes[1].Status = pasExcluded);
  Check('project: non-u unit skipped', LRes[2].Status = pasExcluded);
  Check('project: unit without table/query has no block', LRes[3].Status = pasNoBlock);
  Check('project: only the eligible unit reached the gate', GGateCalls = 1, IntToStr(GGateCalls));
  Check('project: plan carried', Pos('@@ -7,0', LRes[0].Plan) > 0);
  Check('project: eligibility is case-insensitive on the u prefix', PAProjectEligible('UFolders'));
  Check('project: exclusion list is case-insensitive', not PAProjectEligible('ucompgrp'));
  GGateResult := False;
  LRes := PARunProject(LUnits, PADefaultOptions, LGate);
  Check('project: gate refusal leaves unit source', (LRes[0].Status = pasRefusedByGate) and (LRes[0].NewSource = FIXTURE_PAS));
end;

procedure RunNamedTests;
const
  MULTI_DFM =
    'object frmX: TForm'#13#10 +
    '  object tblA: TTable'#13#10 +
    '    object tblAID: TIntegerField'#13#10 +
    '      FieldName = ''ID'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object tblB: TTable'#13#10 +
    '    object tblBCODE: TStringField'#13#10 +
    '      FieldName = ''CODE'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object qOne: TFDQuery'#13#10 +
    '    ParamData = <'#13#10 +
    '      item'#13#10 +
    '        Name = ''ID'''#13#10 +
    '        DataType = ftInteger'#13#10 +
    '      end>'#13#10 +
    '  end'#13#10 +
    '  object qTwo: TFDQuery'#13#10 +
    '    ParamData = <'#13#10 +
    '      item'#13#10 +
    '        Name = ''CODE'''#13#10 +
    '        DataType = ftString'#13#10 +
    '      end>'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
var
  LSrc, LDst: TPAColumns;
  LQ, LT: string;
begin
  Check('named: exact pick of first table + first query',
    PADiscoverNamed(MULTI_DFM, 'qOne', 'tblA', LQ, LT, LSrc, LDst) and (LQ = 'qOne') and (LT = 'tblA')
      and (Length(LSrc) = 1) and (LSrc[0].FieldName = 'ID') and (Length(LDst) = 1) and (LDst[0].Name = 'ID'));
  Check('named: other pair',
    PADiscoverNamed(MULTI_DFM, 'qTwo', 'tblB', LQ, LT, LSrc, LDst) and (LSrc[0].FieldName = 'CODE')
      and (LDst[0].Name = 'CODE'));
  Check('named: names are case-insensitive', PADiscoverNamed(MULTI_DFM, 'QONE', 'TBLA', LQ, LT, LSrc, LDst));
  Check('named: absent query is a miss, never a fallback',
    not PADiscoverNamed(MULTI_DFM, 'qNope', 'tblA', LQ, LT, LSrc, LDst));
  Check('named: absent table is a miss', not PADiscoverNamed(MULTI_DFM, 'qOne', 'tblNope', LQ, LT, LSrc, LDst));
  Check('named: only the query named, table by the LAST-table heuristic',
    PADiscoverNamed(MULTI_DFM, 'qOne', '', LQ, LT, LSrc, LDst) and (LT = 'tblB') and (LQ = 'qOne'));
  Check('named: empty names = PADiscoverFromDfm',
    PADiscoverNamed(MULTI_DFM, '', '', LQ, LT, LSrc, LDst) and (LQ = 'qTwo') and (LT = 'tblB'));
  Check('markers: golden block has markers', PABlockHasMarkers(GoldenText));
  Check('markers: clean text has none', not PABlockHasMarkers('  qIns.Execute(I);'#13#10));
  Check('markers: MISSING PARAMS alone counts', PABlockHasMarkers('x'#13#10'// MISSING PARAMS'#13#10));
end;

procedure RunPrepareTests;
const
  PREP_DFM =
    'object frmLoad: TfrmLoad'#13#10 +
    '  Left = 0'#13#10 +
    '  Caption = ''Load'''#13#10 +
    '  object tblFOLDERS: TTable'#13#10 +
    '    TableName = ''FOLDERS'''#13#10 +
    '    object tblFOLDERSID: TIntegerField'#13#10 +
    '      FieldName = ''ID'''#13#10 +
    '    end'#13#10 +
    '    object tblFOLDERSNAME: TStringField'#13#10 +
    '      FieldName = ''NAME'''#13#10 +
    '      Size = 40'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object qryFOLDERS: TFDQuery'#13#10 +
    '    AutoCalcFields = False'#13#10 +
    '    CachedUpdates = True'#13#10 +
    '    Connection = dmMain.IBD'#13#10 +
    '    SchemaAdapter = SA1'#13#10 +
    '    UpdateObject = updFOLDERS'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''/* load */ SELECT ID, NAME'''#13#10 +
    '      ''FROM FOLDERS'')'#13#10 +
    '    Left = 32'#13#10 +
    '    Top = 48'#13#10 +
    '    object qryFOLDERSID: TIntegerField'#13#10 +
    '      FieldName = ''ID'''#13#10 +
    '      Origin = ''ID'''#13#10 +
    '    end'#13#10 +
    '    object qryFOLDERSNAME: TStringField'#13#10 +
    '      FieldName = ''NAME'''#13#10 +
    '      Size = 40'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object qryProc: TFDQuery'#13#10 +
    '    UpdateObject = updFOLDERS'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''EXECUTE PROCEDURE P_X'')'#13#10 +
    '    Left = 32'#13#10 +
    '    Top = 96'#13#10 +
    '  end'#13#10 +
    '  object updFOLDERS: TFDUpdateSQL'#13#10 +
    '    InsertSQL.Strings = ('#13#10 +
    '      ''INSERT INTO FOLDERS (ID, NAME)'''#13#10 +
    '      ''VALUES (:NEW_ID, :NEW_NAME)'')'#13#10 +
    '    ModifySQL.Strings = ('#13#10 +
    '      ''UPDATE FOLDERS SET NAME = :NEW_NAME WHERE ID = :OLD_ID'')'#13#10 +
    '    Left = 64'#13#10 +
    '    Top = 48'#13#10 +
    '  end'#13#10 +
    '  object SA1: TFDSchemaAdapter'#13#10 +
    '    Left = 96'#13#10 +
    '    Top = 48'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  PREP_DFM_EXPECTED =
    'object frmLoad: TfrmLoad'#13#10 +
    '  Left = 0'#13#10 +
    '  Caption = ''Load'''#13#10 +
    '  object tblFOLDERS: TTable'#13#10 +
    '    TableName = ''FOLDERS'''#13#10 +
    '    object tblFOLDERSID: TIntegerField'#13#10 +
    '      FieldName = ''ID'''#13#10 +
    '    end'#13#10 +
    '    object tblFOLDERSNAME: TStringField'#13#10 +
    '      FieldName = ''NAME'''#13#10 +
    '      Size = 40'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object qryFOLDERS: TFDQuery'#13#10 +
    '    AutoCalcFields = False'#13#10 +
    '    ObjectView = False'#13#10 +
    '    Connection = dmMain.IBD'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''INSERT INTO FOLDERS (ID, NAME)'''#13#10 +
    '      ''VALUES (:NEW_ID, :NEW_NAME)'')'#13#10 +
    '    Left = 32'#13#10 +
    '    Top = 48'#13#10 +
    '    ParamData = <'#13#10 +
    '      item'#13#10 +
    '        Name = ''NEW_ID'''#13#10 +
    '        DataType = ftInteger'#13#10 +
    '        ParamType = ptInput'#13#10 +
    '      end'#13#10 +
    '      item'#13#10 +
    '        Name = ''NEW_NAME'''#13#10 +
    '        DataType = ftString'#13#10 +
    '        ParamType = ptInput'#13#10 +
    '        Size = 40'#13#10 +
    '      end>'#13#10 +
    '  end'#13#10 +
    '  object qryProc: TFDQuery'#13#10 +
    '    UpdateObject = ZZZupdFOLDERS'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''EXECUTE PROCEDURE P_X'')'#13#10 +
    '    Left = 32'#13#10 +
    '    Top = 96'#13#10 +
    '  end'#13#10 +
    '  object ZZZupdFOLDERS: TFDUpdateSQL'#13#10 +
    '    InsertSQL.Strings = ('#13#10 +
    '      ''INSERT INTO FOLDERS (ID, NAME)'''#13#10 +
    '      ''VALUES (:NEW_ID, :NEW_NAME)'')'#13#10 +
    '    ModifySQL.Strings = ('#13#10 +
    '      ''UPDATE FOLDERS SET NAME = :NEW_NAME WHERE ID = :OLD_ID'')'#13#10 +
    '    Left = 64'#13#10 +
    '    Top = 48'#13#10 +
    '  end'#13#10 +
    '  object ZZZSA1: TFDSchemaAdapter'#13#10 +
    '    Left = 96'#13#10 +
    '    Top = 48'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  PREP_PAS =
    'unit uLoad;'#13#10#13#10 +
    'interface'#13#10#13#10 +
    'type'#13#10 +
    '  TfrmLoad = class(TForm)'#13#10 +
    '    tblFOLDERS: TTable;'#13#10 +
    '    tblFOLDERSID: TIntegerField;'#13#10 +
    '    tblFOLDERSNAME: TStringField;'#13#10 +
    '    qryFOLDERS: TFDQuery;'#13#10 +
    '    qryFOLDERSID: TIntegerField;'#13#10 +
    '    qryFOLDERSNAME: TStringField;'#13#10 +
    '    qryProc: TFDQuery;'#13#10 +
    '    updFOLDERS: TFDUpdateSQL;'#13#10 +
    '    SA1: TFDSchemaAdapter;'#13#10 +
    '  private'#13#10 +
    '    FCount: Integer;'#13#10 +
    '  end;'#13#10#13#10 +
    'implementation'#13#10#13#10 +
    '{$R *.dfm}'#13#10#13#10 +
    'end.'#13#10;

  PREP_PAS_EXPECTED =
    'unit uLoad;'#13#10#13#10 +
    'interface'#13#10#13#10 +
    'type'#13#10 +
    '  TfrmLoad = class(TForm)'#13#10 +
    '    tblFOLDERS: TTable;'#13#10 +
    '    tblFOLDERSID: TIntegerField;'#13#10 +
    '    tblFOLDERSNAME: TStringField;'#13#10 +
    '    qryFOLDERS: TFDQuery;'#13#10 +
    '    qryProc: TFDQuery;'#13#10 +
    '    ZZZupdFOLDERS: TFDUpdateSQL;'#13#10 +
    '    ZZZSA1: TFDSchemaAdapter;'#13#10 +
    '  private'#13#10 +
    '    FCount: Integer;'#13#10 +
    '  end;'#13#10#13#10 +
    'implementation'#13#10#13#10 +
    '{$R *.dfm}'#13#10#13#10 +
    'end.'#13#10;

  { a SELECT query with no update object / schema adapter, ObjectView already written, a
    comment line and a continued string item before the SELECT }
  BARE_DFM =
    'object frmB: TfrmB'#13#10 +
    '  object qB: TFDQuery'#13#10 +
    '    ObjectView = True'#13#10 +
    '    CachedUpdates = False'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''-- it''''s a comment'''#13#10 +
    '      '#13#10 +
    '        ''sel'' +'#13#10 +
    '        ''ect * FROM T'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  BARE_DFM_EXPECTED =
    'object frmB: TfrmB'#13#10 +
    '  object qB: TFDQuery'#13#10 +
    '    ObjectView = False'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''-- it''''s a comment'''#13#10 +
    '      '#13#10 +
    '        ''sel'' +'#13#10 +
    '        ''ect * FROM T'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

  DIFF_OLD = 'a'#13#10'b'#13#10'c'#13#10'd'#13#10;
  DIFF_NEW = 'a'#13#10'B'#13#10'c'#13#10'd'#13#10'e'#13#10;
  DIFF_EXPECTED =
    '--- a/x.dfm'#13#10 +
    '+++ b/x.dfm'#13#10 +
    '@@ -2,1 +2,1 @@'#13#10 +
    '-b'#13#10 +
    '+B'#13#10 +
    '@@ -4,0 +5,1 @@'#13#10 +
    '+e'#13#10;
var
  LPrep, LAgain: TPAPrepareResult;
  LQ, LT: string;
  LSrc, LDst: TPAColumns;
  LCollide: string;
begin
  LPrep := PAPrepareQueries(PREP_DFM, PREP_PAS, '');
  Check('prepare: changed', LPrep.Changed);
  Check('prepare: dfm rewrite (golden)', LPrep.Dfm = PREP_DFM_EXPECTED, FirstDiff(PREP_DFM_EXPECTED, LPrep.Dfm));
  Check('prepare: pas field declarations (golden)', LPrep.Pas = PREP_PAS_EXPECTED, FirstDiff(PREP_PAS_EXPECTED, LPrep.Pas));
  Check('prepare: one query prepared', (Length(LPrep.Queries) = 1) and (LPrep.Queries[0] = 'qryFOLDERS'));
  Check('prepare: two renames', Length(LPrep.Renamed) = 2, IntToStr(Length(LPrep.Renamed)));
  Check('prepare: two persistent fields removed', Length(LPrep.RemovedFields) = 2, IntToStr(Length(LPrep.RemovedFields)));
  Check('prepare: no warnings', Length(LPrep.Warnings) = 0, string.Join(' | ', LPrep.Warnings));
  Check('prepare: discovery sees the INSERT params',
    PADiscoverFromDfm(LPrep.Dfm, LQ, LT, LSrc, LDst) and (LQ = 'qryFOLDERS') and (Length(LDst) = 2));
  Check('prepare: param names and types come from the removed fields',
    (Length(LDst) = 2) and (LDst[0].Name = 'NEW_ID') and (LDst[0].DataType = pftInteger) and (LDst[1].DataType = pftString));
  Check('prepare: unprepared DFM has no parameterised query (control)',
    not PADiscoverFromDfm(PREP_DFM, LQ, LT, LSrc, LDst));
  LAgain := PAPrepareQueries(LPrep.Dfm, LPrep.Pas, '');
  Check('prepare: idempotent (INSERT SQL is not prepared again)',
    (not LAgain.Changed) and (LAgain.Dfm = LPrep.Dfm) and (LAgain.Pas = LPrep.Pas));
  LAgain := PAPrepareQueries(PREP_DFM, PREP_PAS, 'qryProc');
  Check('prepare: --query naming a non-SELECT query changes nothing',
    (not LAgain.Changed) and (LAgain.Dfm = PREP_DFM));
  LAgain := PAPrepareQueries(PREP_DFM, PREP_PAS, 'QRYFOLDERS');
  Check('prepare: --query is case-insensitive', LAgain.Dfm = PREP_DFM_EXPECTED);

  LAgain := PAPrepareQueries(BARE_DFM, '', '');
  Check('prepare: bare SELECT -> ObjectView False, CachedUpdates line dropped, SQL kept',
    LAgain.Dfm = BARE_DFM_EXPECTED, FirstDiff(BARE_DFM_EXPECTED, LAgain.Dfm));
  Check('prepare: missing update object / schema adapter are warnings',
    (Length(LAgain.Warnings) = 2) and ContainsText(LAgain.Warnings[0], 'Update Object is not assigned')
      and ContainsText(LAgain.Warnings[1], 'Schema Adapter is not assigned'), string.Join(' | ', LAgain.Warnings));

  LCollide := StringReplace(PREP_DFM, '  object SA1: TFDSchemaAdapter',
    '  object ZZZSA1: TFDSchemaAdapter'#13#10'  end'#13#10'  object SA1: TFDSchemaAdapter', []);
  LAgain := PAPrepareQueries(LCollide, PREP_PAS, '');
  Check('prepare: rename onto an existing name is skipped with a warning',
    ContainsText(string.Join(' | ', LAgain.Warnings), 'ZZZSA1') and ContainsStr(LAgain.Dfm, '  object SA1: TFDSchemaAdapter')
      and not ContainsStr(LAgain.Dfm, 'SchemaAdapter = SA1'), string.Join(' | ', LAgain.Warnings));

  Check('diff: zero-context unified hunks', PAUnifiedDiff('x.dfm', DIFF_OLD, DIFF_NEW) = DIFF_EXPECTED,
    PAUnifiedDiff('x.dfm', DIFF_OLD, DIFF_NEW));
  Check('diff: identical texts -> empty', PAUnifiedDiff('x.dfm', DIFF_OLD, DIFF_OLD) = '');
  Check('diff: prepare diff names both files',
    ContainsStr(PAUnifiedDiff('uLoad.dfm', PREP_DFM, LPrep.Dfm), '+    ObjectView = False') and
    ContainsStr(PAUnifiedDiff('uLoad.dfm', PREP_DFM, LPrep.Dfm), '-    CachedUpdates = True'));
end;

begin
  GPass := 0;
  GFail := 0;
  try
    RunTests;
    RunNamedTests;
    RunPrepareTests;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL exception ' + E.ClassName + ': ' + E.Message);
    end;
  end;
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
