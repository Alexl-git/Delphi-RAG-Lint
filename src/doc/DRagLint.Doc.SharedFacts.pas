unit DRagLint.Doc.SharedFacts;

{ Shared-unit facts: the ONE place that knows how an inbound fact line is split
  into entries, which entries a project cannot see, and how two projects' views
  of the same block are reconciled.

  THE PROBLEM, measured 2026-08-13 on YADF/YADFOT/YADFSetup. A unit compiled by
  three projects has three indexes, and each index truthfully holds only its own
  closure. `YADF.Options.ParseEncoding` stores

      Called from: YADF.Options.OptionTable (YADF.Options.pas), YadfMain.ParseFlags (YadfMain.pas)

  and renders, under YADFOT's index, the same block WITHOUT the YadfMain entry --
  every other line byte-identical, because YADFOT does not compile YadfMain.pas.
  `TDocDrift` byte-compared, called the block stale, and the repair dropped the
  entry; YADF then called it stale in the other direction. YADFOT reported 31
  such findings and YADFSetup 34, while YADF reported 0 on the very same files.

  TWO HALVES, AND NEITHER WORKS ALONE.

  * The CHECKER forgives a stored entry missing from the fresh render when the
    unit is marked `dl:shared`, the entry names a unit outside this closure, and
    the entry is not flagged uncertain. Without this the narrow project calls the
    union stale forever.
  * The WRITER unions those same entries back in, so a write from ANY project
    preserves what the others contributed instead of replacing it. Without this
    the first write from a narrow project destroys the wide project's entries,
    and the wide project re-adds them on its next run -- which is drift under the
    rule that an entry in FRESH and not in STORED is always drift. That rule
    stays: it is what records a genuinely NEW caller.

  Together the block converges to the UNION across every project that compiles
  the unit, which is what a reader of a shared unit actually wants.

  ENTRIES ONLY ACCUMULATE, AND THAT IS THE PRICE. A caller deleted in ANOTHER
  project's source is indistinguishable, from here, from a caller this project
  simply cannot see -- both are "in stored, not in fresh, unit not in my
  closure". So this design never reaps such an entry. Reaping belongs to a
  command that can open every index at once; until one exists, a stale entry on a
  shared unit outlives the code it names. Do not describe this as a limitation
  that might not matter: it is the direct cost of the ruling.

  FAIL-SAFE DIRECTION. Every uncertainty here resolves toward DRIFT, never toward
  silence. If a block cannot be parsed confidently, if a list is truncated, if a
  label is unrecognised, the answer is the byte compare that shipped before this
  unit existed. A false "stale" costs a rewrite; a false "current" leaves a lie
  in the source and is the failure this whole seam has now produced five times.

  WHY TRUNCATED LISTS ARE EXCLUDED. Inbound lists are capped (`docs.max_callers`,
  5 in the manifest) and the overflow renders as a `(+N more)` suffix. The
  visible entries are then a WINDOW onto the list, not the list: an entry can
  leave the window because the cap fell differently, and a real deletion can hide
  inside the count. Set difference over a window is unsound in both directions,
  so a truncated line keeps the byte compare and is never merged. Measured cost:
  6 of 55 inbound lines on the real shared units, none of them in
  YADF.Options.pas, which is 21 of the 31 findings.

  ...AND WHY THAT COST IS NOW ZERO, 2026-08-14 (Q0). The exclusion above was the
  only thing keeping the family from converging, so DRagLint.Doc.Facts stopped
  producing the window: a `dl:shared` unit's inbound lists are rendered UNCAPPED,
  at both cap sites (CalledFrom's `docs.max_callers` and UsedInUnits'
  DocDisplayCount). The rule here is UNCHANGED and still live -- a STORED line
  can carry `(+N more)` because it was written before that change or by hand, and
  it is no more set-differenceable for having aged. What changed is that the
  engine no longer creates such lines.

  That also means this guard had NO TEST COVERAGE until 2026-08-14. The fixture
  that claimed to cover it exercised the residual compare below instead (its
  narrow project renders no block at all, so `SRes <> FRes` decides first and
  IsTruncated is never reached). tests\autotest\run_shared_unit_staleness.ps1's
  `MarkTrunc` case is the first that actually reaches it.

  THE EMPTY-RENDER HOLE, closed 2026-08-14. It was DESTRUCTIVE: when the narrow
  project's fresh render is EMPTY -- it compiles the unit but calls nothing in it
  -- the residual compare below exited on 'Pure' vs '' before any inbound label
  was consulted, and TDocumenter then emitted a pure tekDeleteLines over the wide
  project's block, which the wide project rewrote on its next run.

  NEITHER HALF ABOVE COULD PREVENT IT, which is the part worth remembering:
  MergeInboundFacts merges INTO a rendered block and there was none, and the
  checker's forgiveness rule sits BELOW a byte compare that had already decided.
  A rule placed under an earlier decision is not a rule. Both halves now call
  HoldsForeignInboundEntries FIRST -- "does the stored block carry entries only
  another project could have written" -- and preserve when it says yes.

  Note that predicate treats a TRUNCATED line as foreign-bearing, which is the
  opposite polarity to the truncation rule above. Both are the same instinct:
  fail toward PRESERVING the source, because a `(+N more)` window may hide
  exactly such an entry.

  WHY `seealso` IS NOT IN SCOPE, despite being listed as inbound in the plan.
  Its crefs are derived from CALLEES and same-unit siblings, both of which are
  properties of this unit's own code, so every project that compiles the unit
  computes the same set. A cref also carries no file location, so the closure
  test would have to guess where a dotted name splits into unit and symbol.
  Nothing to forgive and no sound way to forgive it. }

interface

uses
  DRagLint.Core.Interfaces;

