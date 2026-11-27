unit DRagLint.Index.DataFlowFacts;  // dl:ok unit-too-large@5e9c -- REVIEWED 1.56 EXT-B1 2026-11-26: the B3 value classes and the EXT-B2 / EXT-B3 hook seam live with the one walker they extend; a split adds a unit to drag-lint.dproj / .dpr (lane INT's files) and is requested there

/// <summary>Index-time data-flow facts: for one routine, which SOURCE (a declared
/// parameter, a field, a unit global, a feeding ref, the var/out slot of an earlier
/// call) can reach which DESTINATION (a call argument, a member write, a field or
/// global write, a var/out parameter of this routine, Result). The rows go to the
/// data_flows table (TDataFlowRow, DF_DST_* / DF_SRC_* in DRagLint.Core.Model) and
/// are composed across routines by the taint rules (DRagLint.Lint.TaintRules).</summary>
/// <remarks>
/// T1 (2026-10-27, plan docs\superpowers\plans\2026-10-27-taint-interprocedural-plan.md
/// sections 2-3). TRoutineVarTable classifies every identifier (parameter / local /
/// Result / other); a forward lattice (TTaintReach, implementation section) runs over
/// TCfgBuilder's CFG with TDataFlowSolver: per routine variable a MAY set of source
/// tokens (with a via-local bit) and a MUST set. A plain assignment kills and gens, a
/// receive (container mutator, member write on a local, var-arg pass) gens, joins union
/// MAY and intersect MUST. Rows are recorded in one final pass over the fixpoint IN
/// values; 'result' / 'outparam' rows come from the IN value of the Exit block. A row's
/// Cond is True when its token is in MAY but not MUST at the destination (a branch or
/// loop decided it). A routine whose CFG is Skipped (goto / label / asm) or has more
/// than DF_CFG_BLOCK_CAP blocks takes the flow-insensitive fallback (source-order
/// walk, gen-only, iterated to a fixpoint; every row Cond = True); lambda bodies are
/// always walked that way with the state at the lambda. `with` bodies (opaque CFG
/// items) emit nothing. Rows are deduplicated on (destination, source) -- ViaLocal
/// and Cond are AND-merged -- and capped at DF_ROW_CAP per routine (a stderr note).
/// 1.56 B3 (lane EXT-B1): values of numeric / Boolean / date-time type flow too. Every
/// source token carries a value class (TDataFlowRow.ValClass, DF_VAL_*): '' for the
/// pre-1.56 flows, which are emitted exactly as before, and a class for a flow the
/// pre-1.56 walk dropped -- a scalar-typed parameter / local, an arithmetic or comparison
/// operator, a numeric member (`L.Count`), a numeric RTL result (`Length`, `StrToInt`).
/// The class is the scalar class the value had where it FIRST became a scalar; a later
/// conversion (`IntToStr`) does not change it. Rows with ValClass '' are therefore the
/// pre-1.56 row set, and value rows are additions with their own DF_ROW_CAP budget.
/// Lane EXT-B1F: a source whose scalar type is DECLARED in the unit -- a field, a unit
/// variable, the result of a function or method (also called without parentheses) --
/// had a pre-1.56 row because the old walk did not know its type. That row is kept
/// (ValClass ''), and the same flow is emitted once more as a value row of the declared
/// class; a field / unit variable of declared scalar class also types what is written
/// to it, and IntToStr types its argument. So ValClass '' means "a pre-1.56 flow", NOT
/// "not numeric": a consumer that wants numeric flows reads ValClass <> ''.
/// Lanes EXT-B2 / EXT-B3 extend the walk through TDataFlowFacts.RegisterExprHook /
/// RegisterWriteHook / RegisterStmtHook (TDataFlowSite).
/// This unit is under src\index, so the extractor version guard hashes it: any change
/// to it is an extractor change. All .pas source: strict 7-bit ASCII, CRLF, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model  // dl:unit DRagLint.Core.Model accepted -- the DF_* kind constants and TDataFlowRow ARE the T0 contract this unit writes
  , TreeSitter
  ;

const
  /// <summary>A routine whose CFG has more blocks than this takes the flow-insensitive
  /// fallback (cost guard; a stderr note names it).</summary>
  DF_CFG_BLOCK_CAP = 2000;
  /// <summary>TDataFlowCallees.DeclaredClass group: a class / record field.</summary>
  DF_DECL_FIELD = 'f';
  /// <summary>TDataFlowCallees.DeclaredClass group: a unit variable.</summary>
  DF_DECL_GLOBAL = 'g';
  /// <summary>TDataFlowCallees.DeclaredClass group: the result of a function or method.</summary>
  DF_DECL_RESULT = 'r';
  /// <summary>Separates the scope from the name in a TDataFlowCallees declared-class key (no
  /// identifier holds it).</summary>
  DF_SCOPE_SEP = '|';

type
  /// <summary>The routines one unit declares, keyed by lower-case name: per argument
  /// position, True when SOME same-named routine of the unit has a var / out
  /// parameter there. Built once per file by TDataFlowFacts.BuildCallees; it decides
  /// which call arguments get an 'argout' source (see TDataFlowFacts.Collect).</summary>
  /// <remarks>
  /// Owned by the caller of BuildCallees. Name-keyed on purpose: the
  /// extractor sees one file, so overloads and same-named methods of different
  /// classes are merged (any var/out at a position keeps that position).
  /// 1.56 (lane EXT-B1F): the same object also carries the DECLARED scalar classes of the
  /// unit's fields, unit variables and function results (DeclaredClass), which is why it
  /// is a class of its own and no longer a bare dictionary alias; the dictionary part is
  /// unchanged.
  /// FIXR-B (REV-1 #6): the declared classes are keyed by SCOPE + name, not by the bare
  /// name. A scope is the lower-case qualified name of the declaring symbol's parent
  /// (ScopeOf): the class / record for a field or a method, the unit for a unit variable
  /// or a plain function. A name-keyed table gave `Other.Total` (a string property of
  /// another class) the class of this unit's `function Total: Currency`. The var/out
  /// masks stay name-keyed.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.DataFlowFacts.pas) ?, DRagLint.Core.Indexer.TIndexer.IndexFileBody (DRagLint.Core.Indexer.pas) ?, DRagLint.Index.DataFlowFacts.TCollector.Create (DRagLint.Index.DataFlowFacts.pas) ?, DRagLint.Index.DataFlowFacts.TDataFlowFacts.BuildCallees (DRagLint.Index.DataFlowFacts.pas), DRagLint.Index.DataFlowFacts.TDataFlowFacts.Collect (DRagLint.Index.DataFlowFacts.pas) ? (+1 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDataFlowCallees = class(TDictionary<string, TArray<Boolean>>)
    private
      FDeclCls  : TDictionary<string, string>;
      FDeclType : TDictionary<string, string>;
      FTypeScope: TDictionary<string, string>;
      FUnitScope: string;
      procedure NoteDeclared(AGroup: Char; const AScope, ALowerName, ACls, ALowerType: string);
      procedure NoteType(const ALowerTypeName, AScope: string);
    public
      /// <summary>Frees the declared-class tables with the dictionary.</summary>
      destructor Destroy; override;
      /// <summary>The scope a symbol is declared in: its qualified name without the last
      /// segment, lower case ('uOrders.TOrder.FTotal' gives 'uorders.torder').</summary>
      /// <param name="AQualifiedName">TSymbol.QualifiedName, as parsed.</param>
      /// <returns>The scope key; '' when the name has no qualifier.</returns>
      class function ScopeOf(const AQualifiedName: string): string; static;
      /// <summary>The bare lower-case name of a type as written in a declaration: generic
      /// arguments and a unit qualifier are dropped ('Generics.TList&lt;TFoo&gt;' gives
      /// 'tlist').</summary>
      /// <param name="ATypeText">The type text of a variable, parameter or field.</param>
      /// <returns>The bare name, lower case; '' for an empty text.</returns>
      class function BareTypeName(const ATypeText: string): string; static;
      /// <summary>The DF_VAL_* class of the ONE declaration of a name in a scope.</summary>
      /// <param name="AGroup">DF_DECL_FIELD ('f', a class / record field), DF_DECL_GLOBAL ('g', a
      /// unit variable) or DF_DECL_RESULT ('r', the result of a function or method).</param>
      /// <param name="AScope">The declaring scope (ScopeOf, ScopeOfType or UnitScope).</param>
      /// <param name="ALowerName">The bare name, lower case.</param>
      /// <returns>The class; '' when that scope declares no such name, when its type is no scalar
      /// (TAINT_SCALAR_TYPES), or when two declarations of the name IN THAT SCOPE differ in class
      /// (overloads: a disagreement claims nothing).</returns>
      function DeclaredClass(AGroup: Char; const AScope, ALowerName: string): string;
      /// <summary>True when the scope declares the name in the group at all, scalar or not.</summary>
      /// <param name="AGroup">As for DeclaredClass.</param>
      /// <param name="AScope">The declaring scope.</param>
      /// <param name="ALowerName">The bare name, lower case.</param>
      /// <returns>False when DeclaredClass would answer '' for want of a declaration.</returns>
      function Declares(AGroup: Char; const AScope, ALowerName: string): Boolean;
      /// <summary>The declared type of a field or unit variable, as a bare type name.</summary>
      /// <param name="AGroup">DF_DECL_FIELD or DF_DECL_GLOBAL.</param>
      /// <param name="AScope">The declaring scope.</param>
      /// <param name="ALowerName">The bare name, lower case.</param>
      /// <returns>BareTypeName of the declared type; '' when the scope declares no such name.</returns>
      function DeclaredType(AGroup: Char; const AScope, ALowerName: string): string;
      /// <summary>The scope of a class / record / interface THIS unit declares.</summary>
      /// <param name="ALowerTypeName">BareTypeName of the type.</param>
      /// <returns>The scope its members are declared in; '' when the unit declares no such type or
      /// declares two of that bare name (nested types).</returns>
      function ScopeOfType(const ALowerTypeName: string): string;
      /// <summary>The scope of the unit's own variables and plain routines; '' when the symbols
      /// held no unit / program symbol.</summary>
      property UnitScope: string read FUnitScope;
  end;

  /// <summary>1.56: the value of one expression as the data-flow walk sees it: the sources
  /// that may / must reach it and its inferred scalar class.</summary>
  /// <remarks>Opaque to a hook: build one with TDataFlowSite.ValueOf / NewSource / Merge and
  /// hand it back unchanged. May = sorted encoded source elements, Must = sorted source ids
  /// (both private to the walk of ONE routine; never keep a value across routines).
  /// Cls = one of DF_VAL_* when the expression's type is known to be that scalar class,
  /// else ''.</remarks>
  TDataFlowValue = record
    /// <summary>Sources reaching on at least one path (encoded; opaque).</summary>
    May : TArray<Integer>;
    /// <summary>Sources reaching on every path (opaque).</summary>
    Must: TArray<Integer>;
    /// <summary>Inferred scalar class of the expression (DF_VAL_*), '' = unknown or not a scalar.</summary>
    Cls : string;
  end;

  /// <summary>1.56 seam (lanes EXT-B2, EXT-B3): what a registered hook may ask of the
  /// data-flow walk of the routine it is called for.</summary>
  /// <remarks>Valid only during the hook call; owned by the walk. Not thread-safe. A hook is
  /// called on EVERY pass of the fixpoint, not once per site: it must be deterministic and
  /// keep no state of its own; EmitRow writes only on the recording pass. A hook may ADD
  /// sources and rows of the 1.56 kinds (DF_SRC_DSFIELD, DF_SRC_EXCEPT, DF_DST_DSFIELD,
  /// DF_DST_RAISE); it must not create a source of a pre-1.56 kind with an empty value
  /// class, because rows of the old kinds with ValClass '' are the pre-1.56 row set.</remarks>
  TDataFlowSite = class abstract
    public
      /// <summary>The source text of a node.</summary>
      /// <param name="ANode">Any node of the routine's tree; a null node gives ''.</param>
      /// <returns>The text, as written.</returns>
      function NodeText(const ANode: TTSNode): string; virtual; abstract;
      /// <summary>True on the pass that writes rows (the passes before it only move state).</summary>
      /// <returns>False during the fixpoint iteration.</returns>
      function IsRecording: Boolean; virtual; abstract;
      /// <summary>The identity of this walk: one number per routine walk, never used twice in a
      /// process (FIXR-B, REV-1 #2).</summary>
      /// <returns>A value greater than 0; every pass of the same walk returns the same one.</returns>
      /// <remarks>What a hook keys a memo of the routine's TREE on: a tree address or a node id
      /// can be reused by a later parse, this cannot.</remarks>
      function WalkId: UInt64; virtual; abstract;
      /// <summary>Evaluates an expression in the state at the hook's site, exactly as the walk
      /// itself would (argument rows of calls inside it are recorded, expression hooks run).</summary>
      /// <param name="AExpr">An expression node; never the node the running expression hook was
      /// called for (that recurses without end).</param>
      /// <returns>Its value; empty for a null node.</returns>
      function ValueOf(const AExpr: TTSNode): TDataFlowValue; virtual; abstract;
      /// <summary>A value made of ONE new source.</summary>
      /// <param name="AKind">The row's src_kind: a 1.56 DF_SRC_* constant.</param>
      /// <param name="AIndex">The row's src_index (-1 = unused).</param>
      /// <param name="APos">The node whose start gives src_line / src_col; null = 0 / 0.</param>
      /// <param name="AName">The row's src_name.</param>
      /// <param name="AValClass">The value class of the source (DF_VAL_* or '').</param>
      /// <returns>The value; the same arguments give the same source on every pass.</returns>
      function NewSource(const AKind: string; AIndex: Integer; const APos: TTSNode; const AName, AValClass: string): TDataFlowValue; virtual; abstract;
      /// <summary>The union of two values (a value fed by both).</summary>
      /// <param name="A">The first value; its Cls is kept.</param>
      /// <param name="B">The second value.</param>
      /// <returns>The sources of both.</returns>
      function Merge(const A, B: TDataFlowValue): TDataFlowValue; virtual; abstract;
      /// <summary>Records one data_flows row per source of AValue (deduplicated like the walk's
      /// own rows). Does nothing before the recording pass.</summary>
      /// <param name="ADstKind">The row's dst_kind: a 1.56 DF_DST_* constant.</param>
      /// <param name="APos">The node whose start gives dst_line / dst_col; null = no row.</param>
      /// <param name="AIndex">The row's dst_index (-1 = unused).</param>
      /// <param name="AName">The row's dst_name.</param>
      /// <param name="AReceiver">The row's dst_receiver.</param>
      /// <param name="AValue">The value reaching the destination.</param>
      procedure EmitRow(const ADstKind: string; const APos: TTSNode; AIndex: Integer; const AName, AReceiver: string;
                        const AValue: TDataFlowValue); virtual; abstract;
  end;

  /// <summary>1.56 seam: called after the walk evaluated an expression node of the registered
  /// node type; the hook may add sources to its value (B14-3: a dataset-field read).</summary>
  /// <param name="ASite">The walk; valid during the call only.</param>
  /// <param name="ANode">The evaluated expression node.</param>
  /// <param name="AValue">Its value; replace it with ASite.Merge(AValue, ASite.NewSource(..)) to add a source.</param>
  TDataFlowExprHook = procedure(ASite: TDataFlowSite; const ANode: TTSNode; var AValue: TDataFlowValue);
  /// <summary>1.56 seam: called at every assignment, before the walk's own handling of the
  /// left side (B14-2: a dataset-field write that has no 'write' row).</summary>
  /// <param name="ASite">The walk; valid during the call only.</param>
  /// <param name="ALhs">The assignment's left-side node (any shape).</param>
  /// <param name="AValue">The value of the right side.</param>
  TDataFlowWriteHook = procedure(ASite: TDataFlowSite; const ALhs: TTSNode; const AValue: TDataFlowValue);
  /// <summary>1.56 seam: called when the walk reaches a statement node of the registered node
  /// type, before its own handling of it (B4: `raise`).</summary>
  /// <param name="ASite">The walk; valid during the call only.</param>
  /// <param name="ANode">The statement node.</param>
  TDataFlowStmtHook = procedure(ASite: TDataFlowSite; const ANode: TTSNode);

  /// <summary>Computes the data_flows rows of one routine from its tree-sitter
  /// subtree. Stateless apart from two process-wide counters; NOT thread-safe
  /// (the indexer's per-file loop is single-threaded).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Core.Indexer.TIndexer.IndexFileBody (DRagLint.Core.Indexer.pas)</para>
  /// <para>Used in units: DRagLint.Core.Indexer</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDataFlowFacts = class
    public
      /// <summary>The data_flows rows of routine ASym (see TDataFlowRow for every
      /// column's meaning).</summary>
      /// <param name="ASym">The routine symbol with its REAL identity: Id = symbols.id
      /// written in this file tx (becomes every row's SymbolId), ParentId = the owning
      /// class's symbols.id or -1 (becomes OwnerId, -1 -> 0).</param>
      /// <param name="AProc">The routine's defProc node.</param>
      /// <param name="ABody">The routine's body (block) node.</param>
      /// <param name="ASrc">The UTF-8 source bytes AProc/ABody index into.</param>
      /// <param name="AOwnerFields">Field names of the owning class (and ancestors known
      /// to this DB), as declared; empty for a plain routine.</param>
      /// <param name="AGlobals">This unit's unit-level variable names, as declared.</param>
      /// <param name="ACallees">This unit's routines (BuildCallees); nil = none known.
      /// Not owned.</param>
      /// <returns>The rows, deduplicated, at most DF_ROW_CAP; nil when nothing is
      /// proven or the body is pure asm. FileId is left 0 (PutDataFlows takes it from
      /// the file tx).</returns>
      /// <remarks>
      /// Never raises: an exception inside the walk (a malformed tree) is
      /// caught, a one-line stderr note names the routine, and nil is returned --
      /// silence over a wrong claim, and the file tx is not rolled back for it.
      /// Literals and nil emit nothing; a value of numeric / Boolean / date-time type
      /// emits VALUE rows (ValClass = a DF_VAL_* class; 1.56 B3); every other row keeps
      /// ValClass '' and is the row the pre-1.56 walk emitted. At most DF_ROW_CAP value
      /// (and hook) rows are added on top of the DF_ROW_CAP pre-1.56 rows.
      /// A field, unit variable or function result whose scalar type ACallees knows
      /// (TDataFlowCallees.DeclaredClass) emits BOTH its pre-1.56 row and a value row.
      /// The type is looked up in the declaring SCOPE (FIXR-B, REV-1 #6): a field in the
      /// class of ASym, a bare function name in that class and then in the unit, a member
      /// `X.M` in the type X is declared with (a local, a parameter, a field of the class,
      /// a unit variable) when this unit declares that type; any other receiver claims
      /// no class.
      /// Identifiers the var table cannot classify are refs (by position).
      /// An argument variable gets an 'argout' source (the callee may write it) only
      /// when the callee may have a var / out parameter at that position: a callee
      /// in ACallees decides by its mask (a position past every same-unit overload
      /// is kept); otherwise a short built-in RTL list decides (value-only routines
      /// drop, TryGetValue keeps position 1 only); every OTHER callee is unresolved
      /// here and KEEPS its argout source -- the linter resolves the callee and
      /// reads its outparam rows, so no taint the walk needs is lost.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Core.Indexer.TIndexer.IndexFileBody (DRagLint.Core.Indexer.pas), DRagLint.Index.DataFlowFacts.TDataFlowFacts.CollectMainBlock (DRagLint.Index.DataFlowFacts.pas)</para>
      /// <para>Calls: DRagLint.Index.DataFlowFacts.TCollector.Create, DRagLint.Index.DataFlowFacts.TCollector.Rows, DRagLint.Index.DataFlowFacts.TCollector.Run, Format, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType, Writeln</para>
      /// <para>Returns: nil; C.Rows</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Directives: static</para>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TCollector.Create"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TCollector.Rows"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TCollector.Run"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Collect(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                             const AOwnerFields: TArray<string>;
                             const AGlobals: TArray<string>;
                             const ACallees: TDataFlowCallees): TArray<TDataFlowRow>; static;
      /// <summary>The data_flows rows of a program's MAIN BLOCK (`begin ... end.` of a .dpr),
      /// attributed to the program symbol.</summary>
      /// <param name="AProgram">The skProgram symbol with its REAL identity (Id = symbols.id,
      /// ParentId -1).</param>
      /// <param name="ARoot">The file's tree root (the `program` / `library` node or its parent).</param>
      /// <param name="ASrc">The UTF-8 source bytes ARoot indexes into.</param>
      /// <param name="AGlobals">The program-level variable names, as declared.</param>
      /// <param name="ACallees">As for Collect; nil = none known. Not owned.</param>
      /// <returns>Collect's rows for the main block; nil when the root is no program or has no
      /// main block.</returns>
      /// <remarks>
      /// 1.52 EXTGAPS (HBEVENTS gap 2): before, a .dpr main block had NO data_flows rows
      /// -- `Fill(GDpr)` and `Application.CreateForm(TMainForm, MainForm)` were invisible to
      /// check-init, which fell back to source text. The block node is handed to Collect as both
      /// routine and body (TCfgBuilder.Build accepts a `block`); program-level vars are globals
      /// (AGlobals), never locals. Never raises (Collect's own guard).
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Core.Indexer.TIndexer.IndexFileBody (DRagLint.Core.Indexer.pas)</para>
      /// <para>Calls: Default, DRagLint.Index.DataFlowFacts.TDataFlowFacts.Collect, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType</para>
      /// <para>Returns: nil; Collect(AProgram, Block, Block, ASrc, nil, AGlobals, ACallees)</para>
      /// <para>Complexity: 11 (cyclomatic, outer body), 26 lines (full implementation)</para>
      /// <para>Directives: static</para>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.Collect"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CollectMainBlock(const AProgram: TSymbol; const ARoot: TTSNode; const ASrc: TBytes;
                                      const AGlobals: TArray<string>;
                                      const ACallees: TDataFlowCallees): TArray<TDataFlowRow>; static;
      /// <summary>The var/out masks of every routine ASymbols declares (parsed from
      /// TSymbol.Signature), for Collect; 1.56: also the declared scalar classes of the
      /// fields, unit variables and function results among ASymbols
      /// (TDataFlowCallees.DeclaredClass).</summary>
      /// <param name="ASymbols">One file's parsed symbols; non-routine kinds are skipped.</param>
      /// <returns>A new dictionary the CALLER frees (never nil).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Core.Indexer.TIndexer.IndexFileBody (DRagLint.Core.Indexer.pas)</para>
      /// <para>Calls: Copy, DRagLint.Index.DataFlowFacts.VarOutMask, LastDelimiter, LowerCase, Pos</para>
      /// <para>Returns: TDataFlowCallees.Create</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Directives: static</para>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.VarOutMask"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.CappedCount"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.Collect"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.CollectMainBlock"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.FallbackCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function BuildCallees(const ASymbols: TArray<TSymbol>): TDataFlowCallees; static;
      /// <summary>Routines that took the flow-insensitive fallback since process start
      /// (Skipped CFG or over DF_CFG_BLOCK_CAP blocks).</summary>
      /// <returns>The running count.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Returns: GFallbacks</para>
      /// <para>Effect-free (proven)</para>
      /// <para>Directives: static</para>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.BuildCallees"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.CappedCount"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.Collect"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.CollectMainBlock"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function FallbackCount: Integer; static;
      /// <summary>Routines whose rows hit DF_ROW_CAP since process start.</summary>
      /// <returns>The running count.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Returns: GCapped</para>
      /// <para>Effect-free (proven)</para>
      /// <para>Directives: static</para>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.BuildCallees"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.Collect"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.CollectMainBlock"/>
      /// <seealso cref="DRagLint.Index.DataFlowFacts.TDataFlowFacts.FallbackCount"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function CappedCount: Integer; static;
      /// <summary>1.56 seam: registers an expression hook for one tree-sitter node type
      /// ('exprDot', 'exprCall', 'exprSubscript', 'identifier', ...).</summary>
      /// <param name="ANodeType">The node type, as the grammar spells it.</param>
      /// <param name="AHook">The hook; nil is ignored.</param>
      /// <remarks>Call from a unit's initialization (process-wide, never removed, not
      /// thread-safe). Hooks of one node type run in registration order. Registering a hook
      /// is extraction: an extractor change.</remarks>
      class procedure RegisterExprHook(const ANodeType: string; AHook: TDataFlowExprHook); static;
      /// <summary>1.56 seam: registers a hook called at every assignment.</summary>
      /// <param name="AHook">The hook; nil is ignored.</param>
      /// <remarks>As RegisterExprHook.</remarks>
      class procedure RegisterWriteHook(AHook: TDataFlowWriteHook); static;
      /// <summary>1.56 seam: registers a statement hook for one node type ('raise', ...).</summary>
      /// <param name="ANodeType">The node type, as the grammar spells it.</param>
      /// <param name="AHook">The hook; nil is ignored.</param>
      /// <remarks>As RegisterExprHook. A statement nested in a `with` body is not walked.</remarks>
      class procedure RegisterStmtHook(const ANodeType: string; AHook: TDataFlowStmtHook); static;
  end;

