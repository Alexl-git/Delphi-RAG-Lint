unit keep;
interface
implementation
procedure P(X: Integer; B: Boolean);
begin
  case X of
    1, 2: Writeln('one or two');
  end;
  case X of
    1..3: Writeln('range');
  end;
  case X of
    4: if B then Writeln('dangling');
  else
    Writeln('else');
  end;
end;
end.
