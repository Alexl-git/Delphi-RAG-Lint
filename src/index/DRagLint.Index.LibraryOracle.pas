unit DRagLint.Index.LibraryOracle;

{ Item 4 (untypable receivers), contract stub: the real binding rules arrive in
  lane R2 (spec 2026-10-28-untypable-receivers s.5 item 4). Until then Bind
  answers '' / no-store so every lane compiles against the final interface. }

interface

uses
  System.SysUtils,
  DRagLint.Core.Interfaces;

type
  /// <summary>Kind of site being bound.</summary>
  TExternalKind = (ekCall, ekMemberAccess, ekBareCall);

  /// <summary>Counters of the oracle's outcomes, printed on the resolve: summary line.</summary>
  TOracleStats = record
    Bound, AmbiguousType, NoMember, NoStore, NoType: Integer;
  end;

  /// <summary>Binds a receiver typed BY NAME to a qualified symbol name in one of the extra
  /// (library) stores. Pure reader: owns no store, writes nothing, caches per type.</summary>
  /// <remarks>Not thread-safe. R0 stub: every Bind declines with no-store.</remarks>
  TLibraryOracle = class
  strict private
    FStores: TArray<ISymbolStore>;
    FStats: TOracleStats;
  public
    /// <param name="AStores">The open extra stores; the oracle does not own them.</param>
    constructor Create(const AStores: TArray<ISymbolStore>);
    /// <param name="ATypeText">spec s.4.1 value without the pending segments; '' for a bare call.</param>
    /// <param name="APending">Dot-joined pending segments or ''.</param>
    /// <param name="AMember">The called member name.</param>
    /// <param name="AKind">Site kind.</param>
    /// <param name="AUsesUnits">Lower-cased unit names the referencing file uses (both sections + the .dpr).</param>
    /// <param name="AReason">ambiguous-type|no-member|no-store|no-type when the result is ''.</param>
    /// <returns>The qualified name, or '' with AReason set.</returns>
    function Bind(const ATypeText, APending, AMember: string; AKind: TExternalKind;
      const AUsesUnits: TArray<string>; out AReason: string): string;
    /// <summary>Outcome counters since Create.</summary>
    property Stats: TOracleStats read FStats;
  end;

implementation

constructor TLibraryOracle.Create(const AStores: TArray<ISymbolStore>);
begin
  inherited Create;
  FStores := AStores;
end;

function TLibraryOracle.Bind(const ATypeText, APending, AMember: string; AKind: TExternalKind;
  const AUsesUnits: TArray<string>; out AReason: string): string;
begin
  Result := '';
  AReason := 'no-store';
  Inc(FStats.NoStore);
end;

end.