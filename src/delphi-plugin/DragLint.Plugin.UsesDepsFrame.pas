unit DragLint.Plugin.UsesDepsFrame;

{ TUsesDepsFrame -- the "Uses & Deps" dock tab: reviewed, per-item FIXES for the
  two Uses & Dependencies actions that the engine can actually apply.

  WHY THIS TAB EXISTS
  -------------------
  The `drag-lint > Uses && Dependencies` submenu carried fourteen items with
  nothing on screen distinguishing a report from an action. Exactly two of them
  had an apply path in the engine that the IDE deliberately declined to expose:

    uses-fix           (--apply --remove-unused)  -- this unit
    reconcile-project  (--apply)                  -- this project

  It declined for a good reason. Both were all-or-nothing, and a button that
  rewrites a unit's uses clause, or two project files, with changes nobody has
  reviewed one by one is not a button worth shipping. `--only <unit,...>` on
  both verbs is what made a reviewed, partial apply expressible; this tab is
  the review surface for it.

  THE RULE THIS FRAME MUST NOT BREAK: the ENGINE owns the edit. This tab never
  rewrites a uses clause or a .dpr itself -- it collects ticks and passes them
  as --only. That is what keeps uses-fix's per-candidate compiler verification
  in the loop, and what stops the plugin growing a second, divergent rewriter.

  WHY NOT CALL IT "Uses". The dock already has a `Find Usages` tab. "Uses"
  beside "Find Usages" puts two similar words on adjacent tabs for unrelated
  ideas -- who REFERENCES a symbol, versus uses-clause hygiene -- which is the
  "organised by how the answer is computed" confusion this whole change exists
  to remove, reintroduced in the tab strip.

  NOTHING RUNS ON ACTIVATION. Both sections start empty behind their own
  Refresh button. `uses-fix` shadow-compiles once per candidate, so an
  automatic refresh on every tab click would make the dock feel broken; and a
  panel that starts work the user did not ask for is how the IDE acquires a
  reputation for stalling.

  SHAPE: ONE SECTION CLASS, USED TWICE. The first cut put both sections in the
  frame and the linter was right to call it a god class (21 methods, 19 fields,
  RFC 67) with a duplicated 128-token apply tail. The two sections differ in
  exactly three things -- which verb they run, how a row is captioned, and
  which files to reload afterwards -- so they are one class parameterised by
  TUsesVerb, and the frame is only a host.

  THE THIRD SECTION (E18 Task 15): "Circular uses" drives `cycles --fix`, whose
  unit of work is ONE strongly connected component rather than a set of ticked
  names, so it is a small descendant (TCircularUsesSection) with radio-like
  ticks and Dry run / Apply buttons. Its command lines, rows and outcome text
  live in the pure DragLint.Plugin.CycleFix, which a console harness tests.

  Code-built (no .dfm) -- see the CreateNew note on the frame constructor. }

interface

uses
  System.Classes
  , System.SysUtils
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.CheckLst
  , System.Generics.Collections
  , DragLint.Plugin.CycleFix // dl:unit DragLint.Plugin.CycleFix accepted -- CYCLE_FIX_TIMEOUT_MS is the one plugin cycle-fix time limit; a second copy here is what let it drift (see StructureForm)
  ;

