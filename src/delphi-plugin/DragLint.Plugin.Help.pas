unit DragLint.Plugin.Help;

{ The ONE way the plugin opens help (spec docs\superpowers\specs\
  2026-10-23-ide-help-line-design.md 3.4 / 3.5): every help link is a registry
  id, resolved against the HelpRoot setting read fresh on each call. The URL
  rules and the matcher live in DragLint.Plugin.HelpIndex (pure, harness-
  tested); this unit adds the browser launch and the session-cached list. }

interface

uses
  DragLint.Plugin.HelpIndex
  ;

/// <summary>Opens the help page of one registry feature in the browser.</summary>
/// <param name="pFeatureId">Registry id (features\entries\&lt;id&gt;.json). An id
/// the loaded feature list does not carry opens the all-features page.</param>
/// <remarks>Reads LoadSettings.HelpRoot on every call -- no cached root, so an
/// Options change applies to the next click. Main thread only.</remarks>
procedure DLOpenHelp(const pFeatureId: string);

/// <summary>Opens a URL with the shell (the default browser).</summary>
/// <param name="pUrl">An http(s) or file: URL; empty does nothing.</param>
procedure DLOpenHelpUrl(const pUrl: string);

/// <summary>Opens the complete feature list (&lt;root&gt;/help/dl/) at the
/// current help root.</summary>
procedure DLOpenAllFeatures;

/// <summary>The offline feature list, located per spec 3.2 and cached for the
/// IDE session; re-read when the file's size or mtime changed.</summary>
/// <returns>Never nil. Loaded = False when no list is installed (FileName '')
/// or the file is unreadable (LastError says why).</returns>
/// <remarks>Owned by this unit -- the caller never frees it. Each call stats
/// the file once; parse only on change. Main thread only.</remarks>
function DLSharedHelpIndex: TDLHelpIndex;

implementation

uses
  System.SysUtils
  , Winapi.Windows
  , Winapi.ShellAPI
  , DragLint.Plugin.Settings
  ;

var
  GIndex: TDLHelpIndex = nil;

function DLSharedHelpIndex: TDLHelpIndex;
var
  Settings: TDragLintSettings;
  Path    : string;
begin
  Settings:= LoadSettings;
  Path:= DLLocateHelpIndex(ExtractFilePath(Settings.ExePath), Settings.HelpRoot,
    ExtractFilePath(GetModuleName(HInstance)));
  if (GIndex = nil) or ((Path = '') and (GIndex.FileName <> '')) then
  begin
    FreeAndNil(GIndex);
    GIndex:= TDLHelpIndex.Create;
  end; // if
  if Path <> '' then
  begin
    if not SameText(Path, GIndex.FileName) then GIndex.LoadFromFile(Path)
    else                                        GIndex.ReloadIfChanged;
  end; // if
  Result:= GIndex;
end; // function

procedure DLOpenHelpUrl(const pUrl: string);
begin
  if pUrl = '' then Exit;
  ShellExecute(0, 'open', PChar(pUrl), nil, nil, SW_SHOWNORMAL);
end; // procedure

procedure DLOpenHelp(const pFeatureId: string);
begin
  DLOpenHelpUrl(DLResolveHelpUrl(LoadSettings.HelpRoot, pFeatureId, DLSharedHelpIndex));
end; // procedure

procedure DLOpenAllFeatures;
begin
  DLOpenHelpUrl(DLHelpAllUrl(LoadSettings.HelpRoot));
end; // procedure

initialization

finalization
  FreeAndNil(GIndex);

end.
