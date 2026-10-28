unit LabClsRegistry;

interface

uses
  LabClsWidget;

procedure LabClsRegister(pKind: TLabClsWidgetClass);
procedure LabClsRunAll;

implementation

var
  GKinds: array of TLabClsWidgetClass;

procedure LabClsRegister(pKind: TLabClsWidgetClass);
begin
  SetLength(GKinds, Length(GKinds) + 1);
  GKinds[High(GKinds)] := pKind;
end;

procedure LabClsRunAll;
var
  I: Integer;
  W: TLabClsWidget;
begin
  for I := 0 to High(GKinds) do
  begin
    W := GKinds[I].Create;
    try
      W.Run;
    finally
      W.Free;
    end;
  end;
end;

end.
