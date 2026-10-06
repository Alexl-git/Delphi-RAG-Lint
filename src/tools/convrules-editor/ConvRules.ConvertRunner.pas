unit ConvRules.ConvertRunner;

{ Executes a Convert run (spec 2026-09-29, part 2, "Run flow"): reindex the
  project before a unit's first book and after every book (convert-apply finds
  and patches .dfm blocks at the index's line ranges), back every unit up ONCE
  (.pas and .dfm share one .BCK<N> number), apply each runnable book in order,
  and restore a unit from
  its backup the moment a unit-level step fails -- a unit is never left
  half-converted, and the rows say so. A book whose rules fail the engine's
  own validation (its rule_errors) is skipped for the rest of the run:
  convert-validate without a From/To pair checks syntax only (measured
  2026-09-29), so it cannot be the pre-check. Runs on a worker thread; no VCL. }

interface

uses
  System.SysUtils
  , ConvRules.Engine
  , ConvRules.ConvertRun
  ;

type
  /// <summary>Outcome of one results-grid row.</summary>
  /// <remarks>
  /// csConverted: the book converted the unit and the reindex after it succeeded.
  /// csFailedRestored: the book's apply (or the reindex after it) failed; the
  ///   unit and its .dfm were restored from this run's backup and the unit's
  ///   remaining books did not run.
  /// csBookSkipped: the book failed the engine's validation (rule_errors) and the
  ///   reply is not a refusal; the unit is untouched by it and the book is not
  ///   tried on any later unit.
  /// csUnitSkipped: the unit was not run at all -- not found on disk, the
  ///   reindex before its first book failed (no backup is taken, the engine is
  ///   not called), or its backup could not be taken (any .BCK already made for
  ///   it is removed).
  /// csRolledBack: the book HAD converted the unit, but a later book failed on
  ///   the same unit and the restore undid this book's change too.
  /// csRestoreFailed: a book failed AND the restore from the backup raised; the
  ///   unit may be half-converted, the Note names the backups (.pas and .dfm)
  ///   to restore by hand.
  /// csRefused: the engine refused this book on the unit (TApplyRow.Refused),
  ///   whether or not the reply also lists rule_errors; the book stays valid for
  ///   later units. The unit's remaining books do not run and it ends unchanged. When an
  ///   earlier book had converted the unit, it is restored like a failure (those
  ///   rows become csRolledBack) and the backup is kept and named. When nothing
  ///   had changed it (the refused book was its first, or every earlier one was
  ///   skipped), nothing is restored and the unneeded backup is DROPPED, as for
  ///   csBookSkipped: Backup / BackupDfm are '' on the row.
  /// </remarks>
  TConvertStatus = (csConverted, csFailedRestored, csBookSkipped, csUnitSkipped, csRolledBack, csRestoreFailed, csRefused);

  /// <summary>One results-grid row: a book x unit, or a unit-level skip.</summary>
  TConvertRow = record
    /// <summary>The .rules path; '' on a csUnitSkipped row.</summary>
    Book   : string;
    /// <summary>The .pas path; on a csBookSkipped row, the unit whose apply
    /// found the book invalid (that unit is untouched by it).</summary>
    UnitPas: string;
    /// <summary>The .pas backup this run made; '' when none, and '' on a
    /// csBookSkipped row (the book did not touch the unit).</summary>
    Backup : string;
    /// <summary>The .dfm backup this run made, numbered like Backup (one shared
    /// N per unit, SharedBackupPaths); '' when the unit has no .dfm, and
    /// wherever Backup is ''.</summary>
    BackupDfm: string;
    /// <summary>Human-readable reason / summary. Also records an unneeded
    /// backup that could not be deleted (it is then kept).</summary>
    Note   : string;
    /// <summary>What happened.</summary>
    Status : TConvertStatus;
    /// <summary>The engine's report when convert-apply ran.</summary>
    Apply  : TApplyRow;
  end;

  /// <summary>Everything a run needs; built by the Convert tab.</summary>
  TConvertJob = record
    /// <summary>Runnable books (Preflight.Runnable), application order.</summary>
    Books      : TArray<string>;
    /// <summary>Source units (.pas).</summary>
    Units      : TArray<string>;
    /// <summary>--db list: project DB FIRST, then the libraries.</summary>
    Dbs        : TArray<string>;
    /// <summary>The project DB reindexed before each unit and after each book.</summary>
    ProjectDb  : string;
    /// <summary>The .dproj/.dpr that owns ProjectDb -- always the DB's own
    /// project file (ProjectFileForDb), never the Unit Rules Destination: an
    /// `index --project` of another project would re-scope this DB.</summary>
    ProjectFile: string;
    /// <summary>The engine reports inherited_instances (C8): a converted row's note then
    /// lists the inherited instances it left (apply/1 inherited[]). False = today's
    /// handling (the engine refuses such a unit).</summary>
    InheritedSupported: Boolean;
  end;

  /// <summary>Called once per row (worker thread!). A unit's rows arrive
  /// together when that unit has finished, already in their final status.</summary>
  TConvertProgress = reference to procedure(const ARow: TConvertRow; ADone, ATotal: Integer);

  /// <summary>Applies one book to one unit in place; the shape of
  /// TEngineAdapter.ApplyConversion with the --db list bound.</summary>
  TApplyFn = reference to function(const AUnitPas, ARulesFile: string; out AJson: string): Integer;

  /// <summary>Refreshes the project index; the shape of
  /// TEngineAdapter.IndexProject with the project bound. 0 = success.</summary>
  TIndexFn = reference to function(out AOutput: string): Integer;

