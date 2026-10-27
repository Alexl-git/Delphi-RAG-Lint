unit upriv;

interface

type
  TWidget = class
  private
    FUsed: Integer;
    procedure LiveProc;
  public
    procedure Run;
  end;

implementation

procedure TWidget.LiveProc;
begin
  FUsed:= 1;
end;

procedure TWidget.Run;
begin
  LiveProc;
  if FUsed > 0 then Exit;
end;

end.