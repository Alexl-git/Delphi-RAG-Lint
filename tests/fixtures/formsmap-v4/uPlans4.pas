unit uPlans4;
interface
uses uPlanIntf4;
type
  TThingHookProc = procedure;

  TDirectPlan4 = class(TInterfacedObject, IThingPlan4)
    procedure EditThing;
  end;

  THookPlan4 = class(TInterfacedObject, IThingPlan4)
    procedure EditThing;
  end;

var
  ThingHook: TThingHookProc;

implementation
uses uDirect4;

procedure TDirectPlan4.EditThing;
begin
  TfrmDirect4.Create(nil).ShowModal;
end;

procedure THookPlan4.EditThing;
begin
  ThingHook();
end;

end.
