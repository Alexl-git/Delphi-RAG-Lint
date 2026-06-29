unit callers;

interface

implementation

uses System.Classes, helpers;

procedure LeaksThroughNonOwning;
var o: TStringList;
begin
  o := TStringList.Create;
  UseButDontFree(o);
end;

procedure SafeThroughOwning;
var o: TStringList;
begin
  o := TStringList.Create;
  TakeAndFree(o);
end;

end.
