{ CHAIN-1 rule chains: pure decisions (detection, texts, keys, marks).
  Spec docs\superpowers\specs\2026-10-27-converter-chain1-design.md sections 4 and 5. }
unit ConvRules.RuleChains;

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , ConvRules.Model
  , ConvRules.BlockFile
  , ConvRules.BlockOps
  ;

type
  /// <summary>What convert-apply's single pass does to a set of rules that look chained.</summary>
  TChainKind = (
    /// <summary>TA -> TB then TB -> TC: a TA ends as TB (spec 4 "Chain").</summary>
    ckChain,
    /// <summary>TA -> TB then TB -> TA: the classes are swapped in one run (spec 4 "Cycle").</summary>
    ckCycle,
    /// <summary>Two headers with the same From type: the first wins (spec 4 "Winner").</summary>
    ckDuplicateFrom,
    /// <summary>A #useswap whose Old is added by another line: ADD wins (spec 4 "Unit chain").</summary>
    ckUnitChain);

  /// <summary>One line of a finding.</summary>
  TChainStage = record
    /// <summary>Index in TRuleBook.Nodes of the #convert header, or of the unit line (ckUnitChain).</summary>
    NodeIdx : Integer;
    /// <summary>The header's From type as written; ckUnitChain: the unit the line removes ('' for an adder).</summary>
    FromType: string;
    /// <summary>The header's To type as written; ckUnitChain: the unit(s) the line adds, comma-joined.</summary>
    ToType  : string;
  end;

  /// <summary>One finding of FindRuleChains.</summary>
  TRuleChain = record
    /// <summary>Which of the four findings this is.</summary>
    Kind  : TChainKind;
    /// <summary>ckChain: the stages root first; ckCycle: the loop from its lowest header, the closing rule
    /// NOT repeated; ckDuplicateFrom: the winner first, losers in file order; ckUnitChain: the adding line, then the swap.</summary>
    Stages: TArray<TChainStage>;
    /// <summary>Identity across saves: 'chain:ta>tb>tc', 'cycle:ta>tb', 'dup:ta', 'unit:a>b>c' (bare, lowercase).</summary>
    Key   : string;
  end;

/// <summary>The bare name of a type or unit: the part after the last '.', trimmed.</summary>
/// <param name="AName">A type or unit name, possibly qualified.</param>
/// <returns>The part after the last dot.</returns>
function ChainBareName(const AName: string): string;
/// <summary>True when A and B name the same type for convert-apply's match: bare names equal, case-insensitive (spec 4).</summary>
/// <param name="A">First name.</param>
/// <param name="B">Second name.</param>
/// <returns>True when the bare names are equal ignoring case and non-empty.</returns>
function SameChainType(const A, B: string): Boolean;
/// <summary>Every chain, cycle, duplicate From and unit chain of ABook (spec 5.1 C1-C6), ordered by the node index of each finding's first stage.</summary>
/// <param name="ABook">The book; not owned, not changed.</param>
/// <returns>The findings; empty when the book is clean.</returns>
function FindRuleChains(ABook: TRuleBook): TArray<TRuleChain>;
/// <summary>'TA -> TB -> TC' from the stages' types as written (a cycle repeats its first From at the end; a duplicate names the From once; a unit chain 'A -> B -> C').</summary>
/// <param name="AChain">The finding.</param>
/// <returns>The path text.</returns>
function ChainPathText(const AChain: TRuleChain): string;
/// <summary>The dialog row: 'chain TA -> TB -> TC (lines 3, 9)', 'cycle TA -> TB -> TA (lines 3, 9)', 'duplicate From TA (line 3 wins; 12 never applied)', 'unit chain A -> B -> C (lines 1, 2)'.</summary>
/// <param name="AChain">The finding.</param>
/// <returns>The row text; line numbers are node index + 1.</returns>
function ChainRowText(const AChain: TRuleChain): string;
/// <summary>The warning mark for stage AStage (0-based) of AChain -- the exact strings are in the implementation constants and pinned by TestRuleChainsTexts.</summary>
/// <param name="AChain">The finding.</param>
/// <param name="AStage">0-based stage index into AChain.Stages.</param>
/// <returns>The mark text; '' when AStage is out of range.</returns>
function ChainMarkText(const AChain: TRuleChain; AStage: Integer): string;
/// <summary>True for ckChain and ckUnitChain (spec 5.3 O2).</summary>
/// <param name="AChain">The finding.</param>
/// <returns>Whether Merge applies.</returns>
function CanMergeChain(const AChain: TRuleChain): Boolean;
/// <summary>True for ckChain only.</summary>
/// <param name="AChain">The finding.</param>
/// <returns>Whether Split applies.</returns>
function CanSplitChain(const AChain: TRuleChain): Boolean;
/// <summary>'' when none; else 'Rule chains: 1 chain, 2 duplicate From types -- see marked rules (Conversion > Rule chains...)' with only the non-zero counts, singular/plural by count.</summary>
/// <param name="AChains">The findings.</param>
/// <returns>The status text.</returns>
function ChainStatusText(const AChains: TArray<TRuleChain>): string;
/// <summary>The findings to offer now: those with CanMerge or CanSplit whose Key is not in AAsked (case-insensitive).</summary>
/// <param name="AChains">The findings.</param>
/// <param name="AAsked">Keys already offered this session.</param>
/// <returns>The findings still to offer.</returns>
function ChainsToOffer(const AChains: TArray<TRuleChain>; const AAsked: TArray<string>): TArray<TRuleChain>;
/// <summary>Adds the warning mark of every finding to every node it involves (spec 5.2 M1); returns the number added; never adds a mark twice.</summary>
/// <param name="ABook">The book whose nodes get the session marks; not owned.</param>
/// <returns>The number of marks added.</returns>
/// <remarks>First drops every chain mark the current findings no longer give (a finding a merge or an
/// edit removed, or whose "line N" moved, must not survive); every other mark is kept. A chain mark is a warning whose
/// text starts with "chain ", "cycle ", "duplicate From type " or "unit chain ".</remarks>
function StaticChainMarks(ABook: TRuleBook): Integer;

// ---- Task 2 (merge composition): TChainMerge, MergeChainPlan, ApplyChainMerge ----
type
  /// <summary>A planned merge of a chain's first stage through its later stages (spec 5.4).</summary>
  TChainMerge = record
    /// <summary>Index of the first stage's header; the replaced range is NodeIdx..LastIdx inclusive.</summary>
    NodeIdx : Integer;
    /// <summary>Last node index of the replaced range (blank lines before the next header are inside it).</summary>
    LastIdx : Integer;
    /// <summary>The replacement lines: the new header, the merge #note, then the body (trailing blank lines of the range kept at the end).</summary>
    NewLines: TArray<string>;
    /// <summary>Links / defaults / migrates rewritten through the next stage.</summary>
    Composed: Integer;
    /// <summary>Lines kept verbatim because the next stage does not map them.</summary>
    Carried : Integer;
    /// <summary>#note lines added (the leading merge note not counted).</summary>
    Noted   : Integer;
    /// <summary>The lines of an earlier stage dropped because a later stage has no line for their To-side path (spec A4 / A5): each one also has a #note in NewLines.</summary>
    Dropped : TArray<string>;
    /// <summary>'' or why the merge is refused (spec A11); then nothing else is valid.</summary>
    Problem : string;
  end;

/// <summary>Plan the merge of AChain (ckChain: compose stage 1 through stages 2..n; ckUnitChain: rewrite the adding line).</summary>
/// <param name="ABook">The book the chain was found in; not owned, not changed.</param>
/// <param name="AChain">A finding of FindRuleChains on ABook.</param>
/// <returns>The plan; Problem is set (and nothing else valid) when the chain is not mergeable or its lines changed since detection.</returns>
/// <remarks>Spec 5.4 A1-A9, A11. The last stage block stays in the book; only the first stage's range is replaced.</remarks>
function MergeChainPlan(ABook: TRuleBook; const AChain: TRuleChain): TChainMerge;
/// <summary>Replace the planned range with the new lines (each parsed into a node, nodes moved in).</summary>
/// <param name="ABook">The book the plan was made for; changed in place.</param>
/// <param name="AMerge">A plan from MergeChainPlan.</param>
/// <returns>The new header's node index (= AMerge.NodeIdx); -1 when AMerge.Problem is set or the range is no longer there.</returns>
function ApplyChainMerge(ABook: TRuleBook; const AMerge: TChainMerge): Integer;

