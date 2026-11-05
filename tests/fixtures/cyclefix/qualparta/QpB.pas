unit QpB;

interface

const
  /// <summary>Upper bound of TQpSlots.</summary>
  CQpTop = 3;

/// <summary>Prints QpATwo.</summary>
procedure QpBRun;

implementation

uses
  QpA;

procedure QpBRun;
begin
  Writeln(QpATwo);
end;

end.
