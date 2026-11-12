unit IncSB;

interface

type
  TIncShared = record
    N: Integer;
  end;

procedure DoIncSB;

implementation

uses
  IncSA;

procedure DoIncSB;
var
  V: TIncShared;
begin
  V.N := 1;
  DoIncSA;
end;

end.