unit DRagLint.V151.CMP;

{ Wave v151 lane CMP -- component-authoring rules: free notification, property
  defaults, palette icons, setters that do not repaint, fixed pixels / colours /
  bounds, write-only properties, IDE notifiers that are never removed, and the
  interface-holder-of-non-refcounted widening (Supports out-parameter and a
  component freed while a local interface still refers to it).
  Scaffold created EMPTY by lane FRAME; lane CMP owns this unit, its
  DRagLint.V151.CMP.Support helpers and DRagLint.Fix.V151.CMP. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md.
  Every rule here reads ONE unit's parse tree. The index (ACtx.Store) is used only
  to answer "does type A descend from TComponent / TControl" and "what is the static
  type of this expression"; without it a well-known class list and the classes
  declared in the unit answer, and an unknown type means no finding. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule id: a component-typed property of a component stores the assigned component
  /// without calling FreeNotification.</summary>
  /// <remarks>Fires (1) at the assignment `FField := Value` in a property setter when the
  /// property type and the owning class both descend from TComponent and neither the setter
  /// nor a method of the same class it calls (three levels) names FreeNotification,
  /// RemoveFreeNotification, ReferenceInterface or `inherited`; (2) at the write accessor of a
  /// PUBLISHED component-typed property that writes its field directly. Silent: a field the
  /// class itself creates (`F := T.Create(..)`), a setter that copies (Assign) instead of
  /// storing the parameter, an unknown property type. Why: when the referenced component is
  /// freed first, only FreeNotification makes the VCL call Notification(opRemove), the one place
  /// the field can be cleared; without it the field points at freed memory.</remarks>
  CMP_FREE_NOTIFICATION_RULE = 'component-missing-free-notification';
  /// <summary>Rule id: a property's `default` value differs from what the constructor sets.</summary>
  /// <remarks>Fires at the `default` value when a constructor (or AfterConstruction) of the same
  /// class assigns the property or its backing field a literal of the same kind (integer, boolean,
  /// identifier, set) with a different value in a top-level statement; also when the default is
  /// a non-zero integer or True, the backing field is declared in the class, and no method of the
  /// class except its own setter ever writes that field (it starts at 0 / False). Silent: a
  /// conditional assignment, a non-literal value, literals of different kinds, a getter method.
  /// Why: the form designer does not store a value equal to the default, so a component that
  /// really starts at another value loads the wrong value from every form that kept the
  /// default.</remarks>
  CMP_DEFAULT_MISMATCH_RULE = 'component-default-mismatch';
  /// <summary>Rule id: a class passed to RegisterComponents has no palette bitmap.</summary>
  /// <remarks>Reads at lint time every resource file the unit names with {$R ..} / {$RESOURCE ..}
  /// (`*` = the unit name, no extension = .res), the unit's sibling .dcr, the .dcr files the
  /// .dpk files in the unit's folder include, and the .rc script next to a .res that does not
  /// exist. A class is satisfied by a resource named like the class in upper case, or that name
  /// followed by `_` or a digit (size variants). Silent: classes passed to RegisterNoIcon.</remarks>
  CMP_PALETTE_ICON_RULE = 'component-palette-icon';
  /// <summary>Rule id: a property setter changes a field that Paint reads but never repaints.</summary>
  /// <remarks>Fires at the assignment to the field, in a class that implements Paint in this unit,
  /// when the field is read by Paint (or a method of the class Paint calls) and the setter, with
  /// the class methods it calls (three levels), names nothing that repaints or notifies:
  /// Invalidate, Repaint, Refresh, Redraw, Change(d), Update, Realign, RecreateWnd, Paint,
  /// Layout, Resize, Adjust, SetBounds, Notify, or `inherited`.</remarks>
  CMP_SETTER_INVALIDATE_RULE = 'component-setter-without-invalidate';
  /// <summary>Rule id: a drawing call in a paint / draw / resize routine uses a fixed pixel value.</summary>
  /// <remarks>Fires once per call of Rect, Bounds, Point, FillRect, Rectangle, RoundRect, Ellipse,
  /// TextOut, TextRect, MoveTo, LineTo, Draw, StretchDraw, InflateRect, OffsetRect, FrameRect, Arc,
  /// Pie, Chord, Polyline or Polygon that has an integer literal of magnitude 2 or more among
  /// its arguments, inside a routine whose name contains Paint or Draw or ends in Resize. Silent:
  /// 0 and 1, the right operand of div / mod / shr / shl / `/`, either operand of `*`, a literal
  /// inside a call that scales (a name containing Scale, or MulDiv). Ships OFF (style).</remarks>
  CMP_FIXED_PIXELS_RULE = 'component-fixed-pixels';
  /// <summary>Rule id: a paint / draw routine uses a hard-coded colour.</summary>
  /// <remarks>Fires inside a routine whose name contains Paint or Draw on an RGB(..) call, a
  /// TColor(&lt;number&gt;) cast, a number assigned to a member whose name ends in Color, and a
  /// number passed to SetTextColor, SetBkColor or CreateSolidBrush. Named colours (clWindow,
  /// clBtnFace) are silent: they follow the system and the VCL style. Ships OFF (style).</remarks>
  CMP_HARDCODED_COLOR_RULE = 'component-hardcoded-color';
  /// <summary>Rule id: code in a VCL unit sets a control's bounds to a fixed pixel value.</summary>
  /// <remarks>Fires on `X.Width / Height / Left / Top / ClientWidth / ClientHeight := n` and on
  /// SetBounds(..) with n a non-zero integer literal or a non-zero integer constant of the unit,
  /// when the target is a control: a bare name inside a method of a TControl descendant, or an
  /// expression whose static type (index) or declared type (local, parameter, field) descends
  /// from TControl. A VCL unit names Vcl.* or Controls / Forms / StdCtrls / ExtCtrls / ComCtrls
  /// in its uses. Silent: 0, a TRect / TBitmap target, an unknown type. Ships OFF (style).</remarks>
  CMP_FIXED_BOUNDS_RULE = 'control-fixed-bounds';
  /// <summary>Rule id: a property has a write accessor and no read accessor.</summary>
  /// <remarks>Fires at the property name of every typed property with `write` and no `read`, in a
  /// class, record or interface. Silent: the dispinterface `writeonly` form. Ships OFF (style).</remarks>
  CMP_WRITE_ONLY_PROPERTY_RULE = 'write-only-property';
  /// <summary>Rule id: an IDE (Open Tools API) notifier, wizard, binding or options page is
  /// registered and never removed.</summary>
  /// <remarks>Only in a unit that uses ToolsAPI. Pairs: AddNotifier / RemoveNotifier, AddWizard /
  /// RemoveWizard, AddKeyboardBinding / RemoveKeyboardBinding, AddPluginInfo / RemovePluginInfo,
  /// AddMenuCreatorNotifier / RemoveMenuCreatorNotifier, RegisterAddInOptions /
  /// UnregisterAddInOptions. Fires when the returned index is thrown away (a bare call
  /// statement), or stored in a variable that no matching remove call of the unit receives;
  /// RegisterAddInOptions fires when the unit never calls UnregisterAddInOptions. Silent: an
  /// index passed straight on to another call. Why: a package that unloads with its notifier
  /// still registered leaves the IDE calling into freed code.</remarks>
  CMP_OTA_NOTIFIER_RULE = 'ota-notifier-not-removed';
  /// <summary>The existing rule this lane widens in place (RefTypeRules owns it).</summary>
  /// <remarks>Two shapes the host does not see: Supports(X, IID, Intf) where X's static type
  /// (index) descends from TComponent and the class does not count references itself; and a
  /// component freed (Free, DisposeOf, FreeAndNil) while a LOCAL interface variable still holds
  /// it -- the variable is released at the end of the routine and touches the freed object.
  /// The second shape is fired at the free and needs no index when the declared types decide.</remarks>
  CMP_INTERFACE_HOLDER_HOST = 'interface-holder-of-non-refcounted';

type
  /// <summary>Checker entry points of v151 lane CMP; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151CMPRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library): every rule of the lane.</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none or when the unit does not parse.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file (unused by this lane).</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>nil.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes (unused by this lane).</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>nil.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check (unused by this lane).</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>nil.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.StrUtils
  , System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , TreeSitter
  , DRagLint.Core.Interfaces
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Lint.RefTypeRules
  , DRagLint.V151.CMP.Support
  ;

const
  SEV_WARNING = 'warning';
  SEV_HINT    = 'hint';
  BASE_COMPONENT = 'tcomponent';
  BASE_CONTROL   = 'tcontrol';
  MAX_REACH  = 3;
  MAX_CHAIN  = 16;
  MIN_PIXELS = 2;
  SUPPORTS_ARGS = 3;
  FREE_NOTIFY_WORDS: array[0..3] of string = ('freenotification', 'removefreenotification', 'referenceinterface', 'inherited');
  REPAINT_WORDS: array[0..15] of string = ('invalidate', 'repaint', 'refresh', 'redraw', 'change', 'update',
    'realign', 'recreatewnd', 'paint', 'layout', 'resize', 'adjust', 'setbounds', 'notify', 'inherited', 'perform');
  DRAW_CALLS: array[0..20] of string = ('rect', 'bounds', 'point', 'fillrect', 'rectangle', 'roundrect', 'ellipse',
    'textout', 'textrect', 'moveto', 'lineto', 'draw', 'stretchdraw', 'inflaterect', 'offsetrect', 'framerect',
    'arc', 'pie', 'chord', 'polyline', 'polygon');
  COLOR_CALLS: array[0..2] of string = ('settextcolor', 'setbkcolor', 'createsolidbrush');
  BOUNDS_MEMBERS: array[0..5] of string = ('width', 'height', 'left', 'top', 'clientwidth', 'clientheight');
  VCL_UNITS: array[0..4] of string = ('controls', 'forms', 'stdctrls', 'extctrls', 'comctrls');
  OTA_ADDS: array[0..5] of string = ('addnotifier', 'addwizard', 'addkeyboardbinding', 'addplugininfo',
    'addmenucreatornotifier', 'registeraddinoptions');
  OTA_REMOVES: array[0..5] of string = ('removenotifier', 'removewizard', 'removekeyboardbinding', 'removeplugininfo',
    'removemenucreatornotifier', 'unregisteraddinoptions');
  OTA_NO_INDEX = 'registeraddinoptions';
  FREE_MEMBERS: array[0..1] of string = ('free', 'disposeof');

type
  TBind = record
    Intf, Obj: string;
    Node     : TTSNode;
  end;

  TCmpRun = class
  strict private
    FCtx     : TV151FileCtx;
    FSrc     : TBytes;
    FRaw     : TBytes;
    FRoot    : TTSNode;
    FClasses : TObjectDictionary<string, TCmpClass>;
    FMethods : TObjectDictionary<string, TList<TTSNode>>;
    FDefs    : TList<TTSNode>;
    FCalls   : TList<TTSNode>;
    FKind    : TDictionary<string, Boolean>;
    FConsts  : TDictionary<string, Int64>;
    FUses    : TList<string>;
    FCreated : TObjectDictionary<string, TDictionary<string, Boolean>>;
    FSeen    : TDictionary<string, Boolean>;
    FOut     : TList<TLintFinding>;
    FReader  : TExprTypeReader;
    FReaderTried: Boolean;
    FAddRefRead : Boolean;
    FAddRefOwners: TArray<string>;
    function Txt(const N: TTSNode): string;
    function Low(const N: TTSNode): string;
    procedure Emit(const ARule, ASeverity, AMessage: string; const AFrom, ATo: TTSNode);
    function Reader: TExprTypeReader;
    function IsKindOf(const ALeaf, ABase: string; ADepth: Integer = 0): Boolean;
    function OwnsRefCount(const ALeaf: string): Boolean;
    function Methods(const ACls, AMethod: string): TList<TTSNode>;
    class function StripParens(const N: TTSNode): TTSNode; static;
    class function HasChild(const N: TTSNode; const AType: string): Boolean; static;
    class function Items(const N: TTSNode): TArray<TTSNode>; static;
    function DefNames(const ADef: TTSNode; out ACls, AMethod: string): Boolean;
    function CallName(const ACall: TTSNode): string;
    function AssignKey(const ALhs: TTSNode): string;
    function LastParam(const ADef: TTSNode): string;
    function LitKey(const N: TTSNode): string;
    procedure AddIdents(const N: TTSNode; AOut: TDictionary<string, Boolean>);
    procedure Reach(const ACls: string; const ADef: TTSNode; ADepth: Integer; AOut, AVisited: TDictionary<string, Boolean>);
    function ReachSet(const ACls: string; const ADef: TTSNode): TDictionary<string, Boolean>;
    function AnyWord(ASet: TDictionary<string, Boolean>; const AWords: array of string; ASubstring: Boolean): Boolean;
    function CreatedFields(const ACls: string): TDictionary<string, Boolean>;
    function DeclaredTypes(const ADef: TTSNode; AWithParams: Boolean): TDictionary<string, string>;
    function EnclosingDef(const N: TTSNode): TTSNode;
    procedure Prepare;
    procedure CheckFreeNotification;
    procedure CheckSetterNotification(const AClass: TCmpClass; const AProp: TCmpProp; const ADef: TTSNode);
    procedure CheckDefaultMismatch;
    procedure CheckDefaultOfProp(const AClass: TCmpClass; const AProp: TCmpProp);
    procedure CheckPaletteIcon;
    function ResourceNames(out AAnyFile: Boolean): TArray<string>;
    procedure CheckSetterInvalidate;
    procedure CheckPaintRoutines;
    function HasFixedLiteral(const N: TTSNode): Boolean;
    function InsideScaling(const N, ADef: TTSNode): Boolean;
    function IsDrawCall(const ACall: TTSNode; const AName: string): Boolean;
    procedure CheckFixedBounds;
    function IsControlTarget(const ABase, ADef: TTSNode; const ACls: string): Boolean;
    function FixedValue(const N: TTSNode): Boolean;
    procedure CheckWriteOnly;
    procedure CheckOtaNotifiers;
    function ReachesRemove(const AHolder: TTSNode; AGot: TDictionary<string, Boolean>): Boolean;
    procedure CheckInterfaceHolder;
    procedure CheckSupportsHolder;
    function IsIntfType(const ALeaf: string): Boolean;
    function IsComponentName(const AName, ACls: string; ATyped: TDictionary<string, string>): Boolean;
    procedure CheckFreeWhileHeld(const ADef: TTSNode);
  public
    constructor Create(const ACtx: TV151FileCtx; const ASrc, ARaw: TBytes; const ARoot: TTSNode);
    destructor Destroy; override;
    function Run: TArray<TLintFinding>;
  end;

{ ---------------------------------------------------------------- plumbing }

constructor TCmpRun.Create(const ACtx: TV151FileCtx; const ASrc, ARaw: TBytes; const ARoot: TTSNode);
begin
  inherited Create;
  FCtx    := ACtx;
  FSrc    := ASrc;
  FRaw    := ARaw;
  FRoot   := ARoot;
  FClasses:= TObjectDictionary<string, TCmpClass>.Create([doOwnsValues]);
  FMethods:= TObjectDictionary<string, TList<TTSNode>>.Create([doOwnsValues]);
  FDefs   := TList<TTSNode>.Create;
  FCalls  := TList<TTSNode>.Create;
  FKind   := TDictionary<string, Boolean>.Create;
  FConsts := TDictionary<string, Int64>.Create;
  FUses   := TList<string>.Create;
  FCreated:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  FSeen   := TDictionary<string, Boolean>.Create;
  FOut    := TList<TLintFinding>.Create;
end;

destructor TCmpRun.Destroy;
begin
  FReader.Free;
  FOut.Free;
  FSeen.Free;
  FCreated.Free;
  FUses.Free;
  FConsts.Free;
  FKind.Free;
  FCalls.Free;
  FDefs.Free;
  FMethods.Free;
  FClasses.Free;
  inherited Destroy;
end;

function TCmpRun.Txt(const N: TTSNode): string;
begin
  Result:= Trim(CmpText(FSrc, N));
end;

function TCmpRun.Low(const N: TTSNode): string;
begin
  Result:= CmpLow(FSrc, N);
end;

procedure TCmpRun.Emit(const ARule, ASeverity, AMessage: string; const AFrom, ATo: TTSNode);
begin
  var F: TLintFinding:= CmpFinding(FCtx.Path, ARule, ASeverity, AMessage, AFrom, ATo);
  var Key: string:= Format('%s:%d:%d', [ARule, F.StartLine, F.StartCol]);
  if FSeen.ContainsKey(Key) then Exit;
  FSeen.Add(Key, True);
  FOut.Add(F);
end;

function TCmpRun.Reader: TExprTypeReader;
begin
  if not FReaderTried then
  begin
    FReaderTried:= True;
    if (FCtx.Store <> nil) and (FCtx.FileId > 0) then
      FReader:= TExprTypeReader.Create(FCtx.Store, FCtx.LibStore, FCtx.FileId, FSrc);
  end;
  Result:= FReader;
end;

{ True when ALeaf is ABase or descends from it: the unit's own classes first, then the
  well-known lists (TComponent / TControl only), then the index. Unknown = False. }
function TCmpRun.IsKindOf(const ALeaf, ABase: string; ADepth: Integer): Boolean;
var
  C: TCmpClass;
begin
  if (ALeaf = '') or (ADepth > MAX_CHAIN) then Exit(False);
  if ALeaf = ABase then Exit(True);
  var Key: string:= ALeaf + '|' + ABase;
  if FKind.TryGetValue(Key, Result) then Exit;
  Result:= False;
  if (ABase = BASE_COMPONENT) and CmpIsKnownComponent(ALeaf) then Result:= True
  else if (ABase = BASE_CONTROL) and CmpIsKnownControl(ALeaf) then Result:= True
  else if FClasses.TryGetValue(ALeaf, C) then
  begin
    for var P: string in C.Parents do
      if IsKindOf(P, ABase, ADepth + 1) then Result:= True;
  end
  else if (Reader <> nil) and (Reader.Descends(ALeaf, ABase) = tdYes) then Result:= True;
  FKind.AddOrSetValue(Key, Result);
end;

{ The class (or an ancestor) declares _AddRef in the project: it counts references itself. }
function TCmpRun.OwnsRefCount(const ALeaf: string): Boolean;
begin
  if not FAddRefRead then
  begin
    FAddRefRead:= True;
    if FCtx.Store <> nil then
      for var S: TSymbol in FCtx.Store.FindSymbolsByExactName('_AddRef') do
        if S.ParentId > 0 then FAddRefOwners:= FAddRefOwners + [LowerCase(FCtx.Store.GetSymbolById(S.ParentId).Name)];
  end;
  for var O: string in FAddRefOwners do
    if (O <> BASE_COMPONENT) and IsKindOf(ALeaf, O) then Exit(True);
  Result:= False;
end;

function TCmpRun.Methods(const ACls, AMethod: string): TList<TTSNode>;
begin
  if not FMethods.TryGetValue(ACls + '|' + AMethod, Result) then Result:= nil;
end;

class function TCmpRun.StripParens(const N: TTSNode): TTSNode;
begin
  Result:= N;
  while (not Result.IsNull) and (Result.NodeType = 'exprParens') and (Result.NamedChildCount = 1) do
    Result:= Result.NamedChild(0);
end;

{ Named children that are code: comments and blanked directives left out. }
class function TCmpRun.Items(const N: TTSNode): TArray<TTSNode>;
begin
  Result:= nil;
  if N.IsNull then Exit;
  for var I: Integer:= 0 to N.NamedChildCount - 1 do
    if not MatchStr(N.NamedChild(I).NodeType, ['comment', 'pp']) then Result:= Result + [N.NamedChild(I)];
end;

class function TCmpRun.HasChild(const N: TTSNode; const AType: string): Boolean;
begin
  for var I: Integer:= 0 to N.NamedChildCount - 1 do
    if N.NamedChild(I).NodeType = AType then Exit(True);
  Result:= False;
end;

{ Class leaf and method name of a routine body; False for a plain routine. }
function TCmpRun.DefNames(const ADef: TTSNode; out ACls, AMethod: string): Boolean;
begin
  ACls:= '';
  AMethod:= '';
  var Hdr: TTSNode:= ADef.ChildByField('header');
  if Hdr.IsNull then Exit(False);
  var Full: string:= Low(Hdr.ChildByField('name'));
  var P: Integer:= LastDelimiter('.', Full);
  AMethod:= Copy(Full, P + 1, MaxInt);
  if P = 0 then Exit(False);
  ACls:= LowerCase(CmpLeaf(Copy(Full, 1, P - 1)));
  Result:= ACls <> '';
end;

{ Lower-case last name of the called routine: `A.B.Foo(..)` -> foo. }
function TCmpRun.CallName(const ACall: TTSNode): string;
begin
  var Ent: TTSNode:= ACall.ChildByField('entity');
  if Ent.IsNull then Exit('');
  if Ent.NodeType = 'exprDot' then Ent:= Ent.ChildByField('rhs');
  Result:= LowerCase(CmpLeaf(Low(Ent)));
end;

{ `Self.FFoo` / `FFoo` -> ffoo; `FFoo[I]` -> ffoo; `A.B` -> a.b. }
function TCmpRun.AssignKey(const ALhs: TTSNode): string;
begin
  Result:= Low(ALhs);
  if StartsStr('self.', Result) then Result:= Copy(Result, Length('self.') + 1, MaxInt);
  var P: Integer:= Pos('[', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
end;

function TCmpRun.LastParam(const ADef: TTSNode): string;
begin
  Result:= '';
  var Hdr: TTSNode:= ADef.ChildByField('header');
  if Hdr.IsNull then Exit;
  var Args: TTSNode:= Hdr.ChildByField('args');
  if Args.IsNull then Exit;
  for var I: Integer:= 0 to Args.NamedChildCount - 1 do
  begin
    var A: TTSNode:= Args.NamedChild(I);
    if A.NodeType <> 'declArg' then Continue;
    var Ty: TTSNode:= A.ChildByField('type');
    var TyStart: Integer:= if Ty.IsNull then MaxInt else Integer(Ty.StartByte);
    for var J: Integer:= 0 to A.NamedChildCount - 1 do
      if (A.NamedChild(J).NodeType = 'identifier') and (Integer(A.NamedChild(J).StartByte) < TyStart) then
        Result:= Low(A.NamedChild(J));
  end;
end;

{ A comparable key for a literal: n:<int>, b:true, i:<name>, s:<sorted members>, c:<text>; '' otherwise. }
function TCmpRun.LitKey(const N: TTSNode): string;
var
  V: Int64;
begin
  var X: TTSNode:= StripParens(N);
  if X.IsNull then Exit('');
  var T: string:= X.NodeType;
  if T = 'defaultValue' then
  begin
    if X.NamedChildCount = 0 then Exit('');
    Exit(LitKey(X.NamedChild(X.NamedChildCount - 1)));
  end;
  if T = 'literalNumber' then
  begin
    if CmpIntLiteral(Txt(X), V) then Exit('n:' + IntToStr(V));
    Exit('');
  end;
  if (T = 'kTrue') or ((T = 'identifier') and (Low(X) = 'true')) then Exit('b:true');
  if (T = 'kFalse') or ((T = 'identifier') and (Low(X) = 'false')) then Exit('b:false');
  if T = 'identifier' then Exit('i:' + Low(X));
  if T = 'literalString' then Exit('c:' + Txt(X));
  if T = 'exprBrackets' then
  begin
    var L: TStringList:= TStringList.Create;
    try
      for var I: Integer:= 0 to X.NamedChildCount - 1 do L.Add(Low(X.NamedChild(I)));
      L.Sort;
      Result:= 's:' + L.CommaText;
    finally
      L.Free;
    end;
    Exit;
  end;
  Result:= '';
end;

procedure TCmpRun.AddIdents(const N: TTSNode; AOut: TDictionary<string, Boolean>);
begin
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then AOut.AddOrSetValue(Low(N), True)
  else if N.NodeType = 'kInherited' then AOut.AddOrSetValue('inherited', True);
  for var I: Integer:= 0 to N.NamedChildCount - 1 do AddIdents(N.NamedChild(I), AOut);
end;

{ Every identifier of ADef's body plus those of the methods of ACls it names, ADepth levels deep. }
procedure TCmpRun.Reach(const ACls: string; const ADef: TTSNode; ADepth: Integer; AOut, AVisited: TDictionary<string, Boolean>);
begin
  var Local: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    AddIdents(ADef.ChildByField('body'), Local);
    for var K: string in Local.Keys do
    begin
      AOut.AddOrSetValue(K, True);
      if (ADepth >= MAX_REACH) or AVisited.ContainsKey(K) then Continue;
      var Ms: TList<TTSNode>:= Methods(ACls, K);
      if Ms = nil then Continue;
      AVisited.Add(K, True);
      for var M: TTSNode in Ms do Reach(ACls, M, ADepth + 1, AOut, AVisited);
    end;
  finally
    Local.Free;
  end;
end;

function TCmpRun.ReachSet(const ACls: string; const ADef: TTSNode): TDictionary<string, Boolean>;
begin
  Result:= TDictionary<string, Boolean>.Create;
  var Visited: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    Reach(ACls, ADef, 0, Result, Visited);
  finally
    Visited.Free;
  end;
end;

function TCmpRun.AnyWord(ASet: TDictionary<string, Boolean>; const AWords: array of string; ASubstring: Boolean): Boolean;
begin
  for var K: string in ASet.Keys do
    for var W: string in AWords do
      if (K = W) or (ASubstring and ContainsStr(K, W)) then Exit(True);
  Result:= False;
end;

{ Fields of ACls that one of its methods assigns from a constructor call: owned, not linked. }
function TCmpRun.CreatedFields(const ACls: string): TDictionary<string, Boolean>;
begin
  if FCreated.TryGetValue(ACls, Result) then Exit;
  Result:= TDictionary<string, Boolean>.Create;
  FCreated.Add(ACls, Result);
  var Assigns: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    for var D: TTSNode in FDefs do
    begin
      var C, M: string;
      if (not DefNames(D, C, M)) or (C <> ACls) then Continue;
      Assigns.Clear;
      CmpCollect(D.ChildByField('body'), 'assignment', Assigns);
      for var A: TTSNode in Assigns do
      begin
        var R: string:= Low(A.ChildByField('rhs'));
        if ContainsStr(R, '.create(') or EndsStr('.create', R) then
          Result.AddOrSetValue(AssignKey(A.ChildByField('lhs')), True);
      end;
    end;
  finally
    Assigns.Free;
  end;
end;

{ name -> declared type leaf (case kept) of a routine's locals, and its parameters when asked. }
function TCmpRun.DeclaredTypes(const ADef: TTSNode; AWithParams: Boolean): TDictionary<string, string>;

  procedure AddDecl(const ADecl: TTSNode);
  begin
    var Ty: TTSNode:= ADecl.ChildByField('type');
    if Ty.IsNull then Exit;
    var T: TTSNode:= Ty;
    if (T.NodeType = 'type') and (T.NamedChildCount > 0) then T:= T.NamedChild(0);
    if T.NodeType <> 'typeref' then Exit;
    var Leaf: string:= CmpLeaf(Txt(T));
    for var J: Integer:= 0 to ADecl.NamedChildCount - 1 do
      if (ADecl.NamedChild(J).NodeType = 'identifier') and (ADecl.NamedChild(J).StartByte < Ty.StartByte) then
        Result.AddOrSetValue(Low(ADecl.NamedChild(J)), Leaf);
  end;

begin
  Result:= TDictionary<string, string>.Create;
  var L: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    var Local: TTSNode:= ADef.ChildByField('local');
    if not Local.IsNull then
    begin
      CmpCollect(Local, 'declVar', L);
      for var V: TTSNode in L do
        if EnclosingDef(V).StartByte = ADef.StartByte then AddDecl(V);
    end;
    if AWithParams then
    begin
      var Hdr: TTSNode:= ADef.ChildByField('header');
      if not Hdr.IsNull then
      begin
        L.Clear;
        CmpCollect(Hdr.ChildByField('args'), 'declArg', L);
        for var A: TTSNode in L do AddDecl(A);
      end;
    end;
  finally
    L.Free;
  end;
end;

function TCmpRun.EnclosingDef(const N: TTSNode): TTSNode;
begin
  Result:= N.Parent;
  while (not Result.IsNull) and (Result.NodeType <> 'defProc') do Result:= Result.Parent;
end;

procedure TCmpRun.Prepare;
begin
  CmpCollectClasses(FSrc, FRoot, FClasses);
  CmpCollect(FRoot, 'defProc', FDefs);
  CmpCollect(FRoot, 'exprCall', FCalls);
  for var D: TTSNode in FDefs do
  begin
    var C, M: string;
    if not DefNames(D, C, M) then Continue;
    var L: TList<TTSNode>;
    if not FMethods.TryGetValue(C + '|' + M, L) then
    begin
      L:= TList<TTSNode>.Create;
      FMethods.Add(C + '|' + M, L);
    end;
    L.Add(D);
    if HasChild(D.ChildByField('header'), 'kConstructor') then
    begin
      if not FMethods.TryGetValue(C + '|.ctor', L) then
      begin
        L:= TList<TTSNode>.Create;
        FMethods.Add(C + '|.ctor', L);
      end;
      L.Add(D);
    end;
  end;
  var Tmp: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    CmpCollect(FRoot, 'declUsesUnit', Tmp);
    for var U: TTSNode in Tmp do FUses.Add(Low(U.NamedChild(0)));
    Tmp.Clear;
    CmpCollect(FRoot, 'declConst', Tmp);
    for var K: TTSNode in Tmp do
    begin
      var V: TTSNode:= K.ChildByField('defaultValue');
      var N: Int64;
      if (not V.IsNull) and (V.NamedChildCount > 0) and (V.NamedChild(V.NamedChildCount - 1).NodeType = 'literalNumber')
         and CmpIntLiteral(Txt(V.NamedChild(V.NamedChildCount - 1)), N) then
        FConsts.AddOrSetValue(Low(K.ChildByField('name')), N);
    end;
  finally
    Tmp.Free;
  end;
end;

{ ------------------------------------------- component-missing-free-notification }

procedure TCmpRun.CheckFreeNotification;
begin
  for var C: TCmpClass in FClasses.Values do
  begin
    if not IsKindOf(C.Name, BASE_COMPONENT) then Continue;
    for var P: TCmpProp in C.Props do
    begin
      if (P.Setter = '') or (P.Setter = '?') or not IsKindOf(P.TypeLeaf, BASE_COMPONENT) then Continue;
      if C.Fields.ContainsKey(P.Setter) then
      begin
        if P.IsPublished and not CreatedFields(C.Name).ContainsKey(P.Setter) then
          Emit(CMP_FREE_NOTIFICATION_RULE, SEV_WARNING,
            Format('Published property %s writes field %s directly, so nothing calls FreeNotification: the field dangles once ' +
              'the linked component is freed. Write it through a setter that calls Value.FreeNotification(Self) and clear it in Notification',
              [Txt(P.NameNode), Txt(P.SetterNode)]), P.SetterNode, P.SetterNode);
        Continue;
      end;
      var Bodies: TList<TTSNode>:= Methods(C.Name, P.Setter);
      if Bodies <> nil then
        for var D: TTSNode in Bodies do CheckSetterNotification(C, P, D);
    end;
  end;
end;

procedure TCmpRun.CheckSetterNotification(const AClass: TCmpClass; const AProp: TCmpProp; const ADef: TTSNode);
begin
  var Param: string:= LastParam(ADef);
  if Param = '' then Exit;
  var Assigns: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    CmpCollect(ADef.ChildByField('body'), 'assignment', Assigns);
    for var A: TTSNode in Assigns do
    begin
      var Field: string:= AssignKey(A.ChildByField('lhs'));
      if (not AClass.Fields.ContainsKey(Field)) or (Low(StripParens(A.ChildByField('rhs'))) <> Param) then Continue;
      if CreatedFields(AClass.Name).ContainsKey(Field) then Exit;
      var Ids: TDictionary<string, Boolean>:= ReachSet(AClass.Name, ADef);
      try
        if AnyWord(Ids, FREE_NOTIFY_WORDS, False) then Exit;
      finally
        Ids.Free;
      end;
      Emit(CMP_FREE_NOTIFICATION_RULE, SEV_WARNING,
        Format('Setter of %s stores the component in %s without calling FreeNotification: when that component is freed ' +
          'first, %s dangles. Call %s.FreeNotification(Self) (and RemoveFreeNotification on the old value) and clear the ' +
          'field in Notification', [Txt(AProp.NameNode), Txt(A.ChildByField('lhs')), Txt(A.ChildByField('lhs')),
          Txt(A.ChildByField('rhs'))]), A, A);
      Exit;
    end;
  finally
    Assigns.Free;
  end;
end;

{ ----------------------------------------------------- component-default-mismatch }

procedure TCmpRun.CheckDefaultMismatch;
begin
  for var C: TCmpClass in FClasses.Values do
    for var P: TCmpProp in C.Props do
      if not P.DefaultNode.IsNull then CheckDefaultOfProp(C, P);
end;

procedure TCmpRun.CheckDefaultOfProp(const AClass: TCmpClass; const AProp: TCmpProp);
var
  Field, Def, V: string;
begin
  Def:= LitKey(AProp.DefaultNode);
  if Def = '' then Exit;
  Field:= if AClass.Fields.ContainsKey(AProp.Getter) then AProp.Getter else '';
  var Inits: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    var L: TList<TTSNode>:= Methods(AClass.Name, '.ctor');
    if L <> nil then Inits.AddRange(L);
    L:= Methods(AClass.Name, 'afterconstruction');
    if L <> nil then Inits.AddRange(L);
    for var D: TTSNode in Inits do
    begin
      var Body: TTSNode:= D.ChildByField('body');
      if Body.IsNull then Continue;
      var Last: TTSNode:= Default(TTSNode);
      for var I: Integer:= 0 to Body.NamedChildCount - 1 do
      begin
        var S: TTSNode:= Body.NamedChild(I);
        if S.NodeType <> 'assignment' then Continue;
        var K: string:= AssignKey(S.ChildByField('lhs'));
        if (K = AProp.Name) or ((Field <> '') and (K = Field)) then Last:= S;
      end;
      if Last.IsNull then Continue;
      V:= LitKey(Last.ChildByField('rhs'));
      if (V = '') or (Copy(V, 1, 2) <> Copy(Def, 1, 2)) or (V = Def) then Continue;
      Emit(CMP_DEFAULT_MISMATCH_RULE, SEV_WARNING,
        Format('Property %s declares default %s, but the constructor sets %s (line %d): the form designer skips storing ' +
          'the default, so a form that kept %s loads %s. Make the default and the constructor agree',
          [Txt(AProp.NameNode), Txt(AProp.DefaultNode), Txt(Last.ChildByField('rhs')), Integer(Last.StartPoint.Row) + 1,
           Txt(AProp.DefaultNode), Txt(Last.ChildByField('rhs'))]), AProp.DefaultNode, AProp.DefaultNode);
      Exit;
    end;
  finally
    Inits.Free;
  end;
  { Never written at all: the field starts at 0 / False. }
  if (Field = '') or not ((Def = 'b:true') or (StartsStr('n:', Def) and (Def <> 'n:0'))) then Exit;
  var Assigns: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    for var D: TTSNode in FDefs do
    begin
      var C, M: string;
      if (not DefNames(D, C, M)) or (C <> AClass.Name) or (M = AProp.Setter) then Continue;
      Assigns.Clear;
      CmpCollect(D, 'assignment', Assigns);
      for var A: TTSNode in Assigns do
        if AssignKey(A.ChildByField('lhs')) = Field then Exit;
      { Passed by reference (FillChar, Read(F), an out argument) also writes it. }
      var Ids: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
      try
        AddIdents(D.ChildByField('body'), Ids);
        if Ids.ContainsKey(Field) and (M <> AProp.Getter) then
        begin
          Assigns.Clear;
          CmpCollect(D.ChildByField('body'), 'exprCall', Assigns);
          for var A: TTSNode in Assigns do
            if ContainsStr(Low(A.ChildByField('args')), Field) then Exit;
        end;
      finally
        Ids.Free;
      end;
    end;
  finally
    Assigns.Free;
  end;
  Emit(CMP_DEFAULT_MISMATCH_RULE, SEV_WARNING,
    Format('Property %s declares default %s, but nothing in %s ever sets %s, so it starts at 0 / False: the form ' +
      'designer skips storing %s and a form that kept it loads 0. Set %s in the constructor',
      [Txt(AProp.NameNode), Txt(AProp.DefaultNode), AClass.Display, AProp.Getter, Txt(AProp.DefaultNode), AProp.Getter]),
    AProp.DefaultNode, AProp.DefaultNode);
end;

{ ------------------------------------------------------- component-palette-icon }

function TCmpRun.ResourceNames(out AAnyFile: Boolean): TArray<string>;
var
  Files: TList<string>;

  procedure AddDirectives(const AText, ADir, ABase: string; AOnlyDcr: Boolean);
  begin
    for var M: TMatch in TRegEx.Matches(AText, '\{\$(?:R|RESOURCE)\s+([^}]*)\}', [roIgnoreCase]) do
    begin
      var Arg: string:= Trim(M.Groups[1].Value);
      if Arg = '' then Continue;
      if Arg[1] = '''' then Arg:= Copy(Arg, 2, Pos('''', Copy(Arg, 2, MaxInt)) - 1)
      else Arg:= Arg.Split([' ', #9])[0];
      Arg:= StringReplace(Arg, '*', ABase, []);
      if ExtractFileExt(Arg) = '' then Arg:= Arg + '.res';
      if AOnlyDcr and not SameText(ExtractFileExt(Arg), '.dcr') then Continue;
      if not TPath.IsPathRooted(Arg) then Arg:= TPath.Combine(ADir, Arg);
      Files.Add(Arg);
    end;
  end;

begin
  Result:= nil;
  AAnyFile:= False;
  var Dir: string:= ExtractFilePath(TPath.GetFullPath(FCtx.Path));
  var Base: string:= ChangeFileExt(ExtractFileName(FCtx.Path), '');
  Files:= TList<string>.Create;
  try
    AddDirectives(TEncoding.UTF8.GetString(FRaw), Dir, Base, False);
    Files.Add(TPath.Combine(Dir, Base + '.dcr'));
    try
      for var Dpk: string in TDirectory.GetFiles(Dir, '*.dpk') do
        AddDirectives(TFile.ReadAllText(Dpk), Dir, ChangeFileExt(ExtractFileName(Dpk), ''), True);
    except
      on EInOutError do ;
      on EDirectoryNotFoundException do ;
    end;
    for var F: string in Files do
    begin
      var Path: string:= F;
      if (not TFile.Exists(Path)) and SameText(ExtractFileExt(Path), '.res') then Path:= ChangeFileExt(Path, '.rc');
      if not TFile.Exists(Path) then Continue;
      AAnyFile:= True;
      Result:= Result + CmpResourceNames(Path);
    end;
  finally
    Files.Free;
  end;
end;

procedure TCmpRun.CheckPaletteIcon;
var
  AnyFile, Loaded: Boolean;
  Names: TArray<string>;
begin
  Loaded:= False;
  AnyFile:= False;
  var NoIcon: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  try
    for var Call: TTSNode in FCalls do
      if CallName(Call) = 'registernoicon' then AddIdents(Call.ChildByField('args'), NoIcon);
    for var Call: TTSNode in FCalls do
    begin
      if CallName(Call) <> 'registercomponents' then Continue;
      var Args: TArray<TTSNode>:= Items(Call.ChildByField('args'));
      if (Length(Args) < 2) or (Args[1].NodeType <> 'exprBrackets') then Continue;
      if not Loaded then
      begin
        Names:= ResourceNames(AnyFile);
        Loaded:= True;
      end;
      for var X: TTSNode in Items(Args[1]) do
      begin
        var Nm: string:= UpperCase(CmpLeaf(Txt(X)));
        if (Nm = '') or NoIcon.ContainsKey(LowerCase(Nm)) then Continue;
        var Found: Boolean:= False;
        for var R: string in Names do
          if (R = Nm) or (StartsStr(Nm, R) and CharInSet(R[Length(Nm) + 1], ['_', '0'..'9'])) then Found:= True;
        if Found then Continue;
        if AnyFile then
          Emit(CMP_PALETTE_ICON_RULE, SEV_HINT,
            Format('Component %s is registered, but no resource the unit includes is named %s: the Tool Palette shows ' +
              'the default icon. Add a %s bitmap to the .dcr', [Txt(X), Nm, Nm]), X, X)
        else
          Emit(CMP_PALETTE_ICON_RULE, SEV_HINT,
            Format('Component %s is registered, but the unit includes no .dcr / .res (and none sits next to it): the Tool ' +
              'Palette shows the default icon. Add {$R *.dcr} with a %s bitmap', [Txt(X), Nm]), X, X);
      end;
    end;
  finally
    NoIcon.Free;
  end;
end;

{ ---------------------------------------------- component-setter-without-invalidate }

procedure TCmpRun.CheckSetterInvalidate;
begin
  for var C: TCmpClass in FClasses.Values do
  begin
    var Paints: TList<TTSNode>:= Methods(C.Name, 'paint');
    if Paints = nil then Continue;
    var Read: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    var PaintIds: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      for var D: TTSNode in Paints do
      begin
        var S: TDictionary<string, Boolean>:= ReachSet(C.Name, D);
        try
          for var K: string in S.Keys do PaintIds.AddOrSetValue(K, True);
        finally
          S.Free;
        end;
      end;
      for var K: string in PaintIds.Keys do
        if C.Fields.ContainsKey(K) then Read.AddOrSetValue(K, True);
      for var P: TCmpProp in C.Props do
        if PaintIds.ContainsKey(P.Name) and C.Fields.ContainsKey(P.Getter) then Read.AddOrSetValue(P.Getter, True);
      for var P: TCmpProp in C.Props do
      begin
        if (P.Setter = '') or (P.Setter = '?') or C.Fields.ContainsKey(P.Setter) then Continue;
        var Bodies: TList<TTSNode>:= Methods(C.Name, P.Setter);
        if Bodies = nil then Continue;
        for var D: TTSNode in Bodies do
        begin
          var Target: TTSNode:= Default(TTSNode);
          var Assigns: TList<TTSNode>:= TList<TTSNode>.Create;
          try
            CmpCollect(D.ChildByField('body'), 'assignment', Assigns);
            for var A: TTSNode in Assigns do
              if Target.IsNull and Read.ContainsKey(AssignKey(A.ChildByField('lhs'))) then Target:= A;
          finally
            Assigns.Free;
          end;
          if Target.IsNull then Continue;
          var Ids: TDictionary<string, Boolean>:= ReachSet(C.Name, D);
          try
            if AnyWord(Ids, REPAINT_WORDS, True) then Continue;
          finally
            Ids.Free;
          end;
          Emit(CMP_SETTER_INVALIDATE_RULE, SEV_HINT,
            Format('Setter of %s changes %s, which Paint reads, but never calls Invalidate: the control keeps showing ' +
              'the old value until something else repaints it', [Txt(P.NameNode), Txt(Target.ChildByField('lhs'))]),
            Target, Target);
        end;
      end;
    finally
      PaintIds.Free;
      Read.Free;
    end;
  end;
end;

{ ------------------------------------- component-fixed-pixels / component-hardcoded-color }

function TCmpRun.HasFixedLiteral(const N: TTSNode): Boolean;
var
  V: Int64;
begin
  if N.IsNull or (N.NodeType = 'exprCall') then Exit(False);
  { A hex literal is a colour or a bit mask, never a distance. }
  if N.NodeType = 'literalNumber' then Exit((not StartsStr('$', Txt(N))) and CmpIntLiteral(Txt(N), V) and (Abs(V) >= MIN_PIXELS));
  if N.NodeType = 'exprBinary' then
  begin
    var Op: string:= Low(N.ChildByField('operator'));
    if Op = '*' then Exit(False);
    if MatchStr(Op, ['div', 'mod', 'shr', 'shl', '/']) then Exit(HasFixedLiteral(N.ChildByField('lhs')));
  end;
  for var I: Integer:= 0 to N.NamedChildCount - 1 do
    if HasFixedLiteral(N.NamedChild(I)) then Exit(True);
  Result:= False;
end;

{ A drawing call whose arguments are distances: the RTL arity of Rect / Bounds / Point (a
  project routine of the same name with another arity is not it), and Draw / StretchDraw only
  on a canvas (an image list's Draw takes an image index). }
function TCmpRun.IsDrawCall(const ACall: TTSNode; const AName: string): Boolean;
const
  RECT_ARITY  = 4;
  POINT_ARITY = 2;
begin
  if not MatchStr(AName, DRAW_CALLS) then Exit(False);
  var N: Integer:= Length(Items(ACall.ChildByField('args')));
  if MatchStr(AName, ['rect', 'bounds']) then Exit(N = RECT_ARITY);
  if AName = 'point' then Exit(N = POINT_ARITY);
  if MatchStr(AName, ['draw', 'stretchdraw']) then
  begin
    var Ent: TTSNode:= ACall.ChildByField('entity');
    Exit((Ent.NodeType = 'exprDot') and EndsStr('canvas', Low(Ent.ChildByField('lhs'))));
  end;
  Result:= True;
end;

function TCmpRun.InsideScaling(const N, ADef: TTSNode): Boolean;
begin
  var P: TTSNode:= N.Parent;
  while (not P.IsNull) and (P.StartByte >= ADef.StartByte) and (P.NodeType <> 'defProc') do
  begin
    if P.NodeType = 'exprCall' then
    begin
      var Nm: string:= CallName(P);
      if ContainsStr(Nm, 'scale') or (Nm = 'muldiv') then Exit(True);
    end;
    P:= P.Parent;
  end;
  Result:= False;
end;

procedure TCmpRun.CheckPaintRoutines;
var
  V: Int64;
begin
  var WantPixels: Boolean:= FCtx.Wants(CMP_FIXED_PIXELS_RULE);
  var WantColor: Boolean:= FCtx.Wants(CMP_HARDCODED_COLOR_RULE);
  var L: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    for var D: TTSNode in FDefs do
    begin
      var C, M: string;
      DefNames(D, C, M);
      var PaintLike: Boolean:= ContainsStr(M, 'paint') or ContainsStr(M, 'draw');
      if not (PaintLike or EndsStr('resize', M)) then Continue;
      var Body: TTSNode:= D.ChildByField('body');
      L.Clear;
      CmpCollect(Body, 'exprCall', L);
      for var Call: TTSNode in L do
      begin
        var Nm: string:= CallName(Call);
        var Args: TTSNode:= Call.ChildByField('args');
        if WantPixels and IsDrawCall(Call, Nm) and (not InsideScaling(Call, D)) and HasFixedLiteral(Args) then
          Emit(CMP_FIXED_PIXELS_RULE, SEV_HINT,
            Format('%s uses a fixed pixel value: it is too small above 96 dpi. Scale it (ScaleValue, MulDiv by the ' +
              'current PPI) or derive it from the font / client size', [Txt(Call.ChildByField('entity'))]), Call, Call);
        if not (WantColor and PaintLike) or Args.IsNull then Continue;
        var Items1: TArray<TTSNode>:= Items(Args);
        if (Nm = 'rgb') or ((Nm = 'tcolor') and (Length(Items1) = 1) and (Items1[0].NodeType = 'literalNumber')) then
          Emit(CMP_HARDCODED_COLOR_RULE, SEV_HINT,
            Format('Hard-coded colour %s in a paint routine: it ignores the system colours and the active VCL style. ' +
              'Use a named system colour or StyleServices', [Txt(Call)]), Call, Call)
        else if MatchStr(Nm, COLOR_CALLS) then
          for var Arg: TTSNode in Items1 do
            if StripParens(Arg).NodeType = 'literalNumber' then
              Emit(CMP_HARDCODED_COLOR_RULE, SEV_HINT,
                Format('Hard-coded colour %s passed to %s: it ignores the system colours and the active VCL style',
                  [Txt(Arg), Txt(Call.ChildByField('entity'))]), Arg, Arg);
      end;
      if not (WantColor and PaintLike) then Continue;
      L.Clear;
      CmpCollect(Body, 'assignment', L);
      for var A: TTSNode in L do
      begin
        var Lhs: string:= AssignKey(A.ChildByField('lhs'));
        var R: TTSNode:= StripParens(A.ChildByField('rhs'));
        if EndsStr('color', Lhs) and (R.NodeType = 'literalNumber') and CmpIntLiteral(Txt(R), V) then
          Emit(CMP_HARDCODED_COLOR_RULE, SEV_HINT,
            Format('Hard-coded colour %s assigned to %s in a paint routine: it ignores the system colours and the ' +
              'active VCL style. Use a named system colour or StyleServices', [Txt(R), Txt(A.ChildByField('lhs'))]), R, R);
      end;
    end;
  finally
    L.Free;
  end;
end;

{ ---------------------------------------------------------- control-fixed-bounds }

function TCmpRun.FixedValue(const N: TTSNode): Boolean;
var
  V: Int64;
begin
  var X: TTSNode:= StripParens(N);
  if X.NodeType = 'literalNumber' then Exit(CmpIntLiteral(Txt(X), V) and (V <> 0));
  if X.NodeType = 'identifier' then Exit(FConsts.TryGetValue(Low(X), V) and (V <> 0));
  Result:= False;
end;

{ The object whose bounds are set is a control: by static type, declared type or own class. }
function TCmpRun.IsControlTarget(const ABase, ADef: TTSNode; const ACls: string): Boolean;
var
  Leaf: string;
  C   : TCmpClass;
begin
  if ABase.IsNull or (Low(ABase) = 'self') then Exit((ACls <> '') and IsKindOf(ACls, BASE_CONTROL));
  if (Reader <> nil) and Reader.Ready and Reader.TypeLeafOf(ABase, Leaf) then Exit(IsKindOf(LowerCase(CmpLeaf(Leaf)), BASE_CONTROL));
  if ABase.NodeType <> 'identifier' then Exit(False);
  var Types: TDictionary<string, string>:= DeclaredTypes(ADef, True);
  try
    if Types.TryGetValue(Low(ABase), Leaf) then Exit(IsKindOf(LowerCase(Leaf), BASE_CONTROL));
  finally
    Types.Free;
  end;
  if (ACls <> '') and FClasses.TryGetValue(ACls, C) and C.Fields.TryGetValue(Low(ABase), Leaf) then
    Exit(IsKindOf(Leaf, BASE_CONTROL));
  Result:= False;
end;

procedure TCmpRun.CheckFixedBounds;
begin
  var Vcl: Boolean:= False;
  for var U: string in FUses do
    if StartsStr('vcl.', U) or MatchStr(U, VCL_UNITS) then Vcl:= True;
  if not Vcl then Exit;
  var L: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    for var D: TTSNode in FDefs do
    begin
      var C, M: string;
      DefNames(D, C, M);
      var Body: TTSNode:= D.ChildByField('body');
      L.Clear;
      CmpCollect(Body, 'assignment', L);
      for var A: TTSNode in L do
      begin
        if EnclosingDef(A).StartByte <> D.StartByte then Continue;
        var Lhs: TTSNode:= A.ChildByField('lhs');
        var Member: TTSNode:= if Lhs.NodeType = 'exprDot' then Lhs.ChildByField('rhs') else Lhs;
        if (Member.NodeType <> 'identifier') or not MatchStr(Low(Member), BOUNDS_MEMBERS) then Continue;
        if not FixedValue(A.ChildByField('rhs')) then Continue;
        var Base: TTSNode:= if Lhs.NodeType = 'exprDot' then Lhs.ChildByField('lhs') else Default(TTSNode);
        if not IsControlTarget(Base, D, C) then Continue;
        Emit(CMP_FIXED_BOUNDS_RULE, SEV_HINT,
          Format('%s is set to the fixed pixel value %s: the control does not grow with the screen scaling. Scale it ' +
            '(ScaleValue / the current PPI) or let Align / Anchors / AutoSize size it', [Txt(Lhs), Txt(A.ChildByField('rhs'))]), A, A);
      end;
      L.Clear;
      CmpCollect(Body, 'exprCall', L);
      for var Call: TTSNode in L do
      begin
        if (CallName(Call) <> 'setbounds') or (EnclosingDef(Call).StartByte <> D.StartByte) then Continue;
        var Args: TTSNode:= Call.ChildByField('args');
        var Fixed: Boolean:= False;
        if not Args.IsNull then
          for var Arg: TTSNode in Items(Args) do
            if FixedValue(Arg) then Fixed:= True;
        if not Fixed then Continue;
        var Ent: TTSNode:= Call.ChildByField('entity');
        var Base: TTSNode:= if Ent.NodeType = 'exprDot' then Ent.ChildByField('lhs') else Default(TTSNode);
        if IsControlTarget(Base, D, C) then
          Emit(CMP_FIXED_BOUNDS_RULE, SEV_HINT,
            Format('%s uses fixed pixel values: the control does not grow with the screen scaling. Scale them or let ' +
              'Align / Anchors size it', [Txt(Call)]), Call, Call);
      end;
    end;
  finally
    L.Free;
  end;
end;

{ ----------------------------------------------------------- write-only-property }

procedure TCmpRun.CheckWriteOnly;
begin
  var L: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    CmpCollect(FRoot, 'declProp', L);
    for var P: TTSNode in L do
      if P.ChildByField('getter').IsNull and (not P.ChildByField('setter').IsNull) and (not P.ChildByField('type').IsNull)
         and not HasChild(P, 'kWriteonly') then
        Emit(CMP_WRITE_ONLY_PROPERTY_RULE, SEV_HINT,
          Format('Property %s can be written but not read: the Object Inspector and the debugger cannot show it and ' +
            'callers cannot check it. Add a read accessor or make it a Set%s method', [Txt(P.ChildByField('name')),
            Txt(P.ChildByField('name'))]), P.ChildByField('name'), P.ChildByField('name'));
  finally
    L.Free;
  end;
end;

{ ------------------------------------------------------- ota-notifier-not-removed }

{ Last dotted segment of an assignment target: Self.FIdx / FIdx[I] / Reg.Index -> fidx / index. }
function LastKey(const AKey: string): string;
begin
  Result:= AKey;
  var P: Integer:= LastDelimiter('.', Result);
  if P > 0 then Result:= Copy(Result, P + 1, MaxInt);
end;

{ The holder of the index, or a variable the unit copies it into (two hops: Reg.Index := FIndex),
  is among the identifiers a matching remove call receives. }
function TCmpRun.ReachesRemove(const AHolder: TTSNode; AGot: TDictionary<string, Boolean>): Boolean;
const
  MAX_COPY_HOPS = 2;
begin
  var Keys: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
  var Assigns: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    var Full: string:= AssignKey(AHolder);
    Keys.AddOrSetValue(Full, True);
    CmpCollect(FRoot, 'assignment', Assigns);
    for var Hop: Integer:= 1 to MAX_COPY_HOPS do
      for var A: TTSNode in Assigns do
        if Keys.ContainsKey(AssignKey(StripParens(A.ChildByField('rhs')))) then
          Keys.AddOrSetValue(AssignKey(A.ChildByField('lhs')), True);
    for var K: string in Keys.Keys do
      if AGot.ContainsKey(LastKey(K)) then Exit(True);
    Result:= False;
  finally
    Assigns.Free;
    Keys.Free;
  end;
end;

procedure TCmpRun.CheckOtaNotifiers;
begin
  var Ota: Boolean:= False;
  for var U: string in FUses do
    if (U = 'toolsapi') or StartsStr('toolsapi.', U) then Ota:= True;
  if not Ota then Exit;
  { remove-call name -> every identifier in its arguments }
  var Removes: TObjectDictionary<string, TDictionary<string, Boolean>>:=
    TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  try
    for var Call: TTSNode in FCalls do
    begin
      var Nm: string:= CallName(Call);
      if not MatchStr(Nm, OTA_REMOVES) then Continue;
      var S: TDictionary<string, Boolean>;
      if not Removes.TryGetValue(Nm, S) then
      begin
        S:= TDictionary<string, Boolean>.Create;
        Removes.Add(Nm, S);
      end;
      AddIdents(Call.ChildByField('args'), S);
    end;
    for var Call: TTSNode in FCalls do
    begin
      var Idx: Integer:= IndexStr(CallName(Call), OTA_ADDS);
      if Idx < 0 then Continue;
      var Remove: string:= OTA_REMOVES[Idx];
      var Got: TDictionary<string, Boolean>;
      var HasRemove: Boolean:= Removes.TryGetValue(Remove, Got);
      var Par: TTSNode:= Call.Parent;
      var Ent: string:= Txt(Call.ChildByField('entity'));
      if OTA_ADDS[Idx] = OTA_NO_INDEX then
      begin
        if not HasRemove then
          Emit(CMP_OTA_NOTIFIER_RULE, SEV_WARNING,
            Format('%s is never undone: the unit calls no %s, so the IDE keeps the page after the package unloads',
              [Ent, OTA_REMOVES[Idx]]), Call, Call);
        Continue;
      end;
      if Par.NodeType = 'statement' then
        Emit(CMP_OTA_NOTIFIER_RULE, SEV_WARNING,
          Format('The index %s returns is thrown away, so the registration can never be removed: when the package ' +
            'unloads the IDE keeps calling freed code. Store the index and pass it to %s on unload', [Ent, OTA_REMOVES[Idx]]),
          Call, Call)
      else if (Par.NodeType = 'assignment') and (Par.ChildByField('rhs').StartByte = Call.StartByte) then
      begin
        if HasRemove and ReachesRemove(Par.ChildByField('lhs'), Got) then Continue;
        Emit(CMP_OTA_NOTIFIER_RULE, SEV_WARNING,
          Format('The index from %s is kept in %s, but no %s in this unit receives it: when the package unloads the ' +
            'IDE keeps calling freed code. Call %s(%s) on unload', [Ent, Txt(Par.ChildByField('lhs')), OTA_REMOVES[Idx],
            OTA_REMOVES[Idx], Txt(Par.ChildByField('lhs'))]), Call, Call);
      end;
    end;
  finally
    Removes.Free;
  end;
end;

{ ------------------------------------------- interface-holder-of-non-refcounted (widened) }

procedure TCmpRun.CheckSupportsHolder;
var
  Leaf: string;
begin
  if (Reader = nil) or not Reader.Ready then Exit;
  for var Call: TTSNode in FCalls do
  begin
    if CallName(Call) <> 'supports' then Continue;
    var Args: TArray<TTSNode>:= Items(Call.ChildByField('args'));
    if Length(Args) <> SUPPORTS_ARGS then Continue;
    var X: TTSNode:= StripParens(Args[0]);
    Leaf:= '';
    if Low(X) = 'self' then
    begin
      var C, M: string;
      var D: TTSNode:= EnclosingDef(Call);
      if (not D.IsNull) and DefNames(D, C, M) then Leaf:= C;
    end
    else if Reader.TypeLeafOf(X, Leaf) then Leaf:= LowerCase(CmpLeaf(Leaf))
    else Continue;
    if (Leaf = '') or (not IsKindOf(Leaf, BASE_COMPONENT)) or OwnsRefCount(Leaf) then Continue;
    Emit(CMP_INTERFACE_HOLDER_HOST, SEV_WARNING,
      Format('Supports stores %s, a %s, in interface %s: TComponent does not count references, so %s keeps nothing ' +
        'alive and dangles once the component is freed', [Txt(X), Leaf, Txt(Args[2]), Txt(Args[2])]),
      Call, Call);
  end;
end;

function TCmpRun.IsIntfType(const ALeaf: string): Boolean;
begin
  if (Length(ALeaf) >= 2) and (ALeaf[1] = 'I') and CharInSet(ALeaf[2], ['A'..'Z']) then Exit(True);
  Result:= (Reader <> nil) and (Reader.Descends(LowerCase(ALeaf), 'iinterface') = tdYes);
end;

function TCmpRun.IsComponentName(const AName, ACls: string; ATyped: TDictionary<string, string>): Boolean;
var
  Leaf: string;
  C   : TCmpClass;
begin
  if ATyped.TryGetValue(AName, Leaf) then Exit(IsKindOf(LowerCase(Leaf), BASE_COMPONENT));
  if (ACls <> '') and FClasses.TryGetValue(ACls, C) and C.Fields.TryGetValue(AName, Leaf) then
    Exit(IsKindOf(Leaf, BASE_COMPONENT));
  Result:= False;
end;

procedure TCmpRun.CheckFreeWhileHeld(const ADef: TTSNode);
var
  C, M, T: string;
begin
  var Locals: TDictionary<string, string>:= DeclaredTypes(ADef, False);
  var Typed: TDictionary<string, string>:= DeclaredTypes(ADef, True);
  var Binds: TList<TBind>:= TList<TBind>.Create;
  var Assigns: TList<TTSNode>:= TList<TTSNode>.Create;
  var L: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    if Locals.Count = 0 then Exit;
    DefNames(ADef, C, M);
    var Body: TTSNode:= ADef.ChildByField('body');
    CmpCollect(Body, 'assignment', Assigns);
    for var A: TTSNode in Assigns do
    begin
      var I: string:= Low(A.ChildByField('lhs'));
      if not (Locals.TryGetValue(I, T) and IsIntfType(T)) then Continue;
      var R: TTSNode:= StripParens(A.ChildByField('rhs'));
      if (R.NodeType = 'exprBinary') and (Low(R.ChildByField('operator')) = 'as') then R:= StripParens(R.ChildByField('lhs'))
      else if (R.NodeType = 'exprCall') and (Length(Items(R.ChildByField('args'))) = 1)
              and (R.ChildByField('entity').NodeType = 'identifier') and IsIntfType(Txt(R.ChildByField('entity'))) then
        R:= StripParens(Items(R.ChildByField('args'))[0]);
      if (R.NodeType = 'identifier') and IsComponentName(Low(R), C, Typed) then
      begin
        var B: TBind;
        B.Intf:= I;
        B.Obj := Low(R);
        B.Node:= A;
        Binds.Add(B);
      end;
    end;
    CmpCollect(Body, 'exprCall', L);
    for var Call: TTSNode in L do
    begin
      var Args: TArray<TTSNode>:= Items(Call.ChildByField('args'));
      if (CallName(Call) <> 'supports') or (Length(Args) <> SUPPORTS_ARGS) then Continue;
      var I: string:= Low(Args[2]);
      var X: TTSNode:= StripParens(Args[0]);
      if Locals.TryGetValue(I, T) and IsIntfType(T) and (X.NodeType = 'identifier') and IsComponentName(Low(X), C, Typed) then
      begin
        var B: TBind;
        B.Intf:= I;
        B.Obj := Low(X);
        B.Node:= Call;
        Binds.Add(B);
      end;
    end;
    if Binds.Count = 0 then Exit;
    { The frees: X.Free / X.DisposeOf / FreeAndNil(X), in source order. }
    var Frees: TList<TBind>:= TList<TBind>.Create;
    try
      var Dots: TList<TTSNode>:= TList<TTSNode>.Create;
      try
        CmpCollect(Body, 'exprDot', Dots);
        for var D: TTSNode in Dots do
          if (D.ChildByField('lhs').NodeType = 'identifier') and MatchStr(Low(D.ChildByField('rhs')), FREE_MEMBERS) then
          begin
            var F: TBind;
            F.Obj := Low(D.ChildByField('lhs'));
            F.Node:= D;
            Frees.Add(F);
          end;
      finally
        Dots.Free;
      end;
      for var Call: TTSNode in L do
        if (CallName(Call) = 'freeandnil') and (Length(Items(Call.ChildByField('args'))) = 1) then
        begin
          var F: TBind;
          F.Obj := Low(StripParens(Items(Call.ChildByField('args'))[0]));
          F.Node:= Call;
          Frees.Add(F);
        end;
      for var B: TBind in Binds do
      begin
        var First: TTSNode:= Default(TTSNode);
        for var F: TBind in Frees do
          if (F.Obj = B.Obj) and (F.Node.StartByte >= B.Node.EndByte)
             and (First.IsNull or (F.Node.StartByte < First.StartByte)) then First:= F.Node;
        if First.IsNull then Continue;
        var Cleared: Boolean:= False;
        for var A: TTSNode in Assigns do
          if (Low(A.ChildByField('lhs')) = B.Intf) and (A.StartByte >= B.Node.EndByte) and (A.StartByte < First.StartByte) then
            Cleared:= True;
        if Cleared then Continue;
        Emit(CMP_INTERFACE_HOLDER_HOST, SEV_WARNING,
          Format('%s is freed while local interface %s still refers to it: TComponent does not count references, and %s ' +
            'is released at the end of the routine (or used later) on the freed object. Set %s := nil before freeing %s',
            [B.Obj, B.Intf, B.Intf, B.Intf, B.Obj]), First, First);
      end;
    finally
      Frees.Free;
    end;
  finally
    L.Free;
    Assigns.Free;
    Binds.Free;
    Typed.Free;
    Locals.Free;
  end;
end;

procedure TCmpRun.CheckInterfaceHolder;
begin
  CheckSupportsHolder;
  for var D: TTSNode in FDefs do CheckFreeWhileHeld(D);
end;

{ ------------------------------------------------------------------- driver }

function TCmpRun.Run: TArray<TLintFinding>;
begin
  Prepare;
  if FCtx.Wants(CMP_FREE_NOTIFICATION_RULE) then CheckFreeNotification;
  if FCtx.Wants(CMP_DEFAULT_MISMATCH_RULE) then CheckDefaultMismatch;
  if FCtx.Wants(CMP_PALETTE_ICON_RULE) then CheckPaletteIcon;
  if FCtx.Wants(CMP_SETTER_INVALIDATE_RULE) then CheckSetterInvalidate;
  if FCtx.Wants(CMP_FIXED_PIXELS_RULE) or FCtx.Wants(CMP_HARDCODED_COLOR_RULE) then CheckPaintRoutines;
  if FCtx.Wants(CMP_FIXED_BOUNDS_RULE) then CheckFixedBounds;
  if FCtx.Wants(CMP_WRITE_ONLY_PROPERTY_RULE) then CheckWriteOnly;
  if FCtx.Wants(CMP_OTA_NOTIFIER_RULE) then CheckOtaNotifiers;
  if FCtx.Wants(CMP_INTERFACE_HOLDER_HOST) then CheckInterfaceHolder;
  Result:= FOut.ToArray;
end;

{ ------------------------------------------------------------- TV151CMPRules }

class procedure TV151CMPRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(CMP_FREE_NOTIFICATION_RULE, 'bug-patterns', SEV_WARNING,
    'Component-typed property stores a linked component without FreeNotification -- the field dangles when that component is freed'));
  ADecls.Add(V151Rule(CMP_DEFAULT_MISMATCH_RULE, 'bug-patterns', SEV_WARNING,
    'Property default value differs from the value the constructor sets -- forms that kept the default load the wrong value'));
  ADecls.Add(V151Rule(CMP_PALETTE_ICON_RULE, 'other', SEV_HINT,
    'Registered component has no palette bitmap in the .dcr / .res the unit includes'));
  ADecls.Add(V151Rule(CMP_SETTER_INVALIDATE_RULE, 'bug-patterns', SEV_HINT,
    'Property setter changes a field Paint reads but never calls Invalidate -- the control shows the old value'));
  ADecls.Add(V151Rule(CMP_FIXED_PIXELS_RULE, 'platform', SEV_HINT,
    'Drawing call in a paint / resize routine uses a fixed pixel value -- too small above 96 dpi', False));
  ADecls.Add(V151Rule(CMP_HARDCODED_COLOR_RULE, 'platform', SEV_HINT,
    'Paint routine uses a hard-coded colour -- ignores system colours and VCL styles', False));
  ADecls.Add(V151Rule(CMP_FIXED_BOUNDS_RULE, 'platform', SEV_HINT,
    'Control bounds set to a fixed pixel value in code -- does not follow screen scaling', False));
  ADecls.Add(V151Rule(CMP_WRITE_ONLY_PROPERTY_RULE, 'structure', SEV_HINT,
    'Property has a write accessor but no read accessor', False));
  ADecls.Add(V151Rule(CMP_OTA_NOTIFIER_RULE, 'resource-lifetime', SEV_WARNING,
    'IDE notifier / wizard / binding registered through the Open Tools API is never removed -- the IDE calls freed code after unload'));
  ADecls.Add(V151Host(CMP_INTERFACE_HOLDER_HOST));
end;

class function TV151CMPRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  var PF: TParsedFile:= TAstParseCache.Get(ACtx.Path);
  if (PF.Tree = nil) or (PF.Src = nil) then Exit;
  var Run: TCmpRun:= TCmpRun.Create(ACtx, PF.Src, PF.RawSrc, PF.Tree.RootNode);
  try
    Result:= Run.Run;
  finally
    Run.Free;
  end;
end;

class function TV151CMPRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV151CMPRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV151CMPRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

end.
