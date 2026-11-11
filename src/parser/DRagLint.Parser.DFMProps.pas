/// <summary>151 ST stub, owned by lane Y2: the dfm_properties producer -- every
/// property assignment of a text .dfm as TDfmPropertyRow rows.</summary>
/// <remarks>Spec: docs\superpowers\specs\2026-11-11-dfm-props-and-comment-facts.md.
/// The indexer (TIndexer.IndexFileBody) calls ExtractDfmPropertyRows for every
/// .dfm and hands the rows to ISymbolStore.PutFileFacts.</remarks>
unit DRagLint.Parser.DFMProps;

interface

uses
  DRagLint.Core.Model;

/// <summary>The property rows of one .dfm, in source order.</summary>
/// <param name="AFilePath">Full path of the .dfm (the producer may re-read it,
/// e.g. for a binary .dfm).</param>
/// <param name="AText">The decoded .dfm text; '' for a binary .dfm.</param>
/// <param name="AObjects">The file's dfm_objects rows (TParseResult.DfmObjects);
/// TDfmPropertyRow.ObjectOrdinal indexes this array.</param>
/// <returns>The rows; the ST stub returns an empty array.</returns>
function ExtractDfmPropertyRows(const AFilePath, AText: string;
  const AObjects: TArray<TDfmObjectRow>): TArray<TDfmPropertyRow>;

implementation

function ExtractDfmPropertyRows(const AFilePath, AText: string;  // dl:ok unused-parameter@20f3 -- 151 ST stub; lane Y2 implements the body
  const AObjects: TArray<TDfmObjectRow>): TArray<TDfmPropertyRow>;  // dl:ok unused-parameter@a7cc -- 151 ST stub; lane Y2 implements the body
begin
  Result:= nil; { 151 ST stub -- lane Y2 fills it }
end;

end.