type
  /// <summary>Which headers go to which stage book (spec 4 "Stage").</summary>
  TChainSplit = record
    /// <summary>Stages[0] = header node indexes that stay (stage 1); Stages[k] = stage k+1, each in file order. Length 1 when nothing moves.</summary>
    Stages  : TArray<TArray<Integer>>;
    /// <summary>Per stage (same index): the #mapping names its blocks #apply, distinct, file order; [] for stage 1.</summary>
    Mappings: TArray<TArray<string>>;
  end;

/// <summary>Assign every winner a stage from AChains (ckChain only; other kinds and losers stay at stage 1).</summary>
/// <param name="ABook">The book; not owned, not changed.</param>
/// <param name="AChains">The findings of FindRuleChains(ABook).</param>
/// <returns>The stage plan; links touching a cycle member are ignored, so those headers stay at stage 1.</returns>
function SplitChainPlan(ABook: TRuleBook; const AChains: TArray<TRuleChain>): TChainSplit;
/// <summary>'C:\x\Book.rules' + 2 -> 'C:\x\Book.stage2.rules'.</summary>
/// <param name="ABookPath">The book file path.</param>
/// <param name="AStage">The 1-based stage number (2 or more).</param>
/// <returns>The stage book path beside the book.</returns>
function StageBookPath(const ABookPath: string; AStage: Integer): string;
/// <summary>The text of one stage book: the '#depth N' line when ABook has a valid one, the #mapping groups named, then the blocks of AHeaderIdx verbatim (from SplitRulesBlocks of ABook.SaveToString), CRLF, trailing EOL.</summary>
/// <param name="ABook">The source book; not owned, not changed.</param>
/// <param name="AHeaderIdx">Header node indexes to carry.</param>
/// <param name="AMappings">#mapping names whose declaration and clause lines are copied (not moved).</param>
/// <returns>The stage book text.</returns>
function StageBookText(ABook: TRuleBook; const AHeaderIdx: TArray<Integer>; const AMappings: TArray<string>): string;
/// <summary>The source without the moved blocks: JoinBlocks(SplitOut(...)) of ABook.SaveToString -- preamble and trailer untouched.</summary>
/// <param name="ABook">The source book; not owned, not changed.</param>
/// <param name="AMovedHeaderIdx">Header node indexes that moved to stage books.</param>
/// <returns>The remaining book text.</returns>
function RemainingBookText(ABook: TRuleBook; const AMovedHeaderIdx: TArray<Integer>): string;
/// <summary>The status line after a split: 'Split 2 block(s) into Book.stage2.rules -- convert with Book.rules first, then Book.stage2.rules (check both on the Convert tab, in that order)' plus '; copied #mapping M1, M2 into the stage book' when any.</summary>
/// <param name="ABookPath">The book file path.</param>
/// <param name="AStageFiles">The stage book paths written, stage 2 first.</param>
/// <param name="AMoved">Number of blocks moved.</param>
/// <param name="AMappings">The #mapping names copied.</param>
/// <returns>The status text.</returns>
function SplitStatusText(const ABookPath: string; const AStageFiles: TArray<string>; AMoved: Integer; const AMappings: TArray<string>): string;

// ---- Task 4 (dialog and MainForm decisions) ----
/// <summary>Whether the Rule chains dialog's Merge button is enabled: at least one finding checked and every checked one CanMergeChain (spec 5.3 O2).</summary>
/// <param name="AChecked">The checked findings.</param>
/// <returns>True when Merge applies to all of them.</returns>
function CanMergeAll(const AChecked: TArray<TRuleChain>): Boolean;
/// <summary>Whether the Rule chains dialog's Split button is enabled: at least one finding checked and every checked one CanSplitChain (spec 5.3 O2).</summary>
/// <param name="AChecked">The checked findings.</param>
/// <returns>True when Split applies to all of them.</returns>
function CanSplitAll(const AChecked: TArray<TRuleChain>): Boolean;
/// <summary>AAsked plus the Key of every finding in AListed not already in it (case-insensitive), order kept: the session's asked set after the dialog listed AListed (spec 5.3 O2, A10).</summary>
/// <param name="AAsked">Keys asked so far.</param>
/// <param name="AListed">The findings the dialog listed.</param>
/// <returns>The new asked set.</returns>
function ChainKeysAsked(const AAsked: TArray<string>; const AListed: TArray<TRuleChain>): TArray<string>;
/// <summary>The status after Merge: 'Merged 2 chain(s): TA -> TB -> TC, TX -> TY -> TZ -- review the composed block, then Save' (spec 5.4 A10), plus '; not merged: p1; p2' for each refused plan; only the refusals when nothing merged ('Nothing merged: p1').</summary>
/// <param name="AMerged">ChainPathText of every chain merged.</param>
/// <param name="AProblems">MergeChainPlan.Problem of every chain refused.</param>
/// <returns>The status text.</returns>
function MergeStatusText(const AMerged, AProblems: TArray<string>): string;
/// <summary>One merged chain's entry for MergeStatusText: AChainText alone, or with ' (dropped N line(s) the later stage does not map: l1; l2 -- see its #note)' when AMerge dropped lines (spec A4 / A5).</summary>
/// <param name="AChainText">ChainPathText of the merged chain.</param>
/// <param name="AMerge">The plan that was applied.</param>
/// <returns>The entry text.</returns>
function MergeChainText(const AChainText: string; const AMerge: TChainMerge): string;
///<summary>The text of an EXISTING stage book after a split appends to it: AExisting's blocks, its last block terminated, then AStage's blocks without AStage's '#depth' line (the existing book's own #depth governs).</summary>
/// <param name="AExisting">The stage book's current text.</param>
/// <param name="AStage">StageBookText of the blocks being moved.</param>
/// <returns>The text to write; CRLF.</returns>
/// <remarks>Spec 5.5 S2 (the Curation append rule). Duplicate headers are reported by the caller (DuplicateHeaders), not refused here.</remarks>
function StageAppendText(const AExisting, AStage: string): string;


implementation

uses
  System.StrUtils
  , System.Classes            // TStringList
  , System.Generics.Defaults
  , ConvRules.ValidateScope  // AddStaticWarningMark
  ;

const
  CHAIN_MARK_FMT     = 'chain %s: stage %d of %d -- convert-apply is single pass, so a %s ends as %s, never %s (Conversion > Rule chains...)';
  CYCLE_MARK_FMT     = 'cycle %s: convert-apply is single pass, so the classes are swapped in one run -- remove one rule if that is not intended';
  DUP_WIN_FMT        = 'duplicate From type %s: this rule wins; %s %s never applied';
  DUP_LOSE_FMT       = 'duplicate From type %s: never applied -- line %d wins; delete this block or merge its lines there';
  UNIT_ADD_FMT       = 'unit chain %s: %s is swapped again by line %d (ADD wins: %s stays)';
  UNIT_SWAP_FMT      = 'unit chain %s: ADD wins, so %s stays and %s is added -- rewrite line %d as %s -> %s (Conversion > Rule chains...)';
  UNIT_SWAP_ADD_FMT  = 'unit chain %s: ADD wins, so %s stays and %s is added -- rewrite line %d to add %s (Conversion > Rule chains...)';
  QUALIFIER_NOTE_FMT = ' (qualifiers differ: %s vs %s)';
  STATUS_FMT         = 'Rule chains: %s -- see marked rules (Conversion > Rule chains...)';
  ARROW              = ' -> ';

// ---- Task 2 (merge composition) implementation ----
const
  MERGE_NOT_MERGEABLE = 'only a chain or a unit chain can be merged';
  MERGE_NOTE          = '#note chain merge: ';

type
  // The counters of one merge, summed over all pairwise steps (spec A7a).
  TMergeCounts = record
    Composed: Integer;
    Carried : Integer;
    Noted   : Integer;
    Dropped : TArray<string>;
  end;

