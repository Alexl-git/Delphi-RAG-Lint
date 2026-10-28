unit DRagLint.Diagnostics.ModernizeChecks;

{ Clippy-parity wave (plan 2026-10-27-clippy-rules-plan.md), lane L12.
  L0 shipped this unit as a STUB: Check returns nil. The lane replaces the body
  and adds the emitted ids to LINT_GATE_MODERNIZE's checker (the ids are already
  in the gate list and in TRuleCatalog.BuiltinRegistry -- a lane registers
  nothing new in CLI.pas or RuleCatalog.pas).
  Rules: index-loop-to-for-in. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the index-loop-to-for-in rules. Flags ascending zero-based index loops that only read Items[I].</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_MODERNIZE).
  /// </remarks>
  TModernizeChecker = class
  public
    /// <summary>Runs the ModernizeChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (thresholds via ThresholdFor).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  ;

const
  HIGH_PREFIX   = 'high(';
  LENGTH_PREFIX = 'length(';
  LENGTH_SUFFIX = ')-1';
  COUNT_SUFFIX  = '.count-1';
  ITEMS_SUFFIX  = '.items';
  { Methods that change a container's size or order: a loop body calling one is not a pure read. }
  MUTATOR_METHODS: array[0..9] of string = ('add', 'addrange', 'insert', 'delete', 'deleterange',
    'remove', 'removeat', 'extract', 'clear', 'setcount');
  { RTL routines that resize or edit their first argument in place. }
  MUTATOR_ROUTINES: array[0..2] of string = ('setlength', 'delete', 'insert');

type
  /// <summary>Per-loop state shared by the body scan helpers.</summary>
  TLoopCtx = record
    Src      : TBytes ;
    LoopVar  : string ;
    Container: string ;
    UseCount : Integer;
    Bad      : Boolean;
  end;

function NodeText(const ASrc: TBytes; const N: TTSNode): string;
var
  S, E: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  E:= Integer(N.EndByte);
  if (E <= S) or (S < 0) or (E > Length(ASrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASrc, S, E - S);
end;

{ Lower-cased text with every blank removed, for shape comparison. }
function Squash(const S: string): string;
var
  C : Char;
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    for C in S do
      if not CharInSet(C, [' ', #9, #10, #13]) then SB.Append(LowerCase(C));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ True when AText is a plain identifier / dotted chain (no calls, no indexes). }
function IsPlainChain(const AText: string): Boolean;
var
  C: Char;
begin
  Result:= AText <> '';
  for C in AText do
    if not CharInSet(C, ['a'..'z', '0'..'9', '_', '.']) then Exit(False);
end;

{ Splits a squashed upper bound High(X) / Length(X)-1 / X.Count-1 into X. }
function ParseBound(const ABound: string; out AContainer: string): Boolean;
begin
  AContainer:= '';
  if StartsStr(HIGH_PREFIX, ABound) and EndsStr(')', ABound) then
    AContainer:= Copy(ABound, Length(HIGH_PREFIX) + 1, Length(ABound) - Length(HIGH_PREFIX) - 1)
  else if StartsStr(LENGTH_PREFIX, ABound) and EndsStr(LENGTH_SUFFIX, ABound) then
    AContainer:= Copy(ABound, Length(LENGTH_PREFIX) + 1,
      Length(ABound) - Length(LENGTH_PREFIX) - Length(LENGTH_SUFFIX))
  else if EndsStr(COUNT_SUFFIX, ABound) then
    AContainer:= Copy(ABound, 1, Length(ABound) - Length(COUNT_SUFFIX));
  Result:= IsPlainChain(AContainer);
end;

function SameSpan(const A, B: TTSNode): Boolean;
begin
  Result:= (not A.IsNull) and (not B.IsNull) and (A.StartByte = B.StartByte) and (A.EndByte = B.EndByte);
end;

{ True when the subscript N (possibly under .Field / [..] chains) is written to. }
function IsWriteTarget(const N: TTSNode): Boolean;
var
  Cur, P: TTSNode;
begin
  Cur:= N;
  P:= Cur.Parent;
  while (not P.IsNull) and ((P.NodeType = 'exprDot') or (P.NodeType = 'exprSubscript')) do
  begin
    Cur:= P;
    P:= Cur.Parent;
  end;
  Result:= (not P.IsNull) and (P.NodeType = 'assignment') and SameSpan(P.ChildByField('lhs'), Cur);
end;

{ True when the call/expression N resizes or edits the loop's container: C.Add(..),
  C.Delete(..), C.Clear, SetLength(C, ..). Such a body can raise or skip items when
  rewritten as for-in, so the loop is left alone. }
function MutatesContainer(const N: TTSNode; const ACtx: TLoopCtx): Boolean;
var
  Ent, Name: string;
  Args: TTSNode;
begin
  Result:= False;
  if N.NodeType = 'exprCall' then
    Ent:= Squash(NodeText(ACtx.Src, N.ChildByField('entity')))
  else if N.NodeType = 'exprDot' then
    Ent:= Squash(NodeText(ACtx.Src, N))
  else Exit;
  if StartsStr(ACtx.Container + '.', Ent) then
  begin
    Name:= Copy(Ent, Length(ACtx.Container) + 2, MaxInt);
    Exit(MatchStr(Name, MUTATOR_METHODS));
  end;
  if (N.NodeType = 'exprCall') and MatchStr(Ent, MUTATOR_ROUTINES) then
  begin
    Args:= N.ChildByField('args');
    Result:= (not Args.IsNull) and (Args.NamedChildCount > 0)
      and (Squash(NodeText(ACtx.Src, Args.NamedChild(0))) = ACtx.Container);
  end;
end;
{ Walks the loop body: every mention of the loop variable must be the sole
  index of a read-only C[I] / C.Items[I]; anything else marks the loop Bad. }
procedure ScanBody(const N: TTSNode; var ACtx: TLoopCtx);
var
  I   : Integer;
  Ent : string;
  Args: TTSNode;
  IsIdx: Boolean;
begin
  if ACtx.Bad or N.IsNull then Exit;
  if MutatesContainer(N, ACtx) then
  begin
    ACtx.Bad:= True;
    Exit;
  end;
  if N.NodeType = 'identifier' then
  begin
    if SameText(NodeText(ACtx.Src, N), ACtx.LoopVar) then ACtx.Bad:= True;
    Exit;
  end;
  if N.NodeType = 'exprSubscript' then
  begin
    Ent := Squash(NodeText(ACtx.Src, N.ChildByField('entity')));
    Args:= N.ChildByField('args');
    IsIdx:= (not Args.IsNull) and (Args.NamedChildCount = 1)
      and (Args.NamedChild(0).NodeType = 'identifier')
      and SameText(NodeText(ACtx.Src, Args.NamedChild(0)), ACtx.LoopVar);
    if IsIdx and ((Ent = ACtx.Container) or (Ent = ACtx.Container + ITEMS_SUFFIX)) then
    begin
      if IsWriteTarget(N) then ACtx.Bad:= True else Inc(ACtx.UseCount);
      Exit;
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanBody(N.NamedChild(I), ACtx);
end;

{ True when AName is mentioned at or after AFromByte, other than as the
  counter of another for loop (which re-initialises it). }
function ReadsAfter(const ASrc: TBytes; const N: TTSNode; const AName: string;
  AFromByte: Cardinal): Boolean;
var
  I: Integer;
  P: TTSNode;
begin
  Result:= False;
  if N.IsNull or (N.EndByte <= AFromByte) then Exit;
  if (N.NodeType = 'identifier') and (N.StartByte >= AFromByte)
    and SameText(NodeText(ASrc, N), AName) then
  begin
    P:= N.Parent;
    Exit(not ((not P.IsNull) and (P.NodeType = 'assignment') and (not P.Parent.IsNull)
      and (P.Parent.NodeType = 'for') and SameSpan(P.ChildByField('lhs'), N)));
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    if ReadsAfter(ASrc, N.NamedChild(I), AName, AFromByte) then Exit(True);
end;

class function TModernizeChecker.Check(const AFile: string; const ACfg: TLintConfig; // dl:ok unused-parameter@2dbb -- fixed signature shared by every built-in checker; this rule is AST-only
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; // dl:ok unused-parameter@9a67 -- fixed checker signature
var
  PF      : TParsedFile;
  Findings: TArray<TLintFinding>;

  procedure CheckFor(const F: TTSNode); // dl:ok too-many-exit-points@f114 -- a chain of shape guards; each Exit is a distinct 'not our pattern' bail-out
  var
    Start, Lhs, BodyN, Scope: TTSNode;
    Ctx     : TLoopCtx;
    IsInline: Boolean;
    I       : Integer;
    HasTo   : Boolean;
    LF      : TLintFinding;
  begin
    HasTo:= False;
    for I:= 0 to F.NamedChildCount - 1 do
    begin
      if F.NamedChild(I).NodeType = 'kDownto' then Exit;
      if F.NamedChild(I).NodeType = 'kTo' then HasTo:= True;
    end;
    Start:= F.ChildByField('start');
    if (not HasTo) or Start.IsNull or (Start.NodeType <> 'assignment') then Exit;
    if Squash(NodeText(PF.Src, Start.ChildByField('rhs'))) <> '0' then Exit;
    Ctx:= Default(TLoopCtx);
    Ctx.Src:= PF.Src;
    if not ParseBound(Squash(NodeText(PF.Src, F.ChildByField('end'))), Ctx.Container) then Exit;
    Lhs:= Start.ChildByField('lhs');
    IsInline:= Lhs.NodeType = 'varAssignDef';
    if IsInline then
    begin
      if Lhs.NamedChildCount = 0 then Exit;
      Lhs:= Lhs.NamedChild(Lhs.NamedChildCount - 1);
    end;
    if Lhs.NodeType <> 'identifier' then Exit;
    Ctx.LoopVar:= NodeText(PF.Src, Lhs);
    BodyN:= F.ChildByField('body');
    ScanBody(BodyN, Ctx);
    if Ctx.Bad or (Ctx.UseCount = 0) then Exit;
    if not IsInline then
    begin
      Scope:= F.Parent;
      while (not Scope.IsNull) and (Scope.NodeType <> 'defProc') do Scope:= Scope.Parent;
      if Scope.IsNull then Scope:= PF.Tree.RootNode;
      if ReadsAfter(PF.Src, Scope, Ctx.LoopVar, F.EndByte) then Exit;
    end;
    LF:= Default(TLintFinding);
    LF.RuleId   := 'index-loop-to-for-in';
    LF.Severity := 'hint';
    LF.Message  := Format('Index loop only reads %s[%s] -- use "for ... in %s do"',
      [Ctx.Container, Ctx.LoopVar, Ctx.Container]);
    LF.FilePath := AFile;
    LF.StartLine:= Integer(F.StartPoint.Row) + 1;
    LF.StartCol := Integer(F.StartPoint.Column) + 1;
    LF.EndLine  := Integer(F.EndPoint.Row) + 1;
    LF.EndCol   := Integer(F.EndPoint.Column) + 1;
    Findings:= Findings + [LF];
  end;

  procedure Walk(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.NodeType = 'for' then CheckFor(N);
    for I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;

begin
  Result:= nil;
  Findings:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Walk(PF.Tree.RootNode);
  Result:= Findings;
end;

end.
