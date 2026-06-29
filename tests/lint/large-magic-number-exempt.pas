unit LargeMagicNumberExempt;

interface

implementation

procedure P;
var
  X: Integer;
begin
  { Powers of two and common constants -- must NOT fire. }
  X := 0;
  X := 1;
  X := 2;
  X := 4;
  X := 8;
  X := 16;
  X := 32;
  X := 64;
  X := 128;
  X := 256;
  X := 512;
  X := 1024;
  X := 2048;
  X := 4096;
  X := 8192;
  X := 65536;
  X := -1;
  { Hex bitmasks -- must NOT fire. }
  X := $FF;
  X := $FFFF;
  { Genuinely arbitrary large constant -- MUST fire. }
  X := 86400;
end;

end.
