program ConvRulesEditor;

{ Standalone visual editor for drag-lint conversion.rules DSL files.
  A front-end to the existing conversion engine -- it authors/edits the rules
  file that `drag-lint convert-apply` consumes; it does NOT convert. }

uses
  System.SysUtils,
  System.IOUtils,
  Vcl.Forms,
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
  ConvRules.MainForm in 'ConvRules.MainForm.pas';

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

{ The library index directory and the project index. The FROM/TO platform (each
  selectable via --from-platform / --to-platform, default FROM=Both, TO=Win64)
  picks which library-Win32/Win64.sqlite each side draws types from; the project
  DB (ORM3) is always-on and additive (project units + project-declared types). }
const
  LibDir    = 'C:\Projects\.drag-lint\';
  ProjectDb = 'C:\Projects\DB\ORM3\drag-lint.sqlite';

{ Parse --from-platform / --to-platform (case-insensitive win32|win64|both).
  Absent -> ADefault, which the caller sets so the defaults reproduce today's
  behavior (FROM=Both, TO=Win64). Scans flag/value pairs positionally. }
function ArgPlatform(const AFlag: string; ADefault: TConvPlatform): TConvPlatform;
var
  i: Integer;
begin
  Result := ADefault;
  for i := 1 to ParamCount - 1 do
    if SameText(ParamStr(i), AFlag) then
      Exit(ParsePlatform(ParamStr(i + 1), ADefault));
end;

var
  Form: TConvRulesForm;
begin
  // Config the globals BEFORE CreateForm (the form's constructor reads them).
  GEditorExe          := ResolveDragLintExe;
  GEditorLibDir       := LibDir;
  GEditorProjectDb    := ProjectDb;
  GEditorCastLib      := ResolveCastLib;
  GEditorFromPlatform := ArgPlatform('--from-platform', cpBoth);
  GEditorToPlatform   := ArgPlatform('--to-platform', cpWin64);
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
