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

  Naming preset combo (Task 7): a "Naming preset" TComboBox sits at the top
  of the "naming" category group box (Embarcadero (A...) / House (p...) /
  Custom). Selecting Embarcadero or House bulk-sets the 8 prefix/casing
  editors (param_prefix, field_prefix, class_prefix, exception_prefix,
  interface_prefix, pointer_prefix, method_case, local_case) to that
  bundle's values; the normal Save walk then persists them -- no separate
  write path. Custom is a detection-only sentinel: selecting it is a no-op,
  and it is shown automatically whenever the live values match neither
  bundle (including right after any manual edit to one of the 8 fields).
  See ApplyPreset / DetectAndSetPreset / NamingFieldChanged / PresetSelected.
}

interface

uses
  System.Classes
  , System.Generics.Collections
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.ExtCtrls
  , Vcl.StdCtrls
  , DRagLint.Lint.Config
  ;

type
  /// <summary>One saved naming-convention preset: a user-chosen Name plus
  /// the 8 prefix/casing values, indexed in the same order as
  /// NAMING_PRESET_PARAMS (param_prefix, field_prefix, class_prefix,
  /// exception_prefix, interface_prefix, pointer_prefix, method_case,
  /// local_case).</summary>
  TNamingPreset = record
    Name  : string;
    Values: array[0..7] of string;
  end;
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
    { auto-fix checkboxes (rule-id -> box), one per FIXABLE rule. References
      only; the boxes are owned by Self / their parent GroupBox and freed by
      ClearBody. Persists past RenderCatalog so Save can read the toggles;
      rebuilt (cleared) at the start of each RenderCatalog. }
    FAutoFixCBs: TDictionary<string, TCheckBox>;
    { search filter (own row below the top panel) }
    FSearch       : string;      { current trimmed search text; '' = show all }
    FPanelSearch  : TPanel;      { second top row hosting the search field }
    FLblSearchIcon: TLabel;      { magnifier glyph (Segoe MDL2 Assets) }
    FLblSearch    : TLabel;      { the word "Search" }
    FEdtSearch    : TEdit;       { search box }
    { naming-convention preset combo (top of the "naming" category group).
      FNamingEditors maps naming param name -> its editor control (TEdit for
      every bundle-relevant param; all are string params) so ApplyPreset can
      bulk-set them and DetectAndSetPreset can read them back. Rebuilt (cleared)
      at the start of each RenderCatalog, same lifetime as FAutoFixCBs. }
    FLblPreset    : TLabel;
    FCboPreset    : TComboBox;
    FBtnSavePreset  : TButton;   { "Save as..." -- writes the current 8 values
                                    as a new/updated named preset (Task 7) }
    FBtnDeletePreset: TButton;   { "Delete" -- removes the selected SAVED
                                    preset; disabled for built-ins/Custom }
    FNamingEditors: TDictionary<string, TEdit>;
    FApplyingPreset: Boolean;    { guard: True while ApplyPreset is bulk-setting
                                    editors, so their OnChange handlers do not
                                    fight back with DetectAndSetPreset (avoids
                                    the apply/detect feedback loop) }
    FSavedPresets : TArray<TNamingPreset>; { cache of user-saved presets, backing
                                    the combo's saved-preset range [2..CustomIndex-1];
                                    refreshed by RebuildPresetCombo }
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
    { naming preset helpers }
    procedure PresetSelected    (Sender: TObject);
    procedure NamingFieldChanged(Sender: TObject);
    procedure ApplyPreset       (AKind: Integer);
    procedure DetectAndSetPreset;
    procedure RebuildPresetCombo;
    procedure UpdatePresetButtons;
    procedure SavePresetClick  (Sender: TObject);
    procedure DeletePresetClick(Sender: TObject);
    function  CustomIndex: Integer;
    function  IsSavedPresetSelected: Boolean;
    { helpers }
    function  CfgPath: string;
    procedure ReloadProfileList;
  public
    /// <summary>Creates the frame and builds all controls dynamically.
    /// No catalog is loaded yet; call ReloadCatalogAndConfig explicitly.</summary>
    constructor Create(AOwner: TComponent); override;
    /// <summary>Frees the auto-fix checkbox reference map (not the boxes,
    /// which are owned by the form / their parent group boxes).</summary>
    destructor Destroy; override;
    /// <summary>Runs "drag-lint rules --json", parses the catalog, loads the
    /// active project's drag-lint-lint.json, and re-renders all rule controls
    /// with the resulting enabled/disabled/param state.</summary>
    procedure ReloadCatalogAndConfig;
    /// <summary>Walks all rendered rule controls, mutates an in-memory
    /// TLintConfig via TLintConfigWriter setters, and saves the result to
    /// the active project's drag-lint-lint.json.</summary>
    procedure Save;
    /// <summary>Reads all saved naming presets from the top-level
    /// "naming.presets" array in CfgPath (the active project's
    /// drag-lint-lint.json). Returns an empty array when no project is
    /// open, the file does not exist, or the key is absent/malformed.</summary>
    /// <returns>One TNamingPreset per well-formed entry (a "name" string
    /// plus a "values" object keyed by the 8 NAMING_PRESET_PARAMS names;
    /// entries with an empty/missing name are skipped).</returns>
    function  ReadNamingPresets: TArray<TNamingPreset>;
    /// <summary>Read-modify-writes APreset into CfgPath's top-level
    /// "naming.presets" array, replacing any existing entry with the same
    /// Name (case-insensitive) or appending a new one. Preserves every
    /// other top-level key (rules, profiles, etc.) and every other key
    /// already under "naming". No-op when CfgPath is '' (no project
    /// open).</summary>
    /// <param name="APreset">The preset to save; Name must not be empty.</param>
    procedure WriteNamingPreset(const APreset: TNamingPreset);
    /// <summary>Read-modify-writes CfgPath's top-level "naming.presets"
    /// array, removing the entry whose Name matches AName
    /// (case-insensitive). Preserves every other top-level and "naming"
    /// key. No-op when CfgPath is '' (no project open) or the preset is
    /// not found.</summary>
    /// <param name="AName">Name of the preset to remove.</param>
    procedure DeleteNamingPreset(const AName: string);
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
  , System.IOUtils
  , Winapi.Windows
  , Vcl.ComCtrls
  , Vcl.Samples.Spin
  , Vcl.Dialogs
  , ToolsAPI
  , DragLint.Plugin.ProcRun
  , DragLint.Plugin.Settings
  , DRagLint.Lint.ConfigWriter
  , DragLint.Plugin.ExeResolver
  
  , DRagLint.Index.Manifest   { TManifestIO.WriteJsonAtomic -- pretty, no BOM, atomic }
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
    Fixable        : Boolean;  { True iff this rule has a registered auto-fix }
    Source         : string;
    Params         : TArray<TRuleParam>;
  end;

  TCatalogRules = TArray<TCatalogRule>;

