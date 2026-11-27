unit DRagLint.CLI.HappensBefore;

{ drag-lint 1.56 -- lane HB4: the `happens-before` verb.
  G-56: `happens-before --a <event> --b <event>` answers YES / NO / MAY (DRagLint.Query.HappensBefore.Verb).
  Parses its own flags (like uses-recover and syntax-count): DRagLint.CLI.ParseArgs returns before its flag loop
  for this verb, so the flags, the database check and the usage text all live here. The accepted flags are
  in ONE table named HAPPENS_BEFORE_FLAG_NAMES, so the docs-sync guard (check 9) can read it once INT teaches it this unit.
  DRagLint.CLI.Run dispatches here in one line. Scaffold created by lane W2FRAME (tranche 2); lane HB4 owns
  this unit. If the lane is cut, INT removes the dispatch line and the verb is unknown again. }

interface

type
  /// <summary>The flags `happens-before` accepts.</summary>
  THappensBeforeFlag = (hbfA, hbfB, hbfPreset, hbfDb, hbfJson, hbfMaxRoutines, hbfMaxSeconds, hbfHelp,
    hbfOutputEncoding);

const
  /// <summary>The spelling of each flag. tests\autotest\run_docs_sync_guard.ps1 is to read this table as
  /// the verb's accepted-flag set (as it reads USES_RECOVER_FLAG_NAMES): rename it there too.</summary>
  HAPPENS_BEFORE_FLAG_NAMES: array[THappensBeforeFlag] of string = ('--a', '--b', '--preset', '--db', '--json',
    '--max-routines', '--max-seconds', '--help', '--output-encoding');

/// <summary>Runs the `happens-before` verb from the process command line.</summary>
/// <returns>0 = YES; 1 = NO or MAY; 2 = usage error, unknown target, missing or unreadable --db;
/// 3 = unknown flag.</returns>
/// <remarks>Reads ParamStr(2..ParamCount) itself. The answer goes to stdout (text, or one JSON line with
/// --json); every error goes to stderr and leaves stdout empty. Read-only: the index is never written.</remarks>
function RunHappensBeforeVerb: Integer;

implementation

uses
  System.SysUtils
, System.IOUtils
, DRagLint.Core.CliError // dl:unit DRagLint.Core.CliError accepted -- the verb reports an unknown flag with the shared cli_err_unknown_flag text every verb uses; the other CliError consts are other verbs' errors
, DRagLint.Core.Interfaces
, DRagLint.Storage.SQLite
, DRagLint.Storage.Schema
, DRagLint.CLI.HelpText
, DRagLint.Query.HappensBefore.Types
, DRagLint.Query.HappensBefore.Verb
, DRagLint.Query.HappensBefore.Judge
  ;

const
  VERB_NAME = 'happens-before';
  EXIT_OK = 0;
  EXIT_USAGE = 2;
  EXIT_UNKNOWN_FLAG = 3;
  FIRST_ARG = 2; { ParamStr(1) is the verb }
  VALUE_FLAGS = [hbfA, hbfB, hbfPreset, hbfDb, hbfMaxRoutines, hbfMaxSeconds, hbfOutputEncoding];
  USAGE_LINE = 'usage: drag-lint happens-before (--a <event> --b <event> | --preset <name>) --db <db> ' +
    '[--json] [--max-routines N] [--max-seconds S]';

type
  { The parsed command line of one run. }
  THappensBeforeArgs = record
    A: string;
    B: string;
    Preset: string;
    DbPath: string;
    AsJson: Boolean;
    ShowHelp: Boolean;
    MaxRoutines: string;
    MaxSeconds: string;
  end;

function Usage(const pWhy: string): Integer;
begin
  Writeln(ErrOutput, 'ERROR: ', VERB_NAME, ': ', pWhy);
  Writeln(ErrOutput, '       ', USAGE_LINE);
  Flush(ErrOutput);
  Result:= EXIT_USAGE;
end;

