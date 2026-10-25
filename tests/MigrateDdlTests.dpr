program MigrateDdlTests;
{$APPTYPE CONSOLE}
{ Deep-review F2 (2026-10-25): Migrate's TryExec swallowed EVERY exception, so
  a failed CREATE TABLE member_accesses / CREATE INDEX (disk full, locked, I/O)
  was indistinguishable from the idempotent no-op. ExecAdditiveDDL (the helper
  TryExec now delegates to) tolerates ONLY SQLite's "duplicate column name".

  T1 POSITIVE CONTROL: a fresh DB migrated, closed, reopened and migrated
     again succeeds -- every additive ALTER hits "duplicate column name" on the
     second run, so this fails if the tolerance is too narrow.
  T2 the same duplicate-column ALTER through the helper directly: no raise.
  T3 a deliberately broken statement through the helper: must raise.
  T4 ALTER on a missing table through the helper: must raise.
  T5 a CREATE TABLE IF NOT EXISTS while another connection holds the write
     lock (no busy timeout): "database is locked" must raise.
  T6 IsDuplicateColumnError answers False for nil and a plain Exception.
  T7 (B2) simulated no-trigram sqlite3.dll: Migrate succeeds, string_fts_tri
     and its triggers are absent, string_fts present, a string_literals insert
     succeeds (SimulateNoTrigramTokenizer is the test hook).
  T8 (B2) POSITIVE CONTROL for T7: trigram available -> string_fts_tri exists.
  T9 (B2) a DB migrated without trigram, later migrated with it: the table is
     created and back-filled from string_literals.

  Built and run by tests\autotest\run_migrate_ddl_raises.ps1. }
uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
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
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite;

var
  GPass, GFail: Integer;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS  ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', pName, ' ', pDetail);
  end;
end;

function OpenRaw(const pPath: string): TFDConnection;
begin
  Result:= TFDConnection.Create(nil);
  Result.DriverName:= 'SQLite';
  Result.Params.Values['Database']:= pPath;
  Result.Params.Values['LockingMode']:= 'Normal';
  Result.Params.Values['SharedCache']:= 'False';
  Result.Params.Values['BusyTimeout']:= '0';
  Result.LoginPrompt:= False;
  Result.Connected:= True;
  Result.ExecSQL('PRAGMA foreign_keys = OFF'); { T7/T9 insert a literal without a files row }
end;

