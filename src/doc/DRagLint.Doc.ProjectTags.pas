unit DRagLint.Doc.ProjectTags;

{ Project tags on inbound doc facts -- the entry grammar `[A,B]entry` and the
  text-only operations `doc-forget` performs on it.

  WHAT A TAG IS. The set of projects whose index RENDERED an inbound entry the
  last time each of them wrote the block. Owner rulings 2026-09-16 (per-entry,
  merged set, name = the project DB's base name) and 2026-09-22/23 (lenient
  names, no header rewrite, a reaping command). It buys REAPING: a project
  removes only its OWN tag from an entry it no longer renders, and the entry
  goes when its set empties -- which the untagged union could never do,
  because "deleted in another project" and "invisible to this project" read
  the same. See docs\INBOX-document-apply-drops-facts-outside-the-db.md.

  WHO DECIDES WHAT. DRagLint.Doc.SharedFacts decides WHEN a block carries tags
  and what a run writes (ReconcileContent); this unit only knows how a tag is
  spelled, split and rewritten. Split out of SharedFacts on 2026-09-23 so the
  reconciliation unit stays one concern. }

interface

const
  { The inbound labels -- the only facts whose contents depend on WHICH project
    is looking. Everything else in the block is computed from the unit's own
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
    it. (Moved here from DRagLint.Doc.SharedFacts with the tag grammar,
    2026-09-23: `doc-forget` rewrites exactly these lines.) }
  /// <summary>The fact labels whose entries depend on which project is looking,
  /// and so carry project tags.</summary>
  INBOUND_LABELS: array[0..2] of string = ('Called from:', 'Used by:', 'Used in units:');

type
  /// <summary>What one `doc-forget` pass does to the project tags on inbound
  /// fact entries.</summary>
  /// <remarks>
  /// Exactly one of the three operations is normally set. Project alone
  /// REMOVES that tag (the entry goes when its set empties); Project with
  /// RenameTo RENAMES it; Untagged drops every UNTAGGED entry in a block that
  /// already carries tags -- the legacy lines no project claims. Tag names
  /// match case-insensitively, the same leniency the writer uses.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Doc.ProjectTags.pas), DRagLint.CLI.DocForgetOptions (DRagLint.CLI.pas), DRagLint.CLI.DoDocForget (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Doc.ProjectTags</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocForgetOptions = record
    /// <summary>The tag to remove, or the OLD name when RenameTo is set.</summary>
    Project : string;
    /// <summary>Non-empty: rename Project to this instead of removing it.</summary>
    RenameTo: string;
    /// <summary>Also drop untagged entries in blocks that carry any tag.</summary>
    Untagged: Boolean;
  end;

  /// <summary>Counts reported by one `doc-forget` pass over one text.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Doc.ProjectTags.pas), DRagLint.CLI.DoDocForget (DRagLint.CLI.pas), DRagLint.Doc.ProjectTags.ForgetTags (DRagLint.Doc.ProjectTags.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Doc.ProjectTags</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocForgetStats = record
    /// <summary>Tags removed from an entry's set.</summary>
    TagsRemoved   : Integer;
    /// <summary>Tags renamed in place.</summary>
    TagsRenamed   : Integer;
    /// <summary>Entries deleted outright (their set emptied, or untagged and
    /// Untagged was set).</summary>
    EntriesDropped: Integer;
    /// <summary>Whole fact lines deleted because no entry survived.</summary>
    LinesDropped  : Integer;
  end;

/// <summary>Splits an inbound fact's content into entries, collapsing runs of
/// whitespace first.</summary>
/// <param name="AContent">The text after the label, e.g.
/// `[A,B]X.Y (X.pas), Z.W (Z.pas)`.</param>
/// <returns>The trimmed, non-empty entries, in order.</returns>
/// <remarks>
/// Entry text never contains a comma -- a qualified name cannot, and the
/// parenthesised location is a file name -- so a comma split is exact OUTSIDE a
/// tag set. A tag set is the one place a comma is not a separator: `[A,B]X.Y
/// (X.pas)` is ONE entry.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.ProjectTags.ParseFactLine (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.SharedFacts.BlockCarriesTags (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.BlockHoldsUnvouchable (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.ReconcileContent (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.ReconcileDropsUnvouchable (DRagLint.Doc.SharedFacts.pas) (+4 more)</para>
/// <para>Calls: Copy, DRagLint.Doc.ProjectTags.CollapseBlanks, DRagLint.Doc.ProjectTags.SplitEntries.AddTok, Trim</para>
/// <para>Returns: L.ToArray</para>
/// <seealso cref="DRagLint.Doc.ProjectTags.CollapseBlanks"/>
/// <seealso cref="DRagLint.Doc.ProjectTags.SplitEntries.AddTok"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SplitEntries(const AContent: string): TArray<string>;