type
  /// <summary>Which engine verb a section drives.</summary>
  TUsesVerb = (uvUnitCleanup, uvProjectMembers, uvCircularUses);

  /// <summary>How a section reports a user-visible message to its host.</summary>
  /// <remarks>A METHOD POINTER, not TProc&lt;string&gt;: Delphi will not
  /// implicitly convert a method to an anonymous-method reference, and the
  /// closure that would be needed captures Self for the life of a child
  /// control. A plain `of object` pointer has neither problem.</remarks>
  TUsesReportProc = procedure (const AText: string) of object;

  /// <summary>One reviewable row. Mirrors an `items[]` entry of the uses-fix/1
  /// document, or one MISSING entry of the reconcile-project document.</summary>
  /// <remarks>A RECORD, not a class: a pure data carrier held in a list
  /// parallel to the TCheckListBox, so a row's identity never depends on
  /// parsing its rendered caption back out.</remarks>
  TUsesDepsRow = record
    /// <summary>What --only is given for this row.</summary>
    UnitName  : string ;
    /// <summary>uses-fix: 'move' or 'remove'. reconcile-project: 'missing'.</summary>
    Kind      : string ;
    /// <summary>Source line of the uses entry; 0 when the verb reports none.</summary>
    Line      : Integer;
    /// <summary>Why a 'skipped' row was skipped; empty otherwise.</summary>
    Reason    : string ;
    /// <summary>reconcile-project only -- what the .dpr entry will say.</summary>
    RelPath   : string ;
    /// <summary>False for 'skipped': the row is shown, disabled, never ticked.</summary>
    Actionable: Boolean;
  end;

  TUsesDepsRows = TList<TUsesDepsRow>;

  /// <summary>One reviewable section: a checklist of candidates for ONE engine
  /// verb, with Refresh / Tick all / Apply selected.</summary>
  /// <remarks>Not thread-safe; VCL, main thread only. Reports progress through
  /// the callback given at construction rather than owning a status label, so
  /// two sections can share one status line without either knowing about the
  /// other.</remarks>
  TUsesDepsSection = class(TGroupBox)
    private
      FVerb      : TUsesVerb    ;
      FBtnRefresh: TButton      ;
      FRows      : TUsesDepsRows;
      FReport    : TUsesReportProc;
      procedure BuildControls;
      function  TickedNames: string;
      function  DryRunArgs (const APas, AProj, ADb: string): string;
      function  ApplyArgs  (const APas, AProj, ADb, AOnly: string): string;
      procedure HandleRefresh(Sender: TObject);
      procedure HandleTickAll(Sender: TObject);
    protected
      FList      : TCheckListBox;
      FBar       : TPanel       ;
      { The middle button: "Tick all" here, "Dry run" in TCircularUsesSection. }
      FBtnTickAll: TButton      ;
      FBtnApply  : TButton      ;
      /// <summary>Forwards AText to the host's status line (dropped when the
      /// constructor was given nil).</summary>
      /// <param name="AText">The message, shown verbatim.</param>
      procedure Report(const AText: string);
      /// <summary>Repaints the checklist from the section's rows.</summary>
      procedure Render; virtual;
      /// <summary>The Apply button: runs the verb's --apply for the ticked rows.</summary>
      /// <param name="Sender">The button; unused.</param>
      procedure HandleApply(Sender: TObject); virtual;
    public
      /// <summary>Builds the section into AParent for AVerb.</summary>
      /// <param name="AOwner">Component owner; frees the section and its controls.</param>
      /// <param name="AParent">Control the section is parented into -- the frame.</param>
      /// <param name="AVerb">Which engine verb this section drives.</param>
      /// <param name="ACaption">Group-box caption; names the scope to the user.</param>
      /// <param name="AOnReport">Receives every user-visible message this section
      /// produces. May be nil, in which case messages are dropped.</param>
      constructor Create(AOwner: TComponent; AParent: TWinControl; AVerb: TUsesVerb;
                         const ACaption: string; AOnReport: TUsesReportProc); reintroduce;
      destructor Destroy; override;
      /// <summary>Re-queries this section and repaints it. Never called on tab
      /// activation -- only from a button or the frame's "Refresh both".</summary>
      procedure Refresh; virtual;
  end;

  /// <summary>The "Circular uses" section: one row per strongly connected
  /// component (SCC) of the project's uses graph, read from
  /// `cycles --format json --causes`, with Dry run and Apply for the ONE
  /// ticked SCC (`cycles --fix --cycle n`).</summary>
  /// <remarks>Ticks are radio-like: ticking a row unticks every other, because
  /// --cycle takes one SCC and fixing one changes the graph the others were
  /// computed on. The engine owns the edit (atomic, compiler-verified, rolled
  /// back on failure); this section only passes --cycle and, on Apply, --apply.
  /// After an apply every `written[]` path is reloaded. Dry run and Apply run
  /// as a Busy job on the plugin's JobQueue (off the main thread, limit
  /// CYCLE_FIX_TIMEOUT_MS); both buttons are disabled while it is in flight and
  /// a second start is refused. Not thread-safe; VCL, main thread only.</remarks>
  TCircularUsesSection = class(TUsesDepsSection)
    private
      FCycles : TArray<TCycleRow>;
      FRunning: Boolean;
      function  TickedCycle: Integer;
      procedure SetRunning(AValue: Boolean);
      procedure RunFix(AApply: Boolean);
      procedure FinishFix(AApply: Boolean; AExit: Integer; const AOutput: string);
      procedure HandleDryRun    (Sender: TObject);
      procedure HandleClickCheck(Sender: TObject);
    protected
      /// <summary>One row per SCC: units, fix state, fix.reason.</summary>
      procedure Render; override;
      /// <summary>Runs `cycles --fix --cycle n --apply` for the ticked SCC.</summary>
      /// <param name="Sender">The button; unused.</param>
      procedure HandleApply(Sender: TObject); override;
    public
      /// <summary>Builds the section and re-captions its strip to
      /// Refresh / Dry run / Apply, with radio-like ticks.</summary>
      /// <param name="AOwner">Component owner; frees the section and its controls.</param>
      /// <param name="AParent">Control the section is parented into -- the frame.</param>
      /// <param name="ACaption">Group-box caption; names the scope to the user.</param>
      /// <param name="AOnReport">Receives every user-visible message; may be nil.</param>
      constructor Create(AOwner: TComponent; AParent: TWinControl; const ACaption: string;
                         AOnReport: TUsesReportProc); reintroduce;
      /// <summary>Unregisters the section, so a cycles --fix job that finishes
      /// after the dock is gone does not call into a freed object.</summary>
      destructor Destroy; override;
      /// <summary>Re-runs the SCC list query and repaints. Writes nothing;
      /// never called on tab activation.</summary>
      procedure Refresh; override;
  end;

  /// <summary>The Uses &amp; Deps dock tab: a scope strip, three sections and one
  /// shared status line.</summary>
  TUsesDepsFrame = class(TForm)
    private
      FTopPanel     : TPanel         ;
      FLblScope     : TLabel         ;
      FBtnRefreshAll: TButton        ;
      FUnitSec      : TUsesDepsSection;
      FSplitter     : TSplitter      ;
      FProjSec      : TUsesDepsSection;
      FSplitter2    : TSplitter      ;
      FCycleSec     : TCircularUsesSection;
      FStatus       : TLabel         ;
      procedure BuildControls;
      procedure SetStatus(const AText: string);
      procedure HandleRefreshAll(Sender: TObject);
    public
      constructor Create(AOwner: TComponent); override;
      /// <summary>Re-queries EVERY section. Public so the dock can offer one
      /// "refresh everything" entry point; never called automatically.</summary>
      procedure RefreshAll;
  end;

