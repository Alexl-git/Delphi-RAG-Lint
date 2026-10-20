program SigInCycle;

// E18 T5 fixture: circular-demo's three-unit ROUTINE-CALL cycle
// (DemoBlueprint -> DemoBlueprint.ViewModel -> DemoControlPlan -> DemoBlueprint,
// all implementation edges) where the routine returns
// TDemoBlueprintViewModel, a class of the cycle, so the inversion must refuse (signature-in-cycle).

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DemoBlueprint.Interfaces in 'DemoBlueprint.Interfaces.pas',
  DemoBlueprint in 'DemoBlueprint.pas',
  DemoBlueprint.ViewModel in 'DemoBlueprint.ViewModel.pas',
  DemoControlPlan in 'DemoControlPlan.pas';

var
  GDrawing: TDemoBlueprint;

begin
  try
    GDrawing := TDemoBlueprint.CreateForFolder(7);
    try
      GDrawing.Show;
      GDrawing.OpenControlPlan;
    finally
      GDrawing.Free;
    end;
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.