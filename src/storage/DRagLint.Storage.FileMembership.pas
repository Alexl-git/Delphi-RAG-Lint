unit DRagLint.Storage.FileMembership;

/// <summary>One question, asked of an index without opening a symbol store:
/// does this database contain a files row for this path?</summary>
/// <remarks>Exists so DB SELECTION can depend on DB CONTENT. The manifest can
/// say which sections could plausibly cover a file, but only the index itself
/// knows whether a given file is actually in that project's compile closure --
/// and once two projects share a directory, plausibility is not enough to pick
/// between them (see DRagLint.Index.Manifest.OrderDbsByMembership).
///
/// Deliberately NOT a method on ISymbolStore: constructing TSQLiteSymbolStore
/// runs schema-currency checks and prepares the full statement set, which is
/// far more than a single existence probe needs and fails outright on a DB whose
/// schema predates the current version -- exactly the databases a caller most
/// wants a truthful "no" from rather than an exception.
///
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

uses
  FireDAC.Comp.Client
  ;

const
  /// <summary>How long a drag-lint connection waits for a lock before a
  /// statement fails SQLITE_BUSY ("database is locked"), in milliseconds.</summary>
  DEFAULT_BUSY_TIMEOUT_MS = 5000;

/// <summary>Makes every statement on AConn -- INCLUDING the pragmas FireDAC runs
/// inside the connect itself -- wait up to ABusyTimeoutMs for a lock instead of
/// failing SQLITE_BUSY at once. Call it BEFORE AConn is connected.</summary>
/// <param name="AConn">An unconnected FireDAC SQLite connection. The caller owns
/// it; its BusyTimeout param and UpdateOptions.LockWait are overwritten.</param>
/// <param name="ABusyTimeoutMs">The wait, in milliseconds.</param>
/// <remarks>
/// WHY `PRAGMA busy_timeout` AFTER THE CONNECT IS NOT ENOUGH. FireDAC runs
/// cache_size, locking_mode, synchronous, journal_mode and foreign_keys pragmas
/// INSIDE `Connected := True` (FireDAC.Phys.SQLite.pas, InternalConnect), and
/// cache_size already reads the schema. Its TSQLiteDatabase starts with a busy
/// timeout of 0 and arms its BusyTimeout param only for statements whose
/// UpdateOptions.LockWait is True (SetupForStmt). So those pragmas ran with NO
/// busy handler, and a reader that opened while another connection briefly
/// held the database EXCLUSIVE -- in WAL mode the LAST connection to close does,
/// to checkpoint and delete the -wal -- died with "database is locked" (about 1
/// open in 300 under 12 concurrent readers, 2026-09-23). Setting LockWait on the
/// connection makes FireDAC call sqlite3_busy_timeout before EVERY statement,
/// the connect-time pragmas included; statements inherit it from the
/// connection. Pinned by tests\autotest\run_readonly_concurrency_guard.ps1.
/// Thread-safe: touches only AConn.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.FileMembership.ConnectReadOnly (DRagLint.Storage.FileMembership.pas), DRagLint.Storage.FileMembership.ConnectWriter (DRagLint.Storage.FileMembership.pas)</para>
/// <para>Calls: IntToStr</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ArmBusyTimeout(AConn: TFDConnection; ABusyTimeoutMs: Integer = DEFAULT_BUSY_TIMEOUT_MS);

