unit uHookReg4;
interface
implementation
uses uPlans4, uHooked4;

procedure ShowThing4;
begin
  TfrmHooked4.Create(nil).ShowModal;
end;

initialization
  uPlans4.ThingHook := ShowThing4;
end.
