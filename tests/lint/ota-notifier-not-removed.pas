unit ota_notifier_not_removed;

{ Fixture for ota-notifier-not-removed (warning). In a unit that uses ToolsAPI:
  fires on an index that is thrown away, an index no matching remove call
  receives, and RegisterAddInOptions with no UnregisterAddInOptions in the unit.
  Silent: an index the unit removes. (+) must fire, (-) must not. }

interface

procedure Register;

implementation

uses
  ToolsAPI;

var
  GIdeIndex: Integer = -1;
  GLeakIndex: Integer = -1;
  GOptions: INTAAddInOptions;

procedure Register;
begin
  GIdeIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TIdeNotifier.Create); { (-) }
  GLeakIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TIdeNotifier.Create); { (+) }
  (BorlandIDEServices as IOTAEditorServices).AddNotifier(TEditNotifier.Create); { (+) }
  (BorlandIDEServices as INTAEnvironmentOptionsServices).RegisterAddInOptions(GOptions); { (+) }
end;

initialization

finalization
  (BorlandIDEServices as IOTAServices).RemoveNotifier(GIdeIndex);
end.
