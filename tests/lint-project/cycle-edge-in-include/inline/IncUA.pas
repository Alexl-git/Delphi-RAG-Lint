unit IncUA;

interface

uses
  IncUB;

type
  TIncUA = class
  public
    function Item: TIncUB;
  end;

implementation

function TIncUA.Item: TIncUB;
begin
  Result := TIncUB.Create;
end;

end.