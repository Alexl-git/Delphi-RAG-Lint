unit DRagLint.CLI.VerifyIndex;

{ 1.53.0 LSP1-VERB: verify-index (status internal). Measures drag-lint's own name resolution
  against DelphiLSP: a deterministic sample of resolved references from one project DB is
  asked of DelphiLSP (textDocument/definition) and the answers are compared with what the
  index says the target is. Spec: docs\superpowers\specs\2026-11-20-verify-index-design.md.

  READ-ONLY (AC23): the DB is opened read-only, no source file or log is written.

  The pure functions (sampling SQL, location parsing, classification, rate, rendering) are on
  the interface so tests\VerifyIndexTests.dpr can call them without a process or a DB. }

interface

uses
    System.SysUtils
  , System.JSON
  , DRagLint.CLI.Common
  ;

const
  VERIFY_DEFAULT_SAMPLE  = 200;
  VERIFY_DEFAULT_SEED    = 1;
  VERIFY_DEFAULT_TIMEOUT = 10000;
  VERIFY_DEFAULT_WARMUP  = 5000;

type
  /// <summary>A bad value for one of the verb's own flags; the CLI hub maps it to exit 3.</summary>
  EVerifyUsage = class(Exception);

  /// <summary>Outcome of one sampled reference (spec "Outcomes").</summary>
  TVerifyOutcome = (voSampled, voMatch, voMismatch, voEmpty, voError, voSkipped);

  /// <summary>One location of an LSP definition answer; Line is 1-based.</summary>
  TVerifyLocation = record
    Path: string;
    Line: Integer;
  end;

  /// <summary>One sampled reference and drag-lint's expected target.</summary>
  TVerifyRow = record
    RefId   : Int64;
    Kind    : string;
    Name    : string;
    RefPath : string;
    Line    : Integer;
    Col     : Integer;
    QName   : string;
    SymPath : string;
    DeclLine: Integer;
    DeclEnd : Integer;
    ImplLine: Integer;   { 0 = none }
    Outcome : TVerifyOutcome;
    Lsp     : TArray<TVerifyLocation>;
    Detail  : string;
  end;

  /// <summary>Per-outcome counts of a run.</summary>
  TVerifyCounts = record
    Match   : Integer;
    Mismatch: Integer;
    Empty   : Integer;
    Error   : Integer;
    Skipped : Integer;
  end;

  /// <summary>Options of one run; 0 (or '') selects the default except WarmupMs, where 0 is a real value and a negative number selects the default.</summary>
  TVerifyOptions = record
    DbPath       : string;
    ProjectPath  : string;
    ConfigPath   : string;
    DelphiLspExe : string;
    TraceFile    : string;
    DelphiLspBits: Integer;
    Sample       : Integer;
    Seed         : Integer;
    TimeoutMs    : Integer;
    WarmupMs     : Integer;
    DryRun       : Boolean;
    Json         : Boolean;
  end;

/// <summary>The sampling SELECT (AC1-AC3): candidate references only, ordered by a seeded hash so the same DB, sample and seed give the same rows in the same order.</summary>
/// <returns>The SELECT text.</returns>
/// <param name="pSample">Row cap (LIMIT).</param>
/// <param name="pSeed">Seed mixed into the ordering hash.</param>
function VerifySampleSql(pSample, pSeed: Integer): string;  // dl:ok unused-public-symbol@0956 -- REVIEWED 2026-11-23 LSP1-VERB: public so tests\VerifyIndexTests.dpr (a separate program, not in the project) can call the pure function without a process

/// <summary>Location | Location[] | LocationLink[] | null -> locations (AC11); nil, null and [] give no location.</summary>
/// <param name="pResult">The response's result; not owned.</param>
/// <returns>Locations in answer order; Line is 1-based.</returns>
function ParseDefinitionLocations(const pResult: TJSONValue): TArray<TVerifyLocation>;  // dl:ok unused-public-symbol@1322 -- REVIEWED 2026-11-23 LSP1-VERB: public so tests\VerifyIndexTests.dpr (a separate program, not in the project) can call the pure function without a process

/// <summary>match / mismatch for a non-empty location list (AC5-AC7); voEmpty for an empty one.</summary>
/// <param name="pRow">The sampled reference with drag-lint's expected target.</param>
/// <param name="pLocs">The locations DelphiLSP answered with.</param>
/// <returns>voMatch, voMismatch or voEmpty.</returns>
/// <remarks>Paths are compared after ExpandFileName, case-insensitively.</remarks>
function ClassifyLocations(const pRow: TVerifyRow; const pLocs: TArray<TVerifyLocation>): TVerifyOutcome;  // dl:ok unused-public-symbol@8d0d -- REVIEWED 2026-11-23 LSP1-VERB: public so tests\VerifyIndexTests.dpr (a separate program, not in the project) can call the pure function without a process

