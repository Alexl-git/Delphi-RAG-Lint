unit DRagLint.Refactor.DeadCode;

interface

uses
  System.SysUtils
  , System.Classes
  , System  .Generics.Collections
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoFindDeadCode (DRagLint.CLI.pas)
  /// Used in units: DRagLint.CLI
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDeadCodeFinder = class
    public
      /// <param name="AStore"><!-- drag-lint:auto --></param>
      /// <param name="AKind"><!-- drag-lint:auto --></param>
      /// <param name="AIncludePrivate"><!-- drag-lint:auto --></param>
      /// <returns><!-- drag-lint:auto -->Observed: AStore.FindSymbolsWithNoCallers(AKind,
      /// AIncludePrivate).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoFindDeadCode (DRagLint.CLI.pas)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithNoCallers
      /// Pure
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithNoCallers"/>
      /// <seealso cref="DRagLint.Refactor.DeadCode.TDeadCodeFinder.RenderText"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Find(const AStore: ISymbolStore; const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;
      /// <param name="ASymbols"><!-- drag-lint:auto --></param>
      /// <param name="AStore"><!-- drag-lint:auto --></param>
      /// <returns><!-- drag-lint:auto -->Observed: Sb.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoFindDeadCode (DRagLint.CLI.pas)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath
      /// Pure
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Refactor.DeadCode.TDeadCodeFinder.Find"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderText(const ASymbols: TArray<TSymbol>; const AStore: ISymbolStore)        : string         ;
  end;

implementation

class function TDeadCodeFinder.Find(const AStore: ISymbolStore; const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;
begin
  Result:= AStore.FindSymbolsWithNoCallers(AKind, AIncludePrivate);
end;

class function TDeadCodeFinder.RenderText(const ASymbols: TArray<TSymbol>; const AStore: ISymbolStore): string;
var
  Sb      : TStringBuilder;
  Sym     : TSymbol       ;
  FilePath: string        ;
begin
  if Length(ASymbols) = 0 then Exit('');
  Sb:= TStringBuilder.Create;
  try
    for Sym in ASymbols do
    begin
      FilePath:= AStore.GetFilePath(Sym.FileId);
      Sb.AppendLine(System.SysUtils.Format('%s  [%s]  %s:%d', [Sym.QualifiedName, Sym.Kind.ToText, FilePath, Sym.StartLine]));
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
