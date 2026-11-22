unit DRagLint.CLI.Convert;

// ---------------------------------------------------------------------------
// The component-conversion verb family (lane v1511 SPLIT, T07): proptree, convert-validate, convert-reemit,
// convert-scaffold, convert-apply and glyph-vacuum, with their tree-depth / progress helpers and the
// apply/1 JSON writer. Moved verbatim out of DRagLint.CLI; the analysis lives in DRagLint.Convert.*.
// ---------------------------------------------------------------------------

interface

uses
  System.JSON, DRagLint.Convert.Rules, DRagLint.CLI.Common;

/// <summary>drag-lint proptree --qname X [--depth N] [--rules FILE] [--no-to-persistent]
/// [--refs-as-leaves] [--min-visibility published|public] [--format text|json] [--json] --db PATH
/// [--db ...] -- Track 3 Batch 1: the index-driven RECURSIVE deep-property
/// enumerator. Resolves class X, walks its own + inherited kind='property'
/// children, parses each property's type from its Signature, and recurses into
/// class-typed property types (depth-capped + a visited-TYPE-name cycle guard) to
/// produce flattened dotted paths (Font.Color, Inner.Shade). Depth is --depth N,
/// else the --rules book's '#depth N', else 5 (ResolveTreeDepth; a bad --depth,
/// --depth &lt; 1 or a bad '#depth' is exit 2). ToPersistent (default ON) stops the ancestor
/// climb at TPersistent/TObject; --no-to-persistent climbs past. --refs-as-leaves
/// (TreatRefsAsLeaves, default OFF) emits a property whose type descends from
/// TComponent as a REFERENCE LEAF instead of recursing into it -- a referenced
/// component is not an owned sub-object -- while owned TPersistent sub-objects
/// (TFont, ...) still expand. text = an
/// indented tree (indent = the path's dot-depth); json = schema proptree/2 (v2:
/// adds per-leaf visibility/is_writable/member_kind; additive over proptree/1).
/// --min-visibility published|public filters the EMITTED leaves by EFFECTIVE
/// (most-derived) visibility: unset (default) emits ALL leaves exactly as
/// proptree/1 did (back-compat); 'published' emits only published leaves;
/// 'public' emits published+public leaves. Applies to both text and json output.
/// With multiple --db, the first DB that resolves the qname to a class is used
/// (ids are per-DB). Write-back is AUTOMATIC: the resolving index is opened
/// WRITABLE so a property type recovered by the lazy ancestry-bridge (across an
/// unresolved/type-alias ancestor edge) is memoized back onto the property row
/// (next query is a plain hit; self-limiting). A writable open that fails falls
/// back to read-only (resolution still works; memoization skipped). --no-write-back
/// forces a read-only (query_only) open that never mutates the DB; killing the
/// process mid-run is safe (each memoized type is its own SQLite statement).
/// --progress-interval S (default 0 = off) writes one JSON progress line to
/// STDERR at most every S seconds while the tree is built (MakeProgressWriter);
/// stdout is unchanged.</summary>
/// <param name="AArgs">QName=class, DepthGiven/DepthRaw=--depth and
/// RulesFile=--rules (recursion cap, see ResolveTreeDepth; default 5),
/// ToPersistent=ancestor-stop, RefsAsLeaves=--refs-as-leaves (TComponent-typed
/// properties are reference leaves, not expanded), NoWriteBack=force read-only
/// (no memoization),
/// MinVisibility=--min-visibility filter ('' = all), Format/AsJson=output,
/// DbPath/DbPaths=index(es).</param>
/// <returns>0 ok; 1 qname not resolved to a class in any DB; 2 usage error / no
/// readable db / invalid --min-visibility value / invalid --depth or --rules
/// book depth / invalid --progress-interval.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: Copy, Default, DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.CLI.Common.OpenWritableStore, DRagLint.CLI.Common.ReportNotFoundFor, DRagLint.CLI.Common.StaleDbRefusesRun, DRagLint.CLI.Common.WriteStdoutDocument, DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs, DRagLint.CLI.Convert.DoPropTree.KindLabel (+13 more)</para>
/// <para>Returns: 2; 1; 0</para>
/// <para>Complexity: 27 (cyclomatic, outer body), 182 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.CLI.Common.OpenWritableStore"/>
/// <seealso cref="DRagLint.CLI.Common.ReportNotFoundFor"/>
/// <seealso cref="DRagLint.CLI.Common.StaleDbRefusesRun"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoPropTree(const AArgs: TArgs): Integer;

/// <summary>drag-lint convert-validate --rules FILE [--from FromType] [--to ToType]
/// [--print-parsed] [--db PATH ...] -- Track 3 Batch 1: parse a reFind-superset
/// conversion-rules DSL file and (when --from/--to types are supplied) validate its
/// #link / #default target/source paths against the REAL members of those types,
/// each path resolved segment by segment (1.20.6, T2b: TPropMemberCache -- no property
/// tree is built, so --depth no longer applies and no path is too deep; a published
/// leaf, each hop published or public-and-class-typed, never private). --rules is required (missing -&gt; usage + exit 2;
/// unreadable -&gt; exit 2). Without --from/--to it is parse-only: only unknown-
/// directive parse errors are reported, path checks are skipped. --print-parsed
/// dumps 'parsed N rule(s)' plus one 'line L: kind ...' summary per rule (so a test
/// can assert the parse result with no trees). A literal '???' path is an explicit
/// STUB marker (the scaffolder emits these) and is NOT a path error. A #link
/// glyph expression (G[I/N] grammar) is checked in either mode, and a problem
/// names the column inside the expression. Prints 'line N: message' per error,
/// then 'line N: warning: message' per warning -- first each UNREACHABLE path
/// (T2h, owner ruling R12: every segment exists but one fails the .dfm surface,
/// 'line N: warning: &lt;path&gt;: &lt;Member&gt; is &lt;visibility&gt; in
/// &lt;Class&gt;; never applied unless a descendant class changes its
/// visibility'), then ConversionRuleWarnings -- all on stdout, then 'OK' when
/// there were no errors; warnings never change the exit code. No JSON mode.</summary>
/// <param name="AArgs">RulesFile=--rules; CallFrom=--from (FromType qname),
/// RenameTo=--to (ToType qname); PrintParsed=--print-parsed; ToPersistent=--no-to-persistent;
/// DbPath/DbPaths=index(es) the from/to classes are resolved in.</param>
/// <returns>0 valid / parse-ok; 1 errors found (parse or validation); 2 bad args
/// (no --rules) or unreadable rules file.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: ConvertClassIn, Default, DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs, DRagLint.CLI.Convert.AmbiguousArgMessage, DRagLint.CLI.Convert.DoConvertValidate.ClassFor, DRagLint.CLI.Convert.DoConvertValidate.RuleSummary, DRagLint.CLI.Convert.QualifyConvertArg, DRagLint.Convert.Apply.MigrateRuleRefusal, DRagLint.Convert.Rules.ConversionRuleWarnings (+10 more)</para>
/// <para>Returns: 2; 1; 0</para>
/// <para>Complexity: 23 (cyclomatic, outer body), 222 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs"/>
/// <seealso cref="DRagLint.CLI.Convert.AmbiguousArgMessage"/>
/// <seealso cref="DRagLint.CLI.Convert.DoConvertValidate.ClassFor"/>
/// <seealso cref="DRagLint.CLI.Convert.DoConvertValidate.RuleSummary"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoConvertValidate(const AArgs: TArgs): Integer;

/// <summary>drag-lint convert-reemit --from-block FILE --rules FILE --from FromType
/// --to ToType --db PATH -- HIDDEN test verb driving the pure ReemitComponent
/// engine. Prints the emitted T DFM block + report as JSON. Not in help/README;
/// superseded by convert-apply (2a-iii).</summary>
/// <param name="AArgs">FromBlockFile=--from-block (one F DFM object block file);
/// RulesFile=--rules; CallFrom=--from (FromType qname), RenameTo=--to (ToType
/// qname); DbPath/DbPaths=index(es) the from/to classes are resolved in.</param>
/// <returns>0 when Ok; 1 on a hard re-emit failure; 2 on bad args.</returns>
/// <remarks>
/// Resolves the F/T classes from the index (like convert-validate,
/// same first-DB-that-resolves-wins loop, ConvertClassIn -- 1.20.6: no property
/// tree is built, each dotted path is resolved lazily), parses the rules DSL, calls
/// ReemitComponent, and serializes the result. Read-only against the store.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.Common.WriteStdoutDocument, DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs, DRagLint.CLI.Convert.AmbiguousArgMessage, DRagLint.CLI.Convert.ConvertClassIn, DRagLint.CLI.Convert.DoConvertReemit.ArrJson, DRagLint.CLI.Convert.QualifyConvertArg, DRagLint.CLI.Convert.UnreachableJson, DRagLint.Convert.CastLib.ParseCastLib (+7 more)</para>
/// <para>Returns: 2; 1</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 175 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.Common.WriteStdoutDocument"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs"/>
/// <seealso cref="DRagLint.CLI.Convert.AmbiguousArgMessage"/>
/// <seealso cref="DRagLint.CLI.Convert.ConvertClassIn"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoConvertReemit(const AArgs: TArgs): Integer;

