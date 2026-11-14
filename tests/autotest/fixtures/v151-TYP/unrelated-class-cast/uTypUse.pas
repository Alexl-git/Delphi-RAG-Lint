unit uTypUse;

{ Casts across the unit boundary. HIT lines must fire, OK lines must not. }

interface

uses
  uTypShapes;

procedure Use(ASquare: TSquare; AShape: TShape; AOther: TOther);

implementation

procedure Use(ASquare: TSquare; AShape: TShape; AOther: TOther);
begin
  TCircle(ASquare).FRadius:= 1; {HIT}
  TSquare(AOther).FSide:= 2; {HIT}
  TCircle(AShape).FRadius:= 3; {OK}
  TShape(ASquare).FName:= 'x'; {OK}
end;

end.
