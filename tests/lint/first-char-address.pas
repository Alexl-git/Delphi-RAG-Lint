unit first_char_address;

interface

implementation

uses System.Classes;

procedure Hits(const AText: string; AStream: TStream);
var
  S: AnsiString;
  U: UnicodeString;
  P: PChar;
begin
  S := 'a';
  U := 'b';
  AStream.WriteBuffer(@AText[1], Length(AText) * SizeOf(Char));
  AStream.WriteBuffer(@S[1], Length(S));
  P := PChar(@U[1]);
  P := @AText[Low(AText)];
end;

end.
