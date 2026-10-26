unit DragLint.Plugin.CycleFix;

{ The pure half of the IDE's `cycles --fix` surface (E18 Task 15): the engine
  command lines, the per-SCC rows of the Uses & Deps tab's "Circular uses"
  section, and the one-line outcome the status line shows.

  PURE ON PURPOSE -- System.JSON and System.SysUtils only, no ToolsAPI, no VCL --
  so tests\autotest\run_plugin_cyclefix_args.ps1 compiles it into a console
  harness and asserts the exact strings. The frame and the menu item call these
  functions; neither builds a cycles command line of its own.

  THE ENGINE OWNS THE EDIT. Nothing here writes a file. A menu click only ever
  reaches the dry run; --apply is built only for the tab's Apply button, which
  is the reviewed surface (one SCC, ticked by the user). }

interface

const
  /// <summary>Time limit, in ms, for every IDE-started `cycles --fix` run (the
  /// tab's Dry run and Apply, and the menu's dry run): 0 = NONE.</summary>
  /// <remarks>Owner ruling 2026-10-26 (lane X-BT): an IDE run has no time
  /// limit -- the IDE shows progress and has Cancel, and a slow machine must not
  /// abort a result the user waits for. (It was 130 minutes, above the engine's
  /// own 120-minute worst case; a plugin kill in the middle of an --apply
  /// bypassed the engine's rollback.) ProcRun reads &lt;= 0 as "no deadline".
  /// The engine runs these without --build-timeout, so its builds are unbounded
  /// too. Stopping a run is Cancel's job: see CYCLE_FIX_CANCEL_GRACE_MS.
  /// tests\autotest\run_cyclefix_timeouts.ps1 pins this value. The other Uses
  /// &amp; Deps sections keep their own 180 s limit.</remarks>
  CYCLE_FIX_TIMEOUT_MS = 0;

  /// <summary>How long, in ms, a cancelled `cycles --fix` job gives the engine
  /// to stand down before its process tree is killed: 90 seconds.</summary>
  /// <remarks>Cancel (the status strip's button, JobQueue.CancelRunning) never
  /// hard-kills the engine mid-apply: it sends the maintenance control
  /// channel's `shutdown` (ProcRun's AStandDownGraceMs), the engine kills the
  /// build it waits on, rolls every written file back and exits 1 with
  /// "cancelled -- rolled back". Only an engine still running after this grace
  /// is killed. ABOVE the engine's own CChildStandDownMs (60 s, what a --part
  /// all parent gives its child to roll back), so a forwarded stand-down
  /// finishes first; run_cyclefix_timeouts.ps1 pins the inequality.</remarks>
  CYCLE_FIX_CANCEL_GRACE_MS = 90 * 1000;

type
  /// <summary>One strongly connected component of the project's uses graph, as
  /// listed by `cycles --format json --causes`.</summary>
  /// <remarks>A record held in a list parallel to the tab's checklist, so a
  /// row's identity never depends on parsing its caption back out.</remarks>
  TCycleRow = record
    /// <summary>1-based position in the engine's list; what --cycle is given.</summary>
    Cycle  : Integer;
    /// <summary>The SCC's units in engine order, joined with ' &lt;-&gt; '.</summary>
    Units  : string ;
    /// <summary>`fix.available`: the engine has a mechanical plan for this SCC.</summary>
    Fixable: Boolean;
    /// <summary>`fix.part` ('a' or 'b'); empty when the document has none.</summary>
    Part   : string ;
    /// <summary>`fix.reason`: why no mechanical plan exists; empty when Fixable.</summary>
    Reason : string ;
  end;

  /// <summary>What one `cycles --fix ... --format json` run reported, read out
  /// of its `cycle-fix/1` document.</summary>
  TCycleFixOutcome = record
    /// <summary>False when no cycle-fix/1 document could be parsed. NOT the
    /// same as "nothing was written" -- the caller must say so.</summary>
    Readable    : Boolean       ;
    /// <summary>'dry-run' or 'apply'.</summary>
    Mode        : string        ;
    /// <summary>The document's top-level `ok`.</summary>
    Ok          : Boolean       ;
    /// <summary>Each cycle's `verdict`, joined with ', ' ('mechanical', 'refused').</summary>
    Verdict     : string        ;
    /// <summary>Top-level `baseline.status` ('ok', 'error', 'skipped').</summary>
    Baseline    : string        ;
    /// <summary>`baseline.errors[0]`, the first dcc line; empty when none.</summary>
    BaselineErr : string        ;
    /// <summary>Every refusal, top level then per cycle, rendered as
    /// `kind -- file:line` (`:line` only when the engine gave one). A
    /// dirty-baseline refusal is rendered `dirty-baseline -- first dcc line`.</summary>
    Refusals    : TArray<string>;
    /// <summary>Total of every cycle's `repairs[]`.</summary>
    Repairs     : Integer       ;
    /// <summary>True when every cycle in the document has `verified` = true
    /// (and there is at least one).</summary>
    Verified    : Boolean       ;
    /// <summary>The first non-empty `verify_reason`.</summary>
    VerifyReason: string        ;
    /// <summary>Any cycle reported `rolled_back` = true.</summary>
    RolledBack  : Boolean       ;
    /// <summary>Every cycle's `written[]`: the files the engine changed or
    /// created on disk. Empty on a dry run.</summary>
    Written     : TArray<string>;
  end;

