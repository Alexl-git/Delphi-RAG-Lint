unit GA_Binary;

{ Grammar-shape audit fixture, shape (c): grammar v1.4.5 groups `A + B < C`
  as `(A + B) < C` (was `A + (B < C)` through the `_ref < _expr` rule), and a
  generic's `<` in an expression is the scanner token kLtTpl aliased to kLt. }

interface

uses
  System.Generics.Collections;

type
  TCalc = class
  private
    FItems: TList<Integer>;
    FCount: Integer;
  public
    procedure DoA;
    function SumLess(pA, pB, pC: Integer): Boolean;
    procedure IfSum(pA, pB, pC: Integer);
    procedure SelfCompare(pA, pB: Integer);
    procedure LengthNeg(const pS: string);
    procedure NotLess(pA, pB: Integer);
    procedure AndLess(pF: Boolean; pA, pB: Integer);
    procedure CountMinus(pI: Integer);
    procedure MagicCompare(pA: Integer);
    procedure GenericToken;
    procedure BoolLit(pA, pB: Integer);
    procedure MixedAndOr(pF, pG: Boolean; pA, pB: Integer);
    procedure UnsignedNeg(pW: Cardinal; pA: Integer);
  end;

implementation

uses
  System.SysUtils;

procedure TCalc.DoA;
begin
  Inc(FCount);
end;

function TCalc.SumLess(pA, pB, pC: Integer): Boolean;
begin
  Result := pA + pB < pC;
end;

procedure TCalc.IfSum(pA, pB, pC: Integer);
begin
  if pA + pB < pC then DoA;
  if pA - pB < 0 then DoA;
  if pA * pB < pA * pB then DoA;
end;

procedure TCalc.SelfCompare(pA, pB: Integer);
begin
  if pA < pA then DoA;
  if pA + pB < pA + pB then DoA;
  if pB + 1 < pB + 1 then DoA;
end;

procedure TCalc.LengthNeg(const pS: string);
begin
  if Length(pS) < 0 then DoA;
  if Length(pS) + 1 < 0 then DoA;
  if Length(pS) - 1 < Length(pS) - 1 then DoA;
end;

procedure TCalc.NotLess(pA, pB: Integer);
begin
  if not pA < pB then DoA;
  if not pA = pB then DoA;
end;

procedure TCalc.AndLess(pF: Boolean; pA, pB: Integer);
begin
  if pF and (pA < pB) then DoA;
  if pF or pA < pB then DoA;
end;

procedure TCalc.CountMinus(pI: Integer);
begin
  if FItems.Count - 1 < pI then DoA;
  if pI < FItems.Count - 1 then DoA;
  if FCount + pI < FCount + pI then DoA;
end;

procedure TCalc.MagicCompare(pA: Integer);
begin
  if pA + 17 < 42 then DoA;
end;

procedure TCalc.GenericToken;
var
  LList: TList<Integer>;
  LDict: TDictionary<string, Integer>;
begin
  LList := TList<Integer>.Create;
  try
    LDict := TDictionary<string, Integer>.Create;
    try
      if LList.Count < LDict.Count then DoA;
      FItems := TList<Integer>.Create;
    finally
      LDict.Free;
    end;
  finally
    LList.Free;
  end;
end;

procedure TCalc.BoolLit(pA, pB: Integer);
begin
  if (pA + pB < 3) = True then DoA;
  if pA + pB < 3 = False then DoA;
end;

procedure TCalc.MixedAndOr(pF, pG: Boolean; pA, pB: Integer);
begin
  if pF and pG or pA + pB < 2 then DoA;
end;

procedure TCalc.UnsignedNeg(pW: Cardinal; pA: Integer);
begin
  if pW + 1 < 0 then DoA;
  if pW < 0 then DoA;
  if pA + pW < 0 then DoA;
end;

end.