{ ============================================================
  Naming-convention preset bundles (Task 7).

  Each preset is a fixed set of values for the 8 naming.* scalar-string
  params that carry prefixes/casing: param_prefix, field_prefix,
  class_prefix, exception_prefix, interface_prefix, pointer_prefix,
  method_case, local_case. Selecting a preset bulk-sets those 8 editor
  controls; the existing Save walk then persists them exactly as if the
  user had typed them by hand. "Custom" is never applied -- it is the
  sentinel shown when the live values match neither a built-in nor a
  saved preset.

  Verified against TNamingConfig.Default (DRagLint.Lint.Config.pas:109):
  ClassPrefix='T', ExceptionPrefix='E', InterfacePrefix='I',
  PointerPrefix='P', FieldPrefix='F', MethodCase='PascalCase',
  LocalCase='PascalCase'. Default.ParamPrefix is '' (prefix check off);
  both presets below set it explicitly (Embarcadero 'A', House 'p') per
  the brief, so neither preset equals Default verbatim -- that is
  intentional, not a bug: picking a preset always turns ON param-prefix.

  Combo layout (Task 7): 0=Embarcadero, 1=House, [2..CustomIndex-1]=user-
  saved presets (FSavedPresets, name-ordered as returned by
  ReadNamingPresets), CustomIndex (= FCboPreset.Items.Count - 1, always the
  LAST item) = Custom. The combo is rebuilt (RebuildPresetCombo) every time
  RenderCatalog runs, so Custom's numeric index moves as saved presets are
  added/removed -- callers must use CustomIndex, never a literal.
  ============================================================ }

const
  PRESET_EMBARCADERO = 0;
  PRESET_HOUSE        = 1;

  { Reserved built-in preset combo labels; also the collision-check names in
    SavePresetClick. Single source of truth so the label text never drifts
    between where the combo is populated and where new names are validated. }
  PRESET_LABEL_EMBARCADERO = 'Embarcadero (A...)';
  PRESET_LABEL_HOUSE       = 'House (p...)';
  PRESET_LABEL_CUSTOM      = 'Custom';

  { Parallel to the 8-field bundle: param_prefix, field_prefix,
    class_prefix, exception_prefix, interface_prefix, pointer_prefix,
    method_case, local_case. Index by PRESET_EMBARCADERO / PRESET_HOUSE. }
  NAMING_PRESET_BUNDLES: array[0..1] of array[0..7] of string = (
    ( 'A', 'F', 'T', 'E', 'I', 'P', 'PascalCase', 'PascalCase' ), { Embarcadero (A...) }
    ( 'p', 'F', 'T', 'E', 'I', 'P', 'PascalCase', 'PascalCase' )  { House (p...) }
  );

  { Param names in the same order as the bundle columns above; also the
    keys used in FNamingEditors. }
  NAMING_PRESET_PARAMS: array[0..7] of string = (
    'param_prefix', 'field_prefix', 'class_prefix', 'exception_prefix',
    'interface_prefix', 'pointer_prefix', 'method_case', 'local_case'
  );

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
begin
  Result:= DragLintExe;
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
  FixableV: TJSONValue  ;
  i       : Integer     ;
