unit DRagLint.V152.ATLB;

{ Wave v152 (1.52.0-alpha) lane ATLB -- gap-matrix rules set B (component-create-without-override, debug-display-placeholder, member-could-be-private).
  debug-display-placeholder landed in 1.52 lane BK-ATTRRULES (B48) on the attributes index fact (B09).
  Scaffold created EMPTY by lane FRAME; lane ATLB owns this unit, its
  DRagLint.V152.ATLB.Support helpers and DRagLint.Fix.V152.ATLB. Called only by
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
  /// <summary>Checker entry points of v152 lane ATLB; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV152ATLBRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>
    /// Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Rule</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Rule"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.Lint.Config.TLintConfig.IsEnabled, DRagLint.V151.Api.TV151FileCtx.Wants, DRagLint.V152.ATLB.Support.TDebugDisplayCheck.Check, SameText</para>
    /// <para>Returns: nil; TDebugDisplayCheck.Check(ACtx.Store, ACtx.LibStore, ACtx.FileId, ACtx.Path, RULE_DEBUG_DISPLAY)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.IsEnabled"/>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
    /// <seealso cref="DRagLint.V152.ATLB.Support.TDebugDisplayCheck.Check"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckDfm"/>
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
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckRawBytes"/>
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
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.ATLB.TV152ATLBRules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindRefsNamingInFiles, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Lint.Config.TLintConfig.IsEnabled, DRagLint.Lint.SharedScope.NoteUndecidedSite, DRagLint.Lint.SharedScope.TSharedScope.Create, DRagLint.Lint.SharedScope.TSharedScope.Judge, DRagLint.V151.Api.TV151ProjectCtx.Wants, DRagLint.V152.ATLB.Support.TMemberPrivacy.Find, LowerCase, SameText</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindRefsNamingInFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.IsEnabled"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.NoteUndecidedSite"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.V152.ATLB.Support
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.SharedScope  { 1.52 BK-XPROJ: a unit another project compiles is judged there too }
  ;

const
  RULE_MEMBER_PRIVATE = 'member-could-be-private';
  RULE_DEBUG_DISPLAY  = 'debug-display-placeholder';  { 1.52 BK-ATTRRULES (B48), on the attributes fact }

class procedure TV152ATLBRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_MEMBER_PRIVATE, 'project-wide', 'hint',
    'Public member is only referenced inside its own unit; it could be private', False));
  ADecls.Add(V151Rule(RULE_DEBUG_DISPLAY, 'bug-patterns', 'warning',
    'DebuggerDisplay attribute placeholder names no member of the decorated type', False));
end;

class function TV152ATLBRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_DEBUG_DISPLAY) then Exit;
  if not (SameText(ACtx.NarrowRule, RULE_DEBUG_DISPLAY) or ACtx.Cfg.IsEnabled(RULE_DEBUG_DISPLAY)) then Exit;
  Result:= TDebugDisplayCheck.Check(ACtx.Store, ACtx.LibStore, ACtx.FileId, ACtx.Path, RULE_DEBUG_DISPLAY);
end;

class function TV152ATLBRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@8d01 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152ATLBRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@32ac -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152ATLBRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_MEMBER_PRIVATE) then Exit;
  if not (SameText(ACtx.NarrowRule, RULE_MEMBER_PRIVATE) or ACtx.Cfg.IsEnabled(RULE_MEMBER_PRIVATE)) then Exit;
  if ACtx.Store = nil then Exit;
  { 1.52 BK-XPROJ (FPM finding): a member of a unit another project also compiles may be
    called from that project (COMMON Pipes.Chunks WriteChunk from SERVER). The peer's index
    answers; a peer that cannot answer withholds the finding (svUndecided). }
  var Shared: TSharedScope:= TSharedScope.Create(ACtx.Store, ACtx.SiblingStore, ACtx.SiblingNames);
  try
    for var F: TLintFinding in TMemberPrivacy.Find(ACtx.Store, ACtx.LibStore, RULE_MEMBER_PRIVATE) do
    begin
      var Low : string:= LowerCase(F.SymbolName);
      var Decl: string:= F.FilePath;
      var Projs: string;
      var Verdict: TSharedVerdict:= Shared.Judge(Decl,
        function(const S: ISymbolStore): Boolean
        begin
          Result:= False;
          for var R in S.FindRefsNamingInFiles(S.GetAllFileIds, [Low]) do
            if not SameText(S.GetFilePath(R.FileId), Decl) then Exit(True);
        end, Projs);
      if Verdict = svUndecided then NoteUndecidedSite(Decl, F.StartLine, RULE_MEMBER_PRIVATE);
      if Verdict in [svUsedElsewhere, svUndecided] then Continue;
      Result:= Result + [F];
    end;
  finally
    Shared.Free;
  end;
end;

end.
