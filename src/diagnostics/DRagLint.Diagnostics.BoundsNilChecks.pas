unit DRagLint.Diagnostics.BoundsNilChecks;

{ Gap-rules wave (plan 2026-10-27-rule-gaps-and-compliance-plan.md), lane G5.
  The ids are already in LINT_GATE_BOUNDS_NIL (CLI.pas) and in
  TRuleCatalog.BuiltinRegistry -- this lane registers nothing in CLI.pas or
  RuleCatalog.pas.
  Rules (pure AST, no symbol store needed):
    nil-check-after-dereference : in ONE block, a statement dereferences an
                           identifier (X.member, X[i], X^) and a LATER statement
                           of the same block tests it (Assigned(X), X <> nil,
                           X = nil) with no assignment to X between. Only simple
                           statements count as the dereference (an `if` that
                           guards the use is not one); X.Free / Destroy / Release
                           are not dereferences for this rule. warning.
    address-of-local-returned : `Result := @L`, `Exit(@L)`, and the casts
                           PChar/PAnsiChar/PWideChar/Pointer(L) of a string or
                           static-array local, where L is a routine local or a
                           BY-VALUE parameter. var/const/out parameters and
                           globals are the non-hit. warning.
    constant-index-out-of-range : A[<literal>] where A is a local, field or
                           const of this file declared array[lo..hi] of and the
                           literal lies outside lo..hi; S[0] where S is a
                           (1-based) string. A name declared with two different
                           shapes in the file is ambiguous and stays silent. warning.
    copy-paste-assignment : OFF. A run of >= 3 consecutive `A.p := B.q`
                           assignments (same A, same B) where all rows but one
                           have p = q and the odd row repeats another row's q; a
                           2-row run is a hit only when the two lhs members are a
                           known axis pair (Left/Top, Width/Height, X/Y, Min/Max).
                           hint. Fixable (risky): the odd rhs member becomes p. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the BoundsNilChecks rules of the gap-rules wave (G5).</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_BOUNDS_NIL). All four rules are emitted on every
  /// call; the CLI filters by --rule and by the enabled set (copy-paste-assignment
  /// is OFF by default).
  /// </remarks>
  TBoundsNilChecker = class
  public
    /// <summary>Runs the BoundsNilChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (unused: the rules have no thresholds).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index (unused: store-free rules).</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , System.RegularExpressions
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  ;

const
  MAX_FINDINGS = 200;
  MIN_RUN_ROWS = 3;
  RULE_NIL_CHECK = 'nil-check-after-dereference';
  RULE_ADDR_LOCAL = 'address-of-local-returned';
  RULE_CONST_INDEX = 'constant-index-out-of-range';
  RULE_COPY_PASTE = 'copy-paste-assignment';
  { Members whose call is not a use of the object for nil-check-after-dereference. }
  RELEASE_MEMBERS: array[0..3] of string = ('free', 'destroy', 'disposeof', 'release');
  { Axis-pair lhs members: a 2-row copy-paste run is a hit only for these. }
  AXIS_PAIRS: array[0..3] of array[0..1] of string = (
    ('left', 'top'), ('width', 'height'), ('x', 'y'), ('min', 'max'));
  STRING_TYPES: array[0..4] of string = (
    'string', 'unicodestring', 'ansistring', 'rawbytestring', 'widestring');
  CAST_NAMES: array[0..3] of string = ('pchar', 'pansichar', 'pwidechar', 'pointer');
  ARRAY_TYPE_PATTERN = '^(?:packed\s+)?array\s*\[\s*(-?\d+)\s*\.\.\s*(-?\d+)\s*\]\s*of\b';

