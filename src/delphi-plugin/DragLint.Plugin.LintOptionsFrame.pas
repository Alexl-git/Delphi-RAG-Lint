unit DragLint.Plugin.LintOptionsFrame;

{ TLintOptionsFrame: dock tab for per-project lint rule enable/disable and
  param editing.  Loads the rule catalog via "drag-lint rules --json", renders
  each category as a TGroupBox with per-rule TCheckBoxes and inline param
  editors (TSpinEdit for int params, TEdit for string/stringlist/bool), and
  round-trips the active project's drag-lint-lint.json via TLintConfigWriter.

  Design notes:
  - All controls are built dynamically in the constructor (no .dfm).
  - The ONLY ToolsAPI dependency is GetActiveProjDir (isolated function).
  - ReloadCatalogAndConfig and Save are the two public operations.
  - A tri-state category checkbox (cbChecked/cbUnchecked/cbGrayed) lets the
    user enable or disable an entire rule group with one click.
  - A "Save" button (rather than autosave) is the round-trip trigger; simpler
    and safer than per-control change handlers mutating the file on every
    keystroke.

  Param routing (all params of all rules are round-tripped):
    naming scalar string params -> cfg.Naming.* fields (by param name):
      class_prefix     -> Naming.ClassPrefix    (under naming.type_prefix.class)
      exception_prefix -> Naming.ExceptionPrefix (naming.type_prefix.exception)
      interface_prefix -> Naming.InterfacePrefix (naming.type_prefix.interface)
      pointer_prefix   -> Naming.PointerPrefix   (naming.type_prefix.pointer)
      field_prefix     -> Naming.FieldPrefix
      param_prefix     -> Naming.ParamPrefix
      method_case      -> Naming.MethodCase
      local_case       -> Naming.LocalCase
      keyword_case     -> Naming.KeywordCase
    naming array params (TEdit, joined/split on comma):
      const_case           -> Naming.ConstCase (TArray<string>)
      hungarian_prefixes   -> Naming.HungarianPrefixes (TArray<string>)
    naming int param:
      min_identifier_len   -> Naming.MinIdentifierLen  (NOT the thresholds block)
    naming bool param (TEdit "true"/"false"):
      short_identifier_check -> Naming.ShortIdentifierCheck
    any other int param -> thresholds block via SetThreshold (e.g. complexity rules)
}

interface

uses
  System.Classes
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.ExtCtrls
  , Vcl.StdCtrls
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Dock tab frame that loads the drag-lint rule catalog and lets
  /// the user enable/disable rules and edit per-rule parameters, then saves
  /// the result back to the active project's drag-lint-lint.json.</summary>
  TLintOptionsFrame = class(TForm)
  private
    { top bar }
    FPanelTop  : TPanel   ;
    FLblCounts : TLabel   ;
    FBtnReload : TButton  ;
    FBtnSave   : TButton  ;
    FLblProfile: TLabel   ;
    FCboProfile: TComboBox;
    { scrollable body }
    FScroll    : TScrollBox;
    { internal catalog + config state }
    FCatalogJSON: string;       { last successful raw JSON from "rules --json" }
    FHasData   : Boolean;       { True after at least one successful load }
    FProfile   : string;        { active profile name; '' = base config }
    FCfg       : TLintConfig;   { active config (base or profile-merged) }
    { search filter }
    FSearch    : string;        { current trimmed search text; '' = show all }
    FEdtSearch : TEdit;         { search box in top panel }
    procedure BuildControls;
    procedure BtnReloadClick  (Sender: TObject);
    procedure BtnSaveClick    (Sender: TObject);
    procedure CatHeaderClick  (Sender: TObject);
    procedure RuleChecked     (Sender: TObject);
    procedure ProfileSelected (Sender: TObject);
    procedure SearchChanged   (Sender: TObject);
    procedure ClearBody;
    procedure RenderCatalog(const AJSON: string);
    procedure UpdateCountsLabel;
    { helpers }
    function  CfgPath: string;
    procedure ReloadProfileList;
  public
    /// <summary>Creates the frame and builds all controls dynamically.
    /// No catalog is loaded yet; call ReloadCatalogAndConfig explicitly.</summary>
    constructor Create(AOwner: TComponent); override;
    /// <summary>Runs "drag-lint rules --json", parses the catalog, loads the
    /// active project's drag-lint-lint.json, and re-renders all rule controls
    /// with the resulting enabled/disabled/param state.</summary>
    procedure ReloadCatalogAndConfig;
    /// <summary>Walks all rendered rule controls, mutates an in-memory
    /// TLintConfig via TLintConfigWriter setters, and saves the result to
    /// the active project's drag-lint-lint.json.</summary>
    procedure Save;
  end;

/// <summary>Creates a TLintOptionsFrame owned by AOwner and parented into
/// AParent (typically a dock tab sheet).  Mirrors the CreateEmbeddedXxx
/// pattern used by other dock tabs.  Task 3 calls this from DockForm.</summary>
procedure CreateEmbeddedLintOptions(AOwner: TComponent; AParent: TWinControl);

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.JSON
  , System.Generics.Collections
  , Winapi.Windows
  , Vcl.ComCtrls
  , Vcl.Samples.Spin
  , ToolsAPI
  , DragLint.Plugin.ProcRun
  , DragLint.Plugin.Settings
  , DRagLint.Lint.ConfigWriter
  ;

{ ============================================================
  Internal data types for catalog rows
  ============================================================ }

type
  TParamKind = (pkInt, pkString, pkStringList, pkBool);

  TRuleParam = record
    Name        : string    ;
    Kind        : TParamKind;
    DefaultValue: string    ;
  end;

  TCatalogRule = record
    Id             : string;
    Category       : string;
    Title          : string;
    DefaultSeverity: string;
    DefaultEnabled : Boolean;
    Source         : string;
    Params         : TArray<TRuleParam>;
  end;

  TCatalogRules = TArray<TCatalogRule>;

