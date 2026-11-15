unit DRagLint.V151.DFMB;

{ Wave v151 lane DFMB -- form-file data-binding rules B (circular datasource, duplicate binding, master fields, field types, required fields, disallowed properties).
  Scaffold created EMPTY by lane FRAME; lane DFMB owns this unit, its
  DRagLint.V151.DFMB.Support helpers and DRagLint.Fix.V151.DFMB. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane DFMB; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151DFMBRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling TEXT form file: dfm-circular-datasource, dfm-duplicate-binding,
    /// dfm-master-without-fields, dfm-control-field-type-mismatch, dfm-required-field-without-control (persistent fields,
    /// i.e. field objects in the form file; runtime fields are not seen) and disallowed-dfm-property (policy entries of
    /// the config block disallowed.names whose name starts with dfm: -- dfm:TClass.Prop, dfm:*.Prop, dfm:TClass.Prop=Value).
    /// Binary form files are skipped. Query-like datasets (SQL, CommandText, Params, ProviderName) never get
    /// dfm-master-without-fields because their parameters link by name.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.V151.DFMB.Support  // dl:ok uses-global-census@e1ef -- REVIEWED 2026-11-14 v151 INT: a frame lane unit reads only the rule-id consts of its own Support unit; the census is the intended shape
  ;

class procedure TV151DFMBRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_CIRCULAR, 'bug-patterns', 'warning',
    'Master/detail or data source links in the form file form a cycle'));
  ADecls.Add(V151Rule(RULE_DUPBIND, 'bug-patterns', 'warning',
    'Two input controls in the form file are bound to the same data source and field'));
  ADecls.Add(V151Rule(RULE_MASTER, 'bug-patterns', 'warning',
    'Dataset has a MasterSource but no MasterFields in the form file'));
  ADecls.Add(V151Rule(RULE_TYPEMISM, 'bug-patterns', 'warning',
    'Data-aware control does not suit the type of the persistent field it is bound to'));
  ADecls.Add(V151Rule(RULE_REQUIRED, 'bug-patterns', 'warning',
    'Required persistent field has no visible data-aware control'));
  ADecls.Add(V151Rule(RULE_DISALLOW, 'policy', 'warning',
    'Form-file property forbidden by the project policy table (disallowed.names entries starting dfm:)'));
end;

class function TV151DFMBRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@5d9e -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151DFMBRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Ctx: TV151FileCtx;
begin
  Result:= nil;
  if ACtx.DfmPath = '' then Exit;
  Ctx:= ACtx;
  Result:= TDfmBChecker.Run(ACtx.Cfg, ACtx.DfmPath,
    function(AId: string): Boolean
    begin
      Result:= Ctx.Wants(AId);
    end);
end;

class function TV151DFMBRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@83f7 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151DFMBRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@43bd -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

end.
