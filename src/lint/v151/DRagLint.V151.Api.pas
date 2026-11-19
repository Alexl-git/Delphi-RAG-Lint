unit DRagLint.V151.Api;

{ Wave v151 (1.51.0-alpha) registration scaffold, lane FRAME: the types every
  v151 rule-lane unit is written against. The lane units, the dispatcher
  (DRagLint.V151.Dispatch) and the CLI hooks all speak these records, so a rule
  lane never edits a shared unit. How-to for lanes:
  C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  , DRagLint.Lint.RuleCatalog
  , DRagLint.Lint.SharedScope  { TSiblingStoreResolver / TSiblingProjectLister (1.52 BK-XPROJ) }
  ;

type
  /// <summary>What a v151 catalog declaration announces.</summary>
  /// <remarks>
  /// vdkNewRule adds a catalog row (`rules --json` counts it).
  /// vdkHostExpansion adds NO row: it says "this lane also emits findings under
  /// the existing rule HostId", so `--rule HostId` still reaches the lane.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.Api.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151DeclKind = (vdkNewRule, vdkHostExpansion);

  /// <summary>One rule id a v151 lane unit may emit.</summary>
  /// <remarks>
  /// Build it with <see cref="V151Rule"/> or <see cref="V151Host"/>,
  /// never by hand. Enabled = False makes the rule OFF by default on every
  /// surface (catalog, `lint`, `lint-all`, LSP completion): the catalog's
  /// BUILTIN_RULES_OFF_BY_DEFAULT folds every provider row declared OFF.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.Api.pas) ?, declaration (DRagLint.V151.APP.pas) ?, DRagLint.V151.Api.V151Host (DRagLint.V151.Api.pas), DRagLint.V151.Api.V151Rule (DRagLint.V151.Api.pas), DRagLint.V151.APP.TV151APPRules.Catalog (DRagLint.V151.APP.pas) ? (+54 more)</para>
  /// <para>Used in units: DRagLint.V151.Api, DRagLint.V151.APP, DRagLint.V151.CMP, DRagLint.V151.DFMA, DRagLint.V151.DFMB, DRagLint.V151.Dispatch, DRagLint.V151.DS, DRagLint.V151.EXC, DRagLint.V151.MEM, DRagLint.V151.OO (+18 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151RuleDecl = record
    Kind    : TV151DeclKind;
    Id      : string;
    Category: string;   // one of the existing categories (`rules --json`)
    Severity: string;   // 'hint' | 'info' | 'warning' | 'error'
    Title   : string;
    Enabled : Boolean;  // default state; False = OFF by default
    Params  : TArray<TRuleParam>;
  end;

  /// <summary>Everything a per-file v151 check gets about the file being linted.</summary>
  /// <remarks>
  /// Built by the CLI hook in DoLint and in the per-file loop of
  /// DoLintAll; read-only for the lanes. Store / LibStore may be nil (`lint`
  /// with no index, or a stale library) and FileId is 0 then: a store-backed
  /// check must degrade to "no finding", never raise.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.APP.pas) ?, DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.V151.Api.TV151FileCtx.Make (DRagLint.V151.Api.pas), DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas) ? (+132 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.V151.Api, DRagLint.V151.APP, DRagLint.V151.CMP, DRagLint.V151.DFMA, DRagLint.V151.DFMB, DRagLint.V151.Dispatch, DRagLint.V151.DS, DRagLint.V151.EXC, DRagLint.V151.MEM (+20 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151FileCtx = record
    Path      : string;         // the .pas being linted, as the verb resolved it
    DfmPath   : string;         // sibling .dfm when it exists, else ''
    Cfg       : TLintConfig;
    Store     : ISymbolStore;   // project index, or nil
    FileId    : Int64;          // Path's id in Store, or 0
    LibStore  : ISymbolStore;   // platform library index, or nil
    NarrowRule: string;         // --rule of this run, '' = every rule
    /// <summary>True when this run reports ARuleId (no --rule, or --rule ARuleId).</summary>
    /// <param name="ARuleId">A rule id the lane is about to compute.</param>
    /// <returns>False when --rule names another rule, or when ARuleId already overran the
    /// per-rule time budget on this file (DRagLint.Core.LintBudget, 1.52 D9).</returns>
    /// <remarks>
    /// Also marks the start of ARuleId's time slice for that budget: call it right
    /// before computing the rule.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.APP.TV151APPRules.CheckFile (DRagLint.V151.APP.pas), DRagLint.V151.CMP.TCmpRun.CheckPaintRoutines (DRagLint.V151.CMP.pas), DRagLint.V151.CMP.TCmpRun.Run (DRagLint.V151.CMP.pas), DRagLint.V151.DFMA.TV151DFMARules.CheckDfm (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMA.TV151DFMARules.CheckFile (DRagLint.V151.DFMA.pas) (+19 more)</para>
    /// <para>Calls: DRagLint.Core.LintBudget.RuleBudgetEnter, SameText</para>
    /// <para>Returns: ((NarrowRule = '') or SameText(NarrowRule, ARuleId)) and RuleBudgetEnter(ARuleId)</para>
    /// <para>Reads: NarrowRule</para>
    /// <seealso cref="DRagLint.Core.LintBudget.RuleBudgetEnter"/>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Make"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Wants(const ARuleId: string): Boolean;
    /// <summary>Builds the context; finds the sibling .dfm itself.</summary>
    /// <param name="APath">The .pas file.</param>
    /// <param name="ACfg">The run's lint configuration.</param>
    /// <param name="AStore">Project index or nil.</param>
    /// <param name="AFileId">APath's file id in AStore, or 0.</param>
    /// <param name="ALibStore">Library index or nil.</param>
    /// <param name="ANarrowRule">The run's --rule, '' for all.</param>
    /// <returns>The filled context.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: Default</para>
    /// <para>Returns: Default(TV151FileCtx)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Make(const APath: string; const ACfg: TLintConfig; const AStore: ISymbolStore;
      AFileId: Int64; const ALibStore: ISymbolStore; const ANarrowRule: string): TV151FileCtx; static;
  end;

  /// <summary>Everything a project-wide v151 check gets (lint-all only).</summary>
  /// <remarks>
  /// Store is never nil here (lint-all requires an index); LibStore
  /// may be nil. FilePaths = every .pas lint-all walked; ProjectPath = the
  /// --project argument or ''.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.Api.pas) ?, declaration (DRagLint.V151.APP.pas) ?, DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.V151.Api.TV151ProjectCtx.Make (DRagLint.V151.Api.pas), DRagLint.V151.APP.TV151APPRules.CheckProject (DRagLint.V151.APP.pas) ? (+52 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.V151.Api, DRagLint.V151.APP, DRagLint.V151.CMP, DRagLint.V151.DFMA, DRagLint.V151.DFMB, DRagLint.V151.Dispatch, DRagLint.V151.DS, DRagLint.V151.EXC, DRagLint.V151.MEM (+19 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151ProjectCtx = record
    Store      : ISymbolStore;
    LibStore   : ISymbolStore;
    Cfg        : TLintConfig;
    NarrowRule : string;
    FilePaths  : TArray<string>;
    ProjectPath: string;
    /// <summary>Opens a sibling project's index by name (SHARED-UNIT-SCOPE); nil when the caller has none.</summary>
    /// <remarks>1.52 BK-XPROJ: set by lint-all after Make, so a project-wide rule can judge a unit other projects also compile (TSharedScope). Make leaves it nil.</remarks>
    SiblingStore: TSiblingStoreResolver;
    /// <summary>Lists the sibling project names the run can ask; nil when the caller has none.</summary>
    /// <remarks>1.52 BK-XPROJ: set together with SiblingStore. Make leaves it nil.</remarks>
    SiblingNames: TSiblingProjectLister;
    /// <summary>True when this run reports ARuleId.</summary>
    /// <param name="ARuleId">A rule id the lane is about to compute.</param>
    /// <returns>False only when --rule names another rule.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.OO.TV151OORules.CheckProject (DRagLint.V151.OO.pas), DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject (DRagLint.V151.RTLCOLL.pas), DRagLint.V152.APP2.TV152APP2Rules.CheckProject (DRagLint.V152.APP2.pas), DRagLint.V152.ATLA.TV152ATLARules.CheckProject (DRagLint.V152.ATLA.pas), DRagLint.V152.ATLB.TV152ATLBRules.CheckProject (DRagLint.V152.ATLB.pas) (+1 more)</para>
    /// <para>Calls: SameText</para>
    /// <para>Returns: (NarrowRule = '') or SameText(NarrowRule, ARuleId)</para>
    /// <para>Reads: NarrowRule</para>
    /// <seealso cref="DRagLint.V151.Api.TV151ProjectCtx.Make"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Wants(const ARuleId: string): Boolean;
    /// <summary>Builds the context.</summary>
    /// <param name="AStore">Project index (not nil).</param>
    /// <param name="ALibStore">Library index or nil.</param>
    /// <param name="ACfg">The run's lint configuration.</param>
    /// <param name="ANarrowRule">The run's --rule, '' for all.</param>
    /// <param name="AFilePaths">Files lint-all walked.</param>
    /// <param name="AProjectPath">--project or ''.</param>
    /// <returns>The filled context.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: Default</para>
    /// <para>Returns: Default(TV151ProjectCtx)</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.TV151ProjectCtx.Wants"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Make(const AStore, ALibStore: ISymbolStore; const ACfg: TLintConfig;
      const ANarrowRule: string; const AFilePaths: TArray<string>; const AProjectPath: string): TV151ProjectCtx; static;
  end;