{ ============================================================
  TParamEditor: holds ONE param control (SpinEdit or TEdit)
  together with its param name and kind so Save can route it.
  ============================================================ }

type
  TParamEditor = record
    ParamName: string    ;
    Kind     : TParamKind;
    Ctrl     : TControl  ;  { TSpinEdit for pkInt, TEdit for pkString/pkStringList/pkBool }
  end;

{ ============================================================
  Tag object: each rule checkbox carries one of these as Tag
  so the Save walk can recover (Rule, ALL param editors).
  We use a TComponent-descendant so VCL owns it.
  ============================================================ }

type
  TRuleTag = class(TComponent)
  public
    Rule    : TCatalogRule;
    Editors : TArray<TParamEditor>;  { one entry per rule param, in catalog order }
    constructor CreateForRule(AOwner: TComponent; const ARule: TCatalogRule);
    destructor  Destroy; override;
  end;

constructor TRuleTag.CreateForRule(AOwner: TComponent; const ARule: TCatalogRule);
begin
  inherited Create(AOwner);
  Rule   := ARule;
  Editors:= nil;
end;

destructor TRuleTag.Destroy;
begin
  Editors:= nil;
  inherited;
end;

{ ============================================================
  Tag for category-header checkbox
  ============================================================ }

type
  TCatTag = class(TComponent)
  public
    RuleBoxes: TList<TCheckBox>;
    constructor CreateForCat(AOwner: TComponent);
    destructor  Destroy; override;
  end;

constructor TCatTag.CreateForCat(AOwner: TComponent);
begin
  inherited Create(AOwner);
  RuleBoxes:= TList<TCheckBox>.Create;
end;

destructor TCatTag.Destroy;
begin
  RuleBoxes.Free;
  inherited;
end;

{ ============================================================
  Helper: exe resolution (mirrors DockForm pattern)
  ============================================================ }

function ResolveExe: string;
var
  BplDir, Win64Exe: string;
begin
  { 1) An explicit, valid ExePath setting always wins. }
  Result:= LoadSettings.ExePath;
  if (Result <> '') and FileExists(Result) then Exit;
  { 2) Prefer the Win64 engine in the sibling dll-win64\ folder -- the same
    resolution the rest of the plugin uses (DLExe64). The 32-bit BPL lives in
    dll-win32\, whose drag-lint.exe may be a stale build predating `rules`; the
    Win64 exe is the current engine. A 32-bit process can spawn a 64-bit child. }
  BplDir  := ExtractFilePath(GetModuleName(HInstance));
  Win64Exe:= ExtractFilePath(ExcludeTrailingPathDelimiter(BplDir)) + 'dll-win64\drag-lint.exe';
  if FileExists(Win64Exe) then Exit(Win64Exe);
  { 3) Fall back to the exe next to the BPL, then PATH. }
  if FileExists(BplDir + 'drag-lint.exe') then Exit(BplDir + 'drag-lint.exe');
  Result:= 'drag-lint.exe';
end;

{ ============================================================
  Helper: active project directory (ONLY ToolsAPI dependency)
  ============================================================ }

function GetActiveProjDir: string;
var
  MS: IOTAModuleServices;
  PG: IOTAProjectGroup  ;
  PR: IOTAProject       ;
begin
  Result:= '';
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
    if MS = nil then Exit;
    PG:= MS.MainProjectGroup; if PG = nil then Exit;
    PR:= PG.ActiveProject;    if PR = nil then Exit;
    Result:= ExtractFilePath(PR.FileName);
  except
    Result:= '';
  end;
end;

{ ============================================================
  Helper: parse TParamKind from JSON "type" string
  ============================================================ }

function ParseParamKind(const AType: string): TParamKind;
begin
  if SameText(AType, 'int') then
    Result:= pkInt
  else if SameText(AType, 'bool') then
    Result:= pkBool
  else if SameText(AType, 'stringlist') then
    Result:= pkStringList
  else
    Result:= pkString;
end;

{ ============================================================
  Helper: parse catalog JSON into TCatalogRules
  ============================================================ }

function ParseCatalog(const AJSON: string): TCatalogRules;
var
  Root    : TJSONValue;
  RulesArr: TJSONArray;
  RuleVal : TJSONValue;
  RuleObj : TJSONObject;
  ParamsArr: TJSONArray;
  ParamVal : TJSONValue;
  ParamObj : TJSONObject;
  Rule    : TCatalogRule;
  Param   : TRuleParam  ;
  EnabledV: TJSONValue  ;
  i       : Integer     ;
