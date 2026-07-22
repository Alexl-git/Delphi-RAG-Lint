unit DRagLint.Doc.SymbolFacts;

// Auto-Document Phase 2, Task 1: the analysis-facts layer. TSymbolFacts
// itself lives in DRagLint.Core.Model (so ISymbolStore.Get/PutSymbolFacts can
// reference it without a circular interface-uses -- see Core.Interfaces).
// This unit holds the record<->DB-column serialize helpers for symbol_facts'
// CSV TEXT columns (reads_fields, writes_fields, sql_reads, sql_writes,
// covered_by); Storage.SQLite stores/reads those columns verbatim as plain
// text, and callers (T2's analyzer, later renderers) use these helpers to
// move between a TArray<string> and that stored CSV form. No analysis is
// performed here yet -- that is every later Phase 2 task's job.

interface

/// <summary>Joins AItems into the CSV text form stored in one of
/// symbol_facts' TEXT columns (ReadsFields, WritesFields, SqlReads,
/// SqlWrites, CoveredBy). Returns '' for an empty array. No escaping is
/// applied: entries are Pascal identifiers / qualified names, which never
/// contain a comma.</summary>
/// <param name="AItems">Field/table/test qualified names, in display order.</param>
function SymbolFactsCsvJoin(const AItems: TArray<string>): string;

/// <summary>Splits a symbol_facts CSV TEXT column back into its entries.
/// Inverse of SymbolFactsCsvJoin. '' (or a blank/whitespace-only string)
/// yields an empty array (never a 1-element array holding '').</summary>
/// <param name="ACsv">A raw symbol_facts TEXT column value, e.g. as returned
/// by ISymbolStore.GetSymbolFacts.</param>
function SymbolFactsCsvSplit(const ACsv: string): TArray<string>;

implementation

uses
  System.SysUtils
  , System.StrUtils
  ;

function SymbolFactsCsvJoin(const AItems: TArray<string>): string;
begin
  if Length(AItems) = 0 then Exit('');
  Result:= string.Join(',', AItems);
end;

function SymbolFactsCsvSplit(const ACsv: string): TArray<string>;
begin
  if Trim(ACsv) = '' then Exit(nil);
  Result:= SplitString(ACsv, ',');
end;

end.
