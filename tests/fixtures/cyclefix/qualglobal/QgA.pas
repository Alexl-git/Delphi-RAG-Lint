unit QgA;

{ Every fact shown here comes from QgB. That separation is deliberate: a comment is no use. }

interface


/// <summary>Sets the hook through its qualified name and runs QgBRun.</summary>
procedure QgAShow;

/// <summary>A fixed value; QgB reads it without parentheses, so the edge QgB to QgA cannot be cut.</summary>
/// <returns>5.</returns>
function QgAFive: Integer;

implementation

uses
  QgB;

procedure QgAShow;
begin
  QgB.GQgHook:= 7;
  Writeln('QgB.GQgHook=', QgB.GQgHook);  // QgB.GQgHook in a comment stays
  QgBRun;
end;

function QgAFive: Integer;
begin
  Result:= 5;
end;

end.
