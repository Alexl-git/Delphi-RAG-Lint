unit LabRcHost;

interface

uses
  LabRcWidget;

function LabRcMake: TLabRcWidget;
procedure LabRcShow(pWidget: TLabRcWidget);

implementation

function LabRcMake: TLabRcWidget;
begin
  Result := TLabRcWidget.Create;
end;

procedure LabRcShow(pWidget: TLabRcWidget);
begin
  pWidget.Describe;
end;

end.
