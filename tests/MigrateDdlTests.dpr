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
  DRagLint.Core.Model,
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

{ T12: writes three data_flows rows for a method of a class through the store and
  reads them back through every reader; '' when every expectation holds, else the
  first broken one. }
function RoundTripDataFlows(const pPath: string): string;
var
  S      : ISymbolStore;
  Tok    : TFileTxToken;
  Cls, M : TSymbol;
  ClsId  : Int64;
  MId    : Int64;
  Rows   : TArray<TDataFlowRow>;
  Got    : TArray<TDataFlowRow>;

  function Row(const pDst: string; pLine, pCol, pIdx: Integer; const pName, pSrc: string;
    pSrcIdx: Integer): TDataFlowRow;
  begin
    Result:= Default(TDataFlowRow);
    Result.FileId     := 999; { must be IGNORED: the token supplies file_id }
    Result.SymbolId   := MId;
    Result.OwnerId    := ClsId;
    Result.DstKind    := pDst;
    Result.DstLine    := pLine;
    Result.DstCol     := pCol;
    Result.DstIndex   := pIdx;
    Result.DstName    := pName;
    Result.DstReceiver:= if pDst = DF_DST_ARG then 'Q' else '';
    Result.SrcKind    := pSrc;
    Result.SrcIndex   := pSrcIdx;
    Result.SrcName    := 'A';
    Result.ViaLocal   := pDst = DF_DST_FIELD;
    Result.Cond       := pDst = DF_DST_GLOBAL;
  end;

begin
  Result:= '';
  S:= TSQLiteSymbolStore.Create(pPath);
  S.Migrate;
  if not S.HasDataFlows then Exit('HasDataFlows False after Migrate');
  Tok:= S.OpenFileTx('C:\fx\uT.pas', 1, 'sha', 'pascal');
  Cls:= Default(TSymbol);
  Cls.ParentId     := -1;
  Cls.Kind         := skClass;
  Cls.Name         := 'TFoo';
  Cls.QualifiedName:= 'uT.TFoo';
  ClsId:= S.UpsertSymbol(Tok, Cls);
  M:= Default(TSymbol);
  M.ParentId     := ClsId;
  M.Kind         := skMethod;
  M.Name         := 'Run';
  M.QualifiedName:= 'uT.TFoo.Run';
  MId:= S.UpsertSymbol(Tok, M);
  Rows:= [Row(DF_DST_ARG, 10, 3, 0, 'ExecSQL', DF_SRC_PARAM, 0),
          Row(DF_DST_FIELD, 11, 3, -1, 'FSql', DF_SRC_PARAM, 0),
          Row(DF_DST_GLOBAL, 12, 3, -1, 'GText', DF_SRC_FIELD, -1)];
  S.PutDataFlows(Tok, Rows);
  S.CommitFileTx(Tok);

  Got:= S.GetDataFlowsAt(Tok.FileId, 10, 3, '');
  if Length(Got) <> 1 then Exit(Format('GetDataFlowsAt: %d rows, want 1', [Length(Got)]));
  if Got[0].FileId <> Tok.FileId then Exit('GetDataFlowsAt: file_id not taken from the token');
  if (Got[0].DstName <> 'ExecSQL') or (Got[0].DstReceiver <> 'Q') or (Got[0].SrcKind <> DF_SRC_PARAM) or
     (Got[0].SymbolId <> MId) or (Got[0].OwnerId <> ClsId) then Exit('GetDataFlowsAt: columns do not round-trip');
  if Length(S.GetDataFlowsAt(Tok.FileId, 10, 3, DF_DST_WRITE)) <> 0 then Exit('GetDataFlowsAt: kind filter ignored');
  if Length(S.GetDataFlowsOf(MId, '')) <> 3 then Exit('GetDataFlowsOf(all) <> 3');
  Got:= S.GetDataFlowsOf(MId, DF_DST_FIELD);
  if (Length(Got) <> 1) or not Got[0].ViaLocal or Got[0].Cond then Exit('GetDataFlowsOf(field) / via_local');
  if Length(S.GetFieldWriters([ClsId], 'fsql')) <> 1 then Exit('GetFieldWriters: NOCASE match failed');
  if Length(S.GetFieldWriters([ClsId + 1000], 'FSql')) <> 0 then Exit('GetFieldWriters: owner filter ignored');
  if Length(S.GetFieldWriters([], 'FSql')) <> 0 then Exit('GetFieldWriters: empty owners must return nothing');
  Got:= S.GetGlobalWriters('GTEXT', 0);
  if (Length(Got) <> 1) or not Got[0].Cond then Exit('GetGlobalWriters(any file) / cond');
  if Length(S.GetGlobalWriters('GText', Tok.FileId + 1000)) <> 0 then Exit('GetGlobalWriters: file filter ignored');
  S:= nil;
end;

const
  SQL_HAS_TRI ='SELECT COUNT(*) FROM sqlite_master WHERE name = ''string_fts_tri''';
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

      // T10 (2026-10-26, polymorphic form launches): Migrate creates the two
      // derived dispatch tables, additively, with their FK-child indexes.
      Check('T10 dispatch_edges created', ScalarInt(Conn,
        'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name = ''dispatch_edges''') = 1);
      Check('T10 classref_args created', ScalarInt(Conn,
        'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name = ''classref_args''') = 1);
      Check('T10 three dispatch indexes created', ScalarInt(Conn,
        'SELECT COUNT(*) FROM sqlite_master WHERE type = ''index'' AND name IN ' +
        '(''idx_dispatch_edges_impl'', ''idx_classref_args_class'', ''idx_classref_args_param'')') = 3);

      // T11 (2026-10-27, taint T0): Migrate creates data_flows additively, with the
      // three indexes whose LEADING columns cover both FK children (file_id, symbol_id).
      Check('T11 data_flows created', ScalarInt(Conn,
        'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name = ''data_flows''') = 1);
      Check('T11 three data_flows indexes created', ScalarInt(Conn,
        'SELECT COUNT(*) FROM sqlite_master WHERE type = ''index'' AND name IN ' +
        '(''idx_data_flows_dst'', ''idx_data_flows_sym'', ''idx_data_flows_name'')') = 3);

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

    // T12 (2026-10-27, taint T0): PutDataFlows -> the four readers, round trip on a
    // migrated store with FK enforcement ON. The file id comes from the token, not the row.
    Msg:= RoundTripDataFlows(DbPath2);
    Check('T12 data_flows round trip', Msg = '', Msg);
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