/// <summary>Runs a whole job (AJob.Books over AJob.Units).</summary>
/// <param name="AJob">The job.</param>
/// <param name="AEngine">An adapter owned by the caller's thread.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled exactly once just before each unit (never between two books of one unit); True stops the run there.</param>
/// <returns>One row per unit x book attempted; an invalid book yields one
/// csBookSkipped row (on the first unit that tried it) and is not tried again.</returns>
function RunConversion(const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>): TArray<TConvertRow>;

/// <summary>The unit loop of RunConversion, for books already validated,
/// against the real engine (AJob.Dbs, AJob.ProjectFile, AJob.ProjectDb).</summary>
/// <param name="AUnits">Source units.</param>
/// <param name="ABooks">Validated books, application order.</param>
/// <param name="AJob">Supplies Dbs, ProjectDb, ProjectFile.</param>
/// <param name="AEngine">Engine adapter.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled exactly once just before each unit; True stops the run there.</param>
/// <returns>See the TApplyFn overload.</returns>
function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>): TArray<TConvertRow>; overload;

/// <summary>The unit loop with the engine calls injected.</summary>
/// <param name="AUnits">Source units.</param>
/// <param name="ABooks">Validated books, application order.</param>
/// <param name="AApply">Applies one book to one unit.</param>
/// <param name="AIndex">Reindexes before each unit's first book and after each
/// successful apply.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled exactly once just before each unit; True stops the run there.</param>
/// <param name="AInheritedSupported">See TConvertJob.InheritedSupported.</param>
/// <returns>One row per unit x book attempted (a missing, not-reindexed or
/// un-backed-up unit: one csUnitSkipped row); a unit whose books were all found
/// invalid on earlier units gets no row, no reindex and no backup.</returns>
/// <remarks>Before a unit's first book the index is refreshed (a .dfm edited
/// since the last index would otherwise be patched at stale line ranges); a
/// failed refresh skips the unit untouched and the run continues. Each unit
/// then gets ONE restore point, .BCK&lt;N&gt; for the .pas and the SAME N for
/// its .dfm (SharedBackupPaths), deleted again when no book changed the unit.
/// A failed or refused apply, or a failed reindex, restores the unit, rewrites its earlier
/// csConverted rows to csRolledBack and stops its remaining books -- except a refusal
/// on a unit nothing has changed yet, which restores nothing and drops the backup. Never
/// raises: file I/O failures and exceptions from AApply / AIndex become row
/// outcomes (see TConvertStatus).</remarks>
function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AApply: TApplyFn; const AIndex: TIndexFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; AInheritedSupported: Boolean = False): TArray<TConvertRow>; overload;

/// <summary>Display text for a status.</summary>
/// <param name="AStatus">The status.</param>
/// <returns>'converted', 'FAILED -- restored', 'book skipped', 'unit skipped',
/// 'rolled back', 'FAILED -- NOT restored', 'refused -- not changed'.</returns>
function ConvertStatusText(AStatus: TConvertStatus): string;

