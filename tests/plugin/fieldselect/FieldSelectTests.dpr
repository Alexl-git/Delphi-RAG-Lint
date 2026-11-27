program FieldSelectTests;

{ Console test runner (no DUnitX) of DragLint.Plugin.FieldSelectModel (drag-lint 1.54, lane TT-DIALOG). One PASS/FAIL line
  per case, a summary line, exit code 1 on any failure.

  FieldSelectTests                                  the unit cases
  FieldSelectTests --rows FILE                      rows of the first dataset of a read-dfm --json output
  FieldSelectTests --names FILE [+FIELD|-FIELD]...  --names after the clicks, then the removed components
  FieldSelectTests --plan FILE OUT [+ID|-ID]...     writes the --select file of a dry run
  (the last three let run_v154_TTDIALOG.ps1 use what a real engine printed) }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  DRagLint.FieldRepo.Kinds in '..\..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.DfmReadSelection in '..\..\..\src\sql\DRagLint.FieldRepo.DfmReadSelection.pas',
  DragLint.Plugin.FieldSelectModel in '..\..\..\src\delphi-plugin\DragLint.Plugin.FieldSelectModel.pas';

const
  READ_JSON = '{"datasets":[{"dfm":"u.dfm","dataset":"qryA","class":"TFDQuery","table":"ORDERS","unresolved":"",' +
    '"fields":{},"noColumn":[],"persistent":[' +
    '{"field":"ID","component":"qryAID","class":"TIntegerField","kind":"data","table":"ORDERS","column":"ID"},' +
    '{"field":"Amount","component":"qryAAmount","class":"TFloatField","kind":"data","table":"ORDERS","column":"QTY"},' +
    '{"field":"CNT","component":"qryACNT","class":"TIntegerField","kind":"data","table":"","column":""},' +
    '{"field":"TNAME","component":"qryATNAME","class":"TStringField","kind":"data","table":"TOOLS","column":"NAME"},' +
    '{"field":"LEGACY","component":"qryALEGACY","class":"TStringField","kind":"data","table":"ORDERS","column":"LEGACY"}],' +
    '"tableFields":[' +
    '{"field":"ID","kind":"data","sourceKey":"","body":""},' +
    '{"field":"QTY","kind":"data","sourceKey":"","body":""},' +
    '{"field":"PRICE","kind":"data","sourceKey":"","body":""},' +
    '{"field":"TOTAL","kind":"calc","sourceKey":"","body":"{{TOTAL}}.Value := {{QTY}}.Value * {{PRICE}}.Value;"},' +
    '{"field":"VAT","kind":"internal-calc","sourceKey":"","body":"{{VAT}}.Value := {{TOTAL}}.Value / 5;"},' +
    '{"field":"TOOLID","kind":"data","sourceKey":"","body":""},' +
    '{"field":"TOOL","kind":"lookup","sourceKey":"TOOLID","body":""},' +
    '{"field":"BAR","kind":"graphical","sourceKey":"","body":""},' +
    '{"field":"BAD","kind":"calc","sourceKey":"","body":"{{BAD}}.Value := {{NOPE}}.Value;"}]}],' +
    '"totals":{},"changeSet":{"direction":"dfm-to-repo","count":0,"blocked":0,"changes":[]},"warnings":[],"applied":0}';
  PLAN_JSON = '{"datasets":[],"changeSet":{"direction":"repo-to-dfm","count":4,"blocked":1,"changes":[' +
    '{"id":1,"op":"update","target":"u.dfm qryAID","prop":"DisplayLabel","old":"","new":"No","checked":true,"blocked":""},' +
    '{"id":2,"op":"insert","target":"u.dfm qryAPRICE","prop":"","old":"","new":"TFloatField","checked":true,"blocked":""},' +
    '{"id":3,"op":"delete","target":"u.dfm qryALEGACY","prop":"","old":"TStringField","new":"","checked":false,"blocked":""},' +
    '{"id":4,"op":"delete","target":"u.dfm qryAAmount","prop":"","old":"TFloatField","new":"","checked":false,"blocked":"used"}]},' +
    '"plan":"3f0c9a51b7e2d684","warnings":["w \u00e4"],"applied":0,"log":[]}';
  MAX_LOG = 3;

var
  GPass, GFail: Integer;

