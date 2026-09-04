program ConvRulesEditor;

{ Standalone visual editor for drag-lint conversion.rules DSL files.
  A front-end to the existing conversion engine -- it authors/edits the rules
  file that `drag-lint convert-apply` consumes; it does NOT convert. }

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Win.Registry,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  ConvRules.Theme in 'ConvRules.Theme.pas',
  ConvRules.Model in 'ConvRules.Model.pas',
  ConvRules.Units in 'ConvRules.Units.pas',
  ConvRules.Casts in 'ConvRules.Casts.pas',
  ConvRules.CastLib in 'ConvRules.CastLib.pas',
  ConvRules.Engine in 'ConvRules.Engine.pas',
  ConvRules.Platform in 'ConvRules.Platform.pas',
  ConvRules.BlockFile in 'ConvRules.BlockFile.pas',
  ConvRules.BlockOps in 'ConvRules.BlockOps.pas',
  ConvRules.WorkingSet in 'ConvRules.WorkingSet.pas',
  ConvRules.CurationForm in 'ConvRules.CurationForm.pas',
  ConvRules.Usage in 'ConvRules.Usage.pas',
  ConvRules.Mappings in 'ConvRules.Mappings.pas',
  ConvRules.MappingForm in 'ConvRules.MappingForm.pas',
  ConvRules.MainForm in 'ConvRules.MainForm.pas';

{ VCL styles (Windows11 Modern Light / Dark) linked as VCLSTYLE resources; without
  them TStyleManager.TrySetStyle returns False and the theme menu does nothing.
  Built from ConvRulesEditorStyles.rc by the build scripts (dcc64 cannot compile a
  .rc itself -- it tries to link it as a .res and fails with E2161). Vcl.Styles,
  above, registers the resource type that makes them auto-discoverable. }
{$R ConvRulesEditorStyles.res}

{ Resolve the drag-lint exe: next to this editor (both deploy to dll-win64), else
  a couple of well-known spots. }
function ResolveDragLintExe: string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := TPath.Combine(Dir, 'drag-lint.exe');
  if TFile.Exists(Result) then Exit;
  Result := 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe';
  if TFile.Exists(Result) then Exit;
  Result := 'drag-lint.exe'; // rely on PATH
end;

{ Resolve the shipped .castlib: next to this editor (co-deployed), else the repo
  default under docs\examples\convrules, else '' (class casts unavailable). }
function ResolveCastLib: string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := TPath.Combine(Dir, 'casts.castlib');                         // (1) beside exe
  if TFile.Exists(Result) then Exit;
  Result := TPath.GetFullPath(TPath.Combine(Dir,                         // (2) repo docs
    '..\..\docs\examples\convrules\casts.castlib'));
  if TFile.Exists(Result) then Exit;
  Result := '';                                                          // (3) none
end;

{ Command line:
    --from-platform win32|win64|both   which library the FROM picker resolves against
    --to-platform   win32|win64|both   ditto for the TO picker
    --form <path>                      a .dfm/.pas to load at start-up; its sibling
                                       is loaded too, and its folder seeds the
                                       Open-form dialog
    --project-db <path>                override the project index below

  The library index directory and the project index. The FROM/TO platform (each
  selectable via --from-platform / --to-platform, default FROM=Win64, TO=Win64)
  picks which library-Win32/Win64.sqlite each side draws types from; the project
  DB (ORM3) is always-on and additive (project units + project-declared types).
  FROM defaulted to Both until 2026-07-29; library-Win32.sqlite is a 9.5 MB
  fragment that adds no names Win64 lacks, so the union only risked shadowing the
  healthy index (proptree resolves from the first --db that answers). }
const
  LibDir    = 'C:\Projects\.drag-lint\';
  { The project index carrying the app's OWN forms and types. It MOVED on
    2026-08-09: indexes are now one DB per project inside that project's own
    _D-RAG folder, and the old shared 'C:\Projects\DB\ORM3\drag-lint.sqlite' was
    DELETED. This constant still named that dead path, so project-declared types
    resolved against nothing and showed up as unindexed. Override with
    --project-db when working on a different project. }
  ProjectDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite';

{ Parse --from-platform / --to-platform (case-insensitive win32|win64|both).
  Absent -> ADefault, which the caller passes as DEFAULT_FROM_PLATFORM /
  DEFAULT_TO_PLATFORM. Scans flag/value pairs positionally. }
function ArgPlatform(const AFlag: string; ADefault: TConvPlatform): TConvPlatform;
var
  i: Integer;
