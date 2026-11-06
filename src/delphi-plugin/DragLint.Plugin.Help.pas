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
/// <remarks>
/// Reads LoadSettings.HelpRoot on every call -- no cached root, so an
/// Options change applies to the next click. Main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DockForm.TDragLintDockFrame.OpenHelpForActiveTab (DragLint.Plugin.DockForm.pas), DragLint.Plugin.Editor.InvokeHelpEffectLegend (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeHelpMenuReference (DragLint.Plugin.Editor.pas), DragLint.Plugin.HelpLine.TDLHelpLine.OpenHit (DragLint.Plugin.HelpLine.pas)</para>
/// <para>Calls: DragLint.Plugin.Help.DLOpenHelpUrl, DragLint.Plugin.Help.DLSharedHelpIndex, DragLint.Plugin.HelpIndex.DLResolveHelpUrl, DragLint.Plugin.Settings.LoadSettings</para>
/// <seealso cref="DragLint.Plugin.Help.DLOpenHelpUrl"/>
/// <seealso cref="DragLint.Plugin.Help.DLSharedHelpIndex"/>
/// <seealso cref="DragLint.Plugin.HelpIndex.DLResolveHelpUrl"/>
/// <seealso cref="DragLint.Plugin.Settings.LoadSettings"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure DLOpenHelp(const pFeatureId: string);

/// <summary>Opens a URL with the shell (the default browser).</summary>
/// <param name="pUrl">An http(s) or file: URL; empty does nothing.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Help.DLOpenAllFeatures (DragLint.Plugin.Help.pas), DragLint.Plugin.Help.DLOpenHelp (DragLint.Plugin.Help.pas), DragLint.Plugin.OptionsFrames.TDLGeneralOptionsFrame.BtnHelpTestClick (DragLint.Plugin.OptionsFrames.pas)</para>
/// <para>Calls: PChar, ShellExecute</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure DLOpenHelpUrl(const pUrl: string);

/// <summary>Opens the complete feature list (&lt;root&gt;/help/dl/) at the
/// current help root.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.InvokeHelpAllFeatures (DragLint.Plugin.Editor.pas), DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick (DragLint.Plugin.HelpLine.pas)</para>
/// <para>Calls: DragLint.Plugin.Help.DLOpenHelpUrl, DragLint.Plugin.HelpIndex.DLHelpAllUrl, DragLint.Plugin.Settings.LoadSettings</para>
/// <seealso cref="DragLint.Plugin.Help.DLOpenHelpUrl"/>
/// <seealso cref="DragLint.Plugin.HelpIndex.DLHelpAllUrl"/>
/// <seealso cref="DragLint.Plugin.Settings.LoadSettings"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure DLOpenAllFeatures;

/// <summary>The offline feature list, located per spec 3.2 and cached for the
/// IDE session; re-read when the file's size or mtime changed.</summary>
/// <returns>Never nil. Loaded = False when no list is installed (FileName '')
/// or the file is unreadable (LastError says why).</returns>
/// <exception cref="EJSONException"><!-- drag-lint:auto exc -->via DragLint.Plugin.HelpIndex.TDLHelpIndex.LoadFromFile: not a JSON array of feature rows</exception>
/// <remarks>
/// Owned by this unit -- the caller never frees it. Each call stats
/// the file once; parse only on change. Main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DockForm.TDragLintDockFrame.OpenHelpForActiveTab (DragLint.Plugin.DockForm.pas), DragLint.Plugin.Help.DLOpenHelp (DragLint.Plugin.Help.pas), DragLint.Plugin.HelpLine.TDLHelpLine.UpdateHits (DragLint.Plugin.HelpLine.pas)</para>
/// <para>Calls: DragLint.Plugin.HelpIndex.DLLocateHelpIndex, DragLint.Plugin.HelpIndex.TDLHelpIndex.LoadFromFile, DragLint.Plugin.HelpIndex.TDLHelpIndex.ReloadIfChanged, DragLint.Plugin.Settings.LoadSettings, ExtractFilePath, FreeAndNil, GetModuleName, SameText</para>
/// <para>Returns: GIndex</para>
/// <seealso cref="DragLint.Plugin.HelpIndex.DLLocateHelpIndex"/>
/// <seealso cref="DragLint.Plugin.HelpIndex.TDLHelpIndex.LoadFromFile"/>
/// <seealso cref="DragLint.Plugin.HelpIndex.TDLHelpIndex.ReloadIfChanged"/>
/// <seealso cref="DragLint.Plugin.Settings.LoadSettings"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
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