/// <summary>drag-lint convert-scaffold --from FromType --to ToType [--output FILE]
/// [--surface dfm|pas] --db PATH [--db ...] -- Track 3 Batch 1: auto-generate a
/// VALID reFind-superset conversion-rules file from the REAL deep-property trees
/// of the From and To types (Task 1's BuildPropTree over BOTH), pre-filling the
/// assignments it can safely infer and leaving only genuine ambiguities as '???'
/// for the user to resolve. --from (reuses CallFrom) and --to (reuses RenameTo)
/// are BOTH required (missing -&gt; usage + exit 2). --output (reuses Output) writes
/// an ASCII/CRLF file; omitted -&gt; stdout. Multiple --db are tried in order; the
/// FIRST db that resolves BOTH types is used (ids are per-DB). If either type is
/// unresolved the verb names it and exits 1. Both trees expand to --depth N, else
/// the --rules book's '#depth N', else 5 (ResolveTreeDepth; a bad value exits 2).
/// proptree assignability engine (Task 5): auto-'#link' TARGETS (the To side
/// only -- From remains an unrestricted candidate SOURCE pool) are restricted to
/// leaves that are actually valid assignment targets, using the is_writable/
/// visibility/member_kind fields BuildPropTree already stamps onto every
/// TPropNode (Tasks 2-4; no extra wiring needed since convert-scaffold's To tree
/// comes from the SAME BuildPropTree call as `proptree`). --surface dfm (the
/// default) requires member_kind='property' AND the effective visibility=
/// 'published' -- the DFM-streamable surface, matching today's dominant
/// component-conversion use case; --surface pas relaxes the bar to visibility in
/// ('published','public'), ANY member_kind (so a public FIELD can be a target
/// too). On EITHER surface a leaf with is_writable=false (a typed class CONST
/// today; a read-only PROPERTY once a later task extracts real property
/// writability) is NEVER a valid target. A To path that fails either bar is
/// fully excluded from the per-To-path loop -- no '#link', no '#default', no
/// '#note' -- mirroring how `proptree --min-visibility` silently drops a
/// tier-failing leaf with no extra annotation (the existing convention for "not
/// part of this surface"; the DSL's own '#ignore' directive was considered and
/// rejected -- it acknowledges an unmapped FROM path, a different direction,
/// not a filtered TO target). A To path's own Visibility='' (defensive-only in
/// practice -- the current parser always stamps a non-empty value; see
/// DRagLint.Convert.PropTree's ResolveInheritedVisibility remark) is treated as
/// PASSING the bar on both surfaces -- graceful degrade so an old/foreign DB
/// row whose visibility could not be resolved is never MORE aggressively
/// filtered than today's "show everything", matching a proptree/1-style
/// consumer's back-compat default. The FROM-side DROPPED-note loop (3) uses the
/// SAME valid-target test, so a From path whose only leaf-name+type counterpart
/// is a filtered-out To leaf is correctly reported DROPPED rather than silently
/// neither linked nor noted.</summary>
/// <param name="AArgs">CallFrom=--from (FromType qname), RenameTo=--to (ToType
/// qname), Output=--output (file; empty=stdout), Surface=--surface dfm|pas ('' =
/// default 'dfm'), DepthGiven/DepthRaw=--depth and RulesFile=--rules (tree
/// depth, see ResolveTreeDepth), ProgressIntervalGiven/ProgressIntervalRaw=
/// --progress-interval S (default 0 = off; one JSON line on STDERR at most every
/// S seconds while the two trees are built, see MakeProgressWriter; stdout is
/// unchanged), DbPath/DbPaths=index(es).</param>
/// <returns>0 success; 1 either type unresolved in every db; 2 bad args (missing
/// --from/--to, invalid --surface value, invalid --depth or book #depth, invalid
/// --progress-interval) or no readable db (an explicit --db that is missing or stale is exit 2).</returns>
/// <remarks>
/// Output is DETERMINISTIC (paths sorted case-insensitively) so the
/// emitted text is stable across runs. Emission order: (1) a '#convert From -&gt;
/// To' header with a best-guess ', unit' uses-add taken from the qname unit
/// prefix(es) of From/To when discoverable (never fabricated); (2) for each
/// VALID-TARGET To path (sorted; see the surface/writability filter above) the F
/// candidates whose LEAF name equals the To leaf (case-insensitive) AND whose
/// declared TypeName is compatible (equal, case-insensitive) -- exactly ONE
/// candidate -&gt; a concrete '#link ToPath &lt;- FromPath'; MULTIPLE -&gt; '#link
/// ToPath &lt;- ???' immediately followed by '#note candidates: p1, p2, ...';
/// ZERO -&gt; '#default ToPath = ???'; (3) for each From path (sorted) with NO
/// compatible VALID-TARGET To counterpart (same leaf+type test, reversed) a
/// '#note DROPPED FromPath (no T target)'. The matching rule is LEAF-NAME +
/// COMPATIBLE-TYPE (documented, not exact-path), so a leaf name that appears at
/// more than one From path is correctly flagged ambiguous. Every concrete path
/// emitted is guaranteed to exist in the real trees and every '???' is tolerated
/// by the validator, so the emitted file round-trips clean through
/// convert-validate. Read-only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: Copy, Default, DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.CLI.Common.StaleDbRefusesRun, DRagLint.CLI.Common.WriteStdoutDocument, DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs, DRagLint.CLI.Convert.DoConvertScaffold.FromCandidates, DRagLint.CLI.Convert.DoConvertScaffold.IsValidTarget, DRagLint.CLI.Convert.DoConvertScaffold.LeafLower (+17 more)</para>
/// <para>Returns: 2; 0</para>
/// <para>Complexity: 30 (cyclomatic, outer body), 289 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.CLI.Common.StaleDbRefusesRun"/>
/// <seealso cref="DRagLint.CLI.Common.WriteStdoutDocument"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoConvertScaffold(const AArgs: TArgs): Integer;

/// <summary>`drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...]`: extracts and decodes every streamed graphic of the .dfm/.fmx under the roots into --output.</summary>
/// <param name="AArgs">--root (one or more), --output, --append, --db (only qualifies, never guesses).</param>
/// <returns>0 on a completed walk (0 graphics is an answer); 2 on bad args or a missing root.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.CLI.Common.StaleDbRefusesRun, DRagLint.Convert.GlyphVacuum.RunGlyphVacuum, Format, Writeln</para>
/// <para>Returns: 2; 0</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.CLI.Common.StaleDbRefusesRun"/>
/// <seealso cref="DRagLint.Convert.GlyphVacuum.RunGlyphVacuum"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoGlyphVacuum(const AArgs: TArgs): Integer;

/// <summary>apply/1 unreachable[] and convert-reemit's: one object per UNREACHABLE rule path (line, path, member, visibility, class, reason, message).</summary>
/// <param name="AItems">The unreachable paths.</param>
/// <returns>A new array; the caller owns it.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Convert.DoConvertReemit (DRagLint.CLI.Convert.pas), DRagLint.CLI.ConvertApplyJson.EmitApplyJson (DRagLint.CLI.ConvertApplyJson.pas)</para>
/// <para>Returns: TJSONArray.Create</para>
/// <para>Owns returned: new (caller owns)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UnreachableJson(const AItems: TArray<TUnreachablePath>): TJSONArray;

/// <summary>S as a quoted JSON string, escaped, non-ASCII as \u -- for the hand-built progress line.</summary>
/// <param name="S">The text.</param>
/// <returns>The JSON string literal, quotes included.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Convert.MakeProgressWriter (DRagLint.CLI.Convert.pas), DRagLint.CLI.ConvertApply.DoConvertApply.ReportUnitProgress (DRagLint.CLI.ConvertApply.pas)</para>
/// <para>Returns: J.ToJSON</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProgressJsonStr(const S: string): string;

implementation

uses
  DRagLint.CLI.ConsumerDbs, Winapi.Windows, DRagLint.Core.OutputEncoding, System.SysUtils, System.Classes,
  System.IOUtils, System.NetEncoding, System.StrUtils, System.DateUtils, System.Generics.Collections,
  System.Diagnostics, System.SyncObjs, System.Math, Data.DB, FireDAC.Stan.Async, FireDAC.Stan.Param,
  FireDAC.DApt, TreeSitter, DRagLint.Core.Interfaces, DRagLint.Convert.PropTree, DRagLint.Convert.PropCache,
  DRagLint.Convert.CastLib, DRagLint.Convert.GlyphVacuum, DRagLint.Convert.DfmReemit, DRagLint.Convert.Apply;

/// <summary>The tree-expansion depth of proptree / convert-scaffold:
/// --depth N &gt; the --rules book's '#depth N' &gt; DEFAULT_TREE_DEPTH (5).</summary>
/// <param name="AArgs">DepthGiven/DepthRaw=--depth; RulesFile=--rules.</param>
/// <param name="ADepth">The depth to expand to (&gt;= 1); only meaningful when the
/// result is True.</param>
/// <returns>True when ADepth is set; False on a usage error, already printed
/// as one 'ERROR: ...' line (the caller exits 2): --depth that is not decimal
/// digits ('+3', '$A' and '-1' included -- the IsDecimalDigits check '#depth'
/// uses) or is &lt; 1; a --rules file that is missing or unreadable; a book whose
/// '#depth' is invalid or repeated (named by file and line).</returns>
/// <remarks>The book is read whenever --rules is given, even beside --depth, so
/// a broken '#depth' never goes unnoticed; its other parse errors are ignored
/// here (convert-validate reports them). Depth is the class-recursion budget:
/// a K-segment path needs depth &gt;= K-1.</remarks>
function ResolveTreeDepth(const AArgs: TArgs; out ADepth: Integer): Boolean;
var
  Book: TConversionRuleSet;
  E   : TRuleError        ;
  Bad : Boolean           ;
