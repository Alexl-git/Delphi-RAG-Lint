unit StreamRead;

interface

uses
  System.Classes;

implementation

procedure Bad(pStream: TStream; pFile: TFileStream);
var
  Buf: array[0..3] of Byte;
  Mem: TMemoryStream;
  N: Integer;
begin
  pStream.Read(Buf, 4);
  pFile.Write(Buf, 4);
  Mem := TMemoryStream.Create;
  Mem.Read(Buf, 4);
  N := pStream.Read(Buf, 4);
  if pStream.Read(Buf, 4) <> 4 then N := 0;
  pStream.ReadBuffer(Buf, 4);
  pStream.WriteBuffer(Buf, 4);
  pStream.Read(Buf);
  Mem.Free;
end;

end.
