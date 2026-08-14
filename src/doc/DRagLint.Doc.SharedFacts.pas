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

  KNOWN HOLE, and it is DESTRUCTIVE: when the narrow project's fresh render is
  EMPTY -- it compiles the unit but calls nothing in it -- the residual compare
  below exits on 'Pure' vs '' before any inbound label is consulted, and
  TDocumenter then emits a pure tekDeleteLines over the wide project's block.
  Neither half of this unit gets a say. See
  docs\INBOX-shared-unit-empty-render-deletes-block.md for the repro and a fix
  sketch; both halves need the same UnitInClosure fact they already use.

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
  /// Used by: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze (DRagLint.Doc.Drift.pas)
  /// Used in units: DRagLint.Doc.Document, DRagLint.Doc.Drift
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
    /// Called from: DRagLint.Doc.Drift.TDocDrift.Analyze (DRagLint.Doc.Drift.pas)
    /// Calls: DRagLint.Doc.SharedFacts.CollapseWs, DRagLint.Doc.SharedFacts.IsTruncated, DRagLint.Doc.SharedFacts.IsUncertainEntry, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.SplitEntries, DRagLint.Doc.SharedFacts.UnitInClosure, DRagLint.Lint.SharedUnit.TSharedUnit.IsShared, LowerCase
    /// Returns: CollapseWs(AStored) &lt;&gt; CollapseWs(AFresh); False
    /// Complexity: 16 (cyclomatic, outer body), 74 lines (full implementation)
    /// Pure
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
    /// Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas)
    /// Calls: CompareText, Copy, DRagLint.Doc.SharedFacts.ExtractBlockBody, DRagLint.Doc.SharedFacts.IsTruncated, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.SplitEntries, DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts.ForgivenOf, DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts.SortedJoin, DRagLint.Lint.SharedUnit.TSharedUnit.IsShared, IsUncertainEntry, LowerCase, Pos, Trim, UnitInClosure
    /// Returns: ADocText; Lines.Text
    /// Complexity: 21 (cyclomatic, outer body), 146 lines (full implementation)
    /// Pure
    /// <seealso cref="DRagLint.Doc.SharedFacts.ExtractBlockBody"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsTruncated"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.ParseBlock"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.SplitEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts.ForgivenOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function MergeInboundFacts(const ADocText, AStoredRemarks: string;
      const AStore: ISymbolStore; const AUnitPath: string): string;
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
  Text     := CollapseWs(ABlock);
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
begin
  { An unmarked unit is not part of this feature at all. }
  if (AStore = nil) or (not TSharedUnit.IsShared(AUnitPath)) then
    Exit(CollapseWs(AStored) <> CollapseWs(AFresh));

  ParseBlock(AStored, SIn, SRes);
  try
    ParseBlock(AFresh, FIn, FRes);
    try
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
              if UnitInClosure(AStore, E) or IsUncertainEntry(E) then Exit(True);
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
           (not UnitInClosure(AStore, E)) and
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
  if not TSharedUnit.IsShared(AUnitPath) then Exit;

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
    if SIn.Count = 0 then Exit;

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

          { Never merge across a truncated window, in either direction. }
          if IsTruncated(Body) or IsTruncated(SC) then Break;

          Preserved:= ForgivenOf(SC, SplitEntries(Body));
          Lines[I] := Prefix + ' ' + SortedJoin(SplitEntries(Body), Preserved);
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

      if Changed then Result:= Lines.Text;
    finally
      Handled.Free;
      Lines.Free;
    end;
  finally
    SIn.Free;
  end;
end;

initialization

finalization
  FreeAndNil(FClosureNames);

end.