/// <summary>PURE: the units ARows converted (C8 R4: an ancestor converted EARLIER IN THE
/// SAME RUN converts its descendants' inherited instances and code uses too).</summary>
/// <param name="ARows">A run's rows so far.</param>
/// <returns>Unit names (file name without extension) of the csConverted rows, first-seen
/// order, once each.</returns>
/// <remarks>A unit whose conversion a later book on it rolled back is csRolledBack, not
/// csConverted, so it is not listed.</remarks>
function UnitsConvertedIn(const ARows: TArray<TConvertRow>): TArray<string>;

implementation

uses
  System.IOUtils
  , System.StrUtils
  , ConvRules.UnitStatus  // dl:ok unused-unit-in-uses@ec0d -- REVIEWED 2026-09-29 false positive: TFileProbe (FileProbe's return type) is declared here; removing the unit fails with E2003
  ;

const
  OUTPUT_HEAD_CHARS = 200;

function ConvertStatusText(AStatus: TConvertStatus): string;
begin
  case AStatus of
    csConverted     : Result:= 'converted';
    csFailedRestored: Result:= 'FAILED -- restored';
    csBookSkipped   : Result:= 'book skipped';
    csUnitSkipped   : Result:= 'unit skipped';
    csRolledBack    : Result:= 'rolled back';
    csRestoreFailed : Result:= 'FAILED -- NOT restored';
    csRefused       : Result:= 'refused -- not changed';
    else              Result:= 'FAILED -- NOT restored';
  end;
end;

function UnitsConvertedIn(const ARows: TArray<TConvertRow>): TArray<string>;
var
  LName: string;
begin
  Result:= nil;
  for var LRow: TConvertRow in ARows do
    if LRow.Status = csConverted then
    begin
      LName:= ChangeFileExt(ExtractFileName(LRow.UnitPas), '');
      if not MatchText(LName, Result) then
        Result:= Result + [LName];
    end;
end;

function FileProbe: TFileProbe;
begin
  Result:= function(const APath: string): Boolean
    begin
      Result:= TFile.Exists(APath);
    end;
end;

function RunConversion(const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>): TArray<TConvertRow>;
begin
  Result:= RunConversionUnits(AJob.Units, AJob.Books, AJob, AEngine, AProgress, ACancelled);
end;

function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>): TArray<TConvertRow>;
var
  LJob   : TConvertJob;
  LEngine: TEngineAdapter;
begin
  LJob   := AJob;
  LEngine:= AEngine;
  Result:= RunConversionUnits(AUnits, ABooks,
    function(const AUnitPas, ARulesFile: string; out AJson: string): Integer
    begin
      Result:= LEngine.ApplyConversion(AUnitPas, ARulesFile, LJob.Dbs, AJson);
    end,
    function(out AOutput: string): Integer
    begin
      Result:= LEngine.IndexProject(LJob.ProjectFile, LJob.ProjectDb, AOutput);
    end,
    AProgress, ACancelled, LJob.InheritedSupported);
end;

