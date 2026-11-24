unit DRagLint.V154.DFM;

{ Wave v154 (1.54.0-alpha) lane DFM -- dfm-duplicate-tab-order, dfm-conflicting-accelerator,
  dfm-conflicting-shortcut, dfm-action-and-onclick, db-component-on-form, dfm-default-component-name,
  dfm-hint-inactive (G-12 G-21 G-34 G-37) and the shipped default policy of disallowed-dfm-property (G-20).
  All seven rules read the text form file through the object tree of DRagLint.V151.DFMB.Support; three of
  them also read the unit's source text. A binary form file keeps every rule silent.
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v154 lanes reuse the
  DRagLint.V151.Api types). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule ids of this lane, as `rules --json`, `--rule` and dl:ok markers spell them.</summary>
  RULE_DUP_TAB_ORDER     = 'dfm-duplicate-tab-order';
  RULE_CONFLICT_ACCEL    = 'dfm-conflicting-accelerator';
  RULE_CONFLICT_SHORTCUT = 'dfm-conflicting-shortcut';
  RULE_ACTION_ONCLICK    = 'dfm-action-and-onclick';
  RULE_DB_ON_FORM        = 'db-component-on-form';
  RULE_DEFAULT_NAME      = 'dfm-default-component-name';
  RULE_HINT_INACTIVE     = 'dfm-hint-inactive';
  /// <summary>Host rule widened by a shipped default policy (G-20): Connected or Active left True in the form file.</summary>
  RULE_HOST_DISALLOWED   = 'disallowed-dfm-property';

type
  /// <summary>Checker entry points of v154 lane DFM; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// Only CheckDfm does work: every rule needs the sibling form file.</remarks>
  TV154DFMRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library); this lane has none.</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>nil.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file: the seven form rules and the default policy.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings located in the .dfm; nil when none or when the form file is binary.</returns>
    /// <remarks>Reads the .pas as text for dfm-action-and-onclick, dfm-default-component-name,
    /// dfm-hint-inactive and db-component-on-form; silent for those when the source cannot be read.</remarks>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes; this lane has none.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>nil.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check; this lane has none.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>nil.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.StrUtils
  , System.RegularExpressions
  , DRagLint.Lint.Config
  , DRagLint.V151.DFMB.Support
  , DRagLint.V154.DFM.Support
  ;

const
  SEV_HINT    = 'hint';
  SEV_INFO    = 'info';
  SEV_WARNING = 'warning';
  CAT_BUGS    = 'bug-patterns';
  CAT_STRUCT  = 'structure';
  POLICY_PREFIX = 'dfm:';

type
  /// <summary>One run over one form file: the tree, the source text and the finding sink.</summary>
  TFormRun = record
    Ctx  : TV151FileCtx;
    Model: TDfmModel;
    Src  : string;
    Found: TList<TLintFinding>;
    procedure Add(const ARule, ADefaultSev: string; ALine, ACol: Integer; const AMessage: string);
    procedure AddAtProp(const ARule, ADefaultSev: string; const AObj: TDfmObj; const AProp, AMessage: string);
  end;

procedure TFormRun.Add(const ARule, ADefaultSev: string; ALine, ACol: Integer; const AMessage: string);
begin
  var F: TLintFinding:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.FilePath := Ctx.DfmPath;
  F.StartLine:= ALine;
  F.StartCol := ACol;
  F.EndLine  := ALine;
  F.EndCol   := ACol + 1;
  F.Severity := Ctx.Cfg.ApplySeverity(ARule, ADefaultSev);
  F.Message  := AMessage;
  Found.Add(F);
end;

procedure TFormRun.AddAtProp(const ARule, ADefaultSev: string; const AObj: TDfmObj; const AProp, AMessage: string);
begin
  var I: Integer:= AObj.IndexOfProp(AProp);
  if I >= 0 then Add(ARule, ADefaultSev, AObj.Props[I].Line, AObj.Props[I].Col, AMessage)
  else Add(ARule, ADefaultSev, AObj.Line, 1, AMessage);
end;

