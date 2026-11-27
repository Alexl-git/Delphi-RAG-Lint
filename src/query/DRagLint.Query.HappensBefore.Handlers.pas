unit DRagLint.Query.HappensBefore.Handlers;

{ drag-lint 1.52 -- lane HBEVORD: ordered event handlers (owner ruling HB5, spec
  docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 5.7).

  A DFM-bound event handler of a form that the program block creates with Application.CreateForm is an
  ORDERED root: it runs only after the program-block prefix (every top-level statement before
  Application.Run, which itself runs after every unit initialization). The solver then takes the
  state just before `Application.Run` as the handler's entry state instead of False.

  The ordering is a NAME heuristic the owner accepted knowingly; every answer that relies on it carries
  the reason code relied-on-handler-order and names the handler and its binding. A handler stays
  UNORDERED (entry False, as every escaped routine) when any of these holds -- the first one found is
  the WhyNot text:
    1. no program (.dpr) is known, or its program block has no unconditional top-level Application.Run;
    2. the prefix can run handlers itself: a top-level statement before Application.Run names a message
       pump or a direct fire (HB_PREFIX_PUMP_WORDS: ShowModal, ProcessMessages, ...);
    3. the routine is not a method of a class with a DFM binding to it;
    4. a binding uses an event of the OnCreate family, or the method has an OnCreate-family name
       (HB_UNORDERED_EVENTS, HB_UNORDERED_EVENT_PREFIXES, HB_UNORDERED_HANDLER_NAMES): these fire
       inside CreateForm or before the message loop;
    5. the code references the method (a call, an address, an `OnX := Method` assignment): it can run
       outside the message loop;
    6. the form class is not created by an unconditional top-level Application.CreateForm before
       Application.Run (a form created at run time: its handlers are ordered only after the routine
       that creates it, which 1.52 does not prove).

  Known limits (recorded in the lane report): a message pump inside a routine the prefix calls, or in a
  unit initialization, is not seen; a descendant of the created class created at run time shares the
  inherited handler only when the binding names the descendant (then rule 6 applies).

  Read-only; nothing is persisted (no extractor change). Every doubt answers "unordered". }

interface

uses
  System.Generics.Collections
, DRagLint.Charts.Index
, DRagLint.Query.HappensBefore.Types
  ;

const
  /// <summary>Event properties whose handlers fire inside Application.CreateForm (DFM streaming,
  /// Loaded, the first show / resize / paint), during destruction, or from a timer that the prefix
  /// can already have started. A handler bound to one of them is never ordered (ruling HB5: the
  /// OnCreate family, excluded by name). Compared case-insensitively.</summary>
  HB_UNORDERED_EVENTS: array[0..19] of string = ('OnCreate', 'OnShow', 'OnActivate', 'OnResize', 'OnPaint',
    'OnConstrainedResize', 'OnCanResize', 'OnAlignPosition', 'OnAlignInsertBefore', 'OnAfterMonitorDpiChanged',
    'OnBeforeMonitorDpiChanged', 'OnDestroy', 'OnTimer', 'OnLogin', 'OnCalcFields', 'OnNewRecord', 'OnFilterRecord',
    'OnGetText', 'OnSetText', 'OnValidate');

  /// <summary>Event-name prefixes of the data-access events (BeforeOpen, AfterConnect, OnAfterScroll ...):
  /// a dataset or connection that is Active / Connected in the form file fires them while CreateForm
  /// streams it. Compared case-insensitively.</summary>
  HB_UNORDERED_EVENT_PREFIXES: array[0..3] of string = ('Before', 'After', 'OnBefore', 'OnAfter');

  /// <summary>Handler method names of the OnCreate family (the IDE's default names): never ordered,
  /// whatever event the form file binds them to. Compared case-insensitively.</summary>
  HB_UNORDERED_HANDLER_NAMES: array[0..9] of string = ('FormCreate', 'FormShow', 'FormActivate', 'FormResize',
    'FormPaint', 'FormConstrainedResize', 'FormCanResize', 'FormDestroy', 'DataModuleCreate', 'DataModuleDestroy');

  /// <summary>Words that, in a top-level statement of the program block before Application.Run, let an
  /// event handler run inside the prefix (a modal or explicit message loop, a dialog, a direct fire).
  /// One of them makes every handler of that program unordered. Whole words, case-insensitive.</summary>
  HB_PREFIX_PUMP_WORDS: array[0..7] of string = ('ShowModal', 'ProcessMessages', 'HandleMessage', 'MessageDlg',
    'ShowMessage', 'MessageBox', 'Execute', 'Click');