begin
  Result:= False;
  ADepth:= DEFAULT_TREE_DEPTH;
  Book  := Default(TConversionRuleSet);
  if AArgs.RulesFile <> '' then
  begin
    if not TFile.Exists(AArgs.RulesFile) then
    begin
      Writeln(Format('ERROR: rules file not found: %s', [AArgs.RulesFile]));
      Exit;
    end;
    try
      Book:= ParseConversionRules(TFile.ReadAllText(AArgs.RulesFile));
    except
      on Ex: Exception do
      begin
        Writeln(Format('ERROR: cannot read rules file: %s (%s)', [AArgs.RulesFile, Ex.Message]));
        Exit;
      end;
    end;
    Bad:= False;
    for E in Book.ParseErrors do
      if E.IsDepthError then
      begin
        Writeln(Format('ERROR: %s line %d: %s', [AArgs.RulesFile, E.LineNo, E.Message]));
        Bad:= True;
      end;
    if Bad then Exit;
  end;
  if AArgs.DepthGiven then
  begin
    // Decimal digits only, exactly like '#depth': TryStrToInt alone takes '+3'
    // and '$A' (hex).
    if not IsDecimalDigits(AArgs.DepthRaw) or not TryStrToInt(AArgs.DepthRaw, ADepth) or
      (ADepth < MIN_BOOK_DEPTH) then
    begin
      Writeln(Format('ERROR: --depth must be an integer >= 1 (got "%s")', [AArgs.DepthRaw]));
      Exit;
    end;
  end
  else if Book.Depth > 0 then
    ADepth:= Book.Depth;
  Result:= True;
end;

const
  MAX_PROGRESS_INTERVAL_S = 86400; // one day; keeps S * 1000 inside an Integer

/// <summary>The progress interval of proptree / convert-scaffold, from
/// --progress-interval S (engine 1.20.6, T2e).</summary>
/// <param name="AArgs">ProgressIntervalGiven/ProgressIntervalRaw.</param>
/// <param name="AMs">The interval in milliseconds; 0 = off -- the default
/// (flag absent) and S = 0 alike. Only meaningful when the result is
/// True.</param>
/// <returns>True when AMs is set; False on a usage error, already printed as
/// one 'ERROR: ...' line (the caller exits 2): S that is not decimal digits
/// (a sign, a '$' hex prefix, a decimal point -- the IsDecimalDigits check
/// '#depth' and --depth use) or is above 86400.</returns>
function ResolveProgressInterval(const AArgs: TArgs; out AMs: Integer): Boolean;
var
  Secs: Integer;
begin
  AMs:= 0;
  if not AArgs.ProgressIntervalGiven then Exit(True);
  if not IsDecimalDigits(AArgs.ProgressIntervalRaw) or not TryStrToInt(AArgs.ProgressIntervalRaw, Secs) or
    (Secs > MAX_PROGRESS_INTERVAL_S) then
  begin
    Writeln(Format('ERROR: --progress-interval must be an integer 0..%d (seconds; got "%s")',
      [MAX_PROGRESS_INTERVAL_S, AArgs.ProgressIntervalRaw]));
    Exit(False);
  end;
  AMs   := Secs * MS_PER_SECOND;
  Result:= True;
end;

// S as a quoted JSON string ("..."), escaped, non-ASCII as \u -- for the
// progress line, which is built by hand to fix its key order and number format.
function ProgressJsonStr(const S: string): string;
var
  J: TJSONString;
begin
  J:= TJSONString.Create(S);
  try
    Result:= J.ToJSON;
  finally
    J.Free;
  end;
end;

/// <summary>The TPropTreeOptions.OnProgress handler of a tree-expanding verb:
/// writes each snapshot as ONE JSON line to STDERR (engine 1.20.6, T2e).</summary>
/// <param name="AVerb">'proptree' or 'convert-scaffold' (the line's "verb").</param>
/// <returns>A handler that writes
/// {"progress":{"elapsed_s":12.3,"verb":"proptree","class":"Unit.TX","depth":2,
/// "max_depth":5,"classes_done":41,"classes_queued":7,"nodes":3114}}
/// -- keys in exactly that order, no blanks, 7-bit ASCII (the class name is
/// JSON-escaped, non-ASCII as \u), elapsed_s with one decimal and a '.' in
/// every locale.</returns>
/// <remarks>elapsed_s counts from THIS call (the verb's arguments are valid by
/// then), so it is non-decreasing across convert-scaffold's two trees; the
/// other fields are TPropTreeProgress's. STDOUT is never written, so the
/// verb's own output is byte-identical with or without progress; a caller
/// that merges the streams (the editor slices the first '{' .. the last '}')
/// must leave progress OFF, which is the default.</remarks>
function MakeProgressWriter(const AVerb: string): TProc<TPropTreeProgress>;
var
  Clock: TStopwatch;
begin
  Clock:= TStopwatch.StartNew;
  Result:= procedure(P: TPropTreeProgress)
  begin
    Writeln(ErrOutput, Format('{"progress":{"elapsed_s":%s,"verb":%s,"class":%s,"depth":%d,' +
      '"max_depth":%d,"classes_done":%d,"classes_queued":%d,"nodes":%d}}',
      [FormatFloat('0.0', Clock.ElapsedMilliseconds / MS_PER_SECOND, TFormatSettings.Invariant),
       ProgressJsonStr(AVerb), ProgressJsonStr(P.RootQName), P.Level, P.MaxDepth, P.ClassesDone, P.ClassesQueued, P.Nodes]));
    Flush(ErrOutput);
  end;
end;

function DoPropTree(const AArgs: TArgs): Integer;
var
  Dbs   : TArray<string>  ;
  Db    : string          ;
  Store : ISymbolStore    ;
  Tree  : TPropTree       ;
  Found : Boolean         ;
  Depth : Integer         ;
  Fmt   : string          ;
  Opts  : TPropTreeOptions;
  MinVis: string          ;
  ProgMs: Integer         ;

  function KindLabel(const ANode: TPropNode): string;
  begin
    Result:= ANode.Kind;
  end;

  // proptree/2 (Task 2, R2): does ANode's effective visibility pass the
  // --min-visibility threshold? AMinVis is already lower-cased/trimmed/
  // validated by the caller ('' | 'published' | 'public').
  // R4 (Task 4 review fix): a FIELD is never a DFM-streamable target,
  // regardless of its own declared visibility -- a `published FBtn:
  // TButton;` field is legal Delphi and DOES get Modifiers='published'
  // stamped by the same declField/CurrentVisibility path a published
  // PROPERTY gets, but proptree's 'published' tier specifically means "the
  // Object Inspector / DFM-streamed property surface", which fields (even
  // published ones) are not part of. This is a member_kind-based FILTER
  // exclusion only -- the node's own Visibility value is NEVER altered
  // (KindLabel/JSON emit still reports the field's real, e.g. 'published',
  // visibility); only whether it PASSES the 'published' bar changes.
  function PassesMinVisibility(const ANode: TPropNode; const AMinVis: string): Boolean;
  var
    Vis: string;
  begin
    if AMinVis = '' then Exit(True); // unset = emit ALL leaves (back-compat)
    if (AMinVis = 'published') and (SameText(Trim(ANode.MemberKind), 'field')) then Exit(False);
    Vis:= LowerCase(Trim(ANode.Visibility));
    if AMinVis = 'published' then Exit(Vis = 'published');
    Result:= (Vis = 'published') or (Vis = 'public'); // AMinVis = 'public'
  end;

