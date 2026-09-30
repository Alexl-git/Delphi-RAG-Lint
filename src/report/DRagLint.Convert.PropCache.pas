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
  dozen classes instead of expanding tens of thousands of nodes.

  T2c: the verbs that DO need a whole tree -- proptree, convert-scaffold and
  glyph-vacuum, which match by walking every node -- build it here too
  (BuildTree / BuildPropTree): each class is resolved once, breadth-first, and
  the tree is emitted depth-first from the cache. }

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
    /// <summary>The flattened property tree of a class, expanded through this
    /// cache (proptree, convert-scaffold, glyph-vacuum).</summary>
    /// <param name="AClassQName">The fully-qualified root class.</param>
    /// <param name="ADepth">The class-recursion budget: root members are
    /// 1-segment paths and a K-segment path needs ADepth &gt;= K-1; ADepth
    /// &lt;= 0 gives the root's members only.</param>
    /// <returns>The tree BuildPropTree documents; RootType = '' with no nodes
    /// when the name resolves to no class.</returns>
    /// <remarks>
    /// Two phases. EXPAND: every class within ADepth hops of the root (through
    /// class-typed properties) is resolved once, breadth-first, level by level;
    /// a class already in the cache -- from an earlier call too -- is not
    /// resolved again. EMIT: the nodes are produced depth-first from the cache
    /// with the per-path type-name cycle guard and the depth cap, in the order
    /// of the pre-cache walk (own properties, each class-typed property's
    /// subtree right after it, then fields). The expand phase can resolve a
    /// class the emit phase never reaches (one reachable only through a type
    /// name already on the path); that costs a resolution, never a node.
    /// </remarks>
    function BuildTree(const AClassQName: string; ADepth: Integer): TPropTree;
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

