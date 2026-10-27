unit basic;

interface

implementation

procedure P(Src: TFileStream; var Buf: TBytes);
begin
  Src.Read(Buf, 4);
  Src.Write(Buf, 4);
end;

end.
