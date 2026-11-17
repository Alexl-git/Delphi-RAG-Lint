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
                           hint. Fixable (risky): the odd rhs member becomes p.
    index-possibly-out-of-range : OFF (1.52, spec 2026-11-16-index-possibly-out-of-range-design.md).
                           A[idx] where A is a static or dynamic array and idx a routine local
                           or parameter, with no dominating guard (for over the bounds, if /
                           while condition, InRange, an earlier Exit/raise guard) and no write
                           history bounding idx on BOTH sides. Reported on the nearest write of
                           idx (warning); an unwritten parameter reports on the access (hint).
                           A subrange type is not a guard. Fixable (risky): an InRange guard
                           raising params.index-possibly-out-of-range.exception_class. }

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
  /// LintRuleWants(rule, LINT_GATE_BOUNDS_NIL). All five rules are emitted on every
  /// call; the CLI filters by --rule and by the enabled set (copy-paste-assignment
  /// and index-possibly-out-of-range are OFF by default).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TBoundsNilChecker = class
  public
    /// <summary>Runs the BoundsNilChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration; only IndexGuardExceptionClass is read (the class the index-possibly-out-of-range fix raises).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index (unused: store-free rules).</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Diagnostics.BoundsNilChecks.TBnRun.Create, DRagLint.Diagnostics.BoundsNilChecks.TBnRun.Run, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, TreeSitter.TTSTree.RootNode</para>
    /// <para>Returns: nil; Run.Run(PF.Tree.RootNode)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Diagnostics.BoundsNilChecks.TBnRun.Create"/>
    /// <seealso cref="DRagLint.Diagnostics.BoundsNilChecks.TBnRun.Run"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <seealso cref="TreeSitter.TTSTree.RootNode"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>; static;
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
  , System.StrUtils
  , DRagLint.Core.LiveDocs
  ;

const
  MAX_FINDINGS = 200;
  MIN_RUN_ROWS = 3;
  RULE_NIL_CHECK = 'nil-check-after-dereference';
  RULE_ADDR_LOCAL = 'address-of-local-returned';
  RULE_CONST_INDEX = 'constant-index-out-of-range';
  RULE_COPY_PASTE = 'copy-paste-assignment';
  RULE_INDEX_RANGE = 'index-possibly-out-of-range';
  DEFAULT_INDEX_GUARD_EXCEPTION = 'EArgumentOutOfRangeException';
  DYN_ARRAY_TYPE_PATTERN = '^(?:packed\s+)?array\s+of\b|^tarray\s*<|^tbytes$';
  { Members whose call is not a use of the object for nil-check-after-dereference. }
  RELEASE_MEMBERS: array[0..3] of string = ('free', 'destroy', 'disposeof', 'release');
  { Axis-pair lhs members: a 2-row copy-paste run is a hit only for these. }
  AXIS_PAIRS: array[0..3] of array[0..1] of string = (
    ('left', 'top'), ('width', 'height'), ('x', 'y'), ('min', 'max'));
  STRING_TYPES: array[0..4] of string = (
    'string', 'unicodestring', 'ansistring', 'rawbytestring', 'widestring');
  CAST_NAMES: array[0..3] of string = ('pchar', 'pansichar', 'pwidechar', 'pointer');
  ARRAY_TYPE_PATTERN = '^(?:packed\s+)?array\s*\[\s*(-?\w+)\s*\.\.\s*(-?\w+)\s*\]\s*of\b';

