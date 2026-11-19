unit DRagLint.Query.HappensBefore.Render;

{ drag-lint 1.52 -- lane HBSKEL: check-init answer rendering (JSON, text, exit code).
  Scaffold created EMPTY by lane FRAME; lane HBSKEL owns it.
  Shapes: spec docs\superpowers\specs\2026-11-17-happens-before-design.md section 2.1 as amended by
  rulings HB2 (literals, writer rows with fired_by / callers) and HB7 (exit 0 / 1 / 2). }

interface

uses
  DRagLint.Query.HappensBefore.Types
  ;

/// <summary>The answer as one JSON document: {target, verdict, proven, scope, summary, reasons, uses,
/// writers, roots, limits, budget {routines, ms, exhausted, max_s, timed_out}}.</summary>
/// <param name="pAnswer">The answer to render.</param>
/// <returns>Compact JSON text (no trailing newline).</returns>
/// <remarks>
/// Every key is always present (empty arrays, 0, '' and false included) so tools never
/// test for absence. Literals come from the Types code functions.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CheckInit.RunCheckInit (DRagLint.CLI.CheckInit.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas), DRagLint.Query.HoverModel.BuildSetBy (DRagLint.Query.HoverModel.pas)</para>
/// <para>Calls: DRagLint.Query.HappensBefore.Render.ReasonsJson, DRagLint.Query.HappensBefore.Render.StringsJson, DRagLint.Query.HappensBefore.Render.TargetJson, DRagLint.Query.HappensBefore.Render.UseJson, DRagLint.Query.HappensBefore.Render.WriterJson, DRagLint.Query.HappensBefore.Types.ScopeCode, DRagLint.Query.HappensBefore.Types.VerdictCode</para>
/// <para>Returns: Root.ToJSON</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.ReasonsJson"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.StringsJson"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.TargetJson"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.UseJson"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.WriterJson"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbAnswerJson(const pAnswer: THbAnswer): string;

/// <summary>The answer as the text layout of spec 2.1: target line, the use line (one use),
/// verdict line, writers, witness, why-not line, uses summary (several uses), reasons, limits.</summary>
/// <param name="pAnswer">The answer to render.</param>
/// <param name="pExplain">True adds the `roots:` line and per-use reasons.</param>
/// <returns>CRLF-separated lines, ending in a line break.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Render.WriteHbAnswer (DRagLint.Query.HappensBefore.Render.pas)</para>
/// <para>Calls: DRagLint.Query.HappensBefore.Render.ReasonsText, DRagLint.Query.HappensBefore.Render.SiteText, DRagLint.Query.HappensBefore.Render.WriterText, DRagLint.Query.HappensBefore.Types.TargetKindCode, DRagLint.Query.HappensBefore.Types.VerdictCode, ExtractFileName, Format, IntToStr, StringOfChar</para>
/// <para>Returns: SB.ToString</para>
/// <para>Complexity: 22 (cyclomatic, outer body), 62 lines (full implementation)</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.ReasonsText"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.SiteText"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.WriterText"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Types.TargetKindCode"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Types.VerdictCode"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbAnswerText(const pAnswer: THbAnswer; pExplain: Boolean): string;  // dl:ok unused-public-symbol@bcad -- REVIEWED 2026-11-17 v152 HBSKEL: frozen contract; the pure text form for HBHOVER / HBIDE, WriteHbAnswer is its stdout wrapper

/// <summary>Writes HbAnswerText to stdout.</summary>
/// <param name="pAnswer">The answer to render.</param>
/// <param name="pExplain">True adds the `roots:` line and per-use reasons.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CheckInit.RunCheckInit (DRagLint.CLI.CheckInit.pas)</para>
/// <para>Calls: DRagLint.Query.HappensBefore.Render.HbAnswerText, Write</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.HbAnswerText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure WriteHbAnswer(const pAnswer: THbAnswer; pExplain: Boolean);

/// <summary>The process exit code of an answer (ruling HB7).</summary>
/// <param name="pAnswer">The answer.</param>
/// <returns>0 when the headline verdict is SET, else 1. Errors (exit 2) never reach an answer.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CheckInit.RunCheckInit (DRagLint.CLI.CheckInit.pas)</para>
/// <para>Returns: if pAnswer.Verdict = hvSet then 0</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbExitCode(const pAnswer: THbAnswer): Integer;

implementation

uses
  System.SysUtils
, System.JSON
  ;

const
  MAX_TOP_CALLERS = 3;

function SiteJson(const pSite: THbSite): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('file', pSite.FileName);
  Result.AddPair('line', TJSONNumber.Create(pSite.Line));
  Result.AddPair('col', TJSONNumber.Create(pSite.Col));
  Result.AddPair('routine', pSite.Routine);
