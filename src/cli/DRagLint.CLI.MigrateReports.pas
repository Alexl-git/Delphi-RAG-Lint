unit DRagLint.CLI.MigrateReports;

{ drag-lint 1.56 -- lane QE-3: verb `migrate-reports`, which brings saved reports / snapshots
  (the three snapshot formats of `compare --save`: .txt report text, .csv forms CSV, .dot chart
  graph) to the CLI style command line of 1.56 and lists what it left alone.

  What can be old in a snapshot is ONE line: the report header's
    COMMAND <id> -Target "t" -Project "p" -Depth 3        (PowerShell style, printed up to 1.55)
  which 1.56 prints as
    COMMAND <id> --target "t" --project "p" --depth 3     (CLI style)
  A forms CSV and a chart DOT carry no command line at all, so a real one is already current
  and is never rewritten.

  Only an UNAMBIGUOUS old line is rewritten: every argument is one the engine printed
  (Target, To, Project, In, Depth, Cap, SurfaceCap, Control, Mode, MaxRows), the line is one
  physical line, and the rewritten line holds exactly the tokens of the old one and parses to
  the same question. Everything else is left byte for byte as it was and listed with its
  reason. In a migrated file only the COMMAND line changes: encoding (UTF-8, BOM kept), line
  ends and every other line stay as they were.

  The verb reads its own flags from the command line (ParamStr(1) is the verb). }

interface

const
  /// <summary>The verb name this unit runs.</summary>
  MIGRATE_REPORTS_VERB = 'migrate-reports';

/// <summary>Runs `drag-lint migrate-reports &lt;path&gt;... [--project X.dproj] [--dry-run]
/// [--json]`: rewrites the old-style COMMAND line of every saved report it is given and
/// lists what it left alone.</summary>
/// <returns>0 = every file was migrated, already current or left alone; 1 = a path does not
/// exist or a file could not be read or written; 2 = usage error.</returns>
/// <remarks>
/// A path is a file or a folder (searched with its subfolders, so the 'auto' snapshots are
/// included); --project adds that project's snapshot folder (ResolveSnapshotDir). Each file is
/// reported once: 'migrated' (a .txt report whose COMMAND line was rewritten in place;
/// 'would migrate' and no write under --dry-run), 'current' (a CLI-style report, or a forms
/// CSV / chart DOT, which carry no command line) or 'left alone' with the reason (a file that
/// is not one of the three formats, a .txt that is no report, a legacy header with no COMMAND
/// line, a wrapped or style-mixing COMMAND line, an unknown argument, a line that would not
/// migrate without loss, text that is not UTF-8). A left-alone file is never an error.
/// Reads ParamStr itself. Not thread-safe.
/// </remarks>
function RunMigrateReportsVerb: Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils, System.Math, System.JSON,
  System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Charts.ReportHeader, DRagLint.Charts.Adapters,
  DRagLint.Charts.Snapshot; // dl:unit DRagLint.Charts.Snapshot accepted -- snapshot_ext_forms / _graph / _report are the three extensions migrate-reports rewrites; they are the snapshot unit's own names for them