// File-scope directive kinds (spec 5.4 block range).
function MergeIsFileScope(AKind: TRuleNodeKind): Boolean;
begin
  Result:= AKind in [rnkMigrate, rnkUse, rnkUnuse, rnkUseSwap, rnkDepth, rnkMapping];
end;

// Last node of the block whose header is AHdr. A block that runs to the end of the book gives up its
// trailing blank / comment / file-scope run (the trailer stays); AAsSource keeps #migrate in the block (a
// source stage's migrates are its own lines, spec A6).
function MergeBlockEnd(ABook: TRuleBook; AHdr: Integer; AAsSource: Boolean): Integer;
var
  LI: Integer;
begin
  for LI:= AHdr + 1 to ABook.Nodes.Count - 1 do
    if ABook.Nodes[LI].Kind = rnkConvert then
      Exit(LI - 1);
  Result:= ABook.Nodes.Count - 1;
  while (Result > AHdr)
    and ((ABook.Nodes[Result].Kind in [rnkBlank, rnkComment])
      or (MergeIsFileScope(ABook.Nodes[Result].Kind) and not (AAsSource and (ABook.Nodes[Result].Kind = rnkMigrate)))) do
    Dec(Result);
end;

// '' when stage AStage still is the #convert block it was detected as, else why not.
function MergeStageProblem(ABook: TRuleBook; const AStage: TChainStage): string;
begin
  Result:= '';
  if (AStage.NodeIdx < 0) or (AStage.NodeIdx >= ABook.Nodes.Count)
    or (ABook.Nodes[AStage.NodeIdx].Kind <> rnkConvert)
    or not SameText(ABook.Nodes[AStage.NodeIdx].FromType, AStage.FromType) then
    Result:= Format('line %d is no longer the #convert %s block that was found; reopen Rule chains', [AStage.NodeIdx + 1, AStage.FromType]);
end;

procedure MergeAddUnique(ALines: TList<string>; const ALine: string);
begin
  if ALines.IndexOf(ALine) < 0 then
    ALines.Add(ALine);
end;

// Indexes of the Q links whose FromPath equals APath (case-insensitive).
function MergeQLinks(const AQ: TArray<TRuleNode>; const APath: string): TArray<Integer>;
var
  LI: Integer;
begin
  Result:= nil;
  for LI:= 0 to High(AQ) do
    if (AQ[LI].Kind = rnkLink) and SameText(Trim(AQ[LI].LinkFrom), APath) then
      Result:= Result + [LI];
end;

function MergeQIgnore(const AQ: TArray<TRuleNode>; const APath: string): Integer;
begin
  for Result:= 0 to High(AQ) do
    if (AQ[Result].Kind = rnkIgnore) and SameText(Trim(AQ[Result].IgnorePath), APath) then
      Exit;
  Result:= -1;
end;

// A2 / A3 / A4 for one #link of P. A4: Q has no line for the B-side path, so Q's pass drops that B property;
// the merged link is dropped too (C need not have the path), with a #note and an entry in AC.Dropped, and its From
// side becomes '#ignore A.y' -- the same result as A3, and the block still maps something, so Save keeps it.
procedure MergeLink(APN: TRuleNode; const APLine, AQDesc: string; const AQ: TArray<TRuleNode>; var AUsed: TArray<Boolean>;
  ARes: TList<string>; var AC: TMergeCounts);
var
  LHits: TArray<Integer>;
  LIg  : Integer;
  LI   : Integer;
  LCast: string;
  LLine: string;
begin
  LHits:= MergeQLinks(AQ, Trim(APN.LinkTo));
  if Length(LHits) > 0 then
    for LI in LHits do
    begin
      AUsed[LI]:= True;
      LCast:= APN.Cast + AQ[LI].Cast;
      if (APN.Cast <> '') and (AQ[LI].Cast <> '') then
      begin
        ARes.Add(Format(MERGE_NOTE + 'casts %s then %s on %s cannot be composed -- pick one', [APN.Cast, AQ[LI].Cast, APN.LinkFrom]));
        Inc(AC.Noted);
        LCast:= '';
      end;
      LLine:= '#link ' + AQ[LI].LinkTo + ' <- ' + APN.LinkFrom;
      if APN.GlyphExpr <> '' then
        LLine:= LLine + ' ' + APN.GlyphExpr;
      if LCast <> '' then
        LLine:= LLine + ' : ' + LCast;
      ARes.Add(LLine);
      Inc(AC.Composed);
    end
  else
  begin
    LIg:= MergeQIgnore(AQ, Trim(APN.LinkTo));
    if LIg >= 0 then
    begin
      AUsed[LIg]:= True;
      ARes.Add('#ignore ' + APN.LinkFrom);
      Inc(AC.Composed);
    end
    else
    begin
      ARes.Add(Format(MERGE_NOTE + 'dropped %s because %s has no #link or #ignore for %s; its From side is ignored below -- link it instead if the value should carry',
        [APLine, AQDesc, Trim(APN.LinkTo)]));
      Inc(AC.Noted);
      MergeAddUnique(ARes, '#ignore ' + Trim(APN.LinkFrom));
      AC.Dropped:= AC.Dropped + [APLine];
    end;
  end;
end;

// A5 for one #default of P (unmatched: dropped like an A4 link).
procedure MergeDefault(APN: TRuleNode; const APLine, AQDesc: string; const AQ: TArray<TRuleNode>; var AUsed: TArray<Boolean>;
  ARes: TList<string>; var AC: TMergeCounts);
var
  LHits: TArray<Integer>;
  LIg  : Integer;
  LI   : Integer;
begin
  LHits:= MergeQLinks(AQ, Trim(APN.DefTo));
  if Length(LHits) > 0 then
    for LI in LHits do
    begin
      AUsed[LI]:= True;
      if AQ[LI].Cast <> '' then
      begin
        ARes.Add(Format(MERGE_NOTE + '#default %s now feeds %s through cast %s (%s); check the value', [APN.DefTo, AQ[LI].LinkTo, AQ[LI].Cast, AQDesc]));
        Inc(AC.Noted);
      end;
      ARes.Add('#default ' + AQ[LI].LinkTo + ' = ' + APN.DefValue);
      Inc(AC.Composed);
    end
  else
  begin
    LIg:= MergeQIgnore(AQ, Trim(APN.DefTo));
    if LIg >= 0 then
    begin
      AUsed[LIg]:= True;
      ARes.Add(Format(MERGE_NOTE + 'dropped #default %s = %s because %s ignores %s', [APN.DefTo, APN.DefValue, AQDesc, APN.DefTo]));
      Inc(AC.Noted);
    end
    else
    begin
      ARes.Add(Format(MERGE_NOTE + 'dropped %s because %s has no #link for %s', [APLine, AQDesc, Trim(APN.DefTo)]));
      Inc(AC.Noted);
      AC.Dropped:= AC.Dropped + [APLine];
    end;
  end;
end;

// A6 for one #migrate of P.
procedure MergeMigrate(APN: TRuleNode; const APLine: string; const AQ: TArray<TRuleNode>; var AUsed: TArray<Boolean>;
  ARes: TList<string>; var AC: TMergeCounts);
var
  LJ   : Integer;
  LLine: string;
begin
  if (APN.MigScope = '') and (APN.MigNew <> '') then
    for LJ:= 0 to High(AQ) do
      if (not AUsed[LJ]) and (AQ[LJ].Kind = rnkMigrate) and (AQ[LJ].MigScope = '') and SameText(AQ[LJ].MigOld, APN.MigNew) then
      begin
        AUsed[LJ]:= True;
        LLine:= '#migrate ' + APN.MigOld + ' -> ' + AQ[LJ].MigNew;
        if AQ[LJ].MigUnits <> '' then
          LLine:= LLine + ', ' + AQ[LJ].MigUnits;
        MergeAddUnique(ARes, LLine);
        Inc(AC.Composed);
        Exit;
      end;
  if ARes.IndexOf(APLine) < 0 then
  begin
    ARes.Add(APLine);
    Inc(AC.Carried);
  end;
end;

// The lines of Q that P's lines did not consume: #default and #migrate copied, the block-scoped rest after a note (A5, A6, A7).
procedure MergeQRest(const AQ: TArray<TRuleNode>; const AUsed: TArray<Boolean>; const AQDesc: string; ARes: TList<string>;
  var AC: TMergeCounts);