/// <summary>Connects AConn to the existing SQLite file ADbPath as a READER: a
/// read-write open (never CREATE) with a PRIVATE cache, the busy timeout armed
/// before the connect, the journal mode the file already has, normal (not
/// exclusive) locking, and `PRAGMA query_only = ON`.</summary>
/// <param name="AConn">An unconnected FireDAC connection; the caller owns it and
/// frees it. Its DriverName, Params and UpdateOptions.LockWait are overwritten.</param>
/// <param name="ADbPath">Full path to the .sqlite file. The caller checks that
/// it exists: OpenMode=ReadWrite (SQLITE_OPEN_READWRITE without
/// SQLITE_OPEN_CREATE) makes the open of a missing file RAISE instead of
/// creating an empty one, as FireDAC's default open mode did before 2026-09-24.</param>
/// <param name="ABusyTimeoutMs">Lock wait for every statement, see ArmBusyTimeout.</param>
/// <remarks>
/// RAISES nothing of its own; FireDAC's ESQLiteNativeException PROPAGATES when
/// the file cannot be opened or a lock outlasts ABusyTimeoutMs, and the verb
/// reports it on stderr with a non-zero exit.
/// The ONE way a drag-lint reader opens an index. NOT OpenMode=ReadOnly (a true
/// SQLITE_OPEN_READONLY), and not because it fails: it works. D25 (2026-09-24)
/// MEASURED that SQLite 3.45.3 (FireDAC's static build) opens a WAL index
/// read-only -- cleanly closed, under another process's BEGIN IMMEDIATE, and
/// with a read-only -shm beside a live writer -- as long as the journal_mode
/// pragma FireDAC always runs names WAL; the "disk I/O error" older comments
/// blamed on the -shm was FireDAC's default `journal_mode = DELETE` (probe
/// table: CHANGELOG v1.18.0-alpha). It is refused for what it does at CLOSE
/// (controller ruling R21, battery 2026-09-24): a read-only connection that
/// closes LAST can neither checkpoint the WAL nor delete the -wal/-shm. So
/// (1) every read of a cleanly closed index, and every graceful LSP shutdown,
/// left both files beside it (run_control_channel_guard.ps1 S5 / F1-4 went
/// red); and (2) WORSE, committed pages a writer left in the -wal -- a killed
/// indexer, a writer that closed while a reader was still open -- stayed
/// OUTSIDE the main file until the next writer, so copying X.sqlite alone, the
/// standard practice here, silently lost them. A read-write handle under
/// query_only does its last-close checkpoint and cleanup like any connection:
/// query_only refuses STATEMENTS, not the pager's close-time checkpoint.
/// Pinned by run_readonly_verbs.ps1 (no sidecar after any read verb; a dead
/// writer's WAL folded into the main file by the closing reader).
/// A PRIVATE CACHE, hence SharedCache=False (kept deliberately, ruling R22).
/// FireDAC's static SQLite switches shared-cache mode on for the whole process
/// (FireDAC.Phys.SQLiteWrapper.Stat, InternalAfterLoad), and a connection with
/// no SharedCache param joins the shared cache of any other connection to the
/// same file in the process. Connections sharing a cache share one pager:
/// they take TABLE-level locks that fail SQLITE_LOCKED, which the busy
/// timeout does not retry (the "database schema is locked" the D25 probe
/// hit), and a pragma or open mode on one leaks to the others (the probe saw
/// a query_only connection beside a live writer ALLOWED to write, rewriting
/// the header). While readers were SQLITE_OPEN_READONLY (D25) a writer that
/// joined a reader's cache could not write at all: `document --project
/// --apply --reindex` died "attempt to write a readonly database" (exit 3).
/// run_readonly_then_writer_same_process.ps1 is the regression check for that
/// verb; since readers are read-write again it can no longer fail on this
/// param, so SharedCache=False is currently UNPINNED by any test.
/// ConnectWriter sets the same param, so no drag-lint connection ever shares
/// a cache with another.
/// What keeps the handle a reader: the journal_mode pragma names the header's
/// mode (HeaderSaysWal), so it is a no-op; locking_mode is Normal, so a reader
/// never holds the file exclusively; and query_only makes every write
/// statement on the handle fail SQLITE_READONLY.
/// A raw TFDConnection opened with FireDAC's DEFAULT params does the opposite on
/// both counts -- LockingMode=Exclusive and JournalMode=Delete, which converted
/// a WAL index to a rollback journal (header byte 18: 2 -> 1) under `top`,
/// `graph`, `diff`, `query hints` and `--selftest-schema` until 2026-09-23.
/// Does not check the schema version: a caller that needs the current schema
/// asks for it (TSQLiteSymbolStore.IsSchemaCurrent) and refuses a stale one.
/// Thread-safe: touches only AConn.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DbLooksHealthy (DRagLint.CLI.pas), DRagLint.CLI.DoDiff (DRagLint.CLI.pas), DRagLint.CLI.DoExportObsidian (DRagLint.CLI.pas), DRagLint.CLI.DoGraph (DRagLint.CLI.pas), DRagLint.CLI.DoMigrateDbs (DRagLint.CLI.pas) (+8 more)</para>
/// <para>Calls: DRagLint.Storage.FileMembership.ArmBusyTimeout, DRagLint.Storage.FileMembership.HeaderSaysWal</para>
/// <seealso cref="DRagLint.Storage.FileMembership.ArmBusyTimeout"/>
/// <seealso cref="DRagLint.Storage.FileMembership.HeaderSaysWal"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ConnectReadOnly(AConn: TFDConnection; const ADbPath: string;
  ABusyTimeoutMs: Integer = DEFAULT_BUSY_TIMEOUT_MS);

