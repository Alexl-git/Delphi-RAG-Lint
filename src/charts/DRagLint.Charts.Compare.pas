unit DRagLint.Charts.Compare;

{ The orchestration of `drag-lint compare` (spec C1-C6, D8, S1a-S1c, S3, S4a): load the
  OLD side from one of five sources, decide which command to rerun, obtain the NEW side
  through an IReportProducer, pick the adapter, diff, and carry out the two side effects
  (snapshot, update-doc). Everything a renderer or the CLI prints comes back in one
  TCompareResult; this unit prints nothing and never raises for a refusal.
  PS trap handled: question ids, argument names and project paths are compared with
  SameText (PowerShell -eq is case-insensitive); exit codes are compared as integers. }

interface

uses
  DRagLint.Charts.Diff, DRagLint.Charts.ReportHeader, DRagLint.Charts.Adapters,
  DRagLint.Charts.Adapter.Graph, DRagLint.Charts.Producer; // dl:unit DRagLint.Charts.Producer accepted -- PRODUCER_EXIT_STALE travels with the producer seam that returns it; compare maps it to its own stale exit

const
  /// <summary>The C2 warning: the old report carries no COMMAND line.</summary>
  WARN_NO_COMMAND = 'The original command is unknown -- this may not be the same question.';
  /// <summary>C6: no differences.</summary>
  COMPARE_EXIT_SAME = 0;
  /// <summary>C6: differences found.</summary>
  COMPARE_EXIT_DIFFERENT = 1;
  /// <summary>C6: setup or usage error; TCompareResult.Message says why.</summary>
  COMPARE_EXIT_SETUP = 2;
  /// <summary>C6: the index of the new run is stale; no diff is returned.</summary>
  COMPARE_EXIT_STALE = 3;
  /// <summary>Equal items kept around each change in a hunk.</summary>
  COMPARE_CONTEXT = 3;

