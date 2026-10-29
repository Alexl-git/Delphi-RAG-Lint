unit basic;

interface

implementation

uses
  System.SysUtils;

procedure DoIt;
begin
end;

procedure P;
begin
  try
    DoIt;
  except
    on E: Exception do raise;
  end;
end;

end.
