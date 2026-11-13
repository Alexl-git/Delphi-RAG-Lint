unit IncCA;

interface

{$I IncCTypes.inc}

procedure DoIncCA;

implementation

uses
  {$I IncCLeafUses.inc}
  IncCB;

procedure DoIncCA;
begin
  DoIncCB;
  IncLeafCall;
end;

end.