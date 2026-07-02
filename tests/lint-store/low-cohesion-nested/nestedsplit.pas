unit nestedsplit;

interface

type
  TNestedSplit = class
  private
    FA: Integer;
    FB: Integer;
  public
    procedure UseA;
    procedure UseAgainA;
    procedure UseB;
    procedure UseAgainB;
  end;

implementation

procedure TNestedSplit.UseA;
begin
  FA:= 1;
end;

procedure TNestedSplit.UseAgainA;

  procedure Nested;
  begin
    FB:= 99;
  end;

begin
  FA:= FA + 1;
end;

procedure TNestedSplit.UseB;
begin
  FB:= 2;
end;

procedure TNestedSplit.UseAgainB;
begin
  FB:= FB + 1;
end;

end.