/// <summary>Enumerates the deep (recursively flattened) property tree of a class,
/// resolving each property's type from the index and recursing into class-typed
/// property types.</summary>
/// <param name="AStore">Open symbol store (ids are per-DB). Read-only for every
/// lookup; the sole write is the lazy MemoizePropertyType write-back described in
/// the remarks, which is itself a no-op when the store was opened read-only.</param>
/// <param name="AClassQName">Fully-qualified class name, e.g. 'Unit.TOuter'.
/// Resolved via FindSymbolsByQualifiedName; the first class-kind match is the
/// root.</param>
/// <param name="AOpts">Depth cap and the ToPersistent ancestor-stop switch.</param>
/// <returns>The flattened tree. RootType='' with empty Nodes when AClassQName
/// resolves to no class-kind symbol.</returns>
/// <remarks>
/// Own properties come from FindAllChildSymbols(classId) filtered to
/// property-kind; inherited properties are gathered by walking the ancestor
/// closure (GetTransitiveAncestors) and enumerating each ancestor class's
/// property children. An ancestor edge the INDEXER left UNRESOLVED (it declines
/// rather than guess a same-named ancestor) no longer ends the climb: the
/// ancestor NAME is bridged at QUERY time via ISymbolStore.ResolveTypeNameToClass
/// -- same shared scope rule (same unit -&gt; unique uses hit -&gt; unique leading
/// dotted-namespace segment -&gt; decline), but matched textually, so it repairs
/// indexes already on disk without a re-index. The name is resolved in the unit
/// of the class whose own heritage declares it; only when NO class in the
/// closure declares it (the declaring symbol is an interface, say) does it fall
/// back to the unit of the class that hop is climbing from -- which, at the
/// outermost hop, is the queried root. Only a class-kind result is accepted, so
/// an ancestor that resolves to an interface symbol is never placed in the
/// chain (this does NOT claim to detect a same-named CLASS standing in for what
/// was written as an interface entry). A decline still stops the climb (never a
/// guess). A bridge is refused outright when the inheriting class and the
/// candidate sit in the two CONFLICTING GUI FRAMEWORK namespaces -- one 'Vcl.*',
/// the other 'FMX.*' -- enforced in the climb itself, because the shared scope
/// rule is bypassed when a name has only one candidate. That refusal is narrow
/// and deliberately so: it is Vcl-vs-FMX ONLY, never a general
/// different-namespace veto, so a 'Vcl.*' class still reaches 'System.*',
/// 'Winapi.*', 'Data.*', a project namespace or an undotted unit normally
/// (refusing those would veto the whole RTL surface a GUI unit legitimately
/// references). Stated precisely, the guarantee is also PER HOP, not transitive:
/// each individual hop is checked, but an intermediate class in an UNDOTTED unit
/// (cxButtons, Abcbtn) belongs to NEITHER framework, so a chain may still pass
/// through one and reach the other side -- deliberately, since that is exactly
/// what lets real third-party roots bridge into Vcl.* at all.
/// The bridged climb is bounded by a visited-class-id set and a depth cap, and
/// performs NO writes, so a read-only
/// (--no-write-back) store is unaffected. Leaf names are deduped -- a redeclared property
/// shadows the ancestor's, and the most-derived declaration wins for DeclaredIn.
/// The type is parsed from the property Signature (a leading ':' + whitespace is
/// trimmed, then the first type token is taken up to whitespace / ';' / 'read' /
/// 'write'); an EMPTY Signature (a bare 'property Color;' redeclaration) is
/// resolved by finding the same-named property in an ancestor that carries a
/// non-empty Signature. As a LAST resort before 'unknown' the type is recovered by
/// BRIDGING an unresolved ancestor edge (e.g. a type-alias ancestor the index left
/// unlinked) up to the class that really declares the property (scope-aware,
/// alias-following via ISymbolStore.ResolveTypeNameToClass); a type found that way
/// is memoized back onto the property via MemoizePropertyType (no-op on a read-only
/// store). If still unresolved, TypeName='unknown', Kind='unknown',
/// and there is NO recursion (a type is never fabricated).
/// The resulting type TOKEN is then resolved to a class through the SAME shared
/// scope rule, scoped PER PROPERTY to the unit of the class that DECLARES that
/// property (not the queried root's unit), and alias-following; a class-kind
/// result is recursed into (Kind='class', IsClassTyped=True, child paths
/// prefixed with '&lt;prop&gt;.'), and the same per-hop Vcl-vs-FMX refusal
/// described above is applied between the declaring class and the candidate --
/// so a VCL class's 'System.*'-typed property (TBasicAction, TList, TComponent,
/// ...) expands normally, and only a genuine cross-GUI-framework candidate is
/// refused. Anything else -- a non-class, a refused candidate, or a decline by
/// the scope rule -- yields Kind='scalar' with TypeName still the token as
/// written, and no recursion; a decline is never retried with a scope-unaware
/// lookup, so the tree may be SMALLER than a careless resolver's but never
/// carries the other GUI framework's property surface. Recursion is bounded by
/// BOTH AOpts.Depth AND a
/// visited-TYPE-name set (keyed by the type NAME as written, so two differently
/// scoped properties naming the same type expand only once per path), so a
/// back-reference (e.g. 'Parent: TWinControl') always terminates. When
/// ToPersistent is True the ancestor climb stops at a class named 'TPersistent'
/// or 'TObject'.
/// R4 (Task 4): each visited class's OWN kind='field' and kind='const'
/// (class-scoped constant) children are ALSO emitted, as FLAT leaves
/// (member_kind='field', never recursed into even when class-typed -- out of
/// scope for this task). IsWritable is True for a field, False for a class
/// const. A field's Modifiers (visibility) is read directly (the parser
/// always stamps it); a const's Modifiers is never stamped by the parser, so
/// its effective visibility is recovered from the nearest visibility-bearing
/// sibling (see ResolveConstVisibilityByProximity) rather than left blank or
/// guessed outright. A field leaf's Kind ('class' vs 'scalar') is still decided
/// by a scope-UNAWARE name lookup -- deliberately, see Walk's field loop.
/// EXPANSION (engine 1.20.6, T2c): the tree is built through a TPropMemberCache.
/// Every class within Depth hops of the root is resolved ONCE, breadth-first, level
/// by level (a class reached on several paths is not re-resolved), and the tree
/// is then EMITTED depth-first from the cache -- own properties, each class-typed
/// property's subtree immediately after it, then fields -- with the per-path
/// cycle guard and the Depth cap applied exactly as before, so the node set and
/// its order are the pre-cache walk's minus private members (ruling R11 for a
/// private redeclaration). Truncated is set where the Depth cap stops a
/// class-typed property that would otherwise be expanded.
/// Borrows AStore; performs no I/O of its own.
/// Not thread-safe with respect to concurrent mutation of the store.
/// </remarks>
function BuildPropTree(const AStore: ISymbolStore; const AClassQName: string;
  const AOpts: TPropTreeOptions): TPropTree;

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

