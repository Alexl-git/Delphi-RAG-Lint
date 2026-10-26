unit ConvRules.ConvertRerun;

{ Pure decisions behind the Convert tab's raise-and-re-run offer (Task 6, encoding): which
  refused units are asked about, what the user's answers make of the re-run, the re-run's
  job and status text, and which rows belong to one run. No UI and no engine calls --
  ConvRules.ConvertTab asks and starts the run; ConvRulesModelTests.dpr pins every rule here.
  Split out of ConvRules.ConvertRunner, which is at its size marker (as ConvertBatch was split
  out of ConvertRun, decision D10). }

interface

uses
  ConvRules.ConvertRunner;

const
  /// <summary>The status lead of a re-run's summary: file count, file names.</summary>
  RERUN_STATUS_FMT = 'Re-run after raising %d file(s) to UTF-8 with BOM: %s';

type
  /// <summary>The user's answer to the raise question for one encoding-refused row:
  /// mrYes, mrNo or mrCancel (System.UITypes); anything else counts as No.</summary>
  TRaiseAskFn = reference to function(const ARow: TConvertRow): Integer;

  /// <summary>What a run's raise questions decided: the re-run's units and their files.</summary>
  TRaisePlan = record
    /// <summary>The units to re-run, in question order.</summary>
    Units: TArray<string>;
    /// <summary>Their files to raise (RaiseFilesOf of each refusal).</summary>
    Files: TArray<string>;
  end;

/// <summary>PURE: the units a run left refused for an encoding reason.</summary>
/// <param name="ARows">The run's rows.</param>
/// <returns>The csRefused rows with HasEncodingRefusal, one per unit (the first row wins).</returns>
function EncodingRefusedRows(const ARows: TArray<TConvertRow>): TArray<TConvertRow>;

/// <summary>PURE: the job of the re-run after the user's Yes to the raise question.</summary>
/// <param name="AJob">The finished run's job.</param>
/// <param name="AUnits">The units the user said Yes for.</param>
/// <param name="AFiles">Their files to raise (RaiseFilesOf of each refusal).</param>
/// <returns>AJob with Units = AUnits and RaiseFiles = AFiles; Books, Dbs, ProjectDb, features and scope unchanged.
/// Books stay ALL the job's books: a refusal restores its unit (the earlier books' rows become csRolledBack, the later
/// books never ran), so every book must run on it again -- on the per-unit AND the batch path (test
/// batch.rerun.each.book.once). RunId is unchanged too: the tab's StartRun numbers every run (ruling I2).</returns>
function RerunJob(const AJob: TConvertJob; const AUnits, AFiles: TArray<string>): TConvertJob;

/// <summary>PURE: whether a finished run asks the raise question for its encoding refusals.</summary>
/// <param name="AJob">The finished run's job.</param>
/// <param name="ACancelled">The user cancelled the run.</param>
/// <returns>True only for an ordinary run (no RaiseFiles: a re-run NEVER asks again, Review Focus 4) of an engine with
/// afEncodingGuard that was not cancelled.</returns>
function ShouldAskRaise(const AJob: TConvertJob; ACancelled: Boolean): Boolean;

/// <summary>PURE: the re-run's status lead.</summary>
/// <param name="AJob">The finished run's job.</param>
/// <returns>Format(RERUN_STATUS_FMT) over the file NAMES of AJob.RaiseFiles joined with ', '; '' for an ordinary run.</returns>
function RerunStatusText(const AJob: TConvertJob): string;

/// <summary>PURE: the rows of ONE run out of the Convert tab's accumulated rows -- a re-run
/// appends to the first run's rows, but its tally, stops, not-reached units and raise
/// question are its own (Task 6, ruling I2).</summary>
/// <param name="AAll">Every row the tab holds (FRunRows).</param>
/// <param name="AFrom">The run's first index (FRunRowsFrom).</param>
/// <returns>AAll[AFrom..High(AAll)]; all of AAll when AFrom &lt; 0; [] when AFrom is past the end.</returns>
function RunRowsOf(const AAll: TArray<TConvertRow>; AFrom: Integer): TArray<TConvertRow>;

