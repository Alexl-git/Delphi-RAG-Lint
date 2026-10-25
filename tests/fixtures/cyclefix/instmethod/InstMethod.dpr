program InstMethod;

// W6-cyc4 (plan B2) fixture: the circular-demo member-access pair whose consumer calls three
// INSTANCE methods of TDemoGagePort inside `with Sender as TDemoGagePort do`: a static method
// (Mark), a virtual one with a default parameter (Reset) and an override of an RTL virtual
// (GetNamePath). The program runs a DESCENDANT, TDemoGagePortEx, that overrides Reset: after
// the cut the consumer calls Reset through the extracted interface, and the output shows the
// override still runs (dispatch unchanged).

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DemoGagePort in 'DemoGagePort.pas',
  DemoUIConnect in 'DemoUIConnect.pas';

type
  /// <summary>A descendant port whose Reset the consumer must still reach.</summary>
  TDemoGagePortEx = class(TDemoGagePort)
  public
    /// <summary>Logs the reset as the descendant's.</summary>
    /// <param name="pCount">The reset count.</param>
    procedure Reset(const pCount: Integer = 1); override;
  end;

procedure TDemoGagePortEx.Reset(const pCount: Integer);
begin
  Log.Add(Format('reset %d (descendant)', [pCount]));
end;

var
  GPort: TDemoGagePort;
  I: Integer;

begin
  try
    GPort := TDemoGagePortEx.Create(nil);
    try
      GPort.ReadGage(42);
      GPort.ReadGage(43);
      for I := 0 to GPort.Log.Count - 1 do
        Writeln('[gageport] ', GPort.Log[I]);
    finally
      GPort.Free;
    end;
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.