type
  /// <summary>Reconciles a managed facts block across the projects that compile
  /// a `dl:shared` unit.</summary>
  /// <remarks>
  /// Both entry points are no-ops on an unmarked unit, so nothing
  /// changes for anyone who has not opted in. Not thread-safe: the closure set
  /// is cached in class state, keyed on the store it was built from.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas)</para>
  /// <para>Used in units: DRagLint.Doc.Document, DRagLint.Doc.Drift</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSharedFacts = class
  public
    /// <summary>True when the stored block differs from a fresh render in a way
    /// that counts as drift.</summary>
    /// <param name="AStored">The managed block body as it stands in the source.
    /// The doc parser flattens newlines to spaces, so this arrives as one
    /// line.</param>
    /// <param name="AFresh">The freshly rendered block, still multi-line.</param>
    /// <param name="AStore">The current project's index. Not owned.</param>
    /// <param name="AUnitPath">Absolute path of the declaring unit; decides
    /// whether the unit is marked.</param>
    /// <returns>True to report `doc-drift`. Identical to a whitespace-collapsed
    /// byte compare on an unmarked unit, on a truncated list, and on any block
    /// this unit cannot confidently parse.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas)</para>
    /// <para>Calls: DRagLint.Doc.SharedFacts.CollapseWs, DRagLint.Doc.SharedFacts.IsTruncated, DRagLint.Doc.SharedFacts.IsUncertainEntry, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.SplitEntries, DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries, DRagLint.Doc.SharedFacts.UnitInClosure, DRagLint.Lint.SharedUnit.TSharedUnit.IsShared, LowerCase</para>
    /// <para>Returns: CollapseWs(AStored) &lt;&gt; CollapseWs(AFresh); False</para>
    /// <para>Complexity: 20 (cyclomatic, outer body), 84 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Doc.SharedFacts.CollapseWs"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsTruncated"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsUncertainEntry"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.ParseBlock"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.SplitEntries"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function BlockDrifted(const AStored, AFresh: string;
      const AStore: ISymbolStore; const AUnitPath: string): Boolean;

    /// <summary>Unions the stored inbound entries this project cannot see into a
    /// freshly built doc comment.</summary>
    /// <param name="ADocText">The whole comment MergeComment just produced,
    /// `///`-prefixed, containing the managed block.</param>
    /// <param name="AStoredRemarks">The existing parsed remarks, holding the old
    /// managed block.</param>
    /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <param name="AUnitPath"><!-- drag-lint:auto type -->const string</param>
    /// <returns>ADocText unchanged on an unmarked unit or when there is nothing
    /// to preserve; otherwise the same text with its inbound fact lines replaced
    /// by the sorted union.</returns>
    /// <remarks>
    /// Sorting is what makes this idempotent. Without a canonical order
    /// the preserved entry appends after A's own entries under A and after B's
    /// under B, so each project would rewrite the line the other just wrote.
    /// Order changes only on marked units.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas)</para>
    /// <para>Calls: CompareText, Copy, DRagLint.Doc.SharedFacts.ExtractBlockBody, DRagLint.Doc.SharedFacts.IsTruncated, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.SplitEntries, DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts.ForgivenOf, DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts.SortedJoin, DRagLint.Lint.SharedUnit.TSharedUnit.IsShared, EndsText (+6 more)</para>
    /// <para>Returns: ADocText; Lines.Text</para>
    /// <para>Complexity: 22 (cyclomatic, outer body), 164 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Doc.SharedFacts.ExtractBlockBody"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsTruncated"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.ParseBlock"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.SplitEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts.ForgivenOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function MergeInboundFacts(const ADocText, AStoredRemarks: string;
      const AStore: ISymbolStore; const AUnitPath: string): string;

    /// <summary>True when the stored block holds inbound entries this project
    /// cannot see, so deleting or replacing it would destroy another project's
    /// contribution.</summary>
    /// <param name="AStoredRemarks">The existing parsed remarks.</param>
    /// <param name="AStore">The current project's index. Not owned.</param>
    /// <param name="AUnitPath">Absolute path of the declaring unit.</param>
    /// <returns>False on an unmarked unit, on an unparseable block, and
    /// whenever every stored entry is either inside this closure or flagged
    /// uncertain -- i.e. it answers True only when there is something here that
    /// ONLY another project could have written.</returns>
    /// <remarks>
    /// Exists because a narrow project that compiles a shared unit but
    /// CALLS nothing in it renders an empty block, and both halves of this unit
    /// are downstream of decisions taken before they are consulted: the checker
    /// exits on the residual compare ('Pure' vs '') and the writer emits a pure
    /// tekDeleteLines. Both now ask this first.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted (DRagLint.Doc.SharedFacts.pas)</para>
    /// <para>Calls: DRagLint.Doc.SharedFacts.IsTruncated, DRagLint.Doc.SharedFacts.IsUncertainEntry, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.SplitEntries, DRagLint.Doc.SharedFacts.UnitInClosure, DRagLint.Lint.SharedUnit.TSharedUnit.IsShared</para>
    /// <para>Returns: False</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsTruncated"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsUncertainEntry"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.ParseBlock"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.SplitEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.UnitInClosure"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function HoldsForeignInboundEntries(const AStoredRemarks: string;
      const AStore: ISymbolStore; const AUnitPath: string): Boolean;

    /// <summary>True when regenerating this block would DELETE stored fact
    /// content that this index cannot vouch for -- which makes the drift
    /// finding unsafe to advertise as an automatic repair.</summary>
    /// <param name="AStored">The managed block body as it stands in the source,
    /// flattened by the doc parser.</param>
    /// <param name="AFresh">The freshly rendered block this index would write in
    /// its place.</param>
    /// <param name="AStore">The current project's index. Not owned. Nil answers
    /// False: with no index there is nothing to vouch with, and the caller's
    /// existing behaviour stands.</param>
    /// <returns>True to withhold the `fixable` flag.</returns>
    /// <remarks>
    /// <para>THIS ANSWERS "CAN I VOUCH FOR THE DELETION", NOT "IS THERE DRIFT".
    /// The finding is still reported either way; only the offer to fix it
    /// automatically is withdrawn. Reporting a real difference is always right.
    /// Deleting a true fact on the strength of an index that structurally
    /// cannot hold it is not.</para>
    ///
    /// <para>WHY A PROJECT INDEX CANNOT VOUCH. Under the one-DB-per-project
    /// layout a production project index is exactly the compile closure, so it
    /// can never hold a test caller. A block written when one database covered
    /// production AND tests therefore regenerates to a strict subset, for ever,
    /// with no code change involved.</para>
    ///
    /// <para>TWO SHAPES, MEASURED, and the second is the larger loss.
    /// `Called from:` / `Used by:` / `Used in units:` are NARROWED entry by
    /// entry. `Covered by:` is DELETED WHOLE -- it names tests by definition, so
    /// a closure index reproduces none of it, and it is not in INBOUND_LABELS,
    /// so the entry-level forgiveness never sees it. On DataCopy one such line
    /// named 41 tests and the regeneration proposed no line at all.</para>
    ///
    /// <para>DELIBERATELY CONSERVATIVE IN ONE DIRECTION ONLY. An entry whose
    /// unit IS in the closure and is genuinely gone stays fixable -- the index
    /// can vouch for that absence, and withholding it would disable the feature
    /// rather than protect it. That case is the positive control in
    /// run_doc_drift_unseen_units.ps1 and it is what stops this predicate from
    /// degenerating into "never fixable".</para>
    /// </remarks>
    class function RegenerationDropsUnvouchable(const AStored, AFresh: string;
      const AStore: ISymbolStore; const AUnitPath: string): Boolean;
  end;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , System.IOUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Doc.Regions
  , DRagLint.Lint.SharedUnit
  ;

