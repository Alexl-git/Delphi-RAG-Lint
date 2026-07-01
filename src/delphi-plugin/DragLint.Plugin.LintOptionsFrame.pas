unit DragLint.Plugin.LintOptionsFrame;

{ TLintOptionsFrame: dock tab for per-project lint rule enable/disable and
  param editing.  Loads the rule catalog via "drag-lint rules --json", renders
  each category as a TGroupBox with per-rule TCheckBoxes and inline param
  editors (TSpinEdit for int params, TEdit for string/stringlist), and
  round-trips the active project's drag-lint-lint.json via TLintConfigWriter.

  Design notes:
  - All controls are built dynamically in the constructor (no .dfm).
  - The ONLY ToolsAPI dependency is GetActiveProjDir (isolated function).
  - ReloadCatalogAndConfig and Save are the two public operations.
  - A tri-state category checkbox (cbChecked/cbUnchecked/cbGrayed) lets the
    user enable or disable an entire rule group with one click.
  - A "Save" button (rather than autosave) is the round-trip trigger; simpler
    and safer than per-control change handlers mutating the file on every
    keystroke. }

interface

uses
  System.Classes
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.ExtCtrls
  , Vcl.StdCtrls
  ;

type
  /// <summary>Dock tab frame that loads the drag-lint rule catalog and lets
  /// the user enable/disable rules and edit per-rule parameters, then saves
  /// the result back to the active project's drag-lint-lint.json.</summary>
  TLintOptionsFrame = class(TFrame)
  private
    { top bar }
    FPanelTop  : TPanel  ;
    FLblCounts : TLabel  ;
    FBtnReload : TButton ;
    FBtnSave   : TButton ;
    { scrollable body }
    FScroll    : TScrollBox;
    { internal catalog + config state }
    FCatalogJSON: string;   { last successful raw JSON from "rules --json" }
    FHasData   : Boolean;   { True after at least one successful load }
    procedure BuildControls;
    procedure BtnReloadClick(Sender: TObject);
    procedure BtnSaveClick  (Sender: TObject);
    procedure CatHeaderClick(Sender: TObject);
    procedure RuleChecked   (Sender: TObject);
    procedure ClearBody;
    procedure RenderCatalog(const AJSON: string);
    procedure UpdateCountsLabel;
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
  , System.JSON
  , System.Generics.Collections
  , Winapi.Windows
  , Vcl.ComCtrls
  , Vcl.Samples.Spin
  , ToolsAPI
  , DragLint.Plugin.ProcRun
  , DragLint.Plugin.Settings
  , DRagLint.Lint.Config
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
  Tag object: each rule checkbox carries one of these as Tag
  so the Save walk can recover (Rule, optional SpinEdit / Edit).
  We use a TComponent-descendant so VCL owns it.
  ============================================================ }

type
  TRuleTag = class(TComponent)
  public
    Rule        : TCatalogRule;
    { Optional param controls -- at most one int and one string per rule for
      the current catalog shape; add more as needed. }
    SpinEdit    : TSpinEdit;  { for the first "int" param, if any }
    StringEdit  : TEdit    ;  { for the first "string"/"stringlist" param }
    constructor CreateForRule(AOwner: TComponent; const ARule: TCatalogRule);
  end;

constructor TRuleTag.CreateForRule(AOwner: TComponent; const ARule: TCatalogRule);
begin
  inherited Create(AOwner);
  Rule:= ARule;
  SpinEdit  := nil;
  StringEdit:= nil;
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
begin
  Result:= LoadSettings.ExePath;
  if (Result = '') or not FileExists(Result) then
    Result:= ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.exe';
  if not FileExists(Result) then Result:= 'drag-lint.exe';
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
  Helper: collect enabled count across all rendered checkboxes
  Counts boxes that have a TRuleTag as Tag (skip cat headers)
  ============================================================ }

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
  TLintOptionsFrame
  ============================================================ }

constructor TLintOptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCatalogJSON:= '';
  FHasData    := False;
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

{ ---- RenderCatalog: clear body, parse, build GroupBoxes + controls ---- }

