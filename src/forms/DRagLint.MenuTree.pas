unit DRagLint.MenuTree;

/// <summary>Code-built menu reader (spec docs\superpowers\specs\2026-10-23-code-built-menu-reader-design.md):
/// the menu tree a Delphi program BUILDS IN CODE, recovered statically. This
/// part holds the model (TMenuNode / TMenuTree), the caption and path keys
/// that must equal featuregen's CaptionKey / MenuKey, and the three renderings
/// (paths, text, menu-tree/1 JSON).</summary>
/// <remarks>Engine only; the CLI verbs menu-tree and menu-drift are thin
/// wrappers. Not thread-safe; one tree per run.</remarks>

interface

uses
  System.SysUtils
  , System.Generics.Collections
  ;

type
  /// <summary>What a node of a code-built menu is (spec 4.1).</summary>
  TMenuNodeKind = (mnkRoot, mnkSubmenu, mnkItem, mnkSeparator, mnkHeader, mnkDynamic, mnkExternalRoot);

  /// <summary>How the reader knows a node (spec 4.4): certain = literal caption,
  /// direct parenting or a recognised helper; derived = const / case expansion
  /// or a callback binding; unknown = a caption it could not evaluate.</summary>
  TMenuConfidence = (mcCertain, mcDerived, mcUnknown);

  /// <summary>One node of a code-built menu. Owns its children.</summary>
  /// <remarks>Caption is the text as written ('&amp;&amp;' kept); the display
  /// form ('&amp;&amp;' -> '&amp;') is what paths show. Ident is the foreign
  /// identifier of an external root, empty otherwise.</remarks>
  TMenuNode = class
  private
    FChildren  : TObjectList<TMenuNode>;
    FParent    : TMenuNode;
    FKind      : TMenuNodeKind;
    FCaption   : string;
    FHandler   : string;
    FSource    : string;
    FConfidence: TMenuConfidence;
    FIdent     : string;
    FDisabled  : Boolean;
    FHasClick  : Boolean;
    FParented  : Boolean;
    procedure AttachTo(pParent: TMenuNode);
  public
    /// <summary>The node's kind.</summary>
    property Kind: TMenuNodeKind read FKind write FKind;
    /// <summary>Caption as written ('&amp;&amp;' kept).</summary>
    property Caption: string read FCaption write FCaption;
    /// <summary>Qualified routine the OnClick ends in; '' when none.</summary>
    property Handler: string read FHandler write FHandler;
    /// <summary>file:line of the statement that made the node.</summary>
    property Source: string read FSource write FSource;
    /// <summary>How the reader knows the node.</summary>
    property Confidence: TMenuConfidence read FConfidence write FConfidence;
    /// <summary>Foreign identifier of an external root; '' otherwise.</summary>
    property Ident: string read FIdent write FIdent;
    /// <summary>Walker state: Enabled := False was seen.</summary>
    property Disabled: Boolean read FDisabled write FDisabled;
    /// <summary>Walker state: an OnClick was assigned.</summary>
    property HasClick: Boolean read FHasClick write FHasClick;
    /// <summary>Walker state: the node was placed under a parent or made a root.</summary>
    property Parented: Boolean read FParented write FParented;
    /// <summary>Creates a node.</summary>
    /// <param name="pKind">Initial kind; the walker settles it in TMenuTree.Finish.</param>
    /// <param name="pCaption">Caption as written.</param>
    /// <param name="pSource">file:line of the statement that made the node.</param>
    constructor Create(pKind: TMenuNodeKind; const pCaption, pSource: string);
    destructor Destroy; override;
    /// <summary>Appends pChild (takes ownership) and returns it.</summary>
    function AddChild(pChild: TMenuNode): TMenuNode;
    /// <summary>Inserts pChild at pIndex (clamped to 0..Count; takes ownership) and returns it.</summary>
    function InsertChild(pIndex: Integer; pChild: TMenuNode): TMenuNode;
    /// <summary>The children, in sibling order.</summary>
    function Children: TObjectList<TMenuNode>;
    /// <summary>The parent node, nil for a root or external root.</summary>
    function Parent: TMenuNode;
    /// <summary>Caption with '&amp;&amp;' shown as '&amp;' (what a user reads).</summary>
    function DisplayCaption: string;
    /// <summary>MenuCaptionKey of the caption.</summary>
    function CaptionKey: string;
    /// <summary>True for the kinds that end a path: item and dynamic.</summary>
    function IsLeaf: Boolean;
  end;

  /// <summary>One leaf of the tree, flattened (paths format and drift input).</summary>
  TMenuLeaf = record
    /// <summary>Display path, segments joined with ' > '.</summary>
    Path      : string;
    /// <summary>Display path of the parent.</summary>
    ParentPath: string;
    Caption   : string;
    Handler   : string;
    Source    : string;
    Kind      : TMenuNodeKind;
    Confidence: TMenuConfidence;
    /// <summary>True when the leaf sits under an external root.</summary>
    External  : Boolean;
  end;

  /// <summary>The code-built menus of one run: roots, external roots and notes.
  /// Owns every node.</summary>
  TMenuTree = class
  private
    FRoots   : TObjectList<TMenuNode>;
    FExternal: TObjectList<TMenuNode>;
    FNotes   : TList<string>;
    procedure CollectLeaves(pNode: TMenuNode; const pPrefix: string; pExternal: Boolean; pAcc: TList<TMenuLeaf>);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Adds a new root node and returns it.</summary>
    function AddRoot(const pCaption, pSource: string): TMenuNode;
    /// <summary>Adopts pNode (already created) as a root.</summary>
    procedure AdoptRoot(pNode: TMenuNode);
    /// <summary>The external root for pIdent, created on first use.</summary>
    function ExternalRoot(const pIdent, pSource: string): TMenuNode;
    /// <summary>Adds a note line (dynamic caption, unparented item, ...).</summary>
    procedure AddNote(const pNote: string);
    function Roots: TObjectList<TMenuNode>;
    function External: TObjectList<TMenuNode>;
    function Notes: TList<string>;
    /// <summary>Every leaf (kind item or dynamic) in tree order, roots first,
    /// then external roots.</summary>
    function Leaves: TArray<TMenuLeaf>;
    /// <summary>paths format: one leaf per line,
    /// path TAB handler TAB file:line TAB confidence; external roots follow,
    /// each after a '## external &lt;ident&gt;' line.</summary>
    function ToPaths: string;
    /// <summary>Indented tree: [kind] caption  -> handler  (file:line, confidence).</summary>
    function ToText: string;
    /// <summary>menu-tree/1 JSON (spec 8).</summary>
    /// <param name="pEngine">Engine version string.</param>
    /// <param name="pProject">The --project path.</param>
    /// <param name="pDb">The project DB path.</param>
    function ToJson(const pEngine, pProject, pDb: string): string;
  end;

  /// <summary>Raised when a file the walk needs changed since it was indexed
  /// (the CLI maps it to exit 3). The message carries the reindex command.</summary>
  EMenuTreeStale = class(Exception);

  /// <summary>Raised for a setup problem: the project is not in the DB, or
  /// --root names no routine (the CLI maps it to exit 2).</summary>
  EMenuTreeSetup = class(Exception);

  /// <summary>The static reader (spec 4): finds builder routines through the
  /// project DB and re-parses only their files with tree-sitter to recover
  /// the code-built menu tree.</summary>
  /// <remarks>Read-only on the DB. Not thread-safe. Files are parsed at most
  /// once per walker.</remarks>
  TMenuWalker = class
  private
    FImpl: TObject;
  public
    /// <summary>Opens the project DB read-only.</summary>
    /// <param name="pDbs">Index DBs; the first is the project DB (the others are not read in v1).</param>
    /// <param name="pProject">The .dproj (or .dpr) the DB indexes; named in the reindex hint.</param>
    /// <exception cref="EMenuTreeSetup">pDbs is empty, or no indexed file lies under the project's folder.</exception>
    constructor Create(const pDbs: TArray<string>; const pProject: string);
    destructor Destroy; override;
    /// <summary>Walks every builder routine (or only pRootQName and what it
    /// reaches) and returns the tree. The caller owns the result.</summary>
    /// <param name="pRootQName">Qualified name of one builder; '' = all.</param>
    /// <exception cref="EMenuTreeStale">A file the walk parsed changed since it was indexed.</exception>
    /// <exception cref="EMenuTreeSetup">pRootQName names no routine with a body.</exception>
    function Walk(const pRootQName: string = ''): TMenuTree;
  end;

/// <summary>Caption key, identical to featuregen's CaptionKey (spec 6):
/// '&amp;&amp;' -> '&amp;', '...' -> space, each of ` * " -> space, collapse
/// whitespace, trim, trim . , ; : ) ( from both ends, lowercase.</summary>
/// <param name="pCaption">A caption as written or displayed.</param>
/// <returns>The key; '' for a caption that is only punctuation.</returns>
function MenuCaptionKey(const pCaption: string): string;

