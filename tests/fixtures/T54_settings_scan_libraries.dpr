program T54_settings_scan_libraries;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.Settings;
var
  S, S2: TDragLintSettings;
begin
  S := DefaultSettings;
  Assert(not S.ScanLibraries, 'Default ScanLibraries must be False');

  S.ScanLibraries := True;
  SaveSettings(S);
  S2 := LoadSettings;
  Assert(S2.ScanLibraries, 'ScanLibraries True roundtrip');

  S.ScanLibraries := False;
  SaveSettings(S);
  S2 := LoadSettings;
  Assert(not S2.ScanLibraries, 'ScanLibraries False roundtrip');

  SaveSettings(DefaultSettings);
  WriteLn('OK');
end.
