unit DRagLint.FormsMap.Dfm;

/// <summary>Report-time reader of a text .dfm for forms-csv v6: builds the
/// object/collection-item tree of one form and answers "which on-screen controls
/// fire handler H, and where does a tester find each of them" -- a menu path
/// (TMainMenu / TPopupMenu TMenuItem nesting), a DevExpress bar path (ribbon tab,
/// bar, sub-item link chain, backstage view), the TAction a button or menu item
/// is bound to, and the enclosing tab sheet of a plain control.</summary>
/// <remarks>Reads the .dfm FILE, not the index: the index carries one dfm_event
/// per handler and no parent chain, which is not enough for a menu path. No
/// extractor change is involved. A binary .dfm (TPF0) yields an empty tree. Not
/// thread-safe; one tree per form, owned by the caller.</remarks>

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  ;

type
  /// <summary>One way a tester can fire a handler: where the control is, what
  /// it says, and what kind of control it is.</summary>
  /// <remarks>Rank orders ways for display: 0 main menu / ribbon, 1 toolbar /
  /// backstage, 2 plain control, 3 popup menu, 4 bare action (no control
  /// shows it), 5 automatic (a timer or dataset event). Lower is shown first;
  /// equal ranks keep .dfm order. IsControl is False for ranks 4 and 5: there
  /// is nothing for a tester to press.</remarks>
  TNavWay = record
    Location : string ; // e.g. "Main menu: Setup > Groups > Assign Groups"
    Click    : string ; // caption pressed (accelerators stripped), or [Name]
    CtrlClass: string ; // e.g. TMenuItem, TButton, TdxBarLargeButton
    CompName : string ; // design-time component name
    Rank     : Integer;
    IsControl: Boolean;
  end;

  /// <summary>One .dfm object or collection item.</summary>
  /// <remarks>Owned by the TFormDfmTree that created it; never free one directly.</remarks>
  TFormDfmNode = class
  private
    FName     : string;
    FCompClass: string;
    FParent   : TFormDfmNode;
    FIsItem   : Boolean;
    FCollProp : string;
    FProps    : TStringList;
    FLine     : Integer;
  public
    /// <summary>Creates an empty node under AParent (nil for the form root).</summary>
    /// <param name="AParent">Enclosing object or item; nil for the root.</param>
    constructor Create(AParent: TFormDfmNode);
    /// <summary>Frees the property list.</summary>
    destructor Destroy; override;
    /// <summary>Value of property AName (case-insensitive), '' when absent.</summary>
    /// <param name="AName">Property name exactly as written in the .dfm.</param>
    /// <returns>The decoded value, or ''.</returns>
    function Prop(const AName: string): string;
    /// <summary>Component name ('' for a collection item).</summary>
    property Name: string read FName write FName;
    /// <summary>Component class name, e.g. TMenuItem ('' for an item).</summary>
    property CompClass: string read FCompClass write FCompClass;
    /// <summary>Enclosing object or item; nil for the form root.</summary>
    property Parent: TFormDfmNode read FParent;
    /// <summary>True for a collection 'item' entry.</summary>
    property IsItem: Boolean read FIsItem write FIsItem;
    /// <summary>Collection property an item belongs to, e.g. ItemLinks.</summary>
    property CollProp: string read FCollProp write FCollProp;
    /// <summary>Name=Value pairs in .dfm order; string values decoded.</summary>
    property Props: TStringList read FProps;
    /// <summary>1-based .dfm line of the object / item header; 0 for a node
    /// added from code (AddCodeMenuItem / AddCodeBarItem).</summary>
    property Line: Integer read FLine write FLine;
  end;

  /// <summary>One .dfm-declared menu surface: where a tester finds a menu
  /// (a DevExpress bar, bar popup, backstage / application menu, or a VCL
  /// TMainMenu / TPopupMenu).</summary>
  /// <remarks>A bar shown in two ribbon tabs is two surfaces (one per prefix).</remarks>
  TBarSurface = record
    /// <summary>The bar / popup / backstage / menu node; owned by the tree.</summary>
    Node  : TFormDfmNode;
    /// <summary>The forms-csv location prefix, e.g. "Ribbon: Lists > Lists Bar",
    /// "Main menu", "Toolbar 'X'", "Right-click menu pop", "File menu".</summary>
    Prefix: string;
  end;

  /// <summary>One entry of a surface or sub-item, in display order.</summary>
  TBarLink = record
    /// <summary>The ItemLinks / Buttons collection item, or the TMenuItem itself
    /// for a VCL menu.</summary>
    Link      : TFormDfmNode;
    /// <summary>The bar item (or TMenuItem) the entry shows; nil when the link's
    /// ItemName names no component of this .dfm.</summary>
    Item      : TFormDfmNode;
    /// <summary>The link's ItemName / Item value (the TMenuItem's name for VCL).</summary>
    ItemName  : string;
    /// <summary>BeginGroup = True on the link (a separator before it).</summary>
    BeginGroup: Boolean;
  end;

  /// <summary>Parsed tree of one text .dfm plus the DevExpress link indexes
  /// needed to turn a handler into tester-facing locations.</summary>
  /// <remarks>Owns every node. Not thread-safe.</remarks>
  TFormDfmTree = class  // dl:ok high-response@05c0 -- RFC is the .dfm walk's string and collection calls; the parser, the link indexes and the way builder share one node list and splitting them only moves the same calls around
  private
    FNodes     : TObjectList<TFormDfmNode>;
    FRoot      : TFormDfmNode;
    FLinkOwners: TObjectDictionary<string, TList<TFormDfmNode>>;
    FBarTabs   : TObjectDictionary<string, TList<TFormDfmNode>>;
    FBackstage : TDictionary<string, Boolean>;
    FLinkLists : TObjectDictionary<TFormDfmNode, TList<TFormDfmNode>>;
    FCodeCount : Integer;
    function NewNode(AParent: TFormDfmNode): TFormDfmNode;
    function LinkListOf(AOwner: TFormDfmNode): TList<TFormDfmNode>;
    function IsBar(ANode: TFormDfmNode): Boolean;
    procedure AddMulti(ADict: TObjectDictionary<string, TList<TFormDfmNode>>; const AKey: string; ANode: TFormDfmNode);
    procedure BuildIndexes;
    function ReadValue(const ALines: TArray<string>; var AIndex: Integer; const ARaw: string; out AValue: string): Boolean;
    function CaptionOf(ANode, AAction: TFormDfmNode): string;
    function BarPrefixes(AOwner: TFormDfmNode; ADepth: Integer): TArray<string>;
    function LinkedWays(const ABase: TNavWay; ACtrl: TFormDfmNode; AList: TList<TNavWay>): Boolean;
    procedure AddWaysFor(AList: TList<TNavWay>; ACtrl, AAction: TFormDfmNode; const AEvent: string);
  public
    /// <summary>Constructor: creates an empty tree with no nodes.</summary>
    constructor Create;
    /// <summary>Frees every node.</summary>
    destructor Destroy; override;
    /// <summary>Parses a text .dfm file; a missing or binary file leaves the
    /// tree empty.</summary>
    /// <param name="APath">Full path to the .dfm.</param>
    procedure LoadFromFile(const APath: string);
    /// <summary>Parses .dfm text already split into lines.</summary>
    /// <param name="ALines">The .dfm lines, in order.</param>
    procedure LoadFromLines(const ALines: TArray<string>);
    /// <summary>Every control a tester can press to run AHandler on this form,
    /// best location first, followed by non-control bindings (an action no
    /// control shows, a timer) with IsControl = False.</summary>
    /// <param name="AHandler">Bare handler method name, e.g. btnOkClick.</param>
    /// <returns>The ways, sorted by Rank (stable); empty when the handler is not
    /// bound to anything in this .dfm (the form root's own events do not count
    /// -- OnShow is not a control a tester presses).</returns>
    function WaysForHandler(const AHandler: string): TArray<TNavWay>;
    /// <summary>Ways for the first non-root control whose caption equals
    /// ACaption (accelerators ignored); empty when none.</summary>
    /// <param name="ACaption">Caption text with accelerators already removed.</param>
    /// <returns>The ways for that one control.</returns>
    function WaysForCaption(const ACaption: string): TArray<TNavWay>;
    /// <summary>The non-root TMenuItem component named AName; nil when this
    /// .dfm has none (a TMainMenu / TPopupMenu of that name does not count).</summary>
    /// <param name="AName">Component name, case-insensitive.</param>
    /// <returns>The node, owned by the tree, or nil.</returns>
    function FindMenuItem(const AName: string): TFormDfmNode;
    /// <summary>forms-csv v8: adds a menu item built in CODE (a menu-tree
    /// external-root child) under a .dfm menu item, so WaysForHandler finds
    /// it with the full main-menu / right-click path.</summary>
    /// <param name="AParent">A TMenuItem node of this tree (FindMenuItem, or an
    /// earlier AddCodeMenuItem result for a code submenu); must not be nil.</param>
    /// <param name="ACaption">Caption as written in code; accelerators are
    /// stripped where paths are built, as for a .dfm caption.</param>
    /// <param name="AHandler">Bare OnClick method name; '' for a submenu.</param>
    /// <returns>The new node (class TMenuItem, no component name), owned by the tree.</returns>
    function AddCodeMenuItem(AParent: TFormDfmNode; const ACaption, AHandler: string): TFormDfmNode;
    /// <summary>The form root (object Name: TClass); nil for an empty tree.</summary>
    /// <returns>The root node, owned by the tree.</returns>
    function Root: TFormDfmNode;
    /// <summary>Every node (objects and collection items, code-added ones too)
    /// in .dfm order; owned by the tree -- never free or add to it.</summary>
    property Nodes: TObjectList<TFormDfmNode> read FNodes;
    /// <summary>Every .dfm-declared menu surface in .dfm order: TdxBar (one
    /// entry per prefix -- a bar in two ribbon tabs gives two), bar popups,
    /// backstage views / application menus, VCL TMainMenu and TPopupMenu.</summary>
    /// <returns>The surfaces; empty for a form without menus.</returns>
    function BarSurfaces: TArray<TBarSurface>;
    /// <summary>The entries shown under AOwner, in display order: ItemLinks
    /// of a bar / sub-item / popup / application menu, Buttons of a backstage
    /// view, child TMenuItems of a VCL menu or menu item. Code links added by
    /// AddCodeBarItem are included at their index.</summary>
    /// <param name="AOwner">A node of this tree; nil gives an empty result.</param>
    /// <returns>The links (Item nil when ItemName names nothing here).</returns>
    function LinksOf(AOwner: TFormDfmNode): TArray<TBarLink>;
    /// <summary>The non-root, non-item component named AName; nil when absent.</summary>
    /// <param name="AName">Component name, case-insensitive.</param>
    /// <returns>The node, owned by the tree, or nil.</returns>
    function ItemByName(const AName: string): TFormDfmNode;
    /// <summary>The forms-csv location prefixes of a surface or sub-item --
    /// the strings WaysForHandler puts before an item's caption (without the
    /// ':' it inserts after "Main menu").</summary>
    /// <param name="AOwner">A bar, popup, sub-item, backstage view, application
    /// menu, TMainMenu or TPopupMenu node.</param>
    /// <returns>One prefix per place AOwner is shown; empty when it is shown nowhere.</returns>
    function SurfacePrefixes(AOwner: TFormDfmNode): TArray<string>;
    /// <summary>Resolves the identifier a menu-tree external root carries to
    /// the .dfm node that owns the links: a component name (bar, popup,
    /// sub-item, TMenuItem), &lt;mgr&gt;.Bars[n] (the n-th TdxBar in .dfm order),
    /// &lt;mgr&gt;.MainMenuBar (the IsMainMenu bar), &lt;mgr&gt;.BarByCaption('X') /
    /// BarByOldName('X') (by Caption / Name).</summary>
    /// <param name="AIdent">The identifier as code wrote it; a 'TFormClass.' prefix naming
    /// this form's class (menu-tree's key for a field link owner) is accepted.</param>
    /// <param name="ADerived">Set True when the owner was found by position or
    /// lookup (Bars[n], MainMenuBar, BarBy*) rather than by name.</param>
    /// <returns>The owner node, or nil when nothing here matches.</returns>
    function FindBarLinkOwner(const AIdent: string; out ADerived: Boolean): TFormDfmNode;
    /// <summary>forms-csv v9: adds a bar item built in CODE and links it under
    /// AOwner at AIndex, so WaysForHandler / LinksOf / SurfacePrefixes see it
    /// like a .dfm link.</summary>
    /// <param name="AOwner">A bar / popup / sub-item node of this tree
    /// (FindBarLinkOwner, or an earlier AddCodeBarItem sub-item); must not be nil.</param>
    /// <param name="ACaption">Caption as written in code.</param>
    /// <param name="AHandler">Bare OnClick method name; '' for a sub-item.</param>
    /// <param name="AClass">Component class, e.g. TdxBarButton or TdxBarSubItem.</param>
    /// <param name="AIndex">Link position; -1 (or past the end) appends.</param>
    /// <returns>The new item node (a synthetic component name), owned by the tree.</returns>
    function AddCodeBarItem(AOwner: TFormDfmNode; const ACaption, AHandler, AClass: string; AIndex: Integer): TFormDfmNode;
  end;

