unit IncSB;

interface

{$I IncSShared.inc}

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