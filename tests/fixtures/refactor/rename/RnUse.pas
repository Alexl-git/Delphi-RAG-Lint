unit RnUse;

interface

procedure RunAll;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, RnTypes;

function Count: Integer;
begin
  Result:= 300;
end;

procedure TwoClasses;
var
  A : TTwoA;
  B : TTwoB;
  K : TKid;
  L : TListy;
  IL: TIntList;
begin
  A := TTwoA.Create;
  B := TTwoB.Create;
  K := TKid.Create;
  L := TListy.Create;
  IL:= TIntList.Create;
  try
    A.Item:= A;
    B.Other:= B;
    A.Size:= 3;
    Writeln(A.Count, ' ', B.Count, ' ', K.Count, ' ', Count);
    Writeln(A.Item.Count + B.Other.Count, ' ', A.Size);
    Writeln(L.Count, ' ', IL.Count);
    Writeln(K.Twice, ' ', K.UsesHelper);
    A.Run; B.Run; K.Run;
  finally
    IL.Free;
    L.Free;
    K.Free;
    B.Free;
    A.Free;
  end;
end;

procedure WithBodies;
var
  R    : TRecX;
  N    : TNoCount;
  Total: Integer;
  Count: Integer;
begin
  Count:= 5;
  R.Count:= 7;
  R.Size:= 1;
  N.Size:= 2;
  with R do Total:= Count + Size;
  Writeln(Total);
  with N do Total:= Count + Size;
  Writeln(Total, ' ', Count);
end;

procedure Shadowing;
var
  Tally: Integer;
begin
  Tally:= 100;
  Writeln(Compute, ' ', Tally);
end;

procedure LocalCapture(pValue: Integer);
var
  Ghost: Integer;
begin
  Ghost:= pValue;
  Writeln(Ghost, ' ', Helper);
end;

procedure Others;
var
  O : TOv;
  D : IDoer;
  Xs: TList<TTwoB>;
  P : Pointer;
  S : TStringList;
begin
  O := TOv.Create;
  D := TDoer.Create;
  Xs:= TList<TTwoB>.Create;
  S := TStringList.Create;
  try
    Writeln(O.Go(1), ' ', O.Go('ab'), ' ', D.Act);
    Xs.Add(TTwoB.Create);
    Writeln(Xs[0].Kind);
    P:= S;
    Writeln(TStringList(P).Capacity >= 0);
    Xs[0].Free;
{$IFDEF NEVER_DEFINED}
    Xs[0].Zeta;
{$ENDIF}
  finally
    S.Free;
    Xs.Free;
    O.Free;
  end;
end;

procedure RunAll;
begin
  TwoClasses;
  WithBodies;
  Shadowing;
  LocalCapture(9);
  Others;
end;

end.
