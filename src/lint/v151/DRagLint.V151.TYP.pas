unit DRagLint.V151.TYP;

{ Wave v151 lane TYP -- typing and ownership rules (unrelated casts, Self as interface in constructors, nil-safe destructors, field free without nil).
  Scaffold created EMPTY by lane FRAME; lane TYP owns this unit, its
  DRagLint.V151.TYP.Support helpers and DRagLint.Fix.V151.TYP. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane TYP; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151TYPRules = class
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
  DRagLint.V151.TYP.Support
  ;

class procedure TV151TYPRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_UNRELATED_CAST, 'bug-patterns', 'warning', 'Hard cast between two classes neither of which descends from the other'));
  ADecls.Add(V151Rule(RULE_SELF_INTF_CTOR, 'bug-patterns', 'warning', 'Self handed out as an interface while construction can still free the object'));
  ADecls.Add(V151Rule(RULE_DTOR_NIL_SAFE, 'resource-lifetime', 'warning', 'Destructor dereferences a field that a raising constructor may have left nil'));
  ADecls.Add(V151Rule(RULE_FREE_WITHOUT_NIL, 'resource-lifetime', 'warning', 'Field freed outside the destructor keeps its dangling reference'));
  ADecls.Add(V151Rule(RULE_OWNERSHIP_UNCLEAR, 'resource-lifetime', 'hint', 'Field created by the class, never freed by it and handed out -- ownership unclear', False));
end;

class function TV151TYPRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= TypCheckFile(ACtx);
end;

class function TV151TYPRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@a8da -- REVIEWED 2026-11-13 v151 TYP: dispatcher signature; lane TYP has no form, raw-byte or project-wide check
begin
  Result:= nil;
end;

class function TV151TYPRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@075e -- REVIEWED 2026-11-13 v151 TYP: dispatcher signature; lane TYP has no form, raw-byte or project-wide check
begin
  Result:= nil;
end;

class function TV151TYPRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@9248 -- REVIEWED 2026-11-13 v151 TYP: dispatcher signature; lane TYP has no form, raw-byte or project-wide check
begin
  Result:= nil;
end;

end.
