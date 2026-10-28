unit uRefInitProbe;

{ Lane REFTYPE fixture, part 2: a constant or type named ONLY inside an
  initializer expression, a subrange / array bound, an enum ordinal, a default
  parameter VALUE or an attribute argument in the INTERFACE section. The runner
  asserts a ref for each expected name on its M- marker line. }

interface

uses
  uRefInitDefs;

type
  TRiRange = RiLo..RiHi; { M-SUBRANGE }
  TRiBoundArr = array[RiLo2..RiHi2] of Byte; { M-ARRBOUND }
  TRiOrd = (roA = RiH, roB); { M-ENUMVAL }

  [RiAttr(RiG)] { M-ATTR }
  TRiTagged = class
  public
    procedure Run(pX: Integer = RiF); { M-DEFVAL }
  end;

const
  CRiUntyped = RiA; { M-UNTYPED }
  CRiTyped: Integer = RiB; { M-TYPED }
  CRiArr: array[0..1] of Integer = (RiC1, RiC2); { M-ARRAY }
  CRiRec: TRiRec = (F: RiD); { M-RECORD }
  CRiExpr = RiE + 1; { M-EXPR }
  CRiSize = SizeOf(TRiSz); { M-SIZEOF }
  CRiSet = [riK1, riK2]; { M-SET }

resourcestring
  SRiMsg = RiS; { M-RESSTR }

var
  GRiInit: Integer = RiJ; { M-VARINIT }

procedure RiFree(pY: Integer = RiF); { M-FREEDEF }

implementation

procedure TRiTagged.Run(pX: Integer);
begin
  if pX = 0 then Exit;
end;

procedure RiFree(pY: Integer);
begin
  if pY = 0 then Exit;
end;

end.