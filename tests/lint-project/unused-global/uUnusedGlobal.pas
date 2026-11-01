unit uUnusedGlobal;

{ Fixture for the `unused-global` project rule (1.40 lane unusedg). TRIGGER-* lines
  must fire; CONTROL-* lines must stay silent. uUnusedGlobalUser.pas is the other unit. }

interface

const
  GIntfUnused = 1;                 // TRIGGER-INTF-CONST
  GIntfOtherUnit = 2;              // CONTROL-INTF-OTHERUNIT (named only from uUnusedGlobalUser)
  GIntfOwnImpl = 3;                // CONTROL-INTF-OWNIMPL (named only in this unit's implementation)

var
  GIntfVarUnused: Integer;         // TRIGGER-INTF-VAR

type
  TIntfAliasUnused = Integer;      // TRIGGER-INTF-TYPE
  TIntfClassPublic = class         // CONTROL-INTF-CLASS (interface classes are public API, not checked)
  end;

procedure RunGlobals;

implementation

const
  CImplUnused = 10;                // TRIGGER-IMPL-CONST
  CImplNested = 11;                // CONTROL-IMPL-NESTED (named only inside a nested routine)
  CImplInit = 12;                  // CONTROL-IMPL-INIT (named only in initialization)
  CBase = 5;                       // CONTROL-IMPL-VIATYPED (named only in a typed const's declaration)
  CTyped: array[0..1] of Integer = (CBase, 6);
  CPlain = 7;                      // CONTROL-IMPL-READ

var
  VImplUnused: Integer;            // TRIGGER-IMPL-VAR
  VImplUsed: Integer;              // CONTROL-IMPL-VARREAD

type
  TImplAliasUnused = Integer;      // TRIGGER-IMPL-TYPE
  TImplRecUnused = record          // TRIGGER-IMPL-RECORD
    X: Integer;
  end;
  TImplRecUsed = record            // CONTROL-IMPL-RECUSED
    Y: Integer;
  end;

procedure RunGlobals;
var
  R: TImplRecUsed;

  procedure Nested;
  begin
    VImplUsed:= CImplNested;
  end;

begin
  R.Y:= CPlain + CTyped[0] + GIntfOwnImpl;
  VImplUsed:= VImplUsed + R.Y;
  Nested;
end;

initialization
  VImplUsed:= CImplInit;

end.