/// <summary>The menu item's command line: a text dry run with no --cycle, so the
/// engine picks the SCC itself (cycle 1 on circular-demo).</summary>
/// <param name="AProj">The active .dproj, unquoted.</param>
/// <param name="ADb">The project index, unquoted.</param>
/// <param name="APlatform">The IDE's active platform (e.g. 'Win32'); sent lower-case as
/// `--platform p`, so the engine's build gate and platform library match the IDE;
/// '' omits the flag (the engine's win64 default).</param>
/// <returns>`cycles --fix --project "P" --db "D" [--platform p] --format text` -- never --apply.</returns>
function CycleFixMenuArgs(const AProj, ADb, APlatform: string): string;

/// <summary>The tab's list query: every SCC with its causes and fix object.</summary>
/// <param name="AProj">The active .dproj, unquoted.</param>
/// <param name="ADb">The project index, unquoted.</param>
/// <param name="APlatform">As CycleFixMenuArgs.</param>
/// <returns>`cycles --project "P" --db "D" [--platform p] --format json --causes`.</returns>
function CycleListArgs(const AProj, ADb, APlatform: string): string;

/// <summary>The tab's Dry run button for one SCC.</summary>
/// <param name="AProj">The active .dproj, unquoted.</param>
/// <param name="ADb">The project index, unquoted.</param>
/// <param name="APlatform">As CycleFixMenuArgs.</param>
/// <param name="ACycle">The row's 1-based TCycleRow.Cycle.</param>
/// <returns>`cycles --fix --project "P" --db "D" [--platform p] --cycle n --format json`.</returns>
function CycleFixDryRunArgs(const AProj, ADb, APlatform: string; ACycle: Integer): string;

/// <summary>The tab's Apply button: CycleFixDryRunArgs plus ` --apply`.</summary>
/// <param name="AProj">The active .dproj, unquoted.</param>
/// <param name="ADb">The project index, unquoted.</param>
/// <param name="APlatform">As CycleFixMenuArgs.</param>
/// <param name="ACycle">The row's 1-based TCycleRow.Cycle.</param>
/// <returns>The dry-run command line with ` --apply` appended.</returns>
function CycleFixApplyArgs(const AProj, ADb, APlatform: string; ACycle: Integer): string;

/// <summary>Reads the SCC rows out of `cycles --format json --causes` output.</summary>
/// <param name="AText">Raw engine output; a banner before the JSON array and
/// notes after it are tolerated.</param>
/// <returns>One row per SCC, in engine order; empty when no array was found.</returns>
/// <remarks>Never raises: a malformed document yields no rows.</remarks>
function ParseCycleRows(const AText: string): TArray<TCycleRow>;

/// <summary>A row's checklist caption: the units, then the fix state.</summary>
/// <param name="ARow">The row to caption.</param>
/// <returns>`n. a &lt;-&gt; b   -- fixable (part a)` or `... -- not fixable: reason`.</returns>
function CycleRowCaption(const ARow: TCycleRow): string;

/// <summary>The question the tab's Apply button asks before it runs
/// `cycles --fix --cycle n --apply` -- the same Yes/No (default No) gate the
/// Structure tree puts in front of its apply.</summary>
/// <param name="ARow">The ticked row.</param>
/// <returns>Several lines: the group number and units, what --apply does to
/// the project (writes with .BCK backups, builds, re-indexes, rolls back a failed
/// build) and that Dry run shows the plan first.</returns>
function CycleFixApplyConfirmText(const ARow: TCycleRow): string;

