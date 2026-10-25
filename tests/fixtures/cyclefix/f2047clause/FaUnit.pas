unit FaUnit;

// W6-cyc5 A4 fixture: FaUnit and FbUnit use each other in the INTERFACE (F2047: dcc rejects the
// project until the cycle is cut).

interface

uses
  FbUnit;

const
  FaBase = 10;
  FaTotal = FbBase + 1;

implementation

end.