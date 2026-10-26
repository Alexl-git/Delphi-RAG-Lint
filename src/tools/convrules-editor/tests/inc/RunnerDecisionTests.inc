{ Lane A (2026-10-26): pure runner decisions that were only reachable through the Convert
  tab -- the raise question's Yes / No / Cancel loop and the run-rows slice (ENC-e) -- and
  the batch path's per-entry exit_code reading (R1, R5). }

// An encoding-refused row of AUnit whose refusal names AFile.
function RaiseRow(const AUnit, AFile: string): TConvertRow;
begin
  Result:= Default(TConvertRow);
  Result.UnitPas:= AUnit;
  Result.Status := csRefused;
  Result.Apply.Refused:= True;
  Result.Apply.EncodingRefusal.FileName:= AFile;
end;

procedure TestRunnerDecisions;
const
  ROWS_3 = 3;
var
  All   : TArray<TConvertRow>;
  Plan  : TRaisePlan;
  Asked : string;
  Answer: string; // one char per question: y / n / c
  Ask   : TRaiseAskFn;
  Doc   : TApplyBatch;
  Entry : TApplyRow;
  N     : Integer; // questions asked so far
begin
  // --- RunRowsOf: a re-run's own rows (FRunRowsFrom) ---
  SetLength(All, ROWS_3);
  All[0].UnitPas:= 'A.pas';
  All[1].UnitPas:= 'B.pas';
  All[2].UnitPas:= 'C.pas';
  Check('runrows.from.middle', (Length(RunRowsOf(All, 1)) = 2) and (RunRowsOf(All, 1)[0].UnitPas = 'B.pas'));
  Check('runrows.from.zero.all', Length(RunRowsOf(All, 0)) = ROWS_3);
  Check('runrows.from.end.empty', Length(RunRowsOf(All, ROWS_3)) = 0);
  Check('runrows.past.end.empty', Length(RunRowsOf(All, ROWS_3 + 1)) = 0);
  Check('runrows.negative.all', Length(RunRowsOf(All, -1)) = ROWS_3);
  Check('runrows.none', Length(RunRowsOf(nil, 0)) = 0);

  // --- RaiseRerunPlan: the Yes / No / Cancel loop of AskRaiseAndRerun ---
  All:= [RaiseRow('C:\p\A.pas', 'C:\p\A.pas'), RaiseRow('C:\p\B.pas', 'C:\p\B.dfm'), RaiseRow('C:\p\C.pas', 'C:\p\C.pas')];
  Ask:= function(const ARow: TConvertRow): Integer
    begin
      Asked:= Asked + ExtractFileName(ARow.UnitPas) + ';';
      Inc(N);
      case Answer[N] of
        'y': Result:= mrYes;
        'c': Result:= mrCancel;
        else Result:= mrNo;
      end; // case
    end;
  Asked := '';
  N     := 0;
  Answer:= 'yny';
  Plan:= RaiseRerunPlan(All, Ask);
  Check('raise.plan.yes.no.yes', (string.Join(',', Plan.Units) = 'C:\p\A.pas,C:\p\C.pas') and (string.Join(',', Plan.Files) = 'C:\p\A.pas,C:\p\C.pas')
    and (Asked = 'A.pas;B.pas;C.pas;'), string.Join(',', Plan.Units) + ' asked ' + Asked);
  Asked := '';
  N     := 0;
  Answer:= 'ycy';
  Plan:= RaiseRerunPlan(All, Ask);
  Check('raise.plan.cancel.stops.keeps.earlier', (string.Join(',', Plan.Units) = 'C:\p\A.pas') and (Asked = 'A.pas;B.pas;'), string.Join(',', Plan.Units) + ' asked ' + Asked);
  Asked := '';
  N     := 0;
  Answer:= 'nyn';
  Plan:= RaiseRerunPlan(All, Ask);
  Check('raise.plan.dfm.file', (string.Join(',', Plan.Units) = 'C:\p\B.pas') and (string.Join(',', Plan.Files) = 'C:\p\B.dfm'), string.Join(',', Plan.Files));
  // A Yes whose file is not the unit's own .pas / .dfm adds nothing.
  All[0].Apply.EncodingRefusal.FileName:= 'C:\p\Other.inc';
  Asked := '';
  N     := 0;
  Answer:= 'ynn';
  Plan:= RaiseRerunPlan(All, Ask);
  Check('raise.plan.foreign.file.no.rerun', (Length(Plan.Units) = 0) and (Length(Plan.Files) = 0) and (Asked = 'A.pas;B.pas;C.pas;'), Asked);
  // Only encoding-refused rows are asked about; nil asker = no plan.
  All[1].Status:= csConverted;
  Asked := '';
  N     := 0;
  Answer:= 'yy';
  Plan:= RaiseRerunPlan(All, Ask);
  Check('raise.plan.only.refused.rows', (string.Join(',', Plan.Units) = 'C:\p\C.pas') and (Asked = 'A.pas;C.pas;'), Asked);
  Check('raise.plan.nil.asker', Length(RaiseRerunPlan(All, nil).Units) = 0);

  // --- R5: apply/1 exit_code, per entry ---
  Check('apply.exit.code.read', ParseApplyJson('{"schema":"apply/1","ok":false,"refused":true,"reason":"x","exit_code":1}', APPLY_FEATURES_ALL).ExitCode = 1);
  Check('apply.exit.code.absent', ParseApplyJson('{"schema":"apply/1","ok":true}', APPLY_FEATURES_ALL).ExitCode = APPLY_EXIT_ABSENT);
  Check('apply.exit.code.string.absent', ParseApplyJson('{"schema":"apply/1","ok":true,"exit_code":"0"}', APPLY_FEATURES_ALL).ExitCode = APPLY_EXIT_ABSENT);
  Check('apply.exit.code.unparsed.absent', ParseApplyJson('engine died', APPLY_FEATURES_ALL).ExitCode = APPLY_EXIT_ABSENT);
  Doc:= ParseApplyBatchJson('{"schema":"apply-batch/1","units_count":2,"ok":false,"exit_code":1,"ok_count":1,"refused_count":1,"failed_count":0,"units":['
    + '{"schema":"apply/1","unit":"a","ok":true,"exit_code":0},{"schema":"apply/1","unit":"b","ok":false,"refused":true,"reason":"r","exit_code":1}]}', APPLY_FEATURES_ALL);
  Check('batch.entry.exit.agrees', BatchEntryExitBroken(Doc) = '', BatchEntryExitBroken(Doc));
  Doc.Units[0].ExitCode:= 2;
  Check('batch.entry.exit.contradicts.ok', BatchEntryExitBroken(Doc) = 'units[0] exit_code 2 contradicts ok=true', BatchEntryExitBroken(Doc));
  Doc.Units[0].ExitCode:= 0;
  Doc.Units[1].ExitCode:= 0;
  Check('batch.entry.exit.contradicts.not.ok', BatchEntryExitBroken(Doc) = 'units[1] exit_code 0 contradicts ok=false', BatchEntryExitBroken(Doc));
  Doc.Units[1].ExitCode:= ENGINE_EXIT_CONFIG;
  Check('batch.entry.exit.exceeds.batch', BatchEntryExitBroken(Doc) = 'units[1] exit_code 6 exceeds the batch exit_code 1', BatchEntryExitBroken(Doc));
  Doc.Units[0].ExitCode:= APPLY_EXIT_ABSENT;
  Doc.Units[1].ExitCode:= APPLY_EXIT_ABSENT;
  Check('batch.entry.exit.absent.trusted', BatchEntryExitBroken(Doc) = '');

  // --- R1: may an entry of an exit-6 chunk have written its unit? ---
  Entry:= Default(TApplyRow);
  Entry.ExitCode:= APPLY_EXIT_ABSENT;
  Entry.Refused := True;
  Entry.ExitCode:= ENGINE_EXIT_CONFIG;
  Check('config.stop.refused.untouched', not ConfigStopMayHaveWritten(Entry));
  Entry.Refused := False;
  Entry.ExitCode:= APPLY_EXIT_ABSENT;
  Check('config.stop.failed.no.code.untouched', not ConfigStopMayHaveWritten(Entry));
  Entry.ExitCode:= 2;
  Check('config.stop.exit2.may.have.written', ConfigStopMayHaveWritten(Entry));
  Entry.ExitCode:= 0;
  Entry.Ok      := True;
  Check('config.stop.ok.wrote', ConfigStopMayHaveWritten(Entry));
end;
