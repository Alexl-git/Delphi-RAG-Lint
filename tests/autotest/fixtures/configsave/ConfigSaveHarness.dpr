program ConfigSaveHarness;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Index.Manifest,
  Config.ManifestSession;
var
  M: TIndexManifest;
  LoadErr, Reason, Dir: string;
  Saved: Boolean;
begin
  Dir:= ExtractFileDir(ParamStr(1));
  LoadErr:= LoadConfigManifest(ParamStr(1), Dir, Dir, M);
  Writeln('LOADERR=', LoadErr);
  Writeln('SECTIONS=', Length(M.Sections));
  Saved:= TrySaveConfigManifest(M, LoadErr, ParamStr(1), Reason);
  Writeln('SAVED=', Ord(Saved));
  Writeln('REASON=', Reason);
end.