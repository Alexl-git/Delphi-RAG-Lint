unit UnsafeStringApi;

interface

implementation

uses SysUtils;

procedure Bad;
var
  Src, Dst: array[0..255] of AnsiChar;
begin
  StrCopy(Dst, Src);
  StrCat(Dst, Src);
  StrMove(Dst, Src, 10);
  StrLen(Src);
  StrPos(Src, Dst);
end;

procedure Good;
var
  S: string;
begin
  S := S + 'ok';
  Copy(S, 1, 3);
end;

end.
