unit uE;

{ The movable entry is the LAST one of a multi-line interface uses clause:
  the fix rewrites the line above (`uC,` -> `uC;`) -- engine dogfood 2026-10-27
  added uB to the implementation uses but left it in the interface (E2004). }

interface

uses
  uC,
  uB;

type
  TE = class
    FC: TC;
  end;

implementation

uses
  uD;

procedure DoE;
begin
  BProc;
end;

end.