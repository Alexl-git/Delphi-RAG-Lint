unit basic;

interface

implementation

procedure Run;
var
  P: PByte;
  S: string;
  Buf: array[0..9] of Byte;
begin
  FillChar(P^, SizeOf(P), 0);
  Move(S[1], Buf, Length(S));
end;

end.