begin
  Result:= nil;
  Root:= TJSONObject.ParseJSONValue(AJSON);
  if Root = nil then Exit;
  try
    if not (Root is TJSONObject) then Exit;
    RulesArr:= TJSONObject(Root).GetValue('rules') as TJSONArray;
    if RulesArr = nil then Exit;
    SetLength(Result, RulesArr.Count);
    i:= 0;
    for RuleVal in RulesArr do
    begin
      if not (RuleVal is TJSONObject) then Continue;
      RuleObj:= RuleVal as TJSONObject;
      Rule.Id             := RuleObj.GetValue('id')              .Value;
      Rule.Category       := RuleObj.GetValue('category')        .Value;
      Rule.Title          := RuleObj.GetValue('title')           .Value;
      Rule.DefaultSeverity:= '';
      Rule.Source         := '';
      Rule.Params         := nil;
      if RuleObj.GetValue('default_severity') <> nil then
        Rule.DefaultSeverity:= RuleObj.GetValue('default_severity').Value;
      if RuleObj.GetValue('source') <> nil then
        Rule.Source:= RuleObj.GetValue('source').Value;
      { default_enabled: JSON bool }
      EnabledV:= RuleObj.GetValue('default_enabled');
      if (EnabledV <> nil) and (EnabledV is TJSONBool) then
        Rule.DefaultEnabled:= TJSONBool(EnabledV).AsBoolean
      else if EnabledV <> nil then
        Rule.DefaultEnabled:= SameText(EnabledV.Value, 'true')
      else
        Rule.DefaultEnabled:= True;
      { params array }
      if RuleObj.GetValue('params') is TJSONArray then
      begin
        ParamsArr:= RuleObj.GetValue('params') as TJSONArray;
        for ParamVal in ParamsArr do
        begin
          if not (ParamVal is TJSONObject) then Continue;
          ParamObj:= ParamVal as TJSONObject;
          Param.Name:= '';
          Param.DefaultValue:= '';
          Param.Kind:= pkString;
          if ParamObj.GetValue('name')    <> nil then Param.Name        := ParamObj.GetValue('name').Value;
          if ParamObj.GetValue('default') <> nil then Param.DefaultValue:= ParamObj.GetValue('default').Value;
          if ParamObj.GetValue('type')    <> nil then Param.Kind        := ParseParamKind(ParamObj.GetValue('type').Value);
          Rule.Params:= Rule.Params + [Param];
        end;
      end;
      Result[i]:= Rule;
      Inc(i);
    end;
    SetLength(Result, i);
  finally
    Root.Free;
  end;
end;

{ ============================================================
  Helper: join a string array into a comma-separated string
  ============================================================ }

function JoinStrArr(const AArr: TArray<string>): string;
var
  i: Integer;
begin
  Result:= '';
  for i:= 0 to High(AArr) do
  begin
    if i > 0 then Result:= Result + ', ';
    Result:= Result + AArr[i];
  end;
end;

{ ============================================================
  Helper: split a comma-separated string into a trimmed array,
  dropping empty parts
  ============================================================ }

function SplitCommaTrimmed(const AText: string): TArray<string>;
var
  Parts: TArray<string>;
  S    : string;
begin
  Result:= nil;
  Parts:= AText.Split([',']);
  for S in Parts do
    if Trim(S) <> '' then
      Result:= Result + [Trim(S)];
end;

{ ============================================================
  Helper: is this param name a naming-block int param?
  Only min_identifier_len maps to Naming.MinIdentifierLen.
  ============================================================ }

function IsNamingIntParam(const AName: string): Boolean;
begin
  Result:= SameText(AName, 'min_identifier_len');
end;

{ ============================================================
  Helper: is this param name a naming-block bool param?
  ============================================================ }

function IsNamingBoolParam(const AName: string): Boolean;
begin
  Result:= SameText(AName, 'short_identifier_check');
end;

{ ============================================================
  Helper: is this param name a naming-block array param?
  ============================================================ }

function IsNamingArrayParam(const AName: string): Boolean;
begin
  Result:= SameText(AName, 'const_case') or SameText(AName, 'hungarian_prefixes');
end;

{ ============================================================
  Helper: is this param name a naming-block scalar string?
  ============================================================ }

function IsNamingStringParam(const AName: string): Boolean;
begin
  Result:= SameText(AName, 'class_prefix') or
           SameText(AName, 'exception_prefix') or
           SameText(AName, 'interface_prefix') or
           SameText(AName, 'pointer_prefix') or
           SameText(AName, 'field_prefix') or
           SameText(AName, 'param_prefix') or
           SameText(AName, 'method_case') or
           SameText(AName, 'local_case') or
           SameText(AName, 'keyword_case');
end;

{ ============================================================
  Helper: read a naming scalar string from cfg by param name
  ============================================================ }

function GetNamingString(const ACfg: TLintConfig; const AName: string): string;
begin
  if SameText(AName, 'class_prefix') then
    Result:= ACfg.Naming.ClassPrefix
  else if SameText(AName, 'exception_prefix') then
    Result:= ACfg.Naming.ExceptionPrefix
  else if SameText(AName, 'interface_prefix') then
    Result:= ACfg.Naming.InterfacePrefix
  else if SameText(AName, 'pointer_prefix') then
    Result:= ACfg.Naming.PointerPrefix
  else if SameText(AName, 'field_prefix') then
    Result:= ACfg.Naming.FieldPrefix
  else if SameText(AName, 'param_prefix') then
    Result:= ACfg.Naming.ParamPrefix
  else if SameText(AName, 'method_case') then
    Result:= ACfg.Naming.MethodCase
  else if SameText(AName, 'local_case') then
    Result:= ACfg.Naming.LocalCase
  else if SameText(AName, 'keyword_case') then
    Result:= ACfg.Naming.KeywordCase
  else
    Result:= '';
end;

{ ============================================================
  Helper: write a naming scalar string back to cfg by param name
  ============================================================ }

procedure SetNamingString(var ACfg: TLintConfig; const AName, AValue: string);
begin
  if SameText(AName, 'class_prefix') then
    ACfg.Naming.ClassPrefix:= AValue
  else if SameText(AName, 'exception_prefix') then
    ACfg.Naming.ExceptionPrefix:= AValue
  else if SameText(AName, 'interface_prefix') then
    ACfg.Naming.InterfacePrefix:= AValue
  else if SameText(AName, 'pointer_prefix') then
    ACfg.Naming.PointerPrefix:= AValue
  else if SameText(AName, 'field_prefix') then
    ACfg.Naming.FieldPrefix:= AValue
  else if SameText(AName, 'param_prefix') then
    ACfg.Naming.ParamPrefix:= AValue
  else if SameText(AName, 'method_case') then
    ACfg.Naming.MethodCase:= AValue
  else if SameText(AName, 'local_case') then
    ACfg.Naming.LocalCase:= AValue
  else if SameText(AName, 'keyword_case') then
    ACfg.Naming.KeywordCase:= AValue;
end;

{ ============================================================
  Helper: recompute category header tri-state from its rule boxes
  ============================================================ }

