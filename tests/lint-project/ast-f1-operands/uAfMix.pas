unit uAfMix;

{ Fixture of run_ast_f1_operands.ps1, row 20 (interface-object-mixing, OFF). TAfComp derives from
  TComponent (not declared here: an unfollowable ancestor that is still NAMED, so the ancestry
  answers yes). A TComponent is not reference counted, so aliasing it into an interface and
  freeing it is no dual handle: CONTROL-MIX. With the F1 fact the rule skips it; without the
  fact it still reports it. TRIGGER-MIX is a plain class, reported in every run. }

interface

type
  IAfThing = interface
  end;

  TAfComp = class(TComponent)
  end;

  TAfPlain = class(TInterfacedObject, IAfThing)
  end;

procedure AfMixComp;
procedure AfMixPlain;

implementation

procedure AfMixComp;
var
  C: TAfComp;
  I: IAfThing;
begin
  I:= C;
  C.Free; // CONTROL-MIX-1
end;

procedure AfMixPlain;
var
  P: TAfPlain;
  I: IAfThing;
begin
  I:= P;
  P.Free; // TRIGGER-MIX-1
end;

end.
