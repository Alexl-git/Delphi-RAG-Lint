unit char_count_as_bytes_clean;

interface

implementation

uses System.Classes, System.SysUtils;

procedure Clean(const S: string; const A: AnsiString; AStream: TStream; Buf: Pointer; const Arr: TBytes);
var
  P: PByte;
begin
  Move(Pointer(S)^, Buf^, Length(S) * SizeOf(Char));
  Move(Pointer(A)^, Buf^, Length(A));
  Move(S[1], Buf^, Length(S));
  Move(Pointer(Arr)^, Buf^, Length(Arr));
  AStream.WriteBuffer(Pointer(S)^, ByteLength(S));
  GetMem(P, Length(S) + 1);
  Move(Buf^, P^, Length(S));
end;

end.
