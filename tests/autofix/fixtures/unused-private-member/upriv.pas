unit upriv;

interface

type
  TWidget = class
  private
    FUsed: Integer;
    FDead: Integer;
    /// <summary>Never called.</summary>
    procedure DeadProc(A: Integer);
    procedure LiveProc;
  public
    procedure Run;
  end;

implementation

procedure TWidget.DeadProc(A: Integer);
begin
  if A > 0 then
  begin
    FUsed:= A;
  end;
end;

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