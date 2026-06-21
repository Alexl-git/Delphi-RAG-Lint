unit DeepNest;

interface

implementation

procedure P(X: Integer);
begin
  if X > 0 then
    if X > 1 then
      if X > 2 then
        if X > 3 then
          if X > 4 then
            if X > 5 then
              WriteLn('deep');
end;

end.
