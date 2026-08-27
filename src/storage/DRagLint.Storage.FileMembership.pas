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

implementation

uses
  System.SysUtils
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
      { NOT OpenMode=ReadOnly. A WAL-mode database cannot be opened that way
        without write access to its -shm wal-index (SQLite wal.html), and every
        index here is WAL -- the open fails with "disk I/O error", which this
        function would then report as a truthful-looking "file not in this DB".
        Same reasoning, same params and same PRAGMA as
        TSQLiteSymbolStore.Connect's read-only path: open normally, then forbid
        writes per-connection. query_only does not disturb a concurrent
        LSP/indexer. }
      Conn.DriverName:= 'SQLite';
      Conn.Params.Values['Database'   ]:= ADbPath;
      Conn.Params.Values['LockingMode']:= 'Normal';
      Conn.Params.Values['JournalMode']:= 'WAL';
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
