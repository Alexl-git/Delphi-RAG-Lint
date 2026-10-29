unit DRagLint.Diagnostics.OwnershipChecks;

{ Gap-rules wave (plan 2026-10-27-rule-gaps-and-compliance-plan.md), lane G4.
  The ids are in LINT_GATE_OWNERSHIP (CLI.pas) and in TRuleCatalog.BuiltinRegistry.
  Rules: field-created-not-freed, free-of-owned-item, mismatched-alloc-free,
  freeonterminate-then-wait, begin-end-pair-not-in-finally.

  Every rule is a purely syntactic, per-file scan over the tree-sitter AST (no
  index needed). Three of them carry a registered autofix (see the
  initialization section): mismatched-alloc-free, begin-end-pair-not-in-finally
  (present-End shape) and field-created-not-freed (existing destructor only). }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the OwnershipChecks rules of the gap-rules wave (G4).</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_OWNERSHIP).
  /// </remarks>
  TOwnershipChecker = class
  public
    /// <summary>Runs the OwnershipChecks rules against one source file.</summary>
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
  , System.Classes
  , System.StrUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  ;

const
  RULE_FIELD   = 'field-created-not-freed' ;
  RULE_OWNED   = 'free-of-owned-item'      ;
  RULE_MISMATCH= 'mismatched-alloc-free'   ;
  RULE_FOT     = 'freeonterminate-then-wait';
  RULE_PAIR    = 'begin-end-pair-not-in-finally';
  PAIR_COUNT   = 7;
  PAIR_BEGIN: array[0..PAIR_COUNT - 1] of string = (
    'beginupdate', 'disablecontrols', 'beginread', 'beginwrite', 'locklist', 'lock', 'starttransaction');
  PAIR_END  : array[0..PAIR_COUNT - 1] of string = (
    'endupdate', 'enablecontrols', 'endread', 'endwrite', 'unlocklist', 'unlock', 'commit');
  PAIR_TRANSACTION = 6;
  FAM_MEM = 'mem';
  FAM_NEW = 'new';
  FAM_STR = 'str';
  FAM_OBJ = 'obj';
  FAMILY_NAMES: array[0..3] of string = (
    'GetMem/AllocMem (FreeMem)', 'New (Dispose)', 'StrAlloc/StrNew (StrDispose)', 'Create (Free)');
  { VCL / DevExpress controls: a constructor argument is their owner or parent, which frees them. }
  OWNED_CONTROLS: array[0..33] of string = (
    'tbutton', 'tedit', 'tlabel', 'tpanel', 'tcheckbox', 'tcombobox', 'tmemo', 'tlistbox', 'tlistview',
    'ttreeview', 'timage', 'ttimer', 'tpagecontrol', 'ttabsheet', 'tsplitter', 'tbitbtn', 'tspeedbutton',
    'tgroupbox', 'tradiobutton', 'tstatusbar', 'ttoolbar', 'ttoolbutton', 'tprogressbar', 'tpopupmenu',
    'tmenuitem', 'taction', 'tactionlist', 'timagelist', 'tdatasource', 'tbevel', 'tscrollbox', 'tpaintbox',
    'tshape', 'tcontrolbar');

