unit TryExceptSwallowed;

interface

implementation

uses System.SysUtils;

procedure Bad;
begin
  try
    Writeln('x');
  except
    // swallowed -- nothing here
  end;
end;

procedure GoodReraise;
begin
  try
    Writeln('x');
  except
    raise;
  end;
end;

procedure GoodLog;
begin
  try
    Writeln('x');
  except
    on E: Exception do
      LogError(E.Message);
  end;
end;

end.
