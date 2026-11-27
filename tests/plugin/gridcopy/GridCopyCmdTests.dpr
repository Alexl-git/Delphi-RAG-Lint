program GridCopyCmdTests;

{ Console test runner (no DUnitX) of the pure part of DragLint.Plugin.Cmd.GridCopy (drag-lint 1.56, lane GCP-P): the
  command lines of `repo copy-grid`, the reading of its --list / --json output, the picks, the --select file. One
  PASS/FAIL line per case, a summary line, exit code 1 on any failure.

  GridCopyCmdTests                                  the unit cases
  GridCopyCmdTests --list FILE                      views and events of a `--list --from V --json` output
  GridCopyCmdTests --plan FILE OUT [+ID|-ID]...     writes the --select file of a dry run --json output
  (the last two let run_v156_GCPP.ps1 use what a real engine printed for the fixture form) }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  DRagLint.FieldRepo.Kinds in '..\..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.DfmReadSelection in '..\..\..\src\sql\DRagLint.FieldRepo.DfmReadSelection.pas',
  DragLint.Plugin.FieldSelectModel in '..\..\..\src\delphi-plugin\DragLint.Plugin.FieldSelectModel.pas',
  DragLint.Plugin.Cmd152 in '..\..\..\src\delphi-plugin\DragLint.Plugin.Cmd152.pas',
  DragLint.Plugin.Cmd.GridCopy in '..\..\..\src\delphi-plugin\DragLint.Plugin.Cmd.GridCopy.pas';

const
  LIST_JSON = '{"views":[{"name":"tvMain","class":"TcxGridDBTableView","item_class":"TcxGridDBColumn","columns":3},' +
    '{"name":"bvMain","class":"TcxGridDBBandedTableView","item_class":"TcxGridDBBandedColumn","columns":1},' +
    '{"name":"cvMain","class":"TcxGridDBCardView","item_class":"TcxGridDBCardViewRow","columns":0}],' +
    '"events":[{"component":"tvMain","class":"TcxGridDBTableView","column":false,"event":"OnCustomDrawCell","handler":"tvMainCustomDrawCell"},' +
    '{"component":"tvMainNAME","class":"TcxGridDBColumn","column":true,"event":"OnGetDisplayText","handler":"tvMainNAMEGetDisplayText"}]}';
  PLAN_JSON = '{"plan":"ABCDEF0123456789","file":"uCopy.dfm","source":"tvMain","source_class":"TcxGridDBTableView","target":"bvMain",' +
    '"target_class":"TcxGridDBBandedTableView","event":"","count":3,"blocked":1,"unchecked":1,"changes":[' +
    '{"id":1,"op":"update","target":"uCopy.dfm bvMain","prop":"OnCustomDrawCell","old":"","new":"tvMainCustomDrawCell","checked":true,"blocked":"","note":""},' +
    '{"id":2,"op":"insert","target":"uCopy.dfm bvMainCODE","prop":"","old":"","new":"TcxGridDBBandedColumn","checked":true,"blocked":"","note":""},' +
    '{"id":3,"op":"update","target":"uCopy.dfm bvMain","prop":"OnX","old":"a","new":"b","checked":false,"blocked":"","note":"the target has another handler"},' +
    '{"id":4,"op":"update","target":"uCopy.dfm bvMain","prop":"OnY","old":"","new":"c","checked":true,"blocked":"no such event","note":""}],' +
    '"remarks":["a remark"],"mode":"dry-run","applied":0,"written":[],"backups":[]}';

var
  GPass, GFail: Integer;

procedure Check(const pName: string; pOk: Boolean; const pDetail: string = '');
begin
  if pOk then
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

procedure TestList;
var
  VViews: TArray<TGcpView>;
  VEvents: TArray<TGcpEvent>;
  VError: string;
