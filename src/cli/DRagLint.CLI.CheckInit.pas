unit DRagLint.CLI.CheckInit;

{ drag-lint 1.52 -- verb `check-init` (happens-before, rulings HB1-HB7).
  Scaffold created by lane FRAME: DRagLint.CLI.pas parses the flags and calls
  RunCheckInit in ONE dispatch line; everything else lives here. Lane HBSKEL
  owns this unit (its signature is the FRAME contract: changing it needs a
  HANDOVER to the CLI.pas dispatch line).

  HBSKEL: usage guards, DB guards, the answer through Render. The answer itself
  comes from DRagLint.Query.HappensBefore.CheckInit (lane HBSOLVER, wired by INT 1.52). }

interface

/// <summary>Runs `drag-lint check-init &lt;QName&gt; [--at &lt;file&gt;:&lt;line&gt;[:&lt;col&gt;]] --db &lt;db&gt;
/// [--json] [--explain] [--max-routines N] [--max-seconds S]`.</summary>
/// <param name="pTarget">Positional QName (or --qname); '' when only --at names the target.</param>
/// <param name="pAt">--at value `file:line[:col]`, '' when absent.</param>
/// <param name="pDbPath">--db value (or the resolved project DB), '' when none.</param>
/// <param name="pProject">--project value, '' when absent; named in the no-DB message only.</param>
/// <param name="pJson">--json (or --format json): stdout is one JSON document.</param>
/// <param name="pExplain">--explain: the text output adds roots and per-use reasons.</param>
/// <param name="pMaxRoutines">--max-routines N; 0 = HB_DEFAULT_MAX_ROUTINES; negative (the parser's
/// value for a non-number) is a usage error.</param>
/// <param name="pMaxSeconds">--max-seconds S as typed ('' = absent = HB_DEFAULT_MAX_SECONDS): a number &gt;= 0,
/// decimals allowed (invariant '.'); 0 = no wall-clock cap. Anything else is a usage error.</param>
/// <returns>Process exit code: 0 all SET, 1 some MAY-BE-UNSET or NEVER-SET, 2 usage or other error.</returns>
/// <remarks>
/// Read-only. Every error goes to stderr with exit 2 and NOTHING on stdout, so a --json
/// consumer never parses a half document. Usage errors: neither QName nor --at; a malformed --at;
/// a bad --max-routines or --max-seconds; no DB; a DB that does not exist or whose schema is too old to read; an
/// unknown / ambiguous target or a --at that names another variable (EHbUsage from the engine).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.CLI.CheckInit.DbUsable, DRagLint.CLI.CheckInit.UsageError, DRagLint.Query.HappensBefore.CheckInit, DRagLint.Query.HappensBefore.Render.HbAnswerJson, DRagLint.Query.HappensBefore.Render.HbExitCode, DRagLint.Query.HappensBefore.Render.WriteHbAnswer, DRagLint.Query.HappensBefore.Types.HbParseAt, Flush, Format, IntToStr, TryStrToFloat, Writeln</para>
/// <para>Returns: UsageError('needs a target: &lt;QName&gt; (e.g. UnitA.GCache, UnitA.TFoo.FBar) or --at &lt;file&gt;:&lt;line&gt;[:&lt;col&gt;]'); UsageError(Format('--at must be &lt;file&gt;:&lt;line&gt;[:&lt;col&gt;] with line and col &gt;= 1, got "%s"', [pAt])); UsageError('--max-routines needs a whole number &gt;= 0 (0 = the default budget)'); 2; HbExitCode(Answer)</para>
/// <para>Complexity: 14 (cyclomatic, outer body), 42 lines (full implementation)</para>
/// <para>Catches: EHbUsage (swallowed)</para>
/// <seealso cref="DRagLint.CLI.CheckInit.DbUsable"/>
/// <seealso cref="DRagLint.CLI.CheckInit.UsageError"/>
/// <seealso cref="DRagLint.Query.HappensBefore.CheckInit"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.HbAnswerJson"/>
/// <seealso cref="DRagLint.Query.HappensBefore.Render.HbExitCode"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RunCheckInit(const pTarget, pAt, pDbPath, pProject: string; pJson, pExplain: Boolean;
  pMaxRoutines: Integer; const pMaxSeconds: string): Integer;

implementation

uses
  System.SysUtils
