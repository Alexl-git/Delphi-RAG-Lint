unit SEQ;

interface

implementation

procedure P(A, B: string);
begin
  if A = B then           // string '=' : string-equality-comparison SHOULD fire
    WriteLn('eq');
end;

end.
