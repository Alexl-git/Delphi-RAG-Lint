unit DRagLint.V151.EXC;

{ Wave v151 lane EXC -- exception and inherited-call rules (handler order, freed exceptions, inherited order and target, message handlers, destroy called directly).
  Scaffold created EMPTY by lane FRAME; lane EXC owns this unit, its
  DRagLint.V151.EXC.Support helpers and DRagLint.Fix.V151.EXC. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane EXC; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151EXCRules = class
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
  DRagLint.V151.EXC.Support
  , DRagLint.Diagnostics.ParseCache
  ;

class procedure TV151EXCRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule('except-handler-order', 'bug-patterns', 'warning', 'A later exception handler is shadowed by an earlier one'));
  ADecls.Add(V151Rule('exception-freed', 'bug-patterns', 'warning', 'Exception object freed by hand in its handler'));
  // OFF by default: 4 of 5 findings over the CLIENT/SERVER/LOADER/YADF copies were TThread descendants, where inherited Destroy
  // must run first (it waits for Execute). Tighten later: exempt classes with a TThread ancestor, then turn ON.
  ADecls.Add(V151Rule('inherited-order', 'bug-patterns', 'warning', 'Destructor calls inherited before freeing its members', False));
  ADecls.Add(V151Rule('inherited-wrong-method', 'bug-patterns', 'warning', 'Override calls inherited of a different method'));
  ADecls.Add(V151Rule('message-handler-without-inherited', 'bug-patterns', 'warning', 'Message handler without inherited or default handler'));
  ADecls.Add(V151Rule('inherited-without-ancestor', 'bug-patterns', 'warning', 'inherited in a method no ancestor declares'));
  ADecls.Add(V151Rule('override-only-inherited', 'dead-code', 'hint', 'Override that only calls inherited'));
  ADecls.Add(V151Rule('destroy-called-directly', 'bug-patterns', 'warning', 'Destroy called instead of Free'));
  ADecls.Add(V151Rule('missing-inherited-call', 'bug-patterns', 'warning', 'Component hook override without inherited'));
end;

class function TV151EXCRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  PF  : TParsedFile;
  Run : TExcRun;
  Ctx : TV151FileCtx;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(ACtx.Path);
  if PF.Tree = nil then Exit;
  Ctx:= ACtx;
  Run:= TExcRun.Create(ACtx.Path, PF.Src, ACtx.Store, ACtx.LibStore, ACtx.FileId,
    function(S: string): Boolean begin Result:= Ctx.Wants(S); end);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

class function TV151EXCRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@f561 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151EXCRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@0b92 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151EXCRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@a3e4 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

end.
