unit enumcase;
interface
type
  TColorKind = (ckRed, ckGreen, ckBlue);
implementation
procedure P(C: TColorKind);
begin
  case C of
    ckRed: Writeln('r');
    ckGreen: Writeln('g');
  end;
  case C of
    ckRed: Writeln('r');
    ckGreen: Writeln('g');
    ckBlue: Writeln('b');
  end;
  case C of
    ckRed: Writeln('r');
  else
    Writeln('other');
  end;
end;
end.
