unit HubSpokeB;

interface

procedure SpokeB;

implementation

uses
  HubMain;

procedure SpokeB;
begin
  // HubMainForm.Note in a comment stays as it is
  HubMainForm.Note('B says HubMainForm.Log', 1);
  if HubMainForm.Ready then HubMainForm.Note('B ready', 2);
end;

end.
