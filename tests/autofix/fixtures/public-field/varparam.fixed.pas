unit varparam;

interface

type
  TBox = class
  private
    FPlain: Integer;
  public
    Count: Integer;
    property Plain: Integer read FPlain write FPlain;
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