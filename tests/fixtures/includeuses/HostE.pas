unit HostE;

// N-06 T7 fixture: an enum whose unit takes its implementation uses clause
// from HostE.Impl.inc. create-enum-helper must not edit the include.

interface

type
  TColorE = (ceRed, ceBlue);

implementation

{$I HostE.Impl.inc}

/// <summary>Uses Leaf so the clause is not dead.</summary>
function ShadeE: Integer;
begin
  Result:= LeafValue;
end;

end.