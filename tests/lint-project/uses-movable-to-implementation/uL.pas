unit uL;

{ Leading-comma layout as the engine source writes it: a column-aligned dotted
  name (uM   .Sub) with a trailing comment, and a plain middle entry -- both move. }

interface

uses
  uC
  , uM   .Sub   { implementation only }
  , uB
  ;

type
  TL = class
    FC: TC;
  end;

implementation

procedure DoL;
begin
  BProc;
  MProc;
end;

end.
