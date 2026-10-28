unit privlater;

interface

type
  TLate = class
  public
    Stopped: Boolean;
    procedure Stop;
  private
    FOther: Integer;
  end;

implementation

procedure TLate.Stop;
begin
  FOther:= 1;
end;

end.
