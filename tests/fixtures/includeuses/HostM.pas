unit HostM;

// N-06 T7 fixture: the interface uses clause lives in HostM.Intf.inc and names
// Leaf, which only the implementation needs -- a uses-fix MOVE candidate that
// uses-fix must SKIP (it never edits an include).

interface

{$I HostM.Intf.inc}

/// <summary>Reads Leaf from the implementation only.</summary>
function ValueM: Integer;

implementation

function ValueM: Integer;
begin
  Result:= LeafValue + 3;
end;

end.