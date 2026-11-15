unit EventCallWithoutAssigned;

interface

type
  TZaehler = class
  private
    FWert: Integer;
    FOnChange: TNotifyEvent;
    FOnDone: TNotifyEvent;
  public
    procedure Erhoehen;
    procedure Fertig;
    procedure Sicher;
  end;

implementation

procedure TZaehler.Erhoehen;
begin
  Inc(FWert);
  FOnChange(Self);
end;

procedure TZaehler.Fertig;
begin
  if FOnDone <> nil then
    FOnDone(Self);
end;

procedure TZaehler.Sicher;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

end.