function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AApply: TApplyFn; const AIndex: TIndexFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; AInheritedSupported: Boolean): TArray<TConvertRow>;
var
  Rows    : TArray<TConvertRow>;
  UnitRows: TArray<TConvertRow>; // the current unit's rows, emitted when it finishes
  Row     : TConvertRow;
  Total   : Integer;
  CurUnit : string;
  BakPas  : string;
  BakDfm  : string;
  Dfm     : string;
  Invalid : TArray<string>; // books whose rules failed the engine's validation this run
  Changed : Boolean;        // the unit's backup is still needed (a change, or a failed book)

  procedure Add;
  begin
    UnitRows:= UnitRows + [Row];
  end;

  procedure Flush;
  begin
    for var LRow: TConvertRow in UnitRows do
    begin
      Rows:= Rows + [LRow];
      if Assigned(AProgress) then
        AProgress(LRow, Length(Rows), Total);
    end;
    UnitRows:= nil;
  end;

  function AllInvalid: Boolean;
  begin
    Result:= True;
    for var LBook: string in ABooks do
      if not MatchText(LBook, Invalid) then
        Exit(False);
  end;

  // '' when ABak ('' = none made) is gone; else a note that it was kept.
  function DropBackup(const ABak: string): string;
  begin
    Result:= '';
    if ABak = '' then
      Exit;
    try
      TFile.Delete(ABak);
    except
      on E: Exception do
        Result:= Format('; unneeded backup kept (delete failed: %s): %s', [E.Message, ABak]);
    end; // try
  end;

  // '' when every backup this run made for the unit is gone; else what was kept.
  function DropBackups: string;
  begin
    Result:= DropBackup(BakPas) + DropBackup(BakDfm);
  end;

  // The unit's backups for a Note: both when it has a .dfm; file names only
  // unless AFullPaths.
  function BackupNames(AFullPaths: Boolean): string;
  begin
    Result:= if AFullPaths then BakPas else ExtractFileName(BakPas);
    if BakDfm <> '' then
      Result:= Result + ' and ' + (if AFullPaths then BakDfm else ExtractFileName(BakDfm));
  end;

  // BakPas / BakDfm are set only once their copy has been made, so a failure
  // leaves them naming exactly the backups DropBackups must remove.
  function TakeBackups(out AError: string): Boolean;
  begin
    AError:= '';
    BakPas:= '';
    BakDfm:= '';
    Dfm   := ChangeFileExt(CurUnit, '.dfm');
    try
      // ONE number for the unit: a stale X.dfm.BCK<N> counts even when the .dfm is gone.
      var LPaths: TArray<string>:= SharedBackupPaths([CurUnit, Dfm], FileProbe());
      TFile.Copy(CurUnit, LPaths[0]);
      BakPas:= LPaths[0];
      if TFile.Exists(Dfm) then
      begin
        TFile.Copy(Dfm, LPaths[1]);
        BakDfm:= LPaths[1];
      end;
      Result:= True;
    except
      on E: Exception do
      begin
        AError:= E.Message;
        Result:= False;
      end;
    end; // try
  end;

  function TryRestore(out AError: string): Boolean;
  begin
    AError:= '';
    try
      TFile.Copy(BakPas, CurUnit, True);
      if BakDfm <> '' then
        TFile.Copy(BakDfm, Dfm, True);
      Result:= True;
    except
      on E: Exception do
      begin
        AError:= E.Message;
        Result:= False;
      end;
    end; // try
  end;

  // Row is the failing book's row; restore the unit and account for its earlier rows.
  // AStatus is the failing row's status: csFailedRestored, or csRefused.
  procedure FailUnit(const AReason: string; AStatus: TConvertStatus);
  var
    LError: string;
    LVerb : string;
  begin
    // A refusal leaves the file untouched (engine contract). When no earlier book
    // changed the unit either, there is nothing to restore and the backup is not
    // needed: RunUnit drops it, as for a skipped book (owner decision, 2026-10-04).
    if (AStatus = csRefused) and not Changed then
    begin
      Row.Backup   := '';
      Row.BackupDfm:= '';
      Row.Status   := csRefused;
      Row.Note     := AReason;
      Add;
      Exit;
    end;
    Changed:= True; // the backup is the restore point the rows name -- keep it
    if not TryRestore(LError) then
    begin
      // Earlier csConverted rows stay: their change may still be on disk.
      Row.Status:= csRestoreFailed;
      Row.Note  := Format('restore failed: %s; the unit may be half-converted -- backup at %s', [LError, BackupNames(True)]);
      Add;
      Exit;
    end;
    LVerb:= if AStatus = csRefused then 'was refused' else 'failed';
    for var I: Integer:= 0 to High(UnitRows) do
      if UnitRows[I].Status = csConverted then
      begin
        UnitRows[I].Status:= csRolledBack;
        UnitRows[I].Note  := Format('undone: %s %s on this unit; restored from %s', [ExtractFileName(Row.Book), LVerb, BackupNames(False)]);
      end;
    Row.Status:= AStatus;
    Row.Note  := AReason;
    Add;
  end;

  // True = AIndex reported success; else AError is the head of its output.
  function TryReindex(out AError: string): Boolean;
  var
    LOutput: string;
    LCode  : Integer;
  begin
    try
      LCode:= AIndex(LOutput);
    except  // dl:ok try-except-swallowed@6298 -- REVIEWED 2026-09-29 not swallowed: becomes a failed reindex, so the unit is restored (or skipped) and the row carries the message
      on E: Exception do
      begin
        LOutput:= 'reindex raised: ' + E.Message;
        LCode  := -1;
      end;
    end; // try
    AError:= Copy(Trim(LOutput), 1, OUTPUT_HEAD_CHARS);
    Result:= LCode = 0;
  end;

  // False = the unit failed; its remaining books must not run.
  function RunBook(const ABook: string): Boolean;
  var
    LJson : string;
    LError: string;
  begin
    Result:= True;
    Row:= Default(TConvertRow);
    Row.UnitPas  := CurUnit;
    Row.Book     := ABook;
    Row.Backup   := BakPas;
    Row.BackupDfm:= BakDfm;
    try
      // A non-zero exit shows up as ok=false or unparseable text in ParseApplyJson.
      AApply(CurUnit, ABook, LJson);
    except  // dl:ok try-except-swallowed@3c3c -- REVIEWED 2026-09-29 not swallowed: the message becomes unparseable apply output, so the unit is restored and the row names it
      on E: Exception do
        LJson:= 'engine call raised: ' + E.Message; // unparseable -> the unit is restored
    end; // try
    Row.Apply:= ParseApplyJson(LJson);
    // A refusal is about THIS unit, even when it also lists rule_errors: it takes the
    // refused path below and leaves the book valid for the next unit.
    if (not Row.Apply.Ok) and (Row.Apply.RuleErrorCount > 0) and not Row.Apply.Refused then
    begin
      // The BOOK is invalid; the engine validates before writing, so this unit
      // is untouched by it. Skip the book for the rest of the run.
      Invalid:= Invalid + [ABook];
      Row.Backup   := ''; // the book made no change; the backups may yet be dropped
      Row.BackupDfm:= '';
      Row.Status:= csBookSkipped;
      Row.Note  := 'rules failed the engine''s validation: ' + Row.Apply.Error;
      Add;
      Exit;
    end;
    if not Row.Apply.Ok then
    begin
      FailUnit(Row.Apply.Error, if Row.Apply.Refused then csRefused else csFailedRestored);
      Exit(False);
    end;
    if not TryReindex(LError) then
    begin
      FailUnit('reindex after apply failed: ' + LError, csFailedRestored);
      Exit(False);
    end;
    Changed   := True;
    Row.Status:= csConverted;
    Row.Note  := Format('%d edit(s), %d remaining for manual work', [Row.Apply.EditsCount, Length(Row.Apply.Remainder)]);
    // E10: only an engine with inherited_instances sends inherited[]; the gate keeps an
    // older engine's output from being read as this contract.
    if AInheritedSupported then
    begin
      // R4: an ancestor this run already converted is not "left" (Rows = earlier units only).
      var LLeft: string:= InheritedLeftNote(Row.Apply.InheritedLeft, UnitsConvertedIn(Rows));
      if LLeft <> '' then
        Row.Note:= Row.Note + '; ' + LLeft;
    end;
    Add;
  end;

  procedure RunUnit;
  var
    LError: string;
  begin
    Row:= Default(TConvertRow);
    Row.UnitPas:= CurUnit;
    if not TFile.Exists(CurUnit) then
    begin
      Row.Status:= csUnitSkipped;
      Row.Note  := 'source unit not found on disk';
      Add;
      Exit;
    end;
    if AllInvalid then
      Exit; // every book already failed validation on an earlier unit: nothing to run, no backup
    // convert-apply patches the .dfm at the index's line ranges: a unit edited
    // (in the IDE, say) since the last index must be re-read first. A failed
    // refresh touches nothing -- no backup, no apply -- and the run goes on.
    if not TryReindex(LError) then
    begin
      Row.Status:= csUnitSkipped;
      Row.Note  := 'reindex before apply failed: ' + LError;
      Add;
      Exit;
    end;
    // One restore point per unit per run, taken before the first book touches it.
    if not TakeBackups(LError) then
    begin
      Row.Status:= csUnitSkipped;
      Row.Note  := 'backup failed: ' + LError + DropBackups;
      Add;
      Exit;
    end;
    Changed:= False;
    for var LBook: string in ABooks do
      if not MatchText(LBook, Invalid) and not RunBook(LBook) then
        Break;
    if Changed then
      Exit;
    // Nothing touched the unit (every book invalid, or refused before any change): the fresh copies are
    // identical to it and would only litter the folder.
    LError:= DropBackups;
    if (LError <> '') and (Length(UnitRows) > 0) then
      UnitRows[High(UnitRows)].Note:= UnitRows[High(UnitRows)].Note + LError;
  end;

begin
  Rows    := nil;
  UnitRows:= nil;
  Invalid := nil;
  if Length(ABooks) = 0 then
    Exit(nil); // no book, no backup
  Total:= Length(AUnits) * Length(ABooks);
  for CurUnit in AUnits do
  begin
    // Cancel is honoured BETWEEN units only: a unit is never left with some of
    // its books applied and the rest not.
    if Assigned(ACancelled) and ACancelled() then
      Break;
    RunUnit;
    Flush;
  end; // for units
  Result:= Rows;
end;

end.
