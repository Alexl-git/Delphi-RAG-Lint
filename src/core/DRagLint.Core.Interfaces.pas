unit DRagLint.Core.Interfaces;

interface

uses
  System.SysUtils,
  DRagLint.Core.Model;

type
  ISymbolStore = interface
    ['{6B9F8AC4-3F19-4E1A-9D38-1A2C3B7EF501}']
    procedure Migrate;
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
    function CountSymbols: Int64;
    function CountFiles: Int64;
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
