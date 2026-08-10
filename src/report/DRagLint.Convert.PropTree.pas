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

  R4 (Task 4): ALSO walks each class's own kind='field' AND kind='const'
  (class-scoped `const X: T = v;`) child symbols, emitted as FLAT leaves
  (member_kind='field', no recursion into class-typed fields -- out of
  scope). This is what lets a PAS-surface conversion target a public field,
  not just a published property. See TPropNode.MemberKind/IsWritable and
  Walk's field loop for the writability + effective-visibility rules.

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
  /// <remarks>
  /// Path is the dotted route from the root class down to this leaf
  /// (e.g. 'Font.Color'); a top-level property is just its own name. TypeName is
  /// the bare declared type ('TColor', 'Integer'), or 'unknown' when it could not
  /// be parsed/resolved. DeclaredIn is the qualified name of the class in which
  /// this property is FIRST declared (a redeclaration in a more-derived class
  /// shadows the ancestor's -- the most-derived declaration wins). IsClassTyped
  /// is True only when TypeName resolved to a class-kind symbol that the walker
  /// recursed INTO. Kind is one of 'scalar' | 'class' | 'enum' | 'set' |
  /// 'unknown'.
  /// Visibility (proptree/2) is the EFFECTIVE, most-derived member visibility,
  /// normalized to the 5-value domain 'published' | 'public' | 'protected' |
  /// 'private' | '' (unresolvable) -- the parser's 'strict private'/'strict
  /// protected' (Delphi's `strict` keyword, unit-scoped access) are collapsed
  /// to 'private'/'protected' respectively, since the strict/non-strict
  /// distinction is same-unit-only and irrelevant to the cross-unit
  /// assignability question proptree exists to answer. A published bare
  /// redeclaration of a protected/public ancestor property RAISES the
  /// effective visibility to published -- the ancestor's (lower) visibility is
  /// never used when the most-derived declaration's own modifiers are known.
  /// When the most-derived declaration's own modifiers are empty (a defensive
  /// case; the current parser always stamps a non-empty value), the same
  /// ancestor walk used for TypeName resolves the nearest ancestor's
  /// visibility instead of leaving it blank.
  /// IsWritable (proptree/2) is REAL property writability (R1, Task 6): the
  /// most-derived declaration's resolved prop_access accessor shape -- 'ro' ->
  /// False, 'rw'/'wo' -> True (write-only is a valid assignment TARGET). A bare
  /// redeclaration inherits the nearest CLASS ancestor's accessor clause (same
  /// resolution as TypeName, interface-filtered); an empty/NULL prop_access (no
  /// clause up-tree, or a pre-v17 / un-re-indexed DB) defaults True -- today's
  /// back-compat behaviour. This is independent of, and does not touch, the
  /// FIELD writability below (Task 4).
  /// MemberKind (proptree/2) is 'property' for property leaves.
  /// R4 (Task 4) adds FIELD leaves: MemberKind='field' for both a plain class
  /// field (`public FThing: Integer;`) and a class-scoped constant
  /// (`const KMax: Integer = v;` inside a class -- the index stores it as a
  /// DIFFERENT SymbolKind, skConstDecl, distinguishable from skField by kind
  /// alone). IsWritable for a field leaf is field-scoped and real (not
  /// staged): True for a plain field, False for a class constant (Object
  /// Pascal constants -- typed or not -- are never assignable). A class
  /// constant's declared visibility is NOT captured by the current indexer
  /// (verified empirically: its Modifiers column is always '', unlike
  /// skField/skProperty which the parser DOES stamp with the enclosing
  /// section's visibility) -- see Walk's field loop and
  /// ResolveConstVisibilityByProximity for how the effective visibility is
  /// recovered from the nearest visibility-bearing sibling instead of being
  /// fabricated.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoConvertScaffold.NodeOfPath (DRagLint.CLI.pas), DRagLint.Convert.DfmReemit.LeafTypeOf (DRagLint.Convert.DfmReemit.pas), DRagLint.Convert.PropTree.BuildPropTree.Walk (DRagLint.Convert.PropTree.pas), DRagLint.Convert.PropTree.BuildPropTree (DRagLint.Convert.PropTree.pas), DRagLint.Convert.Rules.PathExists (DRagLint.Convert.Rules.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Convert.DfmReemit, DRagLint.Convert.PropTree, DRagLint.Convert.Rules
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPropNode = record
    Path        : string;   // dotted, e.g. 'Font.Color'
    TypeName    : string;   // 'TColor'; 'unknown' if unresolvable
    DeclaredIn  : string;   // class qname where this property is first declared
    IsClassTyped: Boolean;  // True if TypeName resolved to a class we recursed into
    Kind        : string;   // 'scalar' | 'class' | 'enum' | 'set' | 'unknown'
    Visibility  : string;   // proptree/2: effective (most-derived) visibility; '' if unresolvable
    IsWritable  : Boolean;  // proptree/2: REAL writability -- property leaves from resolved prop_access (R1/Task 6: ro=>false, rw/wo=>true, ''/NULL=>true back-compat); field leaves from R4 (false only for a class const)
    MemberKind  : string;   // proptree/2: 'property' or 'field' (R4: field/const leaves)
  end;

  /// <summary>Tuning knobs for BuildPropTree.</summary>
  /// <remarks>
  /// Depth caps recursion into class-typed properties (the caller applies
  /// its own default -- typically 6 -- before calling; a Depth &lt;= 0 yields only
  /// the root class's own + inherited properties, no recursion). ToPersistent,
  /// when True (the CLI default), stops the ancestor climb at a class named
  /// 'TPersistent' or 'TObject' so the enumerator does not surface TObject's
  /// non-published noise -- pragmatic, name-based, no RTTI.
  /// No field is a managed type, so a local variable of this record is raw,
  /// UNINITIALISED stack memory in Delphi -- nothing zeroes it. Every caller
  /// MUST start with `Opts:= Default(TPropTreeOptions);` before assigning any
  /// field, so a field the caller does not explicitly set (today or after a
  /// future field is added) is deterministically False/0/'' rather than
  /// whatever garbage happened to be on the stack.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoPropTree (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate (DRagLint.CLI.pas), DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.CLI.DoConvertScaffold (DRagLint.CLI.pas), DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas) (+2 more)
  /// Used in units: DRagLint.CLI, DRagLint.Convert.Apply, DRagLint.Convert.PropTree
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPropTreeOptions = record
    Depth       : Integer;
    ToPersistent: Boolean;
    /// <summary>When True, a property whose type is a TComponent descendant is a
    /// REFERENCE leaf (emitted, NOT recursed into) -- a referenced component is not
    /// an owned sub-object. Owned TPersistent sub-objects (TFont, TStrings, ...)
    /// still expand. Default False (unchanged legacy behavior); the proptree verb
    /// sets it from --refs-as-leaves.</summary>
    TreatRefsAsLeaves: Boolean;
  end;

  /// <summary>The flattened deep-property tree of a class.</summary>
  /// <remarks>
  /// RootType is the bare class name ('TOuter'), or '' when the class
  /// qname did not resolve (in which case Nodes is empty). Nodes are in
  /// enumeration order (own properties before recursed children). Truncated is
  /// True when the Depth cap stopped a class-typed expansion that would otherwise
  /// have recursed further.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoPropTree (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate.TreeFor (DRagLint.CLI.pas), DRagLint.CLI.DoConvertReemit (DRagLint.CLI.pas), DRagLint.CLI.DoConvertReemit.TreeFor (DRagLint.CLI.pas) (+9 more)
  /// Used in units: DRagLint.CLI, DRagLint.Convert.Apply, DRagLint.Convert.DfmReemit, DRagLint.Convert.PropTree, DRagLint.Convert.Rules
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
/// Borrows AStore; performs no I/O of its own.
/// Not thread-safe with respect to concurrent mutation of the store.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoConvertApply.TreeFor (DRagLint.CLI.pas), DRagLint.CLI.DoConvertReemit.TreeFor (DRagLint.CLI.pas), DRagLint.CLI.DoConvertScaffold (DRagLint.CLI.pas), DRagLint.CLI.DoConvertValidate.TreeFor (DRagLint.CLI.pas), DRagLint.CLI.DoPropTree (DRagLint.CLI.pas) (+1 more)
/// Calls: AddId, BodyOf, ClassChain, Climb, ClimbFrom, ClosureClassIds, CollectFields, CollectProps, CrossesGuiFramework, Default (+21 more)
/// Returns: List.ToArray; Climb(AClass); Ids.ToArray; Default(TPropTree)
/// Pure
/// <seealso cref="DRagLint.Convert.PropTree.BuildPropTree.ResolveClassByQName"/>
/// <seealso cref="DRagLint.Convert.PropTree.BuildPropTree.Walk"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
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