const
  EXIT_OK = 0;
  EXIT_FAILED = 1;
  EXIT_USAGE = 2;
  FIRST_FLAG_PARAM = 2;
  CMD_PREFIX = 'COMMAND ';
  CMD_WORD = 'COMMAND';
  REMARKS_OPEN = '<remarks>';
  CR = #13;
  LF = #10;
  QUOTE = '"';
  DASH = '-';
  SPACE = ' ';
  TOKEN_NAME = 'N:';
  TOKEN_VALUE = 'V:';
  TOKEN_UNBALANCED = 'U:';
  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);
  { the arguments the engine ever printed on a COMMAND line, in ParseCommandLine's canonical spelling }
  KNOWN_ARGS: array[0..9] of string = ('Target', 'To', 'Project', 'In', 'Depth', 'Cap', 'SurfaceCap',
    'Control', 'Mode', 'MaxRows');
  FLAG_DRY_RUN = '--dry-run';
  FLAG_JSON = '--json';
  FLAG_PROJECT = '--project';
  HELP_FLAGS: array[0..3] of string = ('--help', '-h', '-?', '/?');
  FORMAT_OTHER = 'other';
  USAGE_TEXT =
    'Usage: drag-lint migrate-reports <file-or-folder>... [--project <App.dproj>] [--dry-run] [--json]' + sLineBreak +
    sLineBreak +
    'Rewrites the COMMAND line of saved reports from the old PowerShell style' + sLineBreak +
    '  COMMAND who-writes -Target "T" -Project "P" -Depth 3' + sLineBreak +
    'to the CLI style drag-lint prints since 1.56' + sLineBreak +
    '  COMMAND who-writes --target "T" --project "P" --depth 3' + sLineBreak +
    'and lists every file it left alone, with the reason.' + sLineBreak +
    sLineBreak +
    '  <file-or-folder>  a snapshot (.txt report, .csv forms CSV, .dot chart) or a folder of them;' + sLineBreak +
    '                    a folder is searched with its subfolders (the auto snapshots included)' + sLineBreak +
    '  --project <dproj> also migrate that project''s snapshot folder (reportsDir of' + sLineBreak +
    '                    _D-RAG\drag-lint-project.json, default <project folder>\drag-lint-reports)' + sLineBreak +
    '  --dry-run         report what would be migrated; write nothing' + sLineBreak +
    '  --json            one JSON object: migrated / current / leftAlone / failed' + sLineBreak +
    sLineBreak +
    'Only an unambiguous line is rewritten, and only that line changes. Left alone: a file that is' + sLineBreak +
    'not one of the three formats, a .txt that is no drag-lint report, a legacy header with no' + sLineBreak +
    'COMMAND line, a COMMAND line that is wrapped, mixes -Name with --name, names an argument' + sLineBreak +
    'drag-lint never printed, or would lose a token. A forms CSV and a chart DOT carry no command' + sLineBreak +
    'line: they are reported as current. `compare` reads both styles, so migrating is optional.' + sLineBreak +
    'Exit: 0 done, 1 a path is missing or a file could not be read / written, 2 usage.';

type
  TOutcome = (ocMigrated, ocCurrent, ocLeftAlone, ocFailed);

  { What happened to one file. }
  TFileReport = record
    Path   : string;
    Format : string;
    Outcome: TOutcome;
    Reason : string;
    Line   : Integer;  { 1-based line of the COMMAND line; 0 when none was found }
    OldLine: string;
    NewLine: string;
  end;

  { One physical line of a text: 1-based start and length, the line end excluded. }
  TLineSpan = record
    Start: Integer;
    Len  : Integer;
  end;

  TOptions = record
    Paths  : TArray<string>;
    Project: string;
    DryRun : Boolean;
    AsJson : Boolean;
    Help   : Boolean;
    Problem: string;
  end;

function Settle(var pRep: TFileReport; pOutcome: TOutcome; const pReason: string): TOutcome;
begin
  pRep.Outcome:= pOutcome;
  pRep.Reason:= pReason;
  Result:= pOutcome;
end;

function SplitSpans(const pText: string): TArray<TLineSpan>;
begin
  var Spans:= TList<TLineSpan>.Create;
  try
    var I:= 1;
    var N:= Length(pText);
    while I <= N do
    begin
      var Span: TLineSpan;
      Span.Start:= I;
      while (I <= N) and (pText[I] <> CR) and (pText[I] <> LF) do
        Inc(I);
      Span.Len:= I - Span.Start;
      Spans.Add(Span);
      if (I <= N) and (pText[I] = CR) then Inc(I);
      if (I <= N) and (pText[I] = LF) then Inc(I);
    end;
    Result:= Spans.ToArray;
  finally
    Spans.Free;
  end;
end;

{ The text of a line as the header parser sees it: the '///' prefix off for a DocInsight answer. }
function BodyOf(const pLine: string; pForm: TReportForm): string;
begin
  if pForm <> rfDocInsight then
    Exit(pLine.TrimRight);
  if not StripDocPrefix(pLine, Result) then
    Result:= '';
end;

function IsNameToken(const pToken: string): Boolean;
begin
  var P:= 1;
  while (P <= Length(pToken)) and (pToken[P] = DASH) do
    Inc(P);
  Result:= (P > 1) and (P <= Length(DASH + DASH) + 1) and (P <= Length(pToken)) and CharInSet(pToken[P], ['A'..'Z', 'a'..'z']);
end;

{ The tokens of a COMMAND line, sorted: a name as 'N:' + its letters in lower case (dashes off,
  so -SurfaceCap and --surface-cap are one name), a value as 'V:' + its text, quotes off. An
  unbalanced quote gives a 'U:' token, which no built line ever holds. }
function CommandTokens(const pLine: string): TArray<string>;
begin
  var Tokens:= TList<string>.Create;
  try
    var Text:= if pLine.StartsWith(CMD_PREFIX) then Copy(pLine, Length(CMD_PREFIX) + 1, MaxInt) else pLine;
    var I:= 1;
    var N:= Length(Text);
    while I <= N do
    begin
      while (I <= N) and (Text[I] = SPACE) do
        Inc(I);
      if I > N then Break;
      var Start:= I;
      var Open:= False;
      while (I <= N) and (Open or (Text[I] <> SPACE)) do
      begin
        if Text[I] = QUOTE then
          Open:= not Open;
        Inc(I);
      end;
      var Written:= Copy(Text, Start, I - Start);
      var Quoted:= Written.Contains(QUOTE);
      var Token:= StringReplace(Written, QUOTE, '', [rfReplaceAll]);
      if Open then
        Tokens.Add(TOKEN_UNBALANCED + Token)
      else if (not Quoted) and IsNameToken(Token) then
        Tokens.Add(TOKEN_NAME + LowerCase(StringReplace(Token, DASH, '', [rfReplaceAll])))
      else
        Tokens.Add(TOKEN_VALUE + Token);
    end;
    Result:= Tokens.ToArray;
    TArray.Sort<string>(Result, TStringComparer.Ordinal);
  finally
    Tokens.Free;
  end;
end;

{ Whether pNew says exactly what pOld said: the same tokens, and the same question when read back. }
function SameCommand(const pOld, pNew: string; const pOldCmd: TReportCommand): Boolean;
begin
  var A:= CommandTokens(pOld);
  var B:= CommandTokens(pNew);
  if Length(A) <> Length(B) then
    Exit(False);
  for var I:= 0 to High(A) do
    if A[I] <> B[I] then
      Exit(False);
  var NewCmd: TReportCommand;
  var Differing: TArray<string>;
  Result:= ParseCommandLine(pNew, NewCmd) and SameQuestion(pOldCmd, NewCmd, Differing);
end;

function EscapeDocText(const pText: string): string;
begin
  Result:= StringReplace(pText , '&', '&amp;', [rfReplaceAll]);
  Result:= StringReplace(Result, '<', '&lt;' , [rfReplaceAll]);
end;

{ The CLI-style line for an old-style COMMAND line; False (pRep settled: current for a line that
  needs no migration, left alone for one that is not unambiguous) when nothing is to be written. }
function BuildNewCommand(const pOld: string; var pRep: TFileReport; out pNew: string): Boolean;
begin
  pNew:= '';
  var Refused:= True;
  case DetectCommandStyle(pOld) of
    csCli  : Settle(pRep, ocCurrent, 'the COMMAND line is already in CLI style');
    csNone : Settle(pRep, ocCurrent, 'the COMMAND line names no argument');
    csMixed: Settle(pRep, ocLeftAlone, 'the COMMAND line mixes -Name and --name arguments');
  else
    Refused:= False;
  end;
  if Refused then
    Exit(False);
  var Cmd: TReportCommand;
  if not ParseCommandLine(pOld, Cmd) then
  begin
    Settle(pRep, ocLeftAlone, 'the COMMAND line does not parse');
    Exit(False);
  end;
  for var Arg in Cmd.Args do
    if not MatchText(Arg.Name, KNOWN_ARGS) then
    begin
      Settle(pRep, ocLeftAlone, 'the COMMAND line names an argument drag-lint never printed: -' + Arg.Name);
      Exit(False);
    end;
  pNew:= CMD_PREFIX + BuildCommandLine(Cmd);
  Result:= SameCommand(pOld, pNew, Cmd);
  if not Result then
    Settle(pRep, ocLeftAlone,
      'the COMMAND line would not migrate without loss (a repeated argument, a value with no name or an unbalanced quote)');
end;

{ Index of the first line of the header sentence: blank lines and a DocInsight <remarks> line skipped. }
function SentenceIndex(const pLines: TArray<string>; pForm: TReportForm): Integer;
begin
  Result:= 0;
  while Result <= High(pLines) do
  begin
    var Body:= BodyOf(pLines[Result], pForm).Trim;
    if (Body <> '') and not SameText(Body, REMARKS_OPEN) then
      Break;
    Inc(Result);
  end;
end;

{ Index of the report's COMMAND line in pLines; -1 (pRep settled as left alone) when the header has
  none that can be rewritten: a legacy header, a line that does not parse, a wrapped line. }
function CommandLineIndex(const pLines: TArray<string>; const pHeader: TReportHeader; var pRep: TFileReport): Integer;
begin
  Result:= -1;
  var First:= SentenceIndex(pLines, pHeader.Form);
  var Last:= First + pHeader.HeaderLines - 1;
  if not pHeader.HasCommand then
  begin
    if (Last < High(pLines)) and BodyOf(pLines[Last + 1], pHeader.Form).StartsWith(CMD_WORD) then
      Settle(pRep, ocLeftAlone, 'the COMMAND line does not parse')
    else
      Settle(pRep, ocLeftAlone, 'a legacy header with no COMMAND line: nothing to migrate');
    Exit;
  end;
  var At:= -1;
  for var I:= First to Min(Last, High(pLines)) do
    if BodyOf(pLines[I], pHeader.Form).StartsWith(CMD_PREFIX) then
    begin
      At:= I;
      Break;
    end;
  if At < 0 then
    Settle(pRep, ocLeftAlone, 'the COMMAND line could not be located')
  else if Last > At then
  begin
    pRep.Line:= At + 1;
    Settle(pRep, ocLeftAlone, 'the COMMAND line is wrapped over several lines');
  end
  else
    Result:= At;
end;

{ A report's text with its COMMAND line in CLI style. pRep receives the outcome, the line number
  and both lines; pNewText is the migrated text when the result is ocMigrated, else ''. Pure. }
function MigrateReportText(const pText: string; var pRep: TFileReport; out pNewText: string): TOutcome;
begin
  pNewText:= '';
  var Spans:= SplitSpans(pText);
  var Lines: TArray<string>;
  SetLength(Lines, Length(Spans));
  for var I:= 0 to High(Spans) do
    Lines[I]:= Copy(pText, Spans[I].Start, Spans[I].Len);
  var Header: TReportHeader;
  if not ParseReportHeader(Lines, Header) then
    Exit(Settle(pRep, ocLeftAlone, 'not a drag-lint report (no header sentence)'));
  var At:= CommandLineIndex(Lines, Header, pRep);
  if At < 0 then
    Exit(pRep.Outcome);
  var Old:= BodyOf(Lines[At], Header.Form);
  if Header.Form = rfDocInsight then
    Old:= XmlUnescape(Old);
  pRep.Line:= At + 1;
  pRep.OldLine:= Old;
  var NewCmd: string;
  if not BuildNewCommand(Old, pRep, NewCmd) then
    Exit(pRep.Outcome);
  pRep.NewLine:= NewCmd;
  var Lead:= Copy(Lines[At], 1, Pos(CMD_PREFIX, Lines[At]) - 1);
  var Written:= Lead + (if Header.Form = rfDocInsight then EscapeDocText(NewCmd) else NewCmd);
  pNewText:= Copy(pText, 1, Spans[At].Start - 1) + Written + Copy(pText, Spans[At].Start + Spans[At].Len, MaxInt);
  Result:= Settle(pRep, ocMigrated, '');
end;

function HasUtf8Bom(const pBytes: TBytes): Boolean;
begin
  Result:= Length(pBytes) >= Length(UTF8_BOM);
  for var I:= 0 to Min(High(UTF8_BOM), High(pBytes)) do
    if pBytes[I] <> UTF8_BOM[I] then
      Exit(False);
end;

{ Reads a file as UTF-8. False with pRep settled: ocFailed when it cannot be read, ocLeftAlone
  when it is not UTF-8 text. }
function ReadUtf8(const pPath: string; var pRep: TFileReport; out pText: string; out pBom: Boolean): Boolean;
begin
  pText:= '';
  pBom:= False;
  var Bytes: TBytes;
  try
    Bytes:= TFile.ReadAllBytes(pPath);
  except
    on E: Exception do
    begin
      Settle(pRep, ocFailed, 'cannot read the file: ' + E.Message);
      Exit(False);
    end;
  end;
  pBom:= HasUtf8Bom(Bytes);
  var Offset:= if pBom then Length(UTF8_BOM) else 0;
  if Length(Bytes) = Offset then
    Exit(True);
  try
    pText:= TEncoding.UTF8.GetString(Bytes, Offset, Length(Bytes) - Offset);
  except
    on E: EEncodingError do
    begin
      Settle(pRep, ocLeftAlone, 'not UTF-8 text');
      Exit(False);
    end;
  end;
  Result:= True;
end;

procedure WriteUtf8(const pPath, pText: string; pBom: Boolean);
begin
  var Body:= TEncoding.UTF8.GetBytes(pText);
  if not pBom then
  begin
    TFile.WriteAllBytes(pPath, Body);
    Exit;
  end;
  var Bytes: TBytes;
  SetLength(Bytes, Length(UTF8_BOM) + Length(Body));
  for var I:= 0 to High(UTF8_BOM) do
    Bytes[I]:= UTF8_BOM[I];
  if Length(Body) > 0 then
    Move(Body[0], Bytes[Length(UTF8_BOM)], Length(Body));
  TFile.WriteAllBytes(pPath, Bytes);
end;

function ProcessFile(const pPath: string; pDryRun: Boolean): TFileReport;
begin
  Result:= Default(TFileReport);
  Result.Path:= pPath;
  var Ext:= ExtractFileExt(pPath);
  var Expected:= cfUnknown;
  if SameText(Ext, SNAPSHOT_EXT_REPORT) then Expected:= cfReportText
  else if SameText(Ext, SNAPSHOT_EXT_FORMS) then Expected:= cfFormsCsv
  else if SameText(Ext, SNAPSHOT_EXT_GRAPH) then Expected:= cfGraph;
  if Expected = cfUnknown then
  begin
    Result.Format:= FORMAT_OTHER;
    Settle(Result, ocLeftAlone, 'not a snapshot format (' + (if Ext = '' then 'no extension' else Ext) +
      '): only .txt, .csv and .dot are migrated');
    Exit;
  end;
  Result.Format:= FormatName(Expected);
  var Text: string;
  var Bom: Boolean;
  if not ReadUtf8(pPath, Result, Text, Bom) then
    Exit;
  if Expected = cfFormsCsv then
  begin
    if DetectFormat(Text, False) = cfFormsCsv then
      Settle(Result, ocCurrent, 'a forms CSV carries no command line')
    else
      Settle(Result, ocLeftAlone, 'not a forms CSV (the first row is not the forms-csv header)');
    Exit;
  end;
  if Expected = cfGraph then
  begin
    if DetectFormat(Text, False) = cfGraph then
      Settle(Result, ocCurrent, 'a chart DOT carries no command line')
    else
      Settle(Result, ocLeftAlone, 'not a chart DOT (it does not open with graph / digraph)');
    Exit;
  end;
  var NewText: string;
  if (MigrateReportText(Text, Result, NewText) <> ocMigrated) or pDryRun then
    Exit;
  try
    WriteUtf8(pPath, NewText, Bom);
  except
    on E: Exception do
      Settle(Result, ocFailed, 'cannot write the file: ' + E.Message);
  end;
end;

function ParseOptions: TOptions;
begin
  Result:= Default(TOptions);
  var Paths:= TList<string>.Create;
  try
    var I:= FIRST_FLAG_PARAM;
    while I <= ParamCount do
    begin
      var Arg:= ParamStr(I);
      if MatchText(Arg, HELP_FLAGS) then
        Result.Help:= True
      else if SameText(Arg, FLAG_DRY_RUN) then
        Result.DryRun:= True
      else if SameText(Arg, FLAG_JSON) then
        Result.AsJson:= True
      else if SameText(Arg, FLAG_PROJECT) then
      begin
        Inc(I);
        if I > ParamCount then
          Result.Problem:= FLAG_PROJECT + ' needs a .dproj path'
        else
          Result.Project:= ParamStr(I);
      end
      else if Arg.StartsWith(DASH + DASH) then
        Result.Problem:= 'unknown option ' + Arg
      else
        Paths.Add(Arg);
      Inc(I);
    end;
    if (Result.Problem = '') and (Result.Project <> '') then
    begin
      if TFile.Exists(Result.Project) then
        Paths.Add(ResolveSnapshotDir(Result.Project, ''))
      else
        Result.Problem:= 'no such project file: ' + Result.Project;
    end;
    if (Result.Problem = '') and (Paths.Count = 0) and not Result.Help then
      Result.Problem:= 'give a report file, a folder of reports or --project <App.dproj>';
    Result.Paths:= Paths.ToArray;
  finally
    Paths.Free;
  end;
end;

{ Every file the paths name: a file as given, a folder with its subfolders, in name order. A path
  that does not exist comes back as an ocFailed report. }
function CollectReports(const pOptions: TOptions): TArray<TFileReport>;
begin
  var Reports:= TList<TFileReport>.Create;
  try
    for var Path in pOptions.Paths do
      if TDirectory.Exists(Path) then
      begin
        var Files:= TDirectory.GetFiles(Path, '*', TSearchOption.soAllDirectories);
        TArray.Sort<string>(Files, TStringComparer.Ordinal);
        for var FileName in Files do
          Reports.Add(ProcessFile(FileName, pOptions.DryRun));
      end
      else if TFile.Exists(Path) then
        Reports.Add(ProcessFile(Path, pOptions.DryRun))
      else
      begin
        var Missing:= Default(TFileReport);
        Missing.Path:= Path;
        Missing.Format:= FORMAT_OTHER;
        Settle(Missing, ocFailed, 'no such file or folder');
        Reports.Add(Missing);
      end;
    Result:= Reports.ToArray;
  finally
    Reports.Free;
  end;
end;

function CountOf(const pReports: TArray<TFileReport>; pOutcome: TOutcome): Integer;
begin
  Result:= 0;
  for var Rep in pReports do
    if Rep.Outcome = pOutcome then
      Inc(Result);
end;

procedure PrintText(const pReports: TArray<TFileReport>; pDryRun: Boolean);
begin
  for var Rep in pReports do
    case Rep.Outcome of
      ocMigrated:
        begin
          Writeln(if pDryRun then 'would migrate: ' else 'migrated: ', Rep.Path, ' (line ', Rep.Line, ')');
          Writeln('  old: ', Rep.OldLine);
          Writeln('  new: ', Rep.NewLine);
        end;
      ocCurrent  : Writeln('current: ', Rep.Path, ' -- ', Rep.Reason);
      ocLeftAlone: Writeln('left alone: ', Rep.Path, ' -- ', Rep.Reason);
      ocFailed   : Writeln('failed: ', Rep.Path, ' -- ', Rep.Reason);
    end;
  Writeln(Format('%s: %d file(s): %d %s, %d already current, %d left alone, %d failed%s',
    [MIGRATE_REPORTS_VERB, Length(pReports), CountOf(pReports, ocMigrated),
     if pDryRun then 'would be migrated' else 'migrated', CountOf(pReports, ocCurrent),
     CountOf(pReports, ocLeftAlone), CountOf(pReports, ocFailed),
     if pDryRun then ' (dry run: nothing written)' else '']));
end;

function ReportJson(const pRep: TFileReport): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('path', pRep.Path);
  Result.AddPair('format', pRep.Format);
  if pRep.Outcome = ocMigrated then
  begin
    Result.AddPair('line', TJSONNumber.Create(pRep.Line));
    Result.AddPair('old', pRep.OldLine);
    Result.AddPair('new', pRep.NewLine);
  end
  else
    Result.AddPair('reason', pRep.Reason);
end;

procedure PrintJson(const pReports: TArray<TFileReport>; pDryRun: Boolean);
const
  LIST_NAMES: array[TOutcome] of string = ('migrated', 'current', 'leftAlone', 'failed');
begin
  var Root:= TJSONObject.Create;
  try
    Root.AddPair('verb', MIGRATE_REPORTS_VERB);
    Root.AddPair('dryRun', TJSONBool.Create(pDryRun));
    Root.AddPair('files', TJSONNumber.Create(Length(pReports)));
    for var Outcome:= Low(TOutcome) to High(TOutcome) do
    begin
      var List:= TJSONArray.Create;
      Root.AddPair(LIST_NAMES[Outcome], List);
      for var Rep in pReports do
        if Rep.Outcome = Outcome then
          List.AddElement(ReportJson(Rep));
    end;
    Writeln(Root.ToJSON);
  finally
    Root.Free;
  end;
end;

function RunMigrateReportsVerb: Integer;
begin
  var Options:= ParseOptions;
  if Options.Help then
  begin
    Writeln(USAGE_TEXT);
    Exit(EXIT_OK);
  end;
  if Options.Problem <> '' then
  begin
    Writeln(ErrOutput, MIGRATE_REPORTS_VERB, ': ', Options.Problem);
    Writeln(ErrOutput, 'Try: drag-lint ', MIGRATE_REPORTS_VERB, ' --help');
    Exit(EXIT_USAGE);
  end;
  var Reports:= CollectReports(Options);
  if Options.AsJson then
    PrintJson(Reports, Options.DryRun)
  else
    PrintText(Reports, Options.DryRun);
  Result:= if CountOf(Reports, ocFailed) > 0 then EXIT_FAILED else EXIT_OK;
end;

end.