type
  /// <summary>Where the OLD side comes from.</summary>
  /// <remarks>csFile: a saved report, forms CSV, .dot or bundle folder (OldPath).
  /// csRemarks: the '/// &lt;remarks&gt;' block around OldLine of the unit OldPath (S1).
  /// csAutoSnapshot: the newest snapshot under &lt;SnapshotDir&gt;\auto (S3).
  /// csOldIndex: the same question answered from the index copy OldDb (S4a).
  /// csTwoFiles: OldPath against NewPath, nothing is rerun.</remarks>
  TCompareSource = (csFile, csRemarks, csAutoSnapshot, csOldIndex, csTwoFiles);

  /// <summary>What to compare and how.</summary>
  TCompareRequest = record
    /// <summary>Where the old side comes from.</summary>
    Source      : TCompareSource;
    /// <summary>csFile / csTwoFiles: the old file or bundle folder; csRemarks: the unit.</summary>
    OldPath     : string;
    /// <summary>csRemarks: a 1-based line inside the remarks block.</summary>
    OldLine     : Integer;
    /// <summary>csTwoFiles only: the new file or bundle folder.</summary>
    NewPath     : string;
    /// <summary>csOldIndex: the old index copy the old side is answered from.</summary>
    OldDb       : string;
    /// <summary>The caller's command (--command, or --question/--target/--project); may be empty.</summary>
    Command     : TReportCommand;
    /// <summary>--project: replaces or adds -Project on the command that is run.</summary>
    ProjectFile : string;
    /// <summary>The snapshot folder; '' resolves it with ResolveSnapshotDir.</summary>
    SnapshotDir : string;
    /// <summary>--save: write the new answer as a snapshot (into auto\ for csAutoSnapshot).</summary>
    SaveSnapshot: Boolean;
    /// <summary>--update-doc: replace the remarks block with the new answer (csRemarks only).</summary>
    UpdateDoc   : Boolean;
    /// <summary>Produces the new side (and the old side for csOldIndex); unused for csTwoFiles.</summary>
    Producer    : IReportProducer;
    /// <summary>Options for the new run; csOldIndex derives the old run's from them.</summary>
    Options     : TProduceOptions;
    /// <summary>The time stamped on snapshots and update-doc; 0 means the clock.</summary>
    Now         : TDateTime;
    /// <summary>The temp file the old chart's SVG is copied to before a rerun; '' lets RunCompare
    /// name one in the temp folder.</summary>
    /// <remarks>Named by the caller so that it can delete the copy on every path, an exception
    /// raised by RunCompare after the copy was taken included. Must not exist yet.</remarks>
    OldSvgCopy  : string;
  end;

  /// <summary>Freshness facts of one index the new run read (C5).</summary>
  TIndexFact = record
    /// <summary>The index path, as the INDEX line named it.</summary>
    Db        : string;
    /// <summary>True when the freshness sweep found changed member files.</summary>
    Stale     : Boolean;
    /// <summary>How many member files changed since the index was built.</summary>
    StaleFiles: Integer;
    /// <summary>'yyyy-mm-dd hh:nn' local time of the last completed index run; '' when the
    /// index file is not there.</summary>
    IndexedAt : string;
  end;

  /// <summary>Everything a compare found.</summary>
  /// <remarks>On exit 2 or 3 only Message, Warnings and what was loaded before the refusal
  /// are set; Edits and Hunks are empty.</remarks>
  TCompareResult = record
    /// <summary>C6: one of the COMPARE_EXIT_* codes.</summary>
    ExitCode   : Integer;
    /// <summary>C2 / C3 warnings, and any side-effect that did not happen.</summary>
    Warnings   : TArray<string>;
    /// <summary>The format both sides are in.</summary>
    Format     : TChartsFormat;
    /// <summary>The old report's header (empty for a CSV or graph).</summary>
    OldHeader  : TReportHeader;
    /// <summary>The new report's header (empty for a CSV or graph from a file).</summary>
    NewHeader  : TReportHeader;
    /// <summary>Freshness facts of every index the new run read.</summary>
    NewIndexes : TArray<TIndexFact>;
    /// <summary>The old side as diff items.</summary>
    OldItems   : TArray<TDiffItem>;
    /// <summary>The new side as diff items.</summary>
    NewItems   : TArray<TDiffItem>;
    /// <summary>The edit script from OldItems to NewItems.</summary>
    Edits      : TArray<TDiffEdit>;
    /// <summary>The edit script grouped with COMPARE_CONTEXT items of context.</summary>
    Hunks      : TArray<TDiffHunk>;
    /// <summary>The old side as read (for a graph, the DOT text).</summary>
    OldText    : string;
    /// <summary>The new side as read or produced (for a graph, the DOT text).</summary>
    NewText    : string;
    /// <summary>cfGraph only: the old chart.</summary>
    OldGraph   : TGraphModel;
    /// <summary>cfGraph only: the new chart.</summary>
    NewGraph   : TGraphModel;
    /// <summary>cfGraph only: the old chart's SVG, '' when none. After a rerun this is a
    /// temp copy taken before the rerun (the bundle folder may be rewritten); the caller may
    /// delete it.</summary>
    OldSvgPath : string;
    /// <summary>cfGraph only: the new chart's SVG, '' when none.</summary>
    NewSvgPath : string;
    /// <summary>The refusal on exit 2 or 3; '' otherwise.</summary>
    Message    : string;
    /// <summary>The snapshot written, '' when none.</summary>
    SnapshotPath: string;
    /// <summary>The unit update-doc rewrote, '' when none.</summary>
    UpdatedFile: string;
    /// <summary>Where the old side came from (copied from the request; for the renderers).</summary>
    OldSource  : TCompareSource;
    /// <summary>csFile / csTwoFiles / csRemarks: the old path; csOldIndex: the old index copy;
    /// csAutoSnapshot: the snapshot file found.</summary>
    OldPath    : string;
    /// <summary>csRemarks: the 1-based line the caller named; 0 otherwise.</summary>
    OldLine    : Integer;
  end;

/// <summary>Runs one compare (spec C1-C6, D8, S1, S3, S4a).</summary>
/// <param name="pRequest">What to compare; see TCompareRequest.</param>
/// <returns>The result; ExitCode 0 or 1 carries the diff, 2 a setup refusal and 3 a stale
/// new index, each with Message.</returns>
/// <remarks>The command run is the old report's COMMAND, or the caller's when the old one
/// is missing (warning WARN_NO_COMMAND) or differs (a warning naming each differing
/// argument; the caller's wins); an auto snapshot's own COMMAND counts as the old one, the
/// caller's command only locating the snapshot. The new run never passes AllowStale, whatever
/// pRequest.Options says (only the S4 old side does). A graph's old DOT is read into memory
/// and its SVG copied to pRequest.OldSvgCopy (or a temp file) before the rerun, because a rerun may overwrite the
/// bundle folder. --save with csTwoFiles is refused. A snapshot is saved with the extension
/// its format is detected by (.txt, .csv, .dot). Snapshot and update-doc happen only on
/// exit 0 or 1; a failed snapshot is a warning, a failed update-doc is exit 2 with the rest
/// of the result intact. Calls the producer from the calling thread; not thread-safe for
/// two calls that update the same unit.</remarks>
function RunCompare(const pRequest: TCompareRequest): TCompareResult;