type
  { One statement-level call, split into receiver and method. }
  TCallInfo = record
    Node   : TTSNode;
    Callee : string ;
    Recv   : string ;
    Meth   : string ;
    Arg0   : string ;
    Arg0Raw: string ;
    RecvRaw: string ;
  end;

  { A Begin/End style call found in a routine. }
  TPairCall = record
    Node   : TTSNode;
    Recv   : string ;
    Idx    : Integer;
    IsBegin: Boolean;
    InFin  : Boolean;
    InExc  : Boolean;
  end;

  { One scan of one file; owns every collection it builds. }
  TOwnershipScan = class
  strict private
    FFile      : string                      ;
    FSrc       : TBytes                      ;
    FRootNode  : TTSNode                     ;
    FFindings  : TList<TLintFinding>         ;
    FRoutines  : TList<TTSNode>              ;
    FFileTypes : TDictionary<string, string> ;
    FFieldType : TDictionary<string, string> ;
    FFieldNames: TDictionary<string, Boolean>;
    FHandled   : TDictionary<string, Boolean>;
    FOwnFlags  : TDictionary<string, Integer>;
    FFotFields : TDictionary<string, Boolean>;
    FFotSetBy  : TDictionary<string, Boolean>;
    FEmitted   : TDictionary<string, Boolean>;
    function NodeStr(const N: TTSNode): string;
    function Canon(const AText: string): string;
    procedure GatherAllRoutines(const N: TTSNode; const AList: TList<TTSNode>);
    procedure Gather(const ARoot: TTSNode; const ATypes: array of string; const AList: TList<TTSNode>);
    procedure GatherWalk(const N: TTSNode; AIsRoot: Boolean; const ATypes: array of string; const AList: TList<TTSNode>);
    procedure Emit(const ARule: string; const N: TTSNode; const AMsg, ASym: string);
    function CallOf(const AStmt: TTSNode): TCallInfo;
    function ClassOf(const ARoutine: TTSNode): string;
    function IsCtor(const ARoutine: TTSNode): Boolean;
    procedure ParseDecl(const AText: string; const AMap: TDictionary<string, string>; const AFields: TDictionary<string, Boolean>);
    procedure LocalsOf(const ARoutine: TTSNode; const ALocals, AAll: TDictionary<string, string>);
    function IsCreateText(const ACanon: string): Boolean;
    function CreateArgs(const ARhs: TTSNode; out AArgs: TArray<string>): Boolean;
    procedure CollectFileFacts;
    procedure MarkHandled(const ARoutine: TTSNode; const AClass: string);
    procedure CheckFieldCreated;
    procedure CheckOwnedItems;
    procedure CheckForeachFree(const AForeach: TTSNode; const AOwning: TDictionary<string, string>);
    procedure CheckOwnedRoutine(const ARoutine: TTSNode; const AIdx: Integer);
    procedure CheckMismatch(const ARoutine: TTSNode);
    procedure CheckFotRoutine(const ARoutine: TTSNode; const AIdx: Integer);
    procedure CheckFotOtherMethods;
    procedure CheckPairs(const ARoutine: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

function StripGeneric(const AName: string): string;
var
  P: Integer;
begin
  P:= Pos('<', AName);
  Result:= if P > 0 then Copy(AName, 1, P - 1) else AName;
end;

{ A statement call that allocates through a var parameter: New(P), GetMem(P, n),
  ReallocMem(P, n). }
function AllocOf(const C: TCallInfo; out AName, AFamily: string): Boolean;
begin
  AName  := C.Arg0;
  AFamily:= '';
  if C.Arg0 <> '' then
  begin
    if C.Callee = 'new' then AFamily:= FAM_NEW
    else if (C.Callee = 'getmem') or (C.Callee = 'reallocmem') then AFamily:= FAM_MEM;
  end;
  Result:= AFamily <> '';
end;

{ A statement call that releases memory or an object: which family it belongs
  to, the pointer's canonical name and its source spelling. }
function ReleaseOf(const C: TCallInfo; out AFamily, AName, ARaw: string): Boolean;
begin
  AFamily:= '';
  AName  := C.Arg0;
  ARaw   := C.Arg0Raw;
  if C.Arg0 <> '' then
  begin
    if C.Callee = 'freemem' then AFamily:= FAM_MEM
    else if C.Callee = 'dispose' then AFamily:= FAM_NEW
    else if C.Callee = 'strdispose' then AFamily:= FAM_STR
    else if C.Callee = 'freeandnil' then AFamily:= FAM_OBJ;
  end
  else if (C.Recv <> '') and ((C.Meth = 'free') or (C.Meth = 'disposeof')) then
  begin
    AFamily:= FAM_OBJ;
    AName  := C.Recv;
    ARaw   := C.RecvRaw;
  end;
  Result:= AFamily <> '';
end;
{ Constructor of a control that takes an owner or parent: TLabel.Create(Panel). }
function IsOwnedControlCreate(const ARhsCanon: string): Boolean;
var
  Cls: string;
  D  : Integer;
begin
  Cls:= Copy(ARhsCanon, 1, Pos('.create', ARhsCanon + '.create') - 1);
  D:= LastDelimiter('.', Cls);
  Cls:= Copy(Cls, D + 1, MaxInt);
  Result:= (IndexStr(Cls, OWNED_CONTROLS) >= 0) or StartsStr('tcx', Cls) or StartsStr('tdx', Cls);
end;

function IsContainerType(const ACanonType: string): Boolean;
begin
  Result:= SameText(StripGeneric(ACanonType), 'tobjectlist') or SameText(StripGeneric(ACanonType), 'tobjectdictionary')
    or SameText(StripGeneric(ACanonType), 'tcomponentlist');
end;

constructor TOwnershipScan.Create(const AFile: string; const ASrc: TBytes);
begin
  inherited Create;
  FFile      := AFile;
  FSrc       := ASrc;
  FFindings  := TList<TLintFinding>.Create;
  FRoutines  := TList<TTSNode>.Create;
  FFileTypes := TDictionary<string, string>.Create;
  FFieldType := TDictionary<string, string>.Create;
  FFieldNames:= TDictionary<string, Boolean>.Create;
  FHandled   := TDictionary<string, Boolean>.Create;
  FOwnFlags  := TDictionary<string, Integer>.Create;
  FFotFields := TDictionary<string, Boolean>.Create;
  FFotSetBy  := TDictionary<string, Boolean>.Create;
  FEmitted   := TDictionary<string, Boolean>.Create;
end;

destructor TOwnershipScan.Destroy;
begin
  FEmitted.Free;
  FFotSetBy.Free;
  FFotFields.Free;
  FOwnFlags.Free;
  FHandled.Free;
  FFieldNames.Free;
  FFieldType.Free;
  FFileTypes.Free;
  FRoutines.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TOwnershipScan.NodeStr(const N: TTSNode): string;
var
  S, E, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  E:= Integer(N.EndByte);
  L:= E - S;
  if (L <= 0) or (S < 0) or (E > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, L);
end;

{ Lower-cased, blanks removed, a leading 'self.' dropped: 'Self.FLock' and
  'FLock' name the same thing. }
function TOwnershipScan.Canon(const AText: string): string;
begin
  Result:= LowerCase(StringReplace(StringReplace(StringReplace(Trim(AText), ' ', '', [rfReplaceAll]),
    #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]));
  if StartsText('self.', Result) then Delete(Result, 1, Length('self.'));
end;

procedure TOwnershipScan.GatherWalk(const N: TTSNode; AIsRoot: Boolean; const ATypes: array of string;
  const AList: TList<TTSNode>);
var
  I, J: Integer;
begin
  if N.IsNull then Exit;
  if (not AIsRoot) and ((N.NodeType = 'defProc') or (N.NodeType = 'lambda')) then Exit;
  for J:= Low(ATypes) to High(ATypes) do
    if N.NodeType = ATypes[J] then
    begin
      AList.Add(N);
      Break;
    end;
  for I:= 0 to N.NamedChildCount - 1 do GatherWalk(N.NamedChild(I), False, ATypes, AList);
end;

{ Every defProc of the file, nested ones included, in document order. }
procedure TOwnershipScan.GatherAllRoutines(const N: TTSNode; const AList: TList<TTSNode>);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then AList.Add(N);
  for I:= 0 to N.NamedChildCount - 1 do GatherAllRoutines(N.NamedChild(I), AList);
end;

{ Document-order walk; a nested routine or anonymous method is not entered
  (it has its own scan). }
procedure TOwnershipScan.Gather(const ARoot: TTSNode; const ATypes: array of string; const AList: TList<TTSNode>);
begin
  GatherWalk(ARoot, True, ATypes, AList);
end;

procedure TOwnershipScan.Emit(const ARule: string; const N: TTSNode; const AMsg, ASym: string);
var
  P, Q: TTSPoint;
  F   : TLintFinding;
  Key : string;
begin
  P:= N.StartPoint;
  Q:= N.EndPoint;
  Key:= Format('%s|%d|%d', [ARule, Integer(P.Row), Integer(P.Column)]);
  if FEmitted.ContainsKey(Key) then Exit;
  FEmitted.Add(Key, True);
  F:= Default(TLintFinding);
  F.RuleId    := ARule;
  F.Severity  := 'warning';
  F.Message   := AMsg;
  F.FilePath  := FFile;
  F.StartLine := Integer(P.Row) + 1;
  F.StartCol  := Integer(P.Column) + 1;
  F.EndLine   := Integer(Q.Row) + 1;
  F.EndCol    := Integer(Q.Column) + 1;
  F.SymbolName:= ASym;
  FFindings.Add(F);
end;

{ The call a statement makes: receiver, method and first argument. }
function TOwnershipScan.CallOf(const AStmt: TTSNode): TCallInfo;
var
  Kid, Ent, Args, A0: TTSNode;
  Dot               : Integer;
begin
  Result:= Default(TCallInfo);
  if (AStmt.NodeType <> 'statement') or (AStmt.NamedChildCount <> 1) then Exit;
  Kid:= AStmt.NamedChild(0);
  Result.Node:= Kid;
  if Kid.NodeType = 'exprCall' then
  begin
    Ent:= Kid.ChildByField('entity');
    Result.Callee:= Canon(NodeStr(Ent));
    if (Ent.NodeType = 'exprDot') then Result.RecvRaw:= Trim(NodeStr(Ent.ChildByField('lhs')));
    Args:= Kid.ChildByField('args');
    if (not Args.IsNull) and (Args.NamedChildCount > 0) then
    begin
      A0:= Args.NamedChild(0);
      Result.Arg0   := Canon(NodeStr(A0));
      Result.Arg0Raw:= Trim(NodeStr(A0));
    end;
  end
  else if (Kid.NodeType = 'exprDot') or (Kid.NodeType = 'identifier') then
  begin
    Result.Callee:= Canon(NodeStr(Kid));
    if Kid.NodeType = 'exprDot' then Result.RecvRaw:= Trim(NodeStr(Kid.ChildByField('lhs')));
  end
  else Exit;
  Dot:= LastDelimiter('.', Result.Callee);
  Result.Meth:= Copy(Result.Callee, Dot + 1, MaxInt);
  if Dot > 0 then Result.Recv:= Copy(Result.Callee, 1, Dot - 1);
end;

function TOwnershipScan.ClassOf(const ARoutine: TTSNode): string;
var
  Nm: string;
  D : Integer;
begin
  Result:= '';
  Nm:= Trim(NodeStr(ARoutine.ChildByField('header').ChildByField('name')));
  D:= LastDelimiter('.', Nm);
  if D > 1 then Result:= Copy(Nm, 1, D - 1);
end;

function TOwnershipScan.IsCtor(const ARoutine: TTSNode): Boolean;
var
  H: TTSNode;
  I: Integer;
begin
  Result:= False;
  H:= ARoutine.ChildByField('header');
  if H.IsNull then Exit;
  for I:= 0 to H.ChildCount - 1 do
    if H.Child(I).NodeType = 'kConstructor' then Exit(True);
end;

{ 'A, B: T;' -> A and B both typed T (canonical, blanks removed). }
procedure TOwnershipScan.ParseDecl(const AText: string; const AMap: TDictionary<string, string>;
  const AFields: TDictionary<string, Boolean>);
var
  P, Cut  : Integer;
  Names, T: string;
  Nm      : string;
begin
  P:= Pos(':', AText);
  if P < 2 then Exit;
  Names:= Copy(AText, 1, P - 1);
  T:= Copy(AText, P + 1, MaxInt);
  Cut:= Pos(';', T);
  if Cut > 0 then T:= Copy(T, 1, Cut - 1);
  Cut:= Pos('=', T);
  if Cut > 0 then T:= Copy(T, 1, Cut - 1);
  T:= StringReplace(StringReplace(StringReplace(Trim(T), ' ', '', [rfReplaceAll]), #13, '', [rfReplaceAll]),
    #10, '', [rfReplaceAll]);
  for Nm in Names.Split([',']) do
    if Trim(Nm) <> '' then
    begin
      AMap.AddOrSetValue(LowerCase(Trim(Nm)), T);
      if AFields <> nil then AFields.AddOrSetValue(LowerCase(Trim(Nm)), True);
    end;
end;

{ Locals (declVars only) go to ALocals; locals plus parameters go to AAll. }
procedure TOwnershipScan.LocalsOf(const ARoutine: TTSNode; const ALocals, AAll: TDictionary<string, string>);
var
  I, J  : Integer;
  K, D  : TTSNode;
  Args  : TTSNode;
begin
  for I:= 0 to ARoutine.NamedChildCount - 1 do
  begin
    K:= ARoutine.NamedChild(I);
    if K.NodeType <> 'declVars' then Continue;
    for J:= 0 to K.NamedChildCount - 1 do
    begin
      D:= K.NamedChild(J);
      if D.NodeType <> 'declVar' then Continue;
      ParseDecl(NodeStr(D), ALocals, nil);
      ParseDecl(NodeStr(D), AAll, nil);
    end;
  end;
  Args:= ARoutine.ChildByField('header').ChildByField('args');
  if Args.IsNull then Exit;
  for J:= 0 to Args.NamedChildCount - 1 do
  begin
    D:= Args.NamedChild(J);
    if D.NodeType = 'declArg' then ParseDecl(NodeStr(D), AAll, nil);
  end;
end;

{ 'tfoo.create' / 'unit.tfoo<x>.create': a class constructor call by the
  Delphi T-prefix convention. }
function TOwnershipScan.IsCreateText(const ACanon: string): Boolean;
var
  Cls: string;
  D  : Integer;
begin
  Result:= False;
  if not EndsText('.create', ACanon) then Exit;
  Cls:= Copy(ACanon, 1, Length(ACanon) - Length('.create'));
  D:= LastDelimiter('.', Cls);
  Cls:= Copy(Cls, D + 1, MaxInt);
  Result:= (Length(Cls) > 1) and (Cls[1] = 't');
end;

{ True when ARhs is `TFoo.Create` or `TFoo.Create(args)`; AArgs holds the
  canonical argument texts. }
function TOwnershipScan.CreateArgs(const ARhs: TTSNode; out AArgs: TArray<string>): Boolean;
var
  Args: TTSNode;
  I   : Integer;
begin
  AArgs:= nil;
  Result:= False;
  if ARhs.NodeType = 'exprDot' then
    Exit(IsCreateText(Canon(NodeStr(ARhs))));
  if ARhs.NodeType <> 'exprCall' then Exit;
  if not IsCreateText(Canon(NodeStr(ARhs.ChildByField('entity')))) then Exit;
  Result:= True;
  Args:= ARhs.ChildByField('args');
  if Args.IsNull then Exit;
  SetLength(AArgs, Args.NamedChildCount);
  for I:= 0 to Args.NamedChildCount - 1 do AArgs[I]:= Canon(NodeStr(Args.NamedChild(I)));
end;

procedure TOwnershipScan.CollectFileFacts;
var
  Decls: TList<TTSNode>;
  N    : TTSNode;
  Types: TList<TTSNode>;
  Cls  : TTSNode;
  CName: string;
  Flds : TList<TTSNode>;
  F    : TTSNode;
  Tmp  : TDictionary<string, string>;
  Pair : TPair<string, string>;
begin
  Decls:= TList<TTSNode>.Create;
  Types:= TList<TTSNode>.Create;
  Flds := TList<TTSNode>.Create;
  Tmp  := TDictionary<string, string>.Create;
  try
    Gather(FRootNode, ['declVar', 'declField'], Decls);
    for N in Decls do ParseDecl(NodeStr(N), FFileTypes, nil);
    Gather(FRootNode, ['declType'], Types);
    for N in Types do
    begin
      Cls:= N.ChildByField('type');
      if (not Cls.IsNull) and (Cls.NodeType = 'type') and (Cls.NamedChildCount > 0) then Cls:= Cls.NamedChild(0);
      if Cls.IsNull or (Cls.NodeType <> 'declClass') then Continue;
      CName:= LowerCase(StripGeneric(Trim(NodeStr(N.ChildByField('name')))));
      Flds.Clear;
      Gather(Cls, ['declField'], Flds);
      for F in Flds do
      begin
        Tmp.Clear;
        ParseDecl(NodeStr(F), Tmp, FFieldNames);
        for Pair in Tmp do FFieldType.AddOrSetValue(CName + '.' + Pair.Key, Pair.Value);
      end;
    end;
  finally
    Tmp.Free;
    Flds.Free;
    Types.Free;
    Decls.Free;
  end;
end;

{ Records what each method of AClass does with a field: frees it, hands it to a
  call, or stores it elsewhere -- all of which stop it being a leak. }
procedure TOwnershipScan.MarkHandled(const ARoutine: TTSNode; const AClass: string);
var
  L  : TList<TTSNode>;
  N  : TTSNode;
  C  : TCallInfo;
  I  : Integer;
begin
  L:= TList<TTSNode>.Create;
  try
    Gather(ARoutine, ['statement', 'exprArgs', 'assignment'], L);
    for N in L do
      if N.NodeType = 'statement' then
      begin
        C:= CallOf(N);
        if (C.Recv <> '') and ((C.Meth = 'free') or (C.Meth = 'disposeof') or (C.Meth = 'release')) then
          FHandled.AddOrSetValue(AClass + '|' + C.Recv, True);
      end
      else if N.NodeType = 'exprArgs' then
      begin
        for I:= 0 to N.NamedChildCount - 1 do
          FHandled.AddOrSetValue(AClass + '|' + Canon(NodeStr(N.NamedChild(I))), True);
      end
      else
        FHandled.AddOrSetValue(AClass + '|' + Canon(NodeStr(N.ChildByField('rhs'))), True);
  finally
    L.Free;
  end;
end;

procedure TOwnershipScan.CheckFieldCreated;
var
  R, A    : TTSNode;
  Assigns : TList<TTSNode>;
  Cls, Fld: string;
  FldRaw  : string;
  ClsRaw  : string;
  FldType : string;
  Args    : TArray<string>;
  Arg     : string;
  Owned   : Boolean;
begin
  Assigns:= TList<TTSNode>.Create;
  try
    for R in FRoutines do
    begin
      ClsRaw:= ClassOf(R);
      if ClsRaw <> '' then MarkHandled(R, LowerCase(ClsRaw));
    end;
    for R in FRoutines do
    begin
      if not IsCtor(R) then Continue;
      ClsRaw:= ClassOf(R);
      if ClsRaw = '' then Continue;
      Cls:= LowerCase(ClsRaw);
      Assigns.Clear;
      Gather(R, ['assignment'], Assigns);
      for A in Assigns do
      begin
        FldRaw:= Trim(NodeStr(A.ChildByField('lhs')));
        if StartsText('self.', FldRaw) then Delete(FldRaw, 1, Length('self.'));
        Fld:= LowerCase(FldRaw);
        if not FFieldType.TryGetValue(Cls + '.' + Fld, FldType) then Continue;
        if not CreateArgs(A.ChildByField('rhs'), Args) then Continue;
        Owned:= False;
        for Arg in Args do
          if (Arg = 'self') or (Arg = 'aowner') or (Arg = 'owner') or (Arg = 'powner') then Owned:= True;
        if Owned then Continue;
        if (Length(Args) > 0) and IsOwnedControlCreate(Canon(NodeStr(A.ChildByField('rhs')))) then Continue;
        if (Length(FldType) > 1) and (FldType[1] = 'I') and CharInSet(FldType[2], ['A'..'Z']) then Continue;
        if SameText(FldType, 'TRegEx') or SameText(FldType, 'TMatch') or SameText(FldType, 'TGUID') then Continue;
        if FHandled.ContainsKey(Cls + '|' + Fld) then Continue;
        Emit(RULE_FIELD, A, Format('Field %s is created in the constructor of %s but no method of the class frees it, ' +
          'hands it on or stores it elsewhere -- it leaks when the owner is destroyed; free it in the destructor',
          [FldRaw, ClsRaw]), ClsRaw + '.' + FldRaw);
      end;
    end;
  finally
    Assigns.Free;
  end;
end;

{ Ownership of a container created by AArgs: 1 = owns its items, 2 = does not. }
function ContainerOwnership(const ATypeName: string; const AArgs: TArray<string>): Integer;
var
  Arg: string;
begin
  if SameText(StripGeneric(ATypeName), 'tobjectdictionary') then
  begin
    Result:= 2;
    for Arg in AArgs do
      if ContainsText(Arg, 'doownsvalues') then Result:= 1;
  end
  else
  begin
    Result:= 1;
    for Arg in AArgs do
      if Arg = 'false' then Result:= 2;
  end;
end;

procedure TOwnershipScan.CheckOwnedItems;
var
  I       : Integer;
  Locals  : TDictionary<string, string>;
  All     : TDictionary<string, string>;
  Assigns : TList<TTSNode>;
  A       : TTSNode;
  Nm, T   : string;
  Args    : TArray<string>;
  Key     : string;
  Flag    : Integer;
begin
  { pass 1: how is each container created? }
  Locals := TDictionary<string, string>.Create;
  All    := TDictionary<string, string>.Create;
  Assigns:= TList<TTSNode>.Create;
  try
    for I:= 0 to FRoutines.Count - 1 do
    begin
      Locals.Clear;
      All.Clear;
      LocalsOf(FRoutines[I], Locals, All);
      Assigns.Clear;
      Gather(FRoutines[I], ['assignment'], Assigns);
      for A in Assigns do
      begin
        Nm:= Canon(NodeStr(A.ChildByField('lhs')));
        if (not All.TryGetValue(Nm, T)) and (not FFileTypes.TryGetValue(Nm, T)) then Continue;
        if not IsContainerType(T) then Continue;
        if not CreateArgs(A.ChildByField('rhs'), Args) then Continue;
        Key:= if Locals.ContainsKey(Nm) then IntToStr(I) + '|' + Nm else Nm;
        if not FOwnFlags.TryGetValue(Key, Flag) then Flag:= 0;
        FOwnFlags.AddOrSetValue(Key, Flag or ContainerOwnership(T, Args));
      end;
    end;
  finally
    Assigns.Free;
    All.Free;
    Locals.Free;
  end;
  for I:= 0 to FRoutines.Count - 1 do CheckOwnedRoutine(FRoutines[I], I);
end;

procedure TOwnershipScan.CheckForeachFree(const AForeach: TTSNode; const AOwning: TDictionary<string, string>);
var
  Inner: TList<TTSNode>;
  S    : TTSNode;
  C    : TCallInfo;
  Lst  : string;
  Iter : string;
begin
  Lst:= Canon(NodeStr(AForeach.ChildByField('iterable')));
  if not AOwning.ContainsKey(Lst) then Exit;
  Iter:= Trim(NodeStr(AForeach.ChildByField('iterator')));
  if StartsText('var ', Iter) then Delete(Iter, 1, Length('var '));
  Iter:= Canon(Iter);
  Inner:= TList<TTSNode>.Create;
  try
    Gather(AForeach.ChildByField('body'), ['statement'], Inner);
    for S in Inner do
    begin
      C:= CallOf(S);
      if ((C.Recv = Iter) and (C.Meth = 'free')) or ((C.Callee = 'freeandnil') and (C.Arg0 = Iter)) then
        Emit(RULE_OWNED, S.NamedChild(0), Format('%s is freed here but the container %s already owns its items -- ' +
          'double free; drop the Free or create the container with OwnsObjects = False', [Trim(NodeStr(S.NamedChild(0))), Lst]), '');
    end;
  finally
    Inner.Free;
  end;
end;

procedure TOwnershipScan.CheckOwnedRoutine(const ARoutine: TTSNode; const AIdx: Integer);
var
  Locals, All: TDictionary<string, string>;
  Owning     : TDictionary<string, string>;
  Alias      : TDictionary<string, string>;
  Extracted  : TDictionary<string, Boolean>;
  Nodes      : TList<TTSNode>;
  N          : TTSNode;
  C          : TCallInfo;
  Nm, T, Key : string;
  Flag       : Integer;
  Rhs        : TTSNode;
  RhsC, Base : string;
begin
  Locals   := TDictionary<string, string>.Create;
  All      := TDictionary<string, string>.Create;
  Owning   := TDictionary<string, string>.Create;
  Alias    := TDictionary<string, string>.Create;
  Extracted:= TDictionary<string, Boolean>.Create;
  Nodes    := TList<TTSNode>.Create;
  try
    LocalsOf(ARoutine, Locals, All);
    { owning containers visible here: locals, then file-wide names }
    for Nm in All.Keys do
      if IsContainerType(All[Nm]) and FOwnFlags.TryGetValue(IntToStr(AIdx) + '|' + Nm, Flag) and (Flag = 1) then
        Owning.AddOrSetValue(Nm, '');
    for Nm in FFileTypes.Keys do
      if IsContainerType(FFileTypes[Nm]) and (not All.ContainsKey(Nm)) and FOwnFlags.TryGetValue(Nm, Flag) and (Flag = 1) then
        Owning.AddOrSetValue(Nm, '');
    if Owning.Count = 0 then Exit;
    Gather(ARoutine, ['foreach', 'assignment', 'statement'], Nodes);
    for N in Nodes do
      if N.NodeType = 'statement' then
      begin
        C:= CallOf(N);
        if (C.Meth = 'extract') and (C.Recv <> '') then Extracted.AddOrSetValue(C.Recv, True);
      end;
    for N in Nodes do
    begin
      if N.NodeType = 'foreach' then CheckForeachFree(N, Owning)
      else if N.NodeType = 'assignment' then
      begin
        Nm := Canon(NodeStr(N.ChildByField('lhs')));
        Rhs:= N.ChildByField('rhs');
        Alias.Remove(Nm);
        if Rhs.NodeType = 'exprSubscript' then
        begin
          Base:= Canon(NodeStr(Rhs.ChildByField('entity')));
          if EndsText('.items', Base) then Base:= Copy(Base, 1, Length(Base) - Length('.items'));
          RhsC:= Base;
          if Owning.ContainsKey(RhsC) then Alias.AddOrSetValue(Nm, RhsC);
        end;
      end
      else
      begin
        C:= CallOf(N);
        if (C.Meth = 'add') and Owning.ContainsKey(C.Recv) and (C.Arg0 <> '') and (not IsCreateText(C.Arg0)) and
           (not ContainsStr(C.Arg0, '(')) then
          Alias.AddOrSetValue(C.Arg0, C.Recv)
        else if ((C.Meth = 'free') and (C.Recv <> '')) or ((C.Callee = 'freeandnil') and (C.Arg0 <> '')) then
        begin
          Key:= if C.Callee = 'freeandnil' then C.Arg0 else C.Recv;
          if Alias.TryGetValue(Key, T) and (not Extracted.ContainsKey(T)) then
            Emit(RULE_OWNED, C.Node, Format('%s is freed here but the container %s already owns its items -- ' +
              'double free; drop the Free or create the container with OwnsObjects = False', [Trim(NodeStr(C.Node)), T]), '');
        end;
      end;
    end;
  finally
    Nodes.Free;
    Extracted.Free;
    Alias.Free;
    Owning.Free;
    All.Free;
    Locals.Free;
  end;
end;

procedure TOwnershipScan.CheckMismatch(const ARoutine: TTSNode);
var
  Locals, All: TDictionary<string, string>;
  Fam        : TDictionary<string, string>;
  Nodes      : TList<TTSNode>;
  N, Rhs     : TTSNode;
  C          : TCallInfo;
  P, Allocd  : string;
  Rel, Entity: string;
  Raw, Repl  : string;
  Args       : TArray<string>;

  function ReplacementFor(const AFam, ARaw: string): string;
  begin
    if AFam = FAM_MEM then Result:= 'FreeMem(' + ARaw + ')'
    else if AFam = FAM_NEW then Result:= 'Dispose(' + ARaw + ')'
    else if AFam = FAM_STR then Result:= 'StrDispose(' + ARaw + ')'
    else Result:= ARaw + '.Free';
  end;

  function FamilyName(const AFam: string): string;
  begin
    Result:= FAMILY_NAMES[IndexStr(AFam, [FAM_MEM, FAM_NEW, FAM_STR, FAM_OBJ])];
  end;

begin
  Locals:= TDictionary<string, string>.Create;
  All   := TDictionary<string, string>.Create;
  Fam   := TDictionary<string, string>.Create;
  Nodes := TList<TTSNode>.Create;
  try
    LocalsOf(ARoutine, Locals, All);
    Gather(ARoutine, ['assignment', 'statement'], Nodes);
    for N in Nodes do
    begin
      if N.NodeType = 'assignment' then
      begin
        P:= Canon(NodeStr(N.ChildByField('lhs')));
        Rhs:= N.ChildByField('rhs');
        Fam.Remove(P);
        if Rhs.NodeType = 'exprCall' then
        begin
          Entity:= Canon(NodeStr(Rhs.ChildByField('entity')));
          if (Entity = 'getmem') or (Entity = 'allocmem') or (Entity = 'reallocmem') then Fam.AddOrSetValue(P, FAM_MEM)
          else if (Entity = 'stralloc') or (Entity = 'strnew') then Fam.AddOrSetValue(P, FAM_STR);
        end;
        if CreateArgs(Rhs, Args) then Fam.AddOrSetValue(P, FAM_OBJ);
        Continue;
      end;
      C:= CallOf(N);
      if C.Callee = '' then Continue;
      if AllocOf(C, P, Allocd) then
      begin
        Fam.AddOrSetValue(P, Allocd);
        Continue;
      end;
      if not ReleaseOf(C, Rel, P, Raw) then Continue;
      if (Length(P) > 1) and (P[1] = '@') and ((Rel = FAM_MEM) or (Rel = FAM_NEW)) then
      begin
        if Locals.ContainsKey(Copy(P, 2, MaxInt)) then
          Emit(RULE_MISMATCH, C.Node, Format('%s releases the address of a local variable -- it was never ' +
            'allocated on the heap; release the pointer that was allocated', [Trim(NodeStr(C.Node))]), '');
        Continue;
      end;
      if Fam.TryGetValue(P, Allocd) then
      begin
        if Allocd <> Rel then
        begin
          Repl:= ReplacementFor(Allocd, Raw);
          Emit(RULE_MISMATCH, C.Node, Format('%s was allocated by %s but is released by %s -- heap corruption; use %s',
            [Raw, FamilyName(Allocd), Trim(NodeStr(C.Node)), Repl]), Repl);
        end;
        Fam.Remove(P);
      end;
    end;
  finally
    Nodes.Free;
    Fam.Free;
    All.Free;
    Locals.Free;
  end;
end;

procedure TOwnershipScan.CheckFotRoutine(const ARoutine: TTSNode; const AIdx: Integer);
var
  Fot         : TDictionary<string, Boolean>;
  Nodes       : TList<TTSNode>;
  N           : TTSNode;
  C           : TCallInfo;
  Lhs, Recv   : string;
  Target      : string;
begin
  Fot  := TDictionary<string, Boolean>.Create;
  Nodes:= TList<TTSNode>.Create;
  try
    Gather(ARoutine, ['assignment', 'statement'], Nodes);
    for N in Nodes do
    begin
      if N.NodeType = 'assignment' then
      begin
        Lhs:= Canon(NodeStr(N.ChildByField('lhs')));
        if EndsText('.freeonterminate', Lhs) then
        begin
          Recv:= Copy(Lhs, 1, Length(Lhs) - Length('.freeonterminate'));
          if Canon(NodeStr(N.ChildByField('rhs'))) = 'true' then
          begin
            Fot.AddOrSetValue(Recv, True);
            if FFieldNames.ContainsKey(Recv) then
            begin
              FFotFields.AddOrSetValue(Recv, True);
              FFotSetBy.AddOrSetValue(IntToStr(AIdx) + '|' + Recv, True);
            end;
          end
          else Fot.Remove(Recv);
        end
        else Fot.Remove(Lhs);
        Continue;
      end;
      C:= CallOf(N);
      Target:= '';
      if (C.Recv <> '') and ((C.Meth = 'waitfor') or (C.Meth = 'free')) then Target:= C.Recv
      else if (C.Callee = 'freeandnil') and (C.Arg0 <> '') then Target:= C.Arg0;
      if (Target <> '') and Fot.ContainsKey(Target) then
        Emit(RULE_FOT, C.Node, Format('%s.FreeOnTerminate is True, so the thread frees itself -- %s may touch a ' +
          'thread that is already gone; clear FreeOnTerminate or drop the wait/free', [Target, Trim(NodeStr(C.Node))]), '');
    end;
  finally
    Nodes.Free;
    Fot.Free;
  end;
end;

{ A field whose thread sets FreeOnTerminate in one method and is waited for or
  freed in another. }
procedure TOwnershipScan.CheckFotOtherMethods;
var
  I     : Integer;
  Nodes : TList<TTSNode>;
  Locals, All: TDictionary<string, string>;
  N     : TTSNode;
  C     : TCallInfo;
  Target: string;
begin
  if FFotFields.Count = 0 then Exit;
  Nodes := TList<TTSNode>.Create;
  Locals:= TDictionary<string, string>.Create;
  All   := TDictionary<string, string>.Create;
  try
    for I:= 0 to FRoutines.Count - 1 do
    begin
      Locals.Clear;
      All.Clear;
      LocalsOf(FRoutines[I], Locals, All);
      Nodes.Clear;
      Gather(FRoutines[I], ['statement'], Nodes);
      for N in Nodes do
      begin
        C:= CallOf(N);
        Target:= '';
        if (C.Recv <> '') and ((C.Meth = 'waitfor') or (C.Meth = 'free')) then Target:= C.Recv
        else if (C.Callee = 'freeandnil') and (C.Arg0 <> '') then Target:= C.Arg0;
        if (Target = '') or (not FFotFields.ContainsKey(Target)) or All.ContainsKey(Target) then Continue;
        if FFotSetBy.ContainsKey(IntToStr(I) + '|' + Target) then Continue;
        Emit(RULE_FOT, C.Node, Format('%s.FreeOnTerminate is set to True in another method, so the thread frees ' +
          'itself -- %s may touch a thread that is already gone', [Target, Trim(NodeStr(C.Node))]), '');
      end;
    end;
  finally
    All.Free;
    Locals.Free;
    Nodes.Free;
  end;
end;

procedure TOwnershipScan.CheckPairs(const ARoutine: TTSNode);
var
  Locals, All: TDictionary<string, string>;
  Dots       : TList<TTSNode>;
  Calls      : TList<TPairCall>;
  D          : TTSNode;
  Nm         : string;
  I, K       : Integer;
  PC         : TPairCall;
  B, E       : TPairCall;
  HasEnd     : Boolean;
  Safe       : Boolean;
  Sym        : string;

  function PairIndex(const AName: string; AIsBegin: Boolean): Integer;
  var
    J: Integer;
  begin
    Result:= -1;
    for J:= 0 to PAIR_COUNT - 1 do
      if (AIsBegin and (PAIR_BEGIN[J] = AName)) or ((not AIsBegin) and (PAIR_END[J] = AName)) then Exit(J);
    if (not AIsBegin) and (AName = 'rollback') then Result:= PAIR_TRANSACTION;
  end;

  procedure Context(const AN: TTSNode; out AInFin, AInExc: Boolean);
  var
    Q  : TTSNode;
    J  : Integer;
    Kid: TTSNode;
  begin
    AInFin:= False;
    AInExc:= False;
    Q:= AN.Parent;
    while (not Q.IsNull) and (Q.NodeType <> 'defProc') do
    begin
      if Q.NodeType = 'try' then
        for J:= 0 to Q.ChildCount - 1 do
        begin
          Kid:= Q.Child(J);
          if (Kid.NodeType = 'kFinally') and (AN.StartByte >= Kid.EndByte) then AInFin:= True;
          if (Kid.NodeType = 'kExcept') and (AN.StartByte >= Kid.EndByte) then AInExc:= True;
        end;
      Q:= Q.Parent;
    end;
  end;

  function StatementOf(const AN: TTSNode): TTSNode;
  var
    Q: TTSNode;
  begin
    Q:= AN.Parent;
    if (not Q.IsNull) and (Q.NodeType = 'exprCall') then Q:= Q.Parent;
    Result:= Default(TTSNode);
    if (not Q.IsNull) and (Q.NodeType = 'statement') then Result:= Q;
  end;

  function SameParent(const A1, A2: TTSNode): Boolean;
  var
    P1, P2: TTSNode;
  begin
    P1:= A1.Parent;
    P2:= A2.Parent;
    Result:= (not P1.IsNull) and (not P2.IsNull) and (P1.StartByte = P2.StartByte) and (P1.EndByte = P2.EndByte) and
      (P1.NodeType = P2.NodeType);
  end;

begin
  Locals:= TDictionary<string, string>.Create;
  All   := TDictionary<string, string>.Create;
  Dots  := TList<TTSNode>.Create;
  Calls := TList<TPairCall>.Create;
  try
    LocalsOf(ARoutine, Locals, All);
    Gather(ARoutine, ['exprDot'], Dots);
    for D in Dots do
    begin
      Nm:= LowerCase(Trim(NodeStr(D.ChildByField('rhs'))));
      PC:= Default(TPairCall);
      PC.Node:= D;
      PC.Recv:= Canon(NodeStr(D.ChildByField('lhs')));
      K:= PairIndex(Nm, True);
      if K >= 0 then PC.IsBegin:= True else K:= PairIndex(Nm, False);
      if K < 0 then Continue;
      PC.Idx:= K;
      Context(D, PC.InFin, PC.InExc);
      Calls.Add(PC);
    end;
    for I:= 0 to Calls.Count - 1 do
    begin
      B:= Calls[I];
      if not B.IsBegin then Continue;
      HasEnd:= False;
      Safe  := False;
      E:= Default(TPairCall);
      for K:= 0 to Calls.Count - 1 do
      begin
        PC:= Calls[K];
        if PC.IsBegin or (PC.Idx <> B.Idx) or (PC.Recv <> B.Recv) or (PC.Node.StartByte <= B.Node.StartByte) then Continue;
        if not HasEnd then E:= PC;
        HasEnd:= True;
        if PC.InFin or ((B.Idx = PAIR_TRANSACTION) and PC.InExc) then Safe:= True;
      end;
      if Safe then Continue;
      Sym:= '';
      if HasEnd then
      begin
        if (not StatementOf(B.Node).IsNull) and (not StatementOf(E.Node).IsNull) and
           SameParent(StatementOf(B.Node), StatementOf(E.Node)) then
          Sym:= IntToStr(Integer(E.Node.StartPoint.Row) + 1);
        Emit(RULE_PAIR, B.Node, Format('%s is not paired with %s inside a finally block -- an exception between the ' +
          'two leaves it unbalanced; wrap the work in try / finally', [Trim(NodeStr(B.Node)), PAIR_END[B.Idx]]), Sym);
      end
      else if Locals.ContainsKey(B.Recv) then
        Emit(RULE_PAIR, B.Node, Format('%s has no matching %s in this routine -- the local is left in the begun state',
          [Trim(NodeStr(B.Node)), PAIR_END[B.Idx]]), '');
    end;
  finally
    Calls.Free;
    Dots.Free;
    All.Free;
    Locals.Free;
  end;
end;

function TOwnershipScan.Run(const ARoot: TTSNode): TArray<TLintFinding>;
var
  Defs: TList<TTSNode>;
  I   : Integer;
begin
  FRootNode:= ARoot;
  Defs:= TList<TTSNode>.Create;
  try
    GatherAllRoutines(ARoot, Defs);
    FRoutines.AddRange(Defs);
  finally
    Defs.Free;
  end;
  CollectFileFacts;
  CheckFieldCreated;
  CheckOwnedItems;
  for I:= 0 to FRoutines.Count - 1 do
  begin
    CheckMismatch(FRoutines[I]);
    CheckFotRoutine(FRoutines[I], I);
    CheckPairs(FRoutines[I]);
  end;
  CheckFotOtherMethods;
  Result:= FFindings.ToArray;
end;

class function TOwnershipChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@1578
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;  // dl:ok unused-parameter@9a67
var
  PF  : TParsedFile    ;
  Scan: TOwnershipScan ;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Scan:= TOwnershipScan.Create(AFile, PF.Src);
  try
    Result:= Scan.Run(PF.Tree.RootNode);
  finally
    Scan.Free;
  end;
end;

{ ---- autofixes ------------------------------------------------------------ }

{ mismatched-alloc-free: swap the release call for the allocation family's. The
  checker put the full replacement text in SymbolName; '' (a @Local release)
  has no fix. Single-line spans only. }
function FixMismatchedAlloc(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line, Span: string;
  E         : TTextEdit;
begin
  Result:= nil;
  if (AFinding.SymbolName = '') or (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  Span:= Copy(Line, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  if Span = '' then Exit;
  E:= Default(TTextEdit);
  E.FilePath  := AFinding.FilePath;
  E.Kind      := tekReplaceInLine;
  E.Line      := AFinding.StartLine;
  E.Col       := AFinding.StartCol;
  E.EndCol    := AFinding.EndCol;
  E.Text      := AFinding.SymbolName;
  E.ExpectText:= Span;
  Result:= [E];
end;

function LeadingBlanks(const ALine: string): string;
var
  N: Integer;
begin
  N:= 0;
  while (N < Length(ALine)) and CharInSet(ALine[N + 1], [' ', #9]) do Inc(N);
  Result:= Copy(ALine, 1, N);
end;

function IsSingleStatementLine(const ALine: string): Boolean;
var
  T: string;
begin
  T:= Trim(ALine);
  Result:= (T <> '') and (T[Length(T)] = ';') and (Pos(';', T) = Length(T)) and (not ContainsStr(T, '//')) and
    (not ContainsStr(T, '{'));
end;

{ begin-end-pair-not-in-finally (present-End shape): the Begin call and the End
  call each sit alone on their line, in the same block. The statements between
  them move into try, the End call into finally. SymbolName holds the End line. }
function FixBeginEndPair(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  B, E   : Integer;
  Wrap   : TTextEdit;
begin
  Result:= nil;
  if not TryStrToInt(AFinding.SymbolName, E) then Exit;
  B:= AFinding.StartLine;
  if (B < 1) or (E < B + 2) or (E > ALines.Count) then Exit;
  if not (IsSingleStatementLine(ALines[B - 1]) and IsSingleStatementLine(ALines[E - 1])) then Exit;
  if not WrapInTryFinally(AFinding.FilePath, ALines, B + 1, E - 1, Trim(ALines[E - 1]), LeadingBlanks(ALines[B - 1]), Wrap) then Exit;
  { The wrap replaces B+1..E-1; the End call it moved into the finally goes too. }
  Wrap.EndLine:= E;
  Result:= [Wrap];
end;

{ field-created-not-freed: insert FreeAndNil(<field>); before `inherited` in the
  EXISTING destructor of the class (SymbolName = 'TClass.FField'). No
  destructor, or none with an `inherited` line, means no fix. }
function FixFieldDestructor(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Cls, Fld, Lo : string;
  Dot, I, J    : Integer;
  Indent, BodyI: string;
  Anchor       : Integer;
  E, U         : TTextEdit;
begin
  Result:= nil;
  Dot:= Pos('.', AFinding.SymbolName);
  if Dot < 2 then Exit;
  Cls:= Copy(AFinding.SymbolName, 1, Dot - 1);
  Fld:= Copy(AFinding.SymbolName, Dot + 1, MaxInt);
  for I:= 0 to ALines.Count - 1 do
  begin
    Lo:= LowerCase(Trim(ALines[I]));
    if not StartsText('destructor ' + LowerCase(Cls) + '.destroy', Lo) then Continue;
    Indent:= LeadingBlanks(ALines[I]);
    for J:= I + 1 to ALines.Count - 1 do
    begin
      Lo:= LowerCase(Trim(ALines[J]));
      if (Lo = 'end;') and (LeadingBlanks(ALines[J]) = Indent) then Exit;
      if StartsText('inherited', Lo) then
      begin
        Anchor:= J;
        BodyI:= LeadingBlanks(ALines[J]);
        E:= Default(TTextEdit);
        E.FilePath  := AFinding.FilePath;
        E.Kind      := tekInsertLines;
        E.Line      := Anchor;
        E.Text      := BodyI + 'FreeAndNil(' + Fld + ');';
        E.ExpectLine:= Anchor;
        E.ExpectText:= Trim(ALines[Anchor - 1]);
        Result:= [E];
        if EnsureImplUses(AFinding.FilePath, ALines, 'System.SysUtils', U) then Result:= Result + [U];
        Exit;
      end;
    end;
    Exit;
  end;
end;

initialization
  RegisterFixer('mismatched-alloc-free', FixMismatchedAlloc, True);
  RegisterFixer('begin-end-pair-not-in-finally', FixBeginEndPair);
  RegisterFixer('field-created-not-freed', FixFieldDestructor, True);

end.
