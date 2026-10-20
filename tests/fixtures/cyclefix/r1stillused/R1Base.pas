unit R1Base;

// E18 T5 fix round 2 fixture (edge-still-used): a base class OUTSIDE the cycle
// whose class method R1Note has the same name as a routine of R1Title.

interface

type
  /// <summary>Base of TR1Form; not in the cycle.</summary>
  TR1Base = class
  public
    /// <summary>Prints a note.</summary>
    /// <param name="pText">The note.</param>
    class procedure R1Note(const pText: string);
  end;

implementation

class procedure TR1Base.R1Note(const pText: string);
begin
  Writeln('[base] ', pText);
end;

end.