unit LabDirB;

interface

type
  TLabDirB = class
  public
    procedure Say;
  end;

implementation

uses
  LabDirA;

procedure TLabDirB.Say;
var
  A: TLabDirA;
begin
  A := TLabDirA.Create;
  try
    Writeln('[dir] ', A.Name);
  finally
    A.Free;
  end;
end;

end.
