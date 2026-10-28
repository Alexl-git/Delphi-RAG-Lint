unit LabRcWidget;

interface

type
  TLabRcWidget = class(TInterfacedObject)
  public
    procedure Describe;
    procedure Again;
  end;

implementation

uses
  LabRcHost;

procedure TLabRcWidget.Describe;
begin
  Writeln('[rc] describe');
end;

procedure TLabRcWidget.Again;
begin
  LabRcShow(Self);
end;

end.