/// <summary>Declares a NEW rule id (adds one catalog row).</summary>
/// <param name="AId">Rule id, lowercase-with-dashes, unique across the catalog.</param>
/// <param name="ACategory">An existing category.</param>
/// <param name="ASeverity">'hint' | 'info' | 'warning' | 'error'.</param>
/// <param name="ATitle">One-line catalog title.</param>
/// <param name="AEnabled">False = OFF by default.</param>
/// <param name="AParams">Optional configurable parameters (MkParam rows).</param>
/// <returns>The declaration to Add to the lane's Catalog list.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.APP.TV151APPRules.Catalog (DRagLint.V151.APP.pas), DRagLint.V151.CMP.TV151CMPRules.Catalog (DRagLint.V151.CMP.pas), DRagLint.V151.DFMA.TV151DFMARules.Catalog (DRagLint.V151.DFMA.pas), DRagLint.V151.DFMB.TV151DFMBRules.Catalog (DRagLint.V151.DFMB.pas), DRagLint.V151.DS.TV151DSRules.Catalog (DRagLint.V151.DS.pas) (+16 more)</para>
/// <para>Calls: Default</para>
/// <para>Returns: Default(TV151RuleDecl)</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function V151Rule(const AId, ACategory, ASeverity, ATitle: string; AEnabled: Boolean = True;
  const AParams: TArray<TRuleParam> = nil): TV151RuleDecl;

