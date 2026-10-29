unit SwapNoTemp;

interface

implementation

procedure Bad(var A, B: Integer);
begin
  A := B;
  B := A;                                   // HIT_A: A is already overwritten, B := B
end;

procedure Good(var A, B, C: Integer);
var T: Integer;
begin
  T := A;                                   // proper swap through a temp
  A := B;
  B := T;
  A := B;
  B := C;                                   // NOT_A: different source
  A := B;
  B := A + 1;                               // NOT_B: rhs is an expression (known FP shape: intentional copy-then-derive)
  A := B;
  C := 0;
  B := A;                                   // NOT_C: not adjacent statements
end;

end.
