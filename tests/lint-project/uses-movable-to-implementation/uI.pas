unit uI;

{ Leading-comma layout: uB is the LAST interface entry and holds the ;
  (the line above takes it); the implementation uses is one entry per line. }

interface

uses
  uC
  , uB;

type
  TI = class
    FC: TC;
  end;

implementation

uses
  uK;

procedure DoI;
begin
  BProc;
  KProc;
end;

end.
