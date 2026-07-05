program Demo4;
uses
  Vcl.Forms,
  uRoot4 in 'uRoot4.pas' {frmRoot4},
  uPlanIntf4 in 'uPlanIntf4.pas',
  uPlans4 in 'uPlans4.pas',
  uDirect4 in 'uDirect4.pas' {frmDirect4},
  uHooked4 in 'uHooked4.pas' {frmHooked4},
  uHookReg4 in 'uHookReg4.pas';

begin
  Application.Initialize;
  Application.CreateForm(TfrmRoot4, frmRoot4);
  Application.Run;
end.
