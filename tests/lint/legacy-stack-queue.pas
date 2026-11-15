unit LegacyStackQueue;

interface

uses
  System.Contnrs, System.Generics.Collections;

type
  TKnoten = class
  end;

  TSuche = class
  private
    FOffen: TObjectStack;
    FModern: TStack<TKnoten>;
    procedure Lauf;
  end;

implementation

procedure TSuche.Lauf;
var
  Knoten: TKnoten;
begin
  Knoten := TKnoten(FOffen.Pop);
  Knoten := FModern.Pop;
end;

end.
