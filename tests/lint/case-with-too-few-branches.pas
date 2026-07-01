unit casefew;
interface
implementation
procedure P(X: Integer);
begin
  case X of
    1: Writeln('one');
  end;
  case X of
    1: Writeln('a');
    2: Writeln('b');
    3: Writeln('c');
  end;
end;
end.
