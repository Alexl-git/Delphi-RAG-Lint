unit DRagLint.V152.PROJ2;

{ Wave v152 (1.52.0-alpha) lane PROJ2 -- unit-used-by-no-unit (ruling B9e).
  Scaffold created EMPTY by lane FRAME; lane PROJ2 owns this unit, its
  DRagLint.V152.PROJ2.Support helpers and DRagLint.Fix.V152.PROJ2. Called only by
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
  /// <summary>Checker entry points of v152 lane PROJ2; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV152PROJ2Rules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>
    /// Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Host, DRagLint.V151.Api.V151Rule</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Host"/>
    /// <seealso cref="DRagLint.V151.Api.V151Rule"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.Catalog"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.Catalog"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.Catalog"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop: unit-used-by-no-unit (B9e)
    /// and the outside-roots half of unit-not-in-dpr (O05).</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// The O05 half runs only with --project: an unscoped run already hands the host check every indexed file.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.TV151ProjectCtx.Wants, DRagLint.V152.PROJ2.Support.FindUnitsUsedByNoUnit, DRagLint.V152.PROJ2.Support.FindUnlistedClosureOutsideRoots</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.TV151ProjectCtx.Wants"/>
    /// <seealso cref="DRagLint.V152.PROJ2.Support.FindUnitsUsedByNoUnit"/>
    /// <seealso cref="DRagLint.V152.PROJ2.Support.FindUnlistedClosureOutsideRoots"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.Catalog"/>
    /// <seealso cref="DRagLint.V152.PROJ2.TV152PROJ2Rules.CheckDfm"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.V152.PROJ2.Support
  ;

class procedure TV152PROJ2Rules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  { Ruling B9e: ON, warning (plan D7). }
  ADecls.Add(V151Rule(PROJ2_RULE_UNIT_USED_BY_NO_UNIT, 'project-wide', 'warning',
    'Unit is listed only by the program file and nothing reaches it (no uses, no reference, no self-registration)'));
  { O05: unit-not-in-dpr also covers closure units outside the walked roots. }
  ADecls.Add(V151Host(PROJ2_RULE_UNIT_NOT_IN_DPR));
end;

class function TV152PROJ2Rules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@008a -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152PROJ2Rules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@1ce2 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152PROJ2Rules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@1db0 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152PROJ2Rules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if ACtx.Wants(PROJ2_RULE_UNIT_USED_BY_NO_UNIT) then
    Result:= Result + FindUnitsUsedByNoUnit(ACtx.Store);
  if ACtx.Wants(PROJ2_RULE_UNIT_NOT_IN_DPR) then
    Result:= Result + FindUnlistedClosureOutsideRoots(ACtx.Store, ACtx.ProjectPath, ACtx.FilePaths);
end;

end.