/// <summary>Path key, identical to featuregen's MenuKey: the segments split on
/// whitespace-'>'-whitespace, each MenuCaptionKey'd, empty ones dropped,
/// joined with ' > '.</summary>
/// <param name="pPath">A display path such as 'drag-lint > Reports > Who calls...'.</param>
function MenuPathKey(const pPath: string): string;

/// <summary>The JSON / text name of a kind ('root', 'submenu', 'item', ...).</summary>
function MenuKindName(pKind: TMenuNodeKind): string;

/// <summary>The JSON / text name of a confidence ('certain', 'derived', 'unknown').</summary>
function MenuConfidenceName(pConfidence: TMenuConfidence): string;

implementation

uses
  System.JSON
  , System.DateUtils
  , System.RegularExpressions
  , System.StrUtils
  , System.IOUtils
  , System.Hash
  , Data.DB
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Storage.SQLite
  ;

const
  PATH_SEP = ' > ';
  KIND_NAMES: array[TMenuNodeKind] of string = ('root', 'submenu', 'item', 'separator', 'header', 'dynamic', 'external-root');
  CONFIDENCE_NAMES: array[TMenuConfidence] of string = ('certain', 'derived', 'unknown');

function MenuCaptionKey(const pCaption: string): string;
var
  S: string;
begin
  S:= pCaption.Replace('&&', '&');
  S:= S.Replace('...', ' ');
  S:= TRegEx.Replace(S, '[`*"]', ' ');
  S:= TRegEx.Replace(S, '\s+', ' ');
  Result:= LowerCase(S.Trim.Trim(['.', ',', ';', ':', ')', '(']));
end;

function MenuPathKey(const pPath: string): string;
var
  Seg, K: string;
  Parts : TList<string>;
begin
  Parts:= TList<string>.Create;
  try
    for Seg in TRegEx.Split(pPath, '\s+>\s+') do
    begin
      K:= MenuCaptionKey(Seg);
      if K <> '' then Parts.Add(K);
    end;
    Result:= string.Join(PATH_SEP, Parts.ToArray);
  finally
    Parts.Free;
  end;
end;

function MenuKindName(pKind: TMenuNodeKind): string;
begin
  Result:= KIND_NAMES[pKind];
end;

function MenuConfidenceName(pConfidence: TMenuConfidence): string;
begin
  Result:= CONFIDENCE_NAMES[pConfidence];
end;

{ ---- TMenuNode ---- }

constructor TMenuNode.Create(pKind: TMenuNodeKind; const pCaption, pSource: string);
begin
  inherited Create;
  FChildren := TObjectList<TMenuNode>.Create(True);
  Kind      := pKind;
  Caption   := pCaption;
  Source    := pSource;
  Confidence:= mcCertain;
end;

destructor TMenuNode.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

function TMenuNode.AddChild(pChild: TMenuNode): TMenuNode;
begin
  FChildren.Add(pChild);
  pChild.AttachTo(Self);
  Result:= pChild;
end;

function TMenuNode.InsertChild(pIndex: Integer; pChild: TMenuNode): TMenuNode;
var
  I: Integer;
begin
  I:= pIndex;
  if I < 0 then I:= 0;
  if I > FChildren.Count then I:= FChildren.Count;
  FChildren.Insert(I, pChild);
  pChild.AttachTo(Self);
  Result:= pChild;
end;

procedure TMenuNode.AttachTo(pParent: TMenuNode);
begin
  FParent  := pParent;
  FParented:= pParent <> nil;
end;

function TMenuNode.Children: TObjectList<TMenuNode>;
begin
  Result:= FChildren;
end;

function TMenuNode.Parent: TMenuNode;
begin
  Result:= FParent;
end;

function TMenuNode.DisplayCaption: string;
begin
  Result:= Caption.Replace('&&', '&');
end;

function TMenuNode.CaptionKey: string;
begin
  Result:= MenuCaptionKey(Caption);
end;

function TMenuNode.IsLeaf: Boolean;
begin
  Result:= Kind in [mnkItem, mnkDynamic];
end;

{ ---- TMenuTree ---- }

constructor TMenuTree.Create;
begin
  inherited Create;
  FRoots   := TObjectList<TMenuNode>.Create(True);
  FExternal:= TObjectList<TMenuNode>.Create(True);
  FNotes   := TList<string>.Create;
end;

destructor TMenuTree.Destroy;
begin
  FNotes.Free;
  FExternal.Free;
  FRoots.Free;
  inherited Destroy;
end;

function TMenuTree.AddRoot(const pCaption, pSource: string): TMenuNode;
begin
  Result:= TMenuNode.Create(mnkRoot, pCaption, pSource);
  AdoptRoot(Result);
end;

procedure TMenuTree.AdoptRoot(pNode: TMenuNode);
begin
  pNode.Kind    := mnkRoot;
  pNode.Parented:= True;
  FRoots.Add(pNode);
end;

function TMenuTree.ExternalRoot(const pIdent, pSource: string): TMenuNode;
var
  N: TMenuNode;
begin
  for N in FExternal do
    if SameText(N.Ident, pIdent) then Exit(N);
  Result:= TMenuNode.Create(mnkExternalRoot, pIdent, pSource);
  Result.Ident   := pIdent;
  Result.Parented:= True;
  FExternal.Add(Result);
end;

procedure TMenuTree.AddNote(const pNote: string);
begin
  FNotes.Add(pNote);
end;

function TMenuTree.Roots: TObjectList<TMenuNode>;
begin
  Result:= FRoots;
end;

function TMenuTree.External: TObjectList<TMenuNode>;
begin
  Result:= FExternal;
end;

function TMenuTree.Notes: TList<string>;
begin
  Result:= FNotes;
end;

procedure TMenuTree.CollectLeaves(pNode: TMenuNode; const pPrefix: string; pExternal: Boolean; pAcc: TList<TMenuLeaf>);
var
  C   : TMenuNode;
  Path: string;
  L   : TMenuLeaf;
begin
  for C in pNode.Children do
  begin
    Path:= pPrefix + PATH_SEP + C.DisplayCaption;
    if C.IsLeaf then
    begin
      L:= Default(TMenuLeaf);
      L.Path      := Path;
      L.ParentPath:= pPrefix;
      L.Caption   := C.Caption;
      L.Handler   := C.Handler;
      L.Source    := C.Source;
      L.Kind      := C.Kind;
      L.Confidence:= C.Confidence;
      L.External  := pExternal;
      pAcc.Add(L);
    end;
    if C.Children.Count > 0 then CollectLeaves(C, Path, pExternal, pAcc);
  end;
end;

function TMenuTree.Leaves: TArray<TMenuLeaf>;
var
  Acc: TList<TMenuLeaf>;
  N  : TMenuNode;
begin
  Acc:= TList<TMenuLeaf>.Create;
  try
    for N in FRoots do CollectLeaves(N, N.DisplayCaption, False, Acc);
    for N in FExternal do CollectLeaves(N, N.Ident, True, Acc);
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function TMenuTree.ToPaths: string;
var
  SB     : TStringBuilder;
  L      : TMenuLeaf;
  LastExt: string;
  Ext    : string;