function TPropMemberCache.BuildTree(const AClassQName: string; ADepth: Integer): TPropTree;
var
  Root     : TClassMembers;
  Nodes    : TList<TPropNode>;
  Visited  : TDictionary<string, Boolean>;
  Truncated: Boolean;

  // EXPAND: resolve every class within ADepth hops once, level by level. A
  // class at distance D is resolved when D <= ADepth -- exactly the classes the
  // emit phase can ask for (it descends from a class only while its budget is
  // above 0) -- and its hops are queued only when D < ADepth.
  procedure Expand;
  var
    Level : TList<Int64>;
    Next  : TList<Int64>;
    Swap  : TList<Int64>;
    Queued: TDictionary<Int64, Boolean>;
    Id    : Int64;
    M     : TClassMembers;
    D     : Integer;
    I     : Integer;
  begin
    Level := TList<Int64>.Create;
    Next  := TList<Int64>.Create;
    Queued:= TDictionary<Int64, Boolean>.Create;
    try
      Level.Add(Root.ClassId);
      Queued.Add(Root.ClassId, True);
      D:= 0;
      while Level.Count > 0 do
      begin
        Next.Clear;
        for Id in Level do
        begin
          M:= MembersOfId(Id);
          if D >= ADepth then Continue;
          for I:= 0 to High(M.Members) do
            if IsDescendable(M, I) and not Queued.ContainsKey(M.TypeId[I]) then
            begin
              Queued.Add(M.TypeId[I], True);
              Next.Add(M.TypeId[I]);
            end;
        end;
        Swap := Level;
        Level:= Next;
        Next := Swap;
        Inc(D);
      end;
    finally
      Queued.Free;
      Next.Free;
      Level.Free;
    end;
  end;

  // EMIT: the pre-cache walk, reading members from the cache. APrefix is the
  // dotted path down to (and including a trailing '.') this class; Visited
  // holds the lowercased TYPE names expanded on this path.
  procedure Emit(const AMembers: TClassMembers; const APrefix: string; ADepthLeft: Integer);
  var
    Idx    : Integer;
    Node   : TPropNode;
    LowType: string;
  begin
    for Idx:= 0 to High(AMembers.Members) do
    begin
      Node     := AMembers.Members[Idx];
      Node.Path:= APrefix + Node.Path;
      Nodes.Add(Node);
      { Only a class-typed PROPERTY recurses; a field leaf is flat even when
        class-typed (R4), and a reference leaf is not class-typed. }
      if not IsDescendable(AMembers, Idx) then Continue;
      LowType:= LowerCase(Node.TypeName);
      if ADepthLeft <= 0 then
        Truncated:= True // the depth cap stopped this expansion
      else if not Visited.ContainsKey(LowType) then // else: a back-reference on this path
      begin
        Visited.Add(LowType, True);
        Emit(MembersOfId(AMembers.TypeId[Idx]), Node.Path + '.', ADepthLeft - 1);
        Visited.Remove(LowType);
      end;
    end;
  end;

begin
  Result:= Default(TPropTree);
  Root  := MembersOf(AClassQName);
  if Root.RootType = '' then Exit; // unresolved class -> empty tree, RootType=''
  Expand;
  Nodes    := TList<TPropNode>.Create;
  Visited  := TDictionary<string, Boolean>.Create;
  Truncated:= False;
  try
    Visited.Add(LowerCase(Root.RootType), True); // guard against direct self-reference
    Emit(Root, '', ADepth);
    Result.RootType := Root.RootType;
    Result.Nodes    := Nodes.ToArray;
    Result.Truncated:= Truncated;
  finally
    Visited.Free;
    Nodes.Free;
  end;
end;

function BuildPropTree(const AStore: ISymbolStore; const AClassQName: string;
  const AOpts: TPropTreeOptions): TPropTree;
var
  Cache: TPropMemberCache;
begin
  Cache:= TPropMemberCache.Create(AStore, AOpts);
  try
    Result:= Cache.BuildTree(AClassQName, AOpts.Depth);
  finally
    Cache.Free;
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
