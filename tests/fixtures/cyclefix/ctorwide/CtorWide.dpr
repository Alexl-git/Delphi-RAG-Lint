program CtorWide;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  Wide.Sink in 'Wide.Sink.pas',
  WideDm in 'WideDm.pas' {WideDmInst: TDataModule},
  Wide.Proc in 'Wide.Proc.pas',
  Wide.Worker in 'Wide.Worker.pas',
  WideHub in 'WideHub.pas';
var
  H: TWideHub;
begin
  try
    H := TWideHub.Create;
    try
      H.Run;
    finally
      H.Free;
    end;
  except
    on E: Exception do Writeln('died: ', E.ClassName);
  end;
end.