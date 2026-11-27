unit uNarrow;

interface

uses uSrc;

procedure Run(ABag: TBag);

implementation

const
  KSmall = 5;

procedure Run(ABag: TBag);
var
  I64: Int64;
  Int: Integer;
  Small: Byte;
  Wide: Int64;
begin
  I64 := 7;
  Int := I64;
  Small := Int;
  Int := Total;
  Int := ABag.Big;
  Int := Integer(I64);
  Int := KSmall;
  Int := I64 and $FF;
  Wide := Int;
  Int := Int;
  Small := Small;
end;

end.