/// <summary>Declares that the lane emits under an EXISTING rule id (in-place expansion).</summary>
/// <param name="AHostId">The existing rule id; it gets no new catalog row.</param>
/// <returns>The declaration to Add to the lane's Catalog list.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.CMP.TV151CMPRules.Catalog (DRagLint.V151.CMP.pas), DRagLint.V151.DFMA.TV151DFMARules.Catalog (DRagLint.V151.DFMA.pas), DRagLint.V151.DS.TV151DSRules.Catalog (DRagLint.V151.DS.pas), DRagLint.V151.MEM.TV151MEMRules.Catalog (DRagLint.V151.MEM.pas), DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.Catalog (DRagLint.V151.RTLCOLL.pas) (+5 more)</para>
/// <para>Calls: Default</para>
/// <para>Returns: Default(TV151RuleDecl)</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function V151Host(const AHostId: string): TV151RuleDecl;

/// <summary>Keeps only the findings ANarrowRule asks for.</summary>
/// <param name="AFindings">Findings of one check.</param>
/// <param name="ANarrowRule">--rule of the run, '' keeps all.</param>
/// <returns>AFindings filtered by rule id (case-insensitive).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.Dispatch.TV151Dispatch.CheckDfm (DRagLint.V151.Dispatch.pas), DRagLint.V151.Dispatch.TV151Dispatch.CheckFile (DRagLint.V151.Dispatch.pas), DRagLint.V151.Dispatch.TV151Dispatch.CheckProject (DRagLint.V151.Dispatch.pas), DRagLint.V151.Dispatch.TV151Dispatch.CheckRawBytes (DRagLint.V151.Dispatch.pas)</para>
/// <para>Calls: SameText</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function V151Narrow(const AFindings: TArray<TLintFinding>; const ANarrowRule: string): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , DRagLint.Core.LintBudget
  ;