procedure TLintOptionsFrame.RenderCatalog(const AJSON: string);
var
  Rules   : TCatalogRules;
  Cfg     : TLintConfig  ;
  ProjPath: string       ;
  CfgPath : string       ;
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

  { Load project config }
  ProjPath:= GetActiveProjDir;
  if ProjPath <> '' then
    CfgPath:= IncludeTrailingPathDelimiter(ProjPath) + 'drag-lint-lint.json'
  else
    CfgPath:= '';
  Cfg:= TLintConfigWriter.LoadOrDefault(CfgPath);

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
        CatName:= Rule.Category;
        if not CatHeights.ContainsKey(CatName) then
        begin
          CatHeights[CatName]:= GHH + CH; { header checkbox }
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
        GrpMap[CatName]:= Grp;

        { Category header tri-state checkbox }
        CatTag:= TCatTag.CreateForCat(Self);
        CatTagMap[CatName]:= CatTag;

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
        CatCBMap[CatName]:= CatCB;

        CatYMap[CatName] := GHH + CH; { y for next rule row inside this grp }
      end;
    finally
      CatHeights.Free;
    end;

    { Second pass: create rule controls }
    for Rule in Rules do
    begin
      CatName:= Rule.Category;
      Grp    := GrpMap[CatName];
      GrpW   := Grp.Width - LM * 2;
      GrpY   := CatYMap[CatName];

      { Enabled overlay: ShouldKeep(id, not default_enabled) }
      Checked:= Cfg.ShouldKeep(Rule.Id, not Rule.DefaultEnabled);

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

      { Param editors }
      for Param in Rule.Params do
      begin
        if Param.Kind = pkInt then
        begin
          { Check if this is a known naming param mapped to cfg.Naming }
          { note: ThresholdFor reads from the thresholds block of config }
          DefVal:= StrToIntDef(Param.DefaultValue, 0);

          PrmLbl:= TLabel.Create(Self);
          PrmLbl.Parent  := Grp;
          PrmLbl.Left    := LM + 16;
          PrmLbl.Top     := GrpY;
          PrmLbl.Width   := GrpW - 16;
          PrmLbl.Caption := Param.Name + ':';
          PrmLbl.AutoSize:= True;
          Inc(GrpY, PH);

          SpnEdt:= TSpinEdit.Create(Self);
          SpnEdt.Parent  := Grp;
          SpnEdt.Left    := LM + 16;
          SpnEdt.Top     := GrpY;
          SpnEdt.Width   := 80;
          SpnEdt.Height  := EH;
          SpnEdt.MinValue:= 0;
          SpnEdt.MaxValue:= 9999;
          SpnEdt.Value   := Cfg.ThresholdFor(Param.Name, DefVal);
          Inc(GrpY, PEH + 4);

          { If RuleTag has no SpinEdit yet, assign it (one per rule) }
          if RuleTag.SpinEdit = nil then RuleTag.SpinEdit:= SpnEdt;
        end
        else
        begin
          { string / stringlist / bool params -> TEdit }
          { Naming-block params: map by name }
          var InitText: string:= Param.DefaultValue;

          { note: naming block params are identified by name; we map the
            common ones directly; unrecognised names fall back to default.
            Task 5 human gate validates runtime behaviour. }
          if SameText(Param.Name, 'param_prefix') then
            InitText:= Cfg.Naming.ParamPrefix
          else if SameText(Param.Name, 'field_prefix') then
            InitText:= Cfg.Naming.FieldPrefix
          else if SameText(Param.Name, 'method_case') then
            InitText:= Cfg.Naming.MethodCase
          else if SameText(Param.Name, 'local_case') then
            InitText:= Cfg.Naming.LocalCase
          else if SameText(Param.Name, 'keyword_case') then
            InitText:= Cfg.Naming.KeywordCase
          else if SameText(Param.Name, 'class_prefix') then
            InitText:= Cfg.Naming.ClassPrefix
          else if SameText(Param.Name, 'exception_prefix') then
            InitText:= Cfg.Naming.ExceptionPrefix
          else if SameText(Param.Name, 'interface_prefix') then
            InitText:= Cfg.Naming.InterfacePrefix
          else if SameText(Param.Name, 'pointer_prefix') then
            InitText:= Cfg.Naming.PointerPrefix;
          { note: const_case and hungarian_prefixes are TArray<string>; if
            needed later, join with comma here.  For now left as default. }

          PrmLbl:= TLabel.Create(Self);
          PrmLbl.Parent  := Grp;
          PrmLbl.Left    := LM + 16;
          PrmLbl.Top     := GrpY;
          PrmLbl.Width   := GrpW - 16;
          PrmLbl.Caption := Param.Name + ':';
          PrmLbl.AutoSize:= True;
          Inc(GrpY, PH);

          StrEdt:= TEdit.Create(Self);
          StrEdt.Parent  := Grp;
          StrEdt.Left    := LM + 16;
          StrEdt.Top     := GrpY;
          StrEdt.Width   := GrpW - 16;
          StrEdt.Height  := EH;
          StrEdt.Text    := InitText;
          StrEdt.Anchors := [akLeft, akTop, akRight];
          Inc(GrpY, PEH + 4);

          if RuleTag.StringEdit = nil then RuleTag.StringEdit:= StrEdt;
        end;
      end;

      CatYMap[CatName]:= GrpY;

      { Register this rule checkbox with the category tag }
      CatTagMap[CatName].RuleBoxes.Add(RuleCB);
      RuleMap[Rule.Id]:= RuleCB;
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
  RenderCatalog(JSON);
