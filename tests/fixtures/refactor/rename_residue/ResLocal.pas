unit ResLocal;

{ Fixture: uses ResA and declares its own TPair, which shadows the used one. }

interface

uses
  ResA;

type
  TPair = record
    Kind: Integer;
  end;

procedure RunLocal;

implementation

procedure RunLocal;
var
  Own: TPair;
  Used: ResA.TPair;
begin
  Own.Kind:= 8;
  Used.Kind:= 9;
  WriteLn('local ', Own.Kind, ' ', Used.Kind);
end;

end.