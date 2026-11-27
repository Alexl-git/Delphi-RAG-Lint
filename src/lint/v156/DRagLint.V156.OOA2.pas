unit DRagLint.V156.OOA2;

{ Wave v156 (1.56.0-alpha) lane OOA-2 -- abstract-method-not-overridden, handler-type-never-raised (G-16 G-22).
  Scaffold created EMPTY by lane FRAME-1; lane OOA-2 owns this unit and DRagLint.V156.OOA2.Support.
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

const
  /// <summary>Rule id of G-16; not in the catalog until Catalog declares it.</summary>
  RULE_ABSTRACT_METHOD_NOT_OVERRIDDEN = 'abstract-method-not-overridden';
  /// <summary>Rule id of G-22; not in the catalog until Catalog declares it.</summary>
  RULE_HANDLER_TYPE_NEVER_RAISED = 'handler-type-never-raised';

type
  /// <summary>Checker entry points of v156 lane OOA-2; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156OOA2Rules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// Both rules are ON by default.</remarks>
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
  DRagLint.V156.OOA2.Support  // dl:ok uses-global-census@f2aa -- REVIEWED 2026-11-26 v156 OOA-2: the Support unit of the lane holds the checks; the pair travels together
  ;

class procedure TV156OOA2Rules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_ABSTRACT_METHOD_NOT_OVERRIDDEN, 'bug-patterns', 'warning', 'Class leaves an inherited abstract method open'));
  ADecls.Add(V151Rule(RULE_HANDLER_TYPE_NEVER_RAISED, 'bug-patterns', 'warning', 'Exception handler for a project type that nothing raises or builds'));
end;

class function TV156OOA2Rules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Found: TList<TLintFinding>;
begin
  Result:= nil;
  Found := TList<TLintFinding>.Create;
  try
    if ACtx.Wants(RULE_ABSTRACT_METHOD_NOT_OVERRIDDEN) then Found.AddRange(CheckAbstractNotOverridden(ACtx));
    if ACtx.Wants(RULE_HANDLER_TYPE_NEVER_RAISED) then Found.AddRange(CheckHandlerNeverRaised(ACtx));
    if Found.Count > 0 then Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

class function TV156OOA2Rules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@c7de -- REVIEWED 2026-11-26 v156 OOA-2: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156OOA2Rules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@16ce -- REVIEWED 2026-11-26 v156 OOA-2: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV156OOA2Rules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@cb34 -- REVIEWED 2026-11-26 v156 OOA-2: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

end.
