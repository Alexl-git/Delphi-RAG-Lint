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
  DRagLint.Core.Interfaces,
  DRagLint.Parser.DocComments;

type
  TIndexer = class(TInterfacedObject, IIndexer)
  strict private
    FStore: ISymbolStore;
    FParsers: TList<IParser>;
    FSkippedUpToDate: Integer;
    function ParserFor(const AExtension: string): IParser;
    procedure ReportProgress(const APath: string; ASymbols, ARefs, AErrors: Integer);
  public
    constructor Create(const AStore: ISymbolStore;
      const AParsers: TArray<IParser>);
    destructor Destroy; override;
    procedure IndexFolder(const APath: string;
      ARecursive: Boolean = True);
    procedure IndexFile(const AFilePath: string);
    function SkippedUpToDate: Integer;
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

function TIndexer.SkippedUpToDate: Integer;
begin
  Result := FSkippedUpToDate;
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

// Returns the TDocCommentRegion immediately preceding ASymStartLine
// (EndLine in [SymStartLine - 1 - ALLOW_GAP, SymStartLine - 1]).
// Sentinel: Result.Kind = TDocCommentKind(-1) means no region found.
function FindDocRegionAbove(ADocRegions: TList<TDocCommentRegion>;
  ASymStartLine: Integer): TDocCommentRegion;
var
  I: Integer;
  Best: TDocCommentRegion;
  HasBest: Boolean;
const
  ALLOW_GAP = 1;  // TODO Task 13: read from .drag-lint.json
begin
  HasBest := False;
  // ADocRegions is sorted by StartLine ascending.
  for I := 0 to ADocRegions.Count - 1 do
  begin
    if (ADocRegions[I].EndLine >= ASymStartLine - 1 - ALLOW_GAP) and
       (ADocRegions[I].EndLine <= ASymStartLine - 1) then
    begin
      Best := ADocRegions[I];
      HasBest := True;
    end;
    if ADocRegions[I].StartLine > ASymStartLine then
      Break;
  end;
  if HasBest then
    Result := Best
  else
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Kind := TDocCommentKind(-1);
  end;
end;

procedure TIndexer.IndexFile(const AFilePath: string);
var
  Parser: IParser;
  Source: TBytes;
  SourceText: string;
  Sha: string;
  Mtime: Int64;
  ParseRes: TParseResult;
  Token: TFileTxToken;
  Sym: TSymbol;
  IdxToId: TDictionary<Integer, Int64>;
  i: Integer;
  ResolvedParent: Int64;
  NewSymId: Int64;
  DocRegions: TList<TDocCommentRegion>;
  DocRegion: TDocCommentRegion;
  ParsedDoc: TParsedDoc;
begin
  Parser := ParserFor(ExtractFileExt(AFilePath));
  if Parser = nil then
    Exit;
  Source := TFile.ReadAllBytes(AFilePath);
  Sha := THashSHA2.GetHashString(TEncoding.ANSI.GetString(Source));
  Mtime := DateTimeToUnix(TFile.GetLastWriteTime(AFilePath), False);
  // v0.4: incremental skip. If the file's already in the DB with the same
  // mtime and sha256, nothing to do - the parser would emit the same
  // symbols. Saves a parse + the per-file transaction.
  if FStore.FileIsUpToDate(AFilePath, Mtime, Sha) then
  begin
    Inc(FSkippedUpToDate);
    Exit;
  end;
  ParseRes := Parser.Parse(Source, AFilePath);
  // v0.16: scan doc-comment regions from the source text once per file
  // so we can associate them with symbols by line proximity below.
  SourceText := TEncoding.ANSI.GetString(Source);
  DocRegions := TDocCommentScanner.Scan(SourceText);
  Token := FStore.OpenFileTx(AFilePath, Mtime, Sha, Parser.LanguageName);
  // v0.16: clear stale doc rows for this file before emitting fresh ones
  // (OpenFileTx already cleared symbols and refs).
  FStore.DeleteFileDocs(Token.FileId);
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
        // v0.16: associate doc comment region to this symbol
        DocRegion := FindDocRegionAbove(DocRegions, Sym.StartLine);
        if DocRegion.Kind <> TDocCommentKind(-1) then
        begin
          ParsedDoc := TDocCommentParser.Dispatch(DocRegion);
          if ParsedDoc.HasContent then
            FStore.UpsertSymbolDoc(Token, NewSymId, ParsedDoc);
        end;
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
    DocRegions.Free;
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
