unit tc_store;

// Phase 4 store-path fixture: cases where the heuristic and the resolver DIVERGE.
//  - TMyFloat alias: resolver fires float-equality; the name heuristic misses.
//  - Fooable (no I-prefix interface): resolver fires freeandnil; heuristic misses.
//  - IMisleading (I-prefix CLASS): resolver suppresses freeandnil; heuristic FPs.

interface

type
  TMyFloat = Double;

  Fooable = interface
    ['{DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD}']
  end;

  IMisleading = class
  end;

procedure Test;

implementation

procedure Test;
var
  a, b   : TMyFloat;
  noPfx  : Fooable;
  mislead: IMisleading;
begin
  if a = b then Exit;     // line 30: float-equality (resolver via alias)
  FreeAndNil(noPfx);      // line 31: freeandnil-on-interface (resolver: real iface)
  FreeAndNil(mislead);    // line 32: NOT an interface -> resolver must NOT fire
end;

end.
