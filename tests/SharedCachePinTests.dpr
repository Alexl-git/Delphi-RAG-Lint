program SharedCachePinTests;
{$APPTYPE CONSOLE}
{ Pins ruling R22: every drag-lint connection opens a PRIVATE SQLite cache
  (SharedCache=False) -- see the remarks on ConnectReadOnly / ConnectWriter in
  src\storage\DRagLint.Storage.FileMembership.pas, which said until 2026-09-28
  that the parameter was "UNPINNED by any test".

  THE SHAPE. A reader holds a cursor open on `files` (a statement mid-step, not
  fully fetched) while a second, in-process writer inserts into `files`. With
  private caches the two connections are ordinary WAL peers: the insert
  succeeds. With a shared cache they share one pager and take TABLE-level
  locks, so the insert fails SQLITE_LOCKED -- which the busy timeout does not
  retry. FireDAC's static SQLite turns shared-cache mode on process-wide, so a
  connection without the parameter would join it.

  THE CONTROL. The same shape opened with SharedCache=True (the two connect
  routines' parameters, copied, with that one value flipped) must FAIL the
  insert. If it does not, this harness cannot observe shared-cache locking and
  the pin would pass whatever the production parameter said.

  Built and run by tests\autotest\run_sharedcache_private_pin.ps1 (dcc64 with
  the engine's src folders on -U). }
uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Error,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.DApt,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Comp.Client,
  DRagLint.Storage.FileMembership;

const
  ROW_COUNT       = 200;
  ROWSET_SIZE     = 10;
  WRITER_WAIT_MS  = 500;

var
  Failed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then Writeln('  [PASS] ', AName)
  else
  begin
    Writeln('  [FAIL] ', AName, '  ', ADetail);
    Inc(Failed);
  end;
end;

{ A fresh WAL database holding ROW_COUNT rows in `files`. }
procedure Seed(const ADbPath: string);
var
  W: TFDConnection;
  I: Integer;
begin
  W:= TFDConnection.Create(nil);
  try
    ConnectWriter(W, ADbPath);
    W.ExecSQL('CREATE TABLE files (id INTEGER PRIMARY KEY, path TEXT NOT NULL)');
    W.StartTransaction;
    for I:= 1 to ROW_COUNT do
      W.ExecSQL('INSERT INTO files (path) VALUES (:p)', [Format('u%d.pas', [I])]);
    W.Commit;
  finally
    W.Free;
  end; // try
end;

{ The CONTROL's connect: ConnectReadOnly's / ConnectWriter's parameters with
  SharedCache flipped to True. Kept beside the pin so a change to the real
  routines is visible as a difference here. }
procedure ConnectShared(AConn: TFDConnection; const ADbPath: string; AReader: Boolean);
begin
  AConn.DriverName:= 'SQLite';
  AConn.Params.Values['Database'   ]:= ADbPath;
  if AReader then AConn.Params.Values['OpenMode']:= 'ReadWrite';
  AConn.Params.Values['SharedCache']:= 'True';
  AConn.Params.Values['LockingMode']:= 'Normal';
  AConn.Params.Values['JournalMode']:= 'WAL';
  AConn.Params.Values['Synchronous']:= 'Normal';
  ArmBusyTimeout(AConn, WRITER_WAIT_MS);
  AConn.LoginPrompt:= False;
  AConn.Connected  := True;
  if AReader then AConn.ExecSQL('PRAGMA query_only = ON');
end;

{ Opens a reader cursor on `files` and leaves it MID-STEP, then inserts through
  a second connection. Returns True when the insert committed; AError carries
  the exception text otherwise. AMidStep reports whether the cursor really was
  still open (not fully fetched) when the insert ran -- without that the case
  proves nothing. }
function InsertBesideOpenCursor(const ADbPath: string; AShared: Boolean;
  out AMidStep: Boolean; out AError: string): Boolean;
var
  R, W: TFDConnection;
  Q   : TFDQuery;
begin
  Result:= False;
  AError:= '';
  AMidStep:= False;
  R:= TFDConnection.Create(nil);
  W:= TFDConnection.Create(nil);
  Q:= TFDQuery.Create(nil);
  try
    if AShared then ConnectShared(R, ADbPath, {AReader=}True)
    else ConnectReadOnly(R, ADbPath);
    Q.Connection:= R;
    Q.FetchOptions.Mode      := fmOnDemand;
    Q.FetchOptions.RowsetSize:= ROWSET_SIZE;
    Q.SQL.Text:= 'SELECT id, path FROM files ORDER BY id';
    Q.Open;
    AMidStep:= Q.Active and (not Q.SourceEOF);

    if AShared then ConnectShared(W, ADbPath, {AReader=}False)
    else ConnectWriter(W, ADbPath, WRITER_WAIT_MS);
    try
      W.ExecSQL('INSERT INTO files (path) VALUES (''added.pas'')');
      Result:= True;
    except
      on E: Exception do AError:= E.ClassName + ': ' + E.Message;
    end; // try
  finally
    Q.Free;
    W.Free;
    R.Free;
  end; // try
end;

procedure RunCase(const ADir: string; AShared: Boolean);
var
  Db     : string;
  MidStep: Boolean;
  Err    : string;
  Ok     : Boolean;
begin
  Db:= TPath.Combine(ADir, IfThen(AShared, 'shared.sqlite', 'private.sqlite'));
  Seed(Db);
  Ok:= InsertBesideOpenCursor(Db, AShared, MidStep, Err);
  if AShared then
  begin
    Check('V control: the reader cursor was still mid-step during the insert', MidStep);
    Check('P1 CONTROL with SharedCache=True the insert FAILS (the harness can see shared-cache locking)',
      not Ok, 'the insert committed -- this harness cannot observe the defect, so the pin below is vacuous');
  end
  else
  begin
    Check('V pin: the reader cursor was still mid-step during the insert', MidStep);
    Check('T1 PIN ConnectReadOnly + ConnectWriter: an in-process insert beside an open reader cursor commits',
      Ok, Err);
  end;
end;

var
  Dir: string;
begin
  try
    Dir:= TPath.Combine(TPath.GetTempPath, Format('drag-lint-sharedcache-pin-%d', [GetCurrentProcessId]));
    TDirectory.CreateDirectory(Dir);
    try
      RunCase(Dir, {AShared=}False);
      RunCase(Dir, {AShared=}True);
    finally
      TDirectory.Delete(Dir, True);
    end; // try
  except
    on E: Exception do
    begin
      Writeln('  [FAIL] unexpected ', E.ClassName, ': ', E.Message);
      Inc(Failed);
    end;
  end; // try
  if Failed = 0 then ExitCode:= 0 else ExitCode:= 1;
end.