type
  { What a declaration says about one name, as far as the rules care. }
  TDeclKind = (dkOther, dkString, dkArray, dkDynArray);

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

  { One A[idx] under analysis by index-possibly-out-of-range: what is being indexed, by what, the
    writes of the index in the routine, and the sides proven so far. }
  TIdxCtx = record
    Access : TTSNode;
    Idx    : string;            { lower-cased index name }
    Arr    : string;            { lower-cased array name }
    Info   : TDeclInfo;         { the array's shape }
    IdxInfo: TDeclInfo;         { the index's declaration (IsParam) }
    Writes : TList<TTSNode>;    { not owned }
    Lo     : Boolean;           { lower side proven }
    Hi     : Boolean;           { upper side proven }
    Silent : Boolean;           { a v1 cut applies: no finding }
    Loop   : TTSNode;           { innermost loop around the access }
  end;

  { One walk over one parsed file. Private to this unit. }
  TBnRun = class
  strict private
    FSrc     : TBytes;
    FFile    : string;
    FFindings: TList<TLintFinding>;
    FGlobals : TDictionary<string, TDeclInfo>;
    FScopes  : TObjectList<TDictionary<string, TDeclInfo>>;
    FConsts  : TDictionary<string, Integer>;      { file-level integer consts with a literal value }
    FConstBad: TDictionary<string, Boolean>;      { const names declared twice with different values }
    FAliases : TDictionary<string, TDeclInfo>;    { file-level type aliases of a string or array[lo..hi] }
    FAliasBad: TDictionary<string, Boolean>;
    FExClass : string;                            { the exception class the index guard fix raises }
    FLenAlias: TDictionary<string, string>;       { per routine: local written once as Length/High/Low(A) -> 'fn:a' }
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
    procedure CollectNamed(const N: TTSNode);
    function ConstValue(const AName: string; out AValue: Integer): Boolean;
    function BoundValue(const AToken: string; out AValue: Integer): Boolean;
    function EvalIndex(const N: TTSNode; out AValue: Integer): Boolean;
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
    function IsBoundedArray(const AName: string; out AInfo: TDeclInfo): Boolean;
    function IsArrayFn(const N: TTSNode; const AFn, AArr: string): Boolean;
    function IsLenMinus(const N: TTSNode; const AArr: string): Boolean;
    function ProvesLower(const E: TTSNode; AStrict: Boolean; const AArr: string; const AInfo: TDeclInfo): Boolean;
    function ProvesUpper(const E: TTSNode; AStrict: Boolean; const AArr: string; const AInfo: TDeclInfo): Boolean;
    procedure CompareFacts(var ACtx: TIdxCtx; const E: TTSNode; ANegate: Boolean);
    procedure CondFacts(var ACtx: TIdxCtx; const C: TTSNode; ANegate: Boolean);
    function IsLeaveStmt(const N: TTSNode): Boolean;
    function IsGrowOf(const N: TTSNode; const AArr: string): Boolean;
    procedure CollectLenAliases(const ABody: TTSNode);
    function AssignTarget(const AAssign: TTSNode): string;
    function Mentions(const N: TTSNode; const AIdent: string): Boolean;
    procedure CollectIdxWrites(const N: TTSNode; const AIdx: string; AList: TList<TTSNode>);
    function WriteKeeps(const ACtx: TIdxCtx; const W: TTSNode; ALower: Boolean): Boolean;
    function CaseOn(const ACase: TTSNode; const AIdx: string): Boolean;
    function HoldsSince(const ACtx: TIdxCtx; AFrom: Cardinal): Boolean;
    function FixAnchorLine(const AAccess: TTSNode): Integer;
    procedure ProvenanceSides(var ACtx: TIdxCtx);
    procedure ApplyBranch(var ACtx: TIdxCtx; const C, P: TTSNode);
    procedure ApplyForBounds(var ACtx: TIdxCtx; const P: TTSNode);
    procedure ApplyLoop(var ACtx: TIdxCtx; const C, P: TTSNode);
    procedure ApplySiblings(var ACtx: TIdxCtx; const C: TTSNode);
    procedure ClimbGuards(var ACtx: TIdxCtx);
    procedure EmitIndexFinding(const AProc: TTSNode; const ACtx: TIdxCtx; AReported: TDictionary<string, Boolean>);
    procedure CheckIndexAccess(const AProc: TTSNode; var ACtx: TIdxCtx; AReported: TDictionary<string, Boolean>);
    procedure CheckIndexFlow(const AProc: TTSNode);
    procedure Visit(const N: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes; const AExClass: string);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

constructor TBnRun.Create(const AFile: string; const ASrc: TBytes; const AExClass: string);
begin
  inherited Create;
  FFile:= AFile;
  FSrc := ASrc;
  FExClass:= if AExClass <> '' then AExClass else DEFAULT_INDEX_GUARD_EXCEPTION;
  FLenAlias:= TDictionary<string, string>.Create;
  FFindings:= TList<TLintFinding>.Create;
  FGlobals := TDictionary<string, TDeclInfo>.Create;
  FScopes  := TObjectList<TDictionary<string, TDeclInfo>>.Create(True);
  FConsts  := TDictionary<string, Integer>.Create;
  FConstBad:= TDictionary<string, Boolean>.Create;
  FAliases := TDictionary<string, TDeclInfo>.Create;
  FAliasBad:= TDictionary<string, Boolean>.Create;
end;

destructor TBnRun.Destroy;
begin
  FLenAlias.Free;
  FAliasBad.Free;
  FAliases.Free;
  FConstBad.Free;
  FConsts.Free;
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
  Alias: TDeclInfo;
begin
  ALo:= 0;
  AHi:= -1;
  Result:= dkOther;
  T:= LowerCase(Trim(ATypeText));
  for S in STRING_TYPES do
    if T = S then Exit(dkString);
  if FAliases.TryGetValue(T, Alias) and (not FAliasBad.ContainsKey(T)) then
  begin
    ALo:= Alias.Lo;
    AHi:= Alias.Hi;
    Exit(Alias.Kind);
  end;
  M:= TRegEx.Match(T, ARRAY_TYPE_PATTERN);
  if M.Success and BoundValue(M.Groups[1].Value, ALo) and BoundValue(M.Groups[2].Value, AHi) then
    Result:= dkArray
  else if TRegEx.IsMatch(T, DYN_ARRAY_TYPE_PATTERN) then
  begin
    ALo:= 0;
    AHi:= -1;
    Result:= dkDynArray;
  end
  else
  begin
    ALo:= 0;
    AHi:= -1;
  end;
end;

{ An array bound token: a decimal literal, or a file-level integer const (a named bound). }
function TBnRun.BoundValue(const AToken: string; out AValue: Integer): Boolean;
var
  Neg: Boolean;
  Tok: string;
begin
  Neg:= (AToken <> '') and (AToken[1] = '-');
  Tok:= AToken;
  if Neg then Delete(Tok, 1, 1);
  Result:= TryStrToInt(Tok, AValue);
  if (not Result) and FConsts.TryGetValue(Tok, AValue) and (not FConstBad.ContainsKey(Tok)) then Result:= True;
  if Result and Neg then AValue:= -AValue;
end;

{ File-level consts with an integer literal value and type aliases of string / array[lo..hi]: the
  names constant-index-out-of-range can resolve. A name declared twice with a different meaning is
  recorded as bad and stays silent. Runs before CollectGlobals so the shapes are known. }
procedure TBnRun.CollectNamed(const N: TTSNode);
var
  T, Nm    : string;
  I, V     : Integer;
  Val, Typ : TTSNode;
  Info, Old: TDeclInfo;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') then Exit;
  if T = 'declConst' then
  begin
    Val:= N.ChildByField('defaultValue');
    Nm := LowerCase(Txt(N.ChildByField('name')));
    if (not Val.IsNull) and (Nm <> '') and (Val.NamedChildCount >= 1) and (Val.NamedChild(Val.NamedChildCount - 1).NodeType = 'literalNumber') then
    begin
      if TryStrToInt(Txt(Val.NamedChild(Val.NamedChildCount - 1)), V) and ((not FConsts.TryGetValue(Nm, I)) or (I = V)) then FConsts.AddOrSetValue(Nm, V)
      else FConstBad.AddOrSetValue(Nm, True);
    end
    else if Nm <> '' then
      FConstBad.AddOrSetValue(Nm, True);
    Exit;
  end;
  if T = 'declType' then
  begin
    Typ:= N.ChildByField('type');
    Nm := LowerCase(Txt(N.ChildByField('name')));
    if (not Typ.IsNull) and (Nm <> '') then
    begin
      Info:= Default(TDeclInfo);
      Info.Kind:= ClassifyType(Txt(Typ), Info.Lo, Info.Hi);
      if Info.Kind = dkOther then FAliasBad.AddOrSetValue(Nm, True)
      else if FAliases.TryGetValue(Nm, Old) and ((Old.Kind <> Info.Kind) or (Old.Lo <> Info.Lo) or (Old.Hi <> Info.Hi)) then
        FAliasBad.AddOrSetValue(Nm, True)
      else FAliases.AddOrSetValue(Nm, Info);
    end
    else if Nm <> '' then
      FAliasBad.AddOrSetValue(Nm, True);
    Exit;
  end;
  for I:= 0 to N.ChildCount - 1 do CollectNamed(N.Child(I));
end;

{ A file-level const by name; a routine-local declaration of the same name shadows it. }
function TBnRun.ConstValue(const AName: string; out AValue: Integer): Boolean;
var
  I: Integer;
begin
  Result:= False;
  AValue:= 0;
  for I:= 0 to FScopes.Count - 1 do
    if FScopes[I].ContainsKey(AName) then Exit;
  Result:= FConsts.TryGetValue(AName, AValue) and (not FConstBad.ContainsKey(AName));
end;

{ The integer value of a constant index expression: a literal, a file-level const, unary minus,
  + / - of those, parentheses. False for anything else (a variable, a call). }
function TBnRun.EvalIndex(const N: TTSNode; out AValue: Integer): Boolean;  // dl:ok too-many-exit-points@f533 -- REVIEWED 2026-11-14 v151 INT: guard clauses per syntax shape; each early exit is a classification
var
  A, B: Integer;
  Op  : string;
begin
  Result:= False;
  AValue:= 0;
  if N.IsNull then Exit;
  if N.NodeType = 'literalNumber' then
    Exit(TRegEx.IsMatch(Txt(N), '^-?\d{1,9}$') and TryStrToInt(Txt(N), AValue));
  if N.NodeType = 'identifier' then
    Exit(ConstValue(LowerCase(Txt(N)), AValue));
  if (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) then
    Exit(EvalIndex(N.NamedChild(0), AValue));
  if N.NodeType = 'exprUnary' then
  begin
    if (OperatorType(N) <> 'kSub') or (not EvalIndex(N.ChildByField('operand'), A)) then Exit;
    AValue:= -A;
    Exit(True);
  end;
  if N.NodeType = 'exprBinary' then
  begin
    Op:= OperatorType(N);
    if ((Op <> 'kAdd') and (Op <> 'kSub')) or (not EvalIndex(N.ChildByField('lhs'), A))
       or (not EvalIndex(N.ChildByField('rhs'), B)) then Exit;
    if Op = 'kAdd' then AValue:= A + B else AValue:= A - B;  // dl:ok ifthen-to-if-expression@191a -- REVIEWED 2026-11-14 v151 INT: classic if/else kept in a lane unit written before the ternary sweep
    Result:= True;
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
  Ent, Args, Arg: TTSNode;
  Name: string;
  Info: TDeclInfo;
  Idx: Integer;
begin
  Ent:= N.ChildByField('entity');
  Args:= N.ChildByField('args');
  if Ent.IsNull or Args.IsNull or (Ent.NodeType <> 'identifier') then Exit;
  if Args.NamedChildCount <> 1 then Exit;
  Arg:= Args.NamedChild(0);
  if Arg.IsNull or (not EvalIndex(Arg, Idx)) then Exit;
  Name:= LowerCase(Txt(Ent));
  if not Lookup(Name, Info) then Exit;
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
          Result:= ALocals.TryGetValue(Name, Info) and not Info.ByRef and (Info.Kind in [dkString, dkArray]);
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

{ ---- index-possibly-out-of-range (1.52 IDXRANGE) ------------------------- }

const
  CMP_OPS    : array[0..3] of string = ('kLt', 'kGt', 'kLte', 'kGte');
  CMP_MIRROR : array[0..3] of string = ('kGt', 'kLt', 'kGte', 'kLte');  { idx < X  ==  X > idx }
  CMP_NEGATED: array[0..3] of string = ('kGte', 'kLte', 'kGt', 'kLt');  { not (idx < X)  ==  idx >= X }

{ `idx <op> X` read as `X <op'> idx`: the mirrored comparison operator ('' for a non-comparison). }
function MirrorOp(const AOp: string): string;
var
  I: Integer;
begin
  I:= IndexStr(AOp, CMP_OPS);
  Result:= if I >= 0 then CMP_MIRROR[I] else '';
end;

{ The comparison operator of `not (idx <op> X)` ('' for a non-comparison). }
function NegateOp(const AOp: string): string;
var
  I: Integer;
begin
  I:= IndexStr(AOp, CMP_OPS);
  Result:= if I >= 0 then CMP_NEGATED[I] else '';
end;

{ True when AName resolves to an array whose bounds the rule can name: a static
  array[lo..hi] or a dynamic / open array (bounds 0..High). }
function TBnRun.IsBoundedArray(const AName: string; out AInfo: TDeclInfo): Boolean;
begin
  Result:= Lookup(AName, AInfo) and (not AInfo.Ambig) and (AInfo.Kind in [dkArray, dkDynArray]);
end;

{ N (parentheses peeled) is the call AFn(AArr) -- Low / High / Length of that array -- or a local
  written once as that call (FLenAlias). }
function TBnRun.IsArrayFn(const N: TTSNode; const AFn, AArr: string): Boolean;
var
  E, Args: TTSNode;
begin
  Result:= False;
  E:= N;
  while (not E.IsNull) and (E.NodeType = 'exprParens') and (E.NamedChildCount = 1) do E:= E.NamedChild(0);
  if E.IsNull then Exit;
  if E.NodeType = 'identifier' then
    Exit(FLenAlias.ContainsKey(LowerCase(Txt(E))) and (FLenAlias[LowerCase(Txt(E))] = AFn + ':' + AArr));
  if E.NodeType <> 'exprCall' then Exit;
  Args:= E.ChildByField('args');
  Result:= (BareIdent(E.ChildByField('entity')) = AFn) and (not Args.IsNull)
    and (Args.NamedChildCount = 1) and (LowerCase(Trim(Txt(Args.NamedChild(0)))) = AArr);
end;

{ N is `Length(A) - k` (k >= 1) or `High(A) - k` (k >= 0): at most High(A). }
function TBnRun.IsLenMinus(const N: TTSNode; const AArr: string): Boolean;
var
  K: Integer;
  IsSub: Boolean;
begin
  IsSub:= (not N.IsNull) and (N.NodeType = 'exprBinary') and (OperatorType(N) = 'kSub');
  if not (IsSub and EvalIndex(N.ChildByField('rhs'), K)) then Exit(False);
  Result:= (IsArrayFn(N.ChildByField('lhs'), 'length', AArr) and (K >= 1))
    or (IsArrayFn(N.ChildByField('lhs'), 'high', AArr) and (K >= 0));
end;

{ idx >= E (AStrict: idx > E) proves the lower side. }
function TBnRun.ProvesLower(const E: TTSNode; AStrict: Boolean; const AArr: string; const AInfo: TDeclInfo): Boolean;
var
  V, Lo: Integer;
begin
  Lo:= if AInfo.Kind = dkArray then AInfo.Lo else 0;
  Result:= IsArrayFn(E, 'low', AArr);
  if (not Result) and EvalIndex(E, V) then
    Result:= (V >= Lo) or (AStrict and (V + 1 >= Lo));
end;

{ idx <= E (AStrict: idx < E) proves the upper side. }
function TBnRun.ProvesUpper(const E: TTSNode; AStrict: Boolean; const AArr: string; const AInfo: TDeclInfo): Boolean;
var
  V: Integer;
begin
  Result:= IsArrayFn(E, 'high', AArr) or IsLenMinus(E, AArr);
  if (not Result) and AStrict then
    Result:= IsArrayFn(E, 'length', AArr);
  if (not Result) and (AInfo.Kind = dkArray) and EvalIndex(E, V) then
    Result:= (V <= AInfo.Hi) or (AStrict and (V <= AInfo.Hi + 1));
end;

{ `idx <op> X` / `X <op> idx` (E a comparison): the side it proves, folded into ACtx. }
procedure TBnRun.CompareFacts(var ACtx: TIdxCtx; const E: TTSNode; ANegate: Boolean);
var
  Other: TTSNode;
  Op: string;
begin
  Op:= OperatorType(E);
  if BareIdent(E.ChildByField('lhs')) = ACtx.Idx then
    Other:= E.ChildByField('rhs')
  else if BareIdent(E.ChildByField('rhs')) = ACtx.Idx then
  begin
    Other:= E.ChildByField('lhs');
    Op:= MirrorOp(Op);
  end
  else
    Exit;
  if ANegate then Op:= NegateOp(Op);
  if Op = 'kGte' then ACtx.Lo:= ACtx.Lo or ProvesLower(Other, False, ACtx.Arr, ACtx.Info)
  else if Op = 'kGt' then ACtx.Lo:= ACtx.Lo or ProvesLower(Other, True, ACtx.Arr, ACtx.Info)
  else if Op = 'kLte' then ACtx.Hi:= ACtx.Hi or ProvesUpper(Other, False, ACtx.Arr, ACtx.Info)
  else if Op = 'kLt' then ACtx.Hi:= ACtx.Hi or ProvesUpper(Other, True, ACtx.Arr, ACtx.Info);
end;

{ The bound facts condition C proves about ACtx.Idx for ACtx.Arr (ANegate: the facts of `not C`). }
procedure TBnRun.CondFacts(var ACtx: TIdxCtx; const C: TTSNode; ANegate: Boolean);
const
  INRANGE_ARGS = 3;
var
  E, Args: TTSNode;
  Op: string;
begin
  E:= C;
  while (not E.IsNull) and (E.NodeType = 'exprParens') and (E.NamedChildCount = 1) do E:= E.NamedChild(0);
  if E.IsNull then Exit;
  if (E.NodeType = 'exprUnary') and (OperatorType(E) = 'kNot') then
    CondFacts(ACtx, E.ChildByField('operand'), not ANegate)
  else if E.NodeType = 'exprCall' then
  begin
    Args:= E.ChildByField('args');
    if (not ANegate) and (BareIdent(E.ChildByField('entity')) = 'inrange') and (not Args.IsNull)
      and (Args.NamedChildCount = INRANGE_ARGS) and (BareIdent(Args.NamedChild(0)) = ACtx.Idx) then
    begin
      ACtx.Lo:= ACtx.Lo or ProvesLower(Args.NamedChild(1), False, ACtx.Arr, ACtx.Info);
      ACtx.Hi:= ACtx.Hi or ProvesUpper(Args.NamedChild(2), False, ACtx.Arr, ACtx.Info);
    end;
  end
  else if E.NodeType = 'exprBinary' then
  begin
    Op:= OperatorType(E);
    if ((Op = 'kAnd') and not ANegate) or ((Op = 'kOr') and ANegate) then
    begin
      CondFacts(ACtx, E.ChildByField('lhs'), ANegate);
      CondFacts(ACtx, E.ChildByField('rhs'), ANegate);
    end
    else
      CompareFacts(ACtx, E, ANegate);
  end;
end;

{ A then-branch that always leaves: raise / Exit / Continue / Break, or a block ending in one. }
function TBnRun.IsLeaveStmt(const N: TTSNode): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'raise' then Exit(True);
  if N.NodeType = 'block' then
  begin
    for I:= N.NamedChildCount - 1 downto 0 do
      if not IsTrivia(N.NamedChild(I)) then Exit(IsLeaveStmt(N.NamedChild(I)));
    Exit;
  end;
  Result:= TRegEx.IsMatch(LowerCase(Trim(Txt(N))), '^(exit|continue|break)\b');
end;

{ A then-branch that grows AArr: `SetLength(A, ...)`, or a block ending in one (the grow-on-demand
  `if i >= Length(A) then SetLength(A, ...)` -- after it, i is below Length(A)). }
function TBnRun.IsGrowOf(const N: TTSNode; const AArr: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'block' then
  begin
    for I:= N.NamedChildCount - 1 downto 0 do
      if not IsTrivia(N.NamedChild(I)) then Exit(IsGrowOf(N.NamedChild(I), AArr));
    Exit;
  end;
  { by text, like IsLeaveStmt: a statement wrapper node may sit between the branch and the call }
  Result:= TRegEx.IsMatch(LowerCase(Trim(Txt(N))), '^setlength\s*\(\s*' + TRegEx.Escape(AArr) + '\s*,');
end;

{ The written identifier of an assignment's left side (also `for var i :=` / `var i :=`). }
function TBnRun.AssignTarget(const AAssign: TTSNode): string;
var
  Lhs: TTSNode;
  I  : Integer;
begin
  Result:= '';
  Lhs:= AAssign.ChildByField('lhs');
  if Lhs.IsNull then Exit;
  if Lhs.NodeType = 'varAssignDef' then
  begin
    for I:= 0 to Lhs.ChildCount - 1 do
      if Lhs.Child(I).NodeType = 'identifier' then Exit(LowerCase(Txt(Lhs.Child(I))));
    Exit;
  end;
  Result:= BareIdent(Lhs);
end;

{ True when N's subtree names AIdent (any identifier node). }
function TBnRun.Mentions(const N: TTSNode; const AIdent: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'identifier') and SameText(Txt(N), AIdent) then Exit(True);
  for I:= 0 to N.ChildCount - 1 do
    if Mentions(N.Child(I), AIdent) then Exit(True);
end;

{ Every write of AIdx in the body: `idx := e`, `Inc(idx)`, `Dec(idx)`, `for idx in ...`. A
  for-loop's own counter assignment is not a write here (the loop bounds it). Lambdas are skipped. }
procedure TBnRun.CollectIdxWrites(const N: TTSNode; const AIdx: string; AList: TList<TTSNode>);
var
  T: string;
  I: Integer;
  Args: TTSNode;
  IsForStart: Boolean;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'lambda') or (T = 'defProc') then Exit;
  IsForStart:= (not N.Parent.IsNull) and (N.Parent.NodeType = 'for') and (N.Parent.ChildByField('start') = N);
  if (T = 'assignment') and (AssignTarget(N) = AIdx) and not IsForStart then
    AList.Add(N)
  else if T = 'exprCall' then
  begin
    Args:= N.ChildByField('args');
    if ((BareIdent(N.ChildByField('entity')) = 'inc') or (BareIdent(N.ChildByField('entity')) = 'dec'))
      and (not Args.IsNull) and (Args.NamedChildCount >= 1) and (BareIdent(Args.NamedChild(0)) = AIdx) then
      AList.Add(N);
  end
  else if (T = 'foreach') and (BareIdent(N.ChildByField('iterator')) = AIdx) then
    AList.Add(N);
  for I:= 0 to N.ChildCount - 1 do CollectIdxWrites(N.Child(I), AIdx, AList);
end;

{ Does write W keep the lower (ALower) / upper side of ACtx.Idx within ACtx.Arr's range by itself? }
function TBnRun.WriteKeeps(const ACtx: TIdxCtx; const W: TTSNode; ALower: Boolean): Boolean;
var
  Rhs: TTSNode;
  K  : Integer;
  Fn : string;
begin
  Result:= False;
  if W.NodeType = 'exprCall' then
  begin
    Fn:= BareIdent(W.ChildByField('entity'));
    Exit((ALower and (Fn = 'inc')) or ((not ALower) and (Fn = 'dec')));
  end;
  if W.NodeType <> 'assignment' then Exit;
  Rhs:= W.ChildByField('rhs');
  Result:= if ALower then ProvesLower(Rhs, False, ACtx.Arr, ACtx.Info) else ProvesUpper(Rhs, False, ACtx.Arr, ACtx.Info);
  { idx := idx + k keeps the lower side, idx := idx - k the upper side (k >= 0) }
  if (not Result) and (Rhs.NodeType = 'exprBinary') and (BareIdent(Rhs.ChildByField('lhs')) = ACtx.Idx)
    and EvalIndex(Rhs.ChildByField('rhs'), K) and (K >= 0) then
    Result:= (ALower and (OperatorType(Rhs) = 'kAdd')) or ((not ALower) and (OperatorType(Rhs) = 'kSub'));
end;

{ `case AIdx of`: the selector is the first non-keyword child. }
function TBnRun.CaseOn(const ACase: TTSNode; const AIdx: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 0 to ACase.NamedChildCount - 1 do
    if not IsTrivia(ACase.NamedChild(I)) then Exit(BareIdent(ACase.NamedChild(I)) = AIdx);
end;

{ True when no write of ACtx.Idx starts strictly between AFrom and the access (a guard still holds). }
function TBnRun.HoldsSince(const ACtx: TIdxCtx; AFrom: Cardinal): Boolean;
var
  W: TTSNode;
begin
  Result:= True;
  for W in ACtx.Writes do
    if (W.StartByte > AFrom) and (W.StartByte < ACtx.Access.StartByte) then Exit(False);
end;

{ The line the autofix inserts its guard before: the access's own statement when that statement
  is a direct member of a statement list and starts its line; 0 when the access sits in a
  condition, a loop header or a one-statement branch (the insertion would change the meaning). }
function TBnRun.FixAnchorLine(const AAccess: TTSNode): Integer;
const
  CONTROL: array[0..10] of string = ('if', 'ifElse', 'while', 'for', 'foreach', 'repeat', 'case',
    'caseCase', 'try', 'with', 'exceptionHandler');
  TAB_BYTE = 9;
  LF_BYTE  = 10;
var
  C, P: TTSNode;
  S: string;
  B: Integer;
begin
  Result:= 0;
  C:= AAccess;
  while not C.IsNull do
  begin
    for S in CONTROL do
      if C.NodeType = S then Exit;
    P:= C.Parent;
    if P.IsNull or (P.NodeType = 'defProc') or (P.NodeType = 'lambda') then Exit;
    if (P.NodeType = 'block') or (P.NodeType = 'statements') then Break;
    C:= P;
  end;
  if C.IsNull then Exit;
  B:= Integer(C.StartByte) - 1;
  while (B >= 0) and ((FSrc[B] = Ord(' ')) or (FSrc[B] = TAB_BYTE)) do Dec(B);
  if (B >= 0) and (FSrc[B] <> LF_BYTE) then Exit;
  Result:= Integer(C.StartPoint.Row) + 1;
end;

{ Provenance: a side holds when every write that can REACH the access keeps it -- earlier writes,
  and later ones inside the outermost loop around it (they flow back on the next iteration).
  Never for a parameter: its incoming value is unknown. }
procedure TBnRun.ProvenanceSides(var ACtx: TIdxCtx);
var
  C, Outer, W: TTSNode;
begin
  ACtx.Lo:= False;
  ACtx.Hi:= False;
  if ACtx.IdxInfo.IsParam or (ACtx.Writes.Count = 0) then Exit;
  Outer:= Default(TTSNode);
  C:= ACtx.Access.Parent;
  while (not C.IsNull) and (C.NodeType <> 'defProc') and (C.NodeType <> 'lambda') do
  begin
    if (C.NodeType = 'while') or (C.NodeType = 'repeat') or (C.NodeType = 'for') or (C.NodeType = 'foreach') then Outer:= C;
    C:= C.Parent;
  end;
  ACtx.Lo:= True;
  ACtx.Hi:= True;
  for W in ACtx.Writes do
    if (W.StartByte < ACtx.Access.StartByte) or ((not Outer.IsNull) and (W.StartByte < Outer.EndByte)) then
    begin
      ACtx.Lo:= ACtx.Lo and WriteKeeps(ACtx, W, True);
      ACtx.Hi:= ACtx.Hi and WriteKeeps(ACtx, W, False);
    end;
end;

{ C under a branching parent P: an if / if-expression branch, or the right side of a short-circuit. }
procedure TBnRun.ApplyBranch(var ACtx: TIdxCtx; const C, P: TTSNode);
var
  ElseAt: Cardinal;
  I: Integer;
begin
  if (P.NodeType = 'if') or (P.NodeType = 'ifElse') then
  begin
    if not HoldsSince(ACtx, P.ChildByField('condition').EndByte) then Exit;
    if P.ChildByField('then') = C then CondFacts(ACtx, P.ChildByField('condition'), False)
    else if P.ChildByField('else') = C then CondFacts(ACtx, P.ChildByField('condition'), True);
  end
  else if P.NodeType = 'exprIf' then
  begin
    if P.ChildByField('condition') = C then Exit;
    { `if c then X else Y` as an expression: X sits before the kElse child, Y after it }
    ElseAt:= P.EndByte;
    for I:= 0 to P.ChildCount - 1 do
      if P.Child(I).NodeType = 'kElse' then ElseAt:= P.Child(I).StartByte;
    CondFacts(ACtx, P.ChildByField('condition'), C.StartByte > ElseAt);
  end
  else if (P.NodeType = 'exprBinary') and (P.ChildByField('rhs') = C) then
  begin
    { short-circuit: `X and A[i]` evaluates the right side only when X holds; `X or A[i]` only when it fails }
    if OperatorType(P) = 'kAnd' then CondFacts(ACtx, P.ChildByField('lhs'), False)
    else if OperatorType(P) = 'kOr' then CondFacts(ACtx, P.ChildByField('lhs'), True);
  end;
end;

{ `for idx := s to/downto e` around the access: both sides when the bounds are recognised, else
  silent (v1 cut: a for loop with other bounds). }
procedure TBnRun.ApplyForBounds(var ACtx: TIdxCtx; const P: TTSNode);
var
  I: Integer;
  IsDown, Bounded: Boolean;
  StartE, EndE: TTSNode;
begin
  IsDown:= False;
  for I:= 0 to P.ChildCount - 1 do
    if P.Child(I).NodeType = 'kDownto' then IsDown:= True;
  StartE:= P.ChildByField('start').ChildByField('rhs');
  EndE  := P.ChildByField('end');
  Bounded:= if IsDown then ProvesUpper(StartE, False, ACtx.Arr, ACtx.Info) and ProvesLower(EndE, False, ACtx.Arr, ACtx.Info)
    else ProvesLower(StartE, False, ACtx.Arr, ACtx.Info) and ProvesUpper(EndE, False, ACtx.Arr, ACtx.Info);
  ACtx.Lo:= ACtx.Lo or Bounded;
  ACtx.Hi:= ACtx.Hi or Bounded;
  ACtx.Silent:= ACtx.Silent or not Bounded;
end;

{ C under a loop P: the while condition, the for bounds, the repeat cut; records the innermost loop. }
procedure TBnRun.ApplyLoop(var ACtx: TIdxCtx; const C, P: TTSNode);
begin
  if ACtx.Loop.IsNull then ACtx.Loop:= P;
  if P.NodeType = 'while' then
  begin
    if (P.ChildByField('body') = C) and HoldsSince(ACtx, P.ChildByField('condition').EndByte) then
      CondFacts(ACtx, P.ChildByField('condition'), False);
  end
  else if P.NodeType = 'repeat' then
    ACtx.Silent:= ACtx.Silent or Mentions(P.ChildByField('condition'), ACtx.Idx)  { v1 cut: repeat conditions }
  else if (P.NodeType = 'for') and (P.ChildByField('body') = C) and (AssignTarget(P.ChildByField('start')) = ACtx.Idx) then
    ApplyForBounds(ACtx, P);
end;

{ Earlier statements of the list holding C: `if <fail> then Exit / raise / Continue / Break` and
  the grow-on-demand `if i >= Length(A) then SetLength(A, ...)` guard; Assert is a v1 cut. }
procedure TBnRun.ApplySiblings(var ACtx: TIdxCtx; const C: TTSNode);
var
  S, ThenN: TTSNode;
begin
  S:= C.PrevSibling;
  while not S.IsNull do
  begin
    ThenN:= S.ChildByField('then');
    if (S.NodeType = 'if') and (IsLeaveStmt(ThenN) or IsGrowOf(ThenN, ACtx.Arr)) and HoldsSince(ACtx, S.EndByte) then
      CondFacts(ACtx, S.ChildByField('condition'), True)
    else if (S.NodeType = 'exprCall') and (BareIdent(S.ChildByField('entity')) = 'assert') and Mentions(S, ACtx.Idx) then
      ACtx.Silent:= True;
    S:= S.PrevSibling;
  end;
end;

{ Every dominating guard from the access up to its routine. }
procedure TBnRun.ClimbGuards(var ACtx: TIdxCtx);
var
  C, P: TTSNode;
  T: string;
begin
  C:= ACtx.Access;
  P:= C.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    T:= P.NodeType;
    if (T = 'if') or (T = 'ifElse') or (T = 'exprIf') or (T = 'exprBinary') then
      ApplyBranch(ACtx, C, P)
    else if (T = 'while') or (T = 'repeat') or (T = 'foreach') or (T = 'for') then
      ApplyLoop(ACtx, C, P)
    else if (T = 'case') and CaseOn(P, ACtx.Idx) then
      ACtx.Silent:= True  { v1 cut: case ranges }
    else if (T = 'block') or (T = 'statements') then
      ApplySiblings(ACtx, C);
    C:= P;
    P:= C.Parent;
  end;
end;

{ The finding for an unproven access: on the nearest preceding write (else a later write inside the
  enclosing loop) as a warning, or on the access as a hint for an unwritten parameter. One finding
  per write / per parameter (AReported). }
procedure TBnRun.EmitIndexFinding(const AProc: TTSNode; const ACtx: TIdxCtx; AReported: TDictionary<string, Boolean>);
const
  MSG_BODY = ' reaches %s[%s] at line %d with no guard bounding it to %s''s range on both sides '
    + '-- check it before the access; ERangeError is only the last resort (in %s; %s)';
var
  Report, W: TTSNode;
  Key, Routine, Tail, Ent, Arg, Body: string;
  Anchor: Integer;
begin
  Report:= Default(TTSNode);
  for W in ACtx.Writes do
    if (W.StartByte < ACtx.Access.StartByte) and (Report.IsNull or (W.StartByte > Report.StartByte)) then Report:= W;
  if Report.IsNull and not ACtx.Loop.IsNull then
    for W in ACtx.Writes do
      if (W.StartByte > ACtx.Access.StartByte) and (W.EndByte <= ACtx.Loop.EndByte) and Report.IsNull then Report:= W;
  if Report.IsNull and not ACtx.IdxInfo.IsParam then Exit;
  Key:= if Report.IsNull then 'p' + ACtx.Idx else 'w' + IntToStr(Report.StartByte);
  if AReported.ContainsKey(Key) then Exit;
  AReported.Add(Key, True);
  Ent:= Txt(ACtx.Access.ChildByField('entity'));
  Arg:= Trim(Txt(ACtx.Access.ChildByField('args')));
  Routine:= Trim(Txt(AProc.ChildByField('header').ChildByField('name')));
  Anchor:= FixAnchorLine(ACtx.Access);
  Tail:= if Anchor > 0 then Format('fix raises %s at line %d', [FExClass, Anchor])
    else 'no autofix: the access sits in a condition or a one-statement branch';
  Body:= Format(MSG_BODY, [Ent, Arg, Integer(ACtx.Access.StartPoint.Row) + 1, Ent, Routine, Tail]);
  if Report.IsNull then
    EmitAt(ACtx.Access, RULE_INDEX_RANGE, Format('Parameter ''%s''', [Arg]) + Body, 'hint')
  else
    EmitAt(Report, RULE_INDEX_RANGE, Format('''%s'' is written here and', [Arg]) + Body, 'warning');
end;

{ One access A[idx]: proves both sides or reports the write that made it unsafe. }
procedure TBnRun.CheckIndexAccess(const AProc: TTSNode; var ACtx: TIdxCtx; AReported: TDictionary<string, Boolean>);
begin
  ProvenanceSides(ACtx);
  ACtx.Silent:= False;
  ACtx.Loop:= Default(TTSNode);
  ClimbGuards(ACtx);
  if ACtx.Silent or (ACtx.Lo and ACtx.Hi) then Exit;
  EmitIndexFinding(AProc, ACtx, AReported);
end;

{ Locals of the body written exactly once, as `n := Length(A)` / `High(A)` / `Low(A)`: a bound on n
  is then a bound on A. Any second write (assignment, Inc / Dec, for counter) disqualifies n. }
procedure TBnRun.CollectLenAliases(const ABody: TTSNode);
var
  Writes: TDictionary<string, Integer>;
  Cand  : TDictionary<string, string>;

  { `Length(x)` / `High(x)` / `Low(x)` -> 'fn:x', else '' }
  function BoundCallKey(const ARhs: TTSNode): string;
  var
    R, Args: TTSNode;
    Fn: string;
  begin
    Result:= '';
    R:= ARhs;
    while (not R.IsNull) and (R.NodeType = 'exprParens') and (R.NamedChildCount = 1) do R:= R.NamedChild(0);
    if R.IsNull or (R.NodeType <> 'exprCall') then Exit;
    Fn:= BareIdent(R.ChildByField('entity'));
    Args:= R.ChildByField('args');
    if not ((Fn = 'length') or (Fn = 'high') or (Fn = 'low')) then Exit;
    if (not Args.IsNull) and (Args.NamedChildCount = 1) and (BareIdent(Args.NamedChild(0)) <> '') then
      Result:= Fn + ':' + BareIdent(Args.NamedChild(0));
  end;

  procedure Walk(const N: TTSNode);
  var
    I, C: Integer;
    T, Nm, Key: string;
    Args: TTSNode;
  begin
    if N.IsNull then Exit;
    T:= N.NodeType;
    if (T = 'lambda') or (T = 'defProc') then Exit;
    Nm:= '';
    if T = 'assignment' then
    begin
      Nm:= AssignTarget(N);
      Key:= BoundCallKey(N.ChildByField('rhs'));
      if (Nm <> '') and (Key <> '') then Cand.AddOrSetValue(Nm, Key);
    end
    else if (T = 'exprCall') and ((BareIdent(N.ChildByField('entity')) = 'inc') or (BareIdent(N.ChildByField('entity')) = 'dec')) then
    begin
      Args:= N.ChildByField('args');
      if (not Args.IsNull) and (Args.NamedChildCount >= 1) then Nm:= BareIdent(Args.NamedChild(0));
    end;
    if Nm <> '' then
    begin
      if not Writes.TryGetValue(Nm, C) then C:= 0;
      Writes.AddOrSetValue(Nm, C + 1);
    end;
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

var
  Pair: TPair<string, string>;
  C: Integer;
begin
  FLenAlias.Clear;
  Writes:= TDictionary<string, Integer>.Create;
  Cand:= TDictionary<string, string>.Create;
  try
    Walk(ABody);
    for Pair in Cand do
      if Writes.TryGetValue(Pair.Key, C) and (C = 1) then FLenAlias.Add(Pair.Key, Pair.Value);
  finally
    Cand.Free;
    Writes.Free;
  end;
end;

{ Every A[idx] of one routine, where A is a bounded array and idx a routine local or parameter. }
procedure TBnRun.CheckIndexFlow(const AProc: TTSNode);
var
  Body: TTSNode;
  Locals: TDictionary<string, TDeclInfo>;
  Accesses: TList<TTSNode>;
  Writes: TList<TTSNode>;
  Reported: TDictionary<string, Boolean>;
  Unsafe: Boolean;

  procedure Gather(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit;
    if (N.NodeType = 'with') or (N.NodeType = 'goto') then Unsafe:= True;
    if N.NodeType = 'exprSubscript' then Accesses.Add(N);
    for I:= 0 to N.ChildCount - 1 do Gather(N.Child(I));
  end;

  { a lambda in the body that names AIdx may write it }
  function InLambda(const N: TTSNode; const AIdx: string): Boolean;
  var
    J: Integer;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'lambda' then Exit(Mentions(N, AIdx));
    for J:= 0 to N.ChildCount - 1 do
      if InLambda(N.Child(J), AIdx) then Exit(True);
  end;

  { a nested routine or a lambda that names AIdx may write it: the routine-local view is blind there }
  function CapturedElsewhere(const AIdx: string): Boolean;
  var
    I: Integer;
  begin
    Result:= InLambda(Body, AIdx);
    if not Result then
      for I:= 0 to AProc.ChildCount - 1 do
        if (AProc.Child(I).NodeType = 'defProc') and Mentions(AProc.Child(I), AIdx) then
          Exit(True);
  end;

var
  N, Args, IdxN: TTSNode;
  Ctx: TIdxCtx;
  V: Integer;
begin
  Body:= AProc.ChildByField('body');
  if Body.IsNull then Exit;
  Locals:= FScopes[FScopes.Count - 1];
  Unsafe:= False;
  Accesses:= TList<TTSNode>.Create;
  Writes:= TList<TTSNode>.Create;
  Reported:= TDictionary<string, Boolean>.Create;
  try
    Gather(Body);
    if Unsafe then Exit;
    CollectLenAliases(Body);
    for N in Accesses do
    begin
      Args:= N.ChildByField('args');
      if Args.IsNull or (Args.NamedChildCount <> 1) then Continue;
      IdxN:= Args.NamedChild(0);
      Ctx:= Default(TIdxCtx);
      Ctx.Access:= N;
      Ctx.Idx:= BareIdent(IdxN);
      Ctx.Arr:= BareIdent(N.ChildByField('entity'));
      if (Ctx.Idx = '') or (Ctx.Arr = '') or EvalIndex(IdxN, V) then Continue;
      if not Locals.TryGetValue(Ctx.Idx, Ctx.IdxInfo) then Continue;   { v1 cut: field / global index }
      if not IsBoundedArray(Ctx.Arr, Ctx.Info) then Continue;
      if CapturedElsewhere(Ctx.Idx) then Continue;
      Writes.Clear;
      CollectIdxWrites(Body, Ctx.Idx, Writes);
      Ctx.Writes:= Writes;
      CheckIndexAccess(AProc, Ctx, Reported);
    end;
  finally
    Reported.Free;
    Writes.Free;
    Accesses.Free;
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
    CheckIndexFlow(N);
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
  CollectNamed(ARoot);
  CollectGlobals(ARoot);
  Visit(ARoot);
  Result:= FFindings.ToArray;
end;

{ ---- the checker entry point -------------------------------------------- }

class function TBoundsNilChecker.Check(const AFile: string; const ACfg: TLintConfig;
  const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;  // dl:ok unused-parameter@255c -- signature fixed by the shared checker shape; the rules are store-free
var
  PF : TParsedFile;
  Run: TBnRun;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Run:= TBnRun.Create(AFile, PF.Src, ACfg.IndexGuardExceptionClass);
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

{ ---- the index-possibly-out-of-range fixer ------------------------------- }

{ Inserts `if not InRange(i, Low(A), High(A)) then raise <Ex>.CreateFmt(...)` on its own line
  before each anchorable access the findings name, at that statement's indentation, and adds
  System.Math / System.SysUtils to the uses clause when missing. Everything it needs is in the
  finding message (`reaches A[i] at line N ... (in R; fix raises Ex at line K)`), so a cached
  finding fixes the same way. A finding whose anchor line no longer contains `A[i` is skipped. }
function FixIndexPossiblyOutOfRange(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
const
  MSG_RE = 'reaches (\w+)\[(\w+)\] at line (\d+) .*\(in ([^;]*); fix raises ([\w.]+) at line (\d+)\)$';
  G_ARR = 1;
  G_IDX = 2;
  G_ACCESS = 3;
  G_ROUTINE = 4;
  G_CLASS = 5;
  G_ANCHOR = 6;
var
  Lines: TStringList;
  M: TMatch;
  Arr, Idx, Routine, ExClass, Indent, Text, Key: string;
  AccessLine, Anchor, L: Integer;
  Seen: TDictionary<string, Boolean>;
  E: TTextEdit;
  Found: Boolean;
begin
  Result:= nil;
  AFixed:= 0;
  Lines:= TStringList.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    Lines.AddStrings(TLiveDocuments.ReadLines(APath));
    for var F: TLintFinding in AFindings do
    begin
      if not SameText(F.RuleId, RULE_INDEX_RANGE) or not SameText(F.FilePath, APath) then Continue;
      M:= TRegEx.Match(F.Message, MSG_RE);
      if not M.Success then Continue;
      Arr       := M.Groups[G_ARR].Value;
      Idx       := M.Groups[G_IDX].Value;
      AccessLine:= StrToIntDef(M.Groups[G_ACCESS].Value, 0);
      Routine   := M.Groups[G_ROUTINE].Value;
      ExClass   := M.Groups[G_CLASS].Value;
      Anchor    := StrToIntDef(M.Groups[G_ANCHOR].Value, 0);
      if (Anchor < 1) or (Anchor > Lines.Count) or (AccessLine < Anchor) or (AccessLine > Lines.Count) then Continue;
      Found:= False;
      for L:= Anchor to AccessLine do
        if ContainsText(Lines[L - 1], Arr + '[' + Idx) then Found:= True;
      if not Found then Continue;
      Indent:= Copy(Lines[Anchor - 1], 1, Length(Lines[Anchor - 1]) - Length(TrimLeft(Lines[Anchor - 1])));
      Text:= Format('%sif not InRange(%s, Low(%s), High(%s)) then raise %s.CreateFmt(''%s index %%d outside %%d..%%d in %s'', [%s, Low(%s), High(%s)]);',
        [Indent, Idx, Arr, Arr, ExClass, Arr, Routine, Idx, Arr, Arr]);
      Key:= IntToStr(Anchor) + #1 + LowerCase(Text);
      Inc(AFixed);
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      E:= Default(TTextEdit);
      E.FilePath:= APath;
      E.Kind    := tekInsertLines;
      E.Line    := Anchor - 1;      { insert AFTER line Anchor-1 = before the access's statement }
      E.Text    := Text;
      Result:= Result + [E];
    end;
    if Length(Result) = 0 then Exit;
    if EnsureImplUses(APath, Lines, 'System.Math', E) then Result:= Result + [E];
    if EnsureImplUses(APath, Lines, 'System.SysUtils', E) then Result:= Result + [E];
  finally
    Seen.Free;
    Lines.Free;
  end;
end;

initialization
  RegisterFixer(RULE_COPY_PASTE, FixCopyPasteAssignment, True);
  RegisterFileFixer(RULE_INDEX_RANGE, FixIndexPossiblyOutOfRange, True);

end.
