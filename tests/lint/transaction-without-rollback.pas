unit TransactionWithoutRollback;

interface

implementation

uses
  FireDAC.Comp.Client;

procedure BadNoRollback(Conn: TFDConnection; Q: TFDQuery);
begin
  Conn.StartTransaction;
  Q.ExecSQL;
  Conn.Commit;
end;

procedure BadTryExceptNoRollback(Conn: TFDConnection; Q: TFDQuery);
begin
  Conn.StartTransaction;
  try
    Q.ExecSQL;
    Conn.Commit;
  except
    on E: Exception do
      Log(E.Message);
  end;
end;

procedure BadRollbackOnOtherConn(Conn, Other: TFDConnection; Q: TFDQuery);
begin
  Conn.StartTransaction;
  try
    Q.ExecSQL;
    Conn.Commit;
  except
    Other.Rollback;
    raise;
  end;
end;

procedure GoodExcept(Conn: TFDConnection; Q: TFDQuery);
begin
  Conn.StartTransaction;
  try
    Q.ExecSQL;
    Conn.Commit;
  except
    Conn.Rollback;
    raise;
  end;
end;

procedure GoodFinally(Conn: TFDConnection; Q: TFDQuery);
var
  Ok: Boolean;
begin
  Ok := False;
  Conn.StartTransaction;
  try
    Q.ExecSQL;
    Conn.Commit;
    Ok := True;
  finally
    if not Ok then
      Conn.Rollback;
  end;
end;

procedure GoodTransactionObject(Conn: TFDConnection; Q: TFDQuery);
begin
  Conn.Transaction.StartTransaction;
  try
    Q.ExecSQL;
    Conn.Transaction.Commit;
  except
    Conn.Transaction.Rollback;
    raise;
  end;
end;

procedure GoodStartOnly(Conn: TFDConnection);
begin
  // the matching Commit / Rollback live in the caller
  Conn.StartTransaction;
end;

end.