begin
  SB:= TStringBuilder.Create;
  try
    LastExt:= '';
    for L in Leaves do
    begin
      if L.External then
      begin
        Ext:= L.Path.Split([PATH_SEP])[0];
        if not SameText(Ext, LastExt) then SB.Append('## external ').Append(Ext).Append(sLineBreak);
        LastExt:= Ext;
      end;
      SB.Append(L.Path).Append(#9).Append(L.Handler).Append(#9).Append(L.Source).Append(#9)
        .Append(MenuConfidenceName(L.Confidence)).Append(sLineBreak);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function TMenuTree.ToText: string;
var
  SB: TStringBuilder;

  procedure Emit(pNode: TMenuNode; pDepth: Integer);
  var
    C: TMenuNode;
  begin
    SB.Append(StringOfChar(' ', 2 * pDepth)).Append('[').Append(MenuKindName(pNode.Kind)).Append('] ');
    if pNode.Kind <> mnkSeparator then SB.Append(pNode.DisplayCaption);
    if pNode.Handler <> '' then SB.Append('  -> ').Append(pNode.Handler);
    SB.Append('  (').Append(pNode.Source).Append(', ').Append(MenuConfidenceName(pNode.Confidence)).Append(')').Append(sLineBreak);
    for C in pNode.Children do Emit(C, pDepth + 1);
  end;

var
  N: TMenuNode;
  S: string;
begin
  SB:= TStringBuilder.Create;
  try
    for N in FRoots do Emit(N, 0);
    for N in FExternal do Emit(N, 0);
    for S in FNotes do SB.Append('NOTE ').Append(S).Append(sLineBreak);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function NodeJson(pNode: TMenuNode): TJSONObject;
var
  Arr: TJSONArray;
  C  : TMenuNode;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('kind', MenuKindName(pNode.Kind));
  if pNode.Kind = mnkExternalRoot then Result.AddPair('ident', pNode.Ident)
  else if pNode.Kind <> mnkSeparator then
  begin
    Result.AddPair('caption', pNode.Caption);
    Result.AddPair('captionKey', pNode.CaptionKey);
  end;
  if pNode.Handler <> '' then Result.AddPair('handler', pNode.Handler);
  Result.AddPair('source', pNode.Source);
  Result.AddPair('confidence', MenuConfidenceName(pNode.Confidence));
  if pNode.Children.Count > 0 then
  begin
    Arr:= TJSONArray.Create;
    for C in pNode.Children do Arr.AddElement(NodeJson(C));
    Result.AddPair('children', Arr);
  end;
end;

function TMenuTree.ToJson(const pEngine, pProject, pDb: string): string;
var
  O  : TJSONObject;
  Arr: TJSONArray;
  N  : TMenuNode;
  S  : string;
begin
  O:= TJSONObject.Create;
  try
    O.AddPair('schema', 'menu-tree/1');
    O.AddPair('engine', pEngine);
    O.AddPair('project', pProject);
    O.AddPair('db', pDb);
    O.AddPair('generated', DateToISO8601(Now, False));
    Arr:= TJSONArray.Create;
    for N in FRoots do Arr.AddElement(NodeJson(N));
    O.AddPair('roots', Arr);
    Arr:= TJSONArray.Create;
    for N in FExternal do Arr.AddElement(NodeJson(N));
    O.AddPair('external', Arr);
    Arr:= TJSONArray.Create;
    for S in FNotes do Arr.Add(S);
    O.AddPair('notes', Arr);
    Result:= O.Format(2);
  finally
    O.Free;
  end;
end;

{ ---- the walker (spec 4) ---- }

type
  TWalkEnv = class;

  /// <summary>What an expression evaluates to, as far as menus care.</summary>
  TMVKind = (mvNone, mvNil, mvNode, mvCaptions, mvHandler, mvProc, mvWrapper, mvForeign);

  TMValue = record
    Kind    : TMVKind;
    Node    : TMenuNode;
    Captions: TArray<string>;
    Conf    : TMenuConfidence;
    Handler : string;
    { Source text of the expression (foreign identifier, dynamic caption). }
    Text    : string;
    { File the text came from: handler / const lookups resolve there. }
    Path    : string;
    { mvProc: an anonymous method (ProcNode non-null) with its captured env,
      or a routine reference (ProcRoutine). }
    ProcNode   : TTSNode;
    ProcPath   : string;
    ProcEnv    : TWalkEnv;
    ProcRoutine: string;
  end;

  TWalkEnv = class
  private
    FVars: TDictionary<string, TMValue>;
  public
    constructor Create;
    property Vars: TDictionary<string, TMValue> read FVars;
    destructor Destroy; override;
  end;

  TWalkFile = class
  private
    FPath    : string;
    FSrc     : TBytes;
    FRoot    : TTSNode;
    FDefProcs: TList<TTSNode>;
  public
    constructor Create(const pPath: string; const pSrc: TBytes; const pRoot: TTSNode);
    property Path: string read FPath;
    property Src: TBytes read FSrc;
    property Root: TTSNode read FRoot;
    property DefProcs: TList<TTSNode> read FDefProcs;
    destructor Destroy; override;
  end;

  TRoutineInfo = record
    Found : Boolean;
    QName : string;
    Path  : string;
    Line  : Integer;
  end;

  /// <summary>One activation: the file it runs in, its variables, the call
  /// site that entered it ('' for a top-level builder) and whether it was
  /// reached through a callback binding (derived confidence).</summary>
  TWalkFrame = record
    F      : TWalkFile;
    Env    : TWalkEnv;
    Site   : string;
    Derived: Boolean;
    Depth  : Integer;
  end;

  /// <summary>What a call runs: the parameter list and body (of a routine or
  /// an anonymous method), its file, the captured env of an anonymous method
  /// (nil for a routine), the call site and how it was reached.</summary>
  TCallee = record
    ArgsDecl: TTSNode;
    Body    : TTSNode;
    F       : TWalkFile;
    Env     : TWalkEnv;
    Site    : string;
    Derived : Boolean;
    Depth   : Integer;
  end;

  TWalkCore = class  // dl:ok high-response@2a94 -- the walker is one interpreter over one CST: eval, call binding, parenting and the index lookups share the env and file caches, and splitting would hand the same calls to a second class
  private
    FStore     : TSQLiteSymbolStore;
    FProject   : string;
    FDbPath    : string;
    FTree      : TMenuTree;
    FFiles     : TObjectDictionary<string, TWalkFile>;
    FEnvs      : TObjectList<TWalkEnv>;
    FCreated   : TList<TMenuNode>;
    FCreatedNil: TList<TMenuNode>;
    FMenuTypes : TList<string>;
    FRoutines  : TDictionary<string, TRoutineInfo>;
    FStack     : TList<string>;
    function Q(const pSql: string; const pParams: array of string): TFDQuery;
    procedure LoadMenuTypes;
    function IsMenuType(const pName: string): Boolean;
    function LoadFile(const pPath: string): TWalkFile;
    function FindDefProc(pFile: TWalkFile; pLine: Integer): TTSNode;
    function Text(const pFrame: TWalkFrame; const pNode: TTSNode): string;
    function Loc(const pFrame: TWalkFrame; const pNode: TTSNode): string;
    function NewEnv: TWalkEnv;
    function ResolveRoutine(const pName, pFromPath: string): TRoutineInfo;
    function QualifyHandler(const pText, pFromPath: string): string;
    function ConstDecl(const pName, pFromPath: string; out pFile: TWalkFile): TTSNode;
    function IsMenuTypedForeign(const pIdent, pFromPath: string): Boolean;
    function CaptionOf(const pNode: TTSNode; const pFrame: TWalkFrame): TMValue;
    function LiteralFunctionCaptions(const pName, pFromPath: string; out pCaptions: TArray<string>): Boolean;
    function ConstArrayCaptions(const pArr, pField, pFromPath: string; out pCaptions: TArray<string>): Boolean;
    function Eval(const pNode: TTSNode; const pFrame: TWalkFrame): TMValue;
    function EvalArg(const pNode: TTSNode; const pFrame: TWalkFrame): TMValue;
    function EvalCall(const pNode: TTSNode; const pFrame: TWalkFrame): TMValue;
    function HandlerOf(const pValue: TMValue): string;
    function CreateNode(const pCall: TTSNode; const pFrame: TWalkFrame): TMValue;
    procedure Parenting(const pReceiver, pArgs: TTSNode; pInsert: Boolean; const pFrame: TWalkFrame);
    procedure SetProp(pTarget: TMenuNode; const pProp: string; const pRhs, pStmt: TTSNode; const pFrame: TWalkFrame);
    function Invoke(const pCallee: TCallee; const pArgs: TArray<TMValue>): TMValue;
    function InvokeExpanded(const pCallee: TCallee; const pArgs: TArray<TMValue>): TMValue;
    function InvokeRoutine(const pInfo: TRoutineInfo; const pArgs: TArray<TMValue>; const pSite: string;
      pDerived: Boolean; pDepth: Integer): TMValue;
    procedure WalkStmt(const pNode: TTSNode; const pFrame: TWalkFrame);
    procedure Settle(pNode: TMenuNode);
    procedure FreeOrphans(pNote: Boolean);
    procedure Finish;
  public
    constructor Create(const pDb, pProject: string);
    destructor Destroy; override;
    function Walk(const pRootQName: string): TMenuTree;
  end;

const
  MAX_DEPTH = 8;
  ROUTINE_KINDS = '''procedure'',''function'',''method'',''constructor'',''destructor''';
  { Statement kinds whose named children are walked as statements (spec 4.2,
    "if .. then .. else": both branches; loops: the body once). }
  COMPOUND_KINDS: array[0..12] of string = ('block', 'statements', 'if', 'ifElse', 'for', 'foreach', 'while',
    'repeat', 'case', 'caseCase', 'try', 'exceptionHandler', 'with');

function NodeLine(const pNode: TTSNode): Integer;
begin
  Result:= Integer(pNode.StartPoint.Row) + 1;
end;

function IsCompound(const pKind: string): Boolean;
var
  K: string;
begin
  for K in COMPOUND_KINDS do
    if K = pKind then Exit(True);
  Result:= False;
end;

function LastSegment(const pText: string): string;
var
  I: Integer;
begin
  I:= pText.LastIndexOf('.');
  Result:= if I >= 0 then pText.Substring(I + 1) else pText;
end;

{ Delphi string literal text -> value: 'a''b' -> a'b, #65 -> A, adjacent parts joined. }
function DecodeLiteral(const pText: string): string;
var
  I, J, Code: Integer;
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    I:= 1;
    while I <= Length(pText) do
    begin
      if pText[I] = '''' then
      begin
        Inc(I);
        while I <= Length(pText) do
        begin
          if pText[I] = '''' then
          begin
            if (I < Length(pText)) and (pText[I + 1] = '''') then
            begin
              SB.Append('''');
              Inc(I, 2);
              Continue;
            end;
            Inc(I);
            Break;
          end;
          SB.Append(pText[I]);
          Inc(I);
        end;
      end
      else if pText[I] = '#' then
      begin
        J:= I + 1;
        while (J <= Length(pText)) and CharInSet(pText[J], ['0'..'9', '$', 'a'..'f', 'A'..'F']) do Inc(J);
        if TryStrToInt(Copy(pText, I + 1, J - I - 1), Code) then SB.Append(Char(Code));
        I:= J;
      end
      else Inc(I);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function MaxConf(pA, pB: TMenuConfidence): TMenuConfidence;
begin
  Result:= if Ord(pA) > Ord(pB) then pA else pB;
end;

function NoValue: TMValue;
begin
  Result:= Default(TMValue);
  Result.Kind:= mvNone;
end;

{ TWalkEnv / TWalkFile }

constructor TWalkEnv.Create;
begin
  inherited Create;
  FVars:= TDictionary<string, TMValue>.Create;
end;

destructor TWalkEnv.Destroy;
begin
  FVars.Free;
  inherited Destroy;
end;

constructor TWalkFile.Create(const pPath: string; const pSrc: TBytes; const pRoot: TTSNode);
begin
  inherited Create;
  FPath    := pPath;
  FSrc     := pSrc;
  FRoot    := pRoot;
  FDefProcs:= TList<TTSNode>.Create;
end;

destructor TWalkFile.Destroy;
begin
  FDefProcs.Free;
  inherited Destroy;
end;

{ TWalkCore }

constructor TWalkCore.Create(const pDb, pProject: string);
var
  QF : TFDQuery;
  Dir: string;
begin
  inherited Create;
  FDbPath    := pDb;
  FProject   := pProject;
  FStore     := TSQLiteSymbolStore.Create(pDb, True);
  FFiles     := TObjectDictionary<string, TWalkFile>.Create([doOwnsValues]);
  FEnvs      := TObjectList<TWalkEnv>.Create(True);
  FCreated   := TList<TMenuNode>.Create;
  FCreatedNil:= TList<TMenuNode>.Create;
  FMenuTypes := TList<string>.Create;
  FRoutines  := TDictionary<string, TRoutineInfo>.Create;
  FStack     := TList<string>.Create;
  { spec 5: exit 2 when the project is not in the DB -- at least one indexed
    file must lie under the project's folder. }
  Dir:= IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(pProject)));
  QF:= Q('SELECT COUNT(*) AS n FROM files WHERE lower(path) LIKE :p', [LowerCase(Dir) + '%']);
  try
    if QF.FieldByName('n').AsInteger = 0 then
      raise EMenuTreeSetup.CreateFmt('project not in db: no indexed file under %s (index it: drag-lint index --project "%s" --db "%s")',
        [Dir, pProject, pDb]);
  finally
    QF.Free;
  end;
  LoadMenuTypes;
end;

destructor TWalkCore.Destroy;
begin
  FStack.Free;
  FRoutines.Free;
  FMenuTypes.Free;
  FCreatedNil.Free;
  FCreated.Free;
  FEnvs.Free;
  FFiles.Free;
  FStore.Free;
  inherited Destroy;
end;

function TWalkCore.Q(const pSql: string; const pParams: array of string): TFDQuery;
var
  I: Integer;
begin
  Result:= TFDQuery.Create(nil);
  try
    Result.Connection:= FStore.GetConnection;
    Result.SQL.Text:= pSql;
    for I:= 0 to High(pParams) do Result.Params[I].AsString:= pParams[I];
    Result.Open;  // dl:ok dataset-open-without-close@f8d5 -- Q hands the OPEN query to its caller, which frees it in a finally (Free closes the cursor)
  except
    on Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

{ spec 4.2 row 1: any class whose ancestry includes TMenuItem counts. }
procedure TWalkCore.LoadMenuTypes;
var
  QA     : TFDQuery;
  Grew   : Boolean;
  Pairs  : TList<TPair<string, string>>;
  Pair   : TPair<string, string>;
  NameFld, AncFld: TField;
begin
  FMenuTypes.Add('TMenuItem');
  Pairs:= TList<TPair<string, string>>.Create;
  try
    QA:= Q('SELECT s.name AS n, a.ancestor_name AS a FROM type_ancestors a JOIN symbols s ON s.id = a.symbol_id', []);
    try
      NameFld:= QA.FieldByName('n');
      AncFld := QA.FieldByName('a');
      while not QA.Eof do
      begin
        Pairs.Add(TPair<string, string>.Create(NameFld.AsString, AncFld.AsString));
        QA.Next;
      end;
    finally
      QA.Free;
    end;
    repeat
      Grew:= False;
      for Pair in Pairs do
        if IsMenuType(Pair.Value) and not IsMenuType(Pair.Key) then
        begin
          FMenuTypes.Add(Pair.Key);
          Grew:= True;
        end;
    until not Grew;
  finally
    Pairs.Free;
  end;
end;

function TWalkCore.IsMenuType(const pName: string): Boolean;
var
  S: string;
begin
  for S in FMenuTypes do
    if SameText(S, LastSegment(pName)) then Exit(True);
  Result:= False;
end;

{ spec 5: exit 3 on a stale index -- a file whose bytes changed since it was
  indexed is refused, never answered from. Same sha basis as the indexer. }
function TWalkCore.LoadFile(const pPath: string): TWalkFile;
var
  QF  : TFDQuery;
  Sha : string;
  PF  : TParsedFile;
  WF  : TWalkFile;

  procedure Collect(const pNode: TTSNode);
  var
    I: Integer;
  begin
    if pNode.IsNull then Exit;
    if pNode.NodeType = 'defProc' then WF.DefProcs.Add(pNode);
    for I:= 0 to pNode.NamedChildCount - 1 do Collect(pNode.NamedChild(I));
  end;

begin
  if FFiles.TryGetValue(LowerCase(pPath), Result) then Exit;
  QF:= Q('SELECT sha256 AS s FROM files WHERE lower(path) = :p', [LowerCase(pPath)]);
  try
    Sha:= if QF.Eof then '' else QF.FieldByName('s').AsString;
  finally
    QF.Free;
  end;
  if (Sha = '') or not TFile.Exists(pPath)
    or not SameText(Sha, THashSHA2.GetHashString(TEncoding.ANSI.GetString(TFile.ReadAllBytes(pPath)))) then
    raise EMenuTreeStale.CreateFmt('%s changed since it was indexed; reindex first: drag-lint index --project "%s" --db "%s"',
      [pPath, FProject, FDbPath]);
  PF:= TAstParseCache.Get(pPath);
  WF:= TWalkFile.Create(pPath, PF.Src, PF.Tree.RootNode);
  FFiles.Add(LowerCase(pPath), WF);
  Collect(WF.Root);
  Result:= WF;
end;

function TWalkCore.FindDefProc(pFile: TWalkFile; pLine: Integer): TTSNode;
var
  N   : TTSNode;
  Best: Int64;
begin
  Result:= Default(TTSNode);
  Best:= High(Int64);
  for N in pFile.DefProcs do
    if (NodeLine(N) <= pLine) and (Integer(N.EndPoint.Row) + 1 >= pLine)
      and (Int64(N.EndByte) - Int64(N.StartByte) < Best) then
    begin
      Best:= Int64(N.EndByte) - Int64(N.StartByte);
      Result:= N;
    end;
end;

function TWalkCore.Text(const pFrame: TWalkFrame; const pNode: TTSNode): string;
var
  S, L: Integer;
begin
  Result:= '';
  if pNode.IsNull then Exit;
  S:= Integer(pNode.StartByte);
  L:= Integer(pNode.EndByte) - S;
  if (L > 0) and (S + L <= Length(pFrame.F.Src)) then Result:= TEncoding.UTF8.GetString(pFrame.F.Src, S, L);
end;

function TWalkCore.Loc(const pFrame: TWalkFrame; const pNode: TTSNode): string;
begin
  Result:= ExtractFileName(pFrame.F.Path) + ':' + IntToStr(NodeLine(pNode));
end;

function TWalkCore.NewEnv: TWalkEnv;
begin
  Result:= TWalkEnv.Create;
  FEnvs.Add(Result);
end;

function TWalkCore.ResolveRoutine(const pName, pFromPath: string): TRoutineInfo;
var
  QR : TFDQuery;
  Key: string;
begin
  Key:= LowerCase(pName + '|' + pFromPath);
  if FRoutines.TryGetValue(Key, Result) then Exit;
  Result:= Default(TRoutineInfo);
  QR:= Q('SELECT s.qualified_name AS q, f.path AS p, s.impl_start_line AS l FROM symbols s JOIN files f ON f.id = s.file_id '
    + 'WHERE s.name = :n COLLATE NOCASE AND s.impl_start_line > 0 AND s.kind IN (' + ROUTINE_KINDS + ') '
    + 'ORDER BY (lower(f.path) = :f) DESC, s.id LIMIT 1', [pName, LowerCase(pFromPath)]);
  try
    if not QR.Eof then
    begin
      Result.Found:= True;
      Result.QName:= QR.FieldByName('q').AsString;
      Result.Path := QR.FieldByName('p').AsString;
      Result.Line := QR.FieldByName('l').AsInteger;
    end;
  finally
    QR.Free;
  end;
  FRoutines.Add(Key, Result);
end;

function TWalkCore.QualifyHandler(const pText, pFromPath: string): string;
var
  QH   : TFDQuery;
  Name : string;
  Owner: string;
  I    : Integer;
begin
  Name := LastSegment(pText);
  Owner:= '';
  I:= pText.LastIndexOf('.');
  if I > 0 then Owner:= LastSegment(pText.Substring(0, I));
  if SameText(Owner, 'Self') then Owner:= '';
  QH:= Q('SELECT s.qualified_name AS q FROM symbols s JOIN files f ON f.id = s.file_id '
    + 'WHERE s.name = :n COLLATE NOCASE AND s.kind IN (' + ROUTINE_KINDS + ') '
    + 'ORDER BY (lower(s.qualified_name) LIKE :o) DESC, (lower(f.path) = :f) DESC, s.id LIMIT 1',
    [Name, '%.' + LowerCase(Owner) + '.' + LowerCase(Name), LowerCase(pFromPath)]);
  try
    Result:= if QH.Eof then pText else QH.FieldByName('q').AsString;
  finally
    QH.Free;
  end;
end;

function TWalkCore.ConstDecl(const pName, pFromPath: string; out pFile: TWalkFile): TTSNode;
var
  QC  : TFDQuery;
  Path: string;
  Line: Integer;

  function Find(const pNode: TTSNode): TTSNode;
  var
    I: Integer;
    N: TTSNode;
  begin
    Result:= Default(TTSNode);
    if pNode.IsNull then Exit;
    if (pNode.NodeType = 'declConst') and (NodeLine(pNode) = Line) then
    begin
      N:= pNode.ChildByField('name');
      if SameText(TEncoding.UTF8.GetString(pFile.Src, Integer(N.StartByte), Integer(N.EndByte) - Integer(N.StartByte)), pName) then
        Exit(pNode);
    end;
    for I:= 0 to pNode.NamedChildCount - 1 do
    begin
      Result:= Find(pNode.NamedChild(I));
      if not Result.IsNull then Exit;
    end;
  end;

begin
  Result:= Default(TTSNode);
  pFile:= nil;
  QC:= Q('SELECT f.path AS p, s.start_line AS l FROM symbols s JOIN files f ON f.id = s.file_id '
    + 'WHERE s.name = :n COLLATE NOCASE AND s.kind = ''const'' ORDER BY (lower(f.path) = :f) DESC, s.id LIMIT 1',
    [pName, LowerCase(pFromPath)]);
  try
    if QC.Eof then Exit;
    Path:= QC.FieldByName('p').AsString;
    Line:= QC.FieldByName('l').AsInteger;
  finally
    QC.Free;
  end;
  pFile:= LoadFile(Path);
  Result:= Find(pFile.Root);
end;

{ spec 4.6: a foreign parent must be a menu-typed component, field or
  variable -- a TObjectList<TMenuItem> that holds items for teardown is not.
  An identifier the index does not know is accepted (an inline var). }
function TWalkCore.IsMenuTypedForeign(const pIdent, pFromPath: string): Boolean;
var
  QI : TFDQuery;
  Sig: string;
begin
  QI:= Q('SELECT s.signature AS g FROM symbols s JOIN files f ON f.id = s.file_id '
    + 'WHERE s.name = :n COLLATE NOCASE AND s.kind IN (''field'',''var'',''local_var'',''component'',''param'') '
    + 'ORDER BY (lower(f.path) = :f) DESC, s.id LIMIT 1', [LastSegment(pIdent), LowerCase(pFromPath)]);
  try
    if QI.Eof then Exit(True);
    Sig:= QI.FieldByName('g').AsString.Trim;
  finally
    QI.Free;
  end;
  Result:= IsMenuType(Sig) or TRegEx.IsMatch(Sig, '^T\w*Menu$', [roIgnoreCase]);
end;

{ spec 4.3 case/if row: F's body assigns only literals to Result (or Exit('lit')). }
function TWalkCore.LiteralFunctionCaptions(const pName, pFromPath: string; out pCaptions: TArray<string>): Boolean;
var
  Info   : TRoutineInfo;
  WF     : TWalkFile;
  Proc   : TTSNode;
  Fr     : TWalkFrame;
  Literal: Boolean;
  Any    : Boolean;

  procedure Scan(const pNode: TTSNode);
  var
    I     : Integer;
    L, R  : TTSNode;
    V     : string;
  begin
    if pNode.IsNull or not Literal then Exit;
    if pNode.NodeType = 'lambda' then Exit;
    if pNode.NodeType = 'assignment' then
    begin
      L:= pNode.ChildByField('lhs');
      if (L.NodeType = 'identifier') and SameText(Text(Fr, L), 'Result') then
      begin
        R:= pNode.ChildByField('rhs');
        if R.NodeType <> 'literalString' then
        begin
          Literal:= False;
          Exit;
        end;
        V:= DecodeLiteral(Text(Fr, R));
        Any:= True;
        if IndexStr(V, pCaptions) < 0 then pCaptions:= pCaptions + [V];
      end;
    end;
    for I:= 0 to pNode.NamedChildCount - 1 do Scan(pNode.NamedChild(I));
  end;

begin
  pCaptions:= nil;
  Result:= False;
  Info:= ResolveRoutine(pName, pFromPath);
  if not Info.Found then Exit;
  WF:= LoadFile(Info.Path);
  Proc:= FindDefProc(WF, Info.Line);
  if Proc.IsNull then Exit;
  Fr:= Default(TWalkFrame);
  Fr.F:= WF;
  Literal:= True;
  Any:= False;
  Scan(Proc.ChildByField('body'));
  Result:= Literal and Any;
end;

{ spec 4.3 ARR[I].Field row: one caption per element, element order. }
function TWalkCore.ConstArrayCaptions(const pArr, pField, pFromPath: string; out pCaptions: TArray<string>): Boolean;
var
  WF  : TWalkFile;
  Decl: TTSNode;
  Fr  : TWalkFrame;

  procedure Scan(const pNode: TTSNode);
  var
    I   : Integer;
    Name: TTSNode;
    V   : TTSNode;
  begin
    if pNode.IsNull then Exit;
    if pNode.NodeType = 'recInitializerField' then
    begin
      Name:= pNode.ChildByField('name');
      V   := pNode.ChildByField('value');
      if SameText(Text(Fr, Name), pField) then
      begin
        if V.NodeType = 'literalString' then pCaptions:= pCaptions + [DecodeLiteral(Text(Fr, V))]
        else Result:= False;
      end;
      Exit;
    end;
    for I:= 0 to pNode.NamedChildCount - 1 do Scan(pNode.NamedChild(I));
  end;

begin
  pCaptions:= nil;
  Decl:= ConstDecl(pArr, pFromPath, WF);
  if Decl.IsNull then Exit(False);
  Fr:= Default(TWalkFrame);
  Fr.F:= WF;
  Result:= True;
  Scan(Decl.ChildByField('defaultValue'));
  Result:= Result and (Length(pCaptions) > 0);
end;

{ spec 4.3: caption evaluation. Never raises; what it cannot see is dynamic. }
function TWalkCore.CaptionOf(const pNode: TTSNode; const pFrame: TWalkFrame): TMValue;  // dl:ok too-many-exit-points@5a76 -- a dispatch on the CST node kind: one guard-and-exit per recognised shape of spec 4.2 / 4.3, kept flat so each row maps to one branch
var
  K       : string;
  A, B    : TMValue;
  E, Args : TTSNode;
  Caps    : TArray<string>;
  WF      : TWalkFile;
  Decl, DV: TTSNode;
  Fr      : TWalkFrame;
  I       : Integer;

  function Dyn(const pText: string): TMValue;
  begin
    Result:= NoValue;
    Result.Kind:= mvForeign;
    Result.Text:= pText;
    Result.Conf:= mcUnknown;
  end;

  function Caps1(const pCaps: TArray<string>; pConf: TMenuConfidence): TMValue;
  begin
    Result:= NoValue;
    Result.Kind    := mvCaptions;
    Result.Captions:= pCaps;
    Result.Conf    := pConf;
  end;

begin
  Result:= Dyn(Text(pFrame, pNode));
  if pNode.IsNull then Exit;
  K:= pNode.NodeType;
  if K = 'literalString' then Exit(Caps1([DecodeLiteral(Text(pFrame, pNode))], mcCertain));
  if K = 'exprParens' then Exit(CaptionOf(pNode.NamedChild(0), pFrame));
  if (K = 'exprBinary') and (pNode.ChildByField('operator').NodeType = 'kAdd') then
  begin
    A:= CaptionOf(pNode.ChildByField('lhs'), pFrame);
    B:= CaptionOf(pNode.ChildByField('rhs'), pFrame);
    if (A.Kind = mvCaptions) and (B.Kind = mvCaptions) and (Length(A.Captions) = 1) and (Length(B.Captions) = 1) then
      Exit(Caps1([A.Captions[0] + B.Captions[0]], MaxConf(A.Conf, B.Conf)));
    Exit;
  end;
  if K = 'identifier' then
  begin
    if pFrame.Env.Vars.TryGetValue(LowerCase(Text(pFrame, pNode)), A) then
    begin
      if A.Kind = mvCaptions then Exit(A);
      if (A.Kind = mvForeign) and (A.Text <> '') and (A.Conf = mcUnknown) then Exit(A);
      Exit;
    end;
    { const identifier declared with a literal }
    Decl:= ConstDecl(Text(pFrame, pNode), pFrame.F.Path, WF);
    if not Decl.IsNull then
    begin
      DV:= Decl.ChildByField('defaultValue');
      Fr:= Default(TWalkFrame);
      Fr.F:= WF;
      for I:= 0 to DV.NamedChildCount - 1 do
        if DV.NamedChild(I).NodeType = 'literalString' then
          Exit(Caps1([DecodeLiteral(Text(Fr, DV.NamedChild(I)))], mcCertain));
    end;
    Exit;
  end;
  if K = 'exprCall' then
  begin
    E   := pNode.ChildByField('entity');
    Args:= pNode.ChildByField('args');
    if E.NodeType <> 'identifier' then Exit;
    { Format('pattern', [...]) keeps the pattern }
    if SameText(Text(pFrame, E), 'Format') and not Args.IsNull and (Args.NamedChildCount > 0)
      and (Args.NamedChild(0).NodeType = 'literalString') then
      Exit(Caps1([DecodeLiteral(Text(pFrame, Args.NamedChild(0)))], mcCertain));
    if LiteralFunctionCaptions(Text(pFrame, E), pFrame.F.Path, Caps) then Exit(Caps1(Caps, mcDerived));
    Exit;
  end;
  if K = 'exprDot' then
  begin
    { ARR[I].Field over a const array of records }
    E:= pNode.ChildByField('lhs');
    if (E.NodeType = 'exprSubscript') and (E.ChildByField('entity').NodeType = 'identifier')
      and ConstArrayCaptions(Text(pFrame, E.ChildByField('entity')), Text(pFrame, pNode.ChildByField('rhs')), pFrame.F.Path, Caps) then
      Exit(Caps1(Caps, mcDerived));
  end;
end;

function TWalkCore.EvalArg(const pNode: TTSNode; const pFrame: TWalkFrame): TMValue;
var
  C: TMValue;
begin
  { a bound parameter / local passes through as bound (its text and file stay the call site's) }
  if (pNode.NodeType = 'identifier') and pFrame.Env.Vars.TryGetValue(LowerCase(Text(pFrame, pNode)), Result) then Exit;
  Result:= Eval(pNode, pFrame);
  if Result.Kind in [mvNode, mvProc, mvWrapper, mvHandler, mvCaptions, mvNil] then Exit;
  C:= CaptionOf(pNode, pFrame);
  if C.Kind = mvCaptions then Exit(C);
  { keep the call-site text: a dynamic caption names it, a handler resolves it here }
  Result.Kind:= mvForeign;
  Result.Text:= if C.Text <> '' then C.Text else Text(pFrame, pNode);
  Result.Path:= pFrame.F.Path;
  Result.Conf:= mcUnknown;
end;

function TWalkCore.HandlerOf(const pValue: TMValue): string;
begin
  case pValue.Kind of
    mvHandler, mvWrapper: Result:= pValue.Handler;
    mvForeign           : Result:= QualifyHandler(pValue.Text, pValue.Path);
    mvProc              : Result:= if pValue.ProcRoutine <> '' then pValue.ProcRoutine else '<anonymous method>';
  else
    Result:= '';
  end;
end;

function TWalkCore.Eval(const pNode: TTSNode; const pFrame: TWalkFrame): TMValue;  // dl:ok too-many-exit-points@7c98 -- a dispatch on the CST node kind: one guard-and-exit per recognised shape of spec 4.2 / 4.3, kept flat so each row maps to one branch
var
  K   : string;
  L   : TTSNode;
  LV  : TMValue;
begin
  Result:= NoValue;
  if pNode.IsNull then Exit;
  K:= pNode.NodeType;
  if K = 'kNil' then
  begin
    Result.Kind:= mvNil;
    Exit;
  end;
  if K = 'exprParens' then Exit(Eval(pNode.NamedChild(0), pFrame));
  if K = 'literalString' then Exit(CaptionOf(pNode, pFrame));
  if K = 'lambda' then
  begin
    Result.Kind    := mvProc;
    Result.ProcNode:= pNode;
    Result.ProcPath:= pFrame.F.Path;
    Result.ProcEnv := pFrame.Env;
    Exit;
  end;
  if K = 'identifier' then
  begin
    if pFrame.Env.Vars.TryGetValue(LowerCase(Text(pFrame, pNode)), Result) then Exit;
    Result.Kind:= mvForeign;
    Result.Text:= Text(pFrame, pNode);
    Result.Path:= pFrame.F.Path;
    Exit;
  end;
  if K = 'exprCall' then Exit(EvalCall(pNode, pFrame));
  if K = 'exprDot' then
  begin
    L:= pNode.ChildByField('lhs');
    { W.HandleClick where W wraps a handler: followed one level (spec 4.2) }
    if L.NodeType = 'exprCall' then LV:= Eval(L, pFrame)
    else if L.NodeType = 'identifier' then
    begin
      if not pFrame.Env.Vars.TryGetValue(LowerCase(Text(pFrame, L)), LV) then LV:= NoValue;
    end
    else LV:= NoValue;
    if LV.Kind = mvWrapper then
    begin
      Result.Kind   := mvHandler;
      Result.Handler:= LV.Handler;
      Exit;
    end;
    Result.Kind:= mvForeign;
    Result.Text:= Text(pFrame, pNode);
    Result.Path:= pFrame.F.Path;
    Exit;
  end;
  Result.Kind:= mvForeign;
  Result.Text:= Text(pFrame, pNode);
  Result.Path:= pFrame.F.Path;
end;

function TWalkCore.CreateNode(const pCall: TTSNode; const pFrame: TWalkFrame): TMValue;
var
  Args : TTSNode;
  N    : TMenuNode;
begin
  Args:= pCall.ChildByField('args');
  N:= TMenuNode.Create(mnkItem, '', if pFrame.Site <> '' then pFrame.Site else Loc(pFrame, pCall));
  if pFrame.Derived then N.Confidence:= mcDerived;
  FCreated.Add(N);
  if not Args.IsNull and (Args.NamedChildCount > 0) and (Args.NamedChild(0).NodeType = 'kNil') then FCreatedNil.Add(N);
  Result:= NoValue;
  Result.Kind:= mvNode;
  Result.Node:= N;
end;

function TWalkCore.EvalCall(const pNode: TTSNode; const pFrame: TWalkFrame): TMValue;  // dl:ok too-many-exit-points@d80b -- a dispatch on the CST node kind: one guard-and-exit per recognised shape of spec 4.2 / 4.3, kept flat so each row maps to one branch
var
  E, Args : TTSNode;
  Name    : string;
  Vals    : TArray<TMValue>;
  V       : TMValue;
  I       : Integer;
  Info    : TRoutineInfo;
  Relevant: Boolean;
  Callee  : TCallee;
begin
  Result:= NoValue;
  E   := pNode.ChildByField('entity');
  Args:= pNode.ChildByField('args');
  Name:= if E.NodeType = 'exprDot' then Text(pFrame, E.ChildByField('rhs')) else Text(pFrame, E);
  { X.Create(Owner): a menu node when X is TMenuItem or a descendant; else a
    one-level click wrapper when its first argument is a handler (spec 4.2) }
  if (E.NodeType = 'exprDot') and SameText(Name, 'Create') then
  begin
    if IsMenuType(Text(pFrame, E.ChildByField('lhs'))) then Exit(CreateNode(pNode, pFrame));
    if not Args.IsNull and (Args.NamedChildCount > 0) then
    begin
      V:= EvalArg(Args.NamedChild(0), pFrame);
      if V.Kind in [mvHandler, mvForeign, mvProc] then
      begin
        Result.Kind   := mvWrapper;
        Result.Handler:= HandlerOf(V);
      end;
    end;
    Exit;
  end;
  { P.Add(X) / P.Insert(i, X) }
  if (E.NodeType = 'exprDot') and (SameText(Name, 'Add') or SameText(Name, 'Insert')) then
  begin
    Parenting(E.ChildByField('lhs'), Args, SameText(Name, 'Insert'), pFrame);
    Exit;
  end;
  Vals:= nil;
  if not Args.IsNull then
    for I:= 0 to Args.NamedChildCount - 1 do Vals:= Vals + [EvalArg(Args.NamedChild(I), pFrame)];
  { host API: AddActionMenu('<Name>', nil, X, ..) makes X a root (spec 4.6) }
  if SameText(Name, 'AddActionMenu') then
  begin
    for V in Vals do
      if (V.Kind = mvNode) and not V.Node.Parented then FTree.AdoptRoot(V.Node);
    Exit;
  end;
  { a procedural parameter bound to an anonymous method / routine (spec 4.5) }
  if (E.NodeType = 'identifier') and pFrame.Env.Vars.TryGetValue(LowerCase(Name), V) and (V.Kind = mvProc) then
  begin
    if not V.ProcNode.IsNull then
    begin
      Callee:= Default(TCallee);
      Callee.ArgsDecl:= V.ProcNode.ChildByField('args');
      Callee.Body    := V.ProcNode.ChildByField('body');
      Callee.F       := LoadFile(V.ProcPath);
      Callee.Env     := V.ProcEnv;
      Callee.Site    := Loc(pFrame, pNode);
      Callee.Derived := True;
      Callee.Depth   := pFrame.Depth + 1;
      Exit(InvokeExpanded(Callee, Vals));
    end;
    Info:= ResolveRoutine(LastSegment(V.ProcRoutine), pFrame.F.Path);
    if Info.Found then Exit(InvokeRoutine(Info, Vals, Loc(pFrame, pNode), True, pFrame.Depth + 1));
    Exit;
  end;
  { a routine that receives a node or a callback: descend with the
    parameters bound (helpers and BuildReportsMenu-style builders alike) }
  Relevant:= False;
  for V in Vals do
    if V.Kind in [mvNode, mvProc] then Relevant:= True;
  if not Relevant then
  begin
    Result.Kind:= mvForeign;
    Result.Text:= Text(pFrame, pNode);
    Result.Path:= pFrame.F.Path;
    Exit;
  end;
  Info:= ResolveRoutine(Name, pFrame.F.Path);
  if not Info.Found then Exit;
  Result:= InvokeRoutine(Info, Vals, if pFrame.Site <> '' then pFrame.Site else Loc(pFrame, pNode), pFrame.Derived, pFrame.Depth + 1);
end;

function TWalkCore.InvokeRoutine(const pInfo: TRoutineInfo; const pArgs: TArray<TMValue>; const pSite: string;
  pDerived: Boolean; pDepth: Integer): TMValue;
var
  WF    : TWalkFile;
  Proc  : TTSNode;
  Head  : TTSNode;
  Callee: TCallee;
begin
  Result:= NoValue;
  if (pDepth > MAX_DEPTH) or FStack.Contains(LowerCase(pInfo.QName)) then Exit;
  WF:= LoadFile(pInfo.Path);
  Proc:= FindDefProc(WF, pInfo.Line);
  if Proc.IsNull then Exit;
  Head:= Proc.ChildByField('header');
  FStack.Add(LowerCase(pInfo.QName));
  try
    Callee:= Default(TCallee);
    Callee.ArgsDecl:= Head.ChildByField('args');
    Callee.Body    := Proc.ChildByField('body');
    Callee.F       := WF;
    Callee.Site    := pSite;
    Callee.Derived := pDerived;
    Callee.Depth   := pDepth;
    Result:= InvokeExpanded(Callee, pArgs);
  finally
    FStack.Delete(FStack.Count - 1);
  end;
end;

{ spec 4.3 expansion: an argument that evaluated to N captions (const array,
  case function) runs the callee once per caption. }
function TWalkCore.InvokeExpanded(const pCallee: TCallee; const pArgs: TArray<TMValue>): TMValue;
var
  I, J: Integer;
  One : TArray<TMValue>;
begin
  for I:= 0 to High(pArgs) do
    if (pArgs[I].Kind = mvCaptions) and (Length(pArgs[I].Captions) > 1) then
    begin
      Result:= NoValue;
      for J:= 0 to High(pArgs[I].Captions) do
      begin
        One:= Copy(pArgs);
        One[I].Captions:= [pArgs[I].Captions[J]];
        Result:= Invoke(pCallee, One);
      end;
      Exit;
    end;
  Result:= Invoke(pCallee, pArgs);
end;

function TWalkCore.Invoke(const pCallee: TCallee; const pArgs: TArray<TMValue>): TMValue;
var
  Fr    : TWalkFrame;
  Env   : TWalkEnv;
  Names : TArray<string>;
  I, J  : Integer;
  Arg   : TTSNode;
  Pair  : TPair<string, TMValue>;
begin
  Result:= NoValue;
  if pCallee.Depth > MAX_DEPTH then Exit;
  Env:= NewEnv;
  if pCallee.Env <> nil then
    for Pair in pCallee.Env.Vars do Env.Vars.AddOrSetValue(Pair.Key, Pair.Value);
  Fr:= Default(TWalkFrame);
  Fr.F      := pCallee.F;
  Fr.Env    := Env;
  Fr.Site   := pCallee.Site;
  Fr.Derived:= pCallee.Derived;
  Fr.Depth  := pCallee.Depth;
  Names:= nil;
  if not pCallee.ArgsDecl.IsNull then
    for I:= 0 to pCallee.ArgsDecl.NamedChildCount - 1 do
    begin
      Arg:= pCallee.ArgsDecl.NamedChild(I);
      if Arg.NodeType <> 'declArg' then Continue;
      for J:= 0 to Arg.NamedChildCount - 1 do
        if Arg.NamedChild(J).NodeType = 'identifier' then Names:= Names + [LowerCase(Text(Fr, Arg.NamedChild(J)))];
    end;
  for I:= 0 to High(Names) do
    if I <= High(pArgs) then Env.Vars.AddOrSetValue(Names[I], pArgs[I])
    else Env.Vars.Remove(Names[I]);
  Env.Vars.Remove('result');
  WalkStmt(pCallee.Body, Fr);
  if not Env.Vars.TryGetValue('result', Result) then Result:= NoValue;
end;

procedure TWalkCore.Parenting(const pReceiver, pArgs: TTSNode; pInsert: Boolean; const pFrame: TWalkFrame);
var
  XNode, Base: TTSNode;
  X, P       : TMValue;
  Index      : Integer;
  Ident      : string;
  Xs         : TArray<TMenuNode>;
  N          : TMenuNode;
  I          : Integer;
begin
  if pArgs.IsNull or (pArgs.NamedChildCount = 0) then Exit;
  Index:= -1;
  if pInsert then
  begin
    if pArgs.NamedChildCount < 2 then Exit;
    if not TryStrToInt(Text(pFrame, pArgs.NamedChild(0)), Index) then Index:= -1;
    XNode:= pArgs.NamedChild(1);
  end
  else XNode:= pArgs.NamedChild(0);
  Xs:= nil;
  if XNode.NodeType = 'exprBrackets' then
  begin
    for I:= 0 to XNode.NamedChildCount - 1 do
    begin
      X:= Eval(XNode.NamedChild(I), pFrame);
      if X.Kind = mvNode then Xs:= Xs + [X.Node];
    end;
  end
  else
  begin
    X:= Eval(XNode, pFrame);
    if X.Kind = mvNode then Xs:= [X.Node];
  end;
  if Xs = nil then Exit;   { a TList.Add of something else }
  for N in Xs do
  begin
    { <B>.Items.Add(X): the host main menu makes X a root; any other B is a
      foreign menu (external root named B) }
    if (pReceiver.NodeType = 'exprDot') and SameText(Text(pFrame, pReceiver.ChildByField('rhs')), 'Items') then
    begin
      Base:= pReceiver.ChildByField('lhs');
      if N.Parented then Continue;
      if SameText(LastSegment(Text(pFrame, Base)), 'MainMenu') then FTree.AdoptRoot(N)
      else FTree.ExternalRoot(Text(pFrame, Base), Loc(pFrame, pReceiver)).AddChild(N);
      Continue;
    end;
    P:= Eval(pReceiver, pFrame);
    if (P.Kind = mvNode) and (P.Node <> N) then
    begin
      if N.Parented then Continue;
      if pInsert and (Index >= 0) then P.Node.InsertChild(Index, N) else P.Node.AddChild(N);
      Continue;
    end;
    { a foreign parent: a DFM item, a looked-up IDE menu. A node already placed
      is only being REMEMBERED (GMenuItems.Add(RootMenu)), not re-parented. }
    if N.Parented or (P.Kind <> mvForeign) then Continue;
    Ident:= Text(pFrame, pReceiver);
    if not IsMenuTypedForeign(Ident, pFrame.F.Path) then Continue;
    if pInsert and (Index >= 0) then FTree.ExternalRoot(Ident, Loc(pFrame, pReceiver)).InsertChild(Index, N)
    else FTree.ExternalRoot(Ident, Loc(pFrame, pReceiver)).AddChild(N);
  end;
end;

procedure TWalkCore.SetProp(pTarget: TMenuNode; const pProp: string; const pRhs, pStmt: TTSNode; const pFrame: TWalkFrame);
var
  C: TMValue;
begin
  if SameText(pProp, 'Caption') then
  begin
    C:= CaptionOf(pRhs, pFrame);
    if C.Kind = mvCaptions then
    begin
      pTarget.Caption   := C.Captions[0];
      pTarget.Confidence:= MaxConf(pTarget.Confidence, C.Conf);
      if Length(C.Captions) > 1 then
        FTree.AddNote(Format('expansion on a directly built item at %s kept only %s: %s',
          [Loc(pFrame, pStmt), QuotedStr(C.Captions[0]), Text(pFrame, pStmt)]));
    end
    else
    begin
      { spec 4.3 last row: never dropped silently -- one dynamic node + a note }
      pTarget.Kind      := mnkDynamic;
      pTarget.Caption   := '<dynamic: ' + (if C.Text <> '' then C.Text else Text(pFrame, pRhs)) + '>';
      pTarget.Confidence:= mcUnknown;
      FTree.AddNote(Format('dynamic caption at %s: %s', [Loc(pFrame, pStmt), Text(pFrame, pStmt)]));
    end;
  end
  else if SameText(pProp, 'OnClick') or SameText(pProp, 'Action') then
  begin
    pTarget.HasClick:= True;
    pTarget.Handler := HandlerOf(Eval(pRhs, pFrame));
  end
  else if SameText(pProp, 'Enabled') and (pRhs.NodeType = 'kFalse') then pTarget.Disabled:= True;
end;

procedure TWalkCore.WalkStmt(const pNode: TTSNode; const pFrame: TWalkFrame);  // dl:ok too-many-exit-points@85f6 -- a dispatch on the CST node kind: one guard-and-exit per recognised shape of spec 4.2 / 4.3, kept flat so each row maps to one branch
var
  K       : string;
  I       : Integer;
  L, R, T : TTSNode;
  V       : TMValue;
  Name    : string;
begin
  if pNode.IsNull then Exit;
  K:= pNode.NodeType;
  if IsCompound(K) then
  begin
    for I:= 0 to pNode.NamedChildCount - 1 do WalkStmt(pNode.NamedChild(I), pFrame);
    Exit;
  end;
  if K = 'statement' then
  begin
    for I:= 0 to pNode.NamedChildCount - 1 do
      if pNode.NamedChild(I).NodeType = 'exprCall' then Eval(pNode.NamedChild(I), pFrame);
    Exit;
  end;
  if K = 'exprCall' then
  begin
    Eval(pNode, pFrame);
    Exit;
  end;
  if K <> 'assignment' then Exit;
  L:= pNode.ChildByField('lhs');
  R:= pNode.ChildByField('rhs');
  if (L.NodeType = 'identifier') or (L.NodeType = 'varAssignDef') then
  begin
    if L.NodeType = 'varAssignDef' then
    begin
      Name:= '';
      for I:= 0 to L.NamedChildCount - 1 do
        if L.NamedChild(I).NodeType = 'identifier' then
        begin
          Name:= Text(pFrame, L.NamedChild(I));
          Break;
        end;
    end
    else Name:= Text(pFrame, L);
    V:= Eval(R, pFrame);
    if V.Kind = mvForeign then
    begin
      { a local that holds a caption, or the expression text a dynamic caption names }
      V:= EvalArg(R, pFrame);
      if V.Kind = mvForeign then V.Text:= Name;
    end;
    if Name <> '' then pFrame.Env.Vars.AddOrSetValue(LowerCase(Name), V);
    Exit;
  end;
  if L.NodeType = 'exprDot' then
  begin
    T:= L.ChildByField('lhs');
    V:= Eval(T, pFrame);   { also runs pAddItem(..) in pAddItem(..).Tag := I }
    if V.Kind = mvNode then SetProp(V.Node, Text(pFrame, L.ChildByField('rhs')), R, pNode, pFrame)
    else Eval(R, pFrame);
    Exit;
  end;
  Eval(R, pFrame);
end;

{ spec 4.2 row 3 + 4.1: the kind a node settles on once the walk is over. }
procedure TWalkCore.Settle(pNode: TMenuNode);
var
  C: TMenuNode;
begin
  for C in pNode.Children do Settle(C);
  if pNode.Kind in [mnkRoot, mnkExternalRoot] then Exit;
  if pNode.Kind = mnkDynamic then
  begin
    if pNode.Children.Count > 0 then pNode.Kind:= mnkSubmenu;
    Exit;
  end;
  if pNode.Caption = '-' then pNode.Kind:= mnkSeparator
  else if pNode.Children.Count > 0 then pNode.Kind:= mnkSubmenu
  else if not pNode.HasClick then pNode.Kind:= mnkHeader
  else pNode.Kind:= mnkItem;
  if pNode.Kind <> mnkItem then pNode.Handler:= '';
end;

procedure TWalkCore.FreeOrphans(pNote: Boolean);
var
  N      : TMenuNode;
  Orphans: TList<TMenuNode>;
begin
  { collect first: an orphan's children are freed with it, so nothing may be
    read from FCreated after the first Free }
  Orphans:= TList<TMenuNode>.Create;
  try
    for N in FCreated do
      if not N.Parented then
      begin
        if pNote and FCreatedNil.Contains(N) then FTree.AdoptRoot(N)
        else Orphans.Add(N);
      end;
    for N in Orphans do
    begin
      if pNote then
        FTree.AddNote(Format('unparented item at %s: %s is created but never added to a menu',
          [N.Source, if N.Caption <> '' then QuotedStr(N.Caption) else '(no caption)']));
      N.Free;
    end;
  finally
    Orphans.Free;
  end;
  FCreated.Clear;
  FCreatedNil.Clear;
end;

procedure TWalkCore.Finish;
var
  N: TMenuNode;
begin
  FreeOrphans(True);
  for N in FTree.Roots do Settle(N);
  for N in FTree.External do Settle(N);
end;

function TWalkCore.Walk(const pRootQName: string): TMenuTree;
var
  QB     : TFDQuery;
  Names  : string;
  S      : string;
  Info   : TRoutineInfo;
  Infos  : TList<TRoutineInfo>;
  Sig    : string;
  Params : string;
  Fr     : TWalkFrame;
  WF     : TWalkFile;
  Proc   : TTSNode;
  QFld, PFld, LFld, GFld: TField;
begin
  FTree:= TMenuTree.Create;
  Infos:= TList<TRoutineInfo>.Create;
  try
    try
      { spec 4.7: candidates are routines whose body span references a menu type }
      Names:= '';
      for S in FMenuTypes do Names:= Names + (if Names = '' then '' else ',') + QuotedStr(S);
      QB:= Q('SELECT s.qualified_name AS q, f.path AS p, s.impl_start_line AS l, s.signature AS g FROM symbols s '
        + 'JOIN files f ON f.id = s.file_id WHERE s.impl_start_line > 0 AND s.kind IN (' + ROUTINE_KINDS + ') '
        + 'AND EXISTS (SELECT 1 FROM refs r WHERE r.file_id = s.file_id AND r.start_line BETWEEN s.impl_start_line '
        + 'AND s.impl_end_line AND r.name_text IN (' + Names + ')) ORDER BY lower(f.path), s.impl_start_line', []);
      try
        QFld:= QB.FieldByName('q');
        PFld:= QB.FieldByName('p');
        LFld:= QB.FieldByName('l');
        GFld:= QB.FieldByName('g');
        while not QB.Eof do
        begin
          Info:= Default(TRoutineInfo);
          Info.Found:= True;
          Info.QName:= QFld.AsString;
          Info.Path := PFld.AsString;
          Info.Line := LFld.AsInteger;
          Sig:= GFld.AsString;
          { a routine that TAKES a menu item is a helper / sub-builder: it is
            walked from its call sites, with the parameter bound }
          Params:= if Sig.StartsWith('(') and (Sig.IndexOf(')') > 0) then Sig.Substring(1, Sig.IndexOf(')') - 1) else '';
          if pRootQName <> '' then
          begin
            if SameText(Info.QName, pRootQName) then Infos.Add(Info);
          end
          else if not TRegEx.IsMatch(Params, ':\s*(' + Names.Replace('''', '').Replace(',', '|') + ')\b', [roIgnoreCase]) then
            Infos.Add(Info);
          QB.Next;
        end;
      finally
        QB.Free;
      end;
      if (pRootQName <> '') and (Infos.Count = 0) then
        raise EMenuTreeSetup.CreateFmt('--root %s: no routine with that qualified name references a menu item in this db', [pRootQName]);
      for Info in Infos do
      begin
        WF:= LoadFile(Info.Path);
        Proc:= FindDefProc(WF, Info.Line);
        if Proc.IsNull then Continue;
        Fr:= Default(TWalkFrame);
        Fr.F  := WF;
        Fr.Env:= NewEnv;
        FStack.Add(LowerCase(Info.QName));
        try
          WalkStmt(Proc.ChildByField('body'), Fr);
        finally
          FStack.Delete(FStack.Count - 1);
        end;
      end;
      Finish;
    except
      on Exception do
      begin
        FreeOrphans(False);
        FreeAndNil(FTree);
        raise;
      end;
    end;
    Result:= FTree;
    FTree:= nil;
  finally
    Infos.Free;
  end;
end;

{ ---- TMenuWalker ---- }

constructor TMenuWalker.Create(const pDbs: TArray<string>; const pProject: string);
begin
  inherited Create;
  if Length(pDbs) = 0 then raise EMenuTreeSetup.Create('need --db');
  FImpl:= TWalkCore.Create(pDbs[0], pProject);
end;

destructor TMenuWalker.Destroy;
begin
  FImpl.Free;
  inherited Destroy;
end;

function TMenuWalker.Walk(const pRootQName: string): TMenuTree;
begin
  Result:= TWalkCore(FImpl).Walk(pRootQName);
end;

end.
