program ConfigSaveHarness;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Index.Manifest,
  Config.ManifestSession;
var
  M: TIndexManifest;
  LoadErr, Reason, Dir, Target: string;
  Saved: Boolean;
begin
  if ParamStr(1) = '--start' then
  begin
    { The GUI with no --config, started in ParamStr(2), beside an engine in
      ParamStr(3): MainForm's Save target is then <exe dir>\drag-lint.json. }
    LoadErr:= LoadConfigManifest('', ParamStr(3), ParamStr(2), M);
    Target := IncludeTrailingPathDelimiter(ParamStr(3)) + 'drag-lint.json';
  end
  else
  begin
    Dir    := ExtractFileDir(ParamStr(1));
    LoadErr:= LoadConfigManifest(ParamStr(1), Dir, Dir, M);
    Target := ParamStr(1);
  end;
  Writeln('LOADERR=', LoadErr);
  Writeln('SECTIONS=', Length(M.Sections));
  Writeln('READONLY=', Ord(IsRepoConfigReadOnly(LoadErr)));
  Saved:= TrySaveConfigManifest(M, LoadErr, Target, Reason);
  Writeln('SAVED=', Ord(Saved));
  Writeln('REASON=', Reason);
end.