unit OverflowWiden;

interface

implementation

procedure Bad;
var
  A, B: Integer;
  C: Cardinal;
  W: Word;
  I64: Int64;
  D: Double;
begin
  I64 := A * B;
  I64 := C * C;
  D := A * W;
  I64 := A shl B;
end;

procedure Good;
var
  A, B: Integer;
  I64: Int64;
  Small: Integer;
begin
  I64 := Int64(A) * B;
  I64 := A + B;
  Small := A * B;
  I64 := A * 1000;
  I64 := Int64(A) * Int64(B);
end;

type
  TBox = class
    FA, FB: Integer;
    FTotal: Int64;
    procedure Run;
  end;

procedure TBox.Run;
begin
  { Known FP shape: fields have no visible declaration in the routine, so
    #declared-type? stays silent (no guess). }
  FTotal := FA * FB;
end;

end.