implementation

uses
  System.StrUtils
  , System.IOUtils
  , System.Generics.Defaults
  , System.RegularExpressions
  ;

const
  BAR_LINK_MAX_DEPTH = 8; // sub-item nesting deeper than this is not followed
  RANK_MENU      = 0;
  RANK_TOOLBAR   = 1;
  RANK_CONTROL   = 2;
  RANK_POPUP     = 3;
  RANK_ACTION    = 4;
  RANK_AUTO      = 5;
  BINARY_DFM_SIGNATURE = 'TPF0';
  EVENT_PREFIX   = 'On';
  MAIN_MENU      = 'Main menu';
  MENU_ITEM_CLASS = 'TMenuItem';
  // Events nobody fires by pressing something: timers and dataset notifications.
  AUTOMATIC_EVENTS : array[0..5] of string = ('OnTimer', 'OnNewRecord', 'OnFilterRecord', 'OnDataChange', 'OnStateChange', 'OnIdle');
  AUTOMATIC_PREFIXES: array[0..2] of string = ('OnAfter', 'OnBefore', 'OnCalc');

/// <summary>True for events no tester fires by pressing something.</summary>
function IsAutomaticEvent(const AEvent: string): Boolean;
var
  S: string;
begin
  if MatchText(AEvent, AUTOMATIC_EVENTS) then Exit(True);
  for S in AUTOMATIC_PREFIXES do
    if StartsText(S, AEvent) then Exit(True);
  Result:= False;
