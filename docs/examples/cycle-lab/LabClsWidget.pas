unit LabClsWidget;

interface

type
  TLabClsWidget = class
  public
    procedure Run; virtual;
  end;

  TLabClsWidgetClass = class of TLabClsWidget;

implementation

uses
  LabClsRegistry;

procedure TLabClsWidget.Run;
begin
  Writeln('[cls] widget runs');
end;

initialization
  LabClsRegister(TLabClsWidget);

end.
