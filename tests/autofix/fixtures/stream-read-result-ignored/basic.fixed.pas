unit basic;

interface

implementation

uses
  System.Classes, System.SysUtils;

procedure P(Src: TFileStream; var Buf: TBytes);
begin
  Src.ReadBuffer(Buf, 4);
  Src.WriteBuffer(Buf, 4);
end;

end.