/// <summary>Connects AConn to the SQLite file ADbPath as a WRITER: a private
/// cache, the busy timeout armed before the connect, normal (not exclusive)
/// locking, synchronous NORMAL, and journal mode WAL.</summary>
/// <param name="AConn">An unconnected FireDAC connection; the caller owns it and
/// frees it. Its DriverName, Params and UpdateOptions.LockWait are overwritten.</param>
/// <param name="ADbPath">Full path to the .sqlite file. A missing file is
/// CREATED (FireDAC's default open mode), in WAL mode.</param>
/// <param name="ABusyTimeoutMs">Lock wait for every statement, see ArmBusyTimeout.</param>
/// <remarks>
/// RAISES nothing of its own; FireDAC's ESQLiteNativeException PROPAGATES when
/// the file cannot be opened or a lock outlasts ABusyTimeoutMs.
/// The ONE way drag-lint opens an index for writing (2026-09-24, D24):
/// TSQLiteSymbolStore.Connect's write path, `import-log` and `migrate-dbs`'s
/// checkpoint probe all come through here. Before it, the last two opened a raw
/// TFDConnection with FireDAC's DEFAULT params -- LockingMode=Exclusive and
/// `journal_mode = DELETE` -- which converted a WAL index to a rollback journal
/// (header byte 18: 2 -> 1) and held it exclusively for the whole run. Pinned
/// by tests\autotest\run_readonly_verbs.ps1.
/// WHY A FIXED 'WAL' (controller ruling R16, fix round 1): every drag-lint
/// index is WAL, and a WRITER requesting WAL is what restores one. The D24
/// defect was a writer flipping WAL -> rollback; requesting WAL never does
/// that. The first cut of this routine kept the header's own mode, which left
/// an index already flipped by the old import-log / migrate-dbs bug a
/// rollback journal for ever -- not power-loss safe under synchronous=NORMAL,
/// and a long-lived LSP reader blocks the indexer's commit. Now any write
/// (an incremental index included) converts it back, as the store's writer
/// did before D24. Readers are different: ConnectReadOnly names the header's
/// mode, because a reader must never convert anything.
/// PRIVATE CACHE (SharedCache=False) for the reasons on ConnectReadOnly: a
/// shared cache means table-level SQLITE_LOCKED the busy timeout does not
/// retry, and pragmas leaking between connections. Unpinned by any test.
/// Thread-safe: touches only AConn.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoImportLog (DRagLint.CLI.pas), DRagLint.CLI.DoMigrateDbs (DRagLint.CLI.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.Connect (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: DRagLint.Storage.FileMembership.ArmBusyTimeout</para>
/// <seealso cref="DRagLint.Storage.FileMembership.ArmBusyTimeout"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ConnectWriter(AConn: TFDConnection; const ADbPath: string;
  ABusyTimeoutMs: Integer = DEFAULT_BUSY_TIMEOUT_MS);

