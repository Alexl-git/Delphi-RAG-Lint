unit DRagLint.Sql.Guarded;

{ ---------------------------------------------------------------------------
  GUARD RAILS FOR `drag-lint sql` -- the read-only SQL passthrough.

  WHY THE GUARD IS NOT A REGEX OVER THE SQL TEXT
    Deciding whether a SQL string is safe by reading it is a losing game: an
    ATTACH can hide behind a comment, a CTE, a case fold or a nested SELECT
    that a hand-written scanner does not model. Every control in this unit is
    therefore a mechanism SQLite ITSELF enforces, at the point where it
    compiles and runs the statement:

      * sqlite3_set_authorizer  -- reached through FireDAC's own
        TSQLiteDatabase.OnAutorize property (Embarcadero's spelling; the 'h'
        is genuinely missing from the identifier). Fires once per action
        DURING PREPARE. This is the real gate: it is what blocks ATTACH,
        PRAGMA and function-based escapes, none of which `PRAGMA query_only`
        touches.
      * sqlite3_progress_handler -- reached through TSQLiteDatabase.OnProgress.
        Fires every N virtual-machine instructions, so a cartesian join is
        interrupted mid-step rather than after it finishes.

    The connection this guard is installed on is opened by
    TSQLiteSymbolStore.Connect(.., AReadOnly=True), which has ALREADY set
    `PRAGMA query_only = ON` and a busy_timeout. That is a THIRD, independent
    layer, and the reason this unit does not repeat it. Do not "fix" that open
    to use FireDAC OpenMode=ReadOnly -- the comment at its site records why a
    WAL database cannot be opened that way.

  FAIL CLOSED, ALWAYS
    Create RAISES when the native handle cannot be reached. A guard that
    quietly does nothing when it cannot install itself is worse than no guard,
    because every caller downstream reads "no exception" as "protected". The
    verb turns that exception into a refusal to run the query at all.

  THE INDEXES ARE THE USER'S WORKING SET
    Some are gigabytes and the IDE/LSP holds them open. A bug here does not
    just return a wrong answer, it can wedge an editor. Hence the time cap is
    a REQUIRED constructor argument rather than an option with a default that
    somebody can forget to pass.
  --------------------------------------------------------------------------- }

interface

uses
  System.SysUtils
  , System.Diagnostics
  , FireDAC.Comp.Client
  , FireDAC.Phys.SQLiteWrapper
  ;

type
  /// <summary>Raised when the guard cannot install itself on a connection.</summary>
  /// <remarks>Distinct class on purpose: the verb catches THIS and refuses to
  /// run the query, which must not be confused with an error raised by the
  /// query itself.</remarks>
  ESqlGuardError = class(Exception);

  /// <summary>Installs an SQLite authorizer and a progress (time-cap) handler
  /// on an already-connected FireDAC SQLite connection, and removes both on
  /// destruction. One guard per query; it is not reusable and not
  /// thread-safe.</summary>
  /// <remarks>
  /// The authorizer permits SELECT, table/column READ, RECURSIVE, safe scalar
  /// functions, and transaction/savepoint control (which cannot mutate
  /// anything on a query_only handle, and which FireDAC may issue on its own
  /// behalf around a dataset open). EVERY other action code is denied,
  /// including ATTACH, DETACH and PRAGMA. The first denial is remembered so
  /// the caller can report WHICH action was refused instead of SQLite's bare
  /// "not authorized".
  ///
  /// Not thread-safe: the hooks are per-connection and the recorded state is
  /// per-instance. Create it, run one query, free it.
  /// </remarks>
  TSqlGuard = class
    private
      FNative     : TSQLiteDatabase;
      FClock      : TStopwatch     ;
      FTimeoutMs  : Integer        ;
      FTimedOut   : Boolean        ;
      FDenied     : Boolean        ;
      FDeniedCode : Integer        ;
      FDeniedName : string         ;
      FPrevNOpers : Integer        ;
      procedure HandleAuthorize(ADB: TSQLiteDatabase; ACode: Integer;
        const AArg1, AArg2, AArg3, AArg4: string; var AResult: Integer);
      procedure HandleProgress(ADB: TSQLiteDatabase; var ACancel: Boolean);
    public
      /// <summary>Installs both hooks on AConn's native SQLite handle.</summary>
      /// <param name="AConn">A CONNECTED FireDAC SQLite connection. The caller
      /// keeps ownership; the guard only borrows it.</param>
      /// <param name="ATimeoutMs">Wall-clock budget for the query, in
      /// milliseconds. Must be positive -- there is deliberately no "no cap"
      /// value, because an unbounded query against a multi-gigabyte index can
      /// wedge the IDE holding it open. Pass a large number instead.</param>
      /// <exception cref="ESqlGuardError">Raised when the native handle cannot be
      /// reached (connection not open, or a non-SQLite driver). The guard
      /// FAILS CLOSED: the caller must abandon the query, not run it
      /// unguarded.</exception>
      constructor Create(AConn: TFDConnection; ATimeoutMs: Integer);

      /// <summary>Removes both hooks and restores the previous progress
      /// granularity.</summary>
      destructor Destroy; override;

      /// <summary>Human-readable account of why the query was stopped.</summary>
      /// <returns>A single line naming the denied action (with its argument)
      /// or the elapsed time cap; empty when neither happened.</returns>
      function Explain: string;

      /// <summary>Milliseconds elapsed since the guard was installed.</summary>
      /// <returns>Wall-clock milliseconds; the value the time cap is compared
      /// against.</returns>
      function ElapsedMs: Int64;

      /// <summary>True when the time cap elapsed and the query was
      /// interrupted mid-execution.</summary>
      property TimedOut: Boolean read FTimedOut;

      /// <summary>True when the authorizer refused an action.</summary>
      property Denied: Boolean read FDenied;
  end;