class procedure TV154DFMRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_DUP_TAB_ORDER, CAT_BUGS, SEV_INFO,
    'Two sibling controls of a form file store the same TabOrder -- the Tab key visits them in an arbitrary order'));
  ADecls.Add(V151Rule(RULE_CONFLICT_ACCEL, CAT_BUGS, SEV_INFO,
    'Two sibling captions (or two items of one menu level) use the same Alt key -- the second one can not be reached by its underlined letter'));
  ADecls.Add(V151Rule(RULE_CONFLICT_SHORTCUT, CAT_BUGS, SEV_WARNING,
    'Two actions of one action list, or two items of one menu, carry the same shortcut -- only one of them runs'));
  ADecls.Add(V151Rule(RULE_ACTION_ONCLICK, CAT_BUGS, SEV_WARNING,
    'A control has an Action and its own OnClick -- the OnClick handler runs instead of the action unless it calls the action itself'));
  ADecls.Add(V151Rule(RULE_DB_ON_FORM, CAT_STRUCT, SEV_HINT,
    'A database access component (connection, query, table, stored procedure) sits on a form instead of a data module', False));
  ADecls.Add(V151Rule(RULE_DEFAULT_NAME, CAT_STRUCT, SEV_HINT,
    'A component that code refers to still has the name the designer gave it (Button1, Label7) -- the code does not say what it is', False));
  ADecls.Add(V151Rule(RULE_HINT_INACTIVE, CAT_BUGS, SEV_HINT,
    'A control stores a Hint but ShowHint is False and ParentShowHint is False -- the hint is never shown', False));
  ADecls.Add(V151Host(RULE_HOST_DISALLOWED));
end;

{ ---------------------------------------------------------------------------
  G-12 dfm-duplicate-tab-order
  --------------------------------------------------------------------------- }

procedure CheckTabOrder(var ARun: TFormRun);
begin
  for var P: TDfmObj in ARun.Model.All do
  begin
    { a layout container orders its controls itself; the children of a splitter belong to its panes (each pane
      numbers its own), so equal numbers under a splitter are not a clash (all 61 findings of the first M2022 run) }
    if ContainsText(ClassLeaf(P.ClsName), 'Layout') or ContainsText(ClassLeaf(P.ClsName), 'Splitter') then Continue;
    var Seen: TDictionary<Integer, TDfmObj>:= TDictionary<Integer, TDfmObj>.Create;
    try
      for var K: TDfmObj in P.Kids do
      begin
        if not K.Has('TabOrder') or BoolPropIs(K, 'Visible', False) or BoolPropIs(K, 'TabStop', False) then Continue;
        var N: Integer:= StrToIntDef(Trim(K.Val('TabOrder')), -1);
        if N < 0 then Continue;
        var First: TDfmObj;
        if Seen.TryGetValue(N, First) then
          ARun.AddAtProp(RULE_DUP_TAB_ORDER, SEV_INFO, K, 'TabOrder',
            Format('%s: %s stores TabOrder = %d, the same as its sibling %s -- the Tab key order of the two is arbitrary.',
              [K.ObjName, K.ClsName, N, First.ObjName]))
        else Seen.Add(N, K);
      end;
    finally
      Seen.Free;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  G-12 dfm-conflicting-accelerator
  --------------------------------------------------------------------------- }

procedure CheckAccelerators(var ARun: TFormRun);
begin
  for var P: TDfmObj in ARun.Model.All do
  begin
    var Seen: TDictionary<Char, TDfmObj>:= TDictionary<Char, TDfmObj>.Create;
    try
      for var K: TDfmObj in P.Kids do
      begin
        if not IsAcceleratorClass(K.ClsName) or not K.Has('Caption') then Continue;
        if BoolPropIs(K, 'Visible', False) or BoolPropIs(K, 'ShowAccelChar', False) then Continue;
        var Key: Char:= AcceleratorOf(DecodeDfmString(K.Val('Caption')));
        if Key = #0 then Continue;
        var First: TDfmObj;
        if Seen.TryGetValue(Key, First) then
          ARun.AddAtProp(RULE_CONFLICT_ACCEL, SEV_INFO, K, 'Caption',
            Format('%s: %s uses the accelerator Alt+%s, the same as its sibling %s -- one of them can not be reached by its letter.',
              [K.ObjName, K.ClsName, Key, First.ObjName]))
        else Seen.Add(Key, K);
      end;
    finally
      Seen.Free;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  G-12 dfm-conflicting-shortcut
  --------------------------------------------------------------------------- }

