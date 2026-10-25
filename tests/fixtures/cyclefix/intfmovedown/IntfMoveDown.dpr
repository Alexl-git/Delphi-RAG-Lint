program IntfMoveDown;

{$APPTYPE CONSOLE}

uses
  Alpha in 'Alpha.pas',
  Beta in 'Beta.pas';

var
  A: TAlpha;
begin
  A := TAlpha.Create;
  try
    Writeln(A.Run, ' ', BetaValue);
  finally
    A.Free;
  end;
end.