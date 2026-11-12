unit IncUA;

interface

uses
  {$I IncUUses.inc}

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