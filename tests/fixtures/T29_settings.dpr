program T29_settings;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.Settings;
var
  S, S2: TDragLintSettings;
begin
  S := DefaultSettings;
  S.ExePath    := 'C:\test\drag-lint.exe';
  S.AutoIndex  := False;
  S.EnableHover := False;
  SaveSettings(S);

  S2 := LoadSettings;
  Assert(S2.ExePath = 'C:\test\drag-lint.exe', 'ExePath roundtrip');
  Assert(not S2.AutoIndex,  'AutoIndex roundtrip');
  Assert(not S2.EnableHover, 'EnableHover roundtrip');

  { v0.29 inline-marker settings round-trip }
  S.EnableInlineMarkers := False;
  S.ShowErrorsInline    := False;
  S.ShowWarningsInline  := True;
  S.ShowHintsInline     := False;
  S.ShowInfoInline      := True;
  SaveSettings(S);
  S2 := LoadSettings;
  Assert(not S2.EnableInlineMarkers,  'EnableInlineMarkers roundtrip');
  Assert(not S2.ShowErrorsInline,     'ShowErrorsInline roundtrip');
  Assert(S2.ShowWarningsInline,       'ShowWarningsInline roundtrip');
  Assert(not S2.ShowHintsInline,      'ShowHintsInline roundtrip');
  Assert(S2.ShowInfoInline,           'ShowInfoInline roundtrip');

  { Reset to defaults }
  SaveSettings(DefaultSettings);

  Assert(ResolveDbPath('<projdir>\.drag-lint.sqlite', 'C:\Projects\foo') =
    'C:\Projects\foo\.drag-lint.sqlite', 'ResolveDbPath substitution');
  WriteLn('OK');
end.
