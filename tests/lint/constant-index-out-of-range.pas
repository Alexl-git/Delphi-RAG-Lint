unit constant_index_out_of_range;

interface

type
  TBox = class
  private
    FCells: array[0..9] of Integer;
  public
    procedure Touch;
  end;

implementation

const
  Names: array[0..1] of string = ('a', 'b');

procedure LocalArray;
var
  A: array[1..3] of Integer;
begin
  A[0] := 1;
  A[4] := 1;
  A[3] := 1;
  A[1] := 1;
end;

procedure NegativeBound;
var
  A: array[-2..2] of Integer;
begin
  A[-3] := 1;
  A[-2] := 1;
end;

procedure StringZero(S: string);
var
  T: UnicodeString;
  C: Char;
begin
  C := S[0];
  C := T[0];
  C := S[1];
end;

procedure ShortStringZero;
var
  S: string[20];
  B: Byte;
begin
  B := Byte(S[0]);
end;

procedure DynamicArray;
var
  D: array of Integer;
begin
  SetLength(D, 3);
  D[0] := 1;
  D[7] := 1;
end;

procedure ConstArray;
var
  X: string;
begin
  X := Names[2];
  X := Names[1];
end;

procedure TBox.Touch;
begin
  FCells[10] := 1;
  FCells[9] := 1;
end;

procedure InlineShadow;
begin
  var FCells := LoadCells;
  FCells[20] := 1;
end;
end.
