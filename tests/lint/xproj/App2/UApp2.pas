unit UApp2;

interface

procedure RunApp2;

implementation

uses
  UShared;

procedure RunApp2;
var
  W: TChunkWriter;
begin
  W:= TChunkWriter.Create;
  try
    W.WriteChunk(UsedOnlyByApp2);
  finally
    W.Free;
  end;
end;

end.