/// <summary>Reads a `cycle-fix/1` document out of raw engine output.</summary>
/// <param name="AText">Raw engine output; a banner before the JSON object is
/// tolerated.</param>
/// <returns>The outcome; Readable=False when no cycle-fix/1 object was found.</returns>
/// <remarks>Never raises.</remarks>
function ParseCycleFixOutcome(const AText: string): TCycleFixOutcome;

/// <summary>One status line saying what a `cycles --fix` run did: verdict,
/// refusals, baseline status, repairs, verified, files written.</summary>
/// <param name="AOutcome">From ParseCycleFixOutcome.</param>
/// <returns>A single line. A refused baseline reads
/// `refused: dirty-baseline -- first dcc line`.</returns>
function DescribeCycleFixOutcome(const AOutcome: TCycleFixOutcome): string;

/// <summary>Whether the run changed files on disk that the IDE must reload.</summary>
/// <param name="AOutcome">From ParseCycleFixOutcome.</param>
/// <returns>True when Written is non-empty and nothing was rolled back.</returns>
function CycleFixWroteFiles(const AOutcome: TCycleFixOutcome): Boolean;

implementation

uses
  System.SysUtils
  , System.JSON
  ;

const
  UNIT_SEP      = ' <-> ';
  FIX_SCHEMA    = 'cycle-fix/1';
  DIRTY_KIND    = 'dirty-baseline';
  MODE_APPLY    = 'apply';

{ ---- command lines ---------------------------------------------------------- }

{ ` --platform p` (lower-case) or '' -- the engine defaults to win64 for its msbuild
  gate and its platform library, so a Win32 IDE must say so (E18 final review F3). }
function PlatformArg(const APlatform: string): string;
begin
  Result:= if APlatform = '' then '' else ' --platform ' + LowerCase(APlatform);
end;

function CycleFixMenuArgs(const AProj, ADb, APlatform: string): string;
begin
  Result:= Format('cycles --fix --project "%s" --db "%s"%s --format text', [AProj, ADb, PlatformArg(APlatform)]);
end;

function CycleListArgs(const AProj, ADb, APlatform: string): string;
begin
  Result:= Format('cycles --project "%s" --db "%s"%s --format json --causes', [AProj, ADb, PlatformArg(APlatform)]);
end;

function CycleFixDryRunArgs(const AProj, ADb, APlatform: string; ACycle: Integer): string;
begin
  Result:= Format('cycles --fix --project "%s" --db "%s"%s --cycle %d --format json',
                  [AProj, ADb, PlatformArg(APlatform), ACycle]);
end;

function CycleFixApplyArgs(const AProj, ADb, APlatform: string; ACycle: Integer): string;
begin
  Result:= CycleFixDryRunArgs(AProj, ADb, APlatform, ACycle) + ' --apply';
end;

function CycleFixApplyConfirmText(const ARow: TCycleRow): string;
begin
  Result:= Format('Apply the mechanical fix to circular group %d?', [ARow.Cycle]) + sLineBreak + sLineBreak
         + ARow.Units + sLineBreak + sLineBreak
         + 'drag-lint writes the edited and new units into the project (with .BCK backups), '
         + 'builds it and re-indexes it; a failed build is rolled back. '
         + 'Use Dry run first to see the plan.';
end;

{ ---- JSON plumbing ---------------------------------------------------------- }

{ The engine prints "(loaded defaults from ...)" before the document and notes
  after it, and ProcRun merges stderr into the same pipe, so the document is
  parsed from the first occurrence of its opening marker to the LAST matching
  closer -- ParseJSONValue returns nil when text follows the value, which is
  exactly where those notes land. nil on any failure. }
function ParseFrom(const AText, AStart: string): TJSONValue;
var
  P, Q  : Integer;
  Closer: string ;
begin
  Result:= nil;
  P:= Pos(AStart, AText);
  if P <= 0 then Exit;
  Closer:= if AStart[1] = '[' then ']' else '}';
  Q:= LastDelimiter(Closer, AText);
  if Q < P then Exit;
  try
    Result:= TJSONObject.ParseJSONValue(Copy(AText, P, Q - P + 1));
  except
    on EJSONException do Result:= nil;
  end;
end;

function StrArr(AObj: TJSONObject; const AName: string): TArray<string>;
var
  Arr: TJSONArray;
  I  : Integer   ;
begin
  SetLength(Result, 0);
  if (AObj = nil) or not AObj.TryGetValue<TJSONArray>(AName, Arr) then Exit;
  SetLength(Result, Arr.Count);
  for I:= 0 to Arr.Count - 1 do Result[I]:= Arr.Items[I].Value;
