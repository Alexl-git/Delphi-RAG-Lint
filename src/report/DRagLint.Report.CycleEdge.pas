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
  /// <remarks>
  /// erTypeIs / erTypeAs / erTypeCast / erTypeDecl split refs.kind
  /// 'type_use' by the line text; erClassReceiver is a call through a class of B
  /// (`TFoo.Create`, `TFoo.CreateForFolder`); erMemberRead is a member of a type of
  /// B read through an instance; erMemberWrite is any write to a variable or member
  /// of B; erOther is everything else bound to B (a plain read, a class name passed
  /// as a value).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.ClassifyTypeUse (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TSurfaceBuilder.AddRef (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TSurfaceBuilder.TakeBareRef (DRagLint.Report.CycleEdge.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEdgeRefKind = (erCall, erTypeIs, erTypeAs, erTypeCast, erTypeDecl, erClassReceiver,
                  erMemberRead, erMemberWrite, erOther);

  /// <summary>One reference of unit A that binds to unit B.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Report.CycleEdge.CallRefusal (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.CarryUse (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.CheckShape (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TSurfaceBuilder.AddRef (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.TakeCtor (DRagLint.Report.CyclePlan.pas) (+16 more)</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge, DRagLint.Report.CyclePlan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas) ?, DRagLint.Report.CycleEdge.SignatureTypes (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.SigTypesOutsideScc (DRagLint.Report.CycleEdge.pas) ?</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSigType = record
    /// <summary>The identifier as written in the signature (a dotted name keeps its unit prefix).</summary>
    Name: string;
    /// <summary>Lower-case stem of the unit that declares it; '' when no index row resolves it.</summary>
    DeclStem: string;
    /// <summary>True when DeclStem is a unit of the circular group.</summary>
    InScc: Boolean;
  end;

  /// <summary>Everything unit FromStem takes from unit ToStem, as index facts.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas) ?, DRagLint.Report.CycleEdge.BuildEdgeSurface (DRagLint.Report.CycleEdge.pas) ?, DRagLint.Report.CycleEdge.EdgeSurfaceToJson (DRagLint.Report.CycleEdge.pas) ?, DRagLint.Report.CycleEdge.TSurfaceBuilder.Create (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TSurfaceBuilder.Run (DRagLint.Report.CycleEdge.pas) ? (+15 more)</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge, DRagLint.Report.CyclePlan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
    /// <summary>Plan B3: symbols.id of every top-level routine of B the edge binds, in the order of
    /// its first reference; empty when it binds none. Set whatever else the edge binds.</summary>
    RoutineIds: TArray<Int64>;
    /// <summary>R1 (lane cyc4): the globals of ToStem that the consumer names qualified (`ToUnit.G`) and
    /// that move into the leaf; the plan rewrites that text to `Leaf.G`, so it is no `qualified-ref`
    /// refusal. Filled by the planner, empty otherwise.</summary>
    QualifiedMoved: TArray<string>;
  end;

  /// <summary>The index access BuildEdgeSurface needs from the cycle planner.</summary>
  /// <remarks>
  /// Implemented by the planner of DRagLint.Report.CyclePlan, which keeps
  /// its own lifetime (not reference counted). All stems are lower-case unit stems.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.BuildEdgeSurface (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PickExistingLeaf (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.SignatureTypes (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TSurfaceBuilder.Create (DRagLint.Report.CycleEdge.pas) (+14 more)</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge, DRagLint.Report.CyclePlan</para>
  /// <para>Implemented by: TCyclePlanner</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  IEdgeSurfaceSource = interface
    ['{006CBD32-42DF-4902-BDF8-4DCA48B4C968}']
    /// <summary>The open index.</summary>
    /// <returns>The store; never nil.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Report.CycleEdge.CallRefusal (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.FinalOrderWhy (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PickExistingLeaf (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas) (+7 more)</para>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.BindName"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FidOfStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FileLines"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.IsSccStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.MemberAccessOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Store: ISymbolStore;
    /// <summary>The source lines of an indexed file.</summary>
    /// <param name="pFid">File id.</param>
    /// <returns>The lines, empty when the file is gone.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Report.CycleEdge.FinalOrderWhy (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.OverloadsTellApart (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.ShadowRefusal (DRagLint.Report.CycleEdge.pas) (+4 more)</para>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.BindName"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FidOfStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.IsSccStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.MemberAccessOf"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.Store"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FileLines(pFid: Int64): TArray<string>;
    /// <summary>File id of a unit stem.</summary>
    /// <param name="pStem">Lower-case unit stem.</param>
    /// <returns>The id, or 0 when no indexed file has that stem.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Report.CycleEdge.OverloadsTellApart (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TEdgeComposer.Create (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.AddLeafUse (DRagLint.Report.CycleEdge.pas) (+4 more)</para>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.BindName"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FileLines"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.IsSccStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.MemberAccessOf"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.Store"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FidOfStem(const pStem: string): Int64;
    /// <summary>Binds a bare name the way Delphi does at one line of a file: its
    /// own declaration first, else the LAST visible used unit that exports it.</summary>
    /// <param name="pFid">The citing file.</param>
    /// <param name="pLine">The line of the reference (selects the visible uses section).</param>
    /// <param name="pName">The identifier.</param>
    /// <param name="pOwner">Receives the top-level declaration it binds to.</param>
    /// <param name="pStem">Receives the stem of the declaring unit.</param>
    /// <returns>False when no visible declaration has that name.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Report.CycleEdge.FinalOrderWhy (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.ShadowRefusal (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.SignatureTypes (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.AddLeafUse (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TSurfaceBuilder.BindBare (DRagLint.Report.CycleEdge.pas) (+2 more)</para>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FidOfStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FileLines"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.IsSccStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.MemberAccessOf"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.Store"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BindName(pFid: Int64; pLine: Integer; const pName: string; out pOwner: TSymbol;
      out pStem: string): Boolean;
    /// <summary>Whether a stem is a unit of the circular group being planned.</summary>
    /// <param name="pStem">Lower-case unit stem.</param>
    /// <returns>True for a member of the group.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Report.CycleEdge.PickExistingLeaf (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.SignatureTypes (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.AddLeafUse (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.CheckCastUnit (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.SkipCycleAncestors (DRagLint.Report.CycleEdge.pas)</para>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.BindName"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FidOfStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FileLines"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.MemberAccessOf"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.Store"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsSccStem(const pStem: string): Boolean;
    /// <summary>The member_accesses row of a reference.</summary>
    /// <param name="pRefId">refs.id.</param>
    /// <param name="pAccess">Receives the row (TargetSymbolId = the member, MemberMode).</param>
    /// <returns>False when the ref has no member_accesses row.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Report.CycleEdge.TSurfaceBuilder.TakeMemberAccess (DRagLint.Report.CycleEdge.pas)</para>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.BindName"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FidOfStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FileLines"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.IsSccStem"/>
    /// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.Store"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function MemberAccessOf(pRefId: Int64; out pAccess: TCallEdge): Boolean;
  end;

  /// <summary>Optional read cache an IEdgeSurfaceSource may also implement (lane 148 HP2B): BuildEdgeSurface
  /// then reads a file's refs, a symbol by id and a child symbol by name through it instead of asking the
  /// store again for every edge of the same consumer.</summary>
  /// <remarks>Each method must return exactly what the store returns for the same arguments (a memo of
  /// ISymbolStore.GetReferencesFromFile / GetSymbolById / FindChildSymbolByName over an index that does not
  /// change while the cache lives), so the surface is the same with or without it. Not thread-safe.</remarks>
  IEdgeSurfaceCache = interface
    ['{5B0E2D7A-3C41-4F8E-9A6B-1D2C7E40B913}']
    /// <summary>The refs recorded in a file, as ISymbolStore.GetReferencesFromFile returns them.</summary>
    /// <param name="pFid">File id; greater than 0.</param>
    /// <returns>The refs, in the store's order.</returns>
    function CachedRefsFromFile(pFid: Int64): TArray<TReference>;
    /// <summary>A symbol by id, as ISymbolStore.GetSymbolById returns it.</summary>
    /// <param name="pId">Symbol id.</param>
    /// <returns>The symbol; Id = 0 when there is none.</returns>
    function CachedSymbolById(pId: Int64): TSymbol;
    /// <summary>A child symbol by name, as ISymbolStore.FindChildSymbolByName returns it.</summary>
    /// <param name="pParentId">Parent symbol id.</param>
    /// <param name="pName">Child name, passed to the store as given.</param>
    /// <returns>The child; Id = 0 when there is none.</returns>
    function CachedChildByName(pParentId: Int64; const pName: string): TSymbol;
  end;

  /// <summary>The recipe that cuts one edge of a circular group.</summary>
  /// <remarks>
  /// crMoveGlobals = move the declarations into a leaf unit (the playbook's
  /// original recipe); crRoutineInversion = R1, call one routine through a
  /// procedural variable (PlanRoutineInversion); crMemberInterface = R2, read the
  /// members through an extracted interface (PlanMemberInterface).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas), declaration (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.RecipeLabel (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.RecipeRank (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.FixHintOf (DRagLint.Report.CyclePlan.pas) (+1 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCutRecipe = (crNone, crMoveGlobals, crRoutineInversion, crMemberInterface);

  /// <summary>One line edit a recipe makes in an existing unit.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas) ?, DRagLint.Report.CycleEdge.AssignmentEdit (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.Create (DRagLint.Report.CycleEdge.pas) ? (+3 more)</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge, DRagLint.Report.CyclePlan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Report.CycleEdge.CallRefusal (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.ShadowRefusal (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.SignatureRefusal (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TEdgeComposer.Run (DRagLint.Report.CycleEdge.pas) (+10 more)</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge, DRagLint.Report.CyclePlan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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

  /// <summary>One routine recipe R1 calls through a procedural variable (plan B3: an edge
  /// can carry several).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas) ?, DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas)</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TInvertedRoutine = record
    /// <summary>symbols.id of the routine.</summary>
    Id: Int64;
    /// <summary>The routine's name, as declared.</summary>
    Name: string;
    /// <summary>`T&lt;Routine&gt;Ptr`.</summary>
    PtrType: string;
    /// <summary>`&lt;Routine&gt;Ptr`.</summary>
    PtrVar: string;
    /// <summary>The procedural type declaration (see TRecipeSteps.TypeDecl).</summary>
    TypeDecl: string;
    /// <summary>The variable declaration (see TRecipeSteps.VarDecl).</summary>
    VarDecl: string;
  end;

  /// <summary>R2: one class of the edge and the interface extracted for it.</summary>
  /// <remarks>
  /// An edge through one class has one entry, which repeats the singular R2 fields of
  /// TRecipeSteps; an edge through several has one per class that is an `is` / `as` operand or a hard-cast
  /// `TX(X).M` target (lane 149 CYB), sorted by class name.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas), declaration (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CycleEdge.MemberSurfaceDecls (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.RenderMemberSurface (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.SettleIfaceName (DRagLint.Report.CyclePlan.pas)</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge, DRagLint.Report.CyclePlan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMemberSurface = record
    /// <summary>The class whose members the interface hands over.</summary>
    ClassTypeName: string;
    /// <summary>symbols.id of that class.</summary>
    ClassId: Int64;
    /// <summary>`I&lt;Class without its T&gt;Surface`, or that name with the lowest free suffix.</summary>
    IfaceName: string;
    /// <summary>Its GUID text `{8-4-4-4-12}` (SurfaceGuid of `&lt;Leaf&gt;.&lt;IfaceName&gt;`).</summary>
    IfaceGuid: string;
    /// <summary>The interface declaration, indented for a `type` block, without the keyword.</summary>
    IfaceDecl: TArray<string>;
    /// <summary>`Name: Type` of every member carried, in declaration order.</summary>
    MemberSigs: TArray<string>;
    /// <summary>`Set&lt;Member&gt;` of every member the consumer writes, in declaration order.</summary>
    Setters: TArray<string>;
    /// <summary>`Name&lt;signature verbatim&gt;` of every instance method carried, in call order.</summary>
    MethodSigs: TArray<string>;
    /// <summary>The ancestor a receiver that does not implement IInterface is cast through; '' when
    /// no line needs a cast.</summary>
    CastAncestor: string;
    /// <summary>The getters the class already declared and the interface reuses as they are.</summary>
    KeptGetters: TArray<string>;
    /// <summary>Lane 148 CY (fabcyc case 8): `As&lt;Surface&gt;`, the helper the consumer gets when it
    /// handles EInvalidCast and casts with `as` unguarded: every `X as TX` becomes `As..(X)`, which raises
    /// EInvalidCast (SInvalidCast) as the class cast did; '' when no helper is needed.</summary>
    AsHelper: string;
    /// <summary>Lane 149 CYB: True when the consumer names EInvalidCast (a handler may rely on what a failed
    /// cast raises); False with an AsHelper means the helper serves an `as` whose receiver's static type is
    /// unknown (149-CY-8b).</summary>
    HandlesInvalidCast: Boolean;
    /// <summary>Lane 149 CYB (149-CY-8b): True when the consumer names EInvalidCast and a hard cast
    /// `TX(X).M` became `(X as I).M` -- a wrong X now raises EIntfCastError where it read through the wrong
    /// object; the plan states it.</summary>
    HardCastChange: Boolean;
    /// <summary>True when the leaf already declares IfaceDecl with exactly this code text (comments
    /// aside); it is reused, nothing is inserted for it.</summary>
    Reused: Boolean;
  end;

  /// <summary>What recipe R1 (routine-call inversion) or R2 (member hand-over) does to
  /// one edge, as data the planner maps onto its leaf machinery and file edits.</summary>
  /// <remarks>
  /// The leaf's new unit, its .dpr / .dproj registration and every uses-clause
  /// edit are NOT here: the planner derives them (UntangleCatalog leaf, Task 3a lexer
  /// edits) from LeafStem / DeclStem / ConsumerFid (R2: also LeafUses / ConsumerUses).
  /// The R1 fields are empty for R2 and the R2 fields empty for R1. On an R2 edge through several
  /// classes the singular class fields (ClassTypeName .. IfaceGuid, CastAncestor) name the first of
  /// Surfaces; Edits, IfaceDecl, LeafUses, ConsumerUses and the signature lists hold all of them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TEdgeComposer.Run (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.Run (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.ResetCycle (DRagLint.Report.CyclePlan.pas) (+9 more)</para>
  /// <para>Used in units: DRagLint.Report.CycleEdge, DRagLint.Report.CyclePlan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
    /// <summary>R2 (B1): `Set&lt;Member&gt;` of every member the consumer WRITES, in declaration
    /// order; each is a read/write property of the interface with a one-line setter. Empty when
    /// the consumer only reads.</summary>
    Setters: TArray<string>;
    /// <summary>R2m (plan B2): `Name&lt;signature verbatim&gt;` of every instance method of the class
    /// the consumer calls inside a `with ... as TX do` body, carried as interface methods, in call
    /// order; empty when it calls none.</summary>
    MethodSigs: TArray<string>;
    /// <summary>R2: the ancestor a receiver that does not implement IInterface is cast
    /// through; '' when no line needs a cast.</summary>
    CastAncestor: string;
    /// <summary>R1 (A2): True when the declaring unit would leave the program after the cut (only the
    /// consumer used it and the .dpr does not list it); the plan then adds it to the .dpr uses
    /// (and a DCCReference to the .dproj when absent) instead of refusing unit-leaves-program.</summary>
    RegisterDecl: Boolean;
    /// <summary>R1 (plan B3): every routine inverted, in first-call order; one entry for a single
    /// routine, which then repeats RoutineId .. VarDecl. The singular fields always name the first.</summary>
    Routines: TArray<TInvertedRoutine>;
    /// <summary>R1 (plan B3): symbols.id of each declaration of B that moves into the leaf before the
    /// pointers (a movable global on the edge, a plain type a signature names); filled by the planner,
    /// empty when nothing moves.</summary>
    MoveIds: TArray<Int64>;
    /// <summary>R1 (W6 C2): True when the leaf already declares TypeDecl and VarDecl with exactly this
    /// text; the plan then inserts neither (the pointer is reused). R2: the leaf already declares IfaceDecl
    /// with exactly this code text (comments aside); the interface is reused, nothing is inserted.</summary>
    ReuseDecl: Boolean;
    /// <summary>R1 (W6 C2): True when the declaring unit already assigns `PtrVar := Routine;` -- the
    /// plan adds no second assignment.</summary>
    AssignExists: Boolean;
    /// <summary>R2 (W6 C2): the getters the class already declared (`Get&lt;Member&gt;`) and the interface
    /// reuses as they are; empty when every getter is new.</summary>
    KeptGetters: TArray<string>;
    /// <summary>R2: one entry per class the edge hands over (see TMemberSurface); empty for R1.</summary>
    Surfaces: TArray<TMemberSurface>;
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
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.TSurfaceBuilder.TakeBareRef (DRagLint.Report.CycleEdge.pas)</para>
/// <para>Returns: erOther</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ClassifyTypeUse(const pLineText, pName: string): TEdgeRefKind;

/// <summary>The types a routine's stored signature names, each resolved to its
/// declaring unit as seen from the routine's own unit.</summary>
/// <param name="pSource">Index access; must not be nil.</param>
/// <param name="pDeclFid">File id of the unit that declares the routine.</param>
/// <param name="pDeclLine">Line of the routine's declaration (selects the visible uses).</param>
/// <param name="pSig">symbols.signature, e.g. `(const pFolderId: Integer): IFoo`.</param>
/// <returns>One entry per distinct type identifier, in signature order.</returns>
/// <remarks>
/// Only the text after a ':' of each `;`/`,`/`(`/`)` group is read (parameter
/// names are not types); `= default` tails and the words const var out array of
/// function procedure reference to packed are dropped. A dotted `Unit.TFoo` keeps its
/// name as written and is declared in the unit its prefix names. An identifier no
/// visible index row declares (e.g. Integer) gets DeclStem ''.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.RoutineSlice (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.CheckMethod (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TSurfaceBuilder.Finish (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.EvaluateEdge (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.ProbeInversionMoves (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: ContainsText, Default, DRagLint.Report.CycleEdge.IEdgeSurfaceSource.BindName, DRagLint.Report.CycleEdge.IEdgeSurfaceSource.IsSccStem, LowerCase</para>
/// <para>Returns: L.ToArray</para>
/// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.BindName"/>
/// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.IsSccStem"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SignatureTypes(const pSource: IEdgeSurfaceSource; pDeclFid: Int64; pDeclLine: Integer;
  const pSig: string): TArray<TSigType>;

/// <summary>Whether every resolved type of a signature lives outside the circular group.</summary>
/// <param name="pTypes">The result of SignatureTypes.</param>
/// <param name="pStems">Receives the distinct declaring stems of the resolved types.</param>
/// <returns>True when at least one type resolved and none is InScc -- a pointer /
/// event type for the routine could then be declared in pStems without touching
/// the cycle.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CyclePlan.TCyclePlanner.EvaluateEdge (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Returns: Stems.Count &gt; 0</para>
/// <para>Mutates: pStems (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SigTypesOutsideScc(const pTypes: TArray<TSigType>; out pStems: TArray<string>): Boolean;

/// <summary>Splits a heritage list (`TAnc, I1, IList&lt;T&gt;`) into its entries.</summary>
/// <param name="pText">The text between the parentheses of a class header, or
/// symbols.heritage.</param>
/// <returns>Each entry trimmed, in order; a comma inside `&lt;...&gt;` does not split.
/// Empty for blank text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.TTypeIndex.ListsInterface (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TTypeIndex.ParentOf (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.BuildBase (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.FindCtor (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: Copy, Trim</para>
/// <para>Returns: L.ToArray</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SplitHeritage(const pText: string): TArray<string>;

/// <summary>Collects what unit pFromFid takes from unit pToStem.</summary>
/// <param name="pSource">Index access; must not be nil. Its IsSccStem must answer for
/// the group the edge belongs to (it fills SigTypes[].InScc).</param>
/// <param name="pFromFid">File id of the citing unit A.</param>
/// <param name="pToStem">Lower-case stem of the used unit B.</param>
/// <returns>The surface; only FromStem / ToStem are set when either unit is not indexed.</returns>
/// <remarks>
/// Reads the index only. A ref with a member_accesses row counts as a member
/// access; the companion 'member-access' rows of a call are skipped; a bare name is
/// bound by its symbol_id when it has one, else by name (BindName), and a name that
/// is a local or parameter of its routine is never bound.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CyclePlan.TCyclePlanner.EdgeSurfacesOf (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.EvaluateEdge (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: DRagLint.Report.CycleEdge.TSurfaceBuilder.Create, DRagLint.Report.CycleEdge.TSurfaceBuilder.Run</para>
/// <para>Returns: B.Run</para>
/// <seealso cref="DRagLint.Report.CycleEdge.TSurfaceBuilder.Create"/>
/// <seealso cref="DRagLint.Report.CycleEdge.TSurfaceBuilder.Run"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildEdgeSurface(const pSource: IEdgeSurfaceSource; const pFromFid: Int64;
  const pToStem: string): TEdgeSurface;

/// <summary>The JSON `cycles --causes` prints for one edge.</summary>
/// <param name="pS">The surface.</param>
/// <returns>A new object {from, to, surface:{members, classes, has_write,
/// has_construction, has_class_method, has_class_ref_arg, has_decl, routine,
/// routine_sig, sig_types:[{name, unit, in_scc}], call_count}}; the caller owns it.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CyclePlan.AddCycleEdgeSurfaces (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: DRagLint.Report.CycleEdge.StringsToJson</para>
/// <para>Returns: TJSONObject.Create</para>
/// <para>Owns returned: new (caller owns)</para>
/// <seealso cref="DRagLint.Report.CycleEdge.StringsToJson"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EdgeSurfaceToJson(const pS: TEdgeSurface): TJSONObject;

/// <summary>Recipe R1, routine-call inversion: the edge A -&gt; B is one routine of B
/// that A calls; A calls it through a procedural variable declared in a leaf and
/// assigned in B's initialization section, so A no longer names B.</summary>
/// <param name="pSource">Index access; must not be nil; IsSccStem answers for the edge's group.</param>
/// <param name="pSurface">The edge's surface (BuildEdgeSurface); RoutineName must be set.</param>
/// <param name="pRefusal">Receives why the recipe does not apply; Kind '' when it does.</param>
/// <param name="pSuffix">W6 C2: 2 or more appends it to the pointer's names (`FooPtr2`, `TFooPtr2`) when the
/// leaf already declares different `FooPtr` / `TFooPtr`; 0 or 1 gives the plain names.</param>
/// <returns>The steps; Recipe = crNone when refused.</returns>
/// <remarks>
/// <para>Refusals, checked in this order: `not-a-routine` (RoutineName ''),
/// `signature-in-cycle` (a SigTypes entry is InScc; names the type),
/// `overloaded-routine` (two signatures of the name in its unit that the call argument counts do not tell
/// apart -- W6 C4: the overload the index bound admits the argument count of EVERY call, no other overload
/// admits any of them and none has a default parameter, otherwise the refusal stays), `signature-unknown`
/// (a function with no stored signature), `routine-not-called`
/// (a ref of the edge is neither a call nor an assignment value -- `@Foo` refuses; W6 C7: `X := Foo` is
/// redirected to the pointer; lane cyc4: so is `F(x, Foo)`, a whole argument on one line, for a procedure or a
/// function with a required parameter -- a parameterless function there is its result and refuses),
/// `qualified-ref` (the consumer names anything but the routine itself as `B.X`, B the declaring unit; W6 C7:
/// `B.Foo(...)` of the inverted routine becomes the pointer call, except behind `@`; lane cyc4: only code counts, not a
/// comment or a string, and a global in TEdgeSurface.QualifiedMoved is no finding), `name-shadowed` (lane cycq: a line
/// to edit also holds the name bound to something else, or `B` there is a declaration of A: the rewrite is text),
/// `init-order` (a call line lies in
/// A's initialization section, or that section -- from `initialization` to `finalization` or `end.` --
/// names the enclosing routine as a whole word: the variable is still nil there), `finalization-order` (lane cyc4: the same
/// for A's finalization section, when B -- finalized first after the cut -- has a statement in its finalization section
/// or a unit-level variable of a type not known to need no finalization),
/// `unsupported-directive` (varargs, or a directive word it cannot classify, on the declaration).
/// The planner (DRagLint.Report.CyclePlan, PlanInversion) refuses one more after this one:
/// `duplicate-identifier` (the leaf declares the pointer's names differently and every suffix up to 99 is taken --
/// W6 C2: identical declarations are reused, different ones get the lowest free `FooPtr2`, `FooPtr3`...); this function
/// refuses it itself when A, B or a class member declares the pointer's name, which would win over it (lane cycq). A declaring
/// unit that would drop out of the program after the cut (so its initialization never ran) is no refusal since A2:
/// the planner adds it to the program's uses clause instead (RegisterDecl).</para>
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
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.SettleInversionNames (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: ChangeFileExt, Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Report.CycleEdge.AssignmentEdit, DRagLint.Report.CycleEdge.CallRefusal, DRagLint.Report.CycleEdge.CodeStarts, DRagLint.Report.CycleEdge.DeclConvention, DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FidOfStem, DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FileLines, DRagLint.Report.CycleEdge.IEdgeSurfaceSource.Store (+10 more)</para>
/// <para>Returns: Default(TRecipeSteps)</para>
/// <para>Mutates: pRefusal (out)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Report.CycleEdge.AssignmentEdit"/>
/// <seealso cref="DRagLint.Report.CycleEdge.CallRefusal"/>
/// <seealso cref="DRagLint.Report.CycleEdge.CodeStarts"/>
/// <seealso cref="DRagLint.Report.CycleEdge.DeclConvention"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlanRoutineInversion(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface;
  out pRefusal: TRecipeRefusal; pSuffix: Integer = 0): TRecipeSteps;

