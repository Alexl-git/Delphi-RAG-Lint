program InitOrder;

// E18 T5 fixture: circular-demo's three-unit ROUTINE-CALL cycle
// (DemoBlueprint -> DemoBlueprint.ViewModel -> DemoControlPlan -> DemoBlueprint,
// all implementation edges) plus an initialization section in
// DemoBlueprint that calls Show, so the routine-call inversion must refuse (init-order).

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