implementation

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  DRagLint.Core.Interfaces, DRagLint.Storage.SQLite, DRagLint.Index.Freshness, // dl:unit DRagLint.Index.Freshness accepted -- INDEXED_AT_KEY names the meta row the freshness module writes, so the --old-db age check reads the same key
  DRagLint.Charts.Remarks, DRagLint.Charts.Snapshot, DRagLint.Charts.DocInsight; // dl:unit DRagLint.Charts.Snapshot, DRagLint.Charts.DocInsight accepted -- the three snapshot extensions name the formats Snapshot writes; DOCINSIGHT_UNKNOWN_PHRASE is the phrase the formatter writes for an unknown question

const
  CRLF = #13#10;
  ARG_PROJECT = 'Project';
  ARG_TARGET = 'Target';
  ARG_TO = 'To';
  PATH_ARROW = ' -> ';
  AUTO_SUBDIR = 'auto';
  STAMP_FORMAT = 'yyyy-mm-dd hh:nn';
  MB_ERR_INVALID_CHARS = 8;
  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);
  SVG_EXT = '.svg';
  RERUN_HINT = ' -- pass --command "<id> -Target ... -Project ..."';

procedure AddWarning(var pResult: TCompareResult; const pText: string);
begin
  pResult.Warnings:= pResult.Warnings + [pText];
end;

{ Records a refusal; returns False so a step can 'Exit(Refuse(...))'. }
function Refuse(var pResult: TCompareResult; pCode: Integer; const pMessage: string): Boolean;
begin
  pResult.ExitCode:= pCode;
  pResult.Message:= pMessage;
  pResult.Edits:= [];
  pResult.Hunks:= [];
  Result:= False;
end;

{ A text file's content: a UTF-8 BOM is dropped, valid UTF-8 is decoded as UTF-8 (an
  Ask-Report answer and a snapshot are UTF-8 without BOM and carry em dashes), anything
  else is ANSI -- mirroring how ReplaceRemarksBlockInFile decodes, so the lines a block
  is found on are the lines it is replaced on. }
function ReadTextFile(const pPath: string): string;
begin
  var Bytes:= TFile.ReadAllBytes(pPath);
  var Skip:= 0;
  if (Length(Bytes) >= Length(UTF8_BOM)) and (Bytes[0] = UTF8_BOM[0]) and (Bytes[1] = UTF8_BOM[1])
    and (Bytes[2] = UTF8_BOM[2]) then
    Skip:= Length(UTF8_BOM);
  var Strict:= TUTF8Encoding.Create(TEncoding.UTF8.CodePage, MB_ERR_INVALID_CHARS, 0);
  try
    try
      Result:= Strict.GetString(Bytes, Skip, Length(Bytes) - Skip);
    except
      on EEncodingError do
        Result:= TEncoding.ANSI.GetString(Bytes, Skip, Length(Bytes) - Skip);
    end;
  finally
    Strict.Free;
  end;
end;

{ Loads one side from a path: a chart (folder with graph.dot, or a .dot) through
  LoadGraphSource, anything else as text. A path whose extension says nothing is
  decided by its content. }
function LoadSide(const pPath: string; out pText, pSvg: string; out pFormat: TChartsFormat;
  out pWhy: string): Boolean;