type
  { What a declaration says about one name, as far as the rules care. }
  TDeclKind = (dkOther, dkString, dkArray);

  TDeclInfo = record
    Kind   : TDeclKind;
    Lo     : Integer;
    Hi     : Integer;
    ByRef  : Boolean;  { var / const / out / constref parameter }
    IsParam: Boolean;
    Ambig  : Boolean;  { the file declares the name with different shapes }
  end;

  { One assignment row of a copy-paste run. }
  TCopyRow = record
    Node : TTSNode;
    LBase: string;
    P    : string;
    RBase: string;
    Q    : string;
  end;

  { One walk over one parsed file. Private to this unit. }
  TBnRun = class
  strict private
    FSrc     : TBytes;
    FFile    : string;
    FFindings: TList<TLintFinding>;
    FGlobals : TDictionary<string, TDeclInfo>;
    FScopes  : TObjectList<TDictionary<string, TDeclInfo>>;
    function Txt(const N: TTSNode): string;
    function IsTrivia(const N: TTSNode): Boolean;
    procedure EmitAt(const ANode: TTSNode; const ARuleId, AMessage, ASeverity: string);
    function BareIdent(const N: TTSNode): string;
    function OperatorType(const N: TTSNode): string;
    function IsTypeLikeName(const AName: string): Boolean;
    function ClassifyType(const ATypeText: string; out ALo, AHi: Integer): TDeclKind;
    procedure NamesBefore(const ADecl, AType: TTSNode; AList: TList<string>);
    procedure AddDecl(ADict: TDictionary<string, TDeclInfo>; const AName: string; const AInfo: TDeclInfo; AMergeAmbig: Boolean);
    procedure RecordDecl(const ADecl: TTSNode; ADict: TDictionary<string, TDeclInfo>; AMergeAmbig: Boolean);
    procedure CollectGlobals(const N: TTSNode);
    function BuildScope(const AProc: TTSNode): TDictionary<string, TDeclInfo>;
    function Lookup(const AName: string; out AInfo: TDeclInfo): Boolean;
    procedure CheckSubscript(const N: TTSNode);
    function IsAddrOfLocal(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
    function IsPointerCastOfLocal(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
    function AddressTarget(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
    procedure ScanReturns(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>);
    procedure CheckProc(const AProc: TTSNode);
    procedure CollectDerefs(const N: TTSNode; ASet: TDictionary<string, Boolean>);
    procedure CollectNilChecks(const N: TTSNode; ASet: TDictionary<string, TTSNode>);
    procedure CollectAssigned(const N: TTSNode; ASet: TDictionary<string, Boolean>);
    procedure CheckNilBlock(const ABlock: TTSNode);
    procedure FlushCopyRun(ARows: TList<TCopyRow>);
    function IsMemberCopy(const N: TTSNode): Boolean;
    procedure CheckCopyBlock(const ABlock: TTSNode);
    procedure Visit(const N: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

constructor TBnRun.Create(const AFile: string; const ASrc: TBytes);
begin
  inherited Create;
  FFile:= AFile;
  FSrc := ASrc;
  FFindings:= TList<TLintFinding>.Create;
  FGlobals := TDictionary<string, TDeclInfo>.Create;
  FScopes  := TObjectList<TDictionary<string, TDeclInfo>>.Create(True);
end;

destructor TBnRun.Destroy;
begin
  FScopes.Free;
  FGlobals.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TBnRun.Txt(const N: TTSNode): string;
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

function TBnRun.IsTrivia(const N: TTSNode): Boolean;
var
  T: string;
begin
  T:= N.NodeType;
  Result:= (T = 'comment') or (T = 'pp')
    or ((Length(T) > 1) and (T[1] = 'k') and CharInSet(T[2], ['A'..'Z']));
end;

procedure TBnRun.EmitAt(const ANode: TTSNode; const ARuleId, AMessage, ASeverity: string);
var
  P: TTSPoint;
  F: TLintFinding;
begin
  if FFindings.Count >= MAX_FINDINGS then Exit;
  P:= ANode.StartPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARuleId;
  F.Severity := ASeverity;
  F.Message  := AMessage;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := Integer(P.Column) + 1;
  F.EndLine  := F.StartLine;
  F.EndCol   := F.StartCol + Length(Trim(Txt(ANode)));
  FFindings.Add(F);
end;

{ The lower-cased text of N when it is a bare identifier (parentheses peeled), else ''. }
function TBnRun.BareIdent(const N: TTSNode): string;
var
  C: TTSNode;
begin
  Result:= '';
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then Exit(LowerCase(Txt(N)));
  if (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) then
  begin
    C:= N.NamedChild(0);
    if C.NodeType = 'identifier' then Result:= LowerCase(Txt(C));
  end;
end;

function TBnRun.OperatorType(const N: TTSNode): string;
var
  O: TTSNode;
begin
  Result:= '';
  O:= N.ChildByField('operator');
  if not O.IsNull then Result:= O.NodeType;
end;

{ `TFoo.Create` / `TFoo.ClassName`: the left side is a type (T + capital), not an object that could be nil. }
function TBnRun.IsTypeLikeName(const AName: string): Boolean;
begin
  Result:= (Length(AName) > 1) and (AName[1] = 'T') and CharInSet(AName[2], ['A'..'Z']);
end;

function TBnRun.ClassifyType(const ATypeText: string; out ALo, AHi: Integer): TDeclKind;
var
  T: string;
  M: TMatch;
  S: string;
begin
  ALo:= 0;
  AHi:= -1;
  Result:= dkOther;
  T:= LowerCase(Trim(ATypeText));
  for S in STRING_TYPES do
    if T = S then Exit(dkString);
  M:= TRegEx.Match(T, ARRAY_TYPE_PATTERN);
  if M.Success then
  begin
    ALo:= StrToIntDef(M.Groups[1].Value, 0);
    AHi:= StrToIntDef(M.Groups[2].Value, -1);
    Result:= dkArray;
  end;
end;

{ The identifiers that name a declaration: its children before the type node. }
procedure TBnRun.NamesBefore(const ADecl, AType: TTSNode; AList: TList<string>);
var
  I: Integer;
  C: TTSNode;
  Limit: Cardinal;
begin
  if AType.IsNull then Exit;
  Limit:= AType.StartByte;
  for I:= 0 to ADecl.ChildCount - 1 do
  begin
    C:= ADecl.Child(I);
    if C.StartByte >= Limit then Break;
    if C.NodeType = 'identifier' then AList.Add(LowerCase(Txt(C)));
  end;
end;

procedure TBnRun.AddDecl(ADict: TDictionary<string, TDeclInfo>; const AName: string; const AInfo: TDeclInfo; AMergeAmbig: Boolean);
var
  Old: TDeclInfo;
  New: TDeclInfo;
begin
  New:= AInfo;
  if AMergeAmbig and ADict.TryGetValue(AName, Old) then
  begin
    if Old.Ambig or (Old.Kind <> New.Kind) or (Old.Lo <> New.Lo) or (Old.Hi <> New.Hi) then
    begin
      New.Kind := dkOther;
      New.Ambig:= True;
    end;
  end;
  ADict.AddOrSetValue(AName, New);
end;

procedure TBnRun.RecordDecl(const ADecl: TTSNode; ADict: TDictionary<string, TDeclInfo>; AMergeAmbig: Boolean);
var
  TypeN: TTSNode;
  Names: TList<string>;
  Info : TDeclInfo;
  S    : string;
  I    : Integer;
begin
  TypeN:= ADecl.ChildByField('type');
  Info:= Default(TDeclInfo);
  Info.Kind:= dkOther;
  if not TypeN.IsNull then Info.Kind:= ClassifyType(Txt(TypeN), Info.Lo, Info.Hi);
  if ADecl.NodeType = 'declArg' then
  begin
    Info.IsParam:= True;
    for I:= 0 to ADecl.ChildCount - 1 do
      if (ADecl.Child(I).NodeType = 'kVar') or (ADecl.Child(I).NodeType = 'kConst')
        or (ADecl.Child(I).NodeType = 'kOut') or (ADecl.Child(I).NodeType = 'kConstref') then
        Info.ByRef:= True;
  end;
  Names:= TList<string>.Create;
  try
    if TypeN.IsNull then
    begin
      TypeN:= ADecl.ChildByField('name');
      if not TypeN.IsNull then Names.Add(LowerCase(Txt(TypeN)));
    end
    else
      NamesBefore(ADecl, TypeN, Names);
    for S in Names do
      AddDecl(ADict, S, Info, AMergeAmbig);
  finally
    Names.Free;
  end;
end;

{ File-level view: every var / field / const declared OUTSIDE a routine. }
procedure TBnRun.CollectGlobals(const N: TTSNode);
var
  T: string;
  I: Integer;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') then Exit;
  if (T = 'declVar') or (T = 'declField') or (T = 'declConst') then
  begin
    RecordDecl(N, FGlobals, True);
    Exit;
  end;
  for I:= 0 to N.ChildCount - 1 do CollectGlobals(N.Child(I));
end;

{ The locals and parameters of one routine. }
function TBnRun.BuildScope(const AProc: TTSNode): TDictionary<string, TDeclInfo>;

  procedure Walk(const N: TTSNode);
  var
    T: string;
    I: Integer;
  begin
    if N.IsNull then Exit;
    T:= N.NodeType;
    if (T = 'declVar') or (T = 'declConst') or (T = 'declArg') then
    begin
      RecordDecl(N, Result, False);
      Exit;
    end;
    if (T = 'defProc') or (T = 'lambda') then Exit;
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

  { Inline `var X := ...` / `const X = ...` / `for var X ...`: the type is inferred, so the name only SHADOWS an outer declaration. }
  procedure WalkInline(const N: TTSNode);
  var
    T: string;
    I: Integer;
    Info: TDeclInfo;
  begin
    if N.IsNull then Exit;
    T:= N.NodeType;
    if (T = 'defProc') or (T = 'lambda') then Exit;
    if (T = 'varDef') or (T = 'varAssignDef') or (T = 'constInline') then
    begin
      Info:= Default(TDeclInfo);
      for I:= 0 to N.ChildCount - 1 do
        if N.Child(I).NodeType = 'identifier' then Result.AddOrSetValue(LowerCase(Txt(N.Child(I))), Info);
    end;
    for I:= 0 to N.ChildCount - 1 do WalkInline(N.Child(I));
  end;
var
  I: Integer;
  T: string;
begin
  Result:= TDictionary<string, TDeclInfo>.Create;
  Walk(AProc.ChildByField('header'));
  WalkInline(AProc.ChildByField('body'));
  for I:= 0 to AProc.ChildCount - 1 do
  begin
    T:= AProc.Child(I).NodeType;
    if (T = 'declVars') or (T = 'declConsts') then Walk(AProc.Child(I));
  end;
end;

function TBnRun.Lookup(const AName: string; out AInfo: TDeclInfo): Boolean;
var
  I: Integer;
begin
  for I:= FScopes.Count - 1 downto 0 do
    if FScopes[I].TryGetValue(AName, AInfo) then Exit(True);
  Result:= FGlobals.TryGetValue(AName, AInfo);
end;

{ ---- constant-index-out-of-range ---------------------------------------- }

procedure TBnRun.CheckSubscript(const N: TTSNode);
var
  Ent, Args, Arg, Opd: TTSNode;
  Name, Lit: string;
  Info: TDeclInfo;
  Idx: Integer;
  Neg: Boolean;
begin
  Ent:= N.ChildByField('entity');
  Args:= N.ChildByField('args');
  if Ent.IsNull or Args.IsNull or (Ent.NodeType <> 'identifier') then Exit;
  if Args.NamedChildCount <> 1 then Exit;
  Arg:= Args.NamedChild(0);
  Neg:= False;
  if (Arg.NodeType = 'exprUnary') and (OperatorType(Arg) = 'kSub') then
  begin
    Opd:= Arg.ChildByField('operand');
    Neg:= True;
    Arg:= Opd;
  end;
  if Arg.IsNull or (Arg.NodeType <> 'literalNumber') then Exit;
  Lit:= Txt(Arg);
  if not TRegEx.IsMatch(Lit, '^-?\d{1,9}$') then Exit;
  Idx:= StrToInt(Lit);
  if Neg then Idx:= -Idx;
  Name:= LowerCase(Txt(Ent));
  if not Lookup(Name, Info) then Exit;  // dl:ok used-before-assignment@945b -- REVIEWED 2026-10-28: Info is an out parameter of Lookup, assigned on every path
  case Info.Kind of
    dkArray:
      if (Idx < Info.Lo) or (Idx > Info.Hi) then
        EmitAt(N, RULE_CONST_INDEX,
          Format('Index %d is outside the declared bounds %d..%d of %s -- range error or memory overrun',
            [Idx, Info.Lo, Info.Hi, Txt(Ent)]), 'warning');
    dkString:
      if Idx = 0 then
        EmitAt(N, RULE_CONST_INDEX,
          Format('Strings are 1-based: %s[0] is out of range', [Txt(Ent)]), 'warning');
  end;
end;

{ ---- address-of-local-returned ------------------------------------------ }

{ True when N is `@L` of a routine-owned, non-reference location. }
function TBnRun.IsAddrOfLocal(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
var
  Name: string;
  Info: TDeclInfo;
begin
  Name:= BareIdent(N.ChildByField('operand'));
  Result:= (Name <> '') and ALocals.TryGetValue(Name, Info) and not Info.ByRef;
end;

{ True when N is `PChar(L)` / `Pointer(L)` ... of a string or static-array routine-owned local. }
function TBnRun.IsPointerCastOfLocal(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
var
  Args: TTSNode;
  Name, Cast, C: string;
  Info: TDeclInfo;
begin
  Result:= False;
  Args:= N.ChildByField('args');
  if not Args.IsNull and (Args.NamedChildCount = 1) then
  begin
    Cast:= BareIdent(N.ChildByField('entity'));
    Name:= BareIdent(Args.NamedChild(0));
    if (Cast <> '') and (Name <> '') then
      for C in CAST_NAMES do
        if C = Cast then
          Result:= ALocals.TryGetValue(Name, Info) and not Info.ByRef and (Info.Kind <> dkOther);
  end;
end;

{ True when N is `@L` / `PChar(L)` ... of a routine-owned storage location. }
function TBnRun.AddressTarget(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) then
    Result:= AddressTarget(N.NamedChild(0), ALocals)
  else if (N.NodeType = 'exprUnary') and (OperatorType(N) = 'kAt') then
    Result:= IsAddrOfLocal(N, ALocals)
  else if N.NodeType = 'exprCall' then
    Result:= IsPointerCastOfLocal(N, ALocals);
end;
procedure TBnRun.ScanReturns(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>);
var
  T, Callee: string;
  I: Integer;
  Lhs, Args, Ent: TTSNode;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') then Exit;
  if T = 'assignment' then
  begin
    Lhs:= N.ChildByField('lhs');
    if (BareIdent(Lhs) = 'result') and AddressTarget(N.ChildByField('rhs'), ALocals) then
      EmitAt(N, RULE_ADDR_LOCAL,
        'Address of a local variable or by-value parameter is returned -- it dangles once the routine exits', 'warning');
  end
  else if T = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    Args:= N.ChildByField('args');
    Callee:= BareIdent(Ent);
    if (Callee = 'exit') and not Args.IsNull and (Args.NamedChildCount = 1)
      and AddressTarget(Args.NamedChild(0), ALocals) then
      EmitAt(N, RULE_ADDR_LOCAL,
        'Address of a local variable or by-value parameter is returned -- it dangles once the routine exits', 'warning');
  end;
  for I:= 0 to N.ChildCount - 1 do ScanReturns(N.Child(I), ALocals);
end;

procedure TBnRun.CheckProc(const AProc: TTSNode);
var
  Locals: TDictionary<string, TDeclInfo>;
begin
  { Only a function can return an address: its header carries a return type. }
  if AProc.ChildByField('header').ChildByField('type').IsNull then Exit;
  Locals:= FScopes[FScopes.Count - 1];
  ScanReturns(AProc.ChildByField('body'), Locals);
end;

{ ---- nil-check-after-dereference ---------------------------------------- }

procedure TBnRun.CollectDerefs(const N: TTSNode; ASet: TDictionary<string, Boolean>);
var
  T, Name, RawName, Member, R: string;
  I: Integer;
  Skip: Boolean;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'lambda') or (T = 'defProc') then Exit;
  Name:= '';
  if T = 'exprDot' then
  begin
    Name:= BareIdent(N.ChildByField('lhs'));
    RawName:= Txt(N.ChildByField('lhs'));
    Member:= LowerCase(Txt(N.ChildByField('rhs')));
    Skip:= False;
    for R in RELEASE_MEMBERS do
      if R = Member then Skip:= True;
    if Skip then Name:= '';
  end
  else if T = 'exprSubscript' then
  begin
    Name:= BareIdent(N.ChildByField('entity'));
    RawName:= Txt(N.ChildByField('entity'));
  end
  else if (T = 'exprUnary') and (OperatorType(N) = 'kHat') then
  begin
    Name:= BareIdent(N.ChildByField('operand'));
    RawName:= Txt(N.ChildByField('operand'));
  end;
  if (Name <> '') and (Name <> 'self') and (Name <> 'inherited') and not IsTypeLikeName(RawName) then
    ASet.AddOrSetValue(Name, True);
  for I:= 0 to N.ChildCount - 1 do CollectDerefs(N.Child(I), ASet);
end;

procedure TBnRun.CollectNilChecks(const N: TTSNode; ASet: TDictionary<string, TTSNode>);
var
  T, Name: string;
  I: Integer;
  L, R, Args: TTSNode;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'lambda') or (T = 'defProc') then Exit;
  if T = 'exprCall' then
  begin
    if SameText(BareIdent(N.ChildByField('entity')), 'assigned') then
    begin
      Args:= N.ChildByField('args');
      if not Args.IsNull and (Args.NamedChildCount = 1) then
      begin
        Name:= BareIdent(Args.NamedChild(0));
        if Name <> '' then ASet.AddOrSetValue(Name, N);
      end;
    end;
  end
  else if (T = 'exprBinary') and ((OperatorType(N) = 'kEq') or (OperatorType(N) = 'kNeq')) then
  begin
    L:= N.ChildByField('lhs');
    R:= N.ChildByField('rhs');
    if (R.NodeType = 'kNil') and (BareIdent(L) <> '') then ASet.AddOrSetValue(BareIdent(L), N)
    else if (L.NodeType = 'kNil') and (BareIdent(R) <> '') then ASet.AddOrSetValue(BareIdent(R), N);
  end;
  for I:= 0 to N.ChildCount - 1 do CollectNilChecks(N.Child(I), ASet);
end;

{ Identifiers assigned anywhere in N (`X := ...`) or passed to FreeAndNil. }
procedure TBnRun.CollectAssigned(const N: TTSNode; ASet: TDictionary<string, Boolean>);
var
  T, Name: string;
  I: Integer;
  Args: TTSNode;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'lambda') or (T = 'defProc') then Exit;
  if T = 'assignment' then
  begin
    Name:= BareIdent(N.ChildByField('lhs'));
    if Name <> '' then ASet.AddOrSetValue(Name, True);
  end
  else if (T = 'exprCall') and SameText(BareIdent(N.ChildByField('entity')), 'freeandnil') then
  begin
    Args:= N.ChildByField('args');
    if not Args.IsNull and (Args.NamedChildCount = 1) then
    begin
      Name:= BareIdent(Args.NamedChild(0));
      if Name <> '' then ASet.AddOrSetValue(Name, True);
    end;
  end;
  for I:= 0 to N.ChildCount - 1 do CollectAssigned(N.Child(I), ASet);
end;

procedure TBnRun.CheckNilBlock(const ABlock: TTSNode);
var
  Derefd : TDictionary<string, Boolean>;
  Stmt   : TDictionary<string, Boolean>;
  Checks : TDictionary<string, TTSNode>;
  Assigns: TDictionary<string, Boolean>;
  I      : Integer;
  Child  : TTSNode;
  Pair   : TPair<string, TTSNode>;
  Key    : string;
  Simple : Boolean;
  Cond   : TTSNode;
begin
  Derefd := TDictionary<string, Boolean>.Create;
  Checks := TDictionary<string, TTSNode>.Create;
  Assigns:= TDictionary<string, Boolean>.Create;
  Stmt   := TDictionary<string, Boolean>.Create;
  try
    for I:= 0 to ABlock.NamedChildCount - 1 do
    begin
      Child:= ABlock.NamedChild(I);
      if Child.IsNull or IsTrivia(Child) then Continue;
      { 1. a nil test on an identifier dereferenced by an EARLIER statement }
      if (Derefd.Count > 0) and ((Child.NodeType = 'if') or (Child.NodeType = 'ifElse')) then
      begin
        Cond:= Child.ChildByField('condition');
        Checks.Clear;
        CollectNilChecks(Cond, Checks);
        for Pair in Checks do
          if Derefd.ContainsKey(Pair.Key) then
          begin
            EmitAt(Pair.Value, RULE_NIL_CHECK,
              Format('%s is dereferenced earlier in this block and only then tested against nil -- either the use is too early or the check is redundant',
                [Pair.Key]), 'warning');
            Break;
          end;
      end;
      { 2. what this statement dereferences (simple statements only) }
      Simple:= (Child.NodeType = 'statement') or (Child.NodeType = 'assignment');
      if Simple then
      begin
        Stmt.Clear;
        CollectDerefs(Child, Stmt);
        Checks.Clear;
        CollectNilChecks(Child, Checks);
        for Key in Stmt.Keys do
          if not Checks.ContainsKey(Key) then Derefd.AddOrSetValue(Key, True);
      end;
      { 3. an assignment anywhere in the statement forgets the dereference }
      Assigns.Clear;
      CollectAssigned(Child, Assigns);
      for Key in Assigns.Keys do Derefd.Remove(Key);
    end;
  finally
    Stmt.Free;
    Assigns.Free;
    Checks.Free;
    Derefd.Free;
  end;
end;

{ ---- copy-paste-assignment ---------------------------------------------- }

function IsAxisPair(const A, B: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= Low(AXIS_PAIRS) to High(AXIS_PAIRS) do
    if ((A = AXIS_PAIRS[I][0]) and (B = AXIS_PAIRS[I][1]))
      or ((A = AXIS_PAIRS[I][1]) and (B = AXIS_PAIRS[I][0])) then
      Exit(True);
end;

procedure TBnRun.FlushCopyRun(ARows: TList<TCopyRow>);
var
  I, J, OddIdx, OddCount: Integer;
  Hit: Boolean;
begin
  OddIdx:= -1;
  OddCount:= 0;
  if ARows.Count >= 2 then
  begin
    for I:= 0 to ARows.Count - 1 do
      if ARows[I].P <> ARows[I].Q then
      begin
        Inc(OddCount);
        OddIdx:= I;
      end;
    if OddCount = 1 then
    begin
      { EndLine := X.StartLine after StartLine := X.StartLine is a one-line span, not a typo. }
      Hit:= False;
      if not (ARows[OddIdx].P.StartsWith('end') and ARows[OddIdx].Q.StartsWith('start')) then
      for J:= 0 to ARows.Count - 1 do
        if (J <> OddIdx) and (ARows[J].Q = ARows[OddIdx].Q)
          and ((ARows.Count >= MIN_RUN_ROWS) or IsAxisPair(ARows[OddIdx].P, ARows[J].P)) then Hit:= True;
      if Hit then
        EmitAt(ARows[OddIdx].Node, RULE_COPY_PASTE,
          Format('Assignment copies "%s.%s" like the row above/below -- likely a copy-paste typo (expected %s.%s)',
            [ARows[OddIdx].RBase, ARows[OddIdx].Q, ARows[OddIdx].RBase, ARows[OddIdx].P]), 'hint');
    end;
  end;
  ARows.Clear;
end;

{ `A.p := B.q`: a plain assignment whose both sides are a member access with a simple member name. }
function TBnRun.IsMemberCopy(const N: TTSNode): Boolean;
var
  Lhs, Rhs: TTSNode;
begin
  Lhs:= N.ChildByField('lhs');
  Rhs:= N.ChildByField('rhs');
  Result:= (N.NodeType = 'assignment') and (OperatorType(N) = 'kAssign')
    and (Lhs.NodeType = 'exprDot') and (Rhs.NodeType = 'exprDot');
  if Result then
    Result:= (Lhs.ChildByField('rhs').NodeType = 'identifier') and (Rhs.ChildByField('rhs').NodeType = 'identifier');
end;

procedure TBnRun.CheckCopyBlock(const ABlock: TTSNode);
var
  Rows: TList<TCopyRow>;
  I   : Integer;
  Child, Lhs, Rhs: TTSNode;
  Row : TCopyRow;
begin
  Rows:= TList<TCopyRow>.Create;
  try
    for I:= 0 to ABlock.NamedChildCount - 1 do
    begin
      Child:= ABlock.NamedChild(I);
      if Child.IsNull or IsTrivia(Child) then Continue;
      Lhs:= Child.ChildByField('lhs');
      Rhs:= Child.ChildByField('rhs');
      if IsMemberCopy(Child) then
      begin
        Row.Node := Child;
        Row.LBase:= LowerCase(Txt(Lhs.ChildByField('lhs')));
        Row.P    := LowerCase(Txt(Lhs.ChildByField('rhs')));
        Row.RBase:= LowerCase(Txt(Rhs.ChildByField('lhs')));
        Row.Q    := LowerCase(Txt(Rhs.ChildByField('rhs')));
        if (Rows.Count > 0) and ((Rows[0].LBase <> Row.LBase) or (Rows[0].RBase <> Row.RBase)) then FlushCopyRun(Rows);
        Rows.Add(Row);
      end
      else
        FlushCopyRun(Rows);
    end;
    FlushCopyRun(Rows);
  finally
    Rows.Free;
  end;
end;

{ ---- the walk ------------------------------------------------------------ }

procedure TBnRun.Visit(const N: TTSNode);
var
  T: string;
  I: Integer;
  Pushed: Boolean;
begin
  if N.IsNull or (FFindings.Count >= MAX_FINDINGS) then Exit;
  T:= N.NodeType;
  Pushed:= False;
  if T = 'defProc' then
  begin
    FScopes.Add(BuildScope(N));
    Pushed:= True;
    CheckProc(N);
  end
  else if (T = 'block') or (T = 'statements') then
  begin
    CheckNilBlock(N);
    CheckCopyBlock(N);
  end
  else if T = 'exprSubscript' then
    CheckSubscript(N);
  for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  if Pushed then FScopes.Delete(FScopes.Count - 1);
end;

function TBnRun.Run(const ARoot: TTSNode): TArray<TLintFinding>;
begin
  CollectGlobals(ARoot);
  Visit(ARoot);
  Result:= FFindings.ToArray;
end;

{ ---- the checker entry point -------------------------------------------- }

class function TBoundsNilChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@0855 -- REVIEWED 2026-10-27: signature fixed by the shared checker shape (LINT_GATE_BOUNDS_NIL call sites); the rules are threshold-free
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;  // dl:ok unused-parameter@9a67 -- REVIEWED 2026-10-27: signature fixed by the shared checker shape; the rules are store-free
var
  PF : TParsedFile;
  Run: TBnRun;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Run:= TBnRun.Create(AFile, PF.Src);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

{ ---- the copy-paste-assignment fixer ------------------------------------ }

{ Rewrites the odd row's right-hand member to the left-hand member:
  `R.Top := A.Left` -> `R.Top := A.Top`. Single-line assignments only. }
function FixCopyPasteAssignment(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line, Span, Lhs, Rhs, PMember, RPrefix, NewRhs: string;
  AssignAt, RhsStart, DotL, DotR: Integer;
  E: TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  Span:= Copy(Line, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  AssignAt:= Pos(':=', Span);
  if AssignAt < 2 then Exit;
  Lhs:= Trim(Copy(Span, 1, AssignAt - 1));
  Rhs:= Trim(Copy(Span, AssignAt + 2, MaxInt));
  DotL:= LastDelimiter('.', Lhs);
  DotR:= LastDelimiter('.', Rhs);
  if (DotL < 2) or (DotR < 2) then Exit;
  PMember:= Copy(Lhs, DotL + 1, MaxInt);
  RPrefix:= Copy(Rhs, 1, DotR);
  NewRhs:= RPrefix + PMember;
  if SameText(NewRhs, Rhs) then Exit;
  RhsStart:= AFinding.StartCol + AssignAt + 1;
  while (RhsStart <= Length(Line)) and (Line[RhsStart] = ' ') do Inc(RhsStart);
  E:= Default(TTextEdit);
  E.FilePath  := AFinding.FilePath;
  E.Kind      := tekReplaceInLine;
  E.Line      := AFinding.StartLine;
  E.Col       := RhsStart;
  E.EndCol    := RhsStart + Length(Rhs);
  E.Text      := NewRhs;
  E.ExpectText:= Rhs;
  Result:= [E];
end;

initialization
  RegisterFixer(RULE_COPY_PASTE, FixCopyPasteAssignment, True);

end.
