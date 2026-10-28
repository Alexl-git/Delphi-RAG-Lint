unit indexlooptoforin;
interface
implementation

uses System.Generics.Collections;

procedure Use(X: Integer);
begin
end;

procedure HitHigh(const A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Use(A[I]);
end;

procedure HitLength(const A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to Length(A) - 1 do
  begin
    Use(A[I]);
  end;
end;

procedure HitCount(L: TList<Integer>);
var
  I: Integer;
begin
  for I := 0 to L.Count - 1 do
    Use(L[I]);
end;

procedure HitItems(L: TList<Integer>);
begin
  for var J := 0 to L.Count - 1 do
    Use(L.Items[J]);
end;

procedure MissArith(const A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Use(A[I] + I);
end;

procedure MissAssigned(var A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    A[I] := 0;
end;

procedure MissWriteField(var A: TArray<TPoint>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    A[I].X := 0;
end;

procedure MissReadAfter(const A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Use(A[I]);
  Use(I);
end;

procedure MissNeighbour(const A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) - 1 do
    Use(A[I + 1]);
end;

procedure MissDownto(const A: TArray<Integer>);
var
  I: Integer;
begin
  for I := High(A) downto 0 do
    Use(A[I]);
end;

procedure MissOtherContainer(const A, B: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Use(B[I]);
end;

procedure MissNonZeroStart(const A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 1 to High(A) do
    Use(A[I]);
end;

procedure MissDelete(L: TList<Integer>);
var
  I: Integer;
begin
  for I := 0 to L.Count - 1 do
  begin
    Use(L[I]);
    L.Delete(0);
  end;
end;

procedure MissAdd(L: TList<Integer>);
var
  I: Integer;
begin
  for I := 0 to L.Count - 1 do
  begin
    Use(L[I]);
    L.Add(0);
  end;
end;

procedure MissSetLength(var A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
  begin
    Use(A[I]);
    SetLength(A, 1);
  end;
end;

end.