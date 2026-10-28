unit privlater;

interface

type
  TLate = class
  private
    FStopped: Boolean;
  public
    property Stopped: Boolean read FStopped write FStopped;
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
