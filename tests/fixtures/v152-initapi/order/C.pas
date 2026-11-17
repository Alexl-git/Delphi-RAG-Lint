unit C;

interface

implementation

uses
  A;

procedure ShowVal;
begin
  Writeln('INIT C ', GVal);
end;

initialization
  ShowVal;
end.