procedure RecomputeCatTriState(ACatCB: TCheckBox);
var
  CT     : TCatTag  ;
  CB     : TCheckBox;
  HaveOn , HaveOff: Boolean;
begin
  if not (TObject(ACatCB.Tag) is TCatTag) then Exit;
  CT:= TCatTag(TObject(ACatCB.Tag));
  HaveOn := False;
  HaveOff:= False;
  for CB in CT.RuleBoxes do
  begin
    if CB.Checked then HaveOn:= True else HaveOff:= True;
    if HaveOn and HaveOff then Break;
  end;
  ACatCB.OnClick:= nil;
  try
    if HaveOn and not HaveOff then
      ACatCB.State:= cbChecked
    else if HaveOff and not HaveOn then
      ACatCB.State:= cbUnchecked
    else
      ACatCB.State:= cbGrayed;
  finally
    { re-connect OnClick from the stored tag }
  end;
end;

{ ============================================================
  Search helpers
  ============================================================ }

/// <summary>Returns True iff ARule should be shown given ASearch filter.
/// Case-insensitive substring match on Id or Title; empty ASearch = show all.</summary>
function RuleMatchesSearch(const ARule: TCatalogRule; const ASearch: string): Boolean;
begin
  if ASearch = '' then
    Result:= True
  else
    Result:= ContainsText(ARule.Id, ASearch) or ContainsText(ARule.Title, ASearch);
end;

/// <summary>OnChange handler for the search TEdit.  Updates FSearch and
/// re-renders the catalog from the cached JSON without a CLI re-call.</summary>
procedure TLintOptionsFrame.SearchChanged(Sender: TObject);
begin
  FSearch:= Trim(FEdtSearch.Text);
  if FHasData then
    RenderCatalog(FCatalogJSON);
end;

{ ============================================================
  TLintOptionsFrame
  ============================================================ }

constructor TLintOptionsFrame.Create(AOwner: TComponent);
begin
  { CreateNew (NOT Create) -- this is a code-built form with NO .dfm resource;
    the TFrame/TCustomForm Create path would call InitInheritedComponent and
    raise EResNotFound. Mirrors TDragLintStructureForm (the working dock tab). }
  inherited CreateNew(AOwner);
  FCatalogJSON:= '';
  FHasData    := False;
  FProfile    := '';
  FCfg        := TLintConfig.Load('', '');  { default no-op config }
  BuildControls;
end;

procedure TLintOptionsFrame.BuildControls;
const
  PH = 34;   { top panel height }
begin
  Width := 500;
  Height:= 600;

  { --- Top panel: counts + buttons --- }
  FPanelTop:= TPanel.Create(Self);
  FPanelTop.Parent     := Self;
  FPanelTop.Align      := alTop;
  FPanelTop.Height     := PH;
  FPanelTop.BevelOuter := bvNone;

  FBtnSave:= TButton.Create(Self);
  FBtnSave.Parent  := FPanelTop;
  FBtnSave.Caption := 'Save';
  FBtnSave.Width   := 60;
  FBtnSave.Height  := 24;
  FBtnSave.Top     := 4;
  FBtnSave.Anchors := [akTop, akRight];
  FBtnSave.Left    := FPanelTop.Width - FBtnSave.Width - 4;
  FBtnSave.OnClick := BtnSaveClick;

  FBtnReload:= TButton.Create(Self);
  FBtnReload.Parent  := FPanelTop;
  FBtnReload.Caption := 'Reload';
  FBtnReload.Width   := 60;
  FBtnReload.Height  := 24;
  FBtnReload.Top     := 4;
  FBtnReload.Anchors := [akTop, akRight];
  FBtnReload.Left    := FBtnSave.Left - FBtnReload.Width - 4;
  FBtnReload.OnClick := BtnReloadClick;

  { Profile combo: editable drop-down; (base) = top-level config, any other
    name = named profile.  Placed to the left of Reload with a short label. }
  FCboProfile:= TComboBox.Create(Self);
  FCboProfile.Parent  := FPanelTop;
  FCboProfile.Style   := csDropDown;   { editable -- lets the user type a new name }
  FCboProfile.Width   := 100;
  FCboProfile.Height  := 24;
  FCboProfile.Top     := 4;
  FCboProfile.Anchors := [akTop, akRight];
  FCboProfile.Left    := FBtnReload.Left - FCboProfile.Width - 4;
  FCboProfile.OnSelect:= ProfileSelected;
  FCboProfile.Items.Add('(base)');
  FCboProfile.ItemIndex:= 0;

  FLblProfile:= TLabel.Create(Self);
  FLblProfile.Parent  := FPanelTop;
  FLblProfile.Caption := 'Profile:';
  FLblProfile.AutoSize:= True;
  FLblProfile.Top     := 10;
  FLblProfile.Left    := FCboProfile.Left - 48;
  FLblProfile.Anchors := [akTop, akRight];

  { Search box: placed between counts label and profile label }
  FEdtSearch:= TEdit.Create(Self);
  FEdtSearch.Parent   := FPanelTop;
  FEdtSearch.Width    := 120;
  FEdtSearch.Height   := 24;
  FEdtSearch.Top      := 4;
  FEdtSearch.Anchors  := [akTop, akRight];
  FEdtSearch.Left     := FLblProfile.Left - FEdtSearch.Width - 4;
  FEdtSearch.TextHint := 'Search rules...';
  FEdtSearch.OnChange := SearchChanged;

  FLblCounts:= TLabel.Create(Self);
  FLblCounts.Parent  := FPanelTop;
  FLblCounts.Left    := 8;
  FLblCounts.Top     := 10;
  FLblCounts.Caption := 'Not loaded';
  FLblCounts.AutoSize:= True;
  FLblCounts.Anchors := [akLeft, akTop, akRight];

  { --- Scrollable body --- }
  FScroll:= TScrollBox.Create(Self);
  FScroll.Parent    := Self;
  FScroll.Align     := alClient;
  FScroll.AutoScroll:= True;
  FScroll.BorderStyle:= bsNone;
