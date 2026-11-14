unit LegacyTList;

interface

uses
  System.Classes, System.Contnrs, System.Generics.Collections;

type
  TPosition = class
  end;

  TBeleg = class
  private
    FPositionen: TList;
    FObjekte: TObjectList;
    FModern: TList<TPosition>;
    procedure Pruefe;
  end;

implementation

procedure TBeleg.Pruefe;
var
  Pos: TPosition;
begin
  Pos := TPosition(FPositionen[0]);
  Pos := TPosition(FObjekte.Items[1]);
  Pos := FObjekte[2] as TPosition;
  Pos := FModern[0];
end;

end.
