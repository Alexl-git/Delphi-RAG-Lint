unit LargeMagicV151;

interface

type
  AnsiString1252 = type AnsiString(1252);

  TRecX = record
    Pad: array[1..28] of Byte;
    Name: array[0..259] of Char;
  end;

implementation

label
  99;

procedure P(I: Integer);
begin
  if I > 0 then
    goto 99;
99:
  case I of
    7: I := 70;
    7001: I := 1234;
  end;
end;

end.
