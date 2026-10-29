; drag-lint tool-set installer (job R2 / T9c).
;
; Design: docs\superpowers\specs\2026-10-05-R2-installer-design-note.md, with the
; owner's answers of 2026-10-05, 2026-10-06 and 2026-10-13. Build it with
; installer\Build-Installer.ps1, never with ISCC directly: the script reads the
; version from DRAGLINT_VERSION, checks the shipped engine reports that same
; version, checks every source exists, and passes the /D defines below.
;
; LAYOUT (owner D1: the runtime is FLAT -- the plugin BPL and the engine
; share one folder):
;   {app}\bin\                 drag-lint.exe + companions, tree-sitter DLLs, rules\,
;                              the Win32 plugin BPL, drag-lint.json
;   {app}\bin\x64\             the Win64 plugin BPL (64-bit IDE only; a second file
;                              of the same name cannot share bin\)
;   {app}\bin\graphviz\bin\    dot.exe + its DLLs + config8 -- the engine finds its
;                              charts folder and dot.exe by layout, with no scripts
;   {app}\yadf\                YADF.exe, YADFSetup.exe, YADFOT.bpl (Win32); x64\ (Win64)
;   {app}\licenses\
;   {app}\report-pairs.example.json  (the engine reads {app}\report-pairs.json)
;
; REGISTRY. Everything is per user (HKCU) in both install modes (owner D4), and
; uninstall removes only what this installer wrote:
;   * Known Packages / Known Packages x64 -- one value each, named by OUR path.
;   * Software\drag-lint\DelphiPlugin\ExePath and Software\YADF\ExePath -- written
;     only when empty, dead, already ours, or the user agrees to replace it; removed
;     only when they still point at this install.
;   * draglint:// -- by drag-lint protocol register, undone by protocol unregister only
;     when this installer registered it (Software\drag-lint\Installer marker).
;
; WHY THE ENGINE PATH IS A SETTING, NOT A FILE BESIDE THE BPL. The plugin used to
; probe <bpl-dir>\drag-lint.exe; that step was removed on 2026-08-26 because a
; stale engine beside a BPL answered wrongly and silently. ExePath is the plugin's
; existing first resolution step, it serves the 32-bit and the 64-bit IDE alike,
; and the plugin finds drag-lint.json beside it.

#ifndef AppVersion
  #error AppVersion is not defined -- build with installer\Build-Installer.ps1
#endif
#ifndef EngineDir
  #error EngineDir is not defined -- build with installer\Build-Installer.ps1
#endif

#ifndef NumericVersion
  #error NumericVersion is not defined -- build with installer\Build-Installer.ps1
#endif

#define AppName "drag-lint"
#define IdeVer  "37.0"
#define IdeKey  "Software\Embarcadero\BDS\" + IdeVer
#define PlugKey "Software\drag-lint\DelphiPlugin"
#define InstKey "Software\drag-lint\Installer"
#define YadfKey "Software\YADF"