/// <summary>Creates a TUsesDepsFrame owned by AOwner and parented into AParent
/// (a dock tab sheet). Mirrors the CreateEmbeddedXxx pattern used by the other
/// dock tabs.</summary>
/// <param name="AOwner">Component owner; frees the frame with the dock.</param>
/// <param name="AParent">The tab sheet the frame fills (alClient).</param>
/// <remarks>Runs no query -- see the unit header. Never raises: a tab that
/// throws during dock construction takes the whole panel with it.</remarks>
procedure CreateEmbeddedUsesDeps(AOwner: TComponent; AParent: TWinControl);

implementation

uses
  System.JSON
  , ToolsAPI
  , DragLint.Plugin.ProcRun
  , DragLint.Plugin.Settings
  , DragLint.Plugin.DbResolver
  , DragLint.Plugin.ExeResolver
  , DragLint.Plugin.Telemetry
  , DragLint.Plugin.JobQueue
  ;

const
  { uses-fix shadow-compiles ONCE PER CANDIDATE, so this is not a network-style
    timeout -- a unit with twenty candidates legitimately takes a while. Long
    enough not to truncate real work, short enough that a hung engine does not
    freeze the IDE forever. }
  ENGINE_TIMEOUT_MS = 180000;

  { Layout. Named rather than sprinkled as literals so the two identical button
    bars cannot drift apart by a pixel edit to one of them. }
  BAR_H      =  31;  { height of a button strip and of the scope strip   }
  BTN_W      = 110;  { every button in this frame is the same width      }
  BTN_H      =  25;
  BTN_TOP    =   3;  { inset inside a BAR_H strip                        }
  BTN_GAP    =   6;  { horizontal gap between adjacent buttons           }
  BTN_LEFT   =   4;  { left inset of the first button                    }
  STATUS_H   =  34;  { two lines of wrapped status text                  }
  SPLIT_H    =   4;
  UNIT_BOX_H = 230;  { initial split; the user drags FSplitter from here }
  PROJ_BOX_H = 170;  { project-members box; FSplitter2 sits below it      }
  FRAME_W    = 620;
  FRAME_H    = 720;

type
  /// <summary>The unit, project and index a query runs against.</summary>
  TUsesScope = record
    Pas    : string ;
    Proj   : string ;
    Db     : string ;
    Ok     : Boolean;
    /// <summary>Why Ok is False -- shown to the user verbatim.</summary>
    Problem: string ;
  end;

  /// <summary>What an --apply run actually did, read out of either verb's
  /// document.</summary>
  TApplyOutcome = record
    Readable : Boolean       ;
    Applied  : Boolean       ;
    Backups  : TArray<string>;
    Edited   : TArray<string>;
    Unmatched: TArray<string>;
    Warning  : string        ;
  end;

{ ---- engine plumbing (unit level: both sections use it) ------------------- }

{ Strip anything the engine printed before the document. The CLI prefixes some
  runs with "(loaded defaults from ...)" on stdout, and ProcRun merges stderr
  into the same pipe, so the first '{' is the only reliable start marker. }
function JsonBody(const AText: string): string;
var
  P: Integer;
begin
  P:= Pos('{', AText);
  if P <= 0 then Exit('');
  Result:= Copy(AText, P, MaxInt);
end;

