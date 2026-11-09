unit DelUse;

interface

procedure RunAll;

implementation

uses
  DelTypes;

procedure RunAll;
begin
  var A: IFoo:= TAgg.Create;
  A.Bar;
  var B: IFoo:= TAgg2.Create;
  B.Bar;
  var C: IFoo:= TFull.Create;
  C.Bar;
end;

end.
