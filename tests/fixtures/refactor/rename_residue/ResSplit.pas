unit ResSplit;

{ Fixture: ResA in the interface uses, ResB in the implementation uses. A bare TPair in the implementation is ResB's,
  in the interface ResA's; the resolver does not know the section of a type text, so it declines both. }

interface

uses
  ResA;

procedure RunSplit;

implementation

uses
  ResB;

procedure RunSplit;
var
  Split: TPair;
begin
  Split.Spare:= 10;
  WriteLn('split ', Split.Spare);
end;

end.