/// <summary>Splits `[A,B]rest` into its tags and the bare entry.</summary>
/// <param name="AEntry">One entry.</param>
/// <param name="ATags">The tags in written order; nil for an untagged entry.</param>
/// <param name="ABare">The entry without its tag set, trimmed.</param>
/// <remarks>
/// An untagged entry -- every entry written before tags existed --
/// yields no tags and itself.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.ProjectTags.AnyTagged (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.ProjectTags.BareEntry (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.ProjectTags.ForgetEntry (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.ProjectTags.ListTags (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.SharedFacts.EntryNorm (DRagLint.Doc.SharedFacts.pas) (+3 more)</para>
/// <para>Calls: Copy, Pos, Trim</para>
/// <para>Mutates: ATags (out), ABare (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SplitTagged(const AEntry: string; out ATags: TArray<string>; out ABare: string);

/// <summary>AEntry without its tag set.</summary>
/// <param name="AEntry">One entry, tagged or not.</param>
/// <returns>The bare entry, trimmed.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.SharedFacts.EntryKey (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.EntryUnitKey (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.PlausibleEntry (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.ReconcileContent (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.TSharedFacts.CompareInboundEntries (DRagLint.Doc.SharedFacts.pas) (+1 more)</para>
/// <para>Calls: DRagLint.Doc.ProjectTags.SplitTagged</para>
/// <seealso cref="DRagLint.Doc.ProjectTags.SplitTagged"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BareEntry(const AEntry: string): string;

/// <summary>True when ATags holds AName, compared case-insensitively.</summary>
/// <param name="ATags">A tag set.</param>
/// <param name="AName">A project name.</param>
/// <returns>True on a case-insensitive match.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.ProjectTags.ForgetEntry (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.ProjectTags.FormatTagged (DRagLint.Doc.ProjectTags.pas)</para>
/// <para>Calls: SameText</para>
/// <para>Returns: False</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HasTag(const ATags: TArray<string>; const AName: string): Boolean;

/// <summary>ATags without AName, compared case-insensitively.</summary>
/// <param name="ATags">A tag set.</param>
/// <param name="AName">The project name to drop; '' drops nothing.</param>
/// <returns>The remaining tags, in order.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.ProjectTags.ForgetEntry (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.SharedFacts.ReconcileContent (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries (DRagLint.Doc.SharedFacts.pas)</para>
/// <para>Calls: SameText</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function WithoutTag(const ATags: TArray<string>; const AName: string): TArray<string>;

/// <summary>The entry in its one canonical spelling.</summary>
/// <param name="ATags">The tag set, in any order, duplicates allowed.</param>
/// <param name="ABare">The bare entry.</param>
/// <returns>`[A,B]bare` -- tags de-duplicated case-insensitively (first
/// spelling wins), sorted, joined by a bare comma, no blank before the name;
/// ABare unchanged when there is no tag.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.ProjectTags.ForgetEntry (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.SharedFacts.EntryNorm (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.ReconcileContent (DRagLint.Doc.SharedFacts.pas)</para>
/// <para>Calls: CompareText, DRagLint.Doc.ProjectTags.HasTag</para>
/// <para>Returns: TAG_OPEN + string.Join(',', L.ToArray) + TAG_CLOSE + ABare</para>
/// <seealso cref="DRagLint.Doc.ProjectTags.HasTag"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatTagged(const ATags: TArray<string>; const ABare: string): string;

/// <summary>True when any of AEntries carries a tag.</summary>
/// <param name="AEntries">Entries as SplitEntries returns them.</param>
/// <returns>True on the first tagged entry.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.ProjectTags.FenceCarriesTags (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.SharedFacts.BlockCarriesTags (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.ReconcileContent (DRagLint.Doc.SharedFacts.pas)</para>
/// <para>Calls: DRagLint.Doc.ProjectTags.SplitTagged</para>
/// <para>Returns: False</para>
/// <seealso cref="DRagLint.Doc.ProjectTags.SplitTagged"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AnyTagged(const AEntries: TArray<string>): Boolean;

