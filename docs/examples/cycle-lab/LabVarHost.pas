unit LabVarHost;

interface

uses
  LabVarWidget;

type
  TLabVarHost = class
  public
    procedure Fill(var pWidget: TLabVarWidget);
  end;

implementation

procedure TLabVarHost.Fill(var pWidget: TLabVarWidget);
begin
  if pWidget = nil then
    pWidget := TLabVarWidget.Create;
  pWidget.Hello;
end;

end.
