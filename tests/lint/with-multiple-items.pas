unit WithMulti;

interface

implementation

procedure P(A, B: TObject);
begin
  with A, B do
    Free;
end;

procedure Q(A: TObject);
begin
  with A do
    Free;
end;

end.
