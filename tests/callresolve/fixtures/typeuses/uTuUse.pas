unit uTuUse;

interface

uses
  uTuLib, uTuLib2;

type
  TBase = class
  end;

  TGen<T> = class(TBase) // TU-HERITAGE
  public
    FItem: T; // NEG-GENERIC
    FShared: TShared; // TU-USED-UNIT
    FClash: TClash; // NEG-AMBIGUOUS
    FImpl: TImplOnly; // NEG-IMPL-SECTION
    FQual: uTuLib.TShared; // NEG-QUALIFIED
    type
      TInner = record
        A: Integer;
      end;
    var
      FIn: TInner; // TU-NESTED
  end;

  TLoc = class
  end;

  TBase2 = class
  public
    type
      TNest = record
        B: Integer;
      end;
  end;

  TDerived2 = class(TBase2)
  public
    FN: TNest; // TU-INHERITED-NESTED
  end;

var
  GBase: TBase; // TU-UNIT-VAR

procedure P(A: TBase); // TU-PARAM

implementation

procedure P(A: TBase);
type
  TLoc = record
    X: Integer;
  end;
var
  L: TLoc; // NEG-LOCAL-TYPE
  G: TGen<TBase>; // TU-GENERIC-ARG
begin
end;

end.