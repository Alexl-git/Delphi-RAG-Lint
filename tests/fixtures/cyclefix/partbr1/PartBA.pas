unit PartBA;

// E18 T7 fixture (Part B is R3-aware): the interface edge PartBA -> PartBB
// (TPartBKind) is cut by Part A; the implementation cycle left behind is
// PartBA -> PartBB (PartBBRun) and PartBB -> PartBA (PartBADouble, one routine
// whose signature names only Integer) -- routine-call inversion cuts it.

interface

uses
  PartBB;

/// <summary>Prints the ordinal of a kind, then runs PartBB.</summary>
/// <param name="pKind">Kind to print.</param>
procedure PartBAShow(const pKind: TPartBKind);

/// <summary>Twice pN.</summary>
/// <param name="pN">Value to double.</param>
/// <returns>pN * 2.</returns>
function PartBADouble(const pN: Integer): Integer;

implementation

procedure PartBAShow(const pKind: TPartBKind);
begin
  Writeln(Ord(pKind));
  PartBBRun;
end;

function PartBADouble(const pN: Integer): Integer;
begin
  Result := pN * 2;
end;

end.