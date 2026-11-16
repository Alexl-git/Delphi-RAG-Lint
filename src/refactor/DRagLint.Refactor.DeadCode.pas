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
      /// <summary>Dead-code candidates: symbols nothing references by name, minus
      /// every unit that some uses clause names (v1511 B03).</summary>
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AKind"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AIncludePrivate"><!-- drag-lint:auto type -->Boolean</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TSymbol&gt; -- Observed: Kept.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoFindDeadCode (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithNoCallers, DRagLint.Core.Interfaces.ISymbolStore.FindUsersOfUnit, LowerCase</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithNoCallers"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindUsersOfUnit"/>
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
      /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Model.TSymbolKindHelper.ToText</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
      /// <seealso cref="DRagLint.Core.Model.TSymbolKindHelper.ToText"/>
      /// <seealso cref="DRagLint.Refactor.DeadCode.TDeadCodeFinder.Find"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RenderText(const ASymbols: TArray<TSymbol>; const AStore: ISymbolStore)        : string         ;
  end;

implementation

class function TDeadCodeFinder.Find(const AStore: ISymbolStore; const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;
var
  Kept: TList<TSymbol>;
begin
  Kept:= TList<TSymbol>.Create;
  try
    { v1511 B03: nothing names a unit in refs.name_text -- a uses clause is stored in
      unit_uses -- so the no-callers query listed EVERY unit, including one the
      program or library compiles. A unit some uses clause names is not dead. }
    for var Sym: TSymbol in AStore.FindSymbolsWithNoCallers(AKind, AIncludePrivate) do
      if (Sym.Kind <> skUnit) or (Length(AStore.FindUsersOfUnit(LowerCase(Sym.Name))) = 0) then
        Kept.Add(Sym);
    Result:= Kept.ToArray;
  finally
    Kept.Free;
  end;
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
