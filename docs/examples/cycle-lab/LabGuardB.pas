unit LabGuardB;

interface

type
  TLabGuardB = class
  public
    procedure Say;
  end;

implementation

uses
  LabGuardA;

procedure TLabGuardB.Say;
var
  A: TLabGuardA;
begin
  A := TLabGuardA.Create;
  try
    Writeln('[guard] ', A.Name);
  finally
    A.Free;
  end;
end;

end.
