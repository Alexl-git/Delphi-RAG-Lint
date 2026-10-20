unit DRagLint.Report.CycleEdge;  // dl:ok unit-too-large@9f6f -- the edge surface and the two recipes read from it (R1, R2) share this unit's private helpers (BareCode, LineOf, MakeRefusal, UnitQualifiedLine); the E18 plan places both recipes here

// ---------------------------------------------------------------------------
// E18 Task 4 -- the SURFACE of one unit edge A -> B of a circular group: what
// A actually does with B, read from index facts only (refs, member_accesses,
// symbols). The `cycles --fix` rewrites (R1 routine-call inversion, R2 member
// hand-over through an extracted interface) decide from this record whether an
// edge has their shape; `cycles --format json --causes` prints it per edge.
//
// Index facts this unit relies on (demo DB, 2026-10-19): an `is` / `as`
// operand, a cast and a var declaration are all refs.kind 'type_use' -- told
// apart by the line text (ClassifyTypeUse); a construction / class-method call
// is a 'read' of the class name plus a 'call' whose receiver_text is the class
// name; member reads and writes are member_accesses rows; class refs carry no
// symbol_id and are bound by NAME against the units the citing unit uses.
//
// F2047 ruling: this unit's interface must not use DRagLint.Report.CyclePlan
// (CyclePlan uses this unit). The planner hands its index access in through
// IEdgeSurfaceSource instead.
// ---------------------------------------------------------------------------

interface

uses
  System.JSON,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>What one reference on an edge A -&gt; B does with unit B.</summary>
  /// <remarks>erTypeIs / erTypeAs / erTypeCast / erTypeDecl split refs.kind
  /// 'type_use' by the line text; erClassReceiver is a call through a class of B
  /// (`TFoo.Create`, `TFoo.CreateForFolder`); erMemberRead is a member of a type of
  /// B read through an instance; erMemberWrite is any write to a variable or member
  /// of B; erOther is everything else bound to B (a plain read, a class name passed
  /// as a value).</remarks>
  TEdgeRefKind = (erCall, erTypeIs, erTypeAs, erTypeCast, erTypeDecl, erClassReceiver,
                  erMemberRead, erMemberWrite, erOther);

  /// <summary>One reference of unit A that binds to unit B.</summary>
  TEdgeRef = record
    /// <summary>1-based line in A.</summary>
    Line: Integer;
    /// <summary>What the reference does.</summary>
    Kind: TEdgeRefKind;
    /// <summary>The name as the ref records it (refs.name_text).</summary>
    Name: string;
    /// <summary>Name of the routine whose body holds the ref; '' outside a body.</summary>
    Enclosing: string;
    /// <summary>The trimmed source line.</summary>
    LineText: string;
    /// <summary>Id of the symbol of B the ref binds to (the member for a member
    /// access, the top-level declaration otherwise).</summary>
    SymbolId: Int64;
    /// <summary>refs.enclosing_symbol_id: the routine whose body holds the ref; 0 outside a body.</summary>
    EnclosingId: Int64;
  end;

  /// <summary>One type a routine signature names.</summary>
  TSigType = record
    /// <summary>The identifier as written in the signature (a dotted name keeps its unit prefix).</summary>
    Name: string;
    /// <summary>Lower-case stem of the unit that declares it; '' when no index row resolves it.</summary>
    DeclStem: string;
    /// <summary>True when DeclStem is a unit of the circular group.</summary>
    InScc: Boolean;
  end;

  /// <summary>Everything unit FromStem takes from unit ToStem, as index facts.</summary>
  TEdgeSurface = record
    /// <summary>Lower-case stem of the citing unit A.</summary>
    FromStem: string;
    /// <summary>Lower-case stem of the used unit B.</summary>
    ToStem: string;
    /// <summary>Every reference of A bound to B, in index order.</summary>
    Refs: TArray<TEdgeRef>;
    /// <summary>Distinct classes of B that A references, sorted.</summary>
    ClassNames: TArray<string>;
    /// <summary>Distinct members of B's types that A READS (member_accesses mode
    /// 'read'), sorted.</summary>
    Members: TArray<string>;
    /// <summary>A writes a variable or member of B.</summary>
    HasWrite: Boolean;
    /// <summary>A calls a constructor through a class of B.</summary>
    HasConstruction: Boolean;
    /// <summary>A calls a non-constructor method through a class of B.</summary>
    HasClassMethod: Boolean;
    /// <summary>A passes a class of B as a value (a read of the class name with no
    /// call or member access through it on that line -- the `FindMDIChildForFolder(TfrmX, ...)`
    /// shape; `TfrmX.ClassName` is a class-method call, HasClassMethod).</summary>
    HasClassRefArg: Boolean;
    /// <summary>A declares something of a type of B (`X: TFoo`).</summary>
    HasDecl: Boolean;
    /// <summary>Set when the edge binds exactly ONE declaration of B and it is a
    /// routine: its name; '' otherwise.</summary>
    RoutineName: string;
    /// <summary>That routine's verbatim symbols.signature; '' otherwise.</summary>
    RoutineSig: string;
    /// <summary>The types RoutineSig names (see SignatureTypes); empty otherwise.</summary>
    SigTypes: TArray<TSigType>;
    /// <summary>Number of call refs of A bound to B.</summary>
    CallCount: Integer;
  end;

  /// <summary>The index access BuildEdgeSurface needs from the cycle planner.</summary>
  /// <remarks>Implemented by the planner of DRagLint.Report.CyclePlan, which keeps
  /// its own lifetime (not reference counted). All stems are lower-case unit stems.</remarks>
  IEdgeSurfaceSource = interface
    ['{006CBD32-42DF-4902-BDF8-4DCA48B4C968}']
    /// <summary>The open index.</summary>
    /// <returns>The store; never nil.</returns>
    function Store: ISymbolStore;
    /// <summary>The source lines of an indexed file.</summary>
    /// <param name="pFid">File id.</param>
    /// <returns>The lines, empty when the file is gone.</returns>
    function FileLines(pFid: Int64): TArray<string>;
    /// <summary>File id of a unit stem.</summary>
    /// <param name="pStem">Lower-case unit stem.</param>
    /// <returns>The id, or 0 when no indexed file has that stem.</returns>
    function FidOfStem(const pStem: string): Int64;
    /// <summary>Binds a bare name the way Delphi does at one line of a file: its
    /// own declaration first, else the LAST visible used unit that exports it.</summary>
    /// <param name="pFid">The citing file.</param>
    /// <param name="pLine">The line of the reference (selects the visible uses section).</param>
    /// <param name="pName">The identifier.</param>
    /// <param name="pOwner">Receives the top-level declaration it binds to.</param>
    /// <param name="pStem">Receives the stem of the declaring unit.</param>
    /// <returns>False when no visible declaration has that name.</returns>
    function BindName(pFid: Int64; pLine: Integer; const pName: string; out pOwner: TSymbol;
      out pStem: string): Boolean;
    /// <summary>Whether a stem is a unit of the circular group being planned.</summary>
    /// <param name="pStem">Lower-case unit stem.</param>
    /// <returns>True for a member of the group.</returns>
    function IsSccStem(const pStem: string): Boolean;
    /// <summary>The member_accesses row of a reference.</summary>
    /// <param name="pRefId">refs.id.</param>
    /// <param name="pAccess">Receives the row (TargetSymbolId = the member, MemberMode).</param>
    /// <returns>False when the ref has no member_accesses row.</returns>
    function MemberAccessOf(pRefId: Int64; out pAccess: TCallEdge): Boolean;
  end;

  /// <summary>The recipe that cuts one edge of a circular group.</summary>
  /// <remarks>crMoveGlobals = move the declarations into a leaf unit (the playbook's
  /// original recipe); crRoutineInversion = R1, call one routine through a
  /// procedural variable (PlanRoutineInversion); crMemberInterface = R2, read the
  /// members through an extracted interface (PlanMemberInterface).</remarks>
  TCutRecipe = (crNone, crMoveGlobals, crRoutineInversion, crMemberInterface);

  /// <summary>One line edit a recipe makes in an existing unit.</summary>
  TRecipeEdit = record
    /// <summary>File id of the edited unit.</summary>
    Fid: Int64;
    /// <summary>1-based line, as indexed.</summary>
    Line: Integer;
    /// <summary>True: replace Line by NewLines; False: insert NewLines after Line.</summary>
    Replace: Boolean;
    /// <summary>The new text.</summary>
    NewLines: TArray<string>;
  end;

  /// <summary>Why a recipe does not apply to an edge.</summary>
  TRecipeRefusal = record
    /// <summary>Refusal kind (2026-10-10 contract 4.4 strings); '' when the recipe applies.</summary>
    Kind: string;
    /// <summary>The symbol the refusal names.</summary>
    Symbol: string;
    /// <summary>File the refusal points at; 0 for none.</summary>
    Fid: Int64;
    /// <summary>Line the refusal points at; 0 for none.</summary>
    Line: Integer;
    /// <summary>One sentence for the playbook.</summary>
    Reason: string;
  end;

  /// <summary>What recipe R1 (routine-call inversion) or R2 (member hand-over) does to
  /// one edge, as data the planner maps onto its leaf machinery and file edits.</summary>
  /// <remarks>The leaf's new unit, its .dpr / .dproj registration and every uses-clause
  /// edit are NOT here: the planner derives them (UntangleCatalog leaf, Task 3a lexer
  /// edits) from LeafStem / DeclStem / ConsumerFid (R2: also LeafUses / ConsumerUses).
  /// The R1 fields are empty for R2 and the R2 fields empty for R1.</remarks>
  TRecipeSteps = record
    /// <summary>crRoutineInversion or crMemberInterface when filled; crNone otherwise.</summary>
    Recipe: TCutRecipe;
    /// <summary>symbols.id of the routine.</summary>
    RoutineId: Int64;
    /// <summary>The routine's name, as declared.</summary>
    RoutineName: string;
    /// <summary>Lower-case stem of the unit that declares it (the edge's ToStem).</summary>
    DeclStem: string;
    /// <summary>File id of the calling unit (the edge's FromStem).</summary>
    ConsumerFid: Int64;
    /// <summary>`T&lt;Routine&gt;Ptr`.</summary>
    PtrType: string;
    /// <summary>`&lt;Routine&gt;Ptr`.</summary>
    PtrVar: string;
    /// <summary>`T&lt;Routine&gt;Ptr = function(&lt;signature verbatim&gt;);` plus the declaration's
    /// calling convention, e.g. ` stdcall;` (no indent).</summary>
    TypeDecl: string;
    /// <summary>`&lt;Routine&gt;Ptr: T&lt;Routine&gt;Ptr;` (no indent).</summary>
    VarDecl: string;
    /// <summary>Stem of the EXISTING unit outside the group that receives TypeDecl / VarDecl
    /// (J2); '' = the declaring unit's `&lt;Source&gt;.Untangle` leaf.</summary>
    LeafStem: string;
    /// <summary>R1: the call-site replacements (consumer) and the initialization assignment
    /// (declaring unit). R2: the `is` / `as` rewrites (consumer), the heritage line, the
    /// getter declarations and the getter bodies (class unit).</summary>
    Edits: TArray<TRecipeEdit>;
    /// <summary>R2: the class whose members the interface hands over.</summary>
    ClassTypeName: string;
    /// <summary>R2: symbols.id of that class.</summary>
    ClassId: Int64;
    /// <summary>R2: `I&lt;Class without its T&gt;Surface`.</summary>
    IfaceName: string;
    /// <summary>R2: its GUID text `{8-4-4-4-12}` (SurfaceGuid of `&lt;Leaf&gt;.&lt;IfaceName&gt;`).</summary>
    IfaceGuid: string;
    /// <summary>R2: the interface declaration, indented for a `type` block, without the keyword.</summary>
    IfaceDecl: TArray<string>;
    /// <summary>R2: the uses entries the leaf's interface section needs for the member types.</summary>
    LeafUses: TArray<string>;
    /// <summary>R2: entries the consumer's implementation uses must gain (System.SysUtils for
    /// Supports, the unit of a cast ancestor), each not visible there yet.</summary>
    ConsumerUses: TArray<string>;
    /// <summary>R2: `Name: Type` of every member carried, in declaration order.</summary>
    MemberSigs: TArray<string>;
    /// <summary>R2: the ancestor a receiver that does not implement IInterface is cast
    /// through; '' when no line needs a cast.</summary>
    CastAncestor: string;
  end;

const
  /// <summary>Classes that implement IInterface for their descendants (R2): a receiver of
  /// one of these types can be cast with `as ISurface` as is; any other receiver is cast
  /// through the first such ancestor of the class.</summary>
  CIInterfaceRoots: array[0..4] of string = ('TInterfacedObject', 'TComponent', 'TInterfacedPersistent',
    'TAggregatedObject', 'TContainedObject');

/// <summary>Tells which kind of type use a refs.kind 'type_use' row is, from its line.</summary>
/// <param name="pLineText">The source line of the reference.</param>
/// <param name="pName">The type name the ref records.</param>
/// <returns>Checked in this order, case-insensitively: `is Name` -&gt; erTypeIs;
/// `as Name` -&gt; erTypeAs; `Name(` -&gt; erTypeCast; `: Name` -&gt; erTypeDecl;
/// else erOther.</returns>
function ClassifyTypeUse(const pLineText, pName: string): TEdgeRefKind;

