unit QpA;

interface

uses
  QpB;

type
  /// <summary>Sized by the const of QpB: the interface coupling.</summary>
  TQpSlots = array[0..CQpTop] of Integer;

/// <summary>Prints the const, qualified.</summary>
procedure QpAShow;

/// <summary>A fixed value.</summary>
/// <returns>2.</returns>
function QpATwo: Integer;

implementation

procedure QpAShow;
begin
  Writeln(QpB.CQpTop);
  QpBRun;
end;

function QpATwo: Integer;
begin
  Result:= 2;
end;

end.
