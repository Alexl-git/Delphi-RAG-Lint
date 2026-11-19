unit DRagLint.V151.THRB;

{ Wave v151 lane THRB -- thread data-race rules B (parallel-for shared writes, unsafe increments, blocking main thread, unobserved task exceptions).
  Scaffold created EMPTY by lane FRAME; lane THRB owns this unit, its
  DRagLint.V151.THRB.Support helpers and DRagLint.Fix.V151.THRB. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md.
  All four rules are AST walks of one unit; the index (when present) only
  refines which classes are threads or forms. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane THRB; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <para>parallel-for-shared-write: the body of TParallel.For, or of a TTask.Run / Create / Future /
  /// TThread.CreateAnonymousThread started inside a loop, stores into a plain variable declared outside
  /// that body (a captured local, a field, a global) and takes no lock. Element stores (`A[I] := ..`),
  /// member stores (`Obj.X := ..`), names the body declares itself, stores inside a nested anonymous
  /// method (Synchronize / Queue bodies run serialised) and stores under a `with` are not reported.</para>
  /// <para>thread-unsafe-increment: Inc / Dec / `X := X + e` / `X := X - e` on a unit-level variable or
  /// class var of the same file, in Execute of a thread class or in a TTask / anonymous-thread body,
  /// with no lock taken in that routine. A threadvar, a local or parameter of the same name, a field
  /// of the thread class, TInterlocked calls and Synchronize / Queue bodies are not reported; a
  /// TParallel.For body or task-in-loop body is left to parallel-for-shared-write.</para>
  /// <para>blocking-call-in-main-thread: in a method of a form or frame class (a unit with
  /// `{$R *.dfm}` / `{$R *.fmx}`), a wait with no time limit: WaitFor / Wait with no argument or
  /// INFINITE, WaitForSingleObject(..., INFINITE), WaitForMultipleObjects(..., INFINITE),
  /// TTask.WaitForAll / WaitForAny without a timeout, and TThread.Sleep. A wait on a receiver the same
  /// routine also stops or frees (Terminate, Stop, Shutdown, Cancel, Free, FreeAndNil: teardown), a destructor, and anonymous-method bodies are not reported.
  /// Plain Sleep stays with sleep-in-vcl.</para>
  /// <para>task-exception-unobserved: TTask.Run / Create / Future whose body (an anonymous method,
  /// or a routine of the same file passed by name) has no top-level try..except, and whose ITask /
  /// IFuture is never observed: the result is discarded (also after `.Start`) or kept in a local the
  /// routine never uses again except to Start it. A task kept in a field, passed on, waited or read
  /// counts as observed; a body that cannot be seen is not reported; TTask.Run with an anonymous
  /// method is left to exception-escapes-thread.</para>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151THRBRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>
    /// Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Rule</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Rule"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckProject"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.TV151FileCtx.Wants, DRagLint.V151.THRB.Support.TThrbFile.Findings, DRagLint.V151.THRB.TThrbRun.Create, DRagLint.V151.THRB.TThrbRun.Execute</para>
    /// <para>Returns: nil; Run.ParsedFile.Findings</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
    /// <seealso cref="DRagLint.V151.THRB.Support.TThrbFile.Findings"/>
    /// <seealso cref="DRagLint.V151.THRB.TThrbRun.Create"/>
    /// <seealso cref="DRagLint.V151.THRB.TThrbRun.Execute"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.Catalog"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.Catalog"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckProject"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.Catalog"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.Catalog"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.THRB.TV151THRBRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.StrUtils
  , TreeSitter
  , DRagLint.V151.THRB.Support
  ;

const
  RULE_PFOR      = 'parallel-for-shared-write';
  RULE_INCREMENT = 'thread-unsafe-increment';
  RULE_BLOCKING  = 'blocking-call-in-main-thread';
  RULE_TASK_EXC  = 'task-exception-unobserved';
  CATEGORY       = 'bug-patterns';
  SEVERITY       = 'warning';
  ARG_INFINITE   = 'infinite';
  WFSO_TIMEOUT_ARG = 1;   // WaitForSingleObject(Handle, Timeout)
  WFMO_TIMEOUT_ARG = 3;   // WaitForMultipleObjects(Count, Handles, WaitAll, Timeout)
  TEARDOWN_LEAVES: array[0..5] of string = ('terminate', 'stop', 'shutdown', 'cancel', 'free', 'destroy');

class procedure TV151THRBRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_PFOR, CATEGORY, SEVERITY,
    'Parallel loop or task-in-loop body writes a variable declared outside it without a lock -- the iterations race'));
  ADecls.Add(V151Rule(RULE_INCREMENT, CATEGORY, SEVERITY,
    'Thread code increments a global or class var without a lock -- concurrent Inc/Dec lose updates; use TInterlocked'));
  ADecls.Add(V151Rule(RULE_BLOCKING, CATEGORY, SEVERITY,
    'Form or frame method waits with no time limit (WaitFor, WaitForSingleObject INFINITE, TTask.WaitForAll, TThread.Sleep) -- the UI freezes'));
  ADecls.Add(V151Rule(RULE_TASK_EXC, CATEGORY, SEVERITY,
    'TTask started with an unguarded body and never waited or read -- an exception raised in it is lost without a trace'));
