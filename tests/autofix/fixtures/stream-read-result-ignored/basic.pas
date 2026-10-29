unit basic;

interface

implementation

uses
  System.Classes, System.SysUtils;

procedure P(Src: TFileStream; var Buf: TBytes);
begin
  Src.Read(Buf, 4);
  Src.Write(Buf, 4);
end;

end.