/// <summary>Recipe R1 for EVERY routine on one edge (plan B3): each routine of
/// pSurface.RoutineIds is planned by PlanRoutineInversion on its own slice of the surface, and
/// the results are merged into one recipe.</summary>
/// <param name="pSource">Index access; must not be nil; IsSccStem answers for the edge's group.</param>
/// <param name="pSurface">The edge's surface (BuildEdgeSurface); RoutineIds must not be empty.
/// Refs bound to anything but these routines are ignored here: the planner moves them.</param>
/// <param name="pMovedTypes">Names of declarations of the edge's ToStem that move into its leaf
/// before the pointers; a signature type of that unit named here counts as OUTSIDE the cycle.</param>
/// <param name="pRefusal">Receives the first routine's refusal (PlanRoutineInversion's kinds, naming
/// that routine); Kind '' when every routine qualifies.</param>
/// <returns>The merged steps; Recipe = crNone when refused. The singular fields name the first
/// routine, Routines lists all of them.</returns>
/// <remarks>
/// The consumer line that calls several of the routines is rewritten ONCE with every
/// pointer; B gets ONE initialization edit holding the N assignments in Routines order. J2 (an
/// existing leaf) applies only when every routine picks the same one and pMovedTypes is empty;
/// otherwise LeafStem is '' (B's Untangle leaf, which receives the moved declarations too).
/// With one routine and nothing moved the result equals PlanRoutineInversion's.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CyclePlan.TCyclePlanner.PlanInversion (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: ChangeFileExt, Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Report.CycleEdge.AssignmentEdit, DRagLint.Report.CycleEdge.CodeStarts, DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FidOfStem, DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FileLines, DRagLint.Report.CycleEdge.IEdgeSurfaceSource.Store, DRagLint.Report.CycleEdge.LineOf, DRagLint.Report.CycleEdge.PlanRoutineInversion, DRagLint.Report.CycleEdge.ReplaceInCode, DRagLint.Report.CycleEdge.RoutineSlice, DRagLint.Report.CycleEdge.StartAt, ExtractFileName, Format</para>
/// <para>Returns: Default(TRecipeSteps); PlanRoutineInversion(pSource, pSurface, pRefusal); Parts[0]</para>
/// <para>Mutates: pRefusal (out)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Report.CycleEdge.AssignmentEdit"/>
/// <seealso cref="DRagLint.Report.CycleEdge.CodeStarts"/>
/// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FidOfStem"/>
/// <seealso cref="DRagLint.Report.CycleEdge.IEdgeSurfaceSource.FileLines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlanRoutinesInversion(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface;
  const pMovedTypes: TArray<string>; out pRefusal: TRecipeRefusal): TRecipeSteps;

/// <summary>The deterministic GUID of an extracted interface (R2).</summary>
/// <param name="pText">`&lt;LeafUnit&gt;.&lt;Interface&gt;`, e.g. `DemoGagePort.Untangle.IDemoGagePortSurface`.</param>
/// <returns>The MD5 of pText (UTF-8) as `{8-4-4-4-12}` upper-case hex, so a plan is
/// reproducible and its text can be pinned.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.TMemberPlan.IfaceDecl (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.Run (DRagLint.Report.CycleEdge.pas)</para>
/// <para>Calls: Copy, UpperCase</para>
/// <para>Returns: '{' + string.Join('-', Parts) + '}'</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
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
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.TMemberPlan.CheckClass (DRagLint.Report.CycleEdge.pas)</para>
/// <para>Calls: DRagLint.Report.CycleEdge.WalkToIInterface</para>
/// <para>Returns: WalkToIInterface(Idx, Start, pAncestor)</para>
/// <seealso cref="DRagLint.Report.CycleEdge.WalkToIInterface"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AncestorImplementingIInterface(const pProject, pLibrary: ISymbolStore; const pClass: TSymbol;
  out pAncestor: string): Boolean;

/// <summary>Whether a bare name inside a method body is a member of the method's own class or of an
/// ancestor (C3: Delphi binds it there, never to a same-named routine of a used unit).</summary>
/// <param name="pProject">The project index; must not be nil.</param>
/// <param name="pLibrary">The platform library index, or nil (the walk then stops at the first
/// ancestor the project does not declare).</param>
/// <param name="pEnclosingId">symbols.id of the routine whose body holds the reference.</param>
/// <param name="pName">The identifier.</param>
/// <returns>True when the routine is a member of a class (or record) and pName is a field, method,
/// property or constant of that type or of an ancestor reached through symbols.heritage; False for
/// a standalone routine, an unknown enclosing id, or a chain that ends before the name is found.</returns>
/// <remarks>
/// Reads the index only. Parameters and locals do not count as members.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CyclePlan.TCyclePlanner.Resolve (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Report.CycleEdge.TTypeIndex.Find, DRagLint.Report.CycleEdge.TTypeIndex.IsLib, DRagLint.Report.CycleEdge.TTypeIndex.ParentOf</para>
/// <para>Returns: False</para>
/// <para>Complexity: 14 (cyclomatic, outer body), 27 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <seealso cref="DRagLint.Report.CycleEdge.TTypeIndex.Find"/>
/// <seealso cref="DRagLint.Report.CycleEdge.TTypeIndex.IsLib"/>
/// <seealso cref="DRagLint.Report.CycleEdge.TTypeIndex.ParentOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsClassChainMember(const pProject, pLibrary: ISymbolStore; pEnclosingId: Int64;
  const pName: string): Boolean;

/// <summary>The symbol IsClassChainMember starts its member search from: pEnclosingId itself when it is a
/// class, record, unit, program or package (or has no parent), else its nearest such ancestor.</summary>
/// <param name="pProject">Project index; must not be nil.</param>
/// <param name="pEnclosingId">refs.enclosing_symbol_id of the bare name.</param>
/// <returns>That symbol; Id = 0 when an id on the way is unknown. Calling IsClassChainMember with the
/// returned class or record id gives the same answer as with pEnclosingId (lane 148 HP2B: the planner
/// memoizes by the type, not by every routine of it).</returns>
/// <remarks>Reads the index only.</remarks>
function EnclosingTypeOf(const pProject: ISymbolStore; pEnclosingId: Int64): TSymbol;

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
/// <param name="pUnitScopes">EffectiveUnitScopes of the project; nil = the Delphi defaults.</param>
/// <param name="pRefusal">Receives why the recipe does not apply; Kind '' when it does.</param>
/// <param name="pIfaceNames">The interface names, parallel to the result's Surfaces (classes sorted by
/// name); nil = `I&lt;Class&gt;Surface` each, a name two classes would share taking the lowest free suffix (the
/// leaf already declaring a name differently, W6 C2 plans again with that name's lowest free suffix).</param>
/// <returns>The steps; Recipe = crNone when refused.</returns>
/// <remarks>
/// <para>Shape (first offending ref, in line order): every ref must be erTypeIs, erTypeAs or
/// erMemberRead -- else `member-write`, `construction`, `class-method` (a method called
/// through the class or an instance, e.g. in a `with` body), `class-ref`, `type-decl`,
/// `type-cast`, `other-ref` (a routine or variable of B); then `qualified-ref` (`B.X` anywhere in A).</para>
/// <para>Several classes (1.42 cyc2): each class that is an `is` / `as` operand of the edge -- or, lane 149 CYB
/// (149-CY-12), that the edge hard-casts as `TX(X).M` (the C7 path) -- gets its own interface; an edge that only
/// hard-casts one class is planned for it the same way; and every check below runs per class, in class-name order. The refs are shared out: a test,
/// cast or type declaration goes to its class; a member goes to EVERY such class that declares or inherits
/// it (a class that only inherits it gets its own getter too, so a member shared by two classes is on both
/// interfaces, and a member of TA is also carried by a descendant TB of TA on the edge, even when only TA's
/// uses read it). A ref that fits no such class goes to the first, whose checks refuse it. A consumer line
/// naming two classes is rewritten once for each. All-or-nothing: the first class refused refuses the edge,
/// under that class's kind, the reason naming the class; no steps come back. `with` bodies of two different
/// classes may overlap (nested, or one `with X as TA, Y as TB do`, where Y is read in TA's scope; 1.43 CYC-C): each
/// class checks every bare name of its whole body, so a name either class declares is carried by that class, or
/// the edge is refused, and the nesting order, unchanged by the rewrite, decides between two carriers as it did
/// between the classes.</para>
/// <para>An edge whose `is` / `as` operand is no class (an interface or an alias its declaring unit keeps)
/// refuses `other-ref`, naming the line (1.43 CYC-C).</para>
/// <para>Members: each must be a field or a property declared in the class itself (an indexed property is carried for reading, its index list verbatim -- W6 C7; a `default` one or a write refuses)
/// (`member-unsupported`; a method is `class-method`); `duplicate-identifier` when the class
/// already has `Get&lt;M&gt;` -- unless it is exactly `function Get&lt;M&gt;: &lt;T&gt;;` and the property M
/// reads through it: then that getter is reused, nothing is added for M (W6 C2). Class: its heritage on its declaration line and its `end;` line
/// (`manual-edit`); an ancestor implementing IInterface (`no-iinterface`); no reference
/// counting on the way -- TInterfacedObject, TAggregatedObject, TContainedObject or an
/// unknown implementation would free the object when the temporary interface is released
/// (`ref-counted`).</para>
/// <para>Consumer: `X is TClass` -&gt; `Supports(X, ISurface)`; `X as TClass` -&gt; `X as
/// ISurface` when X's static type implements IInterface, else `TAnc(X) as ISurface` (TAnc =
/// AncestorImplementingIInterface). X must be `Self`, a parameter or local of the enclosing
/// routine, or a field / property of the enclosing class or its ancestors, else an `as` goes through the
/// As&lt;Surface&gt; helper below (lane 149 CYB, 149-CY-8b; `receiver-unknown` when its name is taken, and for a
/// hard cast `TX(X).M` on such a receiver);
/// a project TAnc must not be declared in B (`cast-unseen`). A `with` head may span lines. A
/// public or published non-indexed field or property of the class chain, a library ancestor included, named bare in a
/// `with X as TClass do` body goes on the interface too (read, or a plain write through a setter; 1.43 CYC-C;
/// an accessor name the chain already declares takes the suffix Surface); one private to its library
/// unit is invisible to the consumer and ignored. Every other name used there that is a
/// member of the class or of an ancestor but not carried (a library method such as `Free`: the temporary
/// interface would be released on a freed object; a protected library member: whether the consumer sees it
/// is not decidable here), a getter name or an IInterface method refuses `with-member` (it would bind to
/// something else after the rewrite); an ancestry no index completes refuses
/// `ancestry-unknown`. The same member read or written as `(X as TClass).M` or `TClass(X).M` is carried the same
/// way; there a library method refuses `class-method` and any other uncarriable one `member-unsupported`. A failed `as ISurface` raises EIntfCastError, not EInvalidCast: when
/// A names EInvalidCast, an `as` without an earlier `is` guard on the same receiver in its
/// routine goes through `As&lt;Surface&gt;(X)` (TObject parameter: nil for nil, else the interface, else raise
/// EInvalidCast) -- `exception-semantics` only when that name is taken (lane 148 CY); a hard cast `TX(X).M` there
/// becomes `(X as I).M` and TMemberSurface.HardCastChange makes the plan state the change (149-CY-8b).</para>
/// <para>Leaf: the units declaring the member types -- a project unit as bound from B, else
/// the library unit B's interface uses names (`type-unresolved`); never a unit of the
/// group (`leaf-uses-cycle`). The dotted prefixes are walked longest to shortest; the first that names a unit wins (a
/// project unit, a uses entry of B, a uses entry under a unit scope of the project's DCC_Namespace (the Delphi defaults when none), a library unit declaring
/// the type); with none and a unit-scope first segment the plan refuses `unresolved-qualified-type`; otherwise it is the outer type of a nested type and the
/// unit declaring that outer type is used (`member-unsupported` when none resolves).</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CyclePlan.TCyclePlanner.PlanMemberHandOver (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.SettleIfaceName (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: DRagLint.Report.CycleEdge.TEdgeComposer.Create, DRagLint.Report.CycleEdge.TEdgeComposer.Run, DRagLint.Report.CycleEdge.TMemberPlan.Create, DRagLint.Report.CycleEdge.TMemberPlan.Run</para>
/// <para>Returns: C.Run(pLeafUnit, pIfaceNames, pRefusal); P.Run(pLeafUnit, (if Length(pIfaceNames) &gt; 0 then pIfaceNames[0] else ''), pRefusal)</para>
/// <seealso cref="DRagLint.Report.CycleEdge.TEdgeComposer.Create"/>
/// <seealso cref="DRagLint.Report.CycleEdge.TEdgeComposer.Run"/>
/// <seealso cref="DRagLint.Report.CycleEdge.TMemberPlan.Create"/>
/// <seealso cref="DRagLint.Report.CycleEdge.TMemberPlan.Run"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlanMemberInterface(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore;
  const pSurface: TEdgeSurface; const pLeafUnit: string; const pUnitScopes: TArray<string>;
  out pRefusal: TRecipeRefusal; const pIfaceNames: TArray<string> = nil): TRecipeSteps;

/// <summary>The interface declarations the leaf must receive for an R2 edge.</summary>
/// <param name="pSurfaces">The edge's surfaces.</param>
/// <returns>The IfaceDecl lines of every surface not Reused, in order, a blank line between two.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.TEdgeComposer.Merge (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.SettleIfaceName (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MemberSurfaceDecls(const pSurfaces: TArray<TMemberSurface>): TArray<string>;

/// <summary>The effective unit-scope names of a project: every `&lt;DCC_Namespace&gt;` value of
/// the .dproj (any configuration group), split at `;`.</summary>
/// <param name="pDprojText">The text of the .dproj; '' when none is available.</param>
/// <returns>The scope names (`System`, `System.Win`, `MyCo`...). The Delphi defaults
/// (System;Xml;Data;Datasnap;Web;Soap;Vcl;Winapi;System.Win) when the project sets no
/// DCC_Namespace, and also added when a value keeps the `$(DCC_Namespace)` macro.</returns>
/// <remarks>
/// The one list that PlanMemberInterface uses both to read `MyCo.Foo.TBar` as the unit
/// `MyCo.Foo` (rule: scope + uses entry) and to refuse `unresolved-qualified-type` for a
/// scope-rooted prefix that names no unit; the two cannot drift.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.ProjectUnitScopes (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.Create (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.PlanMemberHandOver (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: ContainsStr, Trim</para>
/// <para>Returns: L.ToArray</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EffectiveUnitScopes(const pDprojText: string): TArray<string>;

type
  /// <summary>Whether a lower-case unit name is a unit of the project index.</summary>
  /// <param name="pUnitLower"><!-- drag-lint:auto type -->const string</param>
  /// <returns><!-- drag-lint:auto type -->Boolean</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas), DRagLint.Lint.ProjectRules.CollectCircularUsesDetailed.MapBareNames (DRagLint.Lint.ProjectRules.pas), DRagLint.Report.CycleEdge.BareUsesBinding (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.BuildCycleGraph (DRagLint.Report.CyclePlan.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProjectUnitTest = reference to function(const pUnitLower: string): Boolean;

/// <summary>The project unit a bare (undotted) uses name binds to, the way dcc binds it
/// (A3-b): the name itself when it is a project unit, else `&lt;scope&gt;.&lt;name&gt;` for the
/// FIRST unit scope that makes a project unit of it, else none.</summary>
/// <param name="pBare">The uses name as written; a dotted name binds to nothing here.</param>
/// <param name="pScopes">The project's unit scopes in DCC_Namespace order (ProjectUnitScopes).</param>
/// <param name="pIsProjectUnit">Tells whether a lower-case unit name is a project unit; must not be nil.</param>
/// <returns>The lower-case project unit name; '' when the name is an external unit (a DCU-only or
/// library unit such as the IDE's `DockForm`): no project edge.</returns>
/// <remarks>
/// The one rule behind the `cycles` graph (BuildCycleGraph) and the `circular-uses` lint
/// rule, so the two cannot disagree. A unit that merely shares the last segment
/// (`DragLint.Plugin.DockForm`) is NOT bound unless `DragLint.Plugin` is a unit scope.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.CollectCircularUsesDetailed.MapBareNames (DRagLint.Lint.ProjectRules.pas), DRagLint.Report.CyclePlan.BuildCycleGraph (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: ContainsStr, LowerCase, pIsProjectUnit</para>
/// <para>Returns: ''</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BareUsesBinding(const pBare: string; const pScopes: TArray<string>;
  const pIsProjectUnit: TProjectUnitTest): string;

/// <summary>The unit scopes of the project an index was built from: EffectiveUnitScopes of the
/// .dproj beside the index's first program (.dpr) or package (.dpk) file.</summary>
/// <param name="pStore">Open index; read only. nil = no project.</param>
/// <returns>The scope names in DCC_Namespace order; the Delphi defaults when the index holds no
/// program or package, or no .dproj sits beside it.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.CollectCircularUsesDetailed.MapBareNames (DRagLint.Lint.ProjectRules.pas), DRagLint.Report.CyclePlan.BuildCycleGraph (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: ChangeFileExt, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Report.CycleEdge.EffectiveUnitScopes, ExtractFileExt, MatchText, StringReplace</para>
/// <para>Returns: EffectiveUnitScopes(Text)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Report.CycleEdge.EffectiveUnitScopes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProjectUnitScopes(const pStore: ISymbolStore): TArray<string>;

type
  /// <summary>B11: what is open where a source line starts.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.CodeOf (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.CodeStarts (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.ReplaceInCode (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.StartAt (DRagLint.Report.CycleEdge.pas) (+1 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCodeStart = (csCode, csInBrace, csInParen);

/// <summary>pLine with every comment (brace and paren-star, which may span lines; `//`), compiler
/// directive and string literal blanked to spaces, so only code is left. Columns are unchanged; the
/// result stops where a `//` comment starts.</summary>
/// <param name="pLine">One source line.</param>
/// <param name="pInBrace">In and out: a brace comment is open at the start / end of the line.</param>
/// <param name="pInParen">In and out: a paren-star comment is open at the start / end of the line.</param>
/// <returns>The code of the line, column-faithful to pLine.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.CodeOf (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.CodeStarts (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.CodeIdentsIn (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.QualifiedGlobals (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.RewriteQualifiedIn (DRagLint.Report.CyclePlan.pas) (+1 more)</para>
/// <para>Calls: Copy, PosEx</para>
/// <para>Returns: pLine; Copy(Result, 1, I - 1)</para>
/// <para>Complexity: 23 (cyclomatic, outer body), 40 lines (full implementation)</para>
/// <para>Mutates: pInBrace (var), pInParen (var)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CodeOnly(const pLine: string; var pInBrace, pInParen: Boolean): string;

/// <summary>B11: what is open at the start of each line of a file.</summary>
/// <param name="pLines">The file.</param>
/// <returns>One TCodeStart per line.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.StartOf (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.BuildSwitches (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.CtorSiteLine (DRagLint.Report.CyclePlan.pas) (+2 more)</para>
/// <para>Calls: DRagLint.Report.CycleEdge.CodeOnly</para>
/// <seealso cref="DRagLint.Report.CycleEdge.CodeOnly"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CodeStarts(const pLines: TArray<string>): TArray<TCodeStart>;

const
  /// <summary>Lane cycq: what may precede a unit qualifier in a pattern: no word character and no member dot. A `..`
  /// is no member dot: `array[0..Unit.cMax]` names the unit, and reading it as a chain hid the use from the planner
  /// (E2242 after the entry was removed).</summary>
  CUnitQualifierStart = '(?<!\w)(?<![^.]\.)';

/// <summary>B11: the code of pLine (CodeOnly) from the start state pStart.</summary>
/// <param name="pLine">The line.</param>
/// <param name="pStart">What is open at its start (CodeStarts).</param>
/// <returns>The code of the line, column-faithful to pLine.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.ReplaceInCode (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.RewriteLine (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.BaseSiteRefusal (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.BuildSwitches (DRagLint.Report.CyclePlan.pas), DRagLint.Report.CyclePlan.TCyclePlanner.CtorSiteLine (DRagLint.Report.CyclePlan.pas) (+2 more)</para>
/// <para>Calls: DRagLint.Report.CycleEdge.CodeOnly</para>
/// <para>Returns: CodeOnly(pLine, InBrace, InParen)</para>
/// <seealso cref="DRagLint.Report.CycleEdge.CodeOnly"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CodeOf(const pLine: string; pStart: TCodeStart): string;

/// <summary>B11: pLine with pPattern replaced in its CODE only (case-insensitive): a string literal
/// or a comment that spells the same name stays byte-identical. pWith may name groups (`$1`).</summary>
/// <param name="pLine">The line, possibly rewritten already; it starts in the state pStart.</param>
/// <param name="pStart">What is open at its start (CodeStarts).</param>
/// <param name="pPattern">The regular expression, matched against the code of the line.</param>
/// <param name="pWith">The replacement.</param>
/// <returns>The rewritten line.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.CheckTypeDecls (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.TMemberPlan.RewriteLine (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.BuildSwitches (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: ContainsStr, Copy, DRagLint.Report.CycleEdge.CodeOf</para>
/// <seealso cref="DRagLint.Report.CycleEdge.CodeOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReplaceInCode(const pLine: string; pStart: TCodeStart; const pPattern, pWith: string): string;

/// <summary>Why a pointer call at pRef may run before the declaring unit assigned the pointer: the
/// line is in the initialization section of its unit, or that section names the routine holding it.</summary>
/// <param name="pLines">The consumer's lines.</param>
/// <param name="pRef">The call: its Line and Enclosing are read.</param>
/// <param name="pUnit">The consumer's name, for the text.</param>
/// <returns>'' when no such order problem is seen.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.CallRefusal (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.TakeCtor (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: DRagLint.Report.CycleEdge.CodeOnlyLines, DRagLint.Report.CycleEdge.LastKeywordLine, DRagLint.Report.CycleEdge.LineOf, Format</para>
/// <para>Returns: ''</para>
/// <para>Complexity: 10 (cyclomatic, outer body), 19 lines (full implementation)</para>
/// <seealso cref="DRagLint.Report.CycleEdge.CodeOnlyLines"/>
/// <seealso cref="DRagLint.Report.CycleEdge.LastKeywordLine"/>
/// <seealso cref="DRagLint.Report.CycleEdge.LineOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function InitOrderWhy(const pLines: TArray<string>; const pRef: TEdgeRef; const pUnit: string): string;

/// <summary>The declaring unit's edit: pAssigns as the first statements of its initialization
/// section, creating the section when there is none.</summary>
/// <param name="pLines">The declaring unit's lines.</param>
/// <param name="pFid">Its file id.</param>
/// <param name="pAssigns">The statements, indented.</param>
/// <param name="pEdit">The edit. Replace is True only when the final `end.` line is rewritten.</param>
/// <returns>False when the unit has no final `end.`, `initialization` or `finalization` line.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CycleEdge.PlanRoutineInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CycleEdge.PlanRoutinesInversion (DRagLint.Report.CycleEdge.pas), DRagLint.Report.CyclePlan.TCyclePlanner.AddCtorEdits (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: Default, DRagLint.Report.CycleEdge.LastKeywordLine, DRagLint.Report.CycleEdge.LineOf</para>
/// <para>Returns: pEdit.Line &gt; 0</para>
/// <para>Mutates: pEdit (out)</para>
/// <seealso cref="DRagLint.Report.CycleEdge.LastKeywordLine"/>
/// <seealso cref="DRagLint.Report.CycleEdge.LineOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AssignmentEdit(const pLines: TArray<string>; pFid: Int64; const pAssigns: TArray<string>; out pEdit: TRecipeEdit): Boolean;

/// <summary>Whether pName is a System type every unit sees without a uses entry.</summary>
/// <param name="pName">A bare type name.</param>
/// <returns>True for a built-in (Integer, string, TObject, TClass ...).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Report.CyclePlan.TCyclePlanner.CtorTypeWhy (DRagLint.Report.CyclePlan.pas)</para>
/// <para>Calls: ContainsText</para>
/// <para>Returns: ContainsText(CBuiltinTypes, ' ' + pName + ' ')</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsBuiltinTypeName(const pName: string): Boolean;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.RegularExpressions, System.Math,
  System.Generics.Collections, System.Generics.Defaults, System.Hash, System.IOUtils;

const
  { The Delphi default unit-scope names (.dproj DCC_Namespace when it sets none); a type written
    `System.Classes.TStrings` names the unit through such a scope when the uses says `Classes`. }
  CUnitScopeNames: array[0..8] of string = ('System', 'Xml', 'Data', 'Datasnap', 'Web', 'Soap', 'Vcl', 'Winapi', 'System.Win');
  CNotTypeWords = ' const var out array of function procedure reference to packed ';
  { System-unit types every unit sees without a uses entry (R1, J2) }
  CBuiltinTypes = ' integer cardinal shortint smallint longint int64 uint64 byte word longword nativeint ' +
    'nativeuint boolean bytebool wordbool longbool char ansichar widechar string ansistring widestring ' +
    'unicodestring shortstring rawbytestring single double extended currency real comp pointer pchar ' +
    'pansichar pwidechar tobject tclass iinterface iunknown variant olevariant tdatetime tguid hresult ';
  { R1 directive classes (fix round 1): carried into the procedural type / refused / no effect on it }
  CConventionWords       = ' register pascal cdecl stdcall safecall winapi ';
  CUnsupportedDirectives = ' varargs ';
  CNeutralDirectives     = ' inline overload external forward deprecated platform library experimental assembler delayed export local near far ';
  CMaxDeclLines          = 8;
  CDeclStartWords        = ' function procedure constructor destructor class operator type var const threadvar ' +
    'resourcestring label begin asm implementation interface initialization finalization exports uses ' +
    'property end strict private protected public published ';  { a routine declaration and its directives span at most this many lines }

