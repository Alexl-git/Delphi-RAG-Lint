unit indexcoverage;

interface

// Auto-Document Phase 3, Task 3c: TParsedDoc.HasContent's OR-chain omits
// ExampleText/SeeAlso/SinceText, and Core.Indexer.pas only calls
// FStore.UpsertSymbolDoc when HasContent is True -- so a comment whose ONLY
// tag is one of these three produces NO symbol_docs row at all. The symbol
// then reads as entirely undocumented to the index, context bundles, MCP,
// and LSP hover/completion, even though the author wrote real documentation.
//
// Each row below carries EXACTLY ONE of the three affected tags and nothing
// else (no summary, no returns tag, no params, no exception, not deprecated)
// so the gap is exercised in isolation, one shape per symbol, rather than
// masked by some OTHER disjunct of HasContent already being True.
// NoCommentControl has no doc comment at all -- it proves "a symbol_docs row
// exists" is not vacuously true for every symbol regardless of content; a
// regression that made the indexer write a row unconditionally would still
// pass the three positive checks but would be caught by this control.

/// <example>WriteLn('example only');</example>
procedure ExampleOnlySymbol;

/// <seealso cref="Other.RelatedThing"/>
procedure SeeAlsoOnlySymbol;

/// <since>1.0</since>
procedure SinceOnlySymbol;

procedure NoCommentControl;

implementation

procedure ExampleOnlySymbol;
begin
end;

procedure SeeAlsoOnlySymbol;
begin
end;

procedure SinceOnlySymbol;
begin
end;

procedure NoCommentControl;
begin
end;

end.