end;

procedure TLintOptionsFrame.ClearBody;
var
  i: Integer;
begin
  { Remove all child controls from the scroll box, oldest-first to avoid
    reparenting artefacts.  Owned controls are freed by Self on destroy,
    but we want them gone from the scroll box now. }
  for i:= FScroll.ControlCount - 1 downto 0 do
    FScroll.Controls[i].Free;
end;

{ ---- category header OnClick: toggle all rule boxes in the group ---- }

procedure TLintOptionsFrame.CatHeaderClick(Sender: TObject);
var
  CB : TCheckBox;
  CT : TCatTag  ;
  RCB: TCheckBox;
  WantChecked: Boolean;
begin
  CB:= TCheckBox(Sender);
  if not (TObject(CB.Tag) is TCatTag) then Exit;
  CT:= TCatTag(TObject(CB.Tag));
  { Use new state as target; if grayed, user click moves to checked. }
  WantChecked:= CB.State <> cbUnchecked;
  CB.AllowGrayed:= False; { user click collapses grayed to checked/unchecked }
  for RCB in CT.RuleBoxes do
    RCB.Checked:= WantChecked;
end;

{ ---- rule checkbox OnClick: propagate to parent cat header ---- }

procedure TLintOptionsFrame.RuleChecked(Sender: TObject);
var
  RuleCB  : TCheckBox  ;
  Prnt    : TWinControl;
  HeaderCB: TCheckBox  ;
  j       : Integer    ;
begin
  RuleCB:= TCheckBox(Sender);
  { Walk siblings to find the category header checkbox (carries TCatTag) }
  Prnt:= RuleCB.Parent;
  if Prnt = nil then Exit;
  for j:= 0 to Prnt.ControlCount - 1 do
  begin
    if Prnt.Controls[j] is TCheckBox then
    begin
      HeaderCB:= TCheckBox(Prnt.Controls[j]);
      if TObject(HeaderCB.Tag) is TCatTag then
      begin
        RecomputeCatTriState(HeaderCB);
        { re-attach OnClick (RecomputeCatTriState clears it) }
        HeaderCB.OnClick:= CatHeaderClick;
        Break;
      end;
    end;
  end;
end;

{ ============================================================
  Helper: Load initial text for a non-int param editor from cfg
  ============================================================ }

function LoadParamInitText(const ACfg: TLintConfig; const AParam: TRuleParam): string;
begin
  { Naming int (min_identifier_len): handled by pkInt branch in RenderCatalog }
  if IsNamingStringParam(AParam.Name) then
    Result:= GetNamingString(ACfg, AParam.Name)
  else if SameText(AParam.Name, 'const_case') then
    Result:= JoinStrArr(ACfg.Naming.ConstCase)
  else if SameText(AParam.Name, 'hungarian_prefixes') then
    Result:= JoinStrArr(ACfg.Naming.HungarianPrefixes)
  else if SameText(AParam.Name, 'short_identifier_check') then
  begin
    if ACfg.Naming.ShortIdentifierCheck then Result:= 'true'
    else Result:= 'false';
  end
  else
    Result:= AParam.DefaultValue;
end;

{ ---- RenderCatalog: clear body, parse, build GroupBoxes + controls ---- }

procedure TLintOptionsFrame.RenderCatalog(const AJSON: string);
var
  Rules   : TCatalogRules;
  CatNames: TList<string>;
  GrpMap  : TDictionary<string, TGroupBox>;
  RuleMap : TDictionary<string, TCheckBox>; { id -> checkbox, for cat tristate }
  CatCBMap: TDictionary<string, TCheckBox>;
  CatTagMap: TDictionary<string, TCatTag> ;
  CatYMap : TDictionary<string, Integer>  ; { running Y per category }
  Rule    : TCatalogRule;
  Param   : TRuleParam  ;
  CatName : string      ;
  Grp     : TGroupBox   ;
  CatCB   : TCheckBox   ;
  RuleCB  : TCheckBox   ;
  RuleTag : TRuleTag    ;
  CatTag  : TCatTag     ;
  SpnEdt  : TSpinEdit   ;
  StrEdt  : TEdit       ;
  PrmLbl  : TLabel      ;
  GrpY    : Integer     ;
  GrpW    : Integer     ;
  Checked : Boolean     ;
  DefVal  : Integer     ;
  GrpLeft : Integer     ;
  PE      : TParamEditor;
const
  LM  = 8 ;   { left margin inside group }
  GM  = 6 ;   { gap between group boxes }
  GHH = 26;   { group box header height }
  CH  = 22;   { checkbox row height }
  EH  = 22;   { edit height }
  PH  = 18;   { param label height }
  PEH = 24;   { param editor height }
  PIH = 46;   { total height per int param row (label + editor) }
  PSH = 44;   { total height per string param row (label + editor) }