/// <summary>The types a routine's stored signature names, each resolved to its
/// declaring unit as seen from the routine's own unit.</summary>
/// <param name="pSource">Index access; must not be nil.</param>
/// <param name="pDeclFid">File id of the unit that declares the routine.</param>
/// <param name="pDeclLine">Line of the routine's declaration (selects the visible uses).</param>
/// <param name="pSig">symbols.signature, e.g. `(const pFolderId: Integer): IFoo`.</param>
/// <returns>One entry per distinct type identifier, in signature order.</returns>
/// <remarks>Only the text after a ':' of each `;`/`,`/`(`/`)` group is read (parameter
/// names are not types); `= default` tails and the words const var out array of
/// function procedure reference to packed are dropped. A dotted `Unit.TFoo` keeps its
/// name as written and is declared in the unit its prefix names. An identifier no
/// visible index row declares (e.g. Integer) gets DeclStem ''.</remarks>
function SignatureTypes(const pSource: IEdgeSurfaceSource; pDeclFid: Int64; pDeclLine: Integer;
  const pSig: string): TArray<TSigType>;

/// <summary>Whether every resolved type of a signature lives outside the circular group.</summary>
/// <param name="pTypes">The result of SignatureTypes.</param>
/// <param name="pStems">Receives the distinct declaring stems of the resolved types.</param>
/// <returns>True when at least one type resolved and none is InScc -- a pointer /
/// event type for the routine could then be declared in pStems without touching
/// the cycle.</returns>
function SigTypesOutsideScc(const pTypes: TArray<TSigType>; out pStems: TArray<string>): Boolean;

/// <summary>Collects what unit pFromFid takes from unit pToStem.</summary>
/// <param name="pSource">Index access; must not be nil. Its IsSccStem must answer for
/// the group the edge belongs to (it fills SigTypes[].InScc).</param>
/// <param name="pFromFid">File id of the citing unit A.</param>
/// <param name="pToStem">Lower-case stem of the used unit B.</param>
/// <returns>The surface; only FromStem / ToStem are set when either unit is not indexed.</returns>
/// <remarks>Reads the index only. A ref with a member_accesses row counts as a member
/// access; the companion 'member-access' rows of a call are skipped; a bare name is
/// bound by its symbol_id when it has one, else by name (BindName), and a name that
/// is a local or parameter of its routine is never bound.</remarks>
function BuildEdgeSurface(const pSource: IEdgeSurfaceSource; const pFromFid: Int64;
  const pToStem: string): TEdgeSurface;

/// <summary>The JSON `cycles --causes` prints for one edge.</summary>
/// <param name="pS">The surface.</param>
/// <returns>A new object {from, to, surface:{members, classes, has_write,
/// has_construction, has_class_method, has_class_ref_arg, has_decl, routine,
/// routine_sig, sig_types:[{name, unit, in_scc}], call_count}}; the caller owns it.</returns>
function EdgeSurfaceToJson(const pS: TEdgeSurface): TJSONObject;

/// <summary>Recipe R1, routine-call inversion: the edge A -&gt; B is one routine of B
/// that A calls; A calls it through a procedural variable declared in a leaf and
/// assigned in B's initialization section, so A no longer names B.</summary>
/// <param name="pSource">Index access; must not be nil; IsSccStem answers for the edge's group.</param>
/// <param name="pSurface">The edge's surface (BuildEdgeSurface); RoutineName must be set.</param>
/// <param name="pRefusal">Receives why the recipe does not apply; Kind '' when it does.</param>
/// <returns>The steps; Recipe = crNone when refused.</returns>
/// <remarks>
/// <para>Refusals, checked in this order: `not-a-routine` (RoutineName ''),
/// `signature-in-cycle` (a SigTypes entry is InScc; names the type),
/// `overloaded-routine` (two signatures of the name in its unit), `signature-unknown` (a function
/// with no stored signature), `routine-not-called`
/// (a ref of the edge is not a call -- `@Foo`, `X := Foo` as a value),
/// `qualified-ref` (the consumer names anything as `B.X`, B the declaring unit), `init-order` (a call line lies in
/// A's initialization section, or that section -- from `initialization` to `end.` --
/// names the enclosing routine as a whole word: the variable is still nil there),
/// `unsupported-directive` (varargs, or a directive word it cannot classify, on the declaration).</para>
/// <para>A calling convention on the declaration (register pascal cdecl stdcall safecall
/// winapi) is carried into the procedural type; inline, overload, external, forward and the
/// hint directives do not change it and are skipped.</para>
/// <para>Leaf (J2): the first resolved signature type's unit that is outside the group,
/// used by BOTH A and B in their interface sections, declares every resolved signature
/// type, and leaves only System built-ins unresolved; else LeafStem '' (the planner
/// uses B's Untangle leaf). The signature is copied verbatim (J3). Callers outside the
/// group are not touched (J6).</para>
/// <para>B's edit: the assignment becomes the first statement of its initialization
/// section; without one, `initialization` is inserted before `finalization`, or the
/// final `end.` is replaced by the section plus `end.`.</para>
/// </remarks>
function PlanRoutineInversion(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface;
  out pRefusal: TRecipeRefusal): TRecipeSteps;

/// <summary>The deterministic GUID of an extracted interface (R2).</summary>
/// <param name="pText">`&lt;LeafUnit&gt;.&lt;Interface&gt;`, e.g. `DemoGagePort.Untangle.IDemoGagePortSurface`.</param>
/// <returns>The MD5 of pText (UTF-8) as `{8-4-4-4-12}` upper-case hex, so a plan is
/// reproducible and its text can be pinned.</returns>
function SurfaceGuid(const pText: string): string;

/// <summary>The first ancestor of a class through which `as ISurface` compiles (R2).</summary>
/// <param name="pProject">The project index; must not be nil.</param>
/// <param name="pLibrary">The platform library index, or nil (the walk then stops at the
/// first ancestor the project does not declare).</param>
/// <param name="pClass">The class (a symbol of pProject).</param>
/// <param name="pAncestor">Receives that ancestor's name; '' when there is none.</param>
/// <returns>True when an ancestor (the class itself excluded) is one of CIInterfaceRoots or
/// lists an interface in its heritage. Walks symbols.heritage in pProject, then pLibrary;
/// TObject and a chain ending at a name no index declares give False.</returns>
function AncestorImplementingIInterface(const pProject, pLibrary: ISymbolStore; const pClass: TSymbol;
  out pAncestor: string): Boolean;

/// <summary>Recipe R2, member hand-over through an extracted interface: the edge A -&gt; B is
/// `is` / `as` tests against ONE class of B plus reads of its fields and properties; the
/// class implements a new interface carrying read-only properties for those members,
/// declared in B's `&lt;B&gt;.Untangle` leaf, and A tests and casts against the interface.</summary>
/// <param name="pSource">Index access; must not be nil; IsSccStem answers for the edge's group.</param>
/// <param name="pLibrary">The platform library index (class ancestry, inherited members, the
/// units of library types); nil = project only, which refuses whenever the answer needs it.</param>
/// <param name="pSurface">The edge's surface (BuildEdgeSurface).</param>
/// <param name="pLeafUnit">The unit name of the leaf that will hold the interface (its GUID
/// is derived from it).</param>
/// <param name="pRefusal">Receives why the recipe does not apply; Kind '' when it does.</param>
/// <returns>The steps; Recipe = crNone when refused.</returns>
/// <remarks>
/// <para>Shape (first offending ref, in line order): every ref must be erTypeIs, erTypeAs or
/// erMemberRead -- else `member-write`, `construction`, `class-method` (a method called
/// through the class or an instance, e.g. in a `with` body), `class-ref`, `type-decl`,
/// `type-cast`, `other-ref` (a routine or variable of B); then `multiple-classes`,
/// `qualified-ref` (`B.X` anywhere in A).</para>
/// <para>Members: each must be a field or a non-indexed property declared in the class itself
/// (`member-unsupported`; a method is `class-method`); `duplicate-identifier` when the class
/// already has `Get&lt;M&gt;`. Class: its heritage on its declaration line and its `end;` line
/// (`manual-edit`); an ancestor implementing IInterface (`no-iinterface`); no reference
/// counting on the way -- TInterfacedObject, TAggregatedObject, TContainedObject or an
/// unknown implementation would free the object when the temporary interface is released
/// (`ref-counted`).</para>
/// <para>Consumer: `X is TClass` -&gt; `Supports(X, ISurface)`; `X as TClass` -&gt; `X as
/// ISurface` when X's static type implements IInterface, else `TAnc(X) as ISurface` (TAnc =
/// AncestorImplementingIInterface). X must be `Self`, a parameter or local of the enclosing
/// routine, or a field / property of the enclosing class or its ancestors (`receiver-unknown`);
/// a project TAnc must not be declared in B (`cast-unseen`). Every name used inside a
/// `with X as TClass do` body that is a member of the class or of an ancestor but not
/// carried, a getter name or an IInterface method refuses `with-member` (it would bind to
/// something else after the rewrite); an ancestry no index completes refuses
/// `ancestry-unknown`. A failed `as ISurface` raises EIntfCastError, not EInvalidCast: when
/// A names EInvalidCast, an `as` without an earlier `is` guard on the same receiver in its
/// routine refuses `exception-semantics`.</para>
/// <para>Leaf: the units declaring the member types -- a project unit as bound from B, else
/// the library unit B's interface uses names (`type-unresolved`); never a unit of the
/// group (`leaf-uses-cycle`). The dotted prefixes are walked longest to shortest; the first that names a unit wins (a
/// project unit, a uses entry of B, a uses entry under a default unit scope, a library unit declaring
/// the type); with none and a unit-scope first segment the plan refuses `unresolved-qualified-type`; otherwise it is the outer type of a nested type and the
/// unit declaring that outer type is used (`member-unsupported` when none resolves).</para>
/// </remarks>
function PlanMemberInterface(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore;
  const pSurface: TEdgeSurface; const pLeafUnit: string; out pRefusal: TRecipeRefusal): TRecipeSteps;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.RegularExpressions, System.Math,
  System.Generics.Collections, System.Generics.Defaults, System.Hash;

const
  { The Delphi default unit-scope names (.dproj DCC_Namespace when it sets none); a type written
    `System.Classes.TStrings` names the unit through such a scope when the uses says `Classes`. }
  CUnitScopeNames: array[0..8] of string = ('System', 'Xml', 'Data', 'Datasnap', 'Web', 'Soap', 'Vcl', 'Winapi', 'System.Win');
  CUnitScopeRoots = ' System Xml Data Datasnap Web Soap Vcl Winapi ';
  CNotTypeWords = ' const var out array of function procedure reference to packed ';
  { System-unit types every unit sees without a uses entry (R1, J2) }
  CBuiltinTypes = ' integer cardinal shortint smallint longint int64 uint64 byte word longword nativeint ' +
    'nativeuint boolean bytebool wordbool longbool char ansichar widechar string ansistring widestring ' +
    'unicodestring shortstring rawbytestring single double extended currency real comp pointer pchar ' +
    'pansichar pwidechar tobject tclass iinterface iunknown variant olevariant tdatetime tguid hresult ';
  { R1 directive classes (fix round 1): carried into the procedural type / refused / no effect on it }
  CConventionWords       = ' register pascal cdecl stdcall safecall winapi ';
  CUnsupportedDirectives = ' varargs ';
  CNeutralDirectives     = ' inline overload external forward deprecated platform library experimental assembler delayed ';
  CMaxDeclLines          = 8;
  CDeclStartWords        = ' function procedure constructor destructor class operator type var const threadvar ' +
    'resourcestring label begin asm implementation interface initialization finalization exports uses ' +
    'property end strict private protected public published ';  { a routine declaration and its directives span at most this many lines }

