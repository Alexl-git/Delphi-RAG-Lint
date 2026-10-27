unit DRagLint.Lint.TaintRules;

/// <summary>Interprocedural taint rules (taint-sql-injection, taint-command-injection,
/// taint-path-traversal): from every catalogued SINK site, walk the data_flows facts
/// backwards across routines, fields, globals and the library store until a catalogued
/// SOURCE, a sanitizer or a dead end; one finding per (sink site, source site) with its
/// path on TLintFinding.Path.</summary>
/// <remarks>
/// T0 (2026-10-27) is the CONTRACT commit: types, rule ids, the catalogue schema and
/// the Check signature; Check is an empty shell that returns nil. T2 implements the
/// walk (plan docs\superpowers\plans\2026-10-27-taint-interprocedural-plan.md
/// sections 4-7) and loads the catalogues.
///
/// CATALOGUE JSON SCHEMA (rules\taint-sources.json, rules\taint-sinks.json,
/// rules\taint-propagators.json; each file is ONE JSON object):
///   taint-sources.json     { "sources":     [ SOURCE, ... ] }
///   taint-sinks.json       { "sinks":       [ SINK, ... ] }
///   taint-propagators.json { "propagators": [ PROPAGATOR, ... ],
///                            "sanitizers":  [ SANITIZER, ... ] }
///   SOURCE     { "id": str (unique), "name": str (qualified 'Vcl.StdCtrls.TCustomEdit.Text'
///                or bare 'ParamStr'), "kind": "call"|"read", "confidence": "certain"|"weak",
///                "enabled": bool (default true; false = second-order, on via second_order),
///                "note": str (optional) }                                 -> TTaintSourceEntry
///   SINK       { "id": str (unique), "rule": one of the TAINT_RULE_* ids, "name": str (leaf
///                name of the call or written member), "kind": "call"|"write",
///                "args": [int, ...] (0-based argument positions; [] for "write" = the RHS),
///                "receiver_suffix": str (optional; matched against refs.receiver_text,
///                e.g. ".SQL"), "type": str (optional; owning type qname or bare name, the
///                resolved target's owner must be it or a descendant), "cwe": "CWE-89" }
///                                                                         -> TTaintSinkEntry
///   PROPAGATOR { "name": str, "args": [int, ...] (0-based; -1 = every argument),
///                "to": "result"|"receiver"|"outparam" (default "result"),
///                "out": int (the outparam position when "to" = "outparam"; else -1) }
///                                                                   -> TTaintPropagatorEntry
///   SANITIZER  { "name": str, "sanitizes": [ "sql"|"cmd"|"path"|"all", ... ] }
///                                                                    -> TTaintSanitizerEntry
/// The `taint` object of .drag-lint.json MERGES additively: keys "sources", "sinks",
/// "propagators", "sanitizers" (same row shapes, appended), "disable": [str] (removes a
/// built-in entry by "id"; propagators/sanitizers, which have no id, by "name"), and the
/// scalars of TTaintConfig under their JSON names (max_depth, lib_depth, max_rounds,
/// follow_ambiguous, weak_receiver_regex, weak_severity_drop, max_paths_per_sink,
/// second_order). Unknown-key handling follows the rest of TLintConfig (T2).
///
/// FIXTURE DB (what T2 develops against before T1 is green): index the fixture project
/// (tests\lint-project\taint\) with an engine built from T0 or later -- data_flows exists
/// and is empty -- then INSERT the rows T1 would emit, keyed by real ids:
/// symbol_id = symbols.id of the routine (by qualified_name), file_id = files.id (by path),
/// owner_id = the routine's parent class symbols.id or 0, every position = the
/// refs.start_line/start_col of the ref at that site; kinds = the DF_* text values;
/// via_local/cond 0|1. The INSERT script is T2's (python sqlite3, the run_purity_emit
/// technique); a real T1 index of the same fixture must give a superset of those rows.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Rule id: tainted data reaches an SQL text sink (error, CWE-89).</summary>
  TAINT_RULE_SQL  = 'taint-sql-injection';
  /// <summary>Rule id: tainted data reaches a process/shell launch sink (error, CWE-78).</summary>
  TAINT_RULE_CMD  = 'taint-command-injection';
  /// <summary>Rule id: tainted data reaches a file-system path sink (warning, CWE-22).</summary>
  TAINT_RULE_PATH = 'taint-path-traversal';
  /// <summary>Sanitizer category of TAINT_RULE_SQL.</summary>
  TAINT_CAT_SQL   = 'sql';
  /// <summary>Sanitizer category of TAINT_RULE_CMD.</summary>
  TAINT_CAT_CMD   = 'cmd';
  /// <summary>Sanitizer category of TAINT_RULE_PATH.</summary>
  TAINT_CAT_PATH  = 'path';
  /// <summary>Sanitizer category that stops every rule (StrToInt and friends).</summary>
  TAINT_CAT_ALL   = 'all';
  /// <summary>Every taint finding's message starts with this text (distinguishes it from the
  /// local shape rules in text and SARIF).</summary>
  TAINT_MSG_PREFIX = 'Tainted data reaches';

