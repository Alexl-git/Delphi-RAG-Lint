unit first_char_address_clean;

interface

implementation

uses System.Classes;

procedure Clean(const AText: string; AStream: TStream);
var
  SS: ShortString;
  B: array[1..4] of Byte;
  T: TBytes;
  P: Pointer;
begin
  SS := 'a';
  P := @SS[1];
  P := @B[1];
  P := @T[0];
  P := Pointer(AText);
  P := @AText[2];
  P := @Undeclared[1];
end;

end.
