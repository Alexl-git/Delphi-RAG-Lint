program R2Extend;

// E18 T6 fixture: the circular-demo member-access pair plus an existing leaf
// DemoGagePort.Untangle that recipe R2 extends.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DemoGagePort.Untangle in 'DemoGagePort.Untangle.pas',
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
    Writeln('[main] unit ', Ord(guInch));
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.