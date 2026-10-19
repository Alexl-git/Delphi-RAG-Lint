unit DemoUIConnect;

// CYCLE ROLE: member-access cycle, edge DemoUIConnect -> DemoGagePort (the
// cuttable one). Everything this unit takes from DemoGagePort is: the class
// TDemoGagePort as an `is` / `as` operand (lines marked below) and READS of
// two of its members, Log and LastGage. No construction, no write, no class
// method -- the shape an extracted interface can carry.
//
// Two receivers, deliberately different: `Owner` is a TComponent (its static
// type implements IInterface, so `Owner as ISomething` compiles as is) and
// `Sender` is a TObject (it does not; `Sender as ISomething` is E2015 and
// needs `TComponent(Sender) as ISomething`).

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
    /// <summary>Announces itself on the owning port's log (the real form's
    /// FormCreate, which reaches the port through Parent).</summary>
    procedure Attach;
    /// <summary>Handles one reading from the port (the real form's DDE item event).</summary>
    /// <param name="Sender">The port that produced the reading; ignored unless it is one.</param>
    procedure OnData(Sender: TObject);
    /// <summary>The reading as text, set by the port before <c>OnData</c>.</summary>
    property InBuf: string read FInBuf write FInBuf;
  end;

var
  /// <summary>The one UI connection. Created and nilled by DemoGagePort.</summary>
  GDemoUIConnect: TDemoUIConnect = nil;

implementation

uses
  DemoGagePort; // <-- the edge to cut: `is`/`as` + two member reads

procedure TDemoUIConnect.Attach;
begin
  if not (Owner is TDemoGagePort) then
    Exit;
  with Owner as TDemoGagePort do
    Log.Add(Format('ui connected (last gage %d)', [LastGage]));
end;

procedure TDemoUIConnect.OnData(Sender: TObject);
begin
  if not (Sender is TDemoGagePort) then
    Exit;
  with Sender as TDemoGagePort do
  begin
    // Log and LastGage bind to the port; InBuf binds to Self.
    Log.Add('data ' + InBuf);
    Log.Add(Format('gage now %d', [LastGage]));
  end;
end;

end.
