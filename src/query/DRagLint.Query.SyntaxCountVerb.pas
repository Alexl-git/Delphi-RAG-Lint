unit DRagLint.Query.SyntaxCountVerb;

{ GAP-SYNTAXQ: the `syntax-count` verb around DRagLint.Query.SyntaxCount.
  Parses its own flags (like init / ask): the CLI dispatches here before
  ParseArgs, so the verb adds no field to TArgs. The index is opened READ-ONLY
  and read for files.path only; nothing is written. }

interface

/// <summary>Runs `drag-lint syntax-count` from the process command line
/// (ParamStr(2) onwards).</summary>
/// <returns>0 = report printed (zero occurrences included); 2 = no --db and no
/// --in, an unknown --feature name, or a --db that is missing or has an old
/// schema; 3 = an unknown flag (error[unknown-flag] on stderr).</returns>
/// <remarks>--db lists every .pas / .dpr / .dpk / .inc row of files.path in that
/// index; --in adds paths. Each file is parsed at the call; the count is of
/// the text as written (no $IFDEF evaluation) and is never capped.</remarks>
function RunSyntaxCountVerb: Integer;

implementation

uses
  System.SysUtils, System.JSON,
  DRagLint.Core.CliError, DRagLint.Core.Interfaces, DRagLint.Core.Model,  // dl:ok uses-global-census -- REVIEWED 2026-11-04: CLI_ERR_UNKNOWN_FLAG is the shared exit vocabulary of every verb
  DRagLint.Storage.SQLite, DRagLint.CLI.HelpText, DRagLint.Query.SyntaxCount;

const
  CVerb = 'syntax-count';
  CExitOk = 0;
  CExitUsage = 2;
  CExitUnknownFlag = 3;
  CFirstArg = 2; // ParamStr(1) is the verb

type
  /// <summary>The flags syntax-count accepts.</summary>
  TSyntaxCountFlag = (scfDb, scfFile, scfFeature, scfPerFile, scfHits, scfJson, scfHelp, scfOutputEncoding);

const
  /// <summary>The spelling of each flag. tests\autotest\run_docs_sync_guard.ps1 reads this
  /// table as the verb's accepted-flag set (as it reads ask's FLAG_NAMES): rename it there too.</summary>
  SYNTAX_COUNT_FLAG_NAMES: array[TSyntaxCountFlag] of string = ('--db', '--in', '--feature',
    '--per-file', '--hits', '--json', '--help', '--output-encoding');
  /// <summary>The flags that take the next token as their value.</summary>
  SYNTAX_COUNT_VALUE_FLAGS = [scfDb, scfFile, scfFeature, scfOutputEncoding];

type
  /// <summary>The parsed flags of one syntax-count run.</summary>
  TSyntaxCountOptions = record
    DbPath     : string;
    Files      : TArray<string>;
    FeatureList: string;
    PerFile    : Boolean;
    Hits       : Boolean;
    AsJson     : Boolean;
    ShowHelp   : Boolean;
  end;

/// <summary>Parses the syntax-count flags.</summary>
/// <param name="pArgs">The tokens after the verb.</param>
/// <param name="pOpts">The options; partly filled on failure.</param>
/// <param name="pError">Why parsing failed; '' on success.</param>
/// <param name="pBadFlag">The unknown flag when that is the failure (exit 3); '' otherwise (exit 2).</param>
/// <returns>True when every token is a known flag with its value.</returns>
function ParseSyntaxCountArgs(const pArgs: TArray<string>; out pOpts: TSyntaxCountOptions;
  out pError, pBadFlag: string): Boolean;
var
  I: Integer;
  LTok, LValue: string;
  LFlag: TSyntaxCountFlag;
  LKnown: Boolean;