begin
  if not ExplicitDbsExist(AArgs, 'proptree') then Exit(2);
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint proptree --qname X [--depth N] [--rules FILE] [--progress-interval S] [--no-to-persistent] [--refs-as-leaves] [--no-write-back] [--min-visibility published|public] [--format text|json] [--json] --db PATH [--db ...]');
    Exit(2);
  end;

  Fmt:= LowerCase(Trim(AArgs.Format));

  // proptree/2 (Task 2, R2): validate --min-visibility up front (usage error,
  // not a silent fall-through) so a typo does not silently emit ALL leaves.
  MinVis:= LowerCase(Trim(AArgs.MinVisibility));
  if (MinVis <> '') and (MinVis <> 'published') and (MinVis <> 'public') then
  begin Writeln(Format('ERROR: --min-visibility must be published|public (got "%s")', [AArgs.MinVisibility]));
  Exit(2); end;

  // --depth > the --rules book's #depth > 5. Before 1.20.6 this read AArgs.Depth,
  // whose parse default is 3, so a proptree with no --depth ran at 3, not the
  // documented 6.
  if not ResolveTreeDepth(AArgs, Depth) then Exit(2);
  if not ResolveProgressInterval(AArgs, ProgMs) then Exit(2);

  Opts:= Default(TPropTreeOptions);
  Opts.Depth            := Depth;
  Opts.ToPersistent     := AArgs.ToPersistent;
  Opts.TreatRefsAsLeaves:= AArgs.RefsAsLeaves;
  Opts.ProgressIntervalMs:= ProgMs;
  if ProgMs > 0 then Opts.OnProgress:= MakeProgressWriter('proptree');

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.');
  Exit(2); end;

  // Multi-db resolution: use the FIRST db whose qname resolves to a class
  // (RootType non-empty). Exit 2 if no --db is readable; exit 1 if none resolve.
  Store:= nil;
  Found:= False;
  Tree := Default(TPropTree);
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    var RoOk: Boolean;
    // Write-back is AUTOMATIC: open the index WRITABLE by default so a bridged type
    // is memoized onto the property row (next query is a plain hit). --no-write-back
    // forces a read-only (query_only) open that never mutates the DB. A writable
    // open that fails (locked / read-only file / stale schema) falls back to
    // read-only so resolution still works -- memoization is best-effort.
    var CandidateStore: ISymbolStore;
    if AArgs.NoWriteBack then CandidateStore:= OpenReadOnlyStore(Db, RoOk)
    else
    begin
      CandidateStore:= OpenWritableStore(Db, RoOk);
      if not RoOk then CandidateStore:= OpenReadOnlyStore(Db, RoOk); // graceful read-only fallback
    end;
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'proptree', Db) then Exit(2);
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    Store:= CandidateStore; // at least one readable db
    var Candidate: TPropTree:= BuildPropTree(CandidateStore, AArgs.QName, Opts);
    if Candidate.RootType <> '' then
    begin
      Tree := Candidate;
      Found:= True;
      Break;
    end;
  end;
  if Store = nil then begin Writeln('ERROR: no readable drag-lint index among --db path(s)');
  Exit(2); end;
  if not Found then
  begin
    ReportNotFoundFor(AArgs.AsJson or SameText(AArgs.Format, 'json'), Format('class not found: %s', [AArgs.QName]));
    Exit(1);
  end;

  if (Fmt = 'json') or ((Fmt = '') and AArgs.AsJson) then
  begin
    var JRoot: TJSONObject:= TJSONObject.Create;
    try
      JRoot.AddPair('schema'   , 'proptree/2'    );
      JRoot.AddPair('qname'    , AArgs.QName      );
      JRoot.AddPair('root_type', Tree.RootType    );
      JRoot.AddPair('truncated', TJSONBool.Create(Tree.Truncated));
      var JProps: TJSONArray:= TJSONArray.Create;
      for var N in Tree.Nodes do
      begin
        if not PassesMinVisibility(N, MinVis) then Continue;
        var JN: TJSONObject:= TJSONObject.Create;
        JN.AddPair('path'          , N.Path      );
        JN.AddPair('type'          , N.TypeName  );
        JN.AddPair('declared_in'   , N.DeclaredIn);
        JN.AddPair('kind'          , KindLabel(N));
        JN.AddPair('is_class_typed', TJSONBool.Create(N.IsClassTyped));
        JN.AddPair('visibility'    , N.Visibility);
        JN.AddPair('is_writable'   , TJSONBool.Create(N.IsWritable));
        JN.AddPair('member_kind'   , N.MemberKind);
        { The `default` clause. ADDITIVE to proptree/2. has_default=false covers
          `nodefault`, a bare `default;` (the default-ARRAY-PROPERTY directive,
          which carries no value) and no clause at all -- in every one of those
          the property is always streamed, so its absence from a .dfm is
          genuinely unknown rather than "at its default". }
        JN.AddPair('has_default'   , TJSONBool.Create(N.HasDefault));
        JN.AddPair('default_value' , N.DefaultValue);
        JProps.AddElement(JN);
      end;
      JRoot.AddPair('properties', JProps);
      // One document, one write, after every stderr byte (WriteStdoutDocument):
      // the bytes Writeln(JRoot.Format(2)) wrote before T2i.
      WriteStdoutDocument(JRoot.Format(2) + sLineBreak);
    finally
      JRoot.Free;
    end;
  end
  else // text (default, or explicit --format text)
  begin
    var ShownCount: Integer:= 0;
    for var N in Tree.Nodes do
      if PassesMinVisibility(N, MinVis) then Inc(ShownCount);
    // One document, one write (WriteStdoutDocument): the same lines Writeln
    // wrote one by one before T2i, each ended by sLineBreak as Writeln ends it.
    var Doc: TStringBuilder:= TStringBuilder.Create;
    try
      Doc.Append(Format('%s  (%d properties%s)', [Tree.RootType, ShownCount,
        IfThen(Tree.Truncated, ', truncated', '')])).Append(sLineBreak);
      for var N in Tree.Nodes do
      begin
        if not PassesMinVisibility(N, MinVis) then Continue;
        // Indent by the path's dot-depth (top-level = 0).
        var DotDepth: Integer:= 0;
        for var Ch in N.Path do if Ch = '.' then Inc(DotDepth);
        var Leaf: string:= N.Path;
        var LastDot: Integer:= LastDelimiter('.', N.Path);
        if LastDot > 0 then Leaf:= Copy(N.Path, LastDot + 1, MaxInt);
        Doc.Append(Format('%s%s: %s [%s]', [StringOfChar(' ', DotDepth * 2), Leaf, N.TypeName, KindLabel(N)])).Append(sLineBreak);
      end;
      WriteStdoutDocument(Doc.ToString);
    finally
      Doc.Free;
    end;
  end;
  Result:= 0;
end; // function

{ convert-validate / convert-reemit: the --from / --to name AName as the
  #convert classes of convert-apply resolve it, with no unit to scope it
  (TConvertTreeCache.ScopedClass with no SetScope): a qualified name is taken
  as written; a bare one is settled by the book's own qualification of it (the
  first #convert whose From -- AToSide: To -- has that bare tail), else by a
  lone unit-level declarer. Returns the qualified name, or AName unchanged when
  it is qualified or resolves nowhere (the verbs' exact-name lookup then
  decides, as before). AScoped carries the answer; PAS_RES_AMBIGUOUS means
  the caller must refuse. Opens ADbs read-only; a DB that does not open is
  skipped (ConvertClassIn reports it). }
function QualifyConvertArg(const ADbs: TArray<string>; const ARules: TConversionRuleSet;
  const AName: string; AToSide: Boolean; out AScoped: TScopedClass): string;
var
  Stores: TArray<ISymbolStore>;
begin
  Result := AName;
  AScoped:= Default(TScopedClass);
  if (Trim(AName) = '') or (AName.Contains('.')) then Exit;
  var Hint: string:= '';
  for var R: TConversionRule in ARules.Rules do
    if (R.Kind = rkConvert) and (Hint = '') then
    begin
      var Spelled: string:= if AToSide then R.ToType else R.FromType;
      if SameText(Copy(Spelled, LastDelimiter('.', Spelled) + 1, MaxInt), Trim(AName)) then Hint:= Spelled;
    end;
  Stores:= nil;
  for var LDb: string in ADbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    var RoOk: Boolean;
    var St: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
    if RoOk then Stores:= Stores + [St];
  end;
  var Trees: TConvertTreeCache:= TConvertTreeCache.Create(Stores);
  try
    AScoped:= Trees.ScopedClass(AName, Hint);
  finally
    Trees.Free;
  end;
  if AScoped.Resolution = PAS_RES_RESOLVED then Result:= AScoped.QName;
end;

{ The refusal for an ambiguous --from / --to (QualifyConvertArg; owner ruling
  2026-10-11: detailed, with the fix): an 'ERROR:' line naming the candidates,
  then one ready-to-use argument per candidate. }
function AmbiguousArgMessage(const AFlag, AName: string; const AScoped: TScopedClass): string;
begin
  var QNames: TArray<string>:= nil;
  for var C: string in AScoped.Candidates do QNames:= QNames + [C + '.' + AName];
  Result:= Format('ERROR: %s %s is ambiguous -- declared by %s (no unit to scope it; the book does not qualify it). ' +
    'Qualify it, or qualify the book''s #convert line. Nothing was validated against a guess',
    [AFlag, AName, String.Join(', ', AScoped.Candidates)]);
  for var Q: string in QNames do Result:= Result + sLineBreak + Format('  use: %s %s', [AFlag, Q]);
end;

{ convert-validate / convert-reemit: the class AQName names in the first of ADbs
  whose index has it (a stale explicit --db sets AStale and stops, as
  StaleDbRefusesRun rules; a stale manifest DB is skipped). Each store opened
  gets its own TPropMemberCache, added to ACaches (which owns it); the result
  pairs AQName with the cache of the store that resolved it. Unset when AQName
  is '' or resolves nowhere. 1.20.6 (T2b): replaces the two verbs' TreeFor, which
  built a whole property tree per type. }
function ConvertClassIn(const AArgs: TArgs; const AVerb: string; const ADbs: TArray<string>;
  const AQName: string; const AOpts: TPropTreeOptions; ACaches: TObjectList<TPropMemberCache>;
  var AStale: Boolean): TClassRef;
var
  LDb  : string;
  Cache: TPropMemberCache;
begin
  Result:= Default(TClassRef);
  if AQName = '' then Exit;
  for LDb in ADbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    var RoOk: Boolean;
    var CandStore: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, AVerb, LDb) then
      begin
        AStale:= True;
        Exit;
      end;
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    Cache:= TPropMemberCache.Create(CandStore, AOpts);
    ACaches.Add(Cache);
    if Cache.MembersOf(AQName).RootType <> '' then
    begin
      Result.QName:= AQName;
      Result.Cache:= Cache;
      Exit;
    end;
  end;
