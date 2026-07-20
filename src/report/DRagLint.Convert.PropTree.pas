unit DRagLint.Convert.PropTree;

{
  Track 3 (component conversion), Batch 1, Task 1 -- the index-driven RECURSIVE
  deep-property enumerator that backs the CLI `proptree` verb and, later, the
  convert-scaffold generator.

  It walks a class's kind='property' child symbols, parses the property type from
  each symbol's Signature, and RECURSES into class-typed property types (depth-
  capped + a visited-TYPE-name set as the cycle guard), producing flattened
  dotted paths like 'Font.Color' or 'Inner.Shade'. Inherited properties are
  included by walking the resolved ancestor closure (GetTransitiveAncestors).

  Mostly READ-ONLY. The one exception is a LAZY, best-effort write-back: when a
  bare-redeclared property's type can only be recovered by bridging an unresolved
  (type-alias) ancestor edge, the recovered type is memoized onto that property's
  signature via ISymbolStore.MemoizePropertyType so the next query is a plain hit.
  That write is a NO-OP on a read-only (query_only) store, so every read verb that
  passes a read-only store still never mutates the index. All lookups are through
  ISymbolStore.
}

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>One flattened property of the enumerated tree.</summary>
  /// <remarks>Path is the dotted route from the root class down to this leaf
  /// (e.g. 'Font.Color'); a top-level property is just its own name. TypeName is
  /// the bare declared type ('TColor', 'Integer'), or 'unknown' when it could not
  /// be parsed/resolved. DeclaredIn is the qualified name of the class in which
  /// this property is FIRST declared (a redeclaration in a more-derived class
  /// shadows the ancestor's -- the most-derived declaration wins). IsClassTyped
  /// is True only when TypeName resolved to a class-kind symbol that the walker
  /// recursed INTO. Kind is one of 'scalar' | 'class' | 'enum' | 'set' |
  /// 'unknown'.</remarks>
  TPropNode = record
    Path        : string;   // dotted, e.g. 'Font.Color'
    TypeName    : string;   // 'TColor'; 'unknown' if unresolvable
    DeclaredIn  : string;   // class qname where this property is first declared
    IsClassTyped: Boolean;  // True if TypeName resolved to a class we recursed into
    Kind        : string;   // 'scalar' | 'class' | 'enum' | 'set' | 'unknown'
  end;

  /// <summary>Tuning knobs for BuildPropTree.</summary>
  /// <remarks>Depth caps recursion into class-typed properties (the caller applies
  /// its own default -- typically 6 -- before calling; a Depth &lt;= 0 yields only
  /// the root class's own + inherited properties, no recursion). ToPersistent,
  /// when True (the CLI default), stops the ancestor climb at a class named
  /// 'TPersistent' or 'TObject' so the enumerator does not surface TObject's
  /// non-published noise -- pragmatic, name-based, no RTTI.</remarks>
  TPropTreeOptions = record
    Depth       : Integer;
    ToPersistent: Boolean;
  end;

  /// <summary>The flattened deep-property tree of a class.</summary>
  /// <remarks>RootType is the bare class name ('TOuter'), or '' when the class
  /// qname did not resolve (in which case Nodes is empty). Nodes are in
  /// enumeration order (own properties before recursed children). Truncated is
  /// True when the Depth cap stopped a class-typed expansion that would otherwise
  /// have recursed further.</remarks>
  TPropTree = record
    RootType : string;
    Nodes    : TArray<TPropNode>;
    Truncated: Boolean;
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
/// <remarks>Own properties come from FindAllChildSymbols(classId) filtered to
/// property-kind; inherited properties are gathered by walking the resolved
/// ancestor closure (GetTransitiveAncestors) and enumerating each ancestor
/// class's property children. Leaf names are deduped -- a redeclared property
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
/// and there is NO recursion (a type is never fabricated). A type that resolves
/// via FindSymbolByExactNameAnywhere to a class-kind symbol is recursed into
/// (Kind='class', IsClassTyped=True, child paths prefixed with '&lt;prop&gt;.');
/// otherwise Kind='scalar'. Recursion is bounded by BOTH AOpts.Depth AND a
/// visited-TYPE-name set, so a back-reference (e.g. 'Parent: TWinControl') always
/// terminates. When ToPersistent is True the ancestor climb stops at a class
/// named 'TPersistent' or 'TObject'. Borrows AStore; performs no I/O of its own.
/// Not thread-safe with respect to concurrent mutation of the store.</remarks>
function BuildPropTree(const AStore: ISymbolStore; const AClassQName: string;
  const AOpts: TPropTreeOptions): TPropTree;

