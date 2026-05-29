unit DRagLint.Refactor.DeadCode;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TDeadCodeFinder = class
  public
    class function Find(const AStore: ISymbolStore;
      const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;
    class function RenderText(const ASymbols: TArray<TSymbol>;
      const AStore: ISymbolStore): string;
  end;

implementation

class function TDeadCodeFinder.Find(const AStore: ISymbolStore;
  const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;
begin
  Result := AStore.FindSymbolsWithNoCallers(AKind, AIncludePrivate);
end;

class function TDeadCodeFinder.RenderText(const ASymbols: TArray<TSymbol>;
  const AStore: ISymbolStore): string;
var
  Sb: TStringBuilder;
  Sym: TSymbol;
  FilePath: string;
begin
  if Length(ASymbols) = 0 then
    Exit('');
  Sb := TStringBuilder.Create;
  try
    for Sym in ASymbols do
    begin
      FilePath := AStore.GetFilePath(Sym.FileId);
      Sb.AppendLine(System.SysUtils.Format('%s  [%s]  %s:%d',
        [Sym.QualifiedName, Sym.Kind.ToText, FilePath, Sym.StartLine]));
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
