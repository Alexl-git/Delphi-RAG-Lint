unit DRagLint.Doc.Facts;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TDocFactRef = record
    Display : string;   { e.g. 'Unit1.DoThing' }
    Location: string;   { e.g. 'U1.pas:42' }
  end;

  /// <summary>Index-grounded facts about one symbol, for the managed
  /// DocInsight remarks block. All lists are capped for display; the *Total
  /// fields carry the true count so the renderer can add '(+N more)'.</summary>
  TDocFacts = record
    CalledFrom     : TArray<TDocFactRef>;
    Calls          : TArray<string>     ;
    UsedInUnits    : TArray<string>     ;
    Raises         : TArray<string>     ;
    ReturnType     : string             ;
    CalledFromTotal: Integer            ;
    CallsTotal     : Integer            ;
    UsedInTotal    : Integer            ;
  end;

  TDocFactsBuilder = class
  public
    /// <summary>Builds the grounded facts for ASym from the index.</summary>
    class function Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
  end;

implementation

class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
begin
  Result:= Default(TDocFacts);
end;

end.