begin
  Result:= nil;
  Root:= TJSONObject.ParseJSONValue(AJSON);
  if Root = nil then Exit;
  try
    if not (Root is TJSONObject) then Exit;
    { The cast is LOAD-BEARING, not redundant, and an autofix removed it in
      41134be leaving the package unbuildable. Root is statically TJSONValue,
      whose GetValue is GENERIC (GetValue<T>) and cannot be called without a type
      argument; the non-generic GetValue(const Name: string): TJSONValue belongs
      to TJSONObject. The `is TJSONObject` guard above narrows the VALUE, not the
      static type, so the compiler still needs to be told. }
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
      Rule.Fixable        := False;
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
      { fixable: JSON bool (absent -> False) }
      FixableV:= RuleObj.GetValue('fixable');
      if (FixableV <> nil) and (FixableV is TJSONBool) then
        Rule.Fixable:= TJSONBool(FixableV).AsBoolean
      else if FixableV <> nil then
        Rule.Fixable:= SameText(FixableV.Value, 'true')
      else
        Rule.Fixable:= False;
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
  FAutoFixCBs := TDictionary<string, TCheckBox>.Create;
  FNamingEditors := TDictionary<string, TEdit>.Create;
  FApplyingPreset:= False;
  BuildControls;
end;

destructor TLintOptionsFrame.Destroy;
begin
  { Only holds references to VCL-owned checkboxes/edits; free the maps, not
    the controls themselves (owned by Self / their parent GroupBox). }
  FAutoFixCBs.Free;
  FNamingEditors.Free;
  inherited;
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

  FLblCounts:= TLabel.Create(Self);
  FLblCounts.Parent  := FPanelTop;
  FLblCounts.Left    := 8;
  FLblCounts.Top     := 10;
  FLblCounts.Caption := 'Not loaded';
  FLblCounts.AutoSize:= True;
  FLblCounts.Anchors := [akLeft, akTop, akRight];

  { --- Search row: its own line below the top button panel --- }
  FPanelSearch:= TPanel.Create(Self);
  FPanelSearch.Parent     := Self;
  FPanelSearch.Align      := alTop;
  FPanelSearch.Top        := PH;      { stack directly below FPanelTop }
  FPanelSearch.Height     := 30;
  FPanelSearch.BevelOuter := bvNone;

  { Magnifier glyph -- Segoe MDL2 Assets U+E721 (Search). Assigned via WideChar
    so the .pas source stays strict 7-bit ASCII (no literal Unicode glyph). }
  FLblSearchIcon:= TLabel.Create(Self);
  FLblSearchIcon.Parent    := FPanelSearch;
  FLblSearchIcon.Left      := 8;
  FLblSearchIcon.Top       := 7;
  FLblSearchIcon.AutoSize  := True;
  FLblSearchIcon.Font.Name := 'Segoe MDL2 Assets';
  FLblSearchIcon.Font.Size := 10;
  FLblSearchIcon.Caption   := WideChar($E721);

  FLblSearch:= TLabel.Create(Self);
  FLblSearch.Parent  := FPanelSearch;
  FLblSearch.Left    := FLblSearchIcon.Left + 22;
  FLblSearch.Top     := 7;
  FLblSearch.AutoSize:= True;
  FLblSearch.Caption := 'Search';

  FEdtSearch:= TEdit.Create(Self);
  FEdtSearch.Parent   := FPanelSearch;
  FEdtSearch.Left     := FLblSearch.Left + 50;
  FEdtSearch.Top      := 3;
  FEdtSearch.Height   := 24;
  FEdtSearch.Width    := FPanelSearch.Width - FEdtSearch.Left - 8;
  FEdtSearch.Anchors  := [akLeft, akTop, akRight];
  FEdtSearch.TextHint := 'Search rules...';
  FEdtSearch.OnChange := SearchChanged;

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
  AutoFixCB: TCheckBox  ;
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
  AFW = 84;   { width reserved on the right for the 'auto-fix' checkbox }
  EH  = 22;   { edit height }
  PH  = 18;   { param label height }
  PEH = 24;   { param editor height }
  PIH = 46;   { total height per int param row (label + editor) }
  PSH = 44;   { total height per string param row (label + editor) }
  PBW = 84;   { preset Save-as/Delete button width (Task 7) }
  PBG = 6 ;   { gap before each preset button }
