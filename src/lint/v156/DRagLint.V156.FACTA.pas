unit DRagLint.V156.FACTA;

{ Wave v156 (1.56.0-alpha) lane FA-1 -- noreturn-contract (G-13), on the stored noreturn fact (B1).
  Wiki: docs\wiki\v156-noreturn-contract.md. Helpers and the rule id: DRagLint.V156.FACTA.Support.
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
  /// <summary>Checker entry points of v156 lane FA-1; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156FACTARules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// Declares noreturn-contract (bug-patterns, warning, ON).</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>The noreturn-contract findings: code after a call to a noreturn routine (warning) and a
    /// routine that never returns but is not declared noreturn (hint); nil when none, and always
    /// nil without a project index.</returns>
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
  DRagLint.V156.FACTA.Support  // dl:ok uses-global-census@2613 -- the named constants are the whole contract this unit draws; the unit pair travels together
  ;

const
  CATEGORY_BUG = 'bug-patterns';
  SEVERITY_WARNING = 'warning';

class procedure TV156FACTARules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_NORETURN_CONTRACT, CATEGORY_BUG, SEVERITY_WARNING, 'Code after a call to a noreturn routine, or a routine that never returns and is not declared noreturn'));
end;

class function TV156FACTARules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Run: TNoReturnRun;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_NORETURN_CONTRACT) then Exit;
  Run:= TNoReturnRun.Create(ACtx);
  try
    Run.Check;
    Result:= Run.Findings;
  finally
    Run.Free;
  end;
end;

class function TV156FACTARules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@c93d -- REVIEWED 2026-11-26 v156 FA-1: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156FACTARules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@b5be -- REVIEWED 2026-11-26 v156 FA-1: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156FACTARules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@52e5 -- REVIEWED 2026-11-26 v156 FA-1: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

end.