, System.IOUtils
, DRagLint.Core.Interfaces
, DRagLint.Storage.SQLite
, DRagLint.Storage.Schema
, DRagLint.Query.HappensBefore.Types
, DRagLint.Query.HappensBefore.Render
, DRagLint.Query.HappensBefore
  ;

const
  VERB_NAME = 'check-init';

function UsageError(const pMsg: string): Integer;
begin
  Writeln(ErrOutput, 'ERROR: ', VERB_NAME, ': ', pMsg);
  Writeln(ErrOutput, '       usage: drag-lint check-init <QName> [--at <file>:<line>[:<col>]] --db <db> '
    + '[--json] [--explain] [--max-routines N] [--max-seconds S]');
  Flush(ErrOutput);
  Result:= 2;
end;

{ True when pDbPath is an existing index whose schema this engine can read; reports on stderr. }
function DbUsable(const pDbPath, pProject: string): Boolean;
var
  Found, Expected: Integer;
begin
  Result:= False;
  if pDbPath = '' then
  begin
    Writeln(ErrOutput, 'ERROR: ', VERB_NAME, ': no --db was given and no project database resolves here'
      + (if pProject <> '' then ' (--project ' + pProject + ')' else '') + '.');
    Writeln(ErrOutput, '       Run "drag-lint resolve-dbs" to list the configured databases,');
    Writeln(ErrOutput, '       or pass --db <file.sqlite> explicitly.');
    Exit;
  end;
  if not TFile.Exists(pDbPath) then
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

function RunCheckInit(const pTarget, pAt, pDbPath, pProject: string; pJson, pExplain: Boolean;  // dl:ok too-many-parameters@e0ca, too-many-exit-points@1aaa -- REVIEWED 2026-11-18 v152 HBFIX: the FRAME dispatch contract takes one parameter per check-init flag from one CLI.pas line; each Exit is a usage guard with its own message
  pMaxRoutines: Integer; const pMaxSeconds: string): Integer;
var
  AtSite: THbSite;
begin
  AtSite:= Default(THbSite);
  if (pTarget = '') and (pAt = '') then
    Exit(UsageError('needs a target: <QName> (e.g. UnitA.GCache, UnitA.TFoo.FBar) or --at <file>:<line>[:<col>]'));
  if (pAt <> '') and not HbParseAt(pAt, AtSite) then
    Exit(UsageError(Format('--at must be <file>:<line>[:<col>] with line and col >= 1, got "%s"', [pAt])));
  if pMaxRoutines < 0 then
    Exit(UsageError('--max-routines needs a whole number >= 0 (0 = the default budget)'));
  var MaxS: Double:= 0;
  if (pMaxSeconds <> '') and not (TryStrToFloat(pMaxSeconds, MaxS, TFormatSettings.Invariant) and (MaxS >= 0)) then
    Exit(UsageError('--max-seconds needs a number >= 0 (0 = no wall-clock cap; default ' +
      IntToStr(HB_DEFAULT_MAX_SECONDS) + ')'));
  if not DbUsable(pDbPath, pProject) then
  begin
    Flush(ErrOutput);
    Exit(2);
  end;
  var Answer: THbAnswer;
  try
    { 1.52 HBSOLVER H-CLI (applied by INT): the solver answers. }
    var Opts:= Default(THbOptions);
    Opts.MaxRoutines:= if pMaxRoutines = 0 then HB_DEFAULT_MAX_ROUTINES else pMaxRoutines;
    Opts.Explain:= pExplain;
    { v152 HBFIX H3: absent = the default cap; an explicit 0 = no cap (THbOptions: negative) }
    Opts.MaxSeconds:= if pMaxSeconds = '' then 0 else if MaxS <= 0 then -1 else MaxS;
    Answer:= CheckInit(pDbPath, pTarget, pAt, Opts);
  except
    on E: EHbUsage do
    begin
      Writeln(ErrOutput, 'ERROR: ', VERB_NAME, ': ', E.Message);
      for var C in E.Candidates do Writeln(ErrOutput, '       candidate: ', C);
      Flush(ErrOutput);
      Exit(2);
    end;
  end;
  if pJson then Writeln(HbAnswerJson(Answer))
  else WriteHbAnswer(Answer, pExplain);
  Result:= HbExitCode(Answer);
end;

end.