var
  LI   : Integer;
  LRest: TList<string>;
begin
  LRest:= TList<string>.Create;
  try
    for LI:= 0 to High(AQ) do
      if not AUsed[LI] then
        case AQ[LI].Kind of
          rnkDefault: MergeAddUnique(ARes, AQ[LI].Emit);
          rnkMigrate:
            if ARes.IndexOf(AQ[LI].Emit) < 0 then
            begin
              ARes.Add(AQ[LI].Emit);
              Inc(AC.Carried);
            end;
          rnkLink, rnkIgnore, rnkTag, rnkNote, rnkComment, rnkBlank: ;  // dropped (A7)
          else
            LRest.Add(AQ[LI].Emit);
        end;
    if LRest.Count > 0 then
    begin
      ARes.Add(Format(MERGE_NOTE + 'the lines below came from %s; review', [AQDesc]));
      Inc(AC.Noted);
      ARes.AddRange(LRest);
    end;
  finally
    LRest.Free;
  end;
end;

// Compose P (its body lines) with the stage block whose header is AQHdr; the result replaces AP's content.
procedure MergeCompose(ABook: TRuleBook; AP: TList<string>; AQHdr: Integer; const AQDesc: string; var AC: TMergeCounts);
var
  LQ   : TArray<TRuleNode>;
  LUsed: TArray<Boolean>;
  LRes : TList<string>;
  LLine: string;
  LPN  : TRuleNode;
  LI   : Integer;
begin
  SetLength(LQ, 0);
  for LI:= AQHdr + 1 to MergeBlockEnd(ABook, AQHdr, True) do
    LQ:= LQ + [ABook.Nodes[LI]];
  SetLength(LUsed, Length(LQ));
  LRes:= TList<string>.Create;
  try
    for LLine in AP do
    begin
      LPN:= ABook.ParseLine(LLine);
      try
        case LPN.Kind of
          rnkLink   : MergeLink(LPN, LLine, AQDesc, LQ, LUsed, LRes, AC);
          rnkDefault: MergeDefault(LPN, LLine, AQDesc, LQ, LUsed, LRes, AC);
          rnkMigrate: MergeMigrate(LPN, LLine, LQ, LUsed, LRes, AC);
          else
            LRes.Add(LLine);
        end;
      finally
        LPN.Free;
      end;
    end;
    MergeQRest(LQ, LUsed, AQDesc, LRes, AC);
    AP.Clear;
    AP.AddRange(LRes);
  finally
    LRes.Free;
  end;
end;

// 'TA -> TB (line 1)' for the #convert header at AHdr.
function MergeStageDesc(ABook: TRuleBook; AHdr: Integer): string;
begin
  Result:= Format('%s -> %s (line %d)', [ABook.Nodes[AHdr].FromType, ABook.Nodes[AHdr].ToType, AHdr + 1]);
end;

function MergeChainStages(ABook: TRuleBook; const AChain: TRuleChain): TChainMerge;
var
  LStage: TChainStage;
  LP    : TList<string>;
  LC    : TMergeCounts;
  LDescs: string;
  LBlank: Integer;
  LLast : TRuleNode;
  LI    : Integer;
  LHdr  : string;
  LTarget: string;
begin
  Result:= Default(TChainMerge);
  for LStage in AChain.Stages do
  begin
    Result.Problem:= MergeStageProblem(ABook, LStage);
    if Result.Problem <> '' then
      Exit;
  end;
  Result.NodeIdx:= AChain.Stages[0].NodeIdx;
  Result.LastIdx:= MergeBlockEnd(ABook, Result.NodeIdx, False);
  LBlank:= 0;
  while (Result.LastIdx - LBlank > Result.NodeIdx) and (ABook.Nodes[Result.LastIdx - LBlank].Kind = rnkBlank) do
    Inc(LBlank);
  LC:= Default(TMergeCounts);
  LDescs:= MergeStageDesc(ABook, Result.NodeIdx);
  LP:= TList<string>.Create;
  try
    for LI:= Result.NodeIdx + 1 to Result.LastIdx - LBlank do
      LP.Add(ABook.Nodes[LI].Emit);
    for LI:= 1 to High(AChain.Stages) do
    begin
      MergeCompose(ABook, LP, AChain.Stages[LI].NodeIdx, ABook.Nodes[AChain.Stages[LI].NodeIdx].FromType + ' -> '
        + ABook.Nodes[AChain.Stages[LI].NodeIdx].ToType + ' (line ' + IntToStr(AChain.Stages[LI].NodeIdx + 1) + ')', LC);
      LDescs:= LDescs + ' + ' + MergeStageDesc(ABook, AChain.Stages[LI].NodeIdx);
    end;
    LLast:= ABook.Nodes[AChain.Stages[High(AChain.Stages)].NodeIdx];
    LTarget:= ABook.Nodes[Result.NodeIdx].FromType + ' -> ' + LLast.ToType;
    LHdr:= LTarget;
    if LLast.Units <> '' then
      LHdr:= LHdr + ', ' + LLast.Units;
    Result.NewLines:= ['#convert ' + LHdr,
      Format(MERGE_NOTE + '%s = %s; %d composed, %d carried, %d dropped, %d noted -- validate on Save',
        [LDescs, LTarget, LC.Composed, LC.Carried, Length(LC.Dropped), LC.Noted])];
    Result.NewLines:= Result.NewLines + LP.ToArray;
    for LI:= 1 to LBlank do
      Result.NewLines:= Result.NewLines + [''];
    Result.Composed:= LC.Composed;
    Result.Carried:= LC.Carried;
    Result.Noted:= LC.Noted;
    Result.Dropped:= LC.Dropped;
  finally
    LP.Free;
  end;
end;

// A9: AOld replaced by ANew inside AUnits, de-duplicated; empty when AOld is not in AUnits.
function MergeSwapUnits(const AUnits: TArray<string>; const AOld: string; const ANew: TArray<string>): TArray<string>;
var
  LU, LN: string;
  LHit  : Boolean;

  procedure AddOne(const AUnit: string);
  var
    LX: string;
  begin
    for LX in Result do
      if SameText(LX, AUnit) then
        Exit;
    Result:= Result + [AUnit];
  end;

begin
  Result:= nil;
  LHit:= False;
  for LU in AUnits do
    if SameText(Trim(LU), Trim(AOld)) then
    begin
      LHit:= True;
      for LN in ANew do
        AddOne(Trim(LN));
    end
    else
      AddOne(Trim(LU));
  if not LHit then
    Result:= nil;
end;

function MergeUnitChain(ABook: TRuleBook; const AChain: TRuleChain): TChainMerge;
var
  LAdd, LSwap: TRuleNode;
  LUnits     : TArray<string>;
  LUnit      : string;
begin
  Result:= Default(TChainMerge);
  if (Length(AChain.Stages) < 2) or (AChain.Stages[0].NodeIdx < 0) or (AChain.Stages[0].NodeIdx >= ABook.Nodes.Count)
    or (AChain.Stages[1].NodeIdx < 0) or (AChain.Stages[1].NodeIdx >= ABook.Nodes.Count) then
  begin
    Result.Problem:= 'the unit lines are no longer there; reopen Rule chains';
    Exit;
  end;
  LAdd:= ABook.Nodes[AChain.Stages[0].NodeIdx];
  LSwap:= ABook.Nodes[AChain.Stages[1].NodeIdx];
  Result.NodeIdx:= AChain.Stages[0].NodeIdx;
  Result.LastIdx:= Result.NodeIdx;
  if LSwap.Kind <> rnkUseSwap then
    Result.Problem:= 'the #useswap line is no longer there; reopen Rule chains'
  else
    case LAdd.Kind of
      rnkUseSwap:
      begin
        LUnits:= MergeSwapUnits(LAdd.SwapNew, LSwap.SwapOld, LSwap.SwapNew);
        Result.NewLines:= ['#useswap ' + LAdd.SwapOld + ' -> ' + string.Join(', ', LUnits)];
      end;
      rnkConvert:
      begin
        LUnits:= MergeSwapUnits(LAdd.Units.Split([',']), LSwap.SwapOld, LSwap.SwapNew);
        Result.NewLines:= ['#convert ' + LAdd.FromType + ' -> ' + LAdd.ToType + ', ' + string.Join(', ', LUnits)];
      end;
      rnkUse:
      begin
        LUnits:= MergeSwapUnits([LAdd.UseUnit], LSwap.SwapOld, LSwap.SwapNew);
        for LUnit in LUnits do
          Result.NewLines:= Result.NewLines + ['#use ' + LUnit];
      end;
      else
        Result.Problem:= 'the line adding the unit is no longer there; reopen Rule chains';
    end;
  if (Result.Problem = '') and (Length(LUnits) = 0) then
    Result.Problem:= 'the line adding the unit no longer names the swapped unit; reopen Rule chains';
  if Result.Problem = '' then
    Result.Composed:= 1;
