unit uF;

{ Leading-comma layout: uB is the FIRST interface entry (the next entry is
  promoted); the implementation uses is leading-comma with the ; on its own
  line, so uB is added as `  , uB` above the ;. }

interface

uses
  uB
  , uC
  ;

type
  TF = class
    FC: TC;
  end;

implementation

uses
  uK
  , uD
  ;

procedure DoF;
begin
  BProc;
  KProc;
end;

end.
