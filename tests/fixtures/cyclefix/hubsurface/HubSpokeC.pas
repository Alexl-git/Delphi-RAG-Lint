unit HubSpokeC;

interface

procedure SpokeC;

implementation

uses
  System.SysUtils,
  HubMain;

procedure SpokeC;
begin
  hubMainForm.log.Add('C ' + BoolToStr(HubMainForm.Ready, True));
end;

end.
