unit uG;

{ Leading-comma layout: uB is a MIDDLE interface entry; there is no
  implementation uses, so one is created. }

interface

uses
  uC
  , uK
  ;

type
  TG = class
    FC: TC;
    FK: TK;
  end;

implementation

uses
  uB;

procedure DoG;
begin
  BProc;
end;

end.