end;

{ msbuild appends " [<the .dproj>]" to every dcc line; the status line has room
  for the error, not for the project path the user already knows. }
function StripProjectSuffix(const ALine: string): string;
var
  P: Integer;
begin
  Result:= ALine;
  if not Result.EndsWith(']') then Exit;
  P:= Result.LastIndexOf(' [');
  if P > 0 then Result:= Result.Substring(0, P);
end;

{ `kind -- file:line`; a dirty baseline names the first dcc line instead of the
  .dproj, because the .dproj is not what the user has to fix. }
function RefusalText(ARef: TJSONObject; const AFirstDcc: string): string;
var
  Kind, FileName: string;
  Line          : Integer;
begin
  Kind:= ARef.GetValue<string>('kind', '');
  if SameText(Kind, DIRTY_KIND) and (AFirstDcc <> '') then Exit(Kind + ' -- ' + AFirstDcc);
  FileName:= ExtractFileName(ARef.GetValue<string>('file', ''));
  Line    := ARef.GetValue<Integer>('line', 0);
  Result:= Kind;
  if FileName = '' then Exit;
  Result:= Result + ' -- ' + FileName;
  if Line > 0 then Result:= Result + ':' + IntToStr(Line);
end;

procedure AddRefusals(AObj: TJSONObject; var AOutcome: TCycleFixOutcome);
var
  Arr: TJSONArray;
  I  : Integer   ;
begin
  if not AObj.TryGetValue<TJSONArray>('refusals', Arr) then Exit;
  for I:= 0 to Arr.Count - 1 do
    if Arr.Items[I] is TJSONObject then
      AOutcome.Refusals:= AOutcome.Refusals
        + [RefusalText(TJSONObject(Arr.Items[I]), AOutcome.BaselineErr)];
end;

{ ---- SCC rows --------------------------------------------------------------- }

function ParseCycleRows(const AText: string): TArray<TCycleRow>;
var
  V  : TJSONValue ;
  Arr: TJSONArray ;
  It : TJSONObject;
  Fix: TJSONObject;
  Row: TCycleRow  ;
  I  : Integer    ;
begin
  SetLength(Result, 0);
  { `[{` first: a banner or note may itself contain a bracket, a document never
    starts with anything else. `[]` is the clean project. }
  V:= ParseFrom(AText, '[{');
  if V = nil then V:= ParseFrom(AText, '[]');
  try
    if not (V is TJSONArray) then Exit;
    Arr:= TJSONArray(V);
    for I:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then Continue;
      It := TJSONObject(Arr.Items[I]);
      Row:= Default(TCycleRow);
      { POSITION, not a field: the engine numbers --cycle by list order (its own
        `fix.dry_run` line says so), and the document carries no `n` here. }
      Row.Cycle:= I + 1;
      Row.Units:= string.Join(UNIT_SEP, StrArr(It, 'units'));
      if It.TryGetValue<TJSONObject>('fix', Fix) then
      begin
        Row.Fixable:= Fix.GetValue<Boolean>('available', False);
        Row.Part   := Fix.GetValue<string> ('part'     , '');
        Row.Reason := Fix.GetValue<string> ('reason'   , '');
      end;
      Result:= Result + [Row];
    end;
  finally
    V.Free;
  end;
end; // function

function CycleRowCaption(const ARow: TCycleRow): string;
begin
  Result:= Format('%d. %s   -- ', [ARow.Cycle, ARow.Units]);
  if ARow.Fixable then
    Result:= Result + (if ARow.Part <> '' then Format('fixable (part %s)', [ARow.Part]) else 'fixable')
  else
    Result:= Result + (if ARow.Reason <> '' then 'not fixable: ' + ARow.Reason else 'not fixable');
end;

{ ---- cycle-fix/1 outcome ---------------------------------------------------- }

procedure ReadCycles(ADoc: TJSONObject; var AOutcome: TCycleFixOutcome);
var
  Arr     : TJSONArray    ;
  Rep     : TJSONArray    ;
  Cy      : TJSONObject   ;
  Verdicts: TArray<string>;
  I       : Integer       ;
