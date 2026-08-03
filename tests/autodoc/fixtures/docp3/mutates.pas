unit mutates;

interface

procedure FillBoth(var AList: TArray<Integer>; out AReason: string; AConst: Integer);
function PureAdd(A, B: Integer): Integer;
function Driver: Integer;

implementation

procedure FillBoth(var AList: TArray<Integer>; out AReason: string; AConst: Integer);
begin
  SetLength(AList, AConst);
  AList[0] := AConst;
  AReason := 'filled';
end;

function PureAdd(A, B: Integer): Integer;
begin
  Result := A + B;
end;

// Calls the other two so each one has a CALLER fact -- without at least one
// fact the engine writes no doc block at all and every assertion about the
// block would be vacuous. Same device as harvest_text.pas / harvest_impl.pas /
// harvest_drift.pas; see harvest_drift.pas for why the parentheses matter.
function Driver: Integer;
var
  L: TArray<Integer>;
  R: string;
begin
  FillBoth(L, R, 2);
  Result := PureAdd(1, 2);
end;

end.
