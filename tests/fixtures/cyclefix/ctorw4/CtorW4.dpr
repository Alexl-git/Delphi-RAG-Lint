program CtorW4;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  W4.Sink in 'W4.Sink.pas',
  W4.Worker in 'W4.Worker.pas',
  W4Hub in 'W4Hub.pas';
var
  H: TW4Hub;
begin
  try
    H := TW4Hub.Create;
    try
      H.Run;
    finally
      H.Free;
    end;
  except
    on E: Exception do Writeln('died: ', E.ClassName);
  end;
end.