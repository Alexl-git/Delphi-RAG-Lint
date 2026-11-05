unit FsA;

interface


/// <summary>Calls FsBStop.</summary>
procedure FsAShutdown;

/// <summary>A fixed value.</summary>
/// <returns>7.</returns>
function FsAValue: Integer;

implementation

uses
  FsB;

procedure FsAShutdown;
begin
  FsBStop;
end;

function FsAValue: Integer;
begin
  Result:= 7;
end;

initialization
  Writeln('init a');

finalization
  FsAShutdown;

end.
