program BaseVar;

// E18 T7 fixture (F5, the mvBase gate): the circular-demo 4-unit cycle, except
// that DemoLogSession takes `var pSession: TDemoSession` (DemoLogger.pas lines
// 40 and 53). A var parameter cannot switch to the extracted base class, so
// Part A must refuse `base-class` naming DemoLogger.pas.

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
  DemoAuditInit;
  try
    DemoConfigLoad('staging');
    GSession := DemoSessionOpen('alexanderl');
    try
      DemoLogSession(GSession, llWarn, 'unit graph contains a cycle');
    finally
      DemoSessionClose;
    end;
  finally
    DemoAuditDone;
  end;
end.