begin
  pText:= '';
  pSvg:= '';
  pWhy:= '';
  pFormat:= DetectFormat(pPath, True);
  if pFormat = cfGraph then
  begin
    Result:= LoadGraphSource(pPath, pText, pSvg);
    if not Result then
      pWhy:= 'cannot read a chart graph from ' + pPath;
    Exit;
  end;
  Result:= False;
  if TDirectory.Exists(pPath) then
    pWhy:= pPath + ' is a folder without graph.dot -- name the report, CSV or .dot file itself'
  else if not TFile.Exists(pPath) then
    pWhy:= 'no such file: ' + pPath
  else
  begin
    try
      pText:= ReadTextFile(pPath);
    except
      on E: Exception do
      begin
        pWhy:= 'cannot read ' + pPath + ': ' + E.Message;
        Exit;
      end;
    end;
    if pFormat = cfUnknown then
      pFormat:= DetectFormat(pText, False);
    Result:= True;
  end;
end;

function HeaderOf(const pText: string): TReportHeader;
begin
  if not ParseReportHeader(SplitAnswerLines(pText), Result) then
    Result:= Default(TReportHeader);
end;

procedure SetArg(var pCmd: TReportCommand; const pName, pValue: string);
begin
  for var I:= 0 to High(pCmd.Args) do
    if SameText(pCmd.Args[I].Name, pName) then
    begin
      pCmd.Args[I].Value:= pValue;
      Exit;
    end;
  var Arg: TCommandArg;
  Arg.Name:= pName;
  Arg.Value:= pValue;
  pCmd.Args:= pCmd.Args + [Arg];
end;

function TargetWithTo(const pCmd: TReportCommand): string;
begin
  Result:= pCmd.Get(ARG_TARGET);
  if pCmd.Has(ARG_TO) then
    Result:= Result + PATH_ARROW + pCmd.Get(ARG_TO);
end;

