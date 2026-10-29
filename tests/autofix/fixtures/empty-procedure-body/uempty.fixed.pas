unit uempty;

interface

type
  TBox = class
  private
    FCount: Integer;
  public
    procedure Run;
  end;

implementation

procedure TBox.Run;
begin
  FCount:= 1;
end;

end.
