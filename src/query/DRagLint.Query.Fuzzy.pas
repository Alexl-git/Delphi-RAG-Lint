unit DRagLint.Query.Fuzzy;

interface

uses
  System.SysUtils
  , System.Generics.Collections
  ;

// Classic O(|a|*|b|) Levenshtein distance with two rolling rows.
// Case-insensitive (lowercases both inputs first) - Pascal identifiers are
// case-insensitive at the language level.
/// <summary><!-- drag-lint:auto -->Classic O(|a|*|b|) Levenshtein distance with two
/// rolling rows. Case-insensitive (lowercases both inputs first) - Pascal identifiers are
/// case-insensitive at the language level.</summary>
/// <param name="A"><!-- drag-lint:auto --></param>
/// <param name="B"><!-- drag-lint:auto --></param>
/// <returns><!-- drag-lint:auto -->Observed: RowPrev[Lb].</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.FindSymbolsFuzzy (DRagLint.Storage.SQLite.pas)
/// Calls: Copy, LowerCase
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function LevenshteinDistance(const A, B: string): Integer;

// Acceptable distance threshold for a fuzzy match against APattern.
// Tighter for short patterns to keep precision; looser for long patterns.
/// <summary><!-- drag-lint:auto -->Acceptable distance threshold for a fuzzy match
/// against APattern. Tighter for short patterns to keep precision; looser for long
/// patterns.</summary>
/// <param name="APattern"><!-- drag-lint:auto --></param>
/// <returns><!-- drag-lint:auto -->Observed: 1; 2; 3.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.FindSymbolsFuzzy (DRagLint.Storage.SQLite.pas)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function FuzzyMaxDistanceFor(const APattern: string): Integer;

// Extracts the case-insensitive 3-gram set of a string. Patterns shorter
// than 3 chars return an empty array (caller should fall back to full scan).
/// <summary><!-- drag-lint:auto -->Extracts the case-insensitive 3-gram set of a string.
/// Patterns shorter than 3 chars return an empty array (caller should fall back to full
/// scan).</summary>
/// <param name="S"><!-- drag-lint:auto --></param>
/// <returns><!-- drag-lint:auto -->Observed: List.ToArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.EnsureTrigramTablePopulated (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.UpsertSymbol (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.FindSymbolsFuzzy (DRagLint.Storage.SQLite.pas)
/// Calls: Copy, LowerCase
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function Trigrams(const S: string): TArray<string>;

implementation

function LevenshteinDistance(const A, B: string): Integer;
var
  La              : Integer         ;
  Lb              : Integer         ;
  i               : Integer         ;
  j               : Integer         ;
  Cost            : Integer         ;
  Above           : Integer         ;
  Left            : Integer         ;
  Diag            : Integer         ;
  Tmp             : Integer         ;
  RowPrev, RowCurr: array of Integer;
  LowA            : string          ;
  LowB            : string          ;
begin
  LowA:= LowerCase(A   );
  LowB:= LowerCase(B   );
  La  := Length   (LowA);
  Lb  := Length   (LowB);
  if La = 0 then Exit(Lb);
  if Lb = 0 then Exit(La);

  SetLength(RowPrev, Lb + 1);
  SetLength(RowCurr, Lb + 1);
  for j:= 0 to Lb do RowPrev[j]:= j;

  for i:= 1 to La do
  begin
    RowCurr[0]:= i;
    for j:= 1 to Lb do
    begin
      if LowA[i] = LowB[j] then Cost:= 0
      else Cost:= 1;
      Above:= RowPrev[j] + 1;
      Left:= RowCurr[j - 1] + 1;
      Diag:= RowPrev[j - 1] + Cost;
      Tmp:= Above;
      if Left < Tmp then Tmp:= Left;
      if Diag < Tmp then Tmp:= Diag;
      RowCurr[j]:= Tmp;
    end;
    RowPrev:= Copy(RowCurr);
  end; // for
  Result:= RowPrev[Lb];
end; // function

function FuzzyMaxDistanceFor(const APattern: string): Integer;
var
  L: Integer;
begin
  L:= Length(APattern);
  if L <= 4 then Result:= 1
  else if L <= 8 then Result:= 2
  else Result:= 3;
end;

function Trigrams(const S: string): TArray<string>;
var
  Low : string                      ;
  i   : Integer                     ;
  N   : Integer                     ;
  Seen: TDictionary<string, Boolean>;
  G   : string                      ;
  List: TList<string>               ;
begin
  Low:= LowerCase(S  );
  N  := Length   (Low);
  if N < 3 then Exit(nil);
  Seen:= TDictionary<string, Boolean>.Create;
  List:= TList<string>.Create;
  try
    for i:= 1 to N - 2 do
    begin
      G:= Copy(Low, i, 3);
      if not Seen.ContainsKey(G) then
      begin
        Seen.Add(G, True);
        List.Add(G);
      end;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
    Seen.Free;
  end;
end; // function

end.
