unit DRagLint.V156.MEMA;

{ Wave v156 (1.56.0-alpha) lane MEM-A -- container-items-leak (G-01).
  Lane MEM-A owns this unit and DRagLint.V156.MEMA.Support (the behaviour is described there).
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v156 lanes reuse the
  DRagLint.V151.Api types). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule id of G-01: fresh objects added to a local container that does not own them.</summary>
  RULE_CONTAINER_ITEMS_LEAK = 'container-items-leak';

type
  /// <summary>Checker entry points of v156 lane MEM-A; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156MEMARules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// Declares container-items-leak: category resource-lifetime, warning, ON by default.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas: container-items-leak in every routine of the file.</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>One finding per leaking local container, at its first fresh addition; nil when none,
    /// when the run does not ask for the rule, or when the file has no parse tree.</returns>
    /// <remarks>A class the file does not declare is looked up in Store, then LibStore; with both nil
    /// such a class is unknown and its additions do not report.</remarks>
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
  DRagLint.V156.MEMA.Support
  , DRagLint.Diagnostics.ParseCache
  ;

const
  RULE_CATEGORY = 'resource-lifetime';
  RULE_SEVERITY = 'warning';
  RULE_TITLE    = 'Objects added to a container that does not own them are never freed';

class procedure TV156MEMARules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_CONTAINER_ITEMS_LEAK, RULE_CATEGORY, RULE_SEVERITY, RULE_TITLE));
end;

class function TV156MEMARules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  PF : TParsedFile;
  Run: TMemaRun;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_CONTAINER_ITEMS_LEAK) then Exit;
  PF:= TAstParseCache.Get(ACtx.Path);
  if PF.Tree = nil then Exit;
  Run:= TMemaRun.Create(ACtx.Path, PF.Src, ACtx.Store, ACtx.LibStore);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

class function TV156MEMARules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@b41c -- REVIEWED 2026-11-26 v156 MEM-A: signature fixed by the v151 lane frame hook; this lane has no check of this kind
begin
  Result:= nil;
end;

class function TV156MEMARules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@bf68 -- REVIEWED 2026-11-26 v156 MEM-A: signature fixed by the v151 lane frame hook; this lane has no check of this kind
begin
  Result:= nil;
end;

class function TV156MEMARules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@d375 -- REVIEWED 2026-11-26 v156 MEM-A: signature fixed by the v151 lane frame hook; this lane has no check of this kind
begin
  Result:= nil;
end;

end.
