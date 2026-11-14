unit char_count_as_bytes;

interface

implementation

uses Winapi.Windows, System.Classes, System.SysUtils;

procedure Hits(const S, T: string; AStream: TStream; Buf: Pointer; H: THandle);
var
  P, Q: PChar;
  W: DWORD;
begin
  Move(Pointer(S)^, Buf^, Length(S));
  AStream.WriteBuffer(PChar(S)^, Length(S));
  AStream.ReadBuffer(Pointer(S)^, Length(S) + 1);
  GetMem(P, Length(S) + 1);
  if CompareMem(Pointer(S), Pointer(T), Length(S)) then
    FillChar(PChar(S)^, Length(S), 0);
  WriteFile(H, PChar(S)^, Length(S), W, nil);
  Q := P;
  Move(P^, Q^, StrLen(P));
end;

end.
