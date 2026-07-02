unit split;

interface

type
  TSplit = class
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

procedure TSplit.UseA;
begin
  FA:= 1;
end;

procedure TSplit.UseAgainA;
begin
  FA:= FA + 1;
end;

procedure TSplit.UseB;
begin
  FB:= 2;
end;

procedure TSplit.UseAgainB;
begin
  FB:= FB + 1;
end;

end.
