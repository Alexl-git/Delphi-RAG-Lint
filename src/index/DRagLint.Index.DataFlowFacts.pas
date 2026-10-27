unit DRagLint.Index.DataFlowFacts;

/// <summary>Index-time data-flow facts: for one routine, which SOURCE (a declared
/// parameter, a field, a unit global, a feeding ref, the var/out slot of an earlier
/// call) can reach which DESTINATION (a call argument, a member write, a field or
/// global write, a var/out parameter of this routine, Result). The rows go to the
/// data_flows table (TDataFlowRow, DF_DST_* / DF_SRC_* in DRagLint.Core.Model) and
/// are composed across routines by the taint rules (DRagLint.Lint.TaintRules).</summary>
/// <remarks>
/// T0 (2026-10-27) is the CONTRACT commit: Collect is an empty shell that returns
/// nil, so an engine built from T0 alone stores no rows. T1 implements it (plan
/// docs\superpowers\plans\2026-10-27-taint-interprocedural-plan.md section 3):
/// TRoutineVarTable classification, a forward TTaintReach lattice over TCfgBuilder's
/// CFG (assignment kills+gens, receives gen, joins union), a flow-insensitive
/// fallback when the CFG is Skipped or over 2,000 blocks (every row Cond = True),
/// dedupe on (dst, src), and the DF_ROW_CAP cap. This unit is under src\index, so
/// the extractor version guard hashes it: any change to it is an extractor change.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , TreeSitter
  ;

type
  /// <summary>Computes the data_flows rows of one routine from its tree-sitter
  /// subtree. Stateless; safe to call from the indexer's per-file loop.</summary>
  TDataFlowFacts = class
    public
      /// <summary>The data_flows rows of routine ASym (see TDataFlowRow for every
      /// column's meaning).</summary>
      /// <param name="ASym">The routine symbol with its REAL identity: Id = symbols.id
      /// written in this file tx (becomes every row's SymbolId), ParentId = the owning
      /// class's symbols.id or -1 (becomes OwnerId, -1 -> 0).</param>
      /// <param name="AProc">The routine's defProc node.</param>
      /// <param name="ABody">The routine's body (block) node.</param>
      /// <param name="ASrc">The UTF-8 source bytes AProc/ABody index into.</param>
      /// <param name="AOwnerFields">Field names of the owning class (and ancestors known
      /// to this DB), as declared; empty for a plain routine.</param>
      /// <param name="AGlobals">This unit's unit-level variable names, as declared.</param>
      /// <returns>The rows, deduplicated, at most DF_ROW_CAP; nil when nothing is
      /// proven. FileId is left 0 (PutDataFlows takes it from the file tx).</returns>
      /// <remarks>T0 shell: always returns nil. Never raises for a malformed tree --
      /// an unclassifiable shape emits nothing (silence over a wrong claim).</remarks>
      class function Collect(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                             const AOwnerFields: TArray<string>;
                             const AGlobals: TArray<string>): TArray<TDataFlowRow>; static;
  end;

implementation

class function TDataFlowFacts.Collect(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                                      const AOwnerFields: TArray<string>;
                                      const AGlobals: TArray<string>): TArray<TDataFlowRow>;
begin
  Result:= nil; { T0 contract shell -- T1 implements (plan section 3) }
end;

end.
