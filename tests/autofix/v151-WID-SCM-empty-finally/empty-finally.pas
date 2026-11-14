unit EmptyFinallyFix;

interface

procedure Run;

implementation

procedure Run;
var
  N: Integer;
begin
  N := 0;
  try
    Inc(N);
    Inc(N);
  finally
  end;
  if N > 0 then
    try
      Inc(N);
    finally
    end;
  try
    Inc(N)
  finally
  end;
end;

end.
