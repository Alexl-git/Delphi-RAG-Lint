unit NestTry;

interface

procedure TwoFinally(A: Integer);
procedure TwoExcept(A: Integer);

implementation

{ Y3: try..finally (resource protection) is not a nesting level. 4 control levels. }
procedure TwoFinally(A: Integer);
var
  X: Integer;
begin
  try
    try
      while A > 0 do
        if A > 1 then
          if A > 2 then
            if A > 3 then
              X:= 1;
    finally
      X:= 0;
    end;
  finally
    X:= 2;
  end;
end;

{ Positive control: try..except still counts -- 2 + 4 = 6. }
procedure TwoExcept(A: Integer);
var
  X: Integer;
begin
  try
    try
      while A > 0 do
        if A > 1 then
          if A > 2 then
            if A > 3 then
              X:= 1;
    except
      X:= 0;
    end;
  except
    X:= 2;
  end;
end;

end.