unit LabExcWidget;

interface

type
  TLabExcWidget = class
  public
    procedure Touch;
  end;

implementation

uses
  LabExcHost;

procedure TLabExcWidget.Touch;
begin
  Writeln('[exc] touched');
  LabExcFire(Self);
end;

end.
