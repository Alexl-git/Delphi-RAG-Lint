/// <summary>151 ST stub, owned by lane W1: the comment_facts producer -- every
/// comment of a source file as TCommentFactRow rows, with its anchor.</summary>
/// <remarks>Spec: docs\superpowers\specs\2026-11-11-dfm-props-and-comment-facts.md.
/// The indexer (TIndexer.IndexFileBody) calls ExtractCommentFacts for every
/// parsed file and hands the rows to ISymbolStore.PutFileFacts. Directives
/// ({$..} / (*$..*)) are not comments and get no row.</remarks>
unit DRagLint.Index.CommentFacts;

interface

uses
  DRagLint.Core.Model;

/// <summary>The comment rows of one file, in source order.</summary>
/// <param name="AFilePath">Full path of the file; the producer decides by its
/// extension which files have comment facts.</param>
/// <param name="AText">The decoded text the DocInsight scanner sees
/// (IndexFileBody's SourceText); offsets are into this text.</param>
/// <param name="ASymbols">The file's parsed symbols (TParseResult.Symbols);
/// TCommentFactRow.AnchorSymbolIdx indexes this array (-1 = none).</param>
/// <returns>The rows; the ST stub returns an empty array.</returns>
function ExtractCommentFacts(const AFilePath, AText: string;
  const ASymbols: TArray<TSymbol>): TArray<TCommentFactRow>;

implementation

function ExtractCommentFacts(const AFilePath, AText: string;  // dl:ok unused-parameter@7f17 -- 151 ST stub; lane W1 implements the body
  const ASymbols: TArray<TSymbol>): TArray<TCommentFactRow>;  // dl:ok unused-parameter@de7b -- 151 ST stub; lane W1 implements the body
begin
  Result:= nil; { 151 ST stub -- lane W1 fills it }
end;

end.
