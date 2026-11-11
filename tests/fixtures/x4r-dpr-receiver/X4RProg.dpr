program X4RProg;

{ X4-r (wave 151) fixture: a bare call inside a .dpr routine has NO receiver.
  The implicit-Self rung must not type it as the routine's parent (the
  program symbol). Positive controls: a qualified method call F.Bar and a
  bare call inside a METHOD body keep the class TX4RFoo as receiver. }

type
  TX4RFoo = class
    procedure Bar;
    procedure Baz;
  end;

procedure TX4RFoo.Bar;
begin
end;

procedure TX4RFoo.Baz;
begin
  Bar;
end;

procedure X4RLocal;
begin
end;

procedure X4RDoIt;
var
  F: TX4RFoo;
begin
  X4RLocal;
  F:= TX4RFoo.Create;
  F.Bar;
end;

begin
  X4RDoIt;
end.