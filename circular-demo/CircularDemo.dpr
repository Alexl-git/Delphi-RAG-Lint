program CircularDemo;

// ---------------------------------------------------------------------------
// A four-unit circular dependency that STILL COMPILES, for demonstrating
// drag-lint's cycle report.
//
//   DemoConfig  -> DemoLogger   (interface uses)
//   DemoLogger  -> DemoSession  (interface uses)
//   DemoSession -> DemoAudit    (interface uses)
//   DemoAudit   -> DemoConfig   (IMPLEMENTATION uses)   <-- legal edge
//
// Every unit also publishes mutable globals that other units in the cycle
// read or write, which is what makes such a knot expensive to untangle.
// ---------------------------------------------------------------------------

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DemoAudit in 'DemoAudit.pas',
  DemoSession in 'DemoSession.pas',
  DemoLogger in 'DemoLogger.pas',
  DemoConfig in 'DemoConfig.pas';

var
  GSession: TDemoSession;

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
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.
