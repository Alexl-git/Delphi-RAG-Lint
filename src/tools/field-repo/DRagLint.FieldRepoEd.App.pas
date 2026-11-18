unit DRagLint.FieldRepoEd.App;

{ drag-lint 1.52 -- lane TTD: command line of the field repository editor (dl-field-repo.exe).

    dl-field-repo.exe [--repo <file.dlrepo>]     open the editor (asks for the file when omitted)
    dl-field-repo.exe --selftest                 run the built-in checks, exit 0 / 1

  The same code is compiled into the DevExpress build (dl-field-repo.exe, default) and the
  TDBGrid build (dl-field-repo-std.exe); see DRagLint.FieldRepoEd.Grid. }

interface

/// <summary>Parses the command line and runs the editor or the self test.</summary>
/// <returns>The process exit code: 0 ok, 1 failed self test or unusable repository.</returns>
function RunEditorApp: Integer;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Vcl.Dialogs,
  Winapi.Windows,
  DRagLint.FieldRepoEd.Form,
  DRagLint.FieldRepoEd.SelfTest;

const
  OPT_SELFTEST = '--selftest';
  OPT_REPO = '--repo';
  REPO_FILTER = 'Field repository (*.dlrepo)|*.dlrepo|All files (*.*)|*.*';

function ArgValue(const pName: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), pName) then
      Exit(ParamStr(I + 1));
end;

function HasArg(const pName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), pName) then
      Exit(True);
end;

function PickRepoFile: string;
var
  Dlg: TOpenDialog;
begin
  Result := '';
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := REPO_FILTER;
    if Dlg.Execute then
      Result := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

function RunEditor: Integer;
var
  FileName: string;
  Form: TRepoEditorForm;
begin
  Result := 0;
  FreeConsole;
  Application.Initialize;
  FileName := ArgValue(OPT_REPO);
  if FileName = '' then
    FileName := PickRepoFile;
  if FileName = '' then
    Exit;
  try
    Form := TRepoEditorForm.CreateEditor(Application);
    Form.OpenRepo(FileName);
    Form.ShowModal;
  except
    on E: Exception do
    begin
      Application.MessageBox(PChar(E.Message), 'drag-lint field repository', MB_OK or MB_ICONERROR);
      Result := 1;
    end;
  end;
end;

function RunEditorApp: Integer;
begin
  Result := if HasArg(OPT_SELFTEST) then RunEditorSelfTest else RunEditor;
end;

end.
