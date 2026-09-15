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
/// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoQueryTypeUsage (DRagLint.CLI.pas), DRagLint.CLI.DoQueryUnitUsage (DRagLint.CLI.pas), DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas), DRagLint.CLI.ResolveFrameworkContextDb.TheOnlyProjectDb (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Storage.FileMembership.NormalizeForLookup</para>
/// <para>Returns: False; not Q.Eof</para>
/// <para>SQL: reads FILES</para>
/// <para>Touches: file system</para>
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
/// <remarks>WHY A CONNECTION HAS TO BE TOLD THE MODE AT ALL. FireDAC executes
/// `PRAGMA journal_mode = &lt;the JournalMode param, else Delete&gt;` on EVERY
/// connect (FireDAC.Phys.SQLite.pas, SetPragma) -- there is no "leave it alone"
/// value. So a READER leaves the header untouched only by asking for what is
/// already there. Passing WAL unconditionally rewrote every rollback-journal
/// database a read probe touched (measured on seven verbs, 2026-09-14); passing
/// nothing sends Delete and converts every real WAL index back on each probe,
/// or fails BUSY under a live LSP reader. Neither is a read.
/// Exported (2026-09-15) so TSQLiteSymbolStore.Connect's read-only path and the
/// LSP server use THIS reading of the header rather than a second copy of it.
/// Thread-safe: no shared state.</remarks>
function HeaderSaysWal(const APath: string): Boolean;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , FireDAC.Comp.Client
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

function DbContainsFile(const ADbPath, AFilePath: string): Boolean;
var
  Conn: TFDConnection;
  Q   : TFDQuery     ;
  NP  : string       ;
  Mode: string       ;
begin
  Result:= False;
  if (ADbPath = '') or (AFilePath = '') then Exit;
  if not TFile.Exists(ADbPath) then Exit;

  NP:= NormalizeForLookup(AFilePath);
  if NP = '' then Exit;

  try
    Conn:= TFDConnection.Create(nil);
    try
      { NOT OpenMode=ReadOnly. A WAL-mode database cannot be opened that way
        without write access to its -shm wal-index (SQLite wal.html), and every
        index here is WAL -- the open fails with "disk I/O error", which this
        function would then report as a truthful-looking "file not in this DB".
        Same reasoning and same PRAGMA as TSQLiteSymbolStore.Connect's read-only
        path: open normally, then forbid writes per-connection. query_only does
        not disturb a concurrent LSP/indexer.

        NOT the same JournalMode, though. Connect still asks for WAL on its
        read-only path too, and its comment claims the journal mode is left
        untouched -- it is not, for the reason on HeaderSaysWal. Here the mode
        is whatever the file already has, so the pragma FireDAC runs at connect
        changes nothing. query_only comes AFTER the connect, so it cannot be
        what protects the header; only naming the current mode can. }
      Mode:= if HeaderSaysWal(ADbPath) then 'WAL' else 'Delete';
      Conn.DriverName:= 'SQLite';
      Conn.Params.Values['Database'   ]:= ADbPath;
      Conn.Params.Values['LockingMode']:= 'Normal';
      Conn.Params.Values['JournalMode']:= Mode;
      Conn.Params.Values['Synchronous']:= 'Normal';
      Conn.LoginPrompt:= False;
      Conn.Open;
      Conn.ExecSQL('PRAGMA query_only = ON');
      Conn.ExecSQL('PRAGMA busy_timeout = 2000');

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