{ False with pError (and pBadFlag for an unknown flag) set. }
function ParseArgs(out pArgs: THappensBeforeArgs; out pError, pBadFlag: string): Boolean;
begin
  pArgs:= Default(THappensBeforeArgs);
  pError:= '';
  pBadFlag:= '';
  var I:= FIRST_ARG;
  while I <= ParamCount do
  begin
    var Tok:= ParamStr(I);
    var Known:= (Tok = '-h') or (Tok = '/?');
    var Flag:= hbfHelp;
    for var F:= Low(THappensBeforeFlag) to High(THappensBeforeFlag) do
      if Tok = HAPPENS_BEFORE_FLAG_NAMES[F] then
      begin
        Flag:= F;
        Known:= True;
      end;
    if not Known then
    begin
      pBadFlag:= Tok;
      pError:= 'Unknown argument: ' + Tok;
      Exit(False);
    end;
    var Value:= '';
    if Flag in VALUE_FLAGS then
    begin
      if (I + 1 > ParamCount) or ParamStr(I + 1).StartsWith('--') then
      begin
        pError:= Tok + ' needs a value';
        Exit(False);
      end;
      Inc(I);
      Value:= ParamStr(I);
    end;
    case Flag of
      hbfA: pArgs.A:= Value;
      hbfB: pArgs.B:= Value;
      hbfPreset: pArgs.Preset:= Value;
      hbfDb: pArgs.DbPath:= ExpandFileName(Value);
      hbfJson: pArgs.AsJson:= True;
      hbfMaxRoutines: pArgs.MaxRoutines:= Value;
      hbfMaxSeconds: pArgs.MaxSeconds:= Value;
      hbfHelp: pArgs.ShowHelp:= True;
      hbfOutputEncoding: ; { consumed by Run before the dispatch; accepted so it is not "unknown" }
    end;
    Inc(I);
  end;
  Result:= True;
end;

{ True when pDbPath is an existing index whose schema this engine can read; reports on stderr. }
function DbUsable(const pDbPath: string): Boolean;
var
  Found, Expected: Integer;
begin
  Result:= False;
  if not TFile.Exists(pDbPath) then  // dl:ok duplicate-code@afc6 -- LINTFIX-A: the check-init verb has its own copy of this --db check; each verb prints errors prefixed with its own name and hint, so a shared helper would need both as parameters for ten lines
  begin
    Writeln(ErrOutput, Format('ERROR: %s: --db does not exist: %s', [VERB_NAME, pDbPath]));
    Writeln(ErrOutput, '       Find it:  drag-lint resolve-dbs --project <x.dproj>   (or --in <x.pas>)');
    Exit;
  end;
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pDbPath, {AReadOnly=}True);
  Store.IsSchemaCurrent(Found, Expected);
  Result:= IsSchemaReadable(Found);
  if not Result then
  begin
    Writeln(ErrOutput, Format('ERROR: %s: the --db is at an OLD SCHEMA (v%d): %s', [VERB_NAME, Found, pDbPath]));
    Writeln(ErrOutput, '       A stale index is not authoritative. Nothing was answered.');
    Writeln(ErrOutput, Format('       Migrate it: drag-lint index --project <x.dproj> --db "%s"', [pDbPath]));
  end;
end;

{ Reads --max-routines / --max-seconds into pOptions (MaxSeconds parsed into pMaxSeconds); '' = fine, else the usage error. }
function BudgetError(const pArgs: THappensBeforeArgs; var pOptions: THbOptions; var pMaxSeconds: Double): string;
begin
  Result:= '';
  if (pArgs.MaxRoutines <> '') and not (TryStrToInt(pArgs.MaxRoutines, pOptions.MaxRoutines) and (pOptions.MaxRoutines >= 0)) then
    Result:= '--max-routines needs a whole number >= 0 (0 = the default budget)'
  else if (pArgs.MaxSeconds <> '') and not (TryStrToFloat(pArgs.MaxSeconds, pMaxSeconds, TFormatSettings.Invariant) and (pMaxSeconds >= 0)) then
    Result:= '--max-seconds needs a number >= 0 (0 = no wall-clock cap)';
end;