/// <summary>Maps an SQLite authorizer action code to its documented name.</summary>
/// <param name="ACode">One of the SQLITE_* authorizer action codes.</param>
/// <returns>The action's name (e.g. 'ATTACH'), or 'action &lt;n&gt;' for a code
/// this build does not know -- a newer SQLite may add codes, and an unnamed
/// code must still be reportable.</returns>
function SqlActionName(ACode: Integer): string;

/// <summary>Rejects anything that is not exactly one SQL statement.</summary>
/// <param name="ASql">The raw query text.</param>
/// <param name="AReason">Set to a user-facing explanation when the result is
/// False; set to '' otherwise.</param>
/// <returns>True when ASql holds exactly one statement (a single trailing
/// semicolon is allowed).</returns>
/// <remarks>
/// This is DEFENCE IN DEPTH, not the gate -- the authorizer is. It exists so
/// that "SELECT 1; DROP TABLE symbols" fails with a clear message about
/// multiple statements rather than a confusing authorizer denial about the
/// second one. The scan skips single-quoted strings, double-quoted and
/// bracketed and backticked identifiers, -- line comments and block comments,
/// so a semicolon inside any of those does not count.
/// </remarks>
function IsSingleStatement(const ASql: string; out AReason: string): Boolean;

implementation

uses
  FireDAC.Phys.SQLiteCli
  ;

{ Scalar functions refused regardless of the action code that carries them.
  None of these ships in a stock SQLite library, but a loadable extension or a
  future Embarcadero build could provide them, and every one of them either
  touches the filesystem or executes code. Denying by name costs nothing and
  the list is the honest statement of what we are afraid of. }
const
  DENIED_FUNCTIONS: array[0..6] of string = (
    'load_extension', 'readfile', 'writefile', 'edit',
    'fts3_tokenizer', 'zipfile', 'sqlite_dbpage'
  );

function SqlActionName(ACode: Integer): string;
begin
  case ACode of
    SQLITE_CREATE_INDEX       : Result:= 'CREATE INDEX'        ;
    SQLITE_CREATE_TABLE       : Result:= 'CREATE TABLE'        ;
    SQLITE_CREATE_TEMP_INDEX  : Result:= 'CREATE TEMP INDEX'   ;
    SQLITE_CREATE_TEMP_TABLE  : Result:= 'CREATE TEMP TABLE'   ;
    SQLITE_CREATE_TEMP_TRIGGER: Result:= 'CREATE TEMP TRIGGER' ;
    SQLITE_CREATE_TEMP_VIEW   : Result:= 'CREATE TEMP VIEW'    ;
    SQLITE_CREATE_TRIGGER     : Result:= 'CREATE TRIGGER'      ;
    SQLITE_CREATE_VIEW        : Result:= 'CREATE VIEW'         ;
    SQLITE_DELETE             : Result:= 'DELETE'              ;
    SQLITE_DROP_INDEX         : Result:= 'DROP INDEX'          ;
    SQLITE_DROP_TABLE         : Result:= 'DROP TABLE'          ;
    SQLITE_DROP_TEMP_INDEX    : Result:= 'DROP TEMP INDEX'     ;
    SQLITE_DROP_TEMP_TABLE    : Result:= 'DROP TEMP TABLE'     ;
    SQLITE_DROP_TEMP_TRIGGER  : Result:= 'DROP TEMP TRIGGER'   ;
    SQLITE_DROP_TEMP_VIEW     : Result:= 'DROP TEMP VIEW'      ;
    SQLITE_DROP_TRIGGER       : Result:= 'DROP TRIGGER'        ;
    SQLITE_DROP_VIEW          : Result:= 'DROP VIEW'           ;
    SQLITE_INSERT             : Result:= 'INSERT'              ;
    SQLITE_PRAGMA             : Result:= 'PRAGMA'              ;
    SQLITE_READ               : Result:= 'READ'                ;
    SQLITE_SELECT             : Result:= 'SELECT'              ;
    SQLITE_TRANSACTION        : Result:= 'TRANSACTION'         ;
    SQLITE_UPDATE             : Result:= 'UPDATE'              ;
    SQLITE_ATTACH             : Result:= 'ATTACH'              ;
    SQLITE_DETACH             : Result:= 'DETACH'              ;
    SQLITE_ALTER_TABLE        : Result:= 'ALTER TABLE'         ;
    SQLITE_REINDEX            : Result:= 'REINDEX'             ;
    SQLITE_ANALYZE            : Result:= 'ANALYZE'             ;
    SQLITE_CREATE_VTABLE      : Result:= 'CREATE VIRTUAL TABLE';
    SQLITE_DROP_VTABLE        : Result:= 'DROP VIRTUAL TABLE'  ;
    SQLITE_FUNCTION           : Result:= 'FUNCTION'            ;
    SQLITE_SAVEPOINT          : Result:= 'SAVEPOINT'           ;
    SQLITE_RECURSIVE          : Result:= 'RECURSIVE'           ;
  else
    Result:= Format('action %d', [ACode]);
  end;