{ --project replaces or adds -Project; a different path than the command's is warned. }
procedure ApplyProject(var pCmd: TReportCommand; const pProjectFile: string; var pResult: TCompareResult);
begin
  if pProjectFile = '' then
    Exit;
  var Prev:= pCmd.Get(ARG_PROJECT);
  if (Prev <> '') and not SameText(ExpandFileName(Prev), ExpandFileName(pProjectFile)) then
    AddWarning(pResult, 'The given --project differs from the COMMAND''s -Project: ' + Prev + ' vs ' + pProjectFile);
  SetArg(pCmd, ARG_PROJECT, pProjectFile);
end;

{ Step 3: the command to rerun, from the old report's COMMAND and the caller's (C2, C3). }
function ChooseCommand(const pOld, pGiven: TReportCommand; var pResult: TCompareResult;
  out pCmd: TReportCommand): Boolean;
begin
  pCmd:= Default(TReportCommand);
  Result:= True;
  if pOld.IsEmpty and pGiven.IsEmpty then
    Exit(False);
  if pOld.IsEmpty then
  begin
    pCmd:= pGiven;
    AddWarning(pResult, WARN_NO_COMMAND);
    Exit;
  end;
  pCmd:= if pGiven.IsEmpty then pOld else pGiven;
  var Differing: TArray<string>;
  if pGiven.IsEmpty or SameQuestion(pOld, pGiven, Differing) then
    Exit;
  // R10: SameQuestion lists arguments only; a different question id is named here.
  if not SameText(pOld.Question, pGiven.Question) then
    Differing:= ['Question: ' + pOld.Question + ' vs ' + pGiven.Question] + Differing;
  AddWarning(pResult, 'The given command differs from the report''s COMMAND: ' + string.Join('; ', Differing));
end;

{ C5: the freshness facts of one index. The stamp is the INDEXED_AT_KEY meta value the
  indexer writes after a completed run (DRagLint.Index.Freshness has no public getter for
  it, so it is read through ISymbolStore.GetMetaValue); an index older than the stamp
  falls back to the database file's last write time. }
function IndexFactFor(const pDb: string; out pFact: TIndexFact; out pWhy: string): Boolean;
begin
  pFact:= Default(TIndexFact);
  pFact.Db:= pDb;
  pWhy:= '';
  if not TFile.Exists(pDb) then
    Exit(True);
  try
    var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pDb, True);
    var Rep:= ProbeIndexFreshness(Store, 0);
    pFact.Stale:= Rep.Verdict = fvStale;
    pFact.StaleFiles:= Rep.Changed;
    var Stamp:= StrToInt64Def(Store.GetMetaValue(INDEXED_AT_KEY), 0);
    var At:= if Stamp > 0 then UnixToDateTime(Stamp, False) else TFile.GetLastWriteTime(pDb);
    pFact.IndexedAt:= FormatDateTime(STAMP_FORMAT, At, TFormatSettings.Invariant);
    Result:= True;
  except
    on E: Exception do
    begin
      pWhy:= 'cannot read the freshness of ' + pDb + ': ' + E.Message;
      Result:= False;
    end;
  end;
end;

function SnapshotDirFor(const pRequest: TCompareRequest; const pCmd: TReportCommand; const pDb: string): string;
begin
  Result:= pRequest.SnapshotDir;
  if Result = '' then
    Result:= ResolveSnapshotDir(pCmd.Get(ARG_PROJECT), pDb);
end;


{ R18: a snapshot keeps the extension its format is detected by. }
function SnapshotExtFor(pFormat: TChartsFormat): string;
begin
  case pFormat of
    cfGraph   : Result:= SNAPSHOT_EXT_GRAPH;
    cfFormsCsv: Result:= SNAPSHOT_EXT_FORMS;
  else
    Result:= SNAPSHOT_EXT_REPORT;
  end;
end;

{ A rerun may rewrite the bundle folder the old chart came from, graph.svg included: the
  old SVG is copied to pCopy (or a temp file of its own when pCopy is '') first and OldSvgPath
  points at the copy. }
function ProtectOldSvg(const pCopy: string; var pResult: TCompareResult): Boolean;
begin
  var Copy_:= if pCopy <> '' then pCopy else TPath.Combine(TPath.GetTempPath, 'drag-lint-compare-old-' + TGUID.NewGuid.ToString + SVG_EXT);
  try
    TFile.Copy(pResult.OldSvgPath, Copy_);
  except
    on E: Exception do
      Exit(Refuse(pResult, COMPARE_EXIT_SETUP, 'cannot keep the old chart ' + pResult.OldSvgPath + ': ' + E.Message));
  end;
  pResult.OldSvgPath:= Copy_;
  Result:= True;
end;

type
  { The state the steps of one RunCompare share. }
  TCompareRun = record
    Block    : TRemarksBlock;   // csRemarks: the block the old side came from
    Cmd      : TReportCommand;  // the command that is run
    CmdChosen: Boolean;         // Cmd was fixed by the old-side step (csOldIndex)
    NewFormat: TChartsFormat;   // the format the new side is in
    FirstDb  : string;          // the first index the new run read ('' when none)
    NewChart : string;          // the file or folder the new chart came from
  end;

{ D6(c): a non-blank DOT that yields no node and no edge was not read (a dialect the adapter
  does not know). Comparing it would call two different charts the same, so it is refused. }
function ChartReadable(const pModel: TGraphModel; const pText, pWhere: string; var pResult: TCompareResult): Boolean;
begin
  Result:= (Trim(pText) = '') or (Length(pModel.Nodes) > 0) or (Length(pModel.Edges) > 0);
  if not Result then
    Refuse(pResult, COMPARE_EXIT_SETUP, 'the chart ' + pWhere + ' parsed as empty -- cannot compare');
end;

function ValidateRequest(const pRequest: TCompareRequest; var pResult: TCompareResult): Boolean;
begin
  Result:= True;
  if pRequest.UpdateDoc and (pRequest.Source <> csRemarks) then
    Result:= Refuse(pResult, COMPARE_EXIT_SETUP,
      'update-doc needs a remarks block to update -- name the unit and a line inside the block')
  else if pRequest.SaveSnapshot and (pRequest.Source = csTwoFiles) then
    Result:= Refuse(pResult, COMPARE_EXIT_SETUP,
      'save needs a rerun -- comparing two files produces no new answer to keep')
  else if (pRequest.Source <> csTwoFiles) and (pRequest.Producer = nil) then
    Result:= Refuse(pResult, COMPARE_EXIT_SETUP, 'no report producer to rerun the question with');
end;

{ csOldIndex has no old report to take a COMMAND from: the caller's is the question,
  fixed before the old side is produced. }
function TakeGivenCommand(const pRequest: TCompareRequest; var pResult: TCompareResult;
  var pRun: TCompareRun): Boolean;
begin
  if pRequest.Command.IsEmpty then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP, 'an old-index compare needs the question' + RERUN_HINT));
  pRun.Cmd:= pRequest.Command;
  ApplyProject(pRun.Cmd, pRequest.ProjectFile, pResult);
  pRun.CmdChosen:= True;
  Result:= True;
end;

