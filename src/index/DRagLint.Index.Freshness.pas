unit DRagLint.Index.Freshness;

/// <summary>Is this index still describing the source on disk? A warn-only
/// sweep over the DB's own file rows, comparing recorded mtime against the
/// filesystem.</summary>
/// <remarks>
/// <para>Backs the 2026-08-13 owner ruling ("a stale DB is not authoritative;
/// the answer is to rescan, not to report") --
/// `docs\superpowers\specs\2026-08-13-db-authority-and-freshness.md`. This is
/// the DECISION-FREE half of it: the sweep and a note on stderr. The ruling's
/// open questions -- where the gate lives, and whether a failed gate refuses,
/// warns, or auto-reindexes -- are NOT answered here. A warning changes no
/// output and no exit code, so it cannot pre-empt them.</para>
///
/// <para>WHY THIS IS NOT DRagLint.Project.Coherence, which already compares the
/// same two numbers. ComputeCoherence is driven by the PROJECT MEMBER LIST and
/// is the better instrument where a .dproj is in hand -- the ruling explicitly
/// wants member units, not DB rows, because a DB can hold ghost rows that no
/// reindex evicts (INBOX-ignored-files-already-indexed-are-never-evicted: YADF's
/// DB reports 18 files where the compile closure is 9). But an ordinary consumer
/// command has a --db and frequently no project file at all, so the member list
/// is not available at the point where the warning has to be emitted. This
/// sweep therefore asks the DB's rows, and handles ghosts by NOT counting them
/// as staleness -- see TFreshnessReport.Missing.</para>
///
/// <para>THE MTIME EXPRESSION IS COPIED DELIBERATELY, NOT REINVENTED.
/// `DateTimeToUnix(TFile.GetLastWriteTime(P), False)` is what the indexer writes
/// (`DRagLint.Core.Indexer.pas:881`) and what ComputeCoherence compares against.
/// Getting the UTC flag wrong here would not fail -- it would report EVERY file
/// as changed, on every command, which reads as a broken index rather than a
/// broken check.</para>
///
/// <para>SILENCE IS NOT A CLAIM OF FRESHNESS. This is an mtime fast path, and
/// the ruling's own concern #3 records why that is not a proof: a file restored
/// from backup or checked out at an older revision has an mtime OLDER than the
/// DB and DIFFERENT content. `ISymbolStore.FileIsUpToDate` takes mtime AND sha
/// for that reason, but a sha means reading every file, which is not affordable
/// on every command. So fvFresh means "nothing detected by the fast path", and
/// the note wording must not promise more.</para>
///
/// <para>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</para>
/// </remarks>

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.IOUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces
  ;

const
  /// <summary>DB-level meta key: unix seconds at which a COMPLETED index run
  /// last stamped this database.</summary>
  /// <remarks>Written beside the indexer fingerprint and for the same reason --
  /// only after a walk that ran to completion, so an interrupted run leaves the
  /// old value and the next run still knows it must look.</remarks>
  INDEXED_AT_KEY = 'indexed_at_unix';

type
  /// <summary>Three outcomes, and folding any two together is worse than not
  /// checking at all.</summary>
  /// <remarks>fvUnknown exists so "I cannot tell" never renders as "fresh".
  /// It is the honest answer for an index written before the stamp existed.</remarks>
  TFreshnessVerdict = (fvFresh, fvStale, fvUnknown);

  /// <summary>What one freshness sweep found.</summary>
  TFreshnessReport = record
    /// <summary>fvStale iff at least one still-present file's mtime differs.</summary>
    Verdict : TFreshnessVerdict;
    /// <summary>File rows compared.</summary>
    Checked : Integer;
    /// <summary>Files whose on-disk mtime differs from the recorded one.</summary>
    Changed : Integer;
    /// <summary>Rows whose file is GONE from disk. Counted, reported, and
    /// deliberately NOT treated as staleness: a never-evicted ghost row is a
    /// known separate defect, and letting it raise a staleness warning on every
    /// command would make the warning worthless.</summary>
    Missing : Integer;
    /// <summary>Up to AMaxExamples changed paths, so the note can name one.</summary>
    Examples: TArray<string>;
    /// <summary>Populated only for fvUnknown: why no verdict was reached.</summary>
    Reason  : string;
  end;

