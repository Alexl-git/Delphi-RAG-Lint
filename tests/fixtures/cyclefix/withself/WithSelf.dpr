program WithSelf;

// E18 T17b fixture withself (D1): a Self-qualified member inside `with ... as` must
// not refuse R2.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DemoGagePort in 'DemoGagePort.pas',
  DemoUIConnect in 'DemoUIConnect.pas';

var
  GPort: TDemoGagePort;
  I: Integer;

begin
  try
    GPort := TDemoGagePort.Create(nil);
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