/// <summary>True when ADbPath is a readable index whose files table holds
/// AFilePath.</summary>
/// <param name="ADbPath">Full path to a .sqlite index. A missing, empty,
/// locked, corrupt or pre-schema database yields False, never an exception.</param>
/// <param name="AFilePath">Absolute path of the source file to look for.</param>
/// <returns>True only on a definite match; False on no-match AND on every
/// failure to determine one.</returns>
/// <remarks>
/// PATH NORMALISATION mirrors the storage layer exactly, because the
/// stored spelling is not the caller's spelling. Rows are written through
/// NormalizeStoredPath (DRagLint.Storage.SQLite): forward slashes folded to
/// backslashes and the DRIVE LETTER upper-cased, with the rest of the path left
/// as spelled. So this expands to a full path, applies the same two rules, tries
/// a BYTE-EXACT match first -- which the UNIQUE index on files.path serves -- and
/// only then retries COLLATE NOCASE for a differently-cased directory or file
/// name.
/// The exact-first order is not a micro-optimisation, it is this codebase's
/// standing rule: SQLite cannot serve a NOCASE comparison from a BINARY index,
/// so a NOCASE-only lookup degrades to a scan on every index built before the
/// NOCASE indexes existed. The retry runs only where the answer would otherwise
/// be a false "no".
/// Opens READ-ONLY and closes before returning: an IDE-side caller must not hold
/// a handle that a concurrent `index --all` would have to drop.
/// LEAVES THE FILE HEADER ALONE TOO. The connection is told the journal mode
/// the file ALREADY has (read from the SQLite header, see HeaderSaysWal), so
/// the journal_mode pragma FireDAC runs on every connect is a no-op: a WAL
/// index stays WAL, a rollback-journal database stays a rollback journal.
/// Until 2026-09-14 the probe asked for WAL unconditionally and rewrote the
/// header of every non-WAL database it touched. Pinned both ways by
/// run_project_db_resolve.ps1 (6d).
/// Thread-safe: no shared state; each call owns its connection.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoQueryTypeUsage (DRagLint.CLI.pas), DRagLint.CLI.DoQueryUnitUsage (DRagLint.CLI.pas), DRagLint.CLI.ResolveFrameworkContextDb.TheOnlyProjectDb (DRagLint.CLI.pas), DRagLint.CLI.ResolveReadDbsForFileWith (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Storage.FileMembership.ConnectReadOnly, DRagLint.Storage.FileMembership.NormalizeForLookup</para>
/// <para>Returns: False; not Q.Eof</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>SQL: reads FILES</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Storage.FileMembership.ConnectReadOnly"/>
/// <seealso cref="DRagLint.Storage.FileMembership.NormalizeForLookup"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DbContainsFile(const ADbPath, AFilePath: string): Boolean;

