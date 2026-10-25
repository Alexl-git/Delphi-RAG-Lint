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

var
  DbPath, Msg: string;
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
  finally
    DeleteFile(DbPath); { returns False when absent -- scratch only }
    DeleteFile(DbPath + '-wal'); { returns False when absent -- scratch only }
    DeleteFile(DbPath + '-shm'); { returns False when absent -- scratch only }
  end;

  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then ExitCode:= 1;
end.
