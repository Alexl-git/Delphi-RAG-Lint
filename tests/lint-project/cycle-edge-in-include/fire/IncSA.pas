unit IncSA;

interface

{$I IncSShared.inc}

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