unit noparams;

interface

type
  TBox = class
  private
    FCount: Integer;
  public
    property Count: Integer read FCount write FCount;
    procedure Reset;
  end;

implementation

procedure TBox.Reset;
begin
  Count := 0;
end;

end.
