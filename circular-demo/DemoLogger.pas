unit DemoLogger;

// CYCLE ROLE: interface edge DemoLogger -> DemoSession.
// DemoLogSession takes a TDemoSession parameter, so the dependency genuinely
// belongs in the INTERFACE and cannot be pushed down to the implementation.

interface

uses
  System.SysUtils,
  DemoSession;

type
  /// <summary>Severity of a log line, ordered from least to most severe.</summary>
  TDemoLogLevel = (llDebug, llInfo, llWarn, llError);

var
  /// <summary>Lowest severity that is actually printed. Written by DemoConfig,
  /// read here.</summary>
  GDemoMinLevel: TDemoLogLevel = llInfo;
  /// <summary>Lines printed so far. Written here, read by DemoConfig.</summary>
  GDemoLogCount: Integer = 0;

/// <summary>Returns the four-character display name of a severity.</summary>
/// <param name="pLevel">Severity to name.</param>
/// <returns>One of DBUG, INFO, WARN, ERR.</returns>
function DemoLogLevelName(const pLevel: TDemoLogLevel): string;

/// <summary>Prints one line, attributed to the globally active session.</summary>
/// <param name="pLevel">Severity; suppressed when below <c>GDemoMinLevel</c>.</param>
/// <param name="pText">Message body.</param>
/// <remarks>Reads the shared globals <c>GDemoActiveSession</c> and
/// <c>GDemoSessionCount</c>, both declared in DemoSession.</remarks>
procedure DemoLog(const pLevel: TDemoLogLevel; const pText: string);

/// <summary>Prints one line attributed to an explicit session.</summary>
/// <param name="pSession">Session to attribute the line to; may be nil.</param>
/// <param name="pLevel">Severity; suppressed when below <c>GDemoMinLevel</c>.</param>
/// <param name="pText">Message body.</param>
procedure DemoLogSession(const pSession: TDemoSession;
  const pLevel: TDemoLogLevel; const pText: string);

implementation

const
  CLevelName: array [TDemoLogLevel] of string = ('DBUG', 'INFO', 'WARN', 'ERR ');

function DemoLogLevelName(const pLevel: TDemoLogLevel): string;
begin
  Result := CLevelName[pLevel];
end;

procedure DemoLogSession(const pSession: TDemoSession;
  const pLevel: TDemoLogLevel; const pText: string);
var
  LWho: string;
  LId: Integer;
begin
  if pLevel < GDemoMinLevel then
    Exit;
  LWho := if pSession = nil then '-' else pSession.User;
  LId := if pSession = nil then 0 else pSession.Id;
  Writeln(Format('[%s] (s%d/%d %s) %s',
    [DemoLogLevelName(pLevel), LId, GDemoSessionCount, LWho, pText]));
  Inc(GDemoLogCount);
end;

procedure DemoLog(const pLevel: TDemoLogLevel; const pText: string);
begin
  DemoLogSession(GDemoActiveSession, pLevel, pText);
end;

end.