begin
  ClearBody;
  FCatalogJSON:= AJSON;

  Rules:= ParseCatalog(AJSON);
  if Length(Rules) = 0 then
  begin
    var ErrLbl: TLabel:= TLabel.Create(Self);
    ErrLbl.Parent  := FScroll;
    ErrLbl.Left    := 8;
    ErrLbl.Top     := 8;
    ErrLbl.Caption := 'No rules returned by drag-lint rules --json.';
    ErrLbl.AutoSize:= True;
    FLblCounts.Caption:= 'No rules loaded.';
    Exit;
  end;

  { Config is loaded into FCfg by ReloadCatalogAndConfig before RenderCatalog
    is called; use it directly here. }

  { Collect categories in order of first appearance }
  CatNames := TList<string>.Create;
  GrpMap   := TDictionary<string, TGroupBox>.Create;
  RuleMap  := TDictionary<string, TCheckBox>.Create;
  CatCBMap := TDictionary<string, TCheckBox>.Create;
  CatTagMap:= TDictionary<string, TCatTag>.Create;
  CatYMap  := TDictionary<string, Integer>.Create;
  try
    { Compute group box heights: one pass to count rows }
    var CatHeights: TDictionary<string, Integer>:= TDictionary<string, Integer>.Create;
    try
      for Rule in Rules do
      begin
        if not RuleMatchesSearch(Rule, FSearch) then Continue;
        CatName:= Rule.Category;
        if not CatHeights.ContainsKey(CatName) then
        begin
          CatHeights.AddOrSetValue(CatName, GHH + CH); { header checkbox }
          CatNames.Add(CatName);
        end;
        { one checkbox row }
        CatHeights[CatName]:= CatHeights[CatName] + CH;
        { param rows }
        for Param in Rule.Params do
        begin
          if Param.Kind = pkInt then
            CatHeights[CatName]:= CatHeights[CatName] + PIH
          else
            CatHeights[CatName]:= CatHeights[CatName] + PSH;
        end;
      end;

      { Create group boxes in order, stacked vertically }
      var GrpTop: Integer:= GM;
      for CatName in CatNames do
      begin
        Grp:= TGroupBox.Create(Self);
        Grp.Parent  := FScroll;
        GrpLeft     := GM;
        Grp.Left    := GrpLeft;
        Grp.Top     := GrpTop;
        Grp.Width   := FScroll.ClientWidth - GM * 2;
        if Grp.Width < 200 then Grp.Width:= 400;
        Grp.Height  := CatHeights[CatName] + 8;
        Grp.Caption := CatName;
        Grp.Anchors := [akLeft, akTop, akRight];
        Inc(GrpTop, Grp.Height + GM);
        GrpMap.AddOrSetValue(CatName, Grp);

        { Category header tri-state checkbox }
        CatTag:= TCatTag.CreateForCat(Self);
        CatTagMap.AddOrSetValue(CatName, CatTag);

        CatCB:= TCheckBox.Create(Self);
        CatCB.Parent     := Grp;
        CatCB.Left       := LM;
        CatCB.Top        := GHH;
        CatCB.Width      := Grp.Width - LM * 2;
        CatCB.Caption    := 'All';
        CatCB.AllowGrayed:= True;
        CatCB.State      := cbGrayed;
        CatCB.Tag        := NativeInt(CatTag);
        CatCB.OnClick    := CatHeaderClick;
        CatCBMap.AddOrSetValue(CatName, CatCB);

        CatYMap.AddOrSetValue(CatName, GHH + CH); { y for next rule row inside this grp }
      end;
    finally
      CatHeights.Free;
    end;

    { Second pass: create rule controls }
    for Rule in Rules do
    begin
      if not RuleMatchesSearch(Rule, FSearch) then Continue;
      CatName:= Rule.Category;
      Grp    := GrpMap[CatName];
      GrpW   := Grp.Width - LM * 2;
      GrpY   := CatYMap[CatName];

      { Enabled overlay: ShouldKeep(id, not default_enabled) }
      Checked:= FCfg.ShouldKeep(Rule.Id, not Rule.DefaultEnabled);

      RuleCB:= TCheckBox.Create(Self);
      RuleCB.Parent  := Grp;
      RuleCB.Left    := LM;
      RuleCB.Top     := GrpY;
      RuleCB.Width   := GrpW;
      RuleCB.Caption := Rule.Id + ' - ' + Rule.Title;
      RuleCB.Checked := Checked;
      RuleCB.Anchors := [akLeft, akTop, akRight];
      RuleCB.OnClick := RuleChecked;
      Inc(GrpY, CH);

      RuleTag:= TRuleTag.CreateForRule(Self, Rule);
      RuleCB.Tag:= NativeInt(RuleTag);

      { Param editors -- build one TParamEditor per param (ALL params) }
      for Param in Rule.Params do
      begin
        PrmLbl:= TLabel.Create(Self);
        PrmLbl.Parent  := Grp;
        PrmLbl.Left    := LM + 16;
        PrmLbl.Top     := GrpY;
        PrmLbl.Width   := GrpW - 16;
        PrmLbl.Caption := Param.Name + ':';
        PrmLbl.AutoSize:= True;
        Inc(GrpY, PH);

        PE.ParamName:= Param.Name;
        PE.Kind     := Param.Kind;

        if Param.Kind = pkInt then
        begin
          DefVal:= StrToIntDef(Param.DefaultValue, 0);

          { min_identifier_len -> Naming.MinIdentifierLen (NOT thresholds) }
          if IsNamingIntParam(Param.Name) then
            DefVal:= FCfg.Naming.MinIdentifierLen
          else
            DefVal:= FCfg.ThresholdFor(Rule.Id, DefVal); { key by rule id, not param name }

          SpnEdt:= TSpinEdit.Create(Self);
          SpnEdt.Parent  := Grp;
          SpnEdt.Left    := LM + 16;
          SpnEdt.Top     := GrpY;
          SpnEdt.Width   := 80;
          SpnEdt.Height  := EH;
          SpnEdt.MinValue:= 0;
          SpnEdt.MaxValue:= 9999;
          SpnEdt.Value   := DefVal;
          Inc(GrpY, PEH + 4);

          PE.Ctrl:= SpnEdt;
        end
        else
        begin
          { string / stringlist / bool params -> TEdit, loaded from correct location }
          StrEdt:= TEdit.Create(Self);
          StrEdt.Parent  := Grp;
          StrEdt.Left    := LM + 16;
          StrEdt.Top     := GrpY;
          StrEdt.Width   := GrpW - 16;
          StrEdt.Height  := EH;
          StrEdt.Text    := LoadParamInitText(FCfg, Param);
          StrEdt.Anchors := [akLeft, akTop, akRight];
          Inc(GrpY, PEH + 4);

          PE.Ctrl:= StrEdt;
        end;

        RuleTag.Editors:= RuleTag.Editors + [PE];
      end;

      CatYMap[CatName]:= GrpY;

      { Register this rule checkbox with the category tag }
      CatTagMap[CatName].RuleBoxes.Add(RuleCB);
      RuleMap.AddOrSetValue(Rule.Id, RuleCB);
    end;

    { Recompute all cat header states }
    for CatName in CatNames do
    begin
      CatCB:= CatCBMap[CatName];
      RecomputeCatTriState(CatCB);
      { re-attach click handler after state set (RecomputeCatTriState detaches) }
      CatCB.OnClick:= CatHeaderClick;
    end;

    FHasData:= True;
    UpdateCountsLabel;

  finally
    CatNames.Free;
    GrpMap.Free;
    RuleMap.Free;
    CatCBMap.Free;
    CatTagMap.Free;
    CatYMap.Free;
  end;
