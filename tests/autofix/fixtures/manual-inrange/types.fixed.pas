unit types;

interface

implementation

uses
  System.Math,
  System.SysUtils;

type
  TColor = (cRed, cGreen, cBlue);

function PInt(X, A, B: Integer): Boolean;
begin
  Result := InRange(X, A, B);
end;

function PChar(C: Char): Boolean;
begin
  Result := (C >= 'a') and (C <= 'z');
end;

function PEnum(E: TColor): Boolean;
begin
  Result := (E >= cRed) and (E <= cGreen);
end;

end.