type
  /// <summary>One SOURCE catalogue row (rules\taint-sources.json "sources"[]).</summary>
  TTaintSourceEntry = record
    /// <summary>Unique id ("disable" key).</summary>
    Id        : string ;
    /// <summary>Qualified or bare name of the call / read member.</summary>
    Name      : string ;
    /// <summary>'call' (the call's result is tainted) or 'read' (the member read is).</summary>
    Kind      : string ;
    /// <summary>'certain' or 'weak'.</summary>
    Confidence: string ;
    /// <summary>False = off unless second_order (TField/TDataSet sources).</summary>
    Enabled   : Boolean;
    /// <summary>Free text.</summary>
    Note      : string ;
  end;

  /// <summary>One SINK catalogue row (rules\taint-sinks.json "sinks"[]).</summary>
  TTaintSinkEntry = record
    /// <summary>Unique id ("disable" key).</summary>
    Id            : string ;
    /// <summary>One of the TAINT_RULE_* ids.</summary>
    Rule          : string ;
    /// <summary>Leaf name of the call or written member.</summary>
    Name          : string ;
    /// <summary>'call' or 'write'.</summary>
    Kind          : string ;
    /// <summary>0-based argument positions that must not be tainted; empty for 'write'.</summary>
    Args          : TArray<Integer>;
    /// <summary>Required suffix of refs.receiver_text ('' = any).</summary>
    ReceiverSuffix: string ;
    /// <summary>Owning type the resolved target must be or descend from ('' = any; bare
    /// entries also match unresolved calls).</summary>
    TypeName      : string ;
    /// <summary>'CWE-89' etc.</summary>
    Cwe           : string ;
  end;

  /// <summary>One PROPAGATOR row (rules\taint-propagators.json "propagators"[]).</summary>
  TTaintPropagatorEntry = record
    /// <summary>Qualified or bare routine name.</summary>
    Name    : string ;
    /// <summary>0-based argument positions whose taint flows on; -1 = every argument.</summary>
    Args    : TArray<Integer>;
    /// <summary>'result', 'receiver' or 'outparam'.</summary>
    ToSlot  : string ;
    /// <summary>The outparam position when ToSlot = 'outparam'; else -1.</summary>
    OutIndex: Integer;
  end;

  /// <summary>One SANITIZER row (rules\taint-propagators.json "sanitizers"[]).</summary>
  TTaintSanitizerEntry = record
    /// <summary>Qualified or bare routine name.</summary>
    Name     : string ;
    /// <summary>TAINT_CAT_* values this sanitizer stops.</summary>
    Sanitizes: TArray<string>;
  end;

  /// <summary>The merged taint configuration: built-in catalogues plus the `taint`
  /// object of .drag-lint.json (see the unit remarks for the JSON shape).</summary>
  TTaintConfig = record
    /// <summary>Merged sources (disabled ones removed).</summary>
    Sources         : TArray<TTaintSourceEntry>;
    /// <summary>Merged sinks.</summary>
    Sinks           : TArray<TTaintSinkEntry>;
    /// <summary>Merged propagators.</summary>
    Propagators     : TArray<TTaintPropagatorEntry>;
    /// <summary>Merged sanitizers.</summary>
    Sanitizers      : TArray<TTaintSanitizerEntry>;
    /// <summary>JSON max_depth: walk depth safety cap (default 16).</summary>
    MaxDepth        : Integer;
    /// <summary>JSON lib_depth: hops inside the library store (default 4).</summary>
    LibDepth        : Integer;
    /// <summary>JSON max_rounds: fixpoint re-query rounds for a key on a cycle (default 4).</summary>
    MaxRounds       : Integer;
    /// <summary>JSON follow_ambiguous: follow 'ambiguous' call edges (default False).</summary>
    FollowAmbiguous : Boolean;
    /// <summary>JSON weak_receiver_regex: an unresolved `.Text` read on a receiver matching it is a
    /// weak source (default '(Edit|Memo|Combo|Input|Query|Param)').</summary>
    WeakReceiverRegex: string;
    /// <summary>JSON weak_severity_drop: a weak finding is one severity lower (default True).</summary>
    WeakSeverityDrop: Boolean;
    /// <summary>JSON max_paths_per_sink: findings per sink before "+N more paths" (default 3).</summary>
    MaxPathsPerSink : Integer;
    /// <summary>JSON second_order: enable Enabled=False (TField/TDataSet) sources (default False).</summary>
    SecondOrder     : Boolean;
    /// <summary>The defaults above with EMPTY catalogues (T2 fills them from rules\taint-*.json).</summary>
    /// <returns>A config with every scalar at its documented default.</returns>
    class function Defaults: TTaintConfig; static;
  end;

  /// <summary>Counters for the `--trace-lint` line
  /// `taint: sinks N, keys N, rows read N, library hops N, hits N, partial keys N, N ms`.</summary>
  TTaintStats = record
    /// <summary>Sink sites examined.</summary>
    Sinks      : Integer;
    /// <summary>Memo keys (routine, slot) evaluated.</summary>
    Keys       : Integer;
    /// <summary>data_flows rows read.</summary>
    RowsRead   : Integer;
    /// <summary>Hops taken inside the library store.</summary>
    LibraryHops: Integer;
    /// <summary>Source hits found (before the per-sink path cap).</summary>
    Hits       : Integer;
    /// <summary>Keys whose answer is partial (a cap or max_rounds was reached).</summary>
    PartialKeys: Integer;
    /// <summary>Wall time of Check.</summary>
    ElapsedMs  : Int64  ;
    /// <summary>True when the project store has data_flows but it is empty (indexed before
    /// extractor 1.26.0): the caller prints ONE stale-index note; no findings.</summary>
    StaleIndex : Boolean;
  end;

  /// <summary>The three taint rules over a store's data_flows facts.</summary>
  TTaintRules = class
    public
      /// <summary>Finds every taint path into a catalogued sink inside the scope files.</summary>
      /// <param name="AStore">The project store (must not be nil).</param>
      /// <param name="ALibStore">The library store the lint path already opened, or nil (library
      /// hops then resolve by bare name only, reported weak).</param>
      /// <param name="AScopeFileIds">files.id of the files being linted (sinks are searched only
      /// there; the walk may leave the scope and the project).</param>
      /// <param name="ACfg">The merged configuration.</param>
      /// <param name="AStats">Counters for --trace-lint; zeroed on entry.</param>
      /// <returns>One finding per (sink site, source site), RuleId one of TAINT_RULE_*, Message
      /// starting with TAINT_MSG_PREFIX, Path = source -> hops -> sink. T0 shell: nil.</returns>
      /// <remarks>Read-only on both stores. A store without data_flows (HasDataFlows False)
      /// returns nil with AStats.StaleIndex True.</remarks>
      class function Check(const AStore, ALibStore: ISymbolStore; const AScopeFileIds: TArray<Int64>;
                           const ACfg: TTaintConfig; out AStats: TTaintStats): TArray<TLintFinding>; static;
  end;

implementation

class function TTaintConfig.Defaults: TTaintConfig;
begin
  Result:= Default(TTaintConfig);
  Result.MaxDepth         := 16;
  Result.LibDepth         := 4;
  Result.MaxRounds        := 4;
  Result.FollowAmbiguous  := False;
  Result.WeakReceiverRegex:= '(Edit|Memo|Combo|Input|Query|Param)';
  Result.WeakSeverityDrop := True;
  Result.MaxPathsPerSink  := 3;
  Result.SecondOrder      := False;
end;

class function TTaintRules.Check(const AStore, ALibStore: ISymbolStore; const AScopeFileIds: TArray<Int64>;
                                 const ACfg: TTaintConfig; out AStats: TTaintStats): TArray<TLintFinding>;
begin
  AStats:= Default(TTaintStats);
  AStats.StaleIndex:= not AStore.HasDataFlows;
  Result:= nil; { T0 contract shell -- T2 implements (plan section 4) }
end;

end.