begin
  pOpts:= Default(TSyntaxCountOptions);
  pError:= '';
  pBadFlag:= '';
  I:= 0;
  while I <= High(pArgs) do
  begin
    LTok:= pArgs[I];
    LKnown:= False;
    LFlag:= Low(TSyntaxCountFlag);
    for var F:= Low(TSyntaxCountFlag) to High(TSyntaxCountFlag) do
      if LTok = SYNTAX_COUNT_FLAG_NAMES[F] then
      begin
        LFlag:= F;
        LKnown:= True;
      end;
    if (not LKnown) and ((LTok = '-h') or (LTok = '/?')) then
    begin
      LFlag:= scfHelp;
      LKnown:= True;
    end;
    if not LKnown then
    begin
      pBadFlag:= LTok;
      pError:= 'Unknown argument: ' + LTok;
      Exit(False);
    end;
    LValue:= '';
    if LFlag in SYNTAX_COUNT_VALUE_FLAGS then
    begin
      if (I + 1 > High(pArgs)) or pArgs[I + 1].StartsWith('--') then
      begin
        pError:= LTok + ' needs a value';
        Exit(False);
      end;
      Inc(I);
      LValue:= pArgs[I];
    end;
    case LFlag of
      scfDb     : pOpts.DbPath:= LValue;
      scfFile   : pOpts.Files:= pOpts.Files + [ExpandFileName(LValue)];
      scfFeature: pOpts.FeatureList:= LValue;
      scfPerFile: pOpts.PerFile:= True;
      scfHits   : pOpts.Hits:= True;
      scfJson   : pOpts.AsJson:= True;
      scfHelp   : pOpts.ShowHelp:= True;
      scfOutputEncoding: ; { consumed by Run before the dispatch; accepted so it is not "unknown" }
    end;
    Inc(I);
  end;
  Result:= True;
end;
function IsSourcePath(const pPath: string): Boolean;
var
  LExt: string;
begin
  LExt:= LowerCase(ExtractFileExt(pPath));
  Result:= (LExt = '.pas') or (LExt = '.dpr') or (LExt = '.dpk') or (LExt = '.inc');
end;

{ The source rows of one index, or False with pError set. Read-only open. }
function FilesOfIndex(const pDbPath: string; out pFiles: TArray<string>; out pError: string): Boolean;
var
  LStore: ISymbolStore;
  LStamp: TFileStamp;
  LFound, LExpected: Integer;
begin
  pFiles:= nil;
  pError:= '';
  if not FileExists(pDbPath) then
  begin
    pError:= 'index not found: ' + pDbPath;
    Exit(False);
  end;
  LStore:= TSQLiteSymbolStore.Create(pDbPath, {AReadOnly=}True);
  if not LStore.IsSchemaCurrent(LFound, LExpected) then
  begin
    pError:= Format('index schema v%d < v%d: re-index %s first', [LFound, LExpected, pDbPath]);
    Exit(False);
  end;
  for LStamp in LStore.GetAllFileStamps do
    if IsSourcePath(LStamp.Path) then
      pFiles:= pFiles + [LStamp.Path];
  Result:= True;
end;

procedure WriteText(const pReport: TSyntaxCountReport; const pOpts: TSyntaxCountOptions);
var
  F: TSyntaxFeature;
  LRow: TSyntaxFileCount;
  LHit: TSyntaxHit;
begin
  Writeln(Format('syntax-count: %d file(s) scanned, %d unreadable, %d with parse errors',
    [pReport.FilesScanned, pReport.FilesUnreadable, pReport.FilesWithParseErrors]));
  Writeln(Format('  %-18s %8s  %s', ['feature', 'count', 'since']));
  for F:= Low(TSyntaxFeature) to High(TSyntaxFeature) do
    if F in pReport.Features then
      Writeln(Format('  %-18s %8d  %s', [SyntaxFeatureName(F), pReport.Totals[F], SyntaxFeatureSince(F)]));
  if pOpts.PerFile then
  begin
    Writeln(Format('files with at least one occurrence: %d', [Length(pReport.Files)]));
    for LRow in pReport.Files do
    begin
      Write('  ', LRow.FilePath);
      for F:= Low(TSyntaxFeature) to High(TSyntaxFeature) do
        if LRow.Counts[F] > 0 then
          Write(Format('  %s=%d', [SyntaxFeatureName(F), LRow.Counts[F]]));
      Writeln;
    end;
  end;
  if pOpts.Hits then
    for LHit in pReport.Hits do
      Writeln(Format('  %s:%d:%d  %s', [LHit.FilePath, LHit.Line, LHit.Col, SyntaxFeatureName(LHit.Feature)]));
