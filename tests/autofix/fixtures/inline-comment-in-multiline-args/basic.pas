unit basic;

interface

implementation

procedure Foo(A, B, C: Integer);
begin
end;

procedure Q;
begin
  Foo(1,
    2, // the second
    3);
end;
end.