begin
  SetLength(Verdicts, 0);
  if not ADoc.TryGetValue<TJSONArray>('cycles', Arr) then Exit;
  AOutcome.Verified:= Arr.Count > 0;
  for I:= 0 to Arr.Count - 1 do
  begin
    if not (Arr.Items[I] is TJSONObject) then Continue;
    Cy:= TJSONObject(Arr.Items[I]);
    if Cy.GetValue<string>('verdict', '') <> '' then
      Verdicts:= Verdicts + [Cy.GetValue<string>('verdict', '')];
    AddRefusals(Cy, AOutcome);
    if Cy.TryGetValue<TJSONArray>('repairs', Rep) then Inc(AOutcome.Repairs, Rep.Count);
    if not Cy.GetValue<Boolean>('verified', False) then AOutcome.Verified:= False;
    if AOutcome.VerifyReason = '' then AOutcome.VerifyReason:= Cy.GetValue<string>('verify_reason', '');
    if Cy.GetValue<Boolean>('rolled_back', False) then AOutcome.RolledBack:= True;
    AOutcome.Written:= AOutcome.Written + StrArr(Cy, 'written');
  end;
  AOutcome.Verdict:= string.Join(', ', Verdicts);
end; // procedure

function ParseCycleFixOutcome(const AText: string): TCycleFixOutcome;
var
  V   : TJSONValue    ;
  Doc : TJSONObject   ;
  Base: TJSONObject   ;
  Errs: TArray<string>;
begin
  Result:= Default(TCycleFixOutcome);
  V:= ParseFrom(AText, '{');
  try
    if not (V is TJSONObject) then Exit;
    Doc:= TJSONObject(V);
    { Another verb's document is not an outcome of this one -- reading its
      `applied` as ours is how a tab reports a write that never happened. }
    if Doc.GetValue<string>('schema', '') <> FIX_SCHEMA then Exit;
    Result.Readable:= True;
    Result.Mode    := Doc.GetValue<string> ('mode', '');
    Result.Ok      := Doc.GetValue<Boolean>('ok'  , False);
    if Doc.TryGetValue<TJSONObject>('baseline', Base) then
    begin
      Result.Baseline:= Base.GetValue<string>('status', '');
      Errs:= StrArr(Base, 'errors');
      if Length(Errs) > 0 then Result.BaselineErr:= StripProjectSuffix(Errs[0]);
    end;
    AddRefusals(Doc, Result);
    ReadCycles(Doc, Result);
  finally
    V.Free;
  end;
end; // function

function CycleFixWroteFiles(const AOutcome: TCycleFixOutcome): Boolean;
begin
  Result:= (Length(AOutcome.Written) > 0) and not AOutcome.RolledBack;
end;

{ Say what HAPPENED, in the order the user decides on it: the verdict, why it
  was refused, whether the project built before any edit, what the compiler
  repairs did, and -- on an apply only -- whether the result verified and what
  is now on disk. A dry run that succeeded says it wrote nothing, so a reader
  cannot take "verdict mechanical" for "done". }
function DescribeCycleFixOutcome(const AOutcome: TCycleFixOutcome): string;
var
  Parts   : TArray<string>;
  R       : string        ;
  IsApply : Boolean       ;
  HasCycle: Boolean       ;
begin
  if not AOutcome.Readable then
    Exit('cycles --fix: no readable cycle-fix/1 document came back -- files may or may not have been written. '
       + 'Check them, or run the menu item to see the raw output.');
  IsApply := SameText(AOutcome.Mode, MODE_APPLY);
  HasCycle:= AOutcome.Verdict <> '';
  SetLength(Parts, 0);
  if HasCycle then Parts:= Parts + ['verdict ' + AOutcome.Verdict];
  for R in AOutcome.Refusals do Parts:= Parts + ['refused: ' + R];
  if AOutcome.Baseline <> '' then Parts:= Parts + ['baseline ' + AOutcome.Baseline];
  if HasCycle then Parts:= Parts + [Format('%d repair(s)', [AOutcome.Repairs])];
  if IsApply then
  begin
    if HasCycle then
      if AOutcome.Verified then Parts:= Parts + ['verified']
      else if AOutcome.VerifyReason <> '' then Parts:= Parts + ['NOT verified: ' + AOutcome.VerifyReason]
      else Parts:= Parts + ['NOT verified'];
    if AOutcome.RolledBack then Parts:= Parts + ['rolled back -- nothing written']
    else Parts:= Parts + [Format('%d file(s) written', [Length(AOutcome.Written)])];
  end
  else if AOutcome.Ok then
    Parts:= Parts + ['nothing written (dry run) -- press Apply to write and verify'];
  if Length(Parts) = 0 then Parts:= ['nothing reported'];
  Result:= Format('cycles --fix (%s): %s.',
                  [if IsApply then MODE_APPLY else 'dry run', string.Join('; ', Parts)]);
end; // function

end.
