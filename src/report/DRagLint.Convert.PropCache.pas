unit DRagLint.Convert.PropCache;

{ The unfolded member cache (engine 1.20.6, tree redesign T2b).

  convert-validate / convert-apply / convert-reemit used to materialise a whole
  property TREE per type (BuildPropTree, depth 6) and then look a handful of
  exact paths up in it. On FireDAC.Comp.Client.TFDQuery that tree is ~700k
  nodes at depth 6 -- hours -- because the same class is re-expanded on every
  path it recurs on. No consumer needed the tree: every one of them asks "does
  THIS path exist, and what is its leaf?".

  This unit answers exactly that. A class's ONE-LEVEL members are resolved once
  (TPropMemberResolver -- the very code BuildPropTree runs per level) and
  cached by class id; a dotted path is then resolved segment by segment, each
  hop a dictionary hit. Validating convrules\BDE-to-FireDAC.rules touches a few
  dozen classes instead of expanding tens of thousands of nodes. }

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Convert.PropTree;

type
  /// <summary>Which surface a path lookup is for.</summary>
  /// <remarks>
  /// psDfm (a .dfm streams it, or a conversion rule names it): the LEAF must be
  /// a published property; an INTERMEDIATE hop must be a published property, or
  /// a public one that is class-typed (a container -- a collection's public
  /// default 'Items', which a .dfm streams as item blocks rather than as a
  /// published hop). Fields never pass on psDfm.
  /// psPas (Pascal source): published, public or protected, on every hop.
  /// Private and strict private never resolve on either surface -- they are not
  /// even cached. Controller ruling R8, 2026-09-30.
  /// </remarks>
  TPropSurface = (psDfm, psPas);

  /// <summary>One class's resolved ONE-LEVEL members, own + inherited
  /// (most-derived wins), private/strict private excluded, fields
  /// included (MemberKind='field').</summary>
  /// <remarks>
  /// Members, TypeQName, TypeId and IsCompRef are index-aligned. Members[i].Path
  /// is the BARE member name; every other TPropNode field is filled exactly as
  /// BuildPropTree fills it. TypeQName/TypeId name the class a property's type
  /// resolved to ('' / 0 for a scalar, an unknown type or a field); IsCompRef
  /// marks a TComponent-typed property under TreatRefsAsLeaves -- a reference
  /// leaf, IsClassTyped False, never descended into. RootType is the class's
  /// bare name, '' when the qualified name resolved to no class.
  /// </remarks>
  TClassMembers = record
    ClassId  : Int64;
    QName    : string;
    RootType : string;
    Members  : TArray<TPropNode>;
    TypeQName: TArray<string>;
    TypeId   : TArray<Int64>;
    IsCompRef: TArray<Boolean>;
  end;

  /// <summary>The unfolded cache: one TClassMembers per class id, built on
  /// first use and kept for the lifetime of the object.</summary>
  /// <remarks>
  /// One per ISymbolStore per process run: convert-apply's TConvertTreeCache
  /// owns one per --db store; convert-validate and convert-reemit one per store
  /// they open. Class ids are per store, so a cache never mixes stores.
  /// Reads only; the store's own memoize write-back (TPropMemberResolver) is
  /// unchanged. Not thread-safe.
  /// </remarks>
  TPropMemberCache = class
  private
    FResolver : TPropMemberResolver;
    FIdByQName: TDictionary<string, Int64>;         // UPPER(qname) -> class id; 0 = does not resolve
    FById     : TDictionary<Int64, TClassMembers>;  // class id -> its members
    FSymById  : TDictionary<Int64, TSymbol>;        // class id -> its symbol, for descending
    FBuilt    : Integer;
    function MembersOfSym(const AClass: TSymbol): TClassMembers;
    function MembersOfId(AClassId: Int64): TClassMembers;
  public
    /// <summary>Creates an empty cache over one index.</summary>
    /// <param name="AStore">The open symbol store. Borrowed, not owned.</param>
    /// <param name="AOpts">ToPersistent and TreatRefsAsLeaves apply exactly as
    /// in BuildPropTree; Depth is ignored -- a path is as deep as it is
    /// written.</param>
    constructor Create(const AStore: ISymbolStore; const AOpts: TPropTreeOptions);
    /// <summary>Frees the cache.</summary>
    destructor Destroy; override;
    /// <summary>The members of the class AClassQName names.</summary>
    /// <param name="AClassQName">A fully-qualified class name.</param>
    /// <returns>The class's members; RootType = '' (and no members) when the
    /// name resolves to no class in this store.</returns>
    /// <remarks>Cached by class id: each class is resolved once per cache, an
    /// unresolved name is remembered too.</remarks>
    function MembersOf(const AClassQName: string): TClassMembers;
    /// <summary>Resolves a dotted member path from a root class, one segment
    /// at a time.</summary>
    /// <param name="ARootQName">The fully-qualified root class.</param>
    /// <param name="APath">The dotted path ('Font.Color'); segments compare
    /// case-insensitively.</param>
    /// <param name="ASurface">Which visibility rule applies -- see
    /// TPropSurface.</param>
    /// <param name="ANode">Receives the leaf member, with Path := APath as
    /// given; Default(TPropNode) when the result is False.</param>
    /// <returns>True when every segment is a member of the class the previous
    /// segment resolved to and passes ASurface.</returns>
    /// <remarks>
    /// An intermediate segment must be a class-typed PROPERTY (fields and
    /// reference leaves are never descended into) whose type has not already
    /// been passed through on this path -- the same per-path cycle guard
    /// BuildPropTree applies (the root's own name counts), so a path is found
    /// here exactly when a tree of sufficient depth would contain it. There is
    /// no depth limit.
    /// </remarks>
    function ResolvePath(const ARootQName, APath: string; ASurface: TPropSurface;
      out ANode: TPropNode): Boolean;
    /// <summary>How many classes this cache has resolved (apply/1
    /// classes_built).</summary>
    property ClassesBuilt: Integer read FBuilt;
  end;

  /// <summary>One side of a conversion: a qualified class name and the cache
  /// of the store it resolved in.</summary>
  /// <remarks>QName = '' or Cache = nil means "not checked here" -- every
  /// query then answers absent and RootType is ''. The record does not own
  /// Cache.</remarks>
  TClassRef = record
    QName: string;
    Cache: TPropMemberCache;
    /// <summary>The class's bare name; '' when it does not resolve.</summary>
    /// <returns>MembersOf(QName).RootType, or '' when unset.</returns>
    function RootType: string;
    /// <summary>TPropMemberCache.ResolvePath from this class.</summary>
    /// <param name="APath">The dotted path.</param>
    /// <param name="ASurface">The visibility rule.</param>
    /// <param name="ANode">Receives the leaf.</param>
    /// <returns>False when unset, or when the path does not resolve.</returns>
    function ResolvePath(const APath: string; ASurface: TPropSurface;
      out ANode: TPropNode): Boolean;
  end;