const
  { The inbound labels -- the only facts whose contents depend on WHICH project
    is looking. Everything else in the block is computed from this unit's own
    code and is identical under every index.

    'Used in units:' IS here, but it was EXCLUDED for several hours and the
    reason is worth keeping. Documenting YADF.Tokens under YADFOT rendered

        Used in units: dxXMLWriter, FireDAC.Comp.QBE, Spring.Data.ExpressionParser,
                       System.Bindings.Evaluator, System.JSON, XPTestedUnitParser, ...

    where the project itself renders four real units -- and none of those names
    exist in YADFOT's own index. They arrived through the facts builder's
    NAME-BASED extra-store fan-out, which `document --project` was feeding with
    every database in the manifest, library index included (CLI.OpenExtraStores;
    its 'Used in units:' bucket at Doc.Facts.pas:1947 has NO ambiguity gate at
    all, unlike the CalledFrom sibling at :1669). Forgiving those entries would
    have welded library noise permanently into every shared unit's source -- the
    accumulate-only cost, spent on entries that were never trustworthy.

    That was fixed at the source rather than worked around here: the fan-out is
    now explicit-`--db` only. With it gone, every entry on this line comes from
    the project's own index, so the label is as trustworthy as the other two and
    belongs in the feature. It is the reason YADF still drifted by 7 while it sat
    outside.

    ONE ASYMMETRY REMAINS, and it is why the entries here are bare names: this
    label renders through JoinEsc, not JoinRefs, so it carries no ' ?' marker at
    all. IsUncertainEntry is therefore always False for it. That is now sound --
    the unverifiable producer is gone -- but if a future change re-introduces any
    unverified contributor to this list, this is the line that stops screening
    it. }
  INBOUND_LABELS: array[0..2] of string = ('Called from:', 'Used by:', 'Used in units:');

  { EVERY label RenderFactsBlock and FormatPhase2FactLines can emit. Used only to
    find where one fact ends in the FLATTENED stored text, so a missing entry
    here makes an inbound slice swallow the fact that follows -- which the
    residual compare then reports as drift. That is the fail-safe direction, but
    it is still wrong, so keep this list in step with Doc.Regions. }
  ALL_LABELS: array[0..19] of string = (
    'Called from:', 'Used by:', 'Calls:', 'Returns:', 'Used in units:',
    'Complexity:', 'Owns returned:', 'Handles:', 'SQL:', 'Covered by:',
    'Mutates:', 'Touches:', 'Transaction:', 'Registered as:', 'Dataset:',
    'Reads:', 'Writes:', 'Recursive', 'UI thread only', 'Pure');

  MORE_MARK = '(+';
  UNCERTAIN_SUFFIX = ' ?';

  { Labels whose content is derived from OTHER units and which a compile-closure
    index therefore cannot reproduce at all -- as opposed to the inbound labels,
    which it reproduces PARTIALLY and which are screened entry by entry.

    `Covered by:` names tests. A production project index is exactly the compile
    closure, so it holds no test unit, so it renders no `Covered by:` line for
    any symbol, ever. The regeneration does not narrow the label; it deletes it.
    Measured on DataCopy 2026-09-02: a line naming 41 tests against a proposed
    text with no such line, on a finding marked [FIXABLE].

    Kept SEPARATE from INBOUND_LABELS on purpose. Adding it there would put it
    through ParseBlock's entry-level set difference, whose entries carry a
    `(file.pas)` part this label does not have -- the keys would not resolve and
    the screening would be nominal. Whole-label absence is the right test for a
    whole-label loss. }
  UNVOUCHABLE_LABELS: array[0..0] of string = ('Covered by:');

type
  TFactMap = TDictionary<string, string>;

var
  { Cache of the closure set, keyed on the store it was built from. Analyze runs
    once per documented decl and this is a whole-table read, so it is built once
    per run; a different store rebuilds rather than answering for the wrong
    project. Single-threaded by assumption, like the rest of the lint pass. }
  FClosureKey  : Pointer                   = nil;
  FClosureNames: TDictionary<string, Byte> = nil;

{ ---------------------------------------------------------------------------
  Small text helpers
  --------------------------------------------------------------------------- }

function CollapseWs(const S: string): string;
var
  Sb  : TStringBuilder;
  I   : Integer;
  Prev: Boolean;
