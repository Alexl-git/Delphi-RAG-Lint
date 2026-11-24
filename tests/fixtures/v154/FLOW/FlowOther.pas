unit FlowOther;

interface

type
  TNotify = procedure(var A: Integer) of object;
  TEnum = function(A: Integer): Boolean;
  ICheck = interface
    function Allowed(A: Integer): Boolean;
    procedure Adjust(var A: Integer);
  end;

procedure Exchange(var A, B: Integer);
procedure RunEnum(AFunc: TEnum);

implementation

procedure Exchange(var A, B: Integer);
var
  T: Integer;
begin
  T := A;
  A := B;
  B := T;
end;

procedure RunEnum(AFunc: TEnum);
begin
  AFunc(1);
end;

end.