end;

/// <summary>What the tester does for a non-click event, '' for a plain click.</summary>
function GestureOf(const AEvent: string): string;
begin
  if (AEvent = '') or MatchText(AEvent, ['OnClick', 'OnExecute', 'OnItemClick']) then Result:= ''
  else if ContainsText(AEvent, 'DblClick') then Result:= 'double-click'
  else if ContainsText(AEvent, 'Key') then Result:= 'key press'
  else if ContainsText(AEvent, 'ButtonClick') then Result:= 'its button'
  else if ContainsText(AEvent, 'Change') then Result:= 'change the value'
  else Result:= Copy(AEvent, Length(EVENT_PREFIX) + 1, MaxInt);
end;

/// <summary>Removes Windows menu accelerators: a single ampersand is dropped
/// and a doubled one becomes one literal ampersand.</summary>
function StripAccel(const S: string): string;
var
  Sb: TStringBuilder;
  I : Integer;
begin
  Sb:= TStringBuilder.Create;
  try
    I:= 1;
    while I <= Length(S) do
    begin
      if S[I] <> '&' then Sb.Append(S[I])
      else if (I < Length(S)) and (S[I + 1] = '&') then
      begin
        Sb.Append('&');
        Inc(I);
      end;
      Inc(I);
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

/// <summary>Decodes a .dfm string value: quoted runs (doubled quotes inside),
/// #nnn character codes and '+' joins; e.g. 'a'#39'b' gives a'b.</summary>
function DecodeDfmString(const S: string): string;
var
  Sb   : TStringBuilder;
  I    : Integer;
  Start: Integer;