type
  /// <summary>How one event handler is ordered in one program (ruling HB5).</summary>
  /// <remarks>
  /// Ordered = True only when every unordered rule of the unit header failed to hold; then
  /// RunSite is the top-level `Application.Run` statement of the program block and CreateSite the
  /// CreateForm statement of the handler's form. WhyNot is '' exactly when Ordered.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Handlers.pas) ?, DRagLint.Query.HappensBefore.Handlers.HbPrefixMissText (DRagLint.Query.HappensBefore.Handlers.pas) ?, DRagLint.Query.HappensBefore.Handlers.HbReliedText (DRagLint.Query.HappensBefore.Handlers.pas) ?, DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf (DRagLint.Query.HappensBefore.Handlers.pas), DRagLint.Query.HappensBefore.TSolver.HandlerOrder (DRagLint.Query.HappensBefore.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Handlers</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbHandlerOrder = record
    /// <summary>symbols.id of the handler method.</summary>
    RoutineId: Int64;
    /// <summary>QName of the handler ('' when the id is no method).</summary>
    Handler: string;
    /// <summary>The class that declares the handler ('' when none).</summary>
    FormClass: string;
    /// <summary>Every DFM binding, `Form.Control.Event`, ', '-joined ('' for none).</summary>
    FiredBy: string;
    /// <summary>The program (name) the order was asked for ('' when unknown).</summary>
    ProgramName: string;
    /// <summary>True: the handler runs only after the program-block prefix of ProgramName.</summary>
    Ordered: Boolean;
    /// <summary>The CreateForm statement of FormClass in the program block (Line 0 when none).</summary>
    CreateSite: THbSite;
    /// <summary>The Application.Run statement of the program block (Line 0 when none).</summary>
    RunSite: THbSite;
    /// <summary>Why the handler is not ordered; '' when Ordered.</summary>
    WhyNot: string;
  end;

  /// <summary>Answers "is this event handler ordered after the program-block prefix?" for the
  /// check-init solver, caching what one program and one form share.</summary>
  /// <remarks>
  /// Owns its caches, not the index. Not thread-safe (the shared parse cache).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.pas) ?, DRagLint.Query.HappensBefore.TSolver.Create (DRagLint.Query.HappensBefore.pas)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbHandlerOrderer = class
  strict private
    type
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Handlers.pas) ?, DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ProgramFacts (DRagLint.Query.HappensBefore.Handlers.pas) ?, DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ReadProgram (DRagLint.Query.HappensBefore.Handlers.pas)</para>
      /// <para>Used in units: DRagLint.Query.HappensBefore.Handlers</para>
      /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf"/>
      /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount"/>
      /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Create"/>
      /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Destroy"/>
      /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      TProgramFacts = record
        Name: string;
        Path: string;
        Run: THbSite;
        Pump: string;
        CreateClasses: TArray<string>;
        CreateSites: TArray<THbSite>;
      end;
    var
      FIndex: TChartsIndex;
      FPrograms: TArray<TProgramFacts>;
      FProgramIds: TArray<Int64>;
      FLines: TDictionary<string, TArray<string>>;
    /// <param name="pProgramBlockId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TProgramFacts -- Observed:
    /// ReadProgram(pProgramBlockId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf (DRagLint.Query.HappensBefore.Handlers.pas), DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.RunSiteOf (DRagLint.Query.HappensBefore.Handlers.pas)</para>
    /// <para>Calls: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ReadProgram</para>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ReadProgram"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ProgramFacts(pProgramBlockId: Int64): TProgramFacts;
    /// <param name="pProgramBlockId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TProgramFacts -- Observed: Default(TProgramFacts).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ProgramFacts (DRagLint.Query.HappensBefore.Handlers.pas)</para>
    /// <para>Calls: Default, DRagLint.Charts.Index.TChartsIndex.Query, DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.Query.HappensBefore.Handlers.CollectLeaves, DRagLint.Query.HappensBefore.Handlers.FindMainBlock, DRagLint.Query.HappensBefore.Handlers.LastSegment, DRagLint.Query.HappensBefore.Handlers.NodeText, DRagLint.Query.HappensBefore.Handlers.Squeezed, FileExists (+6 more)</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 46 lines (full implementation)</para>
    /// <para>SQL: reads FILES, SYMBOLS</para>
    /// <seealso cref="DRagLint.Charts.Index.TChartsIndex.Query"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.CharCol"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.CollectLeaves"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.FindMainBlock"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ReadProgram(pProgramBlockId: Int64): TProgramFacts;
    /// <param name="pPath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="pLine"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: if InRange(pLine, 1,
    /// Length(L)) then L[pLine - 1].</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf (DRagLint.Query.HappensBefore.Handlers.pas)</para>
    /// <para>Calls: FileExists, InRange</para>
    /// <para>Catches: EFileStreamError (swallowed); EInOutError (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Destroy"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SourceLine(const pPath: string; pLine: Integer): string;
    /// <summary><!-- drag-lint:auto sum -->Every DFM binding of pClass.pMethod: pBindings
    /// = `Form.Control.Event`, pEvents = the event names.</summary>
    /// <param name="pClass"><!-- drag-lint:auto type -->const string</param>
    /// <param name="pMethod"><!-- drag-lint:auto type -->const string</param>
    /// <param name="pBindings"><!-- drag-lint:auto type -->out TArray&lt;string&gt;</param>
    /// <param name="pEvents"><!-- drag-lint:auto type -->out TArray&lt;string&gt;</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: pBindings &lt;&gt; nil.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf (DRagLint.Query.HappensBefore.Handlers.pas)</para>
    /// <para>Calls: Copy, DRagLint.Charts.Index.TChartsIndex.Query, DRagLint.Query.HappensBefore.Handlers.Sq, DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.SourceLine, Trim</para>
    /// <para>SQL: reads FILES, REFS, SYMBOLS</para>
    /// <para>Mutates: pBindings (out), pEvents (out)</para>
    /// <seealso cref="DRagLint.Charts.Index.TChartsIndex.Query"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.Sq"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.SourceLine"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BindingsOf(const pClass, pMethod: string; out pBindings, pEvents: TArray<string>): Boolean;
    /// <summary><!-- drag-lint:auto sum -->References to the method from code: resolved
    /// refs of any kind but the DFM binding, call edges, and unresolved refs of the same
    /// name (a doubt counts).</summary>
    /// <param name="pRoutineId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="pMethod"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: if R.Count &gt; 0 then
    /// R[0].I('n').</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf (DRagLint.Query.HappensBefore.Handlers.pas)</para>
    /// <para>Calls: DRagLint.Charts.Index.TChartsIndex.Query, DRagLint.Query.HappensBefore.Handlers.Sq, IntToStr</para>
    /// <seealso cref="DRagLint.Charts.Index.TChartsIndex.Query"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.Sq"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CodeRefCount(pRoutineId: Int64; const pMethod: string): Integer;
  public
    /// <summary>Creates an orderer over an open index.</summary>
    /// <param name="pIndex">The project index; must stay open while the orderer lives. Not owned.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.TSolver.Create (DRagLint.Query.HappensBefore.pas)</para>
    /// <para>constructor</para>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Destroy"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ProgramFacts"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const pIndex: TChartsIndex);
    /// <summary>Frees the caches (not the index).</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ProgramFacts"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>The top-level `Application.Run` statement of a program block.</summary>
    /// <param name="pProgramBlockId">symbols.id of the program symbol (its main block).</param>
    /// <param name="pSite">Out: the statement start (1-based line and column, file of the program).</param>
    /// <returns>False when the id is no program or its block has no unconditional top-level
    /// Application.Run; the solver then asks no prefix state.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.TSolver.LoadPrograms (DRagLint.Query.HappensBefore.pas)</para>
    /// <para>Calls: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ProgramFacts</para>
    /// <para>Returns: pSite.Line &gt; 0</para>
    /// <para>Mutates: pSite (out)</para>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ProgramFacts"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Create"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function RunSiteOf(pProgramBlockId: Int64; out pSite: THbSite): Boolean;
    /// <summary>Judges one escaped routine against one program (rules of the unit header).</summary>
    /// <param name="pProgramBlockId">symbols.id of the program symbol; 0 = no program known.</param>
    /// <param name="pRoutineId">symbols.id of the routine (normally a dfm-event escaped root).</param>
    /// <returns>The order; Ordered = False with WhyNot set for every doubt. Never raises for an unknown id.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.TSolver.HandlerOrder (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.TSolver.RootReasons (DRagLint.Query.HappensBefore.pas)</para>
    /// <para>Calls: Default, DRagLint.Charts.Index.TChartsIndex.Query, DRagLint.Query.HappensBefore.Handlers.HbIsUnorderedEvent, DRagLint.Query.HappensBefore.Handlers.HbIsUnorderedHandlerName, DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf, DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount, DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.ProgramFacts, Format, IntToStr, SameText</para>
    /// <para>Returns: Default(THbHandlerOrder)</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 71 lines (full implementation)</para>
    /// <para>SQL: reads SYMBOLS</para>
    /// <seealso cref="DRagLint.Charts.Index.TChartsIndex.Query"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.HbIsUnorderedEvent"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.HbIsUnorderedHandlerName"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.BindingsOf"/>
    /// <seealso cref="DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.CodeRefCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function OrderOf(pProgramBlockId, pRoutineId: Int64): THbHandlerOrder;
  end;

  /// <summary>One call through a procedural slot (method pointer, event, callback parameter) that can
  /// run a routine: an indirect_edges row with the position of its call ref (1.56 B5, phase 3).</summary>
  /// <remarks>RefId 0 = the slot is never called in this index (a library event, a .dfm event the
  /// framework fires, a slot that is only stored): CallerId, Line and Col are then 0 and FilePath is ''.
  /// The row says "CAN run": every binding of a slot is paired with every call through it.</remarks>
  THbIndirectSite = record
    /// <summary>refs.id of the call through the slot; 0 = none.</summary>
    RefId: Int64;
    /// <summary>symbols.id of the routine that holds the call; 0 = none.</summary>
    CallerId: Int64;
    /// <summary>symbols.id of the routine that can run.</summary>
    TargetId: Int64;
    /// <summary>File of the call through the slot ('' when RefId is 0).</summary>
    FilePath: string;
    /// <summary>Line of the call through the slot (0 when RefId is 0).</summary>
    Line: Integer;
    /// <summary>Column of the call through the slot (0 when RefId is 0).</summary>
    Col: Integer;
    /// <summary>The name the call is written with (`FOnTick` of `FOnTick(Self)`); '' when RefId is 0.</summary>
    SlotName: string;
    /// <summary>indirect_edges.kind: method-pointer, event, callback-arg or dfm-event.</summary>
    Kind: string;
    /// <summary>The slot as written at the binding site.</summary>
    ViaText: string;
    /// <summary>files.id of the binding site; 0 = unknown.</summary>
    BindFileId: Int64;
    /// <summary>Line of the routine name at the binding site; 0 = unknown.</summary>
    BindLine: Integer;
    /// <summary>Column of the routine name at the binding site; 0 = unknown.</summary>
    BindCol: Integer;
    /// <summary>True for confidence `resolved`; False for a link matched by name only.</summary>
    Resolved: Boolean;
  end;

  /// <summary>Reads the indirect-call edges of the index (table indirect_edges, 1.56 B5) for the
  /// happens-before engine: who can run a routine through a procedural slot, which slots a routine
  /// calls through, and whether a routine that is named as a value runs ONLY through such calls.</summary>
  /// <remarks>
  /// Read-only. Owns its caches, not the index. Not thread-safe. On an index without the table every
  /// list is empty and OnlyThroughSlots is False, so a caller keeps its pre-1.56 answer.
  /// OnlyThroughSlots is a PROOF fact; every doubt answers False. It holds when all of these do:
  ///   1. every place that names the routine as a value is the binding site of an edge;
  ///   2. every edge has a call site in the index and is resolved (not matched by name);
  ///   3. the called slot is placed: a parameter or local of the calling routine, a field of its
  ///      class or a variable of its unit, or the one unit variable of that name in the index;
  ///   4. the slot is CLOSED: besides calls and assignments it is only read as `Assigned(Slot)`, no
  ///      unresolved reference carries its name, and a property over a field slot is only written;
  ///   5. the binding writes that very slot (the slot, a property over it, or the callee whose
  ///      parameter it is), so the value did not travel through another slot;
  ///   6. every call written with the slot's name (resolved to it, or unresolved) has an edge to the
  ///      routine -- a call the index did not pair with the binding could run it unseen.
  /// Not seen: a reference to the routine that the index could not resolve at all (the same blind
  /// spot the escape classifier has).
  /// </remarks>
  THbIndirectFacts = class
  strict private
    FIndex: TChartsIndex;
    FAvailable: Integer;
    FOf: TDictionary<Int64, TArray<THbIndirectSite>>;
    FIn: TDictionary<Int64, TArray<THbIndirectSite>>;
    FWhyNot: TDictionary<Int64, string>;
    FSlotWhy: TDictionary<Int64, string>;
    function Count(const pSql: string): Integer;
    function Ids(const pSql: string): TArray<Int64>;
    function ReadSites(const pWhere: string): TArray<THbIndirectSite>;
    function SlotOf(const pSite: THbIndirectSite): Int64;
    function PropertiesOver(pSlotId: Int64; out pComplete: Boolean): TArray<Int64>;
    function PropertyWhyNot(pPropertyId: Int64; const pSlotName: string): string;
    function SlotWhyNot(pSlotId: Int64): string;
    function BoundDirectly(const pSite: THbIndirectSite; pSlotId: Int64): Boolean;
    function UnpairedCalls(pTargetId, pSlotId: Int64): Integer;
    function UnboundNaming(pTargetId: Int64; const pSites: TArray<THbIndirectSite>): string;
    function SiteWhyNot(const pSite: THbIndirectSite): string;
    function ComputeWhyNot(pTargetId: Int64): string;
  public
    /// <summary>Binds the reader to an open index.</summary>
    /// <param name="pIndex">The project index; not owned, must outlive this object.</param>
    constructor Create(const pIndex: TChartsIndex);
    /// <summary>Frees the caches (never the index).</summary>
    destructor Destroy; override;
    /// <summary>True when the index has the indirect_edges table (written by a 1.56 indexer).</summary>
    /// <returns>False on an older index: every other method then answers empty / False.</returns>
    function Available: Boolean;
    /// <summary>Every edge that can run a routine, with and without a call site.</summary>
    /// <param name="pTargetId">symbols.id of the routine that can run.</param>
    /// <returns>Rows ordered by call position; empty when there is none.</returns>
    function SitesOf(pTargetId: Int64): TArray<THbIndirectSite>;
    /// <summary>Every call through a slot inside one routine, one row per routine it can run.</summary>
    /// <param name="pCallerId">symbols.id of the routine that holds the calls.</param>
    /// <returns>Rows ordered by call position; empty when there is none.</returns>
    function SitesIn(pCallerId: Int64): TArray<THbIndirectSite>;
    /// <summary>True when the routine, wherever it is named as a value, can run only through the
    /// call sites SitesOf lists (the six conditions of the class remarks).</summary>
    /// <param name="pTargetId">symbols.id of a routine.</param>
    /// <param name="pWhyNot">'' when True; else the first condition that failed, as a sentence part.</param>
    /// <returns>False on any doubt and on an index without the table.</returns>
    function OnlyThroughSlots(pTargetId: Int64; out pWhyNot: string): Boolean;
  end;

