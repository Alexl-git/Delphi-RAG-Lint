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
  /// <remarks>Ordered = True only when every unordered rule of the unit header failed to hold; then
  /// RunSite is the top-level `Application.Run` statement of the program block and CreateSite the
  /// CreateForm statement of the handler's form. WhyNot is '' exactly when Ordered.</remarks>
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
  /// <remarks>Owns its caches, not the index. Not thread-safe (the shared parse cache).</remarks>
  THbHandlerOrderer = class
  strict private
    type
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
    function ProgramFacts(pProgramBlockId: Int64): TProgramFacts;
    function ReadProgram(pProgramBlockId: Int64): TProgramFacts;
    function SourceLine(const pPath: string; pLine: Integer): string;
    function BindingsOf(const pClass, pMethod: string; out pBindings, pEvents: TArray<string>): Boolean;
    function CodeRefCount(pRoutineId: Int64; const pMethod: string): Integer;
  public
    /// <summary>Creates an orderer over an open index.</summary>
    /// <param name="pIndex">The project index; must stay open while the orderer lives. Not owned.</param>
    constructor Create(const pIndex: TChartsIndex);
    /// <summary>Frees the caches (not the index).</summary>
    destructor Destroy; override;
    /// <summary>The top-level `Application.Run` statement of a program block.</summary>
    /// <param name="pProgramBlockId">symbols.id of the program symbol (its main block).</param>
    /// <param name="pSite">Out: the statement start (1-based line and column, file of the program).</param>
    /// <returns>False when the id is no program or its block has no unconditional top-level
    /// Application.Run; the solver then asks no prefix state.</returns>
    function RunSiteOf(pProgramBlockId: Int64; out pSite: THbSite): Boolean;
    /// <summary>Judges one escaped routine against one program (rules of the unit header).</summary>
    /// <param name="pProgramBlockId">symbols.id of the program symbol; 0 = no program known.</param>
    /// <param name="pRoutineId">symbols.id of the routine (normally a dfm-event escaped root).</param>
    /// <returns>The order; Ordered = False with WhyNot set for every doubt. Never raises for an unknown id.</returns>
    function OrderOf(pProgramBlockId, pRoutineId: Int64): THbHandlerOrder;
  end;

/// <summary>True when an event property name belongs to the OnCreate family (HB_UNORDERED_EVENTS or a
/// HB_UNORDERED_EVENT_PREFIXES prefix), or is empty / unknown ('?').</summary>
/// <param name="pEvent">The property name as the form file writes it, e.g. 'OnClick'.</param>
/// <returns>True = a handler bound to it is never ordered.</returns>
function HbIsUnorderedEvent(const pEvent: string): Boolean;

/// <summary>True when a handler method name is one of HB_UNORDERED_HANDLER_NAMES.</summary>
/// <param name="pName">The bare method name, e.g. 'FormCreate'.</param>
/// <returns>True = the handler is never ordered, whatever it is bound to.</returns>
function HbIsUnorderedHandlerName(const pName: string): Boolean;

/// <summary>The text an answer shows when a use relied on the order of pOrder: it names the handler,
/// its bindings and the program-block statements the order hangs on, and says it is a name heuristic.</summary>
/// <param name="pOrder">An Ordered handler order.</param>
/// <returns>One line, e.g. 'relies on handler order: hoMain.TMainForm.btnGoClick (fired by
/// MainForm.btnGo.OnClick) runs only after the program-block prefix of HandlersOrder (Application.Run at
/// HandlersOrder.dpr:17) -- name heuristic, OnCreate family excluded'.</returns>
function HbReliedText(const pOrder: THbHandlerOrder): string;

/// <summary>The "why not SET" text of a use whose root is an ordered handler entered with the bit
/// False: the prefix of the program does not write the target on every path.</summary>
/// <param name="pOrder">An Ordered handler order.</param>
/// <param name="pTarget">The target's display name (e.g. 'GLate').</param>
/// <returns>One line naming the handler, its bindings, the program and the Application.Run statement.</returns>
function HbPrefixMissText(const pOrder: THbHandlerOrder; const pTarget: string): string;

implementation

uses
  System.SysUtils
, System.Classes
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
  Result:= if (pLine >= 1) and (pLine <= Length(L)) then L[pLine - 1] else '';
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
    Site.Col:= Integer(L.Node.StartPoint.column) + 1;
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
  var R:= FIndex.Query('SELECT (SELECT COUNT(*) FROM refs WHERE kind <> ''event-binding'' AND (symbol_id = ' + Id +
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

function THbHandlerOrderer.OrderOf(pProgramBlockId, pRoutineId: Int64): THbHandlerOrder;
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

end.
