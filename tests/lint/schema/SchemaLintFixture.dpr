program SchemaLintFixture;

{ Lane FR-LINT fixture project for schema-maxlen-drift / schema-length-bound
  (tests\autotest\run_lint_schema_rules.ps1). Indexed, never built. }

uses
  Vcl.Forms,
  uMaxLen in 'uMaxLen.pas',
  uBounds in 'uBounds.pas',
  fMain in 'fMain.pas' {frmMain},
  uLimits in 'uLimits.pas',
  uShadow in 'uShadow.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