/// <summary>True when an event property name belongs to the OnCreate family (HB_UNORDERED_EVENTS or a
/// HB_UNORDERED_EVENT_PREFIXES prefix), or is empty / unknown ('?').</summary>
/// <param name="pEvent">The property name as the form file writes it, e.g. 'OnClick'.</param>
/// <returns>True = a handler bound to it is never ordered.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf (DRagLint.Query.HappensBefore.Handlers.pas)</para>
/// <para>Calls: CharInSet, DRagLint.Query.HappensBefore.Handlers.InList, Trim</para>
/// <para>Returns: False</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Handlers.InList"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbIsUnorderedEvent(const pEvent: string): Boolean;  // dl:ok unused-public-symbol@6826 -- REVIEWED 2026-11-17 v152 HBEVORD: HB5 contract; called by HandlersHarness.dpr (fixture, not in the project index) and by OrderOf

/// <summary>True when a handler method name is one of HB_UNORDERED_HANDLER_NAMES.</summary>
/// <param name="pName">The bare method name, e.g. 'FormCreate'.</param>
/// <returns>True = the handler is never ordered, whatever it is bound to.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.OrderOf (DRagLint.Query.HappensBefore.Handlers.pas)</para>
/// <para>Calls: DRagLint.Query.HappensBefore.Handlers.InList, Trim</para>
/// <para>Returns: InList(Trim(pName), HB_UNORDERED_HANDLER_NAMES)</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Handlers.InList"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbIsUnorderedHandlerName(const pName: string): Boolean;  // dl:ok unused-public-symbol@51a2 -- REVIEWED 2026-11-17 v152 HBEVORD: HB5 contract; called by HandlersHarness.dpr (fixture, not in the project index) and by OrderOf