implementation

{ TPropMemberCache }

constructor TPropMemberCache.Create(const AStore: ISymbolStore; const AOpts: TPropTreeOptions);
begin
  inherited Create;
  FResolver := TPropMemberResolver.Create(AStore, AOpts);
  FIdByQName:= TDictionary<string, Int64>.Create;
  FById     := TDictionary<Int64, TClassMembers>.Create;
  FSymById  := TDictionary<Int64, TSymbol>.Create;
end;

destructor TPropMemberCache.Destroy;
begin
  FSymById.Free;
  FById.Free;
  FIdByQName.Free;
  FResolver.Free;
  inherited Destroy;
end;

function TPropMemberCache.MembersOfSym(const AClass: TSymbol): TClassMembers;
var
  Types: TArray<TSymbol>;
  I    : Integer;
begin
  if FById.TryGetValue(AClass.Id, Result) then Exit;
  Result         := Default(TClassMembers);
  Result.ClassId := AClass.Id;
  Result.QName   := AClass.QualifiedName;
  Result.RootType:= AClass.Name;
  FResolver.ResolveMembers(AClass, Result.Members, Types, Result.IsCompRef);
  SetLength(Result.TypeQName, Length(Result.Members));
  SetLength(Result.TypeId   , Length(Result.Members));
  for I:= 0 to High(Types) do
    if Types[I].Id > 0 then
    begin
      Result.TypeQName[I]:= Types[I].QualifiedName;
      Result.TypeId[I]   := Types[I].Id;
      FSymById.AddOrSetValue(Types[I].Id, Types[I]);
    end;
  FSymById.AddOrSetValue(AClass.Id, AClass);
  FById.Add(AClass.Id, Result);
  Inc(FBuilt);
end;

function TPropMemberCache.MembersOfId(AClassId: Int64): TClassMembers;
var
  Sym: TSymbol;