end;

type
  /// <summary>One run of the four rules over one file.</summary>
  TThrbRun = class  // dl:ok high-response@d6c1 -- REVIEWED 2026-11-14 v151 INT: one scanner class holding the per-rule checks of one lane; a split is beyond 1.51
  strict private
    FParsedFile: TThrbFile;
    FCtx : TV151FileCtx;
    function EnclosingScope(const ANode: TTSNode): TTSNode;
    function ShadowedLocally(const ANode: TTSNode; const AName: string): Boolean;
    function InsideWith(const ANode, AStop: TTSNode): Boolean;
    procedure WalkWrites(const ANode: TTSNode; const ADeclared: TList<string>; const AWithStop: TTSNode);
    procedure CheckParallelBody(const ALambda: TTSNode; AKind: TThrbLambdaKind);
    procedure WalkIncrements(const ANode: TTSNode; const AClass: string);
    procedure CheckIncrements(const ABody: TTSNode; const AClass: string);
    function IsInfiniteArg(const AArgs: TTSNode; AIndex: Integer): Boolean;
    function TornDownInRoutine(const ABody: TTSNode; const AReceiver: string): Boolean;
    procedure WalkBlocking(const ANode, ABody: TTSNode);
    function RoutineBodyByName(const AName: string; out ABody: TTSNode): Boolean;
    function TaskObserved(const ACall: TTSNode): Boolean;
    function LocalUsedAgain(const ALhs: TTSNode): Boolean;
    procedure CheckTask(const ACall: TTSNode);
  public
    constructor Create(const ACtx: TV151FileCtx);
    destructor Destroy; override;
    /// <summary>Runs every wanted rule; the findings are in File.Findings.</summary>
    procedure Execute;
    /// <summary>The parsed file and its findings.</summary>
    property ParsedFile: TThrbFile read FParsedFile;
  end;

constructor TThrbRun.Create(const ACtx: TV151FileCtx);
begin
  inherited Create;
  FCtx := ACtx;
  FParsedFile:= TThrbFile.Create(ACtx.Path, ACtx.Store, ACtx.FileId, ACtx.LibStore);
end;

destructor TThrbRun.Destroy;
begin
  FParsedFile.Free;
  inherited;  // dl:ok inherited-bare@246d -- REVIEWED 2026-11-14 v151 INT: bare inherited calls the same-named ancestor method, intended
end;

{ The nearest enclosing defProc or lambda of ANode (not ANode itself). }
function TThrbRun.EnclosingScope(const ANode: TTSNode): TTSNode;
begin
  Result:= ANode.Parent;
  while (not Result.IsNull) and (Result.NodeType <> 'defProc') and (Result.NodeType <> 'lambda') do
    Result:= Result.Parent;
end;

{ True when AName is declared by any routine or lambda enclosing ANode. }
function TThrbRun.ShadowedLocally(const ANode: TTSNode; const AName: string): Boolean;
var
  Scope: TTSNode;
  Names: TList<string>;
begin
  Result:= False;
  Names:= TList<string>.Create;
  try
    Scope:= EnclosingScope(ANode);
    while not Scope.IsNull do
    begin
      Names.Clear;
      ThrbDeclaredNames(FParsedFile, Scope, Names);
      if Names.IndexOf(AName) >= 0 then Exit(True);
      Scope:= EnclosingScope(Scope);
    end;
  finally
    Names.Free;
  end;
end;