/// <summary>The text an answer shows when a use relied on the order of pOrder: it names the handler,
/// its bindings and the program-block statements the order hangs on, and says it is a name heuristic.</summary>
/// <param name="pOrder">An Ordered handler order.</param>
/// <returns>One line, e.g. 'relies on handler order: hoMain.TMainForm.btnGoClick (fired by
/// MainForm.btnGo.OnClick) runs only after the program-block prefix of HandlersOrder (Application.Run at
/// HandlersOrder.dpr:17) -- name heuristic, OnCreate family excluded'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.TSolver.JudgeUse (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Calls: ExtractFileName, Format</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbReliedText(const pOrder: THbHandlerOrder): string;

/// <summary>The "why not SET" text of a use whose root is an ordered handler entered with the bit
/// False: the prefix of the program does not write the target on every path.</summary>
/// <param name="pOrder">An Ordered handler order.</param>
/// <param name="pTarget">The target's display name (e.g. 'GLate').</param>
/// <returns>One line naming the handler, its bindings, the program and the Application.Run statement.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.TSolver.RootReasons (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Calls: ExtractFileName, Format</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbPrefixMissText(const pOrder: THbHandlerOrder; const pTarget: string): string;

implementation

uses
  System.SysUtils
, System.Classes
, System.Math
, System.IOUtils
, System.RegularExpressions
, TreeSitter
, DRagLint.Diagnostics.ParseCache
  ;

const
  KIND_PROGRAM = 'program';
  KIND_LIBRARY = 'library';
  KIND_CLASS = 'class';
  { the main block sits at most this deep under the tree root (the solver uses the same bound) }
  MAIN_BLOCK_MAX_DEPTH = 3;
  RE_CREATE = '^Application\.CreateForm\(([A-Za-z_][A-Za-z0-9_.]*),';
  RE_RUN = '^Application\.Run(\(\))?;?$';
  HEURISTIC_NOTE = 'name heuristic, OnCreate family excluded';

{ ---------------------------------------------------------------------------------------------- }
{ small helpers                                                                                   }

function Sq(const pS: string): string;
begin
  Result:= QuotedStr(pS);
end;

function LastSegment(const pName: string): string;
begin
  var P:= LastDelimiter('.', pName);
  Result:= Copy(pName, P + 1, MaxInt);
end;

function InList(const pName: string; const pList: array of string): Boolean;
begin
  for var S in pList do
    if SameText(S, pName) then Exit(True);
  Result:= False;
end;

