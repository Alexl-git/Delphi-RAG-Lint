unit FsB;

interface

/// <summary>Prints the value and the stop count.</summary>
procedure FsBStop;

implementation

uses
  FsA;

var
  GFsStops: Integer;

procedure FsBStop;
begin
  Inc(GFsStops);
  Writeln('stop ', GFsStops + FsAValue);
end;

end.
