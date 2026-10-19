program ConfigSaveHarness;
{$APPTYPE CONSOLE}
{ Drives Config.ManifestSession the way Config.MainForm does, without a GUI.
    ConfigSaveHarness <path>                       load, Save unchanged
    ConfigSaveHarness <path> --set-maxjobs <n>     load, edit settings.maxJobs, Save
    ConfigSaveHarness <path> --add-section <name>  load, append a section, Save
    ConfigSaveHarness <path> --drop-section <name> load, remove that section, Save
    ConfigSaveHarness --no-config <exeDir> <startDir>
                                                   no --config: what MainForm loads and
                                                   where it saves when started in startDir
    ConfigSaveHarness --discover <exeDir> <startDir>
                                                   control: what TManifestIO.Load (the
                                                   engine's merge) sees from startDir }
uses
  System.SysUtils,
  DRagLint.Index.Manifest,
  Config.ManifestSession;
var
  M: TIndexManifest;
  LoadErr, Reason, Path, Original, Op, Arg: string;
  Saved: Boolean;
  I, K: Integer;
begin
  if ParamStr(1) = '--discover' then
  begin
    M:= TManifestIO.Load(ParamStr(2), ParamStr(3));
    Writeln('SECTIONS=', Length(M.Sections));
    Exit;
  end;
  if ParamStr(1) = '--no-config' then
  begin
    Path:= ConfigTargetPath('', ParamStr(2));
    LoadErr:= LoadConfigManifest(Path, M, Original);
    Op:= '';
  end
  else
  begin
    Path:= ParamStr(1);
    LoadErr:= LoadConfigManifest(Path, M, Original);
    Op:= ParamStr(2);
  end;
  Arg:= ParamStr(3);
  Writeln('TARGET=', Path);
  Writeln('LOADERR=', LoadErr);
  Writeln('SECTIONS=', Length(M.Sections));
  if Op = '--set-maxjobs' then M.Settings.MaxJobs:= StrToInt(Arg)
  else if Op = '--add-section' then
  begin
    SetLength(M.Sections, Length(M.Sections) + 1);
    M.Sections[High(M.Sections)].Name:= Arg;
    M.Sections[High(M.Sections)].Include:= ['C:\x\' + Arg + '.dproj'];
  end
  else if Op = '--drop-section' then
  begin
    K:= 0;
    for I:= 0 to High(M.Sections) do
      if not SameText(M.Sections[I].Name, Arg) then
      begin
        M.Sections[K]:= M.Sections[I];
        Inc(K);
      end;
    SetLength(M.Sections, K);
  end;
  Saved:= TrySaveConfigManifest(M, LoadErr, Original, Path, Reason);
  Writeln('SAVED=', Ord(Saved));
  Writeln('REASON=', Reason);
end.
