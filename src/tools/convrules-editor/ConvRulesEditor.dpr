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

{ Default index DBs to resolve property trees from. Prefer the manifest via the
  engine's own resolution when no --db given, but the editor passes an explicit
  set so property trees resolve for library types too. }
function DefaultDbs: TArray<string>;
begin
  Result := [
    'C:\Projects\.drag-lint\library-Win32.sqlite',
    'C:\Projects\DB\ORM3\drag-lint.sqlite'
  ];
end;

var
  Form: TConvRulesForm;
begin
  // Config the globals BEFORE CreateForm (the form's constructor reads them).
  GEditorExe := ResolveDragLintExe;
  GEditorDbs := DefaultDbs;
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
