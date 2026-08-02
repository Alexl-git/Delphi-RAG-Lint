program PrinterCrashRepro;

{ Minimal repro for a RAD Studio designer crash: a datamodule (DMStyles) hosts a
  TdxComponentPrinter whose TdxGridReportLink targets a cxGrid on ANOTHER form
  (Form2). The main ribbon form (Form1) USES DMStyles. Opening Form1 in the
  designer crashes the IDE while resolving the cross-module report link.

  REPRO STEPS: build once so all forms exist, then in the IDE open Unit1
  (Form1) in the FORM DESIGNER -> the IDE crashes. See README.txt. }

uses
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {Form1},
  Unit2 in 'Unit2.pas' {Form2},
  DMStyles in 'DMStyles.pas' {dmReproStyles: TDataModule};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TdmStyles, dmReproStyles);
  Application.CreateForm(TForm2, Form2);
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
