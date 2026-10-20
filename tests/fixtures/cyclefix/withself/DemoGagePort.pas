unit DemoGagePort;

// E18 T17b fixture withself (D1): the member-access pair where BOTH classes declare
// a field-backed property InBuf. The consumer reads `Self.InBuf` inside
// `with pPort as TDemoGagePort do`: Self-qualified, so it binds to the consumer
// before and after the rewrite -- R2 must not refuse it as `with-member`. The
// unqualified `InBuf` there (the positive control, made by the runner) would
// bind to the port today and to the consumer after the rewrite: refused.

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
    FInBuf: string;
  public
    /// <summary>Creates the port with an empty log.</summary>
    /// <param name="pOwner">Owner component, or nil.</param>
    constructor Create(pOwner: TComponent); override;
    /// <summary>Releases the log.</summary>
    destructor Destroy; override;
    /// <summary>Takes one reading and hands it to the UI connection.</summary>
    /// <param name="pValue">The gage value read.</param>
    procedure ReadGage(const pValue: Integer);
    /// <summary>What the UI connection reads: the port's log.</summary>
    property Log: TStrings read FLog;
    /// <summary>The port's own raw buffer; the same name as the consumer's.</summary>
    property InBuf: string read FInBuf;
  end;

implementation

uses
  DemoUIConnect; // constructs TDemoUIConnect: not a mechanical cut

constructor TDemoGagePort.Create(pOwner: TComponent);
begin
  inherited Create(pOwner);
  FLog := TStringList.Create;
  FInBuf := 'port-raw';
end;

destructor TDemoGagePort.Destroy;
begin
  FLog.Free;
  inherited Destroy;
end;

procedure TDemoGagePort.ReadGage(const pValue: Integer);
var
  LConn: TDemoUIConnect;
begin
  LConn := TDemoUIConnect.Create(Self);
  LConn.InBuf := IntToStr(pValue);
  LConn.OnData(Self);
end;

end.