{ The menu a menu item belongs to (its nearest ancestor that is a menu but not an item); else the parent. }
function ShortCutScope(const AObj: TDfmObj): TDfmObj;
begin
  Result:= AObj.Parent;
  if not ContainsText(AObj.ClsName, 'MenuItem') then Exit;
  var O: TDfmObj:= AObj.Parent;
  while O <> nil do
  begin
    if ContainsText(O.ClsName, 'Menu') and not ContainsText(O.ClsName, 'MenuItem') then Exit(O);
    O:= O.Parent;
  end;
end;

{ What the shortcut's neighbours are called in the message. }
function ScopeWord(const AObj: TDfmObj): string;
begin
  if ContainsText(AObj.ClsName, 'MenuItem') then Exit('menu');
  Result:= if ContainsText(AObj.ClsName, 'dxBar') then 'bar manager' else 'action list';
end;

procedure CheckShortcuts(var ARun: TFormRun);
begin
  var Seen: TDictionary<string, TDfmObj>:= TDictionary<string, TDfmObj>.Create;
  try
    for var K: TDfmObj in ARun.Model.All do
    begin
      if not K.Has('ShortCut') or K.Has('Action') then Continue;
      if BoolPropIs(K, 'Visible', False) or BoolPropIs(K, 'Enabled', False) or SameText(Trim(K.Val('Visible')), 'ivNever') then Continue;
      var V: Integer:= StrToIntDef(Trim(K.Val('ShortCut')), 0);
      if V = 0 then Continue;
      var Scope: TDfmObj:= ShortCutScope(K);
      var Key: string:= IntToHex(NativeInt(Pointer(Scope)), 1) + '/' + IntToStr(V);
      var First: TDfmObj;
      if Seen.TryGetValue(Key, First) then
        ARun.AddAtProp(RULE_CONFLICT_SHORTCUT, SEV_WARNING, K, 'ShortCut',
          Format('%s: %s has the shortcut %s, the same as %s in the same %s -- only one of them runs.',
            [K.ObjName, K.ClsName, ShortCutName(V), First.ObjName, ScopeWord(K)]))
      else Seen.Add(Key, K);
    end;
  finally
    Seen.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  G-12 dfm-action-and-onclick
  --------------------------------------------------------------------------- }

procedure CheckActionOnClick(var ARun: TFormRun);
begin
  if ARun.Src = '' then Exit;
  for var K: TDfmObj in ARun.Model.All do
  begin
    if not (K.Has('Action') and K.Has('OnClick')) then Continue;
    var ActName: string:= Trim(K.Val('Action'));
    var Handler: string:= Trim(K.Val('OnClick'));
    if (ActName = '') or SameText(ActName, 'nil') or (Handler = '') then Continue;
    var Act: TDfmObj:= ARun.Model.Find(ActName);
    var ActHandler: string:= if Act <> nil then Trim(Act.Val('OnExecute')) else '';
    if (ActHandler <> '') and SameText(ActHandler, Handler) then Continue;
    var Body: string:= MethodBody(ARun.Src, Handler);
    if Body = '' then Continue;  { handler not visible in this unit: it may call the action }
    if ContainsText(Body, 'Execute') or ContainsText(Body, 'Action') or ((ActHandler <> '') and ContainsText(Body, ActHandler)) then Continue;
    ARun.AddAtProp(RULE_ACTION_ONCLICK, SEV_WARNING, K, 'OnClick',
      Format('%s: %s has Action = %s and its own OnClick = %s -- the handler runs instead of the action and does not call it.',
        [K.ObjName, K.ClsName, ActName, Handler]));
  end;
end;

