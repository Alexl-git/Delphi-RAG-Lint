program MemberWrite;

// E18 T6 fixture: the circular-demo member-access pair whose consumer WRITES a member
// inside its `with` body. Removing that line gives the clean pair R2 cuts.

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