begin
  ClearBody;
  FCatalogJSON:= AJSON;

  { ClearBody freed the old checkboxes; drop the now-dangling references.
    The dictionary persists (form field) so Save can read the rebuilt set. }
  if FAutoFixCBs = nil then
    FAutoFixCBs:= TDictionary<string, TCheckBox>.Create
  else
    FAutoFixCBs.Clear;

  { Same lifetime as FAutoFixCBs: ClearBody freed the old naming editors too. }
  if FNamingEditors = nil then
    FNamingEditors:= TDictionary<string, TEdit>.Create
  else
    FNamingEditors.Clear;
  FLblPreset      := nil;
  FCboPreset      := nil;
  FBtnSavePreset  := nil;
  FBtnDeletePreset:= nil;

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

      { Reserve one extra row in the "naming" category for the preset combo
        (Task 7), placed above its rule rows. }
      if CatHeights.ContainsKey('naming') then
        CatHeights['naming']:= CatHeights['naming'] + CH;

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

        var NextY: Integer:= GHH + CH; { y for next rule row inside this grp }

        { Naming preset combo (Task 7): top of the "naming" group, above its
          rule rows. Bulk-applies a bundle to the 8 naming.* editors below;
          detection/selection is finished after the second pass builds them. }
        if SameText(CatName, 'naming') then
        begin
          FLblPreset:= TLabel.Create(Self);
          FLblPreset.Parent  := Grp;
          FLblPreset.Left    := LM;
          FLblPreset.Top     := NextY + 4;
          FLblPreset.AutoSize:= True;
          FLblPreset.Caption := 'Naming preset:';

          FCboPreset:= TComboBox.Create(Self);
          FCboPreset.Parent    := Grp;
          FCboPreset.Style     := csDropDownList;
          FCboPreset.Left      := LM + 96;
          FCboPreset.Top       := NextY;
          { Width leaves room for the two buttons anchored to the right edge
            (PBW each, PBG gap before each -- see below). }
          FCboPreset.Width     := Grp.Width - LM * 2 - 96 - 2 * (PBW + PBG);
          FCboPreset.Height    := EH;
          FCboPreset.Anchors   := [akLeft, akTop, akRight];
          FCboPreset.OnSelect  := PresetSelected;

          { "Save as..." / "Delete" (Task 7), right of the combo, anchored to
            the group box's right edge so they track FCboPreset.Width as the
            frame resizes (FCboPreset itself is anchored akLeft+akRight, so
            its right edge tracks the same resize). }
          FBtnSavePreset:= TButton.Create(Self);
          FBtnSavePreset.Parent  := Grp;
          FBtnSavePreset.Caption := 'Save as...';
          FBtnSavePreset.Top     := NextY;
          FBtnSavePreset.Width   := PBW;
          FBtnSavePreset.Height  := EH;
          FBtnSavePreset.Left    := Grp.Width - LM - 2 * PBW - PBG;
          FBtnSavePreset.Anchors := [akTop, akRight];
          FBtnSavePreset.OnClick := SavePresetClick;

          FBtnDeletePreset:= TButton.Create(Self);
          FBtnDeletePreset.Parent  := Grp;
          FBtnDeletePreset.Caption := 'Delete';
          FBtnDeletePreset.Top     := NextY;
          FBtnDeletePreset.Width   := PBW;
          FBtnDeletePreset.Height  := EH;
          FBtnDeletePreset.Left    := Grp.Width - LM - PBW;
          FBtnDeletePreset.Anchors := [akTop, akRight];
          FBtnDeletePreset.OnClick := DeletePresetClick;

          { Populate combo (built-ins + saved + Custom) now that FCboPreset
            exists; then Custom's numeric index is known for button state. }
          RebuildPresetCombo;
          UpdatePresetButtons;
          Inc(NextY, CH);
        end;

        CatYMap.AddOrSetValue(CatName, NextY);
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

      { For a FIXABLE rule, add a second 'auto-fix' checkbox on the SAME row,
        right-aligned. Narrow the enable box to leave room. The auto-fix box
        carries NO TRuleTag (Tag stays 0) so the Save enable-walk and
        UpdateCountsLabel -- which both filter on (Tag<>0) and (Tag is TRuleTag)
        -- never treat it as an enable box. It is tracked in FAutoFixCBs (by
        rule-id) so Save can read its toggle. Do NOT Inc(GrpY) again -- the
        enable box already advanced the row. }
      if Rule.Fixable then
      begin
        RuleCB.Width:= GrpW - AFW;

        AutoFixCB:= TCheckBox.Create(Self);
        AutoFixCB.Parent  := Grp;
        AutoFixCB.Top     := RuleCB.Top;
        AutoFixCB.Left    := LM + (GrpW - AFW);
        AutoFixCB.Width   := AFW;
        AutoFixCB.Caption := 'auto-fix';
        AutoFixCB.Checked := FCfg.IsAutoFix(Rule.Id);
        AutoFixCB.Anchors := [akTop, akRight];
        FAutoFixCBs.AddOrSetValue(Rule.Id, AutoFixCB);
      end;

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

          { One of the 8 preset-bundle params (Task 7): register for
            ApplyPreset/DetectAndSetPreset and wire the "manual edit flips
            the combo to Custom" handler. }
          if MatchStr(Param.Name, NAMING_PRESET_PARAMS) then
          begin
            FNamingEditors.AddOrSetValue(Param.Name, StrEdt);
            StrEdt.OnChange:= NamingFieldChanged;
          end;

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

    { Initial preset detection -- runs after all 8 naming editors exist
      (search filtering may hide the naming category entirely, in which
      case FCboPreset is nil and DetectAndSetPreset is a no-op). }
    DetectAndSetPreset;
    UpdatePresetButtons;

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

  { Collect auto-fix state from the per-rule 'auto-fix' checkboxes. SetAutoFix
    REPLACES the whole array, so toggling a box OFF removes its id (AddAutoFix
    is append-only and would not remove -- do NOT use it here). Only fixable
    rules ever get a box, so only fixable ids can appear. }
  var AFIds: TArray<string>:= nil;
  if FAutoFixCBs <> nil then
    for var Pair in FAutoFixCBs do
      if Pair.Value.Checked then
        AFIds:= AFIds + [Pair.Key];
  Cfg.SetAutoFix(AFIds);

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
  Naming-convention preset persistence (Task 6).

  Presets live under a new top-level "naming" object in CfgPath
  (drag-lint-lint.json), as a sibling of "rules"/"profiles". Shape (JSON,
  not Pascal comment braces -- see the round-trip test for a literal
  example): top-level "naming" object holding a "presets" array; each
  entry has a "name" string and a "values" object keyed by the 8
  NAMING_PRESET_PARAMS names (param_prefix, field_prefix, class_prefix,
  exception_prefix, interface_prefix, pointer_prefix, method_case,
  local_case).

  Every RMW below re-parses the WHOLE file into a TJSONObject, mutates only
  the "naming" sub-object in place (or creates it), and re-serializes the
  full Root -- so "rules", "profiles", and any other top-level key survive
  untouched. This mirrors WriteMaxReturnCases's RMW shape in
  DragLint.Plugin.OptionsFrames.pas (reuse-or-create nested object,
  RemovePair before re-adding, TFile.WriteAllText(..., TEncoding.UTF8)).
  ============================================================ }

function TLintOptionsFrame.ReadNamingPresets: TArray<TNamingPreset>;
var
  Path  : string;
  Parsed: TJSONValue;
  Root  : TJSONObject;
  NamingVal, ObjVal, ValsVal: TJSONValue;
  Naming: TJSONObject;
  Arr   : TJSONArray;
  i, k  : Integer;
  Obj, Vals: TJSONObject;
  P     : TNamingPreset;
  Res   : TList<TNamingPreset>;
  NameVal: TJSONValue;
begin
  SetLength(Result, 0);
  Path:= CfgPath;
  if (Path = '') or not TFile.Exists(Path) then Exit;

  Parsed:= nil;
  try
    Parsed:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Path));
  except
    Exit; { malformed config: no presets rather than raising in Options UI }
  end; // try
  if not (Parsed is TJSONObject) then
  begin
    Parsed.Free;
    Exit;
  end;
  Root:= TJSONObject(Parsed);

  Res:= TList<TNamingPreset>.Create;
  try
    NamingVal:= Root.GetValue('naming');
    if NamingVal is TJSONObject then
    begin
      Naming:= TJSONObject(NamingVal);
      ObjVal:= Naming.GetValue('presets');
      if ObjVal is TJSONArray then
      begin
        Arr:= TJSONArray(ObjVal);
        for i:= 0 to Arr.Count - 1 do
          if Arr.Items[i] is TJSONObject then
          begin
            Obj:= TJSONObject(Arr.Items[i]);
            NameVal:= Obj.GetValue('name');
            if NameVal is TJSONString then
              P.Name:= NameVal.Value
            else
              P.Name:= '';
            for k:= 0 to 7 do P.Values[k]:= '';
            ValsVal:= Obj.GetValue('values');
            if ValsVal is TJSONObject then
            begin
              Vals:= TJSONObject(ValsVal);
              for k:= 0 to 7 do
              begin
                NameVal:= Vals.GetValue(NAMING_PRESET_PARAMS[k]);
                if NameVal is TJSONString then
                  P.Values[k]:= NameVal.Value;
              end;
            end;
            if P.Name <> '' then Res.Add(P);
          end;
      end;
    end;
    Result:= Res.ToArray;
  finally
    Res.Free;
    Root.Free;
  end; // try
