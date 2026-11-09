program Ex3App;

uses
  Forms,
  uEx3Types in 'uEx3Types.pas',
  uEx3Local in 'uEx3Local.pas';

const
  COne: TEx3Rec = (Alpha: 1; Beta: 2);
  CPlain = 7;

var
  GRun: TEx3Runner;
  GCount: Integer;

begin
  GRun := TEx3Runner.Create;
  GRun.Go;
  GCount := COne.Alpha + CPlain;
end.