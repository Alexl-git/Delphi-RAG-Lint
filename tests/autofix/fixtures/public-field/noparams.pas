unit noparams;

interface

type
  TBox = class
  public
    Count: Integer;
    procedure Reset;
  end;

implementation

procedure TBox.Reset;
begin
  Count := 0;
end;

end.