{ Fills the two events and the options from the parsed flags; '' = fine, else the usage error. }
function Validate(var pArgs: THappensBeforeArgs; out pOptions: THbOptions): string;
begin
  pOptions:= Default(THbOptions);
  var MaxS: Double:= 0;
  { the presets that take a variable rewrite --a / --b themselves and are then a plain question }
  var TargetError:= '';
  var WithPreset:= (pArgs.Preset <> '') and not HbvPresetTarget(pArgs.Preset, pArgs.A, pArgs.B, TargetError);
  var PresetA:= '';
  var PresetB:= '';
  var Known:= WithPreset and HbvPresetEvents(pArgs.Preset, PresetA, PresetB);
  { a preset names B, and A too unless it takes the caller's --a (HbvPresetEvents leaves A empty) }
  var TakesA:= Known and (PresetA = '');
  var Clash:= WithPreset and not TakesA and ((pArgs.A <> '') or (pArgs.B <> ''));
  if Known and not Clash then
  begin
    if not TakesA then pArgs.A:= PresetA;
    if not TakesA or (pArgs.B = '') then pArgs.B:= PresetB
    else Clash:= True;
  end;
  if TargetError <> '' then
    Result:= TargetError
  else if Clash and TakesA then
    Result:= Format('--preset %s names event B: give --a <event> only', [LowerCase(pArgs.Preset)])
  else if Clash then
    Result:= '--preset names both events: do not give --a or --b with it'
  else if WithPreset and not Known then
    Result:= Format('unknown preset "%s". Presets: %s', [pArgs.Preset, string.Join(', ', HbvPresetNames)])
  else if TakesA and (pArgs.A = '') then
    Result:= Format('--preset %s needs --a <event>: the event that must happen first', [LowerCase(pArgs.Preset)])
  else if (pArgs.A = '') or (pArgs.B = '') then
    Result:= 'needs --a <event> and --b <event>, or --preset <name>'
  else if pArgs.DbPath = '' then
    Result:= 'give --db <file.sqlite>'
  else
    Result:= BudgetError(pArgs, pOptions, MaxS);
  { as check-init: absent = the default cap; an explicit 0 = no cap (THbOptions: negative) }
  pOptions.MaxSeconds:= if pArgs.MaxSeconds = '' then 0 else if MaxS <= 0 then -1 else MaxS;
end;

function Answer(const pArgs: THappensBeforeArgs; const pOptions: THbOptions): Integer;
begin
  var Ans: THbvAnswer;
  try
    Ans:= HappensBefore(pArgs.DbPath, pArgs.A, pArgs.B, pOptions);
  except
    on E: EHbUsage do
    begin
      Writeln(ErrOutput, 'ERROR: ', VERB_NAME, ': ', E.Message);
      for var C in E.Candidates do Writeln(ErrOutput, '       candidate: ', C);
      Flush(ErrOutput);
      Exit(EXIT_USAGE);
    end;
  end;
  Ans.Preset:= LowerCase(pArgs.Preset);
  if pArgs.AsJson then Writeln(HbvAnswerJson(Ans))
  else WriteHbvAnswer(Ans);
  Result:= HbvExitCode(Ans);
end;

function RunHappensBeforeVerb: Integer;
var
  Args: THappensBeforeArgs;
  Options: THbOptions;
  Error, BadFlag: string;
begin
  if not ParseArgs(Args, Error, BadFlag) then
  begin
    if BadFlag = '' then Exit(Usage(Error));
    WriteCliError(CLI_ERR_UNKNOWN_FLAG, Error, CommandLineWantsJson, 'flag', BadFlag);
    Exit(EXIT_UNKNOWN_FLAG);
  end;
  if Args.ShowHelp then
  begin
    WriteVerbHelp(VERB_NAME);
    Exit(EXIT_OK);
  end;
  Error:= Validate(Args, Options);
  if Error <> '' then Exit(Usage(Error));
  if not DbUsable(Args.DbPath) then
  begin
    Flush(ErrOutput);
    Exit(EXIT_USAGE);
  end;
  Result:= Answer(Args, Options);
end;

end.