function ParseDoc(const AText: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result:= nil;
  { A malformed document is a real condition the caller reports on screen, so
    the exception is absorbed here -- but LOGGED, because "no readable
    document" on its own gives nobody anything to debug with. }
  try
    V:= TJSONObject.ParseJSONValue(JsonBody(AText));
  except
    on E: Exception do
    begin
      V:= nil;
      DLT('uses-deps', 'JSON parse failed: ' + E.ClassName + ': ' + E.Message);
    end;
  end;
  if V is TJSONObject then Result:= TJSONObject(V)
  else V.Free;
end;

function StringsOf(AObj: TJSONObject; const AName: string): TArray<string>;
var
  Arr: TJSONArray;
  I  : Integer   ;
begin
  SetLength(Result, 0);
  if AObj = nil then Exit;
  if not AObj.TryGetValue<TJSONArray>(AName, Arr) then Exit;
  SetLength(Result, Arr.Count);
  for I:= 0 to Arr.Count - 1 do Result[I]:= Arr.Items[I].Value;
end;

{ Resolve the unit, project and index. Returns a record with Ok=False and a
  human-readable Problem rather than raising: a dock tab that throws into the
  IDE message loop is worse than one that says it has nothing to show. }
function ResolveScope: TUsesScope;
var
  Dbs: TArray<string>;
begin
  Result:= Default(TUsesScope);
  try
    Result.Pas := GetActiveEditorFilePath;
    Result.Proj:= GetActiveProjectFilePath;
    Dbs        := ResolveActiveIndexDbs(LoadSettings);
    if Length(Dbs) > 0 then Result.Db:= Dbs[0];
  except
    on E: Exception do
    begin
      Result.Problem:= 'scope could not be resolved: ' + E.Message;
      Exit;
    end;
  end;
  if Result.Proj = '' then begin Result.Problem:= 'No active project -- open one first.'; Exit; end;
  if Result.Db   = '' then begin Result.Problem:= 'No index (DB) resolved for this project.'; Exit; end;
  Result.Ok:= True;
end;

{ SAVE FIRST. Both verbs read the file from disk; an unsaved buffer means the
  candidates were computed from stale text and the apply then rewrites a file
  the editor is about to overwrite. }
procedure SaveAllModules;
var
  MS: IOTAModuleServices;
begin
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll;
end;

{ One place that spawns the engine, so the wait cursor, the quoting and the
  timeout cannot differ between the four call sites. Returns a negative value
  when the engine could not be started at all. }
function RunEngine(const AArgs: string; out AOutput: string): Integer;
var
  Exe: string;
begin
  AOutput:= '';
  Exe:= DragLintExe;
  if (Exe = '') or not FileExists(Exe) then Exit(-1);
  Screen.Cursor:= crHourGlass;
  try
    Result:= RunCaptureStdout(Format('"%s" %s', [Exe, AArgs]), AOutput, ENGINE_TIMEOUT_MS);
  finally
    Screen.Cursor:= crDefault;
  end;
end;

{ Read the outcome fields out of either verb's document, and NORMALISE the one
  place their schemas genuinely differ: uses-fix/1 spells its backup as a single
  `backup` string (it rewrites one unit), reconcile-project as a `backups` array
  (it rewrites two project files). Everything else is simply absent in the
  document that does not carry it.

  Readable=False means the document could not be parsed -- which is NOT the same
  as "nothing was written", and the caller must say so rather than report a
  silent no-op over a write that may have happened. }
function ReadOutcome(const AOutput: string): TApplyOutcome;
var
  Doc   : TJSONObject;
  Backup: string     ;
begin
  Result:= Default(TApplyOutcome);
  Doc:= ParseDoc(AOutput);
  if Doc = nil then Exit;
  try
    Doc.TryGetValue<Boolean>('applied', Result.Applied);
    Doc.TryGetValue<string> ('warning', Result.Warning);
    Result.Backups  := StringsOf(Doc, 'backups'  );
    Result.Edited   := StringsOf(Doc, 'edited'   );
    Result.Unmatched:= StringsOf(Doc, 'unmatched');
    Backup:= '';
    Doc.TryGetValue<string>('backup', Backup);
    if (Backup <> '') and (Length(Result.Backups) = 0) then Result.Backups:= [Backup];
  finally
    Doc.Free;
  end;
  Result.Readable:= True;
end;

{ THE ONE CORRECTNESS REQUIREMENT IN THIS WHOLE TAB.

  The engine writes the file on disk while the IDE may be holding it open. A
  stale editor buffer silently overwrites the fix on the user's next save --
  the change appears to work, then vanishes, with nothing to blame it on.

  ForceQueue, not a direct call: the refresh must happen after the click has
  returned to the message loop, for the reason recorded in Keyboard.pas --
  refreshing a module from inside a control's own dispatch left a dangling
  TEditSource refcount and closed the tab. The closure captures only strings;
  no OTAPI interface reference outlives this procedure. }
procedure ReloadModules(const APaths: TArray<string>);
var
  Paths: TArray<string>;
begin
  Paths:= Copy(APaths);
  if Length(Paths) = 0 then Exit;
  TThread.ForceQueue(nil,
    procedure
    var
      MS: IOTAModuleServices;
      M : IOTAModule        ;
      P : string            ;
    begin
      try
        if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
        for P in Paths do
        begin
          if P = '' then Continue;
          M:= MS.FindModule(P);
          if M <> nil then M.Refresh(True);
        end;
      except
        { A queued proc must never throw into the IDE message loop -- but it
          must not vanish either: a refresh that failed is exactly how the
          stale-buffer bug this procedure prevents would come back. }
        on E: Exception do
          DLT('uses-deps', 'deferred Refresh failed: ' + E.ClassName + ': ' + E.Message);
      end;
    end);
end; // procedure

{ Say what HAPPENED. `applied` is the outcome, not the flag -- it is false when
  there was nothing to write -- so the exit code is not the thing to believe.
  A revert is only mentioned when a backup actually exists, and the best-effort
  warning is surfaced because this tab is the one caller putting a button in
  front of a human. }
function DescribeOutcome(const AWhat: string; const AOutcome: TApplyOutcome): string;
begin
  if not AOutcome.Applied then
    Exit(AWhat + ': nothing was written -- the selection needed no change.');
  Result:= AWhat + ': applied.';
  if Length(AOutcome.Backups) > 0 then
    Result:= Result + ' Revert from: ' + string.Join('; ', AOutcome.Backups) + '.';
  if AOutcome.Warning <> '' then Result:= Result + ' ' + AOutcome.Warning;
  { A typo in the selection is reported, never swallowed: it otherwise looks
    exactly like a clean run against an already-reconciled project. }
  if Length(AOutcome.Unmatched) > 0 then
    Result:= Result + ' Not matched: ' + string.Join(', ', AOutcome.Unmatched) + '.';
end;

{ ---- TUsesDepsSection ----------------------------------------------------- }

constructor TUsesDepsSection.Create(AOwner: TComponent; AParent: TWinControl;
  AVerb: TUsesVerb; const ACaption: string; AOnReport: TUsesReportProc);
begin
  inherited Create(AOwner);
  FVerb   := AVerb;
  FReport := AOnReport;
  FRows   := TUsesDepsRows.Create;
  Parent  := AParent;
  Caption := ACaption;
  BuildControls;
end;

destructor TUsesDepsSection.Destroy;
begin
  { Only the row list is owned here; the controls belong to Self. }
  FRows.Free;
  inherited Destroy;
end;

procedure TUsesDepsSection.BuildControls;

  function MakeButton(const ACaption: string; AIndex: Integer; AHandler: TNotifyEvent): TButton;
  begin
    Result:= TButton.Create(Self);
    Result.Parent := FBar;
    Result.Left   := BTN_LEFT + AIndex * (BTN_W + BTN_GAP);
    Result.Top    := BTN_TOP;
    Result.Width  := BTN_W;
    Result.Height := BTN_H;
    Result.Caption:= ACaption;
    Result.OnClick:= AHandler;
  end;

begin
  FBar:= TPanel.Create(Self);
  FBar.Parent    := Self;
  FBar.Align     := alBottom;
  FBar.Height    := BAR_H;
  FBar.BevelOuter:= bvNone;

  FBtnRefresh:= MakeButton('Refresh'       , 0, HandleRefresh);
  FBtnTickAll:= MakeButton('Tick all'      , 1, HandleTickAll);
  FBtnApply  := MakeButton('Apply selected', 2, HandleApply  );

  FList:= TCheckListBox.Create(Self);
  FList.Parent:= Self;
  FList.Align := alClient;
end;

procedure TUsesDepsSection.Report(const AText: string);
begin
  if Assigned(FReport) then FReport(AText);
end;

{ The dry-run query. --remove-unused IS PASSED ON THE DRY RUN TOO: without it
  the engine never emits a single `remove` candidate, so the unused half of the
  unit section would be permanently empty and read as a clean unit. It writes
  nothing without --apply; only the verification compiles. }
function TUsesDepsSection.DryRunArgs(const APas, AProj, ADb: string): string;
begin
  if FVerb = uvUnitCleanup then
    Result:= Format('uses-fix "%s" --project "%s" --db "%s" --remove-unused --format json',
                    [APas, AProj, ADb])
  else
    Result:= Format('reconcile-project "%s" --json', [AProj]);
end;

{ --only carries the review. The engine still decides what is safe -- uses-fix
  re-verifies every selected candidate by compiling it -- so a tick is a
  request, never an instruction to skip verification. }
function TUsesDepsSection.ApplyArgs(const APas, AProj, ADb, AOnly: string): string;
begin
  if FVerb = uvUnitCleanup then
    Result:= Format('uses-fix "%s" --project "%s" --db "%s" --remove-unused --only %s --apply --format json',
                    [APas, AProj, ADb, AOnly])
  else
    Result:= Format('reconcile-project "%s" --only %s --apply --json', [AProj, AOnly]);
end;

procedure TUsesDepsSection.Render;
var
  I  : Integer     ;
  Row: TUsesDepsRow;
  Cap: string      ;
begin
  FList.Items.BeginUpdate;
  try
    FList.Clear;
    for I:= 0 to FRows.Count - 1 do
    begin
      Row:= FRows[I];
      if FVerb = uvProjectMembers then Cap:= Format('%-38s -> %s', [Row.UnitName, Row.RelPath])
      else                             Cap:= Format('%-8s %-38s line %d', [Row.Kind, Row.UnitName, Row.Line]);
      if not Row.Actionable then Cap:= Cap + '   -- ' + Row.Reason;
      FList.Items.Add(Cap);
      { A SKIPPED ROW IS SHOWN, NOT HIDDEN, and disabled rather than merely
        unticked. A candidate that vanished with no explanation is what makes a
        user stop trusting the panel; a candidate that can be ticked but will
        not be applied is worse still. }
      FList.ItemEnabled[I]:= Row.Actionable;
      FList.Checked    [I]:= False;
    end;
  finally
    FList.Items.EndUpdate;
  end;
end; // procedure

{ The ticked rows as a --only value. Only ACTIONABLE rows can contribute: a
  disabled row cannot be ticked through the UI, but this is the gate the apply
  actually passes through, so it is enforced here too rather than trusted. }
function TUsesDepsSection.TickedNames: string;
var
  Names: TArray<string>;
  I    : Integer       ;
begin
  SetLength(Names, 0);
  for I:= 0 to FList.Items.Count - 1 do
    if (I < FRows.Count) and FRows[I].Actionable and FList.Checked[I] then
    begin
      SetLength(Names, Length(Names) + 1);
      Names[High(Names)]:= FRows[I].UnitName;
    end;
  Result:= string.Join(',', Names);
end;

procedure TUsesDepsSection.Refresh;
var
  Scope   : TUsesScope ;
  Output  : string     ;
  Doc     : TJSONObject;
  Arr     : TJSONArray ;
  I       : Integer    ;
  It      : TJSONObject;
  Row     : TUsesDepsRow;
  Actions : Integer    ;
begin
  FRows.Clear;
  Render;
  Scope:= ResolveScope;
  if not Scope.Ok then begin Report(Scope.Problem); Exit; end;
  if (FVerb = uvUnitCleanup) and (Scope.Pas = '') then
  begin
    Report('Open a .pas unit to see its uses cleanup.');
    Exit;
  end;
  SaveAllModules;

  if RunEngine(DryRunArgs(Scope.Pas, Scope.Proj, Scope.Db), Output) < 0 then
  begin
    Report('drag-lint.exe not found -- check drag-lint Options.');
    Exit;
  end;

  Doc:= ParseDoc(Output);
  if Doc = nil then
  begin
    Report('The engine returned no readable document. Run the same action from the menu to see its raw output.');
    Exit;
  end;
  try
    { uses-fix lists every CANDIDATE under `items`; reconcile-project lists the
      actionable set under `missing`. MISSING ONLY for the project section:
      --apply adds missing units and touches nothing else, so EXTRA and STALE
      have no fix affordance here and stay on the menu report. Listing them
      beside a checkbox that cannot act on them is exactly the report/action
      confusion this tab exists to remove. }
    if FVerb = uvUnitCleanup then Doc.TryGetValue<TJSONArray>('items', Arr)
    else                          Doc.TryGetValue<TJSONArray>('missing', Arr);
    if Arr <> nil then
      for I:= 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then Continue;
        It := Arr.Items[I] as TJSONObject;
        Row:= Default(TUsesDepsRow);
        Row.UnitName:= It.GetValue<string>('unit', '');
        if FVerb = uvProjectMembers then
        begin
          Row.Kind      := 'missing';
          Row.RelPath   := It.GetValue<string>('relPath', '');
          Row.Actionable:= Row.UnitName <> '';
        end
        else
        begin
          Row.Kind   := It.GetValue<string> ('kind'  , '');
          Row.Line   := It.GetValue<Integer>('line'  , 0 );
          Row.Reason := It.GetValue<string> ('reason', '');
          { 'deselected' only happens when --only was passed, which this dry run
            never does -- so in practice a row is actionable iff it verified. }
          Row.Actionable:= SameText(It.GetValue<string>('status', ''), 'verified');
        end;
        FRows.Add(Row);
      end;
  finally
    Doc.Free;
  end;
  Render;

  Actions:= 0;
  for Row in FRows do
    if Row.Actionable then Inc(Actions);
  if FVerb = uvUnitCleanup then
    Report(Format('uses-fix: %d candidate(s), %d can be applied, %d skipped.',
                  [FRows.Count, Actions, FRows.Count - Actions]))
  else
    Report(Format('reconcile-project: %d member(s) used but not listed.', [FRows.Count]));
end; // procedure

procedure TUsesDepsSection.HandleRefresh(Sender: TObject);
begin
  Refresh;
end;

{ Ticks every ACTIONABLE row and leaves the rest alone. It is a selection
  helper, not a second apply mode -- "Apply selected" stays the only thing that
  writes, so a mis-click here costs a click to undo and nothing else. }
procedure TUsesDepsSection.HandleTickAll(Sender: TObject);
var
  I: Integer;
begin
  for I:= 0 to FList.Items.Count - 1 do
    if (I < FRows.Count) and FRows[I].Actionable then FList.Checked[I]:= True;
end;

procedure TUsesDepsSection.HandleApply(Sender: TObject);
var
  Only   : string       ;
  Scope  : TUsesScope   ;
  Output : string       ;
  Outcome: TApplyOutcome;
begin
  Only:= TickedNames;
  if Only = '' then begin Report('Nothing ticked in this section.'); Exit; end;
  Scope:= ResolveScope;
  if not Scope.Ok then begin Report(Scope.Problem); Exit; end;
  SaveAllModules;

  if RunEngine(ApplyArgs(Scope.Pas, Scope.Proj, Scope.Db, Only), Output) < 0 then
  begin
    Report('drag-lint.exe not found -- check drag-lint Options.');
    Exit;
  end;

  Outcome:= ReadOutcome(Output);
  if not Outcome.Readable then
  begin
    { NOT reported as "nothing was written": the engine may well have written
      before whatever spoiled the document. The user is told to look. }
    Report('The apply returned no readable document -- files may or may not have been written. Check them before re-running.');
    Exit;
  end;

  { Name the VERB, not the section: the status line is shared, so "applied"
    with no subject cannot say which of the two just wrote. }
  if FVerb = uvUnitCleanup then Report(DescribeOutcome('uses-fix', Outcome))
  else                          Report(DescribeOutcome('reconcile-project', Outcome));

  { WHICH FILES TO RELOAD. uses-fix rewrites the ONE unit it was given and its
    document names no others; reconcile-project reports `edited`, which is
    exactly the project files that changed, so nothing else is disturbed. }
  if Outcome.Applied then
    if FVerb = uvUnitCleanup then ReloadModules([Scope.Pas])
    else                          ReloadModules(Outcome.Edited);

  { Repaint from what is now true, not from what was true before the write. }
  Refresh;
end; // procedure

{ ---- TCircularUsesSection ------------------------------------------------- }

var
  { Every live TCircularUsesSection, main thread only. A cycles --fix job's
    OnDone runs on the main thread up to 35 minutes after it was queued; the
    dock may have been closed (and the section freed) in between, so OnDone
    checks membership here before it touches the section. }
  GLiveCycleSections: TList<TCircularUsesSection> = nil;

function IsLiveCycleSection(ASection: TCircularUsesSection): Boolean;
begin
  Result:= (GLiveCycleSections <> nil) and GLiveCycleSections.Contains(ASection);
end;

constructor TCircularUsesSection.Create(AOwner: TComponent; AParent: TWinControl;
  const ACaption: string; AOnReport: TUsesReportProc);
begin
  inherited Create(AOwner, AParent, uvCircularUses, ACaption, AOnReport);
  if GLiveCycleSections = nil then GLiveCycleSections:= TList<TCircularUsesSection>.Create;
  GLiveCycleSections.Add(Self);
  { The base strip is Refresh / Tick all / Apply selected. "Tick all" has no
    meaning when one SCC is the unit of work, so the middle button becomes the
    dry run -- the button a user should press before Apply. }
  FBtnTickAll.Caption:= 'Dry run';
  FBtnTickAll.OnClick:= HandleDryRun;
  FBtnApply.Caption  := 'Apply';
  FList.OnClickCheck := HandleClickCheck;
end;

destructor TCircularUsesSection.Destroy;
begin
  if GLiveCycleSections <> nil then GLiveCycleSections.Remove(Self);
  inherited Destroy;
end;

{ Both fix buttons follow the in-flight state; Refresh stays enabled, it is
  also how a section recovers from a job the queue dropped (see Refresh). }
procedure TCircularUsesSection.SetRunning(AValue: Boolean);
begin
  FRunning           := AValue;
  FBtnTickAll.Enabled:= not AValue;
  FBtnApply.Enabled  := not AValue;
end;

procedure TCircularUsesSection.Render;
var
  I: Integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Clear;
    { EVERY SCC IS LISTED, fixable or not, and every row can be ticked: the dry
      run of an unfixable SCC is how the user reads the engine's refusal in
      full, and Apply on one is refused by the engine, not by this panel. }
    for I:= 0 to High(FCycles) do
    begin
      FList.Items.Add(CycleRowCaption(FCycles[I]));
      FList.Checked[I]:= False;
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

{ Radio-like: --cycle takes ONE SCC. }
procedure TCircularUsesSection.HandleClickCheck(Sender: TObject);
var
  I: Integer;
begin
  if (FList.ItemIndex < 0) or not FList.Checked[FList.ItemIndex] then Exit;
  for I:= 0 to FList.Items.Count - 1 do
    if I <> FList.ItemIndex then FList.Checked[I]:= False;
end;

{ The ticked SCC's 1-based --cycle number; 0 when none is ticked. }
function TCircularUsesSection.TickedCycle: Integer;
var
  I: Integer;
begin
  for I:= 0 to FList.Items.Count - 1 do
    if (I <= High(FCycles)) and FList.Checked[I] then Exit(FCycles[I].Cycle);
  Result:= 0;
end;

procedure TCircularUsesSection.Refresh;
var
  Scope : TUsesScope;
  Output: string    ;
  Fixable: Integer  ;
  Row   : TCycleRow ;
begin
  { A job the queue dropped (ClearPending, shutdown) never runs its OnDone; it
    is no longer counted by JobQueueBusy, so that is the signal to re-enable. }
  if FRunning and not JobQueueBusy then SetRunning(False);
  if FRunning then
  begin
    Report('A cycles --fix run is in progress -- the list refreshes when it finishes.');
    Exit;
  end;
  SetLength(FCycles, 0);
  Render;
  Scope:= ResolveScope;
  if not Scope.Ok then
  begin
    Report(Scope.Problem);
    Exit;
  end;
  SaveAllModules;
  if RunEngine(CycleListArgs(Scope.Proj, Scope.Db), Output) < 0 then
  begin
    Report('drag-lint.exe not found -- check drag-lint Options.');
    Exit;
  end;
  FCycles:= ParseCycleRows(Output);
  Render;
  Fixable:= 0;
  for Row in FCycles do
    if Row.Fixable then Inc(Fixable);
  Report(Format('cycles: %d circular unit group(s), %d with a mechanical fix. Tick one, then Dry run.',
                [Length(FCycles), Fixable]));
end; // procedure

{ One path for both buttons, so the dry run the user reviewed and the apply
  that follows cannot differ in anything but --apply.

  OFF THE MAIN THREAD, through the plugin's JobQueue -- the same Busy-job shape
  as StructureForm.EnqueueFixJob: a fix that builds the project two or three
  times would otherwise freeze the IDE for minutes. Busy gives the wait cursor
  and makes JobQueueBusy refuse a second fix anywhere in the plugin; the limit
  is CYCLE_FIX_TIMEOUT_MS, above the engine's own build timeout, so a kill can
  never land in the middle of an --apply. }
procedure TCircularUsesSection.RunFix(AApply: Boolean);
var
  N      : Integer     ;
  Scope  : TUsesScope  ;
  Exe    : string      ;
  Job    : TDragLintJob;
  Sec    : TCircularUsesSection;
  IsApply: Boolean     ;
begin
  if FRunning or JobQueueBusy then
  begin
    Report('A drag-lint fix is already running -- wait for it to finish.');
    Exit;
  end;
  N:= TickedCycle;
  if N <= 0 then
  begin
    Report('Tick one circular unit group first.');
    Exit;
  end;
  Scope:= ResolveScope;
  if not Scope.Ok then
  begin
    Report(Scope.Problem);
    Exit;
  end;
  Exe:= DragLintExe;
  if (Exe = '') or not FileExists(Exe) then
  begin
    Report('drag-lint.exe not found -- check drag-lint Options.');
    Exit;
  end;
  SaveAllModules;
  Job:= TDragLintJob.Create;
  Job.Kind       := jkGeneric;
  Job.Busy       := True;
  Job.Title      := Format('cycles --fix cycle %d (%s)', [N, if AApply then 'apply' else 'dry run']);
  Job.CoalesceKey:= 'cyclefix:' + LowerCase(Scope.Db);
  Job.CmdLine    := Format('"%s" %s', [Exe,
                      if AApply then CycleFixApplyArgs(Scope.Proj, Scope.Db, N)
                      else CycleFixDryRunArgs(Scope.Proj, Scope.Db, N)]);
  Job.TimeoutMs  := CYCLE_FIX_TIMEOUT_MS;
  Job.Streaming  := False;
  { Locals, so the closure captures copies; Sec is checked for liveness before
    use because the dock may be gone when the job finishes. }
  Sec    := Self;
  IsApply:= AApply;
  Job.OnDone:=
    procedure(AExit: Integer; AOutput: string)
    begin
      if IsLiveCycleSection(Sec) then Sec.FinishFix(IsApply, AExit, AOutput);
    end;
  SetRunning(True);
  Report(Job.Title + ' -- running in the background; the IDE stays usable.');
  JobQueue.Enqueue(Job);
end; // procedure

{ Main thread (the job's OnDone). Re-enables the buttons first, whatever the
  outcome -- completion, failure or timeout. }
procedure TCircularUsesSection.FinishFix(AApply: Boolean; AExit: Integer; const AOutput: string);
var
  Outcome: TCycleFixOutcome;
begin
  SetRunning(False);
  if AExit = PROCRUN_TIMED_OUT_EXIT_CODE then
  begin
    Report(Format('cycles --fix: killed after the %d min limit -- files may or may not have been written. '
                + 'Check them before re-running.', [CYCLE_FIX_TIMEOUT_MS div (MSecsPerSec * SecsPerMin)]));
    Exit;
  end;
  Outcome:= ParseCycleFixOutcome(AOutput);
  { The written[] paths, not a guess: the engine creates new units and edits the
    .dpr/.dproj as well as the cycle's units, and every one may be open. }
  if CycleFixWroteFiles(Outcome) then ReloadModules(Outcome.Written);
  if AApply and Outcome.Readable then
    Refresh;   { the graph changed; repaint from what is now true }
  { AFTER the refresh, whose own count line would otherwise overwrite it. }
  Report(DescribeCycleFixOutcome(Outcome));
end; // procedure

procedure TCircularUsesSection.HandleDryRun(Sender: TObject);
begin
  RunFix(False);
end;

procedure TCircularUsesSection.HandleApply(Sender: TObject);
begin
  RunFix(True);
end;

{ ---- TUsesDepsFrame ------------------------------------------------------- }

constructor TUsesDepsFrame.Create(AOwner: TComponent);
begin
  { CreateNew (NOT Create) -- this is a code-built form with NO .dfm resource;
    the TCustomForm Create path calls InitInheritedComponent and raises
    EResNotFound. Same as TLintOptionsFrame and TDragLintStructureForm. }
  inherited CreateNew(AOwner);
  BuildControls;
end;

procedure TUsesDepsFrame.BuildControls;
begin
  Width := FRAME_W;
  Height:= FRAME_H;

  { --- scope strip ------------------------------------------------------- }
  FTopPanel:= TPanel.Create(Self);
  FTopPanel.Parent    := Self;
  FTopPanel.Align     := alTop;
  FTopPanel.Height    := BAR_H;
  FTopPanel.BevelOuter:= bvNone;

  FLblScope:= TLabel.Create(Self);
  FLblScope.Parent := FTopPanel;
  FLblScope.Left   := BTN_LEFT;
  FLblScope.Top    := BTN_TOP + 5;
  FLblScope.Caption:= 'scope: (press Refresh)';

  FBtnRefreshAll:= TButton.Create(Self);
  FBtnRefreshAll.Parent := FTopPanel;
  FBtnRefreshAll.Align  := alRight;
  FBtnRefreshAll.Width  := BTN_W;
  FBtnRefreshAll.Caption:= 'Refresh all';
  FBtnRefreshAll.OnClick:= HandleRefreshAll;

  { --- status line, pinned to the bottom so a long list cannot push it off - }
  FStatus:= TLabel.Create(Self);
  FStatus.Parent  := Self;
  FStatus.Align   := alBottom;
  FStatus.Layout  := tlCenter;
  FStatus.WordWrap:= True;
  FStatus.Height  := STATUS_H;
  FStatus.Caption := '  Nothing has been queried yet.';

  { --- the three sections, all reporting into the one status line --------- }
  FUnitSec:= TUsesDepsSection.Create(Self, Self, uvUnitCleanup,
    ' This unit -- uses cleanup (uses-fix) ', SetStatus);
  FUnitSec.Align := alTop;
  FUnitSec.Height:= UNIT_BOX_H;

  FSplitter:= TSplitter.Create(Self);
  FSplitter.Parent:= Self;
  FSplitter.Align := alTop;
  FSplitter.Height:= SPLIT_H;
  FSplitter.Top   := FUnitSec.Top + FUnitSec.Height;

  FProjSec:= TUsesDepsSection.Create(Self, Self, uvProjectMembers,
    ' This project -- members used but not listed (reconcile-project) ', SetStatus);
  FProjSec.Align := alTop;
  FProjSec.Height:= PROJ_BOX_H;
  FProjSec.Top   := FSplitter.Top + FSplitter.Height;

  FSplitter2:= TSplitter.Create(Self);
  FSplitter2.Parent:= Self;
  FSplitter2.Align := alTop;
  FSplitter2.Height:= SPLIT_H;
  FSplitter2.Top   := FProjSec.Top + FProjSec.Height;

  FCycleSec:= TCircularUsesSection.Create(Self, Self,
    ' This project -- Circular uses (cycles --fix) ', SetStatus);
  FCycleSec.Align:= alClient;
end; // procedure

procedure TUsesDepsFrame.SetStatus(const AText: string);
begin
  if FStatus <> nil then FStatus.Caption:= '  ' + AText;
end;

procedure TUsesDepsFrame.RefreshAll;
var
  Scope: TUsesScope;
begin
  Scope:= ResolveScope;
  FLblScope.Caption:= Format('scope: %s | %s',
    [ExtractFileName(Scope.Pas), ExtractFileName(Scope.Proj)]);
  FUnitSec.Refresh;
  FProjSec.Refresh;
  FCycleSec.Refresh;
end;

procedure TUsesDepsFrame.HandleRefreshAll(Sender: TObject);
begin
  RefreshAll;
end;

{ ---- factory -------------------------------------------------------------- }

procedure CreateEmbeddedUsesDeps(AOwner: TComponent; AParent: TWinControl);
var
  Frame: TUsesDepsFrame;
begin
  Frame:= TUsesDepsFrame.Create(AOwner);
  Frame.BorderStyle:= bsNone;   { embed child-style, no window frame }
  Frame.FormStyle  := fsNormal;
  Frame.Align      := alClient;
  Frame.Parent     := AParent;
  Frame.Visible    := True;     { CreateNew forms default to invisible }
  { Deliberately NOT refreshed here -- see the unit header: nothing runs until
    the user presses Refresh. }
end;

initialization

finalization
  FreeAndNil(GLiveCycleSections);

end.
