unit FfIncA;

interface

uses
  {$I FfIncUses.inc}

type
  TFfIncA = class
  public
    function Item: TFfIncB;
  end;

implementation

{$I FfDefs.inc}

function TFfIncA.Item: TFfIncB;
begin
  Result:= TFfIncB.Create;
end;

end.
