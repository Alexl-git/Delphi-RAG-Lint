unit QgB;

interface

var
  /// <summary>Written by QgA, read here.</summary>
  GQgHook: Integer;

/// <summary>Prints the hook.</summary>
procedure QgBRun;

implementation

uses
  QgA;

procedure QgBRun;
begin
  Writeln('run ', GQgHook + QgAFive);
end;

end.
