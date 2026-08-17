unit DemoAudit;

// ---------------------------------------------------------------------------
// CYCLE ROLE: this unit CLOSES the cycle.
//
//   DemoConfig  -> DemoLogger   (interface)
//   DemoLogger  -> DemoSession  (interface)
//   DemoSession -> DemoAudit    (interface)
//   DemoAudit   -> DemoConfig   (IMPLEMENTATION)  <-- the legal edge
//
// Delphi rejects a cycle only when every edge sits in an INTERFACE uses
// clause. Because the closing edge below is in the IMPLEMENTATION uses
// clause, this genuine four-unit cycle still compiles.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils,
  System.Classes;

type
  /// <summary>Classification recorded with each audit entry.</summary>
  TDemoAuditKind = (akOpen, akWork, akClose);

  /// <summary>Append-only, in-memory audit trail.</summary>
  /// <remarks>
  ///   Not thread-safe; the demo is single-threaded. The instance owned by
  ///   <c>GDemoAuditTrail</c> is created by <c>DemoAuditInit</c> and released
  ///   by <c>DemoAuditDone</c>.
  /// </remarks>
  TDemoAuditTrail = class
  private
    FEntries: TStringList;
    function GetCount: Integer;
  public
    /// <summary>Creates an empty trail.</summary>
    constructor Create;
    /// <summary>Releases the backing storage.</summary>
    destructor Destroy; override;
    /// <summary>Appends one entry and bumps the global entry counter.</summary>
    /// <param name="pKind">Entry classification.</param>
    /// <param name="pText">Free-form description of what happened.</param>
    /// <remarks>Also increments the shared global <c>GDemoAuditCount</c>.</remarks>
    procedure Add(const pKind: TDemoAuditKind; const pText: string);
    /// <summary>Renders a one-line summary of the trail.</summary>
    /// <returns>Summary text built from the global settings record that lives
    /// in DemoConfig -- the read that forces the cycle-closing uses clause.</returns>
    function Summary: string;
    /// <summary>Number of entries recorded so far.</summary>
    property Count: Integer read GetCount;
  end;

var
  /// <summary>Process-wide audit trail. Owned here, consumed by DemoSession.</summary>
  GDemoAuditTrail: TDemoAuditTrail = nil;
  /// <summary>Total entries appended. Written here, read by DemoSession.</summary>
  GDemoAuditCount: Integer = 0;

/// <summary>Creates the global audit trail if it does not exist yet.</summary>
procedure DemoAuditInit;
/// <summary>Destroys the global audit trail and nils the handle.</summary>
procedure DemoAuditDone;

implementation

uses
  DemoConfig; // <-- IMPLEMENTATION edge: this is what makes the cycle legal

const
  CKindName: array [TDemoAuditKind] of string = ('OPEN', 'WORK', 'CLOSE');

constructor TDemoAuditTrail.Create;
begin
  inherited Create;
  FEntries := TStringList.Create;
end;

destructor TDemoAuditTrail.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

function TDemoAuditTrail.GetCount: Integer;
begin
  Result := FEntries.Count;
end;

procedure TDemoAuditTrail.Add(const pKind: TDemoAuditKind; const pText: string);
begin
  FEntries.Add(Format('%s: %s', [CKindName[pKind], pText]));
  Inc(GDemoAuditCount);
end;

function TDemoAuditTrail.Summary: string;
begin
  // Reads GDemoSettings, the global record declared over in DemoConfig.
  Result := Format('[audit] %s/%s: %d entries, retained %d days',
    [GDemoSettings.AppName, GDemoSettings.Environment, FEntries.Count,
     GDemoSettings.RetainDays]);
end;

procedure DemoAuditInit;
begin
  if GDemoAuditTrail = nil then
    GDemoAuditTrail := TDemoAuditTrail.Create;
end;

procedure DemoAuditDone;
begin
  FreeAndNil(GDemoAuditTrail);
end;

end.
