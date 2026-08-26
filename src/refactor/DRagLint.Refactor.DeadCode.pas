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
  /// <para>Used by: DRagLint.CLI.DoFindDeadCode (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDeadCodeFinder = class
    public
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AKind"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AIncludePrivate"><!-- drag-lint:auto type -->Boolean</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TSymbol&gt; -- Observed:
      /// AStore.FindSymbolsWithNoCallers(AKind, AIncludePrivate).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoFindDeadCode (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithNoCallers</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithNoCallers"/>
      /// <seealso cref="DRagLint.Refactor.DeadCode.TDeadCodeFinder.RenderText"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Find(const AStore: ISymbolStore; const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;
      /// <param name="ASymbols"><!-- drag-lint:auto type -->const TArray&lt;TSymbol&gt;</param>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: Sb.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoFindDeadCode (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath</para>
      /// <para>Pure</para>
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
