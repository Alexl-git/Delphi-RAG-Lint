unit LabIncA;

interface

uses
  {$I LabIncUses.inc}

type
  TLabIncA = class
  public
    function Item: TLabIncB;
  end;

implementation

function TLabIncA.Item: TLabIncB;
begin
  Result := TLabIncB.Create;
end;

end.
