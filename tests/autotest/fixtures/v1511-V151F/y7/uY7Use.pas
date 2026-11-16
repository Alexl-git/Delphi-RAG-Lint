unit uY7Use;

{ Y7: unrelated-class-cast. HIT lines must fire, OK lines must not. }

interface

uses
  uY7Shapes;

procedure Use(ASquare: TSquare; AOther: TOther; AOrphan: TOrphan);

implementation

procedure Use(ASquare: TSquare; AOther: TOther; AOrphan: TOrphan);
begin
  TCircle(ASquare).FRadius:= 1; {HIT}
  TOrphan(ASquare).FY:= 2; {OK}
  TSquare(AOrphan).FSide:= 3; {OK}
  if AOther is TCircle then
    TCircle(AOther).FRadius:= 4; {OK}
  if AOther is TCircle then
  begin
    TCircle(AOther).FRadius:= 5; {OK}
  end;
end;

end.
