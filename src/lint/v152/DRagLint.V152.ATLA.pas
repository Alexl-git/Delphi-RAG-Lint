unit DRagLint.V152.ATLA;

{ Wave v152 (1.52.0-alpha) lane ATLA -- gap-matrix rules set A (architecture-contract-content, implicit-package-import, noreturn-returns, reserved-word-identifier).
  Scaffold created EMPTY by lane FRAME; lane ATLA owns this unit, its
  DRagLint.V152.ATLA.Support helpers and DRagLint.Fix.V152.ATLA. Called only by
  DRagLint.V151.Dispatch (the ONE provider mechanism; v152 lanes reuse the
  DRagLint.V151.Api types). How-to: C:\TEMP\claude\lanes\v152\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v152 lane ATLA; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV152ATLARules = class
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
  System.IOUtils
  , DRagLint.V151.APP.Support  // RULE_CONTRACT_CLASS
  , DRagLint.V152.ATLA.Support
  ;

{ Rule set A of the gap matrix (C:\TEMP\claude\lanes\1501\ATLAS\GAP-MATRIX.md):
    row 75 architecture-contract-content -> an in-place expansion of lane APP's
           contract-unit-declares-class (same purpose; a second id would report
           every class twice): units named by drag-lint.json "contractUnits".
    row 70 implicit-package-import -> new rule.
    row 57 noreturn-returns -> NOT in 1.52: needs an extractor fact
           (docs\INBOX-noreturn-returns-needs-extractor-fact.md).
    backlog B27 reserved-word-identifier -> new rule. }

class procedure TV152ATLARules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_RESERVED_IDENT, 'bug-patterns', 'warning',
    'Reserved word used as a variable, field, parameter, constant or type name (dcc E2029)'));
  ADecls.Add(V151Rule(RULE_IMPLICIT_IMPORT, 'structure', 'warning',
    'Package unit uses a project unit that is not in contains or a required package (W1033)'));
  ADecls.Add(V151Host(RULE_CONTRACT_CLASS));
end;

class function TV152ATLARules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  var Acc:= TList<TLintFinding>.Create;
  try
    if ACtx.Wants(RULE_RESERVED_IDENT) then TAtlaChecks.ReservedIdentifiers(ACtx.Path, Acc);
    if ACtx.Wants(RULE_CONTRACT_CLASS) then
      TAtlaChecks.ContractClasses(ACtx.Path, TAtlaChecks.LoadContractGlobs(ExtractFilePath(ParamStr(0))), Acc);
    if ACtx.Wants(RULE_IMPLICIT_IMPORT) then TAtlaChecks.ImplicitImports(ACtx.Path, '', Acc);
    Result:= if Acc.Count = 0 then nil else Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

class function TV152ATLARules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@6314 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152ATLARules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@1635 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

{ A package's units whose .dpk the per-file search (unit folder and its parent)
  cannot see are checked here, once, from the --project package; the rest were
  already checked per file, so nothing is reported twice. }
class function TV152ATLARules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_IMPLICIT_IMPORT) or (ACtx.ProjectPath = '') then Exit;
  var Dpk: string:= ChangeFileExt(ACtx.ProjectPath, '.dpk');
  if not FileExists(Dpk) then Exit;
  var Acc:= TList<TLintFinding>.Create;
  try
    for var F: string in TAtlaChecks.ContainedFiles(Dpk) do
      if FileExists(F) and not TAtlaChecks.DpkVisibleFrom(F, Dpk) then
        TAtlaChecks.ImplicitImports(F, Dpk, Acc);
    Result:= if Acc.Count = 0 then nil else Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

end.