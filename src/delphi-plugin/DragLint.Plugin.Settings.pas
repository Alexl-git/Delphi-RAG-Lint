unit DragLint.Plugin.Settings;

interface

type
  TDragLintSettings = record
    ExePath:              string;
    DbPathTemplate:       string;
    AutoIndex:            Boolean;
    AutoReindexOnSave:    Boolean;
    AutoDiagnosticsOnSave: Boolean;  { v0.42: run syntax/lint diagnostics on save }
    AutoCompileOnSave:    Boolean;   { v0.47: out-of-process compile-check on save (surfaces E2003 etc.) }
    AutoCompileBuffer:    Boolean;   { v0.47: auto-compile the UNSAVED buffer on idle (ghost-check) -- compiler errors without saving }
    EnableHover:          Boolean;
    EnableCompletion:     Boolean;
    EnableSignature:      Boolean;
    EnableDiagnostics:    Boolean;
    EnableInlineMarkers:  Boolean;
    ShowErrorsInline:     Boolean;
    ShowWarningsInline:   Boolean;
    ShowHintsInline:      Boolean;
    ShowInfoInline:       Boolean;
    ScanLibraries:        Boolean;
    EnableCodeLens:       Boolean;
    EnableWorkspaceMode:  Boolean;
    EnableHoverTooltip:   Boolean;
    { v0.40.3: explicit list of additional DB paths to include in every
      LSP/query invocation (in addition to project + auto-discovered DBs).
      Stored as '|'-delimited string in the registry; presented as a
      one-path-per-line edit in the Settings dialog. }
    IndexDbs:             TArray<string>;
    AutoDiscoverDbs:      Boolean;  { default True - find sibling .sqlite by walking project root }
    IncludeLibraryDb:     Boolean;  { default True - merge exe-relative drag-lint-library.sqlite }
  end;

function LoadSettings: TDragLintSettings;
procedure SaveSettings(const ASettings: TDragLintSettings);
function DefaultSettings: TDragLintSettings;
function ResolveDbPath(const ATemplate, AProjDir: string): string;

implementation

uses
  System.SysUtils, System.Win.Registry, Winapi.Windows;

const
  REG_KEY = 'Software\drag-lint\DelphiPlugin';

function DefaultSettings: TDragLintSettings;
begin
  Result.ExePath        := 'drag-lint.exe';
  Result.DbPathTemplate := '<projdir>\drag-lint.sqlite';
  Result.AutoIndex            := True;
  Result.AutoReindexOnSave    := True;
  Result.AutoDiagnosticsOnSave := True;
  Result.AutoCompileOnSave    := True;
  Result.AutoCompileBuffer    := True;
  Result.EnableHover          := True;
  Result.EnableCompletion  := True;
  Result.EnableSignature   := True;
  Result.EnableDiagnostics := True;
  Result.EnableInlineMarkers  := True;
  Result.ShowErrorsInline     := True;
  Result.ShowWarningsInline   := True;
  Result.ShowHintsInline      := True;
  Result.ShowInfoInline       := False;
  Result.ScanLibraries        := False;
  Result.EnableCodeLens       := True;
  Result.EnableWorkspaceMode  := True;
  Result.EnableHoverTooltip   := True;
  SetLength(Result.IndexDbs, 0);
  Result.AutoDiscoverDbs      := True;
  Result.IncludeLibraryDb     := True;
end;

function LoadSettings: TDragLintSettings;
var
  Reg: TRegistry;