{ Runs pSql through ExecAdditiveDDL; returns '' when nothing was raised,
  else the exception's class and message. }
function RaisedBy(const pConn: TFDConnection; const pSql: string): string;
begin
  Result:= '';
  try
    ExecAdditiveDDL(pConn, pSql);
  except on E: Exception do
    Result:= E.ClassName + ': ' + E.Message;
  end;
end;

{ First column of the first row of pSql as an integer; -1 when there is no row. }
function ScalarInt(const pConn: TFDConnection; const pSql: string): Integer;
var Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= pConn;
    Q.SQL.Text:= pSql;
    Q.Open;
    if Q.Eof then Result:= -1 else Result:= Q.Fields[0].AsInteger;
  finally
    Q.Free;
  end;
end;

{ Migrates a fresh-or-existing DB at pPath with the trigram hook set to
  pNoTrigram; '' on success, else the exception text. }
function MigrateWith(const pPath: string; pNoTrigram: Boolean): string;
var S: ISymbolStore;
begin
  Result:= '';
  SimulateNoTrigramTokenizer:= pNoTrigram;
  try
    try
      S:= TSQLiteSymbolStore.Create(pPath);
      S.Migrate;
      S:= nil;
    except on E: Exception do  // dl:ok try-except-swallowed@714b -- REVIEWED 2026-10-25: the message IS the result
      Result:= E.ClassName + ': ' + E.Message;
    end;
  finally
    SimulateNoTrigramTokenizer:= False;
  end;
end;

const
  SQL_HAS_TRI = 'SELECT COUNT(*) FROM sqlite_master WHERE name = ''string_fts_tri''';
  SQL_TRI_TRIGGERS = 'SELECT COUNT(*) FROM sqlite_master WHERE type = ''trigger'' ' +
    'AND name LIKE ''string_literals%'' AND sql LIKE ''%string_fts_tri%''';
  SQL_INSERT_LIT = 'INSERT INTO string_literals(file_id, source, kind, text, ' +
    'start_line, start_col, end_line, end_col) VALUES (1, ''pas'', ''lit'', ' +
    '''hello world'', 1, 1, 1, 5)';

var
  DbPath, DbPath2, Msg: string;
  Store      : ISymbolStore;
  Conn, Lock : TFDConnection;
begin
  DbPath:= TPath.Combine(TPath.GetTempPath,
    Format('migrate-ddl-%d.sqlite', [GetCurrentProcessId]));
  DeleteFile(DbPath); { returns False when absent -- scratch only }
  try
    // T1: positive control -- Migrate twice on one DB.
    Msg:= '';
    try
      Store:= TSQLiteSymbolStore.Create(DbPath);
      Store.Migrate;
      Store:= nil;
      Store:= TSQLiteSymbolStore.Create(DbPath);
      Store.Migrate;
      Store:= nil;
    except on E: Exception do  // dl:ok try-except-swallowed@714b -- REVIEWED 2026-10-25: the message IS the result; T1 fails on it
      Msg:= E.ClassName + ': ' + E.Message;
    end;
    Check('T1 re-Migrate of a migrated DB succeeds', Msg = '', Msg);

    Conn:= OpenRaw(DbPath);
    try
      Msg:= RaisedBy(Conn, 'ALTER TABLE symbols ADD COLUMN heritage TEXT');
      Check('T2 duplicate column is tolerated', Msg = '', Msg);

      Msg:= RaisedBy(Conn, 'CREATE TABLE IF NOT EXISTS f2_broken (');
      Check('T3 broken DDL raises', Msg <> '');

      Msg:= RaisedBy(Conn, 'ALTER TABLE f2_no_such_table ADD COLUMN x TEXT');
      Check('T4 ALTER on a missing table raises', Msg <> '');

      Lock:= OpenRaw(DbPath);
      try
        Lock.ExecSQL('BEGIN IMMEDIATE');
        try
          Msg:= RaisedBy(Conn, 'CREATE TABLE IF NOT EXISTS f2_locked_probe (x INTEGER)');
          Check('T5 locked DB raises', Pos('locked', LowerCase(Msg)) > 0, '[' + Msg + ']');
        finally
          Lock.ExecSQL('ROLLBACK');
        end;
      finally
        Lock.Free;
      end;
    finally
      Conn.Free;
    end;

    Check('T6 nil is not a duplicate-column error', not IsDuplicateColumnError(nil));
    Msg:= 'duplicate column name: x';
    var Plain:= Exception.Create(Msg);
    try
      Check('T6 a plain Exception is not a duplicate-column error',
        not IsDuplicateColumnError(Plain));
    finally
      Plain.Free;
    end;
    // T7: simulated no-trigram sqlite3.dll.
    DbPath2:= DbPath + '.notri';
    Msg:= MigrateWith(DbPath2, True);
    Check('T7 Migrate without trigram does not raise', Msg = '', Msg);
    Conn:= OpenRaw(DbPath2);
    try
      Check('T7 string_fts_tri absent', ScalarInt(Conn, SQL_HAS_TRI) = 0);
      Check('T7 string_fts present', ScalarInt(Conn,
        'SELECT COUNT(*) FROM sqlite_master WHERE name = ''string_fts''') = 1);
      Check('T7 no trigger references string_fts_tri', ScalarInt(Conn, SQL_TRI_TRIGGERS) = 0);
      Check('T7 sync triggers still present', ScalarInt(Conn,
        'SELECT COUNT(*) FROM sqlite_master WHERE type = ''trigger'' AND name LIKE ''string_literals%''') = 3);
      Msg:= '';
      try
        Conn.ExecSQL(SQL_INSERT_LIT);
      except on E: Exception do  // dl:ok try-except-swallowed@714b -- REVIEWED 2026-10-25: the message IS the result
        Msg:= E.Message;
      end;
      Check('T7 string_literals insert succeeds', Msg = '', Msg);
    finally
      Conn.Free;
    end;

    // T9: upgrade -- migrated without trigram, then with it.
    Msg:= MigrateWith(DbPath2, False);
    Check('T9 re-Migrate with trigram does not raise', Msg = '', Msg);
    Conn:= OpenRaw(DbPath2);
    try
      Check('T9 string_fts_tri now exists', ScalarInt(Conn, SQL_HAS_TRI) = 1);
      Check('T9 triggers now reference string_fts_tri', ScalarInt(Conn, SQL_TRI_TRIGGERS) = 3);
      Check('T9 pre-existing literal back-filled into the trigram index',
        ScalarInt(Conn, 'SELECT COUNT(*) FROM string_fts_tri WHERE string_fts_tri MATCH ''"llo wor"''') = 1);
    finally
      Conn.Free;
    end;

    // T8: positive control -- trigram available on a fresh DB.
    DeleteFile(DbPath2); { returns False when absent -- scratch only }
    DeleteFile(DbPath2 + '-wal'); { returns False when absent -- scratch only }
    DeleteFile(DbPath2 + '-shm'); { returns False when absent -- scratch only }
    Msg:= MigrateWith(DbPath2, False);
    Check('T8 Migrate with trigram does not raise', Msg = '', Msg);
    Conn:= OpenRaw(DbPath2);
    try
      Check('T8 string_fts_tri exists', ScalarInt(Conn, SQL_HAS_TRI) = 1);
      Check('T8 triggers reference string_fts_tri', ScalarInt(Conn, SQL_TRI_TRIGGERS) = 3);
    finally
      Conn.Free;
    end;
  finally
    DeleteFile(DbPath); { returns False when absent -- scratch only }
    DeleteFile(DbPath + '-wal'); { returns False when absent -- scratch only }
    DeleteFile(DbPath + '-shm'); { returns False when absent -- scratch only }
    DeleteFile(DbPath + '.notri'); { returns False when absent -- scratch only }
    DeleteFile(DbPath + '.notri-wal'); { returns False when absent -- scratch only }
    DeleteFile(DbPath + '.notri-shm'); { returns False when absent -- scratch only }
  end;

  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then ExitCode:= 1;
end.
