unit DRagLint.Plugin.DbProbe;

interface

uses
  DRagLint.Plugin.Settings;

/// <summary>Chooses the on-disk index DB for a project's own directory: the
/// settings-template file (`&lt;projdir&gt;\_D-RAG\&lt;projname&gt;.sqlite` by default)
/// if it exists and is non-empty, else the project-name file
/// (`&lt;projdir&gt;\&lt;projname&gt;.sqlite`, i.e. ChangeFileExt of the .dproj) if it
/// exists and is non-empty, else the pre-relocation flat file
/// (`&lt;projdir&gt;\drag-lint.sqlite`) if it exists and is non-empty, else ''.
/// Template-first preserves existing setups; the project-name probe fixes the
/// "Code Elements 0" case where a project was indexed to &lt;projname&gt;.sqlite; the
/// flat-file probe keeps an IDE whose registry still holds the pre-relocation
/// template (or whose DB was never migrated into _D-RAG) finding an index.
/// Pure: only path math + file existence/size, no OTA.</summary>
/// <param name="AProjPath">Full path to the .dproj (or '').</param>
/// <param name="ASettings">Resolver settings; DbPathTemplate drives the template file.</param>
/// <returns>Chosen existing non-empty DB path, or '' when no candidate qualifies.</returns>
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
  ProjName: string;
  Template: string;
  ByName  : string;
  Flat    : string;
begin
  Result := '';
  if AProjPath = '' then Exit;
  ProjDir  := ExtractFilePath(AProjPath);
  ProjName := ChangeFileExt(ExtractFileName(AProjPath), ''); // <projname>
  Template := ResolveDbPath(ASettings.DbPathTemplate, ProjDir, ProjName);
  if ExistsNonEmpty(Template) then Exit(Template);
  ByName := ChangeFileExt(AProjPath, '.sqlite'); // <projdir>\<projname>.sqlite
  if ExistsNonEmpty(ByName) then Exit(ByName);
  Flat := TPath.Combine(ProjDir, 'drag-lint.sqlite'); // pre-relocation fallback
  if ExistsNonEmpty(Flat) then Exit(Flat);
end;

end.