end;

procedure TLintOptionsFrame.WriteNamingPreset(const APreset: TNamingPreset);
var
  Path      : string;
  Parsed    : TJSONValue;
  Root      : TJSONObject;
  NamingVal : TJSONValue;
  Naming    : TJSONObject;
  PresetsVal: TJSONValue;
  Arr, NewArr: TJSONArray;
  i, k      : Integer;
  ExistingObj, NewObj, ValsObj: TJSONObject;
  Nm        : string;
  NameVal   : TJSONValue;
  OldPair   : TJSONPair;
begin
  if APreset.Name = '' then Exit;
  Path:= CfgPath;
  if Path = '' then Exit;

  Root:= nil;
  try
    if TFile.Exists(Path) then
    begin
      Parsed:= nil;
      try
        Parsed:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Path));
      except
        Parsed:= nil; { malformed config text: fall through to a fresh object }
      end; // try
      if Parsed is TJSONObject then
        Root:= TJSONObject(Parsed)
      else
        Parsed.Free; { either nil (no-op) or a non-object JSON value we cannot use }
    end; // if
    if Root = nil then Root:= TJSONObject.Create; { no file yet, or unparsable: start fresh }

    { Reuse or create the top-level "naming" object so every OTHER top-level
      key (rules, profiles, ...) survives untouched. }
    NamingVal:= Root.GetValue('naming');
    if NamingVal is TJSONObject then
      Naming:= TJSONObject(NamingVal)
    else
    begin
      Naming:= TJSONObject.Create;
      Root.AddPair('naming', Naming);
    end; // if

    { Rebuild "presets" minus any same-named entry (SameText), then append
      the new/updated one. }
    NewArr:= TJSONArray.Create;
    PresetsVal:= Naming.GetValue('presets');
    if PresetsVal is TJSONArray then
    begin
      Arr:= TJSONArray(PresetsVal);
      for i:= 0 to Arr.Count - 1 do
        if Arr.Items[i] is TJSONObject then
        begin
          ExistingObj:= TJSONObject(Arr.Items[i]);
          NameVal:= ExistingObj.GetValue('name');
          if NameVal is TJSONString then Nm:= NameVal.Value else Nm:= '';
          if not SameText(Nm, APreset.Name) then
            NewArr.AddElement(ExistingObj.Clone as TJSONObject);
        end;
    end;

    ValsObj:= TJSONObject.Create;
    for k:= 0 to 7 do ValsObj.AddPair(NAMING_PRESET_PARAMS[k], APreset.Values[k]);
    NewObj:= TJSONObject.Create;
    NewObj.AddPair('name', APreset.Name);
    NewObj.AddPair('values', ValsObj);
    NewArr.AddElement(NewObj);

    { TJSONObject has no in-place "set" -- remove any existing pair first so
      a repeated save never leaves two "presets" pairs behind. }
    OldPair:= Naming.RemovePair('presets');
    OldPair.Free; { RemovePair returns nil if absent; TObject(nil).Free is a no-op }
    Naming.AddPair('presets', NewArr);

    { Pretty + no BOM + atomic swap, via the one implementation that gets it
      right -- see TManifestIO.WriteJsonAtomic. }
    TManifestIO.WriteJsonAtomic(Path, Root);
  finally
    Root.Free;
  end; // try