implementation

uses
  DRagLint.Core.Encoding { 1.52 EXTGAPS2: data_flows positions are refs' CHARACTER columns }
  , DRagLint.Analysis.Cfg
  , DRagLint.Analysis.DataFlow
  , DRagLint.Analysis.Flow.Lattices
  ;

type
  TExprHookReg = record
    NodeType: string;
    Hook    : TDataFlowExprHook;
  end;

  TStmtHookReg = record
    NodeType: string;
    Hook    : TDataFlowStmtHook;
  end;

var
  GFallbacks : Integer = 0;
  GCapped    : Integer = 0;
  { FIXR-B (REV-1 #2): the last TDataFlowSite.WalkId handed out; one per TCollector }
  GWalkSeq   : UInt64 = 0;
  { 1.56 seam: filled from unit initializations, read by every TCollector }
  GExprHooks : TArray<TExprHookReg>;
  GWriteHooks: TArray<TDataFlowWriteHook>;
  GStmtHooks : TArray<TStmtHookReg>;

const
  { Engine knowledge (plan section 2). Growing any list is safe -- it only adds
    rows or flow -- but it IS extraction: an extractor bump. }
  { receive: `X.<m>(e)` means "local/param X receives e" }
  TAINT_RECEIVER_MUTATORS: array[0..5] of string = ('add', 'append', 'insert', 'addstrings', 'assign', 'addpair');
  { a call of one of these names with ONE argument is a typecast: its value is its argument's }
  TAINT_TYPECASTS: array[0..12] of string = ('string', 'unicodestring', 'ansistring', 'widestring', 'rawbytestring',
    'utf8string', 'shortstring', 'pchar', 'pwidechar', 'pansichar', 'variant', 'olevariant', 'pointer');
  { calls whose RESULT is numeric / boolean: no flow out (arg rows are still recorded) }
  TAINT_NOFLOW_RESULT: array[0..20] of string = ('length', 'high', 'low', 'sizeof', 'ord', 'assigned', 'inc', 'dec',
    'setlength', 'freeandnil', 'pos', 'sametext', 'samestr', 'comparetext', 'comparestr', 'inttostr', 'strtoint',
    'strtointdef', 'round', 'trunc', 'odd');
  { member reads of a local/param that are numeric: `L.Count` is not "read L" }
  TAINT_NUMERIC_MEMBERS: array[0..4] of string = ('count', 'length', 'capacity', 'itemindex', 'recordcount');
  { declared types whose values carry no taint }
  TAINT_SCALAR_TYPES: array[0..27] of string = ('integer', 'int64', 'cardinal', 'byte', 'word', 'longint',
    'longword', 'shortint', 'smallint', 'uint64', 'uint32', 'int32', 'uint16', 'int16', 'uint8', 'int8',
    'nativeint', 'nativeuint', 'boolean', 'bytebool', 'wordbool', 'longbool', 'double', 'single', 'extended',
    'real', 'currency', 'tdatetime');
  TAINT_STRING_TYPES: array[0..6] of string = ('string', 'unicodestring', 'ansistring', 'widestring',
    'rawbytestring', 'utf8string', 'shortstring');
  { expression nodes that carry no source: literals, nil, booleans, and shapes with no ref to point at }
  TAINT_INERT_NODES: array[0..9] of string = ('literalString', 'literalNumber', 'literalChar', 'kNil', 'kTrue', 'kFalse',
    'inherited', 'exprTpl', 'typeref', 'comment');
  { argout (lane ARGOUT): RTL routines with NO var/out parameter -- an argument
    passed to one is never written by it. Consulted only for a callee this unit
    does not declare. Name-keyed: a project routine of the same name in ANOTHER
    unit with a var/out parameter would lose its argout source (accepted). }
  TAINT_ARGOUT_NONE: array[0..58] of string = ('copy', 'trim', 'trimleft', 'trimright', 'lowercase',
    'uppercase', 'ansilowercase', 'ansiuppercase', 'extractfileext', 'extractfilename', 'extractfilepath',
    'extractfiledir', 'changefileext', 'expandfilename', 'includetrailingpathdelimiter',
    'excludetrailingpathdelimiter', 'startsstr', 'startstext', 'endsstr', 'endstext', 'containsstr',
    'containstext', 'matchstr', 'matchtext', 'indexstr', 'indextext', 'posex', 'lastdelimiter', 'ifthen',
    'charinset', 'fileexists', 'directoryexists', 'forcedirectories', 'quotedstr', 'stringreplace', 'format',
    'containskey', 'containsvalue', 'combine', 'getfullpath', 'ispathrooted', 'getdirectoryname',
    'getextension', 'getfilename', 'getfilenamewithoutextension', 'readalltext', 'readallbytes',
    'readalllines', 'writealltext', 'writeallbytes', 'exists', 'ismatch', 'addorsetvalue', 'addpair',
    'createdirectory', 'getlastwritetime', 'leftstr', 'rightstr', 'midstr');
  { RTL routines whose ONLY var/out parameter is at TAINT_ARGOUT_OUT1_POS (TryGetValue(Key, out Value)) }
  TAINT_ARGOUT_OUT1: array[0..0] of string = ('trygetvalue');
  TAINT_ARGOUT_OUT1_POS = 1;
  { the flow-insensitive walk iterates to a fixpoint, at most this many passes }
  DF_FLAT_PASSES = 8;
  { BaseIdent descends at most this many receiver levels (a malformed-tree guard, not a semantic limit) }
  DF_RECEIVER_DEPTH = 32;
  { ---- 1.56 B3: value classes. Each list refines TAINT_SCALAR_TYPES / TAINT_NOFLOW_RESULT; a name
    in neither sub-list is DF_VAL_INT. Growing a list is extraction (an extractor change). }
  DF_BOOL_TYPES: array[0..3] of string = ('boolean', 'bytebool', 'wordbool', 'longbool');
  DF_FLOAT_TYPES: array[0..3] of string = ('double', 'single', 'extended', 'real');
  DF_CURRENCY_TYPE = 'currency';
  DF_DATETIME_TYPE = 'tdatetime';
  { TAINT_NOFLOW_RESULT members with a Boolean result }
  DF_NOFLOW_BOOL: array[0..3] of string = ('assigned', 'sametext', 'samestr', 'odd');
  { TAINT_NOFLOW_RESULT members with NO result (procedures) }
  DF_NOFLOW_PROC: array[0..3] of string = ('inc', 'dec', 'setlength', 'freeandnil');
  { Inc(X, D) / Dec(X, D): X receives D }
  DF_STEP_PROCS: array[0..1] of string = ('inc', 'dec');
  DF_STEP_ARGS = 2;
  { the one TAINT_NOFLOW_RESULT member whose RESULT is a string (its argument is the integer) }
  DF_INTTOSTR = 'inttostr';
  { field accessors whose member name states the value class }
  DF_ACC_INT: array[0..6] of string = ('asinteger', 'aslargeint', 'asint64', 'aslongword', 'assmallint', 'asword', 'asbyte');
  DF_ACC_FLOAT: array[0..2] of string = ('asfloat', 'asextended', 'assingle');
  DF_ACC_CURRENCY: array[0..1] of string = ('ascurrency', 'asbcd');
  DF_ACC_DATETIME: array[0..2] of string = ('asdatetime', 'asdate', 'astime');
  DF_ACC_BOOL: array[0..0] of string = ('asboolean');
  { binary operators (lower-case source text) }
  DF_COMPARE_OPS: array[0..6] of string = ('=', '<>', '<', '>', '<=', '>=', 'in');
  DF_LOGIC_OPS: array[0..2] of string = ('and', 'or', 'xor');
  DF_INT_OPS: array[0..3] of string = ('div', 'mod', 'shl', 'shr');
  DF_OP_IS = 'is';
  DF_OP_FDIV = '/';
  { the pre-1.56 kinds: a row of these with an empty value class counts against the pre-1.56 cap }
  DF_OLD_DST_KINDS: array[0..5] of string = (DF_DST_ARG, DF_DST_WRITE, DF_DST_RESULT, DF_DST_FIELD, DF_DST_GLOBAL, DF_DST_OUTPARAM);
  DF_OLD_SRC_KINDS: array[0..4] of string = (DF_SRC_PARAM, DF_SRC_REF, DF_SRC_FIELD, DF_SRC_GLOBAL, DF_SRC_ARGOUT);
  { test seam: with this environment variable set the unit registers its three self-test hooks
    (tests\autotest\run_v156_EXTB1_valclass.ps1, V5); never set in production }
  DF_TEST_HOOK_ENV = 'DRAGLINT_TEST_V156_DFHOOK';
  DF_TEST_ACCESSOR = 'AsFloat';

function InList(const AName: string; const AList: array of string): Boolean;
var
  S: string;
begin
  for S in AList do
    if S = AName then Exit(True);
  Result:= False;
end;

{ ---- sorted unique integer sets ---------------------------------------- }

type
  TIntSet = TArray<Integer>;

function SetHas(const A: TIntSet; V: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Lo:= 0;
  Hi:= High(A);
  while Lo <= Hi do
  begin
    Mid:= (Lo + Hi) shr 1;
    if A[Mid] = V then Exit(True);
    if A[Mid] < V then Lo:= Mid + 1 else Hi:= Mid - 1;
  end;
  Result:= False;
end;

function SetUnion(const A, B: TIntSet): TIntSet;
var
  I, J, K: Integer;
begin
  if Length(A) = 0 then Exit(B);
  if Length(B) = 0 then Exit(A);
  SetLength(Result, Length(A) + Length(B));
  I:= 0;
  J:= 0;
  K:= 0;
  while (I < Length(A)) or (J < Length(B)) do
  begin
    if (J >= Length(B)) or ((I < Length(A)) and (A[I] < B[J])) then
    begin
      Result[K]:= A[I];
      Inc(I);
    end
    else if (I >= Length(A)) or (B[J] < A[I]) then
    begin
      Result[K]:= B[J];
      Inc(J);
    end
    else
    begin
      Result[K]:= A[I];
      Inc(I);
      Inc(J);
    end;
    Inc(K);
  end;
  SetLength(Result, K);
end;

function SetInter(const A, B: TIntSet): TIntSet;
var
  I, J, K: Integer;
begin
  SetLength(Result, Length(A));
  I:= 0;
  J:= 0;
  K:= 0;
  while (I < Length(A)) and (J < Length(B)) do
  begin
    if A[I] < B[J] then Inc(I)
    else if B[J] < A[I] then Inc(J)
    else
    begin
      Result[K]:= A[I];
      Inc(K);
      Inc(I);
      Inc(J);
    end;
  end;
  SetLength(Result, K);
end;

function SetEq(const A, B: TIntSet): Boolean;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for I:= 0 to High(A) do
    if A[I] <> B[I] then Exit(False);
  Result:= True;
end;

function SetNorm(const A: TIntSet): TIntSet;
var
  I, K: Integer;
begin
  Result:= Copy(A);
  if Length(Result) < 2 then Exit;
  TArray.Sort<Integer>(Result);
  K:= 1;
  for I:= 1 to High(Result) do
    if Result[I] <> Result[K - 1] then
    begin
      Result[K]:= Result[I];
      Inc(K);
    end;
  SetLength(Result, K);
end;

{ ---- lattice value ------------------------------------------------------ }

type
  /// <summary>Per routine variable slot: MAY = encoded source elements (token * 2 +
  /// via-local bit), MUST = token ids reaching on every path. Reached = False is the
  /// lattice bottom (an unreached block; MUST's top).</summary>
  TTaintVal = record
    Reached: Boolean;
    May    : TArray<TIntSet>;
    Must   : TArray<TIntSet>;
  end;

  { May = encoded elements, Must = token ids, Cls = inferred scalar class (1.56: the public record) }
  TExprVal = TDataFlowValue;

  TSrcTok = record
    Kind : string;
    Index: Integer;
    Line : Integer;
    Col  : Integer;
    Name : string;
    Cls  : string;   { 1.56 B3: DF_VAL_* of the value this source carries; '' = a pre-1.56 flow }
  end;

  PTaintVal = ^TTaintVal;

  TCollector = class;

  TTaintReach = class(TInterfacedObject, IDataFlowAnalysis<TTaintVal>)
  strict private
    FC: TCollector;
  public
    constructor Create(AC: TCollector);
    function Direction: TFlowDir;
    function Bottom: TTaintVal;
    function Boundary: TTaintVal;
    function Join(const A, B: TTaintVal): TTaintVal;
    function Transfer(const ABlock: TCfgBlock; const AIn: TTaintVal): TTaintVal;
    function Equals(const A, B: TTaintVal): Boolean; reintroduce;
  end;

  TCollector = class(TDataFlowSite)  // dl:ok god-class@3c0e, high-response@3c0e -- one private per-routine walker: the lattice ops, the expression evaluator and the row sink share one state by design (taint T1)
  strict private
    FSlotCls    : TArray<string>;   { 1.56 B3: DF_VAL_* of a scalar-typed slot, '' otherwise }
    FValRows    : Integer;          { rows outside the pre-1.56 set (value rows, hook rows) }
    FValCapped  : Boolean;
    FCur        : PTaintVal;        { the state at the running hook's site; nil outside a hook }
    FSym        : TSymbol;
    FProc       : TTSNode;
    FBody       : TTSNode;
    FSrc        : TBytes;
    FVars       : TRoutineVarTable;
    FWalkId     : UInt64;
    { FIXR-B #6: the scope ASym is declared in (its class for a method), and the declared class of
      each class-less source token that has one (token index -> DF_VAL_*) }
    FScope      : string;
    FTokDecl    : TDictionary<Integer, string>;
    FNSlots     : Integer;
    FSlotKind   : TArray<TVarKind>;
    FSlotScalar : TArray<Boolean>;
    FSlotString : TArray<Boolean>;
    FSlotPIdx   : TArray<Integer>;
    FSlotPTok   : TArray<Integer>;
    FSlotName   : TArray<string>;
    FSiteLine   : TArray<Integer>;
    FSiteCol    : TArray<Integer>;
    FResultSlot : Integer;
    FFields     : TDictionary<string, string>;
    FGlobals    : TDictionary<string, string>;
    FCallees    : TDataFlowCallees;
    FIterables  : TDictionary<string, TArray<TTSNode>>;
    FToks       : TList<TSrcTok>;
    FTokIdx     : TDictionary<string, Integer>;
    FRows       : TList<TDataFlowRow>;
    FRowIdx     : TDictionary<string, Integer>;
    FRecording  : Boolean;
    FInsensitive: Boolean;
    FCapped     : Boolean;
    function Text(const N: TTSNode): string;
    function Tok(const AKind: string; AIndex, ALine, ACol: Integer; const AName: string; const ACls: string = ''): Integer;
    function TokVal(ATok: Integer): TExprVal;
    function SlotOf(const N: TTSNode): Integer;
    function BaseIdent(const N: TTSNode): TTSNode;
    function CopyVal(const A: TTaintVal): TTaintVal;
    procedure AddRow(const AKind: string; ALine, ACol, AIndex: Integer; const AName, ARecv: string;
                     ATok: Integer; AVia, ACond: Boolean);
    procedure RecordDst(const AKind: string; const APos: TTSNode; AIndex: Integer; const AName, ARecv: string;
                        const AV: TExprVal);
    procedure AssignSlot(var St: TTaintVal; ASlot: Integer; const AV: TExprVal; AKill: Boolean; const ASite: TTSNode);
    procedure ReceiveInto(var St: TTaintVal; const ABase: TTSNode; const AV: TExprVal);
    function ReadSlot(const St: TTaintVal; ASlot: Integer): TExprVal;
    function Eval(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalIdent(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalDot(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalCall(var St: TTaintVal; const N: TTSNode): TExprVal;
    function ArgMayBeWritten(const ACallee: string; AIndex: Integer): Boolean;
    procedure ApplyAssignment(var St: TTaintVal; const N: TTSNode);
    procedure ApplyMemberWrite(var St: TTaintVal; const ALhs: TTSNode; const AV: TExprVal);
    procedure ApplyStmtExpr(var St: TTaintVal; const E: TTSNode);
    procedure ApplyItem(var St: TTaintVal; const N: TTSNode);
    procedure WalkLambda(const St: TTaintVal; const N: TTSNode);
    procedure FlatWalk(var St: TTaintVal; const N: TTSNode);
    procedure EmitExitRows(const St: TTaintVal);
    procedure RunInsensitive;
    procedure RunCfg(const ACfg: TCfg);
    procedure ScanBody(const N: TTSNode);
    function Reclass(const AV: TExprVal; const ACls: string): TExprVal;
    function EvalNode(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalBinary(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalUnary(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalNoFlowCall(var St: TTaintVal; const ACallee: string; const AArgs: TTSNode;
                            const AArgVals: TArray<TExprVal>; ABare: Boolean): TExprVal;
    procedure RunExprHooks(var St: TTaintVal; const N: TTSNode; var AV: TExprVal);
    procedure RunWriteHooks(var St: TTaintVal; const ALhs: TTSNode; const AV: TExprVal);
    procedure RunStmtHooks(var St: TTaintVal; const N: TTSNode);
    function ScopedCls(AGroup: Char; const AScope, ALowerName: string): string;
    function FieldCls(const ALowerName: string): string;
    function GlobalCls(const ALowerName: string): string;
    function BareResultCls(const ALowerName: string): string;
    function RecvScope(const ARecv: TTSNode): string;
    function RecvResultCls(const ARecv: TTSNode; const ALowerName: string): string;
    function TypedTokVal(const AKind: string; ALine, ACol: Integer; const AName, ACls: string): TExprVal;
    procedure RecordTypedDst(const AKind: string; AGroup: Char; const APos: TTSNode; const AV: TExprVal);
    procedure RecordArgs(const ANameN: TTSNode; const ARecvText, ACallee: string; ABare: Boolean;
                         const AArgVals: TArray<TExprVal>);
  public
    constructor Create(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                       const AOwnerFields, AGlobals: TArray<string>; const ACallees: TDataFlowCallees);
    destructor Destroy; override;
    function Bottom: TTaintVal;
    function Boundary: TTaintVal;
    function Join(const A, B: TTaintVal): TTaintVal;
    function Transfer(const ABlock: TCfgBlock; const AIn: TTaintVal): TTaintVal;
    function Same(const A, B: TTaintVal): Boolean;
    procedure Run;
    function Rows: TArray<TDataFlowRow>;
    { TDataFlowSite }
    function NodeText(const ANode: TTSNode): string; override;
    function IsRecording: Boolean; override;
    function WalkId: UInt64; override;
    function ValueOf(const AExpr: TTSNode): TDataFlowValue; override;
    function NewSource(const AKind: string; AIndex: Integer; const APos: TTSNode; const AName, AValClass: string): TDataFlowValue; override;
    function Merge(const A, B: TDataFlowValue): TDataFlowValue; override;
    procedure EmitRow(const ADstKind: string; const APos: TTSNode; AIndex: Integer; const AName, AReceiver: string;
                      const AValue: TDataFlowValue); override;
  end;

function ExprUnion(const A, B: TExprVal): TExprVal;
begin
  Result.May := SetUnion(A.May, B.May);
  Result.Must:= SetUnion(A.Must, B.Must);
  Result.Cls := '';
end;

function ExprEmpty: TExprVal;
begin
  Result.May := nil;
  Result.Must:= nil;
  Result.Cls := '';
end;

{ ---- 1.56 B3: value classes ---------------------------------------------- }

{ The DF_VAL_* class of a declared type (lower case); '' when it is no TAINT_SCALAR_TYPES member. }
function ScalarClass(const ALowerType: string): string;
begin
  if not InList(ALowerType, TAINT_SCALAR_TYPES) then Exit('');
  if InList(ALowerType, DF_BOOL_TYPES) then Exit(DF_VAL_BOOL);
  if InList(ALowerType, DF_FLOAT_TYPES) then Exit(DF_VAL_FLOAT);
  if ALowerType = DF_CURRENCY_TYPE then Exit(DF_VAL_CURRENCY);
  if ALowerType = DF_DATETIME_TYPE then Exit(DF_VAL_DATETIME);
  Result:= DF_VAL_INT;
end;

{ The class of a TAINT_NOFLOW_RESULT call's result; '' for the procedures among them. }
function NoFlowClass(const ACallee: string): string;
begin
  if InList(ACallee, DF_NOFLOW_PROC) then Exit('');
  Result:= if InList(ACallee, DF_NOFLOW_BOOL) then DF_VAL_BOOL else DF_VAL_INT;
end;

{ The class a field accessor's name states (`AsFloat`); '' for any other member. }
function AccessorClass(const AMember: string): string;
begin
  Result:= '';
  if AMember = '' then Exit;
  if InList(AMember, DF_ACC_INT) then Exit(DF_VAL_INT);
  if InList(AMember, DF_ACC_FLOAT) then Exit(DF_VAL_FLOAT);
  if InList(AMember, DF_ACC_CURRENCY) then Exit(DF_VAL_CURRENCY);
  if InList(AMember, DF_ACC_DATETIME) then Exit(DF_VAL_DATETIME);
  if InList(AMember, DF_ACC_BOOL) then Result:= DF_VAL_BOOL;
end;

{ A numeric literal: hexadecimal and plain digits are integers, a fraction or an exponent is a float. }
function NumberClass(const AText: string): string;
begin
  if AText.StartsWith('$') then Exit(DF_VAL_INT);
  Result:= if AText.Contains('.') or AText.ToLower.Contains('e') then DF_VAL_FLOAT else DF_VAL_INT;
end;

{ The class of `A <op> B` for an arithmetic / logical operator (lower-case text) from its operands'
  classes ('' = unknown). Never '': with nothing known the result is DF_VAL_FLOAT ("a number") for
  an arithmetic operator and DF_VAL_BOOL for and / or / xor. }
function ArithClass(const AOp, A, B: string): string;
var
  AnyInt: Boolean;
begin
  AnyInt:= (A = DF_VAL_INT) or (B = DF_VAL_INT);
  if InList(AOp, DF_INT_OPS) then Result:= DF_VAL_INT
  else if InList(AOp, DF_LOGIC_OPS) then Result:= if AnyInt then DF_VAL_INT else DF_VAL_BOOL
  else if (A = DF_VAL_CURRENCY) or (B = DF_VAL_CURRENCY) then Result:= DF_VAL_CURRENCY
  else if (A = DF_VAL_DATETIME) or (B = DF_VAL_DATETIME) then Result:= DF_VAL_DATETIME
  else if (AOp = DF_OP_FDIV) or (A = DF_VAL_FLOAT) or (B = DF_VAL_FLOAT) then Result:= DF_VAL_FLOAT
  else Result:= if AnyInt then DF_VAL_INT else DF_VAL_FLOAT;
end;

function IsOldRowKind(const ADstKind, ASrcKind: string): Boolean;
begin
  Result:= InList(ADstKind, DF_OLD_DST_KINDS) and InList(ASrcKind, DF_OLD_SRC_KINDS);
end;

{ ---- 1.56 lane EXT-B1F: declared scalar classes ---------------------------- }

{ The declared result type (lower case) of signature text ASig ('(const A: string): Integer',
  ': Currency'); '' for a procedure. The parameter list is skipped by bracket depth. }
function ResultTypeOf(const ASig: string): string;
var
  I, Depth: Integer;
  Rest    : string;
begin
  Result:= '';
  Rest:= Trim(ASig);
  if Rest.StartsWith('(') then
  begin
    Depth:= 0;
    for I:= 1 to Length(Rest) do
      if CharInSet(Rest[I], ['(', '[']) then Inc(Depth)
      else if CharInSet(Rest[I], [')', ']']) then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Rest:= Trim(Copy(Rest, I + 1, MaxInt));
          Break;
        end;
      end;
    if Depth <> 0 then Exit;
  end;
  if not Rest.StartsWith(':') then Exit;
  Rest:= Copy(Rest, 2, MaxInt);
  if Rest.Contains(';') then Rest:= Copy(Rest, 1, Pos(';', Rest) - 1);
  Result:= LowerCase(Trim(Rest));
end;

destructor TDataFlowCallees.Destroy;
begin
  FDeclCls.Free;
  FDeclType.Free;
  FTypeScope.Free;
  inherited;
end;

class function TDataFlowCallees.ScopeOf(const AQualifiedName: string): string;
var
  Cut: Integer;
begin
  Cut:= LastDelimiter('.', AQualifiedName);
  Result:= if Cut > 1 then LowerCase(Copy(AQualifiedName, 1, Cut - 1)) else '';
end;

class function TDataFlowCallees.BareTypeName(const ATypeText: string): string;
begin
  Result:= LowerCase(Trim(ATypeText));
  if Result.Contains('<') then Result:= Trim(Copy(Result, 1, Pos('<', Result) - 1));
  Result:= Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

{ One declaration of ALowerName in group AGroup of scope AScope has class ACls ('' = not a scalar)
  and type ALowerType. A second declaration IN THE SAME SCOPE with another class (an overload)
  leaves '' for good: the name claims nothing. }
procedure TDataFlowCallees.NoteDeclared(AGroup: Char; const AScope, ALowerName, ACls, ALowerType: string);
var
  Key, Old: string;
begin
  if ALowerName = '' then Exit;
  if FDeclCls = nil then
  begin
    FDeclCls := TDictionary<string, string>.Create;
    FDeclType:= TDictionary<string, string>.Create;
  end;
  Key:= AGroup + AScope + DF_SCOPE_SEP + ALowerName;
  if FDeclCls.TryGetValue(Key, Old) and (Old <> ACls) then FDeclCls[Key]:= ''
  else FDeclCls.AddOrSetValue(Key, ACls);
  FDeclType.AddOrSetValue(Key, ALowerType);
end;

{ A class / record / interface of this unit; a second type of the same bare name claims nothing. }
procedure TDataFlowCallees.NoteType(const ALowerTypeName, AScope: string);
var
  Old: string;
begin
  if ALowerTypeName = '' then Exit;
  if FTypeScope = nil then FTypeScope:= TDictionary<string, string>.Create;
  if FTypeScope.TryGetValue(ALowerTypeName, Old) and (Old <> AScope) then FTypeScope[ALowerTypeName]:= ''
  else FTypeScope.AddOrSetValue(ALowerTypeName, AScope);
end;

function TDataFlowCallees.DeclaredClass(AGroup: Char; const AScope, ALowerName: string): string;
begin
  if (FDeclCls = nil) or not FDeclCls.TryGetValue(AGroup + AScope + DF_SCOPE_SEP + ALowerName, Result) then Result:= '';
end;

function TDataFlowCallees.Declares(AGroup: Char; const AScope, ALowerName: string): Boolean;
begin
  Result:= (FDeclCls <> nil) and FDeclCls.ContainsKey(AGroup + AScope + DF_SCOPE_SEP + ALowerName);
end;

function TDataFlowCallees.DeclaredType(AGroup: Char; const AScope, ALowerName: string): string;
begin
  if (FDeclType = nil) or not FDeclType.TryGetValue(AGroup + AScope + DF_SCOPE_SEP + ALowerName, Result) then Result:= '';
end;

function TDataFlowCallees.ScopeOfType(const ALowerTypeName: string): string;
begin
  if (FTypeScope = nil) or (ALowerTypeName = '') or not FTypeScope.TryGetValue(ALowerTypeName, Result) then Result:= '';
end;

function IsDottedIdentChain(const N: TTSNode): Boolean;
var
  R: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then Exit(True);
  if N.NodeType <> 'exprDot' then Exit;
  R:= N.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'identifier') then Exit;
  Result:= IsDottedIdentChain(N.ChildByField('lhs'));
end;

function IsIndexedReceiver(const N: TTSNode): Boolean;  // dl:ok too-many-exit-points@0ebd -- shape-dispatch guard clauses mirroring the parser's IsIndexedMemberReceiver
var
  Op, Operand, R: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'exprSubscript' then Exit(True);
  if N.NodeType = 'exprUnary' then
  begin
    Op     := N.ChildByField('operator');
    Operand:= N.ChildByField('operand');
    if Op.IsNull or Operand.IsNull or (Op.StartByte < Operand.EndByte) then Exit; { prefix operator }
    Exit(IsDottedIdentChain(Operand) or IsIndexedReceiver(Operand));
  end;
  if N.NodeType <> 'exprDot' then Exit;
  R:= N.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'identifier') then Exit;
  Result:= IsIndexedReceiver(N.ChildByField('lhs'));
end;

function IsParenRooted(const N: TTSNode): Boolean;
var
  R: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'exprParens' then Exit(True);
  if N.NodeType <> 'exprDot' then Exit;
  R:= N.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'identifier') then Exit;
  Result:= IsParenRooted(N.ChildByField('lhs'));
end;

{ Mirror of the parser's IsHardCastRootedReceiver (ref-gap G5): a bare identifier
  called with exactly ONE argument -- T(X) -- or a dotted identifier chain rooted
  in one, T(X).A.B. A cast and a one-argument function call look alike; the
  parser records the ref either way and the resolver decides. }
function IsHardCastRooted(const N: TTSNode): Boolean;
var
  E, A, R: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'exprCall' then
  begin
    E:= N.ChildByField('entity');
    A:= N.ChildByField('args');
    Exit((not E.IsNull) and (E.NodeType = 'identifier') and (not A.IsNull) and (A.NamedChildCount = 1));
  end;
  if N.NodeType <> 'exprDot' then Exit;
  R:= N.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'identifier') then Exit;
  Result:= IsHardCastRooted(N.ChildByField('lhs'));
end;

{ The receiver shapes L for which the parser emits a 'member-access' ref at the
  member identifier of `L.M` (DRagLint.Parser.Delphi13, ref-gaps G, G2, G3, G4, G5):
  a plain identifier other than Self, a dotted identifier chain, an indexed, a
  parenthesised or a hard-cast root. Mirrored here so every 'write' row and every src 'ref' row
  lands on a refs row (run_dataflow_facts.ps1 joins them). }
function RefShapeOk(const L: TTSNode; AIsSelf: Boolean): Boolean;
begin
  Result:= False;
  if L.IsNull then Exit;
  if L.NodeType = 'identifier' then Exit(not AIsSelf);
  Result:= ((L.NodeType = 'exprDot') and IsDottedIdentChain(L)) or IsIndexedReceiver(L) or IsParenRooted(L) or IsHardCastRooted(L);
end;
{ ---- TTaintReach -------------------------------------------------------- }

constructor TTaintReach.Create(AC: TCollector);
begin
  inherited Create;
  FC:= AC;
end;

function TTaintReach.Direction: TFlowDir;
begin
  Result:= fdForward;
end;

function TTaintReach.Bottom: TTaintVal;
begin
  Result:= FC.Bottom;
end;

function TTaintReach.Boundary: TTaintVal;
begin
  Result:= FC.Boundary;
end;

function TTaintReach.Join(const A, B: TTaintVal): TTaintVal;
begin
  Result:= FC.Join(A, B);
end;

function TTaintReach.Transfer(const ABlock: TCfgBlock; const AIn: TTaintVal): TTaintVal;
begin
  Result:= FC.Transfer(ABlock, AIn);
end;

function TTaintReach.Equals(const A, B: TTaintVal): Boolean;
begin
  Result:= FC.Same(A, B);
end;

{ ---- TCollector --------------------------------------------------------- }

constructor TCollector.Create(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                              const AOwnerFields, AGlobals: TArray<string>; const ACallees: TDataFlowCallees);
var
  S          : string;
  I, PCounter: Integer;
  RV         : TRoutineVar;
  LType      : string;
begin
  inherited Create;
  Inc(GWalkSeq);
  FWalkId   := GWalkSeq;
  FCallees  := ACallees;
  FScope    := TDataFlowCallees.ScopeOf(ASym.QualifiedName);
  FTokDecl  := TDictionary<Integer, string>.Create;
  FSym      := ASym;
  FProc     := AProc;
  FBody     := ABody;
  FSrc      := ASrc;
  FFields   := TDictionary<string, string>.Create;
  FGlobals  := TDictionary<string, string>.Create;
  FIterables:= TDictionary<string, TArray<TTSNode>>.Create;
  FToks     := TList<TSrcTok>.Create;
  FTokIdx   := TDictionary<string, Integer>.Create;
  FRows     := TList<TDataFlowRow>.Create;
  FRowIdx   := TDictionary<string, Integer>.Create;
  for S in AOwnerFields do FFields.AddOrSetValue(LowerCase(S), S);
  for S in AGlobals do FGlobals.AddOrSetValue(LowerCase(S), S);
  FVars:= TRoutineVarTable.Build(AProc, ASrc);
  ScanBody(ABody);
  FNSlots:= FVars.Count;
  SetLength(FSlotKind, FNSlots);
  SetLength(FSlotScalar, FNSlots);
  SetLength(FSlotCls, FNSlots);
  SetLength(FSlotString, FNSlots);
  SetLength(FSlotPIdx, FNSlots);
  SetLength(FSlotPTok, FNSlots);
  SetLength(FSlotName, FNSlots);
  SetLength(FSiteLine, FNSlots);
  SetLength(FSiteCol, FNSlots);
  PCounter:= 0;
  for I:= 0 to FNSlots - 1 do
  begin
    RV:= FVars.Get(I);
    LType:= LowerCase(Trim(RV.TypeText));
    FSlotKind[I]  := RV.Kind;
    FSlotCls[I]   := ScalarClass(LType);
    FSlotScalar[I]:= FSlotCls[I] <> '';
    FSlotString[I]:= InList(LType, TAINT_STRING_TYPES);
    FSlotName[I]  := RV.Display;
    FSlotPIdx[I]  := -1;
    FSlotPTok[I]  := -1;
    if RV.Kind in [vkParamVar, vkParamOut, vkParamConst, vkParamValue] then
    begin
      FSlotPIdx[I]:= PCounter;
      Inc(PCounter);
      { 1.56 B3: a scalar parameter is a source too; its token carries the class }
      FSlotPTok[I]:= Tok(DF_SRC_PARAM, FSlotPIdx[I], 0, 0, RV.Display, FSlotCls[I]);
    end;
  end;
  FResultSlot:= FVars.IndexOf('result');
end;

destructor TCollector.Destroy;
begin
  FRowIdx.Free;
  FTokDecl.Free;
  FRows.Free;
  FTokIdx.Free;
  FToks.Free;
  FIterables.Free;
  FGlobals.Free;
  FFields.Free;
  FVars.Free;
  inherited;
end;

{ Registers what TRoutineVarTable.Build leaves out on purpose (a single bare inline
  `var X: T;` -- see its RegisterRedeclaredDefs) and collects every foreach
  iterator -> iterable expression. Lambdas and nested routines are their own scope. }
procedure TCollector.ScanBody(const N: TTSNode);
var
  I      : Integer;
  IdN, It: TTSNode;
  RV     : TRoutineVar;
  Key    : string;
  Arr    : TArray<TTSNode>;
begin
  if N.IsNull then Exit;
  if (N.NodeType = 'defProc') or (N.NodeType = 'lambda') then Exit;
  if N.NodeType = 'varDef' then
  begin
    IdN:= Default(TTSNode);
    for I:= 0 to N.NamedChildCount - 1 do
      if N.NamedChild(I).NodeType = 'identifier' then
      begin
        IdN:= N.NamedChild(I);
        Break;
      end;
    if (not IdN.IsNull) and (FVars.IndexOf(LowerCase(Text(IdN))) < 0) then
    begin
      RV:= Default(TRoutineVar);
      RV.Name    := LowerCase(Text(IdN));
      RV.Display := Text(IdN);
      RV.Kind    := vkLocal;
      RV.TypeText:= Trim(Text(N.ChildByField('type')));
      RV.DeclLine:= Integer(IdN.StartPoint.Row) + 1;
      RV.DeclCol := Utf8ByteColToCharCol(FSrc, IdN.StartByte, IdN.StartPoint.Column) + 1;
      FVars.Add(RV);
    end;
  end;
  if N.NodeType = 'foreach' then
  begin
    It:= N.ChildByField('iterator');
    if (not It.IsNull) and (It.NodeType = 'varAssignDef') then
      for I:= 0 to It.NamedChildCount - 1 do
        if It.NamedChild(I).NodeType = 'identifier' then
        begin
          It:= It.NamedChild(I);
          Break;
        end;
    if (not It.IsNull) and (It.NodeType = 'identifier') and (not N.ChildByField('iterable').IsNull) then
    begin
      Key:= LowerCase(Text(It));
      if not FIterables.TryGetValue(Key, Arr) then Arr:= nil;
      FIterables.AddOrSetValue(Key, Arr + [N.ChildByField('iterable')]);
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanBody(N.NamedChild(I));
end;

function TCollector.Text(const N: TTSNode): string;
var
  S, E: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  E:= Integer(N.EndByte);
  if (S < 0) or (E <= S) or (E > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, E - S);
end;

function TCollector.Tok(const AKind: string; AIndex, ALine, ACol: Integer; const AName: string; const ACls: string): Integer;
var
  Key: string;
  T  : TSrcTok;
begin
  Key:= AKind + '|' + IntToStr(AIndex) + '|' + IntToStr(ALine) + '|' + IntToStr(ACol) + '|' + LowerCase(AName)
        + '|' + ACls;
  if FTokIdx.TryGetValue(Key, Result) then Exit;
  T.Kind := AKind;
  T.Index:= AIndex;
  T.Line := ALine;
  T.Col  := ACol;
  T.Name := AName;
  T.Cls  := ACls;
  Result:= FToks.Add(T);
  FTokIdx.Add(Key, Result);
end;

function TCollector.TokVal(ATok: Integer): TExprVal;
begin
  Result.May := [ATok * 2];
  Result.Must:= [ATok];
  Result.Cls := '';
end;

{ 1.56 B3: AV as a value of scalar class ACls. Every source that still has no class (a pre-1.56
  flow that the old walk dropped at this point) becomes the same source WITH the class; a source
  that already has one keeps it (the class is the FIRST scalar the value became). The result
  never holds a class-less source, so no pre-1.56 row can come out of it.
  Lane EXT-B1F: a source whose DECLARED type is a scalar (FTokDecl) takes that class, not ACls --
  a Currency field compared with 0 is a currency source of a Boolean, as a Currency parameter is. }
function TCollector.Reclass(const AV: TExprVal; const ACls: string): TExprVal;
var
  I, T: Integer;
  K   : TSrcTok;

  function ClsFor(ATokIdx: Integer): string;
  begin
    if not FTokDecl.TryGetValue(ATokIdx, Result) then Result:= ACls;
  end;

begin
  Result.Cls:= ACls;
  if ACls = '' then
  begin
    Result.May := AV.May;
    Result.Must:= AV.Must;
    Exit;
  end;
  SetLength(Result.May, Length(AV.May));
  for I:= 0 to High(AV.May) do
  begin
    T:= AV.May[I] shr 1;
    K:= FToks[T];
    if K.Cls = '' then T:= Tok(K.Kind, K.Index, K.Line, K.Col, K.Name, ClsFor(T));
    Result.May[I]:= T * 2 + (AV.May[I] and 1);
  end;
  SetLength(Result.Must, Length(AV.Must));
  for I:= 0 to High(AV.Must) do
  begin
    T:= AV.Must[I];
    K:= FToks[T];
    if K.Cls = '' then T:= Tok(K.Kind, K.Index, K.Line, K.Col, K.Name, ClsFor(T));
    Result.Must[I]:= T;
  end;
  Result.May := SetNorm(Result.May);
  Result.Must:= SetNorm(Result.Must);
end;

{ ---- 1.56 lane EXT-B1F: declared scalar types ------------------------------
  A field, a unit variable or the result of a function THIS unit declares with a scalar type is
  typed at the source. Its pre-1.56 source (no class) is kept wherever the old walk made it, so the
  rows with ValClass '' stay the pre-1.56 set; a twin source carrying the declared class travels
  with it and gives the value rows. Types come from TDataFlowCallees.DeclaredClass, keyed by the
  declaring scope (FIXR-B, REV-1 #6): an inherited field of another unit, a property, a routine of
  another unit and a member of a receiver whose type this unit does not declare stay untyped. }

function TCollector.ScopedCls(AGroup: Char; const AScope, ALowerName: string): string;
begin
  Result:= if Assigned(FCallees) then FCallees.DeclaredClass(AGroup, AScope, ALowerName) else '';
end;

{ A field of the routine's own class (FFields holds exactly those). }
function TCollector.FieldCls(const ALowerName: string): string;
begin
  Result:= ScopedCls(DF_DECL_FIELD, FScope, ALowerName);
end;

function TCollector.GlobalCls(const ALowerName: string): string;
begin
  Result:= if Assigned(FCallees) then FCallees.DeclaredClass(DF_DECL_GLOBAL, FCallees.UnitScope, ALowerName) else '';
end;

{ A bare name read as a call (`Total`, `Twice(X)`): a method of the routine's own class, else a
  plain function of the unit. A method the class declares hides the unit's function even when its
  result is no scalar. }
function TCollector.BareResultCls(const ALowerName: string): string;
begin
  Result:= '';
  if not Assigned(FCallees) then Exit;
  if (FScope <> FCallees.UnitScope) and FCallees.Declares(DF_DECL_RESULT, FScope, ALowerName) then
    Exit(FCallees.DeclaredClass(DF_DECL_RESULT, FScope, ALowerName));
  Result:= FCallees.DeclaredClass(DF_DECL_RESULT, FCallees.UnitScope, ALowerName);
end;

{ The scope the members of receiver ARecv are declared in: Self, or a plain identifier whose
  declared type (a local / parameter, a field of the class, a unit variable) is a type of this
  unit. '' = not known: a longer chain, a call, a type of another unit. }
function TCollector.RecvScope(const ARecv: TTSNode): string;
var
  Nm  : string;
  Slot: Integer;
begin
  Result:= '';
  if (not Assigned(FCallees)) or ARecv.IsNull or (ARecv.NodeType <> 'identifier') then Exit;
  Nm:= LowerCase(Text(ARecv));
  if Nm = 'self' then Exit(FScope);
  Slot:= SlotOf(ARecv);
  if Slot >= 0 then Exit(FCallees.ScopeOfType(TDataFlowCallees.BareTypeName(FVars.Get(Slot).TypeText)));
  if FFields.ContainsKey(Nm) then Exit(FCallees.ScopeOfType(FCallees.DeclaredType(DF_DECL_FIELD, FScope, Nm)));
  if FGlobals.ContainsKey(Nm) then Result:= FCallees.ScopeOfType(FCallees.DeclaredType(DF_DECL_GLOBAL, FCallees.UnitScope, Nm));
end;

{ `ARecv.Name` read as a call: the result class of the method the receiver's type declares. An
  unknown receiver claims nothing (REV-1 #6: the bare name alone matched any function of the unit). }
function TCollector.RecvResultCls(const ARecv: TTSNode; const ALowerName: string): string;
var
  Scope: string;
begin
  Scope:= RecvScope(ARecv);
  Result:= if Scope <> '' then ScopedCls(DF_DECL_RESULT, Scope, ALowerName) else '';
end;

{ The value of one source read: the pre-1.56 token and, when the declaration the caller resolved
  has scalar class ACls, its classed twin. The class is remembered for the class-less token
  (FTokDecl), so a later Reclass of the value keeps the DECLARED class. }
function TCollector.TypedTokVal(const AKind: string; ALine, ACol: Integer; const AName, ACls: string): TExprVal;
var
  T: Integer;
begin
  T:= Tok(AKind, -1, ALine, ACol, AName);
  Result:= TokVal(T);
  if ACls = '' then Exit;
  FTokDecl.AddOrSetValue(T, ACls);
  Result:= ExprUnion(Result, TokVal(Tok(AKind, -1, ALine, ACol, AName, ACls)));
  Result.Cls:= ACls;
end;

{ A write to the field / unit variable at APos. A destination of declared scalar class types what
  reaches it: every class-less source gains a value row of that class beside its pre-1.56 row. }
procedure TCollector.RecordTypedDst(const AKind: string; AGroup: Char; const APos: TTSNode; const AV: TExprVal);
var
  Cls: string;
  V  : TExprVal;
begin
  V:= AV;
  Cls:= if AGroup = DF_DECL_FIELD then FieldCls(LowerCase(Text(APos))) else GlobalCls(LowerCase(Text(APos)));
  if Cls <> '' then V:= ExprUnion(AV, Reclass(AV, Cls));
  RecordDst(AKind, APos, -1, Text(APos), '', V);
end;

{ The 'arg' rows of one call. Lane EXT-B1F: a bare IntToStr's argument IS an integer, whatever the
  walk knows of its type -- each class-less source gains a value row beside its pre-1.56 row. }
procedure TCollector.RecordArgs(const ANameN: TTSNode; const ARecvText, ACallee: string; ABare: Boolean;
                                const AArgVals: TArray<TExprVal>);
var
  I: Integer;
begin
  for I:= 0 to High(AArgVals) do RecordDst(DF_DST_ARG, ANameN, I, Text(ANameN), ARecvText, AArgVals[I]);
  if ABare and (ACallee = DF_INTTOSTR) then
    for I:= 0 to High(AArgVals) do RecordDst(DF_DST_ARG, ANameN, I, Text(ANameN), ARecvText, Reclass(AArgVals[I], DF_VAL_INT));
end;

function TCollector.SlotOf(const N: TTSNode): Integer;
begin
  Result:= -1;
  if N.IsNull or (N.NodeType <> 'identifier') then Exit;
  Result:= FVars.IndexOfAt(LowerCase(Text(N)), Integer(N.StartByte));
end;

{ The leftmost identifier of a receiver expression (`X`, `X.f`, `X[i]`, `X.f[i].g`),
  skipping a leading `Self.`; a null node when the root is not an identifier. }
function TCollector.BaseIdent(const N: TTSNode): TTSNode;
var
  Cur, L: TTSNode;
  Guard : Integer;
begin
  Result:= Default(TTSNode);
  Cur   := N;
  for Guard:= 1 to DF_RECEIVER_DEPTH do
  begin
    if Cur.IsNull then Exit;
    if Cur.NodeType = 'identifier' then Exit(Cur);
    if Cur.NodeType = 'exprDot' then
    begin
      L:= Cur.ChildByField('lhs');
      if (not L.IsNull) and (L.NodeType = 'identifier') and SameText(Text(L), 'Self') then Exit(Cur.ChildByField('rhs'));
      Cur:= L;
    end
    else if Cur.NodeType = 'exprSubscript' then Cur:= Cur.ChildByField('entity')
    else Exit;
  end;
end;

function TCollector.CopyVal(const A: TTaintVal): TTaintVal;
begin
  Result.Reached:= A.Reached;
  Result.May    := Copy(A.May);
  Result.Must   := Copy(A.Must);
end;

function TCollector.Bottom: TTaintVal;
begin
  Result.Reached:= False;
  Result.May    := nil;
  Result.Must   := nil;
end;

function TCollector.Boundary: TTaintVal;
var
  I: Integer;
begin
  Result.Reached:= True;
  SetLength(Result.May, FNSlots);
  SetLength(Result.Must, FNSlots);
  for I:= 0 to FNSlots - 1 do
    if (FSlotPTok[I] >= 0) and (FSlotKind[I] <> vkParamOut) then
    begin
      Result.May[I] := [FSlotPTok[I] * 2];
      Result.Must[I]:= [FSlotPTok[I]];
    end;
end;

function TCollector.Join(const A, B: TTaintVal): TTaintVal;
var
  I: Integer;
begin
  if not A.Reached then Exit(B);
  if not B.Reached then Exit(A);
  Result.Reached:= True;
  SetLength(Result.May, FNSlots);
  SetLength(Result.Must, FNSlots);
  for I:= 0 to FNSlots - 1 do
  begin
    Result.May[I] := SetUnion(A.May[I], B.May[I]);
    Result.Must[I]:= SetInter(A.Must[I], B.Must[I]);
  end;
end;

function TCollector.Same(const A, B: TTaintVal): Boolean;
var
  I: Integer;
begin
  if A.Reached <> B.Reached then Exit(False);
  if not A.Reached then Exit(True);
  for I:= 0 to FNSlots - 1 do
    if not (SetEq(A.May[I], B.May[I]) and SetEq(A.Must[I], B.Must[I])) then Exit(False);
  Result:= True;
end;

procedure TCollector.AddRow(const AKind: string; ALine, ACol, AIndex: Integer; const AName, ARecv: string;  // dl:ok too-many-parameters@254c -- one argument per data_flows column; a record would only restate TDataFlowRow
                            ATok: Integer; AVia, ACond: Boolean);
var
  Key  : string;
  Idx  : Integer;
  R    : TDataFlowRow;
  T    : TSrcTok;
  Added: Boolean;
begin
  Key:= AKind + '|' + IntToStr(ALine) + '|' + IntToStr(ACol) + '|' + IntToStr(AIndex) + '|' + LowerCase(AName)
        + '|' + IntToStr(ATok);
  if FRowIdx.TryGetValue(Key, Idx) then
  begin
    R:= FRows[Idx];
    R.ViaLocal:= R.ViaLocal and AVia;
    R.Cond    := R.Cond and ACond;
    FRows[Idx]:= R;
    Exit;
  end;
  T:= FToks[ATok];
  { 1.56 B3: two budgets, so a value / hook row can never push a pre-1.56 row out }
  Added:= (T.Cls <> '') or not IsOldRowKind(AKind, T.Kind);
  if Added then
  begin
    if FValRows >= DF_ROW_CAP then
    begin
      if not FValCapped then
      begin
        FValCapped:= True;
        Writeln(ErrOutput, Format('data_flows: value-row cap %d reached in %s (line %d); later value rows dropped',
          [DF_ROW_CAP, FSym.Name, FSym.ImplStartLine]));
      end;
      Exit;
    end;
    Inc(FValRows);
  end
  else if FRows.Count - FValRows >= DF_ROW_CAP then
  begin
    if not FCapped then
    begin
      FCapped:= True;
      Inc(GCapped);
      Writeln(ErrOutput, Format('data_flows: row cap %d reached in %s (line %d); later rows dropped',
        [DF_ROW_CAP, FSym.Name, FSym.ImplStartLine]));
    end;
    Exit;
  end;
  R:= Default(TDataFlowRow);
  R.SymbolId   := FSym.Id;
  R.OwnerId    := if FSym.ParentId > 0 then FSym.ParentId else 0;
  R.DstKind    := AKind;
  R.DstLine    := ALine;
  R.DstCol     := ACol;
  R.DstIndex   := AIndex;
  R.DstName    := AName;
  R.DstReceiver:= ARecv;
  R.SrcKind    := T.Kind;
  R.SrcIndex   := T.Index;
  R.SrcLine    := T.Line;
  R.SrcCol     := T.Col;
  R.SrcName    := T.Name;
  R.ViaLocal   := AVia;
  R.Cond       := ACond;
  R.ValClass   := T.Cls;
  FRowIdx.Add(Key, FRows.Add(R));
end;

procedure TCollector.RecordDst(const AKind: string; const APos: TTSNode; AIndex: Integer; const AName, ARecv: string;
                               const AV: TExprVal);
var
  E, T: Integer;
begin
  if (not FRecording) or APos.IsNull then Exit;
  for E in AV.May do
  begin
    T:= E shr 1;
    AddRow(AKind, Integer(APos.StartPoint.Row) + 1, Utf8ByteColToCharCol(FSrc, APos.StartByte, APos.StartPoint.Column) + 1, AIndex, AName, ARecv,
      T, (E and 1) = 1, FInsensitive or not SetHas(AV.Must, T));
  end;
end;

procedure TCollector.AssignSlot(var St: TTaintVal; ASlot: Integer; const AV: TExprVal; AKill: Boolean;
                                const ASite: TTSNode);
var
  L, C: Integer;
  V   : TExprVal;
begin
  if (ASlot < 0) or (ASlot >= FNSlots) then Exit;
  { 1.56 B3: a scalar slot holds value sources only (pre-1.56 it held nothing) }
  V:= if FSlotScalar[ASlot] then Reclass(AV, FSlotCls[ASlot]) else AV;
  if AKill and not FInsensitive then
  begin
    St.May[ASlot] := V.May;
    St.Must[ASlot]:= V.Must;
  end
  else
  begin
    St.May[ASlot] := SetUnion(St.May[ASlot], V.May);
    St.Must[ASlot]:= SetUnion(St.Must[ASlot], V.Must);
  end;
  if FRecording and (not ASite.IsNull) then
  begin
    L:= Integer(ASite.StartPoint.Row) + 1;
    C:= Utf8ByteColToCharCol(FSrc, ASite.StartByte, ASite.StartPoint.Column) + 1;
    if (FSiteLine[ASlot] = 0) or (L < FSiteLine[ASlot]) or ((L = FSiteLine[ASlot]) and (C < FSiteCol[ASlot])) then
    begin
      FSiteLine[ASlot]:= L;
      FSiteCol[ASlot] := C;
    end;
  end;
end;

{ `X.Add(e)`, `X.f := e`, `X[i] := e`: the base X receives e. A local/param slot
  gains e's sources; a field or global base is a 'field' / 'global' destination. }
procedure TCollector.ReceiveInto(var St: TTaintVal; const ABase: TTSNode; const AV: TExprVal);
var
  Slot: Integer;
  Nm  : string;
begin
  if ABase.IsNull or (ABase.NodeType <> 'identifier') then Exit;
  Slot:= SlotOf(ABase);
  if Slot >= 0 then
  begin
    AssignSlot(St, Slot, AV, False, ABase);
    Exit;
  end;
  Nm:= LowerCase(Text(ABase));
  if FFields.ContainsKey(Nm) then RecordDst(DF_DST_FIELD, ABase, -1, Text(ABase), '', AV)
  else if FGlobals.ContainsKey(Nm) then RecordDst(DF_DST_GLOBAL, ABase, -1, Text(ABase), '', AV);
end;

function TCollector.ReadSlot(const St: TTaintVal; ASlot: Integer): TExprVal;
var
  I, E: Integer;
begin
  Result:= ExprEmpty;
  if (ASlot < 0) or (ASlot >= FNSlots) then Exit;
  Result.Cls:= FSlotCls[ASlot];
  SetLength(Result.May, Length(St.May[ASlot]));
  for I:= 0 to High(St.May[ASlot]) do
  begin
    E:= St.May[ASlot][I];
    { a parameter read as itself is direct; everything else came through state }
    if (E shr 1) <> FSlotPTok[ASlot] then E:= E or 1;
    Result.May[I]:= E;
  end;
  Result.May := SetNorm(Result.May);
  Result.Must:= St.Must[ASlot];
end;

function TCollector.EvalIdent(var St: TTaintVal; const N: TTSNode): TExprVal;
var
  Slot: Integer;
  Nm  : string;
begin
  Result:= ExprEmpty;
  Nm:= LowerCase(Text(N));
  if (Nm = '') or (Nm = 'self') then Exit;
  Slot:= SlotOf(N);
  if Slot >= 0 then Exit(ReadSlot(St, Slot));
  if FFields.ContainsKey(Nm) then Exit(TypedTokVal(DF_SRC_FIELD, 0, 0, Text(N), FieldCls(Nm)));
  if FGlobals.ContainsKey(Nm) then Exit(TypedTokVal(DF_SRC_GLOBAL, 0, 0, Text(N), GlobalCls(Nm)));
  Result:= TypedTokVal(DF_SRC_REF, Integer(N.StartPoint.Row) + 1, Utf8ByteColToCharCol(FSrc, N.StartByte, N.StartPoint.Column) + 1, Text(N), BareResultCls(Nm));
end;

function TCollector.EvalDot(var St: TTaintVal; const N: TTSNode): TExprVal;
var
  L, R, Base: TTSNode;
  LV        : TExprVal;
  Member, BN: string;
  MCls      : string;
begin
  L:= N.ChildByField('lhs');
  R:= N.ChildByField('rhs');
  if (not L.IsNull) and (L.NodeType = 'identifier') and SameText(Text(L), 'Self') then
  begin
    if R.IsNull or (R.NodeType <> 'identifier') then Exit(Eval(St, R));
    if FFields.ContainsKey(LowerCase(Text(R))) then Exit(TypedTokVal(DF_SRC_FIELD, 0, 0, Text(R), FieldCls(LowerCase(Text(R)))));
    Exit(TypedTokVal(DF_SRC_REF, Integer(R.StartPoint.Row) + 1, Utf8ByteColToCharCol(FSrc, R.StartByte, R.StartPoint.Column) + 1, Text(R), ScopedCls(DF_DECL_RESULT, FScope, LowerCase(Text(R)))));
  end;
  LV:= Eval(St, L);
  Member:= '';
  if (not R.IsNull) and (R.NodeType = 'identifier') then Member:= LowerCase(Text(R));
  Base:= BaseIdent(L);
  { lane EXT-B1F: the member is a function with a scalar result (a call without parentheses);
    FIXR-B #6: of the type the RECEIVER is declared with, not any function of that name }
  MCls:= if Member <> '' then RecvResultCls(L, Member) else '';
  { a member of a local / param reads that variable }
  if SlotOf(Base) >= 0 then
  begin
    Result:= LV;
    { lane EXT-B1F: ... and the method's result is a value source of its own. Only the classed
      source: the pre-1.56 walk made no ref here, so no class-less row may appear }
    if MCls <> '' then
      Result:= ExprUnion(Result, TokVal(Tok(DF_SRC_REF, -1, Integer(R.StartPoint.Row) + 1, Utf8ByteColToCharCol(FSrc, R.StartByte, R.StartPoint.Column) + 1, Text(R), MCls)));
  end
  else if (Member <> '') and RefShapeOk(L, SameText(Text(L), 'Self')) then
  begin
    Result:= TypedTokVal(DF_SRC_REF, Integer(R.StartPoint.Row) + 1, Utf8ByteColToCharCol(FSrc, R.StartByte, R.StartPoint.Column) + 1, Text(R), MCls);
    BN:= LowerCase(Text(Base));
    if ((BN <> '') and (FFields.ContainsKey(BN) or FGlobals.ContainsKey(BN))) or IsHardCastRooted(L) then Result:= ExprUnion(Result, LV); { a cast keeps its operand's taint }
  end
  else Result:= LV;
  { 1.56 B3: a numeric member (`L.Count`) was no flow at all; now it is an integer derived from its
    receiver. An accessor (`F.AsFloat`) keeps its pre-1.56 sources and only states its class. }
  if InList(Member, TAINT_NUMERIC_MEMBERS) then Result:= Reclass(Result, DF_VAL_INT)
  else Result.Cls:= if AccessorClass(Member) <> '' then AccessorClass(Member) else MCls;
end;

function TCollector.EvalCall(var St: TTaintVal; const N: TTSNode): TExprVal;
var
  Ent, Args, NameN, Arg, Recv: TTSNode;
  Callee, RecvText           : string;
  I, Slot, CallLine, CallCol : Integer;
  ArgVals                    : TArray<TExprVal>;
  RecvVal, All               : TExprVal;
  T                          : Integer;
begin
  Result:= ExprEmpty;
  Ent := N.ChildByField('entity');
  Args:= N.ChildByField('args');
  NameN:= Default(TTSNode);
  Recv := Default(TTSNode);
  RecvText:= '';
  if not Ent.IsNull then
  begin
    if Ent.NodeType = 'identifier' then NameN:= Ent
    else if Ent.NodeType = 'exprDot' then
    begin
      NameN:= Ent.ChildByField('rhs');
      Recv := Ent.ChildByField('lhs');
      RecvText:= Trim(Text(Recv));
    end;
  end;
  if not Args.IsNull then
  begin
    SetLength(ArgVals, Args.NamedChildCount);
    for I:= 0 to Args.NamedChildCount - 1 do ArgVals[I]:= Eval(St, Args.NamedChild(I));
  end;
  RecvVal:= ExprEmpty;
  if not Recv.IsNull then RecvVal:= Eval(St, Recv);
  if NameN.IsNull or (NameN.NodeType <> 'identifier') then
  begin
    if (not Ent.IsNull) and (Ent.NodeType <> 'exprDot') and (Ent.NodeType <> 'identifier') then Eval(St, Ent);
    Exit;
  end;
  Callee:= LowerCase(Text(NameN));
  if Recv.IsNull and (Length(ArgVals) = 1) and InList(Callee, TAINT_TYPECASTS) then Exit(ArgVals[0]);
  if Recv.IsNull and (Callee = 'exit') then Exit;
  CallLine:= Integer(NameN.StartPoint.Row) + 1;
  CallCol := Utf8ByteColToCharCol(FSrc, NameN.StartByte, NameN.StartPoint.Column) + 1;
  RecordArgs(NameN, RecvText, Callee, Recv.IsNull, ArgVals);
  { receive: X.Add(e) and friends }
  if (not Recv.IsNull) and InList(Callee, TAINT_RECEIVER_MUTATORS) then
  begin
    All:= ExprEmpty;
    for I:= 0 to High(ArgVals) do All:= ExprUnion(All, ArgVals[I]);
    ReceiveInto(St, BaseIdent(Recv), All);
  end;
  { argout: a plain variable argument may be written by the callee (a var/out slot) }
  if not InList(Callee, TAINT_NOFLOW_RESULT) then
    for I:= 0 to High(ArgVals) do
    begin
      Arg:= Args.NamedChild(I);
      Slot:= SlotOf(Arg);
      if (Slot < 0) or not ArgMayBeWritten(Callee, I) then Continue;
      { 1.56 B3: a scalar variable gets the argout source too, as a value source of its class }
      T:= Tok(DF_SRC_ARGOUT, I, CallLine, CallCol, Text(NameN), FSlotCls[Slot]);
      St.May[Slot] := SetUnion(St.May[Slot], [T * 2]);
      St.Must[Slot]:= SetUnion(St.Must[Slot], [T]);
    end;
  if InList(Callee, TAINT_NOFLOW_RESULT) then Exit(EvalNoFlowCall(St, Callee, Args, ArgVals, Recv.IsNull));
  Result:= TypedTokVal(DF_SRC_REF, CallLine, CallCol, Text(NameN),
             if Recv.IsNull then BareResultCls(LowerCase(Text(NameN))) else RecvResultCls(Recv, LowerCase(Text(NameN))));
  { a method of a string-typed local/param (`S.Trim`, `S.Substring(1)`) derives from it }
  Slot:= SlotOf(BaseIdent(Recv));
  if (Slot >= 0) and FSlotString[Slot] then Result:= ExprUnion(Result, RecvVal);
end;

{ 1.56 B3: the value of a TAINT_NOFLOW_RESULT call (pre-1.56: nothing flowed out of these). The
  result is a scalar derived from the arguments (`Length(S)`, `StrToInt(S)`, `Round(X)`);
  IntToStr's result is a string that keeps its integer sources; Inc(X, D) / Dec(X, D) with a
  scalar variable X feed D into X and have no result. }
function TCollector.EvalNoFlowCall(var St: TTaintVal; const ACallee: string; const AArgs: TTSNode;
                                   const AArgVals: TArray<TExprVal>; ABare: Boolean): TExprVal;
var
  I, Slot: Integer;
  All    : TExprVal;
begin
  Result:= ExprEmpty;
  if NoFlowClass(ACallee) <> '' then
  begin
    All:= ExprEmpty;
    for I:= 0 to High(AArgVals) do All:= ExprUnion(All, AArgVals[I]);
    Result:= Reclass(All, NoFlowClass(ACallee));
    if ACallee = DF_INTTOSTR then Result.Cls:= '';
  end
  else if InList(ACallee, DF_STEP_PROCS) and ABare and (Length(AArgVals) = DF_STEP_ARGS) then
  begin
    Slot:= SlotOf(AArgs.NamedChild(0));
    if (Slot >= 0) and FSlotScalar[Slot] then AssignSlot(St, Slot, AArgVals[1], False, AArgs.NamedChild(0));
  end;
end;

{ 1.56 B3: `A <op> B`. `+` unions as before (its class is known only when both sides' are); `as`
  is its left side; every other operator yields a scalar, which pre-1.56 was no flow: `X is T`
  derives from X only, a comparison is a Boolean derived from both sides, the rest is arithmetic
  or logic (ArithClass). }
function TCollector.EvalBinary(var St: TTaintVal; const N: TTSNode): TExprVal;
var
  Op, OpT: string;
  A, B   : TExprVal;
  OpN    : TTSNode;
begin
  OpN:= N.ChildByField('operator');
  Op := if OpN.IsNull then '' else OpN.NodeType;
  A:= Eval(St, N.ChildByField('lhs'));
  B:= Eval(St, N.ChildByField('rhs'));
  OpT:= LowerCase(Trim(Text(OpN)));
  if Op = 'kAdd' then
  begin
    Result:= ExprUnion(A, B);
    if (A.Cls <> '') and (B.Cls <> '') then Result.Cls:= ArithClass('', A.Cls, B.Cls);
  end
  else if Op = 'kAs' then Result:= A
  else if OpT = DF_OP_IS then Result:= Reclass(A, DF_VAL_BOOL)
  else if InList(OpT, DF_COMPARE_OPS) then Result:= Reclass(ExprUnion(A, B), DF_VAL_BOOL)
  else Result:= Reclass(ExprUnion(A, B), ArithClass(OpT, A.Cls, B.Cls));
end;

{ 1.56 B3: `@X` and `X^` are X (as before); `not X` is Boolean unless X is an integer; a sign
  keeps the operand's class (a number of unknown type: DF_VAL_FLOAT). }
function TCollector.EvalUnary(var St: TTaintVal; const N: TTSNode): TExprVal;
var
  Op : string;
  OpN: TTSNode;
begin
  OpN:= N.ChildByField('operator');
  Op := if OpN.IsNull then '' else OpN.NodeType;
  Result:= Eval(St, N.ChildByField('operand'));
  if (Op = 'kAt') or (Op = 'kHat') then Exit;
  Result:= Reclass(Result, if Op = 'kNot' then (if Result.Cls = DF_VAL_INT then DF_VAL_INT else DF_VAL_BOOL)
                           else (if Result.Cls <> '' then Result.Cls else DF_VAL_FLOAT));
end;

{ May the callee ACallee (lower case) write argument AIndex? A same-unit callee
  answers by its var/out mask (a position past every overload: unknown, kept);
  else the RTL lists; else unresolved here -- kept, the linter resolves it. }
function TCollector.ArgMayBeWritten(const ACallee: string; AIndex: Integer): Boolean;
var
  Mask: TArray<Boolean>;
begin
  if Assigned(FCallees) and FCallees.TryGetValue(ACallee, Mask) then Exit((AIndex > High(Mask)) or Mask[AIndex]);
  Result:= if InList(ACallee, TAINT_ARGOUT_OUT1) then AIndex = TAINT_ARGOUT_OUT1_POS else not InList(ACallee, TAINT_ARGOUT_NONE);
end;

{ Per declared parameter of signature text ASig ('(const A, B: string; var C): T'),
  True when it is a var / out parameter. Splits on ';' at paren/bracket depth 0;
  a leading [attribute] is skipped. No parameter list: empty. }
function VarOutMask(const ASig: string): TArray<Boolean>;
var
  P, I, Depth, Start: Integer;
  Groups            : TArray<string>;
  G, Names, Modif   : string;
  IsVar             : Boolean;
begin
  Result:= nil;
  P:= Pos('(', ASig);
  if P = 0 then Exit;
  Groups:= nil;
  Depth:= 0;
  Start:= P + 1;
  for I:= P + 1 to Length(ASig) do
  begin
    if CharInSet(ASig[I], ['(', '[']) then Inc(Depth)
    else if CharInSet(ASig[I], [')', ']']) then
    begin
      if Depth = 0 then
      begin
        Groups:= Groups + [Copy(ASig, Start, I - Start)];
        Break;
      end;
      Dec(Depth);
    end
    else if (ASig[I] = ';') and (Depth = 0) then
    begin
      Groups:= Groups + [Copy(ASig, Start, I - Start)];
      Start:= I + 1;
    end;
  end;
  for G in Groups do
  begin
    Names:= Trim(G);
    if Names.StartsWith('[') and Names.Contains(']') then Names:= Trim(Copy(Names, Pos(']', Names) + 1, MaxInt));
    if Names.Contains(':') then Names:= Trim(Copy(Names, 1, Pos(':', Names) - 1));
    if Names = '' then Continue;
    Modif:= LowerCase(Names.Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty)[0]);
    IsVar:= (Modif = 'var') or (Modif = 'out');
    for I:= 0 to High(Names.Split([','])) do Result:= Result + [IsVar];
  end;
end;

function TCollector.Eval(var St: TTaintVal; const N: TTSNode): TExprVal;
begin
  Result:= EvalNode(St, N);
  if (GExprHooks <> nil) and not N.IsNull then RunExprHooks(St, N, Result);
end;

function TCollector.EvalNode(var St: TTaintVal; const N: TTSNode): TExprVal;  // dl:ok too-many-exit-points@1d4a -- node-type dispatcher: one Exit per grammar node kind
var
  NT  : string;
  I   : Integer;
  A, B: TExprVal;
begin
  Result:= ExprEmpty;
  if N.IsNull then Exit;
  NT:= N.NodeType;
  { 1.56 B3: a literal still carries no source, but its class types the expression around it }
  if NT = 'literalNumber' then
  begin
    Result.Cls:= NumberClass(Text(N));
    Exit;
  end;
  if (NT = 'kTrue') or (NT = 'kFalse') then
  begin
    Result.Cls:= DF_VAL_BOOL;
    Exit;
  end;
  if InList(NT, TAINT_INERT_NODES) then Exit;
  if NT = 'identifier' then Exit(EvalIdent(St, N));
  if NT = 'exprDot' then Exit(EvalDot(St, N));
  if NT = 'exprCall' then Exit(EvalCall(St, N));
  if NT = 'assignment' then
  begin
    ApplyAssignment(St, N);
    Exit;
  end;
  if NT = 'lambda' then
  begin
    WalkLambda(St, N);
    Exit;
  end;
  if NT = 'exprSubscript' then
  begin
    Eval(St, N.ChildByField('args'));
    Exit(Eval(St, N.ChildByField('entity')));
  end;
  if NT = 'exprBinary' then Exit(EvalBinary(St, N));
  if NT = 'exprUnary' then Exit(EvalUnary(St, N));
  if NT = 'exprIf' then
  begin
    Eval(St, N.ChildByField('condition'));
    A:= Eval(St, N.ChildByField('then'));
    B:= Eval(St, N.ChildByField('else'));
    Result.May := SetUnion(A.May, B.May);
    Result.Must:= SetInter(A.Must, B.Must);
    if A.Cls = B.Cls then Result.Cls:= A.Cls;
    Exit;
  end;
  { exprParens, exprBrackets (`[A, B]`: an open array is one value), exprArgs, anything else }
  if N.NamedChildCount = 1 then Exit(Eval(St, N.NamedChild(0))); { `(X)` keeps X's class }
  for I:= 0 to N.NamedChildCount - 1 do Result:= ExprUnion(Result, Eval(St, N.NamedChild(I)));
end;

procedure TCollector.ApplyMemberWrite(var St: TTaintVal; const ALhs: TTSNode; const AV: TExprVal);
var
  Ent, Member, Recv, Base: TTSNode;
begin
  Ent:= ALhs;
  if ALhs.NodeType = 'exprSubscript' then
  begin
    Eval(St, ALhs.ChildByField('args'));
    Ent:= ALhs.ChildByField('entity');
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') then
    begin
      { X[i] := e }
      ReceiveInto(St, Ent, AV);
      Exit;
    end;
  end;
  if Ent.IsNull or (Ent.NodeType <> 'exprDot') then
  begin
    Eval(St, Ent);
    Exit;
  end;
  Recv  := Ent.ChildByField('lhs');
  Member:= Ent.ChildByField('rhs');
  Eval(St, Recv);
  if (not Recv.IsNull) and (Recv.NodeType = 'identifier') and SameText(Text(Recv), 'Self') then
  begin
    if (not Member.IsNull) and (Member.NodeType = 'identifier') then
      RecordTypedDst(DF_DST_FIELD, DF_DECL_FIELD, Member, AV);
    Exit;
  end;
  Base:= BaseIdent(Recv);
  ReceiveInto(St, Base, AV);
  if (not Member.IsNull) and (Member.NodeType = 'identifier') and RefShapeOk(Recv, SameText(Text(Recv), 'Self')) then
    RecordDst(DF_DST_WRITE, Member, -1, Text(Member), Trim(Text(Recv)), AV);
end;

procedure TCollector.ApplyAssignment(var St: TTaintVal; const N: TTSNode);
var
  Lhs, OpN, IdN: TTSNode;
  V            : TExprVal;
  Kill         : Boolean;
  Slot, I      : Integer;
  Nm           : string;
begin
  Lhs:= N.ChildByField('lhs');
  OpN:= N.ChildByField('operator');
  V  := Eval(St, N.ChildByField('rhs'));
  Kill:= OpN.IsNull or (OpN.NodeType = 'kAssign');
  if Lhs.IsNull then Exit;
  if GWriteHooks <> nil then RunWriteHooks(St, Lhs, V);
  if Lhs.NodeType = 'varAssignDef' then
  begin
    IdN:= Lhs.ChildByField('name');
    if IdN.IsNull then
      for I:= 0 to Lhs.NamedChildCount - 1 do
        if Lhs.NamedChild(I).NodeType = 'identifier' then
        begin
          IdN:= Lhs.NamedChild(I);
          Break;
        end;
    AssignSlot(St, SlotOf(IdN), V, True, IdN);
    Exit;
  end;
  if Lhs.NodeType = 'identifier' then
  begin
    Slot:= SlotOf(Lhs);
    if Slot >= 0 then
    begin
      AssignSlot(St, Slot, V, Kill, Lhs);
      Exit;
    end;
    Nm:= LowerCase(Text(Lhs));
    if FFields.ContainsKey(Nm) then RecordTypedDst(DF_DST_FIELD, DF_DECL_FIELD, Lhs, V)
    else if FGlobals.ContainsKey(Nm) then RecordTypedDst(DF_DST_GLOBAL, DF_DECL_GLOBAL, Lhs, V)
    else RecordDst(DF_DST_WRITE, Lhs, -1, Text(Lhs), '', V);
    Exit;
  end;
  if (Lhs.NodeType = 'exprDot') or (Lhs.NodeType = 'exprSubscript') then
  begin
    ApplyMemberWrite(St, Lhs, V);
    Exit;
  end;
  Eval(St, Lhs);
end;

procedure TCollector.ApplyStmtExpr(var St: TTaintVal; const E: TTSNode);
var
  Ent, Args: TTSNode;
begin
  if E.IsNull then Exit;
  if E.NodeType = 'exprCall' then
  begin
    Ent := E.ChildByField('entity');
    Args:= E.ChildByField('args');
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and SameText(Text(Ent), 'exit') then
    begin
      if (not Args.IsNull) and (Args.NamedChildCount > 0) and (FResultSlot >= 0) then
        AssignSlot(St, FResultSlot, Eval(St, Args.NamedChild(0)), True, E);
      Exit;
    end;
  end;
  Eval(St, E);
end;

procedure TCollector.ApplyItem(var St: TTaintVal; const N: TTSNode);
var
  I : Integer;
  NT: string;
begin
  NT:= N.NodeType;
  if GStmtHooks <> nil then
  begin
    RunStmtHooks(St, N);
    if NT = 'statement' then
      for I:= 0 to N.NamedChildCount - 1 do RunStmtHooks(St, N.NamedChild(I));
  end;
  if NT = 'assignment' then ApplyAssignment(St, N)
  else if NT = 'statement' then
    for I:= 0 to N.NamedChildCount - 1 do ApplyStmtExpr(St, N.NamedChild(I))
  else if (NT = 'exprCall') or (NT = 'exprDot') or (NT = 'identifier') then ApplyStmtExpr(St, N)
  else if (NT <> 'varDef') and (NT <> 'asm') then Eval(St, N);
end;

{ A lambda body: walked structurally with a COPY of the state at the lambda (its
  captured locals), flow-insensitively, recording on the second pass only. Its
  writes never flow back into the enclosing routine's state. }
procedure TCollector.WalkLambda(const St: TTaintVal; const N: TTSNode);
var
  LS        : TTaintVal;
  SaveRec   : Boolean;
  SaveInsens: Boolean;
begin
  if (not FRecording) or (not St.Reached) then Exit;
  LS:= CopyVal(St);
  SaveRec:= FRecording;
  SaveInsens:= FInsensitive;
  FInsensitive:= True;
  try
    FRecording:= False;
    FlatWalk(LS, N.ChildByField('body'));
    FRecording:= SaveRec;
    FlatWalk(LS, N.ChildByField('body'));
  finally
    FRecording  := SaveRec;
    FInsensitive:= SaveInsens;
  end;
end;

{ Source-order walk of a statement subtree (the flow-insensitive mode). }
procedure TCollector.FlatWalk(var St: TTaintVal; const N: TTSNode);
var
  I     : Integer;
  NT    : string;
  It, Cn: TTSNode;
begin
  if N.IsNull then Exit;
  NT:= N.NodeType;
  if (NT = 'defProc') or (NT = 'with') or (NT = 'asm') or (NT = 'comment') then Exit;
  if (NT = 'assignment') or (NT = 'statement') or (NT = 'raise') then
  begin
    ApplyItem(St, N);
    Exit;
  end;
  if NT.StartsWith('expr') or (NT = 'identifier') or (NT = 'lambda') then
  begin
    ApplyStmtExpr(St, N);
    Exit;
  end;
  if NT = 'foreach' then
  begin
    It:= N.ChildByField('iterator');
    if (not It.IsNull) and (It.NodeType = 'varAssignDef') then
      for I:= 0 to It.NamedChildCount - 1 do
        if It.NamedChild(I).NodeType = 'identifier' then
        begin
          It:= It.NamedChild(I);
          Break;
        end;
    AssignSlot(St, SlotOf(It), Eval(St, N.ChildByField('iterable')), False, It);
    FlatWalk(St, N.ChildByField('body'));
    Exit;
  end;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    Cn:= N.NamedChild(I);
    FlatWalk(St, Cn);
  end;
end;

function TCollector.Transfer(const ABlock: TCfgBlock; const AIn: TTaintVal): TTaintVal;
var
  Item    : TCfgItem;
  Name    : string;
  Slot    : Integer;
  Iters   : TArray<TTSNode>;
  ItN     : TTSNode;
  V       : TExprVal;
  SaveRec : Boolean;
begin
  if not AIn.Reached then Exit(AIn);
  Result:= CopyVal(AIn);
  for Name in ABlock.EntryDefs do
  begin
    Slot:= FVars.IndexOf(Name);
    if (Slot < 0) or not FIterables.TryGetValue(Name, Iters) then Continue;
    V:= ExprEmpty;
    SaveRec:= FRecording;
    FRecording:= False;
    try
      for ItN in Iters do V:= ExprUnion(V, Eval(Result, ItN));
    finally
      FRecording:= SaveRec;
    end;
    AssignSlot(Result, Slot, V, True, Default(TTSNode));
  end;
  for Item in ABlock.Items do
  begin
    if Item.Opaque then Continue;
    ApplyItem(Result, Item.Node);
  end;
end;

procedure TCollector.EmitExitRows(const St: TTaintVal);
var
  S, E, T, L, C, Idx: Integer;
  Kind, Nm          : string;
begin
  if not St.Reached then Exit;
  for S:= 0 to FNSlots - 1 do
  begin
    { 1.56 B3: a scalar Result / var / out slot emits its value rows (it holds no other source) }
    if S = FResultSlot then
    begin
      Kind:= DF_DST_RESULT;
      Idx:= -1;
      Nm:= '';
    end
    else if FSlotKind[S] in [vkParamVar, vkParamOut] then
    begin
      Kind:= DF_DST_OUTPARAM;
      Idx:= FSlotPIdx[S];
      Nm:= FSlotName[S];
    end
    else Continue;
    L:= FSiteLine[S];
    C:= FSiteCol[S];
    if L = 0 then
    begin
      L:= Integer(FProc.StartPoint.Row) + 1;
      C:= Utf8ByteColToCharCol(FSrc, FProc.StartByte, FProc.StartPoint.Column) + 1;
    end;
    for E in St.May[S] do
    begin
      T:= E shr 1;
      if T = FSlotPTok[S] then Continue; { a var param still holding its own entry value }
      AddRow(Kind, L, C, Idx, Nm, '', T, (E and 1) = 1, FInsensitive or not SetHas(St.Must[S], T));
    end;
  end;
end;

procedure TCollector.RunInsensitive;
var
  St, Prev: TTaintVal;
  Pass    : Integer;
begin
  Inc(GFallbacks);
  FInsensitive:= True;
  FRecording  := False;
  St:= Boundary;
  for Pass:= 1 to DF_FLAT_PASSES do
  begin
    Prev:= CopyVal(St);
    FlatWalk(St, FBody);
    if Same(Prev, St) then Break;
  end;
  FRecording:= True;
  FlatWalk(St, FBody);
  EmitExitRows(St);
end;

procedure TCollector.RunCfg(const ACfg: TCfg);
var
  Ana     : IDataFlowAnalysis<TTaintVal>;
  Ins, Outs: TArray<TTaintVal>;
  B       : TCfgBlock;
begin
  Ana:= TTaintReach.Create(Self);
  if not TDataFlowSolver<TTaintVal>.Solve(ACfg, Ana, Ins, Outs) then
  begin
    RunInsensitive;
    Exit;
  end;
  FRecording:= True;
  for B in ACfg.Blocks do
    if Ins[B.Index].Reached then Transfer(B, Ins[B.Index]);
  EmitExitRows(Ins[ACfg.ExitIdx]);
end;

procedure TCollector.Run;
var
  Cfg: TCfg;
begin
  { CFG-CONSTLOOP: the same CFG shape the flow lint sees -- while True / until False get no test-exit
    edge, so only a Break reaches the code after the loop. }
  Cfg:= TCfgBuilder.Build(FProc, FSrc, True);
  try
    if Cfg.Skipped then RunInsensitive
    else if Cfg.BlockCount > DF_CFG_BLOCK_CAP then
    begin
      Writeln(ErrOutput, Format('data_flows: flow-insensitive fallback for %s (line %d, %d CFG blocks > %d)',
        [FSym.Name, FSym.ImplStartLine, Cfg.BlockCount, DF_CFG_BLOCK_CAP]));
      RunInsensitive;
    end
    else RunCfg(Cfg);
  finally
    Cfg.Free;
  end;
end;

function TCollector.Rows: TArray<TDataFlowRow>;
begin
  Result:= FRows.ToArray;
end;

{ ---- 1.56 seam: the registered hooks and what they may ask (TDataFlowSite) ---- }

procedure TCollector.RunExprHooks(var St: TTaintVal; const N: TTSNode; var AV: TExprVal);
var
  Save: PTaintVal;
  NT  : string;
  I   : Integer;
begin
  NT:= N.NodeType;
  Save:= FCur;
  FCur:= @St;
  try
    for I:= 0 to High(GExprHooks) do
      if GExprHooks[I].NodeType = NT then GExprHooks[I].Hook(Self, N, AV);
  finally
    FCur:= Save;
  end;
end;

procedure TCollector.RunWriteHooks(var St: TTaintVal; const ALhs: TTSNode; const AV: TExprVal);
var
  Save: PTaintVal;
  I   : Integer;
begin
  Save:= FCur;
  FCur:= @St;
  try
    for I:= 0 to High(GWriteHooks) do GWriteHooks[I](Self, ALhs, AV);
  finally
    FCur:= Save;
  end;
end;

procedure TCollector.RunStmtHooks(var St: TTaintVal; const N: TTSNode);
var
  Save: PTaintVal;
  NT  : string;
  I   : Integer;
begin
  if N.IsNull then Exit;
  NT:= N.NodeType;
  Save:= FCur;
  FCur:= @St;
  try
    for I:= 0 to High(GStmtHooks) do
      if GStmtHooks[I].NodeType = NT then GStmtHooks[I].Hook(Self, N);
  finally
    FCur:= Save;
  end;
end;

function TCollector.NodeText(const ANode: TTSNode): string;
begin
  Result:= Text(ANode);
end;

function TCollector.IsRecording: Boolean;
begin
  Result:= FRecording;
end;

function TCollector.WalkId: UInt64;
begin
  Result:= FWalkId;
end;

function TCollector.ValueOf(const AExpr: TTSNode): TDataFlowValue;
begin
  if (FCur = nil) or AExpr.IsNull then Exit(ExprEmpty);
  Result:= Eval(FCur^, AExpr);
end;

function TCollector.NewSource(const AKind: string; AIndex: Integer; const APos: TTSNode;
                              const AName, AValClass: string): TDataFlowValue;
var
  L, C: Integer;
begin
  L:= 0;
  C:= 0;
  if not APos.IsNull then
  begin
    L:= Integer(APos.StartPoint.Row) + 1;
    C:= Utf8ByteColToCharCol(FSrc, APos.StartByte, APos.StartPoint.Column) + 1;
  end;
  Result:= TokVal(Tok(AKind, AIndex, L, C, AName, AValClass));
  Result.Cls:= AValClass;
end;

function TCollector.Merge(const A, B: TDataFlowValue): TDataFlowValue;
begin
  Result:= ExprUnion(A, B);
  Result.Cls:= A.Cls;
end;

procedure TCollector.EmitRow(const ADstKind: string; const APos: TTSNode; AIndex: Integer;
                             const AName, AReceiver: string; const AValue: TDataFlowValue);
begin
  RecordDst(ADstKind, APos, AIndex, AName, AReceiver, AValue);
end;

{ ---- self-test hooks (DF_TEST_HOOK_ENV only): one of each kind, the shapes EXT-B2 / EXT-B3 need ---- }

function FirstCall(const N: TTSNode): TTSNode;
var
  I: Integer;
begin
  Result:= Default(TTSNode);
  if N.IsNull then Exit;
  if N.NodeType = 'exprCall' then Exit(N);
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    Result:= FirstCall(N.NamedChild(I));
    if not Result.IsNull then Exit;
  end;
end;

{ `<x>.AsFloat` read: adds a positioned dsfield source }
procedure SelfTestExprHook(ASite: TDataFlowSite; const ANode: TTSNode; var AValue: TDataFlowValue);
var
  R: TTSNode;
begin
  R:= ANode.ChildByField('rhs');
  if SameText(ASite.NodeText(R), DF_TEST_ACCESSOR) then
    AValue:= ASite.Merge(AValue, ASite.NewSource(DF_SRC_DSFIELD, -1, R, DF_TEST_ACCESSOR, DF_VAL_FLOAT));
end;

{ `<x>.AsFloat := e`: a dsfield destination row }
procedure SelfTestWriteHook(ASite: TDataFlowSite; const ALhs: TTSNode; const AValue: TDataFlowValue);
var
  R: TTSNode;
begin
  if ALhs.NodeType <> 'exprDot' then Exit;
  R:= ALhs.ChildByField('rhs');
  if SameText(ASite.NodeText(R), DF_TEST_ACCESSOR) then
    ASite.EmitRow(DF_DST_DSFIELD, R, -1, DF_TEST_ACCESSOR, Trim(ASite.NodeText(ALhs.ChildByField('lhs'))), AValue);
end;

{ `raise E.Create(a, b)`: one raise row per constructor argument }
procedure SelfTestStmtHook(ASite: TDataFlowSite; const ANode: TTSNode);
var
  Call, Ent, Args: TTSNode;
  I              : Integer;
begin
  Call:= FirstCall(ANode);
  if Call.IsNull then Exit;
  Ent := Call.ChildByField('entity');
  Args:= Call.ChildByField('args');
  if Ent.IsNull or (Ent.NodeType <> 'exprDot') or Args.IsNull then Exit;
  for I:= 0 to Args.NamedChildCount - 1 do
    ASite.EmitRow(DF_DST_RAISE, ANode, I, Trim(ASite.NodeText(Ent.ChildByField('lhs'))), '', ASite.ValueOf(Args.NamedChild(I)));
end;

{ ---- TDataFlowFacts ----------------------------------------------------- }

class function TDataFlowFacts.Collect(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                                      const AOwnerFields: TArray<string>;
                                      const AGlobals: TArray<string>;
                                      const ACallees: TDataFlowCallees): TArray<TDataFlowRow>;
var
  C: TCollector;
begin
  Result:= nil;
  if AProc.IsNull or ABody.IsNull or (ABody.NodeType = 'asm') then Exit;
  C:= TCollector.Create(ASym, AProc, ABody, ASrc, AOwnerFields, AGlobals, ACallees);
  try
    try
      C.Run;
      Result:= C.Rows;
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, Format('data_flows: %s (line %d) skipped: %s: %s', [ASym.Name, ASym.ImplStartLine, E.ClassName, E.Message]));
        Result:= nil;
      end;
    end;
  finally
    C.Free;
  end;
end;

class function TDataFlowFacts.CollectMainBlock(const AProgram: TSymbol; const ARoot: TTSNode; const ASrc: TBytes;
                                               const AGlobals: TArray<string>;
                                               const ACallees: TDataFlowCallees): TArray<TDataFlowRow>;
var
  Prog, Block: TTSNode;
  I          : Integer;
begin
  Result:= nil;
  if ARoot.IsNull then Exit;
  Prog:= Default(TTSNode);
  if (ARoot.NodeType = 'program') or (ARoot.NodeType = 'library') then Prog:= ARoot
  else
    for I:= 0 to ARoot.NamedChildCount - 1 do
      if (ARoot.NamedChild(I).NodeType = 'program') or (ARoot.NamedChild(I).NodeType = 'library') then
      begin
        Prog:= ARoot.NamedChild(I);
        Break;
      end;
  if Prog.IsNull then Exit;
  { the main block is the program node's own `block` child (a nested routine's block hangs
    under its defProc, never directly under the program) -- the last one, by position }
  Block:= Default(TTSNode);
  for I:= 0 to Prog.NamedChildCount - 1 do
    if Prog.NamedChild(I).NodeType = 'block' then Block:= Prog.NamedChild(I);
  if Block.IsNull then Exit;
  Result:= Collect(AProgram, Block, Block, ASrc, nil, AGlobals, ACallees);
end;

class function TDataFlowFacts.BuildCallees(const ASymbols: TArray<TSymbol>): TDataFlowCallees;
var
  S         : TSymbol;
  Key, Scope: string;
  Mask, Old : TArray<Boolean>;
  I         : Integer;
begin
  Result:= TDataFlowCallees.Create;
  for S in ASymbols do
  begin
    { FIXR-B #6: every declaration is filed under the scope that declares it }
    Scope:= TDataFlowCallees.ScopeOf(S.QualifiedName);
    if (S.Kind in [skUnit, skProgram, skPackage]) and (Result.FUnitScope = '') then Result.FUnitScope:= LowerCase(S.QualifiedName)
    else if S.Kind in [skClass, skRecord, skInterface] then Result.NoteType(TDataFlowCallees.BareTypeName(S.Name), LowerCase(S.QualifiedName));
    { lane EXT-B1F: a field's / unit variable's Signature is its declared type }
    if S.Kind = skField then
      Result.NoteDeclared(DF_DECL_FIELD, Scope, LowerCase(S.Name), ScalarClass(LowerCase(Trim(S.Signature))), TDataFlowCallees.BareTypeName(S.Signature))
    else if S.Kind = skVarDecl then
      Result.NoteDeclared(DF_DECL_GLOBAL, Scope, LowerCase(S.Name), ScalarClass(LowerCase(Trim(S.Signature))), TDataFlowCallees.BareTypeName(S.Signature));
    if S.Kind not in [skFunction, skProcedure, skMethod, skConstructor, skDestructor] then Continue;
    { 'TFoo.Bar' (an implementation header) and 'Bar<T>' key as 'bar', the call's identifier }
    Key:= LowerCase(S.Name);
    if Key.Contains('<') then Key:= Copy(Key, 1, Pos('<', Key) - 1);
    Key:= Copy(Key, LastDelimiter('.', Key) + 1, MaxInt);
    { lane EXT-B1F: a function's declared result class (a procedure / constructor has none) }
    if ResultTypeOf(S.Signature) <> '' then
      Result.NoteDeclared(DF_DECL_RESULT, Scope, Key, ScalarClass(ResultTypeOf(S.Signature)), TDataFlowCallees.BareTypeName(ResultTypeOf(S.Signature)));
    Mask:= VarOutMask(S.Signature);
    if Result.TryGetValue(Key, Old) then
    begin
      if Length(Old) > Length(Mask) then SetLength(Mask, Length(Old));
      for I:= 0 to High(Old) do Mask[I]:= Mask[I] or Old[I];
    end;
    Result.AddOrSetValue(Key, Mask);
  end;
end;

class function TDataFlowFacts.FallbackCount: Integer;
begin
  Result:= GFallbacks;
end;

class function TDataFlowFacts.CappedCount: Integer;
begin
  Result:= GCapped;
end;

class procedure TDataFlowFacts.RegisterExprHook(const ANodeType: string; AHook: TDataFlowExprHook);
var
  R: TExprHookReg;
begin
  if not Assigned(AHook) then Exit;
  R.NodeType:= ANodeType;
  R.Hook    := AHook;
  GExprHooks:= GExprHooks + [R];
end;

class procedure TDataFlowFacts.RegisterWriteHook(AHook: TDataFlowWriteHook);
begin
  if not Assigned(AHook) then Exit;
  SetLength(GWriteHooks, Length(GWriteHooks) + 1);
  GWriteHooks[High(GWriteHooks)]:= AHook;
end;

class procedure TDataFlowFacts.RegisterStmtHook(const ANodeType: string; AHook: TDataFlowStmtHook);
var
  R: TStmtHookReg;
begin
  if not Assigned(AHook) then Exit;
  R.NodeType:= ANodeType;
  R.Hook    := AHook;
  GStmtHooks:= GStmtHooks + [R];
end;

initialization
  if GetEnvironmentVariable(DF_TEST_HOOK_ENV) <> '' then
  begin
    TDataFlowFacts.RegisterExprHook('exprDot', SelfTestExprHook);
    TDataFlowFacts.RegisterWriteHook(SelfTestWriteHook);
    TDataFlowFacts.RegisterStmtHook('raise', SelfTestStmtHook);
  end;

end.
