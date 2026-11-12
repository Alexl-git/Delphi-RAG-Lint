unit IncUA;

interface

uses
  {$I IncUUses.inc} // dl:ok cycle-edge-in-include@173d -- reviewed: the include is generated, kept on purpose

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