[Setup]
AppId={{6E0A3C52-3D7B-4C1E-9B0D-7F2A4D8E5C11}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#NumericVersion}
VersionInfoProductVersion={#NumericVersion}
VersionInfoTextVersion={#AppVersion}
VersionInfoProductTextVersion={#AppVersion}
AppPublisher=Alexander Liberov
AppPublisherURL=https://github.com/
DefaultDirName={autopf}\drag-lint
DefaultGroupName=drag-lint
DisableProgramGroupPage=yes
; owner D4: "Just for me" (default, no admin) or "All users" (admin; Windows asks)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutDir}
OutputBaseFilename=drag-lint-setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
LicenseFile={#RepoRoot}\installer\licenses\drag-lint-LICENSE.txt
UninstallDisplayName={#AppName} {#AppVersion}
CloseApplications=yes
RestartApplications=no
; (e) code signing: leave disabled until a certificate exists
; SignTool=drag-lint $f

[Types]
Name: "full";   Description: "Full installation"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "core";      Description: "drag-lint engine, rules and chart scripts"; Types: full custom; Flags: fixed
Name: "convrules"; Description: "ConvRulesEditor (conversion rules editor)"; Types: full
Name: "graph";     Description: "drag-lint-graph (call-graph tool)";          Types: full
Name: "graphviz";  Description: "Graphviz dot (needed by the charts)";        Types: full
Name: "plugin32";  Description: "IDE plugin for RAD Studio 13 (32-bit IDE)";  Types: full
Name: "plugin64";  Description: "IDE plugin for RAD Studio 13 (64-bit IDE)";  Types: full
Name: "yadf";      Description: "YADF formatter (YADF.exe + YADFSetup.exe)";  Types: full
Name: "yadfot32";  Description: "YADF IDE plugin (32-bit IDE)";               Types: full
Name: "yadfot64";  Description: "YADF IDE plugin (64-bit IDE)";               Types: full

[Tasks]
Name: "protocol"; Description: "Register draglint:// links (click a chart node to open the source in the IDE)"; Components: core
Name: "mcp";      Description: "Register drag-lint as an MCP server for Claude Code and VS Code"; Components: core; Flags: unchecked

[Files]
; ---- core: the engine and what it loads at start-up -------------------------
Source: "{#EngineDir}\drag-lint.exe";            DestDir: "{app}\bin"; Components: core; Flags: ignoreversion
Source: "{#EngineDir}\drag-lint-config.exe";     DestDir: "{app}\bin"; Components: core; Flags: ignoreversion
Source: "{#EngineDir}\drag-lint-switch.exe";     DestDir: "{app}\bin"; Components: core; Flags: ignoreversion
Source: "{#EngineDir}\sqlite3.dll";             DestDir: "{app}\bin"; Components: core; Flags: ignoreversion
Source: "{#EngineDir}\tree-sitter.dll";          DestDir: "{app}\bin"; Components: core; Flags: ignoreversion
Source: "{#EngineDir}\tree-sitter-delphi13.dll"; DestDir: "{app}\bin"; Components: core; Flags: ignoreversion
Source: "{#EngineDir}\tree-sitter-dfm.dll";      DestDir: "{app}\bin"; Components: core; Flags: ignoreversion
Source: "{#EngineDir}\rules\*";                  DestDir: "{app}\bin\rules"; Components: core; Flags: ignoreversion recursesubdirs createallsubdirs
; starter manifest (R2-X2): zero sections is the engine's first-run state. Never
; overwritten, never removed -- after the first run it is the user's file. In an
; all-users install it sits under Program Files, so users get modify rights on it
; (drag-lint-config.exe edits it in place).
Source: "{#RepoRoot}\installer\drag-lint.starter.json"; DestDir: "{app}\bin"; DestName: "drag-lint.json"; Components: core; Flags: onlyifdoesntexist uninsneveruninstall; Check: not IsAdminInstallMode
Source: "{#RepoRoot}\installer\drag-lint.starter.json"; DestDir: "{app}\bin"; DestName: "drag-lint.json"; Components: core; Flags: onlyifdoesntexist uninsneveruninstall; Permissions: users-modify; Check: IsAdminInstallMode
Source: "{#RepoRoot}\charts\report-pairs.example.json"; DestDir: "{app}"; Components: core; Flags: ignoreversion
; ---- optional tools ---------------------------------------------------------
Source: "{#EngineDir}\drag-lint-open.exe"; DestDir: "{app}\bin"; Components: core; Flags: ignoreversion
Source: "{#EngineDir}\ConvRulesEditor.exe";  DestDir: "{app}\bin"; Components: convrules; Flags: ignoreversion
Source: "{#EngineDir}\drag_lint_graph.exe";  DestDir: "{app}\bin"; Components: graph; Flags: ignoreversion
Source: "{#GraphvizBin}\dot.exe";  DestDir: "{app}\bin\graphviz\bin"; Components: graphviz; Flags: ignoreversion
Source: "{#GraphvizBin}\*.dll";    DestDir: "{app}\bin\graphviz\bin"; Components: graphviz; Flags: ignoreversion
Source: "{#GraphvizBin}\config8";  DestDir: "{app}\bin\graphviz\bin"; Components: graphviz; Flags: ignoreversion
; ---- IDE plugins (a BPL loads only in the IDE it was built for: 37.0) --------
Source: "{#Plugin32Dir}\dclDragLintWizard.bpl"; DestDir: "{app}\bin";     Components: plugin32; Check: InstallPlugin32; Flags: ignoreversion
Source: "{#EngineDir}\dclDragLintWizard.bpl";   DestDir: "{app}\bin\x64"; Components: plugin64; Check: InstallPlugin64; Flags: ignoreversion
; ---- YADF (owner 2026-10-13: a component; YADFSetup is its settings editor) ---
Source: "{#YadfDir}\Win64\Release\EXE\YADF.exe";      DestDir: "{app}\yadf";     Components: yadf; Flags: ignoreversion
Source: "{#YadfDir}\Win64\Release\EXE\YADFSetup.exe"; DestDir: "{app}\yadf";     Components: yadf; Flags: ignoreversion
Source: "{#YadfDir}\Win32\Release\EXE\YADFOT.bpl";    DestDir: "{app}\yadf";     Components: yadfot32; Check: InstallYadfot32; Flags: ignoreversion
Source: "{#YadfDir}\Win64\Release\EXE\YADFOT.bpl";    DestDir: "{app}\yadf\x64"; Components: yadfot64; Check: InstallYadfot64; Flags: ignoreversion
; YADF's Options-page preview sample. YADF before 1.0.19.0 looks for Demo\Sample.pas beside
; the HOST module (yadf\ serves YADFSetup.exe and the 32-bit YADFOT; the 64-bit YADFOT needs its
; own copy). Newer YADF (4b01ac1) embeds the sample and writes it once per user to
; %APPDATA%\YADF itself, so it is shipped ONLY with the old binaries -- decided at compile time
; from the packaged YADF.exe. Missing is harmless either way (a built-in snippet is shown).
; Gate: version < 1.0.19.0 (the first release that embeds it). An unreadable version SHIPS the
; copies: extra files are ignored by a new build, while a missing sample costs an old one its preview.
#define YadfPacked 0
#define YadfVerStr GetPackedVersion(YadfDir + "\Win64\Release\EXE\YADF.exe", YadfPacked)
#pragma message "YADF.exe version: " + (YadfVerStr == "" ? "unreadable" : YadfVerStr)
#if YadfVerStr == "" || YadfPacked < PackVersionComponents(1, 0, 19, 0)
Source: "{#YadfDir}\Demo\Sample.pas"; DestDir: "{app}\yadf\Demo";     Components: yadf or yadfot32; Flags: ignoreversion
Source: "{#YadfDir}\Demo\Sample.pas"; DestDir: "{app}\yadf\x64\Demo"; Components: yadfot64; Check: InstallYadfot64; Flags: ignoreversion
#endif
; ---- licences ---------------------------------------------------------------
Source: "{#RepoRoot}\installer\licenses\*.txt"; DestDir: "{app}\licenses"; Components: core; Flags: ignoreversion
Source: "{#YadfDir}\LICENSE"; DestDir: "{app}\licenses"; DestName: "YADF-LICENSE.txt"; Components: yadf; Flags: ignoreversion

[Registry]
; plugin registration: ONE value each, named by our own path; uninstall deletes
; exactly that value and never touches other Known Packages entries.
Root: HKCU; Subkey: "{#IdeKey}\Known Packages";     ValueType: string; ValueName: "{app}\bin\dclDragLintWizard.bpl";     ValueData: "drag-lint IDE plugin"; Components: plugin32; Check: InstallPlugin32; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#IdeKey}\Known Packages x64"; ValueType: string; ValueName: "{app}\bin\x64\dclDragLintWizard.bpl"; ValueData: "drag-lint IDE plugin"; Components: plugin64; Check: InstallPlugin64; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#IdeKey}\Known Packages";     ValueType: string; ValueName: "{app}\yadf\YADFOT.bpl";     ValueData: "YADF formatter"; Components: yadfot32; Check: InstallYadfot32; Flags: uninsdeletevalue
Root: HKCU; Subkey: "{#IdeKey}\Known Packages x64"; ValueType: string; ValueName: "{app}\yadf\x64\YADFOT.bpl"; ValueData: "YADF formatter"; Components: yadfot64; Check: InstallYadfot64; Flags: uninsdeletevalue
; marker: this installer registered draglint:// (read by the uninstaller)
Root: HKCU; Subkey: "{#InstKey}"; ValueType: string; ValueName: "ProtocolRegisteredBy"; ValueData: "{app}"; Tasks: protocol; Check: RegisterProtocol; Flags: uninsdeletevalue uninsdeletekeyifempty

[Run]
Filename: "{app}\bin\drag-lint.exe"; Parameters: "protocol register --handler ""{app}\bin\drag-lint-open.exe"" --force"; StatusMsg: "Registering draglint:// ..."; Tasks: protocol; Check: RegisterProtocol; Flags: runhidden runasoriginaluser waituntilterminated
Filename: "{app}\bin\drag-lint.exe"; Parameters: "mcp-config --all --engine ""{app}\bin\drag-lint.exe"""; StatusMsg: "Registering the MCP server ..."; Tasks: mcp; Flags: runhidden runasoriginaluser waituntilterminated
Filename: "{app}\yadf\YADFSetup.exe"; Description: "Open YADFSetup to choose formatting settings"; Components: yadf; Flags: postinstall nowait skipifsilent unchecked runasoriginaluser

[UninstallRun]
Filename: "{app}\bin\drag-lint.exe"; Parameters: "protocol unregister"; RunOnceId: "UnregisterProtocol"; Check: WeRegisteredProtocol; Flags: runhidden waituntilterminated
Filename: "{app}\bin\drag-lint.exe"; Parameters: "mcp-config --all --remove"; RunOnceId: "RemoveMcp"; Tasks: mcp; Flags: runhidden waituntilterminated

[Code]
{ ---- IDE detection (owner D2: offer the plugin only where RAD Studio 13 is) - }

function IdeRoot: string;
begin
  Result:= '';
  if not RegQueryStringValue(HKCU, '{#IdeKey}', 'RootDir', Result) then
    if not RegQueryStringValue(HKLM32, 'SOFTWARE\Embarcadero\BDS\{#IdeVer}', 'RootDir', Result) then
      Result:= '';
end;

function Have32BitIde: Boolean;
begin
  Result:= (IdeRoot <> '') and FileExists(AddBackslash(IdeRoot) + 'bin\bds.exe');
end;

function Have64BitIde: Boolean;
begin
  Result:= (IdeRoot <> '') and FileExists(AddBackslash(IdeRoot) + 'bin64\bds.exe');
end;

function IdeRunning: Boolean;
var
  Wmi, Svc, Procs: Variant;
begin
  Result:= False;
  try
    Wmi:= CreateOleObject('WbemScripting.SWbemLocator');
    Svc:= Wmi.ConnectServer('.', 'root\CIMV2');
    Procs:= Svc.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name = ''bds.exe''');
    Result:= Procs.Count > 0;
  except
    Result:= False;  { cannot tell -- the file copy itself fails loudly on a locked BPL }
  end;
end;

{ Another copy of the same package already registered (e.g. a developer's
  repo build) makes the IDE refuse to load one of them. Returns that path. }
function OtherRegistration(const Subkey, BplName, Ours: string): string;
var
  Names: TArrayOfString;
  I    : Integer;
begin
  Result:= '';
  if RegGetValueNames(HKCU, Subkey, Names) then
    for I:= 0 to GetArrayLength(Names) - 1 do
      if (CompareText(ExtractFileName(Names[I]), BplName) = 0) and (CompareText(Names[I], Ours) <> 0) then
      begin
        Result:= Names[I];
        Exit;
      end;
end;

{ One plugin slot: Subkey (Known Packages or Known Packages x64), the BPL file
  name, and the path this install registers. }
function SlotOther(Slot: Integer): string;
begin
  case Slot of
    0: Result:= OtherRegistration('{#IdeKey}\Known Packages',     'dclDragLintWizard.bpl', ExpandConstant('{app}\bin\dclDragLintWizard.bpl'));
    1: Result:= OtherRegistration('{#IdeKey}\Known Packages x64', 'dclDragLintWizard.bpl', ExpandConstant('{app}\bin\x64\dclDragLintWizard.bpl'));
    2: Result:= OtherRegistration('{#IdeKey}\Known Packages',     'YADFOT.bpl', ExpandConstant('{app}\yadf\YADFOT.bpl'));
  else Result:= OtherRegistration('{#IdeKey}\Known Packages x64', 'YADFOT.bpl', ExpandConstant('{app}\yadf\x64\YADFOT.bpl'));
  end;
end;

{ Whether to install the plugin in Slot. Needs its IDE. A SILENT install never
  adds a second registration of a package already registered from elsewhere --
  the IDE would refuse one of them, and nobody is there to be warned -- so it
  skips that plugin and logs why. An interactive install has already asked on
  the components page (NextButtonClick), so the user's choice stands. }
function InstallSlot(Slot: Integer): Boolean;
var
  Other: string;
begin
  if (Slot = 0) or (Slot = 2) then Result:= Have32BitIde else Result:= Have64BitIde;
  if not Result or not WizardSilent then Exit;
  Other:= SlotOther(Slot);
  if Other <> '' then
  begin
    Result:= False;
    Log('plugin slot ' + IntToStr(Slot) + ' skipped: the same package is already registered from ' + Other);
  end;
end;

function InstallPlugin32: Boolean; begin Result:= InstallSlot(0); end;
function InstallPlugin64: Boolean; begin Result:= InstallSlot(1); end;
function InstallYadfot32: Boolean; begin Result:= InstallSlot(2); end;
function InstallYadfot64: Boolean; begin Result:= InstallSlot(3); end;
{ ---- draglint:// (owner D5: ask before replacing an existing registration) - }

var
  ProtocolDecided, ProtocolOk: Boolean;

{ True when the protocol task should run: either nothing is
  registered yet or the user agreed to replace it. A silent install never
  replaces an existing registration. Asked once. }
function RegisterProtocol: Boolean;
var
  Cmd: string;
begin
  if not ProtocolDecided then
  begin
    ProtocolDecided:= True;
    ProtocolOk:= True;
    if RegQueryStringValue(HKCU, 'Software\Classes\draglint\shell\open\command', '', Cmd) then
      if WizardSilent then
        ProtocolOk:= False
      else
        ProtocolOk:= MsgBox('draglint:// links are already registered:' + #13#10 + Cmd + #13#10#13#10 +
          'Register them for this installation instead?', mbConfirmation, MB_YESNO) = IDYES;
    if not ProtocolOk then Log('draglint://: not registered by this setup');
  end;
  Result:= ProtocolOk;
end;
{ ---- the components page: grey out what this machine cannot use --------- }

function ComponentIndex(const Prefix: string): Integer;
var
  I: Integer;
begin
  Result:= -1;
  for I:= 0 to WizardForm.ComponentsList.Items.Count - 1 do
    if Pos(Prefix, WizardForm.ComponentsList.ItemCaption[I]) = 1 then
    begin
      Result:= I;
      Exit;
    end;
end;

procedure DisableComponent(const Prefix, Why: string);
var
  I: Integer;
begin
  I:= ComponentIndex(Prefix);
  if I < 0 then Exit;
  WizardForm.ComponentsList.Checked[I]:= False;
  WizardForm.ComponentsList.ItemEnabled[I]:= False;
  WizardForm.ComponentsList.ItemCaption[I]:= WizardForm.ComponentsList.ItemCaption[I] + ' -- ' + Why;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectComponents then
  begin
    if not Have32BitIde then
    begin
      DisableComponent('IDE plugin for RAD Studio 13 (32-bit', 'RAD Studio 13 not found');
      DisableComponent('YADF IDE plugin (32-bit', 'RAD Studio 13 not found');
    end;
    if not Have64BitIde then
    begin
      DisableComponent('IDE plugin for RAD Studio 13 (64-bit', '64-bit IDE not found');
      DisableComponent('YADF IDE plugin (64-bit', '64-bit IDE not found');
    end;
  end;
end;

{ Interactive only: silent installs skip the wizard pages. InstallSlot enforces
  the same two rules (IDE present, no second registration) in silent mode. }
function NextButtonClick(CurPageID: Integer): Boolean;
var
  Slot : Integer;
  Comp : array[0..3] of string;
  What : array[0..3] of string;
  Other: string;
begin
  Result:= True;
  if CurPageID <> wpSelectComponents then Exit;
  Comp[0]:= 'plugin32'; What[0]:= 'The drag-lint IDE plugin (32-bit IDE)';
  Comp[1]:= 'plugin64'; What[1]:= 'The drag-lint IDE plugin (64-bit IDE)';
  Comp[2]:= 'yadfot32'; What[2]:= 'The YADF IDE plugin (32-bit IDE)';
  Comp[3]:= 'yadfot64'; What[3]:= 'The YADF IDE plugin (64-bit IDE)';
  for Slot:= 0 to 3 do
  begin
    if not WizardIsComponentSelected(Comp[Slot]) then Continue;
    Other:= SlotOther(Slot);
    if Other = '' then Continue;
    Result:= MsgBox(What[Slot] + ' is already registered from' + #13#10 + Other + #13#10#13#10 +
      'Two copies of the same package make the IDE refuse to load one of them. Remove that entry ' +
      '(Component > Install Packages) or untick it here.' + #13#10#13#10 + 'Continue anyway?',
      mbConfirmation, MB_YESNO) = IDYES;
    if not Result then Exit;
  end;
end;
{ DEC-13 (owner 2026-10-28): replacing an engine is a CHANNEL stop first, never a kill.
  The previous install's engine is asked to hold off its respawn (ide-release) and every
  running engine (lsp, cycles --fix, index, lint-all) to stand down cleanly (shutdown --all
  --wait). An index run stops between files with its database consistent; the same command
  resumes. Whatever does not comply is left to CloseApplications (Restart Manager), the
  last resort. A missing old engine, or one older than the channel, is simply a no-op. }
procedure StopRunningEngines;
var
  Old: String;
  Rc: Integer;
begin
  Old:= ExpandConstant('{app}\bin\drag-lint.exe');
  if not FileExists(Old) then Exit;
  Exec(Old, 'ide-release --seconds 900', '', SW_HIDE, ewWaitUntilTerminated, Rc);
  Exec(Old, 'shutdown --all --wait 30', '', SW_HIDE, ewWaitUntilTerminated, Rc);
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result:= '';
  StopRunningEngines;
  if (WizardIsComponentSelected('plugin32') or WizardIsComponentSelected('plugin64') or
      WizardIsComponentSelected('yadfot32') or WizardIsComponentSelected('yadfot64')) and IdeRunning then
    Result:= 'RAD Studio is running. Close it first: it keeps the plugin BPL loaded and locked.';
end;

{ ---- settings that point at us (ask before replacing someone else's) ----- }

{ Writes Key\Value := Path when the current value is empty, dead, already Path,
  or the user agrees to replace it. A silent install never replaces a live
  value. Records the write under InstKey so the uninstaller can undo only it. }
procedure ClaimPathSetting(const Key, Value, Path, What, Marker: string);
var
  Cur: string;
  Take: Boolean;
begin
  if not RegQueryStringValue(HKCU, Key, Value, Cur) then Cur:= '';
  Take:= (Cur = '') or (CompareText(Cur, Path) = 0) or not FileExists(Cur);
  if (not Take) and not WizardSilent then
    Take:= MsgBox(What + ' currently points at' + #13#10 + Cur + #13#10#13#10 +
      'Point it at this installation instead?' + #13#10 + Path, mbConfirmation, MB_YESNO) = IDYES;
  if Take then
  begin
    RegWriteStringValue(HKCU, Key, Value, Path);
    RegWriteStringValue(HKCU, '{#InstKey}', Marker, Path);
  end
  else
    Log(What + ': kept ' + Cur);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep <> ssPostInstall then Exit;
  if (WizardIsComponentSelected('plugin32') and InstallPlugin32) or (WizardIsComponentSelected('plugin64') and InstallPlugin64) then
    ClaimPathSetting('{#PlugKey}', 'ExePath', ExpandConstant('{app}\bin\drag-lint.exe'),
      'The drag-lint IDE plugin''s engine setting', 'PluginExePath');
  if WizardIsComponentSelected('yadf') then
    ClaimPathSetting('{#YadfKey}', 'ExePath', ExpandConstant('{app}\yadf\YADF.exe'),
      'The YADF.exe setting (used by drag-lint and the YADF IDE plugin)', 'YadfExePath');
end;

{ ---- uninstall ----------------------------------------------------------- }

function InitializeUninstall: Boolean;
begin
  Result:= True;
  if IdeRunning then
  begin
    MsgBox('RAD Studio is running. Close it first: it keeps the plugin BPL loaded and locked.', mbError, MB_OK);
    Result:= False;
  end;
end;

function WeRegisteredProtocol: Boolean;
var
  By: string;
begin
  Result:= RegQueryStringValue(HKCU, '{#InstKey}', 'ProtocolRegisteredBy', By) and
           (CompareText(By, ExpandConstant('{app}')) = 0);
end;

{ Removes Key\Value only when it still holds the path we wrote. }
procedure ReleasePathSetting(const Key, Value, Marker: string);
var
  Ours, Cur: string;
begin
  if not RegQueryStringValue(HKCU, '{#InstKey}', Marker, Ours) then Exit;
  if RegQueryStringValue(HKCU, Key, Value, Cur) and (CompareText(Cur, Ours) = 0) then
    RegDeleteValue(HKCU, Key, Value);
  RegDeleteValue(HKCU, '{#InstKey}', Marker);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  ReleasePathSetting('{#PlugKey}', 'ExePath', 'PluginExePath');
  ReleasePathSetting('{#YadfKey}', 'ExePath', 'YadfExePath');
  RegDeleteKeyIfEmpty(HKCU, '{#InstKey}');
  RegDeleteKeyIfEmpty(HKCU, 'Software\drag-lint');
end;