end;

procedure WriteReport(const pReport: TSyntaxCountReport; const pOpts: TSyntaxCountOptions);
var
  LJson: TJSONObject;
begin
  if not pOpts.AsJson then
  begin
    WriteText(pReport, pOpts);
    Exit;
  end;
  LJson:= SyntaxCountToJson(pReport, pOpts.PerFile, pOpts.Hits);
  try
    Writeln(LJson.ToJSON);
  finally
    LJson.Free;
  end;
end;

function Usage(const pWhy: string; pAsJson: Boolean): Integer;
begin
  Writeln(ErrOutput, 'syntax-count: ' + pWhy);
  if not pAsJson then
    Writeln(ErrOutput, 'usage: drag-lint syntax-count (--db <file.sqlite> | --in <path>...) [--feature <a,b>|all] [--per-file] [--hits] [--json]');
  Result:= CExitUsage;
end;

{ The --db file list (when given) followed by the --in paths, or False with
  pError set. A store that raises on open is reported, never propagated. }
function CollectFiles(const pOpts: TSyntaxCountOptions; out pFiles: TArray<string>; out pError: string): Boolean;
begin
  pFiles:= nil;
  pError:= '';
  Result:= True;
  if pOpts.DbPath <> '' then
  try
    Result:= FilesOfIndex(pOpts.DbPath, pFiles, pError);
  except
    on E: Exception do
    begin
      pError:= 'cannot read index ' + pOpts.DbPath + ': ' + E.Message;
      Result:= False;
    end;
  end;
  pFiles:= pFiles + pOpts.Files;
end;

function RunSyntaxCountVerb: Integer;
var
  LArgs, LFiles: TArray<string>;
  LOpts: TSyntaxCountOptions;
  LError, LBadFlag, LBadName: string;
  LFeatures: TSyntaxFeatures;
  I: Integer;
begin
  LArgs:= nil;
  for I:= CFirstArg to ParamCount do
    LArgs:= LArgs + [ParamStr(I)];
  if not ParseSyntaxCountArgs(LArgs, LOpts, LError, LBadFlag) then
  begin
    if LBadFlag <> '' then
    begin
      WriteCliError(CLI_ERR_UNKNOWN_FLAG, LError, CommandLineWantsJson, 'flag', LBadFlag);
      Result:= CExitUnknownFlag;
    end
    else
      Result:= Usage(LError, CommandLineWantsJson);
  end
  else if LOpts.ShowHelp then
  begin
    WriteVerbHelp(CVerb);
    Result:= CExitOk;
  end
  else if not TryParseSyntaxFeatures(LOpts.FeatureList, LFeatures, LBadName) then
    Result:= Usage(Format('unknown --feature "%s" (if-expr, is-not, not-in, inline-var, inline-const, anon-method, multiline-string, all)',
      [LBadName]), LOpts.AsJson)
  else if (LOpts.DbPath = '') and (Length(LOpts.Files) = 0) then
    Result:= Usage('give --db <file.sqlite> and/or --in <path>', LOpts.AsJson)
  else if not CollectFiles(LOpts, LFiles, LError) then
    Result:= Usage(LError, LOpts.AsJson)
  else
  begin
    WriteReport(CountSyntaxFeatures(LFiles, LFeatures, LOpts.Hits), LOpts);
    Result:= CExitOk;
  end;
end;

end.