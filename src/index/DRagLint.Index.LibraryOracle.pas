unit DRagLint.Index.LibraryOracle;

{ Item 4 (untypable receivers), spec 2026-10-28-untypable-receivers s.5 item 4.
  Binds a call or member access whose receiver the PROJECT index typed only BY
  NAME (the type lives in the platform library) to the qualified NAME of the
  member in one of the extra (library) stores. The answer lands on
  refs.external_target; it is a name, never an id, because call_edges can only
  point into the project's own symbols table.

  The rules are deliberately narrow -- a wrong external name is a wrong FACT:
    * exactly ONE type of the leaf name across the stores (forward declarations
      and the body share one qualified name and count once; a nested type never
      counts; a `type X = Y` alias counts only when its ordinal-0 ancestor row
      lands on a class / record / interface), else the candidates whose
      declaring unit the referencing file uses, else decline ambiguous-type;
    * the member is looked up on that type, then its library ancestors in
      breadth-first order; the FIRST type declaring the name decides, and when
      what it declares is not of an acceptable kind the answer is no-member --
      a nearer declaration hides a farther one in Delphi, so the oracle never
      skips past it;
    * same-named overloads on the deciding type are ONE qualified name.
  No reference to the resolver: readers (find-callees, context) can use it. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  /// <summary>A set of symbol kinds the oracle accepts at one step.</summary>
  TOracleKindSet = set of TSymbolKind;

  /// <summary>Kind of site being bound.</summary>
  TExternalKind = (ekCall, ekMemberAccess, ekBareCall);

  /// <summary>Counters of the oracle's outcomes, printed on the resolve: summary line.</summary>
  /// <remarks>Every Bind / BindHead / BindBare call increments exactly one counter.
  /// Intrinsic and LateBound (E-RECV-UNDECIDABLE D08 / D10, owner ruling 2026-11-08) count the
  /// binds that are not a routine: a dynamic-array constructor (`TBytes.Create`, bound to the
  /// synthetic INTRINSIC_DYNARRAY_CREATE) and a call through an event property or procedural
  /// field (`V.OnColumnSizeChanged(V, nil)`, bound to the property). They are not in Bound;
  /// LastKind tells the caller which kind the last answer was.</remarks>
  TOracleStats = record
    Bound, AmbiguousType, NoMember, NoStore, NoType, Intrinsic, LateBound: Integer;
  end;


  /// <summary>Binds a receiver typed BY NAME to a qualified symbol name in one of the extra
  /// (library) stores. Pure reader: owns no store, writes nothing, caches per type.</summary>
  /// <remarks>Not thread-safe. One instance per resolve pass or reader; the caches assume the
  /// stores do not change while it lives.</remarks>
  TLibraryOracle = class
  strict private type
    TLibCand = record
      Store   : Integer;        // index into FStores
      Ids     : TArray<Int64>;  // every row of ONE qualified name (forward declaration + body)
      QName   : string;
      Name    : string;
      UnitStem: string;         // lower-cased declaring unit (file stem)
      FileId  : Int64;
      Kind    : TSymbolKind;
      Sig     : string;
    end;
  strict private
    FStores   : TArray<ISymbolStore>;
    FStats    : TOracleStats;
    FTypes    : TDictionary<string, TArray<TLibCand>>;
    FValues   : TDictionary<string, TArray<TLibCand>>;
    FRoutines : TDictionary<string, TArray<TLibCand>>;
    FKids     : TDictionary<string, TArray<TSymbol>>;
    FAncestors: TDictionary<string, TArray<TTypeAncestor>>;
    FStems    : TDictionary<string, string>;
    FFileUses : TDictionary<string, TArray<string>>;
    FHelperMembers: TDictionary<string, string>;
    FHelperTypes  : TDictionary<string, TArray<TLibCand>>;
    FAliases      : TDictionary<string, TArray<TLibCand>>;
    FLastKind     : string;
    function IsDynArrayType(const ATypeText: string; const AUses: TArray<string>; ADepth: Integer): Boolean;
    function NamesVisibleType(const AText, ALeaf: string; const AUses: TArray<string>): Boolean;
    function InQualifier(const AText: string; const ACands: TArray<TLibCand>): TArray<TLibCand>;
    function HelperCands(const ALeaf: string): TArray<TLibCand>;
    function PickTypeOrHelper(const ATypeText: string; const ATypeUses, AHelperUses: TArray<string>;
      out ACand: TLibCand; out AReason: string): Boolean;
    function HelpersDeclare(const AStore: ISymbolStore; const AStoreTag, ATypeName, AMember: string): Boolean;
    function CandProvesAbsent(const ACand: TLibCand; const AMember: string; const AProjectStore: ISymbolStore): Boolean;
    function Key(AStore: Integer; AId: Int64): string;
    function UnitStemOf(AStore: Integer; AFileId: Int64): string;
    function LibraryUses(AStore: Integer; AFileId: Int64): TArray<string>;
    function Collect(const AName: string; AKinds: TOracleKindSet; AFollowAlias: Boolean): TArray<TLibCand>;
    function Cached(ACache: TDictionary<string, TArray<TLibCand>>; const AName: string;
      AKinds: TOracleKindSet; AFollowAlias: Boolean): TArray<TLibCand>;
    function Pick(const ACands: TArray<TLibCand>; const AUses: TArray<string>; out ACand: TLibCand;
      out AReason: string): Boolean;
    function PickType(const ATypeText: string; const AUses: TArray<string>; out ACand: TLibCand;
      out AReason: string): Boolean;
    function Kids(AStore: Integer; AId: Int64): TArray<TSymbol>;
    function Ancestors(AStore: Integer; AId: Int64): TArray<TTypeAncestor>;
    function DeclaringMember(const ACand: TLibCand; const AName: string; out AHit: TSymbol): Boolean;
    function ImplicitRootMember(const ACand: TLibCand; const AName: string; out AHit: TSymbol): Boolean;
    function AgreedMember(const ATypeText, AMember: string; AKind: TExternalKind; const AUses: TArray<string>): string;
    function VisibleOf(const ACands: TArray<TLibCand>; const AUses: TArray<string>): TArray<TLibCand>;
    function UnitRoutine(const AChain, AMember: string; const AUses: TArray<string>; out AQName: string): Integer;
    function StepPending(var ACand: TLibCand; const APending: string; const AHelperUses: TArray<string>;
      out AReason: string): Boolean;
    function MemberOf(const ACand: TLibCand; const AMember: string; AKind: TExternalKind;
      out AReason: string): string;
    function Count(const AResult, AReason: string): string;
  public
    /// <param name="AStores">The open extra stores; the oracle does not own them.</param>
    constructor Create(const AStores: TArray<ISymbolStore>);
    /// <summary>Frees the caches; the stores are the caller's.</summary>
    destructor Destroy; override;
    /// <summary>Binds AMember on the type named ATypeText, after stepping the pending segments.</summary>
    /// <param name="ATypeText">spec s.4.1 value without the pending segments; '' for a bare call.</param>
    /// <param name="APending">Dot-joined pending segments or ''.</param>
    /// <param name="AMember">The called member name.</param>
    /// <param name="AKind">Site kind; ekBareCall delegates to BindBare with no scope type.</param>
    /// <param name="AUsesUnits">Lower-cased unit names the referencing file uses (both sections + the .dpr).</param>
    /// <param name="AReason">ambiguous-type|no-member|no-store|no-type when the result is ''.</param>
    /// <returns>The qualified name, or '' with AReason set.</returns>
    /// <remarks>A type name Pick cannot choose still answers when every candidate is a class
    /// and all of them give the SAME member (`Acc.Free` on TList): the choice cannot matter.
    /// A name no library type answers (a built-in such as string or Boolean, at the head or
    /// as a pending segment's type) is answered by its one library helper visible from the
    /// calling file (`S.Split` -> TStringHelper.Split); two visible helpers decline.</remarks>
    function Bind(const ATypeText, APending, AMember: string; AKind: TExternalKind;
      const AUsesUnits: TArray<string>; out AReason: string): string;
    /// <summary>E-RECV-UNDECIDABLE D08: binds a dynamic-array constructor call whose receiver
    /// is a generic type text no head rung reads (`TArray&lt;Integer&gt;.Create(1)`) to the
    /// synthetic INTRINSIC_DYNARRAY_CREATE.</summary>
    /// <param name="AReceiver">The call's receiver text as written.</param>
    /// <param name="AMember">The called member; only `Create` binds.</param>
    /// <param name="AUsesUnits">The calling file's used units.</param>
    /// <returns>INTRINSIC_DYNARRAY_CREATE, or '' (and no counter moves) when it is not one.</returns>
    /// <remarks>A hit counts as Stats.Intrinsic and sets LastKind to EXTERNAL_KIND_INTRINSIC.</remarks>
    function BindIntrinsic(const AReceiver, AMember: string; const AUsesUnits: TArray<string>): string;
    /// <summary>The kind of the last non-empty answer of Bind / BindHead / BindBare /
    /// BindIntrinsic: '' (a routine), EXTERNAL_KIND_INDIRECT or EXTERNAL_KIND_INTRINSIC.</summary>
    /// <remarks>Read it right after the call whose answer it describes; the next call resets it.</remarks>
    property LastKind: string read FLastKind;
    /// <summary>Binds a receiver whose HEAD identifier no project rung typed: in Delphi's
    /// order, a member inherited by the enclosing class from AScopeType, a routine of a used
    /// unit the whole chain names (`System.SysUtils.DeleteFile`), a library type, a library
    /// unit-level var / const, then `Unit.Name.TType` as a unit-qualified type.</summary>
    /// <remarks>A type in a unit the file does not use cannot be what the head names: when a
    /// library var / const of the name IS visible, the value rung answers, and only a visible
    /// value (`Application` beside typelib interfaces of that name). Without a visible value
    /// the type rung behaves as it always did. Several visible values decline.</remarks>
    /// <param name="AChain">The receiver, a dot-joined identifier chain (`CodeSite`, `TEncoding.UTF8`).</param>
    /// <param name="AMember">The called member name.</param>
    /// <param name="AKind">ekCall or ekMemberAccess.</param>
    /// <param name="AUsesUnits">As for Bind.</param>
    /// <param name="AScopeType">The enclosing class's first library ancestor name, or ''.</param>
    /// <param name="AReason">As for Bind.</param>
    /// <param name="ATypeText">The receiver's type text as the head typed it, leaf-normalised,
    /// with the pending segments appended -- the value to persist; '' when the head was not typed.</param>
    /// <returns>The qualified name, or '' with AReason set.</returns>
    function BindHead(const AChain, AMember: string; AKind: TExternalKind; const AUsesUnits: TArray<string>;
      const AScopeType: string; out AReason: string; out ATypeText: string): string;
    /// <summary>Binds a BARE call: a method the enclosing class inherits from AScopeType, else
    /// exactly one library unit-level routine of the name whose unit the file uses.</summary>
    /// <param name="AName">The called name.</param>
    /// <param name="AUsesUnits">As for Bind; the System unit is always visible.</param>
    /// <param name="AScopeType">The enclosing class's first library ancestor name, or ''.</param>
    /// <param name="AReason">As for Bind.</param>
    /// <returns>The qualified name, or '' with AReason set.</returns>
    function BindBare(const AName: string; const AUsesUnits: TArray<string>; const AScopeType: string;
      out AReason: string): string;
    /// <summary>True only when the library PROVES that a type named ATypeText cannot supply
    /// AMember, so a `with` target descending from it does not hide an outer AMember.</summary>
    /// <param name="ATypeText">The ancestor's name as the project wrote it; generics and unit
    /// qualifier are ignored.</param>
    /// <param name="AMember">The bare name being looked up.</param>
    /// <param name="AProjectStore">The project's store: a helper the project declares on a
    /// library type counts as a member. May be nil.</param>
    /// <returns>True when at least one library type has that leaf name and EVERY one of them
    /// has a chain wholly inside its store (TObject / IInterface / IUnknown excepted) that
    /// declares no AMember and carries no helper declaring it. False for anything else: no
    /// store, no such type, a chain leaving the library, a declaration, a helper.</returns>
    /// <remarks>Every same-leaf candidate must agree, instead of Pick's uses-based choice,
    /// because the ancestor's name was written in the DECLARING unit of a type possibly far
    /// from the site. Helper targets match by exact name (type_helpers.target_name). Does not
    /// touch the outcome counters: it binds nothing.</remarks>
    function MemberProvablyAbsent(const ATypeText, AMember: string; const AProjectStore: ISymbolStore): Boolean;
    /// <summary>Outcome counters since Create.</summary>
    property Stats: TOracleStats read FStats;
  end;

/// <summary>A declared type text reduced to the name the oracle and refs.receiver_type_text
/// carry: generic arguments and unit qualifier stripped, a leading '^' kept.</summary>
/// <param name="ATypeText">A declaration's type text, e.g. 'System.Classes.TStream', 'TList&lt;T&gt;'.</param>
/// <returns>The leaf (`TStream`, `TList`, `^TRec`), or '' when the text is not a plain type
/// name (`array of T`, `class of T`, a set, a procedural type).</returns>
function NormalizeTypeLeaf(const ATypeText: string): string;

/// <summary>True for an ancestor every class or interface has whether or not it is indexed.</summary>
/// <param name="AName">The ancestor's name as written, possibly unit-qualified.</param>
/// <returns>True for TObject, IInterface and IUnknown, whose members the caller answers from
/// its own floor list.</returns>
function IsRootAncestorName(const AName: string): Boolean;

const
  /// <summary>The class every class with no written parent descends from.</summary>
  IMPLICIT_ROOT_CLASS = 'TObject';

implementation

const
  IMPLICIT_ROOT_UNIT = 'system';
  OK_CALL   : TOracleKindSet = [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
  OK_ACCESS : TOracleKindSet = [skProcedure, skFunction, skMethod, skConstructor, skDestructor, skProperty, skField];
  TYPE_KINDS: TOracleKindSet = [skClass, skInterface, skRecord];
  VALUE_KINDS: TOracleKindSet = [skVarDecl, skConstDecl];
  ROUTINE_KINDS: TOracleKindSet = [skProcedure, skFunction];
  { What a pending segment / an inherited head may be: a value or a parenless function. }
  STEP_KINDS: TOracleKindSet = [skField, skProperty, skMethod, skFunction];
  R_AMBIGUOUS = 'ambiguous-type';
  R_NO_MEMBER = 'no-member';
  R_NO_STORE  = 'no-store';
  R_NO_TYPE   = 'no-type';
  R_INTRINSIC = 'intrinsic';   // D08: no declaration exists (`TBytes.Create`)
  R_LATE_BOUND= 'late-bound';  // D10: the routine is chosen at run time (an event property)
  { How deep IsDynArrayType follows an alias chain (`TBytes = TArray<Byte>` -> `array of T`). }
  MAX_ALIAS_HOPS = 3;

function IsIdent(const S: string): Boolean;
begin
  Result:= S <> '';
  for var i:= 1 to Length(S) do
    if not (CharInSet(S[i], ['A'..'Z', 'a'..'z', '_']) or ((i > 1) and CharInSet(S[i], ['0'..'9']))) then Exit(False);
end;

function NormalizeTypeLeaf(const ATypeText: string): string;
var
  Ptr: string;
begin
  Result:= Trim(ATypeText);
  Ptr   := '';
  if Result.StartsWith('^') then
  begin
    Ptr   := '^';
    Result:= Trim(Copy(Result, 2, MaxInt));
  end;
  var Eq: Integer:= Pos('=', Result);
  if Eq > 0 then Result:= Trim(Copy(Result, 1, Eq - 1));
  var Lt: Integer:= Pos('<', Result);
  if Lt > 0 then Result:= Trim(Copy(Result, 1, Lt - 1));
  for var Seg: string in Result.Split(['.']) do
    if not IsIdent(Trim(Seg)) then Exit('');
  var Dot: Integer:= Result.LastDelimiter('.');
  if Dot >= 0 then Result:= Trim(Copy(Result, Dot + 2, MaxInt));
  Result:= if Result = '' then '' else Ptr + Result;
end;

{ The declared type text a member stands for: a field's type, a property's type
  (after any index parameters), a function's return type; '' for a procedure. }
function MemberTypeText(const AMember: TSymbol): string;
var
  S    : string ;
  Depth: Integer;
  K    : Integer;
begin
  S:= Trim(AMember.Signature);
  if AMember.Kind = skField then Exit(S);
  if (S <> '') and CharInSet(S[1], ['(', '[']) then
  begin
    Depth:= 0;
    for K:= 1 to Length(S) do
    begin
      if CharInSet(S[K], ['(', '[']) then Inc(Depth)
      else if CharInSet(S[K], [')', ']']) then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          S:= TrimLeft(Copy(S, K + 1, MaxInt));
          Break;
        end;
      end;
    end;
    if Depth <> 0 then Exit('');
  end;
  if (S <> '') and (S[1] = ':') then S:= Trim(Copy(S, 2, MaxInt))
  else if AMember.Kind <> skProperty then Exit('');
  K:= Pos(';', S);
  if K > 0 then S:= Trim(Copy(S, 1, K - 1));
  K:= Pos(' ', S);
  if K > 0 then S:= Copy(S, 1, K - 1); // `TFoo read GetFoo write SetFoo`
  Result:= S;
end;

function IsRootAncestorName(const AName: string): Boolean;
begin
  var N: string:= LowerCase(AName);
  if LastDelimiter('.', N) > 0 then N:= Copy(N, LastDelimiter('.', N) + 1, MaxInt);
  Result:= (N = 'tobject') or (N = 'iinterface') or (N = 'iunknown');
end;

function InUses(const AStem: string; const AUses: TArray<string>): Boolean;
begin
  for var U: string in AUses do
    if (U = AStem) or AStem.EndsWith('.' + U) then Exit(True);
  Result:= False;
end;

constructor TLibraryOracle.Create(const AStores: TArray<ISymbolStore>);
begin
  inherited Create;
  FStores   := AStores;
  FTypes    := TDictionary<string, TArray<TLibCand>>.Create;
  FValues   := TDictionary<string, TArray<TLibCand>>.Create;
  FRoutines := TDictionary<string, TArray<TLibCand>>.Create;
  FKids     := TDictionary<string, TArray<TSymbol>>.Create;
  FAncestors:= TDictionary<string, TArray<TTypeAncestor>>.Create;
  FStems    := TDictionary<string, string>.Create;
  FFileUses := TDictionary<string, TArray<string>>.Create;
  FHelperMembers:= TDictionary<string, string>.Create;
  FHelperTypes  := TDictionary<string, TArray<TLibCand>>.Create;
  FAliases      := TDictionary<string, TArray<TLibCand>>.Create;
end;

destructor TLibraryOracle.Destroy;
begin
  FAliases.Free;
  FHelperTypes.Free;
  FHelperMembers.Free;
  FFileUses.Free;
  FStems.Free;
  FAncestors.Free;
  FKids.Free;
  FRoutines.Free;
  FValues.Free;
  FTypes.Free;
  inherited Destroy;
end;

function TLibraryOracle.Key(AStore: Integer; AId: Int64): string;
begin
  Result:= IntToStr(AStore) + '#' + IntToStr(AId);
end;

function TLibraryOracle.UnitStemOf(AStore: Integer; AFileId: Int64): string;
begin
  var K: string:= Key(AStore, AFileId);
  if FStems.TryGetValue(K, Result) then Exit;
  Result:= LowerCase(ChangeFileExt(ExtractFileName(FStores[AStore].GetFilePath(AFileId)), ''));
  FStems.Add(K, Result);
end;

function TLibraryOracle.LibraryUses(AStore: Integer; AFileId: Int64): TArray<string>;
begin
  var K: string:= Key(AStore, AFileId);
  if FFileUses.TryGetValue(K, Result) then Exit;
  Result:= [UnitStemOf(AStore, AFileId), 'system', 'sysinit'];
  for var U: TUnitUse in FStores[AStore].GetUnitUsesForFile(AFileId) do
    Result:= Result + [LowerCase(U.UnitName)];
  FFileUses.Add(K, Result);
end;

function TLibraryOracle.Collect(const AName: string; AKinds: TOracleKindSet;
  AFollowAlias: Boolean): TArray<TLibCand>;
var
  ByQName: TDictionary<string, Integer>;

  procedure Add(AStore: Integer; const S: TSymbol);
  var
    Ix: Integer;
  begin
    if ByQName.TryGetValue(LowerCase(S.QualifiedName), Ix) then
    begin
      if Result[Ix].Store = AStore then Result[Ix].Ids:= Result[Ix].Ids + [S.Id];
      Exit;
    end;
    var C: TLibCand:= Default(TLibCand);
    C.Store   := AStore;
    C.Ids     := [S.Id];
    C.QName   := S.QualifiedName;
    C.Name    := S.Name;
    C.UnitStem:= UnitStemOf(AStore, S.FileId);
    C.FileId  := S.FileId;
    C.Kind    := S.Kind;
    C.Sig     := S.Signature;
    ByQName.Add(LowerCase(S.QualifiedName), Length(Result));
    Result:= Result + [C];
  end;

begin
  Result := [];
  ByQName:= TDictionary<string, Integer>.Create;
  try
    for var Si:= 0 to High(FStores) do
    begin
      if FStores[Si] = nil then Continue;
      for var S: TSymbol in FStores[Si].FindSymbolsByExactName(AName) do
      begin
        if not SameText(S.Name, AName) then Continue;
        { Unit level only: a nested `TOuter.TDataSet` is not what `TDataSet` names. }
        if not SameText(S.QualifiedName, UnitStemOf(Si, S.FileId) + '.' + S.Name) then Continue;
        if S.Kind in AKinds then Add(Si, S)
        else if AFollowAlias and (S.Kind = skTypeAlias) then
          for var A: TTypeAncestor in Ancestors(Si, S.Id) do
          begin
            { Followed ONCE, through the alias's own ordinal-0 edge; an alias
              whose target is not a class / record / interface is ignored. }
            if (A.Ordinal = 0) and A.Resolved and (A.SymbolId > 0) then
            begin
              var T: TSymbol:= FStores[Si].GetSymbolById(A.SymbolId);
              if T.Kind in AKinds then Add(Si, T);
            end;
            Break;
          end;
      end;
    end;
  finally
    ByQName.Free;
  end;
end;

function TLibraryOracle.Cached(ACache: TDictionary<string, TArray<TLibCand>>; const AName: string;
  AKinds: TOracleKindSet; AFollowAlias: Boolean): TArray<TLibCand>;
begin
  var K: string:= LowerCase(AName);
  if ACache.TryGetValue(K, Result) then Exit;
  Result:= Collect(AName, AKinds, AFollowAlias);
  ACache.Add(K, Result);
end;

function TLibraryOracle.Pick(const ACands: TArray<TLibCand>; const AUses: TArray<string>;
  out ACand: TLibCand; out AReason: string): Boolean;
var
  Hits: Integer;
begin
  Result := False;
  AReason:= '';
  ACand  := Default(TLibCand);
  if Length(ACands) = 0 then
  begin
    AReason:= R_NO_TYPE;
    Exit;
  end;
  if Length(ACands) = 1 then
  begin
    ACand:= ACands[0];
    Exit(True);
  end;
  Hits:= 0;
  for var C: TLibCand in ACands do
    if InUses(C.UnitStem, AUses) then
    begin
      Inc(Hits);
      ACand:= C;
    end;
  Result:= Hits = 1;
  if not Result then
  begin
    AReason:= R_AMBIGUOUS;
    ACand  := Default(TLibCand);
  end;
end;

function TLibraryOracle.PickType(const ATypeText: string; const AUses: TArray<string>;
  out ACand: TLibCand; out AReason: string): Boolean;
begin
  var Leaf: string:= NormalizeTypeLeaf(ATypeText);
  if (Leaf = '') or Leaf.StartsWith('^') then
  begin
    ACand  := Default(TLibCand);
    AReason:= R_NO_TYPE;
    Exit(False);
  end;
  Result:= Pick(Cached(FTypes, Leaf, TYPE_KINDS, True), AUses, ACand, AReason);
end;

{ E-RECV-UNDECIDABLE D08: True when ATypeText names a dynamic array type: `TArray<X>` (the
  generic arguments do not matter) or a library alias whose every visible declaration is
  `array of ..`, directly or through at most MAX_ALIAS_HOPS further aliases
  (`TBytes = TArray<Byte>`). A name that is also a visible class / record / interface, or that
  no visible alias declares, is not one. }
{ A visible class / record / interface the type text can name: a text WITH generic arguments
  (`TArray<Integer>`) names only a generic declaration, so System.Generics.Collections' plain
  `TArray` class does not hide System's `TArray<T> = array of T`. }
function TLibraryOracle.NamesVisibleType(const AText, ALeaf: string; const AUses: TArray<string>): Boolean;
begin
  Result:= False;
  var Generic: Boolean:= Pos('<', AText) > 0;
  for var C: TLibCand in VisibleOf(Cached(FTypes, ALeaf, TYPE_KINDS, True), AUses) do
    if not Generic or (FStores[C.Store].GetSymbolById(C.Ids[0]).GenericParams <> '') then Exit(True);
end;

{ The candidates a UNIT-QUALIFIED text can mean (`SysUtils.TBytes` -> System.SysUtils's, as
  Spring writes it): declared in a unit whose name is the qualifier or ends with `.qualifier`.
  An unqualified text keeps every candidate. }
function TLibraryOracle.InQualifier(const AText: string; const ACands: TArray<TLibCand>): TArray<TLibCand>;
begin
  var Plain: string:= AText;
  var Lt: Integer:= Pos('<', Plain);
  if Lt > 0 then Plain:= Copy(Plain, 1, Lt - 1);
  var Dot: Integer:= Plain.LastIndexOf('.');
  if Dot < 0 then Exit(ACands);
  var Q: string:= LowerCase(Trim(Copy(Plain, 1, Dot)));
  Result:= [];
  for var C: TLibCand in ACands do
    if (C.UnitStem = Q) or C.UnitStem.EndsWith('.' + Q) then Result:= Result + [C];
end;

function TLibraryOracle.IsDynArrayType(const ATypeText: string; const AUses: TArray<string>;
  ADepth: Integer): Boolean;
begin
  var Text: string:= Trim(ATypeText);
  if Text.ToLower.StartsWith('array of') then Exit(True);
  var Leaf: string:= NormalizeTypeLeaf(Text);
  { Too deep, not a plain name, or a visible class / record / interface the text can name. }
  if (ADepth > MAX_ALIAS_HOPS) or (Leaf = '') or Leaf.StartsWith('^') or NamesVisibleType(Text, Leaf, AUses) then
    Exit(False);
  var Seen: TArray<TLibCand>:= InQualifier(Text, VisibleOf(Cached(FAliases, Leaf, [skTypeAlias], False), AUses));
  Result:= Length(Seen) > 0;
  for var C: TLibCand in Seen do
    Result:= Result and IsDynArrayType(C.Sig, LibraryUses(C.Store, C.FileId) + [IMPLICIT_ROOT_UNIT], ADepth + 1);
end;

function TLibraryOracle.BindIntrinsic(const AReceiver, AMember: string; const AUsesUnits: TArray<string>): string;
begin
  var Lt: Integer:= Pos('<', AReceiver);
  var GenericHead: Boolean:= (Lt > 1) and AReceiver.EndsWith('>') and IsIdent(Copy(AReceiver, 1, Lt - 1));
  Result   := '';
  FLastKind:= '';
  if (Length(FStores) > 0) and SameText(AMember, 'Create') and GenericHead
     and IsDynArrayType(AReceiver, AUsesUnits + [IMPLICIT_ROOT_UNIT, 'sysinit'], 0) then
    Result:= Count(INTRINSIC_DYNARRAY_CREATE, R_INTRINSIC);
end;

{ E-RECV-UNDECIDABLE D05: every library helper whose target is named ALeaf
  (`record helper for string` -> TStringHelper), one candidate per helper. }
function TLibraryOracle.HelperCands(const ALeaf: string): TArray<TLibCand>;
begin
  var K: string:= LowerCase(ALeaf);
  if FHelperTypes.TryGetValue(K, Result) then Exit;
  Result:= [];
  for var Si:= 0 to High(FStores) do
  begin
    if FStores[Si] = nil then Continue;
    for var H: THelperEdge in FStores[Si].FindHelpersOfType(ALeaf) do
    begin
      var S: TSymbol:= FStores[Si].GetSymbolById(H.HelperSymbolId);
      if S.Id <= 0 then Continue;
      var C: TLibCand:= Default(TLibCand);
      C.Store   := Si;
      C.Ids     := [S.Id];
      C.QName   := S.QualifiedName;
      C.Name    := S.Name;
      C.UnitStem:= UnitStemOf(Si, S.FileId);
      C.FileId  := S.FileId;
      C.Kind    := S.Kind;
      C.Sig     := S.Signature;
      Result:= Result + [C];
    end;
  end;
  FHelperTypes.Add(K, Result);
end;

{ A type name no library type answers may still have members: a built-in type's
  helper (`S.Split`, `B.ToString`). Only one helper per type is active in Delphi,
  so exactly one visible helper answers; two decline. The helper's scope is the
  CALLING file's (AHelperUses), whatever unit named the type. }
function TLibraryOracle.PickTypeOrHelper(const ATypeText: string; const ATypeUses, AHelperUses: TArray<string>;
  out ACand: TLibCand; out AReason: string): Boolean;
begin
  Result:= PickType(ATypeText, ATypeUses, ACand, AReason);
  if Result or (AReason <> R_NO_TYPE) then Exit;
  var Leaf: string:= NormalizeTypeLeaf(ATypeText);
  if (Leaf = '') or Leaf.StartsWith('^') then Exit;
  var Seen: TArray<TLibCand>:= VisibleOf(HelperCands(Leaf), AHelperUses);
  if Length(Seen) = 1 then
  begin
    ACand  := Seen[0];
    AReason:= '';
    Exit(True);
  end;
  if Length(Seen) > 1 then AReason:= R_AMBIGUOUS;
end;

function TLibraryOracle.Kids(AStore: Integer; AId: Int64): TArray<TSymbol>;
begin
  var K: string:= Key(AStore, AId);
  if FKids.TryGetValue(K, Result) then Exit;
  Result:= FStores[AStore].FindAllChildSymbols(AId);
  FKids.Add(K, Result);
end;

function TLibraryOracle.Ancestors(AStore: Integer; AId: Int64): TArray<TTypeAncestor>;
begin
  var K: string:= Key(AStore, AId);
  if FAncestors.TryGetValue(K, Result) then Exit;
  Result:= FStores[AStore].GetTransitiveAncestors(AId);
  FAncestors.Add(K, Result);
end;

function TLibraryOracle.DeclaringMember(const ACand: TLibCand; const AName: string; out AHit: TSymbol): Boolean;
var
  Visit: TArray<Int64>;
begin
  AHit := Default(TSymbol);
  Visit:= ACand.Ids;
  for var Id: Int64 in ACand.Ids do
    for var A: TTypeAncestor in Ancestors(ACand.Store, Id) do
      if A.Resolved and (A.SymbolId > 0) then Visit:= Visit + [A.SymbolId];
  for var Id: Int64 in Visit do
    for var S: TSymbol in Kids(ACand.Store, Id) do
      if SameText(S.Name, AName) and (S.Kind <> skParam) then
      begin
        AHit:= S;
        Exit(True);
      end;
  Result:= ImplicitRootMember(ACand, AName, AHit);
end;

{ The last step of a class's chain, which no ancestor row records when the class has no
  written parent: TObject. Only for a class (an interface or record has no such root) and
  only when every written ancestor resolved: an unknown parent may redeclare the member. }
function TLibraryOracle.ImplicitRootMember(const ACand: TLibCand; const AName: string; out AHit: TSymbol): Boolean;
begin
  Result:= False;
  AHit  := Default(TSymbol);
  if ACand.Kind <> skClass then Exit;
  for var Id: Int64 in ACand.Ids do
    for var A: TTypeAncestor in Ancestors(ACand.Store, Id) do
      if not A.Resolved and not IsRootAncestorName(A.Name) then Exit;
  for var T: TLibCand in Cached(FTypes, IMPLICIT_ROOT_CLASS, TYPE_KINDS, True) do
    if T.UnitStem = IMPLICIT_ROOT_UNIT then
      for var Id: Int64 in T.Ids do
        for var S: TSymbol in Kids(T.Store, Id) do
          if SameText(S.Name, AName) and (S.Kind <> skParam) then
          begin
            AHit:= S;
            Exit(True);
          end;
end;

{ One target whichever candidate the type name means: every candidate is a class and each
  declares the member under the same qualified name. Only the candidates AUses can see are
  asked when any is visible (a unit the file does not use cannot be what the name means --
  wave-146 b7 leftover, `List.Free` on TList<T> beside Spring's unseen TList); with none
  visible, every candidate is asked as before. }
function TLibraryOracle.AgreedMember(const ATypeText, AMember: string; AKind: TExternalKind;
  const AUses: TArray<string>): string;
var
  Hit: TSymbol;
begin
  Result:= '';
  var Cands: TArray<TLibCand>:= Cached(FTypes, NormalizeTypeLeaf(ATypeText), TYPE_KINDS, True);
  var Seen: TArray<TLibCand>:= VisibleOf(Cands, AUses);
  if Length(Seen) > 0 then Cands:= Seen;
  for var C: TLibCand in Cands do
  begin
    if (C.Kind <> skClass) or not DeclaringMember(C, AMember, Hit)
       or (Hit.Kind not in (if AKind = ekMemberAccess then OK_ACCESS else OK_CALL)) then Exit('');
    if (Result <> '') and not SameText(Result, Hit.QualifiedName) then Exit('');
    Result:= Hit.QualifiedName;
  end;
end;

function TLibraryOracle.VisibleOf(const ACands: TArray<TLibCand>; const AUses: TArray<string>): TArray<TLibCand>;
begin
  Result:= [];
  for var C: TLibCand in ACands do
    if InUses(C.UnitStem, AUses) then Result:= Result + [C];
end;

{ How many qualified routines named AMember live in a unit the file uses whose name is AChain,
  written whole (`System.SysUtils`) or as the suffix InUses accepts (`SysUtils`). }
function TLibraryOracle.UnitRoutine(const AChain, AMember: string; const AUses: TArray<string>;
  out AQName: string): Integer;
begin
  Result:= 0;
  AQName:= '';
  var Lc: string:= LowerCase(AChain);
  for var R: TLibCand in VisibleOf(Cached(FRoutines, AMember, ROUTINE_KINDS, False), AUses) do
    if (R.UnitStem = Lc) or R.UnitStem.EndsWith('.' + Lc) then
    begin
      Inc(Result);
      AQName:= R.QName;
    end;
end;

function TLibraryOracle.HelpersDeclare(const AStore: ISymbolStore; const AStoreTag, ATypeName, AMember: string): Boolean;
var
  CacheKey: string;
  Names   : string;
begin
  { One `;name;name;` list per store and type: a with target is asked about many names. }
  CacheKey:= AStoreTag + '#' + LowerCase(ATypeName);
  if not FHelperMembers.TryGetValue(CacheKey, Names) then
  begin
    Names:= ';';
    for var H: THelperEdge in AStore.FindHelpersOfType(ATypeName) do
      for var S: TSymbol in AStore.FindAllChildSymbols(H.HelperSymbolId) do
        Names:= Names + LowerCase(S.Name) + ';';
    FHelperMembers.Add(CacheKey, Names);
  end;
  Result:= Names.Contains(';' + LowerCase(AMember) + ';');
end;

function TLibraryOracle.CandProvesAbsent(const ACand: TLibCand; const AMember: string;
  const AProjectStore: ISymbolStore): Boolean;
var
  Hit  : TSymbol;
  Chain: TArray<string>;
begin
  if DeclaringMember(ACand, AMember, Hit) then Exit(False);
  Chain:= [ACand.Name, 'TObject'];
  for var Id: Int64 in ACand.Ids do
    for var A: TTypeAncestor in Ancestors(ACand.Store, Id) do
      if A.Resolved and (A.SymbolId > 0) then Chain:= Chain + [NormalizeTypeLeaf(A.Name)]
      else if not IsRootAncestorName(A.Name) then Exit(False);
  for var TypeName: string in Chain do
  begin
    if (AProjectStore <> nil) and HelpersDeclare(AProjectStore, 'project', TypeName, AMember) then Exit(False);
    for var Si:= 0 to High(FStores) do
      if (FStores[Si] <> nil) and HelpersDeclare(FStores[Si], IntToStr(Si), TypeName, AMember) then Exit(False);
  end;
  Result:= True;
end;

function TLibraryOracle.MemberProvablyAbsent(const ATypeText, AMember: string;
  const AProjectStore: ISymbolStore): Boolean;
begin
  var Leaf: string:= NormalizeTypeLeaf(ATypeText);
  if (Length(FStores) = 0) or (Leaf = '') or Leaf.StartsWith('^') then Exit(False);
  var Cands: TArray<TLibCand>:= Cached(FTypes, Leaf, TYPE_KINDS, True);
  Result:= Length(Cands) > 0;
  for var C: TLibCand in Cands do
    Result:= Result and CandProvesAbsent(C, AMember, AProjectStore);
end;

function TLibraryOracle.StepPending(var ACand: TLibCand; const APending: string;
  const AHelperUses: TArray<string>; out AReason: string): Boolean;
var
  Hit : TSymbol ;
  Next: TLibCand;
begin
  AReason:= '';
  if APending = '' then Exit(True);
  for var Seg: string in APending.Split(['.']) do
  begin
    if not DeclaringMember(ACand, Trim(Seg), Hit)
       or (Hit.Kind not in STEP_KINDS) then
    begin
      AReason:= R_NO_MEMBER;
      Exit(False);
    end;
    { The member's type is named in ITS declaring unit: prefer that unit, then
      what that unit uses -- never the project file's uses. }
    if not PickTypeOrHelper(MemberTypeText(Hit), LibraryUses(ACand.Store, Hit.FileId), AHelperUses, Next, AReason) then
    begin
      if AReason = R_NO_TYPE then AReason:= R_NO_MEMBER;
      Exit(False);
    end;
    ACand:= Next;
  end;
  Result:= True;
end;

function TLibraryOracle.MemberOf(const ACand: TLibCand; const AMember: string; AKind: TExternalKind;
  out AReason: string): string;
var
  Hit: TSymbol;
begin
  AReason:= '';
  if DeclaringMember(ACand, AMember, Hit) then
  begin
    if Hit.Kind in (if AKind = ekMemberAccess then OK_ACCESS else OK_CALL) then Exit(Hit.QualifiedName);
    { D10: a call through a property or field -- an event; what runs is decided at run time,
      so the answer is the PROPERTY, marked late-bound (never a routine). }
    if (AKind = ekCall) and (Hit.Kind in [skProperty, skField]) then
    begin
      AReason:= R_LATE_BOUND;
      Exit(Hit.QualifiedName);
    end;
  end;
  AReason:= R_NO_MEMBER;
  Result := '';
end;

function TLibraryOracle.Count(const AResult, AReason: string): string;
begin
  Result   := AResult;
  FLastKind:= '';
  if (AResult <> '') and (AReason = R_LATE_BOUND) then
  begin
    Inc(FStats.LateBound);
    FLastKind:= EXTERNAL_KIND_INDIRECT;
  end
  else if (AResult <> '') and (AReason = R_INTRINSIC) then
  begin
    Inc(FStats.Intrinsic);
    FLastKind:= EXTERNAL_KIND_INTRINSIC;
  end
  else if AResult <> '' then Inc(FStats.Bound)
  else if AReason = R_AMBIGUOUS then Inc(FStats.AmbiguousType)
  else if AReason = R_NO_STORE then Inc(FStats.NoStore)
  else if AReason = R_NO_TYPE then Inc(FStats.NoType)
  else Inc(FStats.NoMember);
end;

function TLibraryOracle.Bind(const ATypeText, APending, AMember: string; AKind: TExternalKind;
  const AUsesUnits: TArray<string>; out AReason: string): string;
var
  C: TLibCand;
begin
  if AKind = ekBareCall then Exit(BindBare(AMember, AUsesUnits, '', AReason));
  Result := '';
  AReason:= '';
  if Length(FStores) = 0 then AReason:= R_NO_STORE
  else if PickTypeOrHelper(ATypeText, AUsesUnits + ['system', 'sysinit'], AUsesUnits + ['system', 'sysinit'], C, AReason)
          and StepPending(C, APending, AUsesUnits + ['system', 'sysinit'], AReason) then
    Result:= MemberOf(C, AMember, AKind, AReason)
  else if (AReason = R_AMBIGUOUS) and (APending = '') then
  begin
    Result:= AgreedMember(ATypeText, AMember, AKind, AUsesUnits + ['system', 'sysinit']);
    if Result <> '' then AReason:= '';
  end;
  Result:= Count(Result, AReason);
end;

function TLibraryOracle.BindHead(const AChain, AMember: string; AKind: TExternalKind;  // dl:ok too-many-exit-points@18cf -- REVIEWED 2026-10-28 (item 4, lane R4R): the exits are Delphi's name-lookup ORDER for an untyped head -- inherited member, library type, library global, unit-qualified type -- each answering and leaving, plus the three declines inside the first rung that must stop the walk (a nearer member hides a farther meaning). One exit would thread a found flag through four rungs whose order is the contract.
  const AUsesUnits: TArray<string>; const AScopeType: string; out AReason: string;
  out ATypeText: string): string;
var
  Segs   : TArray<string>;
  Head   : string;
  Pending: string;
  Visible   : TArray<string>;
  C      : TLibCand;
  Hit    : TSymbol;
  Why    : string;

  function Finish(const AText: string): string;
  begin
    ATypeText:= AText + (if Pending <> '' then '.' + Pending else '');
    Result   := if StepPending(C, Pending, Visible, AReason) then MemberOf(C, AMember, AKind, AReason) else '';
  end;

begin
  Result   := '';
  AReason  := '';
  ATypeText:= '';
  if Length(FStores) = 0 then Exit(Count('', R_NO_STORE));
  Segs   := AChain.Split(['.']);
  Head   := Trim(Segs[0]);
  Pending:= string.Join('.', Segs, 1, Length(Segs) - 1);
  Visible   := AUsesUnits + ['system', 'sysinit'];
  { 1. Self-less: a member the enclosing class inherits from the library is
       nearer than any type or global of the name. An undecidable scope type
       (absent / ambiguous) is passed over -- a project class's library parent
       that no store holds cannot be asked. }
  if (AScopeType <> '') and PickType(AScopeType, Visible, C, Why) and DeclaringMember(C, Head, Hit) then
  begin
    if Hit.Kind not in STEP_KINDS then Exit(Count('', R_NO_MEMBER));
    var Step: TLibCand;
    if not PickType(MemberTypeText(Hit), LibraryUses(C.Store, Hit.FileId), Step, Why) then
      Exit(Count('', R_NO_MEMBER));
    C:= Step;
    Exit(Count(Finish(C.Name), AReason));
  end;
  var Values: TArray<TLibCand>:= Cached(FValues, Head, VALUE_KINDS, False);
  var SeenValues: TArray<TLibCand>:= VisibleOf(Values, Visible);
  var SeenType: Boolean:= Length(VisibleOf(Cached(FTypes, Head, TYPE_KINDS, True), Visible)) > 0;
  { 1b. `System.SysUtils.DeleteFile`: nothing visible is named Head, so the chain is a unit. }
  if not SeenType and (Length(SeenValues) = 0) then
  begin
    var Routine: string;
    var Routines: Integer:= UnitRoutine(AChain, AMember, Visible, Routine);
    if Routines > 1 then Exit(Count('', R_AMBIGUOUS));
    if Routines = 1 then Exit(Count(Routine, ''));
  end;
  if SeenType or (Length(SeenValues) = 0) then
  begin
    { 2. The head IS a library type: `TEncoding.UTF8`, `TStringList.Create`. }
    if PickType(Head, Visible, C, Why) then Exit(Count(Finish(C.Name), AReason));
    if Why = R_AMBIGUOUS then Exit(Count('', R_AMBIGUOUS));
  end
  else
    Values:= SeenValues; // a type in an unused unit does not hide what the file can see
  { 3. A library unit-level var / const: `Application`, `CodeSite`. }
  if Length(Values) > 0 then
  begin
    var V: TLibCand;
    if not Pick(Values, Visible, V, Why) then Exit(Count('', R_AMBIGUOUS));
    if not PickType(Trim(V.Sig), LibraryUses(V.Store, V.FileId), C, Why) then
      Exit(Count('', Why));
    Exit(Count(Finish(C.Name), AReason));
  end;
  { 4. `Unit.Name.TType`: the trailing segment a type declared in exactly that unit. }
  if Length(Segs) >= 2 then
  begin
    var Leaf: string:= Trim(Segs[High(Segs)]);
    var Prefix: string:= LowerCase(string.Join('.', Segs, 0, High(Segs)));
    for var T: TLibCand in Cached(FTypes, Leaf, TYPE_KINDS, True) do
      if T.UnitStem = Prefix then
      begin
        C      := T;
        Pending:= '';
        Exit(Count(Finish(C.Name), AReason));
      end;
  end;
  { D08: `TBytes.Create(1, 2)`, `TArray<Integer>.Create(1)` -- a dynamic array's constructor
    is a compiler intrinsic with no declaration: bind it to the synthetic built-in name. }
  if (AKind = ekCall) and (Pending = '') and SameText(AMember, 'Create') and IsDynArrayType(Head, Visible, 0) then
    Exit(Count(INTRINSIC_DYNARRAY_CREATE, R_INTRINSIC));
  Result:= Count('', R_NO_TYPE);
end;

function TLibraryOracle.BindBare(const AName: string; const AUsesUnits: TArray<string>;
  const AScopeType: string; out AReason: string): string;
var
  C   : TLibCand;
  Hit : TSymbol ;
  Why : string  ;
  Hits: Integer ;
begin
  Result := '';
  AReason:= '';
  if Length(FStores) = 0 then Exit(Count('', R_NO_STORE));
  var Visible: TArray<string>:= AUsesUnits + ['system', 'sysinit'];
  if (AScopeType <> '') and PickType(AScopeType, Visible, C, Why) and DeclaringMember(C, AName, Hit) then
  begin
    if Hit.Kind in OK_CALL then Exit(Count(Hit.QualifiedName, ''));
    Exit(Count('', R_NO_MEMBER));
  end;
  { A free routine: its unit must be one the file uses (System always is);
    exactly one such qualified name, or nothing. }
  Hits:= 0;
  for var R: TLibCand in Cached(FRoutines, AName, ROUTINE_KINDS, False) do
    if InUses(R.UnitStem, Visible) then
    begin
      Inc(Hits);
      Result:= R.QName;
    end;
  if Hits > 1 then
  begin
    Result := '';
    AReason:= R_AMBIGUOUS;
  end
  else if Hits = 0 then AReason:= R_NO_MEMBER;
  Result:= Count(Result, AReason);
end;

end.
