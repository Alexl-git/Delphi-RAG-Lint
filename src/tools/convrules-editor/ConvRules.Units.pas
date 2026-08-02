unit ConvRules.Units;

{ Pure, headless "no doubles" brain for unit-replacement rules.

  Computes the normalized ADD/REMOVE unit sets from a rule book (dedup +
  ADD-wins conflicts), and the auto-derive from #convert type pairs via a
  resolver callback. No UI, no engine, no I/O -- the console-runner spec target.

  Normalization rule (single source of truth, shared with the future apply path):
    ADD    = every #use + every #useswap New + every #convert trailing unit.
    REMOVE = every #unuse + every #useswap Old.
    A unit in BOTH -> ADD wins: it lands in Conflicts and is dropped from Removes. }

interface

uses
  System.SysUtils
  , System.Classes
  , ConvRules.Model
  ;

type
  /// <summary>Normalized unit sets for a rule book. Adds/Removes are deduped
  /// (case-insensitive); Conflicts lists units that appeared in both (ADD won,
  /// so they are in Adds, NOT Removes).</summary>
  TUnitSets = record
    Adds     : TArray<string>;
    Removes  : TArray<string>;
    Conflicts: TArray<string>;
  end;

  /// <summary>One From/To type pair fed to auto-derive (a #convert header).</summary>
  TConvPair = record
    FromType: string;
    ToType  : string;
  end;

  /// <summary>Resolve a type name to its declaring unit ('' when unresolved).</summary>
  TUnitResolver = reference to function(const ATypeName: string): string;

/// <summary>Normalized ADD/REMOVE unit sets for a whole rule book (see the unit
/// header for the rule). Pure; case-insensitive dedup; ADD wins on conflict.</summary>
function NormalizeUnitSets(ABook: TRuleBook): TUnitSets;

/// <summary>Auto-derive: Adds = each ToType's resolved unit; Removes = each
/// FromType's resolved unit. An empty resolver result (unresolved type) is
/// skipped. Each list deduped case-insensitively. Conflicts is left empty --
/// the caller runs NormalizeUnitSets once the derived nodes are in the book.</summary>
function DeriveUnits(const APairs: TArray<TConvPair>;
  const AResolve: TUnitResolver): TUnitSets;

implementation

{ Add AUnit to AList unless blank or already present (case-insensitive). }
procedure AddUniq(AList: TStringList; const AUnit: string);
begin
  if Trim(AUnit) = '' then Exit;
  if AList.IndexOf(AUnit) < 0 then AList.Add(AUnit);
end;

function ToArr(AList: TStringList): TArray<string>;
var
  i: Integer;
begin
  SetLength(Result, AList.Count);
  for i := 0 to AList.Count - 1 do Result[i] := AList[i];
end;

function NormalizeUnitSets(ABook: TRuleBook): TUnitSets;
var
  Adds, Removes, Conflicts: TStringList;
  N    : TRuleNode;
  U    : string   ;
  Parts: TArray<string>;
  P    : string   ;
begin
  Adds := TStringList.Create; Removes := TStringList.Create; Conflicts := TStringList.Create;
  try
    Adds.CaseSensitive := False; Removes.CaseSensitive := False; Conflicts.CaseSensitive := False;
    for N in ABook.Nodes do
      case N.Kind of
        rnkUse:   AddUniq(Adds, N.UseUnit);
        rnkUnuse: AddUniq(Removes, N.UnuseUnit);
        rnkUseSwap:
          begin
            AddUniq(Removes, N.SwapOld);
            for U in N.SwapNew do AddUniq(Adds, U);
          end;
        rnkConvert:
          begin
            Parts := N.Units.Split([',']);
            for P in Parts do AddUniq(Adds, Trim(P));
          end;
      end;
    // ADD wins: any unit present in both -> Conflicts, removed from Removes.
    for U in ToArr(Adds) do
      if Removes.IndexOf(U) >= 0 then
      begin
        AddUniq(Conflicts, U);
        Removes.Delete(Removes.IndexOf(U));
      end;
    Result.Adds      := ToArr(Adds);
    Result.Removes   := ToArr(Removes);
    Result.Conflicts := ToArr(Conflicts);
  finally
    Adds.Free; Removes.Free; Conflicts.Free;
  end;
end;

function DeriveUnits(const APairs: TArray<TConvPair>;
  const AResolve: TUnitResolver): TUnitSets;
var
  Adds, Removes: TStringList;
  Pair: TConvPair;
begin
  Adds := TStringList.Create; Removes := TStringList.Create;
  try
    Adds.CaseSensitive := False; Removes.CaseSensitive := False;
    for Pair in APairs do
    begin
      AddUniq(Adds, AResolve(Pair.ToType));
      AddUniq(Removes, AResolve(Pair.FromType));
    end;
    Result.Adds      := ToArr(Adds);
    Result.Removes   := ToArr(Removes);
    Result.Conflicts := nil;
  finally
    Adds.Free; Removes.Free;
  end;
end;

end.
