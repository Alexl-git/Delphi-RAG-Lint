unit DemoUIConnect;

// E18 T17b fixture withself (D1): the consumer. Inside `with pPort as TDemoGagePort do`
// it reads the port's Log and its OWN InBuf through `Self.` -- both classes declare
// InBuf, so only the qualification keeps the binding.

interface

uses
  System.SysUtils,
  System.Classes;

type
  /// <summary>Stand-in for the UI-connection form owned by a gage port.</summary>
  TDemoUIConnect = class(TComponent)
  private
    FInBuf: string;
  public
    /// <summary>Handles one reading from the port.</summary>
    /// <param name="pPort">The port that produced the reading; ignored unless it is one.</param>
    procedure OnData(pPort: TComponent);
    /// <summary>The reading as text, set by the port before <c>OnData</c>.</summary>
    property InBuf: string read FInBuf write FInBuf;
  end;

implementation

uses
  DemoGagePort; // <-- the edge to cut: `is`/`as` + one member read

procedure TDemoUIConnect.OnData(pPort: TComponent);
begin
  if not (pPort is TDemoGagePort) then
    Exit;
  with pPort as TDemoGagePort do
    Log.Add('data ' + Self.InBuf);
end;

end.