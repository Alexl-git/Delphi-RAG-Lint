unit uMain;

interface

uses
  uPlib,
  uQcoll,
  uRcoll;

procedure MainProc;

implementation

procedure Helper(V: Integer; X: Integer);
begin
  if V > X then Exit;
end;

procedure MainProc;
begin
  PProc;
  Helper(1, 2);
end;

end.