// True when a class symbol's declaration is INDISTINGUISHABLE, in the index as
// it exists on disk, from a class-REFERENCE declaration
// ('TWinControlClass = class of TWinControl;'). The parser emits such a
// declaration as kind='class' with heritage='TWinControl' spanning a single
// line -- byte-for-byte the same shape it emits for a genuine one-line subclass
// ('EFIBInterBaseError = class(EFIBError) end;'): same kind, empty signature,
// empty modifiers, single line, non-empty heritage. VERIFIED against
// library-Win64.sqlite: all five TWinControlClass rows and the fib/FIBDataSet
// one-line subclasses are identical on every stored column.
//
// This matters because a class REFERENCE does not inherit an instance property
// surface -- `class of TWinControl` has no Align, no Font, no Left. Bridging
// such an edge would hand the conversion editor thousands of leaves that cannot
// be assigned (measured: Vcl.Controls.TControl's FloatingDockSiteClass alone
// expanded from 1 leaf to 2957). Telling the two constructs apart needs a
// parser/schema change and therefore a RE-INDEX, which the query-time fallback
// exists precisely to avoid, so the fallback applies the same policy as the
// rest of this engine: when unsure, don't claim -- it declines to bridge from
// one, leaving those chains exactly where they stop today.
//
// Only the query-time FALLBACK consults this. Edges the indexer already
// resolved keep their current behaviour untouched (this changes nothing about
// them), and the bare-property-type walk (ResolveViaBridgedAncestry) never
// needs it: a class reference declares no properties, so that walk cannot
// reach one as a property-declaring class.
function IsIndistinguishableFromClassRef(const ASym: TSymbol): Boolean;
begin
  Result:= (ASym.Kind = skClass) and (ASym.Heritage.Trim <> '') and
           (ASym.EndLine <= ASym.StartLine);
end;

// Normalize ONE raw heritage token to the form stored in
// type_ancestors.ancestor_name: trim, drop a generic argument list
// (TList<TFoo> -> TList), then take the dotted tail
// (System.Classes.TComponent -> TComponent). Deliberately mirrors
// DRagLint.Storage.SQLite's NormalizeAncestorName (kept local -- that one is
// unit-private) so a heritage token and the ancestor_name row the indexer
// derived FROM it compare equal by construction.
function NormalizeHeritageToken(const ARaw: string): string;
var
  S: string ;
  P: Integer;
begin
  S:= Trim(ARaw);
  P:= Pos('<', S);
  if P > 0 then S:= Trim(Copy(S, 1, P - 1));
  P:= LastDelimiter('.', S);
  if P > 0 then S:= Copy(S, P + 1, MaxInt);
  Result:= Trim(S);
end;

// True when AName is one of AHeritage's OWN entries -- i.e. the class carrying
// AHeritage is the one that DIRECTLY inherits/implements AName. Splits on
// TOP-LEVEL commas only (mirrors DRagLint.Storage.SQLite's SplitHeritageList,
// so a generic ancestor's own comma -- TDictionary<string, Integer> -- does not
// split the list) and compares each token through NormalizeHeritageToken.
// Used by the query-time ancestor fallback to find WHICH class in a transitive
// closure actually declares an unresolved ancestor name, so that name is
// resolved in THAT class's unit scope (design criterion 7) rather than in the
// scope of whatever class the walk happened to start from.
function HeritageDeclares(const AHeritage, AName: string): Boolean;
var
  Depth: Integer;
  Start: Integer;
  i    : Integer;
  Ch   : Char   ;
begin
  Result:= False;
  if (Trim(AHeritage) = '') or (Trim(AName) = '') then Exit;
  Depth:= 0;
  Start:= 1;
  for i:= 1 to Length(AHeritage) do
  begin
    Ch:= AHeritage[i];
    if Ch = '<' then Inc(Depth)
    else if Ch = '>' then Dec(Depth)
    else if (Ch = ',') and (Depth <= 0) then
    begin
      if SameText(NormalizeHeritageToken(Copy(AHeritage, Start, i - Start)), AName) then Exit(True);
      Start:= i + 1;
    end;
  end;
  if Start <= Length(AHeritage) then
    Result:= SameText(NormalizeHeritageToken(Copy(AHeritage, Start, MaxInt)), AName);
end;

