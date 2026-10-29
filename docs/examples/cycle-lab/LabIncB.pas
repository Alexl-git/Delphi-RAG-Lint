unit LabIncB;

interface

type
  TLabIncB = class
  public
    procedure Say;
  end;

implementation

uses
  LabIncA;

procedure TLabIncB.Say;
var
  A: TLabIncA;
begin
  A := TLabIncA.Create;
  try
    Writeln('[inc] ', A.ClassName);
  finally
    A.Free;
  end;
end;

end.