function StemOfPath(const pPath: string): string;
begin
  Result:= LowerCase(ChangeFileExt(ExtractFileName(StringReplace(pPath, '/', '\', [rfReplaceAll])), ''));
end;

function ClassifyTypeUse(const pLineText, pName: string): TEdgeRefKind;
var
  N: string;
begin
  N:= TRegEx.Escape(pName);
  if TRegEx.IsMatch(pLineText, '\bis\s+' + N + '\b', [roIgnoreCase]) then Exit(erTypeIs);
  if TRegEx.IsMatch(pLineText, '\bas\s+' + N + '\b', [roIgnoreCase]) then Exit(erTypeAs);
  if TRegEx.IsMatch(pLineText, '\b' + N + '\s*\(', [roIgnoreCase]) then Exit(erTypeCast);
  if TRegEx.IsMatch(pLineText, ':\s*' + N + '\b', [roIgnoreCase]) then Exit(erTypeDecl);
  Result:= erOther;
end;

function SignatureTypes(const pSource: IEdgeSurfaceSource; pDeclFid: Int64; pDeclLine: Integer;
  const pSig: string): TArray<TSigType>;
var
  L    : TList<TSigType>;
  Seen : TDictionary<string, Boolean>;
  T    : TSigType;
  Owner: TSymbol;
  Stem : string;
begin
  L   := TList<TSigType>.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for var Group in pSig.Split([';', ',', '(', ')']) do
    begin
      var P:= Group.LastIndexOf(':');
      if P < 0 then Continue;
      var TypeText:= Group.Substring(P + 1);
      var Eq:= TypeText.IndexOf('=');
      if Eq >= 0 then TypeText:= TypeText.Substring(0, Eq);
      for var M in TRegEx.Matches(TypeText, '[A-Za-z_][A-Za-z0-9_.]*') do
      begin
        var Dot  := M.Value.LastIndexOf('.');
        var Ident:= M.Value.Substring(Dot + 1);
        if (Ident = '') or ContainsText(CNotTypeWords, ' ' + Ident + ' ') then Continue;
        if Seen.ContainsKey(LowerCase(M.Value)) then Continue;
        Seen.Add(LowerCase(M.Value), True);
        T:= Default(TSigType);
        T.Name:= M.Value;
        if Dot > 0 then T.DeclStem:= LowerCase(M.Value.Substring(0, Dot))
        else if pSource.BindName(pDeclFid, pDeclLine, Ident, Owner, Stem) then T.DeclStem:= Stem;
        T.InScc:= (T.DeclStem <> '') and pSource.IsSccStem(T.DeclStem);
        L.Add(T);
      end;
    end;
    Result:= L.ToArray;
  finally
    Seen.Free;
    L.Free;
  end;
end;

function SigTypesOutsideScc(const pTypes: TArray<TSigType>; out pStems: TArray<string>): Boolean;
var
  Stems: TList<string>;
begin
  pStems:= nil;
  Stems := TList<string>.Create;
  try
    for var T in pTypes do
    begin
      if T.InScc then Exit(False);
      if (T.DeclStem <> '') and not Stems.Contains(T.DeclStem) then Stems.Add(T.DeclStem);
    end;
    pStems:= Stems.ToArray;
    Result:= Stems.Count > 0;
  finally
    Stems.Free;
  end;
end;

type
  { One BuildEdgeSurface run: the edge, its caches, and the record being filled. }
  TSurfaceBuilder = class  // dl:ok high-response@2506 -- implementation-private one-shot builder of one edge; the response set is its small Take/Bind steps plus the store and RTL calls they make, not a design smell
  private
    FSource   : IEdgeSurfaceSource;
    FStore    : ISymbolStore;
    FFromFid  : Int64;
    FToFid    : Int64;
    FLines    : TArray<string>;
    FSyms     : TDictionary<Int64, TSymbol>;
    FRefs     : TList<TEdgeRef>;
    FClasses  : TStringList;
    FMembers  : TStringList;
    FOwners   : TDictionary<Int64, TSymbol>;
    FRcvLines : TDictionary<string, Boolean>;
    FClassUses: TList<TReference>;
    FSurface  : TEdgeSurface;
    function Sym(pId: Int64): TSymbol;
    function TopLevel(const pSym: TSymbol): TSymbol;
    function IsLocal(const pR: TReference): Boolean;
    function LineText(pLine: Integer): string;
    function BindBare(const pR: TReference; const pName: string; out pOwner: TSymbol): Boolean;
    procedure AddRef(const pR: TReference; pKind: TEdgeRefKind; pSymbolId: Int64);
    function TakeMemberAccess(const pR: TReference): Boolean;
    function TakeReceiverRef(const pR: TReference): Boolean;
    procedure TakeClassMemberAccess(const pR: TReference);
    procedure TakeBareRef(const pR: TReference);
    procedure Finish;
    procedure Collect;
  public
    constructor Create(const pSource: IEdgeSurfaceSource; pFromFid: Int64; const pToStem: string);
    destructor Destroy; override;
    function Run: TEdgeSurface;
  end;

constructor TSurfaceBuilder.Create(const pSource: IEdgeSurfaceSource; pFromFid: Int64; const pToStem: string);
begin
  inherited Create;
  FSource := pSource;
  FStore  := pSource.Store;
  FFromFid:= pFromFid;
  FToFid  := pSource.FidOfStem(pToStem);
  FSurface := Default(TEdgeSurface);
  FSurface.ToStem:= pToStem;
  if pFromFid > 0 then FSurface.FromStem:= StemOfPath(FStore.GetFilePath(pFromFid));
  FSyms     := TDictionary<Int64, TSymbol>.Create;
  FRefs     := TList<TEdgeRef>.Create;
  FClasses  := TStringList.Create(dupIgnore, True, False);
  FMembers  := TStringList.Create(dupIgnore, True, False);
  FOwners   := TDictionary<Int64, TSymbol>.Create;
  FRcvLines := TDictionary<string, Boolean>.Create;
  FClassUses:= TList<TReference>.Create;
end;

destructor TSurfaceBuilder.Destroy;
begin
  FClassUses.Free;
  FRcvLines.Free;
  FOwners.Free;
  FMembers.Free;
  FClasses.Free;
  FRefs.Free;
  FSyms.Free;
  inherited Destroy;
end;

function TSurfaceBuilder.Sym(pId: Int64): TSymbol;
begin
  if FSyms.TryGetValue(pId, Result) then Exit;
  Result:= FStore.GetSymbolById(pId);
  FSyms.Add(pId, Result);
end;

function TSurfaceBuilder.TopLevel(const pSym: TSymbol): TSymbol;
begin
  Result:= pSym;
  while Result.ParentId > 0 do
  begin
    var Parent:= Sym(Result.ParentId);
    if (Parent.Id <= 0) or (Parent.Kind in [skUnit, skProgram, skPackage]) then Break;
    Result:= Parent;
  end;
end;

function TSurfaceBuilder.IsLocal(const pR: TReference): Boolean;
var
  Local: TSymbol;
begin
  if pR.EnclosingSymbolId <= 0 then Exit(False);
  Local:= FStore.FindChildSymbolByName(pR.EnclosingSymbolId, pR.NameText);
  Result:= (Local.Id > 0) and (Local.Kind in [skLocalVar, skParam]);
end;

function TSurfaceBuilder.LineText(pLine: Integer): string;
begin
  if (pLine >= 1) and (pLine <= Length(FLines)) then Result:= Trim(FLines[pLine - 1])
  else Result:= '';
end;

function TSurfaceBuilder.BindBare(const pR: TReference; const pName: string; out pOwner: TSymbol): Boolean;
var
  Stem: string;
begin
  if pR.SymbolId > 0 then
  begin
    pOwner:= TopLevel(Sym(pR.SymbolId));
    Exit(pOwner.FileId = FToFid);
  end;
  Result:= FSource.BindName(FFromFid, pR.StartLine, pName, pOwner, Stem) and (Stem = FSurface.ToStem);
end;

procedure TSurfaceBuilder.AddRef(const pR: TReference; pKind: TEdgeRefKind; pSymbolId: Int64);
var
  E: TEdgeRef;
begin
  E:= Default(TEdgeRef);
  E.Line    := pR.StartLine;
  E.Kind    := pKind;
  E.Name    := pR.NameText;
  E.LineText:= LineText(pR.StartLine);
  E.SymbolId:= pSymbolId;
  E.EnclosingId:= pR.EnclosingSymbolId;
  if pR.EnclosingSymbolId > 0 then E.Enclosing:= Sym(pR.EnclosingSymbolId).Name;
  FRefs.Add(E);
end;

{ A ref with a member_accesses row: a member (or unit-level var) access, never bound by name. }
function TSurfaceBuilder.TakeMemberAccess(const pR: TReference): Boolean;
var
  MA: TCallEdge;
begin
  if not FSource.MemberAccessOf(pR.Id, MA) then Exit(False);
  Result:= True;
  if MA.TargetSymbolId <= 0 then Exit;
  var M:= Sym(MA.TargetSymbolId);
  if M.FileId <> FToFid then Exit;
  FOwners.AddOrSetValue(TopLevel(M).Id, TopLevel(M));
  if SameText(MA.MemberMode, 'write') then
  begin
    FSurface.HasWrite:= True;
    AddRef(pR, erMemberWrite, M.Id);
  end
  else if (M.ParentId > 0) and (Sym(M.ParentId).Kind in [skClass, skRecord, skInterface]) then
  begin
    FMembers.Add(M.Name);
    AddRef(pR, erMemberRead, M.Id);
  end
  else AddRef(pR, erOther, M.Id);
end;

{ A ref with a receiver: a call through a class of B, or a call bound to a routine of B. }
function TSurfaceBuilder.TakeReceiverRef(const pR: TReference): Boolean;
var
  Cls : TSymbol;
  Stem: string;
begin
  if pR.ReceiverText = '' then Exit(False);
  Result:= True;
  if not SameText(pR.Kind, 'call') then Exit;
  var Rcv:= pR.ReceiverText.Substring(pR.ReceiverText.LastIndexOf('.') + 1);
  if FSource.BindName(FFromFid, pR.StartLine, Rcv, Cls, Stem) and (Stem = FSurface.ToStem) and
    (Cls.Kind = skClass) then
  begin
    var Ctor:= if pR.SymbolId > 0 then Sym(pR.SymbolId).Kind = skConstructor
      else SameText(pR.NameText, 'Create') or (FStore.FindChildSymbolByName(Cls.Id, pR.NameText).Kind = skConstructor);
    if Ctor then FSurface.HasConstruction:= True
    else FSurface.HasClassMethod:= True;
    Inc(FSurface.CallCount);
    FClasses.Add(Cls.Name);
    FOwners.AddOrSetValue(Cls.Id, Cls);
    FRcvLines.AddOrSetValue(Format('%d:%s', [pR.StartLine, LowerCase(Cls.Name)]), True);
    AddRef(pR, erClassReceiver, Cls.Id);
    Exit;
  end;
  if (pR.SymbolId <= 0) or (Sym(pR.SymbolId).FileId <> FToFid) then Exit;
  Inc(FSurface.CallCount);
  FOwners.AddOrSetValue(TopLevel(Sym(pR.SymbolId)).Id, TopLevel(Sym(pR.SymbolId)));
  AddRef(pR, erCall, pR.SymbolId);
end;

{ A 'member-access' row whose receiver is a class of B and that no call row on its line
  already took (TakeReceiverRef keys those lines): `TFoo.ClassName`, `TFoo.Create` written
  without parentheses -- a call through the class all the same. }
procedure TSurfaceBuilder.TakeClassMemberAccess(const pR: TReference);
var
  Cls : TSymbol;
  Stem: string;
begin
  if pR.ReceiverText = '' then Exit;
  var Rcv:= pR.ReceiverText.Substring(pR.ReceiverText.LastIndexOf('.') + 1);
  if not (FSource.BindName(FFromFid, pR.StartLine, Rcv, Cls, Stem) and (Stem = FSurface.ToStem) and
    (Cls.Kind = skClass) and SameText(Cls.Name, Rcv)) then Exit;
  var Key:= Format('%d:%s', [pR.StartLine, LowerCase(Cls.Name)]);
  if FRcvLines.ContainsKey(Key) then Exit;
  if SameText(pR.NameText, 'Create') or (FStore.FindChildSymbolByName(Cls.Id, pR.NameText).Kind = skConstructor) then
    FSurface.HasConstruction:= True
  else FSurface.HasClassMethod:= True;
  FClasses.Add(Cls.Name);
  FOwners.AddOrSetValue(Cls.Id, Cls);
  FRcvLines.Add(Key, True);
  AddRef(pR, erClassReceiver, Cls.Id);
end;

procedure TSurfaceBuilder.TakeBareRef(const pR: TReference);
var
  Owner: TSymbol;
  Kind : TEdgeRefKind;
begin
  if IsLocal(pR) or not BindBare(pR, pR.NameText, Owner) then Exit;
  FOwners.AddOrSetValue(Owner.Id, Owner);
  if Owner.Kind = skClass then FClasses.Add(Owner.Name);
  Kind:= erOther;
  if SameText(pR.Kind, 'call') then
  begin
    Kind:= erCall;
    Inc(FSurface.CallCount);
  end
  else if SameText(pR.Kind, 'type_use') then
  begin
    Kind:= ClassifyTypeUse(LineText(pR.StartLine), pR.NameText);
    if Kind = erTypeDecl then FSurface.HasDecl:= True;
  end
  else if SameText(pR.Kind, 'write') then
  begin
    Kind:= erMemberWrite;
    FSurface.HasWrite:= True;
  end
  else if SameText(pR.Kind, 'read') and (Owner.Kind = skClass) then FClassUses.Add(pR);
  AddRef(pR, Kind, Owner.Id);
end;

procedure TSurfaceBuilder.Finish;
var
  Owner: TSymbol;
begin
  Owner:= Default(TSymbol);
  for var R in FClassUses do
    if not FRcvLines.ContainsKey(Format('%d:%s', [R.StartLine, LowerCase(R.NameText)])) then
      FSurface.HasClassRefArg:= True;
  FSurface.Refs      := FRefs.ToArray;
  FSurface.ClassNames:= FClasses.ToStringArray;
  FSurface.Members   := FMembers.ToStringArray;
  if FOwners.Count <> 1 then Exit;
  for var O in FOwners.Values do Owner:= O;
  if not (Owner.Kind in [skProcedure, skFunction]) then Exit;
  FSurface.RoutineName:= Owner.Name;
  FSurface.RoutineSig := Owner.Signature;
  FSurface.SigTypes   := SignatureTypes(FSource, FToFid, Owner.StartLine, Owner.Signature);
end;

function TSurfaceBuilder.Run: TEdgeSurface;
begin
  if (FFromFid > 0) and (FToFid > 0) then Collect;
  Result:= FSurface;
end;

procedure TSurfaceBuilder.Collect;
begin
  FLines:= FSource.FileLines(FFromFid);
  for var R in FStore.GetReferencesFromFile(FFromFid) do
  begin
    if TakeMemberAccess(R) then Continue;
    if SameText(R.Kind, 'member-access') then
    begin
      { the companion row of a call -- or, without one, a member reached through a
        class of B with no call row (`TFoo.ClassName`): a class method (E18 T6) }
      TakeClassMemberAccess(R);
      Continue;
    end;
    if TakeReceiverRef(R) then Continue;
    TakeBareRef(R);
  end;
  Finish;
end;

function BuildEdgeSurface(const pSource: IEdgeSurfaceSource; const pFromFid: Int64;
  const pToStem: string): TEdgeSurface;
var
  B: TSurfaceBuilder;
begin
  B:= TSurfaceBuilder.Create(pSource, pFromFid, pToStem);
  try
    Result:= B.Run;
  finally
    B.Free;
  end;
end;

function StringsToJson(const pItems: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pItems do Result.Add(S);
end;

function EdgeSurfaceToJson(const pS: TEdgeSurface): TJSONObject;
var
  Surf : TJSONObject;
  Types: TJSONArray;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('from', pS.FromStem);
  Result.AddPair('to', pS.ToStem);
  Surf:= TJSONObject.Create;
  Result.AddPair('surface', Surf);
  Surf.AddPair('members', StringsToJson(pS.Members));
  Surf.AddPair('classes', StringsToJson(pS.ClassNames));
  Surf.AddPair('has_write', TJSONBool.Create(pS.HasWrite));
  Surf.AddPair('has_construction', TJSONBool.Create(pS.HasConstruction));
  Surf.AddPair('has_class_method', TJSONBool.Create(pS.HasClassMethod));
  Surf.AddPair('has_class_ref_arg', TJSONBool.Create(pS.HasClassRefArg));
  Surf.AddPair('has_decl', TJSONBool.Create(pS.HasDecl));
  Surf.AddPair('routine', pS.RoutineName);
  Surf.AddPair('routine_sig', pS.RoutineSig);
  Types:= TJSONArray.Create;
  Surf.AddPair('sig_types', Types);
  for var T in pS.SigTypes do
  begin
    var JT:= TJSONObject.Create;
    Types.AddElement(JT);
    JT.AddPair('name', T.Name);
    JT.AddPair('unit', T.DeclStem);
    JT.AddPair('in_scc', TJSONBool.Create(T.InScc));
  end;
  Surf.AddPair('call_count', TJSONNumber.Create(pS.CallCount));
end;

{ ---------------------------------------------------------------------------
  R1 -- routine-call inversion
  --------------------------------------------------------------------------- }

function LineOf(const pLines: TArray<string>; pLine: Integer): string;
begin
  if (pLine >= 1) and (pLine <= Length(pLines)) then Result:= pLines[pLine - 1]
  else Result:= '';
end;

{ The code of a line before a `//` comment, trimmed. }
function BareCode(const pLine: string): string;
begin
  var P:= Pos('//', pLine);
  Result:= Trim(if P > 0 then Copy(pLine, 1, P - 1) else pLine);
end;

{ 1-based number of the LAST line whose code is exactly pWord, or 0. }
function LastKeywordLine(const pLines: TArray<string>; const pWord: string): Integer;
begin
  for var I:= High(pLines) downto 0 do
    if SameText(BareCode(pLines[I]), pWord) then Exit(I + 1);
  Result:= 0;
end;

function MakeRefusal(const pKind, pSymbol: string; pFid: Int64; pLine: Integer; const pReason: string): TRecipeRefusal;
begin
  Result.Kind  := pKind;
  Result.Symbol:= pSymbol;
  Result.Fid   := pFid;
  Result.Line  := pLine;
  Result.Reason:= pReason;
end;

function UsesInInterface(const pStore: ISymbolStore; pFid: Int64; const pStem: string): Boolean;
begin
  for var U in pStore.GetUnitUsesForFile(pFid) do
    if (U.Section = uusInterface) and SameText(U.UnitName, pStem) then Exit(True);
  Result:= False;
end;

{ J2: the existing unit outside the group that both ends use in their interface
  and that declares every resolved type of the signature; '' when there is none. }
function PickExistingLeaf(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface;
  pFromFid, pDeclFid: Int64): string;
var
  Cand: string;
begin
  Result:= '';
  Cand  := '';
  for var T in pSurface.SigTypes do
    if T.DeclStem = '' then
    begin
      if not ContainsText(CBuiltinTypes, ' ' + T.Name.Substring(T.Name.LastIndexOf('.') + 1) + ' ') then Exit;
    end
    else if Cand = '' then Cand:= T.DeclStem
    else if T.DeclStem <> Cand then Exit;
  if (Cand = '') or pSource.IsSccStem(Cand) then Exit;
  if UsesInInterface(pSource.Store, pFromFid, Cand) and UsesInInterface(pSource.Store, pDeclFid, Cand) then
    Result:= Cand;
end;

{ J4, conservative: the call runs in the consumer's initialization section, or
  that section names the routine that holds the call. }
function InitOrderWhy(const pLines: TArray<string>; const pRef: TEdgeRef; const pUnit: string): string;
begin
  Result:= '';
  var Init:= LastKeywordLine(pLines, 'initialization');
  if Init = 0 then Exit;
  var Stop:= LastKeywordLine(pLines, 'end.');
  if Stop < Init then Stop:= Length(pLines) + 1;
  if (pRef.Line > Init) and (pRef.Line < Stop) then
    Exit(Format('the call at line %d runs in the initialization section of `%s`, before the variable ' +
      'may be assigned', [pRef.Line, pUnit]));
  var Encl:= pRef.Enclosing.Substring(pRef.Enclosing.LastIndexOf('.') + 1);
  if Encl = '' then Exit;
  for var L:= Init + 1 to Stop - 1 do
    if TRegEx.IsMatch(BareCode(LineOf(pLines, L)), '\b' + TRegEx.Escape(Encl) + '\b', [roIgnoreCase]) then
      Exit(Format('`%s` (it makes the call at line %d) is named at line %d, in the initialization section of ' +
        '`%s`: it may run before the variable is assigned', [Encl, pRef.Line, L, pUnit]));
end;

{ The declaring unit's edit: the assignment as the first statement of its
  initialization section, creating the section when there is none. }
function AssignmentEdit(const pLines: TArray<string>; pFid: Int64; const pAssign: string; out pEdit: TRecipeEdit): Boolean;
begin
  pEdit    := Default(TRecipeEdit);
  pEdit.Fid:= pFid;
  var Init:= LastKeywordLine(pLines, 'initialization');
  var Fin := LastKeywordLine(pLines, 'finalization');
  var Stop:= LastKeywordLine(pLines, 'end.');
  if Init > 0 then
  begin
    pEdit.Line    := Init;
    pEdit.NewLines:= [pAssign];
  end
  else if Fin > 0 then
  begin
    pEdit.Line    := Fin - 1;
    pEdit.NewLines:= ['initialization', pAssign, ''];
  end
  else if Stop > 0 then
  begin
    pEdit.Line    := Stop;
    pEdit.Replace := True;
    pEdit.NewLines:= ['initialization', pAssign, '', LineOf(pLines, Stop)];
  end;
  Result:= pEdit.Line > 0;
end;

{ R1 refusals a signature can give: not one routine, a type of the cycle, no stored
  signature, an overloaded name (the index binds a call of an overload by NAME, so the
  surface's signature may be another overload's -- E2010 in the run that found it). }
function SignatureRefusal(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface; pDeclFid: Int64;
  out pRoutine: TSymbol): TRecipeRefusal;
var
  Sigs: TList<string>;
begin
  Result  := Default(TRecipeRefusal);
  pRoutine:= Default(TSymbol);
  var Name:= pSurface.RoutineName;
  if (Name = '') or (Length(pSurface.Refs) = 0) then
    Exit(MakeRefusal('not-a-routine', '', pDeclFid, 0, 'the edge is not exactly one routine'));
  for var T in pSurface.SigTypes do
    if T.InScc then
      Exit(MakeRefusal('signature-in-cycle', T.Name, pDeclFid, 0, Format('the signature of `%s` names ' +
        '`%s`, declared in `%s`, a unit of this cycle -- a procedural type outside the cycle cannot name it',
        [Name, T.Name, T.DeclStem])));
  pRoutine:= pSource.Store.GetSymbolById(pSurface.Refs[0].SymbolId);
  Sigs:= TList<string>.Create;
  try
    for var S in pSource.Store.FindSymbolsByExactName(Name) do
      if (S.FileId = pDeclFid) and (S.Kind in [skFunction, skProcedure]) and not Sigs.Contains(S.Signature) then
        Sigs.Add(S.Signature);
    if Sigs.Count > 1 then
      Result:= MakeRefusal('overloaded-routine', Name, pDeclFid, pRoutine.StartLine, Format('`%s` is ' +
        'overloaded (%d signatures); the index cannot tell which one each call binds to', [Name, Sigs.Count]))
    else if (pRoutine.Kind = skFunction) and (pSurface.RoutineSig = '') then
      Result:= MakeRefusal('signature-unknown', Name, pDeclFid, pRoutine.StartLine,
        Format('the index holds no signature for the function `%s`', [Name]));
  finally
    Sigs.Free;
  end;
end;

{ Skips pText[pPos..] up to and past the next `;` outside a string literal; False when there is none. }
function SkipPastSemicolon(const pText: string; var pPos: Integer): Boolean;
var
  InStr: Boolean;
begin
  InStr:= False;
  while pPos <= Length(pText) do
  begin
    if pText[pPos] = '''' then InStr:= not InStr
    else if (pText[pPos] = ';') and not InStr then
    begin
      Inc(pPos);
      Exit(True);
    end;
    Inc(pPos);
  end;
  Result:= False;
end;

{ Whether the word pWord, ending before pText[pAfter], starts the declaration that
  follows a routine's directives: a declaration keyword, or an identifier followed
  by `:` `,` `=` `.` `(` `[` (a field, a variable, a qualified name). }
function StartsNextDeclaration(const pText: string; pAfter: Integer; const pWord: string): Boolean;
begin
  if ContainsStr(CDeclStartWords, ' ' + pWord + ' ') then Exit(True);
  var Rest:= TrimLeft(pText.Substring(pAfter - 1));
  Result:= (Rest = '') or CharInSet(Rest[1], [':', ',', '=', '.', '(', '[']);
end;

{ The calling convention of the routine pName declared at line pLine, read from the
  directives after its signature. False, with pWhy, on a directive that changes the
  procedural type in a way R1 does not carry (varargs), or on text it cannot read. }
function DeclConvention(const pLines: TArray<string>; pLine: Integer; const pName: string;
  out pConv, pWhy: string): Boolean;
var
  Depth: Integer;
begin
  pConv:= '';
  pWhy := '';
  var SB:= TStringBuilder.Create;
  try
    for var L:= pLine to Min(pLine + CMaxDeclLines - 1, Length(pLines)) do SB.Append(BareCode(LineOf(pLines, L))).Append(' ');
    var Text:= SB.ToString;
    if ContainsStr(Text, '{$') or ContainsStr(Text, '(*$') then
    begin
      pWhy:= 'a compiler directive inside its declaration';
      Exit(False);
    end;
    Text:= TRegEx.Replace(TRegEx.Replace(Text, '\{[^}]*\}', ' '), '\(\*.*?\*\)', ' ');
    var M:= TRegEx.Match(Text, '\b(function|procedure)\s+' + TRegEx.Escape(pName) + '\b', [roIgnoreCase]);
    if not M.Success then
    begin
      pWhy:= Format('its declaration at line %d could not be read', [pLine]);
      Exit(False);
    end;
    var P:= M.Index + M.Length;
    while (P <= Length(Text)) and (Text[P] = ' ') do Inc(P);
    if (P <= Length(Text)) and (Text[P] = '(') then
    begin
      Depth:= 0;
      repeat
        if Text[P] = '(' then Inc(Depth) else if Text[P] = ')' then Dec(Depth);
        Inc(P);
      until (Depth = 0) or (P > Length(Text));
    end;
    if not SkipPastSemicolon(Text, P) then
    begin
      pWhy:= Format('its declaration at line %d could not be read', [pLine]);
      Exit(False);
    end;
    while True do
    begin
      var W:= TRegEx.Match(Text.Substring(P - 1), '^\s*([A-Za-z_]\w*)');
      if not W.Success then Break;
      var Word:= LowerCase(W.Groups[1].Value);
      if ContainsStr(CConventionWords, ' ' + Word + ' ') then pConv:= Word
      else if ContainsStr(CUnsupportedDirectives, ' ' + Word + ' ') then
      begin
        pWhy:= Format('the directive `%s` changes its procedural type', [Word]);
        Exit(False);
      end
      else if not ContainsStr(CNeutralDirectives, ' ' + Word + ' ') then
      begin
        { the directive run ends at the next declaration; any other word is a
          directive this planner cannot classify }
        if StartsNextDeclaration(Text, P + W.Length, Word) then Break;
        pWhy:= Format('the directive `%s` is not one the plan can classify', [Word]);
        Exit(False);
      end;
      Inc(P, W.Length);
      if not SkipPastSemicolon(Text, P) then Break;
    end;
    Result:= True;
  finally
    SB.Free;
  end;
end;

{ The first `<DeclUnit>.<member>` of the consumer (a qualified name is no ref on the edge
  surface, but needs the uses entry the cut removes): its line, member in pMember; 0 for none.
  `<DeclUnit>.<more>` that is itself a unit of the project (e.g. its Untangle leaf) is skipped. }
function UnitQualifiedLine(const pSource: IEdgeSurfaceSource; const pLines: TArray<string>;
  const pDeclUnit: string; out pMember: string): Integer;
begin
  pMember:= '';
  var Parts:= pDeclUnit.Split(['.']);
  for var I:= 0 to High(Parts) do Parts[I]:= TRegEx.Escape(Parts[I]);
  var Rx:= '(?<![\w.])' + string.Join('\s*\.\s*', Parts) + '\s*\.\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)';
  for var L:= 1 to Length(pLines) do
    for var M in TRegEx.Matches(BareCode(pLines[L - 1]), Rx, [roIgnoreCase]) do
    begin
      var Tail:= TRegEx.Replace(M.Groups[1].Value, '\s', '').Split(['.']);
      var IsUnit:= False;
      var Name  := pDeclUnit;
      for var Seg in Tail do
      begin
        Name:= Name + '.' + Seg;
        if pSource.FidOfStem(LowerCase(Name)) > 0 then IsUnit:= True;
      end;
      if IsUnit then Continue;
      pMember:= Tail[0];
      Exit(L);
    end;
  Result:= 0;
end;

{ R1 refusals a call site can give: not a call, a name qualified by the declaring unit
  anywhere in the consumer (the uses entry it needs would be removed), init order (J4). }
function CallRefusal(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface; pFromFid: Int64;
  const pLines: TArray<string>; const pFromUnit, pDeclUnit: string): TRecipeRefusal;
var
  Member: string;
begin
  Result:= Default(TRecipeRefusal);
  var Name:= pSurface.RoutineName;
  var Q:= UnitQualifiedLine(pSource, pLines, pDeclUnit, Member);
  if Q > 0 then
    Exit(MakeRefusal('qualified-ref', Member, pFromFid, Q, Format('line %d names `%s` qualified by its unit ' +
      '(`%s`); that use keeps needing the uses entry the cut removes', [Q, Member, Trim(pLines[Q - 1])])));
  for var R in pSurface.Refs do
  begin
    if R.Kind <> erCall then
      Exit(MakeRefusal('routine-not-called', Name, pFromFid, R.Line, Format('line %d uses `%s` without ' +
        'calling it (`%s`)', [R.Line, Name, R.LineText])));
    var Why:= InitOrderWhy(pLines, R, pFromUnit);
    if Why <> '' then Exit(MakeRefusal('init-order', Name, pFromFid, R.Line, Why));
  end;
end;

function PlanRoutineInversion(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface;
  out pRefusal: TRecipeRefusal): TRecipeSteps;
var
  Routine: TSymbol;
  Edits  : TList<TRecipeEdit>;
  Done   : TList<Integer>;
  E      : TRecipeEdit;
  Conv   : string;
  Why    : string;
begin
  Result  := Default(TRecipeSteps);
  var FromFid:= pSource.FidOfStem(pSurface.FromStem);
  var DeclFid:= pSource.FidOfStem(pSurface.ToStem);
  var Name   := pSurface.RoutineName;
  var Lines  := pSource.FileLines(FromFid);
  pRefusal:= SignatureRefusal(pSource, pSurface, DeclFid, Routine);
  if pRefusal.Kind = '' then
    pRefusal:= CallRefusal(pSource, pSurface, FromFid, Lines,
      ChangeFileExt(ExtractFileName(pSource.Store.GetFilePath(FromFid)), ''),
      ChangeFileExt(ExtractFileName(pSource.Store.GetFilePath(DeclFid)), ''));
  if (pRefusal.Kind = '') and not DeclConvention(pSource.FileLines(DeclFid), Routine.StartLine, Name, Conv, Why) then
    pRefusal:= MakeRefusal('unsupported-directive', Name, DeclFid, Routine.StartLine, Format('`%s`: %s', [Name, Why]));
  if pRefusal.Kind <> '' then Exit;
  Result.Recipe     := crRoutineInversion;
  Result.RoutineId  := Routine.Id;
  Result.RoutineName:= Name;
  Result.DeclStem   := pSurface.ToStem;
  Result.ConsumerFid:= FromFid;
  Result.PtrVar     := Name + 'Ptr';
  Result.PtrType    := 'T' + Result.PtrVar;
  Result.TypeDecl   := Format('%s = %s%s;%s', [Result.PtrType,
    (if Routine.Kind = skFunction then 'function' else 'procedure'), pSurface.RoutineSig,
    (if Conv <> '' then ' ' + Conv + ';' else '')]);
  Result.VarDecl    := Format('%s: %s;', [Result.PtrVar, Result.PtrType]);
  Result.LeafStem   := PickExistingLeaf(pSource, pSurface, FromFid, DeclFid);
  Edits:= TList<TRecipeEdit>.Create;
  Done := TList<Integer>.Create;
  try
    for var R in pSurface.Refs do
    begin
      if Done.Contains(R.Line) then Continue;
      Done.Add(R.Line);
      E:= Default(TRecipeEdit);
      E.Fid     := FromFid;
      E.Line    := R.Line;
      E.Replace := True;
      E.NewLines:= [TRegEx.Replace(LineOf(Lines, R.Line), '(?<![\w.])' + TRegEx.Escape(Name) + '\b',
        Result.PtrVar, [roIgnoreCase])];
      Edits.Add(E);
    end;
    if not AssignmentEdit(pSource.FileLines(DeclFid), DeclFid, Format('  %s := %s;', [Result.PtrVar, Name]), E) then
    begin
      pRefusal:= MakeRefusal('manual-edit', Name, DeclFid, 0, 'the declaring unit has no final `end.`');
      Exit(Default(TRecipeSteps));
    end;
    Edits.Add(E);
    Result.Edits:= Edits.ToArray;
  finally
    Done.Free;
    Edits.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  R2 -- member hand-over through an extracted interface
  --------------------------------------------------------------------------- }

const
  CMaxAncestorHops = 32;  { a heritage walk longer than this is a loop in the index }
  { IInterface roots whose _Release never frees the object / roots that count references }
  CSafeRoots      : array[0..1] of string = ('TComponent', 'TInterfacedPersistent');
  CRefCountedRoots: array[0..2] of string = ('TInterfacedObject', 'TAggregatedObject', 'TContainedObject');
  CIInterfaceMethods: array[0..2] of string = ('QueryInterface', '_AddRef', '_Release');
  CGuidGroups     : array[0..4] of Integer = (8, 4, 4, 4, 12);
  CSysUtilsUnit   = 'System.SysUtils';
  CRootClass      = 'TObject';

function SurfaceGuid(const pText: string): string;
var
  MD5: THashMD5;
  P  : Integer;
begin
  MD5:= THashMD5.Create;
  MD5.Update(TEncoding.UTF8.GetBytes(pText));
  var Hex:= UpperCase(MD5.HashAsString);
  var Parts: TArray<string>;
  SetLength(Parts, Length(CGuidGroups));
  P:= 1;
  for var I:= 0 to High(CGuidGroups) do
  begin
    Parts[I]:= Copy(Hex, P, CGuidGroups[I]);
    Inc(P, CGuidGroups[I]);
  end;
  Result:= '{' + string.Join('-', Parts) + '}';
end;

type
  { A class / interface symbol and the index that holds it. }
  TStoredType = record
    Sym  : TSymbol;
    Store: ISymbolStore;
  end;

  { The indexes R2 reads types from: the project first, then the platform library.
    A library type's ancestors are looked up in the library only. }
  TTypeIndex = record
    Project: ISymbolStore;
    Lib    : ISymbolStore;
    function Find(const pName: string; pLibOnly: Boolean; out pType: TStoredType): Boolean;
    function IsLib(const pType: TStoredType): Boolean;
    function IsInterfaceName(const pName: string; pLibOnly: Boolean): Boolean;
    function ParentOf(const pType: TStoredType): string;
    function ListsInterface(const pType: TStoredType): Boolean;
  end;

{ A type name without unit prefix and generic arguments. }
function BareTypeName(const pName: string): string;
begin
  Result:= Trim(pName);
  var Lt:= Result.IndexOf('<');
  if Lt >= 0 then Result:= Result.Substring(0, Lt);
  Result:= Trim(Result.Substring(Result.LastIndexOf('.') + 1));
end;

function UnitOfFile(const pPath: string): string;
begin
  Result:= ChangeFileExt(ExtractFileName(StringReplace(pPath, '/', '\', [rfReplaceAll])), '');
end;

{ symbols.heritage split at its top-level commas. }
function SplitHeritage(const pText: string): TArray<string>;
var
  L    : TList<string>;
  Depth: Integer;
  Start: Integer;
begin
  L:= TList<string>.Create;
  try
    Depth:= 0;
    Start:= 1;
    for var I:= 1 to Length(pText) do
      if pText[I] = '<' then Inc(Depth)
      else if pText[I] = '>' then Dec(Depth)
      else if (pText[I] = ',') and (Depth = 0) then
      begin
        L.Add(Trim(Copy(pText, Start, I - Start)));
        Start:= I + 1;
      end;
    var Last:= Trim(Copy(pText, Start, MaxInt));
    if Last <> '' then L.Add(Last);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ The widest class / interface row named pName in pStore (a forward declaration spans one line). }
function PickType(const pStore: ISymbolStore; const pName: string; var pType: TStoredType): Boolean;
var
  Best: Integer;
begin
  Result:= False;
  Best  := -1;
  if (pStore = nil) or (pName = '') then Exit;
  for var S in pStore.FindSymbolsByExactName(pName) do
    if (S.Kind in [skClass, skInterface]) and (S.EndLine - S.StartLine > Best) then
    begin
      Best       := S.EndLine - S.StartLine;
      pType.Sym  := S;
      pType.Store:= pStore;
      Result     := True;
    end;
end;

function TTypeIndex.Find(const pName: string; pLibOnly: Boolean; out pType: TStoredType): Boolean;
begin
  pType:= Default(TStoredType);
  var N:= BareTypeName(pName);
  Result:= ((not pLibOnly) and PickType(Project, N, pType)) or PickType(Lib, N, pType);
end;

function TTypeIndex.IsLib(const pType: TStoredType): Boolean;
begin
  Result:= (Lib <> nil) and (pType.Store = Lib);
end;

function TTypeIndex.IsInterfaceName(const pName: string; pLibOnly: Boolean): Boolean;
var
  T: TStoredType;
begin
  if Find(pName, pLibOnly, T) then Exit(T.Sym.Kind = skInterface);
  Result:= TRegEx.IsMatch(BareTypeName(pName), '^I[A-Z]');  { no index declares it: the naming convention }
end;

function TTypeIndex.ParentOf(const pType: TStoredType): string;
begin
  if (pType.Sym.Kind <> skClass) or SameText(pType.Sym.Name, CRootClass) then Exit('');
  var Parts:= SplitHeritage(pType.Sym.Heritage);
  Result:= if (Length(Parts) = 0) or IsInterfaceName(Parts[0], IsLib(pType)) then CRootClass else Parts[0];
end;

function TTypeIndex.ListsInterface(const pType: TStoredType): Boolean;
begin
  var Parts:= SplitHeritage(pType.Sym.Heritage);
  Result:= (Length(Parts) > 1) or ((Length(Parts) = 1) and IsInterfaceName(Parts[0], IsLib(pType)));
end;

{ The first ancestor of pStart (itself excluded) that is a CIInterfaceRoots class or lists
  an interface; False at TObject or at a name no index declares. }
function WalkToIInterface(const pIdx: TTypeIndex; const pStart: TStoredType; out pAncestor: string): Boolean;
var
  Next: TStoredType;
begin
  pAncestor:= '';
  var Cur:= pStart;
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    var P:= BareTypeName(pIdx.ParentOf(Cur));
    if (P = '') or SameText(P, CRootClass) then Break;
    if MatchText(P, CIInterfaceRoots) then
    begin
      pAncestor:= P;
      Break;
    end;
    if not pIdx.Find(P, pIdx.IsLib(Cur), Next) then Break;
    if pIdx.ListsInterface(Next) then
    begin
      pAncestor:= Next.Sym.Name;
      Break;
    end;
    Cur:= Next;
  end;
  Result:= pAncestor <> '';
end;

function AncestorImplementingIInterface(const pProject, pLibrary: ISymbolStore; const pClass: TSymbol;
  out pAncestor: string): Boolean;
var
  Idx  : TTypeIndex;
  Start: TStoredType;
begin
  Idx.Project:= pProject;
  Idx.Lib    := pLibrary;
  Start.Sym  := pClass;
  Start.Store:= pProject;
  Result:= WalkToIInterface(Idx, Start, pAncestor);
end;

{ Whether a static type implements IInterface: an interface, a CIInterfaceRoots class, a
  class that lists an interface, or one with such an ancestor. TObject and an unindexed
  name do not. }
function ImplementsIInterface(const pIdx: TTypeIndex; const pTypeName: string): Boolean;
var
  T  : TStoredType;
  Anc: string;
begin
  var N:= BareTypeName(pTypeName);
  if MatchText(N, CIInterfaceRoots) then Exit(True);
  if SameText(N, CRootClass) or not pIdx.Find(N, False, T) then Exit(False);
  Result:= (T.Sym.Kind = skInterface) or pIdx.ListsInterface(T) or WalkToIInterface(pIdx, T, Anc);
end;

{ '' when the class gets IInterface from TComponent or TInterfacedPersistent (neither frees
  the object on _Release); else why `as` / Supports could free it. }
function RefCountWhy(const pIdx: TTypeIndex; const pClass: TStoredType): string;
var
  Next: TStoredType;
begin
  var Cur:= pClass;
  var N  := Cur.Sym.Name;
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    if MatchText(N, CSafeRoots) then Exit('');
    if MatchText(N, CRefCountedRoots) then
      Exit(Format('`%s` descends from `%s`, which counts references: releasing the temporary interface ' +
        'of `as` / Supports would free the object', [pClass.Sym.Name, N]));
    N:= BareTypeName(pIdx.ParentOf(Cur));
    if (N = '') or SameText(N, CRootClass) then Break;
    if MatchText(N, CSafeRoots) or MatchText(N, CRefCountedRoots) then Continue;
    if not pIdx.Find(N, pIdx.IsLib(Cur), Next) then Break;
    Cur:= Next;
  end;
  Result:= Format('`%s` gets IInterface from neither TComponent nor TInterfacedPersistent: whether releasing ' +
    'the temporary interface of `as` / Supports frees the object is unknown', [pClass.Sym.Name]);
end;

{ Adds the member names (no params / locals) of pClass and every ancestor to pNames; False,
  with pStop, when the chain reaches a name no index declares. }
function ChainMembers(const pIdx: TTypeIndex; const pClass: TStoredType; pNames: TStringList;
  out pStop: string): Boolean;
var
  Next: TStoredType;
begin
  pStop := pClass.Sym.Name;
  Result:= False;
  var Cur:= pClass;
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    for var S in Cur.Store.FindAllChildSymbols(Cur.Sym.Id) do
      if not (S.Kind in [skParam, skLocalVar]) then pNames.Add(S.Name);
    var P:= pIdx.ParentOf(Cur);
    if P = '' then Exit(True);
    pStop:= BareTypeName(P);
    if not pIdx.Find(P, pIdx.IsLib(Cur), Next) then Break;
    Cur:= Next;
  end;
end;

{ The type (symbols.signature) of the field or property pName of pClass or an ancestor. }
function MemberTypeInChain(const pIdx: TTypeIndex; const pClass: TStoredType; const pName: string;
  out pType: string): Boolean;
var
  Next: TStoredType;
begin
  pType:= '';
  var Cur:= pClass;
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    var M:= Cur.Store.FindChildSymbolByName(Cur.Sym.Id, pName);
    if (M.Id > 0) and (M.Kind in [skField, skProperty]) then
    begin
      pType:= Trim(M.Signature);
      Break;
    end;
    if not pIdx.Find(pIdx.ParentOf(Cur), pIdx.IsLib(Cur), Next) then Break;
    Cur:= Next;
  end;
  Result:= pType <> '';
end;

// The code of a line without string literals and brace comments.
function PlainCode(const pLine: string): string;
begin
  Result:= TRegEx.Replace(TRegEx.Replace(BareCode(pLine), '''[^'']*''', ''''''), '\{[^}]*\}', ' ');
end;

{ The last line of the statement the `with ... do` at line pLine governs: a begin..end
  block, or one statement up to its `;` (an enclosing `end` also ends it). }
function WithBodyEnd(const pLines: TArray<string>; pLine: Integer): Integer;
var
  Depth : Integer;
  SeenDo: Boolean;
begin
  Depth := 0;
  SeenDo:= False;
  for var L:= pLine to Length(pLines) do
  begin
    var Code:= PlainCode(LineOf(pLines, L));
    if not SeenDo then
    begin
      var M:= TRegEx.Match(Code, '\bdo\b', [roIgnoreCase]);
      if not M.Success then Continue;
      SeenDo:= True;
      Code  := Code.Substring(M.Index + M.Length - 1);
    end;
    for var T in TRegEx.Matches(Code, '\b(begin|case|try|asm|end)\b|;', [roIgnoreCase]) do
      if T.Value = ';' then
      begin
        if Depth = 0 then Exit(L);
      end
      else if SameText(T.Value, 'end') then
      begin
        Dec(Depth);
        if Depth <= 0 then Exit(L);
      end
      else Inc(Depth);
  end;
  Result:= Length(pLines);
end;

// Where the getter bodies go in the class unit: after the `$R *.dfm` resource line when the
// unit has one, else after its implementation uses clause, else after `implementation`.
function BodyAnchor(const pLines: TArray<string>): Integer;
begin
  var Impl:= 0;
  for var L:= 1 to Length(pLines) do
    if SameText(BareCode(pLines[L - 1]), 'implementation') then
    begin
      Impl:= L;
      Break;
    end;
  if Impl = 0 then Exit(0);
  for var L:= Impl + 1 to Length(pLines) do
    if TRegEx.IsMatch(pLines[L - 1], '^\s*\{\$R\s+\*\.(dfm|fmx)\}', [roIgnoreCase]) then Exit(L);
  Result:= Impl;
  var L:= Impl + 1;
  while (L <= Length(pLines)) and (PlainCode(pLines[L - 1]) = '') do Inc(L);
  if (L > Length(pLines)) or not TRegEx.IsMatch(PlainCode(pLines[L - 1]), '^uses\b', [roIgnoreCase]) then Exit;
  while (L <= Length(pLines)) and not ContainsStr(PlainCode(pLines[L - 1]), ';') do Inc(L);
  if L <= Length(pLines) then Result:= L;
end;

type
  { One PlanMemberInterface run: the edge, the class, and the steps being built. }
  TMemberPlan = class  // dl:ok high-response@c843, god-class@c843 -- implementation-private one-shot planner of one edge; the response set is its check steps plus the store and RTL calls they make
  private
    FSource  : IEdgeSurfaceSource;
    FStore   : ISymbolStore;
    FIdx     : TTypeIndex;
    FSurface : TEdgeSurface;
    FFromFid : Int64;
    FClsFid  : Int64;
    FLines   : TArray<string>;
    FClsLines: TArray<string>;
    FCls     : TSymbol;
    FIface   : string;
    FMembers : TList<TSymbol>;
    FGetters : TList<string>;
    FReads   : TList<string>;  // per member: what its getter returns
    FEdits   : TList<TRecipeEdit>;
    FUses    : TList<string>;  // consumer implementation uses to add
    FLeafUses: TList<string>;
    FWithLines: TList<Integer>;
    FCastUsed: Boolean;
    FCastAnc : string;
    FRefusal : TRecipeRefusal;
    function Refuse(const pKind, pSymbol: string; pFid: Int64; pLine: Integer; const pReason: string): Boolean;
    function Stored(const pSym: TSymbol): TStoredType;
    function RefRefusal(const pR: TEdgeRef; out pKind, pWhat: string): Boolean;
    function CheckShape: Boolean;
    function CheckMembers: Boolean;
    function CheckClass: Boolean;
    function ConsumerSees(const pUnit: string): Boolean;
    function ReceiverType(const pX: string; pEnclosing: Int64; out pType: string): Boolean;
    function RewriteLine(pLine: Integer; pEnclosing: Int64; out pText: string): Boolean;
    function RewriteConsumer: Boolean;
    function CheckCastUnit: Boolean;
    function CheckWithBodies: Boolean;
    function LibUnitOf(const pIdent: string): string;
    function KnownUnitPrefix(const pSegments: TArray<string>; pCount: Integer): string;
    function LibDeclaresIn(const pIdent, pUnit: string): Boolean;
    function AddLeafUse(const pM: TSymbol; const pTypeName, pShown: string): Boolean;
    function AddNestedLeafUse(const pM: TSymbol; const pOuter, pShown: string): Boolean;
    function CheckCastExceptions: Boolean;
    function CollectLeafUses: Boolean;
    procedure AddEdit(pFid: Int64; pLine: Integer; pReplace: Boolean; const pLines: TArray<string>);
    procedure BuildClassEdits;
    function IfaceDecl(const pLeafUnit: string): TArray<string>;
  public
    constructor Create(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore; const pSurface: TEdgeSurface);
    destructor Destroy; override;
    function Run(const pLeafUnit: string; out pRefusal: TRecipeRefusal): TRecipeSteps;
  end;

constructor TMemberPlan.Create(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore;
  const pSurface: TEdgeSurface);
begin
  inherited Create;
  FSource     := pSource;
  FStore      := pSource.Store;
  FIdx.Project:= FStore;
  FIdx.Lib    := pLibrary;
  FSurface    := pSurface;
  FFromFid    := pSource.FidOfStem(pSurface.FromStem);
  FClsFid     := pSource.FidOfStem(pSurface.ToStem);
  FLines      := pSource.FileLines(FFromFid);
  FClsLines   := pSource.FileLines(FClsFid);
  FMembers    := TList<TSymbol>.Create;
  FGetters    := TList<string>.Create;
  FReads      := TList<string>.Create;
  FEdits      := TList<TRecipeEdit>.Create;
  FUses       := TList<string>.Create;
  FLeafUses   := TList<string>.Create;
  FWithLines  := TList<Integer>.Create;
end;

destructor TMemberPlan.Destroy;
begin
  FWithLines.Free;
  FLeafUses.Free;
  FUses.Free;
  FEdits.Free;
  FReads.Free;
  FGetters.Free;
  FMembers.Free;
  inherited Destroy;
end;

function TMemberPlan.Refuse(const pKind, pSymbol: string; pFid: Int64; pLine: Integer; const pReason: string): Boolean;
begin
  FRefusal:= MakeRefusal(pKind, pSymbol, pFid, pLine, pReason);
  Result  := False;
end;

function TMemberPlan.Stored(const pSym: TSymbol): TStoredType;
begin
  Result.Sym  := pSym;
  Result.Store:= FStore;
end;

{ Whether one ref of the edge has a shape the interface cannot carry: its kind and what it does. }
function TMemberPlan.RefRefusal(const pR: TEdgeRef; out pKind, pWhat: string): Boolean;
begin
  pKind:= '';
  pWhat:= '';
  var S:= if pR.SymbolId > 0 then FStore.GetSymbolById(pR.SymbolId) else Default(TSymbol);
  case pR.Kind of
    erTypeIs, erTypeAs, erMemberRead: Exit(False);
    erMemberWrite:
      begin
        pKind:= 'member-write';
        pWhat:= Format('writes `%s`; the interface carries reads only', [pR.Name]);
      end;
    erClassReceiver:
      if SameText(pR.Name, 'Create') or (FStore.FindChildSymbolByName(pR.SymbolId, pR.Name).Kind = skConstructor) then
      begin
        pKind:= 'construction';
        pWhat:= Format('constructs `%s`; an interface cannot create the object', [S.Name]);
      end
      else
      begin
        pKind:= 'class-method';
        pWhat:= Format('calls `%s` through the class `%s`; the interface carries field and property reads only',
          [pR.Name, S.Name]);
      end;
    erTypeDecl:
      begin
        pKind:= 'type-decl';
        pWhat:= Format('declares something of type `%s`, which would still need its unit', [pR.Name]);
      end;
    erTypeCast:
      begin
        pKind:= 'type-cast';
        pWhat:= Format('casts to `%s`, which would still need its unit', [pR.Name]);
      end;
    erCall:
      if (S.Kind = skClass) and SameText(pR.Name, S.Name) then
      begin
        pKind:= 'type-cast';
        pWhat:= Format('casts to `%s`, which would still need its unit', [pR.Name]);
      end
      else if (S.Kind = skClass) or ((S.ParentId > 0) and (FStore.GetSymbolById(S.ParentId).Kind in [skClass, skRecord])) then
      begin
        pKind:= 'class-method';
        pWhat:= Format('calls the method `%s`; the interface carries field and property reads only', [pR.Name]);
      end
      else
      begin
        pKind:= 'other-ref';
        pWhat:= Format('calls the routine `%s`, which no interface of a class carries', [pR.Name]);
      end;
  else
    if S.Kind = skClass then
    begin
      pKind:= 'class-ref';
      pWhat:= Format('passes the class `%s` as a value', [S.Name]);
    end
    else
    begin
      pKind:= 'other-ref';
      pWhat:= Format('uses `%s`, which is no member of a class', [pR.Name]);
    end;
  end;
  Result:= True;
end;

{ Every ref is an `is` / `as` operand or a member read, on one class; no `B.X` in A. }
function TMemberPlan.CheckShape: Boolean;
var
  Kind, What, BestKind, BestWhat, Member: string;
  Best: TEdgeRef;
begin
  Best:= Default(TEdgeRef);
  for var R in FSurface.Refs do
    if (FCls.Id = 0) and (R.Kind in [erTypeIs, erTypeAs]) and (R.SymbolId > 0) then FCls:= FStore.GetSymbolById(R.SymbolId);
  { the first offending line; on one line, what is done through the class (a call, a
    construction) names it rather than the plain read of the class name it comes with }
  for var R in FSurface.Refs do
  begin
    if not RefRefusal(R, Kind, What) then Continue;
    var Earlier := (Best.Line = 0) or (R.Line < Best.Line);
    var Stronger:= (R.Line = Best.Line) and (Best.Kind = erOther) and (R.Kind <> erOther);
    if Earlier or Stronger then
    begin
      Best    := R;
      BestKind:= Kind;
      BestWhat:= What;
    end;
  end;
  if Best.Line > 0 then
    Exit(Refuse(BestKind, Best.Name, FFromFid, Best.Line, Format('line %d %s (`%s`)', [Best.Line, BestWhat,
      Best.LineText])));
  if Length(FSurface.ClassNames) <> 1 then
    Exit(Refuse('multiple-classes', string.Join(', ', FSurface.ClassNames), FFromFid, 0,
      Format('the edge names %d classes (%s); one interface hands over the members of one class',
      [Length(FSurface.ClassNames), string.Join(', ', FSurface.ClassNames)])));
  if (FCls.Id = 0) or (FCls.Kind <> skClass) or (FCls.FileId <> FClsFid) then
    Exit(Refuse('other-ref', FSurface.ClassNames[0], FFromFid, 0, Format('no `is` / `as` operand of the edge ' +
      'binds to the class `%s` of `%s`', [FSurface.ClassNames[0], FSurface.ToStem])));
  var Q:= UnitQualifiedLine(FSource, FLines, UnitOfFile(FStore.GetFilePath(FClsFid)), Member);
  if Q > 0 then
    Exit(Refuse('qualified-ref', Member, FFromFid, Q, Format('line %d names `%s` qualified by its unit (`%s`); ' +
      'that use keeps needing the uses entry the cut removes', [Q, Member, Trim(LineOf(FLines, Q))])));
  Result:= True;
end;

{ Each member read is a field or a non-indexed property of the class itself, and the class
  has no `Get<Member>` yet. Members are kept in declaration order. }
function TMemberPlan.CheckMembers: Boolean;
var
  Ids: TList<Int64>;
begin
  Ids:= TList<Int64>.Create;
  try
    for var R in FSurface.Refs do
      if (R.Kind = erMemberRead) and not Ids.Contains(R.SymbolId) then
      begin
        Ids.Add(R.SymbolId);
        var M:= FStore.GetSymbolById(R.SymbolId);
        if M.Kind in [skMethod, skFunction, skProcedure] then
          Exit(Refuse('class-method', M.Name, FFromFid, R.Line, Format('line %d calls the method `%s` of `%s` ' +
            '(`%s`); the interface carries field and property reads only', [R.Line, M.Name, FCls.Name, R.LineText])));
        if M.ParentId <> FCls.Id then
          Exit(Refuse('member-unsupported', M.Name, FFromFid, R.Line, Format('line %d reads `%s`, which is not ' +
            'declared in `%s` itself', [R.Line, M.Name, FCls.Name])));
        var Sig:= Trim(M.Signature);
        { an indexed property keeps only its element type in symbols.signature: read the declaration }
        var Indexed:= (M.Kind = skProperty) and TRegEx.IsMatch(BareCode(LineOf(FClsLines, M.StartLine)),
          '\bproperty\s+' + TRegEx.Escape(M.Name) + '\s*\[', [roIgnoreCase]);
        if not (M.Kind in [skField, skProperty]) or Indexed or (Sig = '') or
          (Sig.IndexOfAny(['[', ']', ':', '(', ')', ';']) >= 0) then
          Exit(Refuse('member-unsupported', M.Name, FFromFid, R.Line, Format('`%s.%s` is not a field or a ' +
            'non-indexed property with a stored type', [FCls.Name, M.Name])));
        var Dup:= FStore.FindChildSymbolByName(FCls.Id, 'Get' + M.Name);
        if Dup.Id > 0 then
          Exit(Refuse('duplicate-identifier', Dup.Name, FClsFid, Dup.StartLine, Format('`%s` already declares ' +
            '`%s` (line %d), the getter the interface needs', [FCls.Name, Dup.Name, Dup.StartLine])));
        FMembers.Add(M);
      end;
  finally
    Ids.Free;
  end;
  FMembers.Sort(TComparer<TSymbol>.Construct(
    function(const pLeft, pRight: TSymbol): Integer
    begin
      Result:= pLeft.StartLine - pRight.StartLine;
    end));
  for var M in FMembers do
  begin
    FGetters.Add('Get' + M.Name);
    var Read:= M.Name;
    if M.Kind = skProperty then
    begin
      var Parts: TArray<string>:= nil;
      for var L:= M.StartLine to Max(M.StartLine, M.EndLine) do Parts:= Parts + [BareCode(LineOf(FClsLines, L))];
      var RM:= TRegEx.Match(string.Join(' ', Parts), '\bread\s+([A-Za-z_][\w.]*)', [roIgnoreCase]);
      if RM.Success then Read:= RM.Groups[1].Value;
    end;
    FReads.Add(Read);
  end;
  Result:= True;
end;

{ The class: heritage on its declaration line, an `end;` line, an IInterface ancestor and
  no reference counting on the way. }
function TMemberPlan.CheckClass: Boolean;
begin
  if not SameText(FCls.Section, 'interface') or
    not TRegEx.IsMatch(LineOf(FClsLines, FCls.StartLine), '=\s*class\b[^(;]*\([^)]*\)', [roIgnoreCase]) then
    Exit(Refuse('manual-edit', FCls.Name, FClsFid, FCls.StartLine, Format('the heritage of `%s` is not on its ' +
      'declaration line %d in the interface section', [FCls.Name, FCls.StartLine])));
  if (FCls.EndLine <= FCls.StartLine) or not TRegEx.IsMatch(BareCode(LineOf(FClsLines, FCls.EndLine)), '^end\b',
    [roIgnoreCase]) then
    Exit(Refuse('manual-edit', FCls.Name, FClsFid, FCls.EndLine, Format('the declaration of `%s` does not end ' +
      'with an `end;` line', [FCls.Name])));
  if not AncestorImplementingIInterface(FStore, FIdx.Lib, FCls, FCastAnc) then
    Exit(Refuse('no-iinterface', FCls.Name, FClsFid, FCls.StartLine, Format('no ancestor of `%s` implements ' +
      'IInterface (or the ancestry leaves the indexes given): it cannot implement an interface', [FCls.Name])));
  var Why:= RefCountWhy(FIdx, Stored(FCls));
  if Why <> '' then Exit(Refuse('ref-counted', FCls.Name, FClsFid, FCls.StartLine, Why));
  Result:= True;
end;

function TMemberPlan.ConsumerSees(const pUnit: string): Boolean;
begin
  for var U in FStore.GetUnitUsesForFile(FFromFid) do
    if SameText(U.UnitName, pUnit) or EndsText('.' + U.UnitName, pUnit) then Exit(True);
  Result:= FUses.Contains(pUnit);
end;

{ The static type of the receiver pX: Self, a parameter or local of the enclosing routine,
  else a field / property of the enclosing class or an ancestor. }
function TMemberPlan.ReceiverType(const pX: string; pEnclosing: Int64; out pType: string): Boolean;
begin
  pType:= '';
  var Cur:= if pEnclosing > 0 then FStore.GetSymbolById(pEnclosing) else Default(TSymbol);
  var IsSelf:= SameText(pX, 'Self');
  while (Cur.Id > 0) and not (Cur.Kind in [skClass, skRecord, skUnit, skProgram, skPackage]) do
  begin
    var L:= FStore.FindChildSymbolByName(Cur.Id, pX);
    if not IsSelf and (L.Id > 0) and (L.Kind in [skParam, skLocalVar]) then
    begin
      pType:= Trim(L.Signature);
      Exit(TRegEx.IsMatch(pType, '^[A-Za-z_][\w.]*$'));
    end;
    Cur:= if Cur.ParentId > 0 then FStore.GetSymbolById(Cur.ParentId) else Default(TSymbol);
  end;
  if (Cur.Id = 0) or (Cur.Kind <> skClass) then Exit(False);
  if IsSelf then
  begin
    pType:= Cur.Name;
    Exit(True);
  end;
  Result:= MemberTypeInChain(FIdx, Stored(Cur), pX, pType) and TRegEx.IsMatch(pType, '^[A-Za-z_][\w.]*$');
end;

{ One consumer line with every `X is TClass` / `X as TClass` rewritten to the interface. }
function TMemberPlan.RewriteLine(pLine: Integer; pEnclosing: Int64; out pText: string): Boolean;
var
  Ty: string;
begin
  var C:= TRegEx.Escape(FCls.Name);
  pText:= LineOf(FLines, pLine);
  pText:= TRegEx.Replace(pText, '\(\s*([A-Za-z_][\w.]*)\s+is\s+' + C + '\s*\)', 'Supports($1, ' + FIface + ')', [roIgnoreCase]);
  pText:= TRegEx.Replace(pText, '(?<![\w.)\]])([A-Za-z_][\w.]*)\s+is\s+' + C + '\b', 'Supports($1, ' + FIface + ')',
    [roIgnoreCase]);
  if ContainsStr(pText, 'Supports(') and not ConsumerSees(CSysUtilsUnit) then FUses.Add(CSysUtilsUnit);
  while True do
  begin
    var M:= TRegEx.Match(pText, '(?<![\w.)\]])([A-Za-z_]\w*)\s+as\s+' + C + '\b', [roIgnoreCase]);
    if not M.Success then Break;
    var X:= M.Groups[1].Value;
    if not ReceiverType(X, pEnclosing, Ty) then
      Exit(Refuse('receiver-unknown', X, FFromFid, pLine, Format('line %d: the static type of `%s` in `%s as %s` ' +
        'is not that of Self, a parameter, a local, or a field or property of the class', [pLine, X, X, FCls.Name])));
    var Repl:= X + ' as ' + FIface;
    if not ImplementsIInterface(FIdx, Ty) then
    begin
      Repl     := Format('%s(%s) as %s', [FCastAnc, X, FIface]);
      FCastUsed:= True;
    end;
    pText:= Copy(pText, 1, M.Index - 1) + Repl + Copy(pText, M.Index + M.Length, MaxInt);
  end;
  if TRegEx.IsMatch(PlainCode(pText), '\b' + C + '\b', [roIgnoreCase]) then
    Exit(Refuse('receiver-unknown', FCls.Name, FFromFid, pLine, Format('line %d still names `%s` after the rewrite ' +
      '(`%s`): an `is` / `as` operand that is not a plain name', [pLine, FCls.Name, Trim(pText)])));
  Result:= True;
end;

function TMemberPlan.RewriteConsumer: Boolean;
var
  Done: TList<Integer>;
  Text: string;
begin
  Done:= TList<Integer>.Create;
  try
    for var R in FSurface.Refs do
    begin
      if not (R.Kind in [erTypeIs, erTypeAs]) or Done.Contains(R.Line) then Continue;
      Done.Add(R.Line);
      if not RewriteLine(R.Line, R.EnclosingId, Text) then Exit(False);
      AddEdit(FFromFid, R.Line, True, [Text]);
      if TRegEx.IsMatch(PlainCode(LineOf(FLines, R.Line)), '\bwith\b.*\bas\s+' + TRegEx.Escape(FCls.Name) + '\b',
        [roIgnoreCase]) then FWithLines.Add(R.Line);
    end;
  finally
    Done.Free;
  end;
  Result:= CheckCastUnit;
end;

{ A cast ancestor must be visible in the consumer without the class unit. }
function TMemberPlan.CheckCastUnit: Boolean;
var
  T       : TStoredType;
  DeclUnit: string;
begin
  Result:= True;
  if not FCastUsed then
  begin
    FCastAnc:= '';
    Exit;
  end;
  if not FIdx.Find(FCastAnc, False, T) then
    Exit(Refuse('cast-unseen', FCastAnc, FFromFid, 0, Format('no index given declares `%s`, the ancestor of ' +
      '`%s` a receiver is cast through (pass --library-db)', [FCastAnc, FCls.Name])));
  DeclUnit:= UnitOfFile(T.Store.GetFilePath(T.Sym.FileId));
  if not FIdx.IsLib(T) then
  begin
    var Stem:= LowerCase(DeclUnit);
    if Stem = FSurface.FromStem then Exit;
    if (Stem = FSurface.ToStem) or (FSource.IsSccStem(Stem) and not ConsumerSees(DeclUnit)) then
      Exit(Refuse('cast-unseen', FCastAnc, FFromFid, 0, Format('`%s`, the ancestor a receiver is cast through, ' +
        'is declared in `%s`, a unit of this cycle', [FCastAnc, DeclUnit])));
  end;
  if not ConsumerSees(DeclUnit) then FUses.Add(DeclUnit);
end;

{ Fix round 1: `as I` raises EIntfCastError where `as TClass` raised EInvalidCast. When the
  consumer handles EInvalidCast anywhere, every `X as TClass` must follow an `X is TClass`
  guard of its routine (the guard becomes Supports, so the cast cannot fail there). }
function TMemberPlan.CheckCastExceptions: Boolean;
begin
  Result:= True;
  var Handles:= False;
  for var L in FLines do
    if TRegEx.IsMatch(PlainCode(L), '\bEInvalidCast\b', [roIgnoreCase]) then Handles:= True;
  if not Handles then Exit;
  var C:= TRegEx.Escape(FCls.Name);
  for var R in FSurface.Refs do
  begin
    if R.Kind <> erTypeAs then Continue;
    for var M in TRegEx.Matches(R.LineText, '(?<![\w.)\]])([A-Za-z_]\w*)\s+as\s+' + C + '\b', [roIgnoreCase]) do
    begin
      var Guarded:= False;
      for var G in FSurface.Refs do
      begin
        var Before:= (G.Kind = erTypeIs) and (G.EnclosingId = R.EnclosingId) and (G.Line < R.Line);
        if Before and TRegEx.IsMatch(G.LineText, '\b' + TRegEx.Escape(M.Groups[1].Value) + '\s+is\s+' + C + '\b',
          [roIgnoreCase]) then Guarded:= True;
      end;
      if not Guarded then
        Exit(Refuse('exception-semantics', FCls.Name, FFromFid, R.Line, Format('line %d casts with `as %s` without ' +
          'an `is` guard, and `%s` handles EInvalidCast: a failed `as %s` raises EIntfCastError instead', [R.Line,
          FCls.Name, UnitOfFile(FStore.GetFilePath(FFromFid)), FIface])));
    end;
  end;
end;
{ No name inside a `with X as TClass do` body may change its binding when the interface
  replaces the class: a member of the class chain the interface does not carry, a getter
  name, an IInterface method. }
function TMemberPlan.CheckWithBodies: Boolean;
var
  Names: TStringList;
  Stop : string;
begin
  Result:= True;
  if FWithLines.Count = 0 then Exit;
  Names:= TStringList.Create(dupIgnore, True, False);
  try
    if not ChainMembers(FIdx, Stored(FCls), Names, Stop) then
      Exit(Refuse('ancestry-unknown', Stop, FClsFid, FCls.StartLine, Format('the ancestry of `%s` stops at ' +
        '`%s`, which no index given declares: what a `with` body binds to it cannot be checked (pass --library-db)',
        [FCls.Name, Stop])));
    Names.AddStrings(FGetters.ToArray);
    Names.AddStrings(CIInterfaceMethods);
    for var M in FMembers do
      if Names.IndexOf(M.Name) >= 0 then Names.Delete(Names.IndexOf(M.Name));
    var Refs:= FStore.GetReferencesFromFile(FFromFid);
    for var W in FWithLines do
    begin
      var DoAt:= TRegEx.Match(LineOf(FLines, W), '\bdo\b', [roIgnoreCase]);
      var Last:= WithBodyEnd(FLines, W);
      for var R in Refs do
      begin
        { a bare name of the body; the `with` expression itself (before `do`) is outside it }
        var InBody:= (R.StartLine >= W) and (R.StartLine <= Last) and (R.ReceiverText = '');
        var InHead:= (R.StartLine = W) and DoAt.Success and (R.StartCol < DoAt.Index);
        if InBody and not InHead and not MatchText(R.Kind, ['type_use', 'member-access']) and
          (Names.IndexOf(R.NameText) >= 0) then
          Exit(Refuse('with-member', R.NameText, FFromFid, R.StartLine, Format('inside `with ... as %s do` ' +
            '(line %d), `%s` at line %d names a member of `%s` or its ancestors that the interface does not ' +
            'carry: after the rewrite it would bind to something else', [FCls.Name, W, R.NameText, R.StartLine,
            FCls.Name])));
      end;
    end;
  finally
    Names.Free;
  end;
end;

{ The uses entry of the class unit's interface section that a library type pIdent binds
  to (the last that declares it); '' when none does. }
function TMemberPlan.LibUnitOf(const pIdent: string): string;
var
  Units: TList<string>;
begin
  Result:= '';
  if FIdx.Lib = nil then Exit;
  Units:= TList<string>.Create;
  try
    for var S in FIdx.Lib.FindSymbolsByExactName(pIdent) do
      if S.Kind in [skClass, skInterface, skRecord, skEnum, skTypeAlias] then
        Units.Add(UnitOfFile(FIdx.Lib.GetFilePath(S.FileId)));
    var Entries:= FStore.GetUnitUsesForFile(FClsFid);
    for var I:= High(Entries) downto 0 do
      if Entries[I].Section = uusInterface then
        for var U in Units do
          if SameText(U, Entries[I].UnitName) or EndsText('.' + Entries[I].UnitName, U) then
            Exit(Entries[I].UnitName);
  finally
    Units.Free;
  end;
end;

{ Whether the platform library declares pIdent in the unit pUnit (a unit written in full, as
  `System.Classes.TStrings` does, though the class unit's uses names it by a unit-scope short name). }
function TMemberPlan.LibDeclaresIn(const pIdent, pUnit: string): Boolean;
begin
  Result:= False;
  if FIdx.Lib = nil then Exit;
  for var S in FIdx.Lib.FindSymbolsByExactName(pIdent) do
    if SameText(UnitOfFile(FIdx.Lib.GetFilePath(S.FileId)), pUnit) then Exit(True);
end;

{ The unit a dotted prefix of a type name names, walking the prefixes from the LONGEST to the shortest
  (`A.B.C` then `A.B` then `A`); the first that is a unit wins and the rest is a nested type inside it.
  A prefix is a unit when it is a project unit stem, a uses entry of the class unit, a uses entry
  under a default unit-scope namespace (`System.` + `Classes`), or the library declares pNext in it.
  pNext is the segment after the prefix. '' when no prefix is a unit (the prefix is the outer type of
  a nested type, or unresolvable). The bare unit `System` counts only as the whole prefix. }
function TMemberPlan.KnownUnitPrefix(const pSegments: TArray<string>; pCount: Integer): string;
begin
  for var N:= pCount downto 1 do
  begin
    var P:= string.Join('.', Copy(pSegments, 0, N));
    var Next:= pSegments[N];
    if ((N = pCount) and SameText(P, 'System')) or (FSource.FidOfStem(LowerCase(P)) > 0) then Exit(P);
    for var U in FStore.GetUnitUsesForFile(FClsFid) do
    begin
      if SameText(U.UnitName, P) then Exit(P);
      for var NS in CUnitScopeNames do
        if SameText(NS + '.' + U.UnitName, P) then Exit(P);
    end;
    if LibDeclaresIn(Next, P) then Exit(P);
  end;
  Result:= '';
end;

{ The leaf uses entry of a nested type pShown = `<pOuter>.<Inner>`: the unit declaring its
  outer type; `member-unsupported` when no index resolves that outer type. }
function TMemberPlan.AddNestedLeafUse(const pM: TSymbol; const pOuter, pShown: string): Boolean;
begin
  Result:= AddLeafUse(pM, pOuter, pShown);
  if not Result and (FRefusal.Kind = 'type-unresolved') then
    Result:= Refuse('member-unsupported', pShown, FClsFid, pM.StartLine, Format('`%s`, the type of `%s.%s`, is a ' +
      'nested type whose outer type `%s` no index given resolves', [pShown, FCls.Name, pM.Name, pOuter]));
end;

{ The leaf uses entry for one type name of a member's signature. pShown is the name as the
  signature writes it (a nested `TOuter.TInner` is resolved through its outer type). }
function TMemberPlan.AddLeafUse(const pM: TSymbol; const pTypeName, pShown: string): Boolean;
var
  Owner: TSymbol;
  Stem : string;
  Entry: string;
begin
  var Dot  := pTypeName.LastIndexOf('.');
  var Ident:= pTypeName.Substring(Dot + 1);
  var Prefix:= if Dot > 0 then pTypeName.Substring(0, Dot) else '';
  { fix round 1: `TOuter.TInner` -- the leaf needs the unit that declares TOuter, never `uses TOuter` }
  { T6-follow: the LONGEST dotted prefix that is a known unit wins (`System.Classes.TStrings`), before the nested path }
  var UnitPart:= '';
  if Prefix <> '' then
  begin
    var Segs:= pTypeName.Split(['.']);
    UnitPart:= KnownUnitPrefix(Segs, Length(Segs) - 1);
    if UnitPart = '' then
    begin
      if ContainsText(CUnitScopeRoots, ' ' + Segs[0] + ' ') then
        Exit(Refuse('unresolved-qualified-type', pShown, FClsFid, pM.StartLine, Format('`%s`, the type of `%s.%s`, ' +
          'is written with a unit-scope prefix that names no unit this plan can find (pass --library-db, or add the unit to ' +
          'the uses clause)', [pShown, FCls.Name, pM.Name])));
      Exit(AddNestedLeafUse(pM, Prefix, pShown));
    end;
  end;
  if (Prefix = '') and (ContainsText(CNotTypeWords, ' ' + Ident + ' ') or ContainsText(CBuiltinTypes, ' ' + Ident + ' ')) then
    Exit(True);
  Stem:= '';
  if UnitPart <> '' then Stem:= LowerCase(UnitPart)
  else if not FSource.BindName(FClsFid, pM.StartLine, Ident, Owner, Stem) then Stem:= '';
  if (Stem <> '') and FSource.IsSccStem(Stem) then
    Exit(Refuse('leaf-uses-cycle', pShown, FClsFid, pM.StartLine, Format('`%s`, the type of `%s.%s`, is declared ' +
      'in `%s`, a unit of this cycle: the leaf cannot use it', [pShown, FCls.Name, pM.Name, Stem])));
  if UnitPart <> '' then Entry:= UnitPart
  else if Stem <> '' then Entry:= UnitOfFile(FStore.GetFilePath(FSource.FidOfStem(Stem)))
  else Entry:= LibUnitOf(Ident);
  if Entry = '' then
    Exit(Refuse('type-unresolved', pShown, FClsFid, pM.StartLine, Format('no index given tells which unit ' +
      'declares `%s`, the type of `%s.%s` (pass --library-db)', [pShown, FCls.Name, pM.Name])));
  if not FLeafUses.Contains(Entry) then FLeafUses.Add(Entry);
  Result:= True;
end;
function TMemberPlan.CollectLeafUses: Boolean;
begin
  for var M in FMembers do
    for var T in TRegEx.Matches(M.Signature, '[A-Za-z_][A-Za-z0-9_.]*') do
      if not AddLeafUse(M, T.Value, T.Value) then Exit(False);
  Result:= True;
end;

procedure TMemberPlan.AddEdit(pFid: Int64; pLine: Integer; pReplace: Boolean; const pLines: TArray<string>);
var
  E: TRecipeEdit;
begin
  E.Fid     := pFid;
  E.Line    := pLine;
  E.Replace := pReplace;
  E.NewLines:= pLines;
  FEdits.Add(E);
end;

{ The class unit: the interface appended to the heritage, the getter declarations before
  the class's `end;`, the getter bodies at BodyAnchor. }
procedure TMemberPlan.BuildClassEdits;
var
  Decls : TList<string>;
  Bodies: TList<string>;
begin
  var Head:= LineOf(FClsLines, FCls.StartLine);
  var M:= TRegEx.Match(Head, '(=\s*class\b[^(;]*\([^)]*)\)', [roIgnoreCase]);
  AddEdit(FClsFid, FCls.StartLine, True, [Copy(Head, 1, M.Index - 1) + M.Groups[1].Value + ', ' + FIface + ')' +
    Copy(Head, M.Index + M.Length, MaxInt)]);
  var Prev:= LineOf(FClsLines, FCls.EndLine - 1);
  var Indent:= if Trim(Prev) <> '' then Copy(Prev, 1, Length(Prev) - Length(TrimLeft(Prev)))
    else Copy(Head, 1, Length(Head) - Length(TrimLeft(Head))) + '    ';
  Decls := TList<string>.Create;
  Bodies:= TList<string>.Create;
  try
    for var I:= 0 to FMembers.Count - 1 do
    begin
      var Ty:= Trim(FMembers[I].Signature);
      Decls.Add(Format('%s/// <summary>%s: returns %s (cycles --plan, member hand-over).</summary>', [Indent, FIface,
        FMembers[I].Name]));
      Decls.Add(Format('%sfunction %s: %s;', [Indent, FGetters[I], Ty]));
      Bodies.Add('');
      Bodies.Add(Format('function %s.%s: %s;', [FCls.Name, FGetters[I], Ty]));
      Bodies.Add('begin');
      Bodies.Add(Format('  Result := %s;', [FReads[I]]));
      Bodies.Add('end;');
    end;
    AddEdit(FClsFid, FCls.EndLine - 1, False, Decls.ToArray);
    AddEdit(FClsFid, BodyAnchor(FClsLines), False, Bodies.ToArray);
  finally
    Bodies.Free;
    Decls.Free;
  end;
end;

function TMemberPlan.IfaceDecl(const pLeafUnit: string): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    L.Add(Format('  /// <summary>The surface of <c>%s</c> that <c>%s</c> uses.</summary>', [FCls.Name,
      UnitOfFile(FStore.GetFilePath(FFromFid))]));
    L.Add(Format('  %s = interface', [FIface]));
    L.Add(Format('    [''%s'']', [SurfaceGuid(pLeafUnit + '.' + FIface)]));
    for var I:= 0 to FMembers.Count - 1 do
      L.Add(Format('    function %s: %s;', [FGetters[I], Trim(FMembers[I].Signature)]));
    for var I:= 0 to FMembers.Count - 1 do
      L.Add(Format('    property %s: %s read %s;', [FMembers[I].Name, Trim(FMembers[I].Signature), FGetters[I]]));
    L.Add('  end;');
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TMemberPlan.Run(const pLeafUnit: string; out pRefusal: TRecipeRefusal): TRecipeSteps;
begin
  Result  := Default(TRecipeSteps);
  FRefusal:= Default(TRecipeRefusal);
  var Ok:= (FFromFid > 0) and (FClsFid > 0) and CheckShape;
  if Ok then
  begin
    FIface:= 'I' + (if (Length(FCls.Name) > 1) and (UpCase(FCls.Name[1]) = 'T') then Copy(FCls.Name, 2, MaxInt)
      else FCls.Name) + 'Surface';
    Ok:= CheckMembers and CheckClass and RewriteConsumer;
    Ok:= Ok and CheckCastExceptions and CheckWithBodies and CollectLeafUses;
  end;
  pRefusal:= FRefusal;
  if not Ok then
  begin
    if pRefusal.Kind = '' then pRefusal:= MakeRefusal('manual-edit', '', FFromFid, 0, 'the edge cannot be read');
    Exit;
  end;
  BuildClassEdits;
  Result.Recipe       := crMemberInterface;
  Result.DeclStem     := FSurface.ToStem;
  Result.ConsumerFid  := FFromFid;
  Result.ClassTypeName:= FCls.Name;
  Result.ClassId      := FCls.Id;
  Result.IfaceName    := FIface;
  Result.IfaceGuid    := SurfaceGuid(pLeafUnit + '.' + FIface);
  Result.IfaceDecl    := IfaceDecl(pLeafUnit);
  Result.LeafUses     := FLeafUses.ToArray;
  Result.ConsumerUses := FUses.ToArray;
  Result.CastAncestor := FCastAnc;
  Result.Edits        := FEdits.ToArray;
  for var M in FMembers do Result.MemberSigs:= Result.MemberSigs + [M.Name + ': ' + Trim(M.Signature)];
end;

function PlanMemberInterface(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore;
  const pSurface: TEdgeSurface; const pLeafUnit: string; out pRefusal: TRecipeRefusal): TRecipeSteps;
var
  P: TMemberPlan;
begin
  P:= TMemberPlan.Create(pSource, pLibrary, pSurface);
  try
    Result:= P.Run(pLeafUnit, pRefusal);
  finally
    P.Free;
  end;
end;

end.