/// <summary>AContent with a trailing `(+N more)` window marker removed.</summary>
/// <param name="AContent">An inbound fact's content.</param>
/// <returns>The content without the marker, right-trimmed.</returns>
/// <remarks>
/// The marker is not an entry. Split in as one, `X (+3 more)` read as
/// naming a unit called `+3 more` that no index holds.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.ProjectTags.ParseFactLine (DRagLint.Doc.ProjectTags.pas), DRagLint.Doc.SharedFacts.BlockHoldsUnvouchable (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.ReconcileContent (DRagLint.Doc.SharedFacts.pas), DRagLint.Doc.SharedFacts.ReconcileDropsUnvouchable (DRagLint.Doc.SharedFacts.pas)</para>
/// <para>Calls: Copy, EndsText, TrimRight</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function WithoutMoreSuffix(const AContent: string): string;

/// <summary>AText with the project tags on its inbound fact entries removed,
/// renamed, or its untagged entries dropped, inside managed fences only.</summary>
/// <param name="AText">A whole unit's text, any line endings; they are kept.</param>
/// <param name="AOptions">What to do.</param>
/// <param name="AStats">What was done.</param>
/// <returns>The rewritten text; AText unchanged when nothing matched.</returns>
/// <remarks>
/// An entry whose tag set empties is deleted, and a fact line with no entry
/// left is deleted whole. Lines outside a managed fence (the engine's BEGIN/END
/// marker pair) are never touched -- a label outside the fence is prose. A line
/// nothing changed on is kept byte for byte. Pure: no I/O.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoDocForget (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.Doc.ProjectTags.FenceCarriesTags, DRagLint.Doc.ProjectTags.ForgetEntry, DRagLint.Doc.ProjectTags.ParseFactLine, Pos</para>
/// <para>Returns: string.Join(#10, Kept.ToArray)</para>
/// <para>Complexity: 10 (cyclomatic, outer body), 53 lines (full implementation)</para>
/// <para>Mutates: AStats (out)</para>
/// <seealso cref="DRagLint.Doc.ProjectTags.FenceCarriesTags"/>
/// <seealso cref="DRagLint.Doc.ProjectTags.ForgetEntry"/>
/// <seealso cref="DRagLint.Doc.ProjectTags.ParseFactLine"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ForgetTags(const AText: string; const AOptions: TDocForgetOptions;
  out AStats: TDocForgetStats): string;

/// <summary>One element per inbound entry, in every managed fence of AText that
/// carries at least one project tag: the entry's tag, or '' for an untagged
/// entry in such a block. An entry with two tags yields two.</summary>
/// <param name="AText">A whole unit's text.</param>
/// <returns>The tags, unaggregated; the caller counts them.</returns>
/// <remarks>
/// Exists so a mistyped or retired project name is discoverable
/// (`doc-forget --list-tags`) instead of silent: the writer is lenient about
/// names by design, because one project cannot know what others exist.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DocForgetListTags (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Doc.ProjectTags.FenceCarriesTags, DRagLint.Doc.ProjectTags.ParseFactLine, DRagLint.Doc.ProjectTags.SplitTagged, Pos</para>
/// <para>Returns: L.ToArray</para>
/// <seealso cref="DRagLint.Doc.ProjectTags.FenceCarriesTags"/>
/// <seealso cref="DRagLint.Doc.ProjectTags.ParseFactLine"/>
/// <seealso cref="DRagLint.Doc.ProjectTags.SplitTagged"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ListTags(const AText: string): TArray<string>;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Doc.Regions
  ;

const
  TAG_OPEN   = '[';
  TAG_CLOSE  = ']';
  MORE_OPEN  = ' (+';
  MORE_CLOSE = ' more)';
  PARA_CLOSE = '</para>';

{ Runs of blanks, tabs and line breaks become one blank; the ends are trimmed. }
function CollapseBlanks(const S: string): string;
var
  Sb  : TStringBuilder;
  C   : Char;
  Prev: Boolean;