begin
  if (AClassId > 0) and FSymById.TryGetValue(AClassId, Sym) then Exit(MembersOfSym(Sym));
  Result:= Default(TClassMembers);
end;

function TPropMemberCache.MembersOf(const AClassQName: string): TClassMembers;
var
  Key: string;
  Id : Int64;
  Sym: TSymbol;
begin
  Key:= UpperCase(Trim(AClassQName));
  if Key = '' then Exit(Default(TClassMembers));
  if FIdByQName.TryGetValue(Key, Id) then Exit(MembersOfId(Id));
  Sym:= FResolver.ResolveClassByQName(Trim(AClassQName));
  FIdByQName.Add(Key, Sym.Id);
  if Sym.Id <= 0 then Exit(Default(TClassMembers));
  Result:= MembersOfSym(Sym);
end;

// Ruling R8 -- see TPropSurface.
function PassesSurface(const ANode: TPropNode; ASurface: TPropSurface; AIsLeaf: Boolean): Boolean;
var
  Vis: string;
begin
  Vis:= LowerCase(Trim(ANode.Visibility));
  if ASurface = psPas then
    Exit((Vis = 'published') or (Vis = 'public') or (Vis = 'protected'));
  if ANode.MemberKind <> 'property' then Exit(False);
  if AIsLeaf then Exit(Vis = 'published');
  Result:= (Vis = 'published') or ((Vis = 'public') and ANode.IsClassTyped);
end;

// Index of the member named AName in AMembers (case-insensitive), -1 if none.
function IndexOfMember(const AMembers: TClassMembers; const AName: string): Integer;
var
  J: Integer;
begin
  for J:= 0 to High(AMembers.Members) do
    if SameText(AMembers.Members[J].Path, AName) then Exit(J);
  Result:= -1;
end;

// True when the member at AIdx can be descended into as a hop: a class-typed
// PROPERTY whose class resolved (fields and reference leaves never are).
function IsDescendable(const AMembers: TClassMembers; AIdx: Integer): Boolean;
begin
  Result:= (AMembers.Members[AIdx].MemberKind = 'property') and AMembers.Members[AIdx].IsClassTyped and
           (AMembers.TypeId[AIdx] > 0);
end;

function TPropMemberCache.ResolvePath(const ARootQName, APath: string; ASurface: TPropSurface;
  out ANode: TPropNode): Boolean;
var
  Segs   : TArray<string>;
  Cur    : TClassMembers;
  Visited: TList<string>;
  I      : Integer;
  Idx    : Integer;
  IsLeaf : Boolean;
begin
  Result:= False;
  ANode := Default(TPropNode);
  Segs  := Trim(APath).Split(['.']);
  Cur   := MembersOf(ARootQName);
  if (Length(Segs) = 0) or (Cur.RootType = '') then Exit;
  Visited:= TList<string>.Create;
  try
    Visited.Add(LowerCase(Cur.RootType)); // BuildPropTree's direct self-reference guard
    for I:= 0 to High(Segs) do
    begin
      IsLeaf:= I = High(Segs);
      Idx   := IndexOfMember(Cur, Trim(Segs[I]));
      if (Idx < 0) or not PassesSurface(Cur.Members[Idx], ASurface, IsLeaf) then Exit;
      if IsLeaf then
      begin
        ANode     := Cur.Members[Idx];
        ANode.Path:= APath;
        Exit(True);
      end;
      { A hop: a class-typed property, not a type already passed through on this
        path (BuildPropTree's per-path cycle guard). }
      if (not IsDescendable(Cur, Idx)) or Visited.Contains(LowerCase(Cur.Members[Idx].TypeName)) then Exit;
      Visited.Add(LowerCase(Cur.Members[Idx].TypeName));
      Cur:= MembersOfId(Cur.TypeId[Idx]);
      if Cur.RootType = '' then Exit;
    end;
  finally
    Visited.Free;
  end;
end;

{ TClassRef }

function TClassRef.RootType: string;
begin
  if (QName = '') or (Cache = nil) then Exit('');
  Result:= Cache.MembersOf(QName).RootType;
end;

function TClassRef.ResolvePath(const APath: string; ASurface: TPropSurface;
  out ANode: TPropNode): Boolean;
begin
  ANode:= Default(TPropNode);
  if (QName = '') or (Cache = nil) then Exit(False);
  Result:= Cache.ResolvePath(QName, APath, ASurface, ANode);
end;

end.
