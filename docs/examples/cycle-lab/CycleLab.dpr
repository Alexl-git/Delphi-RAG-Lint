program CycleLab;

// ---------------------------------------------------------------------------
// Three circular unit dependencies that STILL COMPILE, for demonstrating
// drag-lint's cycle report. Each is a different shape:
//
// 1. Four units, INTERFACE-coupled, closed by one implementation edge and
//    kept alive by shared global constants / variables:
//
//      DemoConfig  -> DemoLogger   (interface uses)
//      DemoLogger  -> DemoSession  (interface uses)
//      DemoSession -> DemoAudit    (interface uses)
//      DemoAudit   -> DemoConfig   (IMPLEMENTATION uses)   <-- legal edge
//
// 2. Three units, implementation-only, whose only cheap cut is a ROUTINE
//    CALL (DemoBlueprint -> DemoBlueprint.ViewModel; see DemoBlueprint.pas).
//
// 3. Two units, implementation-only, whose only cheap cut is a MEMBER
//    ACCESS through `is` / `as` (DemoUIConnect -> DemoGagePort; see
//    DemoGagePort.pas).
//
// Delphi rejects a cycle only when every edge sits in an INTERFACE uses
// clause, so all three compile.
// ---------------------------------------------------------------------------

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DemoAudit in 'DemoAudit.pas',
  DemoSession in 'DemoSession.pas',
  DemoLogger in 'DemoLogger.pas',
  DemoConfig in 'DemoConfig.pas',
  DemoBlueprint.Interfaces in 'DemoBlueprint.Interfaces.pas',
  DemoBlueprint in 'DemoBlueprint.pas',
  DemoBlueprint.ViewModel in 'DemoBlueprint.ViewModel.pas',
  DemoControlPlan in 'DemoControlPlan.pas',
  DemoGagePort in 'DemoGagePort.pas',
  DemoUIConnect in 'DemoUIConnect.pas',
  LabCtorOwner in 'LabCtorOwner.pas',
  LabCtorChild in 'LabCtorChild.pas',
  LabClsRegistry in 'LabClsRegistry.pas',
  LabClsWidget in 'LabClsWidget.pas',
  LabExcHost in 'LabExcHost.pas',
  LabExcWidget in 'LabExcWidget.pas',
  LabRcHost in 'LabRcHost.pas',
  LabRcWidget in 'LabRcWidget.pas',
  LabVarHost in 'LabVarHost.pas',
  LabVarWidget in 'LabVarWidget.pas',
  LabInitConsumer in 'LabInitConsumer.pas',
  LabInitSink in 'LabInitSink.pas',
  LabDirA in 'LabDirA.pas',
  LabDirB in 'LabDirB.pas',
  LabIncA in 'LabIncA.pas',
  LabIncB in 'LabIncB.pas',
  LabGuardA in 'LabGuardA.pas',
  LabGuardB in 'LabGuardB.pas';

var
  GSession: TDemoSession;
  GDrawing: TDemoBlueprint;
  GPort: TDemoGagePort;
  I: Integer;

begin
  try
    DemoAuditInit;
    try
      DemoConfigLoad('staging');

      GSession := DemoSessionOpen('alexanderl');
      try
        GSession.Note(akWork, 'reindexed 4 units');
        DemoLogSession(GSession, llWarn, 'unit graph contains a cycle');
        GSession.Note(akWork, 'wrote cycle report');
        DemoLog(llDebug, 'this line is below the configured level');
      finally
        DemoSessionClose;
      end;

      Writeln(GDemoAuditTrail.Summary);
      Writeln(DemoConfigDescribe);
    finally
      DemoAuditDone;
    end;

    // Cycle 2: the routine-call shape.
    GDrawing := TDemoBlueprint.CreateForFolder(7);
    try
      GDrawing.Show;
      GDrawing.OpenControlPlan;
    finally
      GDrawing.Free;
    end;

    // Cycle 3: the member-access shape.
    GPort := TDemoGagePort.Create(nil);
    try
      GPort.ReadGage(42);
      GPort.ReadGage(43);
      for I := 0 to GPort.Log.Count - 1 do
        Writeln('[gageport] ', GPort.Log[I]);
    finally
      GPort.Free;
    end;

    // Lab cases (see README.md): the units are linked; two of them also run.
    with TLabCtorOwner.Create do
      try
        Poke;
      finally
        Free;
      end;
    LabClsRunAll;
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.