end;

function MergeChainPlan(ABook: TRuleBook; const AChain: TRuleChain): TChainMerge;
begin
  case AChain.Kind of
    ckChain    : Result:= MergeChainStages(ABook, AChain);
    ckUnitChain: Result:= MergeUnitChain(ABook, AChain);
    else
    begin
      Result:= Default(TChainMerge);
      Result.Problem:= MERGE_NOT_MERGEABLE;
    end;
  end;
end;

function ApplyChainMerge(ABook: TRuleBook; const AMerge: TChainMerge): Integer;
var
  LNodes: TArray<TRuleNode>;
  LLine : string;
  LI    : Integer;
begin
  Result:= -1;
  if (AMerge.Problem <> '') or (Length(AMerge.NewLines) = 0) then
    Exit;
  if (AMerge.NodeIdx < 0) or (AMerge.LastIdx < AMerge.NodeIdx) or (AMerge.LastIdx >= ABook.Nodes.Count) then
    Exit;
  if not (ABook.Nodes[AMerge.NodeIdx].Kind in [rnkConvert, rnkUse, rnkUseSwap]) then
    Exit;
  SetLength(LNodes, 0);
  for LLine in AMerge.NewLines do
    LNodes:= LNodes + [ABook.ParseLine(LLine)];
  ABook.Nodes.DeleteRange(AMerge.NodeIdx, AMerge.LastIdx - AMerge.NodeIdx + 1);
  for LI:= 0 to High(LNodes) do
    ABook.Nodes.Insert(AMerge.NodeIdx + LI, LNodes[LI]);
  Result:= AMerge.NodeIdx;
end;
// ---- end Task 2 implementation ----

function ChainBareName(const AName: string): string;
var
  LPos: Integer;
begin
  Result:= Trim(AName);
  LPos:= LastDelimiter('.', Result);
  if LPos > 0 then
    Result:= Trim(Copy(Result, LPos + 1, MaxInt));
end;

function SameChainType(const A, B: string): Boolean;
var
  LA: string;
begin
  LA:= ChainBareName(A);
  Result:= (LA <> '') and SameText(LA, ChainBareName(B));
end;

// The qualifier of a name ('Vcl.X.TLabel' -> 'Vcl.X'); '' when bare.
function QualifierOf(const AName: string): string;
var
  LName: string;
  LPos : Integer;
begin
  LName:= Trim(AName);
  LPos := LastDelimiter('.', LName);
  if LPos > 0 then
    Result:= Copy(LName, 1, LPos - 1)
  else
    Result:= '';
end;

// The qualifier note for the first link (To of one stage, From of the next) whose two names are both qualified and differ.
function QualifierNote(const AChain: TRuleChain): string;
var
  LNext : Integer;
  LCount: Integer;
  LI    : Integer;
  LQa   : string;
  LQb   : string;
begin
  Result:= '';
  LCount:= Length(AChain.Stages);
  for LI:= 0 to LCount - 1 do
  begin
    LNext:= LI + 1;
    if LNext >= LCount then
    begin
      if AChain.Kind <> ckCycle then
        Break;
      LNext:= 0;
    end;
    LQa:= QualifierOf(AChain.Stages[LI].ToType);
    LQb:= QualifierOf(AChain.Stages[LNext].FromType);
    if (LQa <> '') and (LQb <> '') and not SameText(LQa, LQb) then
      Exit(Format(QUALIFIER_NOTE_FMT, [LQa, LQb]));
  end;
end;

type
  TRuleInfo = record
    NodeIdx: Integer;
    FromT  : string;
    ToT    : string;
  end;

procedure AddFinding(AList: TList<TRuleChain>; AKind: TChainKind; const AStages: TArray<TChainStage>; const AKey: string);
var
  LChain: TRuleChain;
begin
  LChain.Kind  := AKind;
  LChain.Stages:= AStages;
  LChain.Key   := AKey;
  AList.Add(LChain);
end;

function StageOf(const ARule: TRuleInfo): TChainStage;
begin
  Result.NodeIdx := ARule.NodeIdx;
  Result.FromType:= ARule.FromT;
  Result.ToType  := ARule.ToT;
end;

// Detection steps 1-4: duplicates, chains, cycles.
procedure FindConvertFindings(ABook: TRuleBook; AList: TList<TRuleChain>);  // dl:ok cyclomatic-complexity@f08a, cognitive-complexity@6cf1 -- REVIEWED 2026-10-27 spec 5.1 steps 1-4 are one deterministic pass over shared arrays; splitting it only passes six arrays around
var
  LRules  : TList<TRuleInfo>;
  LInfo   : TRuleInfo;
  LNode   : TRuleNode;
  LHeader : Integer;
  LWinner : TArray<Integer>;
  LNext   : TArray<Integer>;
  LIsNext : TArray<Boolean>;
  LDone   : TArray<Boolean>;
  LStages : TList<TChainStage>;
  LOnPath : TArray<Boolean>;
  LKey    : string;
  LI      : Integer;
  LJ      : Integer;
  LCur    : Integer;
  LCount  : Integer;
  LCloses : Boolean;
