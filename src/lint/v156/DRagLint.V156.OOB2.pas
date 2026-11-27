unit DRagLint.V156.OOB2;

{ Wave v156 (1.56.0-alpha) lane OOB-2 -- dunitx-attribute-hygiene, variant-in-loop (G-26 G-30; rider G-62).
  Scaffold created EMPTY by lane FRAME-1; lane OOB-2 owns this unit and DRagLint.V156.OOB2.Support.
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v156 lanes reuse the
  DRagLint.V151.Api types). The rule ids below are fixed by the 1.56 plan; Catalog declares
  them when the lane implements them, so the catalog counts do not move before that. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v156 lane OOB-2; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156OOB2Rules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
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
  DRagLint.V156.OOB2.Support
  ;

const
  CATEGORY_BUG = 'bug-patterns';
  CATEGORY_REFACTORING = 'refactoring';
  SEVERITY_WARNING = 'warning';
  SEVERITY_HINT = 'hint';

class procedure TV156OOB2Rules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_DUNITX_ATTRIBUTE_HYGIENE, CATEGORY_BUG, SEVERITY_WARNING, 'DUnitX fixture without a test, [Ignore] without a reason, or [Setup] / [TearDown] used twice in one fixture'));
  ADecls.Add(V151Rule(RULE_VARIANT_IN_LOOP, CATEGORY_REFACTORING, SEVERITY_HINT, 'Arithmetic on a Variant inside a loop (late-bound calls)', False));
end;

class function TV156OOB2Rules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if ACtx.Wants(RULE_DUNITX_ATTRIBUTE_HYGIENE) then Result:= Result + TOob2Dunitx.Check(ACtx);
  { OFF unless the config or --rule asks for it: computed only then }
  if ACtx.Wants(RULE_VARIANT_IN_LOOP) and (SameText(ACtx.NarrowRule, RULE_VARIANT_IN_LOOP) or ACtx.Cfg.ShouldKeep(RULE_VARIANT_IN_LOOP, True)) then
    Result:= Result + TOob2Variant.Check(ACtx);
end;

class function TV156OOB2Rules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@281c -- REVIEWED 2026-11-26 v156 OOB2: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156OOB2Rules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@d23f -- REVIEWED 2026-11-26 v156 OOB2: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156OOB2Rules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@d2f9 -- REVIEWED 2026-11-26 v156 OOB2: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

end.