end;

procedure TLintOptionsFrame.DeleteNamingPreset(const AName: string);
var
  Path      : string;
  Parsed    : TJSONValue;
  Root      : TJSONObject;
  NamingVal : TJSONValue;
  Naming    : TJSONObject;
  PresetsVal: TJSONValue;
  Arr, NewArr: TJSONArray;
  i         : Integer;
  ExistingObj: TJSONObject;
  Nm        : string;
  NameVal   : TJSONValue;
  OldPair   : TJSONPair;
begin
  if AName = '' then Exit;
  Path:= CfgPath;
  if Path = '' then Exit;
  if not TFile.Exists(Path) then Exit; { nothing saved yet: nothing to delete }

  Root:= nil;
  try
    Parsed:= nil;
    try
      Parsed:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Path));
    except
      Exit; { malformed config: nothing safe to rewrite }
    end; // try
    if not (Parsed is TJSONObject) then
    begin
      Parsed.Free;
      Exit;
    end;
    Root:= TJSONObject(Parsed);

    NamingVal:= Root.GetValue('naming');
    if not (NamingVal is TJSONObject) then Exit; { no "naming" object: nothing to delete }
    Naming:= TJSONObject(NamingVal);

    PresetsVal:= Naming.GetValue('presets');
    if not (PresetsVal is TJSONArray) then Exit; { no presets array: nothing to delete }
    Arr:= TJSONArray(PresetsVal);

    { Rebuild "presets" minus the named entry; do NOT append. }
    NewArr:= TJSONArray.Create;
    for i:= 0 to Arr.Count - 1 do
      if Arr.Items[i] is TJSONObject then
      begin
        ExistingObj:= TJSONObject(Arr.Items[i]);
        NameVal:= ExistingObj.GetValue('name');
        if NameVal is TJSONString then Nm:= NameVal.Value else Nm:= '';
        if not SameText(Nm, AName) then
          NewArr.AddElement(ExistingObj.Clone as TJSONObject);
      end;

    OldPair:= Naming.RemovePair('presets');
    OldPair.Free; { RemovePair returns nil if absent; TObject(nil).Free is a no-op }
    Naming.AddPair('presets', NewArr);

    { Pretty + no BOM + atomic swap, via the one implementation that gets it
      right -- see TManifestIO.WriteJsonAtomic. }
    TManifestIO.WriteJsonAtomic(Path, Root);
  finally
    Root.Free;
  end; // try
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
  { Fast path: the rule catalog is static and does not change between profiles --
    only the config overlay does. When the catalog JSON is already cached, just
    reload the config and re-render from that cache; skip the (slow) re-spawn of
    "drag-lint rules --json". The Reload button still forces the full CLI path. }
  if FHasData and (FCatalogJSON <> '') then
  begin
    FCfg:= TLintConfig.Load(CfgPath, FProfile);
    RenderCatalog(FCatalogJSON);
  end
  else
    ReloadCatalogAndConfig;
end;

{ ============================================================
  Naming-convention preset combo (Task 7)
  ============================================================ }

/// <summary>Index of the 'Custom' sentinel item, always the LAST combo item.
/// Custom's numeric index is NOT fixed -- it shifts as saved presets are
/// added/removed by RebuildPresetCombo -- so every comparison against
/// "is this Custom?" must call this function rather than use a literal.
/// Returns -1 if FCboPreset is nil (naming group not rendered, e.g. filtered
/// out by search) or has no items yet.</summary>
function TLintOptionsFrame.CustomIndex: Integer;
begin
  if FCboPreset = nil then
    Result:= -1
  else
    Result:= FCboPreset.Items.Count - 1;
end;

