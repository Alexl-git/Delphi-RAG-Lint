unit uEcUse;

interface

uses uEcLib, uEcLib2;

type
  TOwnKind = (okA, okB);

function Decode(pI: Integer; pO: TObject): Integer;

implementation

function Decode(pI: Integer; pO: TObject): Integer;
var
  K: TOwnKind;
  L: TLibKind;
  O: TObject;
  C: TClashE;
begin
  K := TOwnKind(pI); // EC-OWN
  L := TLibKind(pI); // EC-USED
  O := TLibClass(pO); // NEG-CLASS
  L := uEcLib.TLibKind(pI); // NEG-QUALIFIED
  C := TClashE(pI); // NEG-AMBIGUOUS
  if Assigned(O) and (C = ceX) then Result := Ord(K) + Ord(L) else Result := 0;
end;

end.
