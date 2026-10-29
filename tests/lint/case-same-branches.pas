unit CaseSameBranches;

interface

implementation

procedure P(X: Integer; var R: Integer);
begin
  case X of
    1: R:= 10;
    2: R:= 20;
    3: R:= 10;
  end;
  case X of
    1, 2: R:= 5;
    3: R:= 6;
  end;
  case X of
    1: begin R:= 1; Inc(R); end;
    2: begin R:= 1;  Inc(R); end;
  end;
  case X of
    1: ;
    2: ;
  end;
  case X of
    1: R:= 1;
  else
    R:= 2;
  end;
end;

end.
