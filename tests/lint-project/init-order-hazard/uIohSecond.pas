unit uIohSecond;

interface

var
  GSecond: Integer;

function SecondValue: Integer;

implementation

uses
  uIohFirst, uIohPlain;

function ViaHop: Integer;
begin
  Result:= FirstValue;
end;

function SecondValue: Integer;
begin
  Result:= GSecond;
end;

initialization
  GSecond:= ViaHop; // TRIGGER-CALL
  GSecond:= GSecond + uIohFirst.GDirect; // TRIGGER-DIRECT
  GSecond:= GSecond + PlainValue; // CONTROL-NOCYCLE
  GSecond:= GSecond + FirstRec; // TRIGGER-NEW
  FirstLazy; // CONTROL-LAZY
  GSecond:= GSecond + FirstNeverSet; // CONTROL-UNSET
  GSecond:= GSecond + FirstShadow; // CONTROL-SHADOW
end.