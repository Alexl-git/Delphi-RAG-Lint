unit DRagLint.V152.RTTI5;

{ Wave v152 (1.52.0-alpha) lane RTTI5 -- rtti-unavailable sub-check 5 (anonymous inline array / set types).
  Scaffold created EMPTY by lane FRAME; lane RTTI5 owns this unit, its
  DRagLint.V152.RTTI5.Support helpers and DRagLint.Fix.V152.RTTI5. Called only by
  DRagLint.V151.Dispatch (the ONE provider mechanism; v152 lanes reuse the
  DRagLint.V151.Api types). How-to: C:\TEMP\claude\lanes\v152\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.IOUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v152 lane RTTI5; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV152RTTI5Rules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>
    /// Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Host</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Host"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: Default, DRagLint.Lint.Config.TLintConfig.ShouldKeep, DRagLint.V152.RTTI5.Support.AnonymousFieldMessage, DRagLint.V152.RTTI5.Support.FindAnonymousFieldTypes, ExtractFileExt, SameText</para>
    /// <para>Catches: EEncodingError (swallowed); EInOutError (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ShouldKeep"/>
    /// <seealso cref="DRagLint.V152.RTTI5.Support.AnonymousFieldMessage"/>
    /// <seealso cref="DRagLint.V152.RTTI5.Support.FindAnonymousFieldTypes"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.Catalog"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckDfm"/>
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
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.Catalog"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckRawBytes"/>
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
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.Catalog"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.Catalog"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.RTTI5.TV152RTTI5Rules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.Lint.RttiRules
  , DRagLint.V152.RTTI5.Support
  ;

class procedure TV152RTTI5Rules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Host(RTTI_UNAVAILABLE_RULE));
end;

class function TV152RTTI5Rules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  { rtti-unavailable is OFF by default: an explicit --rule or a config that enables it opts in. }
  if not (SameText(ACtx.NarrowRule, RTTI_UNAVAILABLE_RULE) or ACtx.Cfg.ShouldKeep(RTTI_UNAVAILABLE_RULE, True)) then Exit;
  if not SameText(ExtractFileExt(ACtx.Path), '.pas') or not TFile.Exists(ACtx.Path) then Exit;
  var Text: string;
  try
    Text:= TFile.ReadAllText(ACtx.Path);
  except  // dl:ok try-except-swallowed@0290 -- REVIEWED 2026-11-17 v152 RTTI5: an unreadable file is skipped, as in CollectRttiUnavailable
    on EInOutError do Exit;
    on EEncodingError do Exit;
  end;
  var Found: TArray<TAnonField>:= FindAnonymousFieldTypes(Text);
  SetLength(Result, Length(Found));
  for var I: Integer:= 0 to High(Found) do
  begin
    var F: TLintFinding:= Default(TLintFinding);
    F.RuleId    := RTTI_UNAVAILABLE_RULE;
    F.FileId    := ACtx.FileId;
    F.FilePath  := ACtx.Path;
    F.StartLine := Found[I].Line;
    F.StartCol  := Found[I].Col;
    F.EndLine   := Found[I].Line;
    F.EndCol    := Found[I].Col;
    F.Severity  := 'warning';
    F.SymbolName:= Found[I].ClassName + '.' + Found[I].Names;
    F.Message   := AnonymousFieldMessage(Found[I]);
    Result[I]:= F;
  end;
end;
class function TV152RTTI5Rules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@c90d -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152RTTI5Rules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@147a -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152RTTI5Rules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@f492 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

end.
