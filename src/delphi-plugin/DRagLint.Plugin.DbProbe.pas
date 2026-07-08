unit DRagLint.Plugin.DbProbe;

interface

uses
  DRagLint.Plugin.Settings;

/// <summary>Chooses the on-disk index DB for a project's own directory: the
/// settings-template file (`&lt;projdir&gt;\drag-lint.sqlite`) if it exists and is
/// non-empty, else the project-name file (`&lt;projdir&gt;\&lt;projname&gt;.sqlite`,
/// i.e. ChangeFileExt of the .dproj) if it exists and is non-empty, else ''.
/// Template-first preserves existing setups; the project-name probe fixes the
/// "Code Elements 0" case where a project was indexed to &lt;projname&gt;.sqlite.
/// Pure: only path math + file existence/size, no OTA.</summary>
/// <param name="AProjPath">Full path to the .dproj (or '').</param>
/// <param name="ASettings">Resolver settings; DbPathTemplate drives the template file.</param>
/// <returns>Chosen existing non-empty DB path, or '' when neither candidate qualifies.</returns>
function PickProjectDb(const AProjPath: string; const ASettings: TDragLintSettings): string;

implementation

uses
  System.SysUtils, System.IOUtils;

function ExistsNonEmpty(const APath: string): Boolean;
begin
  Result := (APath <> '') and TFile.Exists(APath) and (TFile.GetSize(APath) > 0);
end;

function PickProjectDb(const AProjPath: string; const ASettings: TDragLintSettings): string;
var
  ProjDir : string;
  Template: string;
  ByName  : string;
begin
  Result := '';
  if AProjPath = '' then Exit;
  ProjDir  := ExtractFilePath(AProjPath);
  Template := ResolveDbPath(ASettings.DbPathTemplate, ProjDir);
  if ExistsNonEmpty(Template) then Exit(Template);
  ByName := ChangeFileExt(AProjPath, '.sqlite'); // <projdir>\<projname>.sqlite
  if ExistsNonEmpty(ByName) then Exit(ByName);
end;

end.