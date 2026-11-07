unit TypeFacts;

interface

uses System.SysUtils, ExcA;

type
  ELocal = class(Exception);

procedure Stamp;

implementation

procedure Thrower;
begin
  raise ELocal.Create('x');
end;

procedure Stamp;
var
  X: Exception;
begin
  X:= nil;
  try
    Thrower;
  except
    on E: ELocal do raise E;
    on E: EDup do raise X;
    on EAbort do raise;
    on E: EConvertError do
    begin
      try
        Thrower;
      except
        raise;
      end;
    end;
    on E: EArgumentException do
    begin
      try
        raise;
      except
        on EOnlyA do ;
      end;
    end;
  else
    raise;
  end;
end;

procedure OutsideHandler(E: ELocal);
begin
  raise E;
end;

procedure RaiseLib;
begin
  raise Exception.Create('lib');
end;

end.
