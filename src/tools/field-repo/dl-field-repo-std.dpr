program dl_field_repo_std;

{$APPTYPE CONSOLE}

{ drag-lint 1.52 -- lane TTD: field repository editor, TDBGrid fallback build (no DevExpress
  needed; DL_DEVEX is not defined). The default shipped build is dl-field-repo.dpr. }

uses
  Vcl.Forms,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.VCLUI.Wait,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema in '..\..\sql\DRagLint.FieldRepo.Schema.pas',
  DRagLint.FieldRepo.TextBackup in '..\..\sql\DRagLint.FieldRepo.TextBackup.pas',
  DRagLint.FieldRepoEd.Grid in 'DRagLint.FieldRepoEd.Grid.pas',
  DRagLint.FieldRepoEd.Form in 'DRagLint.FieldRepoEd.Form.pas',
  DRagLint.FieldRepoEd.SelfTest in 'DRagLint.FieldRepoEd.SelfTest.pas',
  DRagLint.FieldRepoEd.App in 'DRagLint.FieldRepoEd.App.pas';

begin
  Halt(RunEditorApp);
end.