begin
  LRules:= TList<TRuleInfo>.Create;
  LStages:= TList<TChainStage>.Create;
  try
    for LHeader in ABook.ConvertHeaders do
    begin
      LNode:= ABook.Nodes[LHeader];
      if LNode.ToType = '' then
        Continue;
      LInfo.NodeIdx:= LHeader;
      LInfo.FromT  := LNode.FromType;
      LInfo.ToT    := LNode.ToType;
      LRules.Add(LInfo);
    end;
    LCount:= LRules.Count;
    SetLength(LWinner, LCount);
    SetLength(LNext, LCount);
    SetLength(LIsNext, LCount);
    SetLength(LDone, LCount);
    SetLength(LOnPath, LCount);
    for LI:= 0 to LCount - 1 do
    begin
      LWinner[LI]:= LI;
      for LJ:= 0 to LI - 1 do
        if SameChainType(LRules[LJ].FromT, LRules[LI].FromT) then
        begin
          LWinner[LI]:= LJ;
          Break;
        end;
    end;
    // duplicates: one finding per winner that has losers
    for LI:= 0 to LCount - 1 do
    begin
      if LWinner[LI] <> LI then
        Continue;
      LStages.Clear;
      LStages.Add(StageOf(LRules[LI]));
      for LJ:= LI + 1 to LCount - 1 do
        if LWinner[LJ] = LI then
          LStages.Add(StageOf(LRules[LJ]));
      if LStages.Count > 1 then
        AddFinding(AList, ckDuplicateFrom, LStages.ToArray, 'dup:' + LowerCase(ChainBareName(LRules[LI].FromT)));
    end;
    // links between winners
    for LI:= 0 to LCount - 1 do
    begin
      LNext[LI]:= -1;
      if LWinner[LI] <> LI then
        Continue;
      for LJ:= 0 to LCount - 1 do
        if (LWinner[LJ] = LJ) and SameChainType(LRules[LJ].FromT, LRules[LI].ToT) then
        begin
          LNext[LI]:= LJ;
          Break;
        end;
      if LNext[LI] >= 0 then
        LIsNext[LNext[LI]]:= True;
    end;
    // chains from every root
    for LI:= 0 to LCount - 1 do
    begin
      if (LWinner[LI] <> LI) or LIsNext[LI] then
        Continue;
      LStages.Clear;
      for LJ:= 0 to LCount - 1 do
        LOnPath[LJ]:= False;
      LCur:= LI;
      while (LCur >= 0) and not LOnPath[LCur] do
      begin
        LOnPath[LCur]:= True;
        LStages.Add(StageOf(LRules[LCur]));
        LCur:= LNext[LCur];
      end;
      if LStages.Count < 2 then
        Continue;
      // key: the From of every stage, then the last To unless it runs back into the path
      LKey:= 'chain:';
      for LJ:= 0 to LStages.Count - 1 do
        LKey:= LKey + IfThen(LJ > 0, '>', '') + LowerCase(ChainBareName(LStages[LJ].FromType));
      if LCur < 0 then
        LKey:= LKey + '>' + LowerCase(ChainBareName(LStages[LStages.Count - 1].ToType));
      AddFinding(AList, ckChain, LStages.ToArray, LKey);
    end;
    // cycles: a winner whose Next walk returns to it
    for LI:= 0 to LCount - 1 do
    begin
      if (LWinner[LI] <> LI) or LDone[LI] then
        Continue;
      LStages.Clear;
      for LJ:= 0 to LCount - 1 do
        LOnPath[LJ]:= False;
      LCur:= LI;
      LCloses:= False;
      while LCur >= 0 do
      begin
        if LCur = LI then
        begin
          if LStages.Count > 0 then
          begin
            LCloses:= True;
            Break;
          end;
        end
        else if LOnPath[LCur] then
          Break;
        LOnPath[LCur]:= True;
        LStages.Add(StageOf(LRules[LCur]));
        LCur:= LNext[LCur];
      end;
      if not LCloses then
        Continue;
      LKey:= 'cycle:';
      for LJ:= 0 to LStages.Count - 1 do
      begin
        LKey:= LKey + IfThen(LJ > 0, '>', '') + LowerCase(ChainBareName(LStages[LJ].FromType));
        for LCur:= 0 to LCount - 1 do
          if LRules[LCur].NodeIdx = LStages[LJ].NodeIdx then
            LDone[LCur]:= True;
      end;
      AddFinding(AList, ckCycle, LStages.ToArray, LKey);
    end;
  finally
    LStages.Free;
    LRules.Free;
  end;
end;

// The units a node adds, trimmed, in order.
function AddedUnits(const ANode: TRuleNode): TArray<string>;
var
  LList: TList<string>;
  LPart: string;
begin
  LList:= TList<string>.Create;
  try
    case ANode.Kind of
      rnkUseSwap:
        for LPart in ANode.SwapNew do
          LList.Add(Trim(LPart));
      rnkUse:
        LList.Add(Trim(ANode.UseUnit));
      rnkConvert:
        for LPart in ANode.Units.Split([',']) do
          if Trim(LPart) <> '' then
            LList.Add(Trim(LPart));
    end;
    Result:= LList.ToArray;
  finally
    LList.Free;
  end;
end;

// Detection step 5: a #useswap whose Old unit is added by another line.
procedure FindUnitFindings(ABook: TRuleBook; AList: TList<TRuleChain>);
var
  LSwap   : Integer;
  LAdder  : Integer;
  LUnit   : string;
  LStages : TArray<TChainStage>;
  LKey    : string;
  LNodeS  : TRuleNode;
  LNodeA  : TRuleNode;
  LFound  : Boolean;
begin
  for LSwap:= 0 to ABook.Nodes.Count - 1 do
  begin
    LNodeS:= ABook.Nodes[LSwap];
    if LNodeS.Kind <> rnkUseSwap then
      Continue;
    for LAdder:= 0 to ABook.Nodes.Count - 1 do
    begin
      if LAdder = LSwap then
        Continue;
      LNodeA:= ABook.Nodes[LAdder];
      LFound:= False;
      for LUnit in AddedUnits(LNodeA) do
        if SameChainType(LUnit, LNodeS.SwapOld) then
        begin
          LFound:= True;
          Break;
        end;
      if not LFound then
        Continue;
      SetLength(LStages, 2);
      LStages[0].NodeIdx := LAdder;
      LStages[0].FromType:= if LNodeA.Kind = rnkUseSwap then LNodeA.SwapOld else '';
      LStages[0].ToType  := LUnit;
      LStages[1].NodeIdx := LSwap;
      LStages[1].FromType:= LNodeS.SwapOld;
      LStages[1].ToType  := string.Join(', ', LNodeS.SwapNew);
      LKey:= 'unit:';
      if LStages[0].FromType <> '' then
        LKey:= LKey + LowerCase(ChainBareName(LStages[0].FromType)) + '>';
      LKey:= LKey + LowerCase(ChainBareName(LUnit)) + '>';
      if Length(LNodeS.SwapNew) > 0 then
        LKey:= LKey + LowerCase(ChainBareName(LNodeS.SwapNew[0]));
      AddFinding(AList, ckUnitChain, LStages, LKey);
    end;
  end;
end;

function FindRuleChains(ABook: TRuleBook): TArray<TRuleChain>;
var
  LList: TList<TRuleChain>;
begin
  LList:= TList<TRuleChain>.Create;
  try
    FindConvertFindings(ABook, LList);
    FindUnitFindings(ABook, LList);
    LList.Sort(TComparer<TRuleChain>.Construct(
      function(const A, B: TRuleChain): Integer
      begin
        Result:= A.Stages[0].NodeIdx - B.Stages[0].NodeIdx;
        if Result = 0 then
          Result:= Ord(A.Kind) - Ord(B.Kind);
      end));
    Result:= LList.ToArray;
  finally
    LList.Free;
  end;
end;

function ChainPathText(const AChain: TRuleChain): string;
var
  LI: Integer;
begin
  Result:= '';
  if Length(AChain.Stages) = 0 then
    Exit;
  case AChain.Kind of
    ckChain:
      begin
        Result:= AChain.Stages[0].FromType;
        for LI:= 0 to High(AChain.Stages) do
          Result:= Result + ARROW + AChain.Stages[LI].ToType;
      end;
    ckCycle:
      begin
        for LI:= 0 to High(AChain.Stages) do
          Result:= Result + (if LI > 0 then ARROW else '') + AChain.Stages[LI].FromType;
        Result:= Result + ARROW + AChain.Stages[0].FromType;
      end;
    ckDuplicateFrom:
      Result:= AChain.Stages[0].FromType;
    ckUnitChain:
      begin
        if AChain.Stages[0].FromType <> '' then
          Result:= AChain.Stages[0].FromType + ARROW;
        Result:= Result + AChain.Stages[0].ToType + ARROW + AChain.Stages[1].ToType;
      end;
  end;
end;

// 'a, b, c' of the node indexes + 1 of the stages from AFirst on.
function LineList(const AChain: TRuleChain; AFirst: Integer): string;
var
  LI: Integer;
begin
  Result:= '';
  for LI:= AFirst to High(AChain.Stages) do
    Result:= Result + IfThen(LI > AFirst, ', ', '') + IntToStr(AChain.Stages[LI].NodeIdx + 1);
end;

function ChainRowText(const AChain: TRuleChain): string;
begin
  case AChain.Kind of
    ckChain:
      Result:= Format('chain %s (lines %s)', [ChainPathText(AChain), LineList(AChain, 0)]);
    ckCycle:
      Result:= Format('cycle %s (lines %s)', [ChainPathText(AChain), LineList(AChain, 0)]);
    ckDuplicateFrom:
      Result:= Format('duplicate From %s (line %d wins; %s never applied)',
        [ChainPathText(AChain), AChain.Stages[0].NodeIdx + 1, LineList(AChain, 1)]);
    ckUnitChain:
      Result:= Format('unit chain %s (lines %s)', [ChainPathText(AChain), LineList(AChain, 0)]);
  end;
end;

function ChainMarkText(const AChain: TRuleChain; AStage: Integer): string;
var
  LLast : Integer;
  LStage: TChainStage;