end;

function IsSingleStatement(const ASql: string; out AReason: string): Boolean;
var
  i    : Integer;
  n    : Integer;
  Ch   : Char   ;
  Ended: Boolean; { a ';' has been passed and only whitespace has followed }
begin
  AReason:= '';
  n:= Length(ASql);
  i:= 1;
  Ended:= False;
  while i <= n do
  begin
    Ch:= ASql[i];

    { Anything at all after a statement-terminating ';' is a second statement.
      Whitespace is not "anything" -- a trailing ';' plus a newline is the
      normal shape of a query pasted out of a .sql file. }
    if Ended and not CharInSet(Ch, [#9, #10, #13, ' ']) then
    begin
      AReason:= 'more than one statement (something follows the '';'')';
      Exit(False);
    end;

    if Ch = '''' then
    begin
      Inc(i);
      while i <= n do
      begin
        if ASql[i] = '''' then
        begin
          if (i < n) and (ASql[i + 1] = '''') then Inc(i) { '' is an escaped quote }
          else Break;
        end;
        Inc(i);
      end;
    end
    else if Ch = '"' then
    begin
      Inc(i);
      while (i <= n) and (ASql[i] <> '"') do Inc(i);
    end
    else if Ch = '`' then
    begin
      Inc(i);
      while (i <= n) and (ASql[i] <> '`') do Inc(i);
    end
    else if Ch = '[' then
    begin
      Inc(i);
      while (i <= n) and (ASql[i] <> ']') do Inc(i);
    end
    else if (Ch = '-') and (i < n) and (ASql[i + 1] = '-') then
    begin
      while (i <= n) and not CharInSet(ASql[i], [#10, #13]) do Inc(i);
      Dec(i); { the loop's Inc puts us back on the line break }
    end
    else if (Ch = '/') and (i < n) and (ASql[i + 1] = '*') then
    begin
      Inc(i, 2);
      while (i < n) and not ((ASql[i] = '*') and (ASql[i + 1] = '/')) do Inc(i);
      Inc(i); { land on the '/', the loop's Inc steps past it }
    end
    else if Ch = ';' then
      Ended:= True;

    Inc(i);
  end;

  { An empty or semicolon-only query is not one statement either, and SQLite
    would answer it with an empty result set rather than an error -- which
    reads as "your query returned nothing" and sends the reader hunting for
    data that was never asked for. }
  if Trim(StringReplace(ASql, ';', '', [rfReplaceAll])) = '' then
  begin
    AReason:= 'the query is empty';
    Exit(False);
  end;

  Result:= True;
end;

constructor TSqlGuard.Create(AConn: TFDConnection; ATimeoutMs: Integer);
var
  Obj: Pointer;
begin
  inherited Create;
  FTimeoutMs := ATimeoutMs;
  FTimedOut  := False;
  FDenied    := False;
  FDeniedCode:= 0;
  FDeniedName:= '';
  FNative    := nil;

  if AConn = nil then
    raise ESqlGuardError.Create('SQL guard: no connection');
  if not AConn.Connected then
    raise ESqlGuardError.Create('SQL guard: the connection is not open, so the SQLite handle does not exist yet');
  if ATimeoutMs <= 0 then
    raise ESqlGuardError.Create('SQL guard: the time cap must be positive');

  { FireDAC exposes the driver-level object behind the connection as CliObj;
    for the SQLite driver that object IS TSQLiteDatabase (see
    FireDAC.Phys.SQLite.TFDPhysSQLiteConnection.GetCliObj). Verified with a
    type check rather than assumed, so a driver swap fails loudly here instead
    of corrupting a pointer. }
  Obj:= AConn.CliObj;
  if Obj = nil then
    raise ESqlGuardError.Create('SQL guard: FireDAC exposed no native SQLite handle (CliObj is nil)');
  if not (TObject(Obj) is TSQLiteDatabase) then
    raise ESqlGuardError.Create('SQL guard: the connection is not an SQLite connection');
  FNative:= TSQLiteDatabase(Obj);

  { Order matters: SetOnProgress installs the handler with the CURRENT
    granularity, so the granularity has to be set first or the first install
    would use FireDAC's default 100 and then be re-installed. }
  FPrevNOpers:= FNative.ProgressNOpers;
  FNative.ProgressNOpers:= 1000;

  FClock:= TStopwatch.StartNew;
  FNative.OnProgress := HandleProgress ;
  FNative.OnAutorize := HandleAuthorize;
end;

destructor TSqlGuard.Destroy;
begin
  if FNative <> nil then
  begin
    { Both setters call into sqlite3 and both ASSERT on a live handle. A
      connection torn down underneath us would make that an access violation
      during cleanup, which would mask whatever the real failure was. }
    try
      FNative.OnAutorize:= nil;
      FNative.OnProgress:= nil;
      FNative.ProgressNOpers:= FPrevNOpers;
    except
      { deliberately swallowed: detaching a hook from a dead handle is not a
        failure the caller can act on, and raising from a destructor would
        replace the original error with this one }
    end;
  end;
  inherited;
end;

function TSqlGuard.ElapsedMs: Int64;
begin
  Result:= FClock.ElapsedMilliseconds;
end;

procedure TSqlGuard.HandleProgress(ADB: TSQLiteDatabase; var ACancel: Boolean);
begin
  if FClock.ElapsedMilliseconds >= FTimeoutMs then
  begin
    FTimedOut:= True;
    ACancel  := True;
  end;
end;

procedure TSqlGuard.HandleAuthorize(ADB: TSQLiteDatabase; ACode: Integer;
  const AArg1, AArg2, AArg3, AArg4: string; var AResult: Integer);
var
  FnName: string;
  Banned: string;
begin
  AResult:= SQLITE_OK;

  case ACode of
    { The reads a SELECT is made of. }
    SQLITE_SELECT, SQLITE_READ, SQLITE_RECURSIVE:
      Exit;

    { Not a relaxation. A BEGIN/COMMIT/SAVEPOINT changes no row and creates no
      object, and the handle is already query_only, so the writes such a
      transaction could wrap are refused anyway. It is permitted because
      FireDAC may issue one AROUND a dataset open on its own initiative --
      denying it would break every legitimate query with an error about a
      statement the user never wrote. }
    SQLITE_TRANSACTION, SQLITE_SAVEPOINT:
      Exit;

    SQLITE_FUNCTION:
      begin
        { SQLite documents SQLITE_FUNCTION as (NULL, function name); FireDAC's
          own comment in SQLiteCli.pas has the two columns the other way round.
          Rather than pick a side, take whichever argument is non-empty. }
        FnName:= AArg2;
        if FnName = '' then FnName:= AArg1;
        for Banned in DENIED_FUNCTIONS do
          if SameText(FnName, Banned) then
          begin
            if not FDenied then
            begin
              FDenied    := True;
              FDeniedCode:= ACode;
              FDeniedName:= FnName + '()';
            end;
            AResult:= SQLITE_DENY;
            Exit;
          end;
        Exit;
      end;
  end;

  { Everything else -- ATTACH, DETACH, PRAGMA, every DDL, every write. }
  if not FDenied then
  begin
    FDenied    := True;
    FDeniedCode:= ACode;
    FDeniedName:= Trim(AArg1);
    if FDeniedName = '' then FDeniedName:= Trim(AArg2);
  end;
  AResult:= SQLITE_DENY;
end;

function TSqlGuard.Explain: string;
begin
  if FTimedOut then
    Exit(Format('the query hit the %d ms time cap and was interrupted (raise it with --timeout-ms)', [FTimeoutMs]));
  if FDenied then
  begin
    Result:= Format('%s is not permitted', [SqlActionName(FDeniedCode)]);
    if FDeniedName <> '' then Result:= Result + Format(' (%s)', [FDeniedName]);
    Exit;
  end;
  Result:= '';
end;

end.
