unit QpC;

interface

/// <summary>Prints the const, qualified, from outside the cycle.</summary>
procedure QpCShow;

implementation

uses
  QpB;

procedure QpCShow;
begin
  Writeln(QpB.CQpTop + 1);
end;

end.