begin
  Result := DefaultSettings;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REG_KEY) then
    try
      if Reg.ValueExists('ExePath')        then Result.ExePath        := Reg.ReadString('ExePath');
      if Reg.ValueExists('DbPathTemplate') then
      begin
        Result.DbPathTemplate := Reg.ReadString('DbPathTemplate');
        { v0.40.5: migrate the obsolete dot-prefixed default to the new one.
          Previous default '<projdir>\.drag-lint.sqlite' assumed a hidden-file
          convention that turned out to be inconvenient on Windows + never
          actually shipped that way in any user's environment. The new
          default has no dot. Existing registry values get silently rewritten. }
        if SameText(Result.DbPathTemplate, '<projdir>\.drag-lint.sqlite') then
          Result.DbPathTemplate := '<projdir>\drag-lint.sqlite';
      end;
      if Reg.ValueExists('AutoIndex')         then Result.AutoIndex         := Reg.ReadInteger('AutoIndex') <> 0;
      if Reg.ValueExists('AutoReindexOnSave') then Result.AutoReindexOnSave := Reg.ReadInteger('AutoReindexOnSave') <> 0;
      if Reg.ValueExists('AutoDiagnosticsOnSave') then Result.AutoDiagnosticsOnSave := Reg.ReadInteger('AutoDiagnosticsOnSave') <> 0;
      if Reg.ValueExists('AutoCompileOnSave') then Result.AutoCompileOnSave := Reg.ReadInteger('AutoCompileOnSave') <> 0;
      if Reg.ValueExists('AutoCompileBuffer') then Result.AutoCompileBuffer := Reg.ReadInteger('AutoCompileBuffer') <> 0;
      if Reg.ValueExists('EnableHover')       then Result.EnableHover       := Reg.ReadInteger('EnableHover') <> 0;
      if Reg.ValueExists('EnableCompletion')  then Result.EnableCompletion  := Reg.ReadInteger('EnableCompletion') <> 0;
      if Reg.ValueExists('EnableSignature')   then Result.EnableSignature   := Reg.ReadInteger('EnableSignature') <> 0;
      if Reg.ValueExists('EnableDiagnostics') then Result.EnableDiagnostics := Reg.ReadInteger('EnableDiagnostics') <> 0;
      if Reg.ValueExists('EnableInlineMarkers') then
        Result.EnableInlineMarkers := Reg.ReadInteger('EnableInlineMarkers') <> 0;
      if Reg.ValueExists('ShowErrorsInline') then
        Result.ShowErrorsInline    := Reg.ReadInteger('ShowErrorsInline') <> 0;
      if Reg.ValueExists('ShowWarningsInline') then
        Result.ShowWarningsInline  := Reg.ReadInteger('ShowWarningsInline') <> 0;
      if Reg.ValueExists('ShowHintsInline') then
        Result.ShowHintsInline     := Reg.ReadInteger('ShowHintsInline') <> 0;
      if Reg.ValueExists('ShowInfoInline') then
        Result.ShowInfoInline      := Reg.ReadInteger('ShowInfoInline') <> 0;
      if Reg.ValueExists('ScanLibraries') then
        Result.ScanLibraries       := Reg.ReadInteger('ScanLibraries') <> 0;
      if Reg.ValueExists('EnableCodeLens') then
        Result.EnableCodeLens      := Reg.ReadInteger('EnableCodeLens') <> 0;
      if Reg.ValueExists('EnableWorkspaceMode') then
        Result.EnableWorkspaceMode := Reg.ReadInteger('EnableWorkspaceMode') <> 0;
      if Reg.ValueExists('EnableHoverTooltip') then
        Result.EnableHoverTooltip  := Reg.ReadInteger('EnableHoverTooltip') <> 0;
      { v0.40.3: explicit DB list + auto-discovery flags. }
      if Reg.ValueExists('IndexDbs') then
      begin
        var Joined := Reg.ReadString('IndexDbs');
        if Joined <> '' then
        begin
          var Parts := Joined.Split(['|'], TStringSplitOptions.ExcludeEmpty);
          SetLength(Result.IndexDbs, Length(Parts));
          for var I := 0 to High(Parts) do
            Result.IndexDbs[I] := Parts[I];
        end;
      end;
      if Reg.ValueExists('AutoDiscoverDbs') then
        Result.AutoDiscoverDbs  := Reg.ReadInteger('AutoDiscoverDbs') <> 0;
      if Reg.ValueExists('IncludeLibraryDb') then
        Result.IncludeLibraryDb := Reg.ReadInteger('IncludeLibraryDb') <> 0;
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

procedure SaveSettings(const ASettings: TDragLintSettings);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(REG_KEY, True) then
    try
      Reg.WriteString('ExePath',        ASettings.ExePath);
      Reg.WriteString('DbPathTemplate', ASettings.DbPathTemplate);
      Reg.WriteInteger('AutoIndex',         Ord(ASettings.AutoIndex));
      Reg.WriteInteger('AutoReindexOnSave', Ord(ASettings.AutoReindexOnSave));
      Reg.WriteInteger('AutoDiagnosticsOnSave', Ord(ASettings.AutoDiagnosticsOnSave));
      Reg.WriteInteger('AutoCompileOnSave', Ord(ASettings.AutoCompileOnSave));
      Reg.WriteInteger('AutoCompileBuffer', Ord(ASettings.AutoCompileBuffer));
      Reg.WriteInteger('EnableHover',       Ord(ASettings.EnableHover));
      Reg.WriteInteger('EnableCompletion',  Ord(ASettings.EnableCompletion));
      Reg.WriteInteger('EnableSignature',   Ord(ASettings.EnableSignature));
      Reg.WriteInteger('EnableDiagnostics', Ord(ASettings.EnableDiagnostics));
      Reg.WriteInteger('EnableInlineMarkers', Ord(ASettings.EnableInlineMarkers));
      Reg.WriteInteger('ShowErrorsInline',    Ord(ASettings.ShowErrorsInline));
      Reg.WriteInteger('ShowWarningsInline',  Ord(ASettings.ShowWarningsInline));
      Reg.WriteInteger('ShowHintsInline',     Ord(ASettings.ShowHintsInline));
      Reg.WriteInteger('ShowInfoInline',      Ord(ASettings.ShowInfoInline));
      Reg.WriteInteger('ScanLibraries',       Ord(ASettings.ScanLibraries));
      Reg.WriteInteger('EnableCodeLens',      Ord(ASettings.EnableCodeLens));
      Reg.WriteInteger('EnableWorkspaceMode', Ord(ASettings.EnableWorkspaceMode));
      Reg.WriteInteger('EnableHoverTooltip',  Ord(ASettings.EnableHoverTooltip));
      { v0.40.3: persist explicit DB list and auto-discovery flags. }
      var Joined := '';
      for var I := 0 to High(ASettings.IndexDbs) do
      begin
        if I > 0 then Joined := Joined + '|';
        Joined := Joined + ASettings.IndexDbs[I];
      end;
      Reg.WriteString('IndexDbs', Joined);
      Reg.WriteInteger('AutoDiscoverDbs',  Ord(ASettings.AutoDiscoverDbs));
      Reg.WriteInteger('IncludeLibraryDb', Ord(ASettings.IncludeLibraryDb));
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

function ResolveDbPath(const ATemplate, AProjDir: string): string;
begin
  Result := StringReplace(ATemplate, '<projdir>',
    ExcludeTrailingPathDelimiter(AProjDir), [rfReplaceAll, rfIgnoreCase]);
end;

end.
