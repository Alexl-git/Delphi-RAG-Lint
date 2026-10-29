unit basic;

interface

procedure P(X: Integer);

implementation

procedure P(X: Integer);
begin
  case X of
    1: Writeln('one');
  end;
  case X + 1 of
    2: Writeln('two');
  else
    Writeln('other');
    Writeln('more');
  end;
  case X of 3: Writeln('three'); end;
end;

end.
