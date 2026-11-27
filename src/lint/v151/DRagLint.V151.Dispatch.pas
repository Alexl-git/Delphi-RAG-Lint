unit DRagLint.V151.Dispatch;

{ Wave v151 (1.51.0-alpha) lane FRAME: the ONE place that calls the fifteen v151
  rule-lane units, (1.52 FRAME F2) the eleven v152, (1.54) the five v154 and (1.56) the eight v156 ones. The CLI hooks call only this unit; the catalog learns the v151
  rows through TRuleCatalog's provider list (RegisterProviderRules), filled in
  this unit's initialization. The lane order below is fixed and alphabetical:
  APP CMP DFMA DFMB DS EXC MEM OO RTLCOLL RTLSTR STY THRA THRB TXT TYP, then the
  v152 lanes APP2 ATLA ATLB DEFAULTS DOCPOL FPS PROJ2 PTW RTTI5 UNCONN XCONST, then
  the v154 lanes DFM EXPR FLOW SCHEMA SQL, then the v156 lanes FACTA MEMA MEMB OOA1 OOA2
  OOB1 OOB2 THR.
  Owned by FRAME; a rule lane never edits it. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Lint.RuleCatalog
  , DRagLint.V151.Api
  ;

type
  /// <summary>Calls every v151 lane unit in a fixed order and merges their findings.</summary>
  /// <remarks>
  /// Stateless after unit initialization (the declaration list is built
  /// once there), so every method is safe to call from any thread the caller
  /// already lints on. With no lane declaring a rule, Wants is always False and
  /// the CLI hooks cost one boolean test per file.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.V151.Dispatch.initialization (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151Dispatch = class
  public
    /// <summary>Every declaration of every lane (new rules and host expansions), lane order.</summary>
    /// <returns>A copy of the start-up list.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: Copy</para>
    /// <para>Returns: Copy(GDecls)</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CatalogRows"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckFile"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckProject"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Decls: TArray<TV151RuleDecl>; static;
    /// <summary>The catalog rows of the NEW v151 rules (host expansions excluded).</summary>
    /// <returns>One TRuleInfo per vdkNewRule declaration, Source = 'builtin'.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.initialization (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: Default</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckFile"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckProject"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckRawBytes"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.Decls"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CatalogRows: TArray<TRuleInfo>; static;
    /// <summary>Every rule id a lane may emit (new ids and host ids), lowercase.</summary>
    /// <returns>Distinct ids; empty while every lane is a stub.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: Copy</para>
    /// <para>Returns: Copy(GIds)</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CatalogRows"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckFile"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckProject"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function RuleIds: TArray<string>; static;
    /// <summary>Does this run need the v151 lanes at all?</summary>
    /// <param name="ANarrowRule">The run's --rule, '' for all.</param>
    /// <returns>False when no lane declares anything, or when --rule names an id no lane declares.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Returns: False</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CatalogRows"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckFile"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckProject"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Wants(const ANarrowRule: string): Boolean; static;
    /// <summary>Per-file pass: every lane's CheckFile, then CheckRawBytes on the .pas, then
    /// (sibling form present) CheckDfm and CheckRawBytes on the .dfm.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <returns>All findings, narrowed to ACtx.NarrowRule.</returns>
    /// <remarks>
    /// An exception in one lane is reported on stderr and that lane's
    /// findings for this file are dropped; the other lanes still run.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Core.LintBudget.RuleBudgetBeginFile, DRagLint.Core.LintBudget.RuleBudgetEffectiveMs, DRagLint.Lint.Config.TLintConfig.RuleTimeBudgetMs, DRagLint.V151.Api.V151Narrow, DRagLint.V151.Dispatch.Budgeted, DRagLint.V151.Dispatch.CloseBudget, DRagLint.V151.Dispatch.LaneFailed, DRagLint.V151.Dispatch.TV151Dispatch.CheckDfm, DRagLint.V151.Dispatch.TV151Dispatch.CheckRawBytes</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Core.LintBudget.RuleBudgetBeginFile"/>
    /// <seealso cref="DRagLint.Core.LintBudget.RuleBudgetEffectiveMs"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.RuleTimeBudgetMs"/>
    /// <seealso cref="DRagLint.V151.Api.V151Narrow"/>
    /// <seealso cref="DRagLint.V151.Dispatch.Budgeted"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Every lane's CheckDfm for ACtx.DfmPath (nil when there is no sibling form).</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <returns>Findings, narrowed.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.TV151Dispatch.CheckFile (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Narrow, DRagLint.V151.Dispatch.Budgeted, DRagLint.V151.Dispatch.LaneFailed</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Narrow"/>
    /// <seealso cref="DRagLint.V151.Dispatch.Budgeted"/>
    /// <seealso cref="DRagLint.V151.Dispatch.LaneFailed"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CatalogRows"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckFile"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Every lane's CheckRawBytes for one file's bytes.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">ACtx.Path or ACtx.DfmPath; read from disk here.</param>
    /// <returns>Findings, narrowed; nil when the file cannot be read.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.TV151Dispatch.CheckFile (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Narrow, DRagLint.V151.Dispatch.Budgeted, DRagLint.V151.Dispatch.LaneFailed</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Narrow"/>
    /// <seealso cref="DRagLint.V151.Dispatch.Budgeted"/>
    /// <seealso cref="DRagLint.V151.Dispatch.LaneFailed"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CatalogRows"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckDfm"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string): TArray<TLintFinding>; static;
    /// <summary>Project-wide pass (lint-all): every lane's CheckProject.</summary>
    /// <param name="ACtx">The project.</param>
    /// <returns>Findings, narrowed.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Narrow, DRagLint.V151.Dispatch.LaneFailed</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Narrow"/>
    /// <seealso cref="DRagLint.V151.Dispatch.LaneFailed"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CatalogRows"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.Dispatch.TV151Dispatch.CheckFile"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Generics.Collections
  , System.IOUtils
  , DRagLint.Core.LintBudget  // dl:unit DRagLint.Core.LintBudget accepted -- 1.52 BUDGET: the frame drives the per-rule budget clock and emits its rule-skipped-budget note, so the ids travel with the clock
  , DRagLint.V151.APP
  , DRagLint.V151.CMP
  , DRagLint.V151.DFMA
  , DRagLint.V151.DFMB
  , DRagLint.V151.DS
  , DRagLint.V151.EXC
  , DRagLint.V151.MEM
  , DRagLint.V151.OO
  , DRagLint.V151.RTLCOLL
  , DRagLint.V151.RTLSTR
  , DRagLint.V151.STY
  , DRagLint.V151.THRA
  , DRagLint.V151.THRB
  , DRagLint.V151.TXT
  , DRagLint.V151.TYP
  , DRagLint.V152.APP2
  , DRagLint.V152.ATLA
  , DRagLint.V152.ATLB
  , DRagLint.V152.DEFAULTS
  , DRagLint.V152.DOCPOL
  , DRagLint.V152.FPS
  , DRagLint.V152.PROJ2
  , DRagLint.V152.PTW
  , DRagLint.V152.RTTI5
  , DRagLint.V152.UNCONN
  , DRagLint.V152.XCONST
  , DRagLint.V154.DFM
  , DRagLint.V154.EXPR
  , DRagLint.V154.FLOW
  , DRagLint.V154.SCHEMA
  , DRagLint.V154.SQL
  , DRagLint.V156.FACTA
  , DRagLint.V156.G32
  , DRagLint.V156.MEMA
  , DRagLint.V156.MEMB
  , DRagLint.V156.OOA1
  , DRagLint.V156.OOA2
  , DRagLint.V156.OOB1
  , DRagLint.V156.OOB2
  , DRagLint.V156.THR
  ;

type
  TFileCheck  = reference to function(const ACtx: TV151FileCtx): TArray<TLintFinding>;
  TBytesCheck = reference to function(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
  TProjCheck  = reference to function(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
  TCatalogFn  = reference to procedure(const ADecls: TList<TV151RuleDecl>);

  { One lane's five entry points, so the fixed order is written exactly once. }
  TLaneEntry = record
    Name   : string;
    Catalog: TCatalogFn;
    OnFile : TFileCheck;
    OnDfm  : TFileCheck;
    OnBytes: TBytesCheck;
    OnProj : TProjCheck;
  end;

var
  GLanes: TArray<TLaneEntry>;
  GDecls: TArray<TV151RuleDecl>;
  GIds  : TArray<string>;

function Lane(const AName: string; const ACatalog: TCatalogFn; const AOnFile, AOnDfm: TFileCheck;
  const AOnBytes: TBytesCheck; const AOnProj: TProjCheck): TLaneEntry;
begin
  Result.Name   := AName;
  Result.Catalog:= ACatalog;
  Result.OnFile := AOnFile;
  Result.OnDfm  := AOnDfm;
  Result.OnBytes:= AOnBytes;
  Result.OnProj := AOnProj;
end;

procedure BuildLanes;
begin
  GLanes:= [
    Lane('APP',     TV151APPRules.Catalog,     TV151APPRules.CheckFile,     TV151APPRules.CheckDfm,     TV151APPRules.CheckRawBytes,     TV151APPRules.CheckProject),
    Lane('CMP',     TV151CMPRules.Catalog,     TV151CMPRules.CheckFile,     TV151CMPRules.CheckDfm,     TV151CMPRules.CheckRawBytes,     TV151CMPRules.CheckProject),
    Lane('DFMA',    TV151DFMARules.Catalog,    TV151DFMARules.CheckFile,    TV151DFMARules.CheckDfm,    TV151DFMARules.CheckRawBytes,    TV151DFMARules.CheckProject),
    Lane('DFMB',    TV151DFMBRules.Catalog,    TV151DFMBRules.CheckFile,    TV151DFMBRules.CheckDfm,    TV151DFMBRules.CheckRawBytes,    TV151DFMBRules.CheckProject),
    Lane('DS',      TV151DSRules.Catalog,      TV151DSRules.CheckFile,      TV151DSRules.CheckDfm,      TV151DSRules.CheckRawBytes,      TV151DSRules.CheckProject),
    Lane('EXC',     TV151EXCRules.Catalog,     TV151EXCRules.CheckFile,     TV151EXCRules.CheckDfm,     TV151EXCRules.CheckRawBytes,     TV151EXCRules.CheckProject),
    Lane('MEM',     TV151MEMRules.Catalog,     TV151MEMRules.CheckFile,     TV151MEMRules.CheckDfm,     TV151MEMRules.CheckRawBytes,     TV151MEMRules.CheckProject),
    Lane('OO',      TV151OORules.Catalog,      TV151OORules.CheckFile,      TV151OORules.CheckDfm,      TV151OORules.CheckRawBytes,      TV151OORules.CheckProject),
    Lane('RTLCOLL', TV151RTLCOLLRules.Catalog, TV151RTLCOLLRules.CheckFile, TV151RTLCOLLRules.CheckDfm, TV151RTLCOLLRules.CheckRawBytes, TV151RTLCOLLRules.CheckProject),
    Lane('RTLSTR',  TV151RTLSTRRules.Catalog,  TV151RTLSTRRules.CheckFile,  TV151RTLSTRRules.CheckDfm,  TV151RTLSTRRules.CheckRawBytes,  TV151RTLSTRRules.CheckProject),
    Lane('STY',     TV151STYRules.Catalog,     TV151STYRules.CheckFile,     TV151STYRules.CheckDfm,     TV151STYRules.CheckRawBytes,     TV151STYRules.CheckProject),
    Lane('THRA',    TV151THRARules.Catalog,    TV151THRARules.CheckFile,    TV151THRARules.CheckDfm,    TV151THRARules.CheckRawBytes,    TV151THRARules.CheckProject),
    Lane('THRB',    TV151THRBRules.Catalog,    TV151THRBRules.CheckFile,    TV151THRBRules.CheckDfm,    TV151THRBRules.CheckRawBytes,    TV151THRBRules.CheckProject),
    Lane('TXT',     TV151TXTRules.Catalog,     TV151TXTRules.CheckFile,     TV151TXTRules.CheckDfm,     TV151TXTRules.CheckRawBytes,     TV151TXTRules.CheckProject),
    Lane('TYP',     TV151TYPRules.Catalog,     TV151TYPRules.CheckFile,     TV151TYPRules.CheckDfm,     TV151TYPRules.CheckRawBytes,     TV151TYPRules.CheckProject),
    // v152 lanes (1.52.0-alpha, FRAME F2): same provider mechanism, alphabetical after the v151 block.
    Lane('APP2',     TV152APP2Rules.Catalog, TV152APP2Rules.CheckFile, TV152APP2Rules.CheckDfm, TV152APP2Rules.CheckRawBytes, TV152APP2Rules.CheckProject),
    Lane('ATLA',     TV152ATLARules.Catalog, TV152ATLARules.CheckFile, TV152ATLARules.CheckDfm, TV152ATLARules.CheckRawBytes, TV152ATLARules.CheckProject),
    Lane('ATLB',     TV152ATLBRules.Catalog, TV152ATLBRules.CheckFile, TV152ATLBRules.CheckDfm, TV152ATLBRules.CheckRawBytes, TV152ATLBRules.CheckProject),
    Lane('DEFAULTS', TV152DEFAULTSRules.Catalog, TV152DEFAULTSRules.CheckFile, TV152DEFAULTSRules.CheckDfm, TV152DEFAULTSRules.CheckRawBytes, TV152DEFAULTSRules.CheckProject),
    Lane('DOCPOL',   TV152DOCPOLRules.Catalog, TV152DOCPOLRules.CheckFile, TV152DOCPOLRules.CheckDfm, TV152DOCPOLRules.CheckRawBytes, TV152DOCPOLRules.CheckProject),
    Lane('FPS',      TV152FPSRules.Catalog, TV152FPSRules.CheckFile, TV152FPSRules.CheckDfm, TV152FPSRules.CheckRawBytes, TV152FPSRules.CheckProject),
    Lane('PROJ2',    TV152PROJ2Rules.Catalog, TV152PROJ2Rules.CheckFile, TV152PROJ2Rules.CheckDfm, TV152PROJ2Rules.CheckRawBytes, TV152PROJ2Rules.CheckProject),
    Lane('PTW',      TV152PTWRules.Catalog, TV152PTWRules.CheckFile, TV152PTWRules.CheckDfm, TV152PTWRules.CheckRawBytes, TV152PTWRules.CheckProject),
    Lane('RTTI5',    TV152RTTI5Rules.Catalog, TV152RTTI5Rules.CheckFile, TV152RTTI5Rules.CheckDfm, TV152RTTI5Rules.CheckRawBytes, TV152RTTI5Rules.CheckProject),
    Lane('UNCONN',   TV152UNCONNRules.Catalog, TV152UNCONNRules.CheckFile, TV152UNCONNRules.CheckDfm, TV152UNCONNRules.CheckRawBytes, TV152UNCONNRules.CheckProject),
    Lane('XCONST',   TV152XCONSTRules.Catalog, TV152XCONSTRules.CheckFile, TV152XCONSTRules.CheckDfm, TV152XCONSTRules.CheckRawBytes, TV152XCONSTRules.CheckProject),
    // v154 lanes (1.54.0-alpha): same provider mechanism, alphabetical after the v152 block.
    Lane('DFM',      TV154DFMRules.Catalog, TV154DFMRules.CheckFile, TV154DFMRules.CheckDfm, TV154DFMRules.CheckRawBytes, TV154DFMRules.CheckProject),
    Lane('EXPR',     TV154EXPRRules.Catalog, TV154EXPRRules.CheckFile, TV154EXPRRules.CheckDfm, TV154EXPRRules.CheckRawBytes, TV154EXPRRules.CheckProject),
    Lane('FLOW',     TV154FLOWRules.Catalog, TV154FLOWRules.CheckFile, TV154FLOWRules.CheckDfm, TV154FLOWRules.CheckRawBytes, TV154FLOWRules.CheckProject),
    Lane('SCHEMA',   TV154SCHEMARules.Catalog, TV154SCHEMARules.CheckFile, TV154SCHEMARules.CheckDfm, TV154SCHEMARules.CheckRawBytes, TV154SCHEMARules.CheckProject),
    Lane('SQL',      TV154SQLRules.Catalog, TV154SQLRules.CheckFile, TV154SQLRules.CheckDfm, TV154SQLRules.CheckRawBytes, TV154SQLRules.CheckProject),
    // v156 lanes (1.56.0-alpha): same provider mechanism, alphabetical after the v154 block. Scaffolds: no rule declared yet.
    Lane('FACTA',  TV156FACTARules.Catalog, TV156FACTARules.CheckFile, TV156FACTARules.CheckDfm, TV156FACTARules.CheckRawBytes, TV156FACTARules.CheckProject),
    Lane('G32',    TV156G32Rules.Catalog, TV156G32Rules.CheckFile, TV156G32Rules.CheckDfm, TV156G32Rules.CheckRawBytes, TV156G32Rules.CheckProject),
    Lane('MEMA',   TV156MEMARules.Catalog, TV156MEMARules.CheckFile, TV156MEMARules.CheckDfm, TV156MEMARules.CheckRawBytes, TV156MEMARules.CheckProject),
    Lane('MEMB',   TV156MEMBRules.Catalog, TV156MEMBRules.CheckFile, TV156MEMBRules.CheckDfm, TV156MEMBRules.CheckRawBytes, TV156MEMBRules.CheckProject),
    Lane('OOA1',   TV156OOA1Rules.Catalog, TV156OOA1Rules.CheckFile, TV156OOA1Rules.CheckDfm, TV156OOA1Rules.CheckRawBytes, TV156OOA1Rules.CheckProject),
    Lane('OOA2',   TV156OOA2Rules.Catalog, TV156OOA2Rules.CheckFile, TV156OOA2Rules.CheckDfm, TV156OOA2Rules.CheckRawBytes, TV156OOA2Rules.CheckProject),
    Lane('OOB1',   TV156OOB1Rules.Catalog, TV156OOB1Rules.CheckFile, TV156OOB1Rules.CheckDfm, TV156OOB1Rules.CheckRawBytes, TV156OOB1Rules.CheckProject),
    Lane('OOB2',   TV156OOB2Rules.Catalog, TV156OOB2Rules.CheckFile, TV156OOB2Rules.CheckDfm, TV156OOB2Rules.CheckRawBytes, TV156OOB2Rules.CheckProject),
    Lane('THR',    TV156THRRules.Catalog, TV156THRRules.CheckFile, TV156THRRules.CheckDfm, TV156THRRules.CheckRawBytes, TV156THRRules.CheckProject)];
end;

procedure BuildDecls;
var
  L   : TList<TV151RuleDecl>;
  Seen: TDictionary<string, Boolean>;
begin
  L:= TList<TV151RuleDecl>.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for var E: TLaneEntry in GLanes do E.Catalog(L);
    // 1.52 BUDGET (D7/D9): the frame's own note, emitted by CheckFile when a rule overran its budget
    L.Add(V151Rule(RULE_SKIPPED_BUDGET_ID, 'other', 'info', RULE_SKIPPED_BUDGET_TITLE));
    GDecls:= L.ToArray;
    GIds:= nil;
    for var D: TV151RuleDecl in GDecls do
      if not Seen.ContainsKey(LowerCase(D.Id)) then
      begin
        Seen.Add(LowerCase(D.Id), True);
        GIds:= GIds + [LowerCase(D.Id)];
      end;
  finally
    Seen.Free;
    L.Free;
  end;
end;

procedure LaneFailed(const ALane, AWhere, APath: string; E: Exception);
begin
  Writeln(ErrOutput, Format('v151 lane %s: %s skipped for %s (%s: %s)', [ALane, AWhere, ExtractFileName(APath), E.ClassName, E.Message]));
end;

{ 1.52 BUDGET: one lane call under the per-rule budget. Skips the call when the lane key
  already overran on this file; drops the findings of every rule (or of the whole call, for
  the lane key) that overran on it. }
function Budgeted(const ALane: string; const ACall: TFunc<TArray<TLintFinding>>): TArray<TLintFinding>;
begin
  Result:= nil;
  if not RuleBudgetBeginCall(ALane) then Exit;
  var Got: TArray<TLintFinding>;
  try
    Got:= ACall();
  finally
    RuleBudgetEndCall;
  end;
  if RuleBudgetIsSkipped(RULE_BUDGET_LANE_PREFIX + ALane) then Exit;
  for var F: TLintFinding in Got do
    if not RuleBudgetIsSkipped(F.RuleId) then Result:= Result + [F];
end;

{ 1.52 BUDGET: closes the file's budget; drops the findings of rules that overran after they
  were collected and adds the file's one rule-skipped-budget note. }
function CloseBudget(const ACtx: TV151FileCtx; ABudgetMs: Integer; const AFindings: TArray<TLintFinding>): TArray<TLintFinding>;
begin
  var Skips: TArray<TRuleBudgetSkip>:= RuleBudgetEndFile;
  if Length(Skips) = 0 then Exit(AFindings);
  Result:= nil;
  for var F: TLintFinding in AFindings do
  begin
    var Dropped: Boolean:= False;
    for var S: TRuleBudgetSkip in Skips do
      if SameText(S.RuleId, F.RuleId) then Dropped:= True;
    if not Dropped then Result:= Result + [F];
  end;
  if not ACtx.Wants(RULE_SKIPPED_BUDGET_ID) then Exit;
  var N: TLintFinding:= Default(TLintFinding);
  N.RuleId   := RULE_SKIPPED_BUDGET_ID;
  N.FilePath := ACtx.Path;
  N.FileId   := ACtx.FileId;
  N.StartLine:= 1;
  N.StartCol := 1;
  N.EndLine  := 1;
  N.EndCol   := 1;
  N.Severity := 'info';
  N.Message  := RuleBudgetNoteMessage(Skips, ABudgetMs);
  Result:= Result + [N];
end;

{ TV151Dispatch }

class function TV151Dispatch.Decls: TArray<TV151RuleDecl>;
begin
  Result:= Copy(GDecls);
end;

class function TV151Dispatch.CatalogRows: TArray<TRuleInfo>;
begin
  Result:= nil;
  for var D: TV151RuleDecl in GDecls do
    if D.Kind = vdkNewRule then
    begin
      var R: TRuleInfo:= Default(TRuleInfo);
      R.Id             := D.Id;
      R.Category       := D.Category;
      R.DefaultSeverity:= D.Severity;
      R.Title          := D.Title;
      R.Source         := 'builtin';
      R.DefaultEnabled := D.Enabled;
      R.Params         := D.Params;
      Result:= Result + [R];
    end;
end;

class function TV151Dispatch.RuleIds: TArray<string>;
begin
  Result:= Copy(GIds);
end;

class function TV151Dispatch.Wants(const ANarrowRule: string): Boolean;
begin
  if Length(GIds) = 0 then Exit(False);
  if ANarrowRule = '' then Exit(True);
  for var Id: string in GIds do
    if SameText(Id, ANarrowRule) then Exit(True);
  Result:= False;
end;

class function TV151Dispatch.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if Length(GIds) = 0 then Exit;
  var BudgetMs: Integer:= RuleBudgetEffectiveMs(ACtx.Cfg.RuleTimeBudgetMs);
  RuleBudgetBeginFile(BudgetMs);
  try
    for var E: TLaneEntry in GLanes do
      try
        Result:= Result + Budgeted(E.Name, function: TArray<TLintFinding> begin Result:= E.OnFile(ACtx); end);
      except  // dl:ok try-except-swallowed@e084 -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
        on X: Exception do LaneFailed(E.Name, 'CheckFile', ACtx.Path, X);
      end;
    Result:= V151Narrow(Result, ACtx.NarrowRule) + CheckRawBytes(ACtx, ACtx.Path) + CheckDfm(ACtx);
    if ACtx.DfmPath <> '' then Result:= Result + CheckRawBytes(ACtx, ACtx.DfmPath);
  finally
    Result:= CloseBudget(ACtx, BudgetMs, Result);
  end;
end;

class function TV151Dispatch.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if (Length(GIds) = 0) or (ACtx.DfmPath = '') then Exit;
  for var E: TLaneEntry in GLanes do
    try
      Result:= Result + Budgeted(E.Name, function: TArray<TLintFinding> begin Result:= E.OnDfm(ACtx); end);
    except  // dl:ok try-except-swallowed@a178 -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
      on X: Exception do LaneFailed(E.Name, 'CheckDfm', ACtx.DfmPath, X);
    end;
  Result:= V151Narrow(Result, ACtx.NarrowRule);
end;

class function TV151Dispatch.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string): TArray<TLintFinding>;
var
  Bytes: TBytes;
begin
  Result:= nil;
  if (Length(GIds) = 0) or (AFilePath = '') then Exit;
  try
    Bytes:= TFile.ReadAllBytes(AFilePath);
  except  // dl:ok try-except-swallowed@1bbf -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
    on X: Exception do
    begin
      LaneFailed('-', 'CheckRawBytes', AFilePath, X);
      Exit;
    end;
  end;
  for var E: TLaneEntry in GLanes do
    try
      Result:= Result + Budgeted(E.Name, function: TArray<TLintFinding> begin Result:= E.OnBytes(ACtx, AFilePath, Bytes); end);
    except  // dl:ok try-except-swallowed@0740 -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
      on X: Exception do LaneFailed(E.Name, 'CheckRawBytes', AFilePath, X);
    end;
  Result:= V151Narrow(Result, ACtx.NarrowRule);
end;

class function TV151Dispatch.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if Length(GIds) = 0 then Exit;
  for var E: TLaneEntry in GLanes do
    try
      Result:= Result + E.OnProj(ACtx);
    except  // dl:ok try-except-swallowed@a704 -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
      on X: Exception do LaneFailed(E.Name, 'CheckProject', ACtx.ProjectPath, X);
    end;
  Result:= V151Narrow(Result, ACtx.NarrowRule);
end;

initialization
  BuildLanes;
  BuildDecls;
  RegisterProviderRules(TV151Dispatch.CatalogRows);

end.