{ ---------------------------------------------------------------------------
  G-21 db-component-on-form
  --------------------------------------------------------------------------- }

function RootIsDataModule(const ARun: TFormRun; const ARoot: TDfmObj): Boolean;
begin
  var Cls: string:= ClassLeaf(ARoot.ClsName);
  if ContainsText(Cls, 'DataModule') or ContainsText(Cls, 'DataMod') or StartsText('TDM', Cls) then Exit(True);
  Result:= (ARun.Src <> '') and TRegEx.IsMatch(ARun.Src,
    '\b' + TRegEx.Escape(Cls) + '\s*=\s*class\s*\(\s*[\w.]*(DataModule|DM)\w*\s*\)', [roIgnoreCase]);
end;

procedure CheckDbOnForm(var ARun: TFormRun);
begin
  if ARun.Model.All.Count = 0 then Exit;
  var Root: TDfmObj:= ARun.Model.All[0];
  if RootIsDataModule(ARun, Root) then Exit;
  var Hits: TList<TDfmObj>:= TList<TDfmObj>.Create;
  try
    for var I:= 1 to ARun.Model.All.Count - 1 do
      if IsDbAccessClass(ARun.Model.All[I].ClsName) then Hits.Add(ARun.Model.All[I]);
    for var K: TDfmObj in Hits do
      ARun.Add(RULE_DB_ON_FORM, SEV_HINT, K.Line, 1,
        Format('%s: %s is a database component on the form %s (%d on this form) -- move it to a data module.',
          [K.ObjName, K.ClsName, Root.ObjName, Hits.Count]));
  finally
    Hits.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  G-34 dfm-default-component-name
  --------------------------------------------------------------------------- }

procedure CheckDefaultNames(var ARun: TFormRun);
begin
  if ARun.Src = '' then Exit;
  for var I:= 1 to ARun.Model.All.Count - 1 do
  begin
    var K: TDfmObj:= ARun.Model.All[I];
    if not HasDefaultName(K) then Continue;
    if CountCodeUses(ARun.Src, K.ObjName) = 0 then Continue;
    ARun.Add(RULE_DEFAULT_NAME, SEV_HINT, K.Line, 1,
      Format('%s: %s keeps the name the designer gave it and the unit refers to it -- rename it to what it is for.',
        [K.ObjName, K.ClsName]));
  end;
end;

{ ---------------------------------------------------------------------------
  G-37 dfm-hint-inactive
  --------------------------------------------------------------------------- }

procedure CheckHintInactive(var ARun: TFormRun);
begin
  if (ARun.Src = '') or SourceControlsHints(ARun.Src) then Exit;
  for var K: TDfmObj in ARun.Model.All do
  begin
    if not K.Has('Hint') or ContainsText(K.ClsName, 'MenuItem') or ContainsText(K.ClsName, 'Action')
      or ContainsText(K.ClsName, 'Field') then Continue;
    var Text: string:= Trim(K.Val('Hint'));
    if (Text = '') or (Text = '''''') then Continue;
    if not HintIsInactive(K) then Continue;
    ARun.AddAtProp(RULE_HINT_INACTIVE, SEV_HINT, K, 'Hint',
      Format('%s: %s stores a Hint, but ShowHint and ParentShowHint are False up its parent chain -- the hint is never shown.',
        [K.ObjName, K.ClsName]));
  end;
end;

{ ---------------------------------------------------------------------------
  G-20 shipped default policy of disallowed-dfm-property
  --------------------------------------------------------------------------- }

