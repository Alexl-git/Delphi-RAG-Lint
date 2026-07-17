program ConvRulesEditor;

{ Standalone visual editor for drag-lint conversion.rules DSL files.
  A front-end to the existing conversion engine -- it authors/edits the rules
  file that `drag-lint convert-apply` consumes; it does NOT convert. }

uses
  System.SysUtils,
  System.IOUtils,
  Vcl.Forms,
  ConvRules.Model in 'ConvRules.Model.pas',
  ConvRules.Casts in 'ConvRules.Casts.pas',
  ConvRules.Engine in 'ConvRules.Engine.pas',
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

{ The per-platform library indexes and the project index. FROM lists the UNION of
  Win32+Win64 libraries -- the user is converting a Win32 app to Win64, and some
  legacy source components resolve in only ONE platform's library (e.g. Orpheus
  TOvcTable is indexed under Win64 only). The project DB (ORM3) supplies project
  units + any project-declared types. }
const
  LibWin32   = 'C:\Projects\.drag-lint\library-Win32.sqlite';
  LibWin64   = 'C:\Projects\.drag-lint\library-Win64.sqlite';
  ProjectDb  = 'C:\Projects\DB\ORM3\drag-lint.sqlite';

{ DBs the FROM picker + property-tree/validate resolution query: BOTH libraries
  (union) + the project DB, so every source type -- visual or not, Win32- or
  Win64-only -- can be listed and its property tree resolved. }
function FromDbs: TArray<string>;
begin
  Result := [LibWin32, LibWin64, ProjectDb];
end;

{ DBs the TO picker queries: only the TARGET platform's library + the project DB.
  The target is Win64 (the app is being migrated to Win64), so conversions target
  Win64 controls. }
function ToDbs: TArray<string>;
begin
  Result := [LibWin64, ProjectDb];
end;

{ Combined set used by the engine adapter's default DbArgs -- proptree/scaffold/
  validate need to resolve BOTH source (FROM) and target (TO) types, so it is the
  union of both platform libs + the project DB. }
function DefaultDbs: TArray<string>;
begin
  Result := [LibWin32, LibWin64, ProjectDb];
end;

var
  Form: TConvRulesForm;
begin
  // Config the globals BEFORE CreateForm (the form's constructor reads them).
  GEditorExe := ResolveDragLintExe;
  GEditorDbs := DefaultDbs;   // engine default: proptree/scaffold/validate (both platforms)
  GEditorFromDbs := FromDbs;  // FROM picker: Win32+Win64 lib union + project
  GEditorToDbs := ToDbs;      // TO picker: target-platform (Win64) lib + project
  Application.Initialize;
  Application.Title := 'ConvRulesEditor';
  Application.MainFormOnTaskbar := True;
  // CreateForm makes this the MainForm -> Application.Run's loop stays alive
  // (a manually-shown CreateNew form does not, and Run returns immediately).
  Application.CreateForm(TConvRulesForm, Form);
  // Open a file passed on the command line -- guarded so a load-time exception
  // surfaces as a dialog rather than tearing down the app before Run.
  if ParamCount >= 1 then
    try
      Form.LoadFile(ParamStr(1));
    except
      on E: Exception do
        Application.MessageBox(PChar('Could not open ' + ParamStr(1) + #13#10 +
          E.ClassName + ': ' + E.Message), 'ConvRulesEditor', 0);
    end;
  Application.Run;
end.
