unit DRagLint.V151.RTLCOLL;

{ Wave v151 lane RTLCOLL -- RTL collection and environment rules (dictionary lookups, string-list objects/sorting, null compare, registry, random seed, elapsed time).
  Scaffold created EMPTY by lane FRAME; lane RTLCOLL owns this unit, its
  DRagLint.V151.RTLCOLL.Support helpers and DRagLint.Fix.V151.RTLCOLL. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane RTLCOLL; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151RTLCOLLRules = class
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
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.TV151FileCtx.Wants, DRagLint.V151.RTLCOLL.AddHits, DRagLint.V151.RTLCOLL.Support.FindDictionaryGetWithoutCheck, DRagLint.V151.RTLCOLL.Support.FindNowForElapsedTime, DRagLint.V151.RTLCOLL.Support.FindNullCompare, DRagLint.V151.RTLCOLL.Support.FindRegistryHklmWrite, DRagLint.V151.RTLCOLL.Support.FindStringListObjectsLeak, DRagLint.V151.RTLCOLL.Support.FindStringListUnsorted, DRagLint.V151.RTLCOLL.Support.MaskSource, DRagLint.V151.RTLCOLL.Support.ReadSourceText</para>
    /// <para>Returns: nil</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.AddHits"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.Support.FindDictionaryGetWithoutCheck"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.Support.FindNowForElapsedTime"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.Support.FindNullCompare"/>
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
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.Catalog"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckRawBytes"/>
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
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.Catalog"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: Default, DRagLint.V151.Api.TV151ProjectCtx.Wants, DRagLint.V151.RTLCOLL.Support.FindFirstRandomCall, DRagLint.V151.RTLCOLL.Support.MaskSource, DRagLint.V151.RTLCOLL.Support.OffsetToLineCol, DRagLint.V151.RTLCOLL.Support.ReadSourceText, DRagLint.V151.RTLCOLL.Support.SeedsRandom, SameText</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.TV151ProjectCtx.Wants"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.Support.FindFirstRandomCall"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.Support.MaskSource"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.Support.OffsetToLineCol"/>
    /// <seealso cref="DRagLint.V151.RTLCOLL.Support.ReadSourceText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.IOUtils
  , DRagLint.V151.RTLCOLL.Support  // dl:ok uses-global-census@2049 -- REVIEWED 2026-11-14 v151 INT: a frame lane unit reads only the rule-id consts of its own Support unit; the census is the intended shape
  ;

const
  { In-place expansion: the elapsed-time check emits under the existing platform rule. }
  HOST_NOW_ELAPSED = 'gettickcount-wraparound';

procedure AddHits(var AList: TArray<TLintFinding>; const ACtx: TV151FileCtx; const AMasked: string;
  const AHits: TArray<TRtlCollHit>; const AId, ASeverity: string);
begin
  for var H: TRtlCollHit in AHits do
  begin
    var F: TLintFinding:= Default(TLintFinding);
    F.RuleId  := AId;
    F.FileId  := ACtx.FileId;
    F.FilePath:= ACtx.Path;
    F.Severity:= ASeverity;
    F.Message := H.Msg;
    OffsetToLineCol(AMasked, H.Offset, F.StartLine, F.StartCol);
    OffsetToLineCol(AMasked, H.Offset + H.Length, F.EndLine, F.EndCol);
    AList:= AList + [F];
  end;
end;

class procedure TV151RTLCOLLRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_DICT_GET, 'bug-patterns', 'warning', 'Dictionary read with no key check -- raises when the key is missing'));
  ADecls.Add(V151Rule(RULE_SL_LEAK, 'bug-patterns', 'warning', 'Object stored in a string list that does not own its objects'));
  ADecls.Add(V151Rule(RULE_SL_UNSORTED, 'bug-patterns', 'warning', 'Find or Duplicates used on a string list that is never sorted'));
  ADecls.Add(V151Rule(RULE_NULL_COMPARE, 'bug-patterns', 'hint', 'Variant compared with Null using = or <> instead of VarIsNull'));
  ADecls.Add(V151Rule(RULE_REG_HKLM, 'platform', 'info', 'Registry write below HKEY_LOCAL_MACHINE'));
  ADecls.Add(V151Rule(RULE_RANDOM, 'security', 'info', 'Random is used but the project never calls Randomize'));
  ADecls.Add(V151Host(HOST_NOW_ELAPSED));
end;

class function TV151RTLCOLLRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  var Text: string:= ReadSourceText(ACtx.Path);
  if Text = '' then Exit;
  var Masked: string:= MaskSource(Text);
  if ACtx.Wants(RULE_DICT_GET) then
    AddHits(Result, ACtx, Masked, FindDictionaryGetWithoutCheck(Masked), RULE_DICT_GET, 'warning');
  if ACtx.Wants(RULE_SL_LEAK) then
    AddHits(Result, ACtx, Masked, FindStringListObjectsLeak(Masked), RULE_SL_LEAK, 'warning');
  if ACtx.Wants(RULE_SL_UNSORTED) then
    AddHits(Result, ACtx, Masked, FindStringListUnsorted(Masked), RULE_SL_UNSORTED, 'warning');
  if ACtx.Wants(RULE_NULL_COMPARE) then
    AddHits(Result, ACtx, Masked, FindNullCompare(Masked), RULE_NULL_COMPARE, 'hint');
  if ACtx.Wants(RULE_REG_HKLM) then
    AddHits(Result, ACtx, Masked, FindRegistryHklmWrite(Masked), RULE_REG_HKLM, 'info');
  if ACtx.Wants(HOST_NOW_ELAPSED) then
    AddHits(Result, ACtx, Masked, FindNowForElapsedTime(Masked), HOST_NOW_ELAPSED, 'warning');
end;

class function TV151RTLCOLLRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@7b75 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151RTLCOLLRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@1eb1 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151RTLCOLLRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_RANDOM) then Exit;
  // one pass: the first Random call of each file; any Randomize / RandSeed in the project silences the rule
  var Firsts: TDictionary<string, string>:= TDictionary<string, string>.Create;
  var Offsets: TDictionary<string, Integer>:= TDictionary<string, Integer>.Create;
  try
    for var P: string in ACtx.FilePaths do
    begin
      if not SameText(TPath.GetExtension(P), '.pas') and not SameText(TPath.GetExtension(P), '.dpr') then Continue;
      var Masked: string:= MaskSource(ReadSourceText(P));
      if SeedsRandom(Masked) then Exit;
      var Off: Integer:= FindFirstRandomCall(Masked);
      if Off >= 0 then
      begin
        Firsts.Add(P, Masked);
        Offsets.Add(P, Off);
      end;
    end;
    for var P in Firsts do
    begin
      var F: TLintFinding:= Default(TLintFinding);
      F.RuleId  := RULE_RANDOM;
      F.FilePath:= P.Key;
      F.Severity:= 'info';
      F.Message := 'Random is called here but no unit of the project calls Randomize or sets RandSeed -- every run gets the same sequence; call Randomize once at start-up (and use a cryptographic generator for secrets)';
      OffsetToLineCol(P.Value, Offsets[P.Key], F.StartLine, F.StartCol);
      F.EndLine:= F.StartLine;
      F.EndCol := F.StartCol + Length('Random');
      Result:= Result + [F];
    end;
  finally
    Offsets.Free;
    Firsts.Free;
  end;
end;

end.
