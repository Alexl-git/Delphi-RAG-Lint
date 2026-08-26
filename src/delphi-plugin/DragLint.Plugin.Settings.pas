unit DragLint.Plugin.Settings;

interface

type
  TDragLintSettings = record
    ExePath              : string ;
    DbPathTemplate       : string ;
    AutoIndex            : Boolean;
    AutoReindexOnSave    : Boolean;
    AutoDiagnosticsOnSave: Boolean; { v0.42: run syntax/lint diagnostics on save }
    AutoCompileOnSave    : Boolean; { v0.47: out-of-process compile-check on save (surfaces E2003 etc.) }
    AutoCompileBuffer    : Boolean; { v0.47: auto-compile the UNSAVED buffer on idle (ghost-check) -- compiler errors without saving }
    AutoCompileOnStartup : Boolean; { v0.48: compile the project once when it opens, so compiler errors show immediately }
    AutoCompileOnSwitch  : Boolean; { v0.48: compile the current state when you switch to a .pas, even if unchanged }
    AutoJumpToDiagnostics: Boolean; { v0.48: after a compile updates the gutter, scroll the Structure tree to the Diagnostics section if it has any }
    EnableHover          : Boolean;
    EnableCompletion     : Boolean;
    EnableSignature      : Boolean;
    EnableDiagnostics    : Boolean;
    EnableInlineMarkers  : Boolean;
    ShowErrorsInline     : Boolean;
    ShowWarningsInline   : Boolean;
    ShowHintsInline      : Boolean;
    ShowInfoInline       : Boolean;
    ScanLibraries        : Boolean;
    EnableCodeLens       : Boolean;
    EnableWorkspaceMode  : Boolean;
    EnableHoverTooltip   : Boolean;
    { v0.40.3: explicit list of additional DB paths to include in every
      LSP/query invocation (in addition to project + auto-discovered DBs).
      Stored as '|'-delimited string in the registry; presented as a
      one-path-per-line edit in the Settings dialog. }
    IndexDbs        : TArray<string>;
    AutoDiscoverDbs : Boolean       ; { default True - find sibling .sqlite by walking project root }
    IncludeLibraryDb: Boolean       ; { default True - merge exe-relative drag-lint-library.sqlite }
    { v1.7: serve KAI's "local model" completion endpoint from inside the IDE.
      OFF BY DEFAULT AND OFF MEANS OFF: nothing binds, no port is opened, no
      thread starts. The owner asked for exactly that -- an unchecked box must
      not leave a listening socket behind.
      WHY IN-PROCESS. KAI drives llm-ls, which POSTs a fill-in-the-middle prompt
      and carries NO file path; llm-ls also truncates to the context window, so
      even the `unit X;` header is usually gone. A separate process therefore
      cannot know what it is completing IN. Hosting the endpoint here does,
      because the OTA answers it directly (TopView.Buffer.FileName + CursorPos). }
    EnableGhostText: Boolean; { default True since 2026-08-19 -- see LoadDefaults }
    GhostTextPort  : Integer; { default 8765; loopback only }
  end; // record

/// <summary>Applies the 2026-08-19 EnableGhostText default to an installation
/// that already stored the old one, exactly once.</summary>
/// <remarks>A CHANGED DEFAULT DOES NOT REACH AN EXISTING USER. DefaultSettings
/// was flipped to True on 2026-08-19, and nothing happened: LoadSettings reads
/// the registry over the top, and
/// HKCU\Software\drag-lint\DelphiPlugin\EnableGhostText was already 0 from
/// the era when the feature shipped off. So the port stayed unbound and KAI
/// kept raising `os error 10061` on every keystroke -- the exact symptom the
/// new default was chosen to end.
///
/// Once, and once only: a marker value records that the migration ran, so a
/// user who deliberately turns ghost text OFF afterwards keeps it off. Writing
/// the default unconditionally on each load would make the setting impossible
/// to change, which is a worse bug than the one being fixed.
///
/// Call from Register, BEFORE anything reads settings. Guarded -- a registry
/// failure leaves the stored value alone rather than raising into the
/// IDE's package load.</remarks>
procedure MigrateGhostTextDefault;

function LoadSettings: TDragLintSettings;
procedure SaveSettings(const ASettings: TDragLintSettings);
function DefaultSettings: TDragLintSettings                      ;
function ResolveDbPath(const ATemplate, AProjDir: string; const AProjName: string = ''): string;