{ S1a/S1b: the old side is the remarks block around the caller's line, and nothing else. }
function LoadRemarksSide(const pRequest: TCompareRequest; var pResult: TCompareResult;
  var pRun: TCompareRun): Boolean;
begin
  var Lines: TArray<string>;
  try
    Lines:= SplitAnswerLines(ReadTextFile(pRequest.OldPath));
  except
    on E: Exception do
      Exit(Refuse(pResult, COMPARE_EXIT_SETUP, 'cannot read ' + pRequest.OldPath + ': ' + E.Message));
  end;
  var Why: string;
  if not FindRemarksBlockAt(Lines, pRequest.OldLine, pRun.Block, Why) then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP, Why));
  if not RemarksBlockIsReport(pRun.Block, pResult.OldHeader) then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP,
      Format('the remarks block at line %d holds no drag-lint report', [pRequest.OldLine])));
  pResult.OldText:= string.Join(CRLF, pRun.Block.Lines) + CRLF;
  pResult.Format:= cfReportText;
  Result:= True;
end;

{ S3: the old side is the newest auto snapshot of the question. The caller's command only
  LOCATES it (question, target, -Project or --project for the folder); the snapshot's own
  COMMAND then meets the caller's in ChooseCommand like any saved report (R16). }
function LoadAutoSnapshotSide(const pRequest: TCompareRequest; var pResult: TCompareResult): Boolean;
begin
  if pRequest.Command.IsEmpty then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP, 'an auto-snapshot compare needs the question' + RERUN_HINT));
  var Locator:= pRequest.Command;
  if pRequest.ProjectFile <> '' then
    SetArg(Locator, ARG_PROJECT, pRequest.ProjectFile);
  var AutoDir:= TPath.Combine(SnapshotDirFor(pRequest, Locator, ''), AUTO_SUBDIR);
  var Latest:= LatestAutoSnapshotAnyFormat(AutoDir, Locator.Question, TargetWithTo(Locator));
  if Latest = '' then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP, Format('no auto snapshot for %s %s under %s',
      [Locator.Question, TargetWithTo(Locator), AutoDir])));
  var Why: string;
  pResult.OldPath:= Latest;
  if not LoadSide(Latest, pResult.OldText, pResult.OldSvgPath, pResult.Format, Why) then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP, Why));
  Result:= True;
end;

{ S4a: the old side is the same question answered from the old index copy; that copy is
  stale by nature, so it is asked with AllowStale. }
function LoadOldIndexSide(const pRequest: TCompareRequest; var pResult: TCompareResult;
  var pRun: TCompareRun): Boolean;
begin
  if not TakeGivenCommand(pRequest, pResult, pRun) then
    Exit(False);
  var OldOpts:= pRequest.Options;
  OldOpts.DbOverride:= pRequest.OldDb;
  OldOpts.AllowStale:= True;
  var Old:= pRequest.Producer.Produce(pRun.Cmd, OldOpts);
  if not Old.Ok then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP, 'the old index ' + pRequest.OldDb + ' could not answer: ' + Old.Reason));
  pResult.OldText:= Old.Text;
  pResult.Format:= DetectFormat(Old.Text, False);
  Result:= True;
end;

{ Step 1: the OLD side, its header and (for a chart) its model -- read into memory now,
  because a rerun may overwrite the bundle folder it came from. }
function LoadOldSide(const pRequest: TCompareRequest; var pResult: TCompareResult;
  var pRun: TCompareRun): Boolean;
begin
  var Why: string;
  case pRequest.Source of
    csFile, csTwoFiles:
      begin
        Result:= LoadSide(pRequest.OldPath, pResult.OldText, pResult.OldSvgPath, pResult.Format, Why);
        if not Result then
          Refuse(pResult, COMPARE_EXIT_SETUP, Why);
      end;
    csRemarks:
      Result:= LoadRemarksSide(pRequest, pResult, pRun);
    csAutoSnapshot:
      Result:= LoadAutoSnapshotSide(pRequest, pResult);
  else
    Result:= LoadOldIndexSide(pRequest, pResult, pRun);
  end;
  if Result and (pResult.Format = cfUnknown) then
    Result:= Refuse(pResult, COMPARE_EXIT_SETUP, 'cannot tell what ' +
      (if pRequest.Source = csOldIndex then 'the old run''s answer from ' + pRequest.OldDb else pRequest.OldPath) + ' holds');
  if Result and (pResult.Format = cfReportText) and (pRequest.Source <> csRemarks) then
    pResult.OldHeader:= HeaderOf(pResult.OldText);
  if Result and (pResult.Format = cfGraph) then
  begin
    pResult.OldGraph:= ParseDot(pResult.OldText);
    Result:= ChartReadable(pResult.OldGraph, pResult.OldText, pResult.OldPath, pResult);
  end;
  if Result and (pResult.Format = cfGraph) and (pRequest.Source <> csTwoFiles) and (pResult.OldSvgPath <> '') then
    Result:= ProtectOldSvg(pRequest.OldSvgCopy, pResult);
