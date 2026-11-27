unit DRagLint.V156.MEMB;

{ Wave v156 (1.56.0-alpha) lane MEM-B -- fresh-instance-as-argument resolved, class-passed-as-interface (G-11),
  and the stored form of indexof-result-unchecked (rider G-63, an in-place expansion of the .scm rule).
  Helpers and the rule ids: DRagLint.V156.MEMB.Support.
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v156 lanes reuse the
  DRagLint.V151.Api types). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v156 lane MEM-B; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156MEMBRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// Declares fresh-instance-as-argument and class-passed-as-interface (both OFF by default) and the host
    /// indexof-result-unchecked.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>The two OFF rules are computed only when the config or --rule asks for them, and need the project
    /// index: without ACtx.Store they report nothing. The stored form of indexof-result-unchecked needs no index.</remarks>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
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
  DRagLint.V156.MEMB.Support  // dl:ok uses-global-census -- the named constants are the whole contract this unit draws; the unit pair travels together
  ;

const
  CATEGORY_LIFETIME = 'resource-lifetime';
  SEVERITY_INFO = 'info';
  SEVERITY_WARNING = 'warning';

{ Both rules are OFF until measured on real projects (plan 2026-11-27, section 5). fresh-instance-as-argument keeps
  the category and severity it had as a .scm rule. }
class procedure TV156MEMBRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_FRESH_INSTANCE_AS_ARGUMENT, CATEGORY_LIFETIME, SEVERITY_INFO,
    'Freshly created object passed to a parameter that the callee only reads (CWE-401)', False));
  ADecls.Add(V151Rule(RULE_CLASS_PASSED_AS_INTERFACE, CATEGORY_LIFETIME, SEVERITY_WARNING,
    'Object of a reference-counted class passed to an interface parameter', False));
  ADecls.Add(V151Host(RULE_INDEXOF_RESULT_UNCHECKED));
end;

class function TV156MEMBRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;

  { An OFF rule is computed only when --rule names it or the config turns it on. }
  function Wanted(const ARule: string): Boolean;
  begin
    Result:= ACtx.Wants(ARule) and (SameText(ACtx.NarrowRule, ARule) or ACtx.Cfg.ShouldKeep(ARule, True));
  end;

var
  Run: TMembRun;
  Fresh, AsInterface, Stored: Boolean;
begin
  Result     := nil;
  Fresh      := Wanted(RULE_FRESH_INSTANCE_AS_ARGUMENT);
  AsInterface:= Wanted(RULE_CLASS_PASSED_AS_INTERFACE);
  Stored     := ACtx.Wants(RULE_INDEXOF_RESULT_UNCHECKED);
  if not (Fresh or AsInterface or Stored) then Exit;
  Run:= TMembRun.Create(ACtx);
  try
    if Fresh or AsInterface then Run.CheckArguments(Fresh, AsInterface);
    if Stored then Run.CheckStoredIndexes;
    Result:= Run.Findings;
  finally
    Run.Free;
  end;
end;

class function TV156MEMBRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@32bc -- REVIEWED 2026-11-26 v156 MEM-B: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156MEMBRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@39fa -- REVIEWED 2026-11-26 v156 MEM-B: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156MEMBRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@4ae8 -- REVIEWED 2026-11-26 v156 MEM-B: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

end.