implementation

uses
  System.SysUtils
  , System.Win.Registry
  , Winapi.Windows
  , DRagLint.Core.Model
  ;

const
  REG_KEY = 'Software\drag-lint\DelphiPlugin';

function DefaultSettings: TDragLintSettings;
begin
  Result.ExePath              := 'drag-lint.exe';
  { v(project-drag-lint-home): the index now lives in the project's own hidden
    _D-RAG folder beside its .dproj -- '<projname>' resolves to the project
    file's base name (see ResolveDbPath below). The old flat
    '<projdir>\drag-lint.sqlite' is still probed as a fallback (DbProbe.pas,
    DbResolver.FindAncestorDb) so an IDE whose registry still holds the
    pre-relocation template keeps finding an index. }
  Result.DbPathTemplate       := '<projdir>\' + DRAG_HOME_DIR + '\<projname>.sqlite';
  Result.AutoIndex            := True;
  Result.AutoReindexOnSave    := True;
  Result.AutoDiagnosticsOnSave:= True;
  Result.AutoCompileOnSave    := True;
  Result.AutoCompileBuffer    := True;
  Result.AutoCompileOnStartup := True;
  Result.AutoCompileOnSwitch  := True;
  Result.AutoJumpToDiagnostics:= True;
  Result.EnableHover          := True;
  Result.EnableCompletion     := True;
  Result.EnableSignature      := True;
  Result.EnableDiagnostics    := True;
  Result.EnableInlineMarkers  := True;
  Result.ShowErrorsInline     := True;
  Result.ShowWarningsInline   := True;
  Result.ShowHintsInline      := True;
  { OWNER RULING 2026-08-26: info markers ON by default. "Users will unclick
    it in the settings if they don't like too many messages. We also have an
    individual rule unclick, so users can adjust it atomically, but we'd rather
    fight false positives to make it more useful than annoying noise."
    A finding worth emitting is worth showing; hiding a whole severity was
    treating noise as a display problem rather than as a rule problem. }
  Result.ShowInfoInline       := True;
  Result.ScanLibraries        := False;
  Result.EnableCodeLens       := True;
  Result.EnableWorkspaceMode  := True;
  Result.EnableHoverTooltip   := True;
  SetLength(Result.IndexDbs, 0);
  Result.AutoDiscoverDbs := True;
  Result.IncludeLibraryDb:= True;
  { ON by default since 2026-08-19, at the owner's request, and the reasoning
    that put it off is worth keeping visible: it opens a listening socket, and a
    feature that starts listening because you installed an update is not one the
    user chose.

    What changed is that NOT listening is not neutral here. KAI is already
    configured to POST to this port, so with nothing bound the IDE raises
      -32603 ... error trying to connect ... (os error 10061)
    on every keystroke it tries to complete. Binding the port and answering an
    EMPTY completion is the quieter and more honest of the two: an empty
    completion is a correct answer, where a plausible invented one could not be
    told from a real suggestion. Loopback only, and Stop() runs on unload. }
  Result.EnableGhostText := True;
  Result.GhostTextPort   := 8765;
end; // function

function LoadSettings: TDragLintSettings;
var
  Reg: TRegistry;