function NodeText(const pSrc: TBytes; const pNode: TTSNode): string;
begin
  Result:= '';
  if pNode.IsNull or (Integer(pNode.EndByte) > Length(pSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(pSrc, Integer(pNode.StartByte), Integer(pNode.EndByte - pNode.StartByte));
end;

{ The text of a statement with every white space removed (comments stay; they never match the patterns
  at the start). }
function Squeezed(const pText: string): string;
begin
  var SB:= TStringBuilder.Create;
  try
    for var C in pText do
      if C > ' ' then SB.Append(C);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ The statements of a container, keywords and comments left out (as the solver's StatementsOf). }
function StatementsOf(const pNode: TTSNode): TArray<TTSNode>;
begin
  Result:= nil;
  for var I:= 0 to pNode.NamedChildCount - 1 do
  begin
    var C:= pNode.NamedChild(I);
    var T:= C.NodeType;
    if (T <> '') and (T[1] = 'k') and (Length(T) > 1) and CharInSet(T[2], ['A'..'Z']) then Continue;
    if T = 'comment' then Continue;
    Result:= Result + [C];
  end;
end;

{ The main block of a program / library: the LAST `block` child of the program node. }
function FindMainBlock(const pRoot: TTSNode): TTSNode;
var
  Best: TTSNode;

  procedure Walk(const pNode: TTSNode; pDepth: Integer);
  begin
    if pDepth > MAIN_BLOCK_MAX_DEPTH then Exit;
    for var I:= 0 to pNode.NamedChildCount - 1 do
    begin
      var C:= pNode.NamedChild(I);
      if (C.NodeType = 'block') and ((pNode.NodeType = KIND_PROGRAM) or (pNode.NodeType = KIND_LIBRARY)) then
        Best:= C;
      Walk(C, pDepth + 1);
    end;
  end;

begin
  Best:= Default(TTSNode);
  Walk(pRoot, 0);
  Result:= Best;
end;

type
  { One statement of the main block in source order; Must = it runs every time the block completes
    normally (top level, nested begin..end, either part of try..finally -- the solver's MarkIsMust). }
  TLeaf = record
    Node: TTSNode;
    Must: Boolean;
  end;

procedure CollectLeaves(const pNode: TTSNode; pMust: Boolean; var pLeaves: TArray<TLeaf>);
begin
  for var C in StatementsOf(pNode) do
  begin
    var T:= C.NodeType;
    if (T = 'block') or (T = 'statements') then
    begin
      CollectLeaves(C, pMust, pLeaves);
      Continue;
    end;
    if T = 'try' then
    begin
      var HasFinally:= False;
      for var I:= 0 to C.NamedChildCount - 1 do
        if C.NamedChild(I).NodeType = 'kFinally' then HasFinally:= True;
      for var I:= 0 to C.NamedChildCount - 1 do
        if C.NamedChild(I).NodeType = 'statements' then CollectLeaves(C.NamedChild(I), pMust and HasFinally, pLeaves);
      Continue;
    end;
    var L: TLeaf;
    L.Node:= C;
    L.Must:= pMust and ((T = 'statement') or (T = 'assignment'));
    pLeaves:= pLeaves + [L];
  end;
end;

{ ---------------------------------------------------------------------------------------------- }
{ public functions                                                                                }

function HbIsUnorderedEvent(const pEvent: string): Boolean;
begin
  var E:= Trim(pEvent);
  if (E = '') or (E = '?') then Exit(True);
  if InList(E, HB_UNORDERED_EVENTS) then Exit(True);
  for var P in HB_UNORDERED_EVENT_PREFIXES do
    if E.StartsWith(P, True) and (Length(E) > Length(P)) and CharInSet(E[Length(P) + 1], ['A'..'Z']) then Exit(True);
  Result:= False;
end;

function HbIsUnorderedHandlerName(const pName: string): Boolean;
begin
  Result:= InList(Trim(pName), HB_UNORDERED_HANDLER_NAMES);
end;

function HbReliedText(const pOrder: THbHandlerOrder): string;
begin
  Result:= Format('relies on handler order: %s (fired by %s) runs only after the program-block prefix of %s ' +
    '(Application.Run at %s:%d) -- %s', [pOrder.Handler, pOrder.FiredBy, pOrder.ProgramName,
    ExtractFileName(pOrder.RunSite.FileName), pOrder.RunSite.Line, HEURISTIC_NOTE]);
end;

function HbPrefixMissText(const pOrder: THbHandlerOrder; const pTarget: string): string;
begin
  Result:= Format('root "%s" relies on handler order (fired by %s): it runs after the program-block prefix of %s, ' +
    'which does not write %s on every path before Application.Run (%s:%d) -- %s', [pOrder.Handler, pOrder.FiredBy,
    pOrder.ProgramName, pTarget, ExtractFileName(pOrder.RunSite.FileName), pOrder.RunSite.Line, HEURISTIC_NOTE]);
end;

{ ---------------------------------------------------------------------------------------------- }
{ THbHandlerOrderer                                                                               }

constructor THbHandlerOrderer.Create(const pIndex: TChartsIndex);
begin
  inherited Create;
  FIndex:= pIndex;
  FLines:= TDictionary<string, TArray<string>>.Create;
end;

destructor THbHandlerOrderer.Destroy;
begin
  FLines.Free;
  inherited;
end;

function THbHandlerOrderer.SourceLine(const pPath: string; pLine: Integer): string;
var
  L: TArray<string>;
begin
  if not FLines.TryGetValue(pPath, L) then
  begin
    L:= nil;
    try
      if FileExists(pPath) then L:= TFile.ReadAllLines(pPath);
    except
      on EInOutError do L:= nil;
      on EFileStreamError do L:= nil;
    end;
    FLines.Add(pPath, L);
  end;
  Result:= if InRange(pLine, 1, Length(L)) then L[pLine - 1] else '';
end;

function THbHandlerOrderer.ProgramFacts(pProgramBlockId: Int64): TProgramFacts;
begin
  for var K:= 0 to High(FProgramIds) do
    if FProgramIds[K] = pProgramBlockId then Exit(FPrograms[K]);
  Result:= ReadProgram(pProgramBlockId);
  FProgramIds:= FProgramIds + [pProgramBlockId];
  FPrograms:= FPrograms + [Result];
end;

function THbHandlerOrderer.ReadProgram(pProgramBlockId: Int64): TProgramFacts;
begin
  Result:= Default(TProgramFacts);
  var R:= FIndex.Query('SELECT s.name, s.kind, f.path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = ' +
    IntToStr(pProgramBlockId));
  try
    if (R.Count = 0) or not ((R[0].S('kind') = KIND_PROGRAM) or (R[0].S('kind') = KIND_LIBRARY)) then Exit;
    Result.Name:= R[0].S('name');
    Result.Path:= R[0].S('path');
  finally
    R.Free;
  end;
  if not FileExists(Result.Path) then Exit;
  var PF:= TAstParseCache.Get(Result.Path);
  if PF.Tree = nil then Exit;
  var Box:= FindMainBlock(PF.Tree.RootNode);
  if Box.IsNull then Exit;
  var Leaves: TArray<TLeaf>:= nil;
  CollectLeaves(Box, True, Leaves);
  var CreateRe:= TRegEx.Create(RE_CREATE, [roIgnoreCase]);
  var RunRe:= TRegEx.Create(RE_RUN, [roIgnoreCase]);
  var PumpRe:= TRegEx.Create('\b(' + string.Join('|', HB_PREFIX_PUMP_WORDS) + ')\b', [roIgnoreCase]);
  for var L in Leaves do
  begin
    var Text:= NodeText(PF.Src, L.Node);
    var Flat:= Squeezed(Text);
    var Site:= Default(THbSite);
    Site.FileName:= Result.Path;
    Site.Line:= Integer(L.Node.StartPoint.row) + 1;
    Site.Col:= TAstParseCache.CharCol(Result.Path, L.Node.StartPoint); { 1.52 BK-COLS2 (B45): sites carry CHARACTER columns, like the index }
    Site.Routine:= Result.Name;
    Site.RoutineId:= pProgramBlockId;
    if L.Must and RunRe.IsMatch(Flat) then
    begin
      Result.Run:= Site;
      Break;
    end;
    var M:= PumpRe.Match(Text);
    if M.Success and (Result.Pump = '') then Result.Pump:= Format('%s, line %d', [M.Groups[1].Value, Site.Line]);
    var C:= CreateRe.Match(Flat);
    if L.Must and C.Success then
    begin
      Result.CreateClasses:= Result.CreateClasses + [LastSegment(C.Groups[1].Value)];
      Result.CreateSites:= Result.CreateSites + [Site];
    end;
  end;
end;

{ Every DFM binding of pClass.pMethod: pBindings = `Form.Control.Event`, pEvents = the event names. }
function THbHandlerOrderer.BindingsOf(const pClass, pMethod: string; out pBindings, pEvents: TArray<string>): Boolean;
begin
  pBindings:= nil;
  pEvents:= nil;
  var B:= FIndex.Query('SELECT fm.name AS form, b.start_line AS ln, b.start_col AS col, f.path, ' +
    '(SELECT c.name FROM symbols c WHERE c.file_id = fm.file_id AND c.kind = ''component'' AND ' +
    'c.start_line <= b.start_line AND c.end_line >= b.start_line ORDER BY c.start_line DESC LIMIT 1) AS ctl ' +
    'FROM symbols fm JOIN refs b ON b.file_id = fm.file_id AND b.kind = ''event-binding'' ' +
    'JOIN files f ON f.id = fm.file_id WHERE fm.kind = ''form'' AND fm.signature = ' + Sq(pClass) +
    ' COLLATE NOCASE AND b.name_text = ' + Sq(pMethod) + ' COLLATE NOCASE ORDER BY f.path, b.start_line');
  try
    for var Row in B do
    begin
      var Ev:= Trim(Copy(SourceLine(Row.S('path'), Row.I('ln')), 1, Row.I('col') - 1));
      if Ev.EndsWith('=') then Ev:= Trim(Copy(Ev, 1, Length(Ev) - 1));
      if Ev = '' then Ev:= '?';
      var Ctl:= Row.S('ctl');
      pBindings:= pBindings + [Row.S('form') + '.' + (if Ctl <> '' then Ctl + '.' else '') + Ev];
      pEvents:= pEvents + [Ev];
    end;
  finally
    B.Free;
  end;
  Result:= pBindings <> nil;
end;

{ References to the method from code: resolved refs of any kind but the DFM binding, call edges, and
  unresolved refs of the same name (a doubt counts). }
function THbHandlerOrderer.CodeRefCount(pRoutineId: Int64; const pMethod: string): Integer;
begin
  var Id:= IntToStr(pRoutineId);
  var R:= FIndex.Query('SELECT (SELECT COUNT(*) FROM refs WHERE kind <> ''event-binding'' AND (symbol_id = ' + Id +  // dl:ok sql-injection-concat@128b -- REVIEWED 2026-11-17 v152 HBEVORD: read-only index query; Id is an Int64 and the name goes through QuotedStr (Sq)
    ' OR (symbol_id IS NULL AND name_text = ' + Sq(pMethod) + ' COLLATE NOCASE))) + ' +
    '(SELECT COUNT(*) FROM call_edges WHERE target_symbol_id = ' + Id + ') AS n');
  try
    Result:= if R.Count > 0 then R[0].I('n') else 0;
  finally
    R.Free;
  end;
end;

function THbHandlerOrderer.RunSiteOf(pProgramBlockId: Int64; out pSite: THbSite): Boolean;
begin
  pSite:= ProgramFacts(pProgramBlockId).Run;
  Result:= pSite.Line > 0;
end;

function THbHandlerOrderer.OrderOf(pProgramBlockId, pRoutineId: Int64): THbHandlerOrder;  // dl:ok too-many-exit-points@f9e8 -- REVIEWED 2026-11-17 v152 HBEVORD: one guard clause per refusal rule of the unit header, in the documented order; the first refusal is the WhyNot
begin
  Result:= Default(THbHandlerOrder);
  Result.RoutineId:= pRoutineId;
  var Name:= '';
  var R:= FIndex.Query('SELECT s.name, s.qualified_name AS q, COALESCE(p.name, '''') AS pn, COALESCE(p.kind, '''') ' +
    'AS pk FROM symbols s LEFT JOIN symbols p ON p.id = s.parent_id WHERE s.id = ' + IntToStr(pRoutineId));
  try
    if R.Count > 0 then
    begin
      Name:= R[0].S('name');
      Result.Handler:= R[0].S('q');
      if R[0].S('pk') = KIND_CLASS then Result.FormClass:= R[0].S('pn');
    end;
  finally
    R.Free;
  end;
  if pProgramBlockId = 0 then
  begin
    Result.WhyNot:= 'no program (.dpr) is known: event handlers are unordered';
    Exit;
  end;
  var P:= ProgramFacts(pProgramBlockId);
  Result.ProgramName:= P.Name;
  if P.Run.Line = 0 then
  begin
    Result.WhyNot:= Format('the program block of %s has no unconditional top-level Application.Run', [P.Name]);
    Exit;
  end;
  if P.Pump <> '' then
  begin
    Result.WhyNot:= Format('the program block of %s can run event handlers before Application.Run (%s)', [P.Name, P.Pump]);
    Exit;
  end;
  var Bindings, Events: TArray<string>;
  if (Result.FormClass = '') or not BindingsOf(Result.FormClass, Name, Bindings, Events) then
  begin
    Result.WhyNot:= Format('%s has no DFM binding (not an event handler of a form)', [Result.Handler]);
    Exit;
  end;
  Result.FiredBy:= string.Join(', ', Bindings);
  for var K:= 0 to High(Events) do
    if HbIsUnorderedEvent(Events[K]) then
    begin
      Result.WhyNot:= Format('%s is bound to %s, which fires inside Application.CreateForm or outside the message ' +
        'loop (OnCreate family, excluded by name)', [Result.Handler, Bindings[K]]);
      Exit;
    end;
  if HbIsUnorderedHandlerName(Name) then
  begin
    Result.WhyNot:= Format('%s has an OnCreate-family handler name (excluded by name)', [Result.Handler]);
    Exit;
  end;
  var N:= CodeRefCount(pRoutineId, Name);
  if N > 0 then
  begin
    Result.WhyNot:= Format('%s is referenced from code (%d site(s)): it can run outside the message loop',
      [Result.Handler, N]);
    Exit;
  end;
  for var K:= 0 to High(P.CreateClasses) do
    if SameText(P.CreateClasses[K], Result.FormClass) then
    begin
      Result.CreateSite:= P.CreateSites[K];
      Result.RunSite:= P.Run;
      Result.Ordered:= True;
      Exit;
    end;
  Result.WhyNot:= Format('form class %s is not created by an unconditional Application.CreateForm before ' +
    'Application.Run in %s (created at run time or conditionally: its handlers are unordered in 1.52)',
    [Result.FormClass, P.Name]);
end;

{ ---------------------------------------------------------------------------------------------- }
{ THbIndirectFacts (1.56 FB-2, happens-before phase 3)                                           }

const
  IE_KIND_POINTER = 'method-pointer';
  IE_KIND_EVT = 'event';
  IE_KIND_CALLBACK = 'callback-arg';
  IE_CONFIDENCE_RESOLVED = 'resolved';
  IE_UNPROBED = -1;
  { `Assigned(` -- the distance from the call ref of Assigned to its argument }
  ASSIGNED_ARG_OFFSET = 9;
  SQL_COUNT_REFS = 'SELECT COUNT(*) AS n FROM refs r WHERE ';
  SQL_UNRESOLVED_NAMED = SQL_COUNT_REFS + 'r.symbol_id IS NULL AND r.kind <> ''call'' AND r.name_text = %s COLLATE NOCASE';
  SQL_SITES = 'SELECT COALESCE(e.ref_id, 0) AS rid, COALESCE(e.caller_symbol_id, 0) AS caller, ' +
    'e.target_symbol_id AS target, e.kind, e.via_text AS via, COALESCE(e.bind_file_id, 0) AS bfid, ' +
    'COALESCE(e.bind_line, 0) AS bl, COALESCE(e.bind_col, 0) AS bc, e.confidence AS conf, ' +
    'COALESCE(f.path, '''') AS path, COALESCE(r.start_line, 0) AS ln, COALESCE(r.start_col, 0) AS col, ' +
    'COALESCE(r.name_text, '''') AS nm FROM indirect_edges e LEFT JOIN refs r ON r.id = e.ref_id ' +
    'LEFT JOIN files f ON f.id = r.file_id WHERE %s ORDER BY f.path, r.start_line, r.start_col, e.id';

constructor THbIndirectFacts.Create(const pIndex: TChartsIndex);
begin
  inherited Create;
  FIndex:= pIndex;
  FAvailable:= IE_UNPROBED;
  FOf:= TDictionary<Int64, TArray<THbIndirectSite>>.Create;
  FIn:= TDictionary<Int64, TArray<THbIndirectSite>>.Create;
  FWhyNot:= TDictionary<Int64, string>.Create;
  FSlotWhy:= TDictionary<Int64, string>.Create;
end;

destructor THbIndirectFacts.Destroy;
begin
  FSlotWhy.Free;
  FWhyNot.Free;
  FIn.Free;
  FOf.Free;
  inherited;
end;

{ The column n of a one-row query; 0 when it returns nothing. Every caller builds pSql from ids
  (Int64) and names that went through QuotedStr (Sq): read-only index queries. }
function THbIndirectFacts.Count(const pSql: string): Integer;
begin
  var R:= FIndex.Query(pSql);
  try
    Result:= if R.Count > 0 then R[0].I('n') else 0;
  finally
    R.Free;
  end;
end;

{ The column id of every row, in query order. }
function THbIndirectFacts.Ids(const pSql: string): TArray<Int64>;
begin
  Result:= nil;
  var R:= FIndex.Query(pSql);
  try
    for var Row in R do Result:= Result + [StrToInt64Def(Row.S('id'), 0)];
  finally
    R.Free;
  end;
end;

function THbIndirectFacts.Available: Boolean;
begin
  if FAvailable = IE_UNPROBED then
    FAvailable:= Count('SELECT COUNT(*) AS n FROM sqlite_master WHERE type = ''table'' AND name = ''indirect_edges''');
  Result:= FAvailable > 0;
end;

function THbIndirectFacts.ReadSites(const pWhere: string): TArray<THbIndirectSite>;
begin
  Result:= nil;
  if not Available then Exit;
  var R:= FIndex.Query(Format(SQL_SITES, [pWhere]));
  try
    for var Row in R do
    begin
      var S:= Default(THbIndirectSite);
      S.RefId:= StrToInt64Def(Row.S('rid'), 0);
      S.CallerId:= StrToInt64Def(Row.S('caller'), 0);
      S.TargetId:= StrToInt64Def(Row.S('target'), 0);
      S.FilePath:= Row.S('path');
      S.Line:= Row.I('ln');
      S.Col:= Row.I('col');
      S.SlotName:= Row.S('nm');
      S.Kind:= Row.S('kind');
      S.ViaText:= Row.S('via');
      S.BindFileId:= StrToInt64Def(Row.S('bfid'), 0);
      S.BindLine:= Row.I('bl');
      S.BindCol:= Row.I('bc');
      S.Resolved:= Row.S('conf') = IE_CONFIDENCE_RESOLVED;
      Result:= Result + [S];
    end;
  finally
    R.Free;
  end;
end;

function THbIndirectFacts.SitesOf(pTargetId: Int64): TArray<THbIndirectSite>;
begin
  if FOf.TryGetValue(pTargetId, Result) then Exit;
  Result:= ReadSites('e.target_symbol_id = ' + IntToStr(pTargetId));
  FOf.Add(pTargetId, Result);
end;

function THbIndirectFacts.SitesIn(pCallerId: Int64): TArray<THbIndirectSite>;
begin
  if FIn.TryGetValue(pCallerId, Result) then Exit;
  Result:= ReadSites('e.caller_symbol_id = ' + IntToStr(pCallerId) + ' AND e.ref_id IS NOT NULL');
  FIn.Add(pCallerId, Result);
end;

{ The symbol a call through a slot is written with; 0 when it cannot be placed without doubt: a
  parameter / local of the caller, else a field of the caller's class or a variable of the caller's
  unit, else the ONE unit variable of that name in the index. A call with a receiver other than Self
  is not placed. }
function THbIndirectFacts.SlotOf(const pSite: THbIndirectSite): Int64;
begin
  Result:= 0;
  if (pSite.RefId = 0) or (pSite.CallerId = 0) or (pSite.SlotName = '') then Exit;
  if Count(SQL_COUNT_REFS + 'r.id = ' + IntToStr(pSite.RefId) +
    ' AND LOWER(COALESCE(r.receiver_text, '''')) NOT IN ('''', ''self'')') > 0 then Exit;
  var Found:= Ids('SELECT s.id FROM symbols s WHERE s.parent_id = ' + IntToStr(pSite.CallerId) +
    ' AND s.name = ' + Sq(pSite.SlotName) + ' COLLATE NOCASE ORDER BY s.id');
  if Found = nil then
    Found:= Ids('SELECT s.id FROM symbols s JOIN symbols c ON c.id = ' + IntToStr(pSite.CallerId) +
      ' WHERE s.parent_id = c.parent_id AND s.kind IN (''field'', ''var'') AND s.name = ' + Sq(pSite.SlotName) +
      ' COLLATE NOCASE ORDER BY s.id');
  if Found = nil then
    Found:= Ids('SELECT s.id FROM symbols s JOIN symbols u ON u.id = s.parent_id WHERE s.kind = ''var'' ' +
      'AND u.kind IN (''unit'', ''program'', ''library'') AND s.name = ' + Sq(pSite.SlotName) +
      ' COLLATE NOCASE ORDER BY s.id');
  if Length(Found) = 1 then Result:= Found[0];
end;

{ The properties declared over a field slot (a `property-spec` ref of the field sits inside the
  declaration of the nearest property of the same class at or above its line). pComplete is False when
  one such ref has no property: the slot then has a reader this unit cannot check. }
function THbIndirectFacts.PropertiesOver(pSlotId: Int64; out pComplete: Boolean): TArray<Int64>;
begin
  Result:= nil;
  pComplete:= True;
  for var P in Ids('SELECT COALESCE((SELECT p.id FROM symbols p WHERE p.kind = ''property'' ' +
    'AND p.parent_id = s.parent_id AND p.file_id = r.file_id AND p.start_line <= r.start_line ' +
    'ORDER BY p.start_line DESC, p.id DESC LIMIT 1), 0) AS id FROM refs r JOIN symbols s ON s.id = r.symbol_id ' +
    'WHERE r.symbol_id = ' + IntToStr(pSlotId) + ' AND r.kind = ''property-spec'' ORDER BY r.id') do
    if P = 0 then pComplete:= False
    else if not TArray.Contains<Int64>(Result, P) then Result:= Result + [P];
end;

{ '' when a property over a field slot is only ever written (a read of it copies the slot's value). }
function THbIndirectFacts.PropertyWhyNot(pPropertyId: Int64; const pSlotName: string): string;
begin
  Result:= '';
  var Prop:= FIndex.Query('SELECT name FROM symbols WHERE id = ' + IntToStr(pPropertyId));
  try
    var PropName:= if Prop.Count > 0 then Prop[0].S('name') else '';
    if Count(SQL_COUNT_REFS + 'r.symbol_id = ' + IntToStr(pPropertyId) +
      ' AND NOT (r.kind = ''write'' OR EXISTS (SELECT 1 FROM member_accesses m WHERE m.ref_id = r.id ' +
      'AND m.member_symbol_id = r.symbol_id AND m.mode = ''write''))') > 0 then
      Result:= 'property ' + PropName + ' over ' + pSlotName + ' is read'
    else if Count(Format(SQL_UNRESOLVED_NAMED, [Sq(PropName)])) > 0 then
      Result:= 'an unresolved reference is named ' + PropName + ' (a property over ' + pSlotName + ')';
  finally
    Prop.Free;
  end;
end;

{ '' when the slot is closed (condition 4 of the class remarks), else why not. Cached per slot. }
function THbIndirectFacts.SlotWhyNot(pSlotId: Int64): string;
begin
  if FSlotWhy.TryGetValue(pSlotId, Result) then Exit;
  Result:= '';
  var Slot:= FIndex.Query('SELECT s.name, s.kind, COALESCE(s.parent_id, 0) AS pid FROM symbols s WHERE s.id = ' +
    IntToStr(pSlotId));
  try
    if Slot.Count = 0 then Result:= 'the slot is not in the index'
    else
    begin
      var Name:= Slot[0].S('name');
      var Scoped:= (Slot[0].S('kind') <> 'field') and (Slot[0].S('kind') <> 'var');
      { a read that is not `Assigned(Slot)`, or any other use, can copy the value away }
      if Count(SQL_COUNT_REFS + 'r.symbol_id = ' + IntToStr(pSlotId) +
        ' AND r.kind NOT IN (''write'', ''call'', ''property-spec'') AND NOT (r.kind = ''read'' AND EXISTS (' +
        'SELECT 1 FROM refs a WHERE a.file_id = r.file_id AND a.start_line = r.start_line AND a.kind = ''call'' ' +
        'AND a.name_text = ''Assigned'' COLLATE NOCASE AND a.start_col + ' + IntToStr(ASSIGNED_ARG_OFFSET) +
        ' = r.start_col))') > 0 then
        Result:= Name + ' is read as a value (it can be copied or passed on)'
      else if Count(Format(SQL_UNRESOLVED_NAMED, [Sq(Name)]) +
        (if Scoped then ' AND r.enclosing_symbol_id = ' + Slot[0].S('pid') else '')) > 0 then
        Result:= 'an unresolved reference is named ' + Name
      else if not Scoped then
      begin
        var Complete: Boolean;
        for var P in PropertiesOver(pSlotId, Complete) do
          if Result = '' then Result:= PropertyWhyNot(P, Name);
        if (Result = '') and not Complete then Result:= 'a property over ' + Name + ' could not be placed';
      end;
    end;
  finally
    Slot.Free;
  end;
  FSlotWhy.Add(pSlotId, Result);
end;

{ Condition 5: the binding statement writes pSlotId itself -- the slot (method-pointer), a property
  over it (event), or it is an argument of a call to the routine whose parameter the slot is
  (callback-arg). }
function THbIndirectFacts.BoundDirectly(const pSite: THbIndirectSite; pSlotId: Int64): Boolean;
begin
  Result:= False;
  var Where:= ' AND r.file_id = ' + IntToStr(pSite.BindFileId) + ' AND r.start_line = ' + IntToStr(pSite.BindLine) +
    ' AND r.start_col < ' + IntToStr(pSite.BindCol);
  if pSite.Kind = IE_KIND_POINTER then
    Result:= Count(SQL_COUNT_REFS + 'r.kind = ''write'' AND r.symbol_id = ' + IntToStr(pSlotId) + Where) > 0
  else if pSite.Kind = IE_KIND_EVT then
  begin
    var Complete: Boolean;
    for var P in PropertiesOver(pSlotId, Complete) do
      if Count(SQL_COUNT_REFS + 'r.symbol_id = ' + IntToStr(P) + Where) > 0 then Result:= True;
  end
  else if pSite.Kind = IE_KIND_CALLBACK then
    Result:= Count('SELECT COUNT(*) AS n FROM refs r LEFT JOIN call_edges c ON c.ref_id = r.id ' +
      'JOIN symbols s ON s.id = ' + IntToStr(pSlotId) + ' WHERE r.kind = ''call'' ' +
      'AND COALESCE(c.target_symbol_id, r.symbol_id) = s.parent_id' + Where) > 0;
end;

{ Condition 6: the calls written with the slot's name that have no edge to pTargetId. A parameter or
  local is looked for in its routine only, a field or unit variable in the whole index. }
function THbIndirectFacts.UnpairedCalls(pTargetId, pSlotId: Int64): Integer;
begin
  Result:= 0;
  var Slot:= FIndex.Query('SELECT s.name, s.kind, COALESCE(s.parent_id, 0) AS pid FROM symbols s WHERE s.id = ' +
    IntToStr(pSlotId));
  try
    if Slot.Count = 0 then Exit(1);
    var Scoped:= (Slot[0].S('kind') <> 'field') and (Slot[0].S('kind') <> 'var');
    Result:= Count(SQL_COUNT_REFS + 'r.kind = ''call'' AND (r.symbol_id = ' + IntToStr(pSlotId) +
      ' OR (r.symbol_id IS NULL AND r.name_text = ' + Sq(Slot[0].S('name')) + ' COLLATE NOCASE' +
      (if Scoped then ' AND r.enclosing_symbol_id = ' + Slot[0].S('pid') else '') + ')) AND r.id NOT IN (' +
      'SELECT e.ref_id FROM indirect_edges e WHERE e.target_symbol_id = ' + IntToStr(pTargetId) +
      ' AND e.ref_id IS NOT NULL)');
  finally
    Slot.Free;
  end;
end;

{ Condition 1: '' when every place that names the routine as a value is the binding site of an edge,
  else the first place that is not. }
function THbIndirectFacts.UnboundNaming(pTargetId: Int64; const pSites: TArray<THbIndirectSite>): string;
begin
  Result:= '';
  var R:= FIndex.Query('SELECT r.file_id AS fid, r.start_line AS ln, r.start_col AS col, f.path FROM refs r ' +
    'JOIN files f ON f.id = r.file_id LEFT JOIN call_edges c ON c.ref_id = r.id WHERE (r.symbol_id = ' +
    IntToStr(pTargetId) + ' AND r.kind <> ''call'') OR (c.target_symbol_id = ' + IntToStr(pTargetId) +
    ' AND c.confidence = ''callback'') ORDER BY f.path, r.start_line, r.start_col');
  try
    for var Row in R do
    begin
      var Bound:= False;
      for var S in pSites do
        if (S.BindFileId = StrToInt64Def(Row.S('fid'), 0)) and (S.BindLine = Row.I('ln')) and (S.BindCol = Row.I('col')) then
          Bound:= True;
      if not Bound then
        Exit(Format('it is named as a value at %s:%d with no indirect-call edge', [ExtractFileName(Row.S('path')), Row.I('ln')]));
    end;
  finally
    R.Free;
  end;
end;

{ Conditions 2 to 6 for one edge: '' when they hold, else the first that does not. }
function THbIndirectFacts.SiteWhyNot(const pSite: THbIndirectSite): string;
begin
  var Slot:= if (pSite.RefId <> 0) and pSite.Resolved then SlotOf(pSite) else 0;
  Result:= if pSite.RefId = 0 then 'bound to ' + pSite.ViaText + ', which this index never calls'
    else if not pSite.Resolved then 'the edge through ' + pSite.ViaText + ' is matched by name only'
    else if Slot = 0 then 'the slot ' + pSite.SlotName + ' could not be placed'
    else SlotWhyNot(Slot);
  if (Result <> '') or (Slot = 0) then Exit;
  if not BoundDirectly(pSite, Slot) then
    Result:= 'it reaches ' + pSite.SlotName + ' through another slot (' + pSite.ViaText + ')'
  else if UnpairedCalls(pSite.TargetId, Slot) > 0 then
    Result:= 'a call written as ' + pSite.SlotName + ' has no edge to it';
end;

function THbIndirectFacts.ComputeWhyNot(pTargetId: Int64): string;
begin
  var Sites:= SitesOf(pTargetId);
  Result:= if not Available then 'the index has no indirect-call edges (written by drag-lint 1.56 or later)'
    else if Sites = nil then 'no indirect-call edge binds it'
    else '';
  for var S in Sites do
    if Result = '' then Result:= SiteWhyNot(S);
  if Result = '' then Result:= UnboundNaming(pTargetId, Sites);
end;

function THbIndirectFacts.OnlyThroughSlots(pTargetId: Int64; out pWhyNot: string): Boolean;
begin
  if not FWhyNot.TryGetValue(pTargetId, pWhyNot) then
  begin
    pWhyNot:= ComputeWhyNot(pTargetId);
    FWhyNot.Add(pTargetId, pWhyNot);
  end;
  Result:= pWhyNot = '';
end;

end.
