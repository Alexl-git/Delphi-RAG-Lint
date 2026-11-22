unit DRagLint.CLI.Compare;

// ---------------------------------------------------------------------------
// The `compare` verb (charts step 1, lane v1511 SPLIT T07): rerun a question, diff it against a snapshot,
// --save / --show / --auto. Moved verbatim out of DRagLint.CLI; the report logic is DRagLint.Charts.*.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>Runs `drag-lint compare` (charts step 1): reruns a report's COMMAND and shows before / delta / after.</summary>
/// <param name="AArgs">The parsed command line; see the verb's lines in --help.</param>
/// <returns>0 same, 1 differences, 2 usage or setup error, 3 stale index (also 2 for a bad usage,
/// and 2 for any exception raised inside the verb: ERROR: &lt;class&gt;: &lt;message&gt;).</returns>
/// <remarks>
/// Output: text or JSON to stdout (or --output), HTML always to a file whose path is printed.
/// The new run never accepts a stale index. The old chart's temp SVG copy is deleted on every path,
/// and an exception while reporting an exception still ends in one ERROR line and exit 2.
/// Not thread-safe (it may rewrite a unit for --update-doc).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.Charts.Compare.RunCompare, DRagLint.Charts.Producer.Delphi.ProducerForCompare, DRagLint.CLI.Compare.CompareChooseSource, DRagLint.CLI.Compare.CompareDropTempSvg, DRagLint.CLI.Compare.CompareEmit, DRagLint.CLI.Compare.CompareIsSnapshotOnly, DRagLint.CLI.Compare.CompareProduceOptions, DRagLint.CLI.Compare.CompareRefuse, DRagLint.CLI.Compare.CompareShowPage, DRagLint.CLI.Compare.CompareTakeSnapshot, DRagLint.CLI.Compare.CompareUsageProblem, LowerCase, MatchStr, Writeln</para>
/// <para>Returns: CompareRefuse(AArgs, 'text', COMPARE_EXIT_SETUP, '--format must be text, json or html', True); CompareEmit(AArgs, Req, RunCompare(Req), Fmt); COMPARE_EXIT_SETUP; CompareRefuse(ToStdout, Fmt, COMPARE_EXIT_SETUP, E.ClassName + ': ' + E.Message, False)</para>
/// <para>Complexity: 14 (cyclomatic, outer body), 66 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Charts.Compare.RunCompare"/>
/// <seealso cref="DRagLint.Charts.Producer.Delphi.ProducerForCompare"/>
/// <seealso cref="DRagLint.CLI.Compare.CompareChooseSource"/>
/// <seealso cref="DRagLint.CLI.Compare.CompareDropTempSvg"/>
/// <seealso cref="DRagLint.CLI.Compare.CompareEmit"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoCompare(const AArgs: TArgs): Integer;

implementation

uses
  Winapi.Windows, DRagLint.Core.CliError, System.SysUtils, System.Classes, System.IOUtils, System.NetEncoding,
  System.JSON, System.StrUtils, System.DateUtils, System.Generics.Collections, System.SyncObjs,
  FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt, TreeSitter, DRagLint.Charts.ReportHeader,
  DRagLint.Charts.Adapters, DRagLint.Charts.Producer, DRagLint.Charts.Producer.Delphi,
  DRagLint.Charts.Snapshot, DRagLint.Charts.Compare, DRagLint.Charts.Render;

{ ---- compare (charts step 1) -------------------------------------------------
  `drag-lint compare` is thin on purpose: DRagLint.Charts.Compare decides and diffs,
  DRagLint.Charts.Render prints; this section only maps flags onto a TCompareRequest,
  routes the output (stdout, --output, an HTML file) and picks the exit code.
  PS trap handled: flag values are case-sensitive here (ParamStr compares exactly), but the
  question id and argument names inside a command are matched case-insensitively by
  ParseCommandLine / SameQuestion, exactly as Ask-Report.ps1 does. }

const
  COMPARE_USAGE = 'Usage: drag-lint compare --old <report|csv|bundle> [--command "<id> ..."] | --in <U.pas> --line <L> [--update-doc] | ' +
    '--show <report|csv|bundle> | --question <id> --target <T> --project <P.dproj> --save [--auto]  (drag-lint --help lists every flag)';
  COMPARE_HTML_DIR = 'drag-lint-reports';
  COMPARE_TEMP_SVG_PREFIX = 'drag-lint-compare-old-';
  COMPARE_SVG_EXT = '.svg';
  COMPARE_STAMP = 'yyyymmdd-hhnn';
  COMPARE_RUN_STAMP = 'yyyymmdd-hhnnss';

