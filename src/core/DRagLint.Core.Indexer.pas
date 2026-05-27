unit DRagLint.Core.Indexer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Hash,
  System.DateUtils,
  System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

type
  TIndexer = class(TInterfacedObject, IIndexer)
  strict private
    FStore: ISymbolStore;
    FParsers: TList<IParser>;
    function ParserFor(const AExtension: string): IParser;
    procedure ReportProgress(const APath: string; ASymbols, ARefs, AErrors: Integer);
  public
    constructor Create(const AStore: ISymbolStore;
      const AParsers: TArray<IParser>);
    destructor Destroy; override;
    procedure IndexFolder(const APath: string;
      ARecursive: Boolean = True);
    procedure IndexFile(const AFilePath: string);
  end;

implementation

constructor TIndexer.Create(const AStore: ISymbolStore;
  const AParsers: TArray<IParser>);
var
  P: IParser;
begin
  inherited Create;
  FStore := AStore;
  FParsers := TList<IParser>.Create;
  for P in AParsers do
    FParsers.Add(P);
end;

destructor TIndexer.Destroy;
begin
  FParsers.Free;
  FStore := nil;
  inherited;
end;

function TIndexer.ParserFor(const AExtension: string): IParser;
var
  P: IParser;
  E: string;
  Lower: string;
begin
  Lower := LowerCase(AExtension);
  for P in FParsers do
    for E in P.FileExtensions do
      if SameText(E, Lower) then
        Exit(P);
  Result := nil;
end;

procedure TIndexer.ReportProgress(const APath: string;
  ASymbols, ARefs, AErrors: Integer);
begin
  Writeln(Format('  %s -> %d symbols, %d refs, %d errors',
    [APath, ASymbols, ARefs, AErrors]));
end;

procedure TIndexer.IndexFile(const AFilePath: string);
var
  Parser: IParser;
  Source: TBytes;
  Sha: string;
  Mtime: Int64;
  ParseRes: TParseResult;
  Token: TFileTxToken;
  Sym: TSymbol;
  IdxToId: TDictionary<Integer, Int64>;
  i: Integer;
  ResolvedParent: Int64;
  NewSymId: Int64;
begin
  Parser := ParserFor(ExtractFileExt(AFilePath));
  if Parser = nil then
    Exit;
  Source := TFile.ReadAllBytes(AFilePath);
  Sha := THashSHA2.GetHashString(TEncoding.ANSI.GetString(Source));
  Mtime := DateTimeToUnix(TFile.GetLastWriteTime(AFilePath), False);
  ParseRes := Parser.Parse(Source, AFilePath);
  Token := FStore.OpenFileTx(AFilePath, Mtime, Sha, Parser.LanguageName);
  IdxToId := TDictionary<Integer, Int64>.Create;
  try
    try
      for i := 0 to High(ParseRes.Symbols) do
      begin
        Sym := ParseRes.Symbols[i];
        // Translate in-array parent index to actual DB id
        if (Sym.ParentId >= 0) and IdxToId.TryGetValue(Integer(Sym.ParentId),
          ResolvedParent) then
          Sym.ParentId := ResolvedParent
        else
          Sym.ParentId := -1;
        NewSymId := FStore.UpsertSymbol(Token, Sym);
        IdxToId.Add(i, NewSymId);
      end;
      for i := 0 to High(ParseRes.References) do
        FStore.UpsertReference(Token, ParseRes.References[i]);
      FStore.CommitFileTx(Token);
      ReportProgress(AFilePath, Length(ParseRes.Symbols),
        Length(ParseRes.References),
        Length(ParseRes.Diagnostics));
    except
      on E: Exception do
      begin
        FStore.RollbackFileTx(Token);
        Writeln(Format('  ERROR indexing %s: %s', [AFilePath, E.Message]));
      end;
    end;
  finally
    IdxToId.Free;
  end;
end;

procedure TIndexer.IndexFolder(const APath: string; ARecursive: Boolean);
var
  Mode: TSearchOption;
  Files: TArray<string>;
  F: string;
  P: IParser;
  Ext: string;
  Patterns: TList<string>;
  Pattern: string;
begin
  if ARecursive then
    Mode := TSearchOption.soAllDirectories
  else
    Mode := TSearchOption.soTopDirectoryOnly;

  Patterns := TList<string>.Create;
  try
    for P in FParsers do
      for Ext in P.FileExtensions do
        Patterns.Add('*' + Ext);

    for Pattern in Patterns do
    begin
      Files := TDirectory.GetFiles(APath, Pattern, Mode);
      for F in Files do
      begin
        try
          IndexFile(F);
        except
          on E: Exception do
            Writeln(Format('  SKIP %s: %s: %s',
              [F, E.ClassName, E.Message]));
        end;
      end;
    end;
  finally
    Patterns.Free;
  end;
end;

end.