function IsBuiltinTypeName(const pName: string): Boolean;
begin
  Result:= ContainsText(CBuiltinTypes, ' ' + pName + ' ');
end;

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
    FCache    : IEdgeSurfaceCache;  // HP2B: the source's read cache, nil when it has none
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
    function Child(pParentId: Int64; const pName: string): TSymbol;
    function TopLevel(const pSym: TSymbol): TSymbol;
    function IsLocal(const pR: TReference): Boolean;
    function LineText(pLine: Integer): string;
    function BindBare(const pR: TReference; const pName: string; out pOwner: TSymbol): Boolean;
    procedure AddRef(const pR: TReference; pKind: TEdgeRefKind; pSymbolId: Int64);
    function TakeMemberAccess(const pR: TReference): Boolean;
    function TakeReceiverRef(const pR: TReference): Boolean;
    procedure TakeClassMemberAccess(const pR: TReference);
    procedure TakeBareRef(const pR: TReference);
    procedure TakeCastMembers(const pR: TReference; const pCls: TSymbol);
    procedure Finish;
    procedure Collect;
  public
    constructor Create(const pSource: IEdgeSurfaceSource; pFromFid: Int64; const pToStem: string);
    destructor Destroy; override;
    function Run: TEdgeSurface;
  end;

function PlainCode(const pLine: string): string; forward;

constructor TSurfaceBuilder.Create(const pSource: IEdgeSurfaceSource; pFromFid: Int64; const pToStem: string);
begin
  inherited Create;
  FSource := pSource;
  FStore  := pSource.Store;
  if not Supports(pSource, IEdgeSurfaceCache, FCache) then FCache:= nil;
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
  Result:= if FCache <> nil then FCache.CachedSymbolById(pId) else FStore.GetSymbolById(pId);
  FSyms.Add(pId, Result);
end;

