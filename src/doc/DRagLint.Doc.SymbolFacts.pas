unit DRagLint.Doc.SymbolFacts;

// Auto-Document Phase 2, Task 1: the analysis-facts layer. TSymbolFacts
// itself lives in DRagLint.Core.Model (so ISymbolStore.Get/PutSymbolFacts can
// reference it without a circular interface-uses -- see Core.Interfaces).
// This unit holds the record<->DB-column serialize helpers for symbol_facts'
// CSV TEXT columns (reads_fields, writes_fields, sql_reads, sql_writes,
// covered_by); Storage.SQLite stores/reads those columns verbatim as plain
// text, and callers (T2's analyzer, later renderers) use these helpers to
// move between a TArray<string> and that stored CSV form.
//
// Task 2 adds TSymbolFactsAnalyzer, the index-time entry point that produces
// one TSymbolFacts row per routine symbol. Its Analyze signature is final as
// of Task 2 -- Tasks 3-8 each fill in one group of fields inside the SAME
// function body (Cyclomatic/BodyLoc, ReadsFields/WritesFields, ReturnsOwner,
// DfmEvent, SqlReads/SqlWrites, CoveredBy respectively) without ever changing
// the signature, so the indexer's call site (DRagLint.Core.Indexer.IndexFile)
// is written once, here, and never touched again. This unit intentionally
// does NOT uses DRagLint.Core.Indexer: the Indexer uses THIS unit, so a
// back-reference would be a circular unit dependency.

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

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

type
  /// <summary>Index-time analyzer that derives a TSymbolFacts row for one
  /// routine symbol -- the single call site the indexer uses for every fact
  /// group Phase 2 will ever add (see the unit banner comment).</summary>
  TSymbolFactsAnalyzer = class
    public
      /// <summary>Analyzes ASym's body and returns the TSymbolFacts row to
      /// persist for it. Task 2 returned an EMPTY-but-Present record; Task 3
      /// (ADP2) fills in Cyclomatic/BodyLoc (see below); Tasks 4-8 populate
      /// the remaining groups one at a time. Never returns Present=False (the
      /// indexer only calls this for a symbol it is about to write a row
      /// for).</summary>
      /// <param name="ASym">The routine symbol being analyzed. Result.SymbolId
      /// is seeded from ASym.Id, but the caller (the indexer) always
      /// overwrites it with the just-inserted DB id afterward -- ASym.Id may
      /// still be a pre-insert placeholder at the point Analyze runs.</param>
      /// <param name="AFilePath">Path to ASym's source file (ADP2 T3) -- the
      /// indexer's own IndexFile parameter, passed through unchanged. Needed
      /// because the indexer's TParseResult carries no tree-sitter tree (only
      /// extracted symbols/refs); this is how Analyze reaches the AST (via
      /// TAstParseCache.Get, memoized per file) for Cyclomatic.</param>
      /// <param name="ABody">The routine's implementation body, one source
      /// line per array entry (ASym.ImplStartLine..ImplEndLine, 1-based),
      /// already bounds-clipped by the caller. Unused by Task 3 (BodyLoc is
      /// pure symbol-range arithmetic, not a text scan); a later fact group
      /// may use it.</param>
      /// <param name="AStore">Read-only access to the rest of the index, for
      /// facts that need a cross-symbol lookup (e.g. DFM event bindings, SQL
      /// table references). Unused by Task 3.</param>
      /// <returns>A TSymbolFacts record with Present=True.</returns>
      /// <remarks>ADP2 T3: Cyclomatic is 0 when no defProc in AFilePath's tree
      /// starts at ASym.ImplStartLine (e.g. AFilePath unreadable/unparseable) --
      /// absence over a wrong number, never fabricated. BodyLoc is always
      /// ImplEndLine - ImplStartLine (clamped to >= 0), independent of the AST.</remarks>
      class function Analyze(const ASym: TSymbol; const AFilePath: string; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , TreeSitter                        { ADP2 T3: TTSNode for the AST-derived Cyclomatic fact }
  , DRagLint.Diagnostics.ParseCache    { ADP2 T3: TAstParseCache -- memoized per-file tree, owned by the cache }
  , DRagLint.Analysis.Cfg              { ADP2 T3: CfgFindProcs -- collect every defProc in the file's tree }
  , DRagLint.Diagnostics.AstChecks     { ADP2 T3: TAstChecker.CyclomaticOf -- ONE shared formula with the lint rule }
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

class function TSymbolFactsAnalyzer.Analyze(const ASym: TSymbol; const AFilePath: string; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts;
var
  PF   : TParsedFile     ;
  Procs: TArray<TTSNode> ;
  Proc : TTSNode         ;
  Body : TTSNode         ;
begin
  // Every fact field starts at Default(TSymbolFacts)'s zero value; Task 3
  // (ADP2) fills in Cyclomatic/BodyLoc below. Tasks 4-8 populate
  // ReadsFields/WritesFields/ReturnsOwner/DfmEvent/SqlReads/SqlWrites/
  // CoveredBy in turn, each inside this same function body -- ABody/AStore
  // stay unused until then.
  Result:= Default(TSymbolFacts);
  Result.SymbolId:= ASym.Id;
  Result.Present := True;

  // BodyLoc: pure symbol-range arithmetic, no AST needed. Clamped to >= 0 as
  // a defensive guard (mirrors TIndexer.SliceBodyLines' Lo/Hi clip) though
  // ImplEndLine >= ImplStartLine always holds for a real routine body.
  Result.BodyLoc:= ASym.ImplEndLine - ASym.ImplStartLine;
  if Result.BodyLoc < 0 then Result.BodyLoc:= 0;

  // Cyclomatic: find the defProc node whose OWN StartPoint matches
  // ASym.ImplStartLine -- the EXACT provenance the parser used to stamp
  // ImplStartLine in the first place (DRagLint.Parser.Delphi13's defProc walk
  // calls SetRoutineImplRange(..., Integer(ANode.StartPoint.row) + 1, ...)
  // where ANode IS the defProc), so this lookup is guaranteed to find the
  // right routine whenever the same source parses the same way twice.
  // TAstParseCache.Get is memoized per file (see this unit's banner comment
  // and the indexer's facts-pass comment): the FIRST Analyze call for a file
  // parses it; every other routine in the SAME file reuses the cached tree --
  // one extra parse PER FILE (on top of the indexer's own parse), not per
  // routine. CfgFindProcs (DRagLint.Analysis.Cfg) collects every defProc in
  // the tree; an O(routines-in-file) linear scan then matches by line -- no
  // positional (point-based) node lookup is exposed by the TTSNode API, and
  // this walk is accepted as index-time cost (see the Phase 2 design).
  PF:= TAstParseCache.Get(AFilePath);
  if PF.Tree <> nil then
  begin
    Procs:= CfgFindProcs(PF.Tree.RootNode);
    for Proc in Procs do
      if Integer(Proc.StartPoint.Row) + 1 = ASym.ImplStartLine then
      begin
        Body:= Proc.ChildByField('body');
        Result.Cyclomatic:= TAstChecker.CyclomaticOf(Body);
        Break;
      end;
    // No matching defProc: Cyclomatic stays 0 (absence over a wrong number --
    // e.g. a stale/mismatched parse, or ASym's file changed between the
    // indexer's own parse and this cache lookup).
  end;
end;

end.
