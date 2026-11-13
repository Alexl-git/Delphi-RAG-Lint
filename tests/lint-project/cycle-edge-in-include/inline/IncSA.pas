unit IncSA;

interface

type
  TIncShared = record
    N: Integer;
  end;

procedure DoIncSA;

implementation

uses
  IncSB;

procedure DoIncSA;
var
  V: TIncShared;
begin
  V.N := 1;
  DoIncSB;
end;

end.