// The class whose OWN heritage lists AName -- i.e. the class actually doing the
// inheriting at this hop, which is the scope an unresolved ancestor name must be
// resolved in (design criterion 7). AKnown is the current hop's class followed
// by the resolved classes of its ancestor closure, most-derived first, so the
// first match is the nearest declarer.
//
// LAST RESORT, stated plainly: when NO class in AKnown declares AName -- e.g.
// the declaring class is an INTERFACE, which never enters AKnown -- this returns
// AFallback, the class the current hop is climbing FROM. At the outermost call
// that IS the queried root, so in exactly that residual case the name is
// resolved in the root's unit. That is the criterion-7 defect at reduced radius,
// not its absence: it is confined to closures whose declarer is not a class, and
// it is one reason the caller ALSO applies CrossesGuiFramework below rather than
// trusting the derived scope on its own.
function ScopeSymbolFor(const AKnown: TList<TSymbol>; const AFallback: TSymbol;
  const AName: string): TSymbol;
var
  K: TSymbol;
begin
  Result:= AFallback;
  if not Assigned(AKnown) then Exit;
  for K in AKnown do
    if HeritageDeclares(K.Heritage, AName) then Exit(K);
end;

// The "which two namespaces are mutually exclusive" question -- {Vcl, FMX} --
// is answered ONCE, by DRagLint.Core.Model.IsGuiFrameworkPrefix, which this
// unit's CrossesGuiFramework (the REFUSE side) and DRagLint.Storage.SQLite's
// ancestry-derived framework anchor (the SELECT side) both call. It used to be
// defined here; it moved to the shared base unit when the select side needed it
// too, so the pair is never spelled out twice. Semantics unchanged.

// True when binding AInheritor to ACandidate would cross between the two
// CONFLICTING GUI FRAMEWORKS -- the guard behind design criterion 5, "SHALL
// NEVER select an FMX.* ancestor for a Vcl.* class, nor the reverse".
//
// WHY THIS IS NEEDED ON TOP OF THE SHARED SCOPE RULE. ResolveTypeNameToClass ->
// PickCandidate short-circuits on a SINGLE candidate (DRagLint.Storage.SQLite:
// 'if Length(Types) = 1 then Exit(Types[0])'), so PickAncestorCandidateByScope
// -- and with it rule 3's namespace check -- is consulted ONLY when two or more
// same-named candidates exist. A Vcl-scoped class whose ancestor name or
// property type resolves to the ONE class of that name, living in an FMX unit,
// would otherwise be accepted with no scope check at all.
//
// SCOPE OF THE REFUSAL -- read this before widening it. It refuses ONLY
// Vcl-vs-FMX. It is NOT a general "different namespace" veto, and an earlier
// revision of this function that WAS one had to be narrowed: refusing on any
// differing prefix vetoed the whole RTL surface referenced from VCL. Measured on
// library-Win64.sqlite, that silently degraded correct, unambiguous resolutions
// to 'scalar' -- 'Vcl.Controls.TControl.Action: TBasicAction' (declared in
// System.Classes, 137 descendants, on 5 of the 6 baseline qnames),
// 'TWinControl.AlignControlList: TList', 'Vcl.Menus.*.PopupComponent:
// TComponent', and every 'PResource'-typed property. Those are not ambiguous and
// not cross-framework; they are ordinary VCL-uses-RTL references.
//
// Criterion 5 says "never select an FMX.* ancestor for a Vcl.* class, nor the
// reverse". It does not say "never cross a namespace". Selecting BY namespace
// affinity is a sound heuristic and the select side (PickAncestorCandidateByScope
// rule 3) stays generic for exactly that reason; refusing BY namespace difference
// is not sound, because most namespace differences are legitimate.
//
// Both segments come from DRagLint.Core.Model.UnitFrameworkPrefix -- the same
// leading-dotted-segment notion the select-side rule uses, one definition. An
// UNDOTTED unit yields '', which is not a GUI framework prefix, so it is never
// refused: that is what keeps the real third-party roots working
// ('cxButtons.TcxCustomButton' -> 'Vcl.StdCtrls.TCustomButton', 'Abcbtn.*' ->
// 'Vcl.Controls.*'). The Vcl/FMX pair itself is named explicitly rather than
// derived -- see DRagLint.Core.Model.IsGuiFrameworkPrefix for why, and for the
// one place it is written down.
{ CrossesGuiFramework MOVED to DRagLint.Core.Model (v: merge main ->
  autodoc-phase3). It was local here; the storage layer's late-ancestor
  resolution needs the SAME refusal, and this unit cannot be a dependency of
  that one. Two copies of a criterion-5 predicate is how criterion 5 ends up
  enforced on one path and not the other -- which is exactly what happened, and
  what run_proptree_ancestor_climb / run_proptree_prop_type_scope caught. The
  call sites below are unchanged; the declaration now lives beside
  UnitFrameworkPrefix and IsGuiFrameworkPrefix, which it is built from. }

const
  // Hard cap on how many BRIDGED hops ClassChain's query-time fallback may
  // take from one starting class. Belt-and-braces next to the visited-class-id
  // set (which alone already terminates the climb, since every recursion must
  // first add a class id never seen on this chain): a malformed or
  // self-referential index must not be able to spin, and no real Object Pascal
  // hierarchy is anywhere near this deep. Matches GetTransitiveAncestors' own
  // 64-hop BFS bound (DRagLint.Storage.SQLite.pas).
  CMaxBridgedChainDepth = 64;

function BuildPropTree(const AStore: ISymbolStore; const AClassQName: string;
  const AOpts: TPropTreeOptions): TPropTree;