begin
  Sb:= TStringBuilder.Create;
  try
    Prev:= False;
    for I:= 1 to Length(S) do
      if CharInSet(S[I], [' ', #9, #13, #10]) then
      begin
        if not Prev then Sb.Append(' ');
        Prev:= True;
      end
      else
      begin
        Sb.Append(S[I]);
        Prev:= False;
      end;
    Result:= Trim(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

{ The managed block's BODY -- what lies between the BEGIN and END markers.
  Returns AText unchanged when there are no markers, which is the right answer for
  a freshly rendered block that has not been wrapped in them yet. }
function ExtractBlockBody(const AText: string): string;
var
  B, E: Integer;
begin
  Result:= AText;
  B:= Pos(AUTO_BEGIN, AText);
  if B = 0 then Exit;
  Inc(B, Length(AUTO_BEGIN));
  E:= PosEx(AUTO_END, AText, B);
  if E = 0 then Exit;
  Result:= Copy(AText, B, E - B);
end;

function IsTruncated(const AContent: string): Boolean;
begin
  Result:= Pos(MORE_MARK, AContent) > 0;
end;

function IsUncertainEntry(const AEntry: string): Boolean;
begin
  Result:= EndsText(UNCERTAIN_SUFFIX, TrimRight(AEntry));
end;

{ Splits an inbound fact's content into entries. Entry text never contains a
  comma -- a qualified name cannot, and the parenthesised location is a file
  name -- so a plain comma split is exact. }
function SplitEntries(const AContent: string): TArray<string>;
var
  L  : TList<string>;
  Tok: string;
begin
  L:= TList<string>.Create;
  try
    for Tok in CollapseWs(AContent).Split([',']) do
      if Trim(Tok) <> '' then L.Add(Trim(Tok));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ The unit an entry names. 'AOnly.CallFromA (AOnly.pas)' -> 'aonly';
  'DRagLint.CLI' (a Used-in-units entry, which has no parentheses) ->
  'draglint.cli'. Lowercased, extension dropped, so it can be matched against
  the closure set either way round. }
function EntryUnitKey(const AEntry: string): string;
var
  P, Q: Integer;
begin
  Result:= Trim(AEntry);
  if EndsText(UNCERTAIN_SUFFIX, Result) then
    Result:= TrimRight(Copy(Result, 1, Length(Result) - Length(UNCERTAIN_SUFFIX)));
  P:= LastDelimiter('(', Result);
  if P > 0 then
  begin
    Q:= LastDelimiter(')', Result);
    if Q > P then Result:= Copy(Result, P + 1, Q - P - 1);
  end;
  Result:= LowerCase(Trim(Result));
  if EndsText('.pas', Result) then Result:= Copy(Result, 1, Length(Result) - 4)
  else if EndsText('.dpr', Result) then Result:= Copy(Result, 1, Length(Result) - 4)
  else if EndsText('.dfm', Result) then Result:= Copy(Result, 1, Length(Result) - 4);
end;

{ ---------------------------------------------------------------------------
  The closure set
  --------------------------------------------------------------------------- }

{ Every unit this index holds, keyed by lowercased base name without extension.
  Cached because Analyze runs once per documented decl and this is a whole-table
  read; the cache is keyed on the store instance, so handing in a different store
  rebuilds rather than answering from the wrong project. }
function ClosureNames(const AStore: ISymbolStore): TDictionary<string, Byte>;
var
  Ids: TArray<Int64>;
  I  : Integer;
  Key: string;
begin
  if (FClosureNames <> nil) and (FClosureKey = Pointer(AStore)) then
    Exit(FClosureNames);

  FreeAndNil(FClosureNames);
  FClosureNames:= TDictionary<string, Byte>.Create;
  FClosureKey  := Pointer(AStore);

  Ids:= AStore.GetAllFileIds;
  for I:= 0 to High(Ids) do
  begin
    Key:= LowerCase(TPath.GetFileNameWithoutExtension(AStore.GetFilePath(Ids[I])));
    if Key <> '' then FClosureNames.AddOrSetValue(Key, 1);
  end;
  Result:= FClosureNames;
end;

function UnitInClosure(const AStore: ISymbolStore; const AEntry: string): Boolean;
var
  Key: string;
begin
  Key:= EntryUnitKey(AEntry);
  Result:= (Key = '') or ClosureNames(AStore).ContainsKey(Key);
end;

{ ---------------------------------------------------------------------------
  Parsing a block into facts
  --------------------------------------------------------------------------- }

{ The 1-based position of the next label at or after AFrom, or 0. }
function NextLabelPos(const AText: string; AFrom: Integer): Integer;
var
  I, P: Integer;
begin
  Result:= 0;
  for I:= Low(ALL_LABELS) to High(ALL_LABELS) do
  begin
    P:= PosEx(ALL_LABELS[I], AText, AFrom);
    if (P > 0) and ((Result = 0) or (P < Result)) then Result:= P;
  end;
end;

{ Splits a block -- flattened or multi-line, both work -- into the three inbound
  facts plus a RESIDUAL holding everything else, collapsed. The residual is what
  keeps intrinsic facts on byte-compare semantics. }
procedure ParseBlock(const ABlock: string; out AInbound: TFactMap; out AResidual: string);
var
  Text  : string;
  Sb    : TStringBuilder;
  Pos1  : Integer;
  I, LP : Integer;
  Lab   : string;
  Stop  : Integer;
begin
  AInbound := TFactMap.Create;
  { v(P8, 2026-08-24): the <para> wrapper is PRESENTATION and must not reach the
    parse. Labels are located by position, not by line anchor, so a wrapped
    block still finds 'Called from:' -- but the fact's VALUE then carries a
    trailing '</para>' and the next one's leading '<para>'. The merged render
    differs from the stored text on every run, and `document` edits the same
    unit forever. Caught by run_shared_unit_staleness's idempotency check, which
    is the only assertion in the battery that exercises this merge path. }
  Text     := CollapseWs(ABlock.Replace('<para>', '').Replace('</para>', ''));
  Sb       := TStringBuilder.Create;
  try
    Pos1:= 1;
    while Pos1 <= Length(Text) do
    begin
      LP:= 0;
      Lab:= '';
      for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
      begin
        var P: Integer:= PosEx(INBOUND_LABELS[I], Text, Pos1);
        if (P > 0) and ((LP = 0) or (P < LP)) then
        begin
          LP := P;
          Lab:= INBOUND_LABELS[I];
        end;
      end;
      if LP = 0 then
      begin
        Sb.Append(Copy(Text, Pos1, MaxInt));
        Break;
      end;
      Sb.Append(Copy(Text, Pos1, LP - Pos1));
      Stop:= NextLabelPos(Text, LP + Length(Lab));
      if Stop = 0 then Stop:= Length(Text) + 1;
      AInbound.AddOrSetValue(Lab, Trim(Copy(Text, LP + Length(Lab), Stop - LP - Length(Lab))));
      Pos1:= Stop;
    end;
    AResidual:= CollapseWs(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

{ Declared here rather than moved: UnitVouchable and LabelContent live further
  down beside RegenerationDropsUnvouchable, which is where they were introduced,
  and the reconciliation below needs both. A forward declaration keeps the
  ordering legal without relocating working code. }
function UnitVouchable(const AStore: ISymbolStore; const AEntry: string): Boolean; forward;
function LabelContent(const AText, ALabel: string): string; forward;

{ The raw block text with ALabel's whole <para> element removed.

  WHY THE RAW TEXT AND NOT THE COLLAPSED RESIDUAL, which is what this did first:
  the residual has already lost its <para> boundaries, so the end of a fact has
  to be GUESSED from the next label or the next tag -- and that guess turned out
  to be position-dependent. Measured: a `Covered by:` sitting LAST round-tripped
  cleanly while the identical label sitting BEFORE two <seealso> crefs did not.
  A rule that depends on where in the block a label happens to sit is not a rule.

  The raw text still carries the delimiters, so removing the element is exact,
  and the residual is then computed from text that never held the label at all.

  NO WRAPPER -> NO CHANGE, deliberately. A hand-written block with a bare
  `Covered by:` and no <para> is left alone, so the compare still fires and the
  finding is still reported. That is this unit's fail-safe direction: report,
  never hide. }
function WithoutParaLabel(const AText, ALabel: string): string;
var
  P, Open, Close: Integer;
begin
  Result:= AText;
  P     := Pos(ALabel, Result);
  if P = 0 then Exit;

  Open:= P;
  while (Open > 1) and (Copy(Result, Open, 6) <> '<para>') do Dec(Open);
  Close:= PosEx('</para>', Result, P);

  if (Copy(Result, Open, 6) = '<para>') and (Close > 0) then
    Delete(Result, Open, Close + Length('</para>') - Open);
end;

{ Does the stored block carry anything this index cannot vouch for -- an inbound
  entry naming a unit it does not hold, or a whole label it cannot produce? }
function BlockHoldsUnvouchable(const AStore: ISymbolStore; const ABlock: string): Boolean;
var
  SIn : TFactMap;
  SRes: string;
  Lab, SC, E: string;
  I   : Integer;
begin
  Result:= False;
  if (AStore = nil) or (ABlock = '') then Exit;

  for I:= Low(UNVOUCHABLE_LABELS) to High(UNVOUCHABLE_LABELS) do
    if LabelContent(ABlock, UNVOUCHABLE_LABELS[I]) <> '' then Exit(True);

  ParseBlock(ABlock, SIn, SRes);
  try
    for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
    begin
      Lab:= INBOUND_LABELS[I];
      if not SIn.TryGetValue(Lab, SC) then Continue;
      for E in SplitEntries(SC) do
        if (not UnitVouchable(AStore, E)) and (not IsUncertainEntry(E)) then Exit(True);
    end;
  finally
    SIn.Free;
  end;
end;

{ Does this unit take part in fact reconciliation at all?

  UNTIL 2026-09-02 THE ANSWER WAS "ONLY IF MARKED `dl:shared`", and that is what
  let DataCopy's 43 findings destroy true facts. The one-DB-per-project layout
  made every production project a compile closure, so a test caller became
  invisible to the project that owns the code -- without anybody marking
  anything, and with no way for a reader to know it had happened.

  Marking every such unit by hand is not an answer: the condition is a property
  of the INDEX LAYOUT, not of the unit, and it now applies to essentially every
  project with a sibling test project.

  So an unmarked unit participates too -- but ONLY ON EVIDENCE, never by
  default. The stored block must actually carry something this index cannot
  vouch for. That distinction is the whole design:

    * it keeps ordinary blocks on their existing semantics, so a stale entry
      whose unit IS indexed is still reported and still reaped -- no silent
      accumulation, and run_docdrift_fix_removal still passes;
    * it engages exactly where deletion would destroy information.

  A marked unit still participates unconditionally: it opted into the
  accumulate-only contract described at the top of this unit. }
function Participates(const AStore: ISymbolStore; const AUnitPath, ABlock: string): Boolean;
begin
  Result:= (AStore <> nil) and
           (TSharedUnit.IsShared(AUnitPath) or BlockHoldsUnvouchable(AStore, ABlock));
end;

{ ---------------------------------------------------------------------------
  TSharedFacts
  --------------------------------------------------------------------------- }

class function TSharedFacts.BlockDrifted(const AStored, AFresh: string;
  const AStore: ISymbolStore; const AUnitPath: string): Boolean;
var
  SIn, FIn      : TFactMap;
  SRes, FRes    : string;
  Lab           : string;
  SC, FC        : string;
  SE, FE        : TArray<string>;
  FreshSet      : TDictionary<string, Byte>;
  StoredSet     : TDictionary<string, Byte>;
  E             : string;
  I             : Integer;
  StoredCmp     : string;
begin
  { An unmarked unit with nothing unvouchable in its block is not part of this
    feature, and keeps the byte compare that shipped before it existed. }
  if not Participates(AStore, AUnitPath, AStored) then
    Exit(CollapseWs(AStored) <> CollapseWs(AFresh));

  { TAKE OUT ANY LABEL THIS INDEX CANNOT PRODUCE, BEFORE THE PARSE.

    `Covered by:` is not an inbound label, so ParseBlock leaves it in the
    RESIDUAL -- and the residual is byte-compared. A compile-closure index
    renders no such line for any symbol, so stored-has / fresh-lacks is
    GUARANTEED, and the compare fired on every one of DataCopy's 42 blocks:
    drift that no code change caused and no repair could ever settle. Step 2a's
    inbound reconciliation could not reach it, because it never looked at the
    residual.

    Its absence from the fresh render is not evidence about the source; it is
    the same blind spot as an unseen caller. A label BOTH sides render is still
    compared normally, and every other residual fact is untouched. }
  StoredCmp:= AStored;
  for I:= Low(UNVOUCHABLE_LABELS) to High(UNVOUCHABLE_LABELS) do
    if (LabelContent(AStored, UNVOUCHABLE_LABELS[I]) <> '') and
       (LabelContent(AFresh,  UNVOUCHABLE_LABELS[I]) =  '') then
      StoredCmp:= WithoutParaLabel(StoredCmp, UNVOUCHABLE_LABELS[I]);

  ParseBlock(StoredCmp, SIn, SRes);
  try
    ParseBlock(AFresh, FIn, FRes);
    try
      { v(2026-08-14): the fresh render produced NO managed block AT ALL -- this
        project compiles the unit but calls nothing in it. The residual compare
        below would then decide on 'Pure' vs '' and report drift on a block this
        project must not touch, which is the checker's half of the pure-deletion
        defect (the writer's half is guarded in TDocumenter). Only forgiven when
        the stored block carries entries that ONLY another project could have
        written; a block with nothing foreign in it is still graded normally. }
      if (FRes = '') and (FIn.Count = 0) and (SIn.Count > 0)
         and HoldsForeignInboundEntries(AStored, AStore, AUnitPath) then Exit(False);

      { Everything that is not an inbound fact keeps byte-compare semantics --
        nothing about sharing makes a wrong Calls: or Complexity: line right. }
      if SRes <> FRes then Exit(True);

      for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
      begin
        Lab:= INBOUND_LABELS[I];
        if not SIn.TryGetValue(Lab, SC) then SC:= '';
        if not FIn.TryGetValue(Lab, FC) then FC:= '';
        if (SC = '') and (FC = '') then Continue;

        { A window onto the list is not the list. }
        if IsTruncated(SC) or IsTruncated(FC) then
        begin
          if SC <> FC then Exit(True);
          Continue;
        end;

        SE:= SplitEntries(SC);
        FE:= SplitEntries(FC);

        StoredSet:= TDictionary<string, Byte>.Create;
        FreshSet := TDictionary<string, Byte>.Create;
        try
          for E in SE do StoredSet.AddOrSetValue(LowerCase(E), 1);
          for E in FE do FreshSet .AddOrSetValue(LowerCase(E), 1);

          { An entry the fresh render found and the source does not record is
            ALWAYS drift: that is how a genuinely new caller gets written down. }
          for E in FE do
            if not StoredSet.ContainsKey(LowerCase(E)) then Exit(True);

          { An entry the source records and this project cannot see is forgiven
            only when it names a unit outside this closure and is not flagged
            uncertain. The '?' test is sound in ONE direction only -- JoinRefs
            emits the marker solely on a MIXED list, so its ABSENCE proves
            nothing -- which is why the closure test carries the decision. }
          for E in SE do
            if not FreshSet.ContainsKey(LowerCase(E)) then
              if UnitVouchable(AStore, E) or IsUncertainEntry(E) then Exit(True);
        finally
          FreshSet.Free;
          StoredSet.Free;
        end;
      end;

      Result:= False;
    finally
      FIn.Free;
    end;
  finally
    SIn.Free;
  end;
end;

class function TSharedFacts.HoldsForeignInboundEntries(const AStoredRemarks: string;
  const AStore: ISymbolStore; const AUnitPath: string): Boolean;
var
  SIn : TFactMap;
  SRes: string  ;
  Lab : string  ;
  SC  : string  ;
  E   : string  ;
  I   : Integer ;
begin
  Result:= False;
  if not Participates(AStore, AUnitPath, AStoredRemarks) then Exit;

  ParseBlock(AStoredRemarks, SIn, SRes);
  try
    for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
    begin
      Lab:= INBOUND_LABELS[I];
      if not SIn.TryGetValue(Lab, SC) then Continue;
      if SC = '' then Continue;
      { A TRUNCATED line is deliberately treated as foreign-bearing. The window
        may hide an entry only another project can see, and the whole point here
        is to refuse to destroy what cannot be reasoned about. This is the
        opposite polarity to BlockDrifted's truncation guard and for the same
        reason: both fail toward PRESERVING the source. }
      if IsTruncated(SC) then Exit(True);
      for E in SplitEntries(SC) do
        if (not UnitVouchable(AStore, E)) and (not IsUncertainEntry(E)) then Exit(True);
    end;
  finally
    SIn.Free;
  end;
end;

class function TSharedFacts.MergeInboundFacts(const ADocText, AStoredRemarks: string;
  const AStore: ISymbolStore; const AUnitPath: string): string;
var
  SIn       : TFactMap;
  SRes      : string;
  Lines     : TStringList;
  Handled   : TDictionary<string, Byte>;
  I, J, P   : Integer;
  Line, Body: string;
  Lab, SC   : string;
  Preserved : TArray<string>;
  Prefix    : string;
  Suffix    : string;   { the fact line's closing </para>, if P8 wrapped it }
  Changed   : Boolean;
  BeginAt   : Integer;

  { The entries STORED holds that this project cannot see -- exactly the set
    BlockDrifted forgives. If the two ever disagree, the writer rewrites a block
    the checker just called current, which is incident five on this seam. }
  function ForgivenOf(const AStoredContent: string; const AAlready: TArray<string>): TArray<string>;
  var
    Seen: TDictionary<string, Byte>;
    L   : TList<string>;
    E   : string;
  begin
    L   := TList<string>.Create;
    Seen:= TDictionary<string, Byte>.Create;
    try
      for E in AAlready do Seen.AddOrSetValue(LowerCase(E), 1);
      for E in SplitEntries(AStoredContent) do
        if (not Seen.ContainsKey(LowerCase(E))) and
           (not UnitVouchable(AStore, E)) and
           (not IsUncertainEntry(E)) then
        begin
          Seen.AddOrSetValue(LowerCase(E), 1);
          L.Add(E);
        end;
      Result:= L.ToArray;
    finally
      Seen.Free;
      L.Free;
    end;
  end;

  function SortedJoin(const A, B: TArray<string>): string;
  var
    L: TList<string>;
    E: string;
  begin
    L:= TList<string>.Create;
    try
      for E in A do L.Add(E);
      for E in B do L.Add(E);
      L.Sort(TComparer<string>.Construct(
        function(const X, Y: string): Integer
        begin
          Result:= CompareText(X, Y);
        end));
      Result:= string.Join(', ', L.ToArray);
    finally
      L.Free;
    end;
  end;

begin
  Result:= ADocText;
  if (AStore = nil) or (AStoredRemarks = '') then Exit;
  if not Participates(AStore, AUnitPath, AStoredRemarks) then Exit;

  { PARSE THE BLOCK BODY, NOT THE WHOLE REMARKS. The remarks continue past
    AUTO_END, and ParseBlock ends a fact at the next LABEL -- so when the last
    fact in the block is an inbound one, its slice ran to the end of the remarks
    and swallowed the END marker into an entry. That wrote

        /// Used in units: ..., YadfMain, YadfMain <!-- drag-lint:auto END -->
        /// <!-- drag-lint:auto END -->

    into YADF.Tokens.pas on the first run against real code: a duplicated entry,
    a marker inside a fact line, and a doubled terminator. BlockDrifted never had
    the bug because its caller hands it ExtractManagedBlockBody's output already.
    The unit test missed it because every fixture block ended with 'Pure', which
    IS a label, so the slice stopped in time -- see the regression fixture whose
    block ends on the inbound line itself. }
  ParseBlock(ExtractBlockBody(AStoredRemarks), SIn, SRes);
  try
    { A block may carry NOTHING but an unvouchable label -- a `Covered by:` with
      no inbound entries at all -- and that block still has something to
      preserve, so the inbound count alone cannot decide there is no work. }
    if (SIn.Count = 0) and
       (not BlockHoldsUnvouchable(AStore, ExtractBlockBody(AStoredRemarks))) then Exit;

    Changed:= False;
    Lines  := TStringList.Create;
    Handled:= TDictionary<string, Byte>.Create;
    try
      Lines.Text:= ADocText;   { TStringList round-trips the trailing EOL state }
      BeginAt   := -1;

      for I:= 0 to Lines.Count - 1 do
      begin
        Line:= Lines[I];
        if (BeginAt < 0) and (Pos(AUTO_BEGIN, Line) > 0) then BeginAt:= I;

        for J:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
        begin
          Lab:= INBOUND_LABELS[J];
          P  := Pos(Lab, Line);
          if P = 0 then Continue;
          Handled.AddOrSetValue(Lab, 1);
          if not SIn.TryGetValue(Lab, SC) then Break;

          Body  := Trim(Copy(Line, P + Length(Lab), MaxInt));
          Prefix:= Copy(Line, 1, P + Length(Lab) - 1);

          { v(P8, 2026-08-24): everything after the label is treated as the entry
            list, so a wrapped line handed '</para>' to SplitEntries as part of
            the last entry -- and the rebuilt line put the merged-in entry AFTER
            the closing tag:

              /// <para>Called from: A.CallFromA (A.pas)</para>, B.CallFromB (B.pas)

            which differs from the stored text on every run, so `document` edited
            the same unit forever. The closing tag is held aside and restored
            after the join; a line without one yields '' and is unaffected. }
          Suffix:= '';
          if EndsText('</para>', Body) then
          begin
            Suffix:= '</para>';
            Body  := TrimRight(Copy(Body, 1, Length(Body) - Length(Suffix)));
          end;

          { Never merge across a truncated window, in either direction. }
          if IsTruncated(Body) or IsTruncated(SC) then Break;

          Preserved:= ForgivenOf(SC, SplitEntries(Body));
          Lines[I] := Prefix + ' ' + SortedJoin(SplitEntries(Body), Preserved) + Suffix;
          if Lines[I] <> Line then Changed:= True;
          Break;
        end;
      end;

      { A label the stored block carries and this project does not render AT ALL
        -- every caller of this symbol lives in another project. Without this the
        write drops the line outright and the other project re-adds it forever.
        It goes directly after the BEGIN marker because 'Called from:'/'Used by:'
        is the first line RenderFactsBlock emits. }
      if BeginAt >= 0 then
        for J:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
        begin
          Lab:= INBOUND_LABELS[J];
          if Handled.ContainsKey(Lab) then Continue;
          if not SIn.TryGetValue(Lab, SC) then Continue;
          if IsTruncated(SC) then Continue;
          Preserved:= ForgivenOf(SC, nil);
          if Length(Preserved) = 0 then Continue;
          Prefix:= Copy(Lines[BeginAt], 1, Pos(AUTO_BEGIN, Lines[BeginAt]) - 1);
          Lines.Insert(BeginAt + 1, Prefix + Lab + ' ' + SortedJoin(Preserved, nil));
          Changed:= True;
        end;

      { CARRY OVER A LABEL THIS INDEX CANNOT PRODUCE AT ALL.

        The loop above only re-inserts INBOUND labels, which is where ParseBlock
        puts its three. `Covered by:` names TESTS, so a compile-closure index
        renders none of it for any symbol -- and it lives in the residual, so
        without this the write drops it outright. 23 such lines across 3 units in
        DataCopy, one of them naming 41 tests.

        Only when the fresh text does not already carry the label: a project that
        CAN see the tests renders its own, and that one wins. }
      if BeginAt >= 0 then
        for J:= Low(UNVOUCHABLE_LABELS) to High(UNVOUCHABLE_LABELS) do
        begin
          Lab:= UNVOUCHABLE_LABELS[J];
          SC := LabelContent(ExtractBlockBody(AStoredRemarks), Lab);
          if SC = '' then Continue;
          if LabelContent(ADocText, Lab) <> '' then Continue;
          Prefix:= Copy(Lines[BeginAt], 1, Pos(AUTO_BEGIN, Lines[BeginAt]) - 1);
          Lines.Insert(BeginAt + 1, Prefix + '<para>' + Lab + ' ' + SC + '</para>');
          Changed:= True;
        end;

      if Changed then Result:= Lines.Text;
    finally
      Handled.Free;
      Lines.Free;
    end;
  finally
    SIn.Free;
  end;
end;

{ Can this index VOUCH for the unit an entry names -- i.e. does it hold that
  unit, so that the entry's absence from a fresh render is a fact rather than a
  blind spot?

  WHY NOT JUST UnitInClosure. That reads the unit out of the '(file.pas)' part
  and, when there is none, falls back to the WHOLE qualified name -- which can
  never match a file base name, so every parenthesis-less entry would read as
  unvouchable. Two real shapes have no file part: a hand-written
  `Called from: driftfixable.NoSuchCallerAnyMore` (the D4 fixture, whose unit IS
  indexed) and `Covered by: Test.Prod.TProdTests.Ping_works` (whose unit is NOT).
  Treating both the same way is wrong in opposite directions.

  So: try the parenthesised form first, then every DOTTED PREFIX of the name.
  Unit names in this codebase are themselves dotted (`Test.Prod`,
  `DRagLint.Doc.Facts`), so the prefix walk is what makes those resolvable at
  all; `Test.Prod` matches a `Test.Prod.pas` row, while a prefix of a test name
  matches nothing in a closure index -- which is exactly the distinction wanted. }
function UnitVouchable(const AStore: ISymbolStore; const AEntry: string): Boolean;
var
  Names: TDictionary<string, Byte>;
  S    : string;
  P, I : Integer;
begin
  if UnitInClosure(AStore, AEntry) then Exit(True);

  S:= Trim(AEntry);
  P:= Pos('(', S);

  { A '(file.pas)' part is BETTER EVIDENCE than any prefix guess, so when one is
    present the answer above is final. Letting the prefix walk run on anyway
    would let `Test.Prod.TProdTests.X (Test.Prod.pas)` vouch through a closure
    that merely holds `Test.pas` -- overriding an explicit, correct "not mine"
    with a coincidence, and permitting the very deletion this guards. }
  if P > 0 then Exit(False);
  if EndsText(UNCERTAIN_SUFFIX, S) then
    S:= TrimRight(Copy(S, 1, Length(S) - Length(UNCERTAIN_SUFFIX)));
  S:= LowerCase(Trim(S));

  Names:= ClosureNames(AStore);
  for I:= 1 to Length(S) do
    if S[I] = '.' then
      if Names.ContainsKey(Copy(S, 1, I - 1)) then Exit(True);

  Result:= False;
end;

{ The content a label carries in a flattened block, or '' when the label is
  absent. Slices to the NEXT label of any kind, exactly as ParseBlock does, so a
  label sitting between two others is not swallowed. }
function LabelContent(const AText, ALabel: string): string;
var
  P, Stop, TagAt: Integer;
  Flat          : string;
begin
  Result:= '';
  Flat  := CollapseWs(AText.Replace('<para>', '').Replace('</para>', ''));
  P     := Pos(ALabel, Flat);
  if P = 0 then Exit;
  Stop:= NextLabelPos(Flat, P + Length(ALabel));
  if Stop = 0 then Stop:= Length(Flat) + 1;

  { STOP AT THE NEXT TAG AS WELL AS THE NEXT LABEL. <seealso .../> survives the
    <para> strip above and is not in ALL_LABELS, so a label followed by crefs
    had no next label at all and the content ran to the end of the block --
    swallowing the crefs. The writer's carry-over then emitted
    `<para>Covered by: X <seealso/> <seealso/></para>` and duplicated the crefs
    below it. A fact's content is plain text; a '<' after it begins the next
    element. }
  TagAt:= PosEx('<', Flat, P + Length(ALabel));
  if (TagAt > 0) and (TagAt < Stop) then Stop:= TagAt;

  Result:= Trim(Copy(Flat, P + Length(ALabel), Stop - P - Length(ALabel)));
end;

class function TSharedFacts.RegenerationDropsUnvouchable(const AStored, AFresh: string;
  const AStore: ISymbolStore; const AUnitPath: string): Boolean;
var
  SIn, FreshIn: TFactMap;
  SRes, FreshRes: string;
  Lab, SC, FreshContent, E: string;
  FreshSet: TDictionary<string, Byte>;
  I: Integer;
begin
  Result:= False;
  if AStore = nil then Exit;

  { A MARKED UNIT IS ALREADY SAFE, AND SAYING OTHERWISE BREAKS IT.

    On a dl:shared unit the WRITER merges: MergeInboundFacts keeps the inbound
    entries this index cannot see and adds the ones it can. So the regeneration
    does not drop them, and the repair is exactly the accumulation the feature
    exists to perform.

    This predicate compares the stored block against the FRESH RENDER, which is
    pre-merge and therefore narrow on any project that cannot see the other's
    callers. Reading that as a loss withdraws `fixable` from the one path that
    was already handling this correctly -- measured: it took the whole --fix arm
    of run_shared_unit_staleness red, on a project whose only job there is to
    ADD its own caller to a shared block.

    The unmarked case is the defect; the marked case is the cure. }
  if TSharedUnit.IsShared(AUnitPath) then Exit(False);

  { 1. A WHOLE LABEL this index cannot reproduce, present then gone. }
  for I:= Low(UNVOUCHABLE_LABELS) to High(UNVOUCHABLE_LABELS) do
    if (LabelContent(AStored, UNVOUCHABLE_LABELS[I]) <> '') and
       (LabelContent(AFresh,  UNVOUCHABLE_LABELS[I]) =  '') then
      Exit(True);

  { 2. Inbound labels, entry by entry. }
  ParseBlock(AStored, SIn, SRes);
  try
    ParseBlock(AFresh, FreshIn, FreshRes);
    try
      for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
      begin
        Lab:= INBOUND_LABELS[I];
        if not SIn.TryGetValue(Lab, SC) then Continue;
        if Trim(SC) = '' then Continue;

        { TRUNCATION ALONE DOES NOT WITHHOLD, and an earlier draft that made it
          do so was a silent, unmeasured regression across every project.

          Inbound lists cap at docs.max_callers (5 by default), so ANY symbol
          with more than five callers renders a `(+N more)` window. Withholding
          on the window itself therefore took `fixable` away from most
          facts-block findings everywhere -- including the commonest and most
          harmless one, a new in-closure caller, where nothing is deleted at all.

          The window is a real limit on what can be known, but it is not
          evidence of loss. What withholds is evidence: a VISIBLE entry this
          index cannot vouch for, or a whole unvouchable label going missing.
          Both are tested below and neither is weakened by a cap.

          ACCEPTED RESIDUAL, stated rather than hidden: an entry hiding BEYOND
          the window on an unmarked unit is still reapable. It is the same
          window-unsoundness this unit's header documents, it is the behaviour
          that shipped before this predicate existed, and closing it needs the
          uncapped render that `dl:shared` units already get. }

        if not FreshIn.TryGetValue(Lab, FreshContent) then FreshContent:= '';

        FreshSet:= TDictionary<string, Byte>.Create;
        try
          for E in SplitEntries(FreshContent) do FreshSet.AddOrSetValue(LowerCase(Trim(E)), 1);
          for E in SplitEntries(SC) do
          begin
            if FreshSet.ContainsKey(LowerCase(Trim(E))) then Continue;
            { Dropped. Vouchable ONLY if this index actually holds the unit the
              entry names -- then its absence is a fact, not a blind spot. }
            if not UnitVouchable(AStore, E) then Exit(True);
          end;
        finally
          FreshSet.Free;
        end;
      end;
    finally
      FreshIn.Free;
    end;
  finally
    SIn.Free;
  end;
end;

initialization

finalization
  FreeAndNil(FClosureNames);

end.