/// <summary>True when the combo's current selection is a SAVED preset --
/// i.e. neither a built-in (Embarcadero/House, index &lt;= PRESET_HOUSE) nor
/// the Custom sentinel. Shared predicate for UpdatePresetButtons (enables
/// FBtnDeletePreset) and DeletePresetClick (guards the delete action), so
/// the two stay in sync by construction. False if FCboPreset is nil or
/// nothing is selected.</summary>
function TLintOptionsFrame.IsSavedPresetSelected: Boolean;
begin
  if FCboPreset = nil then Exit(False);
  Result:= (FCboPreset.ItemIndex > PRESET_HOUSE) and (FCboPreset.ItemIndex <> CustomIndex);
end;

/// <summary>Clears and repopulates FCboPreset: built-in bundles first
/// (Embarcadero, House), then every user-saved preset (name order as
/// returned by ReadNamingPresets, cached into FSavedPresets), then 'Custom'
/// last. Combo index 2+i maps to FSavedPresets[i]. Called once at combo
/// creation (RenderCatalog) and again after every Save/Delete so the list
/// stays in sync with disk. No-op if FCboPreset is nil.</summary>
procedure TLintOptionsFrame.RebuildPresetCombo;
var
  i: Integer;
begin
  if FCboPreset = nil then Exit;

  FSavedPresets:= ReadNamingPresets;
  FCboPreset.Items.BeginUpdate;
  try
    FCboPreset.Items.Clear;
    FCboPreset.Items.Add(PRESET_LABEL_EMBARCADERO); { PRESET_EMBARCADERO = 0 }
    FCboPreset.Items.Add(PRESET_LABEL_HOUSE);       { PRESET_HOUSE = 1 }
    for i:= 0 to High(FSavedPresets) do
      FCboPreset.Items.Add(FSavedPresets[i].Name); { saved presets start at 2 }
    FCboPreset.Items.Add(PRESET_LABEL_CUSTOM);      { always LAST -- see CustomIndex }
  finally
    FCboPreset.Items.EndUpdate;
  end;
end;

/// <summary>Enables FBtnDeletePreset only when the combo's current selection
/// is a SAVED preset (built-ins Embarcadero/House and the Custom sentinel
/// are not deletable). No-op if the buttons/combo were not rendered (naming
/// group filtered out by search).</summary>
procedure TLintOptionsFrame.UpdatePresetButtons;
begin
  if (FBtnDeletePreset = nil) or (FCboPreset = nil) then Exit;
  FBtnDeletePreset.Enabled:= IsSavedPresetSelected;
end;

/// <summary>Bulk-sets the 8 naming.* editor controls in FNamingEditors to
/// the values for AKind: a built-in bundle (PRESET_EMBARCADERO/PRESET_HOUSE)
/// or a saved preset (any combo index from 2 up to, but excluding,
/// CustomIndex -- mapped to FSavedPresets[AKind - 2]). The existing Save
/// button walk persists the new values exactly as if the user had typed
/// them by hand -- no extra "dirty" flag is needed. Sets FApplyingPreset
/// around the writes so the editors' own OnChange handler (NamingFieldChanged)
/// does not immediately flip the combo back to Custom. CustomIndex is
/// intentionally not handled here (Custom is never applied; callers must
/// not invoke ApplyPreset for it).</summary>
procedure TLintOptionsFrame.ApplyPreset(AKind: Integer);
var
  i , si: Integer;
  Ed    : TEdit;
  Vals  : array[0..7] of string;