begin
  Check('L1 list: views and events are read', ParseGridCopyList('noise' + sLineBreak + LIST_JSON, VViews, VEvents, VError) and (VError = '')
    and (Length(VViews) = 3) and (Length(VEvents) = 2), VError);
  Check('L2 list: a view keeps name, class, column count', (VViews[1].Name = 'bvMain') and (VViews[1].ViewClass = 'TcxGridDBBandedTableView')
    and (VViews[0].Columns = 3));
  Check('L3 list: an event keeps component, event, handler, column flag', (VEvents[1].Component = 'tvMainNAME')
    and (VEvents[1].Event = 'OnGetDisplayText') and (VEvents[1].Handler = 'tvMainNAMEGetDisplayText') and VEvents[1].IsColumn
    and not VEvents[0].IsColumn);
  Check('L4 list: output without a views list is an error that quotes the output',
    not ParseGridCopyList('exit 1: no such file', VViews, VEvents, VError) and (Pos('no such file', VError) > 0) and (VViews = nil));
end;

procedure TestArgs;
var
  VRequest: TGcpRequest;
begin
  Check('A1 list args', GridCopyListArgs('C:\f\u.dfm', '') = '--dfm "C:\f\u.dfm" --list --json');
  Check('A2 list args with a view', GridCopyListArgs('C:\f\u.dfm', 'tvMain') = '--dfm "C:\f\u.dfm" --list --from tvMain --json');
  VRequest := Default(TGcpRequest);
  VRequest.Dfm := 'C:\f\u.dfm';
  VRequest.Source := 'tvMain';
  VRequest.Target := 'bvMain';
  Check('A3 everything: dry run', GridCopyArgs(VRequest, grPlan, '') = '--dfm "C:\f\u.dfm" --from tvMain --to bvMain --dry-run --json');
  Check('A4 everything: write run is the select file only',
    GridCopyArgs(VRequest, grApply, 'C:\t\s.txt') = '--dfm "C:\f\u.dfm" --from tvMain --to bvMain --select "C:\t\s.txt"');
  VRequest.Event := 'OnGetDisplayText';
  VRequest.SourceColumn := 'tvMainNAME';
  Check('A5 one column event names the source column',
    GridCopyArgs(VRequest, grPlan, '') = '--dfm "C:\f\u.dfm" --from tvMain --to bvMain --event OnGetDisplayText --from-column tvMainNAME --dry-run --json');
  VRequest.SourceColumn := '';
  Check('A6 one view event has no --from-column', Pos('--from-column', GridCopyArgs(VRequest, grApply, 'x')) = 0);
  VRequest.Event := '';
  VRequest.SourceColumn := 'tvMainNAME';
  Check('A7 a column without an event is not sent (the verb refuses it)', Pos('--from-column', GridCopyArgs(VRequest, grPlan, '')) = 0);
end;

procedure TestPlan;
var
  VPlan: TFsPlan;
  VError: string;
begin
  Check('P1 plan: id, changes, remark', ParseGridCopyPlan(PLAN_JSON, VPlan, VError) and (VPlan.PlanId = 'ABCDEF0123456789')
    and (Length(VPlan.Changes) = 4) and (Length(VPlan.Warnings) = 1) and (VPlan.Warnings[0] = 'a remark'), VError);
  Check('P2 plan: a change keeps op, target, prop, old, new',
    (VPlan.Changes[0].Op = 'update') and (VPlan.Changes[0].Target = 'uCopy.dfm bvMain') and (VPlan.Changes[0].Prop = 'OnCustomDrawCell')
    and (VPlan.Changes[0].NewText = 'tvMainCustomDrawCell') and (VPlan.Changes[2].OldText = 'a'));
  Check('P3 plan: checked as the engine says; a blocked change is never checked',
    VPlan.Changes[0].Checked and VPlan.Changes[1].Checked and not VPlan.Changes[2].Checked and not VPlan.Changes[3].Checked
    and (VPlan.Changes[3].Blocked = 'no such event') and (VPlan.CheckedCount = 2));
  Check('P4 plan: the select file is the plan line and the checked ids',
    VPlan.SelectFileText = '# plan ABCDEF0123456789' + sLineBreak + '1' + sLineBreak + '2' + sLineBreak);
  VPlan.Changes[2].Checked := True;
  Check('P5 plan: an unchecked change the user checks goes in', Pos(sLineBreak + '3' + sLineBreak, VPlan.SelectFileText) > 0);
  Check('P6 plan: a list output is no plan', not ParseGridCopyPlan(LIST_JSON, VPlan, VError) and (VError <> ''));
  Check('P7 plan: an empty plan is a plan', ParseGridCopyPlan('{"plan":"0000000000000000","changes":[]}', VPlan, VError)
    and (Length(VPlan.Changes) = 0) and (VPlan.SelectFileText = ''));