end;

function DoConvertValidate(const AArgs: TArgs): Integer;
var
  RulesText: string             ;
  RuleSet  : TConversionRuleSet ;
  Errors   : TArray<TRuleError> ;
  FromCls  : TClassRef          ;
  ToCls    : TClassRef          ;
  Opts     : TPropTreeOptions   ;
  Dbs      : TArray<string>     ;
  Caches   : TObjectList<TPropMemberCache>; { one per store opened -- owns them }
  E        : TRuleError         ;
  R        : TConversionRule    ;
  { ClassFor returns a TClassRef, so it cannot Exit(2) on a stale explicit --db.
    It raises this flag instead and the body refuses right after the calls. }
  StaleExplicitDb: Boolean      ;
  Unreach  : TArray<TUnreachablePath>; { T2h: paths through inaccessible members -- warnings }
  U        : TUnreachablePath   ;

  function KindStr(const AKind: TRuleKind): string;
  begin
    case AKind of
      rkUnuse  : Result:= 'unuse';
      rkRemove : Result:= 'remove';
      rkMigrate: Result:= 'migrate';
      rkConvert: Result:= 'convert';
      rkLink   : Result:= 'link';
      rkDefault: Result:= 'default';
      rkNote   : Result:= 'note';
      rkPcre   : Result:= 'pcre';
      rkIgnore : Result:= 'ignore';
      rkUse    : Result:= 'use';
      rkUseSwap: Result:= 'useswap';
      rkMapping: Result:= 'mapping';
      rkApply  : Result:= 'apply';
      rkDepth  : Result:= 'depth';
      rkWarn    : Result:= 'warn';
      rkCheckRef: Result:= 'check-ref';
    else        Result:= '?';
    end;
  end;

  // Render a #mapping branch's set list as 'A = 1, B = 2'. A pair with an empty
  // Value prints as the bare ToPath -- the shape the editor's parser accepts and
  // re-emits, so the printer must not invent an '=' that the source lacked.
  function SetsSummary(const ASets: TArray<TMappingSetPair>): string;
  var
    Parts: TArray<string>;
    P    : TMappingSetPair      ;
  begin
    Parts:= nil;
    for P in ASets do
      if P.Value = '' then
        Parts:= Parts + [P.ToPath]
      else
        Parts:= Parts + [P.ToPath + ' = ' + P.Value];
    Result:= String.Join(', ', Parts);
  end;

  // One-line summary of a parsed rule's key fields (for --print-parsed).
  function RuleSummary(const R: TConversionRule): string;
  begin
    case R.Kind of
      rkUnuse  : Result:= Format('unuse %s', [R.UnitName]);
      rkRemove : Result:= Format('remove %s%s', [R.PropName, IfThen(R.DfmOnly, ' (DFM-only)', '')]);
      rkMigrate: Result:= Format('migrate %s%s -> %s%s', [R.Scope, R.Old, R.New,
                            IfThen(Length(R.UnitsAdd) > 0, ' [+' + String.Join(',', R.UnitsAdd) + ']', '')]);
      rkConvert: Result:= Format('convert %s -> %s%s', [R.FromType, R.ToType,
                            IfThen(Length(R.UnitsAdd) > 0, ' [+' + String.Join(',', R.UnitsAdd) + ']', '')]);
      { The cast is printed as a SEPARATE, LABELLED field, not re-joined onto
        FromPath with ' : '. Re-joining is what this printer used to do by
        accident -- it echoed the corrupted FromPath as `link Size <- Size :
        Round`, which reads exactly like a captured cast and is why the parser
        defect survived a review of this very output. A reader must be able to
        tell "the cast was captured" from "the path swallowed it". }
      rkLink   : Result:= Format('link %s <- %s%s%s', [R.ToPath, R.FromPath,
                            IfThen(R.GlyphExpr <> '', ' [glyph ' + R.GlyphExpr + ']', ''),
                            IfThen(R.Cast <> '', ' [cast ' + R.Cast + ']', '')]);
      rkDefault: Result:= Format('default %s = %s', [R.ToPath, R.Value]);
      rkNote   : Result:= Format('note %s', [R.Text]);
      rkPcre   : Result:= Format('pcre %s -> %s', [R.Search, R.Replace]);
      rkIgnore : Result:= Format('ignore FromPath=%s', [R.FromPath]);
      rkUse    : Result:= Format('use %s', [R.UnitName]);
      rkUseSwap: Result:= Format('useswap %s -> %s', [R.UnitName, String.Join(', ', R.UnitsAdd)]);
      { A #mapping is THREE flat sibling line forms sharing only <Name>, so the
        summary must show WHICH form this line is -- a declaration, a #when or a
        #else -- or a reader cannot tell a captured condition from a lost one.
        Same lesson as the rkLink cast above: print the parts separately. }
      rkMapping: if R.IsElse then
                   Result:= Format('mapping %s #else -> %s', [R.MapName, SetsSummary(R.Sets)])
                 else if R.WhenFrom <> '' then
                   Result:= Format('mapping %s #when %s = %s -> %s',
                              [R.MapName, R.WhenFrom, R.WhenValue, SetsSummary(R.Sets)])
                 else if R.MapFromType <> '' then
                   Result:= Format('mapping %s from %s to %s',
                              [R.MapName, R.MapFromType, String.Join(', ', R.MapToTypes)])
                 else
                   Result:= Format('mapping %s', [R.MapName]);
      rkApply  : Result:= Format('apply %s', [R.MapName]);
      rkDepth  : Result:= Format('depth %d', [R.Depth]);
      rkWarn    : Result:= Format('warn %s "%s"', [R.FromPath, R.Text]);
      rkCheckRef: Result:= Format('check-ref %s -> %s', [R.ToPath, String.Join(', ', R.RefTargets)]);
    else        Result:= KindStr(R.Kind);
    end;
  end;

  // The class a type qname names across the resolved DBs (first DB that resolves
  // it wins), with that store's member cache. Unset if unresolved / no db.
  function ClassFor(const AQName: string): TClassRef;
  begin
    Result:= ConvertClassIn(AArgs, 'convert-validate', Dbs, AQName, Opts, Caches, StaleExplicitDb);
  end;