end;

{ Steps 3 and 4: choose the command (C2, C3), rerun it, refuse a stale index (C4), and
  collect the new run's index facts (C5). }
function ProduceNewSide(const pRequest: TCompareRequest; var pResult: TCompareResult;
  var pRun: TCompareRun): Boolean;
begin
  if not pRun.CmdChosen then
  begin
    var OldCmd:= if pResult.Format = cfReportText then pResult.OldHeader.Command else Default(TReportCommand);
    if not ChooseCommand(OldCmd, pRequest.Command, pResult, pRun.Cmd) then
      Exit(Refuse(pResult, COMPARE_EXIT_SETUP, 'no COMMAND in the old report and none given' + RERUN_HINT));
    ApplyProject(pRun.Cmd, pRequest.ProjectFile, pResult);
  end;
  // R17 / C4: the new run never answers from a stale index, whatever the caller's options.
  var NewOpts:= pRequest.Options;
  NewOpts.AllowStale:= False;
  var NewRun:= pRequest.Producer.Produce(pRun.Cmd, NewOpts);
  if NewRun.ExitCode = PRODUCER_EXIT_STALE then
    Exit(Refuse(pResult, COMPARE_EXIT_STALE,
      'the index is stale for the new run, so there is no current answer to compare: ' + NewRun.Reason));
  if not NewRun.Ok then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP, Format('the new run failed (exit %d): %s', [NewRun.ExitCode, NewRun.Reason])));
  pResult.NewHeader:= HeaderOf(NewRun.Text);
  for var Db in NewRun.IndexPaths do
  begin
    var Fact: TIndexFact;
    var Why: string;
    if not IndexFactFor(Db, Fact, Why) then
      AddWarning(pResult, Why);
    pResult.NewIndexes:= pResult.NewIndexes + [Fact];
  end;
  if Length(NewRun.IndexPaths) > 0 then
    pRun.FirstDb:= NewRun.IndexPaths[0];
  pResult.NewText:= NewRun.Text;
  pRun.NewFormat:= DetectFormat(NewRun.Text, False);
  var Dot, Svg: string;
  if pResult.Format = cfGraph then
  begin
    if not LoadGraphSource(NewRun.BundlePath, Dot, Svg) then
      Exit(Refuse(pResult, COMPARE_EXIT_SETUP, 'the new run''s chart could not be read from ' +
        (if NewRun.BundlePath = '' then '(the answer has no BUNDLE line)' else NewRun.BundlePath)));
    pRun.NewFormat:= cfGraph;
    pRun.NewChart:= NewRun.BundlePath;
    pResult.NewText:= Dot;
    pResult.NewSvgPath:= Svg;
  end;
  Result:= True;
end;

{ Step 2 + 4: the NEW side, from the second file or from a rerun, and the D8 check. }
function LoadNewSide(const pRequest: TCompareRequest; var pResult: TCompareResult;
  var pRun: TCompareRun): Boolean;
begin
  if pRequest.Source = csTwoFiles then
  begin
    var Why: string;
    Result:= LoadSide(pRequest.NewPath, pResult.NewText, pResult.NewSvgPath, pRun.NewFormat, Why);
    if not Result then
      Exit(Refuse(pResult, COMPARE_EXIT_SETUP, Why));
    if pResult.Format = cfReportText then
      pResult.NewHeader:= HeaderOf(pResult.NewText);
  end
  else if not ProduceNewSide(pRequest, pResult, pRun) then
    Exit(False);
  if pRun.NewFormat <> pResult.Format then
    Exit(Refuse(pResult, COMPARE_EXIT_SETUP,
      'cannot compare a ' + FormatName(pResult.Format) + ' with a ' + FormatName(pRun.NewFormat)));
  if pResult.Format = cfGraph then
  begin
    pResult.NewGraph:= ParseDot(pResult.NewText);
    if not ChartReadable(pResult.NewGraph, pResult.NewText,
      if pRequest.Source = csTwoFiles then pRequest.NewPath else pRun.NewChart, pResult) then
      Exit(False);
  end;
  Result:= True;
