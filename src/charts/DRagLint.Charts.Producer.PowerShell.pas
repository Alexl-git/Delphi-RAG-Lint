unit DRagLint.Charts.Producer.PowerShell;

{ The step-1 report producer (spec P2): runs charts\src\Ask-Report.ps1 -Plain in a pwsh
  child and maps its exit code and streams onto TProduceResult.

  Ask-Report's contract: stdout is the plain answer (header sentence, COMMAND, BUNDLE, INDEX
  lines, body); stderr carries 'ask-report: <message>' lines; the exit code is 0 answered,
  1 refused, 2 setup, 3 stale index.

  PS trap handled: names and values are handed to PowerShell as separate, individually quoted
  arguments, so none of PowerShell's own splitting, '-eq' coercion or case-insensitive
  parameter matching can change what was asked. Known gap: pwsh writes redirected stdout in
  the console output code page, so a non-ASCII character in a report is decoded here as
  UTF-8 only if the script set [Console]::OutputEncoding itself; plain reports are ASCII. }

interface

uses
  DRagLint.Charts.ReportHeader, DRagLint.Charts.Producer;

type
  /// <summary>Produces reports by running Ask-Report.ps1 -Plain through pwsh.</summary>
  /// <remarks>Holds no state between calls except the script path last used (for Describe);
  /// call it from one thread at a time.</remarks>
  TPowerShellProducer = class(TInterfacedObject, IReportProducer)
  private
    FScriptPath: string;
  public
    /// <summary>Runs one question through Ask-Report.ps1.</summary>
    /// <param name="pCommand">The question; its Question must be a plain id (letters, digits, '-', '_').</param>
    /// <param name="pOptions">Script path ('' resolves it), engine, index override, staleness, timeout.</param>
    /// <returns>Exit 0 gives Ok with Text, IndexPaths and BundlePath. A refusal (1) or stale index (3) gives
    /// the exit code and the 'ask-report:' reason. A missing script, a missing pwsh, a process that would not
    /// start, a timeout and a bad question id all give exit code 2 with a reason.</returns>
    function Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
    /// <summary>Says which script this producer runs.</summary>
    /// <returns>'PowerShell Ask-Report.ps1 at &lt;path&gt;' (the path of the last Produce, else the
    /// default resolution; '(not found)' when there is none).</returns>
    function Describe: string;
  end;

/// <summary>Finds Ask-Report.ps1.</summary>
/// <param name="pExplicit">A path the caller insists on; '' skips this step.</param>
/// <param name="pWhy">Empty on success; otherwise one line per place looked, each with the path tried.</param>
/// <returns>The full path of the first existing candidate, in this order: pExplicit; the environment
/// variable DRAGLINT_ASK_REPORT; Ask-Report.ps1 beside the running exe; ..\..\charts\src\Ask-Report.ps1
/// from the exe folder; ..\..\..\..\charts\src\Ask-Report.ps1 from the exe folder. '' when none exists.</returns>
function ResolveAskReportScript(const pExplicit: string; out pWhy: string): string;

/// <summary>Finds PowerShell 7.</summary>
/// <returns>%ProgramW6432%\PowerShell\7\pwsh.exe when it exists, else pwsh.exe found on PATH, else ''.</returns>
function ResolvePwsh: string;

/// <summary>Builds the command line that runs Ask-Report for one question.</summary>
/// <param name="pPwsh">Path of pwsh.exe.</param>
/// <param name="pScript">Path of Ask-Report.ps1.</param>
/// <param name="pEngine">Path of the engine exe, passed as -Engine.</param>
/// <param name="pCommand">The question and its explicit arguments.</param>
/// <param name="pOptions">DbOverride and AllowStale are appended when set.</param>
/// <returns>"pwsh" -NoProfile -NonInteractive -File "script" -Question q [-Target "t"] [-To "b"]
/// [-Project "p" | -In "f"] [-Depth n] [-Cap n] [-SurfaceCap n] [-Control "c"] [-Mode m] [-MaxRows n]
/// -Engine "exe" -Plain [-DbPath "db"] [-AllowStale]. Only arguments the command carries are passed;
/// never -Open.</returns>
/// <remarks>Quoted values escape embedded quotes and trailing backslashes the way
/// CommandLineToArgvW expects, so a path ending in a backslash cannot swallow the next argument.</remarks>
function BuildProducerCommandLine(const pPwsh, pScript, pEngine: string; const pCommand: TReportCommand;
  const pOptions: TProduceOptions): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils, DRagLint.Charts.Process;

