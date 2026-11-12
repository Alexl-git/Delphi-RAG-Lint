unit IncUB;

interface

type
  TIncUB = class
  public
    procedure Say;
  end;

implementation

uses
  IncUA;

procedure TIncUB.Say;
var
  A: TIncUA;
begin
  A := TIncUA.Create;
  A.Free;
end;

end.