end;

{ Step 5: items, edit script, hunks, and the C6 code. }
procedure DiffSides(var pResult: TCompareResult);
begin
  pResult.OldItems:= ItemsFor(pResult.Format, pResult.OldText);
  pResult.NewItems:= ItemsFor(pResult.Format, pResult.NewText);
  pResult.Edits:= MyersDiff(pResult.OldItems, pResult.NewItems);
  pResult.Hunks:= BuildHunks(pResult.Edits, COMPARE_CONTEXT);
  var Eq, Del, Ins: Integer;
  pResult.ExitCode:= if CountEdits(pResult.Edits, Eq, Del, Ins) then COMPARE_EXIT_DIFFERENT else COMPARE_EXIT_SAME;
end;

{ S1c: the remarks block becomes the new answer in DocInsight form. The caption phrase is
  the new header's, else the old one's, else DOCINSIGHT_UNKNOWN_PHRASE -- the engine has
  no question catalog. }
procedure UpdateDoc(const pRequest: TCompareRequest; var pResult: TCompareResult; const pRun: TCompareRun;
  pWhen: TDateTime);
begin
  var Phrase:= pResult.NewHeader.Phrase;
  if Phrase = '' then
    Phrase:= pResult.OldHeader.Phrase;
  if Phrase = '' then
    Phrase:= DOCINSIGHT_UNKNOWN_PHRASE;
  var NewBlock:= FormatAnswerAsDocInsight(Phrase, pRun.Cmd.Question, TargetWithTo(pRun.Cmd), pWhen, pResult.NewText);
  var Why: string;
  if ReplaceRemarksBlockInFile(pRequest.OldPath, pRun.Block, NewBlock, Why) then
    pResult.UpdatedFile:= pRequest.OldPath
  else
  begin
    pResult.ExitCode:= COMPARE_EXIT_SETUP;
    pResult.Message:= 'the diff is ready but update-doc failed: ' + Why;
  end;
end;

{ Step 6: the side effects of a rerun that reached a diff (exit 0 / 1). }
procedure ApplySideEffects(const pRequest: TCompareRequest; var pResult: TCompareResult;
  const pRun: TCompareRun; pWhen: TDateTime);
begin
  if pRequest.SaveSnapshot then
  begin
    var Dir:= SnapshotDirFor(pRequest, pRun.Cmd, pRun.FirstDb);
    var Saved: string;
    if SaveSnapshot(Dir, pRequest.Source = csAutoSnapshot, pRun.Cmd.Question, TargetWithTo(pRun.Cmd),
      pResult.NewText, pWhen, Saved, SnapshotExtFor(pResult.Format)) then
      pResult.SnapshotPath:= Saved
    else
      AddWarning(pResult, 'The new answer was not kept as a snapshot under ' + Dir +
        ' (the folder cannot be written, or 20 newer auto snapshots exist).');
  end;
  if pRequest.UpdateDoc then
    UpdateDoc(pRequest, pResult, pRun, pWhen);
end;

function RunCompare(const pRequest: TCompareRequest): TCompareResult;
begin
  var R:= Default(TCompareResult);
  R.ExitCode:= COMPARE_EXIT_SETUP;
  R.OldSource:= pRequest.Source;
  R.OldPath:= if pRequest.Source = csOldIndex then pRequest.OldDb else pRequest.OldPath;
  R.OldLine:= if pRequest.Source = csRemarks then pRequest.OldLine else 0;
  var Run:= Default(TCompareRun);
  if ValidateRequest(pRequest, R) and LoadOldSide(pRequest, R, Run) and LoadNewSide(pRequest, R, Run) then
  begin
    DiffSides(R);
    if pRequest.Source <> csTwoFiles then
      ApplySideEffects(pRequest, R, Run, if pRequest.Now = 0 then Now else pRequest.Now);
  end;
  Result:= R;
end;

end.