function TThrbRun.InsideWith(const ANode, AStop: TTSNode): Boolean;
var
  Anc: TTSNode;
begin
  Result:= False;
  Anc:= ANode.Parent;
  while (not Anc.IsNull) and (not ThrbSameNode(Anc, AStop)) do
  begin
    if Anc.NodeType = 'with' then Exit(True);
    Anc:= Anc.Parent;
  end;
end;

{ ---- parallel-for-shared-write ---- }

procedure TThrbRun.WalkWrites(const ANode: TTSNode; const ADeclared: TList<string>; const AWithStop: TTSNode);
var
  Target: TTSNode;
  IsInc : Boolean;
  Name  : string;
begin
  if ANode.IsNull or (ANode.NodeType = 'lambda') or (ANode.NodeType = 'defProc') then Exit;
  Target:= ThrbWrittenName(FParsedFile, ANode, IsInc);
  if not Target.IsNull then
  begin
    Name:= FParsedFile.Canon(Target);
    if (ADeclared.IndexOf(Name) < 0) and (not InsideWith(ANode, AWithStop)) then
      FParsedFile.Emit(ANode, RULE_PFOR, Format('''%s'' is declared outside the parallel body and every iteration ' +
        'writes it with no lock -- the writes race and updates are lost; give each iteration its own slot ' +
        '(an array element, a local), or guard it with a lock or TInterlocked', [FParsedFile.Text(Target)]));
  end;
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do WalkWrites(ANode.NamedChild(I), ADeclared, AWithStop);
end;

procedure TThrbRun.CheckParallelBody(const ALambda: TTSNode; AKind: TThrbLambdaKind);
var
  Body    : TTSNode;
  Declared: TList<string>;
begin
  if AKind not in [tlkParallelFor, tlkTaskInLoop] then Exit;
  Body:= ALambda.ChildByField('body');
  if Body.IsNull or ThrbTakesLock(FParsedFile, Body) then Exit;
  Declared:= TList<string>.Create;
  try
    ThrbDeclaredNames(FParsedFile, ALambda, Declared);
    for var I: Integer:= 0 to Body.NamedChildCount - 1 do WalkWrites(Body.NamedChild(I), Declared, ALambda);
  finally
    Declared.Free;
  end;
end;

{ ---- thread-unsafe-increment ---- }

procedure TThrbRun.WalkIncrements(const ANode: TTSNode; const AClass: string);
var
  Target: TTSNode;
  IsInc : Boolean;
  Name  : string;
begin
  if ANode.IsNull or (ANode.NodeType = 'lambda') or (ANode.NodeType = 'defProc') then Exit;
  Target:= ThrbWrittenName(FParsedFile, ANode, IsInc);
  if (not Target.IsNull) and IsInc then
  begin
    Name:= FParsedFile.Canon(Target);
    if FParsedFile.IsGlobal(Name) and (not FParsedFile.IsFieldOf(AClass, Name)) and (not ShadowedLocally(ANode, Name)) then
      FParsedFile.Emit(ANode, RULE_INCREMENT, Format('''%s'' is shared by every thread and this read-modify-write is ' +
        'not atomic -- two threads interleave and an update is lost; use TInterlocked.Increment / Add, or ' +
        'take a lock around it', [FParsedFile.Text(Target)]));
  end;
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do WalkIncrements(ANode.NamedChild(I), AClass);
end;

procedure TThrbRun.CheckIncrements(const ABody: TTSNode; const AClass: string);
begin
  if ABody.IsNull or ThrbTakesLock(FParsedFile, ABody) then Exit;
  for var I: Integer:= 0 to ABody.NamedChildCount - 1 do WalkIncrements(ABody.NamedChild(I), AClass);
end;

{ ---- blocking-call-in-main-thread ---- }

function TThrbRun.IsInfiniteArg(const AArgs: TTSNode; AIndex: Integer): Boolean;
begin
  Result:= (not AArgs.IsNull) and (AIndex >= 0) and (AIndex < AArgs.NamedChildCount)
    and (FParsedFile.Canon(AArgs.NamedChild(AIndex)) = ARG_INFINITE);
end;

