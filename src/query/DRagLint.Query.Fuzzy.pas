unit DRagLint.Query.Fuzzy;

interface

uses
  System.SysUtils;

// Classic O(|a|*|b|) Levenshtein distance with two rolling rows.
// Case-insensitive (lowercases both inputs first) — Pascal identifiers are
// case-insensitive at the language level.
function LevenshteinDistance(const A, B: string): Integer;

// Acceptable distance threshold for a fuzzy match against APattern.
// Tighter for short patterns to keep precision; looser for long patterns.
function FuzzyMaxDistanceFor(const APattern: string): Integer;

implementation

function LevenshteinDistance(const A, B: string): Integer;
var
  La, Lb, i, j, Cost, Above, Left, Diag, Tmp: Integer;
  RowPrev, RowCurr: array of Integer;
  LowA, LowB: string;
begin
  LowA := LowerCase(A);
  LowB := LowerCase(B);
  La := Length(LowA);
  Lb := Length(LowB);
  if La = 0 then Exit(Lb);
  if Lb = 0 then Exit(La);

  SetLength(RowPrev, Lb + 1);
  SetLength(RowCurr, Lb + 1);
  for j := 0 to Lb do
    RowPrev[j] := j;

  for i := 1 to La do
  begin
    RowCurr[0] := i;
    for j := 1 to Lb do
    begin
      if LowA[i] = LowB[j] then
        Cost := 0
      else
        Cost := 1;
      Above := RowPrev[j] + 1;
      Left := RowCurr[j - 1] + 1;
      Diag := RowPrev[j - 1] + Cost;
      Tmp := Above;
      if Left < Tmp then Tmp := Left;
      if Diag < Tmp then Tmp := Diag;
      RowCurr[j] := Tmp;
    end;
    RowPrev := Copy(RowCurr);
  end;
  Result := RowPrev[Lb];
end;

function FuzzyMaxDistanceFor(const APattern: string): Integer;
var
  L: Integer;
begin
  L := Length(APattern);
  if L <= 4 then
    Result := 1
  else if L <= 8 then
    Result := 2
  else
    Result := 3;
end;

end.