function V151Rule(const AId, ACategory, ASeverity, ATitle: string; AEnabled: Boolean;
  const AParams: TArray<TRuleParam>): TV151RuleDecl;
begin
  Result:= Default(TV151RuleDecl);
  Result.Kind    := vdkNewRule;
  Result.Id      := AId;
  Result.Category:= ACategory;
  Result.Severity:= ASeverity;
  Result.Title   := ATitle;
  Result.Enabled := AEnabled;
  Result.Params  := AParams;
end;

function V151Host(const AHostId: string): TV151RuleDecl;
begin
  Result:= Default(TV151RuleDecl);
  Result.Kind   := vdkHostExpansion;
  Result.Id     := AHostId;
  Result.Enabled:= True;
end;

function V151Narrow(const AFindings: TArray<TLintFinding>; const ANarrowRule: string): TArray<TLintFinding>;
begin
  if ANarrowRule = '' then Exit(AFindings);
  Result:= nil;
  for var F: TLintFinding in AFindings do
    if SameText(F.RuleId, ANarrowRule) then Result:= Result + [F];
end;

{ TV151FileCtx }

function TV151FileCtx.Wants(const ARuleId: string): Boolean;
begin
  { 1.52 BUDGET: report the rule to the per-file budget; False once it overran on this file }
  Result:= ((NarrowRule = '') or SameText(NarrowRule, ARuleId)) and RuleBudgetEnter(ARuleId);
end;

class function TV151FileCtx.Make(const APath: string; const ACfg: TLintConfig; const AStore: ISymbolStore;
  AFileId: Int64; const ALibStore: ISymbolStore; const ANarrowRule: string): TV151FileCtx;
begin
  Result:= Default(TV151FileCtx);
  Result.Path      := APath;
  Result.Cfg       := ACfg;
  Result.Store     := AStore;
  Result.FileId    := if AStore <> nil then AFileId else 0;
  Result.LibStore  := ALibStore;
  Result.NarrowRule:= ANarrowRule;
  var Dfm: string:= TPath.ChangeExtension(APath, '.dfm');
  Result.DfmPath   := if TFile.Exists(Dfm) then Dfm else '';
end;

{ TV151ProjectCtx }

function TV151ProjectCtx.Wants(const ARuleId: string): Boolean;
begin
  Result:= (NarrowRule = '') or SameText(NarrowRule, ARuleId);
end;

class function TV151ProjectCtx.Make(const AStore, ALibStore: ISymbolStore; const ACfg: TLintConfig;
  const ANarrowRule: string; const AFilePaths: TArray<string>; const AProjectPath: string): TV151ProjectCtx;
begin
  Result:= Default(TV151ProjectCtx);
  Result.Store      := AStore;
  Result.LibStore   := ALibStore;
  Result.Cfg        := ACfg;
  Result.NarrowRule := ANarrowRule;
  Result.FilePaths  := AFilePaths;
  Result.ProjectPath:= AProjectPath;
end;

end.
