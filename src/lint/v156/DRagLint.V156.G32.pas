unit DRagLint.V156.G32;

{ Wave v156 (1.56.0-alpha) lane G32 -- math-single-overload (G-32).
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v156 lanes reuse the
  DRagLint.V151.Api types). The rule is OFF by default (opt in with --rule or the config). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v156 lane G32; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.</remarks>
  TV156G32Rules = class
  public
    /// <summary>Declares every rule id this lane may emit.</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up; must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the sibling form file; the lane has none.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <returns>Always nil.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Raw-bytes check; the lane has none.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from.</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Always nil.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check; the lane has none.</summary>
    /// <param name="ACtx">The project.</param>
    /// <returns>Always nil.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.V156.G32.Support  // dl:ok uses-global-census -- REVIEWED v156 G32: the Support unit of the lane holds the check; the pair travels together
  ;

const
  RULE_MATH_SINGLE_OVERLOAD = 'math-single-overload';

class procedure TV156G32Rules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_MATH_SINGLE_OVERLOAD, 'bug-patterns', 'warning', 'Max / Min / Power on Single arguments and literals binds the Single overload; the result feeds a Double / Extended variable', False));
end;

class function TV156G32Rules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_MATH_SINGLE_OVERLOAD) then Exit;
  if not (SameText(ACtx.NarrowRule, RULE_MATH_SINGLE_OVERLOAD) or ACtx.Cfg.IsEnabled(RULE_MATH_SINGLE_OVERLOAD)) then Exit;
  Result:= TG32Checks.Check(ACtx.Store, ACtx.FileId, ACtx.Path, RULE_MATH_SINGLE_OVERLOAD);
end;

class function TV156G32Rules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@281c -- REVIEWED 2026-11-27 v156 G32: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156G32Rules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@d23f -- REVIEWED 2026-11-27 v156 G32: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156G32Rules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@d2f9 -- REVIEWED 2026-11-27 v156 G32: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

end.
