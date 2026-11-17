unit A;

interface

uses
  B;

var
  GVal: Integer;

implementation

initialization
  GVal:= 42;
  Writeln('INIT A');
end.
