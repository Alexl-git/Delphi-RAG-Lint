program HandlersCond;

{ check-init fixture handlers-cond (lane HBEVORD): TCondForm is created only under an `if`, so its
  handler is not ordered (MAY-BE-UNSET); TBaseForm is created unconditionally inside try..finally, so
  its handler is ordered after the prefix (SET, relied-on-handler-order). Both read GCond, written
  before Application.Run. }

uses
  Vcl.Forms,
  hcData in 'hcData.pas',
  hcForms in 'hcForms.pas' {BaseForm},
  hcCond in 'hcCond.pas' {CondForm};

begin
  Application.Initialize;
  try
    Application.CreateForm(TBaseForm, BaseForm);
  finally
    GCond:= 1;
  end;
  if ParamCount > 0 then
    Application.CreateForm(TCondForm, CondForm);
  Application.Run;
end.
