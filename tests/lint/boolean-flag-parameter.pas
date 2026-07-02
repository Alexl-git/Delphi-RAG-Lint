unit boolflag;
interface
implementation

type
  TBase = class
    procedure Handle(AFlag: Boolean); virtual;
  end;

  TDer = class(TBase)
    procedure Handle(AFlag: Boolean); override;
  end;

procedure DoIt(AApply: Boolean);
var
  Total: Integer;
begin
  Total := 0;
  if AApply then
    Total := 1
  else
    Total := 2;
end;

procedure Store(AKeep: Boolean);
var
  Saved: Boolean;
begin
  Saved := AKeep;
end;

procedure TBase.Handle(AFlag: Boolean);
begin
end;

procedure TDer.Handle(AFlag: Boolean);
begin
  if AFlag then
    Exit;
end;

procedure ButtonClick(Sender: TObject; ASkip: Boolean);
begin
  if ASkip then
    Exit;
end;

end.
