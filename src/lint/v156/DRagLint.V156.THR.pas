unit DRagLint.V156.THR;

{ Wave v156 (1.56.0-alpha) lane THR-R -- lock-order-inversion (G-05), on the lock sites of DRagLint.Query.LockSites.
  Scaffold created by lane FRAME-1; lane THR-R owns this unit and DRagLint.V156.THR.Support (the analysis).
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v156 lanes reuse the
  DRagLint.V151.Api types). The rule is project-wide (lint-all): the two places of an inversion are in
  different routines, often in different units. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule id of G-05: two places take the same two locks in opposite order.</summary>
  RULE_LOCK_ORDER_INVERSION = 'lock-order-inversion';

type
  /// <summary>Checker entry points of v156 lane THR-R; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156THRRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// Declares lock-order-inversion (bug-patterns, warning, ON by default).</remarks>
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
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop: lock-order-inversion.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>One finding per place where a second lock is taken (directly, or by a called routine) while a
    /// first is held and another place takes the two in the opposite order; nil when none, or when --rule
    /// names another rule.</returns>
    /// <remarks>Silent for locks that are not Exact (locals, parameters, other objects), try-enters, a
    /// re-entered lock, readers on both sides, and two orders under one common gate lock.
    /// See DRagLint.V156.THR.Support.</remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.V156.THR.Support
  ;

const
  CATEGORY = 'bug-patterns';
  SEVERITY = 'warning';
  TITLE    = 'Two locks are taken in opposite order in two places (directly or through a call) -- two threads can deadlock';

class procedure TV156THRRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_LOCK_ORDER_INVERSION, CATEGORY, SEVERITY, TITLE));
end;

class function TV156THRRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV156THRRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV156THRRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV156THRRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if ACtx.Wants(RULE_LOCK_ORDER_INVERSION) then
    Result:= LockOrderInversions(ACtx.Store, ACtx.Cfg, RULE_LOCK_ORDER_INVERSION, SEVERITY);
end;

end.
