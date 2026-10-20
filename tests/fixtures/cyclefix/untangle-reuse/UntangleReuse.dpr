program UntangleReuse;

// E18 T4b fixture: circular-demo's four-unit INTERFACE cycle
// (DemoConfig -> DemoLogger -> DemoSession -> DemoAudit -> DemoConfig) plus
// an existing leaf unit DemoAudit.Untangle that the cycle does not use.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DemoAudit in 'DemoAudit.pas',
  DemoSession in 'DemoSession.pas',
  DemoLogger in 'DemoLogger.pas',
  DemoConfig in 'DemoConfig.pas',
  DemoAudit.Untangle in 'DemoAudit.Untangle.pas';

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
