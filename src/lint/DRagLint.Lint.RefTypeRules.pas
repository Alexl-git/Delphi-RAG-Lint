unit DRagLint.Lint.RefTypeRules;

{ The project lint rules that stand on index fact F1, table ref_types: the static
  type of a reference (1.44, lane rulesf1; spec lanes\143\fabcyc\REPORT.md section 5).

  One walk over each unit's tree. An expression's static type comes ONLY from
  ref_types and from a type name written in the source, never from a guess:

    * x, a.b.c, F(y) -- the ref_types row of the last name;
    * TFoo(x), x as TFoo -- the written type.

  Anything else (a subscript, a dereference, an arithmetic expression) has no
  static type here and the rules stay silent. A subscript is excluded on purpose:
  the row of `List` in `List[i]` is the type of the list, not of the element.

  A class's ancestry is the transitive closure of type_ancestors in the project,
  continued by name in the library index. Homonyms are intersected: an ancestor
  counts only when EVERY class of that name has it, so a homonym can only make a
  rule silent, never make it fire. No library index and an unresolved ancestor
  leave the closure incomplete, which is also silence.

  Inside a `with` body a bare name may bind to a member of the with-expression,
  and that binding is the part of the index a rule cannot check, so an operand
  there has no static type.

  An index older than 1.44 has no ref_types table: every rule answers nothing.

  ui-access-in-thread-typed (1.45) adds call edges to the same walk: thread code is walked
  like any other tree, and a resolved call into a routine parses that routine's unit and
  swaps the per-file state for the time of that one routine (RoutineFacts). The rule's
  contract is on the constant below; the guard is
  tests\lint-project\ui-thread-typed\run_ui_thread_typed.ps1. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , TreeSitter
  ;

const
  /// <summary>Rule id: `x is T` where the static type of x already descends from T.</summary>
  IS_ALWAYS_TRUE_RULE = 'is-always-true';
  /// <summary>Rule id: `x is T` that no object can answer yes to.</summary>
  /// <remarks>Fires on proof only, both ancestries followed to the end and no homonym: two classes
  /// where neither descends from the other (one parent chain cannot hold both); a sealed class
  /// against an interface it does not implement, either way round, because no descendant can add
  /// it. A class that is not sealed against an interface is silent: a descendant may implement it.
  /// An interface against an interface is silent: QueryInterface decides at run time. Silent
  /// without a library index when the ancestry leaves the project, and silent on a sealed library
  /// class in a library index older than the fact.</remarks>
  IS_NEVER_TRUE_RULE = 'is-never-true';
  /// <summary>Rule id, shared with the lexical check in AstChecks: this unit answers every
  /// hard cast whose operand has a ref_types row, and that check only the others.</summary>
  UNSAFE_TYPECAST_RULE = 'unsafe-typecast-without-is';
  /// <summary>Rule id, shared with the lexical check in AstChecks: this unit answers the
  /// shapes that check cannot type, a member chain or a call result, and `x as T`.</summary>
  REDUNDANT_CAST_RULE = 'redundant-cast';
  /// <summary>Rule id: an argument wider than the parameter it is passed to.</summary>
  ARGUMENT_NARROWS_RULE = 'argument-narrows';
  /// <summary>Rule id: an interface variable assigned an object that is not reference counted.</summary>
  INTERFACE_HOLDER_RULE = 'interface-holder-of-non-refcounted';
  /// <summary>Rule id: `with TFoo.Create do` that nobody frees.</summary>
  WITH_ON_TEMPORARY_RULE = 'with-on-temporary';
  /// <summary>Rule id: a cast to an ancestor and straight back down, TLeaf(TBase(x)).</summary>
  UPCAST_THEN_DOWNCAST_RULE = 'upcast-then-downcast';
  /// <summary>Every project rule this unit emits, as `--rule` and dl:ok markers spell them.</summary>
  /// <summary>Rule id: thread code touches a reference whose receiver's static type is a UI
  /// class, directly or over resolved calls.</summary>
  /// <remarks>
  /// A UI class descends from TControl, TCustomForm, TApplication, TScreen or TFmxObject in the
  /// indexed ancestry; `Application` and `Screen` count as globals when unbound in the project
  /// and the unit names a Forms unit. TStrings, TBitmap, TCanvas and a menu are not UI classes
  /// here: `Lst.Add` and `Bmp.Canvas` stay silent, `Memo1.Lines.Add` fires because of Memo1.
  /// Thread code is Execute of a TThread descendant and a lambda or routine passed to
  /// TThread.CreateAnonymousThread, TTask.Run, TTask.Create, TTask.Future or TParallel.For. Not
  /// thread code: the arguments of Synchronize, Queue and ForceQueue, a routine body that names
  /// a main-thread check, and a lambda nobody is proven to start on a thread. Silent: an untyped
  /// receiver, a member the project declares (a plain field of a form; its methods are followed
  /// as calls instead), the TObject and TComponent data members. A called routine that names
  /// Synchronize or Queue is taken to marshal itself, as ui-access-in-thread-transitive does.
  /// </remarks>
  UI_ACCESS_IN_THREAD_TYPED_RULE = 'ui-access-in-thread-typed';
  REF_TYPE_RULES: array[0..8] of string = (IS_ALWAYS_TRUE_RULE, IS_NEVER_TRUE_RULE, UPCAST_THEN_DOWNCAST_RULE, WITH_ON_TEMPORARY_RULE, INTERFACE_HOLDER_RULE, ARGUMENT_NARROWS_RULE, REDUNDANT_CAST_RULE, UNSAFE_TYPECAST_RULE, UI_ACCESS_IN_THREAD_TYPED_RULE);
  /// <summary>The ones that ship OFF; each names why in the catalog.</summary>
  REF_TYPE_RULES_OFF: array of string = [UNSAFE_TYPECAST_RULE, UI_ACCESS_IN_THREAD_TYPED_RULE, IS_NEVER_TRUE_RULE];

/// <summary>True when the rule ships OFF by default (see the catalog).</summary>
/// <param name="ARuleId">One of REF_TYPE_RULES.</param>
/// <returns>The value to hand TLintConfig.ShouldKeep as ADefaultDisabled.</returns>
function RefTypeRuleDefaultOff(const ARuleId: string): Boolean;

/// <summary>The static type ref_types records for the reference at a position.</summary>
/// <param name="AStore">The index; nil or a store that is not SQLite answers False.</param>
/// <param name="AFileId">The file's id in AStore; 0 answers False.</param>
/// <param name="ALine">1-based line.</param>
/// <param name="ACol">1-based column.</param>
/// <param name="AName">The name written there: a ref of another name is no answer.</param>
/// <param name="ATypeLeaf">Out: the type's leaf name.</param>
/// <returns>False with no table (an index older than 1.44) or no row: the caller
/// keeps what it knew without the fact.</returns>
/// <remarks>Two queries per call, for rule candidates and not for every expression.</remarks>
function RefStaticTypeAt(const AStore: ISymbolStore; AFileId: Int64; ALine, ACol: Integer; const AName: string;
  out ATypeLeaf: string): Boolean;

type
  /// <summary>The answer to "does type A descend from type B" over the indexed ancestry.</summary>
  /// <remarks>Three values on purpose: a rule that wants to SUPPRESS on proof uses tdYes, a rule
  /// that wants to FIRE on proof of absence uses tdNo, and tdUnknown never changes what a rule
  /// does today.</remarks>
  TDescent = (
    /// <summary>Not decidable: no such type, a homonym that disagrees, an unresolved or generic
    /// ancestor with no library index, or not a class or interface.</summary>
    tdUnknown,
    /// <summary>The whole ancestry was followed and the ancestor is not in it.</summary>
    tdNo,
    /// <summary>The ancestor is in the ancestry of every class of that name.</summary>
    tdYes);

/// <summary>Whether a class or interface descends from an ancestor (index fact type_ancestors).</summary>
/// <param name="AStore">The project index; nil or a store that is not SQLite answers tdUnknown.</param>
/// <param name="ALibStore">The platform library index, or nil. Without it an ancestor outside the
/// project is not followed: a positive answer still stands, a negative one becomes tdUnknown.</param>
/// <param name="ATypeLeaf">The type's name; a qualified name is cut to its leaf. Case-insensitive.</param>
/// <param name="AAncestorLeaf">The ancestor's name, leaf only. Case-insensitive. The type itself counts.</param>
/// <returns>tdYes, tdNo or tdUnknown; see TDescent. Needs no ref_types table, only type_ancestors.</returns>
/// <remarks>Homonyms are intersected as in the unit comment: they can turn tdYes into tdUnknown,
/// never create one. One call builds its own caches; use TExprTypeReader.Descends in a loop.</remarks>
function TypeDescendsFrom(const AStore, ALibStore: ISymbolStore; const ATypeLeaf, AAncestorLeaf: string): TDescent;

type
  /// <summary>Static types of expressions in ONE unit, from ref_types (index fact F1).</summary>
  /// <remarks>Not thread-safe. Owns its caches and a query on AStore's connection, so it must not
  /// outlive the store. Creating it costs one query for the file's refs; ask many nodes of the same
  /// file from one reader. Safe inside a `with`, no caller has to guard: there a name may bind to
  /// a member of the with-subject, so the reader answers only when the resolver decided the name
  /// (see TypeLeafOf). The first with-subject is outside its own scope; a later one is inside.</remarks>
  TExprTypeReader = class
    strict private
      FScan : TObject;
      FReady: Boolean;
    public
      /// <summary>Opens the unit's refs for reading.</summary>
      /// <param name="AStore">The project index; nil or not SQLite makes every answer false/unknown.</param>
      /// <param name="ALibStore">The platform library index, or nil (see TypeDescendsFrom).</param>
      /// <param name="AFileId">The unit's id in AStore.</param>
      /// <param name="ASrc">The unit's source bytes exactly as the node was parsed from (UTF-8).</param>
      constructor Create(const AStore, ALibStore: ISymbolStore; AFileId: Int64; const ASrc: TBytes);
      destructor Destroy; override;
      /// <summary>False when the index has no ref_types table (older than 1.44) or the store is unusable.</summary>
      property Ready: Boolean read FReady;
      /// <summary>The static type leaf of an expression node.</summary>
      /// <param name="ANode">An identifier, a dotted chain (`A.B.C`: the type of C), a call (`F(x)`,
      /// `A.B(x)`: the result type), a parenthesised expression, `x as T` or `T(x)`.</param>
      /// <param name="ALeaf">Out: the type's leaf name as written in the index; '' when false.</param>
      /// <returns>False with no table, no row, a conflicting row, or an expression shape that has
      /// no static type (a subscript, a dereference, arithmetic): the caller keeps what it knew.
      /// Inside a `with` scope also False unless a ref_types row proves it: the expression's own row
      /// and the row of its leftmost name (or an explicit Self), neither of them a cast. The written
      /// type of `x as T` or `T(x)` is no proof there, and neither is a chain rooted in a subscript or
      /// parentheses. Never a wrong type: unknown instead.</returns>
      function TypeLeafOf(const ANode: TTSNode; out ALeaf: string): Boolean;
      /// <summary>TypeDescendsFrom on this reader's caches.</summary>
      /// <param name="ATypeLeaf">See TypeDescendsFrom.</param>
      /// <param name="AAncestorLeaf">See TypeDescendsFrom.</param>
      /// <returns>See TypeDescendsFrom.</returns>
      function Descends(const ATypeLeaf, AAncestorLeaf: string): TDescent;
  end;

/// <summary>One-shot TExprTypeReader.TypeLeafOf: the static type leaf of one expression node.</summary>
/// <param name="AStore">The project index.</param>
/// <param name="AFileId">The unit's id in AStore.</param>
/// <param name="ANode">The expression node (see TExprTypeReader.TypeLeafOf).</param>
/// <param name="ASrc">The unit's source bytes the node came from.</param>
/// <param name="ALeaf">Out: the type's leaf name.</param>
/// <returns>False when no fact answers; see TExprTypeReader.TypeLeafOf.</returns>
/// <remarks>Loads the unit's refs on every call: for more than a few nodes of one unit make a
/// TExprTypeReader.</remarks>
function StaticTypeLeafOfExpr(const AStore: ISymbolStore; AFileId: Int64; const ANode: TTSNode; const ASrc: TBytes;  // dl:ok unused-public-symbol@1e97 -- REVIEWED 2026-11-06: public for tests\lint-project\ref-type-helpers, the harness that pins it (H4/O1); the rules reach it through the type reader
  out ALeaf: string): Boolean;
/// <summary>Runs the rules on index fact F1 over a project index.</summary>
/// <param name="AStore">The project index; nil, a store that is not SQLite, or an
/// index with no ref_types table yields no findings.</param>
/// <param name="ALibStore">The platform library index, or nil. Without it a class
/// on a library base has an incomplete ancestry and the rules that need the
/// ancestor stay silent.</param>
/// <param name="ARules">The rule ids to evaluate; empty yields no findings.</param>
/// <param name="AOnlyFileId">One file's id, or 0 for every file of the index.</param>
/// <returns>One finding per offending expression, anchored at it.</returns>
/// <remarks>Reads one file's refs per file (one query) and parses through
/// TAstParseCache. A ref whose name no longer matches the source at its position
/// answers nothing, so a stale index errs towards silence.</remarks>
function CollectRefTypeRules(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>;
  AOnlyFileId: Int64): TArray<TLintFinding>;

implementation

uses
  System.Generics.Collections
  , System.RegularExpressions
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param  // dl:ok unused-unit-in-uses@c61d -- REVIEWED 2026-11-05: TFDParam.SetAsLargeInt is inline, and without this unit the compiler says H2443 at every parameter assignment
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Storage.SQLite
  ;

const
  TYPE_NODE_ID     = 'identifier';
  NODE_DOT         = 'exprDot';
  NODE_CALL        = 'exprCall';
  NODE_PARENS      = 'exprParens';
  { The grammar aliases exprAs to exprBinary: `x as T` is told apart by its operator node. }
  OP_NODE_AS       = 'kAs';
  NODE_BINARY      = 'exprBinary';
  NODE_WITH        = 'with';
  FIELD_LHS        = 'lhs';
  FIELD_RHS        = 'rhs';
  FIELD_OP         = 'operator';
  FIELD_ENTITY     = 'entity';
  FIELD_ARGS       = 'args';
  OP_IS            = 'is';
  ROOT_CLASS       = 'tobject';
  OVERLOAD_WORD    = 'overload';
  { How many aliases of an alias are followed. }
  MAX_ALIAS_HOPS   = 4;
  { Storage of the signed and unsigned integer types and the floats: a rank, not a promise of sizeof. }
  WIDTH_FLOAT_BASE = 100;
  NODE_ASSIGN      = 'assignment';
  OP_NODE_ASSIGN   = 'kAssign';
  SELF_WORD        = 'Self';
  ADDREF_NAME      = '_AddRef';
  { Bases whose _AddRef / _Release do nothing. }
  NON_REFCOUNTED: array[0..2] of string = ('tcomponent', 'tnorefcountobject', 'tsingletonimplementation');
  { How far a nested routine's parents are climbed to reach its class. }
  MAX_PARENT_HOPS  = 8;
  CLASS_COMPONENT  = 'tcomponent';
  CLASS_THREAD     = 'tthread';
  FIELD_BODY       = 'body';
  VIA_CTOR         = 'ctor';
  VIA_RESULT       = 'result';
  VIA_CAST         = 'cast';
  KEYWORD_NODE_PREFIX = 'k';
  NIL_WORD         = 'nil';
  { A call that ends the object's life, or hands the job to the object. }
  FREE_WORDS_RX    = '\b(free|destroy|release|disposeof|freeandnil|freeonterminate)\b';
  SEV_WARNING      = 'warning';
  SEV_HINT         = 'hint';
  { Bits of the line in a position key; a column stays far below 2^20. }
  POS_LINE_SHIFT   = 20;
  NODE_LAMBDA      = 'lambda';
  NODE_DEFPROC     = 'defProc';
  DOT_SEP    = '.';
  FIELD_HEADER     = 'header';
  FIELD_NAME       = 'name';
  { The classes whose members are not thread-safe, by leaf name. TCustomForm is listed beside
    TControl because the FMX and VCL TForm homonyms intersect above TControl. Parallel arrays. }
  UI_ROOTS: array[0..4] of string = ('tcontrol', 'tcustomform', 'tapplication', 'tscreen', 'tfmxobject');
  UI_ROOT_NAMES: array[0..4] of string = ('TControl', 'TCustomForm', 'TApplication', 'TScreen', 'TFmxObject');
  { A bare member of a form may be declared on these, above the homonym intersection. }
  UI_FORM_BASES: array[0..2] of string = ('tcontrol', 'twincontrol', 'tscrollingwincontrol');
  ROOT_APPLICATION = 'tapplication';
  ROOT_SCREEN      = 'tscreen';
  ROOT_APPLICATION_NAME = 'TApplication';
  { Data of TObject and TComponent: no window, no message, no paint. }
  UI_SAFE_MEMBERS: array[0..13] of string = ('classname', 'classtype', 'classinfo', 'classparent', 'inheritsfrom',
    'unitname', 'qualifiedclassname', 'tag', 'name', 'gethashcode', 'tostring', 'equals', 'fieldaddress', 'instancesize');
  UI_SAFE_APP_MEMBERS: array[0..2] of string = ('terminated', 'exename', 'handle');
  MARSHAL_CALLS: array[0..2] of string = ('synchronize', 'queue', 'forcequeue');
  THREAD_STARTS: array[0..4] of string = ('tthread.createanonymousthread', 'ttask.run', 'ttask.create', 'ttask.future', 'tparallel.for');
  { Upper case: a body that names a main-thread check took care of itself. }
  GUARD_WORDS: array[0..1] of string = ('MAINTHREAD', 'CURRENTTHREAD');
  SELF_MARSHAL_WORDS: array[0..1] of string = ('SYNCHRONIZE', 'QUEUE');
  THREAD_ROOT      = 'tthread';
  EXECUTE_NAME     = 'Execute';
  CREATE_NAME      = 'Create';
  APPLICATION_NAME = 'Application';
  SCREEN_NAME      = 'Screen';
  FORMS_UNIT_RX    = '\bforms\b';
  { Units whose own `Application` shadows the one of Forms. }
  OTHER_APP_UNIT_RX = '\b(svcmgr|webbroker)\b';
  GENERIC_ARGS_RX  = '<[^>]*>';
  { As ui-access-in-thread-transitive walks. }
  MAX_THREAD_HOPS  = 5;
  { How much of an expression a message quotes. }
  MAX_QUOTED_EXPR  = 60;

type
  /// <summary>The ref_types row of one reference, as read for one file.</summary>
  TRefFact = record
    Name        : string;
    SymbolId    : Int64 ;
    TypeSymbolId: Int64 ;
    TypeQName   : string;
    Via         : string;
    Enclosing   : Int64 ;
    { Two refs at one position disagree on the type: no answer. }
    Conflict    : Boolean;
    /// <summary>The project symbol ANY row at this position binds to; 0 when none does.</summary>
    MemberSym   : Int64;
    /// <summary>The certain call_edges target of any row at this position; 0 when none.</summary>
    CallTarget  : Int64;
  end;

  /// <summary>One thing thread code does: a UI access, or a resolved call.</summary>
  TThreadTouch = record
    IsCall   : Boolean;
    StartLine: Integer;
    StartCol : Integer;
    EndLine  : Integer;
    EndCol   : Integer;
    /// <summary>The access as a message quotes it; for a call, the callee as written.</summary>
    Text     : string;
    Target   : Int64;
  end;

  /// <summary>What a routine does when a thread runs it.</summary>
  TRoutineThreadFacts = record
    /// <summary>Its first UI access and where; '' when it has none or protects itself.</summary>
    Witness: string;
    Callees: TArray<Int64>;
  end;

  /// <summary>The nearest UI access over resolved calls from one routine.</summary>
  TThreadReach = record
    Path   : string;
    Witness: string;
  end;

  /// <summary>What the rules need to know about one type.</summary>
  TTypeFacts = record
    Known     : Boolean;
    IsClass   : Boolean;
    IsIntf    : Boolean;
    /// <summary>The written or declared name, for messages.</summary>
    Name      : string;
    /// <summary>Lower-case leaf names of the type and of every ancestor.</summary>
    Closure   : TArray<string>;
    /// <summary>False when some ancestor could not be followed.</summary>
    Complete  : Boolean;
    /// <summary>The type's symbol in the project index; 0 for a library type or a homonym.</summary>
    SymbolId  : Int64;
    /// <summary>The name stands for several types, so it identifies none of them.</summary>
    Homonym   : Boolean;
    /// <summary>Declared `class sealed`; of a homonym, every one of them.</summary>
    Sealed    : Boolean;
    function HasAncestor(const ALeaf: string): Boolean;
  end;

  /// <summary>The static type of one expression.</summary>
  TExprType = record
    Known: Boolean;
    Facts: TTypeFacts;
  end;

  /// <summary>One run over a project index.</summary>
  TRefTypeScan = class  // dl:ok god-class@9eb0, high-response@9eb0 -- REVIEWED 2026-11-05: one scan and its caches; the rules share the type closure and the per-file ref map, and splitting them would only pass that state around
    strict private
      FStore   : ISymbolStore;
      FLib     : ISymbolStore;
      FRules   : TArray<string>;
      FFindings: TList<TLintFinding>;
      FRefs    : TDictionary<Int64, TRefFact>;
      FByName  : TDictionary<string, TTypeFacts>;
      FById    : TDictionary<Int64, TTypeFacts>;
      FLibName : TDictionary<string, TTypeFacts>;
      FQuery   : TFDQuery;
      FPath    : string;
      FFileId  : Int64;
      FSrc     : TBytes;
      FSymbols : TDictionary<Int64, TSymbol>;
      { 'operand text|type', lower case: the `x is T` tests of the current file. File-scoped,
        as the lexical check's are: a guard elsewhere silences, which errs towards silence. }
      FGuards  : TDictionary<string, Boolean>;
      FWithDepth: Integer;
      FOwnRefCount: TArray<string>;
      FOwnRefCountRead: Boolean;
      { ui-access-in-thread-typed }
      FTouches : TList<TThreadTouch>;
      FSelfFacts: TTypeFacts;
      FRoutineFacts: TDictionary<Int64, TRoutineThreadFacts>;
      FReach   : TDictionary<Int64, TThreadReach>;
      FUiOwners: TDictionary<string, TArray<string>>;
      FOwnRoots: TDictionary<string, Boolean>;
      FEmitted : TDictionary<Int64, Boolean>;
      function ProjectOwnsName(const ALeaf: string): Boolean;
      function UiRootOf(const AFacts: TTypeFacts): string;
      function SourceNames(const APattern: string): Boolean;
      function UiGlobalRoot(const ANode: TTSNode): string;
      function IsUiMember(const AName: string; const AFacts: TTypeFacts): Boolean;
      function RoutineClassFacts(const ANode: TTSNode): TTypeFacts;
      function BodyNames(const ABody: TTSNode; const AWords: array of string): Boolean;
      procedure AddTouch(const ANode: TTSNode; AIsCall: Boolean; const AText: string; ATarget: Int64);
      procedure AddAccess(const ANode: TTSNode; const ATypeName, ARoot: string);
      procedure CollectDot(const ANode: TTSNode);
      procedure CollectBare(const ANode: TTSNode);
      procedure CollectThreadCode(const ANode: TTSNode);
      procedure CollectBody(const ABody: TTSNode);
      function FindDefProc(const ANode: TTSNode; ALine: Integer): TTSNode;
      function SwitchToFile(AFileId: Int64): Boolean;
      function RoutineFacts(AId: Int64): TRoutineThreadFacts;
      function ReachOf(ATarget: Int64; out AReach: TThreadReach): Boolean;
      procedure EmitThreadFinding(const ATouch: TThreadTouch; const AMessage: string);
      procedure EmitReach(const ATouch: TThreadTouch; const AEntry: string);
      procedure CheckThreadBody(const ABody: TTSNode; const AEntry: string);
      procedure CheckExecuteEntry(const ANode: TTSNode);
      procedure CheckThreadStart(const ANode: TTSNode);
      function Wants(const ARuleId: string): Boolean;
      function Text(const ANode: TTSNode): string;
      function FactAt(const ANode: TTSNode; out AFact: TRefFact): Boolean;
      procedure LoadRefs(AFileId: Int64);
      procedure Emit(const ARuleId: string; const ANode: TTSNode; const AMessage: string; const ASeverity: string = SEV_WARNING);
      function ClosureFromStore(const AStore: ISymbolStore; const ASym: TSymbol; AOutermost: Boolean;
        var AFacts: TTypeFacts): Boolean;
      function FactsOfSymbol(const AStore: ISymbolStore; const ASym: TSymbol; AOutermost: Boolean): TTypeFacts;
      function MergeSymbols(const AStore: ISymbolStore; const ASyms: TArray<TSymbol>; const AName: string;
        AOutermost: Boolean): TTypeFacts;
      function LibraryFacts(const ALeaf: string): TTypeFacts;
      function FactsOfName(const AName: string): TTypeFacts;
      function FactsOfId(AId: Int64): TTypeFacts;
      function WrittenType(const ANode: TTSNode): TTypeFacts;
      function CastTarget(const ANode: TTSNode; out AFacts: TTypeFacts; out AOperand: TTSNode): Boolean;
      function StaticType(const ANode: TTSNode): TExprType;
      function CastParts(const ANode: TTSNode; out ATarget: TTypeFacts; out AOperand: TTSNode): Boolean;
      procedure CheckUpcastThenDowncast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
      procedure CheckRedundantCast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
      procedure CollectGuards(const ANode: TTSNode);
      procedure CheckUnsafeCast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
      procedure CheckCast(const ANode: TTSNode);
      procedure CheckWith(const ANode: TTSNode);
      function OwnRefCountClasses: TArray<string>;
      function SelfType(const AAssignLhs: TTSNode): TExprType;
      procedure CheckAssign(const ANode: TTSNode);
      function SymbolOf(AId: Int64): TSymbol;
      function ResolveAlias(const ATypeName: string): string;
      function NumericName(const ANode: TTSNode; out AFact: TRefFact): Boolean;
      procedure CheckArguments(const ANode: TTSNode);
      procedure CheckIs(const ANode: TTSNode);
      procedure Walk(const ANode: TTSNode);
    public
      constructor Create(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>);
      destructor Destroy; override;
      /// <summary>Scans one file of the index.</summary>
      procedure ScanFile(AFileId: Int64);
      /// <summary>True when the index carries the ref_types table.</summary>
      function HasFact: Boolean;
      /// <summary>Points the scan at one file's refs and source, for ExprTypeLeaf.</summary>
      procedure Attach(AFileId: Int64; const ASrc: TBytes);
      /// <summary>The static type leaf of an expression; False when no fact answers.</summary>
      function ExprTypeLeaf(const ANode: TTSNode; out ALeaf: string): Boolean;
      { True when a name in ANode may bind to a member of an enclosing with-subject. }
      function InWithScope(const ANode: TTSNode): Boolean;
      { The identifier whose ref carries the type of the (parens-free) expression; null when none. }
      function LastHopName(const AInner: TTSNode): TTSNode;
      { ExprTypeLeaf inside a with scope: answers only on proof, see TExprTypeReader.TypeLeafOf. }
      function WithProofLeaf(const AInner: TTSNode; out ALeaf: string): Boolean;
      /// <summary>Descent of a type name from an ancestor leaf over the closure.</summary>
      function DescentOf(const ATypeLeaf, AAncestorLeaf: string): TDescent;
      /// <summary>The findings so far, in scan order.</summary>
      function Findings: TArray<TLintFinding>;
  end;

/// <summary>Bytes of a numeric type name, plus WIDTH_FLOAT_BASE for a float; 0 for any other type.</summary>
function NumericWidth(const ALowerType: string): Integer;  // dl:ok too-many-exit-points@f4c0 -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
const
  WIDTH_1: array[0..1] of string = ('shortint', 'byte');
  WIDTH_2: array[0..1] of string = ('smallint', 'word');
  WIDTH_4: array[0..5] of string = ('integer', 'longint', 'cardinal', 'longword', 'fixedint', 'fixeduint');
  WIDTH_8: array[0..5] of string = ('int64', 'uint64', 'nativeint', 'nativeuint', 'intptr', 'uintptr');
  BYTES_1 = 1; BYTES_2 = 2; BYTES_4 = 4; BYTES_8 = 8;
begin
  Result:= 0;
  for var S: string in WIDTH_1 do if S = ALowerType then Exit(BYTES_1);
  for var S: string in WIDTH_2 do if S = ALowerType then Exit(BYTES_2);
  for var S: string in WIDTH_4 do if S = ALowerType then Exit(BYTES_4);
  for var S: string in WIDTH_8 do if S = ALowerType then Exit(BYTES_8);
  if ALowerType = 'single' then Exit(WIDTH_FLOAT_BASE + BYTES_4);
  if (ALowerType = 'double') or (ALowerType = 'real') then Exit(WIDTH_FLOAT_BASE + BYTES_8);
end;

/// <summary>The by-value parameter types of a routine signature in order; '' for a
/// var / out / untyped / array parameter, which never narrows.</summary>
function ParamTypes(const ASignature: string): TArray<string>;
begin
  Result:= nil;
  var Open: Integer:= ASignature.IndexOf('(');
  if Open < 0 then Exit;
  var Depth: Integer:= 0;
  var Close: Integer:= -1;
  for var I: Integer:= Open to ASignature.Length - 1 do
  begin
    if ASignature.Chars[I] = '(' then Inc(Depth)
    else if ASignature.Chars[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close:= I;
        Break;
      end;
    end;
  end;
  if Close < 0 then Exit;
  for var Part: string in ASignature.Substring(Open + 1, Close - Open - 1).Split([';']) do
  begin
    var P: string:= Part.Trim;
    var Colon: Integer:= P.IndexOf(':');
    var Names: string:= if Colon >= 0 then P.Substring(0, Colon) else P;
    var TypeText: string:= '';
    if Colon >= 0 then TypeText:= P.Substring(Colon + 1).Split(['='])[0].Trim;
    var Low: string:= Names.Trim.ToLower;
    if Low.StartsWith('var ') or Low.StartsWith('out ') then TypeText:= '';
    for var N: string in Names.Split([',']) do
      Result:= Result + [TypeText];
  end;
end;

function IsAsNode(const ANode: TTSNode): Boolean;
begin
  Result:= (ANode.NodeType = NODE_BINARY) and (not ANode.ChildByField(FIELD_OP).IsNull)
    and (ANode.ChildByField(FIELD_OP).NodeType = OP_NODE_AS);
end;

function LeafOf(const AName: string): string;
var
  Dot: Integer;
begin
  Result:= AName.Trim;
  Dot   := Result.LastDelimiter('.');
  if Dot >= 0 then Result:= Result.Substring(Dot + 1);
end;

function TTypeFacts.HasAncestor(const ALeaf: string): Boolean;
begin
  Result:= False;
  for var S: string in Closure do
    if S = ALeaf then Exit(True);
end;

function PosKey(ALine, ACol: Integer): Int64;
begin
  Result:= (Int64(ALine) shl POS_LINE_SHIFT) or Int64(ACol);
end;

constructor TRefTypeScan.Create(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>);
begin
  inherited Create;
  FStore   := AStore;
  FLib     := ALibStore;
  FRules   := ARules;
  FFindings:= TList<TLintFinding>.Create;
  FRefs    := TDictionary<Int64, TRefFact>.Create;
  FByName  := TDictionary<string, TTypeFacts>.Create;
  FById    := TDictionary<Int64, TTypeFacts>.Create;
  FLibName := TDictionary<string, TTypeFacts>.Create;
  FSymbols := TDictionary<Int64, TSymbol>.Create;
  FGuards  := TDictionary<string, Boolean>.Create;
  FTouches := TList<TThreadTouch>.Create;
  FRoutineFacts:= TDictionary<Int64, TRoutineThreadFacts>.Create;
  FReach   := TDictionary<Int64, TThreadReach>.Create;
  FUiOwners:= TDictionary<string, TArray<string>>.Create;
  FOwnRoots:= TDictionary<string, Boolean>.Create;
  FEmitted := TDictionary<Int64, Boolean>.Create;
  FQuery   := TFDQuery.Create(nil);
  FQuery.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
end;

destructor TRefTypeScan.Destroy;
begin
  FQuery.Free;
  FEmitted.Free;
  FOwnRoots.Free;
  FUiOwners.Free;
  FReach.Free;
  FRoutineFacts.Free;
  FTouches.Free;
  FSymbols.Free;
  FGuards.Free;
  FLibName.Free;
  FById.Free;
  FByName.Free;
  FRefs.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TRefTypeScan.HasFact: Boolean;
begin
  FQuery.SQL.Text:= 'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = ''ref_types''';
  FQuery.Open;
  try
    Result:= not FQuery.Eof;
  finally
    FQuery.Close;
  end;
end;

function TRefTypeScan.Findings: TArray<TLintFinding>;
begin
  Result:= FFindings.ToArray;
end;

function TRefTypeScan.Wants(const ARuleId: string): Boolean;
begin
  Result:= False;
  for var S: string in FRules do
    if SameText(S, ARuleId) then Exit(True);
end;

function TRefTypeScan.Text(const ANode: TTSNode): string;
var
  StartIdx: Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  Len     := Integer(ANode.EndByte) - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (StartIdx + Len > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, StartIdx, Len);
end;

procedure TRefTypeScan.LoadRefs(AFileId: Int64);
const
  COL_LINE = 0; COL_COL = 1; COL_NAME = 2; COL_SYM = 3; COL_ENCL = 4; COL_TID = 5; COL_QNAME = 6; COL_VIA = 7;
  COL_CALL = 8; COL_CONF = 9;
  CONFIDENCE_CERTAIN = 'certain';
begin
  FRefs.Clear;
  FQuery.SQL.Text:= 'SELECT r.start_line, r.start_col, r.name_text, r.symbol_id, r.enclosing_symbol_id, ' +
                    '  t.type_symbol_id, t.type_qname, t.via, e.target_symbol_id, e.confidence ' +
                    'FROM refs r LEFT JOIN ref_types t ON t.ref_id = r.id ' +
                    'LEFT JOIN call_edges e ON e.ref_id = r.id WHERE r.file_id = :f';
  FQuery.ParamByName('f').AsLargeInt:= AFileId;
  FQuery.Open;
  try
    while not FQuery.Eof do
    begin
      var Key: Int64:= PosKey(FQuery.Fields[COL_LINE].AsInteger, FQuery.Fields[COL_COL].AsInteger);
      var F: TRefFact:= Default(TRefFact);
      F.Name        := FQuery.Fields[COL_NAME].AsString;
      F.SymbolId    := FQuery.Fields[COL_SYM].AsLargeInt;
      F.Enclosing   := FQuery.Fields[COL_ENCL].AsLargeInt;
      F.TypeSymbolId:= FQuery.Fields[COL_TID].AsLargeInt;
      F.TypeQName   := FQuery.Fields[COL_QNAME].AsString;
      F.Via         := FQuery.Fields[COL_VIA].AsString;
      F.MemberSym   := F.SymbolId;
      if FQuery.Fields[COL_CONF].AsString = CONFIDENCE_CERTAIN then F.CallTarget:= FQuery.Fields[COL_CALL].AsLargeInt;
      var Old: TRefFact;
      if FRefs.TryGetValue(Key, Old) then
      begin
        var AnySym : Int64:= if F.MemberSym > 0 then F.MemberSym else Old.MemberSym;
        var AnyCall: Int64:= if F.CallTarget > 0 then F.CallTarget else Old.CallTarget;
        { A second ref at one position: an untyped one adds nothing; a typed one
          that disagrees leaves no answer. }
        if F.TypeQName = '' then F:= Old
        else if (Old.TypeQName <> '') and not SameText(Old.TypeQName, F.TypeQName) then F.Conflict:= True;
        F.MemberSym := AnySym;
        F.CallTarget:= AnyCall;
      end;
      FRefs.AddOrSetValue(Key, F);
      FQuery.Next;
    end;
  finally
    FQuery.Close;
  end;
end;

function TRefTypeScan.FactAt(const ANode: TTSNode; out AFact: TRefFact): Boolean;
begin
  AFact:= Default(TRefFact);
  Result:= (not ANode.IsNull)
    and FRefs.TryGetValue(PosKey(Integer(ANode.StartPoint.Row) + 1, Integer(ANode.StartPoint.Column) + 1), AFact)
    and (not AFact.Conflict)
    and SameText(AFact.Name, Text(ANode));
end;

procedure TRefTypeScan.Emit(const ARuleId: string; const ANode: TTSNode; const AMessage: string; const ASeverity: string);
var
  F: TLintFinding;
begin
  F:= Default(TLintFinding);
  F.RuleId   := ARuleId;
  F.Severity := ASeverity;
  F.Message  := AMessage;
  F.FileId   := FFileId;
  F.FilePath := FPath;
  F.StartLine:= Integer(ANode.StartPoint.Row) + 1;
  F.StartCol := Integer(ANode.StartPoint.Column) + 1;
  F.EndLine  := Integer(ANode.EndPoint.Row) + 1;
  F.EndCol   := Integer(ANode.EndPoint.Column) + 1;
  FFindings.Add(F);
end;

function TRefTypeScan.ClosureFromStore(const AStore: ISymbolStore; const ASym: TSymbol; AOutermost: Boolean;
  var AFacts: TTypeFacts): Boolean;
var
  Names: TList<string>;
begin
  Result:= True;
  Names := TList<string>.Create;
  try
    Names.Add(ASym.Name.ToLower);
    for var A: TTypeAncestor in AStore.GetTransitiveAncestors(ASym.Id) do
    begin
      var Leaf: string:= LeafOf(A.Name).ToLower;
      if Leaf.Contains('<') then
      begin
        { A generic base: its instantiation is a different class from a plain
          homonym, so it is kept verbatim and not followed. }
        Names.Add(Leaf);
        Result:= False;
        Continue;
      end;
      if not Names.Contains(Leaf) then Names.Add(Leaf);
      { An alias in a heritage list: the class it landed on counts too, or is-never-true calls it unrelated. }
      if (A.ResolvedName <> '') and not Names.Contains(LeafOf(A.ResolvedName).ToLower) then Names.Add(LeafOf(A.ResolvedName).ToLower);
      if A.Resolved then Continue;
      if not AOutermost then
      begin
        Result:= False;
        Continue;
      end;
      var Lib: TTypeFacts:= LibraryFacts(Leaf);
      if not Lib.Known then
      begin
        Result:= False;
        Continue;
      end;
      if not Lib.Complete then Result:= False;
      for var N: string in Lib.Closure do
        if not Names.Contains(N) then Names.Add(N);
    end;
    if (ASym.Kind = skClass) and not Names.Contains(ROOT_CLASS) then Names.Add(ROOT_CLASS);
    AFacts.Closure:= Names.ToArray;
  finally
    Names.Free;
  end;
end;

function TRefTypeScan.FactsOfSymbol(const AStore: ISymbolStore; const ASym: TSymbol; AOutermost: Boolean): TTypeFacts;
begin
  Result        := Default(TTypeFacts);
  Result.Known  := True;
  Result.Name   := ASym.Name;
  if AOutermost then Result.SymbolId:= ASym.Id;
  Result.IsClass:= ASym.Kind = skClass;
  Result.IsIntf := ASym.Kind = skInterface;
  Result.Sealed := Result.IsClass and SameText(ASym.Directives, CLASS_DIRECTIVE_SEALED);
  if not (Result.IsClass or Result.IsIntf) then Exit;
  Result.Complete:= ClosureFromStore(AStore, ASym, AOutermost, Result);
end;

function TRefTypeScan.MergeSymbols(const AStore: ISymbolStore; const ASyms: TArray<TSymbol>; const AName: string;
  AOutermost: Boolean): TTypeFacts;
const
  TYPE_KINDS = [skClass, skInterface, skRecord, skEnum, skTypeAlias];
begin
  Result:= Default(TTypeFacts);
  var First: Boolean:= True;
  for var S: TSymbol in ASyms do
  begin
    if S.Kind not in TYPE_KINDS then Continue;
    var One: TTypeFacts:= FactsOfSymbol(AStore, S, AOutermost);
    if First then
    begin
      Result:= One;
      First := False;
      Continue;
    end;
    { A homonym: only what ALL of them agree on survives. }
    Result.Homonym := True;
    Result.SymbolId:= 0;
    Result.IsClass := Result.IsClass and One.IsClass;
    Result.IsIntf  := Result.IsIntf and One.IsIntf;
    Result.Sealed  := Result.Sealed and One.Sealed;
    Result.Complete:= Result.Complete and One.Complete;
    var Keep: TArray<string>:= nil;
    for var N: string in Result.Closure do
      if One.HasAncestor(N) then Keep:= Keep + [N];
    Result.Closure:= Keep;
  end;
  if Result.Known then Result.Name:= AName;
end;

function TRefTypeScan.LibraryFacts(const ALeaf: string): TTypeFacts;
begin
  Result:= Default(TTypeFacts);
  if FLib = nil then Exit;
  var Key: string:= ALeaf.ToLower;
  if FLibName.TryGetValue(Key, Result) then Exit;
  Result:= MergeSymbols(FLib, FLib.FindSymbolsByExactName(ALeaf), ALeaf, {AOutermost=}False);
  FLibName.Add(Key, Result);
end;

function TRefTypeScan.FactsOfName(const AName: string): TTypeFacts;
begin
  var Leaf: string:= LeafOf(AName);
  var Key : string:= Leaf.ToLower;
  if FByName.TryGetValue(Key, Result) then Exit;
  if Leaf.Contains('<') or Leaf.Contains(' ') then Result:= Default(TTypeFacts)
  else
  begin
    Result:= MergeSymbols(FStore, FStore.FindSymbolsByExactName(Leaf), Leaf, {AOutermost=}True);
    if not Result.Known then Result:= LibraryFacts(Leaf);
  end;
  FByName.Add(Key, Result);
end;

function TRefTypeScan.FactsOfId(AId: Int64): TTypeFacts;
begin
  if FById.TryGetValue(AId, Result) then Exit;
  Result:= FactsOfSymbol(FStore, FStore.GetSymbolById(AId), {AOutermost=}True);
  FById.Add(AId, Result);
end;

function TRefTypeScan.WrittenType(const ANode: TTSNode): TTypeFacts;
begin
  Result:= Default(TTypeFacts);
  if ANode.IsNull then Exit;
  if (ANode.NodeType <> TYPE_NODE_ID) and (ANode.NodeType <> NODE_DOT) then Exit;
  var Name: TTSNode:= if ANode.NodeType = NODE_DOT then ANode.ChildByField(FIELD_RHS) else ANode;
  var Fact: TRefFact;
  if FactAt(Name, Fact) and (Fact.SymbolId > 0) then
  begin
    Result:= FactsOfId(Fact.SymbolId);
    if Result.IsClass or Result.IsIntf then Exit;
    { A bound name that is not a type (a variable, a routine) is not a type name. }
    Exit(Default(TTypeFacts));
  end;
  Result:= FactsOfName(Text(Name));
end;

function TRefTypeScan.CastTarget(const ANode: TTSNode; out AFacts: TTypeFacts; out AOperand: TTSNode): Boolean;
begin
  Result:= False;
  AFacts:= Default(TTypeFacts);
  AOperand:= Default(TTSNode);
  if ANode.NodeType <> NODE_CALL then Exit;
  var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
  var Args: TTSNode:= ANode.ChildByField(FIELD_ARGS);
  if Ent.IsNull or Args.IsNull or (Args.NamedChildCount <> 1) then Exit;
  AFacts:= WrittenType(Ent);
  if not (AFacts.IsClass or AFacts.IsIntf) then Exit;
  AOperand:= Args.NamedChild(0);
  Result:= True;
end;

function TRefTypeScan.StaticType(const ANode: TTSNode): TExprType;  // dl:ok too-many-exit-points@f142 -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
var
  Fact: TRefFact;
begin
  Result:= Default(TExprType);
  if ANode.IsNull then Exit;
  var NT: string:= ANode.NodeType;
  if NT = NODE_PARENS then Exit(StaticType(ANode.NamedChild(0)));
  if IsAsNode(ANode) then
  begin
    Result.Facts:= WrittenType(ANode.ChildByField(FIELD_RHS));
    Result.Known:= Result.Facts.IsClass or Result.Facts.IsIntf;
    Exit;
  end;
  var Name: TTSNode:= Default(TTSNode);
  if NT = TYPE_NODE_ID then Name:= ANode
  else if NT = NODE_DOT then Name:= ANode.ChildByField(FIELD_RHS)
  else if NT = NODE_CALL then
  begin
    var Operand: TTSNode;
    var Target : TTypeFacts;
    if CastTarget(ANode, Target, Operand) then
    begin
      Result.Facts:= Target;
      Result.Known:= True;
      Exit;
    end;
    var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
    if Ent.IsNull then Exit;
    if Ent.NodeType = TYPE_NODE_ID then Name:= Ent
    else if Ent.NodeType = NODE_DOT then Name:= Ent.ChildByField(FIELD_RHS);
  end;
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) then Exit;
  if (FWithDepth > 0) and ((NT = TYPE_NODE_ID) or (ANode.ChildByField(FIELD_LHS).IsNull)) then Exit;
  if not FactAt(Name, Fact) or (Fact.TypeQName = '') then Exit;
  Result.Facts:= if Fact.TypeSymbolId > 0 then FactsOfId(Fact.TypeSymbolId) else FactsOfName(Fact.TypeQName);
  Result.Known:= Result.Facts.Known;
end;

{ The proof IS_NEVER_TRUE_RULE's contract states: see the constant. }
function IsNeverTrue(const ALhs, ATarget: TTypeFacts): Boolean;
begin
  Result:= False;
  if ALhs.Homonym or ATarget.Homonym or not (ALhs.Complete and ATarget.Complete) then Exit;
  if ALhs.IsClass and ATarget.IsClass then
    Result:= not ALhs.HasAncestor(ATarget.Name.ToLower) and not ATarget.HasAncestor(ALhs.Name.ToLower)
  else if ALhs.IsClass and ATarget.IsIntf then
    Result:= ALhs.Sealed and not ALhs.HasAncestor(ATarget.Name.ToLower)
  else if ALhs.IsIntf and ATarget.IsClass then
    Result:= ATarget.Sealed and not ATarget.HasAncestor(ALhs.Name.ToLower);
end;

procedure TRefTypeScan.CheckIs(const ANode: TTSNode);
begin
  var Op: TTSNode:= ANode.ChildByField(FIELD_OP);
  if Op.IsNull or not SameText(Text(Op).Trim, OP_IS) then Exit;
  var LhsN: TTSNode:= ANode.ChildByField(FIELD_LHS);
  var Lhs: TExprType:= StaticType(LhsN);
  if not Lhs.Known then Exit;
  var Target: TTypeFacts:= WrittenType(ANode.ChildByField(FIELD_RHS));
  if Wants(IS_NEVER_TRUE_RULE) and IsNeverTrue(Lhs.Facts, Target) then
    Emit(IS_NEVER_TRUE_RULE, ANode,
      Format('''%s'' is declared %s, and no %s can be a %s: this test is always False, so the branch it guards is dead.',
        [Text(LhsN), Lhs.Facts.Name, Lhs.Facts.Name, Target.Name]));
  if (not Lhs.Facts.IsClass) or (not Target.IsClass) or Target.Homonym then Exit;
  if Wants(IS_ALWAYS_TRUE_RULE) and Lhs.Facts.HasAncestor(Target.Name.ToLower) then
    Emit(IS_ALWAYS_TRUE_RULE, ANode,
      Format('''%s'' is declared %s, which is already a %s: this test only asks whether it is nil. Write Assigned(%s), or the declared type is wrong.',
        [Text(LhsN), Lhs.Facts.Name, Target.Name, Text(LhsN)]));
end;

function TRefTypeScan.CastParts(const ANode: TTSNode; out ATarget: TTypeFacts; out AOperand: TTSNode): Boolean;
begin
  Result  := False;
  ATarget := Default(TTypeFacts);
  AOperand:= Default(TTSNode);
  if ANode.IsNull then Exit;
  if ANode.NodeType = NODE_CALL then Exit(CastTarget(ANode, ATarget, AOperand));
  if ANode.NodeType = NODE_PARENS then Exit(CastParts(ANode.NamedChild(0), ATarget, AOperand));
  if not IsAsNode(ANode) then Exit;
  ATarget := WrittenType(ANode.ChildByField(FIELD_RHS));
  AOperand:= ANode.ChildByField(FIELD_LHS);
  Result  := ATarget.IsClass or ATarget.IsIntf;
end;

procedure TRefTypeScan.CheckUpcastThenDowncast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
var
  Inner  : TTypeFacts;
  InnerOp: TTSNode;
begin
  if not CastParts(AOperand, Inner, InnerOp) then Exit;
  if (not Inner.IsClass) or Inner.Homonym then Exit;
  var Source: TExprType:= StaticType(InnerOp);
  if (not Source.Known) or not Source.Facts.IsClass then Exit;
  var InnerLeaf: string:= Inner.Name.ToLower;
  if not (Source.Facts.HasAncestor(InnerLeaf) and AOuter.HasAncestor(InnerLeaf)) then Exit;
  if SameText(AOuter.Name, Inner.Name) then Exit;
  Emit(UPCAST_THEN_DOWNCAST_RULE, ANode,
    Format('''%s'' is declared %s: the cast to %s adds nothing and the cast on to %s narrows it unchecked. Cast once, with ''as'' or behind an ''is'' test, or fix the declared type.',
      [Text(InnerOp), Source.Facts.Name, Inner.Name, AOuter.Name]));
end;

procedure TRefTypeScan.CheckRedundantCast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
begin
  { A hard cast of a single variable is AstChecks' shape (it finds it without an index);
    a bare function call, which its type map cannot type, is this one's. }
  var Fact: TRefFact;
  if (ANode.NodeType = NODE_CALL) and (AOperand.NodeType = TYPE_NODE_ID)
     and not (FactAt(AOperand, Fact) and (Fact.Via = VIA_RESULT)) then Exit;
  var Source: TExprType:= StaticType(AOperand);
  if (not Source.Known) or (not Source.Facts.IsClass) or Source.Facts.Homonym then Exit;
  if not SameText(Source.Facts.Name, AOuter.Name) then Exit;
  if (Source.Facts.SymbolId <> AOuter.SymbolId) and (Source.Facts.SymbolId > 0) and (AOuter.SymbolId > 0) then Exit;
  Emit(REDUNDANT_CAST_RULE, ANode, Format('Redundant cast: %s is already of type %s', [Text(AOperand), AOuter.Name]), SEV_HINT);
end;

procedure TRefTypeScan.CollectGuards(const ANode: TTSNode);
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = NODE_BINARY then
  begin
    var Op: TTSNode:= ANode.ChildByField(FIELD_OP);
    if (not Op.IsNull) and SameText(Text(Op).Trim, OP_IS) then
      FGuards.AddOrSetValue(Text(ANode.ChildByField(FIELD_LHS)).Trim.ToLower + '|' + LeafOf(Text(ANode.ChildByField(FIELD_RHS))).ToLower, True);
  end;
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
    CollectGuards(ANode.NamedChild(I));
end;

procedure TRefTypeScan.CheckUnsafeCast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);  // dl:ok too-many-exit-points@701b -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
var
  Inner  : TTypeFacts;
  InnerOp: TTSNode;
begin
  if ANode.NodeType <> NODE_CALL then Exit;
  if SameText(AOuter.Name, ROOT_CLASS) then Exit;
  { A cast of a cast is upcast-then-downcast's. }
  if CastParts(AOperand, Inner, InnerOp) then Exit;
  var Source: TExprType:= StaticType(AOperand);
  if (not Source.Known) or (not Source.Facts.IsClass) then Exit;
  if Source.Facts.HasAncestor(AOuter.Name.ToLower) then Exit; { an upcast cannot fail }
  var OperandText: string:= Text(AOperand).Trim;
  if FGuards.ContainsKey(OperandText.ToLower + '|' + AOuter.Name.ToLower) then Exit;
  Emit(UNSAFE_TYPECAST_RULE, ANode,
    Format('Unchecked hard cast %s(%s): its static type is %s, with no ''is %s'' guard; a wrong run-time type crashes or corrupts. Guard with ''is'' or use the ''as'' operator.',
      [AOuter.Name, OperandText, Source.Facts.Name, AOuter.Name]));
end;

procedure TRefTypeScan.CheckCast(const ANode: TTSNode);
var
  Outer  : TTypeFacts;
  Operand: TTSNode;
begin
  if not CastParts(ANode, Outer, Operand) then Exit;
  if (not Outer.IsClass) or Outer.Homonym then Exit;
  if Wants(UPCAST_THEN_DOWNCAST_RULE) then CheckUpcastThenDowncast(ANode, Outer, Operand);
  if Wants(REDUNDANT_CAST_RULE) then CheckRedundantCast(ANode, Outer, Operand);
  if Wants(UNSAFE_TYPECAST_RULE) then CheckUnsafeCast(ANode, Outer, Operand);
end;

procedure TRefTypeScan.CheckWith(const ANode: TTSNode);
var
  Fact: TRefFact;
begin
  var Body: TTSNode:= ANode.ChildByField(FIELD_BODY);
  if Body.IsNull then Exit;
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
  begin
    var Ent: TTSNode:= ANode.NamedChild(I);
    if Ent.StartByte >= Body.StartByte then Break;
    var Callee: TTSNode:= Ent;
    var Args  : TTSNode:= Default(TTSNode);
    if Ent.NodeType = NODE_CALL then
    begin
      Callee:= Ent.ChildByField(FIELD_ENTITY);
      Args  := Ent.ChildByField(FIELD_ARGS);
    end;
    if Callee.IsNull or (Callee.NodeType <> NODE_DOT) then Continue;
    if (not FactAt(Callee.ChildByField(FIELD_RHS), Fact)) or (Fact.Via <> VIA_CTOR) then Continue;
    { The written class, not the row's: `TFoo.Create` may bind to a constructor TFoo inherits. }
    var Cls: TTypeFacts:= WrittenType(Callee.ChildByField(FIELD_LHS));
    if not Cls.IsClass then Continue;
    if Cls.HasAncestor(CLASS_THREAD) then Continue; { may free itself (FreeOnTerminate) }
    if Cls.HasAncestor(CLASS_COMPONENT) and (not Args.IsNull) and (Args.NamedChildCount > 0)
       and not SameText(Text(Args.NamedChild(0)).Trim, NIL_WORD) then Continue; { an owner takes it }
    if TRegEx.IsMatch(Text(Body), FREE_WORDS_RX, [roIgnoreCase]) then Continue;
    Emit(WITH_ON_TEMPORARY_RULE, Ent,
      Format('with on a new %s that nothing frees: the object has no name once the block ends, so it leaks. Hold it in a variable, or free it in the block.', [Cls.Name]));
  end;
end;

function TRefTypeScan.OwnRefCountClasses: TArray<string>;
begin
  if not FOwnRefCountRead then
  begin
    FOwnRefCountRead:= True;
    for var S: TSymbol in FStore.FindSymbolsByExactName(ADDREF_NAME) do
      if S.ParentId > 0 then FOwnRefCount:= FOwnRefCount + [FStore.GetSymbolById(S.ParentId).Name.ToLower];
  end;
  Result:= FOwnRefCount;
end;

function TRefTypeScan.SelfType(const AAssignLhs: TTSNode): TExprType;
var
  Fact: TRefFact;
begin
  Result:= Default(TExprType);
  var Name: TTSNode:= if AAssignLhs.NodeType = NODE_DOT then AAssignLhs.ChildByField(FIELD_RHS) else AAssignLhs;
  if (not FactAt(Name, Fact)) or (Fact.Enclosing <= 0) then Exit;
  var Id: Int64:= Fact.Enclosing;
  for var Hop: Integer:= 1 to MAX_PARENT_HOPS do
  begin
    if Id <= 0 then Exit;
    var Sym: TSymbol:= FStore.GetSymbolById(Id);
    if Sym.Kind = skClass then
    begin
      Result.Facts:= FactsOfId(Id);
      Result.Known:= True;
      Exit;
    end;
    Id:= Sym.ParentId;
  end;
end;

procedure TRefTypeScan.CheckAssign(const ANode: TTSNode);  // dl:ok too-many-exit-points@c598 -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
begin
  var Op: TTSNode:= ANode.ChildByField(FIELD_OP);
  if Op.IsNull or (Op.NodeType <> OP_NODE_ASSIGN) then Exit;
  var LhsN: TTSNode:= ANode.ChildByField(FIELD_LHS);
  var Holder: TExprType:= StaticType(LhsN);
  if (not Holder.Known) or not Holder.Facts.IsIntf then Exit;
  var RhsN: TTSNode:= ANode.ChildByField(FIELD_RHS);
  while (not RhsN.IsNull) and (RhsN.NodeType = NODE_PARENS) do RhsN:= RhsN.NamedChild(0);
  if RhsN.IsNull then Exit;
  if IsAsNode(RhsN) then RhsN:= RhsN.ChildByField(FIELD_LHS);
  var Source: TExprType:= if SameText(Text(RhsN), SELF_WORD) then SelfType(LhsN) else StaticType(RhsN);
  if (not Source.Known) or not Source.Facts.IsClass then Exit;
  var Base: string:= '';
  for var S: string in NON_REFCOUNTED do
    if Source.Facts.HasAncestor(S) then Base:= S;
  if Base = '' then Exit;
  for var S: string in OwnRefCountClasses do
    if Source.Facts.HasAncestor(S) then Exit; { its class counts references itself }
  Emit(INTERFACE_HOLDER_RULE, ANode,
    Format('Interface variable %s of type %s holds a %s, whose %s does not count references: the variable keeps nothing alive and dangles once the object is freed.',
      [Text(LhsN), Holder.Facts.Name, Source.Facts.Name, Base]));
end;

function TRefTypeScan.SymbolOf(AId: Int64): TSymbol;
begin
  if FSymbols.TryGetValue(AId, Result) then Exit;
  Result:= FStore.GetSymbolById(AId);
  FSymbols.Add(AId, Result);
end;

function TRefTypeScan.ResolveAlias(const ATypeName: string): string;
begin
  Result:= LeafOf(ATypeName);
  for var Hop: Integer:= 1 to MAX_ALIAS_HOPS do
  begin
    if NumericWidth(Result.ToLower) > 0 then Exit;
    var Target: string:= '';
    var Count : Integer:= 0;
    for var S: TSymbol in FStore.FindSymbolsByExactName(Result) do
      if S.Kind = skTypeAlias then
      begin
        Inc(Count);
        Target:= S.Signature;
      end;
    { A homonym names no one type. }
    if (Count <> 1) or (Target = '') then Exit;
    Result:= LeafOf(Target);
  end;
end;

function TRefTypeScan.NumericName(const ANode: TTSNode; out AFact: TRefFact): Boolean;
begin
  Result:= False;
  AFact := Default(TRefFact);
  var Name: TTSNode:= Default(TTSNode);
  if ANode.NodeType = TYPE_NODE_ID then
  begin
    if FWithDepth > 0 then Exit;
    Name:= ANode;
  end
  else if ANode.NodeType = NODE_DOT then Name:= ANode.ChildByField(FIELD_RHS)
  else if ANode.NodeType = NODE_CALL then
  begin
    var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
    if Ent.IsNull then Exit;
    if Ent.NodeType = TYPE_NODE_ID then
    begin
      if FWithDepth > 0 then Exit;
      Name:= Ent;
    end
    else if Ent.NodeType = NODE_DOT then Name:= Ent.ChildByField(FIELD_RHS);
  end;
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) then Exit;
  if (not FactAt(Name, AFact)) or (AFact.TypeQName = '') or (AFact.SymbolId <= 0) then Exit;
  { A constant's value is known to fit, or the compiler said so. }
  Result:= SymbolOf(AFact.SymbolId).Kind <> skConstDecl;
end;

procedure TRefTypeScan.CheckArguments(const ANode: TTSNode);  // dl:ok too-many-exit-points@d8e0 -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
var
  Callee: TRefFact;
  Arg   : TRefFact;
begin
  var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
  var Args: TTSNode:= ANode.ChildByField(FIELD_ARGS);
  if Ent.IsNull or Args.IsNull then Exit;
  var Name: TTSNode:= if Ent.NodeType = NODE_DOT then Ent.ChildByField(FIELD_RHS) else Ent;
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) then Exit;
  if (Ent.NodeType = TYPE_NODE_ID) and (FWithDepth > 0) then Exit;
  if (not FactAt(Name, Callee)) or (Callee.SymbolId <= 0) then Exit;
  var Sym: TSymbol:= SymbolOf(Callee.SymbolId);
  if Sym.Kind not in [skProcedure, skFunction, skMethod, skConstructor] then Exit;
  { The resolver's overload choice is the part a width argument cannot rest on. }
  if Sym.Directives.ToLower.Contains(OVERLOAD_WORD) or Sym.Modifiers.ToLower.Contains(OVERLOAD_WORD) then Exit;
  var Params: TArray<string>:= ParamTypes(Sym.Signature);
  if Integer(Args.NamedChildCount) > Length(Params) then Exit;
  for var I: Integer:= 0 to Integer(Args.NamedChildCount) - 1 do
  begin
    if Params[I] = '' then Continue;
    var ArgN: TTSNode:= Args.NamedChild(I);
    if not NumericName(ArgN, Arg) then Continue;
    var ArgType  : string:= ResolveAlias(Arg.TypeQName);
    var ParamType: string:= ResolveAlias(Params[I]);
    var ArgW  : Integer:= NumericWidth(ArgType.ToLower);
    var ParamW: Integer:= NumericWidth(ParamType.ToLower);
    if (ArgW = 0) or (ParamW = 0) then Continue;
    if (ArgW > WIDTH_FLOAT_BASE) <> (ParamW > WIDTH_FLOAT_BASE) then Continue;
    if ArgW <= ParamW then Continue;
    Emit(ARGUMENT_NARROWS_RULE, ArgN,
      Format('%s is %s but parameter %d of %s is %s: the value is truncated silently. Widen the parameter, or narrow it explicitly after a range check.',
        [Text(ArgN), ArgType, I + 1, Sym.Name, ParamType]));
  end;
end;

function TRefTypeScan.ProjectOwnsName(const ALeaf: string): Boolean;
begin
  if FOwnRoots.TryGetValue(ALeaf, Result) then Exit;
  Result:= False;
  for var S: TSymbol in FStore.FindSymbolsByExactName(ALeaf) do
    if (S.Kind = skClass) and not (S.QualifiedName.StartsWith('Vcl.', True) or S.QualifiedName.StartsWith('FMX.', True)
      or S.QualifiedName.StartsWith('System.', True)) then
    begin
      Result:= True;
      Break;
    end;
  FOwnRoots.Add(ALeaf, Result);
end;

function TRefTypeScan.UiRootOf(const AFacts: TTypeFacts): string;
begin
  Result:= '';
  if not AFacts.IsClass then Exit;
  for var I: Integer:= Low(UI_ROOTS) to High(UI_ROOTS) do
    if AFacts.HasAncestor(UI_ROOTS[I]) and not ProjectOwnsName(UI_ROOTS[I]) then Exit(UI_ROOT_NAMES[I]);
end;

function TRefTypeScan.SourceNames(const APattern: string): Boolean;
begin
  Result:= TRegEx.IsMatch(TEncoding.UTF8.GetString(FSrc), APattern, [roIgnoreCase]);
end;

function TRefTypeScan.UiGlobalRoot(const ANode: TTSNode): string;
var
  Fact: TRefFact;
begin
  Result:= '';
  if ANode.NodeType <> TYPE_NODE_ID then Exit;
  var Name: string:= Text(ANode);
  if not (SameText(Name, APPLICATION_NAME) or SameText(Name, SCREEN_NAME)) then Exit;
  if (FWithDepth > 0) or (not FactAt(ANode, Fact)) or (Fact.MemberSym > 0) or
     (not SourceNames(FORMS_UNIT_RX)) or SourceNames(OTHER_APP_UNIT_RX) then Exit;
  var Leaf: string:= if SameText(Name, APPLICATION_NAME) then ROOT_APPLICATION else ROOT_SCREEN;
  if ProjectOwnsName(Leaf) then Exit;
  for var I: Integer:= Low(UI_ROOTS) to High(UI_ROOTS) do
    if UI_ROOTS[I] = Leaf then Exit(UI_ROOT_NAMES[I]);
end;

function TRefTypeScan.IsUiMember(const AName: string; const AFacts: TTypeFacts): Boolean;
const
  MEMBER_KINDS = [skMethod, skFunction, skProcedure, skProperty, skField];
var
  Owners: TArray<string>;
begin
  Result:= False;
  if FLib = nil then Exit;
  var Key: string:= AName.ToLower;
  if not FUiOwners.TryGetValue(Key, Owners) then
  begin
    Owners:= nil;
    for var S: TSymbol in FLib.FindSymbolsByExactName(AName) do
    begin
      if S.Kind not in MEMBER_KINDS then Continue;
      var Parts: TArray<string>:= S.QualifiedName.Split([DOT_SEP]);
      if Length(Parts) < 2 then Continue;
      var Owner: string:= Parts[High(Parts) - 1].ToLower;
      if UiRootOf(LibraryFacts(Owner)) <> '' then Owners:= Owners + [Owner];
    end;
    FUiOwners.Add(Key, Owners);
  end;
  var IsForm: Boolean:= AFacts.HasAncestor('tcustomform');
  for var O: string in Owners do
  begin
    if AFacts.HasAncestor(O) then Exit(True);
    if IsForm then
      for var B: string in UI_FORM_BASES do
        if B = O then Exit(True);
  end;
end;

function TRefTypeScan.RoutineClassFacts(const ANode: TTSNode): TTypeFacts;
begin
  Result:= Default(TTypeFacts);
  var Outer: TTSNode:= Default(TTSNode);
  var P: TTSNode:= ANode;
  while not P.IsNull do
  begin
    if P.NodeType = NODE_DEFPROC then Outer:= P;
    P:= P.Parent;
  end;
  if Outer.IsNull or Outer.ChildByField(FIELD_HEADER).IsNull then Exit;
  var Name: TTSNode:= Outer.ChildByField(FIELD_HEADER).ChildByField(FIELD_NAME);
  if Name.IsNull or Name.ChildByField(FIELD_LHS).IsNull then Exit;
  Result:= FactsOfName(Text(Name.ChildByField(FIELD_LHS)));
end;

function TRefTypeScan.BodyNames(const ABody: TTSNode; const AWords: array of string): Boolean;
begin
  Result:= False;
  var Up: string:= Text(ABody).ToUpper;
  for var W: string in AWords do
    if Up.Contains(W) then Exit(True);
end;

procedure TRefTypeScan.AddTouch(const ANode: TTSNode; AIsCall: Boolean; const AText: string; ATarget: Int64);
begin
  var T: TThreadTouch:= Default(TThreadTouch);
  T.IsCall   := AIsCall;
  T.StartLine:= Integer(ANode.StartPoint.Row) + 1;
  T.StartCol := Integer(ANode.StartPoint.Column) + 1;
  T.EndLine  := Integer(ANode.EndPoint.Row) + 1;
  T.EndCol   := Integer(ANode.EndPoint.Column) + 1;
  T.Text     := AText;
  T.Target   := ATarget;
  FTouches.Add(T);
end;

procedure TRefTypeScan.AddAccess(const ANode: TTSNode; const ATypeName, ARoot: string);
begin
  var Quoted: string:= TRegEx.Replace(Text(ANode), '\s+', ' ');
  if Quoted.Length > MAX_QUOTED_EXPR then Quoted:= Quoted.Substring(0, MAX_QUOTED_EXPR) + '...';
  if SameText(ATypeName, ARoot) then AddTouch(ANode, False, Format('%s (%s)', [Quoted, ARoot]), 0)
  else AddTouch(ANode, False, Format('%s (%s, a %s)', [Quoted, ATypeName, ARoot]), 0);
end;

procedure TRefTypeScan.CollectDot(const ANode: TTSNode);
var
  Fact: TRefFact;
begin
  var Lhs: TTSNode:= ANode.ChildByField(FIELD_LHS);
  var Rhs: TTSNode:= ANode.ChildByField(FIELD_RHS);
  if (not Rhs.IsNull) and FactAt(Rhs, Fact) then
  begin
    if Fact.CallTarget > 0 then AddTouch(Rhs, True, Text(Rhs), Fact.CallTarget);
    { A member the project declares is project code: a plain field is no UI access and a
      method is followed as a call. Only an inherited, library member is the UI's own. }
    if Fact.MemberSym = 0 then
    begin
      var Member: string:= Text(Rhs).ToLower;
      var IsClassRef: Boolean:= (not Lhs.IsNull) and SameText(Member, CREATE_NAME) and (FWithDepth = 0);
      var TypeName: string:= '';
      var Root: string;
      if SameText(Text(Lhs), SELF_WORD) then
      begin
        Root    := UiRootOf(FSelfFacts);
        TypeName:= FSelfFacts.Name;
      end
      else
      begin
        Root:= UiGlobalRoot(Lhs);
        if Root <> '' then TypeName:= Root
        else
        begin
          var Recv: TExprType:= StaticType(Lhs);
          if Recv.Known then
          begin
            Root    := UiRootOf(Recv.Facts);
            TypeName:= Recv.Facts.Name;
          end
          else if IsClassRef then
          begin
            var Written: TTypeFacts:= WrittenType(Lhs);
            Root    := UiRootOf(Written);
            TypeName:= Written.Name;
          end;
        end;
      end;
      var Safe: Boolean:= False;
      for var S: string in UI_SAFE_MEMBERS do
        if S = Member then Safe:= True;
      if Root = ROOT_APPLICATION_NAME then
        for var S: string in UI_SAFE_APP_MEMBERS do
          if S = Member then Safe:= True;
      if (Root <> '') and not Safe then
      begin
        AddAccess(ANode, TypeName, Root);
        Exit;
      end;
    end;
  end;
  CollectThreadCode(Lhs);
end;

procedure TRefTypeScan.CollectBare(const ANode: TTSNode);
var
  Fact: TRefFact;
begin
  if not FactAt(ANode, Fact) then Exit;
  if Fact.CallTarget > 0 then
  begin
    AddTouch(ANode, True, Text(ANode), Fact.CallTarget);
    Exit;
  end;
  if (Fact.MemberSym > 0) or (FWithDepth > 0) then Exit;
  var Root: string:= UiRootOf(FSelfFacts);
  if (Root <> '') and IsUiMember(Text(ANode), FSelfFacts) then AddAccess(ANode, FSelfFacts.Name, Root);
end;

procedure TRefTypeScan.CollectThreadCode(const ANode: TTSNode);
begin
  if ANode.IsNull then Exit;
  var NT: string:= ANode.NodeType;
  { A nested routine runs when called: the call edge says so. A lambda nobody is proven to
    start on a thread stays out, and one passed to a thread start is an entry of its own. }
  if (NT = NODE_LAMBDA) or (NT = NODE_DEFPROC) then Exit;
  if NT = NODE_DOT then
  begin
    CollectDot(ANode);
    Exit;
  end;
  if NT = TYPE_NODE_ID then
  begin
    CollectBare(ANode);
    Exit;
  end;
  if NT = NODE_CALL then
  begin
    var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
    var Callee: string:= '';
    if (not Ent.IsNull) and (Ent.NodeType = TYPE_NODE_ID) then Callee:= Text(Ent)
    else if (not Ent.IsNull) and (Ent.NodeType = NODE_DOT) then Callee:= Text(Ent.ChildByField(FIELD_RHS));
    for var M: string in MARSHAL_CALLS do
      if SameText(M, Callee) then Exit;
  end;
  var IsWith: Boolean:= NT = NODE_WITH;
  if IsWith then Inc(FWithDepth);
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
    CollectThreadCode(ANode.NamedChild(I));
  if IsWith then Dec(FWithDepth);
end;

procedure TRefTypeScan.CollectBody(const ABody: TTSNode);
begin
  FTouches.Clear;
  FSelfFacts:= RoutineClassFacts(ABody);
  for var I: Integer:= 0 to Integer(ABody.NamedChildCount) - 1 do
    CollectThreadCode(ABody.NamedChild(I));
end;

function TRefTypeScan.FindDefProc(const ANode: TTSNode; ALine: Integer): TTSNode;
begin
  Result:= Default(TTSNode);
  if ANode.IsNull or (Integer(ANode.StartPoint.Row) + 1 > ALine) or (Integer(ANode.EndPoint.Row) + 1 < ALine) then Exit;
  if ANode.NodeType = NODE_DEFPROC then Result:= ANode;
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
  begin
    var Inner: TTSNode:= FindDefProc(ANode.NamedChild(I), ALine);
    if not Inner.IsNull then Exit(Inner);
  end;
end;

function TRefTypeScan.SwitchToFile(AFileId: Int64): Boolean;
begin
  Result:= False;
  var Path: string:= FStore.GetFilePath(AFileId);
  if Path = '' then Exit;
  var PF: TParsedFile:= TAstParseCache.Get(Path);
  if PF.Tree = nil then Exit;
  FFileId:= AFileId;
  FPath  := Path;
  FSrc   := PF.Src;
  LoadRefs(AFileId);
  Result:= True;
end;

function TRefTypeScan.RoutineFacts(AId: Int64): TRoutineThreadFacts;
begin
  if FRoutineFacts.TryGetValue(AId, Result) then Exit;
  Result:= Default(TRoutineThreadFacts);
  var Sym: TSymbol:= SymbolOf(AId);
  if (Sym.FileId > 0) and (Sym.ImplStartLine > 0) then
  begin
    var SavedFile : Int64     := FFileId;
    var SavedPath : string    := FPath;
    var SavedSrc  : TBytes    := FSrc;
    var SavedSelf : TTypeFacts:= FSelfFacts;
    var SavedWith : Integer   := FWithDepth;
    var SavedTouch: TArray<TThreadTouch>:= FTouches.ToArray;
    try
      var Same: Boolean:= Sym.FileId = FFileId;
      if Same or SwitchToFile(Sym.FileId) then
      begin
        FWithDepth:= 0;
        var Def : TTSNode:= FindDefProc(TAstParseCache.Get(FPath).Tree.RootNode, Sym.ImplStartLine);
        var Body: TTSNode:= if Def.IsNull then Default(TTSNode) else Def.ChildByField(FIELD_BODY);
        if (not Body.IsNull) and not (BodyNames(Body, GUARD_WORDS) or BodyNames(Body, SELF_MARSHAL_WORDS)) then
        begin
          CollectBody(Body);
          for var T: TThreadTouch in FTouches do
            if T.IsCall then Result.Callees:= Result.Callees + [T.Target]
            else if Result.Witness = '' then
              Result.Witness:= Format('%s at %s:%d', [T.Text, ExtractFileName(FPath), T.StartLine]);
        end;
      end;
    finally
      if FFileId <> SavedFile then
      begin
        LoadRefs(SavedFile);
        FFileId:= SavedFile;
      end;
      FPath:= SavedPath;
      FSrc := SavedSrc;
      FSelfFacts:= SavedSelf;
      FWithDepth:= SavedWith;
      FTouches.Clear;
      FTouches.AddRange(SavedTouch);
    end;
  end;
  FRoutineFacts.Add(AId, Result);
end;

function TRefTypeScan.ReachOf(ATarget: Int64; out AReach: TThreadReach): Boolean;
type
  TStep = record
    Id  : Int64;
    Path: string;
  end;

  function ShortName(const AQName: string): string;
  begin
    var Parts: TArray<string>:= AQName.Split([DOT_SEP]);
    Result:= if Length(Parts) >= 2 then Parts[High(Parts) - 1] + DOT_SEP + Parts[High(Parts)] else AQName;
  end;

begin
  if FReach.TryGetValue(ATarget, AReach) then Exit(AReach.Witness <> '');
  AReach:= Default(TThreadReach);
  var Visited: TDictionary<Int64, Boolean>:= TDictionary<Int64, Boolean>.Create;
  try
    var Step: TStep;
    Step.Id  := ATarget;
    Step.Path:= ShortName(SymbolOf(ATarget).QualifiedName);
    var Frontier: TArray<TStep>:= [Step];
    Visited.Add(ATarget, True);
    for var Hop: Integer:= 1 to MAX_THREAD_HOPS do
    begin
      var Next: TArray<TStep>:= nil;
      for var St: TStep in Frontier do
      begin
        var Facts: TRoutineThreadFacts:= RoutineFacts(St.Id);
        if Facts.Witness <> '' then
        begin
          AReach.Path   := St.Path;
          AReach.Witness:= Facts.Witness;
          FReach.Add(ATarget, AReach);
          Exit(True);
        end;
        for var C: Int64 in Facts.Callees do
        begin
          if Visited.ContainsKey(C) then Continue;
          Visited.Add(C, True);
          var N: TStep;
          N.Id  := C;
          N.Path:= St.Path + ' -> ' + ShortName(SymbolOf(C).QualifiedName);
          Next:= Next + [N];
        end;
      end;
      Frontier:= Next;
    end;
  finally
    Visited.Free;
  end;
  FReach.Add(ATarget, AReach);
  Result:= False;
end;

procedure TRefTypeScan.EmitThreadFinding(const ATouch: TThreadTouch; const AMessage: string);
begin
  var Key: Int64:= PosKey(ATouch.StartLine, ATouch.StartCol);
  if FEmitted.ContainsKey(Key) then Exit;
  FEmitted.Add(Key, True);
  var F: TLintFinding:= Default(TLintFinding);
  F.RuleId   := UI_ACCESS_IN_THREAD_TYPED_RULE;
  F.Severity := SEV_WARNING;
  F.Message  := AMessage;
  F.FileId   := FFileId;
  F.FilePath := FPath;
  F.StartLine:= ATouch.StartLine;
  F.StartCol := ATouch.StartCol;
  F.EndLine  := ATouch.EndLine;
  F.EndCol   := ATouch.EndCol;
  FFindings.Add(F);
end;

procedure TRefTypeScan.EmitReach(const ATouch: TThreadTouch; const AEntry: string);
var
  Reach: TThreadReach;
begin
  if ReachOf(ATouch.Target, Reach) then
    EmitThreadFinding(ATouch, Format('%s runs on a worker thread and reaches UI code: %s -> %s, which touches %s ' +
      '-- marshal the call through Synchronize or Queue', [AEntry, AEntry, Reach.Path, Reach.Witness]));
end;

procedure TRefTypeScan.CheckThreadBody(const ABody: TTSNode; const AEntry: string);
begin
  if ABody.IsNull or BodyNames(ABody, GUARD_WORDS) then Exit;
  var SavedSelf: TTypeFacts:= FSelfFacts;
  CollectBody(ABody);
  var Touches: TArray<TThreadTouch>:= FTouches.ToArray;
  for var T: TThreadTouch in Touches do
    if T.IsCall then EmitReach(T, AEntry)
    else EmitThreadFinding(T, Format('%s runs on a worker thread and touches %s -- VCL/FMX is not thread-safe; ' +
      'marshal it through Synchronize or Queue', [AEntry, T.Text]));
  FSelfFacts:= SavedSelf;
end;

procedure TRefTypeScan.CheckExecuteEntry(const ANode: TTSNode);
begin
  var Hdr: TTSNode:= ANode.ChildByField(FIELD_HEADER);
  if Hdr.IsNull then Exit;
  var Name: TTSNode:= Hdr.ChildByField(FIELD_NAME);
  if Name.IsNull or (not SameText(Text(Name.ChildByField(FIELD_RHS)), EXECUTE_NAME)) then Exit;
  var Cls: string:= Text(Name.ChildByField(FIELD_LHS));
  if (not FactsOfName(Cls).HasAncestor(THREAD_ROOT)) or ProjectOwnsName(THREAD_ROOT) then Exit;
  CheckThreadBody(ANode.ChildByField(FIELD_BODY), LeafOf(Cls) + DOT_SEP + EXECUTE_NAME);
end;

procedure TRefTypeScan.CheckThreadStart(const ANode: TTSNode);
const
  ROUTINE_KINDS = [skMethod, skFunction, skProcedure];
var
  Fact: TRefFact;
begin
  var Ent : TTSNode:= ANode.ChildByField(FIELD_ENTITY);
  var Args: TTSNode:= ANode.ChildByField(FIELD_ARGS);
  { A generic call, TTask.Future<T>(..), has no exprDot at its head: the written name decides. }
  if Ent.IsNull or Args.IsNull or (Ent.NodeType = TYPE_NODE_ID) then Exit;
  var Written: string:= TRegEx.Replace(Text(Ent), GENERIC_ARGS_RX, '');
  Written:= Written.Replace('&', '').Replace(' ', '').ToLower;
  var Parts: TArray<string>:= Written.Split([DOT_SEP]);
  if Length(Parts) < 2 then Exit;
  var Start: string:= Parts[High(Parts) - 1] + DOT_SEP + Parts[High(Parts)];
  var Known: Boolean:= False;
  for var S: string in THREAD_STARTS do
    if S = Start then Known:= True;
  { A project class of that name is not the RTL's. }
  if (not Known) or ProjectOwnsName(Parts[High(Parts) - 1]) then Exit;
  var Entry: string:= TRegEx.Replace(Text(Ent), '\s+', '') + ' body';
  for var I: Integer:= 0 to Integer(Args.NamedChildCount) - 1 do
  begin
    var Arg: TTSNode:= Args.NamedChild(I);
    if Arg.NodeType = NODE_LAMBDA then
    begin
      var Body: TTSNode:= Arg.ChildByField(FIELD_BODY);
      CheckThreadBody(if Body.IsNull then Arg else Body, Entry);
      Continue;
    end;
    var Last: TTSNode:= if Arg.NodeType = NODE_DOT then Arg.ChildByField(FIELD_RHS) else Arg;
    if Last.IsNull or (Last.NodeType <> TYPE_NODE_ID) or (not FactAt(Last, Fact)) or (Fact.MemberSym <= 0) then Continue;
    if SymbolOf(Fact.MemberSym).Kind in ROUTINE_KINDS then
    begin
      var T: TThreadTouch:= Default(TThreadTouch);
      T.IsCall   := True;
      T.StartLine:= Integer(Arg.StartPoint.Row) + 1;
      T.StartCol := Integer(Arg.StartPoint.Column) + 1;
      T.EndLine  := Integer(Arg.EndPoint.Row) + 1;
      T.EndCol   := Integer(Arg.EndPoint.Column) + 1;
      T.Target   := Fact.MemberSym;
      EmitReach(T, Entry);
    end;
  end;
end;

procedure TRefTypeScan.Walk(const ANode: TTSNode);
begin
  if ANode.IsNull then Exit;
  var NT: string:= ANode.NodeType;
  if NT = NODE_CALL then
  begin
    CheckCast(ANode);
    if Wants(ARGUMENT_NARROWS_RULE) then CheckArguments(ANode);
  end
  else if IsAsNode(ANode) then CheckCast(ANode)
  else if NT = NODE_BINARY then CheckIs(ANode)
  else if (NT = NODE_ASSIGN) and Wants(INTERFACE_HOLDER_RULE) then CheckAssign(ANode);
  if Wants(UI_ACCESS_IN_THREAD_TYPED_RULE) then
  begin
    if NT = NODE_DEFPROC then CheckExecuteEntry(ANode)
    else if NT = NODE_CALL then CheckThreadStart(ANode);
  end;
  var IsWith: Boolean:= NT = NODE_WITH;
  if IsWith and Wants(WITH_ON_TEMPORARY_RULE) then CheckWith(ANode);
  if IsWith then Inc(FWithDepth);
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
    Walk(ANode.NamedChild(I));
  if IsWith then Dec(FWithDepth);
end;

procedure TRefTypeScan.ScanFile(AFileId: Int64);
begin
  FFileId:= AFileId;
  FPath  := FStore.GetFilePath(AFileId);
  if FPath = '' then Exit;
  var PF: TParsedFile:= TAstParseCache.Get(FPath);
  if PF.Tree = nil then Exit;
  FSrc:= PF.Src;
  LoadRefs(AFileId);
  if FRefs.Count = 0 then Exit;
  FWithDepth:= 0;
  FEmitted.Clear;
  FGuards.Clear;
  if Wants(UNSAFE_TYPECAST_RULE) then CollectGuards(PF.Tree.RootNode);
  Walk(PF.Tree.RootNode);
end;

function RefStaticTypeAt(const AStore: ISymbolStore; AFileId: Int64; ALine, ACol: Integer; const AName: string;
  out ATypeLeaf: string): Boolean;
var
  Q: TFDQuery;
begin
  Result   := False;
  ATypeLeaf:= '';
  if (AStore = nil) or (AFileId <= 0) or (AStore is not TSQLiteSymbolStore) then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
    Q.SQL.Text  := 'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = ''ref_types''';
    Q.Open;
    if Q.Eof then Exit;
    Q.Close;
    Q.SQL.Text:= 'SELECT t.type_qname FROM refs r JOIN ref_types t ON t.ref_id = r.id ' +
                 'WHERE r.file_id = :f AND r.start_line = :l AND r.start_col = :c AND r.name_text = :n COLLATE NOCASE LIMIT 1';
    Q.ParamByName('f').AsLargeInt  := AFileId;
    Q.ParamByName('l').AsInteger   := ALine;
    Q.ParamByName('c').AsInteger   := ACol;
    Q.ParamByName('n').AsWideString:= AName;
    Q.Open;
    if Q.Eof then Exit;
    ATypeLeaf:= LeafOf(Q.Fields[0].AsString);
    Result   := True;
  finally
    Q.Free;
  end;
end;

procedure TRefTypeScan.Attach(AFileId: Int64; const ASrc: TBytes);
begin
  FFileId   := AFileId;
  FSrc      := ASrc;
  FWithDepth:= 0;
  LoadRefs(AFileId);
end;

function TRefTypeScan.ExprTypeLeaf(const ANode: TTSNode; out ALeaf: string): Boolean;
begin
  ALeaf := '';
  Result:= False;
  if ANode.IsNull then Exit;
  var Inner: TTSNode:= ANode;
  while (not Inner.IsNull) and (Inner.NodeType = NODE_PARENS) do Inner:= Inner.NamedChild(0);
  if Inner.IsNull then Exit;
  if InWithScope(ANode) then Exit(WithProofLeaf(Inner, ALeaf));
  var T: TExprType:= StaticType(ANode);
  if T.Known and (T.Facts.Name <> '') then
  begin
    ALeaf := LeafOf(T.Facts.Name);
    Exit(True);
  end;
  { A type the store has no class for (a record, a simple type) still has its recorded name. }
  var Fact: TRefFact;
  var Name: TTSNode:= LastHopName(Inner);
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) or not FactAt(Name, Fact) or (Fact.TypeQName = '') then Exit;
  ALeaf := LeafOf(Fact.TypeQName);
  Result:= ALeaf <> '';
end;

function TRefTypeScan.InWithScope(const ANode: TTSNode): Boolean;
begin
  Result:= False;
  var P: TTSNode:= ANode.Parent;
  while not P.IsNull do
  begin
    if P.NodeType = NODE_WITH then
    begin
      { The first subject is evaluated outside its own with; every other child is inside. The
        grammar's keywords are named children (kWith first). A comment before the subject reads as
        the first child: that errs towards unknown. }
      var First: TTSNode:= Default(TTSNode);
      for var I: Integer:= 0 to Integer(P.NamedChildCount) - 1 do
      begin
        First:= P.NamedChild(I);
        if not First.NodeType.StartsWith(KEYWORD_NODE_PREFIX) then Break;
      end;
      if First.IsNull or (ANode.StartByte < First.StartByte) or (ANode.EndByte > First.EndByte) then Exit(True);
    end;
    P:= P.Parent;
  end;
end;

function TRefTypeScan.LastHopName(const AInner: TTSNode): TTSNode;
begin
  Result:= Default(TTSNode);
  if AInner.NodeType = TYPE_NODE_ID then Result:= AInner
  else if AInner.NodeType = NODE_DOT then Result:= AInner.ChildByField(FIELD_RHS)
  else if AInner.NodeType = NODE_CALL then
  begin
    var Ent: TTSNode:= AInner.ChildByField(FIELD_ENTITY);
    if Ent.IsNull then Exit;
    if Ent.NodeType = TYPE_NODE_ID then Result:= Ent
    else if Ent.NodeType = NODE_DOT then Result:= Ent.ChildByField(FIELD_RHS);
  end;
end;

function TRefTypeScan.WithProofLeaf(const AInner: TTSNode; out ALeaf: string): Boolean;
var
  Fact: TRefFact;
begin
  ALeaf := '';
  Result:= False;
  var Name: TTSNode:= LastHopName(AInner);
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) or not FactAt(Name, Fact) then Exit;
  if (Fact.TypeQName = '') or (Fact.Via = VIA_CAST) then Exit;
  { The resolver's with verdict decided the chain's leftmost name, unless that name is a cast head:
    the cast rung takes any call whose name is a type, without asking the with scope. }
  var Root: TTSNode:= AInner;
  while not Root.IsNull do
    if Root.NodeType = NODE_DOT then Root:= Root.ChildByField(FIELD_LHS)
    else if Root.NodeType = NODE_CALL then Root:= Root.ChildByField(FIELD_ENTITY)
    else Break;
  if Root.IsNull or (Root.NodeType <> TYPE_NODE_ID) then Exit;
  if not SameText(Text(Root), SELF_WORD) then
  begin
    var RootFact: TRefFact;
    if (not FactAt(Root, RootFact)) or (RootFact.TypeQName = '') or (RootFact.Via = VIA_CAST) then Exit;
  end;
  ALeaf := LeafOf(Fact.TypeQName);
  Result:= ALeaf <> '';
end;

function TRefTypeScan.DescentOf(const ATypeLeaf, AAncestorLeaf: string): TDescent;
begin
  Result:= tdUnknown;
  var F: TTypeFacts:= FactsOfName(ATypeLeaf);
  if (not F.Known) or not (F.IsClass or F.IsIntf) then Exit;
  if F.HasAncestor(LeafOf(AAncestorLeaf).ToLower) then Exit(tdYes);
  if F.Complete and not F.Homonym then Result:= tdNo;
end;

constructor TExprTypeReader.Create(const AStore, ALibStore: ISymbolStore; AFileId: Int64; const ASrc: TBytes);
begin
  inherited Create;
  if (AStore = nil) or (AStore is not TSQLiteSymbolStore) then Exit;
  FScan := TRefTypeScan.Create(AStore, ALibStore, nil);
  FReady:= TRefTypeScan(FScan).HasFact;
  if FReady and (AFileId > 0) then TRefTypeScan(FScan).Attach(AFileId, ASrc);
end;

destructor TExprTypeReader.Destroy;
begin
  FScan.Free;
  inherited Destroy;
end;

function TExprTypeReader.TypeLeafOf(const ANode: TTSNode; out ALeaf: string): Boolean;
begin
  ALeaf := '';
  Result:= FReady and TRefTypeScan(FScan).ExprTypeLeaf(ANode, ALeaf);
end;

function TExprTypeReader.Descends(const ATypeLeaf, AAncestorLeaf: string): TDescent;
begin
  Result:= tdUnknown;
  if FScan <> nil then Result:= TRefTypeScan(FScan).DescentOf(ATypeLeaf, AAncestorLeaf);
end;

function TypeDescendsFrom(const AStore, ALibStore: ISymbolStore; const ATypeLeaf, AAncestorLeaf: string): TDescent;
begin
  var R: TExprTypeReader:= TExprTypeReader.Create(AStore, ALibStore, 0, nil);
  try
    Result:= R.Descends(ATypeLeaf, AAncestorLeaf);
  finally
    R.Free;
  end;
end;

function StaticTypeLeafOfExpr(const AStore: ISymbolStore; AFileId: Int64; const ANode: TTSNode; const ASrc: TBytes;
  out ALeaf: string): Boolean;
begin
  var R: TExprTypeReader:= TExprTypeReader.Create(AStore, nil, AFileId, ASrc);
  try
    Result:= R.TypeLeafOf(ANode, ALeaf);
  finally
    R.Free;
  end;
end;
function RefTypeRuleDefaultOff(const ARuleId: string): Boolean;
begin
  Result:= False;
  for var S: string in REF_TYPE_RULES_OFF do
    if SameText(S, ARuleId) then Exit(True);
end;

function CollectRefTypeRules(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>;
  AOnlyFileId: Int64): TArray<TLintFinding>;
begin
  Result:= nil;
  if (AStore = nil) or (Length(ARules) = 0) or (AStore is not TSQLiteSymbolStore) then Exit;
  var Scan: TRefTypeScan:= TRefTypeScan.Create(AStore, ALibStore, ARules);
  try
    if not Scan.HasFact then Exit;
    if AOnlyFileId > 0 then Scan.ScanFile(AOnlyFileId)
    else
      for var Id: Int64 in AStore.GetAllFileIds do
      begin
        Scan.ScanFile(Id);
        TAstParseCache.Clear; { a whole-project walk: one tree at a time }
      end;
    Result:= Scan.Findings;
  finally
    Scan.Free;
  end;
end;

end.