/// <summary>Compare every file row's recorded mtime against the filesystem.</summary>
/// <param name="AStore">An open store. Not modified.</param>
/// <param name="AMaxExamples">How many changed paths to keep for the message.</param>
/// <returns>A report; fvUnknown when the DB carries no INDEXED_AT_KEY stamp,
/// because an index written before this existed cannot be judged.</returns>
/// <remarks>One query plus one stat per row. Never raises: an unreadable path
/// counts as Missing, on the principle that a freshness check must not be able
/// to break the command it is advising.</remarks>
function ProbeIndexFreshness(const AStore: ISymbolStore;
  AMaxExamples: Integer = 3): TFreshnessReport;

/// <summary>The one-line stderr note for a report, or '' when there is nothing
/// actionable to say.</summary>
/// <param name="AReport">A report from ProbeIndexFreshness.</param>
/// <param name="ADbPath">Database path, named so the reader knows which index.</param>
/// <returns>Empty for fvFresh and for fvUnknown -- see the remarks.</returns>
/// <remarks>fvUnknown returns EMPTY on purpose, and that is the one place this
/// unit bends the "never fold UNKNOWN into FRESH" rule: every index built before
/// the stamp existed is fvUnknown, so speaking would put a line on every command
/// until the whole tree is reindexed, and a warning that always fires is one
/// nobody reads. The verdict is still fvUnknown in the record for any caller
/// that wants to render it; only this convenience line stays quiet.</remarks>
function FreshnessNote(const AReport: TFreshnessReport; const ADbPath: string): string;

implementation

function ProbeIndexFreshness(const AStore: ISymbolStore;
  AMaxExamples: Integer = 3): TFreshnessReport;
var
  Stamps: TArray<TFileStamp>;
  S     : TFileStamp        ;
  DiskDT: TDateTime          ;
begin
  Result := Default(TFreshnessReport);
  Result.Verdict := fvUnknown;

  if AStore = nil then
  begin
    Result.Reason := 'no store';
    Exit;
  end;

  { The DB-level stamp is asked FIRST and is not merely informational: without
    it there is no evidence the index was ever completed by an engine that knew
    to record one, so a clean mtime sweep would be answering a question the DB
    cannot support. }
  if AStore.GetMetaValue(INDEXED_AT_KEY) = '' then
  begin
    Result.Reason := 'index predates the freshness stamp; reindex to enable the check';
    Exit;
  end;

  Stamps := AStore.GetAllFileStamps;
  for S in Stamps do
  begin
    { FileAge, not TFile.Exists + TFile.GetLastWriteTime. The latter pair RAISES
      when a file is locked, denied, or deleted between the two calls -- and a
      freshness check must not be able to break the command it is advising. The
      obvious try/except around it is a silent swallow, which this repo's own
      try-except-swallowed rule flags, correctly.

      The risk this trades in: FileAge must produce the SAME number the indexer
      wrote with DateTimeToUnix(TFile.GetLastWriteTime(P), False), or every file
      reports changed and the note fires on every command. That is asserted, not
      assumed -- run_index_freshness.ps1's F1 builds a fresh index and requires
      ZERO changed files, which is exactly this equivalence. }
    if not FileAge(S.Path, DiskDT) then
    begin
      Inc(Result.Missing);
      Continue;
    end;
    Inc(Result.Checked);
    if DateTimeToUnix(DiskDT, False) <> S.MTimeUnix then
    begin
      Inc(Result.Changed);
      if Length(Result.Examples) < AMaxExamples then
        Result.Examples := Result.Examples + [S.Path];
    end;
  end;

  if Result.Changed > 0 then Result.Verdict := fvStale
  else Result.Verdict := fvFresh;
end;

function FreshnessNote(const AReport: TFreshnessReport; const ADbPath: string): string;
var Extra: string;
begin
  Result := '';
  if AReport.Verdict <> fvStale then Exit;

  Extra := '';
  if Length(AReport.Examples) > 0 then
    Extra := ' e.g. ' + TPath.GetFileName(AReport.Examples[0]);

  { Names the count, one example, and the repair -- in that order, because a
    warning that does not say what to do about it gets read once and then
    ignored. The repair is the incremental form on purpose: the ruling is
    "refresh, do not full-reindex". }
  Result := Format(
    'drag-lint: note: %d of %d indexed file(s) changed since this index was built%s.' +
    ' Answers may be stale -- refresh with: drag-lint index <dir> --db %s',
    [AReport.Changed, AReport.Checked, Extra, ADbPath]);
end;

end.