begin
  Sb:= TStringBuilder.Create;
  try
    Prev:= False;
    for C in S do
      if CharInSet(C, [' ', #9, #13, #10]) then
      begin
        if not Prev then Sb.Append(' ');
        Prev:= True;
      end
      else
      begin
        Sb.Append(C);
        Prev:= False;
      end;
    Result:= Trim(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

function SplitEntries(const AContent: string): TArray<string>;
var
  L    : TList<string>;
  S    : string;
  I    : Integer;
  Start: Integer;
  Depth: Integer;

  procedure AddTok(const ATok: string);
  begin
    if Trim(ATok) <> '' then L.Add(Trim(ATok));
  end;

begin
  L:= TList<string>.Create;
  try
    S    := CollapseBlanks(AContent);
    Start:= 1;
    Depth:= 0;
    for I:= 1 to Length(S) do
      if S[I] = TAG_OPEN then Inc(Depth)
      else if (S[I] = TAG_CLOSE) and (Depth > 0) then Dec(Depth)
      else if (S[I] = ',') and (Depth = 0) then
      begin
        AddTok(Copy(S, Start, I - Start));
        Start:= I + 1;
      end;
    AddTok(Copy(S, Start, MaxInt));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure SplitTagged(const AEntry: string; out ATags: TArray<string>; out ABare: string);
var
  S    : string;
  Close: Integer;
  T    : string;
begin
  ATags:= nil;
  S    := Trim(AEntry);
  ABare:= S;
  if (S = '') or (S[1] <> TAG_OPEN) then Exit;
  Close:= Pos(TAG_CLOSE, S);
  if Close = 0 then Exit;
  for T in Copy(S, 2, Close - 2).Split([',']) do
    if Trim(T) <> '' then ATags:= ATags + [Trim(T)];
  ABare:= Trim(Copy(S, Close + 1, MaxInt));
end;

function BareEntry(const AEntry: string): string;
var
  Tags: TArray<string>;
begin
  SplitTagged(AEntry, Tags, Result);
end;

function HasTag(const ATags: TArray<string>; const AName: string): Boolean;
var
  T: string;
begin
  Result:= False;
  for T in ATags do
    if SameText(T, AName) then Exit(True);
end;

function WithoutTag(const ATags: TArray<string>; const AName: string): TArray<string>;
var
  T: string;
begin
  Result:= nil;
  for T in ATags do
    if not SameText(T, AName) then Result:= Result + [T];
end;

function FormatTagged(const ATags: TArray<string>; const ABare: string): string;
var
  L: TList<string>;
  T: string;
begin
  L:= TList<string>.Create;
  try
    for T in ATags do
      if not HasTag(L.ToArray, T) then L.Add(T);
    if L.Count = 0 then Exit(ABare);
    L.Sort(TComparer<string>.Construct(
      function(const X, Y: string): Integer
      begin
        Result:= CompareText(X, Y);
      end));
    Result:= TAG_OPEN + string.Join(',', L.ToArray) + TAG_CLOSE + ABare;
  finally
    L.Free;
  end;
end;

function AnyTagged(const AEntries: TArray<string>): Boolean;
var
  E   : string;
  Tags: TArray<string>;
  Bare: string;
begin
  Result:= False;
  for E in AEntries do
  begin
    SplitTagged(E, Tags, Bare);
    if Length(Tags) > 0 then Exit(True);
  end;
end;

function WithoutMoreSuffix(const AContent: string): string;
var
  P: Integer;
begin
  Result:= TrimRight(AContent);
  if not EndsText(MORE_CLOSE, Result) then Exit;
  P:= Result.LastIndexOf(MORE_OPEN) + 1;
  if P > 0 then Result:= TrimRight(Copy(Result, 1, P - 1));
end;

{ Takes one source line apart if it is an inbound fact line: AHead is everything
  up to and including the label, AEntries its entries, and the three tails --
  a `(+N more)` marker, a closing </para>, a CR -- are held aside so a rewrite
  puts them back exactly. False for any other line. }
function ParseFactLine(const ALine: string; out AHead: string; out AEntries: TArray<string>;
  out AMore, ATail, ACR: string): Boolean;
var
  Lab : string;
  P   : Integer;
  Rest: string;
  Bare: string;
begin
  Result  := False;
  AHead   := '';
  AEntries:= nil;
  AMore   := '';
  ATail   := '';
  ACR     := '';
  for Lab in INBOUND_LABELS do
  begin
    P:= Pos(Lab, ALine);
    if P = 0 then Continue;
    AHead:= Copy(ALine, 1, P + Length(Lab) - 1);
    Rest := Copy(ALine, P + Length(Lab), MaxInt);
    if EndsStr(#13, Rest) then
    begin
      ACR := #13;
      Rest:= Copy(Rest, 1, Length(Rest) - 1);
    end;
    Rest:= TrimRight(Rest);
    if EndsText(PARA_CLOSE, Rest) then
    begin
      ATail:= PARA_CLOSE;
      Rest := TrimRight(Copy(Rest, 1, Length(Rest) - Length(PARA_CLOSE)));
    end;
    Bare:= WithoutMoreSuffix(Rest);
    if Bare <> Rest then AMore:= Copy(Rest, Length(Bare) + 1, MaxInt);
    AEntries:= SplitEntries(Bare);
    Exit(True);
  end;
end;

{ Does the fence opening after line AFrom carry any tagged inbound entry? }
function FenceCarriesTags(const ALines: TArray<string>; AFrom: Integer): Boolean;
var
  I      : Integer;
  Head   : string;
  Entries: TArray<string>;
  More, Tail, CR: string;
begin
  Result:= False;
  for I:= AFrom to High(ALines) do
  begin
    if Pos(AUTO_END, ALines[I]) > 0 then Exit;
    if ParseFactLine(ALines[I], Head, Entries, More, Tail, CR) and AnyTagged(Entries) then Exit(True);
  end;
end;

{ One entry under AOptions: appended to AKeep unless it is dropped, with AStats
  counting what happened. True when the entry changed or went. }
function ForgetEntry(const AEntry: string; const AOptions: TDocForgetOptions; ABlockTagged: Boolean;
  const AKeep: TList<string>; var AStats: TDocForgetStats): Boolean;
var
  Tags: TArray<string>;
  Bare: string;
begin
  Result:= False;
  SplitTagged(AEntry, Tags, Bare);
  if Length(Tags) = 0 then
  begin
    Result:= AOptions.Untagged and ABlockTagged;
    if Result then Inc(AStats.EntriesDropped) else AKeep.Add(AEntry);
    Exit;
  end;
  if (AOptions.Project = '') or not HasTag(Tags, AOptions.Project) then
  begin
    AKeep.Add(AEntry);
    Exit;
  end;
  Tags:= WithoutTag(Tags, AOptions.Project);
  if AOptions.RenameTo <> '' then
  begin
    Inc(AStats.TagsRenamed);
    AKeep.Add(FormatTagged(Tags + [AOptions.RenameTo], Bare));
  end
  else
  begin
    Inc(AStats.TagsRemoved);
    if Length(Tags) = 0 then Inc(AStats.EntriesDropped)
    else AKeep.Add(FormatTagged(Tags, Bare));
  end;
  Result:= True;
end;

function ForgetTags(const AText: string; const AOptions: TDocForgetOptions;
  out AStats: TDocForgetStats): string;
var
  Lines  : TArray<string>;
  Kept   : TList<string>;
  Keep   : TList<string>;
  I      : Integer;
  InFence: Boolean;
  Tagged : Boolean;
  Head, More, Tail, CR: string;
  Entries: TArray<string>;
  E      : string;
  Changed: Boolean;
begin
  AStats := Default(TDocForgetStats);
  Lines  := AText.Split([#10]);   { each element keeps its own #13 }
  Kept   := TList<string>.Create;
  Keep   := TList<string>.Create;
  try
    InFence:= False;
    Tagged := False;
    for I:= 0 to High(Lines) do
    begin
      if Pos(AUTO_BEGIN, Lines[I]) > 0 then
      begin
        InFence:= True;
        Tagged := FenceCarriesTags(Lines, I + 1);
      end
      else if Pos(AUTO_END, Lines[I]) > 0 then InFence:= False
      else if InFence and ParseFactLine(Lines[I], Head, Entries, More, Tail, CR) then
      begin
        Keep.Clear;
        Changed:= False;
        for E in Entries do
          if ForgetEntry(E, AOptions, Tagged, Keep, AStats) then Changed:= True;
        if Changed and (Keep.Count = 0) then
        begin
          Inc(AStats.LinesDropped);
          Continue;
        end;
        if Changed then
        begin
          Kept.Add(Head + ' ' + string.Join(', ', Keep.ToArray) + More + Tail + CR);
          Continue;
        end;
      end;
      Kept.Add(Lines[I]);
    end;
    Result:= string.Join(#10, Kept.ToArray);
  finally
    Keep.Free;
    Kept.Free;
  end;
end;

function ListTags(const AText: string): TArray<string>;
var
  Lines  : TArray<string>;
  I      : Integer;
  InFence: Boolean;
  Tagged : Boolean;
  Head, More, Tail, CR: string;
  Entries: TArray<string>;
  E, Bare: string;
  Tags   : TArray<string>;
  L      : TList<string>;
begin
  Lines  := AText.Split([#10]);
  InFence:= False;
  Tagged := False;
  L      := TList<string>.Create;
  try
    for I:= 0 to High(Lines) do
      if Pos(AUTO_BEGIN, Lines[I]) > 0 then
      begin
        InFence:= True;
        Tagged := FenceCarriesTags(Lines, I + 1);
      end
      else if Pos(AUTO_END, Lines[I]) > 0 then InFence:= False
      else if InFence and Tagged and ParseFactLine(Lines[I], Head, Entries, More, Tail, CR) then
        for E in Entries do
        begin
          SplitTagged(E, Tags, Bare);
          if Length(Tags) = 0 then L.Add('') else L.AddRange(Tags);
        end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

end.
