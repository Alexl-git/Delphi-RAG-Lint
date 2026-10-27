unit largestack;
interface
implementation

var
  GlobalBuf: array[0..99999] of Integer;

procedure Big;
var
  Buf: array[0..99999] of Integer;
  Grid: array[0..299, 0..299] of Integer;
  Small: array[0..99] of Integer;
  Edge: array[0..16383] of Integer;
  Name: string[255];
  Huge: string[65535];
begin
  Buf[0] := 1;
end;

procedure Inl;
begin
  var Local: array[0..99999] of Byte;
  Local[0] := 1;
end;

end.