begin
  if AKind = CustomIndex then Exit; { Custom: detection-only sentinel }
  if FNamingEditors = nil then Exit;

  if AKind <= PRESET_HOUSE then
  begin
    if AKind < PRESET_EMBARCADERO then Exit;
    for i:= 0 to High(NAMING_PRESET_PARAMS) do
      Vals[i]:= NAMING_PRESET_BUNDLES[AKind][i];
  end
  else
  begin
    si:= AKind - 2; { saved-preset index, parallel to the combo's [2..CustomIndex-1] range }
    if si > High(FSavedPresets) then Exit; { si >= 0 guaranteed: AKind > PRESET_HOUSE here }
    for i:= 0 to High(NAMING_PRESET_PARAMS) do
      Vals[i]:= FSavedPresets[si].Values[i];
  end;

  FApplyingPreset:= True;
  try
    for i:= 0 to High(NAMING_PRESET_PARAMS) do
      if FNamingEditors.TryGetValue(NAMING_PRESET_PARAMS[i], Ed) then
        Ed.Text:= Vals[i];
  finally
    FApplyingPreset:= False;
  end;
end;

/// <summary>Reads the 8 naming.* editor controls back and selects the combo
/// item whose values match exactly -- a built-in bundle first, then every
/// saved preset in FSavedPresets order -- or 'Custom' when none match. A
/// missing editor (e.g. hidden by the search filter) counts as a mismatch,
/// so a partially-rendered naming section safely falls back to Custom
/// rather than mis-detecting a preset. No-op when the naming group was not
/// rendered (FCboPreset = nil, e.g. filtered out entirely by search).</summary>
procedure TLintOptionsFrame.DetectAndSetPreset;
var
  Kind   : Integer;
  si     : Integer;
  i      : Integer;
  Ed     : TEdit;
  Matches: Boolean;
  Found  : Boolean;
begin
  if FCboPreset = nil then Exit;
  if FNamingEditors = nil then Exit;

  Found:= False;
  for Kind:= PRESET_EMBARCADERO to PRESET_HOUSE do
  begin
    Matches:= True;
    for i:= 0 to High(NAMING_PRESET_PARAMS) do
    begin
      if not FNamingEditors.TryGetValue(NAMING_PRESET_PARAMS[i], Ed) then
      begin
        Matches:= False;
        Break;
      end;
      if Ed.Text <> NAMING_PRESET_BUNDLES[Kind][i] then
      begin
        Matches:= False;
        Break;
      end;
    end;
    if Matches then
    begin
      FCboPreset.ItemIndex:= Kind;
      Found:= True;
      Break;
    end;
  end;

  if not Found then
    for si:= 0 to High(FSavedPresets) do
    begin
      Matches:= True;
      for i:= 0 to High(NAMING_PRESET_PARAMS) do
      begin
        if not FNamingEditors.TryGetValue(NAMING_PRESET_PARAMS[i], Ed) then
        begin
          Matches:= False;
          Break;
        end;
        if Ed.Text <> FSavedPresets[si].Values[i] then
        begin
          Matches:= False;
          Break;
        end;
      end;
      if Matches then
      begin
        FCboPreset.ItemIndex:= 2 + si;
        Found:= True;
        Break;
      end;
    end;

  if not Found then
    FCboPreset.ItemIndex:= CustomIndex;
end;

/// <summary>OnSelect handler for the naming preset combo. Applies the chosen
/// bundle or saved preset; picking Custom leaves the current values
/// untouched, matching the brief's "selecting it does nothing" contract.
/// Also refreshes the Delete button's enabled state for the new selection.</summary>
procedure TLintOptionsFrame.PresetSelected(Sender: TObject);
begin
  if FCboPreset = nil then Exit;
  if FCboPreset.ItemIndex <> CustomIndex then
    ApplyPreset(FCboPreset.ItemIndex); { Custom: no-op by design }
  UpdatePresetButtons;
end;

/// <summary>OnChange handler wired to every naming.* editor. A manual edit
/// flips the combo to Custom (or re-detects a saved-preset match) without
/// reapplying a bundle. Guarded by FApplyingPreset so ApplyPreset's own
/// bulk-set does not immediately re-detect and fight itself -- ApplyPreset
/// already set the exact values for its bundle, so re-running detection
/// there would be redundant, not wrong, but the guard keeps the two code
/// paths cleanly separated and avoids the two firing recursively into each
/// other.</summary>
procedure TLintOptionsFrame.NamingFieldChanged(Sender: TObject);
begin
  if FApplyingPreset then Exit;
  DetectAndSetPreset;
  UpdatePresetButtons;
end;

/// <summary>OnClick handler for "Save as...". Prompts for a name, rejects an
/// empty name or one colliding with a built-in/Custom label, then writes the
/// current 8 editor values as a named preset (WriteNamingPreset), refreshes
/// the combo (RebuildPresetCombo, which also re-reads FSavedPresets from
/// disk), and selects the newly-saved entry.</summary>
procedure TLintOptionsFrame.SavePresetClick(Sender: TObject);
var
  Nm: string;
  P : TNamingPreset;
  k : Integer;
  Ed: TEdit;
begin
  if FCboPreset = nil then Exit;
  if FNamingEditors = nil then Exit;

  Nm:= '';
  if not InputQuery('Save naming preset', 'Preset name:', Nm) then Exit;
  Nm:= Trim(Nm);
  if Nm = '' then Exit;

  if SameText(Nm, PRESET_LABEL_CUSTOM) or SameText(Nm, PRESET_LABEL_EMBARCADERO)
    or SameText(Nm, PRESET_LABEL_HOUSE) then
  begin
    ShowMessage('That name is reserved for a built-in preset.');
    Exit;
  end;

  P.Name:= Nm;
  for k:= 0 to 7 do
  begin
    if FNamingEditors.TryGetValue(NAMING_PRESET_PARAMS[k], Ed) then
      P.Values[k]:= Ed.Text
    else
      P.Values[k]:= '';
  end;
  WriteNamingPreset(P);

  RebuildPresetCombo;
  FCboPreset.ItemIndex:= FCboPreset.Items.IndexOf(Nm);
  UpdatePresetButtons;
end;

/// <summary>OnClick handler for "Delete". A no-op unless the combo's current
/// selection is a saved preset (built-ins and Custom are excluded, mirroring
/// FBtnDeletePreset.Enabled). Confirms via MessageDlg, then deletes
/// (DeleteNamingPreset), refreshes the combo, and falls back to Custom since
/// the just-deleted selection no longer exists.</summary>
procedure TLintOptionsFrame.DeletePresetClick(Sender: TObject);
var
  Nm: string;
begin
  if FCboPreset = nil then Exit;
  if FCboPreset.ItemIndex < 0 then Exit;
  if not IsSavedPresetSelected then Exit; { built-ins + Custom are not deletable }

  Nm:= FCboPreset.Items[FCboPreset.ItemIndex];
  if MessageDlg(Format('Delete saved preset "%s"?', [Nm]), mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;

  DeleteNamingPreset(Nm);
  RebuildPresetCombo;
  FCboPreset.ItemIndex:= CustomIndex;
  UpdatePresetButtons;
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
