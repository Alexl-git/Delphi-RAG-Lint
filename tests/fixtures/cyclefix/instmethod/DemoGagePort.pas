unit DemoGagePort;

// ---------------------------------------------------------------------------
// W6-cyc4 fixture instmethod (plan B2): the circular-demo member-access pair; see DemoUIConnect.
//
// CYCLE ROLE: the MEMBER-ACCESS cycle (two units, implementation-only).
//
//   DemoGagePort  -> DemoUIConnect  (implementation: CONSTRUCTS TDemoUIConnect,
//                                    writes and reads the global GDemoUIConnect)
//   DemoUIConnect -> DemoGagePort   (implementation: `is` / `as` tests against
//                                    TDemoGagePort, then reads exactly TWO of
//                                    its members: Log and LastGage)
//
// Modelled on a real client: a gage-port form creates a UI-connection form
// and keeps it in a global; the UI-connection form checks that its owner /
// the event sender IS the gage-port form and reads a memo and a counter from
// it. The cheapest cut is the SECOND edge: the consumer never constructs or
// writes the class, so an interface carrying those two members, declared in
// a new leaf unit and implemented by TDemoGagePort, lets DemoUIConnect drop
// DemoGagePort -- "member hand-over through an extracted interface". The
// `is` becomes Supports(), the `as` becomes `as IDemoGagePortSurface`; the
// `Sender: TObject` receiver needs a cast through TComponent first, because
// TObject does not implement IInterface.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils,
  System.Classes;

type
  /// <summary>Stand-in for the gage-port form: a channel feeding a log.</summary>
  /// <remarks>Owns the log and the UI connection it creates (component ownership).</remarks>
  TDemoGagePort = class(TComponent)
  private
    FLog: TStrings;
    FLastGage: Integer;
  public
    /// <summary>Creates the port with an empty log.</summary>
    /// <param name="pOwner">Owner component, or nil.</param>
    constructor Create(pOwner: TComponent); override;
    /// <summary>Releases the log.</summary>
    destructor Destroy; override;
    /// <summary>Takes one reading: opens the UI connection on first use, then
    /// hands the reading to it.</summary>
    /// <param name="pValue">The gage value read.</param>
    procedure ReadGage(const pValue: Integer);
    /// <summary>Appends a mark to the log (a static method).</summary>
    /// <param name="pText">The mark.</param>
    procedure Mark(const pText: string);
    /// <summary>Appends a touch to the log (a static method with no parameters).</summary>
    procedure Touch;
    /// <summary>Resets the port (a virtual method; descendants override it).</summary>
    /// <param name="pCount">The reset count.</param>
    procedure Reset(const pCount: Integer = 1); virtual;
    /// <summary>The port's name path (an override of an RTL virtual).</summary>
    /// <returns>Always 'gageport'.</returns>
    function GetNamePath: string; override;
    /// <summary>What the UI connection reads: the port's log (the real form's memo).</summary>
    property Log: TStrings read FLog;
    /// <summary>What the UI connection reads: the last value taken.</summary>
    property LastGage: Integer read FLastGage;
  end;

implementation

uses
  DemoUIConnect; // constructs TDemoUIConnect, writes GDemoUIConnect: not a mechanical cut

constructor TDemoGagePort.Create(pOwner: TComponent);
begin
  inherited Create(pOwner);
  FLog := TStringList.Create;
end;

destructor TDemoGagePort.Destroy;
begin
  if (GDemoUIConnect <> nil) and (GDemoUIConnect.Owner = Self) then
    GDemoUIConnect := nil; // freed by component ownership below
  FLog.Free;
  inherited Destroy;
end;

procedure TDemoGagePort.ReadGage(const pValue: Integer);
begin
  if GDemoUIConnect = nil then
  begin
    GDemoUIConnect := TDemoUIConnect.Create(Self);
    GDemoUIConnect.Attach;
  end;
  FLastGage := pValue;
  GDemoUIConnect.InBuf := IntToStr(pValue);
  GDemoUIConnect.OnData(Self);
end;

procedure TDemoGagePort.Mark(const pText: string);
begin
  FLog.Add('mark ' + pText);
end;

procedure TDemoGagePort.Touch;
begin
  FLog.Add('touch');
end;

procedure TDemoGagePort.Reset(const pCount: Integer);
begin
  FLog.Add(Format('reset %d (base)', [pCount]));
end;

function TDemoGagePort.GetNamePath: string;
begin
  Result := 'gageport';
end;

end.
