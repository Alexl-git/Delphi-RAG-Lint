/// <summary>151 Y2: the dfm_properties producer -- every property assignment of a
/// text .dfm as TDfmPropertyRow rows.</summary>
/// <remarks>Spec: docs\superpowers\specs\2026-11-11-dfm-props-and-comment-facts.md.
/// The indexer (TIndexer.IndexFileBody) calls ExtractDfmPropertyRows for every
/// .dfm and hands the rows to ISymbolStore.PutFileFacts. The rows come from the
/// SAME tree-sitter-dfm object walk that writes dfm_objects
/// (DRagLint.Parser.DFM.ExtractDfmPropertyRowsFromBytes).</remarks>
unit DRagLint.Parser.DFMProps;

interface

uses
  DRagLint.Core.Model;

/// <summary>The property rows of one .dfm, in source order.</summary>
/// <param name="AFilePath">Full path of the .dfm; read only to name the file (a
/// binary .dfm is not converted -- it has no dfm_objects rows either).</param>
/// <param name="AText">The decoded .dfm text the indexer parsed (SourceText: the
/// file transcoded to UTF-8 by EnsureUtf8Bytes, BOM stripped, a BOM-less ANSI file
/// read as Windows-1252); '' for a binary .dfm.</param>
/// <param name="AObjects">The file's dfm_objects rows (TParseResult.DfmObjects);
/// TDfmPropertyRow.ObjectOrdinal indexes this array.</param>
/// <returns>The rows (see ExtractDfmPropertyRowsFromBytes for the row shape);
/// empty for AText = '' or a .dfm with no object. A row whose ObjectOrdinal is
/// outside AObjects (a text that does not walk to the same blocks) gets -1.</returns>
/// <remarks>Pure; one tree-sitter parse of AText per call.</remarks>
function ExtractDfmPropertyRows(const AFilePath, AText: string;
  const AObjects: TArray<TDfmObjectRow>): TArray<TDfmPropertyRow>;

implementation

uses
  System.SysUtils
  , DRagLint.Parser.DFM
  ;

function ExtractDfmPropertyRows(const AFilePath, AText: string;  // dl:ok unused-parameter@20f3 -- the path is part of the ST producer contract (a later binary-.dfm reader); the text is what the indexer parsed
  const AObjects: TArray<TDfmObjectRow>): TArray<TDfmPropertyRow>;
var
  I: Integer;
begin
  Result:= nil;
  if AText = '' then Exit;
  Result:= ExtractDfmPropertyRowsFromBytes(TEncoding.UTF8.GetBytes(AText));
  for I:= 0 to High(Result) do
    if Result[I].ObjectOrdinal > High(AObjects) then Result[I].ObjectOrdinal:= -1;
end;

end.