begin
  if not ExplicitDbsExist(AArgs, 'convert-validate') then Exit(2);
  if AArgs.RulesFile = '' then
  begin
    Writeln('Usage: drag-lint convert-validate --rules FILE [--from FromType] [--to ToType] [--print-parsed] [--glyph-stitch] [--db PATH ...]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin Writeln(Format('ERROR: rules file not found: %s', [AArgs.RulesFile]));
  Exit(2); end;

  try
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin Writeln(Format('ERROR: cannot read rules file: %s (%s)', [AArgs.RulesFile, Ex.Message]));
    Exit(2); end;
  end;

  RuleSet:= ParseConversionRules(RulesText);

  if AArgs.PrintParsed then
  begin
    Writeln(Format('parsed %d rule(s)', [Length(RuleSet.Rules)]));
    for R in RuleSet.Rules do
      Writeln(Format('line %d: %s', [R.LineNo, RuleSummary(R)]));
    for E in RuleSet.ParseErrors do
      Writeln(Format('line %d: parse error: %s', [E.LineNo, E.Message]));
  end;

  // Resolve the from/to classes when the types are supplied. Ids are per-DB, so
  // each side is paired with the cache of the store it resolved in. When neither
  // is given this is parse-only: only parse errors surface (unset sides skip
  // path checks). Referenced components are expanded, as they always were here.
  Opts:= Default(TPropTreeOptions);
  Opts.ToPersistent:= AArgs.ToPersistent;

  Dbs     := ResolveConsumerDbs(AArgs);
  StaleExplicitDb:= False; { a local Boolean is not zero-initialised }
  Caches  := TObjectList<TPropMemberCache>.Create(True);
  try
  { a bare --from / --to resolves as convert-apply's #convert classes do --
    the book's own qualification, else a lone unit-level declarer -- and an
    ambiguous one is refused below, never guessed }
  var FromScoped, ToScoped: TScopedClass;
  var FromName: string:= QualifyConvertArg(Dbs, RuleSet, AArgs.CallFrom, False, FromScoped);
  var ToName  : string:= QualifyConvertArg(Dbs, RuleSet, AArgs.RenameTo, True, ToScoped);
  FromCls := ClassFor(FromName); // --from reuses CallFrom
  ToCls   := ClassFor(ToName);   // --to   reuses RenameTo
  { ClassFor cannot Exit(2) from inside a function returning a class, so the
    refusal it could only flag is enforced here. }
  if StaleExplicitDb then Exit(2);
  if (FromScoped.Resolution = PAS_RES_AMBIGUOUS) or (ToScoped.Resolution = PAS_RES_AMBIGUOUS) then
  begin
    if FromScoped.Resolution = PAS_RES_AMBIGUOUS then Writeln(AmbiguousArgMessage('--from', AArgs.CallFrom, FromScoped));
    if ToScoped.Resolution = PAS_RES_AMBIGUOUS then Writeln(AmbiguousArgMessage('--to', AArgs.RenameTo, ToScoped));
    Exit(1);
  end;

  Errors:= ValidateConversionRules(RuleSet, FromCls, ToCls, Unreach);
  if AArgs.GlyphStitch then
  begin
    { --from names ONE class, so only the blocks converting THAT class are judged. }
    var GlyphBlocks: TArray<TBlockClasses>:= [Default(TBlockClasses)];
    for var GR: TConversionRule in RuleSet.Rules do
      if GR.Kind = rkConvert then
      begin
        var GB: TBlockClasses:= Default(TBlockClasses);
        if SameText(GR.FromType.Substring(GR.FromType.LastIndexOf('.') + 1), FromCls.QName.Substring(FromCls.QName.LastIndexOf('.') + 1)) then GB.FromClass:= FromCls;
        GlyphBlocks:= GlyphBlocks + [GB];
      end;
    Errors:= Errors + MissingGlyphCountReaders(RuleSet, GlyphBlocks);
  end;
  finally
    Caches.Free;
  end;

  for E in Errors do
    Writeln(Format('line %d: %s', [E.LineNo, E.Message]));
  { Warnings never change the exit code: the book is valid, just suspicious.
    T2h (owner ruling R12): a path through an inaccessible member first, each
    its whole 'line N: warning: ...' text, on stdout beside the errors. }
  for U in DistinctUnreachable(Unreach) do
    Writeln(U.Message);
  for E in ConversionRuleWarnings(RuleSet) do
    Writeln(Format('line %d: warning: %s', [E.LineNo, E.Message]));
  { G3: a member #migrate (inside a #convert block) convert-apply will not
    realise -- its own refusal sentence; a file-scope #migrate is not a member
    migration and is left alone, as convert-apply does }
  var InBlock: Boolean:= False;
  for R in RuleSet.Rules do
  begin
    InBlock:= InBlock or (R.Kind = rkConvert);
    if not InBlock or (R.Kind <> rkMigrate) then Continue;
    { 1.38 (D2): a plain rule naming uses units is an identifier #migrate,
      which convert-apply realises }
    var Plain: TConversionRule:= R;
    Plain.UnitsAdd:= nil;
    if (Length(R.UnitsAdd) > 0) and (MigrateRuleRefusal(Plain) = '') then Continue;
    var Why: string:= MigrateRuleRefusal(R);
    if Why <> '' then
      Writeln(Format('line %d: warning: #migrate %s -> %s is not applied by convert-apply -- %s', [R.LineNo, R.Old, R.New, Why]));
  end;

  { 1.26.1: without both types the paths were never checked -- say so (on
    stderr, so the stdout contract 'OK' is unchanged), or a bare run reads as
    a validated book. }
  if (AArgs.CallFrom = '') or (AArgs.RenameTo = '') then
    Writeln(ErrOutput, 'NOTE: --from and --to not both given -- the book was PARSED only; #link/#default paths were not checked (convert-apply validates every block)');
  if Length(Errors) > 0 then Exit(1);
  if not AArgs.PrintParsed then Writeln('OK');
  Result:= 0;
end; // function

{ T2h (owner ruling R12): apply/1 unreachable[] and convert-reemit's -- one
  object per UNREACHABLE rule path, keys line, path, member, visibility,
  class, reason (always 'unreachable') and message (the exact text line), in
  that order. The caller owns the array. }
function UnreachableJson(const AItems: TArray<TUnreachablePath>): TJSONArray;
var
  U : TUnreachablePath;
  JU: TJSONObject;
begin
  Result:= TJSONArray.Create;
  for U in AItems do
  begin
    JU:= TJSONObject.Create;
    JU.AddPair('line'      , TJSONNumber.Create(U.LineNo));
    JU.AddPair('path'      , U.Path);
    JU.AddPair('member'    , U.Member);
    JU.AddPair('visibility', U.Visibility);
    JU.AddPair('class'     , U.DeclaringClass);
    JU.AddPair('reason'    , 'unreachable');
    JU.AddPair('message'   , U.Message);
    Result.AddElement(JU);
  end;
end;

function DoConvertReemit(const AArgs: TArgs): Integer;
var
  FromCls  : TClassRef          ;
  ToCls    : TClassRef          ;
  Rules    : TConversionRuleSet ;
  Res      : TReemitResult      ;
  Opts     : TPropTreeOptions   ;
  Caches   : TObjectList<TPropMemberCache>; { one per store opened -- owns them }
  Dbs      : TArray<string>     ;
  BlockText: string             ;
  RulesText: string             ;
  JRoot    : TJSONObject        ;
  JReport  : TJSONObject        ;
  { ConvertClassIn cannot Exit(2) on a stale explicit --db. It raises this flag
    instead and the body refuses right after the calls. }
  StaleExplicitDb: Boolean      ;
  Unreach  : TArray<TUnreachablePath>; { T2h: skipped, and listed in unreachable[] }

  function ArrJson(const A: TArray<string>): TJSONArray;
  var S: string;
  begin
    Result:= TJSONArray.Create;
    for S in A do Result.Add(S);
  end;

begin
  if not ExplicitDbsExist(AArgs, 'convert-reemit') then Exit(2);
  if (AArgs.FromBlockFile = '') or (AArgs.RulesFile = '') or
     (AArgs.CallFrom = '') or (AArgs.RenameTo = '') then
  begin
    Writeln('Usage: drag-lint convert-reemit --from-block FILE --rules FILE --from FromType --to ToType --db PATH');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.FromBlockFile) then
  begin Writeln('from-block not found: ' + AArgs.FromBlockFile);
  Exit(2); end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin Writeln('rules not found: ' + AArgs.RulesFile);
  Exit(2); end;

  try
    BlockText:= TFile.ReadAllText(AArgs.FromBlockFile);
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin Writeln(Format('ERROR: cannot read input file (%s)', [Ex.Message]));
    Exit(2); end;
  end;

  Rules:= ParseConversionRules(RulesText);
  { Same refusal as convert-apply: a G-link is not realised yet (CV-2), and
    re-emitting without it would carry the source image whole. }
  var Unrealised: TArray<TRuleError>:= UnrealisedGlyphLinks(Rules);
  if Length(Unrealised) > 0 then
  begin
    for var U in Unrealised do Writeln(Format('ERROR: line %d: %s', [U.LineNo, U.Message]));
    Exit(1);
  end;

  // Resolve the F/T classes in the first DB that resolves each qname (the same
  // store-open + multi-db loop as convert-validate: ConvertClassIn). Referenced
  // components are expanded, as they always were in this verb.
  Opts:= Default(TPropTreeOptions);
  Opts.ToPersistent:= AArgs.ToPersistent;

  Dbs     := ResolveConsumerDbs(AArgs);
  StaleExplicitDb:= False; { a local Boolean is not zero-initialised }
  Caches  := TObjectList<TPropMemberCache>.Create(True);
  try
  { a bare --from / --to: convert-validate's rule (QualifyConvertArg) }
  var FromScoped, ToScoped: TScopedClass;
  var FromName: string:= QualifyConvertArg(Dbs, Rules, AArgs.CallFrom, False, FromScoped);
  var ToName  : string:= QualifyConvertArg(Dbs, Rules, AArgs.RenameTo, True, ToScoped);
  FromCls := ConvertClassIn(AArgs, 'convert-reemit', Dbs, FromName, Opts, Caches, StaleExplicitDb); // --from reuses CallFrom
  ToCls   := ConvertClassIn(AArgs, 'convert-reemit', Dbs, ToName, Opts, Caches, StaleExplicitDb);   // --to   reuses RenameTo
  if StaleExplicitDb then Exit(2);
  if (FromScoped.Resolution = PAS_RES_AMBIGUOUS) or (ToScoped.Resolution = PAS_RES_AMBIGUOUS) then
  begin
    if FromScoped.Resolution = PAS_RES_AMBIGUOUS then Writeln(AmbiguousArgMessage('--from', AArgs.CallFrom, FromScoped));
    if ToScoped.Resolution = PAS_RES_AMBIGUOUS then Writeln(AmbiguousArgMessage('--to', AArgs.RenameTo, ToScoped));
    Exit(1);
  end;

  { T2h (owner ruling R12): a #link / #default / #mapping path through a member
    that exists but is inaccessible is skipped, as in convert-apply. Only the
    unreachable half of the validation is used here -- this verb never refused
    on a missing path, and does not start to. }
  ValidateConversionRules(Rules, FromCls, ToCls, Unreach);
  Res:= ReemitComponent(BlockText, Rules, FromCls, ToCls, ParseCastLib(AArgs.CastLibFile), Unreach);
  finally
    Caches.Free;
  end;

  JRoot:= TJSONObject.Create;
  try
    JRoot.AddPair('ok', TJSONBool.Create(Res.Ok));
    JRoot.AddPair('error', Res.Error);
    JRoot.AddPair('dfm', Res.DfmText);
    JReport:= TJSONObject.Create;
    JReport.AddPair('dropped',    ArrJson(Res.Report.Dropped));
    JReport.AddPair('ignored',    ArrJson(Res.Report.Ignored));
    JReport.AddPair('mismatched', ArrJson(Res.Report.Mismatched));
    JReport.AddPair('created',    ArrJson(Res.Report.Created));
    JReport.AddPair('ownedParts', ArrJson(Res.Report.OwnedParts));
    JReport.AddPair('stubs',      ArrJson(Res.Report.Stubs));
    JReport.AddPair('relocated',  ArrJson(Res.Report.Relocated));
    var JCarried: TJSONArray:= TJSONArray.Create;
    for var CR in Res.Report.Carried do
    begin
      var JCR: TJSONObject:= TJSONObject.Create;
      JCR.AddPair('fromPath', CR.FromPath);
      JCR.AddPair('toPath'  , CR.ToPath);
      JCR.AddPair('ruleLine', TJSONNumber.Create(CR.RuleLine));
      JCR.AddPair('type'    , CR.TypeName);
      JCarried.AddElement(JCR);
    end;
    JReport.AddPair('carried', JCarried);
    JReport.AddPair('mappingNotes', ArrJson(Res.Report.MappingNotes));
    var JNotApplied: TJSONArray:= TJSONArray.Create;
    for var NA in Res.Report.NotApplied do
    begin
      var JNA: TJSONObject:= TJSONObject.Create;
      JNA.AddPair('mapName' , NA.MapName);
      JNA.AddPair('ruleLine', TJSONNumber.Create(NA.RuleLine));
      JNA.AddPair('path'    , NA.Path);
      JNA.AddPair('value'   , NA.Value);
      JNotApplied.AddElement(JNA);
    end;
    JReport.AddPair('notApplied', JNotApplied);
    var JSuperseded: TJSONArray:= TJSONArray.Create;
    for var DS in Res.Report.DefaultsSuperseded do
    begin
      var JDS: TJSONObject:= TJSONObject.Create;
      JDS.AddPair('path'    , DS.Path);
      JDS.AddPair('value'   , DS.Value);
      JDS.AddPair('existing', DS.Existing);
      JDS.AddPair('ruleLine', TJSONNumber.Create(DS.RuleLine));
      JSuperseded.AddElement(JDS);
    end;
    JReport.AddPair('defaultsSuperseded', JSuperseded);
    var JResolved: TJSONArray:= TJSONArray.Create;
    for var DR in Res.Report.DefaultsResolved do
    begin
      var JDR: TJSONObject:= TJSONObject.Create;
      JDR.AddPair('fromPath', DR.FromPath);
      JDR.AddPair('toPath'  , DR.ToPath);
      JDR.AddPair('value'   , DR.Value);
      JDR.AddPair('ruleLine', TJSONNumber.Create(DR.RuleLine));
      JResolved.AddElement(JDR);
    end;
    JReport.AddPair('defaultsResolved', JResolved);
    var JEnumUn: TJSONArray:= TJSONArray.Create;
    for var EU in Res.Report.EnumUnmapped do
    begin
      var JEU: TJSONObject:= TJSONObject.Create;
      JEU.AddPair('castName', EU.CastName);
      JEU.AddPair('fromPath', EU.FromPath);
      JEU.AddPair('toPath'  , EU.ToPath);
      JEU.AddPair('value'   , EU.Value);
      JEU.AddPair('ruleLine', TJSONNumber.Create(EU.RuleLine));
      JEnumUn.AddElement(JEU);
    end;
    JReport.AddPair('enumUnmapped', JEnumUn);
    { 'notes' deliberately stays the UNION of stubs + relocated + notes.
      DRagLint.Convert.DfmReemit split those two OUT of Notes so each entry can
      carry a stable kind instead of being classified by matching its prose; this
      key predates the split, so emitting the union keeps every existing consumer
      reading exactly what it read before. 'stubs'/'relocated' are additive. }
    JReport.AddPair('notes',      ArrJson(Res.Report.Stubs + Res.Report.Relocated +
                                          Res.Report.MappingNotes + Res.Report.Notes));
    JRoot.AddPair('report', JReport);
    JRoot.AddPair('unreachable', UnreachableJson(DistinctUnreachable(Unreach))); { T2h -- same objects as apply/1 }
    WriteStdoutDocument(JRoot.ToJSON + sLineBreak); // after every stderr byte (T2i R18)
  finally
    JRoot.Free;
  end;

  if Res.Ok then Exit(0) else Exit(1);
end; // function

function DoConvertScaffold(const AArgs: TArgs): Integer;
var
  Dbs      : TArray<string>  ;
  LDb      : string          ;
  FromTree : TPropTree       ;
  ToTree   : TPropTree       ;
  HaveStore: Boolean         ;
  Opts     : TPropTreeOptions;
  Depth    : Integer         ;
  Sb       : TStringBuilder  ;
  OutText  : string          ;
  Surface  : string          ;
  ProgMs   : Integer         ;

  // Bare leaf (last dotted segment) of a path, lowercased for matching.
  function LeafLower(const APath: string): string;
  var
    D: Integer;
  begin
    D:= LastDelimiter('.', APath);
    if D > 0 then Result:= Copy(APath, D + 1, MaxInt) else Result:= APath;
    Result:= LowerCase(Result);
  end;

  // Unit prefix of a qualified name ('ConvFix.TFrom' -> 'ConvFix'); '' if none.
  function UnitOf(const AQName: string): string;
  var
    D: Integer;
  begin
    D:= LastDelimiter('.', AQName);
    if D > 0 then Result:= Copy(AQName, 1, D - 1) else Result:= '';
  end;

  // Sorted copy of a tree's paths (case-insensitive). A Sorted TStringList with
  // CaseSensitive=False orders by CompareText -- no custom callback needed.
  function SortedPaths(const ATree: TPropTree): TArray<string>;
  var
    L: TStringList;
    N: TPropNode;
  begin
    L:= TStringList.Create;
    try
      L.CaseSensitive := False;
      L.Duplicates    := dupAccept;
      L.Sorted        := True;
      for N in ATree.Nodes do L.Add(N.Path);
      Result:= L.ToStringArray;
    finally
      L.Free;
    end;
  end;

  // The declared TypeName for a path in a tree ('' if not found).
  function TypeOfPath(const ATree: TPropTree; const APath: string): string;
  var
    N: TPropNode;
  begin
    Result:= '';
    for N in ATree.Nodes do
      if SameText(N.Path, APath) then Exit(N.TypeName);
  end;

  // The full TPropNode for a path in a tree (Path='' -- not present -- if
  // not found; every real leaf has a non-empty Path, so this is a safe
  // not-found sentinel).
  function NodeOfPath(const ATree: TPropTree; const APath: string): TPropNode;
  var
    N: TPropNode;
  begin
    Result:= Default(TPropNode);
    for N in ATree.Nodes do
      if SameText(N.Path, APath) then Exit(N);
  end;

  // proptree assignability engine (Task 5): does ANode qualify as a valid
  // auto-'#link'/'#default' TARGET under ASurface ('dfm' or 'pas', already
  // lower-cased/validated by the caller)? is_writable=false (a typed class
  // CONST today) is NEVER a valid target on EITHER surface. 'dfm' additionally
  // requires member_kind='property' (DFM streaming is properties only -- a
  // FIELD, even a published one, is never DFM-streamable, mirroring
  // DoPropTree's PassesMinVisibility 'published' tier) AND the effective
  // visibility='published'; 'pas' allows visibility in ('published','public')
  // and ANY member_kind (so a public FIELD is a valid PAS-surface target).
  // Graceful degrade: an UNRESOLVABLE effective visibility (Visibility='') is
  // treated as PASSING the bar on BOTH surfaces rather than being silently
  // dropped -- defensive-only in practice (the current parser always stamps a
  // non-empty Modifiers value; see DRagLint.Convert.PropTree's
  // ResolveInheritedVisibility remark), but this keeps an old/foreign DB row
  // whose visibility could not be resolved exactly as visible as it is today
  // (no filter existed before this task) instead of quietly vanishing it.
  function IsValidTarget(const ANode: TPropNode; const ASurface: string): Boolean;
  var
    Vis: string;
  begin
    if not ANode.IsWritable then Exit(False); // read-only -- never a valid target, any surface
    Vis:= LowerCase(Trim(ANode.Visibility));
    // GRACEFUL-DEGRADE SAFETY NET, not dead code: Visibility='' means the
    // effective visibility could not be resolved at all (own Modifiers empty
    // AND the ancestor walk in DRagLint.Convert.PropTree also came up empty).
    // Unreachable via TODAY's indexer/parser (Modifiers is always stamped
    // non-empty; see ResolveInheritedVisibility's own remark there) -- this
    // branch exists for an old/foreign DB row a FUTURE producer could still
    // emit, so it degrades to "do not filter" (pass) rather than silently
    // dropping a target more aggressively than pre-Task-5 behavior (which had
    // no filter at all). Do not delete as unreachable; it is a documented,
    // intentional back-compat contract, not leftover debris.
    if Vis = '' then Exit(True);
    if ASurface = 'dfm' then
    begin
      if SameText(Trim(ANode.MemberKind), 'field') then Exit(False); // DFM streams properties only
      Exit(Vis = 'published');
    end;
    Result:= (Vis = 'published') or (Vis = 'public'); // ASurface = 'pas'
  end;

  // From-tree paths whose leaf name = ATLeaf (lowercased) AND whose declared
  // type is compatible (equal, case-insensitive) with ATType. Sorted (a Sorted
  // CaseSensitive=False TStringList orders by CompareText).
  function FromCandidates(const ATLeaf, ATType: string): TArray<string>;
  var
    L: TStringList;
    N: TPropNode;
  begin
    L:= TStringList.Create;
    try
      L.CaseSensitive := False;
      L.Duplicates    := dupAccept;
      L.Sorted        := True;
      for N in FromTree.Nodes do
        if (LeafLower(N.Path) = ATLeaf) and SameText(N.TypeName, ATType) then
          L.Add(N.Path);
      Result:= L.ToStringArray;
    finally
      L.Free;
    end;
  end;

  // True when SOME VALID-TARGET To path has the leaf+compatible-type of the
  // given F node (used to decide whether an F path is DROPPED). Uses the same
  // IsValidTarget test as the #link loop, so a From path whose only
  // leaf+type counterpart is a filtered-out (read-only / wrong-surface) To
  // leaf is correctly reported DROPPED rather than silently neither linked
  // nor noted.
  function ToHasCounterpart(const AFLeaf, AFType: string): Boolean;
  var
    N: TPropNode;
  begin
    Result:= False;
    for N in ToTree.Nodes do
      if (LeafLower(N.Path) = AFLeaf) and SameText(N.TypeName, AFType) and IsValidTarget(N, Surface) then
        Exit(True);
  end;

var
  TPath   : string        ;
  TType   : string        ;
  Cands   : TArray<string>;
  FPath   : string        ;
  FType   : string        ;
  UFrom   : string        ;
  UTo     : string        ;
  Header  : string        ;
begin
  if not ExplicitDbsExist(AArgs, 'convert-scaffold') then Exit(2);
  if (AArgs.CallFrom = '') or (AArgs.RenameTo = '') then
  begin
    Writeln('Usage: drag-lint convert-scaffold --from FromType --to ToType [--output FILE] [--surface dfm|pas] [--depth N] [--rules FILE] [--progress-interval S] --db PATH [--db ...]');
    Exit(2);
  end;

  // proptree assignability engine (Task 5): --surface dfm|pas picks the
  // TARGET-side visibility bar (see IsValidTarget above); unset defaults to
  // 'dfm' -- component conversion (DFM-streamable published surface) is
  // convert-scaffold's dominant use case today (the existing
  // run_convert_scaffold.ps1 fixture is all-published, so this default does
  // not change its output). A typo'd value is a usage error (exit 2), not a
  // silent fall-through, matching --min-visibility's own validation pattern
  // in DoPropTree.
  Surface:= LowerCase(Trim(AArgs.Surface));
  if Surface = '' then Surface:= 'dfm';
  if (Surface <> 'dfm') and (Surface <> 'pas') then
  begin Writeln(Format('ERROR: --surface must be dfm|pas (got "%s")', [AArgs.Surface]));
  Exit(2); end;

  if not ResolveTreeDepth(AArgs, Depth) then Exit(2); // --depth > #depth > 5
  if not ResolveProgressInterval(AArgs, ProgMs) then Exit(2);
  Opts:= Default(TPropTreeOptions);
  Opts.Depth       := Depth;
  Opts.ToPersistent:= AArgs.ToPersistent;
  Opts.ProgressIntervalMs:= ProgMs;
  if ProgMs > 0 then Opts.OnProgress:= MakeProgressWriter('convert-scaffold');

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.');
  Exit(2); end;

  // Use the FIRST db that resolves BOTH types (ids are per-DB, so both trees
  // must come from the same store). Exit 2 if no --db is readable.
  HaveStore:= False;
  FromTree := Default(TPropTree);
  ToTree   := Default(TPropTree);
  for LDb in Dbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    var RoOk: Boolean;
    var CandStore: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'convert-scaffold', LDb) then Exit(2);
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    HaveStore:= True;
    // One member cache per store for BOTH trees (1.20.6 T2c): a class the two
    // sides share (TStrings, TParams, ...) is resolved once.
    var CF: TPropTree;
    var CT: TPropTree;
    var TreeCache: TPropMemberCache:= TPropMemberCache.Create(CandStore, Opts);
    try
      CF:= TreeCache.BuildTree(AArgs.CallFrom, Opts.Depth);
      CT:= TreeCache.BuildTree(AArgs.RenameTo, Opts.Depth);
    finally
      TreeCache.Free;
    end;
    if (CF.RootType <> '') and (CT.RootType <> '') then
    begin FromTree:= CF;
    ToTree:= CT; Break; end;
    // Keep the first db's partial trees so we can report which type failed.
    if FromTree.RootType = '' then FromTree:= CF;
    if ToTree.RootType   = '' then ToTree  := CT;
  end;
  if not HaveStore then begin Writeln('ERROR: no readable drag-lint index among --db path(s)');
  Exit(2); end;
  if FromTree.RootType = '' then begin Writeln(Format('class not found: %s', [AArgs.CallFrom]));
  Exit(1); end;
  if ToTree.RootType   = '' then begin Writeln(Format('class not found: %s', [AArgs.RenameTo]));
  Exit(1); end;

  Sb:= TStringBuilder.Create;
  try
    // (1) #convert header + best-guess uses-add (the qname unit prefixes).
    UFrom:= UnitOf(AArgs.CallFrom);
    UTo  := UnitOf(AArgs.RenameTo);
    Header:= Format('#convert %s -> %s', [AArgs.CallFrom, AArgs.RenameTo]);
    if (UTo <> '') and (not SameText(UTo, UFrom)) then
      Header:= Header + ', ' + UTo
    else if (UTo = '') and (UFrom <> '') then
      Header:= Header + ', ' + UFrom;
    Sb.AppendLine(Header);
    Sb.AppendLine('#note scaffold: review every ??? -- concrete #link lines are inferred by leaf-name+type');

    // (2) One rule per VALID-TARGET To path (sorted). A To path that fails
    // IsValidTarget (read-only on either surface; wrong member_kind/visibility
    // for the DFM surface) is skipped entirely -- no '#link', no '#default',
    // no '#note' -- it is simply not part of this surface's assignable target
    // set (Task 5).
    for TPath in SortedPaths(ToTree) do
    begin
      if not IsValidTarget(NodeOfPath(ToTree, TPath), Surface) then Continue;
      TType:= TypeOfPath(ToTree, TPath);
      Cands:= FromCandidates(LeafLower(TPath), TType);
      if Length(Cands) = 1 then
        Sb.AppendLine(Format('#link %s <- %s', [TPath, Cands[0]]))
      else if Length(Cands) > 1 then
      begin
        Sb.AppendLine(Format('#link %s <- ???', [TPath]));
        Sb.AppendLine('#note candidates: ' + String.Join(', ', Cands));
      end
      else
        Sb.AppendLine(Format('#default %s = ???', [TPath]));
    end;

    // (3) DROPPED note per From path with no compatible To target (sorted).
    for FPath in SortedPaths(FromTree) do
    begin
      FType:= TypeOfPath(FromTree, FPath);
      if not ToHasCounterpart(LeafLower(FPath), FType) then
        Sb.AppendLine(Format('#note DROPPED %s (no T target)', [FPath]));
    end;

    OutText:= Sb.ToString;
  finally
    Sb.Free;
  end;

  if AArgs.Output <> '' then
  begin
    // ASCII / CRLF file (rules DSL is strict 7-bit ASCII). AppendLine already
    // emitted platform CRLFs on Windows; ANSI keeps the bytes 1:1.
    WriteOutputFile(AArgs.Output, OutText);
    Writeln('Wrote ', AArgs.Output);
  end
  else
    WriteStdoutDocument(OutText); // already CRLF-terminated per line; after every stderr byte (T2i)

  Result:= 0;