begin
  Result:= '';
  LLast:= High(AChain.Stages);
  if (AStage < 0) or (AStage > LLast) then
    Exit;
  LStage:= AChain.Stages[AStage];
  case AChain.Kind of
    ckChain:
      Result:= Format(CHAIN_MARK_FMT, [ChainPathText(AChain), AStage + 1, LLast + 1,
        AChain.Stages[0].FromType, AChain.Stages[0].ToType, AChain.Stages[LLast].ToType]) + QualifierNote(AChain);
    ckCycle:
      Result:= Format(CYCLE_MARK_FMT, [ChainPathText(AChain)]) + QualifierNote(AChain);
    ckDuplicateFrom:
      if AStage = 0 then
        Result:= Format(DUP_WIN_FMT, [LStage.FromType, IfThen(LLast > 1, 'lines', 'line'),
          LineList(AChain, 1) + IfThen(LLast > 1, ' are', ' is')])
      else
        Result:= Format(DUP_LOSE_FMT, [AChain.Stages[0].FromType, AChain.Stages[0].NodeIdx + 1]);
    ckUnitChain:
      if AStage = 0 then
        Result:= Format(UNIT_ADD_FMT, [ChainPathText(AChain), LStage.ToType, AChain.Stages[1].NodeIdx + 1, LStage.ToType])
      else if AChain.Stages[0].FromType <> '' then
        Result:= Format(UNIT_SWAP_FMT, [ChainPathText(AChain), AChain.Stages[0].ToType, LStage.ToType,
          AChain.Stages[0].NodeIdx + 1, AChain.Stages[0].FromType, LStage.ToType])
      else
        Result:= Format(UNIT_SWAP_ADD_FMT, [ChainPathText(AChain), AChain.Stages[0].ToType, LStage.ToType,
          AChain.Stages[0].NodeIdx + 1, LStage.ToType]);
  end;
end;

function CanMergeChain(const AChain: TRuleChain): Boolean;
begin
  Result:= AChain.Kind in [ckChain, ckUnitChain];
end;

function CanSplitChain(const AChain: TRuleChain): Boolean;
begin
  Result:= AChain.Kind = ckChain;
end;

function CountPhrase(ACount: Integer; const ASingular, APlural: string): string;
begin
  Result:= IntToStr(ACount) + ' ' + (if ACount = 1 then ASingular else APlural);
end;

function ChainStatusText(const AChains: TArray<TRuleChain>): string;
var
  LChain : TRuleChain;
  LCounts: array[TChainKind] of Integer;
  LKind  : TChainKind;
  LParts : TArray<string>;
begin
  Result:= '';
  if Length(AChains) = 0 then
    Exit;
  for LKind:= Low(TChainKind) to High(TChainKind) do
    LCounts[LKind]:= 0;
  for LChain in AChains do
    Inc(LCounts[LChain.Kind]);
  if LCounts[ckChain] > 0 then
    LParts:= LParts + [CountPhrase(LCounts[ckChain], 'chain', 'chains')];
  if LCounts[ckCycle] > 0 then
    LParts:= LParts + [CountPhrase(LCounts[ckCycle], 'cycle', 'cycles')];
  if LCounts[ckDuplicateFrom] > 0 then
    LParts:= LParts + [CountPhrase(LCounts[ckDuplicateFrom], 'duplicate From type', 'duplicate From types')];
  if LCounts[ckUnitChain] > 0 then
    LParts:= LParts + [CountPhrase(LCounts[ckUnitChain], 'unit chain', 'unit chains')];
  Result:= Format(STATUS_FMT, [string.Join(', ', LParts)]);
end;

function ChainsToOffer(const AChains: TArray<TRuleChain>; const AAsked: TArray<string>): TArray<TRuleChain>;
var
  LChain: TRuleChain;
  LAsked: string;
  LSeen : Boolean;
begin
  Result:= nil;
  for LChain in AChains do
  begin
    if not (CanMergeChain(LChain) or CanSplitChain(LChain)) then
      Continue;
    LSeen:= False;
    for LAsked in AAsked do
      if SameText(LAsked, LChain.Key) then
      begin
        LSeen:= True;
        Break;
      end;
    if not LSeen then
      Result:= Result + [LChain];
  end;
end;

// True for a mark StaticChainMarks owns (the text shapes of ChainMarkText).
function IsChainMark(const AMark: TRuleMark): Boolean;
begin
  var LChainText: Boolean:= AMark.Text.StartsWith('chain ') or AMark.Text.StartsWith('cycle ')
    or AMark.Text.StartsWith('duplicate From type ') or AMark.Text.StartsWith('unit chain ');
  Result:= LChainText and AMark.IsWarning and not AMark.FromSyntax;
end;

function StaticChainMarks(ABook: TRuleBook): Integer;
var
  LChains: TArray<TRuleChain>;
  LWanted: TStringList; // '<node index>|<mark text>' of every mark the current findings give
  LChain : TRuleChain;
  LNode  : TRuleNode;
  LKeep  : TArray<TRuleMark>;
  LMark  : TRuleMark;
  LI     : Integer;
begin
  Result := 0;
  LChains:= FindRuleChains(ABook);
  LWanted:= TStringList.Create;
  try
    LWanted.CaseSensitive:= True;
    for LChain in LChains do
      for LI:= 0 to High(LChain.Stages) do
        LWanted.Add(IntToStr(LChain.Stages[LI].NodeIdx) + '|' + ChainMarkText(LChain, LI));
    LWanted.Sorted:= True;
    for LI:= 0 to ABook.Nodes.Count - 1 do
    begin
      LNode:= ABook.Nodes[LI];
      LKeep:= nil;
      for LMark in LNode.Marks do
        if not IsChainMark(LMark) or (LWanted.IndexOf(IntToStr(LI) + '|' + LMark.Text) >= 0) then
          LKeep:= LKeep + [LMark];
      if Length(LKeep) <> Length(LNode.Marks) then
        LNode.Marks:= LKeep;
    end;
  finally
    LWanted.Free;
  end;
  for LChain in LChains do
    for LI:= 0 to High(LChain.Stages) do
      if AddStaticWarningMark(ABook.Nodes[LChain.Stages[LI].NodeIdx], ChainMarkText(LChain, LI)) then
        Inc(Result);
end;

// ---- Task 3 (split planning, stage-book text) ----

// Stage number per #convert header node: roots 1, stage(R2) = max(stage(R1) + 1) over the ckChain links;
// links touching a cycle member are ignored. Fixed point, at most one round per node.
procedure AssignChainStages(ABook: TRuleBook; const AChains: TArray<TRuleChain>; AStage: TDictionary<Integer, Integer>);
var
  LCycle  : TDictionary<Integer, Boolean>;
  LChain  : TRuleChain;
  LI, LJ  : Integer;
  LRound  : Integer;
  LFrom   : Integer;
  LTo     : Integer;
  LChanged: Boolean;
begin
  LCycle:= TDictionary<Integer, Boolean>.Create;
  try
    for LI:= 0 to ABook.Nodes.Count - 1 do
      if ABook.Nodes[LI].Kind = rnkConvert then
        AStage.Add(LI, 1);
    for LChain in AChains do
      if LChain.Kind = ckCycle then
        for LJ:= 0 to High(LChain.Stages) do
          LCycle.AddOrSetValue(LChain.Stages[LJ].NodeIdx, True);
    LRound:= 0;
    repeat
      LChanged:= False;
      Inc(LRound);
      for LChain in AChains do
        if LChain.Kind = ckChain then
          for LJ:= 0 to High(LChain.Stages) - 1 do
          begin
            LFrom:= LChain.Stages[LJ].NodeIdx;
            LTo  := LChain.Stages[LJ + 1].NodeIdx;
            if LCycle.ContainsKey(LFrom) or LCycle.ContainsKey(LTo)
              or not AStage.ContainsKey(LFrom) or not AStage.ContainsKey(LTo) then
              Continue;
            if AStage[LFrom] + 1 > AStage[LTo] then
            begin
              AStage[LTo]:= AStage[LFrom] + 1;
              LChanged   := True;
            end;
          end;
    until (not LChanged) or (LRound > ABook.Nodes.Count);
  finally
    LCycle.Free;
  end;
end;

// Adds the distinct '#apply X' names of ABlock to ANames, in order.
procedure AddApplyNames(const ABlock: TRuleBlock; ANames: TList<string>);
var
  LLine: string;
  LName: string;
