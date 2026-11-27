unit DRagLint.V156.OOA1.Support;

{ Wave v156 lane OOA-1 -- helpers of DRagLint.V156.OOA1 (private to the lane).
    ambiguous-unit-reference (G-06)  a bare name two used units both declare: the last unit in the uses list wins
    assignment-narrows       (G-15)  a wider integer assigned to a narrower integer variable by plain assignment
  Every check is conservative: a shape the lane cannot prove stays silent. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  RULE_AMBIGUOUS_UNIT_REFERENCE = 'ambiguous-unit-reference';
  RULE_ASSIGNMENT_NARROWS = 'assignment-narrows';

/// <summary>ambiguous-unit-reference of one project.</summary>
/// <param name="ACtx">The project; Store is not nil.</param>
/// <returns>One finding per (unit, name) at the first bare reference; nil when none.</returns>
/// <remarks>Only the directly used PROJECT units are compared (a library unit is not in the project index).
/// A name is left alone when the using unit declares it too, when the reference is qualified or bound to a local
/// or member, when the declarations are an overload set with differing signatures, or when they are identical
/// type aliases. A reference inside a method is judged only when no class, in the project or the library, has a
/// member of that name (an inherited member would win over both units).</remarks>
function CheckAmbiguousUnitReference(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;

/// <summary>assignment-narrows of one unit.</summary>
/// <param name="ACtx">The file; Store must hold ref_types for it (index 1.44 or later), else nil.</param>
/// <returns>One finding per narrowing assignment; nil when none.</returns>
/// <remarks>Judged only when both sides are a plain name, a member name or a call of one, both types are integer
/// types of known width and the right is wider. Silent for a constant, an explicit cast, a masked or computed
/// value, an overloaded routine, anything inside `with`, and a line that already carries an imported compiler
/// finding.</remarks>
function CheckAssignmentNarrows(const ACtx: TV151FileCtx): TArray<TLintFinding>;

implementation

uses
  System.Generics.Collections
  , System.StrUtils
  , TreeSitter
  , DRagLint.Core.Interfaces
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Lint.RefTypeRules
  ;

const
  SEVERITY_WARNING = 'warning';
  NODE_ASSIGN = 'assignment';
  NODE_CALL = 'exprCall';
  NODE_DOT = 'exprDot';
  NODE_PARENS = 'exprParens';
  NODE_WITH = 'with';
  NODE_IDENT = 'identifier';
  OP_ASSIGN = 'kAssign';
  FIELD_LHS = 'lhs';
  FIELD_RHS = 'rhs';
  FIELD_OP = 'operator';
  FIELD_ENTITY = 'entity';
  OVERLOAD_WORD = 'overload';
  SECTION_INTERFACE = 'interface';
  KIND_MEMBER_ACCESS = 'member-access';
  MAX_ALIAS_HOPS = 4;

{ ---- ambiguous-unit-reference ---- }

type
  /// <summary>One unit-level declaration of a used unit.</summary>
  TUnitDecl = record
    UnitName: string;
    Sym     : TSymbol;
  end;

function IsRoutineKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skProcedure, skFunction];
end;

{ The interface-section, unit-level declarations of one file: name (lower case) -> symbols. }
function UnitLevelDecls(const AStore: ISymbolStore; const APath: string; out AUnitId: Int64;
  out AUnitName: string): TDictionary<string, TArray<TSymbol>>;
begin
  Result:= TDictionary<string, TArray<TSymbol>>.Create;
  AUnitId:= 0;
  AUnitName:= '';
  var Syms: TArray<TSymbol>:= AStore.FindSymbolsByFile(APath);
  for var S: TSymbol in Syms do
    if S.Kind = skUnit then
    begin
      AUnitId  := S.Id;
      AUnitName:= S.Name;
      Break;
    end;
  if AUnitId = 0 then Exit;
  for var S: TSymbol in Syms do
  begin
    if (S.ParentId <> AUnitId) or (S.Kind in [skUnit, skProgram, skPackage]) then Continue;
    var Key: string:= S.Name.ToLower;
    var Old: TArray<TSymbol>;
    if not Result.TryGetValue(Key, Old) then Old:= nil;
    Result.AddOrSetValue(Key, Old + [S]);
  end;
end;

{ True when every other declaration of the group is a type alias that names AGroup[ATarget] (X = Unit.X): one type under two names. }
function AllAliasOfTarget(const AGroup: TArray<TUnitDecl>; ATarget: Integer): Boolean;
begin
  Result:= True;
  for var I: Integer:= 0 to High(AGroup) do
    if I <> ATarget then
      if (AGroup[I].Sym.Kind <> skTypeAlias)
        or not SameText(AGroup[I].Sym.Signature, AGroup[ATarget].UnitName + '.' + AGroup[ATarget].Sym.Name) then
        Exit(False);
end;

{ True when a group of same-named declarations is an overload set or an alias set the compiler accepts. }function IsBenignGroup(const AGroup: TArray<TUnitDecl>): Boolean;
begin
  Result:= False;
  var AllRoutines: Boolean:= True;
  var AnyOverload: Boolean:= False;
  var AllAlias   : Boolean:= True;
  var SameSig    : Boolean:= True;
  var AllConst   : Boolean:= True;
  for var I: Integer:= 0 to High(AGroup) do
  begin
    var S: TSymbol:= AGroup[I].Sym;
    if not IsRoutineKind(S.Kind) then AllRoutines:= False;
    if S.Directives.ToLower.Contains(OVERLOAD_WORD) or S.Modifiers.ToLower.Contains(OVERLOAD_WORD) then AnyOverload:= True;
    if S.Kind <> skTypeAlias then AllAlias:= False;
    if S.Kind <> skConstDecl then AllConst:= False;
    if not SameText(S.Signature, AGroup[0].Sym.Signature) then SameSig:= False;
  end;
  if AllRoutines and AnyOverload and not SameSig then Exit(True);
  if AllAlias and SameSig then Exit(True);
  { v156 FP-1: identical constants (same type and value) and X = Unit.X redirects cannot change what a reference means }
  if AllConst and SameSig and (AGroup[0].Sym.Signature <> '') then Exit(True);
  for var T: Integer:= 0 to High(AGroup) do
    if AllAliasOfTarget(AGroup, T) then Exit(True);
end;

function HasMemberNamed(const AStore, ALibStore: ISymbolStore; const AName: string; AUnitIds: TDictionary<Int64, Boolean>): Boolean;
begin
  Result:= False;
  for var S: TSymbol in AStore.FindSymbolsByExactName(AName) do
    if not AUnitIds.ContainsKey(S.ParentId) then Exit(True);
  if ALibStore <> nil then
    for var S: TSymbol in ALibStore.FindSymbolsByExactName(AName) do
      if (S.Kind in [skMethod, skProperty, skField, skProcedure, skFunction, skConstructor]) and (S.ParentId <> 0) then
      begin
        var P: TSymbol:= ALibStore.GetSymbolById(S.ParentId);
        if P.Kind in [skClass, skRecord, skInterface] then Exit(True);
      end;
end;

function MakeFinding(const AFileId: Int64; const APath: string; const ARef: TReference; const AMessage: string;
  const AName: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId    := RULE_AMBIGUOUS_UNIT_REFERENCE;
  Result.Severity  := SEVERITY_WARNING;
  Result.FileId    := AFileId;
  Result.FilePath  := APath;
  Result.StartLine := ARef.StartLine;
  Result.StartCol  := ARef.StartCol;
  Result.EndLine   := ARef.EndLine;
  Result.EndCol    := ARef.EndCol;
  Result.SymbolName:= AName;
  Result.Message   := AMessage;
end;

function CheckAmbiguousUnitReference(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
var
  Decls   : TDictionary<string, TDictionary<string, TArray<TSymbol>>>;
  UnitIds : TDictionary<Int64, Boolean>;
  Found   : TList<TLintFinding>;
begin
  Result:= nil;
  if (ACtx.Store = nil) or not ACtx.Wants(RULE_AMBIGUOUS_UNIT_REFERENCE) then Exit;
  Decls  := TObjectDictionary<string, TDictionary<string, TArray<TSymbol>>>.Create([doOwnsValues]);
  UnitIds:= TDictionary<Int64, Boolean>.Create;
  Found  := TList<TLintFinding>.Create;
  try
    { pass 1: the unit-level declarations of every project unit, by lower-case unit name }
    var Paths: TDictionary<string, string>:= TDictionary<string, string>.Create;
    try
      for var P: string in ACtx.FilePaths do
      begin
        if not P.ToLower.EndsWith('.pas') then Continue;
        var UId: Int64;
        var UName: string;
        var D: TDictionary<string, TArray<TSymbol>>:= UnitLevelDecls(ACtx.Store, P, UId, UName);
        if UId = 0 then
        begin
          D.Free;
          Continue;
        end;
        UnitIds.AddOrSetValue(UId, True);
        Decls.AddOrSetValue(UName.ToLower, D);
        Paths.AddOrSetValue(UName.ToLower, P);
      end;
      { pass 2: every file, its used units, its bare references }
      for var KV: TPair<string, string> in Paths do
      begin
        var FileId: Int64:= ACtx.Store.FindFileIdByPath(KV.Value);
        if FileId = 0 then Continue;
        var Own: TDictionary<string, TArray<TSymbol>>:= Decls[KV.Key];
        { used project units in uses-list order: interface first, then implementation }
        var Used: TArray<string>:= nil;
        var UseList: TArray<TUnitUse>:= ACtx.Store.GetUnitUsesForFile(FileId);
        for var Sec: Integer:= 0 to 1 do
          for var U: TUnitUse in UseList do
            if (Ord(U.Section) = Sec) and Decls.ContainsKey(U.UnitName.ToLower) and (U.UnitName.ToLower <> KV.Key) then
              Used:= Used + [U.UnitName.ToLower];
        if Length(Used) < 2 then Continue;
        { name -> declarations in the used units }
        var ByName: TDictionary<string, TArray<TUnitDecl>>:= TDictionary<string, TArray<TUnitDecl>>.Create;
        try
          for var UN: string in Used do
            for var NameKV: TPair<string, TArray<TSymbol>> in Decls[UN] do
            begin
              var G: TArray<TUnitDecl>;
              if not ByName.TryGetValue(NameKV.Key, G) then G:= nil;
              for var S: TSymbol in NameKV.Value do
              begin
                var D: TUnitDecl;
                D.UnitName:= UN;
                D.Sym     := S;
                G:= G + [D];
              end;
              ByName.AddOrSetValue(NameKV.Key, G);
            end;
          var Reported: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
          try
            for var R: TReference in ACtx.Store.GetReferencesFromFile(FileId) do
            begin
              if (R.ReceiverText <> '') or (R.Kind = KIND_MEMBER_ACCESS) then Continue;
              var Key: string:= R.NameText.ToLower;
              var G: TArray<TUnitDecl>;
              if not ByName.TryGetValue(Key, G) then Continue;
              { two distinct used units must declare the name }
              var Distinct: TArray<string>:= nil;
              for var D: TUnitDecl in G do
                if not MatchStr(D.UnitName, Distinct) then Distinct:= Distinct + [D.UnitName];
              if Length(Distinct) < 2 then Continue;
              if Reported.ContainsKey(Key) or Own.ContainsKey(Key) then Continue;
              if IsBenignGroup(G) then Continue;
              { a reference bound to a local, a member or this unit's own declaration is not the uses-order case }
              if R.SymbolId > 0 then
              begin
                var T: TSymbol:= ACtx.Store.GetSymbolById(R.SymbolId);
                if (T.Id = 0) or (T.FileId = FileId) or not UnitIds.ContainsKey(T.ParentId) then Continue;
              end;
              { inside a method an inherited member of the same name would win over both units }
              if R.EnclosingSymbolId > 0 then
              begin
                var E: TSymbol:= ACtx.Store.GetSymbolById(R.EnclosingSymbolId);
                if (E.ParentId <> 0) and not UnitIds.ContainsKey(E.ParentId)
                  and HasMemberNamed(ACtx.Store, ACtx.LibStore, R.NameText, UnitIds) then Continue;
              end;
              Reported.Add(Key, True);
              var Winner: string:= Distinct[High(Distinct)];
              var Others: string:= '';
              for var UN: string in Distinct do
                if UN <> Winner then Others:= Others + IfThen(Others = '', '', ', ') + UN;
              Found.Add(MakeFinding(FileId, KV.Value, R,
                Format('%s is declared by %s and by %s, both used here; the last unit in the uses list (%s) wins. '
                  + 'Reordering the uses clause silently changes which one is called. Qualify the name (%s.%s) or use only one unit.',
                  [R.NameText, Others, Winner, Winner, Winner, R.NameText]), R.NameText));
            end;
          finally
            Reported.Free;
          end;
        finally
          ByName.Free;
        end;
      end;
    finally
      Paths.Free;
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    UnitIds.Free;
    Decls.Free;
  end;
end;

{ ---- assignment-narrows ---- }

{ The storage width of an integer type (lower case); 0 for anything else, floats included. }
function IntegerWidth(const ALowerType: string): Integer;
const
  BYTES_1 = 1; BYTES_2 = 2; BYTES_4 = 4; BYTES_8 = 8;
begin
  Result:= 0;
  if MatchStr(ALowerType, ['shortint', 'byte']) then Exit(BYTES_1);
  if MatchStr(ALowerType, ['smallint', 'word']) then Exit(BYTES_2);
  if MatchStr(ALowerType, ['integer', 'longint', 'cardinal', 'longword', 'fixedint', 'fixeduint']) then Exit(BYTES_4);
  if MatchStr(ALowerType, ['int64', 'uint64', 'nativeint', 'nativeuint', 'intptr', 'uintptr']) then Exit(BYTES_8);
end;

function LeafName(const AName: string): string;
begin
  Result:= AName.Trim;
  var Dot: Integer:= Result.LastDelimiter('.');
  if Dot >= 0 then Result:= Result.Substring(Dot + 1);
end;

{ The integer width of a type name, following simple aliases; 0 when it is not one integer type. }
function TypeWidth(const AStore: ISymbolStore; const ATypeQName: string; out ALeaf: string): Integer;
begin
  ALeaf:= LeafName(ATypeQName);
  Result:= 0;
  if ALeaf.Contains('<') then Exit;
  for var Hop: Integer:= 0 to MAX_ALIAS_HOPS do
  begin
    Result:= IntegerWidth(ALeaf.ToLower);
    if Result > 0 then Exit;
    var Target: string:= '';
    var Count : Integer:= 0;
    for var S: TSymbol in AStore.FindSymbolsByExactName(ALeaf) do
      if S.Kind = skTypeAlias then
      begin
        Inc(Count);
        Target:= S.Signature;
      end;
    if (Count <> 1) or (Target = '') then Exit(0);
    ALeaf:= LeafName(Target);
    if ALeaf.Contains('<') or ALeaf.Contains('.') or ALeaf.Contains('(') then Exit(0);
  end;
  Result:= 0;
end;

type
  /// <summary>One run of assignment-narrows over one file.</summary>
  TNarrowScan = class
  private
    FCtx     : TV151FileCtx;
    FPath    : string;
    FSrc     : TBytes;
    FFindings: TList<TLintFinding>;
    FCompilerLines: TDictionary<Integer, Boolean>;
    FWithDepth: Integer;
    function Text(const ANode: TTSNode): string;
    function NameNode(const ANode: TTSNode; AAllowCall: Boolean): TTSNode;
    function NameType(const AName: TTSNode; out AWidth: Integer; out ALeaf: string): Boolean;
    function SourceIsPlainValue(const AName: TTSNode): Boolean;
    procedure CheckAssign(const ANode: TTSNode);
    procedure Walk(const ANode: TTSNode);
  public
    constructor Create(const ACtx: TV151FileCtx);
    destructor Destroy; override;
    function Run: TArray<TLintFinding>;
  end;

constructor TNarrowScan.Create(const ACtx: TV151FileCtx);
begin
  inherited Create;
  FCtx:= ACtx;
  FFindings:= TList<TLintFinding>.Create;
  FCompilerLines:= TDictionary<Integer, Boolean>.Create;
end;

destructor TNarrowScan.Destroy;
begin
  FCompilerLines.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TNarrowScan.Text(const ANode: TTSNode): string;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  var StartIdx: Integer:= Integer(ANode.StartByte);
  var Len: Integer:= Integer(ANode.EndByte) - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (StartIdx + Len > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, StartIdx, Len);
end;

{ The identifier that names the value: the name itself, the member after a dot, or the callee of a call. }
function TNarrowScan.NameNode(const ANode: TTSNode; AAllowCall: Boolean): TTSNode;
begin
  Result:= Default(TTSNode);
  var N: TTSNode:= ANode;
  while (not N.IsNull) and (N.NodeType = NODE_PARENS) do N:= N.NamedChild(0);
  if N.IsNull then Exit;
  if AAllowCall and (N.NodeType = NODE_CALL) then
  begin
    N:= N.ChildByField(FIELD_ENTITY);
    if N.IsNull then Exit;
  end;
  if N.NodeType = NODE_DOT then N:= N.ChildByField(FIELD_RHS);
  if (not N.IsNull) and (N.NodeType = NODE_IDENT) then Result:= N;
end;

function TNarrowScan.NameType(const AName: TTSNode; out AWidth: Integer; out ALeaf: string): Boolean;
begin
  AWidth:= 0;
  ALeaf := '';
  var QName: string;
  Result:= RefStaticTypeAt(FCtx.Store, FCtx.FileId, Integer(AName.StartPoint.Row) + 1,
    TAstParseCache.CharCol(FPath, AName.StartPoint), Text(AName), QName);
  if not Result then Exit;
  AWidth:= TypeWidth(FCtx.Store, QName, ALeaf);
  Result:= AWidth > 0;
end;

{ The source side must be a bound variable, field, property or non-overloaded function: not a constant, not a cast. }
function TNarrowScan.SourceIsPlainValue(const AName: TTSNode): Boolean;
begin
  Result:= False;
  var R: TReference:= FCtx.Store.FindReferenceAt(FCtx.FileId, Integer(AName.StartPoint.Row) + 1,
    TAstParseCache.CharCol(FPath, AName.StartPoint));
  if (R.Id = 0) or (R.SymbolId <= 0) then Exit;
  var S: TSymbol:= FCtx.Store.GetSymbolById(R.SymbolId);
  if S.Id = 0 then Exit;
  if S.Kind in [skConstDecl, skEnumValue, skTypeAlias, skClass, skRecord, skEnum] then Exit;
  if S.Directives.ToLower.Contains(OVERLOAD_WORD) or S.Modifiers.ToLower.Contains(OVERLOAD_WORD) then Exit;
  Result:= True;
end;

procedure TNarrowScan.CheckAssign(const ANode: TTSNode);
var
  LW, RW: Integer;
  LLeaf, RLeaf: string;
begin
  var Op: TTSNode:= ANode.ChildByField(FIELD_OP);
  var LhsN: TTSNode:= NameNode(ANode.ChildByField(FIELD_LHS), False);
  var RhsN: TTSNode:= NameNode(ANode.ChildByField(FIELD_RHS), True);
  var Line: Integer:= Integer(ANode.StartPoint.Row) + 1;
  { one chain: each step runs only when the earlier ones held, so the type lookups are the last resort }
  var Narrows: Boolean:= (not Op.IsNull) and (Op.NodeType = OP_ASSIGN) and (FWithDepth = 0)
    and (not LhsN.IsNull) and (not RhsN.IsNull) and (not FCompilerLines.ContainsKey(Line))
    and NameType(LhsN, LW, LLeaf) and SourceIsPlainValue(RhsN) and NameType(RhsN, RW, RLeaf) and (RW > LW);
  if not Narrows then Exit;
  var F: TLintFinding:= Default(TLintFinding);
  F.RuleId   := RULE_ASSIGNMENT_NARROWS;
  F.Severity := SEVERITY_WARNING;
  F.FileId   := FCtx.FileId;
  F.FilePath := FPath;
  F.StartLine:= Line;
  F.StartCol := TAstParseCache.CharCol(FPath, ANode.StartPoint);
  F.EndLine  := Integer(ANode.EndPoint.Row) + 1;
  F.EndCol   := TAstParseCache.CharCol(FPath, ANode.EndPoint);
  F.SymbolName:= Text(LhsN);
  F.Message  := Format('%s is %s but %s is %s: the assignment drops the high bits silently when range checking is off. '
    + 'Widen %s, or narrow the value explicitly after a range check.', [Text(RhsN), RLeaf, Text(LhsN), LLeaf, Text(LhsN)]);
  FFindings.Add(F);
end;

procedure TNarrowScan.Walk(const ANode: TTSNode);
begin
  if ANode.IsNull then Exit;
  var NT: string:= ANode.NodeType;
  if NT = NODE_ASSIGN then CheckAssign(ANode);
  var IsWith: Boolean:= NT = NODE_WITH;
  if IsWith then Inc(FWithDepth);
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do Walk(ANode.NamedChild(I));
  if IsWith then Dec(FWithDepth);
end;

function TNarrowScan.Run: TArray<TLintFinding>;
begin
  Result:= nil;
  FPath:= FCtx.Path;
  var PF: TParsedFile:= TAstParseCache.Get(FPath);
  if PF.Tree = nil then Exit;
  FSrc:= PF.Src;
  for var CF: TCompilerFinding in FCtx.Store.FindCompilerFindingsForFile(FCtx.FileId) do
    FCompilerLines.AddOrSetValue(CF.LineNo, True);
  Walk(PF.Tree.RootNode);
  Result:= FFindings.ToArray;
end;

function CheckAssignmentNarrows(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if (ACtx.Store = nil) or (ACtx.FileId <= 0) or not ACtx.Wants(RULE_ASSIGNMENT_NARROWS) then Exit;
  var Scan: TNarrowScan:= TNarrowScan.Create(ACtx);
  try
    Result:= Scan.Run;
  finally
    Scan.Free;
  end;
end;

end.