/// <summary>True when the SQLite file at APath is in WAL mode, read straight
/// from the file header (offset 18, "file format write version": 2 = WAL,
/// 1 = rollback journal -- sqlite.org/fileformat2).</summary>
/// <param name="APath">Full path to a .sqlite file. Opened read-only, shared,
/// and closed before returning.</param>
/// <returns>True only when the header says WAL. A missing, unreadable or
/// too-short file (0 bytes -- created and never written) reads as False, i.e.
/// a rollback journal, on which journal_mode=Delete is a no-op.</returns>
/// <remarks>
/// WHY A CONNECTION HAS TO BE TOLD THE MODE AT ALL. FireDAC executes
/// `PRAGMA journal_mode = &lt;the JournalMode param, else Delete&gt;` on EVERY
/// connect (FireDAC.Phys.SQLite.pas, SetPragma) -- there is no "leave it alone"
/// value. So a READER leaves the header untouched only by asking for what is
/// already there. Passing WAL unconditionally rewrote every rollback-journal
/// database a read probe touched (measured on seven verbs, 2026-09-14); passing
/// nothing sends Delete and converts every real WAL index back on each probe,
/// or fails BUSY under a live LSP reader. Neither is a read.
/// Exported (2026-09-15) so TSQLiteSymbolStore.Connect's read-only path and the
/// LSP server use THIS reading of the header rather than a second copy of it.
/// Thread-safe: no shared state.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.FileMembership.ConnectReadOnly (DRagLint.Storage.FileMembership.pas)</para>
/// <para>Returns: False; (F.Read(Hdr, SizeOf(Hdr)) = SizeOf(Hdr))</para>
/// <para>Catches: Exception (swallowed)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HeaderSaysWal(const APath: string): Boolean;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , FireDAC.Stan.Def
  , FireDAC.Stan.Param
  , FireDAC.Phys.SQLite
  , FireDAC.DApt
  ;

{ Same two rules as DRagLint.Storage.SQLite.NormalizeStoredPath. Duplicated
  rather than exported from there because that unit is the whole 275 KB symbol
  store; a membership probe that dragged it in would defeat this unit's purpose.
  Three lines, and the pair is pinned by run_project_db_resolve.ps1, which asserts
  against DBs the real indexer wrote. }