{ True when the project's own policy list already has a dfm: entry for the property -- then the project decides. }
function PolicyNamesProp(const ACfg: TLintConfig; const AProp: string): Boolean;
begin
  Result:= False;
  for var E in ACfg.DisallowedNames do
  begin
    if not StartsText(POLICY_PREFIX, E.Name) then Continue;
    var Body: string:= Trim(Copy(E.Name, Length(POLICY_PREFIX) + 1, MaxInt));
    var Eq: Integer:= Pos('=', Body);
    if Eq > 0 then Body:= Trim(Copy(Body, 1, Eq - 1));
    var Dot: Integer:= Pos('.', Body);
    if (Dot > 0) and SameText(Trim(Copy(Body, Dot + 1, MaxInt)), AProp) then Exit(True);
  end;
end;

procedure CheckDefaultPolicy(var ARun: TFormRun);
begin
  var ConnOwned: Boolean:= PolicyNamesProp(ARun.Ctx.Cfg, 'Connected');
  var ActiveOwned: Boolean:= PolicyNamesProp(ARun.Ctx.Cfg, 'Active');
  for var K: TDfmObj in ARun.Model.All do
  begin
    var Leaf: string:= ClassLeaf(K.ClsName);
    if not ConnOwned and BoolPropIs(K, 'Connected', True) and IsDbAccessClass(K.ClsName)
      and (ContainsText(Leaf, 'Connection') or ContainsText(Leaf, 'Database')) then
      ARun.AddAtProp(RULE_HOST_DISALLOWED, SEV_WARNING, K, 'Connected',
        Format('%s.Connected (%s) is True in the form file -- the program opens the developer''s database at start-up; connect in code (default policy).',
          [K.ClsName, K.ObjName]))
    else if not ActiveOwned and BoolPropIs(K, 'Active', True) and IsDbAccessClass(K.ClsName)
      and not ContainsText(Leaf, 'Connection') and not ContainsText(Leaf, 'Database') then
      ARun.AddAtProp(RULE_HOST_DISALLOWED, SEV_WARNING, K, 'Active',
        Format('%s.Active (%s) is True in the form file -- the dataset is opened with the developer''s data at start-up; open it in code (default policy).',
          [K.ClsName, K.ObjName]));
  end;
end;

{ ---------------------------------------------------------------------------
  entry points
  --------------------------------------------------------------------------- }

class function TV154DFMRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@6d9b -- REVIEWED 2026-11-24 v154 DFM: signature fixed by the TV151 lane interface; every rule of this lane needs the form file
begin
  Result:= nil;
end;

class function TV154DFMRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if ACtx.DfmPath = '' then Exit;
  var Run: TFormRun:= Default(TFormRun);
  Run.Ctx:= ACtx;
  try
    Run.Model:= TDfmModel.Parse(TEncoding.ANSI.GetString(TFile.ReadAllBytes(ACtx.DfmPath)));
  except  // dl:ok bare-except@8f3b, try-except-swallowed@8f3b -- REVIEWED 2026-11-24 v154 DFM: an unreadable form file means the rules stay silent: no finding beats a false finding
    Exit;
  end;
  Run.Found:= TList<TLintFinding>.Create;
  try
    if Run.Model.All.Count = 0 then Exit;
    Run.Src:= ReadSource(ACtx.Path);
    if ACtx.Wants(RULE_DUP_TAB_ORDER) then CheckTabOrder(Run);
    if ACtx.Wants(RULE_CONFLICT_ACCEL) then CheckAccelerators(Run);
    if ACtx.Wants(RULE_CONFLICT_SHORTCUT) then CheckShortcuts(Run);
    if ACtx.Wants(RULE_ACTION_ONCLICK) then CheckActionOnClick(Run);
    if ACtx.Wants(RULE_DB_ON_FORM) then CheckDbOnForm(Run);
    if ACtx.Wants(RULE_DEFAULT_NAME) then CheckDefaultNames(Run);
    if ACtx.Wants(RULE_HINT_INACTIVE) then CheckHintInactive(Run);
    if ACtx.Wants(RULE_HOST_DISALLOWED) then CheckDefaultPolicy(Run);
    Result:= Run.Found.ToArray;
  finally
    Run.Found.Free;
    Run.Model.Free;
  end;
end;

class function TV154DFMRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@aa3f -- REVIEWED 2026-11-24 v154 DFM: signature fixed by the TV151 lane interface; this lane has no raw-byte check
begin
  Result:= nil;
end;

class function TV154DFMRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@2af0 -- REVIEWED 2026-11-24 v154 DFM: signature fixed by the TV151 lane interface; this lane has no project-wide check
begin
  Result:= nil;
end;

end.
