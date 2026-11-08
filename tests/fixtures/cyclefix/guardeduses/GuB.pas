unit GuB;

interface

/// <summary>Writes the name of a TGuA.</summary>
procedure GuSay;

implementation

uses
  GuA;

procedure GuSay;
var
  A: TGuA;
begin
  A := TGuA.Create;
  try
    Writeln('[gu] ', A.Name);
  finally
    A.Free;
  end;
end;

end.