/// <summary>AC10: '' when the line text is usable for the row, else the skip reason ('moved' or 'non-ascii').</summary>
/// <param name="pRow">The sampled reference.</param>
/// <param name="pLineText">The 1-based line pRow.Line of the file as it is on disk now.</param>
/// <returns>'' when usable, 'moved' or 'non-ascii'.</returns>
function SkipReason(const pRow: TVerifyRow; const pLineText: string): string;  // dl:ok unused-public-symbol@5a3c -- REVIEWED 2026-11-23 LSP1-VERB: public so tests\VerifyIndexTests.dpr (a separate program, not in the project) can call the pure function without a process

/// <summary>AC14: mismatch / (match + mismatch); 0 when that denominator is 0.</summary>
/// <param name="pCounts">The run's outcome counts.</param>
/// <returns>The mismatch rate, 0..1.</returns>
function MismatchRate(const pCounts: TVerifyCounts): Double;  // dl:ok unused-public-symbol@4f1b -- REVIEWED 2026-11-23 LSP1-VERB: public so tests\VerifyIndexTests.dpr (a separate program, not in the project) can call the pure function without a process

/// <summary>AC12 first line.</summary>
/// <param name="pDb">DB path shown in the line.</param>
/// <param name="pSample">The requested sample size.</param>
/// <param name="pSeed">The seed used.</param>
/// <param name="pCounts">The run's outcome counts.</param>
/// <returns>The summary line (no line break).</returns>
function SummaryLine(const pDb: string; pSample, pSeed: Integer; const pCounts: TVerifyCounts): string;

/// <summary>AC12 row line (tab-separated).</summary>
/// <param name="pRow">A classified row.</param>
/// <returns>The row line (no line break).</returns>
function RowLine(const pRow: TVerifyRow): string;

/// <summary>AC13 document.</summary>
/// <param name="pOpts">The run's options (db, sample, seed, config).</param>
/// <param name="pExe">The DelphiLSP executable that was used ('' for a dry run).</param>
/// <param name="pCounts">The run's outcome counts.</param>
/// <param name="pRows">The rows to list (every non-match row, or every sampled row for --dry-run).</param>
/// <returns>A new object; the caller frees it.</returns>
function ReportJson(const pOpts: TVerifyOptions; const pExe: string; const pCounts: TVerifyCounts;  // dl:ok unused-public-symbol@f2e4 -- REVIEWED 2026-11-23 LSP1-VERB: public so tests\VerifyIndexTests.dpr (a separate program, not in the project) can call the pure function without a process
  const pRows: TArray<TVerifyRow>): TJSONObject;

/// <summary>Runs the verb (AC15-AC23).</summary>
/// <param name="pOpts">The options; 0 or '' selects the default except WarmupMs.</param>
/// <returns>0 = no mismatch, 1 = at least one mismatch, 2 = setup error (one ERROR line on stderr, nothing on stdout).</returns>
function RunVerifyIndex(const pOpts: TVerifyOptions): Integer;  // dl:ok unused-public-symbol@82b0 -- REVIEWED 2026-11-23 LSP1-VERB: public so tests\VerifyIndexTests.dpr (a separate program, not in the project) can call the pure function without a process

/// <summary>Entry point for the CLI hub: reads the verb's own flags (--sample, --seed, --warmup-ms, --delphi-lsp-config) from ParamStr and runs.</summary>
/// <param name="pArgs">The parsed command line; DbPath is already resolved by the hub.</param>
/// <returns>0 = no mismatch, 1 = at least one mismatch, 2 = setup error.</returns>
/// <exception cref="EVerifyUsage">A flag value that is not a whole number (the hub maps it to exit 3).</exception>
function RunVerifyIndexVerb(const pArgs: TArgs): Integer;

implementation

uses
    Winapi.Windows
  , System.Classes
  , System.Generics.Collections
  , System.IOUtils
  , System.Math
  , System.NetEncoding
  , System.StrUtils
  , DRagLint.Charts.Index
  , DRagLint.LSP.Proxy // dl:unit DRagLint.LSP.Proxy accepted -- LSP_BITS_32 / LSP_BITS_64 are the DelphiLSP bitness values the proxy defines; verify-index normalises its DelphiLspBits option to one of the same two values
  , DRagLint.LSP.VerifyClient
  ;