end;

procedure TLintOptionsFrame.UpdateCountsLabel;
var
  Rules       : TCatalogRules;
  Cats        : TList<string> ;
  Rule        : TCatalogRule  ;
  TotalRules  : Integer       ;
  EnabledCount: Integer       ;
  C           : TControl      ;
  CB          : TCheckBox     ;
  i           : Integer       ;
begin
  if not FHasData or (FCatalogJSON = '') then
  begin
    FLblCounts.Caption:= 'Not loaded';
    Exit;
  end;
  Rules:= ParseCatalog(FCatalogJSON);
  TotalRules:= Length(Rules);

  { Count categories }
  Cats:= TList<string>.Create;
  try
    for Rule in Rules do
      if not Cats.Contains(Rule.Category) then Cats.Add(Rule.Category);

    { Count enabled from rendered checkboxes }
    EnabledCount:= 0;
    for i:= 0 to FScroll.ControlCount - 1 do
    begin
      C:= FScroll.Controls[i];
      if C is TGroupBox then
      begin
        var GB: TGroupBox:= TGroupBox(C);
        var j: Integer;
        for j:= 0 to GB.ControlCount - 1 do
        begin
          if GB.Controls[j] is TCheckBox then
          begin
            CB:= TCheckBox(GB.Controls[j]);
            { Only rule checkboxes (not cat headers) carry a TRuleTag }
            if (CB.Tag <> 0) and (TObject(CB.Tag) is TRuleTag) then
              if CB.Checked then Inc(EnabledCount);
          end;
        end;
      end;
    end;

    FLblCounts.Caption:= Format(
      '%d rules across %d categories, %d enabled',
      [TotalRules, Cats.Count, EnabledCount]);
  finally
    Cats.Free;
  end;
end;

{ ============================================================
  Public: ReloadCatalogAndConfig
  ============================================================ }

procedure TLintOptionsFrame.ReloadCatalogAndConfig;
var
  ExePath, Cmd, JSON: string;
  ExitCode: Integer;
  CP: string;