end; // function

// drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...]
// Walk every .dfm/.fmx under the roots, extract and decode every streamed graphic,
// pair it with its count property, write instances.tsv / classes.tsv / skipped.tsv /
// gallery.html / images\ into --output. --db only QUALIFIES (class_unit, declared count
// default, runtime_refs); without one those columns are empty, never guessed.
// Exit 0 on a completed walk (0 graphics is an answer); 2 on bad args or a missing root.
function DoGlyphVacuum(const AArgs: TArgs): Integer;
var
  Opts   : TGlyphVacuumOptions;
  Summary: TGlyphVacuumSummary;
  Err    : string;
  Dbs    : TArray<string>;
  LDb    : string;
  RoOk   : Boolean;
  Store  : ISymbolStore;
begin
  if (Length(AArgs.Roots) = 0) or (AArgs.Output = '') then
  begin
    Writeln('Usage: drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...]');
    Exit(2);
  end;
  if not ExplicitDbsExist(AArgs, 'glyph-vacuum') then Exit(2);
  Opts:= Default(TGlyphVacuumOptions);
  Opts.Roots := AArgs.Roots;
  Opts.OutDir:= AArgs.Output;
  Opts.Append:= AArgs.AppendOut;
  { EXPLICIT --db ONLY. Every other consumer auto-selects from the manifest; this
    verb must not, because its qualification columns are documented as EMPTY
    without a --db, and a column filled from a DB nobody named is a guess. }
  Dbs:= AArgs.DbPaths;
  for LDb in Dbs do
  begin
    if not TFile.Exists(LDb) then Continue;
    Store:= OpenReadOnlyStore(LDb, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'glyph-vacuum', LDb) then Exit(2);
      Continue;
    end;
    Opts.Stores:= Opts.Stores + [Store];
  end;
  if not RunGlyphVacuum(Opts, Summary, Err) then
  begin
    Writeln('ERROR: glyph-vacuum: ' + Err);
    Exit(2);
  end;
  Writeln(Format('glyph-vacuum: dfm=%d graphics=%d distinct=%d skipped=%d -> %s',
    [Summary.DfmFiles, Summary.Graphics, Summary.DistinctPayloads, Summary.Skipped, AArgs.Output]));
  Result:= 0;
end;

end.
