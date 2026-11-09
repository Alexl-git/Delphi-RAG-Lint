unit HubSpokeA;

interface

procedure SpokeA;

implementation

uses
  System.SysUtils, HubMain;

procedure SpokeA;
begin
  HubMainForm.Counter:= HubMainForm.Counter + 1;
  HubMainForm.Log.Add('A counter=' + IntToStr(HubMainForm.Counter));
end;

end.