begin
  ExePath := ResolveExe;
  Cmd     := '"' + ExePath + '" rules --json';
  ExitCode:= RunCaptureStdout(Cmd, JSON, 15000);
  if ExitCode <> 0 then
  begin
    { Show error label; don't crash }
    ClearBody;
    var ErrLbl: TLabel:= TLabel.Create(Self);
    ErrLbl.Parent  := FScroll;
    ErrLbl.Left    := 8;
    ErrLbl.Top     := 8;
    ErrLbl.WordWrap:= True;
    ErrLbl.Width   := FScroll.ClientWidth - 16;
    if ErrLbl.Width < 100 then ErrLbl.Width:= 300;
    ErrLbl.Caption := Format(
      'drag-lint rules --json failed (exit %d). Ensure the exe path is set in Settings.',
      [ExitCode]);
    ErrLbl.AutoSize:= False;
    FLblCounts.Caption:= 'Load failed.';
    Exit;
  end;
  { Load the active config (base or profile-merged) into the field so
    RenderCatalog can reference it directly. }
  CP    := CfgPath;
  FCfg  := TLintConfig.Load(CP, FProfile);
  RenderCatalog(JSON);
  ReloadProfileList;  { refresh combo after successful load }
end;

{ ============================================================
  Public: Save -- routes every catalog param to the location
  the linter actually reads (naming block or thresholds block).
  Iterates ALL params of ALL rules; no Break after first match.
  ============================================================ }

procedure TLintOptionsFrame.Save;
var
  CP   : string       ;
  Cfg  : TLintConfig  ;
  i, j : Integer      ;
  GB   : TGroupBox    ;
  CB   : TCheckBox    ;
  RT   : TRuleTag     ;
  Rule : TCatalogRule ;
  PE   : TParamEditor ;
  SpnEdt: TSpinEdit   ;
  StrEdt: TEdit       ;
begin
  if not FHasData then Exit;

  CP:= CfgPath;
  if CP = '' then Exit; { no active project -- silently skip }

  { Baseline from the currently-displayed config so a search filter or loaded
    profile does not overwrite unrendered rules with stale on-disk values.
    FCfg holds the base-or-profile-merged config set in ReloadCatalogAndConfig.
    Rendered rules will override their values below; unrendered rules keep FCfg. }
  Cfg:= FCfg;

  { Walk group boxes then their child checkboxes }
  for i:= 0 to FScroll.ControlCount - 1 do
  begin
    if not (FScroll.Controls[i] is TGroupBox) then Continue;
    GB:= TGroupBox(FScroll.Controls[i]);
    for j:= 0 to GB.ControlCount - 1 do
    begin
      if not (GB.Controls[j] is TCheckBox) then Continue;
      CB:= TCheckBox(GB.Controls[j]);
      { Skip category headers (they have TCatTag, not TRuleTag) }
      if (CB.Tag = 0) or not (TObject(CB.Tag) is TRuleTag) then Continue;
      RT  := TRuleTag(TObject(CB.Tag));
      Rule:= RT.Rule;

      { Toggle enabled/disabled via ConfigWriter }
      if Rule.DefaultEnabled then
        TLintConfigWriter.SetRuleDisabled(Cfg, Rule.Id, not CB.Checked)
      else
        TLintConfigWriter.SetRuleEnabled(Cfg, Rule.Id, CB.Checked);

      { Persist ALL param editors -- no Break; route each to the correct location }
      for PE in RT.Editors do
      begin
        if PE.Ctrl = nil then Continue;

        if PE.Kind = pkInt then
        begin
          SpnEdt:= TSpinEdit(PE.Ctrl);
          { min_identifier_len -> Naming.MinIdentifierLen (naming block, NOT thresholds) }
          if IsNamingIntParam(PE.ParamName) then
            Cfg.Naming.MinIdentifierLen:= SpnEdt.Value
          else
            TLintConfigWriter.SetThreshold(Cfg, Rule.Id, SpnEdt.Value); { key by rule id, not param name }
        end
        else
        begin
          StrEdt:= TEdit(PE.Ctrl);
          if IsNamingStringParam(PE.ParamName) then
            SetNamingString(Cfg, PE.ParamName, StrEdt.Text)
          else if SameText(PE.ParamName, 'const_case') then
            Cfg.Naming.ConstCase:= SplitCommaTrimmed(StrEdt.Text)
          else if SameText(PE.ParamName, 'hungarian_prefixes') then
            Cfg.Naming.HungarianPrefixes:= SplitCommaTrimmed(StrEdt.Text)
          else if SameText(PE.ParamName, 'short_identifier_check') then
            Cfg.Naming.ShortIdentifierCheck:= SameText(Trim(StrEdt.Text), 'true');
          { unrecognised params are silently skipped; Task 5 human gate validates }
        end;
      end;
    end;
  end;

  { Branch destination: base config or named profile }
  var Target: string:= Trim(FCboProfile.Text);
  if (Target = '') or SameText(Target, '(base)') then
    TLintConfigWriter.SaveToFile(CP, Cfg)
  else
  begin
    TLintConfigWriter.SaveToProfile(CP, Target, Cfg);
    FProfile:= Target;
    ReloadProfileList;                                  { include a newly-typed name }
    FCboProfile.ItemIndex:= FCboProfile.Items.IndexOf(Target);
  end;
  UpdateCountsLabel;
end;

{ ============================================================
  CfgPath: returns the active project's drag-lint-lint.json path,
  or '' when no project is open.
  ============================================================ }

function TLintOptionsFrame.CfgPath: string;
var
  ProjDir: string;
begin
  ProjDir:= GetActiveProjDir;
  if ProjDir = '' then
    Result:= ''
  else
    Result:= IncludeTrailingPathDelimiter(ProjDir) + 'drag-lint-lint.json';
end;

{ ============================================================
  ReloadProfileList: fills FCboProfile with '(base)' plus any
  named profiles found in the on-disk config file.
  ============================================================ }

procedure TLintOptionsFrame.ReloadProfileList;
var
  CP    : string;
  Names : TArray<string>;
  N     : string;
  Idx   : Integer;
begin
  CP:= CfgPath;
  FCboProfile.Items.BeginUpdate;
  try
    FCboProfile.Items.Clear;
    FCboProfile.Items.Add('(base)');
    if CP <> '' then
    begin
      Names:= TLintConfigWriter.ListProfileNames(CP);
      for N in Names do
        FCboProfile.Items.Add(N);
    end;
    { Restore selection to the active profile }
    if FProfile = '' then
      FCboProfile.ItemIndex:= 0
    else
    begin
      Idx:= FCboProfile.Items.IndexOf(FProfile);
      if Idx >= 0 then
        FCboProfile.ItemIndex:= Idx
      else
        FCboProfile.Text:= FProfile; { typed name not yet on disk }
    end;
  finally
    FCboProfile.Items.EndUpdate;
  end;
end;

{ ============================================================
  ProfileSelected: fires when the user picks or edits the combo.
  Updates FProfile and reloads catalog + config.
  ============================================================ }

procedure TLintOptionsFrame.ProfileSelected(Sender: TObject);
var
  Sel: string;
begin
  Sel:= Trim(FCboProfile.Text);
  if SameText(Sel, '(base)') or (Sel = '') then
    FProfile:= ''
  else
    FProfile:= Sel;
  ReloadCatalogAndConfig;
end;

{ ============================================================
  Button handlers
  ============================================================ }

procedure TLintOptionsFrame.BtnReloadClick(Sender: TObject);
begin
  ReloadCatalogAndConfig;
end;

procedure TLintOptionsFrame.BtnSaveClick(Sender: TObject);
begin
  Save;
end;

{ ============================================================
  CreateEmbeddedLintOptions -- dock-tab factory (Task 3 calls this)
  ============================================================ }

/// <summary>Creates TLintOptionsFrame owned by AOwner and parented into
/// AParent. Mirrors the CreateEmbeddedXxx pattern used by other dock tabs.</summary>
procedure CreateEmbeddedLintOptions(AOwner: TComponent; AParent: TWinControl);
var
  Frame: TLintOptionsFrame;
begin
  Frame:= TLintOptionsFrame.Create(AOwner);
  Frame.BorderStyle:= bsNone;      { embed child-style, no window frame }
  Frame.FormStyle  := fsNormal;
  Frame.Align      := alClient;
  Frame.Parent     := AParent;
  Frame.Visible    := True;        { CreateNew forms default to invisible }
  Frame.ReloadCatalogAndConfig;    { load the catalog on open (graceful on failure) }
end;

end.
