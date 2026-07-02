unit magiclit;
interface
implementation

const
  K_LIMIT = 99;

type
  TColor = (clRed, clGreen = 5, clBlue);

procedure P(A: Integer = 42);
var
  Total: Integer;
  Arr: array[0..9] of Integer;
begin
  Total := 0;
  if Total > 42 then
    Total := 1;
  case Total of
    1: Total := 1;
    99: Total := 2;
  else
    Total := -1;
  end;
  Arr[1] := 2;
end;

end.
