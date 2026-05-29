unit DRagLint.Core.Interfaces;

interface

uses
  System.SysUtils,
  DRagLint.Core.Model;

type
  ISymbolStore = interface
    ['{6B9F8AC4-3F19-4E1A-9D38-1A2C3B7EF501}']
    procedure Migrate;
    // v0.4: returns True if this file is already indexed at exactly this
    // mtime AND sha256 - so the indexer can skip re-parsing it.
    function FileIsUpToDate(const APath: string; AMtimeUnix: Int64;
      const ASha: string): Boolean;
    function OpenFileTx(const APath: string; AMtimeUnix: Int64;
      const ASha: string; const ALanguage: string): TFileTxToken;
    function UpsertSymbol(const AToken: TFileTxToken;
      const ASymbol: TSymbol): Int64;
    procedure UpsertReference(const AToken: TFileTxToken;
      const ARef: TReference);
    procedure UpsertChunk(const AToken: TFileTxToken; const AChunk: TChunk);
    procedure CommitFileTx(const AToken: TFileTxToken);
    procedure RollbackFileTx(const AToken: TFileTxToken);

    function FindSymbolsByExactName(const AName: string): TArray<TSymbol>;
    function FindSymbolsByQualifiedName(const AQName: string): TArray<TSymbol>;
    function FindReferencesTo(ASymbolId: Int64): TArray<TReference>;
    function FindCallersByName(const ACalleeName: string): TArray<TReference>;
    function FindSymbolsFuzzy(const APattern: string; ATopK: Integer = 10): TArray<TSymbol>;
    function GetFilePath(AFileId: Int64): string;
    function CountSymbols: Int64;
    function CountReferences: Int64;
    function CountFiles: Int64;

    // v0.17: blast-radius pack
    function FindTransitiveCallers(const ASymbolName: string;
      ADepth: Integer): TArray<TImpactLevel>;
    function GetClassSurface(const AQName: string;
      AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine>;
    function GetSymbolSlice(const AQName: string): TArray<TSliceChunk>;
    function FindCallersByNameWithContext(const ACalleeName: string;
      AContextLines: Integer): TArray<TReference>;

    procedure UpsertSymbolDoc(const AToken: TFileTxToken;
      ASymbolId: Int64; const ADoc: TParsedDoc);
    function GetSymbolDoc(ASymbolId: Int64): TParsedDoc;
    function FindByDocTag(const ATag: string): TArray<TSymbol>;
    function FindUndocumented(const AKind: string;
      APublicOnly: Boolean): TArray<TSymbol>;
    function FindByDocContains(const ASubstring: string): TArray<TSymbol>;
    procedure DeleteFileDocs(AFileId: Int64);

    // v0.18: bench-context — symbols that have at least one non-null summary
    function ListDocumentedSymbols(ALimit: Integer): TArray<TSymbol>;

    // v0.19: type-at-position helpers
    function FindContainingSymbol(AFileId: Int64; ALine: Integer): TSymbol;
    function FindFileIdByPath(const APath: string): Int64;
    function FindSymbolByExactNameAnywhere(const AName: string): TSymbol;
    function FindChildSymbolByName(AParentId: Int64;
      const AName: string): TSymbol;
  end;

  TParseResult = record
    Symbols: TArray<TSymbol>;
    References: TArray<TReference>;
    Chunks: TArray<TChunk>;
    Diagnostics: TArray<string>;
  end;

  IParser = interface
    ['{8C45D5A2-1B6E-4C2D-A3E8-9F0E7B41E612}']
    function LanguageName: string;
    function FileExtensions: TArray<string>;
    function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

  IIndexer = interface
    ['{2D8E7AC5-0F33-4B19-B25A-83C176D8EE7C}']
    procedure IndexFolder(const APath: string;
      ARecursive: Boolean = True);
    procedure IndexFile(const AFilePath: string);
    function SkippedUpToDate: Integer;
  end;

  ILinter = interface
    ['{F1C7E8D6-9A24-4F08-B7D2-46AC0E532D89}']
    function Run(const ARuleId: string = ''): TArray<TLintFinding>;
  end;

  IQueryEngine = interface
    ['{4A30E1B9-8F25-46D7-BCE1-2D5B97A4C4E0}']
    function FindCallers(const ASymbolName: string): TArray<TReference>;
    function FindOverrides(const ASymbolName: string): TArray<TSymbol>;
    function FindByName(const AName: string;
      AFuzzy: Boolean = False): TArray<TSymbol>;
  end;

implementation

end.