begin
  Result:= DefaultSettings;
  Reg:= TRegistry.Create(KEY_READ);
  try
    Reg.RootKey:= HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REG_KEY) then
    try
      if Reg.ValueExists('ExePath') then Result.ExePath:= Reg.ReadString('ExePath');
      { A BARE EXE NAME IS A LANDMINE, not a convenience. This machine sets
        NoDefaultCurrentDirectoryInExePath, so a bare 'drag-lint.exe' resolves
        off PATH -- which once meant a frozen two-month-old Win32 build
        answering, and reporting 33,626 findings against a real 14,764. The
        diagnose screen flags it ("BARE NAME -- manifest lookups beside the
        engine cannot resolve"); resolving it here fixes every consumer at
        once instead of each spawn site guessing.

        Resolution mirrors EnsureLspClient: the Win64 exe in the sibling
        dll-win64\ folder, else one beside the BPL. If neither exists the bare
        name survives untouched -- a wrong absolute path would be worse than
        the status quo. }
      if (Result.ExePath <> '') and (ExtractFilePath(Result.ExePath) = '') then
      begin
        var BplDir  : string:= ExtractFilePath(GetModuleName(HInstance));
        { THE TRAILING BACKSLASH IS LOAD-BEARING. Without it the probe below
          tests ...\third_party\dll-win64drag-lint.exe, a path that cannot
          exist, so the Win64 branch never runs and a bare name silently
          resolves to whatever sits beside the BPL. That is how the IDE menu
          came to spawn a 2026-06-10 0.41.0-alpha engine on 2026-08-26: it
          rejected --platform, a flag the CLI has accepted for months.
          EnsureLspClient bakes the separator into its own literal
          (dll-win64\); this line has to append it explicitly. }
        var Win64Dir: string:= ExtractFilePath(ExcludeTrailingPathDelimiter(BplDir)) + 'dll-win64\';
        if FileExists(Win64Dir + Result.ExePath) then Result.ExePath:= Win64Dir + Result.ExePath
        else if FileExists(BplDir + Result.ExePath) then Result.ExePath:= BplDir + Result.ExePath;
      end;
      if Reg.ValueExists('DbPathTemplate') then
      begin
        Result.DbPathTemplate:= Reg.ReadString('DbPathTemplate');
        { v0.40.5: migrate the obsolete dot-prefixed default to the new one.
          Previous default '<projdir>\.drag-lint.sqlite' assumed a hidden-file
          convention that turned out to be inconvenient on Windows + never
          actually shipped that way in any user's environment. The new
          default has no dot. Existing registry values get silently rewritten. }
        if SameText(Result.DbPathTemplate, '<projdir>\.drag-lint.sqlite') then Result.DbPathTemplate:= '<projdir>\drag-lint.sqlite';
        { v(2026-08-24): AND ON to the CURRENT default. The migration above
          stopped at the flat '<projdir>\drag-lint.sqlite', which the _D-RAG
          relocation then made obsolete in turn -- so a registry written before
          that relocation was migrated from one dead template to another and
          left there. The plugin's own diagnose screen reports it as
          "pre-_D-RAG template: has no <projname>, so it cannot name a
          per-project index", which is where the owner found it on 2026-08-24.

          Migrating rather than merely warning is the point: a saved value
          SHADOWS a changed default, so shipping a better default fixes nobody
          who already has a registry key. Only the two known dead templates are
          rewritten -- a deliberately customised template is never touched. }
        if SameText(Result.DbPathTemplate, '<projdir>\drag-lint.sqlite') then
          Result.DbPathTemplate:= '<projdir>' + DRAG_HOME_DIR + '\<projname>.sqlite';
      end;
      if Reg.ValueExists('AutoIndex'            ) then Result.AutoIndex            := Reg.ReadInteger('AutoIndex'            ) <> 0;
      if Reg.ValueExists('AutoReindexOnSave'    ) then Result.AutoReindexOnSave    := Reg.ReadInteger('AutoReindexOnSave'    ) <> 0;
      if Reg.ValueExists('AutoDiagnosticsOnSave') then Result.AutoDiagnosticsOnSave:= Reg.ReadInteger('AutoDiagnosticsOnSave') <> 0;
      if Reg.ValueExists('AutoCompileOnSave'    ) then Result.AutoCompileOnSave    := Reg.ReadInteger('AutoCompileOnSave'    ) <> 0;
      if Reg.ValueExists('AutoCompileBuffer'    ) then Result.AutoCompileBuffer    := Reg.ReadInteger('AutoCompileBuffer'    ) <> 0;
      if Reg.ValueExists('AutoCompileOnStartup' ) then Result.AutoCompileOnStartup := Reg.ReadInteger('AutoCompileOnStartup' ) <> 0;
      if Reg.ValueExists('AutoCompileOnSwitch'  ) then Result.AutoCompileOnSwitch  := Reg.ReadInteger('AutoCompileOnSwitch'  ) <> 0;
      if Reg.ValueExists('AutoJumpToDiagnostics') then Result.AutoJumpToDiagnostics:= Reg.ReadInteger('AutoJumpToDiagnostics') <> 0;
      if Reg.ValueExists('EnableHover'          ) then Result.EnableHover          := Reg.ReadInteger('EnableHover'          ) <> 0;
      if Reg.ValueExists('EnableCompletion'     ) then Result.EnableCompletion     := Reg.ReadInteger('EnableCompletion'     ) <> 0;
      if Reg.ValueExists('EnableSignature'      ) then Result.EnableSignature      := Reg.ReadInteger('EnableSignature'      ) <> 0;
      if Reg.ValueExists('EnableDiagnostics'    ) then Result.EnableDiagnostics    := Reg.ReadInteger('EnableDiagnostics'    ) <> 0;
      if Reg.ValueExists('EnableInlineMarkers'  ) then Result.EnableInlineMarkers  := Reg.ReadInteger('EnableInlineMarkers'  ) <> 0;
      if Reg.ValueExists('ShowErrorsInline'     ) then Result.ShowErrorsInline     := Reg.ReadInteger('ShowErrorsInline'     ) <> 0;
      if Reg.ValueExists('ShowWarningsInline'   ) then Result.ShowWarningsInline   := Reg.ReadInteger('ShowWarningsInline'   ) <> 0;
      if Reg.ValueExists('ShowHintsInline'      ) then Result.ShowHintsInline      := Reg.ReadInteger('ShowHintsInline'      ) <> 0;
      if Reg.ValueExists('ShowInfoInline'       ) then Result.ShowInfoInline       := Reg.ReadInteger('ShowInfoInline'       ) <> 0;
      if Reg.ValueExists('ScanLibraries'        ) then Result.ScanLibraries        := Reg.ReadInteger('ScanLibraries'        ) <> 0;
      if Reg.ValueExists('EnableCodeLens'       ) then Result.EnableCodeLens       := Reg.ReadInteger('EnableCodeLens'       ) <> 0;
      if Reg.ValueExists('EnableWorkspaceMode'  ) then Result.EnableWorkspaceMode  := Reg.ReadInteger('EnableWorkspaceMode'  ) <> 0;
      if Reg.ValueExists('EnableHoverTooltip'   ) then Result.EnableHoverTooltip   := Reg.ReadInteger('EnableHoverTooltip'   ) <> 0;
      { v0.40.3: explicit DB list + auto-discovery flags. }
      if Reg.ValueExists('IndexDbs') then
      begin
        var Joined:= Reg.ReadString('IndexDbs');
        if Joined <> '' then
        begin
          var Parts:= Joined.Split(['|'], TStringSplitOptions.ExcludeEmpty);
          SetLength(Result.IndexDbs, Length(Parts));
          for var I:= 0 to High(Parts) do Result.IndexDbs[I]:= Parts[I];
        end;
      end;
      if Reg.ValueExists('AutoDiscoverDbs' ) then Result.AutoDiscoverDbs := Reg.ReadInteger('AutoDiscoverDbs' ) <> 0;
      if Reg.ValueExists('IncludeLibraryDb') then Result.IncludeLibraryDb:= Reg.ReadInteger('IncludeLibraryDb') <> 0;
      if Reg.ValueExists('EnableGhostText' ) then Result.EnableGhostText := Reg.ReadInteger('EnableGhostText' ) <> 0;
      { A port of 0 (or junk) would bind an arbitrary OS-assigned port that the
        KAI dialog could never be pointed at. Fall back to the default rather
        than listening somewhere nobody can reach. }
      if Reg.ValueExists('GhostTextPort') then
      begin
        Result.GhostTextPort:= Reg.ReadInteger('GhostTextPort');
        if (Result.GhostTextPort < 1024) or (Result.GhostTextPort > 65535) then Result.GhostTextPort:= 8765;
      end;
    finally
      Reg.CloseKey;
    end; // try
  finally
    Reg.Free;
  end; // try
end; // function

procedure MigrateGhostTextDefault;
const
  MIGRATED_VALUE = 'GhostTextDefaultMigrated';
var
  Reg: TRegistry;
begin
  Reg:= TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      { Create the key if it is absent: a fresh install has no stored 0 to
        override, but stamping the marker there too means this never runs again
        and the code path stays a one-shot everywhere. }
      if not Reg.OpenKey(REG_KEY, True) then Exit;
      try
        if Reg.ValueExists(MIGRATED_VALUE) then Exit;   { already done }
        { Only a stored OFF is rewritten. An absent value already picks up the
          new default through DefaultSettings, and a stored 1 needs nothing. }
        if Reg.ValueExists('EnableGhostText') and (Reg.ReadInteger('EnableGhostText') = 0) then
          Reg.WriteInteger('EnableGhostText', 1);
        Reg.WriteInteger(MIGRATED_VALUE, 1);
      finally
        Reg.CloseKey;
      end; // try
    except
      { Best effort. A machine where this cannot be written is one where ghost
        text stays off -- which is the state it was already in. }
    end; // try
  finally
    { The Exits above are why this is a try/finally and not a trailing Free:
      both of them leave the procedure, and neither is an error path. }
    Reg.Free;
  end; // try
end; // procedure

procedure SaveSettings(const ASettings: TDragLintSettings);
var
  Reg: TRegistry;
begin
  Reg:= TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey:= HKEY_CURRENT_USER;
    if Reg.OpenKey(REG_KEY, True) then
    try
      Reg.WriteString('ExePath'       , ASettings.ExePath       );
      Reg.WriteString('DbPathTemplate', ASettings.DbPathTemplate);
      Reg.WriteInteger('AutoIndex'            , Ord(ASettings.AutoIndex            ));
      Reg.WriteInteger('AutoReindexOnSave'    , Ord(ASettings.AutoReindexOnSave    ));
      Reg.WriteInteger('AutoDiagnosticsOnSave', Ord(ASettings.AutoDiagnosticsOnSave));
      Reg.WriteInteger('AutoCompileOnSave'    , Ord(ASettings.AutoCompileOnSave    ));
      Reg.WriteInteger('AutoCompileBuffer'    , Ord(ASettings.AutoCompileBuffer    ));
      Reg.WriteInteger('AutoCompileOnStartup' , Ord(ASettings.AutoCompileOnStartup ));
      Reg.WriteInteger('AutoCompileOnSwitch'  , Ord(ASettings.AutoCompileOnSwitch  ));
      Reg.WriteInteger('AutoJumpToDiagnostics', Ord(ASettings.AutoJumpToDiagnostics));
      Reg.WriteInteger('EnableHover'          , Ord(ASettings.EnableHover          ));
      Reg.WriteInteger('EnableCompletion'     , Ord(ASettings.EnableCompletion     ));
      Reg.WriteInteger('EnableSignature'      , Ord(ASettings.EnableSignature      ));
      Reg.WriteInteger('EnableDiagnostics'    , Ord(ASettings.EnableDiagnostics    ));
      Reg.WriteInteger('EnableInlineMarkers'  , Ord(ASettings.EnableInlineMarkers  ));
      Reg.WriteInteger('ShowErrorsInline'     , Ord(ASettings.ShowErrorsInline     ));
      Reg.WriteInteger('ShowWarningsInline'   , Ord(ASettings.ShowWarningsInline   ));
      Reg.WriteInteger('ShowHintsInline'      , Ord(ASettings.ShowHintsInline      ));
      Reg.WriteInteger('ShowInfoInline'       , Ord(ASettings.ShowInfoInline       ));
      Reg.WriteInteger('ScanLibraries'        , Ord(ASettings.ScanLibraries        ));
      Reg.WriteInteger('EnableCodeLens'       , Ord(ASettings.EnableCodeLens       ));
      Reg.WriteInteger('EnableWorkspaceMode'  , Ord(ASettings.EnableWorkspaceMode  ));
      Reg.WriteInteger('EnableHoverTooltip'   , Ord(ASettings.EnableHoverTooltip   ));
      { v0.40.3: persist explicit DB list and auto-discovery flags. }
      var Joined:= '';
      for var I:= 0 to High(ASettings.IndexDbs) do
      begin
        if I > 0 then Joined:= Joined + '|';
        Joined:= Joined + ASettings.IndexDbs[I];
      end;
      Reg.WriteString('IndexDbs', Joined);
      Reg.WriteInteger('AutoDiscoverDbs' , Ord(ASettings.AutoDiscoverDbs ));
      Reg.WriteInteger('IncludeLibraryDb', Ord(ASettings.IncludeLibraryDb));
      Reg.WriteInteger('EnableGhostText' , Ord(ASettings.EnableGhostText ));
      Reg.WriteInteger('GhostTextPort'   ,     ASettings.GhostTextPort    );
    finally
      Reg.CloseKey;
    end; // try
  finally
    Reg.Free;
  end; // try
end; // procedure

function ResolveDbPath(const ATemplate, AProjDir: string; const AProjName: string = ''): string;
begin
  Result:= StringReplace(ATemplate, '<projdir>', ExcludeTrailingPathDelimiter(AProjDir), [rfReplaceAll, rfIgnoreCase]);
  Result:= StringReplace(Result, '<projname>', AProjName, [rfReplaceAll, rfIgnoreCase]);
end;

end.