function CompareReadText(const APath: string): string;
begin
  var Bytes:= TFile.ReadAllBytes(APath);
  var Enc: TEncoding:= TEncoding.UTF8;
  var Skip:= TEncoding.GetBufferEncoding(Bytes, Enc, TEncoding.UTF8);
  Result:= Enc.GetString(Bytes, Skip, Length(Bytes) - Skip);
end;

{ Text/JSON/HTML are Delphi strings; the HTML declares utf-8, so every file is UTF-8 without BOM. }
procedure CompareWriteFile(const APath, AText: string);
begin
  var Dir:= ExtractFilePath(ExpandFileName(APath));
  if Dir <> '' then ForceDirectories(Dir);  // dl:ok ignored-must-use-result@f55c -- REVIEWED 2026-11-22 SLZ-S02: ignored-must-use-result best-effort: a failed ForceDirectories surfaces as the next file write raising with the path; a failed temp DeleteFile is harmless
  TFile.WriteAllText(APath, AText, TUTF8Encoding.Create(False));
end;

function CompareTargetOf(const ACmd: TReportCommand): string;
begin
  Result:= ACmd.Get('Target');
  if ACmd.Has('To') then Result:= Result + ' -> ' + ACmd.Get('To');
end;

{ The command the caller gave: --command wins over --question/--target (+ -Project from --project). }
function CompareBuildCommand(const AArgs: TArgs; out ACmd: TReportCommand; out AErr: string): Boolean;
begin
  ACmd:= Default(TReportCommand);
  AErr:= '';
  Result:= True;
  if AArgs.CompareCommand <> '' then
  begin
    Result:= ParseCommandLine(AArgs.CompareCommand, ACmd);
    { B-25: ParamStr drops the quote of an MSVC-style \" escape and keeps its backslash, so
      a quoted value arrived as \C:\P\A.dproj\ . No Target / Project value starts AND ends
      with a backslash, so that pair is the escape's remains. }
    if Result then
      for var CmdArgIx: Integer:= 0 to High(ACmd.Args) do
        if (Length(ACmd.Args[CmdArgIx].Value) > 2) and ACmd.Args[CmdArgIx].Value.StartsWith('\') and ACmd.Args[CmdArgIx].Value.EndsWith('\') then
          ACmd.Args[CmdArgIx].Value:= Copy(ACmd.Args[CmdArgIx].Value, 2, Length(ACmd.Args[CmdArgIx].Value) - 2);
    if not Result then
      AErr:= 'cannot read --command "' + AArgs.CompareCommand + '" -- it must start with the question id';
  end
  else if AArgs.Question <> '' then
  begin
    if AArgs.Target = '' then
    begin
      AErr:= '--question needs --target';
      Exit(False);
    end;
    var Text:= Format('%s -Target "%s"', [AArgs.Question, AArgs.Target]);
    if AArgs.ProjectPath <> '' then Text:= Text + Format(' -Project "%s"', [ExpandFileName(AArgs.ProjectPath)]);
    if not ParseCommandLine(Text, ACmd) then
    begin
      AErr:= 'cannot build a command from --question "' + AArgs.Question + '"';
      Exit(False);
    end;
  end;
end;

{ Which old side the flags name; exactly one of --in, --old-db, --old, --auto. }
function CompareChooseSource(const AArgs: TArgs; out ASource: TCompareSource; out AErr: string): Boolean;
begin
  AErr:= '';
  ASource:= csFile;
  var Named:= Ord(AArgs.InFile <> '') + Ord(AArgs.CompareOldDb <> '') + Ord(AArgs.CompareOld <> '') + Ord(AArgs.CompareAuto);
  Result:= False;
  if Named = 0 then AErr:= 'no old side -- give --old, --in/--line, --old-db or --auto'
  else if Named > 1 then AErr:= 'give only one old side: --old, --in/--line, --old-db or --auto'
  else if (AArgs.InFile <> '') and (AArgs.RefLine <= 0) then AErr:= '--in needs --line <L> (a line inside the remarks block)'
  else if (AArgs.CompareNew <> '') and (AArgs.CompareOld = '') then AErr:= '--new needs --old'
  else if (AArgs.UpdateDoc) and (AArgs.InFile = '') then AErr:= '--update-doc needs --in <U.pas> --line <L>'
  else
  begin
    Result:= True;
    if AArgs.InFile <> '' then ASource:= csRemarks
    else if AArgs.CompareOldDb <> '' then ASource:= csOldIndex
    else if AArgs.CompareAuto then ASource:= csAutoSnapshot
    else if AArgs.CompareNew <> '' then ASource:= csTwoFiles
    else ASource:= csFile;
  end;
end;

procedure CompareOpenOrReport(const AArgs: TArgs; const APath: string);
begin
  Writeln(APath);
  if AArgs.Open then OpenInBrowser(APath);
end;

{ Only the temp copy named for the old chart (name + folder both checked) is deleted; a path
  that was never written is not there to delete. }
procedure CompareDropTempSvg(const ASvg: string);
begin
  var Svg:= ASvg;
  if (Svg <> '') and StartsText(COMPARE_TEMP_SVG_PREFIX, ExtractFileName(Svg)) and
     SameText(ExcludeTrailingPathDelimiter(ExtractFilePath(Svg)), ExcludeTrailingPathDelimiter(TPath.GetTempPath)) then
    DeleteFile(Svg); // a temp file that cannot be deleted is the OS's to reap  // dl:ok ignored-must-use-result@7255 -- REVIEWED 2026-11-22 SLZ-S02: ignored-must-use-result best-effort: a failed ForceDirectories surfaces as the next file write raising with the path; a failed temp DeleteFile is harmless
end;

function CompareHtmlPath(const AArgs: TArgs; const AReq: TCompareRequest; const AResult: TCompareResult): string;
begin
  Result:= AArgs.Output;
  if Result <> '' then Exit;
  var Q:= AReq.Command.Question;
  var T:= CompareTargetOf(AReq.Command);
  if Q = '' then Q:= AResult.NewHeader.QuestionId;
  if Q = '' then Q:= AResult.OldHeader.QuestionId;
  if T = '' then T:= AResult.NewHeader.Target;
  if T = '' then T:= AResult.OldHeader.Target;
  if Q = '' then Q:= 'compare';
  Result:= TPath.Combine(TPath.Combine(TPath.GetTempPath, COMPARE_HTML_DIR),
    'compare-' + SanitiseTargetForFileName(Q) + '-' + SanitiseTargetForFileName(T) + '-' + FormatDateTime(COMPARE_STAMP, Now) + '.html');
end;

{ Sends the result where the caller asked; returns the exit code. On exit 2/3 the refusal goes
  to stderr first and is flushed, so a machine caller reading --format json still gets the
  envelope on stdout afterwards (the rule `sql` follows). Exit 3 (stale) also writes the
  stale-index reason (DRagLint.Core.CliError) -- run_cli_error_reason.ps1. }
function CompareEmit(const AArgs: TArgs; const AReq: TCompareRequest; const AResult: TCompareResult; const AFormat: string): Integer;
begin
  Result:= AResult.ExitCode;
  var Refused:= AResult.ExitCode in [COMPARE_EXIT_SETUP, COMPARE_EXIT_STALE];
  if Refused then
  begin
    for var W in AResult.Warnings do Writeln(ErrOutput, 'WARNING: ' + W);
    Writeln(ErrOutput, 'ERROR: ' + AResult.Message);
    { A14 reason after the prose; JSON object form for --format json / --json. }
    if AResult.ExitCode = COMPARE_EXIT_STALE then
    begin
      var First:= AResult.Message;
      var Cut:= Pos(#13, First);
      if Cut > 0 then SetLength(First, Cut - 1);
      WriteCliError(CLI_ERR_STALE_INDEX, 'compare: ' + First, AArgs.AsJson or SameText(AFormat, 'json'), '', '');
    end;
    Flush(ErrOutput);
  end;
  if SameText(AFormat, 'html') then
  begin
    if Refused then Exit;
    var Dest:= CompareHtmlPath(AArgs, AReq, AResult);
    CompareWriteFile(Dest, RenderCompareHtml(AResult));
    CompareOpenOrReport(AArgs, Dest);
    Exit;
  end;
  var Doc:= '';
  if SameText(AFormat, 'json') then Doc:= RenderCompareJson(AResult) + sLineBreak
  else if not Refused then Doc:= RenderCompareText(AResult);
  if Doc = '' then Exit;
  if AArgs.Output <> '' then CompareWriteFile(AArgs.Output, Doc)
  else Write(Doc);
end;

{ Option set common to every rerun: the running exe is the engine; --db pins the new run's index.
  The new run's bundle goes to a PER-RUN folder under --out-root, default %TEMP%\drag-lint-reports: the bundle name is
  question + target only, so two runs in the shared folder overwrote each other's chart (INBOX
  compare item 3). }
function CompareProduceOptions(const AArgs: TArgs): TProduceOptions;
begin
  Result:= DefaultProduceOptions;
  Result.EnginePath:= ParamStr(0);
  Result.OutRoot:= TPath.Combine(if AArgs.CompareOutRoot <> '' then AArgs.CompareOutRoot else TPath.Combine(TPath.GetTempPath, COMPARE_HTML_DIR),
    Format('compare-run-%s-%d', [FormatDateTime(COMPARE_RUN_STAMP, Now), GetCurrentProcessId]));
  if Length(AArgs.DbPaths) > 0 then Result.DbOverride:= AArgs.DbPaths[0];
end;

{ ONE refusal path for every exit 2 / 3 the verb decides itself: builds the refused result and sends it
  through CompareEmit, so stderr gets ERROR (flushed) and, with --format json, stdout still gets the
  compare/1 envelope. AUsage adds the usage line to stderr. An INVALID --format value cannot say what
  the caller wanted, so that one refusal is emitted as text (stderr only). }
function CompareRefuse(const AArgs: TArgs; const AFormat: string; ACode: Integer; const AMessage: string;
  AUsage: Boolean): Integer;
begin
  var R:= Default(TCompareResult);
  R.ExitCode:= ACode;
  R.Message:= AMessage;
  if AUsage then Writeln(ErrOutput, COMPARE_USAGE);
  Result:= CompareEmit(AArgs, Default(TCompareRequest), R, AFormat);
end;
{ --show renders ONE thing; any old side, rerun or action beside it is a usage error. }
function CompareShowHasOtherSource(const AArgs: TArgs): Boolean;
begin
  var Sides:= (AArgs.CompareOld <> '') or (AArgs.CompareNew <> '') or (AArgs.CompareOldDb <> '') or (AArgs.InFile <> '');
  var Actions:= AArgs.CompareAuto or AArgs.CompareSave or AArgs.UpdateDoc;
  Result:= Sides or Actions or (AArgs.Question <> '') or (AArgs.CompareCommand <> '');
end;

{ F4: any report, CSV or bundle folder as the same HTML page the compare view uses. }
function CompareShowPage(const AArgs: TArgs; const AFormat: string): Integer;
begin
  if CompareShowHasOtherSource(AArgs) then
    Exit(CompareRefuse(AArgs, AFormat, COMPARE_EXIT_SETUP, '--show takes no other source or action', True));
  var Path:= ExpandFileName(AArgs.CompareShow);
  var Svg: string:= '';
  var TextFile:= Path;
  if TDirectory.Exists(Path) then
  begin
    TextFile:= TPath.Combine(Path, 'graph.dot');
    if TFile.Exists(TPath.Combine(Path, 'graph.svg')) then Svg:= TPath.Combine(Path, 'graph.svg');
  end
  else if SameText(ExtractFileExt(Path), '.dot') and TFile.Exists(ChangeFileExt(Path, '.svg')) then
    Svg:= ChangeFileExt(Path, '.svg');
  if not TFile.Exists(TextFile) then
    Exit(CompareRefuse(AArgs, AFormat, COMPARE_EXIT_SETUP, 'cannot read ' + AArgs.CompareShow, False));
  var Fmt:= DetectFormat(Path, True);
  var Title:= ExtractFileName(ExcludeTrailingPathDelimiter(Path));
  var Page:= RenderReportHtml(Title, CompareReadText(TextFile), Fmt, Svg);
  var Dest:= AArgs.Output;
  if Dest = '' then
    Dest:= TPath.Combine(TPath.Combine(TPath.GetTempPath, COMPARE_HTML_DIR),
      'show-' + SanitiseTargetForFileName(Title) + '-' + FormatDateTime(COMPARE_STAMP, Now) + '.html');
  CompareWriteFile(Dest, Page);
  CompareOpenOrReport(AArgs, Dest);
  Result:= 0;
end;

{ --save with no old side to compare against: run the question once and keep the answer. }
function CompareTakeSnapshot(const AArgs: TArgs; const ACmd: TReportCommand; const AOpts: TProduceOptions;
  const AFormat: string): Integer;
begin
  { R19: a snapshot-only run has no diff, no unit to rewrite and no page to render -- say so
    instead of silently ignoring the flags. }
  if AArgs.UpdateDoc or (AArgs.CompareNew <> '') or (AFormat <> 'text') then
    Exit(CompareRefuse(AArgs, AFormat, COMPARE_EXIT_SETUP,
      '--save without an old side only takes a snapshot; it cannot be combined with --update-doc, --new or --format json|html', True));
  var Cmd:= ACmd;
  var Asker:= ProducerForCompare;
  var Prod:= Asker.Produce(Cmd, AOpts);
  if Prod.ExitCode = PRODUCER_EXIT_STALE then
  begin
    Exit(CompareRefuse(AArgs, AFormat, COMPARE_EXIT_STALE, 'the index is stale, so there is no current answer to keep: ' + Prod.Reason, False));
  end;
  if not Prod.Ok then
  begin
    Exit(CompareRefuse(AArgs, AFormat, COMPARE_EXIT_SETUP, Format('the question failed (exit %d): %s', [Prod.ExitCode, Prod.Reason]), False));
  end;
  var Fmt:= DetectFormat(Prod.Text, False);
  var Body:= Prod.Text;
  var Ext:= SNAPSHOT_EXT_REPORT;
  if Fmt = cfFormsCsv then Ext:= SNAPSHOT_EXT_FORMS
  else if Fmt = cfGraph then
  begin
    var Dot:= TPath.Combine(Prod.BundlePath, 'graph.dot');
    if (Prod.BundlePath = '') or not TFile.Exists(Dot) then
    begin
      Exit(CompareRefuse(AArgs, AFormat, COMPARE_EXIT_SETUP, 'the chart could not be read from ' + Prod.BundlePath, False));
    end;
    Body:= CompareReadText(Dot);
    Ext:= SNAPSHOT_EXT_GRAPH;
  end;
  var Dir:= AArgs.SnapshotDir;
  if Dir = '' then
    Dir:= ResolveSnapshotDir(if AArgs.ProjectPath <> '' then AArgs.ProjectPath else Cmd.Get('Project'),
      if Length(Prod.IndexPaths) > 0 then Prod.IndexPaths[0] else '');
  var Saved: string;
  if not SaveSnapshot(Dir, AArgs.CompareAuto, Cmd.Question, CompareTargetOf(Cmd), Body, Now, Saved, Ext) then
  begin
    Exit(CompareRefuse(AArgs, AFormat, COMPARE_EXIT_SETUP, 'cannot keep the snapshot under ' + Dir, False));
  end;
  Writeln('snapshot: ', Saved);
  Result:= 0;
end;


{ --save with no old side at all (a question to keep), or --auto --save before the first auto snapshot exists. }
function CompareIsSnapshotOnly(const AArgs: TArgs; const ACmd: TReportCommand): Boolean;
begin
  Result:= False;
  if (not AArgs.CompareSave) or ACmd.IsEmpty then Exit;
  var HasOldSide:= (AArgs.InFile <> '') or (AArgs.CompareOldDb <> '') or (AArgs.CompareOld <> '') or AArgs.CompareAuto;
  if not HasOldSide then Exit(True);
  if AArgs.CompareAuto then
  begin
    var SnapDir:= AArgs.SnapshotDir;
    if SnapDir = '' then SnapDir:= ResolveSnapshotDir(if AArgs.ProjectPath <> '' then AArgs.ProjectPath else ACmd.Get('Project'), '');
    Result:= LatestAutoSnapshotAnyFormat(TPath.Combine(SnapDir, 'auto'), ACmd.Question, CompareTargetOf(ACmd)) = '';
  end;
end;

{ The usage mistakes that need no engine to see; '' when the flags hang together. Also builds the command. }
function CompareUsageProblem(const AArgs: TArgs; out ACmd: TReportCommand): string;
begin
  if not CompareBuildCommand(AArgs, ACmd, Result) then Exit;
  if (AArgs.CompareNew <> '') and (AArgs.CompareOld = '') then Result:= '--new needs --old'
  else if (AArgs.InFile <> '') and (AArgs.RefLine <= 0) then Result:= '--in needs --line <L> (a line inside the remarks block)'
  else if (AArgs.CompareOldDb <> '') and ACmd.IsEmpty then
    Result:= '--old-db needs the question: --command "<id> -Target ..." or --question <id> --target <T>'
  else Result:= '';
end;

function DoCompare(const AArgs: TArgs): Integer;
begin
  var Fmt:= if AArgs.Format = '' then 'text' else LowerCase(AArgs.Format);
  if AArgs.Open and (AArgs.Format = '') then Fmt:= 'html';
  if not MatchStr(Fmt, ['text', 'json', 'html']) then
    Exit(CompareRefuse(AArgs, 'text', COMPARE_EXIT_SETUP, '--format must be text, json or html', True));
  // R26: the old chart's temp copy is named here, so it is deleted on every path below --
  // an exception raised inside RunCompare after the copy was taken included.
  var Req:= Default(TCompareRequest);
  Req.OldSvgCopy:= TPath.Combine(TPath.GetTempPath, COMPARE_TEMP_SVG_PREFIX + TGUID.NewGuid.ToString + COMPARE_SVG_EXT);
  // C6 keeps exit 3 for a stale index: an exception escaping to Run would print FATAL and exit 3,
  // so anything unexpected inside the verb is a setup refusal (exit 2) with the same envelope.
  try
    try
      if AArgs.CompareShow <> '' then Exit(CompareShowPage(AArgs, Fmt));

      var Err: string;
      Err:= CompareUsageProblem(AArgs, Req.Command);
      if Err <> '' then Exit(CompareRefuse(AArgs, Fmt, COMPARE_EXIT_SETUP, Err, True));
      Req.ProjectFile:= AArgs.ProjectPath;
      Req.SnapshotDir:= AArgs.SnapshotDir;
      Req.SaveSnapshot:= AArgs.CompareSave;
      Req.UpdateDoc:= AArgs.UpdateDoc;
      Req.Options:= CompareProduceOptions(AArgs);
      if CompareIsSnapshotOnly(AArgs, Req.Command) then Exit(CompareTakeSnapshot(AArgs, Req.Command, Req.Options, Fmt));
      if not CompareChooseSource(AArgs, Req.Source, Err) then Exit(CompareRefuse(AArgs, Fmt, COMPARE_EXIT_SETUP, Err, True));
      case Req.Source of
        csRemarks:
          begin
            Req.OldPath:= AArgs.InFile;
            Req.OldLine:= AArgs.RefLine;
          end;
        csOldIndex: Req.OldDb:= AArgs.CompareOldDb;
        csTwoFiles:
          begin
            Req.OldPath:= AArgs.CompareOld;
            Req.NewPath:= AArgs.CompareNew;
          end;
        csFile: Req.OldPath:= AArgs.CompareOld;
      end;
      if Req.Source <> csTwoFiles then Req.Producer:= ProducerForCompare;

      Result:= CompareEmit(AArgs, Req, RunCompare(Req), Fmt);
    except
      on E: Exception do
      begin
        // the envelope goes to stdout: the exception may have come from writing --output itself
        var ToStdout:= AArgs;
        ToStdout.Output:= '';
        Result:= COMPARE_EXIT_SETUP;
        try
          Result:= CompareRefuse(ToStdout, Fmt, COMPARE_EXIT_SETUP, E.ClassName + ': ' + E.Message, False);
        except
          on Exception do
          try
            // the envelope itself failed: one plain stderr line, still exit 2, never FATAL
            Writeln(ErrOutput, 'ERROR: ' + E.ClassName + ': ' + E.Message);
          except
            on Exception do Result:= COMPARE_EXIT_SETUP; // stderr is gone too: the exit code is all that is left
          end;
        end;
      end;
    end;
  finally
    CompareDropTempSvg(Req.OldSvgCopy);
  end;
end;

end.