{ ISymbolStore.FindChildSymbolByName, through the source's cache when it has one. }
function TSurfaceBuilder.Child(pParentId: Int64; const pName: string): TSymbol;
begin
  Result:= if FCache <> nil then FCache.CachedChildByName(pParentId, pName)
    else FStore.FindChildSymbolByName(pParentId, pName);
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
  Local:= Child(pR.EnclosingSymbolId, pR.NameText);
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
      else SameText(pR.NameText, 'Create') or (Child(Cls.Id, pR.NameText).Kind = skConstructor);
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
  if SameText(pR.NameText, 'Create') or (Child(Cls.Id, pR.NameText).Kind = skConstructor) then
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
    { C7: the index records a hard cast `TX(Y)` as a call of TX }
    if (Owner.Kind = skClass) and SameText(pR.NameText, Owner.Name) then Kind:= erTypeCast
    else
    begin
      Kind:= erCall;
      Inc(FSurface.CallCount);
    end;
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
  if Kind = erTypeCast then TakeCastMembers(pR, Owner);
end;

{ C7: the index records no member access after a hard cast, so `TX(Y).M` and `TX(Y).M := v` get
  their member read / write from the line: one ref per field or property of TX named that way
  (a member TX does not declare itself is left to RefRefusal, which refuses the cast). }
procedure TSurfaceBuilder.TakeCastMembers(const pR: TReference; const pCls: TSymbol);
var
  R: TReference;
begin
  var C:= TRegEx.Escape(pCls.Name);
  for var M in TRegEx.Matches(PlainCode(LineText(pR.StartLine)),
    '(?<![\w.])' + C + '\s*\(\s*[A-Za-z_]\w*\s*\)\s*\.\s*([A-Za-z_]\w*)(\s*:=)?', [roIgnoreCase]) do
  begin
    var Member:= Child(pCls.Id, M.Groups[1].Value);
    if (Member.Id <= 0) or not (Member.Kind in [skField, skProperty]) then Continue;
    R:= pR;
    R.NameText:= Member.Name;
    if (M.Groups.Count > 2) and (M.Groups[2].Value <> '') then
    begin
      FSurface.HasWrite:= True;
      AddRef(R, erMemberWrite, Member.Id);
    end
    else
    begin
      FMembers.Add(Member.Name);
      AddRef(R, erMemberRead, Member.Id);
    end;
  end;
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
  { B3: the routines among the owners, in first-reference order (a top-level routine's ref
    carries the routine's own id) }
  var Ids:= TList<Int64>.Create;
  try
    for var R in FRefs do
      if FOwners.TryGetValue(R.SymbolId, Owner) and (Owner.Kind in [skProcedure, skFunction]) and
        not Ids.Contains(R.SymbolId) then Ids.Add(R.SymbolId);
    FSurface.RoutineIds:= Ids.ToArray;
  finally
    Ids.Free;
  end;
  Owner:= Default(TSymbol);
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
  var Refs:= if FCache <> nil then FCache.CachedRefsFromFile(FFromFid) else FStore.GetReferencesFromFile(FFromFid);
  for var R in Refs do
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

{ 1-based number of the LAST line whose code is exactly pWord, or 0. W6 C6: a block comment
  after the word (`end.` then a comment) is not code. }
function LastKeywordLine(const pLines: TArray<string>; const pWord: string): Integer;
begin
  for var I:= High(pLines) downto 0 do
    if SameText(TRegEx.Replace(BareCode(pLines[I]), '\s*(\{[^}]*\}|\(\*.*?\*\))$', ''), pWord) then Exit(I + 1);
  Result:= 0;
end;

{ W6 C6: where the heritage list of the class declared at pStart closes. The header is joined
  over at most CMaxDeclLines lines (`//` comments dropped); False when the line at pStart does
  not open a heritage list or the parentheses do not balance before a `;`. }
function HeritageClose(const pLines: TArray<string>; pStart: Integer; out pLine, pCol: Integer): Boolean;
begin
  pLine:= 0;
  pCol := 0;
  if not TRegEx.IsMatch(BareCode(LineOf(pLines, pStart)), '=\s*class\b[^(;]*\(', [roIgnoreCase]) then Exit(False);
  var Depth:= 0;
  for var L:= pStart to Min(pStart + CMaxDeclLines - 1, Length(pLines)) do
  begin
    var S:= LineOf(pLines, L);
    var Cut:= Pos('//', S);
    if Cut > 0 then S:= Copy(S, 1, Cut - 1);
    for var C:= 1 to Length(S) do
      if S[C] = '(' then Inc(Depth)
      else if S[C] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          pLine:= L;
          pCol := C;
          Exit(True);
        end;
      end
      else if (S[C] = ';') and (Depth = 0) then Exit(False);
  end;
  Result:= False;
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

// The lines with every comment (line, brace and paren-star; the last two across lines) and string
// literal blanked; the line count and numbering are unchanged. C3: a name that only a comment
// mentions is no code. A compiler directive is a brace comment here as well.
function CodeOnlyLines(const pLines: TArray<string>): TArray<string>;
var
  InBrace, InParen: Boolean;
begin
  SetLength(Result, Length(pLines));
  InBrace:= False;
  InParen:= False;
  for var L:= 0 to High(pLines) do
  begin
    var S:= pLines[L];
    var SB:= TStringBuilder.Create;
    try
      var I:= 1;
      while I <= Length(S) do
      begin
        var C:= S[I];
        var N:= if I < Length(S) then S[I + 1] else #0;
        if InBrace then
          InBrace:= C <> '}'
        else if InParen then
        begin
          if (C = '*') and (N = ')') then
          begin
            InParen:= False;
            Inc(I);
          end;
        end
        else if C = '{' then InBrace:= True
        else if (C = '(') and (N = '*') then
        begin
          InParen:= True;
          Inc(I);
        end
        else if (C = '/') and (N = '/') then Break
        else if C = '''' then
        begin
          Inc(I);
          while (I <= Length(S)) and ((S[I] <> '''') or ((I < Length(S)) and (S[I + 1] = ''''))) do
            Inc(I, if S[I] = '''' then 2 else 1);
          SB.Append(''''' ');
        end
        else SB.Append(C);
        Inc(I);
      end;
      Result[L]:= SB.ToString;
    finally
      SB.Free;
    end;
  end;
end;

function CodeOnly(const pLine: string; var pInBrace, pInParen: Boolean): string;
const
  CPairLen = 2;
var
  I: Integer;
begin
  Result:= pLine;
  I:= 1;
  while I <= Length(Result) do
  begin
    var Pair:= Copy(Result, I, CPairLen);
    var Opens:= (not pInBrace) and (not pInParen) and ((Result[I] = '{') or (Pair = '(*'));
    if Opens then
    begin
      pInBrace:= Result[I] = '{';
      pInParen:= not pInBrace;
    end;
    if (not pInBrace) and (not pInParen) and (Pair = '//') then
      Exit(Copy(Result, 1, I - 1));
    if (not pInBrace) and (not pInParen) and (Result[I] = '''') then
    begin
      var J:= PosEx('''', Result, I + 1);
      if J = 0 then J:= Length(Result);
      for var K:= I to J do Result[K]:= ' ';
      I:= J + 1;
      Continue;
    end;
    if pInBrace or pInParen then
    begin
      var Closes:= (pInBrace and (Result[I] = '}')) or (pInParen and (Pair = '*)') and not Opens);
      if pInParen and Closes then Result[I + 1]:= ' ';
      if Closes then
      begin
        pInBrace:= False;
        pInParen:= False;
      end;
      Result[I]:= ' ';
    end;
    Inc(I);
  end;
end;

function CodeStarts(const pLines: TArray<string>): TArray<TCodeStart>;
begin
  SetLength(Result, Length(pLines));
  var InBrace:= False;
  var InParen:= False;
  for var I:= 0 to High(pLines) do
  begin
    Result[I]:= if InBrace then csInBrace else if InParen then csInParen else csCode;
    CodeOnly(pLines[I], InBrace, InParen);
  end;
end;

function CodeOf(const pLine: string; pStart: TCodeStart): string;
begin
  var InBrace:= pStart = csInBrace;
  var InParen:= pStart = csInParen;
  Result:= CodeOnly(pLine, InBrace, InParen);
end;

function ReplaceInCode(const pLine: string; pStart: TCodeStart; const pPattern, pWith: string): string;
begin
  Result:= pLine;
  var Ms:= TRegEx.Matches(CodeOf(pLine, pStart), pPattern, [roIgnoreCase]);
  for var I:= Ms.Count - 1 downto 0 do
  begin
    var Text:= if ContainsStr(pWith, '$1') then pWith.Replace('$1', Ms[I].Groups[1].Value) else pWith;
    Result:= Copy(Result, 1, Ms[I].Index - 1) + Text + Copy(Result, Ms[I].Index + Ms[I].Length, MaxInt);
  end;
end;

{ The start state of 1-based line pLine; csCode past either end of the file. }
function StartAt(const pStarts: TArray<TCodeStart>; pLine: Integer): TCodeStart;
begin
  Result:= if InRange(pLine, 1, Length(pStarts)) then pStarts[pLine - 1] else csCode;
end;

{ J4, conservative: the call runs in the consumer's initialization section, or
  that section names the routine that holds the call (as code: a comment naming it is not a use).
  Lane cyc4: the section ends at `finalization`: code there runs long after every initialization, so
  the variable is assigned by then (FinalOrderWhy holds what can go wrong there instead). }
function InitOrderWhy(const pLines: TArray<string>; const pRef: TEdgeRef; const pUnit: string): string;
begin
  Result:= '';
  var Code:= CodeOnlyLines(pLines);
  var Init:= LastKeywordLine(Code, 'initialization');
  if Init = 0 then Exit;
  var Stop:= LastKeywordLine(Code, 'end.');
  if Stop < Init then Stop:= Length(Code) + 1;
  var Fin:= LastKeywordLine(Code, 'finalization');
  if (Fin > Init) and (Fin < Stop) then Stop:= Fin;
  if (pRef.Line > Init) and (pRef.Line < Stop) then
    Exit(Format('the call at line %d runs in the initialization section of `%s`, before the variable ' +
      'may be assigned', [pRef.Line, pUnit]));
  var Encl:= pRef.Enclosing.Substring(pRef.Enclosing.LastIndexOf('.') + 1);
  if Encl = '' then Exit;
  for var L:= Init + 1 to Stop - 1 do
    if TRegEx.IsMatch(LineOf(Code, L), '\b' + TRegEx.Escape(Encl) + '\b', [roIgnoreCase]) then
      Exit(Format('`%s` (it makes the call at line %d) is named at line %d, in the initialization section of ' +
        '`%s`: it may run before the variable is assigned', [Encl, pRef.Line, L, pUnit]));
end;

{ Lane cyc4: why the state of the declaring unit may be gone when a routine runs from the consumer's
  finalization section. The declaring unit keeps using the consumer after the cut, so it initializes
  later and FINALIZES FIRST, whatever the order was before. Safe only when finalizing it does nothing
  the routine could see: no statement in its finalization section and no unit-level variable the
  compiler finalizes (a string, an interface, a dynamic array, a record ...). The types below are the
  ones known to need no finalization; any other type counts as managed, unless it binds to a class or a
  plain procedural type. '' when safe, or when the section does not run the call at all. }
function FinalOrderWhy(const pSource: IEdgeSurfaceSource; const pLines: TArray<string>; const pRef: TEdgeRef;
  const pUnit: string; pDeclFid: Int64; const pDeclUnit: string): string;
const
  CUnmanagedType = '^(Integer|Cardinal|Boolean|ByteBool|WordBool|LongBool|Byte|Word|ShortInt|SmallInt|LongInt|LongWord|Int8|' +
    'Int16|Int32|Int64|UInt8|UInt16|UInt32|UInt64|NativeInt|NativeUInt|Single|Double|Extended|Real|Currency|Char|AnsiChar|' +
    'WideChar|Pointer|TObject|TClass|TDateTime|TDate|TTime|THandle|DWORD|HWND)$';
var
  Owner: TSymbol;
  Stem : string;
begin
  Result:= '';
  var Code:= CodeOnlyLines(pLines);
  var Fin := LastKeywordLine(Code, 'finalization');
  if Fin = 0 then Exit;
  var Stop:= LastKeywordLine(Code, 'end.');
  if Stop < Fin then Stop:= Length(Code) + 1;
  var Runs:= (pRef.Line > Fin) and (pRef.Line < Stop);
  var Encl:= pRef.Enclosing.Substring(pRef.Enclosing.LastIndexOf('.') + 1);
  if (not Runs) and (Encl <> '') then
    for var L:= Fin + 1 to Stop - 1 do
      if TRegEx.IsMatch(LineOf(Code, L), '\b' + TRegEx.Escape(Encl) + '\b', [roIgnoreCase]) then Runs:= True;
  if not Runs then Exit;
  var Lead:= Format('the call at line %d runs from the finalization section of `%s`, and after the cut `%s` is ' +
    'finalized first: ', [pRef.Line, pUnit, pDeclUnit]);
  var DeclCode:= CodeOnlyLines(pSource.FileLines(pDeclFid));
  var DeclFin := LastKeywordLine(DeclCode, 'finalization');
  var DeclEnd := LastKeywordLine(DeclCode, 'end.');
  if DeclFin > 0 then
    for var L:= DeclFin + 1 to DeclEnd - 1 do
      if Trim(LineOf(DeclCode, L)) <> '' then
        Exit(Lead + Format('its finalization section (line %d) has already run', [L]));
  for var S in pSource.Store.FindSymbolsByFile(pSource.Store.GetFilePath(pDeclFid)) do
  begin
    if S.Kind <> skVarDecl then Continue;
    var T:= Trim(S.Signature);
    if TRegEx.IsMatch(T, CUnmanagedType, [roIgnoreCase]) or TRegEx.IsMatch(T, '^(procedure|function)\b', [roIgnoreCase]) then Continue;
    if pSource.BindName(pDeclFid, S.StartLine, T, Owner, Stem) and (Owner.Kind = skClass) then Continue;
    Exit(Lead + Format('its variable `%s` (`%s`) may be finalized already', [S.Name, T]));
  end;
end;

{ The declaring unit's edit: the assignments (B3: one per inverted routine) as the first
  statements of its initialization section, creating the section when there is none. }
function AssignmentEdit(const pLines: TArray<string>; pFid: Int64; const pAssigns: TArray<string>; out pEdit: TRecipeEdit): Boolean;
begin
  pEdit    := Default(TRecipeEdit);
  pEdit.Fid:= pFid;
  var Init:= LastKeywordLine(pLines, 'initialization');
  var Fin := LastKeywordLine(pLines, 'finalization');
  var Stop:= LastKeywordLine(pLines, 'end.');
  if Init > 0 then
  begin
    pEdit.Line    := Init;
    pEdit.NewLines:= pAssigns;
  end
  else if Fin > 0 then
  begin
    pEdit.Line    := Fin - 1;
    pEdit.NewLines:= ['initialization'] + pAssigns + [''];
  end
  else if Stop > 0 then
  begin
    pEdit.Line    := Stop;
    pEdit.Replace := True;
    pEdit.NewLines:= ['initialization'] + pAssigns + ['', LineOf(pLines, Stop)];
  end;
  Result:= pEdit.Line > 0;
end;

{ W6 C4: the parameter count of a stored signature (`(const pA, pB: Integer; var pC): string`), and whether
  any parameter has a default value. }
function SignatureArity(const pSig: string; out pHasDefault: Boolean): Integer;
begin
  Result     := 0;
  pHasDefault:= False;
  var P:= Pos('(', pSig);
  if P = 0 then Exit;
  var Depth:= 0;
  var Group := TStringBuilder.Create;
  var Groups:= TList<string>.Create;
  try
    for var I:= P to Length(pSig) do
    begin
      var C:= pSig[I];
      if C = '(' then
      begin
        Inc(Depth);
        if Depth = 1 then Continue;
      end
      else if C = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then Break;
      end
      else if (C = ';') and (Depth = 1) then
      begin
        Groups.Add(Group.ToString);
        Group.Clear;
        Continue;
      end;
      Group.Append(C);
    end;
    if Trim(Group.ToString) <> '' then Groups.Add(Group.ToString);
    for var G in Groups do
    begin
      var Names:= Copy(G, 1, Pos(':', G + ':') - 1);
      Inc(Result, Length(Names.Split([','])));
      if TRegEx.IsMatch(Copy(G, Pos(':', G + ':'), MaxInt), '=') then pHasDefault:= True;
    end;
  finally
    Groups.Free;
    Group.Free;
  end;
end;

{ W6 C4: the argument counts of the calls of pName that start on line pLine (the argument list may run over
  CMaxDeclLines lines). False when a list does not close. }
function CallArities(const pLines: TArray<string>; pLine: Integer; const pName: string; pArities: TList<Integer>): Boolean;
begin
  Result:= True;
  var SB:= TStringBuilder.Create;
  try
    for var L:= pLine to Min(pLine + CMaxDeclLines - 1, Length(pLines)) do SB.Append(BareCode(LineOf(pLines, L))).Append(' ');
    var Text:= SB.ToString;
    var M:= TRegEx.Match(LineOf(pLines, pLine), '(?<![\w.])' + TRegEx.Escape(pName) + '\b', [roIgnoreCase]);
    var Skip:= 0;
    while M.Success do
    begin
      Inc(Skip);
      M:= M.NextMatch;
    end;
    var Pos0:= 1;
    for var K:= 1 to Skip do
    begin
      var Hit:= TRegEx.Match(Text.Substring(Pos0 - 1), '(?<![\w.])' + TRegEx.Escape(pName) + '\b', [roIgnoreCase]);
      if not Hit.Success then Exit(False);
      var P:= Pos0 - 1 + Hit.Index + Hit.Length;  { TMatch.Index is 1-based }
      Pos0:= P;
      while (P <= Length(Text)) and (Text[P] = ' ') do Inc(P);
      if (P > Length(Text)) or (Text[P] <> '(') then
      begin
        pArities.Add(0);
        Continue;
      end;
      var Depth:= 0;
      var Args := 0;
      var Seen := False;
      var InStr:= False;
      repeat
        var C:= Text[P];
        if C = '''' then InStr:= not InStr
        else if not InStr then
        begin
          if CharInSet(C, ['(', '[']) then
          begin
            Inc(Depth);
            if Depth > 1 then Seen:= True;
          end
          else if CharInSet(C, [')', ']']) then Dec(Depth)
          else if (C = ',') and (Depth = 1) then Inc(Args)
          else if (Depth >= 1) and (C <> ' ') then Seen:= True;
        end;
        Inc(P);
      until (Depth = 0) or (P > Length(Text));
      if Depth <> 0 then Exit(False);
      pArities.Add(if Seen then Args + 1 else 0);
    end;
  finally
    SB.Free;
  end;
end;

{ W6 C4: whether the overloads (distinct signatures of the routine's name in its unit) are told apart by
  the argument count of every call: the bound overload pBound admits all the calls' counts, no other
  overload admits any of them, and no overload has a default parameter. The index binds a call of an
  overload by name, so only the overload it bound can be trusted -- and only when the counts agree. }
function OverloadsTellApart(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface; const pSigs: TList<string>;
  const pBound: string): Boolean;
var
  Arities: TList<Integer>;
  Done   : TList<Integer>;
begin
  Result:= False;
  var Lines:= pSource.FileLines(pSource.FidOfStem(pSurface.FromStem));
  Arities:= TList<Integer>.Create;
  Done   := TList<Integer>.Create;
  try
    for var R in pSurface.Refs do
    begin
      if Done.Contains(R.Line) then Continue;
      Done.Add(R.Line);
      if not CallArities(Lines, R.Line, pSurface.RoutineName, Arities) then Exit;
    end;
    if Arities.Count = 0 then Exit;
    for var Sig in pSigs do
    begin
      var HasDef: Boolean;
      var N:= SignatureArity(Sig, HasDef);
      if HasDef then Exit;
      var Admits:= False;
      for var A in Arities do
        if A = N then Admits:= True;
      if Sig = pBound then
      begin
        for var A in Arities do
          if A <> N then Exit;
      end
      else if Admits then Exit;
    end;
    Result:= True;
  finally
    Done.Free;
    Arities.Free;
  end;
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
    if (Sigs.Count > 1) and not OverloadsTellApart(pSource, pSurface, Sigs, pRoutine.Signature) then
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
  `<DeclUnit>.<more>` that is itself a unit of the project (e.g. its Untangle leaf) is skipped.
  W6 C7: `<DeclUnit>.<pAllowName>` alone (the inverted routine) is not a finding when pAllowedLines is
  given -- its line is collected there instead. Lane cyc4: only code counts (a comment or a string that
  reads `Unit. Word` is no use), and a name in pMoved is no finding: the plan rewrites it to the leaf. }
function UnitQualifiedLine(const pSource: IEdgeSurfaceSource; const pLines: TArray<string>;
  const pDeclUnit: string; out pMember: string; const pAllowName: string = '';
  pAllowedLines: TList<Integer> = nil; const pMoved: TArray<string> = nil): Integer;
begin
  pMember:= '';
  var Parts:= pDeclUnit.Split(['.']);
  for var I:= 0 to High(Parts) do Parts[I]:= TRegEx.Escape(Parts[I]);
  var Rx:= CUnitQualifierStart + string.Join('\s*\.\s*', Parts) + '\s*\.\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)';
  var Code:= CodeOnlyLines(pLines);
  for var L:= 1 to Length(Code) do
    for var M in TRegEx.Matches(Code[L - 1], Rx, [roIgnoreCase]) do
    begin
      var Tail:= TRegEx.Replace(M.Groups[1].Value, '\s', '').Split(['.']);
      var IsUnit:= False;
      var Name  := pDeclUnit;
      for var Seg in Tail do
      begin
        Name:= Name + '.' + Seg;
        if pSource.FidOfStem(LowerCase(Name)) > 0 then IsUnit:= True;
      end;
      if IsUnit or MatchText(Tail[0], pMoved) then Continue;
      if (pAllowedLines <> nil) and (Length(Tail) = 1) and SameText(Tail[0], pAllowName) then
      begin
        if not pAllowedLines.Contains(L) then pAllowedLines.Add(L);
        Continue;
      end;
      pMember:= Tail[0];
      Exit(L);
    end;
  Result:= 0;
end;

{ W6 C7: whether pText names pName as the VALUE of an assignment (`X := Name`, `X := Unit.Name`), not
  calling it with arguments and not taking its address -- the one non-call use R1 can redirect. }
function IsValueUse(const pText, pName: string): Boolean;
begin
  Result:= TRegEx.IsMatch(pText, ':=\s*(?:[A-Za-z_][\w.]*\s*\.\s*)?' + TRegEx.Escape(pName) + '\b(?!\s*\()', [roIgnoreCase]);
end;

{ Lane cyc4: whether pText passes pName as a whole ARGUMENT (`F(x, Name)`, `F(Unit.Name, y)`). pText must be
  one line of code; an argument on a continuation line of its own shows no `(` or `,` before it and stays
  refused. }
function IsArgumentUse(const pText, pName: string): Boolean;
begin
  Result:= TRegEx.IsMatch(CodeOnlyLines([pText])[0], '[(,]\s*(?:[A-Za-z_][\w.]*\s*\.\s*)?' + TRegEx.Escape(pName) + '\s*[,)]', [roIgnoreCase]);
end;

{ Lane cyc4: whether naming pRoutine without arguments can only mean the routine, never a call of it: a
  procedure has no value, a function with a required parameter cannot be called without it. A parameterless
  function as an argument is its RESULT, and `Pointer(F)` would read a variable differently: refused. }
function NameIsTheRoutine(const pRoutine: TSymbol; const pSig: string): Boolean;
var
  HasDefault: Boolean;
begin
  if pRoutine.Kind = skProcedure then Exit(True);
  Result:= (SignatureArity(pSig, HasDefault) > 0) and not HasDefault;
end;

{ W6 C7: the qualified use `<DeclUnit>.<Name>` on pLine, classified like a bare ref: a call (arguments, or a
  statement of its own), an assignment value or (lane cyc4, when pAllowArg) a whole argument; `@` before it,
  or any other shape, is refused. }
function QualifiedUseOk(const pText, pName, pDeclUnit: string; pAllowArg: Boolean): Boolean;
begin
  var Parts:= pDeclUnit.Split(['.']);
  for var I:= 0 to High(Parts) do Parts[I]:= TRegEx.Escape(Parts[I]);
  var Q:= '(?<![\w.@])' + string.Join('\s*\.\s*', Parts) + '\s*\.\s*' + TRegEx.Escape(pName) + '\b';
  Result:= TRegEx.IsMatch(pText, Q + '\s*\(', [roIgnoreCase]) or TRegEx.IsMatch(pText, '^\s*' + Q + '\s*;', [roIgnoreCase]) or
    IsValueUse(pText, pName) or (pAllowArg and IsArgumentUse(pText, pName));
  if TRegEx.IsMatch(pText, '@\s*(?:[A-Za-z_][\w.]*\s*\.\s*)?' + TRegEx.Escape(pName) + '\b', [roIgnoreCase]) then Result:= False;
end;

{ Lane cycq: PlanRoutineInversion rewrites `Name` and `<DeclUnit>.Name` as TEXT on every line it edits, so each
  occurrence on such a line has to BE the routine. Same-named things bind by scope: `Foo(1); DUnit.Foo(2);` in a
  method of a class with its own Foo became `FooPtr(1); FooPtr(2);`, which compiled and called the wrong routine; a
  local named like the unit makes `DUnit.Foo` a member of that local. The refs of the file say which is which: a bare
  name must have one ref bound to the routine per occurrence (a count, so a column that reads differently cannot
  pass it), a qualified one must not be bound to anything else. A unit-level routine of another used unit counts when
  the uses order binds the name to this routine (BindName decides that for the surface too). Refuses name-shadowed,
  naming the line; a qualified call of ANOTHER overload of the routine refuses overloaded-routine. }
function ShadowRefusal(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface; pFromFid, pDeclFid: Int64;
  const pDeclUnit: string; pQualified: TList<Integer>; const pRoutine: TSymbol): TRecipeRefusal;
var
  Edited: TList<Integer>;
  Owner : TSymbol;
  Stem  : string;
begin
  var Lines:= pSource.FileLines(pFromFid);
  Result:= Default(TRecipeRefusal);
  var Name:= pSurface.RoutineName;
  var Parts:= pDeclUnit.Split(['.']);
  var Escaped:= Copy(Parts);
  for var I:= 0 to High(Escaped) do Escaped[I]:= TRegEx.Escape(Escaped[I]);
  var QualRx:= '(?<![\w.@])(' + string.Join('\s*\.\s*', Escaped) + ')\s*\.\s*(' + TRegEx.Escape(Name) + ')\b';
  var BareRx:= '(?<![\w.])' + TRegEx.Escape(Name) + '\b';
  var Code  := CodeOnlyLines(Lines);
  var Refs  := pSource.Store.GetReferencesFromFile(pFromFid);
  Edited:= TList<Integer>.Create;
  try
    Edited.AddRange(pQualified);
    for var R in pSurface.Refs do
      if not Edited.Contains(R.Line) then Edited.Add(R.Line);
    for var L in Edited do
    begin
      if (L < 1) or (L > Length(Code)) then Continue;
      var Bound:= 0;
      for var R in Refs do
        if (R.StartLine = L) and (R.ReceiverText = '') and SameText(R.NameText, Name) then
        begin
          if R.SymbolId = pRoutine.Id then Inc(Bound)
          else
          begin
            { an unresolved ref (two used units export the name) or another unit's routine: the uses order decides }
            var Outside:= R.SymbolId <= 0;
            if not Outside then
            begin
              var Target:= pSource.Store.GetSymbolById(R.SymbolId);
              Outside:= (Target.FileId <> pFromFid) and (Target.Kind in [skProcedure, skFunction]);
            end;
            if Outside and pSource.BindName(pFromFid, L, Name, Owner, Stem) and (Owner.FileId = pDeclFid) then Inc(Bound);
          end;
        end;
      if TRegEx.Matches(Code[L - 1], BareRx, [roIgnoreCase]).Count <> Bound then
        Exit(MakeRefusal('name-shadowed', Name, pFromFid, L, Format('line %d also names something else called `%s` ' +
          '(`%s`): the plan rewrites a line as text, so that name would become the pointer too', [L, Name, Trim(Lines[L - 1])])));
      for var M in TRegEx.Matches(Code[L - 1], QualRx, [roIgnoreCase]) do
        for var R in Refs do
        begin
          if (R.StartLine <> L) or (R.SymbolId <= 0) then Continue;
          if (R.StartCol = M.Groups[2].Index) and SameText(R.NameText, Name) and (R.SymbolId <> pRoutine.Id) then
            if pSource.Store.GetSymbolById(R.SymbolId).FileId = pDeclFid then
              Exit(MakeRefusal('overloaded-routine', Name, pDeclFid, pRoutine.StartLine, Format('line %d calls another ' +
                'overload of `%s` (`%s`)', [L, Name, Trim(Lines[L - 1])])))
            else
              Exit(MakeRefusal('name-shadowed', Name, pFromFid, L, Format('line %d: `%s` there is not the routine of ' +
                '`%s` (`%s`)', [L, Trim(M.Value), pDeclUnit, Trim(Lines[L - 1])])));
          if (R.StartCol = M.Groups[1].Index) and SameText(R.NameText, Parts[0]) and
            (pSource.Store.GetSymbolById(R.SymbolId).Kind <> skUnit) then
            Exit(MakeRefusal('name-shadowed', Parts[0], pFromFid, L, Format('line %d: `%s` there is a declaration of ' +
              'the consumer, not the unit `%s` (`%s`)', [L, Parts[0], pDeclUnit, Trim(Lines[L - 1])])));
        end;
    end;
  finally
    Edited.Free;
  end;
end;

{ Lane cycq: a symbol that would win over the pointer variable in the consumer, or over the assignment in the
  declaring unit: anything of those two files (their own scope comes before a used unit), or a member of any class
  (a method body sees its class first). A declaration in another used unit loses: the leaf goes last in the uses. }
function PointerHider(const pSource: IEdgeSurfaceSource; const pPtrVar: string; pFromFid, pDeclFid: Int64; out pHider: TSymbol): Boolean;
begin
  for var S in pSource.Store.FindSymbolsByExactName(pPtrVar) do
    if (S.FileId = pFromFid) or (S.FileId = pDeclFid) or (S.Kind in [skMethod, skField, skProperty]) then
    begin
      pHider:= S;
      Exit(True);
    end;
  pHider:= Default(TSymbol);
  Result:= False;
end;

{ R1 refusals a call site can give: not a call, a name qualified by the declaring unit
  anywhere in the consumer (the uses entry it needs would be removed), init order (J4).
  W6 C7: the inverted routine itself, qualified (`B.Foo(...)`) or assigned as a value (`X := Foo`), is
  redirected to the pointer under the same init-order check; any other `B.X` and `@Foo` still refuse.
  pQualified receives the lines that name the inverted routine qualified.
  Lane cyc4: a routine passed as a whole argument (`F(x, Foo)`) is redirected too (see NameIsTheRoutine), a
  `B.G` the plan moves (pSurface.QualifiedMoved) is rewritten, and a call that runs from the finalization
  section refuses finalization-order when the declaring unit's finalization can be seen (FinalOrderWhy). }
function CallRefusal(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface; pFromFid: Int64;
  const pLines: TArray<string>; const pFromUnit, pDeclUnit: string; pQualified: TList<Integer>;
  const pRoutine: TSymbol; pDeclFid: Int64): TRecipeRefusal;
var
  Member: string;
begin
  Result:= Default(TRecipeRefusal);
  var Name:= pSurface.RoutineName;
  var AllowArg:= NameIsTheRoutine(pRoutine, pSurface.RoutineSig);
  var Q:= UnitQualifiedLine(pSource, pLines, pDeclUnit, Member, Name, pQualified, pSurface.QualifiedMoved);
  if Q > 0 then
    Exit(MakeRefusal('qualified-ref', Member, pFromFid, Q, Format('line %d names `%s` qualified by its unit ' +
      '(`%s`); that use keeps needing the uses entry the cut removes', [Q, Member, Trim(pLines[Q - 1])])));
  Result:= ShadowRefusal(pSource, pSurface, pFromFid, pDeclFid, pDeclUnit, pQualified, pRoutine);
  if Result.Kind <> '' then Exit;
  for var L in pQualified do
  begin
    if not QualifiedUseOk(BareCode(LineOf(pLines, L)), Name, pDeclUnit, AllowArg) then
      Exit(MakeRefusal('qualified-ref', Name, pFromFid, L, Format('line %d names `%s` qualified by its unit in a ' +
        'shape the plan cannot redirect (`%s`)', [L, Name, Trim(LineOf(pLines, L))])));
    var Ref:= Default(TEdgeRef);
    Ref.Line:= L;
    var Encl:= pSource.Store.FindEnclosingRoutineByImpl(pFromFid, L);
    if Encl.Id > 0 then Ref.Enclosing:= Encl.Name;
    var QWhy:= InitOrderWhy(pLines, Ref, pFromUnit);
    if QWhy <> '' then Exit(MakeRefusal('init-order', Name, pFromFid, L, QWhy));
    QWhy:= FinalOrderWhy(pSource, pLines, Ref, pFromUnit, pDeclFid, pDeclUnit);
    if QWhy <> '' then Exit(MakeRefusal('finalization-order', Name, pFromFid, L, QWhy));
  end;
  for var R in pSurface.Refs do
  begin
    if (R.Kind <> erCall) and not ((IsValueUse(R.LineText, Name) or (AllowArg and IsArgumentUse(R.LineText, Name))) and
      not TRegEx.IsMatch(R.LineText, '@\s*' + TRegEx.Escape(Name) + '\b', [roIgnoreCase])) then
      Exit(MakeRefusal('routine-not-called', Name, pFromFid, R.Line, Format('line %d uses `%s` without ' +
        'calling it (`%s`)', [R.Line, Name, R.LineText])));
    var Why:= InitOrderWhy(pLines, R, pFromUnit);
    if Why <> '' then Exit(MakeRefusal('init-order', Name, pFromFid, R.Line, Why));
    Why:= FinalOrderWhy(pSource, pLines, R, pFromUnit, pDeclFid, pDeclUnit);
    if Why <> '' then Exit(MakeRefusal('finalization-order', Name, pFromFid, R.Line, Why));
  end;
end;

function PlanRoutineInversion(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface;
  out pRefusal: TRecipeRefusal; pSuffix: Integer): TRecipeSteps;
var
  Routine  : TSymbol;
  Edits    : TList<TRecipeEdit>;
  Done     : TList<Integer>;
  Qualified: TList<Integer>;
  E        : TRecipeEdit;
  Conv     : string;
  Why      : string;
begin
  Result  := Default(TRecipeSteps);
  var FromFid:= pSource.FidOfStem(pSurface.FromStem);
  var DeclFid:= pSource.FidOfStem(pSurface.ToStem);
  var Name   := pSurface.RoutineName;
  var Lines  := pSource.FileLines(FromFid);
  Qualified:= TList<Integer>.Create;
  Edits    := TList<TRecipeEdit>.Create;
  Done     := TList<Integer>.Create;
  try
    pRefusal:= SignatureRefusal(pSource, pSurface, DeclFid, Routine);
    if pRefusal.Kind = '' then
      pRefusal:= CallRefusal(pSource, pSurface, FromFid, Lines,
        ChangeFileExt(ExtractFileName(pSource.Store.GetFilePath(FromFid)), ''),
        ChangeFileExt(ExtractFileName(pSource.Store.GetFilePath(DeclFid)), ''), Qualified, Routine, DeclFid);
    if (pRefusal.Kind = '') and not DeclConvention(pSource.FileLines(DeclFid), Routine.StartLine, Name, Conv, Why) then
      pRefusal:= MakeRefusal('unsupported-directive', Name, DeclFid, Routine.StartLine, Format('`%s`: %s', [Name, Why]));
    if pRefusal.Kind <> '' then Exit;
    Result.Recipe     := crRoutineInversion;
    Result.RoutineId  := Routine.Id;
    Result.RoutineName:= Name;
    Result.DeclStem   := pSurface.ToStem;
    Result.ConsumerFid:= FromFid;
    Result.PtrVar     := Name + 'Ptr' + (if pSuffix > 1 then IntToStr(pSuffix) else '');
    var Hider: TSymbol;
    if PointerHider(pSource, Result.PtrVar, FromFid, DeclFid, Hider) then
    begin
      pRefusal:= MakeRefusal('duplicate-identifier', Result.PtrVar, Hider.FileId, Hider.StartLine, Format('`%s` is already ' +
        'declared at `%s:%d` and would win over the pointer of that name', [Result.PtrVar,
        ExtractFileName(pSource.Store.GetFilePath(Hider.FileId)), Hider.StartLine]));
      Exit(Default(TRecipeSteps));
    end;
    Result.PtrType    := 'T' + Result.PtrVar;
    Result.TypeDecl   := Format('%s = %s%s;%s', [Result.PtrType,
      (if Routine.Kind = skFunction then 'function' else 'procedure'), pSurface.RoutineSig,
      (if Conv <> '' then ' ' + Conv + ';' else '')]);
    Result.VarDecl    := Format('%s: %s;', [Result.PtrVar, Result.PtrType]);
    Result.LeafStem   := PickExistingLeaf(pSource, pSurface, FromFid, DeclFid);
    for var R in pSurface.Refs do
      if not Qualified.Contains(R.Line) then Qualified.Add(R.Line);  { W6 C7: Qualified now holds every line to edit }
    Qualified.Sort;
    var QualRx:= '(?<![\w.@])' + TRegEx.Escape(ChangeFileExt(ExtractFileName(pSource.Store.GetFilePath(DeclFid)), '')).Replace('\.',
      '\s*\.\s*') + '\s*\.\s*' + TRegEx.Escape(Name) + '\b';
    var Starts:= CodeStarts(Lines);  { B11: a string or a comment naming the routine stays as written }
    for var L in Qualified do
    begin
      if Done.Contains(L) then Continue;
      Done.Add(L);
      E:= Default(TRecipeEdit);
      E.Fid     := FromFid;
      E.Line    := L;
      E.Replace := True;
      E.NewLines:= [ReplaceInCode(ReplaceInCode(LineOf(Lines, L), StartAt(Starts, L), QualRx, Result.PtrVar),
        StartAt(Starts, L), '(?<![\w.])' + TRegEx.Escape(Name) + '\b', Result.PtrVar)];
      Edits.Add(E);
    end;
    if not AssignmentEdit(pSource.FileLines(DeclFid), DeclFid, [Format('  %s := %s;', [Result.PtrVar, Name])], E) then
    begin
      pRefusal:= MakeRefusal('manual-edit', Name, DeclFid, 0, 'the declaring unit has no final `end.`');
      Exit(Default(TRecipeSteps));
    end;
    Edits.Add(E);
    Result.Edits:= Edits.ToArray;
  finally
    Done.Free;
    Edits.Free;
    Qualified.Free;
  end;
  var One:= Default(TInvertedRoutine);
  One.Id      := Result.RoutineId;
  One.Name    := Name;
  One.PtrType := Result.PtrType;
  One.PtrVar  := Result.PtrVar;
  One.TypeDecl:= Result.TypeDecl;
  One.VarDecl := Result.VarDecl;
  Result.Routines:= [One];
end;

{ B3: the slice of pSurface that is the one routine pRoutineId -- its refs, its signature, and
  its signature types with a type of the declaring unit named in pMovedTypes counted as
  outside the cycle (it moves into the leaf, where the pointer type can name it). }
function RoutineSlice(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface; pRoutineId: Int64;
  const pMovedTypes: TArray<string>): TEdgeSurface;
var
  Refs: TList<TEdgeRef>;
begin
  Result:= pSurface;
  var Routine:= pSource.Store.GetSymbolById(pRoutineId);
  Refs:= TList<TEdgeRef>.Create;
  try
    Result.CallCount:= 0;
    for var R in pSurface.Refs do
      if R.SymbolId = pRoutineId then
      begin
        Refs.Add(R);
        if R.Kind = erCall then Inc(Result.CallCount);
      end;
    Result.Refs:= Refs.ToArray;
  finally
    Refs.Free;
  end;
  Result.RoutineIds := [pRoutineId];
  Result.RoutineName:= Routine.Name;
  Result.RoutineSig := Routine.Signature;
  Result.SigTypes   := SignatureTypes(pSource, Routine.FileId, Routine.StartLine, Routine.Signature);
  for var I:= 0 to High(Result.SigTypes) do
  begin
    var T:= Result.SigTypes[I];
    if T.InScc and (T.DeclStem = pSurface.ToStem) and
      MatchText(T.Name.Substring(T.Name.LastIndexOf('.') + 1), pMovedTypes) then
    begin
      T.InScc   := False;
      T.DeclStem:= '';  { no J2 leaf can declare it: it moves into B's Untangle leaf }
      Result.SigTypes[I]:= T;
    end;
  end;
end;

function PlanRoutinesInversion(const pSource: IEdgeSurfaceSource; const pSurface: TEdgeSurface;
  const pMovedTypes: TArray<string>; out pRefusal: TRecipeRefusal): TRecipeSteps;
var
  Parts  : TList<TRecipeSteps>;
  Lines  : TList<Integer>;
  Assigns: TList<string>;
  Edits  : TList<TRecipeEdit>;
  E      : TRecipeEdit;
begin
  Result  := Default(TRecipeSteps);
  pRefusal:= Default(TRecipeRefusal);
  if Length(pSurface.RoutineIds) = 0 then
    Exit(PlanRoutineInversion(pSource, pSurface, pRefusal));
  Parts  := TList<TRecipeSteps>.Create;
  Lines  := TList<Integer>.Create;
  Assigns:= TList<string>.Create;
  Edits  := TList<TRecipeEdit>.Create;
  try
    for var Id in pSurface.RoutineIds do
    begin
      var Steps:= PlanRoutineInversion(pSource, RoutineSlice(pSource, pSurface, Id, pMovedTypes), pRefusal);
      if pRefusal.Kind <> '' then Exit(Default(TRecipeSteps));
      Parts.Add(Steps);
    end;
    if (Parts.Count = 1) and (Length(pMovedTypes) = 0) then Exit(Parts[0]);
    Result:= Parts[0];
    Result.Routines:= nil;
    for var P in Parts do
    begin
      Result.Routines:= Result.Routines + P.Routines;
      if (P.LeafStem <> Result.LeafStem) or (Length(pMovedTypes) > 0) then Result.LeafStem:= '';
      for var R in P.Edits do
        if (R.Fid = Result.ConsumerFid) and not Lines.Contains(R.Line) then Lines.Add(R.Line);
    end;
    { every call line once, with every routine's name replaced by its pointer }
    var FromLines:= pSource.FileLines(Result.ConsumerFid);
    var DeclFid  := pSource.FidOfStem(pSurface.ToStem);
    { W6 C7: a name qualified by the declaring unit (`B.Foo`) becomes the pointer too }
    var UnitRx:= TRegEx.Escape(ChangeFileExt(ExtractFileName(pSource.Store.GetFilePath(DeclFid)), '')).Replace('\.',
      '\s*\.\s*') + '\s*\.\s*';
    Lines.Sort;
    var Starts:= CodeStarts(FromLines);  { B11: as PlanRoutineInversion }
    for var L in Lines do
    begin
      var Text:= LineOf(FromLines, L);
      for var R in Result.Routines do
        Text:= ReplaceInCode(ReplaceInCode(Text, StartAt(Starts, L), '(?<![\w.@])' + UnitRx + TRegEx.Escape(R.Name) + '\b',
          R.PtrVar), StartAt(Starts, L), '(?<![\w.])' + TRegEx.Escape(R.Name) + '\b', R.PtrVar);
      E:= Default(TRecipeEdit);
      E.Fid     := Result.ConsumerFid;
      E.Line    := L;
      E.Replace := True;
      E.NewLines:= [Text];
      Edits.Add(E);
    end;
    for var R in Result.Routines do Assigns.Add(Format('  %s := %s;', [R.PtrVar, R.Name]));
    { PlanRoutineInversion already made one such edit per routine, so this cannot fail }
    AssignmentEdit(pSource.FileLines(DeclFid), DeclFid, Assigns.ToArray, E);
    Edits.Add(E);
    Result.Edits:= Edits.ToArray;
  finally
    Edits.Free;
    Assigns.Free;
    Lines.Free;
    Parts.Free;
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
  CSysConstUnit   = 'System.SysConst'; // lane 148 CY: SInvalidCast, for the As<Surface> helper
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

  { A class chain's member a consumer names: the nearest declaration (its visibility decides) and the
    nearest holding a type; a redeclaration without one has Sym <> TypedSym. }
  TChainMember = record
    Owner   : TStoredType;
    Typed   : TStoredType;
    Sym     : TSymbol;
    TypedSym: TSymbol;
  end;

  { The indexes R2 reads types from: the project first, then the platform library.
    A library type's ancestors are looked up in the library only. }
  TTypeIndex = record
    Project: ISymbolStore;
    Lib    : ISymbolStore;
    function Find(const pName: string; pLibOnly: Boolean; out pType: TStoredType): Boolean;
    function FindFrom(const pName: string; const pFrom: TStoredType; out pType: TStoredType): Boolean;
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

{ 1.43: the ancestor pName of pFrom as pFrom's own unit sees it. The library holds both Vcl.StdCtrls.TLabel and
  FMX.StdCtrls.TLabel (TForm, TEdit, TButton the same) and Find takes the widest: the wrong chain hides members
  from a `with` check. A library name declared by several units is taken from pFrom's unit, else from the last uses
  entry of pFrom's file that names one of them; with none, what Find answers. }
function TTypeIndex.FindFrom(const pName: string; const pFrom: TStoredType; out pType: TStoredType): Boolean;
begin
  Result:= Find(pName, IsLib(pFrom), pType);
  if not Result or not IsLib(pType) then Exit;
  var Candidates: TArray<TSymbol>:= nil;
  for var S in Lib.FindSymbolsByExactName(BareTypeName(pName)) do
    if (S.Kind in [skClass, skInterface]) and (S.FileId <> pType.Sym.FileId) then Candidates:= Candidates + [S];
  if Candidates = nil then Exit;
  Candidates:= Candidates + [pType.Sym];
  for var S in Candidates do
    if IsLib(pFrom) and (S.FileId = pFrom.Sym.FileId) and (S.EndLine > S.StartLine) then
    begin
      pType.Sym:= S;
      Exit;
    end;
  var Entries:= pFrom.Store.GetUnitUsesForFile(pFrom.Sym.FileId);
  for var I:= High(Entries) downto 0 do
    for var S in Candidates do
    begin
      var U:= UnitOfFile(Lib.GetFilePath(S.FileId));
      if (S.EndLine > S.StartLine) and (SameText(U, Entries[I].UnitName) or EndsText('.' + Entries[I].UnitName, U)) then
      begin
        pType.Sym:= S;
        Exit;
      end;
    end;
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
    if not pIdx.FindFrom(P, Cur, Next) then Break;
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

function EnclosingTypeOf(const pProject: ISymbolStore; pEnclosingId: Int64): TSymbol;
begin
  Result:= pProject.GetSymbolById(pEnclosingId);
  for var Up:= 1 to CMaxAncestorHops do
  begin
    if (Result.Id <= 0) or (Result.Kind in [skClass, skRecord, skUnit, skProgram, skPackage]) or (Result.ParentId <= 0) then Break;
    Result:= pProject.GetSymbolById(Result.ParentId);
  end;
end;

{ C3: whether pName is a member (not a parameter or local) of the class or record that
  encloses symbol pEnclosingId, or of one of its ancestors in the project or the library --
  a bare name the consumer resolves to its own (inherited) member, not to a cycle unit. }
function IsClassChainMember(const pProject, pLibrary: ISymbolStore; pEnclosingId: Int64;
  const pName: string): Boolean;
var
  Idx  : TTypeIndex;
  Cur  : TStoredType;
  Next : TStoredType;
begin
  Result:= False;
  if (pProject = nil) or (pEnclosingId <= 0) or (pName = '') then Exit;
  var S:= EnclosingTypeOf(pProject, pEnclosingId);
  if (S.Id <= 0) or not (S.Kind in [skClass, skRecord]) then Exit;
  Idx.Project:= pProject;
  Idx.Lib    := pLibrary;
  Cur.Sym    := S;
  Cur.Store  := pProject;
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    var M:= Cur.Store.FindChildSymbolByName(Cur.Sym.Id, pName);
    if (M.Id > 0) and not (M.Kind in [skParam, skLocalVar]) then Exit(True);
    if not Idx.Find(Idx.ParentOf(Cur), Idx.IsLib(Cur), Next) then Exit;
    Cur:= Next;
  end;
end;

// The code of a line without string literals and brace comments.
function PlainCode(const pLine: string): string;
begin
  Result:= TRegEx.Replace(TRegEx.Replace(BareCode(pLine), '''[^'']*''', ''''''), '\{[^}]*\}', ' ');
end;

const
  { compiler intrinsics that take their arguments by value (B1) }
  CValueIntrinsics: array[0..13] of string = ('Exit', 'Ord', 'Chr', 'Abs', 'Length', 'High', 'Low', 'Succ', 'Pred',
    'Assigned', 'SizeOf', 'Odd', 'Round', 'Trunc');
  { words a `(` follows that are no call }
  CIdentChars = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  CNoCallee: array[0..13] of string = ('if', 'while', 'until', 'not', 'and', 'or', 'xor', 'div', 'mod', 'in', 'then',
    'do', 'of', 'case');

{ B1: whether the routine pS takes a parameter by var / out / [ref]; a type (a cast) does not. }
function SignatureMayWrite(const pS: TSymbol): Boolean;
begin
  Result:= (pS.Kind in [skProcedure, skFunction, skMethod, skConstructor]) and
    TRegEx.IsMatch(pS.Signature, '\b(var|out)\s|\[\s*ref\s*\]', [roIgnoreCase]);
end;
{ B1: the 1-based index of the last character before pAt that is not a blank, or 0. }
function SkipBlanksBack(const pCode: string; pAt: Integer): Integer;
begin
  Result:= pAt;
  while (Result >= 1) and (pCode[Result] = ' ') do Dec(Result);
end;

{ B1: back from pAt (the character before a member name) over a receiver chain -- `X.`,
  `A.B.`, `(A as T).`, `T(A).` -- to the first character before it that is not a blank. }
function SkipReceiverBack(const pCode: string; pAt: Integer): Integer;
begin
  Result:= SkipBlanksBack(pCode, pAt);
  while (Result >= 1) and (pCode[Result] = '.') do
  begin
    Result:= SkipBlanksBack(pCode, Result - 1);
    if (Result >= 1) and (pCode[Result] = ')') then
    begin
      var Nest:= 0;
      repeat
        if pCode[Result] = ')' then Inc(Nest) else if pCode[Result] = '(' then Dec(Nest);
        Dec(Result);
      until (Result < 1) or (Nest = 0);
    end;
    while (Result >= 1) and CharInSet(pCode[Result], CIdentChars) do Dec(Result);
    Result:= SkipBlanksBack(pCode, Result);
  end;
end;

{ B1: the innermost bracket `(` or `[` still open at pAt (counting back), or 0. }
function OpenBracketBack(const pCode: string; pAt: Integer): Integer;
begin
  var Depth:= 0;
  for var I:= pAt downto 1 do
    if CharInSet(pCode[I], [')', ']']) then Inc(Depth)
    else if CharInSet(pCode[I], ['(', '[']) then
    begin
      if Depth = 0 then Exit(I);
      Dec(Depth);
    end;
  Result:= 0;
end;

{ B1: the identifier right before the `(` at pOpen, when it names a call (no keyword, no
  number); else ''. }
function CalleeBefore(const pCode: string; pOpen: Integer): string;
begin
  var E:= SkipBlanksBack(pCode, pOpen - 1);
  var B:= E;
  while (B >= 1) and CharInSet(pCode[B], CIdentChars) do Dec(B);
  Result:= Copy(pCode, B + 1, E - B);
  if (Result <> '') and (CharInSet(Result[1], ['0'..'9']) or MatchText(Result, CNoCallee)) then Result:= '';
end;

{ B1: the routine of which pName is a WHOLE argument in pCode (`Foo(X.F)`, `Foo(1, F)`,
  `Foo((A as T).F, 2)`), or '' -- an element of an open-array constructor `[F]`, a part of
  an expression or a parenthesised operand is no argument. }
function CallArgumentCallee(const pCode, pName: string): string;
begin
  Result:= '';
  for var Mt in TRegEx.Matches(pCode, '(?<!\w)' + TRegEx.Escape(pName) + '(?!\w)', [roIgnoreCase]) do
  begin
    var K:= Mt.Index + Mt.Length;
    while (K <= Length(pCode)) and (pCode[K] = ' ') do Inc(K);
    if (K > Length(pCode)) or not CharInSet(pCode[K], [',', ')']) then Continue;
    var J:= SkipReceiverBack(pCode, Mt.Index - 1);
    if (J < 1) or not CharInSet(pCode[J], ['(', ',']) then Continue;
    var Open:= OpenBracketBack(pCode, J);
    if (Open > 0) and (pCode[Open] = '(') then Result:= CalleeBefore(pCode, Open);
    if Result <> '' then Exit;
  end;
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

{ Whether the `as pClass` on line pLine is an item of a `with` head: `with` precedes it on that line, or
  on an earlier line with nothing but the rest of the head between (`with A as TA,` / `  B as TB do`). }
function IsWithHeadLine(const pLines: TArray<string>; pLine: Integer; const pClass: string): Boolean;
const
  CHeadEnd      = '\b(do|then|else|begin|end|of|try|repeat|except|finally)\b|;';
  CWithWord     = '\bwith\b';
  CMaxHeadLines = 8;  { a `with` head longer than this is not written by hand }
begin
  var Code:= PlainCode(LineOf(pLines, pLine));
  var AsAt:= TRegEx.Match(Code, '\bas\s+' + TRegEx.Escape(pClass) + '\b', [roIgnoreCase]);
  if not AsAt.Success then Exit(False);
  var Before:= Copy(Code, 1, AsAt.Index - 1);
  if TRegEx.IsMatch(Before, CWithWord, [roIgnoreCase]) then Exit(True);
  if TRegEx.IsMatch(Before, CHeadEnd, [roIgnoreCase]) then Exit(False);
  for var L:= pLine - 1 downto Max(1, pLine - CMaxHeadLines) do
  begin
    var Prev:= PlainCode(LineOf(pLines, L));
    var Withs:= TRegEx.Matches(Prev, CWithWord, [roIgnoreCase]);
    if Withs.Count > 0 then
      Exit(not TRegEx.IsMatch(Copy(Prev, Withs[Withs.Count - 1].Index + Withs[Withs.Count - 1].Length, MaxInt), CHeadEnd,
        [roIgnoreCase]));
    if TRegEx.IsMatch(Prev, CHeadEnd, [roIgnoreCase]) then Exit(False);
  end;
  Result:= False;
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

const
  { B2 (R2m): directives only a class method declaration takes; the class keeps them and the
    interface declaration drops them (an interface method implemented by a virtual method
    dispatches virtually: run_cyclefix_instmethod_dcc.ps1 pins it) }
  CMethodOnlyDirectives = ' virtual override dynamic reintroduce abstract final ';

{ B2 (R2m): the directive run after the method pName declared at line pLine of its class:
  the calling convention in pConv, pOverload when `overload` is among them. False, with
  pWhy, on a directive an interface method cannot carry (message, dispid, varargs, any word
  this planner cannot classify), a compiler directive inside the declaration, or text it
  cannot read. The scan mirrors DeclConvention (R1). }
function MethodDirectives(const pLines: TArray<string>; pLine: Integer; const pName: string;
  out pConv, pWhy: string; out pOverload: Boolean): Boolean;
var
  Depth: Integer;
begin
  pConv    := '';
  pWhy     := '';
  pOverload:= False;
  var Text:= '';
  for var L:= pLine to Min(pLine + CMaxDeclLines - 1, Length(pLines)) do Text:= Text + BareCode(LineOf(pLines, L)) + ' ';  // dl:ok duplicate-code@e7f0 -- mirrors the R1 DeclConvention scan with method directives; left separate so lanes editing R1 do not collide
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
    else if Word = 'overload' then pOverload:= True
    else if not ContainsStr(CMethodOnlyDirectives + CNeutralDirectives, ' ' + Word + ' ') then
    begin
      if StartsNextDeclaration(Text, P + W.Length, Word) then Break;
      pWhy:= Format('the directive `%s` is not one an interface method can carry', [Word]);
      Exit(False);
    end;
    Inc(P, W.Length);
    if not SkipPastSemicolon(Text, P) then Break;
  end;
  Result:= True;
end;

{ B2 (R2m): whether the line pCode takes the method pName without calling it. A bare name is
  a call when an argument list follows it, when it is a procedure statement, or when it is a
  function in an expression; `@M`, or a procedure named anywhere else (`OnX := M`, `F(M)`),
  is a method pointer -- an interface method cannot be one -- whatever refs.kind the index
  gave the name. }
function MethodTakenAt(const pCode, pName: string; pIsFunc: Boolean): Boolean;
begin
  var N:= TRegEx.Escape(pName);
  Result:= TRegEx.IsMatch(pCode, '@\s*' + N + '\b', [roIgnoreCase]) or (not pIsFunc and
    not TRegEx.IsMatch(pCode, '(^|;|\b(do|then|else|begin|try|finally|except)\b)\s*' + N + '\s*(;|$|\b(end|else)\b)|\b' +
    N + '\s*\(', [roIgnoreCase]));
end;

type
  { One PlanMemberInterface run: the edge, the class, and the steps being built. }  TMemberPlan = class  // dl:ok high-response@c843, god-class@c843 -- implementation-private one-shot planner of one edge; the response set is its check steps plus the store and RTL calls they make
  private
    FSource  : IEdgeSurfaceSource;
    FStore   : ISymbolStore;
    FIdx     : TTypeIndex;
    FScopes  : TArray<string>;
    FSurface : TEdgeSurface;
    FFromFid : Int64;
    FClsFid  : Int64;
    FLines   : TArray<string>;
    FStarts  : TArray<TCodeStart>;  // B11: of FLines, on first use (StartOf)
    FClsLines: TArray<string>;
    FCls     : TSymbol;
    FIface   : string;
    FMembers : TList<TSymbol>;
    FGetters : TList<string>;
    FReads   : TList<string>;  // per member: what its getter returns
    FSetters : TArray<string>; // per member: its setter (B1), '' when the consumer only reads it
    FEdits   : TList<TRecipeEdit>;
    FUses    : TList<string>;  // consumer implementation uses to add
    FLeafUses: TList<string>;
    FWithLines: TList<Integer>;
    FCastUsed: Boolean;
    FCastAnc : string;
    FAsHelper: string;  // lane 148 CY: the raise-preserving cast helper, '' when not needed
    FHandles : Boolean;  // lane 149 CYB: the consumer names EInvalidCast
    FHardCastChange: Boolean;  // lane 149 CYB: a hard cast was rewritten while FHandles
    FRefusal : TRecipeRefusal;
    FMethods : TList<TSymbol>;  // B2: instance methods carried as interface methods
    FMethodDecls: TList<string>;  // B2: their interface declarations
    FKeptGetters: TList<string>;  // W6 C2: `Get<M>` the class declares already, reused as the getter
    FIndexed : TDictionary<Int64, string>;  // W6 C7: member id -> its index parameter list (indexed property)
    function GetterReusable(const pM, pDup: TSymbol): Boolean;
    function IndexedPropertyOk(const pM: TSymbol; const pR: TEdgeRef): Boolean;
    function IndexList(pI: Integer; const pOpen, pClose: string): string;
    function CarriedMethodOf(const pR: TEdgeRef; const pS: TSymbol): TSymbol;
    function CheckMethod(const pR: TEdgeRef; const pM: TSymbol): Boolean;
    function CheckMethods: Boolean;
    function CheckMethodMentions: Boolean;
    function Refuse(const pKind, pSymbol: string; pFid: Int64; pLine: Integer; const pReason: string): Boolean;
    function Stored(const pSym: TSymbol): TStoredType;
    function StartOf(pLine: Integer): TCodeStart;
    function RefRefusal(const pR: TEdgeRef; out pKind, pWhat: string): Boolean;
    function HardCastWhat(const pR: TEdgeRef; const pCls: TSymbol): string;
    function GuardedBefore(const pX: string; pEnclosing: Int64; pLine: Integer): Boolean;
    function CheckShape: Boolean;
    function LocalDeclOf(const pR: TEdgeRef; out pLocal: TSymbol): Boolean;
    function LocalUseWhy(const pLocal, pRoutine: TSymbol; out pLine: Integer): string;
    function CheckTypeDecls: Boolean;
    function InheritedWhy(const pM: TSymbol; out pKind: string): string;
    function CheckMembers: Boolean;
    function MemberOf(const pR: TEdgeRef): TSymbol;
    function MemberUseRefusal(const pR: TEdgeRef; out pKind, pWhat: string): Boolean;
    function MemberShapeWhy(const pR: TEdgeRef; const pS: TSymbol): string;
    function CallMayWrite(const pCallee: string; pLine: Integer): Boolean;
    function CheckWrites: Boolean;
    procedure AddSetterLines(pI: Integer; const pIndent: string; pDecls, pBodies: TList<string>);
    procedure AddIfaceSetters(pL: TList<string>);
    function WriteClause(pI: Integer): string;
    function CheckClass: Boolean;
    function ConsumerSees(const pUnit: string): Boolean;
    function ReceiverType(const pX: string; pEnclosing: Int64; out pType: string): Boolean;
    function RewriteLine(pLine: Integer; pEnclosing: Int64; out pText: string): Boolean;
    function RewriteConsumer: Boolean;
    function CheckCastUnit: Boolean;
    procedure SkipCycleAncestors;
    function BareBodyRefs(pWith: Integer; const pRefs: TArray<TReference>): TArray<TReference>;
    function ChainMemberOf(const pName: string; out pMember: TChainMember): Boolean;
    function FirstCarry(const pR: TReference; pInWith: Boolean; pNames, pChain: TStringList;
      pCarried: TDictionary<string, Integer>; out pIdx: Integer): Boolean;
    function CarryUse(const pR: TReference; pIdx: Integer; pChain: TStringList): Boolean;
    function CarryChainMember(const pR: TReference; pInWith: Boolean; pNames, pChain: TStringList;
      pCarried: TDictionary<string, Integer>): Boolean;
    procedure RemoveCarriedNames(pNames: TStringList);
    function CheckCastChainMembers: Boolean;
    function CheckWithBodies: Boolean;
    function LibUnitOf(const pIdent: string): string;
    function IsScopeRoot(const pSegment: string): Boolean;
    function KnownUnitPrefix(const pSegments: TArray<string>; pCount: Integer): string;
    function LibDeclaresIn(const pIdent, pUnit: string): Boolean;
    function AddLeafUse(const pM: TSymbol; const pTypeName, pShown: string): Boolean;
    function AddNestedLeafUse(const pM: TSymbol; const pOuter, pShown: string): Boolean;
    function CheckCastExceptions: Boolean;
    function AsHelperName: string;
    function AsHelperLines: TArray<string>;
    function AsHelperAnchor: Integer;
    function CollectLeafUses: Boolean;
    procedure AddEdit(pFid: Int64; pLine: Integer; pReplace: Boolean; const pLines: TArray<string>);
    procedure BuildClassEdits;
    function IfaceDecl(const pLeafUnit: string): TArray<string>;
  public
    constructor Create(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore; const pSurface: TEdgeSurface;
      const pUnitScopes: TArray<string>);
    destructor Destroy; override;
    function Run(const pLeafUnit, pIfaceName: string; out pRefusal: TRecipeRefusal): TRecipeSteps;
  end;

constructor TMemberPlan.Create(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore;
  const pSurface: TEdgeSurface; const pUnitScopes: TArray<string>);
begin
  inherited Create;
  FScopes     := if Length(pUnitScopes) > 0 then pUnitScopes else EffectiveUnitScopes('');
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
  FMethods    := TList<TSymbol>.Create;
  FMethodDecls:= TList<string>.Create;
  FKeptGetters:= TList<string>.Create;
  FIndexed    := TDictionary<Int64, string>.Create;
end;

destructor TMemberPlan.Destroy;
begin
  FIndexed.Free;
  FKeptGetters.Free;
  FMethodDecls.Free;
  FMethods.Free;
  FWithLines.Free;
  FLeafUses.Free;
  FUses.Free;
  FEdits.Free;
  FReads.Free;
  FGetters.Free;
  FMembers.Free;
  inherited Destroy;
end;

{ W6 C2: the class already declares `Get<M>`. It serves as the interface getter unchanged only when
  it is exactly `function Get<M>: <T>;` (no parameters, no directive) AND the property M reads
  through it -- then `ISurface.M` returns what `TX.M` returns. Any other GetM (another signature,
  or a method the property does not read through) keeps the refusal: its value is not M's. }
function TMemberPlan.GetterReusable(const pM, pDup: TSymbol): Boolean;
begin
  if (pM.Kind <> skProperty) or not (pDup.Kind in [skMethod, skFunction]) then Exit(False);
  var Decl:= '';
  for var L:= pDup.StartLine to Max(pDup.StartLine, pDup.EndLine) do Decl:= Decl + ' ' + BareCode(LineOf(FClsLines, L));
  if not TRegEx.IsMatch(Trim(Decl), '^function\s+' + TRegEx.Escape(pDup.Name) + '\s*:\s*' +
    TRegEx.Escape(Trim(pM.Signature)) + '\s*;$', [roIgnoreCase]) then Exit(False);
  var Prop:= '';
  for var L:= pM.StartLine to Max(pM.StartLine, pM.EndLine) do Prop:= Prop + ' ' + BareCode(LineOf(FClsLines, L));
  Result:= TRegEx.IsMatch(Prop, '\bread\s+' + TRegEx.Escape(pDup.Name) + '\b', [roIgnoreCase]);
end;

function TMemberPlan.Refuse(const pKind, pSymbol: string; pFid: Int64; pLine: Integer; const pReason: string): Boolean;
begin
  FRefusal:= MakeRefusal(pKind, pSymbol, pFid, pLine, pReason);
  Result  := False;
end;

function TMemberPlan.StartOf(pLine: Integer): TCodeStart;
begin
  if FStarts = nil then FStarts:= CodeStarts(FLines);
  Result:= StartAt(FStarts, pLine);
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
  if CarriedMethodOf(pR, S).Id > 0 then Exit(False);  { B2: CheckMethods decides }
  case pR.Kind of
    erTypeIs, erTypeAs: Exit(False);
    erMemberRead, erMemberWrite: Exit(MemberUseRefusal(pR, pKind, pWhat));
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
        var Local: TSymbol;
        if LocalDeclOf(pR, Local) then Exit(False);  { CYC-C (1): CheckTypeDecls decides }
        pKind:= 'type-decl';
        pWhat:= Format('declares something of type `%s`, which would still need its unit', [pR.Name]);
      end;
    erTypeCast:
      begin
        { C7: `TX(Y).M` with M a field / property of TX is carried; any other cast stays }
        pWhat:= HardCastWhat(pR, S);
        if pWhat = '' then Exit(False);
        pKind:= 'type-cast';
      end;
    erCall:
      if (S.Kind = skClass) and SameText(pR.Name, S.Name) then
      begin
        pWhat:= HardCastWhat(pR, S);
        if pWhat = '' then Exit(False);
        pKind:= 'type-cast';
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

{ C7: '' when every hard cast `TX(...)` of the line is `TX(name).M` with M a field or property TX
  declares itself (the surface synthesised that member's read / write; RewriteLine turns the cast
  into `(name as ISurface).M`); else why the cast cannot be carried. }
function TMemberPlan.HardCastWhat(const pR: TEdgeRef; const pCls: TSymbol): string;
begin
  var C    := TRegEx.Escape(pCls.Name);
  var Code := PlainCode(pR.LineText);
  var Casts:= TRegEx.Matches(Code, '(?<![\w.])' + C + '\s*\(', [roIgnoreCase]).Count;
  var Shaped:= 0;
  for var M in TRegEx.Matches(Code, '(?<![\w.])' + C + '\s*\(\s*[A-Za-z_]\w*\s*\)\s*\.\s*([A-Za-z_]\w*)', [roIgnoreCase]) do
  begin
    var Child:= FStore.FindChildSymbolByName(pCls.Id, M.Groups[1].Value);
    if (Child.Id <= 0) or not (Child.Kind in [skField, skProperty]) then
      Exit(Format('casts to `%s` and reads `%s` through the cast, which is not a field or property `%s` ' +
        'declares itself', [pCls.Name, M.Groups[1].Value, pCls.Name]));
    Inc(Shaped);
  end;
  if Shaped < Casts then
    Exit(Format('casts to `%s` other than as `%s(name).member`, which would still need its unit', [pCls.Name, pCls.Name]));
  Result:= '';
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
  { lane 149 CYB (149-CY-12): a class the edge only hard-casts (`TX(X).M`, the C7 path) is the class too }
  for var R in FSurface.Refs do
    if (FCls.Id = 0) and (R.Kind = erTypeCast) and (R.SymbolId > 0) then
    begin
      var S:= FStore.GetSymbolById(R.SymbolId);
      if S.Kind = skClass then FCls:= S;
    end;
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
  { 1.43 CYC-C: an `is` / `as` operand of the edge that is no class: nothing to hand over. The moves were
    tried first (the planner reaches here only when the declaration stayed), so the refusal names the line }
  if Length(FSurface.ClassNames) = 0 then
    for var R in FSurface.Refs do
      if R.Kind in [erTypeIs, erTypeAs] then
        Exit(Refuse('other-ref', R.Name, FFromFid, R.Line, Format('line %d tests or casts against `%s`, which is no ' +
          'class of `%s` (`%s`): the hand-over extracts an interface from a class, and this declaration could not be ' +
          'moved out of the unit either; move what it names, or the declaration, by hand', [R.Line, R.Name,
          FSurface.ToStem, Trim(R.LineText)])));
  { 1.42 cyc2: an edge through several classes never reaches here with more than one (TEdgeComposer) }
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

{ CYC-C (1): pR is `V: T;` alone on its line (a trailing `//` comment aside) and V is a local
  variable of a routine of the consumer -- the one type declaration the interface can take over;
  CheckTypeDecls checks T and every use of V. A field, a parameter, a global, an inline `var`, a
  list `A, B: T` and any other declaration keep the type-decl refusal. }
function TMemberPlan.LocalDeclOf(const pR: TEdgeRef; out pLocal: TSymbol): Boolean;
begin
  pLocal:= Default(TSymbol);
  var M:= TRegEx.Match(PlainCode(BareCode(LineOf(FLines, pR.Line))), '^\s*([A-Za-z_]\w*)\s*:\s*' +
    TRegEx.Escape(pR.Name) + '\s*;\s*$', [roIgnoreCase]);
  if not M.Success then Exit(False);
  for var S in FStore.FindSymbolsByExactName(M.Groups[1].Value) do
    if (S.FileId = FFromFid) and (S.Kind = skLocalVar) and (S.StartLine = pR.Line) and (S.ParentId > 0) then
    begin
      pLocal:= S;
      Exit(True);
    end;
  Result:= False;
end;

{ CYC-C (1): '' when every mention of the local pLocal inside the body of its routine pRoutine
  (nested routines included) is one an interface-typed local carries unchanged -- `V := X as TX`,
  `V := nil`, `Assigned(V)`, `V = nil`, `V <> nil`, `V.M` with M a member the interface carries;
  else what the first other mention does, its line in pLine. The body is the line span of the
  refs the index encloses in pRoutine (its header line to its last use: the routine symbol is
  the class declaration, not the body), widened by every ref bound to the local. The scan is
  lexical: a mention the whitelist does not name (a call argument, `V.Free`, `with V do`,
  `Y := V`) refuses. }
function TMemberPlan.LocalUseWhy(const pLocal, pRoutine: TSymbol; out pLine: Integer): string;
begin
  pLine:= 0;
  var V:= TRegEx.Escape(pLocal.Name);
  var C:= TRegEx.Escape(FCls.Name);
  var First:= pLocal.StartLine;
  var Last := pLocal.StartLine;
  for var R in FStore.GetReferencesFromFile(FFromFid) do
    if (R.EnclosingSymbolId = pRoutine.Id) or (R.SymbolId = pLocal.Id) then
    begin
      First:= Min(First, R.StartLine);
      Last := Max(Last, R.StartLine);
    end;
  for var L:= First to Last do
  begin
    if L = pLocal.StartLine then Continue;
    var Code:= PlainCode(BareCode(LineOf(FLines, L)));
    for var M in TRegEx.Matches(Code, '(?<![\w.])' + V + '\b', [roIgnoreCase]) do
    begin
      var Rest  := Copy(Code, M.Index, MaxInt);
      var Before:= Copy(Code, 1, M.Index - 1);
      var Dot   := TRegEx.Match(Rest, '^' + V + '\s*\.\s*([A-Za-z_]\w*)', [roIgnoreCase]);
      var Carried:= False;
      if Dot.Success then
        for var Mb in FMembers do
          if SameText(Mb.Name, Dot.Groups[1].Value) then Carried:= True;
      var Ok:= Carried or
        TRegEx.IsMatch(Rest, '^' + V + '\s*:=\s*(nil|[A-Za-z_]\w*\s+as\s+' + C + ')\s*(;|$|\b(end|else)\b)',
          [roIgnoreCase]) or
        TRegEx.IsMatch(Rest, '^' + V + '\s*(=|<>)\s*nil\b', [roIgnoreCase]) or
        (TRegEx.IsMatch(Before, '\bAssigned\s*\(\s*$', [roIgnoreCase]) and TRegEx.IsMatch(Rest, '^' + V + '\s*\)'));
      if Ok then Continue;
      pLine:= L;
      Exit(Format('uses the local `%s` other than as `%s := X as %s`, `%s := nil`, `Assigned(%s)`, a compare with ' +
        'nil or `%s.<member the interface carries>` (`%s`)', [pLocal.Name, pLocal.Name, FCls.Name, pLocal.Name,
        pLocal.Name, pLocal.Name, Trim(LineOf(FLines, L))]));
    end;
  end;
  Result:= '';
end;

{ CYC-C (1): each type declaration of the edge -- CheckShape let through only a routine local
  `V: T;` (LocalDeclOf) -- is retyped `V: <interface>` when T is the class and every use of V is
  one the interface carries (LocalUseWhy); the `as` casts that assign V are rewritten by
  RewriteConsumer like any other. Else the type-decl refusal names the first other use. }
function TMemberPlan.CheckTypeDecls: Boolean;
var
  Local: TSymbol;
  Line : Integer;
  Done : TList<Integer>;
begin
  Done:= TList<Integer>.Create;
  try
    for var R in FSurface.Refs do
    begin
      if (R.Kind <> erTypeDecl) or Done.Contains(R.Line) then Continue;
      Done.Add(R.Line);
      LocalDeclOf(R, Local);  { CheckShape refused every other type declaration }
      var Routine:= FStore.GetSymbolById(Local.ParentId);
      if not SameText(R.Name, FCls.Name) or (Routine.Id <= 0) then
        Exit(Refuse('type-decl', R.Name, FFromFid, R.Line, Format('line %d declares something of type `%s`, which ' +
          'would still need its unit (`%s`)', [R.Line, R.Name, R.LineText])));
      var Why:= LocalUseWhy(Local, Routine, Line);
      if Why <> '' then
        Exit(Refuse('type-decl', Local.Name, FFromFid, Line, Format('line %d %s; the local `%s` declared at line %d ' +
          'can become `%s` only when the interface carries every use', [Line, Why, Local.Name, R.Line, FIface])));
      AddEdit(FFromFid, R.Line, True, [ReplaceInCode(LineOf(FLines, R.Line), StartOf(R.Line), ':\s*' +
        TRegEx.Escape(FCls.Name) + '\b', ': ' + FIface)]);
    end;
  finally
    Done.Free;
  end;
  Result:= True;
end;

{ CYC-C (3): '' when pM, a member the consumer reads that the class does not declare itself, is
  carried like an own member: an ancestor of the class declared in the class unit declares it (the
  getter, a method of the class, reads it by name), not under `strict private`, and no class of the
  chain from the class's parent up to that ancestor declares `Get<M>` / `Set<M>` (the names the
  interface needs; the class itself is checked by CheckMembers / CheckWrites). Else why not, the
  refusal kind in pKind: member-unsupported, or duplicate-identifier for a getter / setter name.
  A member of a library ancestor or of another unit is never on the edge; inside a `with` body
  CheckWithBodies carries a library one and refuses the other. }
function TMemberPlan.InheritedWhy(const pM: TSymbol; out pKind: string): string;
var
  Next: TStoredType;
begin
  pKind:= 'member-unsupported';
  var Cur:= Stored(FCls);
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    if not FIdx.Find(FIdx.ParentOf(Cur), False, Next) or FIdx.IsLib(Next) or (Next.Sym.FileId <> FClsFid) then Break;
    for var N in TArray<string>.Create('Get' + pM.Name, 'Set' + pM.Name) do
      if Next.Store.FindChildSymbolByName(Next.Sym.Id, N).Id > 0 then
      begin
        pKind:= 'duplicate-identifier';
        Exit(Format('its ancestor `%s` already declares `%s`, a name the interface needs', [Next.Sym.Name, N]));
      end;
    if Next.Sym.Id = pM.ParentId then
    begin
      for var L:= pM.StartLine - 1 downto Next.Sym.StartLine do
      begin
        var V:= TRegEx.Match(BareCode(LineOf(FClsLines, L)), '^\s*(strict\s+)?(private|protected|public|published)\b',
          [roIgnoreCase]);
        if not V.Success then Continue;
        if (V.Groups[1].Length > 0) and SameText(V.Groups[2].Value, 'private') then
          Exit(Format('`%s.%s` is strict private: no method of `%s` can read it', [Next.Sym.Name, pM.Name, FCls.Name]));
        Break;
      end;
      Exit('');
    end;
    Cur:= Next;
  end;
  Result:= Format('no ancestor of `%s` declared in its unit declares it', [FCls.Name]);
end;

{ W6 C7: the argument list that passes an index parameter list on (const pRow, pCol: Integer;
  pName: string -> pRow, pCol, pName). }
function IndexArgs(const pParams: string): string;
begin
  Result:= '';
  for var Group in pParams.Split([';']) do
  begin
    var Colon:= Group.IndexOf(':');
    var Names:= if Colon >= 0 then Group.Substring(0, Colon) else Group;
    Names:= Trim(TRegEx.Replace(Names, '^\s*(const|var|out|constref)\s+', '', [roIgnoreCase]));
    for var N in Names.Split([',']) do
      if Trim(N) <> '' then Result:= Result + (if Result <> '' then ', ' else '') + Trim(N);
  end;
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
      if (R.Kind in [erMemberRead, erMemberWrite]) and not Ids.Contains(MemberOf(R).Id) then
      begin
        var M:= MemberOf(R);
        Ids.Add(M.Id);
        if M.Kind in [skMethod, skFunction, skProcedure] then
          Exit(Refuse('class-method', M.Name, FFromFid, R.Line, Format('line %d calls the method `%s` of `%s` ' +
            '(`%s`); the interface carries field and property reads only', [R.Line, M.Name, FCls.Name, R.LineText])));
        if M.ParentId <> FCls.Id then
        begin
          var Kind:= '';
          var Why := InheritedWhy(M, Kind);
          if Why <> '' then
            Exit(Refuse(Kind, M.Name, FFromFid, R.Line, Format('line %d reads `%s`, which is not declared in `%s` ' +
              'itself: %s', [R.Line, M.Name, FCls.Name, Why])));
        end;
        var Sig:= Trim(M.Signature);
        { an indexed property keeps only its element type in symbols.signature: read the declaration }
        var Indexed:= (M.Kind = skProperty) and TRegEx.IsMatch(BareCode(LineOf(FClsLines, M.StartLine)),
          '\bproperty\s+' + TRegEx.Escape(M.Name) + '\s*\[', [roIgnoreCase]);
        if Indexed and not IndexedPropertyOk(M, R) then Exit(False);
        if not (M.Kind in [skField, skProperty]) or (Sig = '') or
          (Sig.IndexOfAny(['[', ']', ':', '(', ')', ';']) >= 0) then
          Exit(Refuse('member-unsupported', M.Name, FFromFid, R.Line, Format('`%s.%s` is not a field or a ' +
            'property with a stored type', [FCls.Name, M.Name])));
        var Dup:= FStore.FindChildSymbolByName(FCls.Id, 'Get' + M.Name);
        if (Dup.Id > 0) and (Indexed or not GetterReusable(M, Dup)) then
          Exit(Refuse('duplicate-identifier', Dup.Name, FClsFid, Dup.StartLine, Format('`%s` already declares ' +
            '`%s` (line %d), the getter the interface needs, and it is not `function %s: %s;` read by the property ' +
            '`%s` (only that one can serve as the interface getter unchanged)', [FCls.Name, Dup.Name, Dup.StartLine,
            Dup.Name, Sig, M.Name])));
        if Dup.Id > 0 then FKeptGetters.Add(Dup.Name);
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
    { CYC-C (3): an inherited member is read by name -- its accessor may be private to the ancestor }
    if (M.Kind = skProperty) and (M.ParentId = FCls.Id) then
    begin
      var Parts: TArray<string>:= nil;
      for var L:= M.StartLine to Max(M.StartLine, M.EndLine) do Parts:= Parts + [BareCode(LineOf(FClsLines, L))];
      var RM:= TRegEx.Match(string.Join(' ', Parts), '\bread\s+([A-Za-z_][\w.]*)', [roIgnoreCase]);
      if RM.Success then Read:= RM.Groups[1].Value;
    end;
    if FIndexed.ContainsKey(M.Id) then Read:= M.Name + '[' + IndexArgs(FIndexed[M.Id]) + ']';  { W6 C7 }
    FReads.Add(Read);
  end;
  Result:= True;
end;

{ W6 C7: an indexed property read through the interface. Its index parameter list is taken from
  the declaration verbatim (FIndexed); the getter becomes `function Get<M>(<params>): <T>` and the
  interface property `property <M>[<params>]: <T> read Get<M>`. A `default` array property
  (the consumer may index the object itself) and a write refuse `member-unsupported`. }
function TMemberPlan.IndexedPropertyOk(const pM: TSymbol; const pR: TEdgeRef): Boolean;
begin
  var Decl:= '';
  for var L:= pM.StartLine to Max(pM.StartLine, pM.EndLine) do Decl:= Decl + ' ' + BareCode(LineOf(FClsLines, L));
  var Head:= TRegEx.Match(Decl, '\bproperty\s+' + TRegEx.Escape(pM.Name) + '\s*\[([^\]]+)\]', [roIgnoreCase]);
  if not Head.Success or TRegEx.IsMatch(Decl, ';\s*default\s*;', [roIgnoreCase]) then
    Exit(Refuse('member-unsupported', pM.Name, FFromFid, pR.Line, Format('`%s.%s` is an indexed property this ' +
      'plan cannot carry (a `default` array property, or its index list is not on its declaration)', [FCls.Name, pM.Name])));
  for var R in FSurface.Refs do
    if (R.Kind = erMemberWrite) and (MemberOf(R).Id = pM.Id) then
      Exit(Refuse('member-unsupported', pM.Name, FFromFid, R.Line, Format('line %d writes `%s`, an indexed property ' +
        'of `%s`; the interface carries indexed properties for reading only', [R.Line, pM.Name, FCls.Name])));
  FIndexed.AddOrSetValue(pM.Id, Trim(TRegEx.Replace(Head.Groups[1].Value, '\s+', ' ')));
  Result:= True;
end;

{ B1: the member a member ref names. A write through a `with` body is a bare ref whose
  SymbolId is the class (TakeBareRef binds it to its top-level owner): its member is the
  child of that name. }
function TMemberPlan.MemberOf(const pR: TEdgeRef): TSymbol;
begin
  Result:= if pR.SymbolId > 0 then FStore.GetSymbolById(pR.SymbolId) else Default(TSymbol);
  if (Result.Kind = skClass) and (pR.Kind = erMemberWrite) then Result:= FStore.FindChildSymbolByName(Result.Id, pR.Name);
end;

{ B1: whether one member read or write of the edge has a shape no interface property can
  carry. The index records `Inc(X.F)`, `X.F` as a call argument and `X.F.Sub := v` as READS
  of F, so both kinds are checked: Inc / Dec, a whole argument of a call that may take it by
  var / out, a write into a member that is no class or interface (through a property it would
  change a copy), a write that is not a plain `F :=`, and a write of something that is no
  member of a class. Every such shape is `member-write`; a plain write is carried by a
  read/write property (CheckWrites). }
function TMemberPlan.MemberUseRefusal(const pR: TEdgeRef; out pKind, pWhat: string): Boolean;
begin
  pKind := 'member-write';
  pWhat := MemberShapeWhy(pR, MemberOf(pR));
  Result:= pWhat <> '';
  if not Result then pKind:= '';
end;

{ What makes the use pR of the member pS uncarriable by an interface property; '' when nothing does. }
function TMemberPlan.MemberShapeWhy(const pR: TEdgeRef; const pS: TSymbol): string;
var
  T: TStoredType;
begin
  Result:= '';
  var Code  := PlainCode(pR.LineText);
  var Name  := TRegEx.Escape(pR.Name);
  var Callee:= CallArgumentCallee(Code, pR.Name);
  if (pR.Kind = erMemberWrite) and not ((pS.Kind in [skField, skProperty]) and (pS.ParentId > 0)) then
    Result:= Format('writes `%s`, which is no field or property of a class; an interface carries members only',
      [pR.Name])
  else if TRegEx.IsMatch(Code, '\b(Inc|Dec)\s*\([^,;]*?(?<!\w)' + Name + '\s*[,)]', [roIgnoreCase]) then
    Result:= Format('changes `%s` with Inc / Dec, which takes a variable; a property cannot be passed to it',
      [pR.Name])
  else if (Callee <> '') and CallMayWrite(Callee, pR.Line) then
    Result:= Format('passes `%s` as an argument of `%s`, which may take it as a var / out parameter; a property ' +
      'cannot be passed to one', [pR.Name, Callee])
  else if TRegEx.IsMatch(Code, '(?<!\w)' + Name + '(\s*(\.\s*\w+|\[[^\]]*\]|\^))+\s*:=', [roIgnoreCase]) and
    not FIdx.Find(Trim(pS.Signature), False, T) then
    Result:= Format('writes into `%s` (of type `%s`), which is no class or interface; through a property the ' +
      'write would change a copy', [pR.Name, Trim(pS.Signature)])
  else if (pR.Kind = erMemberWrite) and not TRegEx.IsMatch(Code, '(?<!\w)' + Name + '\s*:=', [roIgnoreCase]) then
    Result:= Format('writes `%s` other than by a plain `%s :=` assignment', [pR.Name, pR.Name]);
end;

{ B1: whether the routine pCallee called on line pLine may take an argument by var / out.
  The call ref of that line decides when the index resolved it; else the routines of that
  name in the nearest index that declares any (the project before the library): False when
  each takes all its parameters by value / const, or the name is a type (a cast) or a
  by-value intrinsic. A name no index declares may write. }
function TMemberPlan.CallMayWrite(const pCallee: string; pLine: Integer): Boolean;
var
  Found: Boolean;
begin
  if MatchText(pCallee, CValueIntrinsics) then Exit(False);
  for var R in FStore.GetReferencesFromFile(FFromFid) do
    if (R.StartLine = pLine) and SameText(R.NameText, pCallee) and (R.SymbolId > 0) then
      Exit(SignatureMayWrite(FStore.GetSymbolById(R.SymbolId)));
  for var St in [FStore, FIdx.Lib] do
  begin
    if St = nil then Continue;
    Found:= False;
    Result:= False;
    for var S in St.FindSymbolsByExactName(pCallee) do
      if S.Kind in [skClass, skInterface, skRecord, skEnum, skTypeAlias, skProcedure, skFunction, skMethod,
        skConstructor] then
      begin
        Found := True;
        Result:= Result or SignatureMayWrite(S);
      end;
    if Found then Exit;
  end;
  Result:= True;
end;

{ B2 (R2m): the instance method of the class itself that a bare call (`Reset(3)`) or a bare
  function read (`GetNamePath`) of the edge binds to -- inside a `with ... as TX do` body;
  Id 0 for any other ref. The surface records such a ref against the class (its top-level
  owner), so the method is found again by name; a call through the class name
  (erClassReceiver) or through another receiver (bound to the method itself) is never one. }
function TMemberPlan.CarriedMethodOf(const pR: TEdgeRef; const pS: TSymbol): TSymbol;
begin
  Result:= Default(TSymbol);
  if not (pR.Kind in [erCall, erOther]) or (FCls.Id = 0) or (pS.Id <> FCls.Id) or SameText(pR.Name, pS.Name) then
    Exit;
  var M:= FStore.FindChildSymbolByName(pS.Id, pR.Name);
  if M.Kind in [skMethod, skFunction, skProcedure] then Result:= M;
end;

{ B2 (R2m): one call of the instance method pM. Refused: a class method, a method taken
  without a call (a method pointer), an overload, a directive an interface cannot carry, a function with no
  stored result type, a signature type of the cycle or one no index resolves. Else pM is
  carried once: `procedure|function <Name><signature verbatim>;[ <conv>;]`. }
function TMemberPlan.CheckMethod(const pR: TEdgeRef; const pM: TSymbol): Boolean;  // dl:ok too-many-exit-points@2e39 -- one guard clause per refusal kind, the TMemberPlan check style
var
  Conv, Why: string;
  IsOverload: Boolean;
begin
  var KW:= TRegEx.Match(BareCode(LineOf(FClsLines, pM.StartLine)), '^\s*(class\s+)?(procedure|function)\s+' +
    TRegEx.Escape(pM.Name) + '\b', [roIgnoreCase]);
  if not KW.Success then
    Exit(Refuse('manual-edit', pM.Name, FClsFid, pM.StartLine, Format('the declaration of `%s.%s` does not start ' +
      'its line %d with `procedure` or `function`', [FCls.Name, pM.Name, pM.StartLine])));
  if KW.Groups[1].Length > 0 then
    Exit(Refuse('class-method', pM.Name, FFromFid, pR.Line, Format('line %d calls `%s`, a class method of `%s` ' +
      '(`%s`); an interface carries instance methods only', [pR.Line, pM.Name, FCls.Name, pR.LineText])));
  var IsFunc:= SameText(KW.Groups[2].Value, 'function');
  if MethodTakenAt(BareCode(LineOf(FLines, pR.Line)), pM.Name, IsFunc) then
    Exit(Refuse('class-method', pM.Name, FFromFid, pR.Line, Format('line %d names the method `%s` without calling ' +
      'it (`%s`); the interface carries calls, not method pointers', [pR.Line, pM.Name, pR.LineText])));
  for var X in FMethods do
    if X.Id = pM.Id then Exit(True);
  if not MethodDirectives(FClsLines, pM.StartLine, pM.Name, Conv, Why, IsOverload) then
    Exit(Refuse('unsupported-directive', pM.Name, FClsFid, pM.StartLine, Format('`%s.%s`: %s', [FCls.Name, pM.Name,
      Why])));
  var Count:= 0;
  for var S in FStore.FindSymbolsByExactName(pM.Name) do
    if (S.ParentId = FCls.Id) and (S.Kind in [skMethod, skFunction, skProcedure]) then Inc(Count);
  if IsOverload or (Count > 1) then
    Exit(Refuse('overloaded-routine', pM.Name, FClsFid, pM.StartLine, Format('`%s.%s` is overloaded; the index ' +
      'cannot tell which declaration each call binds to, and the interface would carry one', [FCls.Name, pM.Name])));
  var Sig:= Trim(pM.Signature);
  if IsFunc and not ContainsStr(Sig.Substring(Sig.LastIndexOf(')') + 1), ':') then
    Exit(Refuse('signature-unknown', pM.Name, FClsFid, pM.StartLine, Format('the index holds no result type for ' +
      'the function `%s.%s`', [FCls.Name, pM.Name])));
  for var T in SignatureTypes(FSource, FClsFid, pM.StartLine, Sig) do
  begin
    if T.InScc then
      Exit(Refuse('signature-in-cycle', T.Name, FClsFid, pM.StartLine, Format('the signature of `%s.%s` names ' +
        '`%s`, declared in `%s`, a unit of this cycle -- an interface outside the cycle cannot name it',
        [FCls.Name, pM.Name, T.Name, T.DeclStem])));
    if not AddLeafUse(pM, T.Name, T.Name) then Exit(False);
  end;
  FMethods.Add(pM);
  FMethodDecls.Add(Format('    %s %s%s;%s', [LowerCase(KW.Groups[2].Value), pM.Name, Sig,
    (if Conv <> '' then ' ' + Conv + ';' else '')]));
  Result:= True;
end;

{ B2 (R2m): every mention of a carried method inside a `with ... as TX do` body -- the index
  leaves some unbound (`FOnX := M` gets no symbol), so the edge surface never shows them --
  is a call (MethodTakenAt), never a method pointer. }
function TMemberPlan.CheckMethodMentions: Boolean;
begin
  Result:= True;
  if FMethods.Count = 0 then Exit;
  var Refs:= FStore.GetReferencesFromFile(FFromFid);
  for var W in FWithLines do
  begin
    var Last:= WithBodyEnd(FLines, W);
    for var R in Refs do
      if (R.StartLine >= W) and (R.StartLine <= Last) and (R.ReceiverText = '') then
        for var I:= 0 to FMethods.Count - 1 do
          if SameText(R.NameText, FMethods[I].Name) and MethodTakenAt(BareCode(LineOf(FLines, R.StartLine)),
            FMethods[I].Name, StartsText('    function', FMethodDecls[I])) then
            Exit(Refuse('class-method', R.NameText, FFromFid, R.StartLine, Format('line %d names the method `%s` ' +
              'without calling it (`%s`); the interface carries calls, not method pointers', [R.StartLine, R.NameText,
              Trim(LineOf(FLines, R.StartLine))])));
  end;
end;

{ B2 (R2m): every ref CarriedMethodOf names passes CheckMethod, in ref order. }
function TMemberPlan.CheckMethods: Boolean;
begin
  for var R in FSurface.Refs do
  begin
    var S:= if R.SymbolId > 0 then FStore.GetSymbolById(R.SymbolId) else Default(TSymbol);
    var M:= CarriedMethodOf(R, S);
    if (M.Id > 0) and not CheckMethod(R, M) then Exit(False);
  end;
  Result:= True;
end;

{ B1: each member the consumer writes becomes a read/write property: a field, or a property
  with a `write` accessor, and the class declares no `Set<Member>` yet. FSetters runs
  parallel to FMembers ('' for a member only read). }
function TMemberPlan.CheckWrites: Boolean;
begin
  SetLength(FSetters, FMembers.Count);
  for var I:= 0 to FMembers.Count - 1 do
  begin
    var M   := FMembers[I];
    var Line:= 0;
    for var R in FSurface.Refs do
      if (Line = 0) and (R.Kind = erMemberWrite) and (MemberOf(R).Id = M.Id) then Line:= R.Line;
    if Line = 0 then Continue;
    var Parts: TArray<string>:= nil;
    for var L:= M.StartLine to Max(M.StartLine, M.EndLine) do Parts:= Parts + [BareCode(LineOf(FClsLines, L))];
    if (M.Kind = skProperty) and not TRegEx.IsMatch(string.Join(' ', Parts), '\bwrite\s+[A-Za-z_]', [roIgnoreCase]) then
      Exit(Refuse('member-write', M.Name, FFromFid, Line, Format('line %d writes `%s`, a property of `%s` without ' +
        'a `write` accessor', [Line, M.Name, FCls.Name])));
    var Dup:= FStore.FindChildSymbolByName(FCls.Id, 'Set' + M.Name);
    if Dup.Id > 0 then
      Exit(Refuse('duplicate-identifier', Dup.Name, FClsFid, Dup.StartLine, Format('`%s` already declares ' +
        '`%s` (line %d), the setter the interface needs', [FCls.Name, Dup.Name, Dup.StartLine])));
    FSetters[I]:= 'Set' + M.Name;
  end;
  Result:= True;
end;

{ B1: the declaration and the one-line body of member pI's setter, when the consumer writes
  it; the body assigns the member itself, so a property runs its own write accessor. }
procedure TMemberPlan.AddSetterLines(pI: Integer; const pIndent: string; pDecls, pBodies: TList<string>);
begin
  if FSetters[pI] = '' then Exit;
  var Ty:= Trim(FMembers[pI].Signature);
  pDecls.Add(Format('%s/// <summary>%s: sets %s (cycles --plan, member hand-over).</summary>', [pIndent, FIface,
    FMembers[pI].Name]));
  pDecls.Add(Format('%sprocedure %s(const pValue: %s);', [pIndent, FSetters[pI], Ty]));
  pBodies.Add('');
  pBodies.Add(Format('procedure %s.%s(const pValue: %s);', [FCls.Name, FSetters[pI], Ty]));
  pBodies.Add('begin');
  pBodies.Add(Format('  %s := pValue;', [FMembers[pI].Name]));
  pBodies.Add('end;');
end;

{ B1: the setter declarations of the interface, after its getters. }
procedure TMemberPlan.AddIfaceSetters(pL: TList<string>);
begin
  for var I:= 0 to FMembers.Count - 1 do
    if FSetters[I] <> '' then
      pL.Add(Format('    procedure %s(const pValue: %s);', [FSetters[I], Trim(FMembers[I].Signature)]));
end;

{ B1: ` write Set<Member>` for a member the consumer writes, else ''. }
function TMemberPlan.WriteClause(pI: Integer): string;
begin
  Result:= if FSetters[pI] <> '' then ' write ' + FSetters[pI] else '';
end;

{ The class: heritage on its declaration line, an `end;` line, an IInterface ancestor and
  no reference counting on the way. }
function TMemberPlan.CheckClass: Boolean;
begin
  var HLine, HCol: Integer;
  if not SameText(FCls.Section, 'interface') or not HeritageClose(FClsLines, FCls.StartLine, HLine, HCol) then
    Exit(Refuse('manual-edit', FCls.Name, FClsFid, FCls.StartLine, Format('the heritage of `%s` is not on its ' +
      'declaration line %d in the interface section (or does not close within %d lines)', [FCls.Name,
      FCls.StartLine, CMaxDeclLines])));
  if (FCls.EndLine <= FCls.StartLine) or not TRegEx.IsMatch(BareCode(LineOf(FClsLines, FCls.EndLine)), '^end\b',
    [roIgnoreCase]) then
    Exit(Refuse('manual-edit', FCls.Name, FClsFid, FCls.EndLine, Format('the declaration of `%s` does not end ' +
      'with an `end;` line', [FCls.Name])));
  if not AncestorImplementingIInterface(FStore, FIdx.Lib, FCls, FCastAnc) then
    Exit(Refuse('no-iinterface', FCls.Name, FClsFid, FCls.StartLine, Format('no ancestor of `%s` implements ' +
      'IInterface (or the ancestry leaves the indexes given): it cannot implement an interface', [FCls.Name])));
  SkipCycleAncestors;
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

{ C1: whether an `X is TX` test on the same receiver text precedes line pLine inside the same
  routine (the guard logic of CheckCastExceptions): a cast reached only when X IS a TX may go
  through the IInterface ancestor although X's static type is unknown. }
function TMemberPlan.GuardedBefore(const pX: string; pEnclosing: Int64; pLine: Integer): Boolean;
begin
  Result:= False;
  var C:= TRegEx.Escape(FCls.Name);
  for var G in FSurface.Refs do
    if (G.Kind = erTypeIs) and (G.EnclosingId = pEnclosing) and (G.Line < pLine) and
      TRegEx.IsMatch(G.LineText, '(?<![\w.])' + TRegEx.Escape(pX) + '\s+is\s+' + C + '\b', [roIgnoreCase]) then Exit(True);
end;

{ One consumer line with every `X is TClass` / `X as TClass` rewritten to the interface. }
function TMemberPlan.RewriteLine(pLine: Integer; pEnclosing: Int64; out pText: string): Boolean;
var
  Ty: string;
begin
  var C:= TRegEx.Escape(FCls.Name);
  var St:= StartOf(pLine);  { B11: only code is rewritten; a string or a comment that spells it stays as written }
  pText:= LineOf(FLines, pLine);
  pText:= ReplaceInCode(pText, St, '\(\s*([A-Za-z_][\w.]*)\s+is\s+' + C + '\s*\)', 'Supports($1, ' + FIface + ')');
  pText:= ReplaceInCode(pText, St, '(?<![\w.)\]])([A-Za-z_][\w.]*)\s+is\s+' + C + '\b', 'Supports($1, ' + FIface + ')');
  if ContainsStr(CodeOf(pText, St), 'Supports(') and not ConsumerSees(CSysUtilsUnit) then FUses.Add(CSysUtilsUnit);
  while True do
  begin
    var M:= TRegEx.Match(CodeOf(pText, St), '(?<![\w.)\]])([A-Za-z_]\w*)\s+as\s+' + C + '\b', [roIgnoreCase]);
    if not M.Success then Break;
    var X:= M.Groups[1].Value;
    var Known:= ReceiverType(X, pEnclosing, Ty);
    { C1: an `X is TX` guard earlier in the same routine proves X a TX there -- the ancestor cast is safe.
      Lane 149 CYB (149-CY-8b): otherwise the raise-preserving helper takes any object (a TObject
      parameter), so an unknown static type no longer refuses; only a helper name taken does }
    if not Known and ((FCastAnc = '') or not GuardedBefore(X, pEnclosing, pLine)) and (FAsHelper = '') then
    begin
      if Length(FStore.FindSymbolsByExactName(AsHelperName)) > 0 then
        Exit(Refuse('receiver-unknown', X, FFromFid, pLine, Format('line %d: the static type of `%s` in `%s as %s` ' +
          'is not that of Self, a parameter, a local, or a field or property of the class, no `%s is %s` guards ' +
          'it earlier in the same routine, and the helper that takes any object, `%s`, names something that exists ' +
          'already', [pLine, X, X, FCls.Name, X, FCls.Name, AsHelperName])));
      FAsHelper:= AsHelperName;
    end;
    var Repl:= X + ' as ' + FIface;
    if FAsHelper <> '' then Repl:= Format('%s(%s)', [FAsHelper, X])  { lane 148 CY: raises EInvalidCast as before }
    else if not Known or not ImplementsIInterface(FIdx, Ty) then
    begin
      Repl     := Format('%s(%s) as %s', [FCastAnc, X, FIface]);
      FCastUsed:= True;
    end;
    pText:= Copy(pText, 1, M.Index - 1) + Repl + Copy(pText, M.Index + M.Length, MaxInt);
  end;
  { C7: a hard cast followed by a member, `TX(X).M` -> `(X as I).M`, through the IInterface ancestor
    when X's static type lacks it; a wrong cast now raises EIntfCastError instead of reading garbage }
  while True do
  begin
    var M:= TRegEx.Match(CodeOf(pText, St), '(?<![\w.])' + C + '\s*\(\s*([A-Za-z_]\w*)\s*\)\s*(?=\.)', [roIgnoreCase]);
    if not M.Success then Break;
    var X:= M.Groups[1].Value;
    var Known:= ReceiverType(X, pEnclosing, Ty);
    if not Known and ((FCastAnc = '') or not GuardedBefore(X, pEnclosing, pLine)) then
      Exit(Refuse('receiver-unknown', X, FFromFid, pLine, Format('line %d: the static type of `%s` in `%s(%s)` ' +
        'is not that of Self, a parameter, a local, or a field or property of the class, and no `%s is %s` guards ' +
        'it earlier in the same routine', [pLine, X, FCls.Name, X, X, FCls.Name])));
    var Repl:= '(' + X + ' as ' + FIface + ')';
    if not Known or not ImplementsIInterface(FIdx, Ty) then
    begin
      Repl     := Format('(%s(%s) as %s)', [FCastAnc, X, FIface]);
      FCastUsed:= True;
    end;
    if FHandles then FHardCastChange:= True;  { lane 149 CYB (149-CY-8b): stated in the plan }
    pText:= Copy(pText, 1, M.Index - 1) + Repl + Copy(pText, M.Index + M.Length, MaxInt);
  end;
  if TRegEx.IsMatch(CodeOf(pText, St), '\b' + C + '\b', [roIgnoreCase]) then
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
      if not (R.Kind in [erTypeIs, erTypeAs, erTypeCast]) or Done.Contains(R.Line) then Continue;
      Done.Add(R.Line);
      if not RewriteLine(R.Line, R.EnclosingId, Text) then Exit(False);
      AddEdit(FFromFid, R.Line, True, [Text]);
      if IsWithHeadLine(FLines, R.Line, FCls.Name) then FWithLines.Add(R.Line);
    end;
  finally
    Done.Free;
  end;
  if FAsHelper <> '' then
  begin
    var At:= AsHelperAnchor;
    if At < 1 then
      Exit(Refuse('exception-semantics', FCls.Name, FFromFid, 0, Format('`%s` handles EInvalidCast and casts with ' +
        '`as %s` unguarded, and no routine start was found to put the raise-preserving helper `%s` before',
        [UnitOfFile(FStore.GetFilePath(FFromFid)), FCls.Name, FAsHelper])));
    AddEdit(FFromFid, At, False, AsHelperLines);
    if not ConsumerSees(CSysUtilsUnit) and not FUses.Contains(CSysUtilsUnit) then FUses.Add(CSysUtilsUnit);
    if not ConsumerSees(CSysConstUnit) and not FUses.Contains(CSysConstUnit) then FUses.Add(CSysConstUnit);
  end;
  Result:= CheckCastUnit;
end;

{ Lane 148 CY: the line the helper goes AFTER -- just before the outermost routine that holds the first `as`
  the helper serves (above that routine's `//` / `///` comment lines, so they stay its own); 0 when none. }
function TMemberPlan.AsHelperAnchor: Integer;
begin
  Result:= 0;
  var C:= TRegEx.Escape(FCls.Name);
  for var R in FSurface.Refs do
  begin
    if (R.Kind <> erTypeAs) or not TRegEx.IsMatch(R.LineText, '\bas\s+' + C + '\b', [roIgnoreCase]) then Continue;
    var S:= FStore.FindEnclosingRoutineByImpl(FFromFid, R.Line);
    if S.Id <= 0 then Exit(0);
    while S.ParentId > 0 do
    begin
      var P:= FStore.GetSymbolById(S.ParentId);
      if P.Kind not in [skProcedure, skFunction, skMethod] then Break;
      S:= P;
    end;
    var First:= if S.ImplStartLine > 0 then S.ImplStartLine else S.StartLine;
    if (First < 2) or (First > Length(FLines)) then Exit(0);
    Result:= First - 1;
    while (Result > 1) and TRegEx.IsMatch(FLines[Result - 1], '^\s*//') do Dec(Result);
    Exit;
  end;
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

{ W6 C1: the first IInterface ancestor may be declared in a unit of the cycle (it cannot be named in the
  consumer): walk on to the next ancestor that implements IInterface -- any of them serves `TAnc(X) as I`.
  Runs before the lines are rewritten, so every cast names the final ancestor. A walk that ends on a class
  of the cycle keeps FCastAnc: CheckCastUnit then refuses cast-unseen. }
procedure TMemberPlan.SkipCycleAncestors;
var
  T: TStoredType;
begin
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    if not FIdx.Find(FCastAnc, False, T) or FIdx.IsLib(T) then Exit;
    var DeclUnit:= UnitOfFile(T.Store.GetFilePath(T.Sym.FileId));
    var Stem:= LowerCase(DeclUnit);
    if Stem = FSurface.FromStem then Exit;
    if not ((Stem = FSurface.ToStem) or (FSource.IsSccStem(Stem) and not ConsumerSees(DeclUnit))) then Exit;
    var Next: string;
    if not WalkToIInterface(FIdx, T, Next) or SameText(Next, FCastAnc) then Exit;
    FCastAnc:= Next;
  end;
end;

{ Fix round 1: `as I` raises EIntfCastError where `as TClass` raised EInvalidCast. When the
  consumer handles EInvalidCast anywhere, every `X as TClass` must follow an `X is TClass`
  guard of its routine (the guard becomes Supports, so the cast cannot fail there).
  Lane 148 CY (fabcyc case 8): an unguarded one no longer refuses. The consumer gets a helper
  `As<Surface>(X)` (AsHelperLines) that returns nil for nil, the interface when X supports it, and
  otherwise raises EInvalidCast.CreateRes(@SInvalidCast) -- the class and the message the failed class
  cast raised (System.SysUtils maps the RTL's reInvalidCast to exactly that); only the raise address
  differs. Every `X as TX` of the consumer then goes through it (RewriteLine). Refuses
  exception-semantics as before when a symbol already carries the helper's name. Runs before
  RewriteConsumer. }
function TMemberPlan.CheckCastExceptions: Boolean;
begin
  Result:= True;
  FAsHelper:= '';
  FHandles := False;
  for var L in FLines do
    if TRegEx.IsMatch(PlainCode(L), '\bEInvalidCast\b', [roIgnoreCase]) then FHandles:= True;
  if not FHandles then Exit;
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
      begin
        var Helper:= AsHelperName;
        if Length(FStore.FindSymbolsByExactName(Helper)) > 0 then
          Exit(Refuse('exception-semantics', FCls.Name, FFromFid, R.Line, Format('line %d casts with `as %s` without ' +
            'an `is` guard, and `%s` handles EInvalidCast: a failed `as %s` raises EIntfCastError instead, and the ' +
            'helper that would raise EInvalidCast, `%s`, names something that exists already', [R.Line,
            FCls.Name, UnitOfFile(FStore.GetFilePath(FFromFid)), FIface, Helper])));
        FAsHelper:= Helper;
        Exit;
      end;
    end;
  end;
end;

{ `As<Surface without its I>`: the name of the raise-preserving cast helper. }
function TMemberPlan.AsHelperName: string;
begin
  Result:= 'As' + (if (Length(FIface) > 1) and (UpCase(FIface[1]) = 'I') then Copy(FIface, 2, MaxInt) else FIface);
end;

{ Lane 148 CY: the helper CheckCastExceptions chose, as lines for the consumer's implementation section. }
function TMemberPlan.AsHelperLines: TArray<string>;
begin
  Result:= [
    Format('/// <summary>`X as %s` through <c>%s</c>: nil for nil, else raises EInvalidCast as the class cast did.</summary>',
      [FCls.Name, FIface]),
    Format('function %s(const pX: TObject): %s;', [FAsHelper, FIface]),
    'begin',
    '  Result := nil;',
    '  if (pX <> nil) and not Supports(pX, ' + FIface + ', Result) then',
    '    raise EInvalidCast.CreateRes(@SInvalidCast);',
    'end;',
    ''];
end;
{ True when the name starting at the 1-based column pCol of line pLine is qualified: the
  last code character before it (on that line, else at the end of the line before) is a
  `.`, as in `Self.InBuf`. The index records `Self.X` as two bare reads, so the source
  is the only witness. A qualified name binds through its qualifier, never through a
  `with` subject. }
function QualifiedAt(const pLines: TArray<string>; pLine, pCol: Integer): Boolean;
begin
  var Before:= TrimRight(Copy(LineOf(pLines, pLine), 1, pCol - 1));
  if Before = '' then Before:= TrimRight(LineOf(pLines, pLine - 1));
  Result:= EndsStr('.', Before) and not EndsStr('..', Before);
end;

{ The refs of the consumer that could rebind inside the `with` at line pWith: bare names (a type, a
  member access or a qualified name cannot rebind) after the `as <class>` of the head -- in `with A as TA,
  B as TB do` B is read in TA's scope, exactly as in the nested form -- up to WithBodyEnd. Columns are read
  from the file as indexed: another class's rewrite of the line in FLines moved them. }
function TMemberPlan.BareBodyRefs(pWith: Integer; const pRefs: TArray<TReference>): TArray<TReference>;
const
  CNoRebind: array[0..1] of string = ('type_use', 'member-access');
begin
  Result:= nil;
  var Indexed:= FSource.FileLines(FFromFid);
  var Head   := TRegEx.Match(LineOf(Indexed, pWith), '\bas\s+' + TRegEx.Escape(FCls.Name) + '\b', [roIgnoreCase]);
  var HeadEnd:= if Head.Success then Head.Index + Head.Length else 0;
  var Last   := WithBodyEnd(FLines, pWith);
  for var R in pRefs do
  begin
    var InHead:= (R.StartLine = pWith) and (R.StartCol < HeadEnd);
    if not InRange(R.StartLine, pWith, Last) or (R.ReceiverText <> '') or InHead then Continue;
    if not MatchText(R.Kind, CNoRebind) and not QualifiedAt(Indexed, R.StartLine, R.StartCol) then Result:= Result + [R];
  end;
end;

{ The nearest declaration of pName walking up from the class: Sym (its visibility decides) and TypedSym,
  the nearest one holding a type (`published property Caption;` redeclares without one). False when
  the chain does not declare it. }
function TMemberPlan.ChainMemberOf(const pName: string; out pMember: TChainMember): Boolean;
var
  Next: TStoredType;
begin
  Result := False;
  pMember:= Default(TChainMember);
  var Cur:= Stored(FCls);
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    var S:= Cur.Store.FindChildSymbolByName(Cur.Sym.Id, pName);
    if (S.Id > 0) and not Result then
    begin
      pMember.Owner:= Cur;
      pMember.Sym  := S;
      Result       := True;
    end;
    if (S.Id > 0) and (Trim(S.Signature) <> '') then
    begin
      pMember.Typed   := Cur;
      pMember.TypedSym:= S;
      Exit;
    end;
    if not FIdx.FindFrom(FIdx.ParentOf(Cur), Cur, Next) then Exit;
    Cur:= Next;
  end;
end;

{ A member's type as symbols.signature holds it: a property redeclared without one (`property Caption;`)
  is stored with the inherited type behind a colon. }
function MemberTypeText(const pSignature: string): string;
begin
  Result:= Trim(pSignature);
  if Result.StartsWith(':') then Result:= Trim(Result.Substring(1));
end;

{ The visibility section a member is declared in, lower case ('strict private'); 'public' when its
  class opens without a section; '' when the source cannot be read. }
function DeclaredVisibility(const pOwner: TStoredType; const pSym: TSymbol): string;
begin
  var Path:= pOwner.Store.GetFilePath(pOwner.Sym.FileId);
  if not TFile.Exists(Path) then Exit('');
  var Lines:= TFile.ReadAllLines(Path);
  Result:= 'public';
  for var L:= Min(pSym.StartLine, Length(Lines)) - 1 downto pOwner.Sym.StartLine do
  begin
    var V:= TRegEx.Match(BareCode(Lines[L - 1]), '^\s*((strict\s+)?(private|protected)|public|published)\b', [roIgnoreCase]);
    if V.Success then Exit(LowerCase(TRegEx.Replace(V.Groups[1].Value, '\s+', ' ')));
  end;
end;

{ Whether pName is an indexed property where pMember's type is declared; '' when not. A source
  that cannot be read answers why. }
function IndexedWhy(const pMember: TChainMember; const pName: string): string;
begin
  Result:= '';
  var Path:= pMember.Typed.Store.GetFilePath(pMember.Typed.Sym.FileId);
  if not TFile.Exists(Path) then Exit('its library source cannot be read, so its declaration cannot be checked');
  var Lines:= TFile.ReadAllLines(Path);
  var Line := pMember.TypedSym.StartLine;
  if InRange(Line, 1, Length(Lines)) and TRegEx.IsMatch(BareCode(Lines[Line - 1]), '\bproperty\s+' + TRegEx.Escape(pName) +
    '\s*\[', [roIgnoreCase]) then Result:= 'it is an indexed property';
end;

{ Why the interface cannot carry the library member, seen from the consumer; '' when it can. pVis: its
  section (DeclaredVisibility). A method: `Free` through an interface would leave a temporary to release on a freed
  object, and no method is carried. A protected member: the consumer sees it only if it descends from its class,
  which this check cannot tell, so carrying could itself rebind. }
function UncarriableWhy(const pMember: TChainMember; const pName, pVis: string): string;
begin
  Result:=
    if pMember.Sym.Kind not in [skField, skProperty] then
      'the interface does not carry a library method (after the rewrite the name would bind to something ' +
      'else); qualify or split the `with` by hand'
    else if pVis = '' then 'its library source cannot be read, so its visibility is unknown'
    else if EndsText('protected', pVis) then
      'it is protected: whether the consumer sees it depends on the consumer''s own ancestry, so carrying ' +
      'it could itself change what the name binds to'
    else if pMember.TypedSym.Id = 0 then 'the index holds no type for it'
    else if MemberTypeText(pMember.TypedSym.Signature).IndexOfAny(['[', ']', ':', '(', ')', ';']) >= 0 then
      'its type is not a plain name'
    else IndexedWhy(pMember, pName);
end;

{ The accessor name for a carried library member: pPrefix + pName, or with the suffix Surface when the chain
  already declares that (TPersistent.GetOwner: a method of that name in the class would hide it). '' when both are taken. }
function FreeAccessorName(pChain: TStringList; const pPrefix, pName: string): string;
begin
  Result:= pPrefix + pName;
  if pChain.IndexOf(Result) < 0 then Exit;
  Result:= Result + 'Surface';
  if pChain.IndexOf(Result) >= 0 then Result:= '';
end;

{ pR names a chain member not carried yet: goes on the interface when it can, pIdx its index in FMembers; -1 when there
  is nothing to carry: a name that is not a member (pNames), a member private to its library unit (the consumer never
  saw it: the name binds past it before and after), and any but a public or published field or property of a project
  class, which stays in pNames for the caller's check. False with the refusal set when it cannot be carried: a
  library member, UncarriableWhy; `with-member` in a `with` body, else `class-method` / `member-unsupported`. }
function TMemberPlan.FirstCarry(const pR: TReference; pInWith: Boolean; pNames, pChain: TStringList;
  pCarried: TDictionary<string, Integer>; out pIdx: Integer): Boolean;
var
  Found: TChainMember;
begin
  Result:= True;
  pIdx  := -1;
  var Name:= pR.NameText;
  var At  := pNames.IndexOf(Name);
  if (At < 0) or not ChainMemberOf(Name, Found) then Exit;
  var Vis:= DeclaredVisibility(Found.Owner, Found.Sym);
  if FIdx.IsLib(Found.Owner) then
  begin
    if EndsText('private', Vis) then
    begin
      pNames.Delete(At);
      Exit;
    end;
    var Why:= UncarriableWhy(Found, Name, Vis);
    if Why <> '' then
    begin
      var IsMember:= Found.Sym.Kind in [skField, skProperty];
      var Kind    := if pInWith then 'with-member' else if IsMember then 'member-unsupported' else 'class-method';
      var Where   := Format((if pInWith then 'inside `with ... as %s do`' else 'through a cast to `%s`'), [FCls.Name]);
      Exit(Refuse(Kind, Name, FFromFid, pR.StartLine, Format('%s, `%s` is %s of the library ancestor `%s`: %s', [Where, Name,
        (if IsMember then 'a member' else 'a method'), Found.Owner.Sym.Name, Why])));
    end;
  end
  else if not MatchText(Vis, ['public', 'published']) or (UncarriableWhy(Found, Name, Vis) <> '') then Exit;
  var Getter:= FreeAccessorName(pChain, 'Get', Found.Sym.Name);
  if Getter = '' then
    Exit(Refuse('duplicate-identifier', 'Get' + Name, FFromFid, pR.StartLine, Format('`%s` or an ancestor already ' +
      'declares `Get%s` and `Get%sSurface`, the getter names the interface could use for the member `%s`',
      [FCls.Name, Name, Name, Name])));
  pNames.Delete(At);
  var M:= Found.Sym;
  M.Id       := 0;  { an id of another store; FIndexed and the edge's refs key on the project's }
  M.Signature:= MemberTypeText(Found.TypedSym.Signature);
  M.FileId   := FClsFid;
  M.StartLine:= FCls.StartLine;  { AddLeafUse binds the type from here }
  M.EndLine  := FCls.StartLine;
  pIdx:= FMembers.Add(M);
  FGetters.Add(Getter);
  FReads.Add(M.Name);
  SetLength(FSetters, FMembers.Count);
  pCarried.Add(LowerCase(Name), pIdx);
end;

{ One use of the carried member pIdx: no shape a property cannot take; a plain write adds its setter. }
function TMemberPlan.CarryUse(const pR: TReference; pIdx: Integer; pChain: TStringList): Boolean;
begin
  Result:= True;
  var U:= Default(TEdgeRef);
  U.Name    := pR.NameText;
  U.Line    := pR.StartLine;
  U.LineText:= LineOf(FLines, pR.StartLine);
  var Written:= SameText(pR.Kind, 'write') or TRegEx.IsMatch(PlainCode(U.LineText), '(?<![\w.])' + TRegEx.Escape(pR.NameText) +
    '\s*:=', [roIgnoreCase]);
  U.Kind:= if Written then erMemberWrite else erMemberRead;
  var Why:= MemberShapeWhy(U, FMembers[pIdx]);
  if Why <> '' then
    Exit(Refuse('member-write', pR.NameText, FFromFid, pR.StartLine, Format('line %d %s (`%s`)', [pR.StartLine, Why,
      Trim(U.LineText)])));
  if not Written or (FSetters[pIdx] <> '') then Exit;
  var Name  := FMembers[pIdx].Name;
  var Setter:= FreeAccessorName(pChain, 'Set', Name);
  if Setter = '' then
    Exit(Refuse('duplicate-identifier', 'Set' + Name, FFromFid, pR.StartLine, Format('line %d writes the member ' +
      '`%s`; `%s` or an ancestor already declares `Set%s` and `Set%sSurface`, the setter names the interface could use',
      [pR.StartLine, Name, FCls.Name, Name, Name])));
  FSetters[pIdx]:= Setter;
end;

{ One bare name of a `with` body, or a member through a cast, against the class chain: a public or published field
  or property goes on the interface (first use), its getter reading it by name and a plain write adding a setter (the
  consumer compiled, so it is writable). The edge does not always hold one a project class declares: the index binds
  a bare name to the innermost `with` only, so the outer class's member in a nested body comes here.
  pCarried: member name (lower case) -> index in FMembers. }
function TMemberPlan.CarryChainMember(const pR: TReference; pInWith: Boolean; pNames, pChain: TStringList;
  pCarried: TDictionary<string, Integer>): Boolean;
var
  Idx: Integer;
begin
  Result:= True;
  if not pCarried.TryGetValue(LowerCase(pR.NameText), Idx) then
  begin
    if not FirstCarry(pR, pInWith, pNames, pChain, pCarried, Idx) then Exit(False);
    if Idx < 0 then Exit;
  end;
  Result:= CarryUse(pR, Idx, pChain);
end;

{ Takes the members and methods the interface carries out of pNames. }
procedure TMemberPlan.RemoveCarriedNames(pNames: TStringList);
  procedure Take(const pName: string);
  begin
    var At:= pNames.IndexOf(pName);
    if At >= 0 then pNames.Delete(At);
  end;
begin
  for var M in FMembers do Take(M.Name);
  for var M in FMethods do Take(M.Name);
end;

{ 1.43: `(X as TClass).M` and `TClass(X).M` on a line the rewrite retypes, with M a member the edge does not list
  (the index binds it to its declaring class, a library ancestor's or another unit's): without M on the interface
  the plan is mechanical and the compile gate rolls it back. So M is carried like a `with` body's name. }
function TMemberPlan.CheckCastChainMembers: Boolean;
var
  Names  : TStringList;
  Chain  : TStringList;
  Carried: TDictionary<string, Integer>;
  Lines  : TList<Integer>;
  Stop   : string;
begin
  Result := True;
  Names  := TStringList.Create(dupIgnore, True, False);
  Chain  := TStringList.Create(dupIgnore, True, False);
  Carried:= TDictionary<string, Integer>.Create;
  Lines  := TList<Integer>.Create;
  try
    var C:= TRegEx.Escape(FCls.Name);
    var Pat:= '(?:\(\s*[A-Za-z_][\w.]*\s+as\s+' + C + '\s*\)|(?<![\w.])' + C + '\s*\(\s*[A-Za-z_]\w*\s*\))\s*\.\s*([A-Za-z_]\w*)(\s*:=)?';
    var Known:= False;
    var Complete:= False;
    for var R in FSurface.Refs do
    begin
      if (R.Kind not in [erTypeAs, erTypeCast]) or Lines.Contains(R.Line) then Continue;
      Lines.Add(R.Line);
      for var M in TRegEx.Matches(PlainCode(LineOf(FLines, R.Line)), Pat, [roIgnoreCase]) do
      begin
        if not Known then
        begin
          Known   := True;
          Complete:= ChainMembers(FIdx, Stored(FCls), Names, Stop);
          Chain.AddStrings(Names);
          RemoveCarriedNames(Names);
        end;
        var Name:= M.Groups[1].Value;
        var U:= Default(TReference);
        U.NameText := Name;
        U.StartLine:= R.Line;
        U.Kind     := if (M.Groups.Count > 2) and (M.Groups[2].Value <> '') then 'write' else 'read';
        if not Complete and not MatchText(Name, Chain.ToStringArray) then
          Exit(Refuse('ancestry-unknown', Stop, FClsFid, FCls.StartLine, Format('the ancestry of `%s` stops at `%s`, ' +
            'which no index given declares, and line %d reads `%s` through a cast (pass --library-db)', [FCls.Name, Stop,
            R.Line, Name])));
        if not CarryChainMember(U, False, Names, Chain, Carried) then Exit(False);
      end;
    end;
  finally
    Lines.Free;
    Carried.Free;
    Chain.Free;
    Names.Free;
  end;
end;

{ No name inside a `with X as TClass do` body may change its binding when the interface
  replaces the class: a member of the class chain the interface does not carry, a getter
  name, an IInterface method. A public or published field or property of the chain is put on the
  interface first (CarryChainMember). A qualified name (`Self.InBuf`) cannot rebind (T17b D1). }
function TMemberPlan.CheckWithBodies: Boolean;
var
  Names  : TStringList;
  Chain  : TStringList;
  Carried: TDictionary<string, Integer>;
  Stop   : string;
begin
  Result:= True;
  if FWithLines.Count = 0 then Exit;
  Names  := TStringList.Create(dupIgnore, True, False);
  Chain  := TStringList.Create(dupIgnore, True, False);
  Carried:= TDictionary<string, Integer>.Create;
  try
    if not ChainMembers(FIdx, Stored(FCls), Names, Stop) then
      Exit(Refuse('ancestry-unknown', Stop, FClsFid, FCls.StartLine, Format('the ancestry of `%s` stops at ' +
        '`%s`, which no index given declares: what a `with` body binds to it cannot be checked (pass --library-db)',
        [FCls.Name, Stop])));
    Chain.AddStrings(Names);
    Names.AddStrings(FGetters.ToArray);
    for var St in FSetters do if St <> '' then Names.Add(St);
    Names.AddStrings(CIInterfaceMethods);
    RemoveCarriedNames(Names);
    { carried for a cast already (CheckCastChainMembers): a write here still needs its setter }
    for var I:= 0 to FMembers.Count - 1 do
      if FMembers[I].Id = 0 then Carried.Add(LowerCase(FMembers[I].Name), I);
    var Refs:=FStore.GetReferencesFromFile(FFromFid);
    for var W in FWithLines do
      for var R in BareBodyRefs(W, Refs) do
        if not CarryChainMember(R, True, Names, Chain, Carried) then Exit(False);
    { what was just carried adds names of its own, which the body must not use either }
    for var I:= 0 to FMembers.Count - 1 do
    begin
      Names.Add(FGetters[I]);
      if FSetters[I] <> '' then Names.Add(FSetters[I]);
    end;
    for var W in FWithLines do
      for var R in BareBodyRefs(W, Refs) do
        if Names.IndexOf(R.NameText) >= 0 then
          Exit(Refuse('with-member', R.NameText, FFromFid, R.StartLine, Format('inside `with ... as %s do` ' +
            '(line %d), `%s` at line %d names a member of `%s` or its ancestors that the interface does not ' +
            'carry: after the rewrite it would bind to something else', [FCls.Name, W, R.NameText, R.StartLine,
            FCls.Name])));
  finally
    Carried.Free;
    Chain.Free;
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

function EffectiveUnitScopes(const pDprojText: string): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    var UseDefaults:= True;
    for var M in TRegEx.Matches(pDprojText, '<DCC_Namespace>([^<]*)</DCC_Namespace>') do
    begin
      UseDefaults:= False;
      for var Part in M.Groups[1].Value.Split([';']) do
      begin
        var N:= Trim(Part);
        if ContainsStr(N, '$(') then UseDefaults:= True
        else if (N <> '') and not L.Contains(N) then L.Add(N);
      end;
    end;
    if UseDefaults then
      for var N in CUnitScopeNames do
        if not L.Contains(N) then L.Add(N);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ Whether pSegment starts a unit-scope name of the project (`System` of `System.Win`, `MyCo`). }
function TMemberPlan.IsScopeRoot(const pSegment: string): Boolean;
begin
  for var NS in FScopes do
    if SameText(NS.Split(['.'])[0], pSegment) then Exit(True);
  Result:= False;
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
      for var NS in FScopes do
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
      if IsScopeRoot(Segs[0]) then
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
  begin
    for var T in TRegEx.Matches(M.Signature, '[A-Za-z_][A-Za-z0-9_.]*') do
      if not AddLeafUse(M, T.Value, T.Value) then Exit(False);
    if FIndexed.ContainsKey(M.Id) then  { W6 C7: the index parameter types }
      for var Group in FIndexed[M.Id].Split([';']) do
      begin
        var Colon:= Group.IndexOf(':');
        if Colon < 0 then Continue;
        for var T in TRegEx.Matches(Group.Substring(Colon + 1), '[A-Za-z_][A-Za-z0-9_.]*') do
          if not AddLeafUse(M, T.Value, T.Value) then Exit(False);
      end;
  end;
  Result:= True;
end;

{ W6 C7: member pI's index parameter list wrapped in pOpen / pClose; '' for a non-indexed member. }
function TMemberPlan.IndexList(pI: Integer; const pOpen, pClose: string): string;
begin
  Result:= if FIndexed.ContainsKey(FMembers[pI].Id) then pOpen + FIndexed[FMembers[pI].Id] + pClose else '';
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
  var HLine, HCol: Integer;
  HeritageClose(FClsLines, FCls.StartLine, HLine, HCol);  { CheckClass proved it closes }
  var Close:= LineOf(FClsLines, HLine);
  AddEdit(FClsFid, HLine, True, [Copy(Close, 1, HCol - 1) + ', ' + FIface + Copy(Close, HCol, MaxInt)]);
  var Prev:= LineOf(FClsLines, FCls.EndLine - 1);
  var Indent:= if Trim(Prev) <> '' then Copy(Prev, 1, Length(Prev) - Length(TrimLeft(Prev)))
    else Copy(Head, 1, Length(Head) - Length(TrimLeft(Head))) + '    ';
  Decls := TList<string>.Create;
  Bodies:= TList<string>.Create;
  try
    for var I:= 0 to FMembers.Count - 1 do
    begin
      var Ty:= Trim(FMembers[I].Signature);
      if FKeptGetters.Contains(FGetters[I]) then
      begin
        { W6 C2: the class's own getter implements the interface's }
        AddSetterLines(I, Indent, Decls, Bodies);
        Continue;
      end;
      Decls.Add(Format('%s/// <summary>%s: returns %s (cycles --plan, member hand-over).</summary>', [Indent, FIface,
        FMembers[I].Name]));
      Decls.Add(Format('%sfunction %s%s: %s;', [Indent, FGetters[I], IndexList(I, '(', ')'), Ty]));
      Bodies.Add('');
      Bodies.Add(Format('function %s.%s%s: %s;', [FCls.Name, FGetters[I], IndexList(I, '(', ')'), Ty]));
      Bodies.Add('begin');
      Bodies.Add(Format('  Result := %s;', [FReads[I]]));
      Bodies.Add('end;');
      AddSetterLines(I, Indent, Decls, Bodies);
    end;
    if Decls.Count > 0 then  { B2: an edge that only calls methods needs no getter }
    begin
      AddEdit(FClsFid, FCls.EndLine - 1, False, Decls.ToArray);
      AddEdit(FClsFid, BodyAnchor(FClsLines), False, Bodies.ToArray);
    end;
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
      L.Add(Format('    function %s%s: %s;', [FGetters[I], IndexList(I, '(', ')'), Trim(FMembers[I].Signature)]));
    AddIfaceSetters(L);
    L.AddRange(FMethodDecls);
    for var I:= 0 to FMembers.Count - 1 do
      L.Add(Format('    property %s%s: %s read %s%s;', [FMembers[I].Name, IndexList(I, '[', ']'), Trim(FMembers[I].Signature), FGetters[I],
        WriteClause(I)]));
    L.Add('  end;');
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ `I<Class without its T>Surface`. }
function DefaultIfaceName(const pClass: string): string;
begin
  Result:= 'I' + (if (Length(pClass) > 1) and (UpCase(pClass[1]) = 'T') then Copy(pClass, 2, MaxInt) else pClass) + 'Surface';
end;

function TMemberPlan.Run(const pLeafUnit, pIfaceName: string; out pRefusal: TRecipeRefusal): TRecipeSteps;
begin
  Result  := Default(TRecipeSteps);
  FRefusal:= Default(TRecipeRefusal);
  var Ok:= (FFromFid > 0) and (FClsFid > 0) and CheckShape;
  if Ok then
  begin
    FIface:= if pIfaceName <> '' then pIfaceName else DefaultIfaceName(FCls.Name);
    Ok:= CheckMembers and CheckWrites and CheckMethods and CheckClass;
    { lane 148 CY: CheckCastExceptions first -- it picks the As<Surface> helper RewriteConsumer writes }
    Ok:= Ok and CheckTypeDecls and CheckCastExceptions and RewriteConsumer;
    Ok:= Ok and CheckCastChainMembers;
    Ok:= Ok and CheckWithBodies and CheckMethodMentions and CollectLeafUses;
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
  for var St in FSetters do if St <> '' then Result.Setters:= Result.Setters + [St];
  for var M in FMethods do Result.MethodSigs:= Result.MethodSigs + [M.Name + Trim(M.Signature)];
  Result.KeptGetters  := FKeptGetters.ToArray;
  SetLength(Result.Surfaces, 1);
  Result.Surfaces[0].ClassTypeName:= Result.ClassTypeName;
  Result.Surfaces[0].ClassId      := Result.ClassId;
  Result.Surfaces[0].IfaceName    := Result.IfaceName;
  Result.Surfaces[0].IfaceGuid    := Result.IfaceGuid;
  Result.Surfaces[0].IfaceDecl    := Result.IfaceDecl;
  Result.Surfaces[0].MemberSigs   := Result.MemberSigs;
  Result.Surfaces[0].Setters      := Result.Setters;
  Result.Surfaces[0].MethodSigs   := Result.MethodSigs;
  Result.Surfaces[0].CastAncestor := Result.CastAncestor;
  Result.Surfaces[0].KeptGetters  := Result.KeptGetters;
  Result.Surfaces[0].AsHelper     := FAsHelper;
  Result.Surfaces[0].HandlesInvalidCast:= FHandles;
  Result.Surfaces[0].HardCastChange    := FHardCastChange;
end;

type
  { One PlanMemberInterface run on an edge through several classes: one TMemberPlan per class, over the
    refs of that class and the consumer lines as the classes before it rewrote them. Decisions: the
    plans stay one-class planners (every existing refusal keeps its meaning, per class), and only this
    composer knows there are several; see PlanMemberInterface's remarks for the contract. }
  TEdgeComposer = class
  private
    FSource : IEdgeSurfaceSource;
    FLibrary: ISymbolStore;
    FStore  : ISymbolStore;
    FIdx    : TTypeIndex;
    FSurface: TEdgeSurface;
    FScopes : TArray<string>;
    FFromFid: Int64;
    FToFid  : Int64;
    FClasses: TArray<TSymbol>;
    FLines  : TArray<string>;
    FRefusal: TRecipeRefusal;
    function Refuse(const pKind, pSymbol: string; pLine: Integer; const pReason: string): Boolean;
    function CollectClasses: Boolean;
    function HoldsMember(const pCls: TSymbol; pParentId: Int64): Boolean;
    function ClassesOfRef(const pR: TEdgeRef): TArray<Integer>;
    function SubSurface(pClass: Integer): TEdgeSurface;
    function PickNames(const pGiven: TArray<string>): TArray<string>;
    procedure Overlay(const pSteps: TRecipeSteps);
    function Merge(const pParts: TArray<TRecipeSteps>): TRecipeSteps;
  public
    constructor Create(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore; const pSurface: TEdgeSurface;
      const pUnitScopes: TArray<string>);
    function Run(const pLeafUnit: string; const pIfaceNames: TArray<string>; out pRefusal: TRecipeRefusal): TRecipeSteps;
  end;

constructor TEdgeComposer.Create(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore;
  const pSurface: TEdgeSurface; const pUnitScopes: TArray<string>);
begin
  inherited Create;
  FSource     := pSource;
  FLibrary    := pLibrary;
  FStore      := pSource.Store;
  FIdx.Project:= FStore;
  FIdx.Lib    := pLibrary;
  FSurface    := pSurface;
  FScopes     := pUnitScopes;
  FFromFid    := pSource.FidOfStem(pSurface.FromStem);
  FToFid      := pSource.FidOfStem(pSurface.ToStem);
  FLines      := pSource.FileLines(FFromFid);
end;

function TEdgeComposer.Refuse(const pKind, pSymbol: string; pLine: Integer; const pReason: string): Boolean;
begin
  FRefusal:= MakeRefusal(pKind, pSymbol, FFromFid, pLine, pReason);
  Result  := False;
end;

{ The classes of the edge that are an `is` / `as` operand or (lane 149 CYB) a hard-cast target, sorted by name;
  any other `is` / `as` operand of the edge (an interface, a type alias) refuses: no class plan would rewrite it. }
function TEdgeComposer.CollectClasses: Boolean;
var
  Found: TList<TSymbol>;
begin
  Found:= TList<TSymbol>.Create;
  try
    for var R in FSurface.Refs do
    begin
      if R.Kind not in [erTypeIs, erTypeAs] then Continue;
      var S:= if R.SymbolId > 0 then FStore.GetSymbolById(R.SymbolId) else Default(TSymbol);
      if (S.Kind <> skClass) or (S.FileId <> FToFid) then
        Exit(Refuse('other-ref', R.Name, R.Line, Format('line %d tests or casts against `%s`, which is no class of ' +
          '`%s` (`%s`)', [R.Line, R.Name, FSurface.ToStem, R.LineText])));
      var Known:= False;
      for var C in Found do
        if C.Id = S.Id then Known:= True;
      if not Known then Found.Add(S);
    end;
    { lane 149 CYB (149-CY-12): a class of the edge it only hard-casts (`TX(X).M`) gets its own plan too --
      the per-class C7 path; a cast to anything else (an enum, a record) is left to the class plans }
    for var R in FSurface.Refs do
    begin
      if (R.Kind <> erTypeCast) or (R.SymbolId <= 0) then Continue;
      var S:= FStore.GetSymbolById(R.SymbolId);
      if (S.Kind <> skClass) or (S.FileId <> FToFid) then Continue;
      var Known:= False;
      for var C in Found do
        if C.Id = S.Id then Known:= True;
      if not Known then Found.Add(S);
    end;
    if Found.Count = 0 then
      Exit(Refuse('multiple-classes', string.Join(', ', FSurface.ClassNames), 0, Format('the edge names %d classes ' +
        '(%s) and neither tests nor casts any of them (`is` / `as` / `TX(X).M`)', [Length(FSurface.ClassNames),
        string.Join(', ', FSurface.ClassNames)])));
    Found.Sort(TComparer<TSymbol>.Construct(
      function(const pLeft, pRight: TSymbol): Integer
      begin
        Result:= CompareText(pLeft.Name, pRight.Name);
      end));
    FClasses:= Found.ToArray;
  finally
    Found.Free;
  end;
  Result:= True;
end;

{ Whether pCls declares a member of the class pParentId, or inherits it through ancestors declared in
  its own unit (the only ones the edge can name). }
function TEdgeComposer.HoldsMember(const pCls: TSymbol; pParentId: Int64): Boolean;
var
  Cur, Next: TStoredType;
begin
  Cur.Sym  := pCls;
  Cur.Store:= FStore;
  for var Hop:= 1 to CMaxAncestorHops do
  begin
    if Cur.Sym.Id = pParentId then Exit(True);
    if not FIdx.Find(FIdx.ParentOf(Cur), False, Next) or FIdx.IsLib(Next) or (Next.Sym.FileId <> pCls.FileId) then Exit(False);
    Cur:= Next;
  end;
  Result:= False;
end;

{ Which classes' plans must see the ref (see PlanMemberInterface's remarks). A bare write in a `with`
  body is recorded against the class declaring the member (MemberOf). }
function TEdgeComposer.ClassesOfRef(const pR: TEdgeRef): TArray<Integer>;
begin
  Result:= nil;
  var S:= if pR.SymbolId > 0 then FStore.GetSymbolById(pR.SymbolId) else Default(TSymbol);
  var ParentId: Int64:= S.ParentId;
  if S.Kind = skClass then
  begin
    if pR.Kind <> erMemberWrite then
    begin
      for var I:= 0 to High(FClasses) do
        if FClasses[I].Id = S.Id then Exit(TArray<Integer>.Create(I));
      Exit(TArray<Integer>.Create(0));
    end;
    ParentId:= S.Id;
  end;
  for var I:= 0 to High(FClasses) do
    if HoldsMember(FClasses[I], ParentId) then Result:= Result + [I];
  if Result = nil then Result:= TArray<Integer>.Create(0);
end;

{ The surface one class's plan sees: the refs of that class, and that class alone. }
function TEdgeComposer.SubSurface(pClass: Integer): TEdgeSurface;
var
  Refs: TList<TEdgeRef>;
begin
  Result:= FSurface;
  Refs  := TList<TEdgeRef>.Create;
  try
    for var R in FSurface.Refs do
      if TArray.Contains<Integer>(ClassesOfRef(R), pClass) then Refs.Add(R);
    Result.Refs:= Refs.ToArray;
  finally
    Refs.Free;
  end;
  Result.ClassNames:= TArray<string>.Create(FClasses[pClass].Name);
end;

{ The name of each class's interface: pGiven when it names them all, else the default; a default
  another class of the edge took first (TFoo and Foo) gets the lowest free suffix. }
function TEdgeComposer.PickNames(const pGiven: TArray<string>): TArray<string>;
begin
  if Length(pGiven) = Length(FClasses) then Exit(pGiven);
  Result:= nil;
  for var C in FClasses do
  begin
    var Name:= DefaultIfaceName(C.Name);
    var N:= 1;
    while MatchText(Name, Result) do
    begin
      Inc(N);
      Name:= DefaultIfaceName(C.Name) + IntToStr(N);
    end;
    Result:= Result + [Name];
  end;
end;

{ The consumer lines the next class's plan reads: this class's rewrites applied (every rewrite
  replaces a whole line, keeping the line numbers). }
procedure TEdgeComposer.Overlay(const pSteps: TRecipeSteps);
begin
  for var E in pSteps.Edits do
    if (E.Fid = FFromFid) and E.Replace and (Length(E.NewLines) = 1) and (E.Line >= 1) and (E.Line <= Length(FLines)) then
      FLines[E.Line - 1]:= E.NewLines[0];
end;


{ Appends pItems not yet in pTo (case-insensitive), in order. }
procedure AddUniqueText(pTo: TList<string>; const pItems: TArray<string>);
begin
  for var S in pItems do
    if not MatchText(S, pTo.ToArray) then pTo.Add(S);
end;

{ The merged steps: the first class's scalars, everybody's lists. An edit of a line an earlier class
  edited: a replace wins (it was made from the earlier text); an insert at the same anchor (the getter
  bodies) follows the earlier lines. }
function TEdgeComposer.Merge(const pParts: TArray<TRecipeSteps>): TRecipeSteps;
var
  Edits: TList<TRecipeEdit>;
  Leaf, Cons: TList<string>;
begin
  Result:= pParts[0];
  Result.MemberSigs:= nil;
  Result.Setters   := nil;
  Result.MethodSigs:= nil;
  Result.KeptGetters:= nil;
  Result.Surfaces  := nil;
  Edits:= TList<TRecipeEdit>.Create;
  Leaf := TList<string>.Create;
  Cons := TList<string>.Create;
  try
    for var P in pParts do
    begin
      for var E in P.Edits do
      begin
        var At:= -1;
        for var I:= 0 to Edits.Count - 1 do
          if (Edits[I].Fid = E.Fid) and (Edits[I].Line = E.Line) and (Edits[I].Replace = E.Replace) then At:= I;
        if At < 0 then Edits.Add(E)
        else
        begin
          var Into:= Edits[At];
          Into.NewLines:= if E.Replace then E.NewLines else Into.NewLines + E.NewLines;
          Edits[At]:= Into;
        end;
      end;
      AddUniqueText(Leaf, P.LeafUses);
      AddUniqueText(Cons, P.ConsumerUses);
      Result.MemberSigs := Result.MemberSigs + P.MemberSigs;
      Result.Setters    := Result.Setters + P.Setters;
      Result.MethodSigs := Result.MethodSigs + P.MethodSigs;
      Result.KeptGetters:= Result.KeptGetters + P.KeptGetters;
      Result.Surfaces   := Result.Surfaces + P.Surfaces;
    end;
    Result.Edits       := Edits.ToArray;
    Result.LeafUses    := Leaf.ToArray;
    Result.ConsumerUses:= Cons.ToArray;
    Result.IfaceDecl   := MemberSurfaceDecls(Result.Surfaces);
  finally
    Cons.Free;
    Leaf.Free;
    Edits.Free;
  end;
end;

function TEdgeComposer.Run(const pLeafUnit: string; const pIfaceNames: TArray<string>;
  out pRefusal: TRecipeRefusal): TRecipeSteps;
var
  Parts  : TArray<TRecipeSteps>;
  Refusal: TRecipeRefusal;
begin
  Result:= Default(TRecipeSteps);
  pRefusal:= Default(TRecipeRefusal);
  if not CollectClasses then
  begin
    pRefusal:= FRefusal;
    Exit;
  end;
  var Names:= PickNames(pIfaceNames);
  FLines:= Copy(FLines);
  SetLength(Parts, Length(FClasses));
  for var I:= 0 to High(FClasses) do
  begin
    var P:= TMemberPlan.Create(FSource, FLibrary, SubSurface(I), FScopes);
    try
      P.FLines:= Copy(FLines);
      Parts[I]:= P.Run(pLeafUnit, Names[I], Refusal);
      if Refusal.Kind <> '' then
      begin
        pRefusal:= Refusal;
        pRefusal.Reason:= Format('class `%s`: %s', [FClasses[I].Name, Refusal.Reason]);
        Exit;
      end;
    finally
      P.Free;
    end;
    Overlay(Parts[I]);
  end;
  Result:= Merge(Parts);
end;

function MemberSurfaceDecls(const pSurfaces: TArray<TMemberSurface>): TArray<string>;
begin
  Result:= nil;
  for var S in pSurfaces do
    if not S.Reused then
    begin
      if Result <> nil then Result:= Result + [''];
      Result:= Result + S.IfaceDecl;
    end;
end;

function PlanMemberInterface(const pSource: IEdgeSurfaceSource; const pLibrary: ISymbolStore;
  const pSurface: TEdgeSurface; const pLeafUnit: string; const pUnitScopes: TArray<string>;
  out pRefusal: TRecipeRefusal; const pIfaceNames: TArray<string>): TRecipeSteps;
var
  P: TMemberPlan;
  C: TEdgeComposer;
begin
  if Length(pSurface.ClassNames) > 1 then
  begin
    C:= TEdgeComposer.Create(pSource, pLibrary, pSurface, pUnitScopes);
    try
      Exit(C.Run(pLeafUnit, pIfaceNames, pRefusal));
    finally
      C.Free;
    end;
  end;
  P:= TMemberPlan.Create(pSource, pLibrary, pSurface, pUnitScopes);
  try
    Result:= P.Run(pLeafUnit, (if Length(pIfaceNames) > 0 then pIfaceNames[0] else ''), pRefusal);
  finally
    P.Free;
  end;
end;

function BareUsesBinding(const pBare: string; const pScopes: TArray<string>;
  const pIsProjectUnit: TProjectUnitTest): string;
begin
  Result:= '';
  if (pBare = '') or ContainsStr(pBare, '.') then Exit;
  if pIsProjectUnit(LowerCase(pBare)) then Exit(LowerCase(pBare));
  for var S in pScopes do
    if pIsProjectUnit(LowerCase(S + '.' + pBare)) then Exit(LowerCase(S + '.' + pBare));
end;

function ProjectUnitScopes(const pStore: ISymbolStore): TArray<string>;
var
  Text: string;
begin
  Text:= '';
  if pStore <> nil then
    for var Fid in pStore.GetAllFileIds do
    begin
      var Path:= StringReplace(pStore.GetFilePath(Fid), '/', '\', [rfReplaceAll]);
      if not MatchText(ExtractFileExt(Path), ['.dpr', '.dpk']) then Continue;
      if TFile.Exists(ChangeFileExt(Path, '.dproj')) then Text:= TFile.ReadAllText(ChangeFileExt(Path, '.dproj'));
      Break;
    end;
  Result:= EffectiveUnitScopes(Text);
end;
end.