const
  OUTCOME_NAMES: array[TVerifyOutcome] of string = ('sampled', 'match', 'mismatch', 'empty', 'error', 'skipped');
  RATE_DECIMALS  = -4;
  PERCENT        = 100;
  ASCII_MAX      = 127;
  FILE_URI       = 'file:///';

{ ---- pure ------------------------------------------------------------------------------- }

function VerifySampleSql(pSample, pSeed: Integer): string;
begin
  { Concatenation, not Format: the SQL holds a modulo operator. }
  Result:=
    'SELECT r.id AS ref_id, r.kind AS kind, r.name_text AS name, f.path AS ref_path, ' +
    'r.start_line AS line, r.start_col AS col, ' +
    's.qualified_name AS qname, sf.path AS sym_path, ' +
    's.start_line AS decl_line, s.end_line AS decl_end, COALESCE(s.impl_start_line, 0) AS impl_line ' +
    'FROM refs r ' +
    'JOIN files f ON f.id = r.file_id ' +
    'LEFT JOIN call_edges ce ON ce.ref_id = r.id AND ce.confidence = ''certain'' ' +
    'JOIN symbols s ON s.id = COALESCE(ce.target_symbol_id, r.symbol_id) ' +
    'JOIN files sf ON sf.id = s.file_id ' +
    'WHERE r.inc_variant = 0 ' +
    'AND r.kind IN (''call'',''read'',''write'',''write-through'',''type_use'',''member-access'',''property-spec'',''record-field'') ' +
    'AND s.kind NOT IN (''local_var'',''param'') ' +
    'ORDER BY ((r.id * 2654435761) + (' + IntToStr(pSeed) + ' * 2246822519)) % 4294967296, r.id ' +
    'LIMIT ' + IntToStr(pSample);
end;

