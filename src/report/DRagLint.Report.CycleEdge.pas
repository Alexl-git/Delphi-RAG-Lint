unit DRagLint.Report.CycleEdge;

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
    /// call through it on that line -- the `FindMDIChildForFolder(TfrmX, ...)` shape).</summary>
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
  /// procedural variable (PlanRoutineInversion); crMemberInterface = R2 (Task 6).</remarks>
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

  /// <summary>What recipe R1 (routine-call inversion) does to one edge, as data the
  /// planner maps onto its leaf machinery and file edits.</summary>
  /// <remarks>The leaf's new unit, its .dpr / .dproj registration and every uses-clause
  /// edit are NOT here: the planner derives them (UntangleCatalog leaf, Task 3a lexer
  /// edits) from LeafStem / DeclStem / ConsumerFid.</remarks>
  TRecipeSteps = record
    /// <summary>crRoutineInversion when filled; crNone otherwise.</summary>
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
    /// <summary>The call-site replacements (consumer) and the initialization assignment
    /// (declaring unit).</summary>
    Edits: TArray<TRecipeEdit>;
  end;

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

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.RegularExpressions, System.Math,
  System.Generics.Collections;

const
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
    if SameText(R.Kind, 'member-access') then Continue;  { the companion row of a call }
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

end.
