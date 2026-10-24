unit HostI;

// N-06 fixture: an INTERFACE-section include carrying a uses clause, and an
// include inside an inactive branch whose uses clause must NOT be extracted.

interface

{$I HostI.Intf.inc}

{$IFDEF NEVER_DEFINED}
{$I HostI.Dead.inc}
{$ENDIF}

/// <summary>Reads Leaf.</summary>
function ValueI: Integer;

implementation

function ValueI: Integer;
begin
  Result:= LeafValue;
end;

end.