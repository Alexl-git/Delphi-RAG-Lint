unit uH;

{ Leading-comma layout: uB is the LAST interface entry, the ; on its own line;
  the implementation uses ends `  , uD;`, so uB goes on a new `  , uB;` line. }

interface

uses
  uC
  ;

type
  TH = class
    FC: TC;
  end;

implementation

uses
  uK
  , uD
  , uB;

procedure DoH;
begin
  BProc;
  KProc;
end;

end.
