unit UApp1;

interface

procedure RunApp1;

implementation

uses
  UShared;

procedure RunApp1;
var
  W: TChunkWriter;
begin
  W:= TChunkWriter.Create;
  try
    W.Flush;
  finally
    W.Free;
  end;
  if UsedByApp1 > 0 then RunApp1;
end;

end.