var
  Nodes    : TList<TPropNode>;
  Truncated: Boolean         ;
  // Per-QUERY memoization for the two scope-aware lookups (each hits the DB
  // several times, and both are re-asked constantly: ClassChain is called at
  // least twice per walked class -- CollectProps + CollectFields -- plus once
  // more for every path a class-typed property is re-expanded on, and a type
  // name is re-resolved for every property leaf that names it). Both caches are
  // pure query-scoped derivations of the index; nothing here writes to the
  // store, so --no-write-back (a read-only store handle) is unaffected.
  ChainCache: TDictionary<Int64 , TArray<TSymbol>>; // class id -> its resolved chain
  TypeCache : TDictionary<string, TSymbol        >; // 'lowername|scopefileid' -> resolved class

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

  // THE scope-aware name -> class step. One definition, three callers: the
  // ancestor climb bridging an unresolved heritage entry (ClassChain), the
  // bare-property-type bridge (ResolveViaBridgedAncestry), and Walk's
  // property-type classification.
  //
  // Delegates to ISymbolStore.ResolveTypeNameToClass, which applies the SHARED
  // scope rule (PickAncestorCandidateByScope: same unit -> unique uses hit ->
  // unique leading dotted-namespace segment -> decline) and chases type
  // ALIASES; the result is then reduced to the defining body via BodyOf, so a
  // forward-declaration stub never reaches a caller (a stub has no property
  // children -- the DevExpress forward-decl case).
  //
  // AScopeFileId must be the FileId of the class doing the referencing AT THIS
  // HOP -- the class that inherits the name, or the class that DECLARES the
  // property whose type this is -- never the FileId of the class the query was
  // rooted at (design criterion 7).
  //
  // Memoized per (name, scope) for the lifetime of ONE query. The cache is a
  // pure derivation of the index and performs no writes, so a --no-write-back
  // (read-only) store is unaffected.
  //
  // Id = 0 means the scope rule DECLINED, which is a correct outcome and never
  // a reason to retry the name with a scope-unaware lookup.
  function ResolveTypeInScope(const AName: string; AScopeFileId: Int64): TSymbol;
  var
    Key: string;
  begin
    Key:= LowerCase(AName) + '|' + IntToStr(AScopeFileId);
    if TypeCache.TryGetValue(Key, Result) then Exit;
    Result:= BodyOf(AStore.ResolveTypeNameToClass(AName, AScopeFileId));
    TypeCache.AddOrSetValue(Key, Result);
  end;

  // Ordered list of the class + its ancestor classes (most-derived first).
  // Stops climbing at TPersistent/TObject when AOpts.ToPersistent.
  //
  // TWO sources feed the chain:
  //  (a) the ancestor edges the INDEXER already resolved -- read in one shot
  //      via GetTransitiveAncestors, exactly as before this change;
  //  (b) QUERY-TIME FALLBACK (design 2026-07-29-proptree-ancestor-scope,
  //      section 3.1, criteria 6-7). ResolveAncestry writes an UNRESOLVED row
  //      (ancestor_kind='?', ancestor_symbol_id=NULL) whenever it cannot
  //      disambiguate a same-named ancestor -- "when unsure, don't claim". This
  //      function used to SKIP those rows, so the climb stopped dead at the
  //      first one and EVERY inherited property above it vanished (the measured
  //      symptom: Vcl.StdCtrls.TEdit and cxButtons.TcxButton expose no Name /
  //      Tag / Left / Top). Each such row is now BRIDGED to its defining class
  //      by AStore.ResolveTypeNameToClass, which applies the SAME shared scope
  //      rule (PickAncestorCandidateByScope: same unit -> unique uses hit ->
  //      unique first-dotted-namespace-segment -> decline) but matches unit
  //      names TEXTUALLY, so -- unlike the index-time resolver -- it does NOT
  //      need unit_uses.target_file_id and therefore repairs indexes that are
  //      ALREADY ON DISK, with no re-index. A decline (Id=0) stays a decline:
  //      the chain simply stops there, exactly as it does today. Nothing here
  //      writes, so a --no-write-back (read-only) store is unaffected.
  //
  // SCOPE, per criterion 7: an unresolved row surfaced by
  // GetTransitiveAncestors' BFS may have been declared by ANY class in the
  // closure, not by the class the walk started from. The name is therefore
  // resolved in the unit of the class whose OWN heritage actually lists it --
  // ScopeSymbolFor over the most-derived-first Known list, which also documents
  // precisely what its last resort falls back to.
  //
  // GUARDS, in the order they apply to an unresolved row:
  //  * IsIndistinguishableFromClassRef -- refuse to bridge FROM a declaration
  //    the index cannot tell apart from a 'class of X' class reference;
  //  * Kind = skClass -- an ancestor that resolves to an INTERFACE symbol is
  //    never placed in the class chain. (This rejects interface SYMBOLS; it
  //    does not detect a same-named CLASS standing in for what was written as
  //    an interface heritage entry.)
  //  * CrossesGuiFramework -- criterion 5, enforced here rather than delegated,
  //    because the shared scope rule is skipped entirely for a single-candidate
  //    name (Vcl-vs-FMX only: a Vcl.* class reaching a System.* ancestor is
  //    legitimate and still bridges);
  //  * a visited-class-id set (each class is placed, and climbed FROM, at most
  //    once, so a self-referential or cyclic index terminates instead of
  //    spinning) plus a CMaxBridgedChainDepth cap on bridged recursion.
  function ClassChain(const ARoot: TSymbol): TArray<TSymbol>;
  var
    List   : TList<TSymbol>             ;
    SeenIds: TDictionary<Int64, Boolean>;

    // Place ASym in the chain unless it is not a class or is already there.
    // Doubles as the cycle guard: False also means "do not climb from it".
    function TryAdd(const ASym: TSymbol): Boolean;
    begin
      Result:= (ASym.Id > 0) and (ASym.Kind = skClass) and not SeenIds.ContainsKey(ASym.Id);
      if not Result then Exit;
      SeenIds.Add(ASym.Id, True);
      List.Add(ASym);
    end;

    procedure ClimbFrom(const AFrom: TSymbol; ADepthLeft: Integer);
    var
      Anc  : TArray<TTypeAncestor>;
      A    : TTypeAncestor        ;
      Known: TList<TSymbol>       ; // AFrom + the resolved classes of its closure
      Sym  : TSymbol              ;
      Brid : TSymbol              ;
      Decl : TSymbol              ; // the class whose OWN heritage lists A.Name
    begin
      if (AFrom.Id <= 0) or (ADepthLeft <= 0) then Exit;
      Known:= TList<TSymbol>.Create;
      try
        Known.Add(AFrom);
        Anc:= AStore.GetTransitiveAncestors(AFrom.Id);
        for A in Anc do
        begin
          // When ToPersistent is on, do not enumerate the props of TPersistent /
          // TObject themselves (and everything above is unreachable anyway).
          if AOpts.ToPersistent and IsStopClass(A.Name) then Break;
          if A.Resolved and (A.SymbolId > 0) and (A.Kind = 'class') then
          begin
            Sym:= BodyOf(AStore.GetSymbolById(A.SymbolId));
            if (Sym.Id > 0) and (Sym.Kind = skClass) then
            begin
              Known.Add(Sym); // a later unresolved row may be ITS heritage entry
              TryAdd(Sym);
            end;
          end
          else if not A.Resolved then
          begin
            // Resolve in the scope of the class that actually inherits this
            // name (criterion 7); AFrom itself only as a last resort -- see
            // ScopeSymbolFor for exactly what that last resort does.
            Decl:= ScopeSymbolFor(Known, AFrom, A.Name);
            // Never bridge FROM something the index cannot tell apart from a
            // 'class of X' class reference -- it has no instance surface to
            // inherit. See IsIndistinguishableFromClassRef.
            if IsIndistinguishableFromClassRef(Decl) then Continue;
            // Bridge the unresolved ancestor NAME to its defining class in that
            // class's unit scope (memoized -- the same broken edge is re-visited
            // by every descendant walked in one query).
            Brid:= ResolveTypeInScope(A.Name, Decl.FileId);
            if (Brid.Id <= 0) or (Brid.Kind <> skClass) then Continue;
            // Criterion 5, enforced HERE and not left to the scope rule: that
            // rule is skipped entirely when the name has a single candidate.
            // Vcl-vs-FMX ONLY -- a Vcl.* class reaching a System.* ancestor
            // through an alias is legitimate and must still bridge. See
            // CrossesGuiFramework.
            if CrossesGuiFramework(Decl, Brid) then Continue;
            if not (AOpts.ToPersistent and IsStopClass(Brid.Name)) and TryAdd(Brid) then
              ClimbFrom(Brid, ADepthLeft - 1); // the bridged class's own chain
          end;
        end;
      finally
        Known.Free;
      end;
    end;

  begin
    if (ARoot.Id > 0) and ChainCache.TryGetValue(ARoot.Id, Result) then Exit;
    List   := TList<TSymbol>.Create;
    SeenIds:= TDictionary<Int64, Boolean>.Create;
    try
      List.Add(ARoot);
      if ARoot.Id > 0 then SeenIds.Add(ARoot.Id, True);
      ClimbFrom(ARoot, CMaxBridgedChainDepth);
      Result:= List.ToArray;
      if ARoot.Id > 0 then ChainCache.AddOrSetValue(ARoot.Id, Result);
    finally
      SeenIds.Free;
      List.Free;
    end;
  end;

  // Resolve an empty-signature (redeclared) property's type by finding the
  // same-named property that DOES carry a signature in an ancestor class.
  // CLASS-ONLY (R3, Task 3): the ancestor closure returned by
  // GetTransitiveAncestors is unfiltered -- it also contains any INTERFACE
  // ancestors a class implements, in BFS (nearest-first) order alongside the
  // real class ancestors. An implemented interface can independently declare
  // a same-named property (Delphi interfaces support `property X: T read
  // GetX;`) with a COMPLETELY UNRELATED type. Without the (A.Kind = 'class')
  // guard, such an interface property can be found and returned BEFORE the
  // walk reaches the queried class's real base -- a wrong-CLASS type leaking
  // in from outside the class hierarchy entirely (worse than the covariance
  // "collapse to base" case: this is collapse to an unrelated type). Mirrors
  // ClassChain's own (A.Kind = 'class') filter, which is why CollectProps'
  // shadowing/DeclaredIn never suffers this -- only this ancestor-only-typed
  // fallback walk did.
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
      if not (A.Resolved and (A.SymbolId > 0) and (A.Kind = 'class')) then Continue;
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

  // Resolve an empty-modifiers property's EFFECTIVE visibility by finding the
  // same-named property that DOES carry a non-empty Modifiers in an ancestor
  // class. Mirrors ResolveInheritedType exactly, but over Modifiers instead of
  // Signature. Defensive: the current parser always stamps a non-empty
  // Modifiers (VisibilityOfSection defaults to 'public'), so this path is not
  // reachable via today's indexer output -- kept so a future/foreign producer
  // of blank Modifiers rows still resolves a visibility instead of the row
  // being dropped from a --min-visibility filter.
  function ResolveInheritedVisibility(const AClass: TSymbol; const APropName: string): string;
  var
    Anc   : TArray<TTypeAncestor>;
    A     : TTypeAncestor        ;
    AncSym: TSymbol              ;
    Child : TSymbol              ;
    Vis   : string               ;
  begin
    Result:= '';
    Anc:= AStore.GetTransitiveAncestors(AClass.Id);
    for A in Anc do
    begin
      if not (A.Resolved and (A.SymbolId > 0)) then Continue;
      AncSym:= BodyOf(AStore.GetSymbolById(A.SymbolId));
      if AncSym.Id <= 0 then Continue;
      Child:= AStore.FindChildSymbolByName(AncSym.Id, APropName);
      if (Child.Id > 0) and (Child.Kind = skProperty) then
      begin
        Vis:= Trim(Child.Modifiers);
        if Vis <> '' then Exit(Vis);
      end;
    end;
  end;

  // R1 (Task 6): resolve a property's EFFECTIVE read/write accessor shape
  // (prop_access) for the case where its OWN declaration carries NO accessor
  // clause -- a bare 'property Color;' redeclaration whose stored prop_access is
  // '' (NULL). Finds the same-named property that DOES carry a non-empty
  // prop_access in the nearest ancestor. Mirrors ResolveInheritedType EXACTLY
  // (same class-only ancestor walk, nearest-first) but over PropAccess instead
  // of Signature -- so a bare redeclaration inherits the ancestor's ro/rw/wo.
  // CLASS-ONLY (R3, Task 3): the (A.Kind = 'class') guard excludes any
  // implemented INTERFACE that independently redeclares a same-named property
  // (Delphi interfaces support `property X: T read GetX;`) with an UNRELATED
  // accessor shape from interposing before the real class base -- identical to
  // the interface-filter rationale documented on ResolveInheritedType. Returns
  // '' when nothing up-tree carries an accessor clause either (the caller then
  // treats '' as writable -- the back-compat default).
  function ResolveInheritedPropAccess(const AClass: TSymbol; const APropName: string): string;
  var
    Anc   : TArray<TTypeAncestor>;
    A     : TTypeAncestor        ;
    AncSym: TSymbol              ;
    Child : TSymbol              ;
    PA    : string               ;
  begin
    Result:= '';
    Anc:= AStore.GetTransitiveAncestors(AClass.Id);
    for A in Anc do
    begin
      if not (A.Resolved and (A.SymbolId > 0) and (A.Kind = 'class')) then Continue;
      AncSym:= BodyOf(AStore.GetSymbolById(A.SymbolId));
      if AncSym.Id <= 0 then Continue;
      Child:= AStore.FindChildSymbolByName(AncSym.Id, APropName);
      if (Child.Id > 0) and (Child.Kind = skProperty) then
      begin
        PA:= Trim(Child.PropAccess);
        if PA <> '' then Exit(PA);
      end;
    end;
  end;

  // R4 (Task 4): a class CONST's (skConstDecl) effective visibility, for the
  // (common) case where its OWN Modifiers is blank. INVESTIGATED empirically
  // (indexed a throwaway fixture, inspected the `symbols` rows directly): the
  // parser's 'declConst' branch (DRagLint.Parser.Delphi13.pas, inside the
  // recursive Walk dispatcher, ~line 1238) calls Emit WITHOUT the
  // ASignature/AModifiers arguments at all -- unlike the 'declField'/
  // 'declProp' branches, which both pass AState.CurrentVisibility -- so a
  // class const's Modifiers column is '' UNCONDITIONALLY, regardless
  // of which visibility section it was actually declared under. Fixing the
  // parser is out of scope here (Task 4 is PropTree.pas-only, no re-index),
  // so the effective visibility is instead recovered from data already IN the
  // index: Delphi visibility sections are purely textual/linear -- every
  // member between one visibility keyword and the next shares that keyword's
  // Modifiers -- so the nearest PRECEDING sibling (by StartLine, among ALL
  // child kinds; fields/properties/methods all DO carry accurate Modifiers)
  // shares the const's real section. Falls back to 'public' -- Delphi's own
  // default for an unspecified/first class section -- only when no earlier
  // sibling carries any visibility info at all (the const is the class's
  // very first member). This is a best-effort reconstruction from real
  // sibling data, not a blind guess; it is NOT expected to be 100% correct on
  // every real corpus (e.g. a const that is the sole member of its own
  // section, preceded only by an EARLIER section's members, could inherit
  // the wrong section) -- documented as a known limitation.
  function ResolveConstVisibilityByProximity(const AClass: TSymbol; const AConst: TSymbol): string;
  var
    Kids     : TArray<TSymbol>;
    Kid      : TSymbol        ;
    Best     : TSymbol        ;
    HaveBest : Boolean        ;
  begin
    HaveBest:= False;
    Best    := Default(TSymbol);
    Kids    := AStore.FindAllChildSymbols(AClass.Id);
    for Kid in Kids do
    begin
      if Kid.Id = AConst.Id then Continue;
      if Trim(Kid.Modifiers) = '' then Continue;         // no visibility signal on this sibling
      if Kid.StartLine > AConst.StartLine then Continue; // must precede the const textually
      if (not HaveBest) or (Kid.StartLine > Best.StartLine) or
         ((Kid.StartLine = Best.StartLine) and (Kid.StartCol > Best.StartCol)) then
      begin
        Best    := Kid;
        HaveBest:= True;
      end;
    end;
    if HaveBest then Result:= Trim(Best.Modifiers)
    else Result:= 'public'; // no earlier sibling at all -- Delphi's own implicit-section default
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
  // (scope = the unit of the class that actually INHERITS that name at that hop,
  // whose uses-clause / namespace prefix disambiguates e.g. Vcl from FMX -- see
  // Climb's rule below), and returns the first KNOWN type declared for APropName
  // above the break. '' when the walk still finds nothing (never fabricates a type).
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
      Anc  : TArray<TTypeAncestor>;
      A    : TTypeAncestor        ;
      Nxt  : TSymbol              ;
      Tok  : string               ;
      Key  : string               ;
      Known: TList<TSymbol>       ; // ASym + the resolved classes of its closure
      Sym  : TSymbol              ;
      Decl : TSymbol              ; // the class whose OWN heritage lists A.Name
    begin
      Result:= '';
      Anc:= AStore.GetTransitiveAncestors(ASym.Id);
      Known:= TList<TSymbol>.Create;
      try
        Known.Add(ASym);
        // (a) any already-RESOLVED CLASS ancestor that declares the property with
        // a type. CLASS-ONLY (R3, Task 3, mirrors ResolveInheritedType's guard
        // above): an implemented interface can appear in this same closure and
        // independently redeclare a same-named property with an unrelated type --
        // excluded so the bridge never resolves to a wrong-class type either.
        for A in Anc do
          if A.Resolved and (A.SymbolId > 0) and (A.Kind = 'class') then
          begin
            Sym:= BodyOf(AStore.GetSymbolById(A.SymbolId));
            // Same admission test ClimbFrom applies, so both Known lists hold
            // real classes only and a zero-Id BodyOf result can never become a
            // scope candidate.
            if (Sym.Id > 0) and (Sym.Kind = skClass) then
              Known.Add(Sym); // a later unresolved row may be ITS heritage entry
            Tok:= PropTypeOn(Sym);
            if Tok <> '' then Exit(Tok);
          end;
        // (b) bridge each UNRESOLVED ancestor name, then keep climbing from it.
        // SCOPE (design criterion 7): resolve the name in the unit of the class
        // that actually INHERITS it -- found by matching the name against each
        // known class's own heritage, most-derived first -- falling back to the
        // class this hop is climbing FROM. It used to pass AClass.FileId, the
        // file of the ROOT class the whole query started from, at every hop;
        // that contradicts ResolveTypeNameToClass's AScopeFileId contract and
        // silently mis-scopes any break that occurs above a unit boundary.
        for A in Anc do
        begin
          if A.Resolved then Continue;
          Key:= LowerCase(A.Name);
          if (Key = '') or Visited.ContainsKey(Key) then Continue;
          Visited.Add(Key, True);
          Decl:= ScopeSymbolFor(Known, ASym, A.Name);
          Nxt := ResolveTypeInScope(A.Name, Decl.FileId);
          if Nxt.Id <= 0 then Continue;
          // Criterion 5, enforced HERE as well as in ClassChain.ClimbFrom: this
          // walk reaches the very same single-candidate PickCandidate
          // short-circuit, so without the guard a bare-redeclared property on a
          // Vcl.* class could take its TYPE from a lone FMX-declared homonym
          // with no scope check having run at all. Vcl-vs-FMX ONLY; see
          // CrossesGuiFramework.
          if CrossesGuiFramework(Decl, Nxt) then Continue;
          Tok:= PropTypeOn(Nxt);   // declared directly on the bridged class?
          if Tok <> '' then Exit(Tok);
          Tok:= Climb(Nxt);        // else climb the bridged class's own chain
          if Tok <> '' then Exit(Tok);
        end;
      finally
        Known.Free;
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
  //
  // ADeclaredBy hands back that class as a SYMBOL, not merely its qualified
  // name: the caller needs its FileId to resolve the property's TYPE in the
  // right unit scope (criterion 7, one layer below the ancestor climb -- a
  // property inherited from Vcl.Controls.TControl must have its type resolved
  // in Vcl.Controls, not in whatever unit the queried root happens to live in),
  // and its QualifiedName for the cross-namespace refusal. Both come from the
  // one symbol, so the two can never disagree about which class is meant.
  procedure CollectProps(const AClass: TSymbol;
    out AOrder: TArray<TSymbol>; out ADeclaredBy: TArray<TSymbol>);
  var
    Chain: TArray<TSymbol> ;
    Cls  : TSymbol         ;
    Kids : TArray<TSymbol> ;
    Kid  : TSymbol         ;
    Seen : TDictionary<string, Boolean>;
    OL   : TList<TSymbol>  ;
    DL   : TList<TSymbol>  ;
    Key  : string          ;
  begin
    Seen:= TDictionary<string, Boolean>.Create;
    OL  := TList<TSymbol>.Create;
    DL  := TList<TSymbol>.Create;
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
          DL.Add(Cls);
        end;
      end;
      AOrder     := OL.ToArray;
      ADeclaredBy:= DL.ToArray;
    finally
      Seen.Free;
      OL.Free;
      DL.Free;
    end;
  end;

  // R4 (Task 4): the distinct FIELD/CONST leaves visible on AClass (own +
  // inherited), each paired with the most-derived class that declares it.
  // Dedupe by leaf name. Mirrors CollectProps exactly (same ClassChain,
  // most-derived-first shadowing) but filters skField/skConstDecl instead of
  // skProperty, and is kept as a SEPARATE walk with its OWN Seen set --
  // deliberately NOT folded into CollectProps -- so the property engine's
  // already class-accurate (Task 3) behavior is never disturbed by this
  // addition. skConstDecl (a class-scoped `const X: T = v;`) is included
  // alongside skField because a typed class const is a required PAS-surface
  // leaf too (read-only; see Walk's field loop).
  procedure CollectFields(const AClass: TSymbol;
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
          if not (Kid.Kind in [skField, skConstDecl]) then Continue;
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

  // True when ASym is (or descends from) TComponent -- a REFERENCE type, not an
  // owned sub-object. Name-based over the ancestor closure (no RTTI), same
  // pragmatic style as IsStopClass. Used to leave referenced components unexpanded.
  function IsComponentType(const ASym: TSymbol): Boolean;
  var A: TTypeAncestor;
  begin
    Result := SameText(ASym.Name, 'TComponent');
    if Result then Exit;
    for A in AStore.GetTransitiveAncestors(ASym.Id) do
      if SameText(A.Name, 'TComponent') then Exit(True);
  end;

  // Recursive walk. APrefix is the dotted path down to (and including a trailing
  // '.') the current class; AVisited holds lowercased TYPE names already expanded
  // on this path (cycle guard). ADepthLeft is the remaining class-recursion budget.
  procedure Walk(const AClass: TSymbol; const APrefix: string;
    ADepthLeft: Integer; AVisited: TDictionary<string, Boolean>);
  var
    Order      : TArray<TSymbol>;
    DeclaredBy : TArray<TSymbol>; // the class declaring Order[i] -- its scope
    idx        : Integer        ;
    Prop       : TSymbol        ;
    Node       : TPropNode      ;
    Tok        : string         ;
    OwnTok     : string         ;
    TypeSym    : TSymbol        ;
    LowType    : string         ;
    ClosureIds : TArray<Int64>  ;
    ClosureDone: Boolean        ;
    // R4 (Task 4): field/const leaves -- separate variable set, mirrors the
    // property loop's shape but is a flat (non-recursive) emission.
    FieldOrder     : TArray<TSymbol>;
    FieldDeclaredIn: TArray<string> ;
    FIdx           : Integer        ;
    Fld            : TSymbol        ;
    FNode          : TPropNode      ;
    FVis           : string         ;
    FTok           : string         ;
    FTypeSym       : TSymbol        ;
  begin
    ClosureDone:= False;
    CollectProps(AClass, Order, DeclaredBy);
    for idx:= 0 to High(Order) do
    begin
      Prop:= Order[idx];
      Node:= Default(TPropNode);
      Node.Path      := APrefix + Prop.Name;
      Node.DeclaredIn:= DeclaredBy[idx].QualifiedName;

      // proptree/2 (Task 2, R2): EFFECTIVE visibility -- the most-derived
      // declaration's own Modifiers (Prop is already the most-derived symbol
      // per CollectProps' shadowing), so a published redeclaration of a
      // protected/public ancestor property RAISES the effective visibility to
      // published without any extra logic. Only when the own Modifiers is
      // empty (defensive; not reachable via the current parser) do we fall
      // back to the ancestor walk instead of leaving it blank.
      Node.Visibility:= Trim(Prop.Modifiers);
      if Node.Visibility = '' then
        Node.Visibility:= ResolveInheritedVisibility(AClass, Prop.Name);

      // Normalize at the single point where the effective value is finalized
      // (covers BOTH the own-declaration and the ancestor-walk paths above):
      // the parser's Modifiers carries a 'strict ' prefix for 'strict private'/
      // 'strict protected' sections (unit-scoped access, Delphi's `strict`
      // keyword), but the documented proptree/2 consumer contract is the
      // 5-value domain 'published'|'public'|'protected'|'private'|''. The
      // strict/non-strict distinction is same-unit-only and irrelevant to
      // cross-unit assignability (what proptree exists to answer), so
      // collapsing it is semantically lossless.
      if Node.Visibility = 'strict private'   then Node.Visibility:= 'private'
      else if Node.Visibility = 'strict protected' then Node.Visibility:= 'protected';

      // R1 (Task 6): REAL property writability from the resolved read/write
      // accessor shape (prop_access). Prop is already the most-derived
      // declaration (CollectProps shadowing), so Prop.PropAccess is its OWN
      // accessor clause; when empty (a bare 'property Color;' redeclaration)
      // resolve it up-tree from the nearest CLASS ancestor with a non-empty
      // clause -- MIRRORS the Signature/type resolution above (own decl else
      // nearest class ancestor, interface-filtered). is_writable is then
      // (resolved <> 'ro'): 'rw'/'wo' -> writable, 'ro' -> not. An empty
      // resolved value (no accessor clause anywhere up-tree, or a pre-v17 /
      // un-re-indexed DB whose prop_access is NULL) defaults TRUE -- today's
      // back-compat behaviour. 'wo' (write-only) is writable: a valid assignment
      // TARGET (the editor handles source-vs-target direction separately).
      var PropAcc: string:= Trim(Prop.PropAccess);
      if PropAcc = '' then PropAcc:= ResolveInheritedPropAccess(AClass, Prop.Name);
      Node.IsWritable:= (PropAcc = '') or (PropAcc <> 'ro');
      Node.MemberKind:= 'property';

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

      // Classify: resolve the type name IN THE UNIT SCOPE OF THE CLASS THAT
      // DECLARES THIS PROPERTY -- criterion 7 one layer below the ancestor
      // climb. This used to be AStore.FindSymbolByExactNameAnywhere(Tok), which
      // takes whichever same-named symbol the index yields first and so gave
      // Vcl.Controls.TControl.Parent (declared ': TWinControl') the type
      // FMX.Controls.Win.TWinControl, then recursed into it -- a Vcl class
      // reporting an FMX property surface. ResolveTypeInScope applies the shared
      // scope rule against the DECLARING class's unit and reduces a forward-decl
      // stub to its body, so a nested class still never enumerates 0 properties
      // (the DevExpress forward-decl case the old stub re-resolution existed for).
      TypeSym:= ResolveTypeInScope(Tok, DeclaredBy[idx].FileId);
      // Criterion 5, enforced HERE for the same reason the ancestor climb
      // enforces it rather than delegating: PickCandidate short-circuits on a
      // lone candidate, so the scope rule never runs for a type name with
      // exactly one -- possibly wrong-framework -- definition. Vcl-vs-FMX ONLY:
      // a VCL class's 'System.*'-typed property (TBasicAction, TList,
      // TComponent, ...) is an ordinary RTL reference and must still expand.
      // See CrossesGuiFramework (and note its guarantee is PER HOP: an undotted
      // declaring unit is not a GUI framework and is never refused).
      if (TypeSym.Id > 0) and CrossesGuiFramework(DeclaredBy[idx], TypeSym) then
        TypeSym:= Default(TSymbol);
      // A DECLINE (Id = 0) leaves the leaf exactly where an unresolvable type
      // leaves it today -- Kind='scalar', not recursed into, TypeName still the
      // token as written. It is never retried with a scope-unaware lookup: a
      // fuller tree bought by a wrong type is a defect, not a feature.
      if (TypeSym.Id > 0) and (TypeSym.Kind = skClass) then
      begin
        // A referenced TComponent (PopupMenu, Action, a nested control) is NOT an
        // owned sub-object. With TreatRefsAsLeaves it is a REFERENCE LEAF -- emitted
        // but not recursed into -- so the tree is not flooded by TComponent's whole
        // surface (.Components/.Owner/.Observers/...). Owned TPersistent sub-objects
        // (TFont, ...) are unaffected and still expand.
        if AOpts.TreatRefsAsLeaves and IsComponentType(TypeSym) then
        begin
          Node.Kind        := 'class';
          Node.IsClassTyped:= False;   // a reference; not recursed into
          Nodes.Add(Node);
          Continue;
        end;

        Node.Kind        := 'class';
        Node.IsClassTyped:= True;
        Nodes.Add(Node);

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

    // R4 (Task 4): own field/const leaves for THIS class, at the SAME prefix
    // depth. Flat leaves only -- unlike class-typed PROPERTIES, a class-typed
    // FIELD is never recursed into (out of scope for this task; the field
    // itself is the assignment target).
    CollectFields(AClass, FieldOrder, FieldDeclaredIn);
    for FIdx:= 0 to High(FieldOrder) do
    begin
      Fld  := FieldOrder[FIdx];
      FNode:= Default(TPropNode);
      FNode.Path      := APrefix + Fld.Name;
      FNode.DeclaredIn:= FieldDeclaredIn[FIdx];
      FNode.MemberKind:= 'field';

      // Effective visibility. A plain field's Modifiers is always populated
      // by the parser (declField stamps AState.CurrentVisibility, same as
      // declProp) -- read directly. A class CONST's Modifiers is NEVER
      // populated (verified empirically -- see ResolveConstVisibilityByProximity's
      // comment) -- recovered from the nearest visibility-bearing sibling.
      FVis:= Trim(Fld.Modifiers);
      if (FVis = '') and (Fld.Kind = skConstDecl) then
        FVis:= ResolveConstVisibilityByProximity(AClass, Fld);
      if FVis = 'strict private'        then FVis:= 'private'
      else if FVis = 'strict protected' then FVis:= 'protected';
      FNode.Visibility:= FVis;

      // Field-scoped writability (Task 4) -- independent of, and does not
      // touch, the staged property IsWritable path above. A plain field is
      // writable; a class CONST is a compile-time constant (typed or not) --
      // never assignable.
      FNode.IsWritable:= Fld.Kind <> skConstDecl;

      FTok:= ParseTypeToken(Fld.Signature);
      if FTok = '' then
      begin
        FNode.TypeName    := 'unknown';
        FNode.Kind        := 'unknown';
        FNode.IsClassTyped:= False;
      end
      else
      begin
        FNode.TypeName:= FTok;
        // DELIBERATELY still the scope-unaware lookup, unlike the property loop
        // above. A field leaf is FLAT -- never recursed into -- so the resolved
        // symbol is not stored, not climbed, and cannot splice another
        // framework's surface into the tree; its only observable effect is the
        // 'class' vs 'scalar' label, and "is there a class of this name" is a
        // question no scope changes the answer to in practice. Routing it
        // through the scope rule would only let a DECLINE downgrade a genuinely
        // class-typed field to 'scalar' -- losing information to buy no
        // correctness. Revisit if/when field leaves ever recurse.
        FTypeSym:= AStore.FindSymbolByExactNameAnywhere(FTok);
        if (FTypeSym.Id > 0) and (FTypeSym.Kind = skClass) then
        begin
          FNode.Kind        := 'class';
          FNode.IsClassTyped:= True; // NOT recursed into -- flat leaf (R4 scope)
        end
        else
        begin
          FNode.Kind        := 'scalar';
          FNode.IsClassTyped:= False;
        end;
      end;
      Nodes.Add(FNode);
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

  Nodes     := TList<TPropNode>.Create;
  Visited   := TDictionary<string, Boolean>.Create;
  ChainCache:= TDictionary<Int64 , TArray<TSymbol>>.Create;
  TypeCache := TDictionary<string, TSymbol        >.Create;
  Truncated := False;
  try
    Result.RootType:= Root.Name;
    Visited.Add(LowerCase(Root.Name), True); // guard against direct self-reference
    Walk(Root, '', AOpts.Depth, Visited);
    Result.Nodes    := Nodes.ToArray;
    Result.Truncated:= Truncated;
  finally
    TypeCache .Free;
    ChainCache.Free;
    Nodes     .Free;
    Visited   .Free;
  end;
end;

end.