end;

function ReasonsJson(const pReasons: TArray<THbReason>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var R in pReasons do Result.Add(ReasonCode(R));
end;

function StringsJson(const pItems: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pItems do Result.Add(S);
end;

function TargetJson(const pTarget: THbTarget): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('qname', pTarget.QName);
  Result.AddPair('kind', TargetKindCode(pTarget.Kind));
  Result.AddPair('file', pTarget.FileName);
  Result.AddPair('line', TJSONNumber.Create(pTarget.Line));
  Result.AddPair('type', pTarget.TypeName);
  Result.AddPair('zero_value', pTarget.ZeroValue);
end;

function UseJson(const pUse: THbUseAnswer): TJSONObject;
begin
  Result:= SiteJson(pUse.Site);
  Result.AddPair('verdict', VerdictCode(pUse.Verdict));
  Result.AddPair('reasons', ReasonsJson(pUse.Reasons));
  Result.AddPair('why', pUse.Why);
  var W:= TJSONArray.Create;
  Result.AddPair('witness', W);
  for var H in pUse.Witness do
  begin
    var O:= TJSONObject.Create;
    W.AddElement(O);
    O.AddPair('step', TJSONNumber.Create(H.Step));
    O.AddPair('routine', H.Routine);
    O.AddPair('file', H.FileName);
    O.AddPair('line', TJSONNumber.Create(H.Line));
    O.AddPair('col', TJSONNumber.Create(H.Col));
    O.AddPair('note', H.Note);
  end;
end;

function WriterJson(const pWriter: THbWriter): TJSONObject;
begin
  Result:= SiteJson(pWriter.Site);
  Result.AddPair('how', HowCode(pWriter.How));
  Result.AddPair('resolved', TJSONBool.Create(pWriter.Resolved));
  Result.AddPair('counts', TJSONBool.Create(pWriter.Counts));
  Result.AddPair('fired_by', pWriter.FiredBy);
  var C:= TJSONObject.Create;
  Result.AddPair('callers', C);
  C.AddPair('count', TJSONNumber.Create(pWriter.CallerCount));
  C.AddPair('top', StringsJson(pWriter.TopCallers));
end;

function HbAnswerJson(const pAnswer: THbAnswer): string;
begin
  var Root:= TJSONObject.Create;
  try
    Root.AddPair('target', TargetJson(pAnswer.Target));
    Root.AddPair('verdict', VerdictCode(pAnswer.Verdict));
    Root.AddPair('proven', TJSONBool.Create(pAnswer.Proven));
    Root.AddPair('scope', ScopeCode(pAnswer.Scope));
    Root.AddPair('summary', pAnswer.Summary);
    Root.AddPair('reasons', ReasonsJson(pAnswer.Reasons));
    var UsesArr:= TJSONArray.Create;
    Root.AddPair('uses', UsesArr);
    for var U in pAnswer.JudgedUses do UsesArr.AddElement(UseJson(U));
    var Writers:= TJSONArray.Create;
    Root.AddPair('writers', Writers);
    for var W in pAnswer.Writers do Writers.AddElement(WriterJson(W));
    var Roots:= TJSONObject.Create;
    Root.AddPair('roots', Roots);
    Roots.AddPair('ordered', StringsJson(pAnswer.Roots.Ordered));
    Roots.AddPair('unordered', TJSONNumber.Create(pAnswer.Roots.Unordered));
    Root.AddPair('limits', StringsJson(pAnswer.Limits));
    var Budget:= TJSONObject.Create;
    Root.AddPair('budget', Budget);
    Budget.AddPair('routines', TJSONNumber.Create(pAnswer.Budget.Routines));
    Budget.AddPair('ms', TJSONNumber.Create(pAnswer.Budget.Ms));
    Budget.AddPair('exhausted', TJSONBool.Create(pAnswer.Budget.Exhausted));
    { v152 HBFIX H3: the wall-clock cap in force (0 = none) and whether it stopped the query }
    Budget.AddPair('max_s', TJSONNumber.Create(pAnswer.Budget.MaxSeconds));
    Budget.AddPair('timed_out', TJSONBool.Create(pAnswer.Budget.TimedOut));
    Result:= Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function SiteText(const pSite: THbSite): string;
begin
  Result:= ExtractFileName(pSite.FileName) + ':' + IntToStr(pSite.Line);
  if pSite.Col > 0 then Result:= Result + ':' + IntToStr(pSite.Col);
end;

function ReasonsText(const pReasons: TArray<THbReason>): string;
begin
  Result:= '';
  for var R in pReasons do
    Result:= Result + (if Result = '' then '' else ', ') + ReasonCode(R);
end;

function WriterText(const pWriter: THbWriter): string;
begin
  Result:= Format('  %s  %s  %s', [SiteText(pWriter.Site), pWriter.Site.Routine, HowCode(pWriter.How)]);
  if not pWriter.Counts then Result:= Result + '  (does not count)';
  if pWriter.FiredBy <> '' then Result:= Result + '  fired by ' + pWriter.FiredBy
  else if pWriter.CallerCount > 0 then
  begin
    Result:= Result + Format('  called from %d routines', [pWriter.CallerCount]);
    var Names:= '';
    for var I:= 0 to High(pWriter.TopCallers) do
      if I < MAX_TOP_CALLERS then Names:= Names + (if Names = '' then '' else ', ') + pWriter.TopCallers[I];
    if Names <> '' then Result:= Result + ': ' + Names;
  end;
end;

function HbAnswerText(const pAnswer: THbAnswer; pExplain: Boolean): string;
var
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    var T:= pAnswer.Target;
    var Head:= if T.QName <> '' then T.QName else '(the variable under --at)';
    if T.TypeName <> '' then Head:= Head + ' : ' + T.TypeName;
    Head:= Head + ' (' + TargetKindCode(T.Kind);
    if T.FileName <> '' then Head:= Head + ', ' + ExtractFileName(T.FileName) + ':' + IntToStr(T.Line);
    Head:= Head + ')';
    if T.ZeroValue <> '' then Head:= Head + ' -- zero value until set: ' + T.ZeroValue;
    SB.AppendLine(Head);
    if Length(pAnswer.JudgedUses) = 1 then
      SB.AppendLine('use  ' + SiteText(pAnswer.JudgedUses[0].Site)
        + (if pAnswer.JudgedUses[0].Site.Routine <> '' then '  in ' + pAnswer.JudgedUses[0].Site.Routine else ''));
    var V:= 'verdict  ' + VerdictCode(pAnswer.Verdict);
    if pAnswer.Summary <> '' then V:= V + '   ' + pAnswer.Summary;
    SB.AppendLine(V);
    if Length(pAnswer.Writers) > 0 then
    begin
      SB.AppendLine(Format('writers (%d)', [Length(pAnswer.Writers)]));
      for var W in pAnswer.Writers do SB.AppendLine(WriterText(W));
    end;
    for var U in pAnswer.JudgedUses do
    begin
      if Length(pAnswer.JudgedUses) > 1 then
        SB.AppendLine(Format('use  %s  %s', [SiteText(U.Site), VerdictCode(U.Verdict)]));
      if Length(U.Witness) > 0 then
      begin
        SB.AppendLine('witness');
        for var H in U.Witness do
          SB.AppendLine(Format('  %d  %s%s  %s:%d:%d  %s', [H.Step, StringOfChar(' ', 2 * (H.Step - 1)),
            H.Routine, ExtractFileName(H.FileName), H.Line, H.Col, H.Note]).TrimRight);
      end;
      if U.Why <> '' then SB.AppendLine(U.Why);
      if pExplain and (Length(U.Reasons) > 0) then SB.AppendLine('  reasons: ' + ReasonsText(U.Reasons));
    end;
    if Length(pAnswer.JudgedUses) > 1 then
    begin
      var Counts: array[THbVerdict] of Integer;
      for var K:= Low(THbVerdict) to High(THbVerdict) do Counts[K]:= 0;
      for var U in pAnswer.JudgedUses do Inc(Counts[U.Verdict]);
      SB.AppendLine(Format('uses judged (%d): %d SET, %d NEVER-SET, %d MAY-BE-UNSET',
        [Length(pAnswer.JudgedUses), Counts[hvSet], Counts[hvNeverSet], Counts[hvMayBeUnset]]));
    end;
    if Length(pAnswer.Reasons) > 0 then SB.AppendLine('reasons: ' + ReasonsText(pAnswer.Reasons));
    if pExplain then
    begin
      var Ordered:= '';
      for var R in pAnswer.Roots.Ordered do Ordered:= Ordered + (if Ordered = '' then '' else ' -> ') + R;
      SB.AppendLine(Format('roots: ordered %d%s, unordered %d', [Length(pAnswer.Roots.Ordered),
        (if Ordered <> '' then ' (' + Ordered + ')' else ''), pAnswer.Roots.Unordered]));
    end;
    var L:= '';
    for var S in pAnswer.Limits do L:= L + (if L = '' then '' else ', ') + S;
    SB.AppendLine('limits: ' + (if L = '' then 'none' else L));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure WriteHbAnswer(const pAnswer: THbAnswer; pExplain: Boolean);
begin
  Write(HbAnswerText(pAnswer, pExplain));
end;

function HbExitCode(const pAnswer: THbAnswer): Integer;
begin
  Result:= if pAnswer.Verdict = hvSet then 0 else 1;
end;

end.