{ file:///c%3A/x/y.pas -> c:\x\y.pas }
function UriToPath(const pUri: string): string;
begin
  Result:= pUri;
  if Result.StartsWith(FILE_URI) then Result:= Copy(Result, Length(FILE_URI) + 1, MaxInt);
  Result:= StringReplace(TNetEncoding.URL.Decode(Result), '/', '\', [rfReplaceAll]);
end;

function PathToUri(const pPath: string): string;
var
  Encoded: string;
begin
  Encoded:= TNetEncoding.URL.EncodePath(StringReplace(pPath, '\', '/', [rfReplaceAll]));
  if Encoded.StartsWith('/') then Encoded:= Copy(Encoded, 2, MaxInt);
  Result:= FILE_URI + Encoded;
end;

{ The start line node at pPrimary, else at pFallback; nil when neither exists. }
function StartLineOf(pObj: TJSONObject; const pPrimary, pFallback: string): TJSONValue;
begin
  Result:= nil;
  if not (pObj.TryGetValue<TJSONValue>(pPrimary, Result) or pObj.TryGetValue<TJSONValue>(pFallback, Result)) then Result:= nil;
end;

{ One Location or LocationLink object; False when it carries neither shape. }
function LocationOf(pObj: TJSONObject; out pLoc: TVerifyLocation): Boolean;
var
  Uri  : string;
  Start: TJSONValue;
begin
  Result:= False;
  pLoc:= Default(TVerifyLocation);
  if pObj.TryGetValue<string>('targetUri', Uri) then
    Start:= StartLineOf(pObj, 'targetSelectionRange.start.line', 'targetRange.start.line')
  else if pObj.TryGetValue<string>('uri', Uri) then
    Start:= StartLineOf(pObj, 'range.start.line', 'range.start.line')
  else
    Exit;
  if Start is not TJSONNumber then Exit;
  pLoc.Path:= UriToPath(Uri);
  pLoc.Line:= TJSONNumber(Start).AsInt + 1;
  Result:= True;
end;
function ParseDefinitionLocations(const pResult: TJSONValue): TArray<TVerifyLocation>;
var
  Loc: TVerifyLocation;
  Item: TJSONValue;
begin
  Result:= nil;
  if pResult is TJSONObject then
  begin
    if LocationOf(TJSONObject(pResult), Loc) then Result:= [Loc];
  end
  else if pResult is TJSONArray then
    for Item in TJSONArray(pResult) do
      if (Item is TJSONObject) and LocationOf(TJSONObject(Item), Loc) then Result:= Result + [Loc];
end;

function ClassifyLocations(const pRow: TVerifyRow; const pLocs: TArray<TVerifyLocation>): TVerifyOutcome;
var
  Loc    : TVerifyLocation;
  Expect : string;
begin
  if Length(pLocs) = 0 then Exit(voEmpty);
  Expect:= ExpandFileName(pRow.SymPath);
  for Loc in pLocs do
    if SameText(ExpandFileName(Loc.Path), Expect)
      and (InRange(Loc.Line, pRow.DeclLine, pRow.DeclEnd) or ((pRow.ImplLine > 0) and (Loc.Line = pRow.ImplLine))) then
      Exit(voMatch);
  Result:= voMismatch;
end;

function SkipReason(const pRow: TVerifyRow; const pLineText: string): string;
var
  i: Integer;
begin
  for i:= 1 to pRow.Col - 1 do
    if (i <= Length(pLineText)) and (Ord(pLineText[i]) > ASCII_MAX) then Exit('non-ascii');
  Result:= if SameText(Copy(pLineText, pRow.Col, Length(pRow.Name)), pRow.Name) and (pRow.Name <> '') then '' else 'moved';
end;

function MismatchRate(const pCounts: TVerifyCounts): Double;
var
  Den: Integer;
begin
  Den:= pCounts.Match + pCounts.Mismatch;
  if Den = 0 then Exit(0);
  Result:= pCounts.Mismatch / Den;
end;

function SummaryLine(const pDb: string; pSample, pSeed: Integer; const pCounts: TVerifyCounts): string;
begin
  Result:= Format('verify-index: db=%s sample=%d seed=%d match=%d mismatch=%d empty=%d error=%d skipped=%d rate=%s%%',
    [pDb, pSample, pSeed, pCounts.Match, pCounts.Mismatch, pCounts.Empty, pCounts.Error, pCounts.Skipped,
     FormatFloat('0.0', MismatchRate(pCounts) * PERCENT, TFormatSettings.Invariant)]);
end;

function LspText(const pRow: TVerifyRow): string;
var
  Loc: TVerifyLocation;
begin
  if pRow.Outcome in [voError, voSkipped] then Exit(pRow.Detail);
  Result:= '';
  for Loc in pRow.Lsp do
    Result:= Result + IfThen(Result <> '', ';', '') + Format('%s:%d', [Loc.Path, Loc.Line]);
  if Result = '' then Result:= '-';
end;

function RowLine(const pRow: TVerifyRow): string;
var
  Decl: string;
begin
  Decl:= IntToStr(pRow.DeclLine);
  if pRow.ImplLine > 0 then Decl:= Decl + '/' + IntToStr(pRow.ImplLine);
  Result:= OUTCOME_NAMES[pRow.Outcome] + #9 + Format('%s:%d:%d', [pRow.RefPath, pRow.Line, pRow.Col]) + #9 +
    pRow.Name + #9 + pRow.Kind + #9 + Format('dl=%s @ %s:%s', [pRow.QName, pRow.SymPath, Decl]) + #9 +
    'lsp=' + LspText(pRow);
end;

function ReportJson(const pOpts: TVerifyOptions; const pExe: string; const pCounts: TVerifyCounts;
  const pRows: TArray<TVerifyRow>): TJSONObject;
var
  Counts: TJSONObject;
  Rows  : TJSONArray;
  Row   : TVerifyRow;
  RowObj: TJSONObject;
  DlObj : TJSONObject;
  Lsp   : TJSONArray;
  Loc   : TVerifyLocation;
  LocObj: TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('verb', 'verify-index');
  Result.AddPair('db', pOpts.DbPath);
  Result.AddPair('delphiLsp', pExe);
  Result.AddPair('config', pOpts.ConfigPath);
  Result.AddPair('sample', TJSONNumber.Create(pOpts.Sample));
  Result.AddPair('seed', TJSONNumber.Create(pOpts.Seed));
  Counts:= TJSONObject.Create;
  Counts.AddPair('match', TJSONNumber.Create(pCounts.Match));
  Counts.AddPair('mismatch', TJSONNumber.Create(pCounts.Mismatch));
  Counts.AddPair('empty', TJSONNumber.Create(pCounts.Empty));
  Counts.AddPair('error', TJSONNumber.Create(pCounts.Error));
  Counts.AddPair('skipped', TJSONNumber.Create(pCounts.Skipped));
  Result.AddPair('counts', Counts);
  Result.AddPair('rate', TJSONNumber.Create(RoundTo(MismatchRate(pCounts), RATE_DECIMALS)));
  Rows:= TJSONArray.Create;
  Result.AddPair('rows', Rows);
  for Row in pRows do
  begin
    RowObj:= TJSONObject.Create;
    RowObj.AddPair('outcome', OUTCOME_NAMES[Row.Outcome]);
    RowObj.AddPair('refId', TJSONNumber.Create(Row.RefId));
    RowObj.AddPair('file', Row.RefPath);
    RowObj.AddPair('line', TJSONNumber.Create(Row.Line));
    RowObj.AddPair('col', TJSONNumber.Create(Row.Col));
    RowObj.AddPair('name', Row.Name);
    RowObj.AddPair('kind', Row.Kind);
    DlObj:= TJSONObject.Create;
    DlObj.AddPair('qname', Row.QName);
    DlObj.AddPair('path', Row.SymPath);
    DlObj.AddPair('line', TJSONNumber.Create(Row.DeclLine));
    DlObj.AddPair('endLine', TJSONNumber.Create(Row.DeclEnd));
    DlObj.AddPair('implLine', TJSONNumber.Create(Row.ImplLine));
    RowObj.AddPair('dl', DlObj);
    Lsp:= TJSONArray.Create;
    for Loc in Row.Lsp do
    begin
      LocObj:= TJSONObject.Create;
      LocObj.AddPair('path', Loc.Path);
      LocObj.AddPair('line', TJSONNumber.Create(Loc.Line));
      Lsp.AddElement(LocObj);
    end;
    RowObj.AddPair('lsp', Lsp);
    RowObj.AddPair('detail', Row.Detail);
    Rows.AddElement(RowObj);
  end;
end;

{ ---- the run ---------------------------------------------------------------------------- }

function Fail(const pMsg: string): Integer;
begin
  Writeln(ErrOutput, 'ERROR: verify-index: ', pMsg);
  Result:= 2;
end;

function LoadSample(const pDb: string; pSample, pSeed: Integer): TArray<TVerifyRow>;
var
  Idx : TChartsIndex;
  Rows: TObjectList<TIndexRow>;
  R   : TIndexRow;
  Row : TVerifyRow;
begin
  Result:= nil;
  Idx:= TChartsIndex.Create(pDb);
  try
    Rows:= Idx.Query(VerifySampleSql(pSample, pSeed));
    try
      for R in Rows do
      begin
        Row:= Default(TVerifyRow);
        Row.RefId   := StrToInt64Def(R.S('ref_id'), 0);
        Row.Kind    := R.S('kind');
        Row.Name    := R.S('name');
        Row.RefPath := R.S('ref_path');
        Row.Line    := R.I('line');
        Row.Col     := R.I('col');
        Row.QName   := R.S('qname');
        Row.SymPath := R.S('sym_path');
        Row.DeclLine:= R.I('decl_line');
        Row.DeclEnd := R.I('decl_end');
        Row.ImplLine:= R.I('impl_line');
        Row.Outcome := voSampled;
        Result:= Result + [Row];
      end;
    finally
      Rows.Free;
    end;
  finally
    Idx.Free;
  end;
end;

{ The `settings` object of a .delphilsp.json as JSON text; '' when absent. }
function SettingsText(const pConfig: string): string;
var
  Json: TJSONValue;
  Sett: TJSONValue;
begin
  Result:= '';
  Json:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pConfig, TEncoding.UTF8));
  try
    if Json is not TJSONObject then Exit;
    Sett:= TJSONObject(Json).GetValue('settings');
    if Sett is TJSONObject then Result:= Sett.ToJSON;
  finally
    Json.Free;
  end;
end;

function ParamsOf(const pJson: string): TJSONValue;
begin
  Result:= TJSONObject.ParseJSONValue(pJson);
end;

procedure Tally(var pCounts: TVerifyCounts; pOutcome: TVerifyOutcome);
begin
  case pOutcome of
    voMatch   : Inc(pCounts.Match);
    voMismatch: Inc(pCounts.Mismatch);
    voEmpty   : Inc(pCounts.Empty);
    voError   : Inc(pCounts.Error);
    voSkipped : Inc(pCounts.Skipped);
  end;
end;

procedure Render(const pOpts: TVerifyOptions; const pExe: string; const pCounts: TVerifyCounts;
  const pRows: TArray<TVerifyRow>);
var
  Doc    : TJSONObject;
  Row    : TVerifyRow;
  Listed : TArray<TVerifyRow>;
begin
  for Row in pRows do
    if Row.Outcome <> voMatch then Listed:= Listed + [Row];
  if pOpts.Json then
  begin
    Doc:= ReportJson(pOpts, pExe, pCounts, Listed);
    try
      Writeln(Doc.ToJSON);
    finally
      Doc.Free;
    end;
    Exit;
  end;
  if pOpts.DryRun then
    Writeln(Format('verify-index: db=%s sample=%d seed=%d dry-run sampled=%d', [pOpts.DbPath, pOpts.Sample, pOpts.Seed, Length(pRows)]))
  else
    Writeln(SummaryLine(pOpts.DbPath, pOpts.Sample, pOpts.Seed, pCounts));
  for Row in Listed do Writeln(RowLine(Row));
end;

{ Asks DelphiLSP for one row; sets Outcome / Lsp / Detail. voEmpty = no answer (the caller may retry). }
procedure AskDefinition(pClient: TLspVerifyClient; const pUri: string; var pRow: TVerifyRow; pTimeoutMs: Integer);
var
  Params: TJSONObject;
  Doc   : TJSONObject;
  PosObj: TJSONObject;
  Res   : TJSONValue;
  Err   : string;
begin
  Doc:= TJSONObject.Create;
  Doc.AddPair('uri', pUri);
  PosObj:= TJSONObject.Create;
  PosObj.AddPair('line', TJSONNumber.Create(pRow.Line - 1));
  PosObj.AddPair('character', TJSONNumber.Create(pRow.Col - 1));
  Params:= TJSONObject.Create;
  Params.AddPair('textDocument', Doc);
  Params.AddPair('position', PosObj);
  if not pClient.Request('textDocument/definition', Params, pTimeoutMs, Res, Err) then
  begin
    pRow.Outcome:= voError;
    pRow.Detail:= Err;
    Exit;
  end;
  try
    pRow.Lsp:= ParseDefinitionLocations(Res);
    pRow.Outcome:= ClassifyLocations(pRow, pRow.Lsp);
    pRow.Detail:= '';
  finally
    Res.Free;
  end;
end;

{ The reply to a workspace/configuration request: the settings once per requested item (AC18);
  null for any other server request. }
function ConfigurationReply(const pSett, pMethod: string; pParams: TJSONValue): string;
var
  Items: TJSONValue;
  n    : Integer;
  k    : Integer;
begin
  Result:= 'null';
  if pMethod <> 'workspace/configuration' then Exit;
  n:= 1;
  if pParams is TJSONObject then
  begin
    Items:= TJSONObject(pParams).GetValue('items');
    if Items is TJSONArray then n:= TJSONArray(Items).Count;
  end;
  Result:= '[';
  for k:= 1 to n do Result:= Result + IfThen(k > 1, ',', '') + pSett;
  Result:= Result + ']';
end;

{ Reads the .delphilsp.json settings and resolves the DelphiLSP executable (AC15, AC20, AC21).
  '' = ready, else the error text. }
function ResolveSetup(var pOpts: TVerifyOptions; out pSett, pExe: string): string;
var
  Cfg : string;
  Bits: Integer;
begin
  Result:= '';
  pSett:= '';
  pExe:= '';
  Cfg:= pOpts.ConfigPath;
  if (Cfg = '') and (pOpts.ProjectPath <> '') then Cfg:= ChangeFileExt(pOpts.ProjectPath, '.delphilsp.json');
  if Cfg = '' then Exit('no .delphilsp.json: give --delphi-lsp-config <file> or --project <x.dproj>');
  if not TFile.Exists(Cfg) then Exit('.delphilsp.json not found: ' + Cfg);
  pOpts.ConfigPath:= Cfg;
  try
    pSett:= SettingsText(Cfg);
  except
    on E: Exception do Exit('cannot read ' + Cfg + ': ' + E.Message);
  end;
  if pSett = '' then Exit('no "settings" object in ' + Cfg);
  Bits:= if pOpts.DelphiLspBits = LSP_BITS_32 then LSP_BITS_32 else LSP_BITS_64;
  pExe:= ResolveDelphiLspPath(pOpts.DelphiLspExe, Bits);
  if (pExe = '') or not TFile.Exists(pExe) then
    Result:= 'DelphiLSP executable not found: ' + (if pExe <> '' then pExe else pOpts.DelphiLspExe);
end;

{ Starts the child and performs the LSP handshake plus the warm-up wait (AC16). '' = ready. }
function StartSession(pClient: TLspVerifyClient; const pOpts: TVerifyOptions; pSett: string): string;
var
  Res    : TJSONValue;
  Err    : string;
  Root   : string;
  InitPar: TJSONObject;
  CfgPar : TJSONObject;
begin
  Result:= '';
  pClient.OnServerRequest:=
    function(pMethod: string; pParams: TJSONValue): string
    begin
      Result:= ConfigurationReply(pSett, pMethod, pParams);
    end;
  try
    pClient.Start;
  except
    on E: Exception do Exit('cannot start DelphiLSP: ' + E.Message);
  end;
  Root:= ExtractFilePath(ExpandFileName(if pOpts.ProjectPath <> '' then pOpts.ProjectPath else pOpts.DbPath));
  InitPar:= TJSONObject.Create;
  InitPar.AddPair('processId', TJSONNumber.Create(Integer(GetCurrentProcessId)));
  InitPar.AddPair('rootUri', PathToUri(ExcludeTrailingPathDelimiter(Root)));
  InitPar.AddPair('capabilities', TJSONObject.Create);
  InitPar.AddPair('initializationOptions', ParamsOf(pSett));
  if not pClient.Request('initialize', InitPar, pOpts.TimeoutMs, Res, Err) then
    Exit('DelphiLSP did not answer initialize: ' + Err);
  Res.Free;
  pClient.Notify('initialized', TJSONObject.Create);
  CfgPar:= TJSONObject.Create;
  CfgPar.AddPair('settings', ParamsOf(pSett));
  pClient.Notify('workspace/didChangeConfiguration', CfgPar);
  pClient.Pump(pOpts.WarmupMs);
end;

{ AC10: reads the row's file once (cached) and applies the skip checks. True = DelphiLSP may be asked;
  False = the row is already classified (skipped). }
function RowIsAskable(var pRow: TVerifyRow; pCache: TDictionary<string, TArray<string>>): Boolean;
var
  Lines: TArray<string>;
begin
  if not pCache.TryGetValue(pRow.RefPath, Lines) then
  begin
    try
      Lines:= TFile.ReadAllLines(pRow.RefPath);
    except
      on Exception do Lines:= nil;
    end;
    pCache.Add(pRow.RefPath, Lines);
  end;
  pRow.Detail:= '';
  if Length(Lines) = 0 then
    pRow.Detail:= 'unreadable'
  else if (pRow.Line < 1) or (pRow.Line > Length(Lines)) then
    pRow.Detail:= 'moved'
  else
    pRow.Detail:= SkipReason(pRow, Lines[pRow.Line - 1]);
  Result:= pRow.Detail = '';
  if not Result then pRow.Outcome:= voSkipped;
end;

{ AC17: textDocument/didOpen once per sampled file. }
procedure OpenDocument(pClient: TLspVerifyClient; pOpened: TDictionary<string, Boolean>; const pPath, pUri: string);
var
  Doc: TJSONObject;
  Par: TJSONObject;
begin
  if pOpened.ContainsKey(pPath) then Exit;
  pOpened.Add(pPath, True);
  Doc:= TJSONObject.Create;
  Doc.AddPair('uri', pUri);
  Doc.AddPair('languageId', 'delphi');
  Doc.AddPair('version', TJSONNumber.Create(1));
  Doc.AddPair('text', TFile.ReadAllText(pPath));
  Par:= TJSONObject.Create;
  Par.AddPair('textDocument', Doc);
  pClient.Notify('textDocument/didOpen', Par);
end;

{ Asks every askable row in sample order, then retries the empty answers once (AC8). }
procedure AskAll(pClient: TLspVerifyClient; pTimeoutMs: Integer; var pRows: TArray<TVerifyRow>);
var
  Cache : TDictionary<string, TArray<string>>;
  Opened: TDictionary<string, Boolean>;
  Retry : TList<Integer>;
  i     : Integer;
  Uri   : string;
begin
  Cache:= TDictionary<string, TArray<string>>.Create;
  Opened:= TDictionary<string, Boolean>.Create;
  Retry:= TList<Integer>.Create;
  try
    for i:= 0 to High(pRows) do
    begin
      if not RowIsAskable(pRows[i], Cache) then Continue;
      Uri:= PathToUri(pRows[i].RefPath);
      OpenDocument(pClient, Opened, pRows[i].RefPath, Uri);
      AskDefinition(pClient, Uri, pRows[i], pTimeoutMs);
      if pRows[i].Outcome = voEmpty then Retry.Add(i);
    end;
    for i in Retry do
      if InRange(i, 0, High(pRows)) then
        AskDefinition(pClient, PathToUri(pRows[i].RefPath), pRows[i], pTimeoutMs);   { still empty stays voEmpty }
  finally
    Retry.Free;
    Opened.Free;
    Cache.Free;
  end;
end;

function RunVerifyIndex(const pOpts: TVerifyOptions): Integer;
var
  Opts  : TVerifyOptions;
  Rows  : TArray<TVerifyRow>;
  Counts: TVerifyCounts;
  Sett  : string;
  Exe   : string;
  Err   : string;
  Client: TLspVerifyClient;
  i     : Integer;
begin
  Opts:= pOpts;
  if Opts.Sample <= 0 then Opts.Sample:= VERIFY_DEFAULT_SAMPLE;
  if Opts.Seed = 0 then Opts.Seed:= VERIFY_DEFAULT_SEED;
  if Opts.TimeoutMs <= 0 then Opts.TimeoutMs:= VERIFY_DEFAULT_TIMEOUT;
  if Opts.WarmupMs < 0 then Opts.WarmupMs:= VERIFY_DEFAULT_WARMUP;
  Counts:= Default(TVerifyCounts);
  if (Opts.DbPath = '') or not TFile.Exists(Opts.DbPath) then Exit(Fail('database not found: ' + Opts.DbPath));
  try
    Rows:= LoadSample(Opts.DbPath, Opts.Sample, Opts.Seed);
  except
    on E: Exception do Exit(Fail('cannot read the index: ' + E.Message));
  end;
  if Opts.DryRun then
  begin
    Render(Opts, '', Counts, Rows);
    Exit(0);
  end;
  Err:= ResolveSetup(Opts, Sett, Exe);
  if Err <> '' then Exit(Fail(Err));
  Client:= TLspVerifyClient.Create(Exe, Opts.TraceFile);
  try
    Err:= StartSession(Client, Opts, Sett);
    if Err = '' then AskAll(Client, Opts.TimeoutMs, Rows);
  finally
    Client.Shutdown;
    Client.Free;
  end;
  if Err <> '' then Exit(Fail(Err));
  for i:= 0 to High(Rows) do Tally(Counts, Rows[i].Outcome);
  Render(Opts, Exe, Counts, Rows);
  Result:= if Counts.Mismatch > 0 then 1 else 0;
end;

{ ---- CLI entry -------------------------------------------------------------------------- }

function FlagValue(const pFlag: string; out pValue: string): Boolean;
var
  i: Integer;
begin
  Result:= False;
  pValue:= '';
  for i:= 1 to ParamCount - 1 do
    if ParamStr(i) = pFlag then
    begin
      pValue:= ParamStr(i + 1);
      Exit(True);
    end;
end;

function FlagInt(const pFlag: string; pDefault: Integer): Integer;
var
  Text: string;
begin
  Result:= pDefault;
  if not FlagValue(pFlag, Text) then Exit;
  if not TryStrToInt(Text, Result) then
    raise EVerifyUsage.CreateFmt('%s must be a whole number, got: %s', [pFlag, Text]);
end;

function RunVerifyIndexVerb(const pArgs: TArgs): Integer;
var
  Opts: TVerifyOptions;
begin
  Opts:= Default(TVerifyOptions);
  Opts.DbPath:= pArgs.DbPath;
  Opts.ProjectPath:= pArgs.ProjectPath;
  Opts.DelphiLspExe:= pArgs.LspDelphiExe;
  Opts.DelphiLspBits:= pArgs.LspDelphiBits;
  Opts.TimeoutMs:= pArgs.TimeoutMs;
  Opts.TraceFile:= pArgs.LspTraceFile;
  Opts.DryRun:= pArgs.DryRun;
  Opts.Json:= pArgs.AsJson or SameText(pArgs.Format, 'json');
  Opts.Sample:= FlagInt('--sample', 0);
  Opts.Seed:= FlagInt('--seed', 0);
  Opts.WarmupMs:= FlagInt('--warmup-ms', -1);
  FlagValue('--delphi-lsp-config', Opts.ConfigPath);
  if Opts.Sample < 0 then raise EVerifyUsage.Create('--sample must be at least 1');
  Result:= RunVerifyIndex(Opts);
end;

end.