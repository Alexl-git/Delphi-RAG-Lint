unit R1Title.Untangle;

// E18 T5 fixture: an EXISTING leaf of R1Title that no unit of the cycle
// uses -- the routine-call inversion extends it instead of creating one.

interface

type
  /// <summary>Unrelated declaration the leaf already holds.</summary>
  TR1TitleStyle = (tsPlain, tsBold);

implementation

end.