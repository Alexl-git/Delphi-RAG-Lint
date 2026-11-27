unit uAmbUse;

interface

uses uAmbC, uAmbD;

function Pick(M: TMode): Integer;

implementation

function Pick(M: TMode): Integer;
begin
  Result := KSame;
  if M = mdB then
    Result := KOther;  // FIRE ambiguous-unit-reference
end;

end.