/// <summary>PURE: the Yes / No / Cancel loop over a run's encoding refusals (the decision
/// behind TConvertTab.AskRaiseAndRerun; the tab supplies the dialog).</summary>
/// <param name="ARows">The run's own rows (RunRowsOf).</param>
/// <param name="AAsk">Asked once per EncodingRefusedRows row, in order, until Cancel; nil =
/// nobody to ask, an empty plan.</param>
/// <returns>Per Yes: the unit and RaiseFilesOf([its refusal's file], unit) -- a Yes whose file
/// is not the unit's own .pas / .dfm adds nothing. No skips the row; Cancel stops asking and
/// keeps the Yes answers before it. Empty Units = no re-run.</returns>
function RaiseRerunPlan(const ARows: TArray<TConvertRow>; const AAsk: TRaiseAskFn): TRaisePlan;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Math
  , System.UITypes  // mrYes / mrCancel: RaiseRerunPlan's answers
  , ConvRules.ConvertRun
  ;

function EncodingRefusedRows(const ARows: TArray<TConvertRow>): TArray<TConvertRow>;
var
  LSeen: TArray<string>;
begin
  Result:= nil;
  LSeen := nil;
  for var LRow: TConvertRow in ARows do
    if (LRow.Status = csRefused) and HasEncodingRefusal(LRow.Apply) and not MatchText(LRow.UnitPas, LSeen) then
    begin
      LSeen := LSeen + [LRow.UnitPas];
      Result:= Result + [LRow];
    end;
end;

function RerunJob(const AJob: TConvertJob; const AUnits, AFiles: TArray<string>): TConvertJob;
begin
  Result:= AJob;
  Result.Units     := Copy(AUnits);
  Result.RaiseFiles:= Copy(AFiles);
end;

function ShouldAskRaise(const AJob: TConvertJob; ACancelled: Boolean): Boolean;
begin
  Result:= (Length(AJob.RaiseFiles) = 0) and (afEncodingGuard in AJob.ApplyFeatures) and not ACancelled;
end;

function RerunStatusText(const AJob: TConvertJob): string;
var
  LNames: TArray<string>;
begin
  if Length(AJob.RaiseFiles) = 0 then
    Exit('');
  LNames:= nil;
  for var LFile: string in AJob.RaiseFiles do
    LNames:= LNames + [ExtractFileName(LFile)];
  Result:= Format(RERUN_STATUS_FMT, [Length(LNames), string.Join(', ', LNames)]);
end;

function RunRowsOf(const AAll: TArray<TConvertRow>; AFrom: Integer): TArray<TConvertRow>;
begin
  Result:= Copy(AAll, Max(AFrom, 0), MaxInt);
end;

function RaiseRerunPlan(const ARows: TArray<TConvertRow>; const AAsk: TRaiseAskFn): TRaisePlan;
var
  LAnswer: Integer;
  LOwn   : TArray<string>;
begin
  Result:= Default(TRaisePlan);
  if not Assigned(AAsk) then
    Exit;
  for var LRow: TConvertRow in EncodingRefusedRows(ARows) do
  begin
    LAnswer:= AAsk(LRow);
    if LAnswer = mrCancel then
      Break;
    if LAnswer <> mrYes then
      Continue;
    // Only a file of the unit itself (its .pas or .dfm) can be raised by its own call.
    LOwn:= RaiseFilesOf([LRow.Apply.EncodingRefusal.FileName], LRow.UnitPas);
    if Length(LOwn) = 0 then
      Continue;
    Result.Units:= Result.Units + [LRow.UnitPas];
    Result.Files:= Result.Files + LOwn;
  end;
end;

end.
