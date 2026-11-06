unit uIohPlain;

{ No uses cycle: always initializes before its users. }

interface

var
  GPlain: Integer;

function PlainValue: Integer;

implementation

function PlainValue: Integer;
begin
  Result:= GPlain;
end;

initialization
  GPlain:= 1;
end.