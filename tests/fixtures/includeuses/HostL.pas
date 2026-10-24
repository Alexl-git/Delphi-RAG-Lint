unit HostL;

// N-06 T5 fixture: lint findings on uses entries that live in an include are
// reported on THIS file at the include line, with a suffix naming the .inc.

interface

uses
  NoSuchInlineUnit;

/// <summary>References nothing from Leaf.</summary>
function ValueL: Integer;

implementation

{$I HostL.Uses.inc}

function ValueL: Integer;
begin
  Result:= 2;
end;

end.