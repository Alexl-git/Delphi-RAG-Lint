unit varparam;

interface

type
  TBox = class
  public
    Count: Integer;
    Plain: Integer;
  end;

implementation

procedure Bump(var X: Integer);
begin
  Inc(X);
end;

procedure Run(B: TBox);
begin
  Bump(B.Count);
end;

end.