unit sample;

interface

type
  TKind = (kA, kB, kC);
  TState = (sIdle, sBusy);

  TThing = class
    FKind : TKind ;
    FState: TState;
    function Alpha: Integer;
    function Beta: Integer;
    function Gamma: Integer;
    function Delta: Integer;
  end;

implementation

function TThing.Alpha: Integer;
begin
  case FKind of
    kA: Result:= 1;
    kB: Result:= 2;
  else
    Result:= 0;
  end;
end;

function TThing.Beta: Integer;
begin
  case FKind of
    kA: Result:= 10;
    kC: Result:= 30;
  else
    Result:= 0;
  end;
end;

function TThing.Gamma: Integer;
begin
  case FKind of
    kB: Result:= 100;
    kC: Result:= 300;
  else
    Result:= 0;
  end;
end;

function TThing.Delta: Integer;
begin
  case FState of
    sIdle: Result:= 1;
    sBusy: Result:= 2;
  else
    Result:= 0;
  end;
end;

end.
