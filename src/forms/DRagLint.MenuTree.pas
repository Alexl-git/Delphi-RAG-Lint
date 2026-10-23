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
    /// <summary>Removes pChild from this node's children WITHOUT freeing it.</summary>
    procedure ExtractChild(pChild: TMenuNode);
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

procedure TMenuNode.ExtractChild(pChild: TMenuNode);
begin
  FChildren.Extract(pChild);
  pChild.AttachTo(nil);
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

end.