implementation

// Parse the bare type token out of a property Signature. Handles a leading
// ": " (some rows carry it, some do not) and stops at the first whitespace,
// ';', or a 'read'/'write' accessor keyword. Returns '' when nothing parseable
// remains (an empty / accessor-only signature).
function ParseTypeToken(const ASignature: string): string;
var
  S  : string;
  P  : Integer;
  Tok: string;
  Low: string;
begin
  Result:= '';
  S:= Trim(ASignature);
  if S = '' then Exit;
  // Trim a single leading ':' then re-trim whitespace.
  if (S <> '') and (S[1] = ':') then S:= Trim(Copy(S, 2, MaxInt));
  if S = '' then Exit;
  // Take the first token up to whitespace / ';'.
  Tok:= '';
  for P:= 1 to Length(S) do
  begin
    if CharInSet(S[P], [' ', #9, #13, #10, ';']) then Break;
    Tok:= Tok + S[P];
  end;
  Low:= LowerCase(Tok);
  if (Low = 'read') or (Low = 'write') then Exit; // accessor-only; no type
  Result:= Tok;
end;

// True when the type name is one we should stop the ancestor climb at (root of
// the published-property surface) when ToPersistent is on.
function IsStopClass(const AName: string): Boolean;
var
  Low: string;
begin
  Low:= LowerCase(Trim(AName));
  Result:= (Low = 'tpersistent') or (Low = 'tobject');
end;

function BuildPropTree(const AStore: ISymbolStore; const AClassQName: string;
  const AOpts: TPropTreeOptions): TPropTree;
var
  Nodes    : TList<TPropNode>;
  Truncated: Boolean         ;

  // True when a class symbol is a mere forward declaration ('TFoo = class;')
  // rather than the real body. A forward decl spans a single line and carries no
  // heritage; the parser emits it as a separate skClass symbol with no property
  // children. DevExpress forward-declares nearly every class, so resolving a
  // qname to the stub yields 0 properties -- ResolveClassByQName must skip it.
  function IsForwardDeclClass(const S: TSymbol): Boolean;
  begin
    Result:= (S.Heritage.Trim = '') and (S.EndLine <= S.StartLine);
  end;

  // Resolve a class qname/name to its class-kind defining symbol; Id=0 if none.
  // Prefers the real body over a forward-declaration stub (both are indexed as
  // separate skClass symbols for a forward-declared class); falls back to the
  // first skClass if only stubs exist.
  function ResolveClassByQName(const AQName: string): TSymbol;
  var
    Cands   : TArray<TSymbol>;
    S       : TSymbol         ;
    FirstAny: TSymbol         ;
    HaveAny : Boolean         ;
  begin
    Result  := Default(TSymbol);
    FirstAny:= Default(TSymbol);
    HaveAny := False;
    Cands   := AStore.FindSymbolsByQualifiedName(AQName);
    for S in Cands do
      if S.Kind = skClass then
      begin
        if not HaveAny then begin FirstAny:= S; HaveAny:= True; end;
        if not IsForwardDeclClass(S) then Exit(S); // the real body -- prefer it
      end;
    if HaveAny then Result:= FirstAny; // only forward stubs found -- best effort
  end;

  // If ASym is a forward-declaration stub, re-resolve to the defining body by
  // qname (the body carries the property children); otherwise return ASym as-is.
  // type_ancestors / GetSymbolById can hand back the stub for a forward-declared
  // ancestor, so every place that reads an ancestor's children must go via this.
  function BodyOf(const ASym: TSymbol): TSymbol;
  var
    Body: TSymbol;
  begin
    Result:= ASym;
    if (ASym.Id > 0) and (ASym.Kind = skClass) and IsForwardDeclClass(ASym) then
    begin
      Body:= ResolveClassByQName(ASym.QualifiedName);
      if (Body.Id > 0) and not IsForwardDeclClass(Body) then Result:= Body;
    end;
  end;

  // Ordered list of the class + its resolved ancestor classes (most-derived
  // first). Stops climbing at TPersistent/TObject when AOpts.ToPersistent.
  function ClassChain(const ARoot: TSymbol): TArray<TSymbol>;
  var
    List: TList<TSymbol>       ;
    Anc : TArray<TTypeAncestor>;
    A   : TTypeAncestor        ;
    Sym : TSymbol              ;
  begin
    List:= TList<TSymbol>.Create;
    try
      List.Add(ARoot);
      Anc:= AStore.GetTransitiveAncestors(ARoot.Id);
      for A in Anc do
      begin
        // When ToPersistent is on, do not enumerate the props of TPersistent /
        // TObject themselves (and everything above is unreachable anyway).
        if AOpts.ToPersistent and IsStopClass(A.Name) then Break;
        if A.Resolved and (A.SymbolId > 0) and (A.Kind = 'class') then
        begin
          Sym:= BodyOf(AStore.GetSymbolById(A.SymbolId));
          if (Sym.Id > 0) and (Sym.Kind = skClass) then List.Add(Sym);
        end;
      end;
      Result:= List.ToArray;
    finally
      List.Free;
    end;
  end;

  // Resolve an empty-signature (redeclared) property's type by finding the
  // same-named property that DOES carry a signature in an ancestor class.
  function ResolveInheritedType(const AClass: TSymbol; const APropName: string): string;
  var
    Anc   : TArray<TTypeAncestor>;
    A     : TTypeAncestor        ;
    AncSym: TSymbol              ;
    Child : TSymbol              ;
    Tok   : string               ;
  begin
    Result:= '';
    Anc:= AStore.GetTransitiveAncestors(AClass.Id);
    for A in Anc do
    begin
      if not (A.Resolved and (A.SymbolId > 0)) then Continue;
      // Re-resolve a forward-decl stub to its body before reading children.
      AncSym:= BodyOf(AStore.GetSymbolById(A.SymbolId));
      if AncSym.Id <= 0 then Continue;
      Child:= AStore.FindChildSymbolByName(AncSym.Id, APropName);
      if (Child.Id > 0) and (Child.Kind = skProperty) then
      begin
        Tok:= ParseTypeToken(Child.Signature);
        if Tok <> '' then Exit(Tok);
      end;
    end;
  end;

  // RESIDUAL resolver -- the lazy ancestry BRIDGE. Runs only when ParseTypeToken
  // AND ResolveInheritedType both failed, i.e. proptree is about to emit 'unknown'
  // for a bare-redeclared (empty-signature) property whose ancestry is broken by
  // an UNRESOLVED edge. The classic case: a TYPE-ALIAS ancestor
  // ('cxButtons.TcxBaseButton = Vcl.StdCtrls.TCustomButton') -- ResolveAncestry's
  // candidate set is class/interface only, so it never links an alias ancestor and
  // the whole VCL-inherited property surface (Align, Caption, Anchors, ...) loses
  // its type. This walks UP the chain BRIDGING each unresolved ancestor NAME to its
  // defining class via the scope-aware, alias-following AStore.ResolveTypeNameToClass
  // (scope = the root class's own file, whose uses-clause disambiguates e.g. Vcl
  // from FMX), and returns the first KNOWN type declared for APropName above the
  // break. '' when the walk still finds nothing (never fabricates a type).
  function ResolveViaBridgedAncestry(const AClass: TSymbol; const APropName: string): string;
  var
    Visited: TDictionary<string, Boolean>;

    // Declared type of APropName directly on ASym (parseable signature), or ''.
    function PropTypeOn(const ASym: TSymbol): string;
    var Child: TSymbol;
    begin
      Result:= '';
      if ASym.Id <= 0 then Exit;
      Child:= AStore.FindChildSymbolByName(ASym.Id, APropName);
      if (Child.Id > 0) and (Child.Kind = skProperty) then
        Result:= ParseTypeToken(Child.Signature);
    end;

    function Climb(const ASym: TSymbol): string;
    var
      Anc: TArray<TTypeAncestor>;
      A  : TTypeAncestor        ;
      Nxt: TSymbol              ;
      Tok: string               ;
      Key: string               ;
    begin
      Result:= '';
      Anc:= AStore.GetTransitiveAncestors(ASym.Id);
      // (a) any already-RESOLVED ancestor that declares the property with a type.
      for A in Anc do
        if A.Resolved and (A.SymbolId > 0) then
        begin
          Tok:= PropTypeOn(BodyOf(AStore.GetSymbolById(A.SymbolId)));
          if Tok <> '' then Exit(Tok);
        end;
      // (b) bridge each UNRESOLVED ancestor name, then keep climbing from it.
      for A in Anc do
      begin
        if A.Resolved then Continue;
        Key:= LowerCase(A.Name);
        if (Key = '') or Visited.ContainsKey(Key) then Continue;
        Visited.Add(Key, True);
        Nxt:= BodyOf(AStore.ResolveTypeNameToClass(A.Name, AClass.FileId));
        if Nxt.Id <= 0 then Continue;
        Tok:= PropTypeOn(Nxt);   // declared directly on the bridged class?
        if Tok <> '' then Exit(Tok);
        Tok:= Climb(Nxt);        // else climb the bridged class's own chain
        if Tok <> '' then Exit(Tok);
      end;
    end;

  begin
    Visited:= TDictionary<string, Boolean>.Create;
    try
      Visited.Add(LowerCase(AClass.Name), True);
      Result:= Climb(AClass);
    finally
      Visited.Free;
    end;
  end;

  // Known limitation: descendants are enumerated by NAME (FindDescendantNames ->
  // FindSymbolByExactNameAnywhere returns one homonym) and the recovered type is
  // derived from the querying class's file scope. A shared bare property reachable
  // from two differently-scoped subtrees (e.g. VCL TAlign vs FMX TAlignLayout) can
  // receive a scope-ambiguous type, last-writer-wins. Bounded by the bare-only
  // safety rule: the worst case is unknown -> maybe-wrong, NEVER correct -> wrong.
  // Follow-up: scope-aware descendant resolution.
  //
  // Class ids of AClass + its transitive (resolved) ancestors + transitive
  // descendants -- the connected tree reachable via RESOLVED edges. Used to
  // propagate a recovered property type onto every bare same-named occurrence.
  // Computed once per walked class (cached by the caller).
  function ClosureClassIds(const AClass: TSymbol): TArray<Int64>;
  var
    Ids : TList<Int64>;
    Seen: TDictionary<Int64, Boolean>;
    A   : TTypeAncestor;
    Nm  : string;
    Sym : TSymbol;
    procedure AddId(AId: Int64);
    begin
      if (AId > 0) and not Seen.ContainsKey(AId) then begin Seen.Add(AId, True); Ids.Add(AId); end;
    end;
  begin
    Ids  := TList<Int64>.Create;
    Seen := TDictionary<Int64, Boolean>.Create;
    try
      AddId(AClass.Id);
      for A in AStore.GetTransitiveAncestors(AClass.Id) do
        if A.Resolved and (A.SymbolId > 0) then AddId(A.SymbolId);
      for Nm in AStore.FindDescendantNames(AClass.Name) do
      begin
        Sym := BodyOf(AStore.FindSymbolByExactNameAnywhere(Nm));
        if (Sym.Id > 0) and (Sym.Kind = skClass) then AddId(Sym.Id);
      end;
      Result := Ids.ToArray;
    finally
      Ids.Free;
      Seen.Free;
    end;
  end;

  // Stamp ATypeTok onto every class in AClassIds whose child property APropName
  // exists AND is bare (empty signature). Best-effort; never overwrites an
  // explicit type (the safety rule). Returns the number of rows updated.
  function PropagateBareType(const AClassIds: TArray<Int64>;
    const APropName, ATypeTok: string): Integer;
  var
    Cid  : Int64;
    Child: TSymbol;
  begin
    Result := 0;
    for Cid in AClassIds do
    begin
      Child := AStore.FindChildSymbolByName(Cid, APropName);
      if (Child.Id > 0) and (Child.Kind = skProperty) and (ParseTypeToken(Child.Signature) = '') then
        if AStore.MemoizePropertyType(Child.Id, ATypeTok) then Inc(Result);
    end;
  end;

  // The distinct property leaves visible on AClass (own + inherited), each
  // paired with the most-derived class that declares it. Dedupe by leaf name.
  procedure CollectProps(const AClass: TSymbol;
    out AOrder: TArray<TSymbol>; out ADeclaredIn: TArray<string>);
  var
    Chain: TArray<TSymbol> ;
    Cls  : TSymbol         ;
    Kids : TArray<TSymbol> ;
    Kid  : TSymbol         ;
    Seen : TDictionary<string, Boolean>;
    OL   : TList<TSymbol>  ;
    DL   : TList<string>   ;
    Key  : string          ;
  begin
    Seen:= TDictionary<string, Boolean>.Create;
    OL  := TList<TSymbol>.Create;
    DL  := TList<string >.Create;
    try
      Chain:= ClassChain(AClass); // most-derived first -> shadowing is automatic
      for Cls in Chain do
      begin
        Kids:= AStore.FindAllChildSymbols(Cls.Id);
        for Kid in Kids do
        begin
          if Kid.Kind <> skProperty then Continue;
          Key:= LowerCase(Kid.Name);
          if Seen.ContainsKey(Key) then Continue; // shadowed by a more-derived decl
          Seen.Add(Key, True);
          OL.Add(Kid);
          DL.Add(Cls.QualifiedName);
        end;
      end;
      AOrder     := OL.ToArray;
      ADeclaredIn:= DL.ToArray;
    finally
      Seen.Free;
      OL.Free;
      DL.Free;
    end;
  end;

  // Recursive walk. APrefix is the dotted path down to (and including a trailing
  // '.') the current class; AVisited holds lowercased TYPE names already expanded
  // on this path (cycle guard). ADepthLeft is the remaining class-recursion budget.
  procedure Walk(const AClass: TSymbol; const APrefix: string;
    ADepthLeft: Integer; AVisited: TDictionary<string, Boolean>);
  var
    Order      : TArray<TSymbol>;
    DeclaredIn : TArray<string> ;
    idx        : Integer        ;
    Prop       : TSymbol        ;
    Node       : TPropNode      ;
    Tok        : string         ;
    OwnTok     : string         ;
    TypeSym    : TSymbol        ;
    Body       : TSymbol        ;
    LowType    : string         ;
    ClosureIds : TArray<Int64>  ;
    ClosureDone: Boolean        ;
  begin
    ClosureDone:= False;
    CollectProps(AClass, Order, DeclaredIn);
    for idx:= 0 to High(Order) do
    begin
      Prop:= Order[idx];
      Node:= Default(TPropNode);
      Node.Path      := APrefix + Prop.Name;
      Node.DeclaredIn:= DeclaredIn[idx];

      // Parse the type from this property's own signature; if empty (a bare
      // redeclaration) resolve it from an ancestor that carries a signature, and
      // -- as a last resort before 'unknown' -- BRIDGE across an unresolved
      // (typically type-alias) ancestor edge to the class that really declares it.
      OwnTok   := ParseTypeToken(Prop.Signature);
      Tok      := OwnTok;
      if Tok = '' then Tok:= ResolveInheritedType(AClass, Prop.Name);
      if Tok = '' then
        Tok:= ResolveViaBridgedAncestry(AClass, Prop.Name);

      if Tok = '' then
      begin
        Node.TypeName    := 'unknown';
        Node.Kind        := 'unknown';
        Node.IsClassTyped:= False;
        Nodes.Add(Node);
        Continue; // no type -> no recursion
      end;

      // Persist a RECOVERED type (own signature was empty, resolved up-tree) for
      // BOTH recovery paths -- not just the bridge -- then propagate it DOWN/UP
      // across the queried class's connected tree onto every bare occurrence.
      if (OwnTok = '') and (Tok <> '') then
      begin
        if not ClosureDone then begin ClosureIds:= ClosureClassIds(AClass); ClosureDone:= True; end;
        PropagateBareType(ClosureIds, Prop.Name, Tok);
        // Ensure the queried row itself is stamped even if the closure walk
        // somehow missed it (e.g. name-lookup ambiguity): direct memoize.
        if Prop.Id > 0 then AStore.MemoizePropertyType(Prop.Id, Tok);
      end;

      Node.TypeName:= Tok;

      // Classify: resolve the type name; a class-kind symbol -> recurse.
      TypeSym:= AStore.FindSymbolByExactNameAnywhere(Tok);
      if (TypeSym.Id > 0) and (TypeSym.Kind = skClass) then
      begin
        Node.Kind        := 'class';
        Node.IsClassTyped:= True;
        Nodes.Add(Node);

        // FindSymbolByExactNameAnywhere may return a forward-decl stub; re-resolve
        // to the defining body (by qname) before recursing, else the nested class
        // would enumerate 0 properties (the DevExpress forward-decl case).
        if IsForwardDeclClass(TypeSym) then
        begin
          Body:= ResolveClassByQName(TypeSym.QualifiedName);
          if Body.Id > 0 then TypeSym:= Body;
        end;

        LowType:= LowerCase(Tok);
        if ADepthLeft <= 0 then
          Truncated:= True                 // depth cap stopped this expansion
        else if AVisited.ContainsKey(LowType) then
          // back-reference on this path -> terminate (already expanded above)
        else
        begin
          AVisited.Add(LowType, True);
          Walk(TypeSym, Node.Path + '.', ADepthLeft - 1, AVisited);
          AVisited.Remove(LowType);
        end;
      end
      else
      begin
        Node.Kind        := 'scalar';
        Node.IsClassTyped:= False;
        Nodes.Add(Node);
      end;
    end;
  end;

var
  Root   : TSymbol                    ;
  Visited: TDictionary<string, Boolean>;
begin
  Result          := Default(TPropTree);
  Result.RootType := '';
  Result.Truncated:= False;
  SetLength(Result.Nodes, 0);

  Root:= ResolveClassByQName(AClassQName);
  if Root.Id = 0 then Exit; // unresolved class -> empty tree, RootType=''

  Nodes    := TList<TPropNode>.Create;
  Visited  := TDictionary<string, Boolean>.Create;
  Truncated:= False;
  try
    Result.RootType:= Root.Name;
    Visited.Add(LowerCase(Root.Name), True); // guard against direct self-reference
    Walk(Root, '', AOpts.Depth, Visited);
    Result.Nodes    := Nodes.ToArray;
    Result.Truncated:= Truncated;
  finally
    Nodes.Free;
    Visited.Free;
  end;
end;

end.