begin
  Sb:= TStringBuilder.Create;
  try
    I:= 1;
    while I <= Length(S) do
    begin
      if S[I] = '''' then
      begin
        Inc(I);
        while I <= Length(S) do
        begin
          if S[I] <> '''' then Sb.Append(S[I])
          else if (I < Length(S)) and (S[I + 1] = '''') then
          begin
            Sb.Append('''');
            Inc(I);
          end
          else
            Break;
          Inc(I);
        end;
        Inc(I); // past the closing quote
      end
      else if S[I] = '#' then
      begin
        Inc(I);
        Start:= I;
        while (I <= Length(S)) and CharInSet(S[I], ['0'..'9']) do Inc(I);
        if I > Start then Sb.Append(Char(StrToIntDef(Copy(S, Start, I - Start), Ord('?'))));
      end
      else
        Inc(I); // '+', blanks between joined runs
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ TFormDfmNode }

constructor TFormDfmNode.Create(AParent: TFormDfmNode);
begin
  inherited Create;
  FParent:= AParent;
  FProps := TStringList.Create;
end;

destructor TFormDfmNode.Destroy;
begin
  FProps.Free;
  inherited Destroy;
end;

function TFormDfmNode.Prop(const AName: string): string;
var
  I: Integer;
begin
  I:= FProps.IndexOfName(AName);
  if I >= 0 then Result:= FProps.ValueFromIndex[I]
  else Result:= '';
end;

{ TFormDfmTree }

constructor TFormDfmTree.Create;
begin
  inherited Create;
  FNodes     := TObjectList<TFormDfmNode>.Create(True);
  FLinkOwners:= TObjectDictionary<string, TList<TFormDfmNode>>.Create([doOwnsValues], TIStringComparer.Ordinal);
  FBarTabs   := TObjectDictionary<string, TList<TFormDfmNode>>.Create([doOwnsValues], TIStringComparer.Ordinal);
  FBackstage := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FLinkLists := TObjectDictionary<TFormDfmNode, TList<TFormDfmNode>>.Create([doOwnsValues]);
end;

destructor TFormDfmTree.Destroy;
begin
  FLinkLists.Free;
  FBackstage.Free;
  FBarTabs.Free;
  FLinkOwners.Free;
  FNodes.Free;
  inherited Destroy;
end;

function TFormDfmTree.NewNode(AParent: TFormDfmNode): TFormDfmNode;
begin
  Result:= TFormDfmNode.Create(AParent);
  FNodes.Add(Result);
  if FRoot = nil then FRoot:= Result;
end;

procedure TFormDfmTree.LoadFromFile(const APath: string);
var
  Head: TBytes;
begin
  if not TFile.Exists(APath) then Exit;
  Head:= TFile.ReadAllBytes(APath);
  // A binary .dfm starts with the TPF0 signature; it has no text tree to read.
  if (Length(Head) >= Length(BINARY_DFM_SIGNATURE)) and (TEncoding.ANSI.GetString(Head, 0, Length(BINARY_DFM_SIGNATURE)) = BINARY_DFM_SIGNATURE) then Exit;
  LoadFromLines(TFile.ReadAllLines(APath, TEncoding.ANSI));
end;

/// <summary>Reads one property value starting at ARaw (the text after '='),
/// consuming continuation lines from ALines[AIndex..]. Returns False for a
/// value the tree does not keep: a '(...)' list or a '{...}' binary blob.</summary>
function TFormDfmTree.ReadValue(const ALines: TArray<string>; var AIndex: Integer; const ARaw: string; out AValue: string): Boolean;
var
  T : string;
  Sb: TStringBuilder;
