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
  , DRagLint.FieldRepo.ParamArray in '..\..\src\sql\DRagLint.FieldRepo.ParamArray.pas';

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

begin
  GPass := 0;
  GFail := 0;
  try
    RunTests;
    RunNamedTests;
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
