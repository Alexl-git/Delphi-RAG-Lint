program T34_save_setting;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.Settings;
var
  S, S2: TDragLintSettings;
begin
  S := DefaultSettings;
  Assert(S.AutoReindexOnSave, 'default AutoReindexOnSave should be True');
  S.AutoReindexOnSave := False;
  SaveSettings(S);
  S2 := LoadSettings;
  Assert(not S2.AutoReindexOnSave, 'AutoReindexOnSave roundtrip False');
  { Reset }
  SaveSettings(DefaultSettings);
  WriteLn('OK');
end.
