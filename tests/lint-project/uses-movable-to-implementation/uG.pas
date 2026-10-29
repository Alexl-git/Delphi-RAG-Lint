unit uG;

{ Leading-comma layout: uB is a MIDDLE interface entry; there is no
  implementation uses, so one is created. }

interface

uses
  uC
  , uB
  , uK
  ;

type
  TG = class
    FC: TC;
    FK: TK;
  end;

implementation

procedure DoG;
begin
  BProc;
end;

end.
