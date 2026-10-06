unit ConvRules.Inheritance;

{ C8 (spec 2026-10-05-c8-inherited-instances-design.md), editor half: which objects
  in a unit's .dfm are INHERITED instances of a checked book's From type (inline
  blocks are the unit's own frames; their children count), which identifiers its own
  class's code uses from an ancestor's From-typed field (E2b), which ancestor declares
  each one and whether that ancestor is converted -- and what the Convert tab does with
  that: row notes, the ancestor-first offer and list insert, the order warning, the
  Convert gate and the no-capability run notes. The decisions are pure: the project
  index, the code uses and the file system come in as function references, so
  ConvRulesModelTests pins every rule with fixture text and a fake index. Not pure:
  DiskTextReader (the real file reader) and CachingLookup (fills a caller-owned
  cache). The engine binders are in ConvRules.InheritanceEngine. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  ;

const
  /// <summary>The .dfm beside a unit's .pas.</summary>
  DFM_EXT = '.dfm';
  /// <summary>The first four bytes of a BINARY .dfm; such a file has no text to scan.</summary>
  BINARY_DFM_SIGNATURE = 'TPF0';
  /// <summary>Longest ancestor chain the walk follows; a cycle stops earlier.</summary>
  MAX_CHAIN_DEPTH = 32;
  /// <summary>TInstanceVerdict.DeclaringUnit of an asOutside verdict whose chain named
  /// no ancestor class at all (the unit's own class records none). Not a class name:
  /// OutsideNote words this case without it.</summary>
  OUTSIDE_NO_ANCESTOR = '(no ancestor class)';
  /// <summary>The failure text CancellableLookup / CancellableCodeUses answer with once
  /// the user cancelled: AnalyzeUnit appends it to the unit's Error, so the unit is
  /// Known = False and the status line says why.</summary>
  ANALYSIS_CANCELLED = 'cancelled';
  /// <summary>The Convert tab's status when the user cancelled the inherited-instance
  /// check that Convert runs first: nothing runs (InheritanceGate = igCancelled).</summary>
  GATE_CANCELLED_TEXT = 'Convert cancelled: the inherited-instance check was cancelled.';

type
  /// <summary>The keyword that opens a .dfm block.</summary>
  TDfmOpener = (doObject, doInherited, doInline);

  /// <summary>One #convert block of a checked book, bare class names ('TLabel', not
  /// 'Vcl.StdCtrls.TLabel').</summary>
  TTypePair = record
    /// <summary>The block's From type.</summary>
    FromType: string;
    /// <summary>The block's To type; '' for a From-only stub.</summary>
    ToType  : string;
  end;

  /// <summary>One object a .dfm opens with `inherited` or `inline` (spec E1).</summary>
  TInheritedInstance = record
    /// <summary>The instance name ('tblFtrs').</summary>
    Name      : string;
    /// <summary>The class as written in the .dfm, without a '[n]' suffix.</summary>
    TypeName  : string;
    /// <summary>1-based .dfm line of the header.</summary>
    Line      : Integer;
    /// <summary>doInherited or doInline.</summary>
    Opener    : TDfmOpener;
    /// <summary>The class of the innermost ENCLOSING `inline` block; '' when the
    /// object belongs to the form (or data module) itself.</summary>
    FrameClass: string;
    /// <summary>The class of the immediately enclosing block; '' for a top-level object
    /// (a direct child of the root).</summary>
    ParentType: string;
    /// <summary>The classes of the enclosing blocks below the root, innermost first,
    /// stopping at (and including) the innermost enclosing `inline` block; [] for a
    /// top-level object. ResolveInstance's frame fallback tries each in turn.</summary>
    Enclosing : TArray<string>;
    /// <summary>True = an E2b CODE use (no .dfm block): Line is the first use in the
    /// unit's .pas, Opener is doInherited, FrameClass and ParentType are '', Enclosing
    /// is [].</summary>
    FromCode  : Boolean;
  end;

  /// <summary>What one .dfm says about inheritance.</summary>
  TDfmInheritance = record
    /// <summary>The root block's class; '' when the text has no header.</summary>
    RootClass: string;
    /// <summary>True for a binary .dfm: nothing was scanned.</summary>
    IsBinary : Boolean;
    /// <summary>Every inherited / inline object below the root, in file order.</summary>
    Instances: TArray<TInheritedInstance>;
  end;

  /// <summary>One .dfm block header, whatever its opener (C12 scope).</summary>
  TDfmInstance = record
    /// <summary>The instance name ('Label1'); the root's name for the root.</summary>
    Name    : string;
    /// <summary>The class as written in the .dfm, without a '[n]' suffix.</summary>
    TypeName: string;
    /// <summary>1-based .dfm line of the header.</summary>
    Line    : Integer;
    /// <summary>The keyword that opened the block.</summary>
    Opener  : TDfmOpener;
    /// <summary>Nesting depth: 0 = the root (the form / data module itself), 1 = a
    /// direct child of the root, and so on through panels and inline frames.</summary>
    Depth   : Integer;
  end;

  /// <summary>One field a class declares itself, with a From type.</summary>
  TFieldDecl = record
    /// <summary>Field name ('tblFtrs').</summary>
    Name    : string;
    /// <summary>Its class as declared ('TTable').</summary>
    TypeName: string;
  end;

  /// <summary>What the project index says about one class.</summary>
  TClassInfo = record
    /// <summary>Exactly one unit of the project index declares the class.</summary>
    Found      : Boolean;
    /// <summary>The index could not be asked (engine failure); unknown, not absent.</summary>
    Failed     : Boolean;
    /// <summary>Failed only: why -- the engine's own text naming the DB (missing,
    /// locked, stale schema, stale files); '' otherwise. AnalyzeUnit appends it to the
    /// unit's Error.</summary>
    Error      : string;
    /// <summary>The declaring unit's .pas (full path); '' unless Found.</summary>
    PasPath    : string;
    /// <summary>The class's first ancestor as written ('TDataModule'); '' when none.</summary>
    ParentClass: string;
    /// <summary>The fields the editor passes: only the From-typed fields the class
    /// ITSELF declares (not inherited ones) -- TEngineAdapter.ListClassFields filters by
    /// the checked books' From types. What an E2b code use is matched against; a
    /// converted ancestor's field (now the To type) is therefore absent.</summary>
    Fields     : TArray<TFieldDecl>;
  end;

  /// <summary>Asks the project index about a class (TEngineAdapter.LookupClass in the
  /// editor, a fake in the tests).</summary>
  TClassLookup = reference to function(const AClassName: string): TClassInfo;

  /// <summary>How a TDfmTextReader answered.</summary>
  /// <remarks>drMissing: no such file (a class with no .dfm declares no component).
  /// drUnreadable: the file exists but could not be read. drRead: AText holds it.</remarks>
  TDfmRead = (drMissing, drUnreadable, drRead);

  /// <summary>Reads a text file (a .dfm).</summary>
  TDfmTextReader = reference to function(const APath: string; out AText: string): TDfmRead;

  /// <summary>One identifier the unit's own class methods use (TEngineAdapter.ListCodeRefs,
  /// mapped through CodeUseName).</summary>
  TCodeUse = record
    /// <summary>The identifier: an implicit-Self name, or a receiver's first segment.</summary>
    Name: string;
    /// <summary>1-based .pas line.</summary>
    Line: Integer;
  end;

  /// <summary>Asks the project index which identifiers AClassName's methods in AUnitPas use.</summary>
  /// <remarks>False = the index could not answer (unknown, never "no uses"); AError then
  /// says why (the engine's text naming the DB), else ''. AnalyzeUnit appends it to the
  /// unit's Error.</remarks>
  TCodeUseLookup = reference to function(const AUnitPas, AClassName: string; out AUses: TArray<TCodeUse>; out AError: string): Boolean;

  /// <summary>The declaring ancestor's state for one inherited instance (spec Terms).</summary>
  /// <remarks>asUnconverted: the ancestor's object still has the instance's (From)
  /// type. asConverted: the declaring object has the To type of a checked pair whose
  /// From type is the instance's (for an E2b code use: the declared field is no longer a
  /// From type). asMismatched: the declaring object's type is neither the instance's
  /// From type nor that pair's To type (engine C8 N1 'mismatched'; FoundType names it) --
  /// converting that ancestor with this book would not help, so it is neither offered
  /// (E6) nor warned about (E7). This reverses preflight ruling C4 (2026-10-06), which
  /// read every non-From type as converted. asOutside: the chain left the project index (a
  /// library ancestor, or an ambiguous class) or ended at an indexed class with no
  /// ancestor, before any .dfm opened the object with `object`. asUnknown: the walk
  /// could not decide -- the index could not be asked, the chain loops or runs past
  /// MAX_CHAIN_DEPTH, or an indexed ancestor's .dfm is binary or unreadable; the
  /// verdict's Reason says which. Never reported as outside (AnalyzeUnit turns it into
  /// Known = False).</remarks>
  TAncestorState = (asUnconverted, asConverted, asMismatched, asOutside, asUnknown);

  /// <summary>One ancestor unit whose .dfm opens an instance with the From type.</summary>
  TChainUnit = record
    /// <summary>The ancestor's .pas.</summary>
    PasPath: string;
    /// <summary>The class's position on the walk from the listed unit's own class (0):
    /// 1 = the first class walked (the form's parent, or for an instance on the unit's
    /// own inline frame the frame class), larger = further up. When the walk goes on
    /// into a frame class after the form chain (a frame placed on an ancestor form),
    /// the frame classes continue the count after the form-chain classes visited, so a
    /// frame unit is always above every form that re-opens its child. A larger Depth
    /// is converted first (topmost first).</summary>
    Depth  : Integer;
  end;

  /// <summary>The verdict on one inherited instance.</summary>
  TInstanceVerdict = record
    /// <summary>The instance as scanned.</summary>
    Instance     : TInheritedInstance;
    /// <summary>The declaring ancestor's state.</summary>
    State        : TAncestorState;
    /// <summary>The declaring unit's name ('Base'); for asOutside the class where the
    /// chain left the index ('TDataModule'), or OUTSIDE_NO_ANCESTOR when the chain
    /// named no ancestor class at all; '' for asUnknown.</summary>
    DeclaringUnit: string;
    /// <summary>The declaring unit's .pas; '' for asOutside and asUnknown.</summary>
    DeclaringPas : string;
    /// <summary>asUnknown only: why the walk could not decide, naming the class.</summary>
    Reason       : string;
    /// <summary>asMismatched only: the declaring object's class as its .dfm writes it
    /// ('TADOTable'); '' otherwise.</summary>
    FoundType    : string;
    /// <summary>Every ancestor unit (declaring or intermediate) whose .dfm still opens
    /// the instance with the From type -- the units to convert first.</summary>
    Chain        : TArray<TChainUnit>;
  end;

  /// <summary>What Convert does after its inherited-instance check (InheritanceGate).</summary>
  /// <remarks>igProceed: run. igCancelled: the user cancelled the check -- stop, nothing
  /// runs. igAsk: some unit could not be checked -- ask ONCE whether to convert anyway
  /// (never a refusal: the owner's E9 rule).</remarks>
  TInheritanceGate = (igProceed, igCancelled, igAsk);

  /// <summary>One listed unit's C8 analysis.</summary>
  TUnitInheritance = record
    /// <summary>The listed .pas.</summary>
    UnitPas : string;
    /// <summary>False = nothing to say: no checked From type, no (text) .dfm, the
    /// unit's own class not in the index, or the index could not answer.</summary>
    Known   : Boolean;
    /// <summary>'' or why the index could not answer (Known is then False).</summary>
    Error   : string;
    /// <summary>One verdict per inherited instance of a checked From type.</summary>
    Verdicts: TArray<TInstanceVerdict>;
  end;

/// <summary>PURE: lists the inherited / inline objects of a text .dfm.</summary>
/// <param name="AText">The whole .dfm as text.</param>
/// <returns>RootClass and the instances; IsBinary and no instances for a binary
/// .dfm; an empty record for '' or text with no header.</returns>
/// <remarks>Depth-tracked header walk (ParseBlockHeader is the one header parser).
/// A property value opening '<', '(' or '{' is skipped to its balanced terminator,
/// judged on StripQuoted text, so a collection's item/end never closes a component
/// and a quoted '>' never ends a list. A value starts a skip only on a line whose left
/// of '=' is a property name (IsPropName), so a string continuation line holding '='
/// and '(' never does. Anonymous blocks are not listed.</remarks>
function ScanDfmInheritance(const AText: string): TDfmInheritance;

/// <summary>PURE: how a .dfm opens the object named AName, at any depth, OUTSIDE
/// every inline block (a frame's children belong to the frame's own .dfm).</summary>
/// <param name="AText">The whole .dfm as text.</param>
/// <param name="AName">Instance name, matched case-insensitively.</param>
/// <param name="AOpener">Receives the opener of the first match.</param>
/// <param name="ATypeName">Receives the class of the first match.</param>
/// <returns>False when the .dfm does not open AName (or is binary).</returns>
function FindDfmObject(const AText, AName: string; out AOpener: TDfmOpener; out ATypeName: string): Boolean;

/// <summary>PURE: every block header of a text .dfm at any depth, in file order, the
/// root included (Depth = 0).</summary>
/// <param name="AText">The whole .dfm as text.</param>
/// <returns>[] for a binary .dfm (BINARY_DFM_SIGNATURE), for '' and for text with
/// no header.</returns>
/// <remarks>The same depth-tracked walk as ScanDfmInheritance: collection items
/// (`item` ... `end` inside `<` `>`), multi-line string / binary values and quoted
/// text are not headers. Children of inline frames are listed (their Depth counts the
/// frame). Anonymous blocks (no instance name) are listed with Name = ''. The C12
/// form scope reads this list; the engine splices against the same headers.</remarks>
function ListDfmInstances(const AText: string): TArray<TDfmInstance>;  // dl:ok unused-public-symbol@5ffa -- REVIEWED 2026-10-06 C12 Task 2: its caller ConvRules.ConvertRequest.BuildScope joins the editor project in Task 4 (ConvertTab), which removes this marker

/// <summary>PURE: the last dotted segment of a class name ('Vcl.StdCtrls.TLabel' -> 'TLabel').</summary>
/// <param name="AType">A bare or unit-qualified class name.</param>
/// <returns>The bare name; '' for ''.</returns>
function BareType(const AType: string): string;

/// <summary>PURE: the #convert pairs of a rule book, bare names, book order.</summary>
/// <param name="ARulesText">The .rules text.</param>
/// <returns>One pair per #convert header that names a From type.</returns>
function TypePairsOfText(const ARulesText: string): TArray<TTypePair>;

/// <summary>PURE: True when AType (bare or qualified) is the From type of one of APairs.</summary>
/// <param name="AType">A class name from a .dfm.</param>
/// <param name="APairs">The checked books' pairs.</param>
/// <returns>Case-insensitive match on the bare names.</returns>
function IsFromType(const AType: string; const APairs: TArray<TTypePair>): Boolean;

/// <summary>PURE: a unit's name from its path ('C:\x\PathToData.pas' -> 'PathToData').</summary>
/// <param name="APasPath">A .pas path.</param>
/// <returns>The file name without its extension.</returns>
function UnitNameOf(const APasPath: string): string;

/// <summary>PURE: walks one instance's ancestor chain to its declaring ancestor (spec E2).</summary>
/// <param name="AInst">The instance.</param>
/// <param name="AStartClass">The first class whose .dfm is read: the form's PARENT
/// class for a form-owned instance, the frame class itself for a frame child.</param>
/// <param name="ALookup">The project index.</param>
/// <param name="AReader">The file system.</param>
/// <param name="APairs">The checked books' pairs: the declaring object's type is the
/// From type (asUnconverted), a matching pair's To type (asConverted) or neither
/// (asMismatched). Empty = no To type is known, so any other type is asMismatched.</param>
/// <returns>The verdict. When the form chain does not declare the instance and it sits
/// in enclosing blocks, each enclosing block's class (AInst.Enclosing, innermost
/// outward) is walked next until one declares it (a frame placed on an ancestor form,
/// at any nesting depth inside the frame); the form chain's re-opening units stay in
/// Chain. asUnknown (with Reason) when the index cannot be asked, the chain loops or
/// passes MAX_CHAIN_DEPTH, or an indexed class's .dfm is binary or unreadable -- the
/// caller (AnalyzeUnit) turns that into Known = False, never into a report.</returns>
function ResolveInstance(const AInst: TInheritedInstance; const AStartClass: string; const ALookup: TClassLookup; const AReader: TDfmTextReader;
  const APairs: TArray<TTypePair>): TInstanceVerdict;

/// <summary>PURE: the C8 analysis of one listed unit (spec E1-E3, E2b).</summary>
/// <param name="AUnitPas">The listed .pas; its .dfm is ChangeFileExt(AUnitPas, DFM_EXT).</param>
/// <param name="APairs">The checked books' pairs; empty = nothing is recorded (E3).</param>
/// <param name="ALookup">The project index (class chain and declared From-typed fields).</param>
/// <param name="AReader">The file system.</param>
/// <param name="ACodeUses">The unit's code uses (E2b); nil = .dfm only.</param>
/// <returns>Known = False when there is nothing to say (see TUnitInheritance.Known);
/// otherwise one verdict per `inherited` .dfm instance whose class is a From type, then
/// one per E2b code use (FromCode, asUnconverted) not already reported. `inline`
/// instances are the unit's OWN frames and are not verdicts; their children are.</returns>
/// <remarks>A code use is an identifier the unit's own class's methods use that an
/// ANCESTOR declares as a field of a From type (TClassInfo.Fields), found on the same
/// walk as an instance; its Chain follows E2a (every ancestor whose .dfm opens it with a
/// From type, plus the declaring unit). Dropped, not reported: a name the .dfm already
/// reported, a field of the unit's own class, a name no project ancestor declares, and
/// a field whose declared type is not a From type (a converted ancestor, E11: absent
/// from the filtered Fields, so its name leaves the index unmatched). Whether an ancestor
/// declares the name is decided from Fields alone, before any .dfm is read, so a name no
/// ancestor declares is never unknown; only for a declared name is the chain walked again
/// reading .dfm files (each read once per call). A code-use walk that cannot decide
/// (asUnknown), or ACodeUses answering False, makes the unit Known = False with Error,
/// like an instance; a failed lookup's or code-use listing's own error text
/// (TClassInfo.Error, the TCodeUseLookup's AError) is appended to Error in
/// parentheses, so the cause (missing DB, stale schema, stale files) reaches the
/// caller. Accepted gap: a closer ancestor redeclaring the name with a
/// non-From type (shadowing) is not in the filtered Fields, so the walk goes on to a
/// further ancestor's From-typed field of that name and counts it.</remarks>
function AnalyzeUnit(const AUnitPas: string; const APairs: TArray<TTypePair>; const ALookup: TClassLookup; const AReader: TDfmTextReader; const ACodeUses: TCodeUseLookup = nil): TUnitInheritance;

/// <summary>PURE: AnalyzeUnit for each of APaths, in order, with ONE .dfm cache for the
/// whole pass (an ancestor's .dfm shared by several listed units is read once).</summary>
/// <param name="APaths">Listed .pas paths.</param>
/// <param name="APairs">See AnalyzeUnit.</param>
/// <param name="ALookup">See AnalyzeUnit; wrap it in CachingLookup for the pass.</param>
/// <param name="AReader">See AnalyzeUnit.</param>
/// <param name="ACodeUses">See AnalyzeUnit.</param>
/// <returns>One analysis per path, APaths order.</returns>
function AnalyzeUnits(const APaths: TArray<string>; const APairs: TArray<TTypePair>; const ALookup: TClassLookup; const AReader: TDfmTextReader; const ACodeUses: TCodeUseLookup = nil): TArray<TUnitInheritance>;

/// <summary>PURE: ALookup, unless ACancelled answers True: then a Failed answer with
/// Error = ANALYSIS_CANCELLED, without asking ALookup.</summary>
/// <param name="AInner">The real lookup.</param>
/// <param name="ACancelled">Polled before each lookup.</param>
/// <returns>The wrapped lookup. CachingLookup never caches the Failed answer.</returns>
function CancellableLookup(const AInner: TClassLookup; const ACancelled: TFunc<Boolean>): TClassLookup;

/// <summary>PURE: ACodeUses, unless ACancelled answers True: then False with AError =
/// ANALYSIS_CANCELLED, without asking ACodeUses.</summary>
/// <param name="AInner">The real code-use lookup.</param>
/// <param name="ACancelled">Polled before each call.</param>
/// <returns>The wrapped lookup.</returns>
function CancellableCodeUses(const AInner: TCodeUseLookup; const ACancelled: TFunc<Boolean>): TCodeUseLookup;

/// <summary>PURE: the status-line text for the units the analysis could not decide
/// (Known = False with an Error -- the index could not answer, or the user cancelled).</summary>
/// <param name="AUnits">The analyses.</param>
/// <returns>'' when no unit has an Error; else '&lt;Unit.pas&gt;: &lt;Error&gt;' for the
/// first such unit, plus ' (+N more)' when N others have one too.</returns>
function UnknownUnitsText(const AUnits: TArray<TUnitInheritance>): string;

/// <summary>PURE: Convert's decision after its inherited-instance check.</summary>
/// <param name="ACancelled">The check ended with ENGINE_OUTCOME_CANCELLED (the work's
/// result, not a text match).</param>
/// <param name="AUnits">The listed units' analyses.</param>
/// <param name="AError">The tab's collected failure text ('' when none).</param>
/// <param name="AQuestion">igAsk only: 'Could not check inherited instances for
/// &lt;Unit.pas, ...&gt; -- convert anyway?' (the units with an Error; 'the listed units'
/// when only AError says something failed); '' otherwise.</param>
/// <returns>igCancelled when ACancelled; else igAsk when AError is not '' or a unit has
/// an Error; else igProceed.</returns>
function InheritanceGate(ACancelled: Boolean; const AUnits: TArray<TUnitInheritance>; const AError: string; out AQuestion: string): TInheritanceGate;

/// <summary>PURE: the status after No to InheritanceGate's question.</summary>
/// <param name="AReason">Why the check failed (the tab's collected failure text).</param>
/// <returns>'Convert cancelled: inherited instances could not be checked -- &lt;reason&gt;'.</returns>
function InheritanceGateStopText(const AReason: string): string;

/// <summary>PURE: the spec E8 note for one asOutside verdict.</summary>
/// <param name="AVerdict">A verdict from ResolveInstance / AnalyzeUnit.</param>
/// <returns>'' unless AVerdict.State = asOutside; 'inherits from &lt;Class&gt;, which is
/// not in this project's index -- convert it from its own project' when the chain left
/// the index at a named class; 'inherits &lt;Instance&gt; from an ancestor that is not in
/// this project's index -- convert it from its own project' when it named no ancestor
/// class at all (DeclaringUnit = OUTSIDE_NO_ANCESTOR).</returns>
function OutsideNote(const AVerdict: TInstanceVerdict): string;

/// <summary>Wraps ALookup with a per-class cache (key: the upper-cased class name).</summary>
/// <param name="AInner">The real lookup.</param>
/// <param name="ACache">Owned by the caller; clear it whenever the index changes.</param>
/// <returns>A lookup that asks AInner once per class; a Failed answer is NOT cached.</returns>
function CachingLookup(const AInner: TClassLookup; ACache: TDictionary<string, TClassInfo>): TClassLookup;

/// <summary>PURE: the identifier a `refs` row stands for: the receiver's first segment
/// ('Self.' skipped; cut at '.', '[', '(' or a space), else the name itself.</summary>
/// <param name="AName">refs.name_text.</param>
/// <param name="AReceiver">refs.receiver_text; '' (or 'Self') for an implicit-Self use.</param>
/// <returns>'tblFtrs' for ('IndexName', 'tblFtrs') and for ('Post', 'Self.tblFtrs').</returns>
function CodeUseName(const AName, AReceiver: string): string;

/// <summary>PURE: the converted row's note for E2b code uses the run could not convert
/// (spec E10, editor side -- the engine's inherited[] covers .dfm instances only).</summary>
/// <param name="AUnit">The unit's analysis taken before the run.</param>
/// <param name="AConvertedUnits">Unit names (no path, no extension) converted EARLIER IN
/// THE SAME RUN: their code uses are not counted -- that conversion retyped the field,
/// so the run converted the use too (spec E11 / N2a).</param>
/// <returns>'' for none; else per declaring unit, in first-seen order, 'N inherited code
/// use(s) left: ancestor &lt;U&gt; not converted', joined '; '.</returns>
function CodeUseLeftNote(const AUnit: TUnitInheritance; const AConvertedUnits: TArray<string> = nil): string;

/// <summary>A TDfmTextReader over the real file system (TFile.ReadAllText).</summary>
/// <returns>A reader that answers drMissing for a missing file, drUnreadable when
/// reading raises, else drRead.</returns>
function DiskTextReader: TDfmTextReader;

/// <summary>PURE: the Convert tab's row note for a unit (spec E5, E8).</summary>
/// <param name="AUnit">The unit's analysis.</param>
/// <returns>'' when AUnit is not Known or nothing is unconverted / outside; else, per
/// declaring unit of its asUnconverted verdicts (.dfm instances and E2b code uses alike)
/// in first-seen order, 'inherits N &lt;types&gt; instance(s) from &lt;Unit&gt; --
/// convert it first (recommended)' (types distinct, first-seen, ', '-joined), then per
/// (declaring unit, type found) of its asMismatched verdicts 'inherits N &lt;types&gt;
/// instance(s) from &lt;Unit&gt;, where they are &lt;Found&gt; -- not this book's From or
/// To type', then each distinct OutsideNote of its asOutside verdicts; all joined '; '.</returns>
/// <param name="ARetypeSupported">The engine reports inherited_retype (C8 N2). False
/// (1.22.0): each 'convert it first (recommended)' part gains ' -- with this engine,
/// converting it now breaks this unit until N2' -- converting that ancestor leaves this
/// unit's inherited instances with the From type under an ancestor that has the To type.</param>
/// <remarks>asConverted says nothing (the engine reports it after the run). asUnknown
/// never yields a note: AnalyzeUnit makes such a unit Known = False. The spec E5 wording
/// itself stays verbatim (owner ruling).</remarks>
function InheritanceRowNote(const AUnit: TUnitInheritance; ARetypeSupported: Boolean): string;

/// <summary>PURE: the ancestor units to convert before AUnit (spec E2a / E6): the chain
/// units of its asUnconverted verdicts -- the units whose .dfm declares or re-opens one of
/// its inherited instances (for an E2b code use, also the unit declaring the field) --
/// de-duplicated by path, topmost first. An ancestor that never mentions an instance is
/// not offered.</summary>
/// <param name="AUnit">The unit's analysis.</param>
/// <returns>.pas paths, larger TChainUnit.Depth first (a unit on several chains takes
/// its largest Depth; equal depths keep first-seen order); [] when nothing is
/// unconverted.</returns>
function AncestorChain(const AUnit: TUnitInheritance): TArray<string>;

/// <summary>PURE: the members of AChain not in AList (paths compared as UnitInIndex
/// does: ExpandFileName'd, case-insensitively).</summary>
/// <param name="AChain">AncestorChain's answer.</param>
/// <param name="AList">The source list.</param>
/// <returns>In AChain order.</returns>
function MissingAncestors(const AChain, AList: TArray<string>): TArray<string>;

/// <summary>PURE: the E6 question, 'Add &lt;chain&gt; ahead of &lt;unit&gt;?', with file names.</summary>
/// <param name="AChain">The units the offer would add: MissingAncestors(AncestorChain(unit),
/// source list) -- the chain units not yet listed, topmost first. Not empty.</param>
/// <param name="AUnitPas">The descendant.</param>
/// <param name="ATypes">UnconvertedTypes of the descendant's analysis.</param>
/// <param name="ARetypeSupported">The engine reports inherited_retype (C8 N2).</param>
/// <returns>'Add Base.pas, Mid.pas ahead of Leaf.pas?'; without retype, followed by '
/// Converting Base.pas, Mid.pas leaves Leaf.pas''s inherited instance(s) as TTable,
/// TQuery until engine N2 -- Leaf.pas may not compile or load.'</returns>
/// <remarks>Ancestor-first stays the long-term order and the offer stays (owner ruling:
/// never blocking); until N2 it says what converting the ancestor does to the
/// descendant.</remarks>
function OfferText(const AChain: TArray<string>; const AUnitPas: string; const ATypes: TArray<string>; ARetypeSupported: Boolean): string;

/// <summary>PURE: AList with AChain's missing units inserted so every ancestor precedes its
/// descendants (spec E6 Yes, as amended 2026-10-05).</summary>
/// <param name="AList">The source list.</param>
/// <param name="AUnitPas">The descendant.</param>
/// <param name="AChain">AncestorChain's answer, topmost first.</param>
/// <returns>A new list. Each MISSING chain unit, taken topmost first, goes directly before
/// the earliest LISTED unit among the chain units after it and AUnitPas; appended when none
/// of those is listed. ([Mid, Leaf] + [Base, Mid] gives [Base, Mid, Leaf].)</returns>
/// <remarks>Units already listed are never moved: a pre-existing misorder stays, and E7
/// (OrderWarnings) still warns about it.</remarks>
function InsertAncestors(const AList: TArray<string>; const AUnitPas: string; const AChain: TArray<string>): TArray<string>;

/// <summary>PURE: one line per (listed descendant, listed ancestor of its AncestorChain
/// listed BELOW it) pair (spec E7).</summary>
/// <param name="AList">The source list, run order.</param>
/// <param name="AUnits">The listed units' analyses (any order).</param>
/// <param name="ARetypeSupported">The engine reports inherited_retype (C8 N2).</param>
/// <returns>Per unit in AUnits order, ancestors topmost first: with retype '&lt;Desc.pas&gt;
/// is listed above its ancestor &lt;Anc.pas&gt;, which is not converted yet'; without it
/// '&lt;Desc.pas&gt; is listed above its ancestor &lt;Anc.pas&gt;.' (the order does not
/// change what this engine does -- OrderWarningText says so).</returns>
/// <remarks>A warning, never a refusal: the run converts the descendant's own part
/// either way (E9).</remarks>
function OrderWarnings(const AList: TArray<string>; const AUnits: TArray<TUnitInheritance>; ARetypeSupported: Boolean): TArray<string>;

/// <summary>PURE: the single E7 confirmation text.</summary>
/// <param name="AWarnings">OrderWarnings' lines; not empty.</param>
/// <param name="ARetypeSupported">The engine reports inherited_retype (C8 N2).</param>
/// <returns>With retype: a heading line, the warnings one per line, a blank line, then
/// 'Convert in this order anyway?'. Without it: the warnings one per line, a blank line,
/// then 'With this engine the order does not change this run''s result: inherited
/// instances are skipped either way. Run anyway?' -- no claim that reordering helps.</returns>
function OrderWarningText(const AWarnings: TArray<string>; ARetypeSupported: Boolean): string;

/// <summary>PURE: the status after No to the E7 warning.</summary>
/// <param name="ARetypeSupported">The engine reports inherited_retype (C8 N2).</param>
/// <returns>With retype 'Convert cancelled: reorder the source units (ancestors first)
/// and press Convert again.'; without it 'Convert cancelled: nothing was run.'</returns>
function OrderCancelledText(ARetypeSupported: Boolean): string;

/// <summary>PURE: the distinct instance types of AUnit's asUnconverted verdicts,
/// first-seen order (the E6 offer's types).</summary>
/// <param name="AUnit">The unit's analysis.</param>
/// <returns>Bare type names as the .dfm (or the declaring field) writes them.</returns>
function UnconvertedTypes(const AUnit: TUnitInheritance): TArray<string>;

/// <summary>PURE: the run notes for an engine WITHOUT inherited_instances: today's
/// convert-apply refuses every unit holding an inherited From instance.</summary>
/// <param name="AUnits">The listed units' analyses.</param>
/// <param name="AInheritedSupported">The engine reports inherited_instances.</param>
/// <returns>[] when supported; else one note per Known unit with at least one .dfm
/// verdict, whatever its state ('&lt;Unit.pas&gt;: N inherited instance(s) of a From type
/// -- this engine refuses such a unit (no inherited_instances capability), so it will be
/// left unchanged').</returns>
/// <remarks>FromCode verdicts are not counted: the engine does not refuse on code. A unit
/// that is not Known gets no note, although the engine may still refuse it.</remarks>
function EngineRefusalNotes(const AUnits: TArray<TUnitInheritance>; AInheritedSupported: Boolean): TArray<string>;

implementation

uses
  System.IOUtils
  , System.Math
  , System.StrUtils
  , ConvRules.BlockFile
  , ConvRules.ConvertRun
  , ConvRules.Model
  , ConvRules.Usage
  ;

const
  KW_END       = 'end';
  KW_INLINE    = 'inline';
  KW_INHERITED = 'inherited';
  OPEN_LIST    = '<';
  CLOSE_LIST   = '>';
  OPEN_PARENS  = '(';
  CLOSE_PARENS = ')';
  OPEN_BLOB    = '{';
  CLOSE_BLOB   = '}';
  NO_CHAR      = #0;
  NOTE_OUTSIDE = 'inherits from %s, which is not in this project''s index -- convert it from its own project';
  NOTE_OUTSIDE_NO_ANCESTOR = 'inherits %s from an ancestor that is not in this project''s index -- convert it from its own project';
  REASON_FAILED = 'the project index could not be asked about %s';
  REASON_CYCLE  = 'the ancestor chain loops back to %s';
  REASON_DEPTH  = 'the ancestor chain is longer than %d classes (stopped at %s)';
  REASON_DFM    = 'the .dfm of %s (%s) is binary or cannot be read';
  REASON_NO_CODE_USES = 'the project index could not list the code uses of %s';
  REASON_OF     = '%s: %s';
  REASON_CAUSE  = '%s (%s)';
  NOTE_CODE_LEFT = '%d inherited code use(s) left: ancestor %s not converted';
  NOTE_JOIN     = '; ';
  SELF_WORD     = 'Self';
  TYPE_SEP      = ', ';
  NOTE_UNCONVERTED  = 'inherits %d %s instance(s) from %s -- convert it first (recommended)';
  NOTE_MISMATCHED   = 'inherits %d %s instance(s) from %s, where they are %s -- not this book''s From or To type';
  OFFER_FMT         = 'Add %s ahead of %s?';
  GATE_ASK_FMT      = 'Could not check inherited instances for %s -- convert anyway?';
  GATE_ALL_UNITS    = 'the listed units';
  GATE_STOP_FMT     = 'Convert cancelled: inherited instances could not be checked -- %s';
  ORDER_WARNING_FMT = '%s is listed above its ancestor %s, which is not converted yet';
  ORDER_HEAD        = 'Some units are listed above an ancestor that is not converted yet; their inherited instances will not convert in this run:';
  ORDER_TAIL        = 'Convert in this order anyway?';
  // Until the engine retypes inherited instances (C8 N2): converting an ancestor leaves
  // its descendants' inherited objects with the From type under an ancestor that declares
  // the To type -- they fail at load (EClassNotFound / EReadError) and From-only member
  // uses stop compiling -- and the order does not change what this engine does.
  NOTE_BREAKS_UNTIL_N2 = ' -- with this engine, converting it now breaks this unit until N2';
  OFFER_N1_FMT         = ' Converting %s leaves %s''s inherited instance(s) as %s until engine N2 -- %1:s may not compile or load.';
  ORDER_WARNING_N1_FMT = '%s is listed above its ancestor %s.';
  ORDER_TAIL_N1        = 'With this engine the order does not change this run''s result: inherited instances are skipped either way. Run anyway?';
  ORDER_CANCELLED      = 'Convert cancelled: reorder the source units (ancestors first) and press Convert again.';
  ORDER_CANCELLED_N1   = 'Convert cancelled: nothing was run.';
  REFUSAL_FMT       = '%s: %d inherited instance(s) of a From type -- this engine refuses such a unit (no inherited_instances capability), so it will be left unchanged';

type
  // How one WalkChain ended: a .dfm (or, for a code use, a field) declared the
  // instance; a class is not in the index; an indexed class has no ancestor; the walk
  // could not decide.
  TWalkEnd = (weDeclared, weLeftIndex, weNoAncestor, weUnknown);

  // How one class's .dfm treats an instance name.
  TDfmMatch = (dmNoDfm, dmUnusable, dmNotOpened, dmOpened);

  // What every step of one walk reads. Inst.FromCode selects the E2b rule: the
  // declaration is a TClassInfo.Fields entry, and a .dfm joins the chain when it opens
  // the name with any From type of Pairs (an instance's own type is not known yet).
  // FieldsOnly (code uses only) skips every .dfm: the walk then decides from
  // TClassInfo.Fields alone whether any ancestor declares the name.
  TWalkCtx = record
    Inst      : TInheritedInstance;
    Lookup    : TClassLookup;
    Reader    : TDfmTextReader;
    Pairs     : TArray<TTypePair>;
    FieldsOnly: Boolean;
  end;

  // One TDfmTextReader answer, kept by CachingReader.
  TCachedDfm = record
    Read: TDfmRead;
    Text: string;
  end;

  // One declaring unit (and, for asMismatched, the type found there), how many verdicts
  // name it and their distinct instance types, first-seen (TallyByUnit).
  TUnitTally = record
    UnitName: string;
    Found   : string; // TInstanceVerdict.FoundType: a tally is per (unit, type found)
    Count   : Integer;
    Types   : TArray<string>;
  end;

  // Which verdicts TallyByUnit counts.
  TVerdictFilter = reference to function(const AVerdict: TInstanceVerdict): Boolean;

  // One block header as the walk meets it.
  THeader = record
    Line      : Integer;
    Opener    : TDfmOpener;
    Name      : string;
    TypeName  : string;
    Depth     : Integer; // 0 = the root
    FrameClass: string;  // innermost enclosing inline block's class; '' when none
    ParentType: string;  // immediately enclosing block's class; '' for the root
    Enclosing : TArray<string>; // see TInheritedInstance.Enclosing
  end;
  THeaderProc = reference to procedure(const AHeader: THeader);

function OpenerOf(const AKeyword: string): TDfmOpener;
begin
  if SameText(AKeyword, KW_INLINE) then
    Result:= doInline
  else if SameText(AKeyword, KW_INHERITED) then
    Result:= doInherited
  else
    Result:= doObject;
end;

function CloserOf(AOpen: Char): Char;
begin
  case AOpen of
    OPEN_LIST  : Result:= CLOSE_LIST;
    OPEN_PARENS: Result:= CLOSE_PARENS;
    OPEN_BLOB  : Result:= CLOSE_BLOB;
    else         Result:= NO_CHAR;
  end; // case
end;

function CountOf(const AText: string; AChar: Char): Integer;
begin
  Result:= 0;
  for var LCh: Char in AText do
    if LCh = AChar then
      Inc(Result);
end;

// The open blocks' classes below the root, innermost first, up to (and including)
// the innermost inline block (see TInheritedInstance.Enclosing).
function EnclosingOf(AStack: TList<THeader>): TArray<string>;
begin
  Result:= nil;
  for var K: Integer:= AStack.Count - 1 downto 1 do
  begin
    Result:= Result + [AStack[K].TypeName];
    if AStack[K].Opener = doInline then
      Break;
  end;
end;

// Calls AOnHeader for every block header of a text .dfm, in file order.
procedure WalkDfmHeaders(const AText: string; const AOnHeader: THeaderProc);
var
  Lines    : TArray<TRawLine>;
  Stack    : TList<THeader>; // the open blocks, innermost last
  Cur      : string;
  Val      : string;
  Cls      : string;
  Inst     : string;
  H        : THeader;
  SkipOpen : Char;
  SkipClose: Char;
  SkipDepth: Integer;
  EqPos    : Integer;
begin
  Lines:= SplitRawLines(AText);
  Stack:= TList<THeader>.Create;
  try
    SkipOpen := NO_CHAR;
    SkipClose:= NO_CHAR;
    SkipDepth:= 0;
    for var I: Integer:= 0 to High(Lines) do
    begin
      Cur:= Trim(Lines[I].Text);
      if Cur = '' then
        Continue;
      if SkipDepth > 0 then
      begin
        Val:= StripQuoted(Cur);
        SkipDepth:= SkipDepth + CountOf(Val, SkipOpen) - CountOf(Val, SkipClose);
        Continue;
      end;
      if ParseBlockHeader(Cur, Cls, Inst) then
      begin
        H:= Default(THeader);
        H.Line    := I + 1;
        H.Opener  := OpenerOf(FirstToken(Cur));
        H.Name    := Inst;
        H.TypeName:= Cls;
        H.Depth   := Stack.Count;
        if Stack.Count > 0 then
        begin
          H.ParentType:= Stack.Last.TypeName;
          H.FrameClass:= if Stack.Last.Opener = doInline then Stack.Last.TypeName else Stack.Last.FrameClass;
          H.Enclosing := EnclosingOf(Stack);
        end;
        AOnHeader(H);
        Stack.Add(H);
        Continue;
      end;
      if SameText(FirstToken(Cur), KW_END) then
      begin
        if Stack.Count > 0 then
          Stack.Delete(Stack.Count - 1);
        Continue;
      end;
      // Judged on the quote-stripped line, and only when the left of '=' is a property
      // name: a string continuation line ('abc = (def' +) is no assignment and must not
      // open a list skip that would swallow every header after it.
      Val:= StripQuoted(Cur);
      EqPos:= Pos('=', Val);
      if (EqPos = 0) or not IsPropName(Trim(Copy(Val, 1, EqPos - 1))) then
        Continue;
      Val:= Trim(Copy(Val, EqPos + 1, MaxInt));
      if Val = '' then
        Continue;
      SkipOpen := Val[1];
      SkipClose:= CloserOf(SkipOpen);
      if SkipClose = NO_CHAR then
        Continue;
      SkipDepth:= CountOf(Val, SkipOpen) - CountOf(Val, SkipClose);
    end; // for
  finally
    Stack.Free;
  end; // try
end;

function ScanDfmInheritance(const AText: string): TDfmInheritance;
var
  LScan: TDfmInheritance;
begin
  LScan:= Default(TDfmInheritance);
  if AText.StartsWith(BINARY_DFM_SIGNATURE) then
  begin
    LScan.IsBinary:= True;
    Exit(LScan);
  end;
  WalkDfmHeaders(AText,
    procedure(const AHeader: THeader)
    var
      LItem: TInheritedInstance;
    begin
      if AHeader.Depth = 0 then
      begin
        if LScan.RootClass = '' then
          LScan.RootClass:= AHeader.TypeName;
        Exit;
      end;
      if (AHeader.Opener = doObject) or (AHeader.Name = '') then
        Exit;
      LItem:= Default(TInheritedInstance);
      LItem.Name      := AHeader.Name;
      LItem.TypeName  := AHeader.TypeName;
      LItem.Line      := AHeader.Line;
      LItem.Opener    := AHeader.Opener;
      LItem.FrameClass:= AHeader.FrameClass;
      LItem.ParentType:= if AHeader.Depth = 1 then '' else AHeader.ParentType;
      LItem.Enclosing := AHeader.Enclosing;
      LScan.Instances := LScan.Instances + [LItem];
    end);
  Result:= LScan;
end;

function FindDfmObject(const AText, AName: string; out AOpener: TDfmOpener; out ATypeName: string): Boolean;
var
  LFound : Boolean;
  LOpener: TDfmOpener;
  LType  : string;
begin
  LFound := False;
  LOpener:= doObject;
  LType  := '';
  if not AText.StartsWith(BINARY_DFM_SIGNATURE) then
    WalkDfmHeaders(AText,
      procedure(const AHeader: THeader)
      begin
        if LFound or (AHeader.Depth = 0) or (AHeader.FrameClass <> '') or not SameText(AHeader.Name, AName) then
          Exit;
        LFound := True;
        LOpener:= AHeader.Opener;
        LType  := AHeader.TypeName;
      end);
  AOpener  := LOpener;
  ATypeName:= LType;
  Result   := LFound;
end;

function ListDfmInstances(const AText: string): TArray<TDfmInstance>;
var
  LList: TArray<TDfmInstance>;
begin
  LList:= nil;
  if not AText.StartsWith(BINARY_DFM_SIGNATURE) then
    WalkDfmHeaders(AText,
      procedure(const AHeader: THeader)
      var
        LItem: TDfmInstance;
      begin
        LItem:= Default(TDfmInstance);
        LItem.Name    := AHeader.Name;
        LItem.TypeName:= AHeader.TypeName;
        LItem.Line    := AHeader.Line;
        LItem.Opener  := AHeader.Opener;
        LItem.Depth   := AHeader.Depth;
        LList:= LList + [LItem];
      end);
  Result:= LList;
end;

function BareType(const AType: string): string;
var
  LDot: Integer;
begin
  LDot:= AType.LastIndexOf('.');
  Result:= if LDot < 0 then AType else AType.Substring(LDot + 1);
end;

function TypePairsOfText(const ARulesText: string): TArray<TTypePair>;
var
  Book: TRuleBook;
  Pair: TTypePair;
begin
  Result:= nil;
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(ARulesText);
    for var LIdx: Integer in Book.ConvertHeaders do
    begin
      Pair.FromType:= BareType(Trim(Book.Nodes[LIdx].FromType));
      Pair.ToType  := BareType(Trim(Book.Nodes[LIdx].ToType));
      if Pair.FromType <> '' then
        Result:= Result + [Pair];
    end;
  finally
    Book.Free;
  end; // try
end;

function IsFromType(const AType: string; const APairs: TArray<TTypePair>): Boolean;
begin
  for var LPair: TTypePair in APairs do
    if SameText(BareType(AType), LPair.FromType) then
      Exit(True);
  Result:= False;
end;

function UnitNameOf(const APasPath: string): string;
begin
  Result:= ChangeFileExt(ExtractFileName(APasPath), '');
end;

function ChainUnitOf(const APasPath: string; ADepth: Integer): TChainUnit;
begin
  Result.PasPath:= APasPath;
  Result.Depth  := ADepth;
end;

// How APasPath's .dfm treats AName: no .dfm (a class with no .dfm declares no
// component), binary or unreadable, does not open it, or opens it (AOpener / AType).
function DfmMatch(const APasPath, AName: string; const AReader: TDfmTextReader; out AOpener: TDfmOpener; out AType: string): TDfmMatch;
var
  LText: string;
begin
  AOpener:= doObject;
  AType  := '';
  case AReader(ChangeFileExt(APasPath, DFM_EXT), LText) of
    drMissing   : Result:= dmNoDfm;
    drUnreadable: Result:= dmUnusable;
    else
      if LText.StartsWith(BINARY_DFM_SIGNATURE) then
        Result:= dmUnusable
      else if FindDfmObject(LText, AName, AOpener, AType) then
        Result:= dmOpened
      else
        Result:= dmNotOpened;
  end; // case
end;

// True when AInfo itself declares a field named AName (AType = its declared class).
function DeclaresField(const AInfo: TClassInfo; const AName: string; out AType: string): Boolean;
begin
  for var LField: TFieldDecl in AInfo.Fields do
    if SameText(LField.Name, AName) then
    begin
      AType:= LField.TypeName;
      Exit(True);
    end;
  AType := '';
  Result:= False;
end;

// E2b: AInfo declares the code use's field with AType. A From type is an unconverted
// inherited use, and the declaring unit closes its Chain; any other type is a
// converted ancestor (E11), which AnalyzeUnit drops.
procedure DeclareField(const ACtx: TWalkCtx; const AInfo: TClassInfo; const AType: string; ADepth: Integer; var AVerdict: TInstanceVerdict);
begin
  AVerdict.Instance.TypeName:= AType;
  AVerdict.DeclaringPas     := AInfo.PasPath;
  AVerdict.DeclaringUnit    := UnitNameOf(AInfo.PasPath);
  if not IsFromType(AType, ACtx.Pairs) then
  begin
    AVerdict.State:= asConverted;
    Exit;
  end;
  AVerdict.State:= asUnconverted;
  if (Length(AVerdict.Chain) = 0) or not SameText(AVerdict.Chain[High(AVerdict.Chain)].PasPath, AInfo.PasPath) then
    AVerdict.Chain:= AVerdict.Chain + [ChainUnitOf(AInfo.PasPath, ADepth)];
end;

// True when AObjType is the To type of a pair whose From type is AFromType (bare names,
// case-insensitive): the declaring ancestor was converted with this book.
function IsToTypeOf(const AObjType, AFromType: string; const APairs: TArray<TTypePair>): Boolean;
begin
  for var LPair: TTypePair in APairs do
    if SameText(LPair.FromType, BareType(AFromType)) and (LPair.ToType <> '') and SameText(BareType(LPair.ToType), BareType(AObjType)) then
      Exit(True);
  Result:= False;
end;

// AReason, plus the engine's own failure text in parentheses when there is one.
function WithCause(const AReason, ACause: string): string;
begin
  Result:= if ACause = '' then AReason else Format(REASON_CAUSE, [AReason, ACause]);
end;

// One class of a walk at ADepth. weNoAncestor here means "go on to AParent" (''
// when the class records no ancestor); weDeclared fills AVerdict's state; a unit
// whose .dfm opens AInst with its own type (a code use: with a From type) joins
// AVerdict.Chain. A code use is declared by a field (DeclareField), never by a .dfm.
function VisitClass(const ACtx: TWalkCtx; const AClass: string; ADepth: Integer; var AVerdict: TInstanceVerdict; out AParent, AReason: string): TWalkEnd;
var
  Info   : TClassInfo;
  Opener : TDfmOpener;
  ObjType: string;
  FldType: string;
  Same   : Boolean;
  Match  : TDfmMatch;
begin
  AParent:= '';
  AReason:= '';
  Result := weNoAncestor;
  Info:= ACtx.Lookup(AClass);
  if Info.Failed then
  begin
    AReason:= WithCause(Format(REASON_FAILED, [AClass]), Info.Error);
    Exit(weUnknown);
  end;
  if not Info.Found then
    Exit(weLeftIndex);
  Match:= if ACtx.FieldsOnly then dmNoDfm else DfmMatch(Info.PasPath, ACtx.Inst.Name, ACtx.Reader, Opener, ObjType);
  case Match of
    dmUnusable:
    begin
      AReason:= Format(REASON_DFM, [AClass, ChangeFileExt(Info.PasPath, DFM_EXT)]);
      Result := weUnknown;
    end;
    dmOpened:
    begin
      Same:= if ACtx.Inst.FromCode then IsFromType(ObjType, ACtx.Pairs) else SameText(BareType(ObjType), BareType(ACtx.Inst.TypeName));
      if Same then
        AVerdict.Chain:= AVerdict.Chain + [ChainUnitOf(Info.PasPath, ADepth)];
      if (Opener = doObject) and not ACtx.Inst.FromCode then
      begin
        AVerdict.DeclaringPas := Info.PasPath;
        AVerdict.DeclaringUnit:= UnitNameOf(Info.PasPath);
        if Same then
          AVerdict.State:= asUnconverted
        else if IsToTypeOf(ObjType, ACtx.Inst.TypeName, ACtx.Pairs) then
          AVerdict.State:= asConverted
        else
        begin
          // Neither this book's From nor its To (engine N1 'mismatched'; reverses
          // preflight ruling C4, which read every non-From type as converted).
          AVerdict.State    := asMismatched;
          AVerdict.FoundType:= ObjType;
        end;
        Result:= weDeclared;
      end;
    end;
    else
      ; // no .dfm, or it does not open AInst: go on up
  end; // case
  if (Result = weNoAncestor) and ACtx.Inst.FromCode and DeclaresField(Info, ACtx.Inst.Name, FldType) then
  begin
    DeclareField(ACtx, Info, FldType, ADepth, AVerdict);
    Result:= weDeclared;
  end;
  AParent:= Info.ParentClass;
end;

// Follows the class chain from AStartClass until a .dfm opens AInst with `object`
// (weDeclared), a class is not in the index (weLeftIndex, ALastClass names it), an
// indexed class records no ancestor (weNoAncestor), or the walk cannot decide
// (weUnknown, AReason: failed lookup, cycle, MAX_CHAIN_DEPTH, unusable .dfm).
// ADepth counts on from its value at entry (see TChainUnit.Depth).
function WalkChain(const ACtx: TWalkCtx; const AStartClass: string; var ADepth: Integer; var AVerdict: TInstanceVerdict; out ALastClass, AReason: string): TWalkEnd;
var
  Cls   : string;
  Parent: string;
  Seen  : TArray<string>;
begin
  ALastClass:= '';
  AReason   := '';
  Result    := weNoAncestor;
  Cls       := AStartClass;
  Seen      := nil;
  while (Cls <> '') and (Result = weNoAncestor) do
  begin
    if MatchText(Cls, Seen) then
      AReason:= Format(REASON_CYCLE, [Cls])
    else if Length(Seen) >= MAX_CHAIN_DEPTH then
      AReason:= Format(REASON_DEPTH, [MAX_CHAIN_DEPTH, Cls]);
    if AReason <> '' then
      Exit(weUnknown);
    Seen      := Seen + [Cls];
    ALastClass:= Cls;
    Inc(ADepth);
    Result:= VisitClass(ACtx, Cls, ADepth, AVerdict, Parent, AReason);
    Cls   := Parent;
  end;
end;

// The verdict on ACtx.Inst: the form chain from AStartClass, then the frame fallback
// over ACtx.Inst.Enclosing ([] for a code use), then the walk's ending as a state
// (see ResolveInstance). Instances and E2b code uses share it.
function ResolveWalk(const ACtx: TWalkCtx; const AStartClass: string): TInstanceVerdict;
var
  LEnd     : TWalkEnd;
  LFallEnd : TWalkEnd;
  LLast    : string;
  LIgnored : string;
  LReason  : string;
  LDepth   : Integer;
  LFallback: TInstanceVerdict;
begin
  Result:= Default(TInstanceVerdict);
  Result.Instance:= ACtx.Inst;
  LFallback  := Result;
  LDepth:= 0;
  LEnd  := WalkChain(ACtx, AStartClass, LDepth, Result, LLast, LReason);
  // A child of an inherited FRAME is declared in the frame's own .dfm, which the form
  // chain never reads (FindDfmObject skips inline blocks): try each enclosing block's
  // class, innermost outward. Each try starts from the form chain's verdict, so the
  // forms that re-open the instance stay in Chain, below the frame (Depth counts on).
  LFallEnd:= weNoAncestor;
  for var LClass: string in ACtx.Inst.Enclosing do
  begin
    if (LEnd in [weDeclared, weUnknown]) or (LFallEnd in [weDeclared, weUnknown]) then
      Break;
    if SameText(LClass, AStartClass) then
      Continue;
    LFallback:= Result;
    LFallEnd := WalkChain(ACtx, LClass, LDepth, LFallback, LIgnored, LReason);
  end;
  if LFallEnd in [weDeclared, weUnknown] then
  begin
    Result:= LFallback;
    LEnd  := LFallEnd;
  end;
  if LEnd = weDeclared then
    Exit;
  Result.Chain       := nil;
  Result.DeclaringPas:= '';
  case LEnd of
    weUnknown:
    begin
      Result.State        := asUnknown;
      Result.DeclaringUnit:= '';
      Result.Reason       := LReason;
    end;
    weLeftIndex:
    begin
      Result.State        := asOutside;
      Result.DeclaringUnit:= LLast;
    end;
    else
    begin
      Result.State        := asOutside;
      Result.DeclaringUnit:= OUTSIDE_NO_ANCESTOR;
    end;
  end; // case
end;

function ResolveInstance(const AInst: TInheritedInstance; const AStartClass: string; const ALookup: TClassLookup; const AReader: TDfmTextReader;
  const APairs: TArray<TTypePair>): TInstanceVerdict;
var
  LCtx: TWalkCtx;
begin
  LCtx       := Default(TWalkCtx);
  LCtx.Inst  := AInst;
  LCtx.Lookup:= ALookup;
  LCtx.Reader:= AReader;
  LCtx.Pairs := APairs;
  Result:= ResolveWalk(LCtx, AStartClass);
end;

// E2b: the verdict on one code use, walked from AStartClass (the unit's own class's
// parent) with ResolveWalk. asUnconverted = an inherited use; asUnknown = the walk could
// not decide; asConverted / asOutside = not an inherited use. Two passes over the same
// walk: Fields only first (most code uses -- methods, properties, RTL calls -- are no
// ancestor's field, and that is decidable without reading any .dfm, so an unusable
// ancestor .dfm cannot make them unknown); the .dfm-reading pass, which builds the E2a
// Chain, runs only for a name an ancestor declares.
function ResolveCodeUse(const AUse: TCodeUse; const AStartClass: string; const APairs: TArray<TTypePair>; const ALookup: TClassLookup;
  const AReader: TDfmTextReader): TInstanceVerdict;
var
  LCtx: TWalkCtx;
begin
  LCtx       := Default(TWalkCtx);
  LCtx.Inst.Name    := AUse.Name;
  LCtx.Inst.Line    := AUse.Line;
  LCtx.Inst.Opener  := doInherited;
  LCtx.Inst.FromCode:= True;
  LCtx.Lookup    := ALookup;
  LCtx.Reader    := AReader;
  LCtx.Pairs     := APairs;
  LCtx.FieldsOnly:= True;
  Result:= ResolveWalk(LCtx, AStartClass);
  if Result.State <> asUnconverted then
    Exit;
  LCtx.FieldsOnly:= False;
  Result:= ResolveWalk(LCtx, AStartClass);
end;

// AInner with a per-call cache (key: the upper-cased path), so one AnalyzeUnit reads
// each ancestor .dfm once however many names it walks. ACache is owned by the caller.
function CachingReader(const AInner: TDfmTextReader; ACache: TDictionary<string, TCachedDfm>): TDfmTextReader;
begin
  Result:= function(const APath: string; out AText: string): TDfmRead
    var
      LEntry: TCachedDfm;
    begin
      if not ACache.TryGetValue(UpperCase(APath), LEntry) then
      begin
        LEntry.Read:= AInner(APath, LEntry.Text);
        ACache.Add(UpperCase(APath), LEntry);
      end;
      AText := LEntry.Text;
      Result:= LEntry.Read;
    end;
end;

function CodeUseName(const AName, AReceiver: string): string;
const
  CUT_CHARS: array[0..3] of Char = ('.', '[', '(', ' ');
var
  LRest: string;
  LCut : Integer;
begin
  LRest:= Trim(AReceiver);
  if LRest.StartsWith(SELF_WORD + '.', True) then
    LRest:= LRest.Substring(Length(SELF_WORD) + 1);
  if (LRest = '') or SameText(LRest, SELF_WORD) then
    Exit(AName);
  LCut:= LRest.IndexOfAny(CUT_CHARS);
  Result:= if LCut < 0 then LRest else LRest.Substring(0, LCut);
end;

// True when AVerdicts already holds an instance named AName (no double count).
function Reported(const AVerdicts: TArray<TInstanceVerdict>; const AName: string): Boolean;
begin
  for var LV: TInstanceVerdict in AVerdicts do
    if SameText(LV.Instance.Name, AName) then
      Exit(True);
  Result:= False;
end;

// One entry per name, at its first (lowest) line, in first-seen order.
function FirstUses(const AUses: TArray<TCodeUse>): TArray<TCodeUse>;
var
  LIdx: Integer;
begin
  Result:= nil;
  for var LUse: TCodeUse in AUses do
  begin
    LIdx:= -1;
    for var I: Integer:= 0 to High(Result) do
      if SameText(Result[I].Name, LUse.Name) then
        LIdx:= I;
    if LIdx < 0 then
      Result:= Result + [LUse]
    else if LUse.Line < Result[LIdx].Line then
      Result[LIdx].Line:= LUse.Line;
  end;
end;

// E2b: appends the unit's code uses on an ancestor's From-typed field to
// AResult.Verdicts. False = unknown (AResult.Error says why): the code uses could not
// be listed, or a use's walk could not decide.
function AddCodeUses(var AResult: TUnitInheritance; const AOwn: TClassInfo; const ARootClass: string; const APairs: TArray<TTypePair>;
  const ALookup: TClassLookup; const AReader: TDfmTextReader; const ACodeUses: TCodeUseLookup): Boolean;
var
  LUses   : TArray<TCodeUse>;
  LVerdict: TInstanceVerdict;
  LOwnType: string;
  LError  : string;
begin
  if not ACodeUses(AResult.UnitPas, ARootClass, LUses, LError) then
  begin
    AResult.Error:= WithCause(Format(REASON_NO_CODE_USES, [ARootClass]), LError);
    Exit(False);
  end;
  for var LUse: TCodeUse in FirstUses(LUses) do
  begin
    if Reported(AResult.Verdicts, LUse.Name) or DeclaresField(AOwn, LUse.Name, LOwnType) then
      Continue; // the .dfm already reported it, or the unit's own class declares it
    LVerdict:= ResolveCodeUse(LUse, AOwn.ParentClass, APairs, ALookup, AReader);
    if LVerdict.State = asUnknown then
    begin
      AResult.Error:= Format(REASON_OF, [LUse.Name, LVerdict.Reason]);
      Exit(False); // unknown is never reported as outside, nor dropped
    end;
    if LVerdict.State = asUnconverted then
      AResult.Verdicts:= AResult.Verdicts + [LVerdict];
    // asOutside (no project ancestor declares it) / asConverted (E11): not a use
  end;
  Result:= True;
end;

// AnalyzeUnit's body; AReader is already the per-call caching reader.
function AnalyzeWith(const AUnitPas: string; const APairs: TArray<TTypePair>; const ALookup: TClassLookup; const AReader: TDfmTextReader;
  const ACodeUses: TCodeUseLookup): TUnitInheritance;
var
  LText   : string;
  LScan   : TDfmInheritance;
  LOwn    : TClassInfo;
  LStart  : string;
  LVerdict: TInstanceVerdict;
  LWanted : TArray<TInheritedInstance>;
begin
  Result:= Default(TUnitInheritance);
  Result.UnitPas:= AUnitPas;
  // E3: no checked From type, no readable .dfm, a binary .dfm or no header -- nothing to say.
  if (Length(APairs) > 0) and (AReader(ChangeFileExt(AUnitPas, DFM_EXT), LText) = drRead) then
    LScan:= ScanDfmInheritance(LText)
  else
    LScan:= Default(TDfmInheritance);
  if LScan.IsBinary or (LScan.RootClass = '') then
    Exit;
  LWanted:= nil;
  for var LInst: TInheritedInstance in LScan.Instances do
    if (LInst.Opener = doInherited) and IsFromType(LInst.TypeName, APairs) then
      LWanted:= LWanted + [LInst];
  if (Length(LWanted) = 0) and not Assigned(ACodeUses) then
  begin
    Result.Known:= True; // E3: known, and nothing to record
    Exit;
  end;
  LOwn:= ALookup(LScan.RootClass);
  if LOwn.Failed then
  begin
    Result.Error:= WithCause(Format(REASON_FAILED, [LScan.RootClass]), LOwn.Error);
    Exit;
  end;
  if not LOwn.Found then
    Exit; // the unit itself is not indexed: its row already says so
  for var LInst: TInheritedInstance in LWanted do
  begin
    LStart  := if LInst.FrameClass <> '' then LInst.FrameClass else LOwn.ParentClass;
    LVerdict:= ResolveInstance(LInst, LStart, ALookup, AReader, APairs);
    if LVerdict.State = asUnknown then
    begin
      Result.Error   := Format(REASON_OF, [LInst.Name, LVerdict.Reason]);
      Result.Verdicts:= nil;
      Exit; // unknown is never reported as outside
    end;
    Result.Verdicts:= Result.Verdicts + [LVerdict];
  end;
  Result.Known:= not Assigned(ACodeUses) or AddCodeUses(Result, LOwn, LScan.RootClass, APairs, ALookup, AReader, ACodeUses);
  if not Result.Known then
    Result.Verdicts:= nil; // AddCodeUses set Error: unknown, never a partial answer
end;

function AnalyzeUnit(const AUnitPas: string; const APairs: TArray<TTypePair>; const ALookup: TClassLookup; const AReader: TDfmTextReader;
  const ACodeUses: TCodeUseLookup): TUnitInheritance;
var
  LCache: TDictionary<string, TCachedDfm>;
begin
  LCache:= TDictionary<string, TCachedDfm>.Create;
  try
    Result:= AnalyzeWith(AUnitPas, APairs, ALookup, CachingReader(AReader, LCache), ACodeUses);
  finally
    LCache.Free;
  end; // try
end;

function AnalyzeUnits(const APaths: TArray<string>; const APairs: TArray<TTypePair>; const ALookup: TClassLookup; const AReader: TDfmTextReader;
  const ACodeUses: TCodeUseLookup): TArray<TUnitInheritance>;
var
  LCache : TDictionary<string, TCachedDfm>;
  LReader: TDfmTextReader;
begin
  Result:= nil;
  LCache:= TDictionary<string, TCachedDfm>.Create;
  try
    LReader:= CachingReader(AReader, LCache); // the PASS cache; AnalyzeUnit's own per-call one sits above it
    for var LPath: string in APaths do
      Result:= Result + [AnalyzeUnit(LPath, APairs, ALookup, LReader, ACodeUses)];
  finally
    LCache.Free;
  end; // try
end;

function CancellableLookup(const AInner: TClassLookup; const ACancelled: TFunc<Boolean>): TClassLookup;
begin
  Result:= function(const AClassName: string): TClassInfo
    begin
      if ACancelled() then
      begin
        Result:= Default(TClassInfo);
        Result.Failed:= True;
        Result.Error := ANALYSIS_CANCELLED;
      end
      else
        Result:= AInner(AClassName);
    end;
end;

function CancellableCodeUses(const AInner: TCodeUseLookup; const ACancelled: TFunc<Boolean>): TCodeUseLookup;
begin
  Result:= function(const AUnitPas, AClassName: string; out AUses: TArray<TCodeUse>; out AError: string): Boolean
    begin
      if ACancelled() then
      begin
        AUses := nil;
        AError:= ANALYSIS_CANCELLED;
        Result:= False;
      end
      else
        Result:= AInner(AUnitPas, AClassName, AUses, AError);
    end;
end;

function UnknownUnitsText(const AUnits: TArray<TUnitInheritance>): string;
var
  LMore: Integer;
begin
  Result:= '';
  LMore := 0;
  for var LUnit: TUnitInheritance in AUnits do
  begin
    if LUnit.Error = '' then
      Continue;
    if Result = '' then
      Result:= ExtractFileName(LUnit.UnitPas) + ': ' + LUnit.Error
    else
      Inc(LMore);
  end;
  if LMore > 0 then
    Result:= Result + Format(' (+%d more)', [LMore]);
end;

function InheritanceGate(ACancelled: Boolean; const AUnits: TArray<TUnitInheritance>; const AError: string; out AQuestion: string): TInheritanceGate;
var
  LNames: TArray<string>;
begin
  AQuestion:= '';
  if ACancelled then
    Exit(igCancelled);
  LNames:= nil;
  for var LUnit: TUnitInheritance in AUnits do
    if LUnit.Error <> '' then
      LNames:= LNames + [ExtractFileName(LUnit.UnitPas)];
  if (Length(LNames) = 0) and (AError = '') then
    Exit(igProceed);
  if Length(LNames) = 0 then
    LNames:= [GATE_ALL_UNITS];
  AQuestion:= Format(GATE_ASK_FMT, [string.Join(TYPE_SEP, LNames)]);
  Result:= igAsk;
end;

function InheritanceGateStopText(const AReason: string): string;
begin
  Result:= Format(GATE_STOP_FMT, [AReason]);
end;

// Per declaring unit (and type found), in first-seen order, how many of AVerdicts AWanted accepts and
// their distinct instance types.
function TallyByUnit(const AVerdicts: TArray<TInstanceVerdict>; const AWanted: TVerdictFilter): TArray<TUnitTally>;
var
  LIdx: Integer;
  LNew: TUnitTally;
begin
  Result:= nil;
  for var LVerdict: TInstanceVerdict in AVerdicts do
  begin
    if not AWanted(LVerdict) then
      Continue;
    LIdx:= -1;
    for var I: Integer:= 0 to High(Result) do
      if SameText(Result[I].UnitName, LVerdict.DeclaringUnit) and SameText(Result[I].Found, LVerdict.FoundType) then
        LIdx:= I;
    if LIdx < 0 then
    begin
      LNew.UnitName:= LVerdict.DeclaringUnit;
      LNew.Found   := LVerdict.FoundType;
      LNew.Count   := 0;
      LNew.Types   := nil;
      Result:= Result + [LNew];
      LIdx  := High(Result);
    end;
    Inc(Result[LIdx].Count);
    if not MatchText(LVerdict.Instance.TypeName, Result[LIdx].Types) then
      Result[LIdx].Types:= Result[LIdx].Types + [LVerdict.Instance.TypeName];
  end;
end;

function CodeUseLeftNote(const AUnit: TUnitInheritance; const AConvertedUnits: TArray<string>): string;
var
  LParts    : TArray<string>;
  LConverted: TArray<string>;
begin
  LParts    := nil;
  LConverted:= AConvertedUnits;
  for var LTally: TUnitTally in TallyByUnit(AUnit.Verdicts,
    function(const AVerdict: TInstanceVerdict): Boolean
    begin
      Result:= AVerdict.Instance.FromCode and (AVerdict.State = asUnconverted) and not MatchText(AVerdict.DeclaringUnit, LConverted);
    end) do
    LParts:= LParts + [Format(NOTE_CODE_LEFT, [LTally.Count, LTally.UnitName])];
  Result:= string.Join(NOTE_JOIN, LParts);
end;

function OutsideNote(const AVerdict: TInstanceVerdict): string;
begin
  if AVerdict.State <> asOutside then
    Result:= ''
  else if AVerdict.DeclaringUnit = OUTSIDE_NO_ANCESTOR then
    Result:= Format(NOTE_OUTSIDE_NO_ANCESTOR, [AVerdict.Instance.Name])
  else
    Result:= Format(NOTE_OUTSIDE, [AVerdict.DeclaringUnit]);
end;

function InheritanceRowNote(const AUnit: TUnitInheritance; ARetypeSupported: Boolean): string;
var
  LParts: TArray<string>;
  LNote : string;
begin
  if not AUnit.Known then
    Exit('');
  LParts:= nil;
  for var LTally: TUnitTally in TallyByUnit(AUnit.Verdicts,
    function(const AVerdict: TInstanceVerdict): Boolean
    begin
      Result:= AVerdict.State = asUnconverted;
    end) do
    LParts:= LParts + [Format(NOTE_UNCONVERTED, [LTally.Count, string.Join(TYPE_SEP, LTally.Types), LTally.UnitName])
      + (if ARetypeSupported then '' else NOTE_BREAKS_UNTIL_N2)];
  for var LTally: TUnitTally in TallyByUnit(AUnit.Verdicts,
    function(const AVerdict: TInstanceVerdict): Boolean
    begin
      Result:= AVerdict.State = asMismatched;
    end) do
    LParts:= LParts + [Format(NOTE_MISMATCHED, [LTally.Count, string.Join(TYPE_SEP, LTally.Types), LTally.UnitName, LTally.Found])];
  for var LVerdict: TInstanceVerdict in AUnit.Verdicts do
  begin
    LNote:= OutsideNote(LVerdict);
    if (LNote <> '') and not MatchText(LNote, LParts) then
      LParts:= LParts + [LNote];
  end;
  Result:= string.Join(NOTE_JOIN, LParts);
end;

function AncestorChain(const AUnit: TUnitInheritance): TArray<string>;
var
  LUnits: TArray<TChainUnit>;
  LIdx  : Integer;
  LKey  : TChainUnit;
  J     : Integer;
begin
  LUnits:= nil;
  Result:= nil; // the paths of LUnits, kept in step for PathIndex
  for var LVerdict: TInstanceVerdict in AUnit.Verdicts do
    if LVerdict.State = asUnconverted then
      for var LLink: TChainUnit in LVerdict.Chain do
      begin
        LIdx:= PathIndex(LLink.PasPath, Result);
        if LIdx >= 0 then
          LUnits[LIdx].Depth:= Max(LUnits[LIdx].Depth, LLink.Depth)
        else
        begin
          LUnits:= LUnits + [LLink];
          Result:= Result + [LLink.PasPath];
        end;
      end;
  // Topmost first: a STABLE insertion sort on Depth, descending (TArray.Sort is not stable).
  for var I: Integer:= 1 to High(LUnits) do
  begin
    LKey:= LUnits[I];
    J   := I - 1;
    while (J >= 0) and (LUnits[J].Depth < LKey.Depth) do
    begin
      LUnits[J + 1]:= LUnits[J];
      Dec(J);
    end;
    LUnits[J + 1]:= LKey;
  end;
  for var I: Integer:= 0 to High(LUnits) do
    Result[I]:= LUnits[I].PasPath;
end;

function MissingAncestors(const AChain, AList: TArray<string>): TArray<string>;
begin
  Result:= nil;
  for var LPas: string in AChain do
    if PathIndex(LPas, AList) < 0 then
      Result:= Result + [LPas];
end;

function OfferText(const AChain: TArray<string>; const AUnitPas: string; const ATypes: TArray<string>; ARetypeSupported: Boolean): string;
var
  LNames: TArray<string>;
begin
  LNames:= nil;
  for var LPas: string in AChain do
    LNames:= LNames + [ExtractFileName(LPas)];
  Result:= Format(OFFER_FMT, [string.Join(TYPE_SEP, LNames), ExtractFileName(AUnitPas)]);
  if not ARetypeSupported then
    Result:= Result + Format(OFFER_N1_FMT, [string.Join(TYPE_SEP, LNames), ExtractFileName(AUnitPas), string.Join(TYPE_SEP, ATypes)]);
end;

function InsertAncestors(const AList: TArray<string>; const AUnitPas: string; const AChain: TArray<string>): TArray<string>;
var
  LPos: Integer;
  LAt : Integer;
begin
  Result:= Copy(AList);
  for var I: Integer:= 0 to High(AChain) do
  begin
    if PathIndex(AChain[I], Result) >= 0 then
      Continue; // listed already: never moved
    LPos:= PathIndex(AUnitPas, Result);
    for var J: Integer:= I + 1 to High(AChain) do
    begin
      LAt:= PathIndex(AChain[J], Result);
      if (LAt >= 0) and ((LPos < 0) or (LAt < LPos)) then
        LPos:= LAt;
    end;
    if LPos < 0 then
      Result:= Result + [AChain[I]]
    else
      Insert(AChain[I], Result, LPos);
  end;
end;

function OrderWarnings(const AList: TArray<string>; const AUnits: TArray<TUnitInheritance>; ARetypeSupported: Boolean): TArray<string>;
var
  LPos: Integer;
begin
  Result:= nil;
  for var LUnit: TUnitInheritance in AUnits do
  begin
    LPos:= PathIndex(LUnit.UnitPas, AList);
    if LPos < 0 then
      Continue;
    for var LPas: string in AncestorChain(LUnit) do
      if PathIndex(LPas, AList) > LPos then
        Result:= Result + [Format(if ARetypeSupported then ORDER_WARNING_FMT else ORDER_WARNING_N1_FMT, [ExtractFileName(LUnit.UnitPas), ExtractFileName(LPas)])];
  end;
end;

function OrderWarningText(const AWarnings: TArray<string>; ARetypeSupported: Boolean): string;
begin
  if ARetypeSupported then
    Result:= ORDER_HEAD + sLineBreak + string.Join(sLineBreak, AWarnings) + sLineBreak + sLineBreak + ORDER_TAIL
  else
    Result:= string.Join(sLineBreak, AWarnings) + sLineBreak + sLineBreak + ORDER_TAIL_N1;
end;

function OrderCancelledText(ARetypeSupported: Boolean): string;
begin
  Result:= if ARetypeSupported then ORDER_CANCELLED else ORDER_CANCELLED_N1;
end;

function UnconvertedTypes(const AUnit: TUnitInheritance): TArray<string>;
begin
  Result:= nil;
  for var LVerdict: TInstanceVerdict in AUnit.Verdicts do
    if (LVerdict.State = asUnconverted) and not MatchText(LVerdict.Instance.TypeName, Result) then
      Result:= Result + [LVerdict.Instance.TypeName];
end;

function EngineRefusalNotes(const AUnits: TArray<TUnitInheritance>; AInheritedSupported: Boolean): TArray<string>;
var
  LDfm: Integer;
begin
  Result:= nil;
  if AInheritedSupported then
    Exit;
  for var LUnit: TUnitInheritance in AUnits do
  begin
    if not LUnit.Known then
      Continue;
    LDfm:= 0; // the engine refuses on .dfm instances only; an E2b code use does not trigger it
    for var LVerdict: TInstanceVerdict in LUnit.Verdicts do
      if not LVerdict.Instance.FromCode then
        Inc(LDfm);
    if LDfm > 0 then
      Result:= Result + [Format(REFUSAL_FMT, [ExtractFileName(LUnit.UnitPas), LDfm])];
  end;
end;

function CachingLookup(const AInner: TClassLookup; ACache: TDictionary<string, TClassInfo>): TClassLookup;
begin
  Result:= function(const AClassName: string): TClassInfo
    begin
      if ACache.TryGetValue(UpperCase(AClassName), Result) then
        Exit;
      Result:= AInner(AClassName);
      if not Result.Failed then
        ACache.AddOrSetValue(UpperCase(AClassName), Result);
    end;
end;

function DiskTextReader: TDfmTextReader;
begin
  Result:= function(const APath: string; out AText: string): TDfmRead
    begin
      AText:= '';
      if not TFile.Exists(APath) then
        Exit(drMissing);
      try
        AText := TFile.ReadAllText(APath);
        Result:= drRead;
      except  // reported as drUnreadable: the analysis runs on drops and must never raise
        on Exception do
          Result:= drUnreadable;
      end; // try
    end;
end;

end.