procedure Check(const pName: string; pOk: Boolean; const pDetail: string = '');
begin
  if pOk then
    Inc(GPass)
  else
    Inc(GFail);
  Writeln(if pOk then 'PASS ' else 'FAIL ', pName, if pOk or (pDetail = '') then '' else ' -- ' + pDetail);
end;

procedure CheckText(const pName, pGot, pWant: string);
begin
  Check(pName, pGot = pWant, 'got <' + pGot.Replace(#13#10, '|') + '> want <' + pWant.Replace(#13#10, '|') + '>');
end;

function FirstDataset(const pOutput: string): TFsDataset;
var
  VAll: TArray<TFsDataset>;
  VError: string;
begin
  Result := Default(TFsDataset);
  if ParseDatasets(pOutput, VAll, VError) and (Length(VAll) > 0) then
    Result := VAll[0];
end;

function RowOf(pSel: TFieldSelection; const pName: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to pSel.Count - 1 do
    if SameText(pSel[VI].Name, pName) then
      Exit(VI);
end;

{ NAME+ checked, NAME- not checked, ! locked }
function RowsText(pSel: TFieldSelection): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 0 to pSel.Count - 1 do
    Result := Result + (if VI = 0 then '' else ' ') + pSel[VI].Name + (if pSel[VI].Checked then '+' else '-') +
      (if pSel[VI].Locked = '' then '' else '!');
end;

function Click(pSel: TFieldSelection; const pName: string; pValue: Boolean; out pMessage: string): Boolean;
begin
  pMessage := '';
  Result := (RowOf(pSel, pName) >= 0) and pSel.SetChecked(RowOf(pSel, pName), pValue, pMessage);
end;

procedure TestParse;
var
  VAll: TArray<TFsDataset>;
  VError: string;
begin
  Check('P1 noise around the object', ParseDatasets('note: x'#13#10 + READ_JSON + #13#10'warning: y', VAll, VError) and
    (Length(VAll) = 1) and (VError = ''), VError);
  if Length(VAll) <> 1 then
    Exit;
  CheckText('P2 caption', VAll[0].Caption, 'qryA (TFDQuery)');
  CheckText('P3 table', VAll[0].TableName, 'ORDERS');
  Check('P4 persistent fields', (Length(VAll[0].Persistent) = 5) and (VAll[0].Persistent[1].Component = 'qryAAmount') and
    (VAll[0].Persistent[1].Column = 'QTY') and (VAll[0].Persistent[3].TableName = 'TOOLS'));
  Check('P5 table fields and kinds', (Length(VAll[0].TableFields) = 9) and (VAll[0].TableFields[4].Kind = frkInternalCalc) and
    (VAll[0].TableFields[7].Kind = frkGraphical) and (VAll[0].TableFields[6].SourceKey = 'TOOLID'));
  Check('P6 no object: an error that shows the output', not ParseDatasets('repo read-dfm: no dataset X in the DFM', VAll, VError) and
    ContainsText(VError, 'no dataset X') and (Length(VAll) = 0), VError);
  Check('P7 an object of something else', not ParseDatasets('{"a":1}', VAll, VError) and (VError <> ''), VError);
  Check('P8 a broken object', not ParseDatasets('{"datasets":[', VAll, VError) and (VError <> ''), VError);
  Check('P9 an object without datasets is no error', ParseDatasets('{"datasets":[]}', VAll, VError) and (Length(VAll) = 0), VError);
end;

procedure TestSelection;
var
  VSel: TFieldSelection;
  VMsg: string;
begin
  VSel := TFieldSelection.Create(FirstDataset(READ_JSON));
  try
    CheckText('S1 pre-checked = the persistent fields; aliases, graphical, foreign and unknown fields',
      RowsText(VSel), 'ID+ QTY+ PRICE- TOTAL- VAT- TOOLID- TOOL- BAR-! BAD- CNT+! TNAME+! LEGACY+!');
    if VSel.Count = 0 then
      Exit;
    CheckText('S2 the component of an aliased field', VSel[RowOf(VSel, 'QTY')].Component, 'qryAAmount');
    CheckText('S3 unchanged selection', VSel.Names, 'ID,QTY');
    CheckText('S4 nothing missing', VSel.MissingNote, '');
    Check('S5 check adds what it needs, transitively', Click(VSel, 'VAT', True, VMsg) and
      (RowsText(VSel) = 'ID+ QTY+ PRICE+ TOTAL+ VAT+ TOOLID- TOOL- BAR-! BAD- CNT+! TNAME+! LEGACY+!'), RowsText(VSel));
    CheckText('S6 and says so', VMsg, 'VAT needs PRICE, TOTAL: added');
    CheckText('S7 names', VSel.Names, 'ID,QTY,PRICE,TOTAL,VAT');
    Check('S8 a needed field stays', not Click(VSel, 'QTY', False, VMsg) and VSel[RowOf(VSel, 'QTY')].Checked);
    CheckText('S9 and says who needs it', VMsg, 'QTY stays: TOTAL needs it');
    Check('S10 uncheck removes nothing else', Click(VSel, 'VAT', False, VMsg) and (VMsg = '') and VSel[RowOf(VSel, 'TOTAL')].Checked);
    Check('S11 a lookup adds its key', Click(VSel, 'TOOL', True, VMsg) and (VMsg = 'TOOL needs TOOLID: added'), VMsg);
    Check('S12 a locked row stays', not Click(VSel, 'BAR', True, VMsg) and (VMsg <> '') and not VSel[RowOf(VSel, 'BAR')].Checked, VMsg);
    CheckText('S12b and says why', VMsg, 'BAR: a grid column, no field');
    Check('S12c a field the repository does not know cannot be removed', not Click(VSel, 'LEGACY', False, VMsg) and VSel[RowOf(VSel, 'LEGACY')].Checked);
    Check('S13 a field without its dependency is refused', not Click(VSel, 'BAD', True, VMsg) and ContainsText(VMsg, 'NOPE') and
      not VSel[RowOf(VSel, 'BAD')].Checked, VMsg);
    Check('S14 clicking a state it has changes nothing', Click(VSel, 'TOOL', True, VMsg) and (VMsg = ''), VMsg);
    CheckText('S15 summary', VSel.Summary, '6 of 8 fields selected: 4 to add, 0 to remove');
    Check('S16 a removed field', Click(VSel, 'ID', False, VMsg) and (string.Join(',', VSel.RemovedComponents) = 'qryAID'));
    CheckText('S17 refusal: none', VSel.Refusal, '');
    Check('S17b it has a table', VSel.HasTable);
    VSel.SetAll(False);
    CheckText('S18 unselect all', RowsText(VSel), 'ID- QTY- PRICE- TOTAL- VAT- TOOLID- TOOL- BAR-! BAD- CNT+! TNAME+! LEGACY+!');
    CheckText('S19 no name', VSel.Names, '');
    Check('S20 an empty selection is refused', VSel.Refusal <> '');
    VSel.SetAll(True);
    CheckText('S21 select all leaves out what cannot be selected', RowsText(VSel),
      'ID+ QTY+ PRICE+ TOTAL+ VAT+ TOOLID+ TOOL+ BAR-! BAD- CNT+! TNAME+! LEGACY+!');
    CheckText('S22 refusal after select all', VSel.Refusal, '');
  finally
    VSel.Free;
  end;
end;

procedure TestSelectionEdges;
var
  VDataset: TFsDataset;
  VSel: TFieldSelection;
  VPersistent: TFsPersistent;
begin
  VDataset := FirstDataset(READ_JSON);
  VPersistent.FieldName := 'Total';
  VPersistent.Component := 'qryATotal';
  VPersistent.Kind := frkCalc;
  VPersistent.TableName := 'orders';
  VPersistent.Column := 'TOTAL';
  VDataset.Persistent := VDataset.Persistent + [VPersistent];
  VSel := TFieldSelection.Create(VDataset);
  try
    CheckText('E1 a form field whose dependency is missing: only said', VSel.MissingNote, 'the selected fields also need PRICE: added on OK');
    Check('E2 pre-check stays the DFM''s', (RowOf(VSel, 'PRICE') >= 0) and not VSel[RowOf(VSel, 'PRICE')].Checked);
    CheckText('E3 names hold it', VSel.Names, 'ID,QTY,PRICE,TOTAL');
  finally
    VSel.Free;
  end;
  VPersistent.FieldName := 'BAD';
  VPersistent.Component := 'qryABAD';
  VPersistent.Column := 'BAD';
  VDataset.Persistent := [VPersistent];
  VSel := TFieldSelection.Create(VDataset);
  try
    Check('E4 a form field with an unknown dependency: the selection cannot be written', ContainsText(VSel.Refusal, 'NOPE'), VSel.Refusal);
    Check('E5 and the dialog still opens', VSel.Count = 9, IntToStr(VSel.Count));
  finally
    VSel.Free;
  end;
  VDataset.TableFields := nil;
  VDataset.Persistent := nil;
  VSel := TFieldSelection.Create(VDataset);
  try
    Check('E6 a table the repository does not have', not VSel.HasTable and (VSel.Count = 0) and ContainsText(VSel.Refusal, 'ORDERS'), VSel.Refusal);
  finally
    VSel.Free;
  end;
  VDataset.TableName := '';
  VDataset.Unresolved := 'the SQL reads 2 tables: A B';
  VSel := TFieldSelection.Create(VDataset);
  try
    Check('E7 a dataset without a table', not VSel.HasTable and ContainsText(VSel.Refusal, 'the SQL reads 2 tables'), VSel.Refusal);
  finally
    VSel.Free;
  end;
end;

procedure TestDatasetToUse;
var
  VAll: TArray<TFsDataset>;
begin
  SetLength(VAll, 2);
  VAll[0].Name := 'qryA';
  VAll[1].Name := 'qryB';
  Check('U1 the selected dataset', DatasetToUse(VAll, ['Button1', 'QRYB']) = 1);
  Check('U2 no dataset selected: ask', DatasetToUse(VAll, ['Button1']) = -1);
  Check('U3 two selected: ask', DatasetToUse(VAll, ['qryA', 'qryB']) = -1);
  Check('U4 the only one', DatasetToUse([VAll[1]], nil) = 0);
  Check('U5 none', DatasetToUse(nil, ['qryA']) = -1);
end;

procedure TestPlan;
var
  VPlan, VOther: TFsPlan;
  VError: string;
begin
  Check('C1 plan', ParsePlan('x'#10 + PLAN_JSON, VPlan, VError) and (Length(VPlan.Changes) = 4) and (VError = ''), VError);
  if Length(VPlan.Changes) <> 4 then
    Exit;
  CheckText('C2 plan id', VPlan.PlanId, '3f0c9a51b7e2d684');
  Check('C3 the engine''s defaults', VPlan.Changes[0].Checked and VPlan.Changes[1].Checked and not VPlan.Changes[2].Checked and
    (VPlan.Changes[3].Blocked = 'used'));
  Check('C4 warnings', (Length(VPlan.Warnings) = 1) and (VPlan.Warnings[0] = 'w '#$E4));
  CheckText('C5 select file', VPlan.SelectFileText, '# plan 3f0c9a51b7e2d684'#13#10'1'#13#10'2'#13#10);
  VPlan.SetAll(True);
  Check('C6 check all leaves a blocked change out', (VPlan.CheckedCount = 3) and not VPlan.Changes[3].Checked, IntToStr(VPlan.CheckedCount));
  VPlan.KeepAllBut(['qryAAmount']);
  Check('C7 a field the user did not uncheck is kept', (VPlan.Changes[2].Blocked <> '') and not VPlan.Changes[2].Checked);
  CheckText('C8 the engine''s reason stays', VPlan.Changes[3].Blocked, 'used');
  CheckText('C9 the kept field is not in the file', VPlan.SelectFileText, '# plan 3f0c9a51b7e2d684'#13#10'1'#13#10'2'#13#10);
  VPlan.SetAll(False);
  Check('C10 uncheck all', VPlan.CheckedCount = 0);
  ParsePlan(PLAN_JSON, VPlan, VError);
  VPlan.KeepAllBut(['QRYALEGACY']);
  CheckText('C11 a removed field stays possible', VPlan.Changes[2].Blocked, '');
  ParsePlan(PLAN_JSON, VOther, VError);
  Check('C12 one plan, one fingerprint', (VOther.Fingerprint <> '') and (VPlan.Fingerprint = VOther.Fingerprint));
  ParsePlan(PLAN_JSON.Replace('"new":"No"', '"new":"Nr"'), VOther, VError);
  Check('C13 another change set, another fingerprint', VPlan.Fingerprint <> VOther.Fingerprint);
  Check('C14 a plan without an id', ParsePlan(READ_JSON, VPlan, VError) and (VPlan.PlanId = '') and (Length(VPlan.Changes) = 0), VError);
  CheckText('C15 no plan line without an id', VPlan.SelectFileText, '');
  Check('C16 no plan', not ParsePlan('repo write-dfm: binary', VPlan, VError) and ContainsText(VError, 'binary'), VError);
  Check('C17 an object without a change set', not ParsePlan('{"datasets":[]}', VPlan, VError) and (VError <> ''), VError);
end;

procedure TestText;
begin
  CheckText('A1 read all', ReadDfmArgs('C:\a b\u.dfm', '', '--json'), '--dfm "C:\a b\u.dfm" --direction dfm-to-repo --json');
  CheckText('A2 read one', ReadDfmArgs('u.dfm', 'qryA', SelectArg('C:\t x\s.txt')),
    '--dfm "u.dfm" --dataset qryA --direction dfm-to-repo --select "C:\t x\s.txt"');
  CheckText('A3 write', WriteDfmArgs('u.dfm', 'qryA', 'ID,QTY', '--json'),
    '--dfm "u.dfm" --dataset qryA --names "ID,QTY" --direction repo-to-dfm --json');
  CheckText('A4 log', ApplyLog('direction x'#13#10'[1] update a: b -> c'#13#10'replacing b with c'#13#10'backup f'#13#10'applied: 1 changes', MAX_LOG),
    'replacing b with c'#13#10'backup f'#13#10'applied: 1 changes');
  CheckText('A5 log, cut', ApplyLog('replacing 1'#10'replacing 2'#10'replacing 3'#10'replacing 4'#10'applied: 4 changes', MAX_LOG),
    'replacing 1'#13#10'replacing 2'#13#10'... 2 more lines'#13#10'applied: 4 changes');
  CheckText('A6 a refusal is shown', ApplyLog('[1] update a: b -> c'#10'repo write-dfm: the plan is now x', MAX_LOG), 'repo write-dfm: the plan is now x');
  CheckText('A7 nothing known: the text itself', ApplyLog('Access violation'#10, MAX_LOG), 'Access violation');
end;

{ What happens to the open form after a write run. }
procedure TestAfterWrite;
begin
  Check('R1 nothing changed on disk', ReloadStep(0, True, False, False) = frNone);
  Check('R2 not open', ReloadStep(0, False, False, True) = frNone);
  Check('R3 written, clean: reload', ReloadStep(0, True, False, True) = frReload);
  Check('R4 written, edited meanwhile: not reloaded', ReloadStep(0, True, True, True) = frDirty);
  Check('R5 a failed run that changed a file: ask', ReloadStep(1, True, False, True) = frAsk);
  Check('R6 a failed run, edited meanwhile: not reloaded', ReloadStep(1, True, True, True) = frDirty);
  Check('R7 a failed run that changed nothing', ReloadStep(1, True, True, False) = frNone);
  CheckText('N1 reloaded: nothing to say', ApplyNotice(frReload, 'u.dfm', ''), '');
  CheckText('N2 edited meanwhile', ApplyNotice(frDirty, 'u.dfm', ''), 'u.dfm was written to disk, NOT reloaded: your editor buffer is older. ' +
    'Saving it overwrites what was written; close the form without saving to get the written one.');
  CheckText('N3 the reload failed', ApplyNotice(frFailed, 'u.dfm', 'EX: no'),
    'u.dfm was written to disk, NOT reloaded (EX: no): your editor buffer is older.');
  CheckText('N4 the user kept the buffer', ApplyNotice(frAsk, 'u.dfm', ''),
    'u.dfm was changed on disk by a run that failed, NOT reloaded: your editor buffer is older.');
end;

{ ---- with the output of a real engine ---- }

procedure TestUsageIcons;
const
  KINDS: array[TFsUseKind] of string = ('dfm', 'grid', 'lookup', 'code');
var
  VSel: TFieldSelection;
  VKind: TFsUseKind;
  VI: Integer;
begin
  CheckText('icon of no use = 0 (blank)', IntToStr(UsageIcon([])), '0');
  for VKind := Low(TFsUseKind) to High(TFsUseKind) do
    CheckText('icon of kind ' + KINDS[VKind] + ' = 1 shl ord', IntToStr(UsageIcon([VKind])), IntToStr(1 shl Ord(VKind)));
  CheckText('icon of all kinds = last of the strip', IntToStr(UsageIcon([fuDfmControl, fuGridColumn, fuLookup, fuCode])),
    IntToStr(USAGE_ICON_COUNT - 1));
  VSel := TFieldSelection.Create(FirstDataset(READ_JSON));
  try
    CheckText('a fresh row has no use', IntToStr(UsageIcon(VSel[0].Used)), '0');
    for VKind := Low(TFsUseKind) to High(TFsUseKind) do
    begin
      VSel.SetUsage('qty', [VKind]);
      VI := RowOf(VSel, 'QTY');
      CheckText('QTY with kind ' + KINDS[VKind] + ' gets its icon', IntToStr(UsageIcon(VSel[VI].Used)),
        IntToStr(1 shl Ord(VKind)));
      Writeln('ICON QTY ', KINDS[VKind], ' ', UsageIcon(VSel[VI].Used));
    end;
    VSel.SetUsage('QTY', [fuDfmControl, fuCode]);
    CheckText('two kinds add up', IntToStr(UsageIcon(VSel[RowOf(VSel, 'QTY')].Used)), '9');
    CheckText('other rows are not touched', IntToStr(UsageIcon(VSel[RowOf(VSel, 'ID')].Used)), '0');
    VSel.SetUsage('NOSUCH', [fuCode]);
    CheckText('an unknown field is ignored', IntToStr(UsageIcon(VSel[RowOf(VSel, 'ID')].Used)), '0');
    CheckText('usage text of two kinds', UsageText([fuDfmControl, fuCode]), 'edit control, code');
    CheckText('usage text of none', UsageText([]), '');
  finally
    VSel.Free;
  end;
end;

procedure Clicks(pSel: TFieldSelection; pFrom: Integer);
var
  VI: Integer;
  VMsg: string;
begin
  for VI := pFrom to ParamCount do
  begin
    Click(pSel, Copy(ParamStr(VI), 2), ParamStr(VI)[1] = '+', VMsg);
    if VMsg <> '' then
      Writeln('message: ', VMsg);
  end;
end;

procedure RunOnRead(pNames: Boolean);
const
  FIRST_CLICK = 3;
var
  VSel: TFieldSelection;
begin
  VSel := TFieldSelection.Create(FirstDataset(TFile.ReadAllText(ParamStr(2))));
  try
    if pNames then
    begin
      Clicks(VSel, FIRST_CLICK);
      Writeln('names: ', VSel.Names);
      Writeln('removed: ', string.Join(',', VSel.RemovedComponents));
    end
    else
      Writeln('rows: ', RowsText(VSel));
    Writeln('refusal: ', VSel.Refusal);
  finally
    VSel.Free;
  end;
end;

procedure RunOnPlan;
const
  OUT_FILE = 3;
  FIRST_CLICK = 4;
var
  VPlan: TFsPlan;
  VError: string;
  VI, VJ: Integer;
begin
  if not ParsePlan(TFile.ReadAllText(ParamStr(2)), VPlan, VError) then
    raise EArgumentException.Create(VError);
  for VI := FIRST_CLICK to ParamCount do
    for VJ := 0 to High(VPlan.Changes) do
      if VPlan.Changes[VJ].Id = StrToInt(Copy(ParamStr(VI), 2)) then
        VPlan.Changes[VJ].Checked := ParamStr(VI)[1] = '+';
  TFile.WriteAllText(ParamStr(OUT_FILE), VPlan.SelectFileText);
  Writeln('plan: ', VPlan.PlanId, ' ', Length(VPlan.Changes), ' changes, ', VPlan.CheckedCount, ' checked');
end;

begin
  try
    if ParamStr(1) = '--rows' then
      RunOnRead(False)
    else if ParamStr(1) = '--names' then
      RunOnRead(True)
    else if ParamStr(1) = '--plan' then
      RunOnPlan
    else
    begin
      TestParse;
      TestSelection;
      TestSelectionEdges;
      TestDatasetToUse;
      TestPlan;
      TestText;
      TestAfterWrite;
      TestUsageIcons;
      Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
      if GFail > 0 then
        ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