begin
  for LLine in ABlock.RawText.Split([#10]) do
    if StartsText('#apply ', Trim(LLine)) then
    begin
      LName:= Trim(Copy(Trim(LLine), Length('#apply ') + 1, MaxInt));
      if (LName <> '') and not ANames.Contains(LName) then
        ANames.Add(LName);
    end;
end;

// The header node indexes of stage ALevel in file order, and (stage 2 and up) the #apply names of their blocks.
procedure CollectChainStage(ABook: TRuleBook; AStage: TDictionary<Integer, Integer>; const ABlocks: TRuleBlocks; ALevel: Integer;
  out AIdxs: TArray<Integer>; out ANames: TArray<string>);
var
  LIdxs : TList<Integer>;
  LNames: TList<string>;
  LJ, LK: Integer;
  LNo   : Integer;
begin
  LIdxs := TList<Integer>.Create;
  LNames:= TList<string>.Create;
  try
    for LJ:= 0 to ABook.Nodes.Count - 1 do  // file order
    begin
      if not (AStage.TryGetValue(LJ, LNo) and (LNo = ALevel)) then
        Continue;
      LIdxs.Add(LJ);
      if ALevel = 1 then
        Continue;
      for LK:= 0 to High(ABlocks) do
        if (ABlocks[LK].Kind = rbkConvert) and (ABlocks[LK].StartLine - 1 = LJ) then
          AddApplyNames(ABlocks[LK], LNames);
    end;
    AIdxs := LIdxs.ToArray;
    ANames:= LNames.ToArray;
  finally
    LNames.Free;
    LIdxs.Free;
  end;
end;

function SplitChainPlan(ABook: TRuleBook; const AChains: TArray<TRuleChain>): TChainSplit;
var
  LStage  : TDictionary<Integer, Integer>;
  LBlocks : TRuleBlocks;
  LI      : Integer;
  LNo     : Integer;
  LMax    : Integer;
begin
  LStage:= TDictionary<Integer, Integer>.Create;
  try
    AssignChainStages(ABook, AChains, LStage);
    LMax:= 1;
    for LNo in LStage.Values do
      if LNo > LMax then
        LMax:= LNo;
    SetLength(Result.Stages, LMax);
    SetLength(Result.Mappings, LMax);
    LBlocks:= SplitRulesBlocks(ABook.SaveToString);
    for LI:= 1 to LMax do
      CollectChainStage(ABook, LStage, LBlocks, LI, Result.Stages[LI - 1], Result.Mappings[LI - 1]);
  finally
    LStage.Free;
  end;
end;
function StageBookPath(const ABookPath: string; AStage: Integer): string;
begin
  Result:= ChangeFileExt(ABookPath, '') + '.stage' + IntToStr(AStage) + ExtractFileExt(ABookPath);
end;

// Positions in ABlocks of the rbkConvert blocks whose header node is in AHeaderIdx.
function ChainBlockPositions(const ABlocks: TRuleBlocks; const AHeaderIdx: TArray<Integer>): TArray<Integer>;
var
  LI, LJ: Integer;
begin
  Result:= nil;
  for LI:= 0 to High(ABlocks) do
    if ABlocks[LI].Kind = rbkConvert then
      for LJ:= 0 to High(AHeaderIdx) do
        if ABlocks[LI].StartLine - 1 = AHeaderIdx[LJ] then
        begin
          Result:= Result + [LI];
          Break;
        end;
end;

function StageBookText(ABook: TRuleBook; const AHeaderIdx: TArray<Integer>; const AMappings: TArray<string>): string;
var
  LBlocks : TRuleBlocks;
  LPos    : TArray<Integer>;
  LName   : string;
  LNode   : TRuleNode;
  LI      : Integer;
  LBuilder: TStringBuilder;
begin
  LBuilder:= TStringBuilder.Create;
  try
    if ABook.DepthState = bdsValid then
      LBuilder.Append('#depth ').Append(ABook.Depth).Append(#13#10);
    for LName in AMappings do
      for LNode in ABook.MappingNodesNamed(LName) do
        LBuilder.Append(LNode.Emit).Append(#13#10);
    LBlocks:= SplitRulesBlocks(ABook.SaveToString);
    LPos   := ChainBlockPositions(LBlocks, AHeaderIdx);
    for LI:= 0 to High(LPos) do
      LBuilder.Append(EnsureTrailingEol(LBlocks[LPos[LI]]).RawText);
    Result:= LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;
function RemainingBookText(ABook: TRuleBook; const AMovedHeaderIdx: TArray<Integer>): string;
var
  LBlocks, LRemaining, LMoved: TRuleBlocks;
begin
  LBlocks:= SplitRulesBlocks(ABook.SaveToString);
  SplitOut(LBlocks, ChainBlockPositions(LBlocks, AMovedHeaderIdx), LRemaining, LMoved);
  Result:= JoinBlocks(LRemaining);
end;

function SplitStatusText(const ABookPath: string; const AStageFiles: TArray<string>; AMoved: Integer; const AMappings: TArray<string>): string;
var
  LNames: TArray<string>;
  LI    : Integer;
begin
  SetLength(LNames, Length(AStageFiles));
  for LI:= 0 to High(AStageFiles) do
    LNames[LI]:= ExtractFileName(AStageFiles[LI]);
  Result:= Format('Split %d block(s) into %s -- convert with %s first, then %s (check both on the Convert tab, in that order)',
    [AMoved, string.Join(', ', LNames), ExtractFileName(ABookPath), string.Join(', then ', LNames)]);
  if Length(AMappings) > 0 then
    Result:= Result + '; copied #mapping ' + string.Join(', ', AMappings) + ' into the stage book';
end;

function CanMergeAll(const AChecked: TArray<TRuleChain>): Boolean;
begin
  Result:= Length(AChecked) > 0;
  for var LChain: TRuleChain in AChecked do
    if not CanMergeChain(LChain) then
      Exit(False);
end;

function CanSplitAll(const AChecked: TArray<TRuleChain>): Boolean;
begin
  Result:= Length(AChecked) > 0;
  for var LChain: TRuleChain in AChecked do
    if not CanSplitChain(LChain) then
      Exit(False);
end;

function ChainKeysAsked(const AAsked: TArray<string>; const AListed: TArray<TRuleChain>): TArray<string>;
begin
  Result:= Copy(AAsked);
  for var LChain: TRuleChain in AListed do
    if (LChain.Key <> '') and (IndexText(LChain.Key, Result) < 0) then
      Result:= Result + [LChain.Key];
end;

function MergeStatusText(const AMerged, AProblems: TArray<string>): string;
begin
  if Length(AMerged) = 0 then
    Exit('Nothing merged: ' + string.Join('; ', AProblems));
  Result:= Format('Merged %d chain(s): %s -- review the composed block, then Save', [Length(AMerged), string.Join(', ', AMerged)]);
  if Length(AProblems) > 0 then
    Result:= Result + '; not merged: ' + string.Join('; ', AProblems);
end;

function MergeChainText(const AChainText: string; const AMerge: TChainMerge): string;
begin
  Result:= AChainText;
  if Length(AMerge.Dropped) > 0 then
    Result:= Format('%s (dropped %d line(s) the later stage does not map: %s -- see its #note)',
      [AChainText, Length(AMerge.Dropped), string.Join('; ', AMerge.Dropped)]);
end;

function StageAppendText(const AExisting, AStage: string): string;
var
  LLines: TArray<string>;
  LKept : TArray<string>;
  LInPre: Boolean;
begin
  // Only the preamble's #depth goes: the existing book's own #depth governs.
  LLines:= AStage.Replace(#13#10, #10).Split([#10]);
  LKept := nil;
  LInPre:= True;
  for var LLine: string in LLines do
  begin
    if StartsText('#convert', TrimLeft(LLine)) then
      LInPre:= False;
    if not (LInPre and StartsText('#depth', TrimLeft(LLine))) then
      LKept:= LKept + [LLine];
  end;
  Result:= JoinBlocks(ConcatBlocks(SplitRulesBlocks(AExisting), SplitRulesBlocks(string.Join(#13#10, LKept))));
end;

end.