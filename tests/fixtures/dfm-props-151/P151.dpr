program P151;
uses
  Vcl.Forms,
  uP151Main in 'uP151Main.pas' {frmP151Main},
  uP151Dlg in 'uP151Dlg.pas' {frmP151Dlg},
  uP151Act in 'uP151Act.pas' {frmP151Act},
  uP151Child in 'uP151Child.pas' {frmP151Child},
  uP151Mdi in 'uP151Mdi.pas' {frmP151Mdi},
  uP151Help in 'uP151Help.pas' {frmP151Help},
  uP151Help2 in 'uP151Help2.pas' {frmP151Help2},
  uP151Hooks in 'uP151Hooks.pas';
begin
  Application.Initialize;
  Application.CreateForm(TfrmP151Main, frmP151Main);
  Application.Run;
end.