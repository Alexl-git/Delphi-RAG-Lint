unit HostN;

// N-06 T7 CONTROL: HostM with the clause inlined -- uses-fix MOVES Leaf.

interface

uses
  Leaf,
  System.SysUtils;

/// <summary>Reads Leaf from the implementation only.</summary>
function ValueN: Integer;

implementation

function ValueN: Integer;
begin
  Result:= LeafValue + 4;
end;

end.