const
  ENV_ASK_REPORT = 'DRAGLINT_ASK_REPORT';
  SCRIPT_NAME = 'Ask-Report.ps1';
  PWSH_REL = 'PowerShell\7\pwsh.exe';
  PWSH_NAME = 'pwsh.exe';
  EXIT_OK = 0;
  EXIT_SETUP = 2;
  REASON_PREFIX = 'ask-report:';
  BUNDLE_PREFIX = 'BUNDLE ';
  INDEX_PREFIX = 'INDEX ';
  INDEX_SUFFIXES: array[0..2] of string = (' (server)', ' (sql)', ' (counterpart)');
  QUOTE: Char = '"';
  BACKSLASH: Char = '\';
  MSG_SEP = '; ';
  PLACE_LABELS: array[0..4] of string = ('explicit path', 'environment variable DRAGLINT_ASK_REPORT',
    'beside the exe', 'two folders up, charts\src', 'four folders up, charts\src');

{ Quotes one argument for CreateProcess: backslashes before a quote (or before the closing
  quote) are doubled and an embedded quote is escaped. }
function QuoteArg(const pValue: string): string;
var
  Slashes: Integer;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append(QUOTE);
    Slashes:= 0;
    for var C in pValue do
    begin
      if C = BACKSLASH then
        Inc(Slashes)
      else
      begin
        if C = QUOTE then SB.Append(BACKSLASH, Slashes + 1)
        else SB.Append(BACKSLASH, Slashes);
        Slashes:= 0;
        SB.Append(C);
      end;
    end;
    SB.Append(BACKSLASH, Slashes * 2);
    SB.Append(QUOTE);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ A value that is normally bare (a number, a mode, the question id): quoted only when it holds
  something that would split or end the argument. }
