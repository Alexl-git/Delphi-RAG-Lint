unit ResB;

{ Fixture: the other unit that declares TPair; listed after ResA, so a bare TPair in ResUse is this one. }

interface

type
  TPair = record
    Kind: Integer;
    Spare: Integer;
    OnlyB: Integer;
  end;

implementation

end.