end;

procedure TestPicks;
var
  VViews: TArray<TGcpView>;
  VEvents: TArray<TGcpEvent>;
  VError: string;
  VIndexes: TArray<Integer>;
  VPicks: TArray<TFsDataset>;
  VRequest: TGcpRequest;
begin
  ParseGridCopyList(LIST_JSON, VViews, VEvents, VError);
  Check('K1 view to use: the one selected view', GridCopyViewToUse(VViews, ['Button1', 'bvMain'], '') = 1);
  Check('K2 view to use: two selected views = ask', GridCopyViewToUse(VViews, ['tvMain', 'bvMain'], '') = -1);
  Check('K3 view to use: the source does not count as target', GridCopyViewToUse(VViews, ['tvMain', 'bvMain'], 'tvMain') = 1);
  Check('K4 view to use: none selected = ask', GridCopyViewToUse(VViews, ['Button1'], '') = -1);
  VPicks := GridCopyViewPicks(VViews, 'tvMain', VIndexes);
  Check('K5 view picks leave the source out and map back', (Length(VPicks) = 2) and (VPicks[0].Name = 'bvMain') and (VIndexes[0] = 1)
    and (VIndexes[1] = 2) and (VPicks[0].DatasetClass = 'TcxGridDBBandedTableView'));
  VPicks := GridCopyEventPicks(VEvents);
  Check('K6 event picks: everything first, then each event', (Length(VPicks) = 3) and (VPicks[0].Name = '(everything)')
    and (VPicks[1].Name = 'OnCustomDrawCell') and (Pos('tvMainNAME', VPicks[2].DatasetClass) = 1));
  VRequest := Default(TGcpRequest);
  GridCopyApplyEventPick(VRequest, VEvents, 0);
  Check('K7 pick 0 = everything', (VRequest.Event = '') and (VRequest.SourceColumn = ''));
  GridCopyApplyEventPick(VRequest, VEvents, 1);
  Check('K8 a view event: no source column', (VRequest.Event = 'OnCustomDrawCell') and (VRequest.SourceColumn = ''));
  GridCopyApplyEventPick(VRequest, VEvents, 2);
  Check('K9 a column event: the column is the source column', (VRequest.Event = 'OnGetDisplayText') and (VRequest.SourceColumn = 'tvMainNAME'));
  GridCopyApplyEventPick(VRequest, VEvents, 99);
  Check('K10 a pick out of range = everything', (VRequest.Event = '') and (VRequest.SourceColumn = ''));
end;

procedure RunOnList;
var
  VViews: TArray<TGcpView>;
  VEvents: TArray<TGcpEvent>;
  VError: string;
  VView: TGcpView;
  VEvent: TGcpEvent;
begin
  if not ParseGridCopyList(TFile.ReadAllText(ParamStr(2)), VViews, VEvents, VError) then raise EArgumentException.Create(VError);
  Writeln('views: ', Length(VViews), ' events: ', Length(VEvents));
  for VView in VViews do Writeln('view ', VView.Name, ' ', VView.ViewClass, ' ', VView.Columns);
  for VEvent in VEvents do Writeln('event ', VEvent.Component, ' ', VEvent.Event, ' ', VEvent.Handler, ' ', VEvent.IsColumn);
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
  if not ParseGridCopyPlan(TFile.ReadAllText(ParamStr(2)), VPlan, VError) then raise EArgumentException.Create(VError);
  for VI := FIRST_CLICK to ParamCount do
    for VJ := 0 to High(VPlan.Changes) do
      if VPlan.Changes[VJ].Id = StrToInt(Copy(ParamStr(VI), 2)) then VPlan.Changes[VJ].Checked := ParamStr(VI)[1] = '+';
  TFile.WriteAllText(ParamStr(OUT_FILE), VPlan.SelectFileText);
  Writeln('plan: ', VPlan.PlanId, ' ', Length(VPlan.Changes), ' changes, ', VPlan.CheckedCount, ' checked');
end;

begin
  try
    if ParamStr(1) = '--list' then RunOnList
    else if ParamStr(1) = '--plan' then RunOnPlan
    else
    begin
      TestList;
      TestArgs;
      TestPlan;
      TestPicks;
      Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
      if GFail > 0 then ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
