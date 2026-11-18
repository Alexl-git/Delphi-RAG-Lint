unit DRagLint.V151.DS.Support;

{ Wave v151 lane DS -- the syntax-tree analysis behind DRagLint.V151.DS (private to the lane).
  One walk over one parsed .pas collects, per routine, the calls, assignments and call
  arguments it contains; the three rules then read those lists:
    dataset-edit-without-post  -- Edit / Append / Insert, a field write, no Post / Cancel
    loop-condition-invariant   -- (host expansion) dataset loop that never advances
    transaction-without-rollback -- StartTransaction + Commit with no Rollback
  Receivers are compared as lower-cased text without blanks ("q", "dm.tblkunde"); a call
  with no receiver inside "with X do" gets the receiver X. Nothing here needs the index. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  ;

type
  /// <summary>One call seen in a routine: Recv.Meth(...), or a bare Meth inside a with.</summary>
  TDsCall = record
    Recv   : string;    // normalised receiver text; '' when there is none
    Meth   : string;    // lower-cased method / property name
    HasArgs: Boolean;   // at least one argument was written
    IsStmt : Boolean;   // the call is a statement of its own
    Pos    : Integer;   // start byte, for "before / after" tests
    Node   : TTSNode;
  end;

  /// <summary>One assignment seen in a routine.</summary>
  TDsAssign = record
    Lhs     : string;   // normalised left-hand side
    WithTop : string;   // innermost with-target at that point, '' when none
    Pos     : Integer;
  end;

  /// <summary>A try ... except statement: where it starts and ends (byte offsets).</summary>
  TDsTry = record
    First: Integer;
    Last : Integer;
  end;

  /// <summary>Everything one subtree contains that the dataset rules look at.</summary>
  TDsFacts = class
  strict private
    FCalls  : TList<TDsCall>;
    FAssigns: TList<TDsAssign>;
    FArgs   : TDictionary<string, Boolean>;
    FTries  : TList<TDsTry>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Every call, in source order.</summary>
    property Calls: TList<TDsCall> read FCalls;
    /// <summary>Every assignment, in source order.</summary>
    property Assigns: TList<TDsAssign> read FAssigns;
    /// <summary>Normalised text of the plain (identifier / member) arguments passed to any call.</summary>
    property Args: TDictionary<string, Boolean> read FArgs;
    /// <summary>The try ... except statements (a finally-only try is not listed).</summary>
    property Tries: TList<TDsTry> read FTries;
  end;

  /// <summary>The v151 DS analysis of one parsed file.</summary>
  /// <remarks>Create it per file and call Run once. Stateless between files.</remarks>
  TDsAnalysis = class  // dl:ok high-response@302d -- REVIEWED 2026-11-13 v151 DS: one walker class holds the three rules; they share the fact collection
  strict private
    FSrc     : TBytes;
    FFile    : string;
    FWanted  : TFunc<string, Boolean>;
    FFindings: TList<TLintFinding>;
    FWith    : TList<string>;
    FPosted  : TDictionary<string, Integer>;  { receiver -> routines of the unit that Post / Cancel it }
    FDecl    : TDictionary<string, Boolean>;  { parameters and locals of the routine being checked }
    procedure PreScanPosts(const N: TTSNode);
    procedure CollectDecls(const N: TTSNode);
    function Txt(const N: TTSNode): string;
    function Norm(const N: TTSNode): string;
    function WithTop: string;
    procedure Emit(const ANode: TTSNode; const ARuleId, AMessage: string);
    procedure Collect(const N: TTSNode; AFacts: TDsFacts; ARoot: Boolean);
    function CallOf(const N: TTSNode; out ACall: TDsCall): Boolean;
    procedure AddArgs(const AArgs: TTSNode; AFacts: TDsFacts);
    function IsAdvance(const ACall: TDsCall; const ARecv: string): Boolean;
    function IsAdvanceStmt(const S: TTSNode; const ARecv: string): Boolean;
    function HasAdvance(const AFacts: TDsFacts; const ARecv: string): Boolean;
    function EndsLoop(const N: TTSNode; AInner: Integer): Boolean;
    function HasLoopExit(const N: TTSNode; AInner: Integer): Boolean;
    function EofReceiver(const ACond: TTSNode; ARepeat: Boolean; out ARecv: string): Boolean;
    procedure CheckContinues(const N: TTSNode; const ARecv: string; AAdvancePos: Integer; ACovered: Boolean);
    procedure AnalyzeLoop(const N: TTSNode);
    function IsFieldWrite(const A: TDsAssign; const ARecv: string): Boolean;
    procedure CheckEdits(AFacts: TDsFacts);
    procedure CheckTransactions(AFacts: TDsFacts);
    procedure AnalyzeRoutine(const N: TTSNode);
    procedure Visit(const N: TTSNode);
  public
    /// <summary>Builds an analysis of one file.</summary>
    /// <param name="AFile">Path reported in the findings.</param>
    /// <param name="ASrc">The parsed source bytes (UTF-8) the tree was built from.</param>
    /// <param name="AWanted">Tells whether the run reports a rule id; a rule that is not wanted is not computed.</param>
    constructor Create(const AFile: string; const ASrc: TBytes; const AWanted: TFunc<string, Boolean>);
    destructor Destroy; override;
    /// <summary>Walks the tree once and returns the findings of the three DS rules.</summary>
    /// <param name="ARoot">Root node of the file's tree.</param>
    /// <returns>The findings; empty when the file is clean.</returns>
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

/// <summary>Runs the DS rules on one file through the shared parse cache.</summary>
/// <param name="AFile">Absolute path of the .pas.</param>
/// <param name="AWanted">Which rule ids to compute.</param>
/// <returns>The findings; nil when the file cannot be parsed.</returns>
function DsCheckFile(const AFile: string; const AWanted: TFunc<string, Boolean>): TArray<TLintFinding>;

implementation

uses
  System.Classes
  , DRagLint.Diagnostics.ParseCache
  ;

const
  RULE_EDIT  = 'dataset-edit-without-post';
  RULE_LOOP  = 'loop-condition-invariant';
  RULE_TRANS = 'transaction-without-rollback';
  SELF_PREFIX = 'self.';

  /// Methods that leave the edit state or save it: Post, Cancel, and the moves that post on their own.
  FINISH_METHODS: array[0..8] of string = (
    'post', 'cancel', 'checkbrowsemode', 'next', 'prior', 'first', 'last', 'locate', 'applyupdates');
  /// Methods that move the cursor of a dataset, so a loop over it ends.
  ADVANCE_METHODS: array[0..14] of string = (
    'next', 'prior', 'first', 'last', 'delete', 'moveby', 'findnext', 'findprior', 'findfirst',
    'findlast', 'locate', 'close', 'gotobookmark', 'setrecno', 'refresh');
  START_METHODS: array[0..1] of string = ('starttransaction', 'begintrans');
  COMMIT_METHODS: array[0..2] of string = ('commit', 'committrans', 'commitretaining');
  ROLLBACK_METHODS: array[0..2] of string = ('rollback', 'rollbacktrans', 'rollbackretaining');

function InSet(const AValue: string; const ASet: array of string): Boolean;
var
  S: string;
begin
  Result:= False;
  for S in ASet do
    if AValue = S then Exit(True);
end;

{ True when AValue starts with one of the words. }
function StartsWithAny(const AValue: string; const AWords: array of string): Boolean;
var
  S: string;
begin
  Result:= False;
  for S in AWords do
    if AValue.StartsWith(S) then Exit(True);
end;

{ A loop statement node type. }
function IsLoopNode(const AType: string): Boolean;
begin
  Result:= (AType = 'while') or (AType = 'repeat') or (AType = 'for') or (AType = 'foreach');
end;

{ Two receivers name the same connection when they are equal or one is a part of the other
  (Conn and Conn.Transaction). A leading Self. does not matter. }
function RelatedRecv(const A, B: string): Boolean;
var
  X, Y: string;
begin
  X:= A;
  Y:= B;
  if X.StartsWith(SELF_PREFIX) then X:= Copy(X, Length(SELF_PREFIX) + 1, MaxInt);
  if Y.StartsWith(SELF_PREFIX) then Y:= Copy(Y, Length(SELF_PREFIX) + 1, MaxInt);
  Result:= (X = Y) or X.StartsWith(Y + '.') or Y.StartsWith(X + '.');
end;

{ TDsFacts }

constructor TDsFacts.Create;
begin
  inherited Create;
  FCalls  := TList<TDsCall>.Create;
  FAssigns:= TList<TDsAssign>.Create;
  FArgs   := TDictionary<string, Boolean>.Create;
  FTries  := TList<TDsTry>.Create;
end;

destructor TDsFacts.Destroy;
begin
  FTries.Free;
  FArgs.Free;
  FAssigns.Free;
  FCalls.Free;
  inherited Destroy;
end;

{ TDsAnalysis }

constructor TDsAnalysis.Create(const AFile: string; const ASrc: TBytes; const AWanted: TFunc<string, Boolean>);
begin
  inherited Create;
  FFile    := AFile;
  FSrc     := ASrc;
  FWanted  := AWanted;
  FFindings:= TList<TLintFinding>.Create;
  FWith    := TList<string>.Create;
  FPosted  := TDictionary<string, Integer>.Create;
  FDecl    := TDictionary<string, Boolean>.Create;
end;

destructor TDsAnalysis.Destroy;
begin
  FPosted.Free;
  FDecl.Free;
  FWith.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TDsAnalysis.Txt(const N: TTSNode): string;
var
  S, E: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  E:= Integer(N.EndByte);
  if (E <= S) or (S < 0) or (E > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, E - S);
end;

{ Lower-cased text without blanks, so `Q . FieldByName ('A')` and `q.fieldbyname('a')` compare equal. }
function TDsAnalysis.Norm(const N: TTSNode): string;
var
  C : Char;
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    for C in LowerCase(Txt(N)) do
      if not CharInSet(C, [' ', #9, #10, #13]) then SB.Append(C);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function TDsAnalysis.WithTop: string;
begin
  Result:= if FWith.Count > 0 then FWith[FWith.Count - 1] else '';
end;

procedure TDsAnalysis.Emit(const ANode: TTSNode; const ARuleId, AMessage: string);
var
  P: TTSPoint;
  F: TLintFinding;
begin
  P:= ANode.StartPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARuleId;
  F.Severity := 'warning';
  F.Message  := AMessage;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := TAstParseCache.CharCol(F.FilePath, P); { 1.52 BK-COLS2: character column }
  F.EndLine  := F.StartLine;
  F.EndCol   := F.StartCol + Length(Trim(Txt(ANode)));
  FFindings.Add(F);
end;

{ Reads a call out of an exprCall, an exprDot used as a call, or (inside a with) a bare identifier. }
function TDsAnalysis.CallOf(const N: TTSNode; out ACall: TDsCall): Boolean;
var
  Ent, Args, Par: TTSNode;
begin
  Result:= False;
  ACall:= Default(TDsCall);
  ACall.Node:= N;
  ACall.Pos := Integer(N.StartByte);
  if N.NodeType = 'exprCall' then
  begin
    Ent := N.ChildByField('entity');
    Args:= N.ChildByField('args');
    ACall.HasArgs:= (not Args.IsNull) and (Args.NamedChildCount > 0);
  end
  else
    Ent:= N;
  if Ent.IsNull then Exit;
  if Ent.NodeType = 'exprDot' then
  begin
    if Ent.ChildByField('rhs').NodeType <> 'identifier' then Exit;
    ACall.Recv:= Norm(Ent.ChildByField('lhs'));
    ACall.Meth:= Norm(Ent.ChildByField('rhs'));
  end
  else if (Ent.NodeType = 'identifier') and (WithTop <> '') then
  begin
    ACall.Recv:= WithTop;
    ACall.Meth:= Norm(Ent);
  end
  else
    Exit;
  Par:= N.Parent;
  ACall.IsStmt:= (not Par.IsNull) and (Par.NodeType = 'statement');
  Result:= True;
end;

procedure TDsAnalysis.AddArgs(const AArgs: TTSNode; AFacts: TDsFacts);
var
  I: Integer;
  A: TTSNode;
begin
  if AArgs.IsNull then Exit;
  for I:= 0 to AArgs.NamedChildCount - 1 do
  begin
    A:= AArgs.NamedChild(I);
    if (A.NodeType = 'identifier') or (A.NodeType = 'exprDot') then AFacts.Args.AddOrSetValue(Norm(A), True);
  end;
end;

{ Fills AFacts with the calls, assignments and plain arguments under N. A nested routine is a
  scope of its own and is not entered; an anonymous method is part of the routine around it. }
procedure TDsAnalysis.Collect(const N: TTSNode; AFacts: TDsFacts; ARoot: Boolean);
var
  I    : Integer;
  T    : string;
  Call : TDsCall;
  Asg  : TDsAssign;
  Ent  : TTSNode;
  Pushed: Boolean;
  Tr   : TDsTry;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') and (not ARoot) then Exit;
  if T = 'assignment' then
  begin
    Asg.Lhs    := Norm(N.ChildByField('lhs'));
    Asg.WithTop:= WithTop;
    Asg.Pos    := Integer(N.StartByte);
    AFacts.Assigns.Add(Asg);
  end
  else if (T = 'exprCall') or (T = 'exprDot') or ((T = 'identifier') and (WithTop <> '')) then
  begin
    if CallOf(N, Call) then AFacts.Calls.Add(Call);
    if T = 'exprCall' then
    begin
      AddArgs(N.ChildByField('args'), AFacts);
      Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'exprDot') then
        Collect(Ent.ChildByField('lhs'), AFacts, False);
      Collect(N.ChildByField('args'), AFacts, False);
      Exit;
    end;
    if T = 'exprDot' then
    begin
      Collect(N.ChildByField('lhs'), AFacts, False);
      Exit;
    end;
    Exit;
  end;
  Pushed:= False;
  if T = 'with' then
  begin
    Ent:= N.ChildByField('entity');
    FWith.Add(if Ent.IsNull then '' else Norm(Ent));
    Pushed:= True;
  end
  else if T = 'try' then
    for I:= 0 to N.ChildCount - 1 do
      if N.Child(I).NodeType = 'kExcept' then
      begin
        Tr.First:= Integer(N.StartByte);
        Tr.Last := Integer(N.EndByte);
        AFacts.Tries.Add(Tr);
        Break;
      end;
  try
    for I:= 0 to N.NamedChildCount - 1 do Collect(N.NamedChild(I), AFacts, False);
  finally
    if Pushed then FWith.Delete(FWith.Count - 1);
  end;
end;

function TDsAnalysis.IsAdvance(const ACall: TDsCall; const ARecv: string): Boolean;
begin
  Result:= (ACall.Recv = ARecv) and InSet(ACall.Meth, ADVANCE_METHODS);
end;

{ A statement that is exactly one advancing call on ARecv (Q.Next;). }
function TDsAnalysis.IsAdvanceStmt(const S: TTSNode; const ARecv: string): Boolean;
var
  Call: TDsCall;
begin
  Result:= (S.NodeType = 'statement') and (S.NamedChildCount = 1) and CallOf(S.NamedChild(0), Call) and IsAdvance(Call, ARecv);
end;

function TDsAnalysis.HasAdvance(const AFacts: TDsFacts; const ARecv: string): Boolean;
var
  C: TDsCall;
  A: TDsAssign;
begin
  Result:= False;
  for C in AFacts.Calls do
    if IsAdvance(C, ARecv) then Exit(True);
  for A in AFacts.Assigns do
    if A.Lhs.StartsWith(ARecv + '.') then Exit(True);
end;

{ True when N itself ends the enclosing loop for good: raise, goto, asm, Exit, Halt, Abort,
  RunError, or a Break that belongs to this loop (AInner = 0). }
function TDsAnalysis.EndsLoop(const N: TTSNode; AInner: Integer): Boolean;
var
  T, W: string;
begin
  T:= N.NodeType;
  Result:= (T = 'raise') or (T = 'goto') or (T = 'asm');
  if (not Result) and (T = 'statement') and (N.NamedChildCount = 1) then
  begin
    W:= LowerCase(Trim(Txt(N.NamedChild(0))));
    Result:= StartsWithAny(W, ['exit', 'halt', 'abort', 'runerror']) or ((W = 'break') and (AInner = 0));
  end;
end;

{ True when the code under N can leave the loop for good (see EndsLoop); nested routines and
  anonymous methods are not entered, a Break inside an inner loop only leaves that loop. }
function TDsAnalysis.HasLoopExit(const N: TTSNode; AInner: Integer): Boolean;
var
  I    : Integer;
  T    : string;
  Inner: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') then Exit;
  Result:= EndsLoop(N, AInner);
  Inner:= AInner;
  if IsLoopNode(T) then Inc(Inner);
  I:= 0;
  while (not Result) and (I < N.NamedChildCount) do
  begin
    Result:= HasLoopExit(N.NamedChild(I), Inner);
    Inc(I);
  end;
end;

{ Recognises "not X.Eof" / "not X.Bof" (while) and "X.Eof" / "X.Bof" (until); ARecv is the dataset. }
function TDsAnalysis.EofReceiver(const ACond: TTSNode; ARepeat: Boolean; out ARecv: string): Boolean;
var
  C, D: TTSNode;
  M   : string;
begin
  Result:= False;
  ARecv:= '';
  C:= ACond;
  while (not C.IsNull) and (C.NodeType = 'exprParens') and (C.NamedChildCount = 1) do C:= C.NamedChild(0);
  if C.IsNull then Exit;
  if not ARepeat then
  begin
    if (C.NodeType <> 'exprUnary') or (C.ChildByField('operator').NodeType <> 'kNot') then Exit;
    C:= C.ChildByField('operand');
    while (not C.IsNull) and (C.NodeType = 'exprParens') and (C.NamedChildCount = 1) do C:= C.NamedChild(0);
    if C.IsNull then Exit;
  end;
  D:= C;
  if D.NodeType = 'exprDot' then
  begin
    M:= Norm(D.ChildByField('rhs'));
    if (M <> 'eof') and (M <> 'bof') then Exit;
    ARecv:= Norm(D.ChildByField('lhs'));
    Result:= True;
  end
  else if (D.NodeType = 'identifier') and (WithTop <> '') then
  begin
    M:= Norm(D);
    if (M <> 'eof') and (M <> 'bof') then Exit;
    ARecv:= WithTop;
    Result:= True;
  end;
end;

{ Reports each Continue of this loop that runs before the loop's own advance statement and is not
  covered by a try/finally whose finally part advances. }
procedure TDsAnalysis.CheckContinues(const N: TTSNode; const ARecv: string; AAdvancePos: Integer; ACovered: Boolean);
var
  I      : Integer;
  T      : string;
  Covered: Boolean;
  Fin    : TDsFacts;
  K, F   : TTSNode;
  InFin  : Boolean;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') or IsLoopNode(T) then Exit;
  if (T = 'statement') and (N.NamedChildCount = 1) and (SameText(Trim(Txt(N.NamedChild(0))), 'continue')) then
  begin
    if (not ACovered) and (Integer(N.StartByte) < AAdvancePos) then
      Emit(N, RULE_LOOP, 'Continue skips the Next at the end of this dataset loop -- the same record is read again and the loop never ends');
    Exit;
  end;
  Covered:= ACovered;
  if T = 'try' then
  begin
    InFin:= False;
    for I:= 0 to N.ChildCount - 1 do
    begin
      K:= N.Child(I);
      if K.NodeType = 'kFinally' then InFin:= True
      else if InFin and (K.NodeType = 'statements') then
      begin
        F:= K;
        Fin:= TDsFacts.Create;
        try
          Collect(F, Fin, False);
          if HasAdvance(Fin, ARecv) then Covered:= True;
        finally
          Fin.Free;
        end;
      end;
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    CheckContinues(N.NamedChild(I), ARecv, AAdvancePos, Covered);
    if (not Covered) and IsAdvanceStmt(N.NamedChild(I), ARecv) then Covered:= True;
  end;
end;

procedure TDsAnalysis.AnalyzeLoop(const N: TTSNode);
var
  Recv    : string;
  Body    : TTSNode;
  Facts   : TDsFacts;
  I       : Integer;
  S       : TTSNode;
  Call    : TDsCall;
  AdvPos  : Integer;
  Items   : TList<TTSNode>;
begin
  if not FWanted(RULE_LOOP) then Exit;
  Body:= N.ChildByField('body');
  if Body.IsNull then Exit;
  if not EofReceiver(N.ChildByField('condition'), N.NodeType = 'repeat', Recv) then Exit;
  Facts:= TDsFacts.Create;
  Items:= TList<TTSNode>.Create;
  try
    Collect(Body, Facts, False);
    if Facts.Args.ContainsKey(Recv) or (Recv = '') then Exit;
    if not HasAdvance(Facts, Recv) then
    begin
      if not HasLoopExit(Body, 0) then
        Emit(N, RULE_LOOP, Format('Dataset loop never moves "%s" on (no Next, Delete or other cursor move in the body) -- it reads the same record forever', [Recv]));
      Exit;
    end;
    { the first statement of the loop body that advances }
    if Body.NodeType = 'block' then
      for I:= 0 to Body.NamedChildCount - 1 do Items.Add(Body.NamedChild(I))
    else
      Items.Add(Body);
    AdvPos:= -1;
    for S in Items do
      if (S.NodeType = 'statement') and (S.NamedChildCount = 1) and CallOf(S.NamedChild(0), Call)
         and IsAdvance(Call, Recv) then
      begin
        AdvPos:= Integer(S.StartByte);
        Break;
      end;
    if AdvPos >= 0 then CheckContinues(Body, Recv, AdvPos, False);
  finally
    Items.Free;
    Facts.Free;
  end;
end;

{ True when assignment A writes a field of the dataset ARecv: Q.FieldByName(..).AsX := .., Q.Fields[..] := ..,
  Q['F'] := .., or the same without the receiver inside "with Q do". }
function TDsAnalysis.IsFieldWrite(const A: TDsAssign; const ARecv: string): Boolean;
begin
  Result:= A.Lhs.StartsWith(ARecv + '.') or A.Lhs.StartsWith(ARecv + '[');
  if (not Result) and (A.WithTop = ARecv) then
    Result:= A.Lhs.StartsWith('fieldbyname(') or A.Lhs.StartsWith('fields');
end;

{ dataset-edit-without-post for one routine's facts. }
procedure TDsAnalysis.CheckEdits(AFacts: TDsFacts);
var
  C, F : TDsCall;
  A    : TDsAssign;
  Done : Boolean;
  Wrote: Boolean;
  Own  : Boolean;
  Cnt  : Integer;
begin
  for C in AFacts.Calls do
  begin
    if (not C.IsStmt) or C.HasArgs or (C.Recv = '') then Continue;
    if not ((C.Meth = 'edit') or (C.Meth = 'append') or (C.Meth = 'insert')) then Continue;
    Wrote:= False;
    for A in AFacts.Assigns do
      if (A.Pos > C.Pos) and IsFieldWrite(A, C.Recv) then Wrote:= True;
    if not Wrote then Continue;
    Done:= AFacts.Args.ContainsKey(C.Recv);
    Own:= False;
    for F in AFacts.Calls do
    begin
      if (F.Pos > C.Pos) and (F.Recv = C.Recv) and InSet(F.Meth, FINISH_METHODS) then Done:= True;
      if (F.Recv = C.Recv) and InSet(F.Meth, FINISH_METHODS) then Own:= True;
    end;
    { T04: a change handler may leave the edit open for a Post / Cancel in another routine of the unit --\r\n      only for a name that denotes the same object there (field / global), never this routine's own parameter or local }
    if (not Done) and (not FDecl.ContainsKey(C.Recv)) and FPosted.TryGetValue(C.Recv, Cnt) and (Cnt - Ord(Own) > 0) then Done:= True;
    if not Done then
      Emit(C.Node, RULE_EDIT, Format('%s.%s starts a record change that is never posted: the routine writes fields but calls neither Post nor Cancel on "%s"', [C.Recv, C.Meth, C.Recv]));
  end;
end;

{ transaction-without-rollback for one routine's facts: a start that is committed later, a try ... except
  at or after the start (the error is caught), and no Rollback on that connection anywhere. }
procedure TDsAnalysis.CheckTransactions(AFacts: TDsFacts);
var
  C, Co, R: TDsCall;
  Tr      : TDsTry;
  Done    : Boolean;
  Wrote   : Boolean;
  Handled : Boolean;
begin
  for C in AFacts.Calls do
  begin
    if (not C.IsStmt) or (not InSet(C.Meth, START_METHODS)) then Continue;
    Done   := AFacts.Args.ContainsKey(C.Recv);
    Wrote  := False;
    Handled:= False;
    for Co in AFacts.Calls do
      if (Co.Pos > C.Pos) and InSet(Co.Meth, COMMIT_METHODS) and RelatedRecv(Co.Recv, C.Recv) then Wrote:= True;
    for Tr in AFacts.Tries do
      if Tr.Last > C.Pos then Handled:= True;
    if (not Wrote) or (not Handled) then Continue;
    for R in AFacts.Calls do
      if InSet(R.Meth, ROLLBACK_METHODS) and RelatedRecv(R.Recv, C.Recv) then Done:= True;
    if not Done then
      Emit(C.Node, RULE_TRANS, Format('Transaction started with %s.%s is committed but never rolled back -- an exception leaves it open; call Rollback in an except or finally part', [C.Recv, C.Meth]));
  end;
end;

{ Gathers the lower-cased names of the parameters and locals declared in one routine (not in nested routines). }
procedure TDsAnalysis.CollectDecls(const N: TTSNode);
var
  I, J: Integer;
  Ch  : TTSNode;
  Lim : Cardinal;
  Typ : TTSNode;
begin
  if N.IsNull then Exit;
  if (N.NodeType = 'declVar') or (N.NodeType = 'declArg') then
  begin
    Typ:= N.ChildByField('type');
    Lim:= if Typ.IsNull then High(Cardinal) else Typ.StartByte;
    for J:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(J);
      if (Ch.NodeType = 'identifier') and (Ch.StartByte < Lim) then FDecl.AddOrSetValue(Norm(Ch), True);
    end;
    Exit;
  end;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    Ch:= N.NamedChild(I);
    if (Ch.NodeType = 'block') or (Ch.NodeType = 'defProc') then Continue;
    CollectDecls(Ch);
  end;
end;

procedure TDsAnalysis.AnalyzeRoutine(const N: TTSNode);
var
  Facts: TDsFacts;
begin
  Facts:= TDsFacts.Create;
  FDecl.Clear;
  CollectDecls(N);
  try
    Collect(N.ChildByField('body'), Facts, False);
    if FWanted(RULE_EDIT) then CheckEdits(Facts);
    if FWanted(RULE_TRANS) then CheckTransactions(Facts);
  finally
    Facts.Free;
  end;
end;

procedure TDsAnalysis.Visit(const N: TTSNode);
var
  I      : Integer;
  T      : string;
  Saved  : TList<string>;
  Pushed : Boolean;
  Ent    : TTSNode;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  Saved := nil;
  Pushed:= False;
  if T = 'defProc' then
  begin
    Saved := FWith;
    FWith := TList<string>.Create;
    AnalyzeRoutine(N);
  end
  else if (T = 'while') or (T = 'repeat') then
    AnalyzeLoop(N)
  else if T = 'with' then
  begin
    Ent:= N.ChildByField('entity');
    FWith.Add(if Ent.IsNull then '' else Norm(Ent));
    Pushed:= True;
  end;
  try
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  finally
    if Pushed then FWith.Delete(FWith.Count - 1);
    if Saved <> nil then
    begin
      FWith.Free;
      FWith:= Saved;
    end;
  end;
end;

{ Counts, per receiver, the routines of the file that call Post / Cancel / ... on it (T04). }
procedure TDsAnalysis.PreScanPosts(const N: TTSNode);
var
  I    : Integer;
  Facts: TDsFacts;
  C    : TDsCall;
  Seen : TList<string>;
  Cnt  : Integer;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then
  begin
    Facts:= TDsFacts.Create;
    Seen := TList<string>.Create;
    try
      Collect(N.ChildByField('body'), Facts, False);
      for C in Facts.Calls do
        if (C.Recv <> '') and InSet(C.Meth, FINISH_METHODS) and (not Seen.Contains(C.Recv)) then
        begin
          Seen.Add(C.Recv);
          if not FPosted.TryGetValue(C.Recv, Cnt) then Cnt:= 0;
          FPosted.AddOrSetValue(C.Recv, Cnt + 1);
        end;
    finally
      Seen.Free;
      Facts.Free;
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do PreScanPosts(N.NamedChild(I));
end;

function TDsAnalysis.Run(const ARoot: TTSNode): TArray<TLintFinding>;
begin
  if FWanted(RULE_EDIT) then PreScanPosts(ARoot);
  Visit(ARoot);
  Result:= FFindings.ToArray;
end;

function DsCheckFile(const AFile: string; const AWanted: TFunc<string, Boolean>): TArray<TLintFinding>;
var
  PF : TParsedFile;
  Run: TDsAnalysis;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Run:= TDsAnalysis.Create(AFile, PF.Src, AWanted);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

end.
