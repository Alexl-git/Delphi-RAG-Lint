unit ConvRules.ConvertRunner;

{ Executes a Convert run (spec 2026-09-29, part 2, "Run flow"): back every
  unit up ONCE, apply each runnable book in order, reindex between books
  (convert-apply finds .dfm blocks through the index), and restore a unit from
  its backup the moment a unit-level step fails -- a unit is never left
  half-converted. A book whose rules fail the engine's own validation (its
  rule_errors) is skipped for the rest of the run: convert-validate without a
  From/To pair checks syntax only (measured 2026-09-29), so it cannot be the
  pre-check. Runs on a worker thread; no VCL. }

interface

uses
  System.SysUtils
  , ConvRules.Engine
  , ConvRules.ConvertRun
  ;

type
  /// <summary>Outcome of one results-grid row.</summary>
  TConvertStatus = (csConverted, csFailedRestored, csBookSkipped, csUnitSkipped);

  /// <summary>One results-grid row: a book x unit, or a book-level skip.</summary>
  TConvertRow = record
    /// <summary>The .rules path; '' on a csUnitSkipped row.</summary>
    Book   : string;
    /// <summary>The .pas path; on a csBookSkipped row, the unit whose apply
    /// found the book invalid (that unit is untouched by it).</summary>
    UnitPas: string;
    /// <summary>The .pas backup this run made; '' when none, and '' on a
    /// csBookSkipped row (the book did not touch the unit).</summary>
    Backup : string;
    /// <summary>Human-readable reason / summary.</summary>
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
    /// <summary>The project DB reindexed between books.</summary>
    ProjectDb  : string;
    /// <summary>The .dproj/.dpr that owns ProjectDb.</summary>
    ProjectFile: string;
  end;

  /// <summary>Called once per row as it is produced (worker thread!).</summary>
  TConvertProgress = reference to procedure(const ARow: TConvertRow; ADone, ATotal: Integer);

/// <summary>Runs a whole job (AJob.Books over AJob.Units).</summary>
/// <param name="AJob">The job.</param>
/// <param name="AEngine">An adapter owned by the caller's thread.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled BETWEEN units only.</param>
/// <returns>One row per unit x book attempted; an invalid book yields one
/// csBookSkipped row (on the first unit that tried it) and is not tried again.</returns>
function RunConversion(const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>): TArray<TConvertRow>;

/// <summary>The unit loop of RunConversion, for books already validated.</summary>
/// <param name="AUnits">Source units.</param>
/// <param name="ABooks">Validated books, application order.</param>
/// <param name="AJob">Supplies Dbs, ProjectDb, ProjectFile.</param>
/// <param name="AEngine">Engine adapter.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; True stops before the NEXT unit.</param>
/// <returns>One row per unit x book attempted (a missing unit: one row).</returns>
/// <remarks>Each existing unit gets ONE .BCK&lt;N&gt; restore point (and one for
/// its .dfm) before its first book; it is deleted again when no book changed
/// the unit. A failed apply or reindex restores the unit from it and stops
/// that unit's remaining books. File I/O errors (backup, restore) propagate
/// as exceptions.</remarks>
function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>): TArray<TConvertRow>;

/// <summary>Display text for a status.</summary>
/// <param name="AStatus">The status.</param>
/// <returns>'converted', 'FAILED -- restored', 'book skipped', 'unit skipped'.</returns>
function ConvertStatusText(AStatus: TConvertStatus): string;

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
    else              Result:= 'unit skipped';
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
  Rows   : TArray<TConvertRow>;
  Row    : TConvertRow;
  Total  : Integer;
  BakPas : string;
  BakDfm : string;
  Dfm    : string;
  Json   : string;
  Output : string;
  Invalid: TArray<string>; // books whose rules failed the engine's validation this run
  Changed: Boolean;        // some book converted this unit -> keep its backup

  procedure Emit;
  begin
    Rows:= Rows + [Row];
    if Assigned(AProgress) then
      AProgress(Row, Length(Rows), Total);
  end;

  procedure Restore;
  begin
    TFile.Copy(BakPas, Row.UnitPas, True);
    if BakDfm <> '' then
      TFile.Copy(BakDfm, Dfm, True);
  end;

begin
  Result := nil;
  Rows   := nil;
  Invalid:= nil;
  if Length(ABooks) = 0 then
    Exit; // no book, no backup
  Total:= Length(AUnits) * Length(ABooks);
  for var LUnit: string in AUnits do
  begin
    // Cancel is honoured BETWEEN units only: a unit is never left with some of
    // its books applied and the rest not.
    if Assigned(ACancelled) and ACancelled() then
      Break;
    Row:= Default(TConvertRow);
    Row.UnitPas:= LUnit;
    if not TFile.Exists(LUnit) then
    begin
      Row.Status:= csUnitSkipped;
      Row.Note  := 'source unit not found on disk';
      Emit;
      Continue;
    end;
    // One restore point per unit per run, taken before the first book touches it.
    BakPas:= NextBackupPath(LUnit, FileProbe());
    TFile.Copy(LUnit, BakPas);
    Dfm   := ChangeFileExt(LUnit, '.dfm');
    BakDfm:= '';
    if TFile.Exists(Dfm) then
    begin
      BakDfm:= NextBackupPath(Dfm, FileProbe());
      TFile.Copy(Dfm, BakDfm);
    end;
    Changed:= False;
    for var LBook: string in ABooks do
    begin
      if MatchText(LBook, Invalid) then
        Continue; // already reported once, on the unit that found it
      Row:= Default(TConvertRow);
      Row.UnitPas:= LUnit;
      Row.Book   := LBook;
      Row.Backup := BakPas;
      // A non-zero exit shows up as ok=false or unparseable text in ParseApplyJson.
      AEngine.ApplyConversion(LUnit, LBook, AJob.Dbs, Json);
      Row.Apply:= ParseApplyJson(Json);
      if (not Row.Apply.Ok) and (Row.Apply.RuleErrorCount > 0) then
      begin
        // The BOOK is invalid; the engine validates before writing, so this unit
        // is untouched by it. Skip the book for the rest of the run.
        Invalid:= Invalid + [LBook];
        Row.Backup:= ''; // the book made no change; the backup may yet be dropped
        Row.Status:= csBookSkipped;
        Row.Note  := 'rules failed the engine''s validation: ' + Row.Apply.Error;
        Emit;
        Continue;
      end;
      if not Row.Apply.Ok then
      begin
        Restore;
        Row.Status:= csFailedRestored;
        Row.Note  := Row.Apply.Error;
        Emit;
        Changed:= True; // the backup is the restore point the row names -- keep it
        Break;          // the unit is back to its backup; its remaining books do not run
      end;
      if AEngine.IndexProject(AJob.ProjectFile, AJob.ProjectDb, Output) <> 0 then
      begin
        Restore;
        Row.Status:= csFailedRestored;
        Row.Note  := 'reindex after apply failed: ' + Copy(Output, 1, OUTPUT_HEAD_CHARS);
        Emit;
        Changed:= True;
        Break;
      end;
      Changed   := True;
      Row.Status:= csConverted;
      Row.Note  := Format('%d edit(s), %d remaining for manual work', [Row.Apply.EditsCount, Length(Row.Apply.Remainder)]);
      Emit;
    end; // for books
    if not Changed then
    begin
      // Nothing touched the unit (every book invalid): the fresh copies are
      // identical to it and would only litter the folder.
      TFile.Delete(BakPas);
      if BakDfm <> '' then
        TFile.Delete(BakDfm);
    end;
  end; // for units
  Result:= Rows;
end;

end.