begin
  Result := ADefault;
  for i := 1 to ParamCount - 1 do
    if SameText(ParamStr(i), AFlag) then
      Exit(ParsePlatform(ParamStr(i + 1), ADefault));
end;

{ The value following AFlag on the command line; '' when the flag is absent or is
  the last argument. Used by --form and --project-db. }
function ArgValue(const AFlag: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to ParamCount - 1 do
    if SameText(ParamStr(i), AFlag) then
      Exit(Trim(ParamStr(i + 1)));
end;

{ Highest installed BDS version key, e.g. '37.0'. '' when none is present. }
function HighestBdsVersion: string;
var
  Reg : TRegistry;
  Keys: TStringList;
  i   : Integer;
  Best: Double;
  v   : Double;
begin
  Result := '';
  Best := -1;
  Reg := TRegistry.Create(KEY_READ);
  Keys := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Embarcadero\BDS') then
    begin
      Reg.GetKeyNames(Keys);
      for i := 0 to Keys.Count - 1 do
        if TryStrToFloat(Keys[i], v, TFormatSettings.Invariant) and (v > Best) then
        begin
          Best := v;
          Result := Keys[i];
        end;
    end;
  finally
    Keys.Free;
    Reg.Free;
  end;
end;

{ The IDE's own theme name, '' when unreadable. '' resolves to light -- see
  ConvRules.Theme.IdeThemeToMode for why that is the safe default. }
function ReadIdeTheme: string;
var
  Reg: TRegistry;
  Ver: string;
begin
  Result := '';
  Ver := HighestBdsVersion;
  if Ver = '' then Exit;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Embarcadero\BDS\' + Ver + '\Theme') then
      if Reg.ValueExists('Theme') then Result := Reg.ReadString('Theme');
  finally
    Reg.Free;
  end;
end;

{ The user's stored theme preference; tpFollowIde when absent or unrecognised.
  Written back by the form's View > Theme menu (TConvRulesForm.SetThemePref). }
function ReadThemePref: TThemePref;
var
  Reg: TRegistry;
begin
  Result := tpFollowIde;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(EDITOR_REG_KEY) then
      if Reg.ValueExists(EDITOR_REG_THEME) then
        Result := StrToThemePref(Reg.ReadString(EDITOR_REG_THEME), tpFollowIde);
  finally
    Reg.Free;
  end;
end;

var
  Form: TConvRulesForm;
begin
  // Config the globals BEFORE CreateForm (the form's constructor reads them).
  GEditorExe          := ResolveDragLintExe;
  GEditorLibDir       := LibDir;
  GEditorProjectDb    := ArgValue('--project-db');
  if GEditorProjectDb = '' then GEditorProjectDb := ProjectDb;
  GEditorFormPath     := ArgValue('--form');
  GEditorCastLib      := ResolveCastLib;
  GEditorFromPlatform := ArgPlatform('--from-platform', DEFAULT_FROM_PLATFORM);
  GEditorToPlatform   := ArgPlatform('--to-platform', DEFAULT_TO_PLATFORM);
  // Theme: read the IDE's setting and the stored preference here, so the form's
  // constructor can apply the resolved mode before anything is painted.
  GEditorIdeTheme     := ReadIdeTheme;
  GEditorThemePref    := ReadThemePref;
  Application.Initialize;
  Application.Title := 'ConvRulesEditor';
  Application.MainFormOnTaskbar := True;
  // CreateForm makes this the MainForm -> Application.Run's loop stays alive
  // (a manually-shown CreateNew form does not, and Run returns immediately).
  Application.CreateForm(TConvRulesForm, Form);
  // Open a file passed on the command line -- but only when ParamStr(1) is a real
  // path, not a '--flag' or a platform-flag value, so mixing a file with the
  // platform flags does not misfire. (A file after the flags is not auto-opened;
  // launch with the file first, or flags only.)
  if (ParamCount >= 1) and (not ParamStr(1).StartsWith('--'))
     and (not SameText(ParamStr(1), 'win32')) and (not SameText(ParamStr(1), 'win64'))
     and (not SameText(ParamStr(1), 'both')) then
    try
      Form.LoadFile(ParamStr(1));
    except
      on E: Exception do
        Application.MessageBox(PChar('Could not open ' + ParamStr(1) + #13#10 +
          E.ClassName + ': ' + E.Message), 'ConvRulesEditor', 0);
    end;
  Application.Run;
end.
