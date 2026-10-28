unit DemoSession;

// CYCLE ROLE: interface edge DemoSession -> DemoAudit.
// TDemoSession.Note takes a TDemoAuditKind, so the dependency genuinely
// belongs in the INTERFACE and cannot be pushed down to the implementation.

interface

uses
  System.SysUtils,
  DemoAudit;

type
  /// <summary>One user session; writes to the global audit trail.</summary>
  /// <remarks>
  ///   Created and released through <c>DemoSessionOpen</c> /
  ///   <c>DemoSessionClose</c>, which also maintain the shared globals
  ///   <c>GDemoSessionCount</c> and <c>GDemoActiveSession</c>.
  /// </remarks>
  TDemoSession = class
  private
    FId: Integer;
    FUser: string;
    FIsOpen: Boolean;
    FAuditAtOpen: Integer;
  public
    /// <summary>Opens a session for the given user and audits the event.</summary>
    /// <param name="pUser">Account name; used verbatim in audit entries.</param>
    constructor Create(const pUser: string);
    /// <summary>Closes the session if still open, then frees it.</summary>
    destructor Destroy; override;
    /// <summary>Appends an audit entry attributed to this session.</summary>
    /// <param name="pKind">Entry classification.</param>
    /// <param name="pText">What happened.</param>
    procedure Note(const pKind: TDemoAuditKind; const pText: string);
    /// <summary>Marks the session closed and audits the event.</summary>
    procedure Close;
    /// <summary>Audit entries appended since this session opened.</summary>
    /// <returns>Delta of the global <c>GDemoAuditCount</c> since Create.</returns>
    function AuditEntriesSeen: Integer;
    /// <summary>Sequence number assigned at open time.</summary>
    property Id: Integer read FId;
    /// <summary>Account name the session was opened for.</summary>
    property User: string read FUser;
    /// <summary>True until <c>Close</c> has run.</summary>
    property IsOpen: Boolean read FIsOpen;
  end;

var
  /// <summary>Sessions opened so far. Written here, read by DemoLogger.</summary>
  GDemoSessionCount: Integer = 0;
  /// <summary>Session currently in scope, or nil. Read by DemoLogger.</summary>
  GDemoActiveSession: TDemoSession = nil;

/// <summary>Opens a session and publishes it as the active one.</summary>
/// <param name="pUser">Account name.</param>
/// <returns>The new session; owned by this unit, not by the caller.</returns>
function DemoSessionOpen(const pUser: string): TDemoSession;
/// <summary>Closes and frees the active session, if any.</summary>
procedure DemoSessionClose;

implementation

constructor TDemoSession.Create(const pUser: string);
begin
  inherited Create;
  Inc(GDemoSessionCount);
  FId := GDemoSessionCount;
  FUser := pUser;
  FIsOpen := True;
  FAuditAtOpen := GDemoAuditCount;
  Note(akOpen, Format('session %d opened for %s', [FId, FUser]));
end;

destructor TDemoSession.Destroy;
begin
  if FIsOpen then
    Close;
  inherited Destroy;
end;

procedure TDemoSession.Note(const pKind: TDemoAuditKind; const pText: string);
begin
  if GDemoAuditTrail <> nil then
    GDemoAuditTrail.Add(pKind, pText);
end;

procedure TDemoSession.Close;
begin
  if not FIsOpen then
    Exit;
  FIsOpen := False;
  Note(akClose, Format('session %d closed after %d audit entries',
    [FId, AuditEntriesSeen]));
end;

function TDemoSession.AuditEntriesSeen: Integer;
begin
  Result := GDemoAuditCount - FAuditAtOpen;
end;

function DemoSessionOpen(const pUser: string): TDemoSession;
begin
  DemoSessionClose;
  Result := TDemoSession.Create(pUser);
  GDemoActiveSession := Result;
end;

procedure DemoSessionClose;
begin
  if GDemoActiveSession = nil then
    Exit;
  try
    GDemoActiveSession.Close;
  finally
    FreeAndNil(GDemoActiveSession);
  end;
end;

end.