begin
  AValue:= ARaw;
  if (ARaw <> '') and CharInSet(ARaw[1], ['(', '{']) then
  begin
    // Skip to the closing bracket; the list or blob is never a caption or event.
    T:= ARaw;
    while not (T.EndsWith(')') or T.EndsWith('}')) and (AIndex < Length(ALines)) do
    begin
      T:= Trim(ALines[AIndex]);
      Inc(AIndex);
    end;
    Exit(False);
  end;
  if (ARaw <> '') and not CharInSet(ARaw[1], ['''', '#']) then Exit(True); // identifier, number, set
  // A string: on this line ('abc' + ...) or, when ARaw is empty, on the next ones.
  Sb:= TStringBuilder.Create;
  try
    T:= ARaw;
    if T <> '' then Sb.Append(DecodeDfmString(T));
    while ((T = '') or T.EndsWith('+')) and (AIndex < Length(ALines)) do
    begin
      T:= Trim(ALines[AIndex]);
      if (T = '') or not CharInSet(T[1], ['''', '#']) then Break;
      Inc(AIndex);
      Sb.Append(DecodeDfmString(T));
    end;
    AValue:= Sb.ToString;
  finally
    Sb.Free;
  end;
  Result:= True;
end;

procedure TFormDfmTree.LoadFromLines(const ALines: TArray<string>);
var
  Stack    : TStack<TFormDfmNode>;
  CollStack: TStack<string>;
  I        : Integer;
  T        : string;
  N        : TFormDfmNode;
  P        : Integer;
  PName    : string;
  PVal     : string;
  Value    : string;
  Top      : TFormDfmNode;
begin
  Stack    := TStack<TFormDfmNode>.Create;
  CollStack:= TStack<string>.Create;
  try
    I:= 0;
    while I < Length(ALines) do
    begin
      T:= Trim(ALines[I]);
      Inc(I);
      if Stack.Count > 0 then Top:= Stack.Peek
      else Top:= nil;
      if StartsText('object ', T) or StartsText('inherited ', T) or StartsText('inline ', T) then
      begin
        // "object Name: TClass" / "inherited Name: TClass [2]"
        N:= NewNode(Top);
        N.Line:= I; // I is already past this line: the 1-based line number
        T:= Trim(Copy(T, Pos(' ', T) + 1, MaxInt));
        P:= Pos(':', T);
        if P > 0 then
        begin
          N.Name     := Trim(Copy(T, 1, P - 1));
          N.CompClass:= Trim(Copy(T, P + 1, MaxInt)).Split([' '])[0];
        end
        else
          N.CompClass:= T;
        Stack.Push(N);
      end
      else if SameText(T, 'item') then
      begin
        N:= NewNode(Top);
        N.Line  := I;
        N.IsItem:= True;
        if CollStack.Count > 0 then N.CollProp:= CollStack.Peek;
        Stack.Push(N);
      end
      else if SameText(T, 'end') or StartsText('end>', T) then
      begin
        if Stack.Count > 0 then Stack.Pop;
        if StartsText('end>', T) and (CollStack.Count > 0) then CollStack.Pop;
      end
      else
      begin
        P:= Pos('=', T);
        if P = 0 then Continue;
        PName:= Trim(Copy(T, 1, P - 1));
        PVal := Trim(Copy(T, P + 1, MaxInt));
        if PVal = '<' then CollStack.Push(PName)
        // Distinct out variable: an out string is cleared on entry, and ARaw is a
        // const reference -- passing PVal twice reads back ''.
        else if (PVal <> '<>') and ReadValue(ALines, I, PVal, Value) and (Top <> nil) then Top.Props.AddPair(PName, Value);
      end;
    end; // while
  finally
    CollStack.Free;
    Stack.Free;
  end;
  BuildIndexes;
end;

procedure TFormDfmTree.AddMulti(ADict: TObjectDictionary<string, TList<TFormDfmNode>>; const AKey: string; ANode: TFormDfmNode);
var
  L: TList<TFormDfmNode>;
begin
  if not ADict.TryGetValue(AKey, L) then
  begin
    L:= TList<TFormDfmNode>.Create;
    ADict.Add(AKey, L);
  end;
  L.Add(ANode);
end;

procedure TFormDfmTree.BuildIndexes;
var
  N  : TFormDfmNode;
  Ref: string;
begin
  for N in FNodes do
  begin
    if not N.IsItem or (N.Parent = nil) then Continue;
    // DevExpress bar links: the item's ItemName (or older 'Item') names the bar
    // item; the collection's owner (a TdxBar, sub-item or popup) is the parent.
    if SameText(N.CollProp, 'ItemLinks') then
    begin
      LinkListOf(N.Parent).Add(N);
      Ref:= N.Prop('ItemName');
      if Ref = '' then Ref:= N.Prop('Item');
      if Ref <> '' then AddMulti(FLinkOwners, Ref, N.Parent);
    end
    // Ribbon tab groups: ToolbarName names the TdxBar shown in that tab.
    else if SameText(N.CollProp, 'Groups') then
    begin
      Ref:= N.Prop('ToolbarName');
      if Ref <> '' then AddMulti(FBarTabs, Ref, N.Parent);
    end
    // Ribbon backstage view buttons: Item names a bar item.
    else if SameText(N.CollProp, 'Buttons') and ContainsText(N.Parent.CompClass, 'Backstage') then
    begin
      LinkListOf(N.Parent).Add(N);
      Ref:= N.Prop('Item');
      if Ref <> '' then FBackstage.AddOrSetValue(Ref, True);
    end;
  end;
end;

function TFormDfmTree.CaptionOf(ANode, AAction: TFormDfmNode): string;
begin
  Result:= StripAccel(ANode.Prop('Caption'));
  if (Result = '') and (AAction <> nil) then Result:= StripAccel(AAction.Prop('Caption'));
end;

function TFormDfmTree.BarPrefixes(AOwner: TFormDfmNode; ADepth: Integer): TArray<string>;
var
  Acc   : TList<string>;
  BarCap: string;
  TabCap: string;
  Tab   : TFormDfmNode;
  Tabs  : TList<TFormDfmNode>;
  Owners: TList<TFormDfmNode>;
  O     : TFormDfmNode;
  Pre   : string;
begin
  Result:= [];
  if (AOwner = nil) or (ADepth > BAR_LINK_MAX_DEPTH) then Exit;
  Acc:= TList<string>.Create;
  try
    // A bar: a TdxBar object, or (older .dfm layout) an item of the Bars collection.
    if SameText(AOwner.CompClass, 'TdxBar') or (AOwner.IsItem and SameText(AOwner.CollProp, 'Bars')) then
    begin
      BarCap:= StripAccel(AOwner.Prop('Caption'));
      if SameText(AOwner.Prop('IsMainMenu'), 'True') then Acc.Add(MAIN_MENU)
      else if (AOwner.Name <> '') and FBarTabs.TryGetValue(AOwner.Name, Tabs) then
        // The bar caption is the group label under the tab; skip it when it only
        // repeats the tab caption ("Additional > Additional").
        for Tab in Tabs do
        begin
          TabCap:= StripAccel(Tab.Prop('Caption'));
          if (BarCap <> '') and not SameText(BarCap, TabCap) then Acc.Add('Ribbon: ' + TabCap + ' > ' + BarCap)
          else Acc.Add('Ribbon: ' + TabCap);
        end
      else if BarCap <> '' then Acc.Add('Toolbar ''' + BarCap + '''')
      else Acc.Add('Toolbar ''' + AOwner.Name + '''');
    end
    else if ContainsText(AOwner.CompClass, 'Popup') then
      Acc.Add('Right-click menu ' + AOwner.Name)
    else
    begin
      // A sub-item: its own caption is one more level, under wherever IT is linked.
      if (AOwner.Name <> '') and FLinkOwners.TryGetValue(AOwner.Name, Owners) then
        for O in Owners do
          for Pre in BarPrefixes(O, ADepth + 1) do
            Acc.Add(Pre + ' > ' + StripAccel(AOwner.Prop('Caption')));
      if (AOwner.Name <> '') and FBackstage.ContainsKey(AOwner.Name) then
        Acc.Add('File menu > ' + StripAccel(AOwner.Prop('Caption')));
    end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

/// <summary>Adds one way per DevExpress link of ACtrl (ribbon / bar / sub-item
/// chain / backstage). Returns False when ACtrl is linked nowhere.</summary>
function TFormDfmTree.LinkedWays(const ABase: TNavWay; ACtrl: TFormDfmNode; AList: TList<TNavWay>): Boolean;
var
  W     : TNavWay;
  Owners: TList<TFormDfmNode>;
  O     : TFormDfmNode;
  Pre   : string;
begin
  Result:= False;
  W:= ABase;
  if FLinkOwners.TryGetValue(ACtrl.Name, Owners) then
    for O in Owners do
      for Pre in BarPrefixes(O, 0) do
      begin
        Result:= True;
        if StartsText(MAIN_MENU, Pre) then
        begin
          // "Main menu" or "Main menu > Sub" -> "Main menu: Sub > Item"
          W.Location:= MAIN_MENU + ': ' + Copy(Pre + ' > ' + W.Click, Length(MAIN_MENU + ' > ') + 1, MaxInt);
          W.Rank    := RANK_MENU;
        end
        else
        begin
          W.Location:= Pre + ' > ' + W.Click;
          if StartsText('Ribbon', Pre) then W.Rank:= RANK_MENU
          else if StartsText('Right-click', Pre) then W.Rank:= RANK_POPUP
          else W.Rank:= RANK_TOOLBAR;
        end;
        AList.Add(W);
      end;
  if FBackstage.ContainsKey(ACtrl.Name) then
  begin
    Result    := True;
    W.Location:= 'File menu > ' + W.Click;
    W.Rank    := RANK_TOOLBAR;
    AList.Add(W);
  end;
end;

procedure TFormDfmTree.AddWaysFor(AList: TList<TNavWay>; ACtrl, AAction: TFormDfmNode; const AEvent: string);
var
  W    : TNavWay;
  Cur  : TFormDfmNode;
  Trail: string;
begin
  W:= Default(TNavWay);
  W.CompName := ACtrl.Name;
  W.CtrlClass:= ACtrl.CompClass;
  W.IsControl:= True;
  W.Click    := CaptionOf(ACtrl, AAction);
  if W.Click = '' then W.Click:= '[' + ACtrl.Name + ']';
  if GestureOf(AEvent) <> '' then W.Click:= W.Click + ' (' + GestureOf(AEvent) + ')';

  // (0) Timers and dataset events fire by themselves: no control to press.
  if IsAutomaticEvent(AEvent) or SameText(ACtrl.CompClass, 'TTimer') then
  begin
    W.Location := '(automatic: ' + ACtrl.Name + '.' + AEvent + ')';
    W.Click    := '';
    W.Rank     := RANK_AUTO;
    W.IsControl:= False;
    AList.Add(W);
    Exit;
  end;

  // (1) VCL menus: walk the TMenuItem chain up to its TMainMenu / TPopupMenu.
  if SameText(ACtrl.CompClass, 'TMenuItem') then
  begin
    Trail:= W.Click;
    Cur:= ACtrl.Parent;
    while (Cur <> nil) and SameText(Cur.CompClass, 'TMenuItem') do
    begin
      Trail:= CaptionOf(Cur, nil) + ' > ' + Trail;
      Cur:= Cur.Parent;
    end;
    if (Cur <> nil) and ContainsText(Cur.CompClass, 'Popup') then
    begin
      W.Location:= 'Right-click menu ' + Cur.Name + ': ' + Trail;
      W.Rank:= RANK_POPUP;
    end
    else
    begin
      W.Location:= MAIN_MENU + ': ' + Trail;
      W.Rank:= RANK_MENU;
    end;
    AList.Add(W);
    Exit;
  end;

  // (2) DevExpress bar items: one way per link (ribbon / bar / sub-item chain).
  if LinkedWays(W, ACtrl, AList) then Exit;

  // (3) A bare action nobody displays: still name it, ranked last.
  if (AAction = nil) and ContainsText(ACtrl.CompClass, 'Action') and (ACtrl.Parent <> nil) and ContainsText(ACtrl.Parent.CompClass, 'Action') then
  begin
    W.Location := 'Action ' + W.Click + ' (no control shows it)';
    W.Rank     := RANK_ACTION;
    W.IsControl:= False;
    AList.Add(W);
    Exit;
  end;

  // (4) Plain control: prefix every enclosing tab sheet's caption.
  Trail:= W.Click;
  Cur:= ACtrl.Parent;
  while (Cur <> nil) and (Cur <> FRoot) do
  begin
    if ContainsText(Cur.CompClass, 'TabSheet') then Trail:= 'Tab ''' + CaptionOf(Cur, nil) + ''' > ' + Trail;
    Cur:= Cur.Parent;
  end;
  W.Location:= Trail;
  W.Rank    := RANK_CONTROL;
  AList.Add(W);
end;

function TFormDfmTree.WaysForHandler(const AHandler: string): TArray<TNavWay>;
var
  L     : TList<TNavWay>;
  Sorted: TList<TNavWay>;
  N     : TFormDfmNode;
  M     : TFormDfmNode;
  I     : Integer;
  PName : string;
  Ev    : string;
  Users : Integer;
  W     : TNavWay;
begin
  L     := TList<TNavWay>.Create;
  Sorted:= TList<TNavWay>.Create;
  try
    for N in FNodes do
    begin
      if (N = FRoot) or N.IsItem then Continue;
      for I:= 0 to N.Props.Count - 1 do
      begin
        if not SameText(N.Props.ValueFromIndex[I], AHandler) then Continue;
        PName:= N.Props.Names[I];
        Ev:= Copy(PName, LastDelimiter('.', PName) + 1, MaxInt); // Properties.OnButtonClick -> OnButtonClick
        if not StartsStr(EVENT_PREFIX, Ev) then Continue;
        if SameText(Ev, 'OnExecute') and ContainsText(N.CompClass, 'Action') then
        begin
          // An action's handler is fired by every control whose Action names it.
          Users:= 0;
          for M in FNodes do
            if (M <> N) and SameText(M.Prop('Action'), N.Name) then
            begin
              AddWaysFor(L, M, N, '');
              Inc(Users);
            end;
          if Users = 0 then AddWaysFor(L, N, nil, Ev);
        end
        else
          AddWaysFor(L, N, nil, Ev);
        Break; // one binding per component is enough
      end;
    end;
    // Stable by construction: TList.Sort is not, and equal ranks must keep .dfm order.
    for I:= RANK_MENU to RANK_AUTO do
      for W in L do
        if W.Rank = I then Sorted.Add(W);
    Result:= Sorted.ToArray;
  finally
    Sorted.Free;
    L.Free;
  end;
end;

function TFormDfmTree.WaysForCaption(const ACaption: string): TArray<TNavWay>;
var
  L: TList<TNavWay>;
  N: TFormDfmNode;
begin
  Result:= [];
  if ACaption = '' then Exit;
  L:= TList<TNavWay>.Create;
  try
    for N in FNodes do
      if (N <> FRoot) and not N.IsItem and SameText(StripAccel(N.Prop('Caption')), ACaption) then
      begin
        AddWaysFor(L, N, nil, '');
        Break;
      end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TFormDfmTree.FindMenuItem(const AName: string): TFormDfmNode;
var
  N: TFormDfmNode;
begin
  Result:= nil;
  if AName = '' then Exit;
  for N in FNodes do
    if (N <> FRoot) and not N.IsItem and SameText(N.Name, AName) and SameText(N.CompClass, MENU_ITEM_CLASS) then Exit(N);
end;

function TFormDfmTree.AddCodeMenuItem(AParent: TFormDfmNode; const ACaption, AHandler: string): TFormDfmNode;
begin
  Result:= NewNode(AParent);
  Result.CompClass:= MENU_ITEM_CLASS;
  Result.Props.Add('Caption=' + ACaption);
  if AHandler <> '' then Result.Props.Add('OnClick=' + AHandler);
end;

function TFormDfmTree.LinkListOf(AOwner: TFormDfmNode): TList<TFormDfmNode>;
begin
  if not FLinkLists.TryGetValue(AOwner, Result) then
  begin
    Result:= TList<TFormDfmNode>.Create;
    FLinkLists.Add(AOwner, Result);
  end;
end;

function TFormDfmTree.IsBar(ANode: TFormDfmNode): Boolean;
begin
  Result:= SameText(ANode.CompClass, 'TdxBar') or (ANode.IsItem and SameText(ANode.CollProp, 'Bars'));
end;

function TFormDfmTree.Root: TFormDfmNode;
begin
  Result:= FRoot;
end;

function TFormDfmTree.SurfacePrefixes(AOwner: TFormDfmNode): TArray<string>;
begin
  Result:= [];
  if AOwner = nil then Exit;
  if ContainsText(AOwner.CompClass, 'Backstage') or ContainsText(AOwner.CompClass, 'ApplicationMenu') then Exit(TArray<string>.Create('File menu'));
  if SameText(AOwner.CompClass, 'TMainMenu') then Exit(TArray<string>.Create(MAIN_MENU));
  if SameText(AOwner.CompClass, 'TPopupMenu') then Exit(TArray<string>.Create('Right-click menu ' + AOwner.Name));
  Result:= BarPrefixes(AOwner, 0);
end;

function TFormDfmTree.BarSurfaces: TArray<TBarSurface>;
var
  Acc: TList<TBarSurface>;
  N  : TFormDfmNode;
  S  : TBarSurface;
  Pre: string;
  Own: Boolean;
begin
  Acc:= TList<TBarSurface>.Create;
  try
    for N in FNodes do
    begin
      if N = FRoot then Continue;
      // A surface: a bar, or a non-item menu owner (popup, backstage, application menu, VCL main menu).
      Own:= (not N.IsItem) and (EndsText('PopupMenu', N.CompClass) or EndsText('BackstageView', N.CompClass)
        or ContainsText(N.CompClass, 'ApplicationMenu') or SameText(N.CompClass, 'TMainMenu'));
      if not (Own or IsBar(N)) then Continue;
      for Pre in SurfacePrefixes(N) do
      begin
        S.Node  := N;
        S.Prefix:= Pre;
        Acc.Add(S);
      end;
    end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function TFormDfmTree.LinksOf(AOwner: TFormDfmNode): TArray<TBarLink>;
var
  Acc : TList<TBarLink>;
  L   : TBarLink;
  N   : TFormDfmNode;
  List: TList<TFormDfmNode>;
begin
  Result:= [];
  if AOwner = nil then Exit;
  Acc:= TList<TBarLink>.Create;
  try
    if FLinkLists.TryGetValue(AOwner, List) then
      for N in List do
      begin
        L.Link      := N;
        L.ItemName  := N.Prop('ItemName');
        if L.ItemName = '' then L.ItemName:= N.Prop('Item');
        L.Item      := ItemByName(L.ItemName);
        L.BeginGroup:= SameText(N.Prop('BeginGroup'), 'True');
        Acc.Add(L);
      end
    else
      // VCL: the child TMenuItems ARE the entries; Caption '-' is the separator.
      for N in FNodes do
        if (N.Parent = AOwner) and SameText(N.CompClass, MENU_ITEM_CLASS) then
        begin
          L.Link      := N;
          L.Item      := N;
          L.ItemName  := N.Name;
          L.BeginGroup:= False;
          Acc.Add(L);
        end;
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

function TFormDfmTree.ItemByName(const AName: string): TFormDfmNode;
var
  N: TFormDfmNode;
begin
  Result:= nil;
  if AName = '' then Exit;
  for N in FNodes do
    if (N <> FRoot) and not N.IsItem and SameText(N.Name, AName) then Exit(N);
end;

function TFormDfmTree.FindBarLinkOwner(const AIdent: string; out ADerived: Boolean): TFormDfmNode;
var
  M   : TMatch;
  N   : TFormDfmNode;
  Want: Integer;
  Seen: Integer;
  Key : string;
begin
  Result  := nil;
  ADerived:= True;
  // <mgr>.Bars[n]: the n-th TdxBar in .dfm order (the manager's Bars collection order)
  M:= TRegEx.Match(AIdent, '(?:^|\.)Bars\s*\[\s*(\d+)\s*\]\s*$', [roIgnoreCase]);
  if M.Success then
  begin
    Want:= StrToInt(M.Groups[1].Value);
    Seen:= 0;
    for N in FNodes do
      if IsBar(N) then
      begin
        if (Seen = Want) and (Result = nil) then Result:= N;
        Inc(Seen);
      end;
  end
  else if TRegEx.IsMatch(AIdent, '(?:^|\.)MainMenuBar\s*$', [roIgnoreCase]) then
  begin
    for N in FNodes do
      if (Result = nil) and IsBar(N) and SameText(N.Prop('IsMainMenu'), 'True') then Result:= N;
  end
  else
  begin
    M:= TRegEx.Match(AIdent, '(?:^|\.)BarBy(Caption|OldName)\s*\(\s*''([^'']*)''\s*\)\s*$', [roIgnoreCase]);
    if M.Success then
    begin
      Key:= M.Groups[2].Value;
      for N in FNodes do
        if (Result = nil) and IsBar(N) and (if SameText(M.Groups[1].Value, 'Caption') then SameText(N.Prop('Caption'), Key)
          else (SameText(N.Prop('OldName'), Key) or SameText(N.Name, Key))) then Result:= N;
    end
    else
    begin
      // A plain component name (Self. allowed); any other expression names nothing here.
      ADerived:= False;
      Key:= AIdent;
      if Key.StartsWith('Self.', True) then Key:= Key.Substring(Length('Self.'));
      // menu-tree keys a field link owner by its class: TfrmMain.popGrid names this form's popGrid
      if (FRoot <> nil) and (FRoot.CompClass <> '') and Key.StartsWith(FRoot.CompClass + '.', True) then
        Key:= Key.Substring(Length(FRoot.CompClass) + 1);
      if not (Key.Contains('.') or Key.Contains('[') or Key.Contains('(')) then Result:= ItemByName(Key);
    end;
  end;
end;

function TFormDfmTree.AddCodeBarItem(AOwner: TFormDfmNode; const ACaption, AHandler, AClass: string; AIndex: Integer): TFormDfmNode;
var
  Link: TFormDfmNode;
  List: TList<TFormDfmNode>;
begin
  Inc(FCodeCount);
  Result:= NewNode(FRoot);
  Result.Name     := 'codeBarItem' + IntToStr(FCodeCount);
  Result.CompClass:= AClass;
  Result.Props.Add('Caption=' + ACaption);
  if AHandler <> '' then Result.Props.Add('OnClick=' + AHandler);
  Link:= NewNode(AOwner);
  Link.IsItem  := True;
  Link.CollProp:= 'ItemLinks';
  Link.Props.Add('ItemName=' + Result.Name);
  List:= LinkListOf(AOwner);
  if (AIndex >= 0) and (AIndex < List.Count) then List.Insert(AIndex, Link)
  else List.Add(Link);
  AddMulti(FLinkOwners, Result.Name, AOwner);
end;

end.
