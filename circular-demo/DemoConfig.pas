unit DemoConfig;

// CYCLE ROLE: interface edge DemoConfig -> DemoLogger.
// TDemoSettings has a TDemoLogLevel field, so the dependency genuinely
// belongs in the INTERFACE and cannot be pushed down to the implementation.

interface

uses
  System.SysUtils,
  DemoLogger;

type
  /// <summary>Whole-process configuration, loaded once at start-up.</summary>
  /// <remarks>Held in the shared global <c>GDemoSettings</c>; DemoAudit reads
  /// it back through its implementation-level uses clause.</remarks>
  TDemoSettings = record
    /// <summary>Product name shown in reports.</summary>
    AppName: string;
    /// <summary>Deployment environment, e.g. dev / staging / prod.</summary>
    Environment: string;
    /// <summary>Lowest severity DemoLogger should print.</summary>
    MinLevel: TDemoLogLevel;
    /// <summary>How long the audit trail is nominally kept.</summary>
    RetainDays: Integer;
  end;

var
  /// <summary>The one settings record. Written here, read by DemoAudit.</summary>
  GDemoSettings: TDemoSettings;

/// <summary>Populates <c>GDemoSettings</c> and pushes the log level into
/// DemoLogger.</summary>
/// <param name="pEnvironment">Environment name; 'prod' raises the log level
/// to warnings only.</param>
/// <remarks>Writes the shared global <c>GDemoMinLevel</c> that lives in
/// DemoLogger.</remarks>
procedure DemoConfigLoad(const pEnvironment: string);

/// <summary>Describes the loaded configuration and logging activity.</summary>
/// <returns>One summary line, including <c>GDemoLogCount</c> read back from
/// DemoLogger.</returns>
function DemoConfigDescribe: string;

implementation

procedure DemoConfigLoad(const pEnvironment: string);
begin
  GDemoSettings.AppName := 'CircularDemo';
  GDemoSettings.Environment := pEnvironment;
  GDemoSettings.RetainDays := if SameText(pEnvironment, 'prod') then 365 else 7;
  GDemoSettings.MinLevel := if SameText(pEnvironment, 'prod') then llWarn
    else llInfo;

  // Push the configured level into DemoLogger's global.
  GDemoMinLevel := GDemoSettings.MinLevel;

  DemoLog(llInfo, Format('config loaded: env=%s minLevel=%s retain=%dd',
    [GDemoSettings.Environment, DemoLogLevelName(GDemoSettings.MinLevel),
     GDemoSettings.RetainDays]));
end;

function DemoConfigDescribe: string;
begin
  // Reads GDemoLogCount, the counter that lives over in DemoLogger.
  Result := Format('[config] %s on %s, %d log line(s) emitted at %s or above',
    [GDemoSettings.AppName, GDemoSettings.Environment, GDemoLogCount,
     DemoLogLevelName(GDemoMinLevel)]);
end;

end.