end;

{ ============================================================
  Public: Save
  ============================================================ }

procedure TLintOptionsFrame.Save;
var
  ProjPath: string       ;
  CfgPath : string       ;
  Cfg     : TLintConfig  ;
  i, j    : Integer      ;
  GB      : TGroupBox    ;
  CB      : TCheckBox    ;
  RT      : TRuleTag     ;
  Rule    : TCatalogRule ;
  Param   : TRuleParam   ;
  ParamIdx: Integer      ;
begin
  if not FHasData then Exit;

  ProjPath:= GetActiveProjDir;
  if ProjPath = '' then Exit; { no active project -- silently skip }

  CfgPath:= IncludeTrailingPathDelimiter(ProjPath) + 'drag-lint-lint.json';
  Cfg    := TLintConfigWriter.LoadOrDefault(CfgPath);

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

      { Persist int param (SpinEdit) via threshold }
      if RT.SpinEdit <> nil then
      begin
        { find the first int param name }
        for ParamIdx:= 0 to High(Rule.Params) do
          if Rule.Params[ParamIdx].Kind = pkInt then
          begin
            TLintConfigWriter.SetThreshold(Cfg, Rule.Params[ParamIdx].Name, RT.SpinEdit.Value);
            Break;
          end;
      end;

      { Persist string param (StringEdit) via naming block or threshold }
      if RT.StringEdit <> nil then
      begin
        for ParamIdx:= 0 to High(Rule.Params) do
        begin
          Param:= Rule.Params[ParamIdx];
          if Param.Kind in [pkString, pkStringList, pkBool] then
          begin
            { Map to naming block fields by param name }
            if SameText(Param.Name, 'param_prefix') then
              Cfg.Naming.ParamPrefix:= RT.StringEdit.Text
            else if SameText(Param.Name, 'field_prefix') then
              Cfg.Naming.FieldPrefix:= RT.StringEdit.Text
            else if SameText(Param.Name, 'method_case') then
              Cfg.Naming.MethodCase:= RT.StringEdit.Text
            else if SameText(Param.Name, 'local_case') then
              Cfg.Naming.LocalCase:= RT.StringEdit.Text
            else if SameText(Param.Name, 'keyword_case') then
              Cfg.Naming.KeywordCase:= RT.StringEdit.Text
            else if SameText(Param.Name, 'class_prefix') then
              Cfg.Naming.ClassPrefix:= RT.StringEdit.Text
            else if SameText(Param.Name, 'exception_prefix') then
              Cfg.Naming.ExceptionPrefix:= RT.StringEdit.Text
            else if SameText(Param.Name, 'interface_prefix') then
              Cfg.Naming.InterfacePrefix:= RT.StringEdit.Text
            else if SameText(Param.Name, 'pointer_prefix') then
              Cfg.Naming.PointerPrefix:= RT.StringEdit.Text;
            { note: unrecognised string params are left unmapped.
              Task 5 human gate validates runtime behaviour for any edge cases. }
            Break;
          end;
        end;
      end;
    end;
  end;

  TLintConfigWriter.SaveToFile(CfgPath, Cfg);
  UpdateCountsLabel;
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
  Frame.Parent:= AParent;
  Frame.Align := alClient;
end;

end.