{ Teardown: the routine also stops or frees AReceiver (X.Terminate / Stop / Shutdown / Cancel / Free,
  FreeAndNil(X)), so the wait is the end of the object's life, not a wait for a result. }
function TThrbRun.TornDownInRoutine(const ABody: TTSNode; const AReceiver: string): Boolean;
var
  Args: TTSNode;
begin
  Result:= False;
  for var N: TTSNode in FParsedFile.Nodes do
  begin
    if (N.StartByte < ABody.StartByte) or (N.EndByte > ABody.EndByte) then Continue;
    if not ((N.NodeType = 'exprDot') or (N.NodeType = 'exprCall')) then Continue;
    var Name: string:= if N.NodeType = 'exprCall' then FParsedFile.Canon(N.ChildByField('entity')) else FParsedFile.Canon(N);
    if (ThrbReceiver(Name) = AReceiver) and MatchText(ThrbLeaf(Name), TEARDOWN_LEAVES) then Exit(True);
    if (N.NodeType = 'exprCall') and (Name = 'freeandnil') then
    begin
      Args:= N.ChildByField('args');
      if (not Args.IsNull) and (Args.NamedChildCount = 1) and (FParsedFile.Canon(Args.NamedChild(0)) = AReceiver) then
        Exit(True);
    end;
  end;
end;

procedure TThrbRun.WalkBlocking(const ANode, ABody: TTSNode);
var
  Name, Leaf, Recv: string;
  Args            : TTSNode;
  Count           : Integer;
  Hit             : Boolean;
  Par             : TTSNode;
begin
  if ANode.IsNull or (ANode.NodeType = 'lambda') or (ANode.NodeType = 'defProc') then Exit;
  Name:= '';
  Args:= Default(TTSNode);
  if ANode.NodeType = 'exprCall' then
  begin
    Name:= FParsedFile.Canon(ANode.ChildByField('entity'));
    Args:= ANode.ChildByField('args');
  end
  else if (ANode.NodeType = 'exprDot') then
  begin
    Par:= ANode.Parent;
    if (not Par.IsNull) and (Par.NodeType = 'statement') then Name:= FParsedFile.Canon(ANode);
  end;
  if Name <> '' then
  begin
    Count:= if Args.IsNull then 0 else Args.NamedChildCount;
    Leaf := ThrbLeaf(Name);
    Recv := ThrbReceiver(Name);
    Hit  := False;
    if (Name = 'waitforsingleobject') or (Name = 'waitforsingleobjectex') then Hit:= IsInfiniteArg(Args, WFSO_TIMEOUT_ARG)
    else if (Name = 'waitformultipleobjects') or (Name = 'waitformultipleobjectsex') then Hit:= IsInfiniteArg(Args, WFMO_TIMEOUT_ARG)
    else if (Name = 'ttask.waitforall') or (Name = 'ttask.waitforany') then
      Hit:= (Count = 1) or IsInfiniteArg(Args, Count - 1)
    else if Name = 'tthread.sleep' then Hit:= True
    else if ((Leaf = 'waitfor') or (Leaf = 'wait')) and (Recv <> '') then
      Hit:= ((Count = 0) or ((Count = 1) and IsInfiniteArg(Args, 0))) and (not TornDownInRoutine(ABody, Recv));
    if Hit then
      FParsedFile.Emit(ANode, RULE_BLOCKING, Format('%s blocks the main thread with no time limit -- the window stops ' +
        'painting and answering input until it returns; wait in a worker and report back with ' +
        'TThread.Queue, or poll with a short timeout', [FParsedFile.Text(if ANode.NodeType = 'exprCall' then
        ANode.ChildByField('entity') else ANode)]));
  end;
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do WalkBlocking(ANode.NamedChild(I), ABody);
end;

{ ---- task-exception-unobserved ---- }

function TThrbRun.RoutineBodyByName(const AName: string; out ABody: TTSNode): Boolean;
var
  Found: Integer;
begin
  Found:= 0;
  ABody:= Default(TTSNode);
  for var N: TTSNode in FParsedFile.Nodes do
  begin
    if N.NodeType <> 'defProc' then Continue;
    var Hdr: TTSNode:= N.ChildByField('header');
    if Hdr.IsNull then Continue;
    if ThrbLeaf(FParsedFile.Canon(Hdr.ChildByField('name'))) <> AName then Continue;
    var Body: TTSNode:= N.ChildByField('body');
    if Body.IsNull then Continue;
    if ThrbGuarded(Body) then Exit(False);
    Inc(Found);
    ABody:= Body;
  end;
  Result:= Found > 0;
end;

function TThrbRun.TaskObserved(const ACall: TTSNode): Boolean;
var
  Cur, Par, Lhs: TTSNode;
begin
  Cur:= ACall;
  Par:= Cur.Parent;
  { TTask.Create(..).Start / .Start(): the value flows on as the ITask Start returns. }
  if (not Par.IsNull) and (Par.NodeType = 'exprDot') and ThrbSameNode(Par.ChildByField('lhs'), Cur)
    and (FParsedFile.Canon(Par.ChildByField('rhs')) = 'start') then
  begin
    Cur:= Par;
    Par:= Cur.Parent;
    if (not Par.IsNull) and (Par.NodeType = 'exprCall') and ThrbSameNode(Par.ChildByField('entity'), Cur) then
    begin
      Cur:= Par;
      Par:= Cur.Parent;
    end;
  end;
  if Par.IsNull then Exit(True);
  if Par.NodeType = 'statement' then Exit(False);
  if (Par.NodeType <> 'assignment') or (not ThrbSameNode(Par.ChildByField('rhs'), Cur)) then Exit(True);
  Lhs:= Par.ChildByField('lhs');
  if Lhs.NodeType = 'varAssignDef' then
  begin
    for var I: Integer:= 0 to Lhs.NamedChildCount - 1 do
      if Lhs.NamedChild(I).NodeType = 'identifier' then Lhs:= Lhs.NamedChild(I);
  end;
  if Lhs.NodeType <> 'identifier' then Exit(True);
  Result:= LocalUsedAgain(Lhs);
end;

{ ALhs is the identifier a task was stored into. True unless it is a local of the enclosing routine that is
  never used again other than being declared, re-assigned or started: any other use observes (or may
  observe) the task. A non-local (field, global) counts as used. }
function TThrbRun.LocalUsedAgain(const ALhs: TTSNode): Boolean;
var
  Routine: TTSNode;
  Name   : string;
  Locals : TList<string>;
  IsLocal: Boolean;
begin
  Name:= FParsedFile.Canon(ALhs);
  Routine:= ALhs.Parent;
  while (not Routine.IsNull) and (Routine.NodeType <> 'defProc') do Routine:= Routine.Parent;
  if Routine.IsNull then Exit(True);
  Locals:= TList<string>.Create;
  try
    ThrbDeclaredNames(FParsedFile, Routine, Locals);
    IsLocal:= Locals.IndexOf(Name) >= 0;
  finally
    Locals.Free;
  end;
  Result:= not IsLocal;
  for var N: TTSNode in FParsedFile.Nodes do
  begin
    if Result then Break;
    if (N.NodeType <> 'identifier') or (N.StartByte < Routine.StartByte) or (N.EndByte > Routine.EndByte)
      or ThrbSameNode(N, ALhs) or (FParsedFile.Canon(N) <> Name) then Continue;
    var P: TTSNode:= N.Parent;
    var IsDecl   : Boolean:= (P.NodeType = 'declVar') or (P.NodeType = 'varAssignDef');
    var IsMember : Boolean:= (P.NodeType = 'exprDot') and ThrbSameNode(P.ChildByField('rhs'), N);
    var IsStart  : Boolean:= (P.NodeType = 'exprDot') and ThrbSameNode(P.ChildByField('lhs'), N)
      and (FParsedFile.Canon(P.ChildByField('rhs')) = 'start');
    var IsRestore: Boolean:= (P.NodeType = 'assignment') and ThrbSameNode(P.ChildByField('lhs'), N);
    Result:= not (IsDecl or IsMember or IsStart or IsRestore);
  end;
end;

procedure TThrbRun.CheckTask(const ACall: TTSNode);  // dl:ok too-many-exit-points@2eeb -- a ladder of guard clauses, one per shape that is not this rule's case
var
  Callee: string;
  Args  : TTSNode;
  Body  : TTSNode;
  Lambda: TTSNode;
  RefArg: TTSNode;
  Shown : string;
begin
  Callee:= FParsedFile.Canon(ACall.ChildByField('entity'));
  if not ((Callee = 'ttask.run') or (Callee = 'ttask.create') or (Callee = 'ttask.future')) then Exit;
  Args:= ACall.ChildByField('args');
  if Args.IsNull then Exit;
  Lambda:= Default(TTSNode);
  RefArg:= Default(TTSNode);
  for var I: Integer:= 0 to Args.NamedChildCount - 1 do
  begin
    var A: TTSNode:= Args.NamedChild(I);
    if (A.NodeType = 'lambda') and Lambda.IsNull then Lambda:= A
    else if ((A.NodeType = 'identifier') or (A.NodeType = 'exprDot')) and RefArg.IsNull then RefArg:= A;
  end;
  if not Lambda.IsNull then
  begin
    if Callee = 'ttask.run' then Exit;                       // exception-escapes-thread reports it
    Body:= Lambda.ChildByField('body');
    if ThrbGuarded(Body) then Exit;
    Shown:= 'its anonymous method';
  end
  else
  begin
    if RefArg.IsNull or (not RoutineBodyByName(ThrbLeaf(FParsedFile.Canon(RefArg)), Body)) then Exit;
    Shown:= FParsedFile.Text(RefArg);
  end;
  if TaskObserved(ACall) then Exit;
  FParsedFile.Emit(ACall, RULE_TASK_EXC, Format('%s runs %s, which has no try..except, and the task is never waited ' +
    'or read -- an exception raised in it is stored in the task and lost; keep the ITask and Wait on it, or ' +
    'catch and report inside the body', [FParsedFile.Text(ACall.ChildByField('entity')), Shown]));
end;

{ ---- driver ---- }

procedure TThrbRun.Execute;
var
  Kind    : TThrbLambdaKind;
  Call    : TTSNode;
  FormUnit: Boolean;
begin
  if not FParsedFile.Ok then Exit;
  FormUnit:= FParsedFile.SourceContains('{$r *.dfm}') or FParsedFile.SourceContains('{$r *.fmx}');
  for var N: TTSNode in FParsedFile.Nodes do
  begin
    if N.NodeType = 'lambda' then
    begin
      Kind:= ThrbLambdaKind(FParsedFile, N, Call);
      if FCtx.Wants(RULE_PFOR) then CheckParallelBody(N, Kind);
      if FCtx.Wants(RULE_INCREMENT) and (Kind = tlkTask) then CheckIncrements(N.ChildByField('body'), '');
    end
    else if N.NodeType = 'defProc' then
    begin
      var Hdr: TTSNode:= N.ChildByField('header');
      if Hdr.IsNull then Continue;
      var NameN: TTSNode:= Hdr.ChildByField('name');
      if NameN.IsNull or (NameN.NodeType <> 'genericDot') then Continue;
      var Cls: string:= FParsedFile.Canon(NameN.ChildByField('lhs'));
      var Meth: string:= FParsedFile.Canon(NameN.ChildByField('rhs'));
      if FCtx.Wants(RULE_INCREMENT) and (Meth = 'execute') and FParsedFile.IsThreadClass(Cls) then
        CheckIncrements(N.ChildByField('body'), Cls);
      if FCtx.Wants(RULE_BLOCKING) and FormUnit and (Hdr.ChildCount > 0) and (Hdr.Child(0).NodeType <> 'kDestructor')
        and FParsedFile.IsFormClass(Cls) then
      begin
        var Body: TTSNode:= N.ChildByField('body');
        if not Body.IsNull then
          for var I: Integer:= 0 to Body.NamedChildCount - 1 do WalkBlocking(Body.NamedChild(I), Body);
      end;
    end
    else if (N.NodeType = 'exprCall') and FCtx.Wants(RULE_TASK_EXC) then
      CheckTask(N);
  end;
end;

class function TV151THRBRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Run: TThrbRun;
begin
  Result:= nil;
  if not (ACtx.Wants(RULE_PFOR) or ACtx.Wants(RULE_INCREMENT) or ACtx.Wants(RULE_BLOCKING)
    or ACtx.Wants(RULE_TASK_EXC)) then Exit;
  Run:= TThrbRun.Create(ACtx);
  try
    Run.Execute;
    Result:= Run.ParsedFile.Findings;
  finally
    Run.Free;
  end;
end;

class function TV151THRBRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@407f -- signature fixed by TV151Dispatch; no form-file rule in this lane
begin
  Result:= nil;
end;

class function TV151THRBRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@ea5d -- signature fixed by TV151Dispatch; no raw-byte rule in this lane
begin
  Result:= nil;
end;

class function TV151THRBRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@f5d3 -- signature fixed by TV151Dispatch; no project-wide rule in this lane
begin
  Result:= nil;
end;

end.