function BareArg(const pValue: string): string;
begin
  if (pValue = '') or (pValue.IndexOfAny([' ', #9, QUOTE]) >= 0) then Result:= QuoteArg(pValue)
  else Result:= pValue;
end;

procedure AddNamed(const pBuilder: TStringBuilder; const pCommand: TReportCommand; const pName: string; pQuoted: Boolean);
begin
  if not pCommand.Has(pName) then Exit;
  pBuilder.Append(' -').Append(pName).Append(' ');
  if pQuoted then pBuilder.Append(QuoteArg(pCommand.Get(pName)))
  else pBuilder.Append(BareArg(pCommand.Get(pName)));
end;

function BuildProducerCommandLine(const pPwsh, pScript, pEngine: string; const pCommand: TReportCommand;
  const pOptions: TProduceOptions): string;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append(QuoteArg(pPwsh)).Append(' -NoProfile -NonInteractive -File ').Append(QuoteArg(pScript));
    SB.Append(' -Question ').Append(BareArg(pCommand.Question));
    AddNamed(SB, pCommand, 'Target', True);
    AddNamed(SB, pCommand, 'To', True);
    if pCommand.Has('Project') then AddNamed(SB, pCommand, 'Project', True)
    else AddNamed(SB, pCommand, 'In', True);
    AddNamed(SB, pCommand, 'Depth', False);
    AddNamed(SB, pCommand, 'Cap', False);
    AddNamed(SB, pCommand, 'SurfaceCap', False);
    AddNamed(SB, pCommand, 'Control', True);
    AddNamed(SB, pCommand, 'Mode', False);
    AddNamed(SB, pCommand, 'MaxRows', False);
    SB.Append(' -Engine ').Append(QuoteArg(pEngine)).Append(' -Plain');
    if pOptions.DbOverride <> '' then SB.Append(' -DbPath ').Append(QuoteArg(pOptions.DbOverride));
    if pOptions.AllowStale then SB.Append(' -AllowStale');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function ResolvePwsh: string;
begin
  var Root:= GetEnvironmentVariable('ProgramW6432');
  if Root <> '' then
  begin
    Result:= TPath.Combine(Root, PWSH_REL);
    if TFile.Exists(Result) then Exit;
  end;
  Result:= FileSearch(PWSH_NAME, GetEnvironmentVariable('PATH'));
  if Result <> '' then Result:= ExpandFileName(Result);
end;

function ResolveAskReportScript(const pExplicit: string; out pWhy: string): string;
begin
  var ExeDir:= ExtractFilePath(ParamStr(0));
  var Paths:= TArray<string>.Create(pExplicit, GetEnvironmentVariable(ENV_ASK_REPORT),
    ExeDir + SCRIPT_NAME,
    ExeDir + '..\..\charts\src\' + SCRIPT_NAME,
    ExeDir + '..\..\..\..\charts\src\' + SCRIPT_NAME);
  var Why:= TStringList.Create;
  try
    Result:= '';
    for var I:= 0 to High(Paths) do
    begin
      if Paths[I] = '' then
        Why.Add(PLACE_LABELS[I] + ': (not given)')
      else if TFile.Exists(Paths[I]) then
      begin
        Result:= ExpandFileName(Paths[I]);
        Break;
      end
      else
        Why.Add(PLACE_LABELS[I] + ': ' + Paths[I] + ' (not found)');
    end;
    if Result = '' then pWhy:= Why.Text.TrimRight
    else pWhy:= '';
  finally
    Why.Free;
  end;
end;

function FailureResult(const pReason: string): TProduceResult;
begin
  Result:= Default(TProduceResult);
  Result.ExitCode:= EXIT_SETUP;
  Result.Reason:= pReason;
end;

function IsPlainId(const pId: string): Boolean;
begin
  Result:= pId <> '';
  for var C in pId do
    if not (CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '-', '_'])) then Exit(False);
end;

{ BUNDLE / INDEX lines form one block right after the header; the scan ends at the first line
  after that block so a body line that happens to start with 'INDEX ' is never taken. }
procedure ReadBundleAndIndex(const pText: string; var pResult: TProduceResult);
begin
  var Paths:= TStringList.Create;
  try
    var InBlock:= False;
    for var Raw in pText.Split([#10]) do
    begin
      var Line:= Raw.TrimRight;
      if StartsStr(BUNDLE_PREFIX, Line) then
      begin
        InBlock:= True;
        pResult.BundlePath:= Trim(Copy(Line, Length(BUNDLE_PREFIX) + 1, MaxInt));
      end
      else if StartsStr(INDEX_PREFIX, Line) then
      begin
        InBlock:= True;
        var Path:= Trim(Copy(Line, Length(INDEX_PREFIX) + 1, MaxInt));
        for var Suffix in INDEX_SUFFIXES do
          if EndsStr(Suffix, Path) then
          begin
            Path:= Copy(Path, 1, Length(Path) - Length(Suffix));
            Break;
          end;
        Paths.Add(Path);
      end
      else if InBlock then
        Break;
    end;
    SetLength(pResult.IndexPaths, Paths.Count);
    for var I:= 0 to Paths.Count - 1 do
      pResult.IndexPaths[I]:= Paths[I];
  finally
    Paths.Free;
  end;
end;

{ The 'ask-report:' messages of a failed run, prefix removed, joined with '; '; the whole
  trimmed stderr when none has the prefix; the exit code when stderr is empty. }
function ReasonFrom(const pStdErr: string; pExitCode: Integer): string;
begin
  Result:= '';
  var Found:= False;
  for var Raw in pStdErr.Split([#10]) do
  begin
    var Line:= Raw.Trim;
    if not StartsText(REASON_PREFIX, Line) then Continue;
    var Msg:= Trim(Copy(Line, Length(REASON_PREFIX) + 1, MaxInt));
    if Found then Result:= Result + MSG_SEP + Msg
    else Result:= Msg;
    Found:= True;
  end;
  if not Found then Result:= pStdErr.Trim;
  if Result = '' then Result:= 'Ask-Report exited with code ' + IntToStr(pExitCode);
end;

function TPowerShellProducer.Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
var
  Run: TProcessResult;
begin
  if not IsPlainId(pCommand.Question) then
    Exit(FailureResult('not a report question id: "' + pCommand.Question + '"'));
  var Why: string;
  var Script:= ResolveAskReportScript(pOptions.ScriptPath, Why);
  if Script = '' then
    Exit(FailureResult('Ask-Report.ps1 not found; looked at' + sLineBreak + Why));
  FScriptPath:= Script;
  var Pwsh:= ResolvePwsh;
  if Pwsh = '' then
    Exit(FailureResult('pwsh.exe (PowerShell 7) not found under %ProgramW6432% or on PATH'));
  var Engine:= pOptions.EnginePath;
  if Engine = '' then Engine:= ParamStr(0);
  var Line:= BuildProducerCommandLine(Pwsh, Script, Engine, pCommand, pOptions);
  if not RunCapture(Line, '', pOptions.TimeoutMs, Run) then
    Exit(FailureResult('could not start ' + Pwsh));
  if Run.TimedOut then
    Exit(FailureResult('Ask-Report timed out after ' + IntToStr(pOptions.TimeoutMs) + ' ms'));
  Result:= Default(TProduceResult);
  Result.ExitCode:= Run.ExitCode;
  Result.Ok:= Run.ExitCode = EXIT_OK;
  Result.Text:= Run.StdOut;
  if Result.Ok then
    ReadBundleAndIndex(Run.StdOut, Result)
  else
    Result.Reason:= ReasonFrom(Run.StdErr, Run.ExitCode);
end;

function TPowerShellProducer.Describe: string;
begin
  var Path:= FScriptPath;
  if Path = '' then
  begin
    var Why: string;
    Path:= ResolveAskReportScript('', Why);
  end;
  if Path = '' then Path:= '(not found)';
  Result:= 'PowerShell ' + SCRIPT_NAME + ' at ' + Path;
end;

end.