function NormalizeForLookup(const APath: string): string;
begin
  Result:= '';
  if APath = '' then Exit;
  Result:= StringReplace(ExpandFileName(APath), '/', '\', [rfReplaceAll]);
  if (Length(Result) >= 2) and (Result[2] = ':') and (Result[1] >= 'a') and (Result[1] <= 'z') then
    Result[1]:= UpCase(Result[1]);
end;

{ See the interface doc on HeaderSaysWal for why a reader must name the mode
  the file already has. }
const
  SQLITE_HDR_WRITE_VERSION_OFFSET = 18; { sqlite.org/fileformat2, "file format write version" }
  SQLITE_HDR_WRITE_VERSION_WAL    = 2 ; { 2 = WAL; 1 = legacy rollback journal }

function HeaderSaysWal(const APath: string): Boolean;
var
  F  : TFileStream                                        ;
  Hdr: array[0..SQLITE_HDR_WRITE_VERSION_OFFSET] of Byte;
begin
  Result:= False;
  try
    F:= TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      Result:= (F.Read(Hdr, SizeOf(Hdr)) = SizeOf(Hdr))
           and (Hdr[SQLITE_HDR_WRITE_VERSION_OFFSET] = SQLITE_HDR_WRITE_VERSION_WAL);
    finally
      F.Free;
    end; // try
  except
    on E: Exception do Result:= False;
  end; // try
end; // function

procedure ArmBusyTimeout(AConn: TFDConnection; ABusyTimeoutMs: Integer);
begin
  AConn.Params.Values['BusyTimeout']:= IntToStr(ABusyTimeoutMs);
  AConn.UpdateOptions.LockWait     := True;
end; // procedure

procedure ConnectReadOnly(AConn: TFDConnection; const ADbPath: string; ABusyTimeoutMs: Integer);
begin
  AConn.DriverName:= 'SQLite';
  AConn.Params.Values['Database'   ]:= ADbPath;
  AConn.Params.Values['OpenMode'   ]:= 'ReadWrite'; { never CREATE; not ReadOnly: a read-only last closer cannot checkpoint (R21) }
  AConn.Params.Values['SharedCache']:= 'False';     { private cache: an in-process writer must never share it }
  AConn.Params.Values['LockingMode']:= 'Normal';
  AConn.Params.Values['JournalMode']:= if HeaderSaysWal(ADbPath) then 'WAL' else 'Delete';
  AConn.Params.Values['Synchronous']:= 'Normal';
  ArmBusyTimeout(AConn, ABusyTimeoutMs);
  AConn.LoginPrompt:= False;
  AConn.Connected  := True;
  AConn.ExecSQL('PRAGMA query_only = ON'); { reject every write on this handle }
end; // procedure

procedure ConnectWriter(AConn: TFDConnection; const ADbPath: string; ABusyTimeoutMs: Integer);
begin
  AConn.DriverName:= 'SQLite';
  AConn.Params.Values['Database'   ]:= ADbPath;
  AConn.Params.Values['SharedCache']:= 'False'; { private cache: see ConnectReadOnly }
  AConn.Params.Values['LockingMode']:= 'Normal';
  AConn.Params.Values['JournalMode']:= 'WAL';   { R16: a writer restores WAL, never leaves it }
  AConn.Params.Values['Synchronous']:= 'Normal';
  ArmBusyTimeout(AConn, ABusyTimeoutMs);
  AConn.LoginPrompt:= False;
  AConn.Connected  := True;
end; // procedure

const
  MEMBERSHIP_BUSY_TIMEOUT_MS = 2000; { a probe answers "no" sooner than a verb gives up }

function DbContainsFile(const ADbPath, AFilePath: string): Boolean;
var
  Conn: TFDConnection;
  Q   : TFDQuery     ;
  NP  : string       ;
begin
  Result:= False;
  if (ADbPath = '') or (AFilePath = '') then Exit;
  if not TFile.Exists(ADbPath) then Exit;

  NP:= NormalizeForLookup(AFilePath);
  if NP = '' then Exit;

  try
    Conn:= TFDConnection.Create(nil);
    try
      { A failed open here would be reported as a truthful-looking "file not in
        this DB", so the open mode matters. ConnectReadOnly opens read-write
        (never create) under query_only, NOT SQLITE_OPEN_READONLY: the latter
        opens a WAL index fine (measured, D25) but, as the last connection to
        close, can neither checkpoint nor delete the -wal/-shm -- and this
        probe is often the only connection (see ConnectReadOnly, ruling R21).
        With FireDAC's default connect-time journal_mode (Delete) a read-only
        WAL open fails "disk I/O error", which the pre-2026-09-24 comment here
        misattributed to missing write access on the -shm. ConnectReadOnly
        names the mode the header already has (HeaderSaysWal), so the pragma is
        a no-op and neither a WAL nor a rollback-journal file is rewritten;
        query_only forbids writes per-connection without disturbing a
        concurrent LSP/indexer; and the busy timeout is armed BEFORE the
        connect (see ArmBusyTimeout). }
      ConnectReadOnly(Conn, ADbPath, MEMBERSHIP_BUSY_TIMEOUT_MS);

      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        try
          { Byte-exact first: served by the UNIQUE index on files.path. }
          Q.SQL.Text:= 'SELECT 1 FROM files WHERE path = :p LIMIT 1';
          Q.ParamByName('p').AsString:= NP;
          Q.Open;
          Result:= not Q.Eof;
          Q.Close;

          { Only on a miss, the case-insensitive retry -- for a differently-cased
            directory or file name. Bounded by the files table, which is
            per-project. }
          if not Result then
          begin
            Q.SQL.Text:= 'SELECT 1 FROM files WHERE path = :p COLLATE NOCASE LIMIT 1';
            Q.ParamByName('p').AsString:= NP;
            Q.Open;
            Result:= not Q.Eof;
          end;
        finally
          Q.Close;
        end; // try
      finally
        Q.Free;
      end; // try
    finally
      Conn.Close;
      Conn.Free;
    end; // try
  except
    { A DB that cannot be opened or has no files table cannot vouch for the file.
      False is the honest answer AND the safe one: the caller leaves its existing
      order alone rather than promoting an index it could not read. }
    on E: Exception do Result:= False;
  end; // try
end; // function

end.
