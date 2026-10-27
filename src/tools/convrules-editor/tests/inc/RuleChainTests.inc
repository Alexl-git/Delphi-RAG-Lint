{ CHAIN-1 rule chains: model tests of ConvRules.RuleChains.
  Plan docs\superpowers\plans\2026-10-27-converter-chain1.md, Tasks 1-3 (spec 2026-10-27-converter-chain1-design.md).
  Task 1 owns the shared fixtures, TestRuleChainsDetect / Texts / Marks. Task 2 fills
  TestRuleChainsMerge, Task 3 fills TestRuleChainsSplit -- each in its own block below. }

const
  CHAIN_CRLF            = #13#10;
  CHAIN_BOOK_CHAIN      = '#convert TA -> TB' + CHAIN_CRLF + '#link x <- y' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#link z <- x';
  CHAIN_BOOK_SHARED     = '#convert TA -> TB' + CHAIN_CRLF + '#convert TX -> TB' + CHAIN_CRLF + '#convert TB -> TC';
  CHAIN_BOOK_CYCLE      = '#convert TA -> TB' + CHAIN_CRLF + '#convert TB -> TA';
  CHAIN_BOOK_INTO_CYCLE = '#convert TX -> TA' + CHAIN_CRLF + '#convert TA -> TB' + CHAIN_CRLF + '#convert TB -> TA';
  CHAIN_BOOK_DUP        = '#convert TA -> TB' + CHAIN_CRLF + '#link a <- b' + CHAIN_CRLF + '#convert TA -> TC';
  CHAIN_BOOK_FROMONLY   = '#convert TA -> ' + CHAIN_CRLF + '#convert TA -> TB';
  CHAIN_BOOK_QUAL       = '#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable' + CHAIN_CRLF + '#convert TFDTable -> Lib.TFDMemTable';
  CHAIN_BOOK_QUALDIFF   = '#convert TA -> Vcl.X.TLabel' + CHAIN_CRLF + '#convert Lib.TLabel -> TC';
  CHAIN_BOOK_UNIT_SWAP  = '#useswap UnitA -> UnitB' + CHAIN_CRLF + '#useswap UnitB -> UnitC';
  CHAIN_BOOK_UNIT_USE   = '#use UnitB' + CHAIN_CRLF + '#useswap UnitB -> UnitC';
  CHAIN_BOOK_UNIT_HDR   = '#convert TA -> TB, UnitB' + CHAIN_CRLF + '#useswap UnitB -> UnitC';
  CHAIN_BOOK_UNIT_CONF  = '#use UnitB' + CHAIN_CRLF + '#unuse UnitB';
  CHAIN_BOOK_CLEAN      = '#convert TA -> TB' + CHAIN_CRLF + '#convert TC -> TD' + CHAIN_CRLF + '#useswap U1 -> U2';

// Loads AText into a new book owned by ABooks.
function ChainMakeBook(ABooks: TObjectList<TRuleBook>; const AText: string): TRuleBook;
begin
  Result:= TRuleBook.Create;
  ABooks.Add(Result);
  Result.LoadFromString(AText);
end;

// '0,2' -- the node indexes of a finding's stages.
function ChainIdxText(const AChain: TRuleChain): string;
var
  LI: Integer;
begin
  Result:= '';
  for LI:= 0 to High(AChain.Stages) do
    Result:= Result + IfThen(LI > 0, ',', '') + IntToStr(AChain.Stages[LI].NodeIdx);
end;

procedure TestRuleChainsDetect;
var
  Books: TObjectList<TRuleBook>;
  C    : TArray<TRuleChain>;

  function Find(const AText: string): TArray<TRuleChain>;
  begin
    Result:= FindRuleChains(ChainMakeBook(Books, AText));
  end;

begin
  Books:= TObjectList<TRuleBook>.Create(True);
  try
    C:= Find(CHAIN_BOOK_CHAIN);
    Check('chains.detect.chain', (Length(C) = 1) and (C[0].Kind = ckChain) and (ChainIdxText(C[0]) = '0,2') and (C[0].Key = 'chain:ta>tb>tc'),
      IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_SHARED);
    Check('chains.detect.shared.tail', (Length(C) = 2) and (C[0].Kind = ckChain) and (C[1].Kind = ckChain)
      and (ChainIdxText(C[0]) = '0,2') and (ChainIdxText(C[1]) = '1,2')
      and (C[0].Key = 'chain:ta>tb>tc') and (C[1].Key = 'chain:tx>tb>tc'), IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_CYCLE);
    Check('chains.detect.cycle', (Length(C) = 1) and (C[0].Kind = ckCycle) and (ChainIdxText(C[0]) = '0,1') and (C[0].Key = 'cycle:ta>tb'),
      IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_INTO_CYCLE);
    Check('chains.detect.into.cycle', (Length(C) = 2) and (C[0].Kind = ckChain) and (ChainIdxText(C[0]) = '0,1,2')
      and (C[1].Kind = ckCycle) and (ChainIdxText(C[1]) = '1,2'), IntToStr(Length(C)));
    C:= Find('#convert TA -> ta');
    Check('chains.detect.self.cycle', (Length(C) = 1) and (C[0].Kind = ckCycle) and (Length(C[0].Stages) = 1) and (C[0].Key = 'cycle:ta'),
      IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_DUP);
    Check('chains.detect.dup', (Length(C) = 1) and (C[0].Kind = ckDuplicateFrom) and (ChainIdxText(C[0]) = '0,2') and (C[0].Key = 'dup:ta'),
      IntToStr(Length(C)));
    C:= Find('#convert TA -> TB' + CHAIN_CRLF + '#convert TA -> TX' + CHAIN_CRLF + '#convert TX -> TC');
    Check('chains.detect.dup.loser.not.linked', (Length(C) = 1) and (C[0].Kind = ckDuplicateFrom), IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_FROMONLY);
    Check('chains.detect.fromonly', Length(C) = 0, IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_QUAL);
    Check('chains.detect.bare.match', (Length(C) = 1) and (C[0].Kind = ckChain)
      and (ChainPathText(C[0]) = 'Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable -> Lib.TFDMemTable'), IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_QUALDIFF);
    Check('chains.detect.qualifiers.differ', (Length(C) = 1) and (C[0].Kind = ckChain)
      and EndsText(' (qualifiers differ: Vcl.X vs Lib)', ChainMarkText(C[0], 0)), IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_UNIT_SWAP);
    Check('chains.detect.unit.swap', (Length(C) = 1) and (C[0].Kind = ckUnitChain) and (ChainIdxText(C[0]) = '0,1') and (C[0].Key = 'unit:unita>unitb>unitc'),
      IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_UNIT_USE);
    Check('chains.detect.unit.use', (Length(C) = 1) and (C[0].Kind = ckUnitChain) and (C[0].Key = 'unit:unitb>unitc'), IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_UNIT_HDR);
    Check('chains.detect.unit.header', (Length(C) = 1) and (C[0].Kind = ckUnitChain) and (ChainIdxText(C[0]) = '0,1'), IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_UNIT_CONF);
    Check('chains.detect.unit.conflict.not', Length(C) = 0, IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_CLEAN);
    Check('chains.detect.clean', (Length(C) = 0) and (ChainStatusText(nil) = ''), IntToStr(Length(C)));
    C:= Find(CHAIN_BOOK_INTO_CYCLE + CHAIN_CRLF + '#useswap A -> B' + CHAIN_CRLF + '#useswap B -> C');
    Check('chains.detect.order', (Length(C) = 3) and (C[0].Kind = ckChain) and (C[1].Kind = ckCycle) and (C[2].Kind = ckUnitChain)
      and (C[0].Stages[0].NodeIdx <= C[1].Stages[0].NodeIdx) and (C[1].Stages[0].NodeIdx <= C[2].Stages[0].NodeIdx), IntToStr(Length(C)));
  finally
    Books.Free;
  end;
end;

procedure TestRuleChainsTexts;
var
  Books: TObjectList<TRuleBook>;
  C    : TArray<TRuleChain>;
  D    : TArray<TRuleChain>;
  U    : TArray<TRuleChain>;
  Many : TArray<TRuleChain>;
  Offer: TArray<TRuleChain>;

  function Find(const AText: string): TArray<TRuleChain>;
  begin
    Result:= FindRuleChains(ChainMakeBook(Books, AText));
  end;

begin
  Books:= TObjectList<TRuleBook>.Create(True);
  try
    C:= Find(CHAIN_BOOK_CHAIN);
    Check('chains.text.mark.chain', (ChainMarkText(C[0], 0) = 'chain TA -> TB -> TC: stage 1 of 2 -- convert-apply is single pass, so a TA ends as TB, never TC (Conversion > Rule chains...)')
      and (ChainMarkText(C[0], 1) = 'chain TA -> TB -> TC: stage 2 of 2 -- convert-apply is single pass, so a TA ends as TB, never TC (Conversion > Rule chains...)'),
      ChainMarkText(C[0], 0));
    Check('chains.text.mark.cycle', ChainMarkText(Find(CHAIN_BOOK_CYCLE)[0], 0)
      = 'cycle TA -> TB -> TA: convert-apply is single pass, so the classes are swapped in one run -- remove one rule if that is not intended',
      ChainMarkText(Find(CHAIN_BOOK_CYCLE)[0], 0));
    D:= Find(CHAIN_BOOK_DUP);
    Check('chains.text.mark.dup', (ChainMarkText(D[0], 0) = 'duplicate From type TA: this rule wins; line 3 is never applied')
      and (ChainMarkText(D[0], 1) = 'duplicate From type TA: never applied -- line 1 wins; delete this block or merge its lines there'),
      ChainMarkText(D[0], 0));
    U:= Find(CHAIN_BOOK_UNIT_SWAP);
    Check('chains.text.mark.unit', (ChainMarkText(U[0], 0) = 'unit chain UnitA -> UnitB -> UnitC: UnitB is swapped again by line 2 (ADD wins: UnitB stays)')
      and (ChainMarkText(U[0], 1) = 'unit chain UnitA -> UnitB -> UnitC: ADD wins, so UnitB stays and UnitC is added -- rewrite line 1 as UnitA -> UnitC (Conversion > Rule chains...)'),
      ChainMarkText(U[0], 1));
    U:= Find(CHAIN_BOOK_UNIT_USE);
    Check('chains.text.mark.unit.use', ChainMarkText(U[0], 1)
      = 'unit chain UnitB -> UnitC: ADD wins, so UnitB stays and UnitC is added -- rewrite line 1 to add UnitC (Conversion > Rule chains...)',
      ChainMarkText(U[0], 1));
    Check('chains.text.row', (ChainRowText(C[0]) = 'chain TA -> TB -> TC (lines 1, 3)')
      and (ChainRowText(Find(CHAIN_BOOK_CYCLE)[0]) = 'cycle TA -> TB -> TA (lines 1, 2)')
      and (ChainRowText(D[0]) = 'duplicate From TA (line 1 wins; 3 never applied)')
      and (ChainRowText(Find(CHAIN_BOOK_UNIT_SWAP)[0]) = 'unit chain UnitA -> UnitB -> UnitC (lines 1, 2)'),
      ChainRowText(C[0]) + ' | ' + ChainRowText(D[0]));
    Many:= Find('#convert TA -> TB' + CHAIN_CRLF + '#convert TA -> TC' + CHAIN_CRLF + '#convert TD -> TE' + CHAIN_CRLF + '#convert TD -> TF');
    Check('chains.text.status', (ChainStatusText(Find(CHAIN_BOOK_INTO_CYCLE)) = 'Rule chains: 1 chain, 1 cycle -- see marked rules (Conversion > Rule chains...)')
      and (ChainStatusText(Find(CHAIN_BOOK_SHARED)) = 'Rule chains: 2 chains -- see marked rules (Conversion > Rule chains...)')
      and (ChainStatusText(Many) = 'Rule chains: 2 duplicate From types -- see marked rules (Conversion > Rule chains...)'),
      ChainStatusText(Many));
    Check('chains.text.can', CanMergeChain(C[0]) and CanMergeChain(U[0]) and not CanMergeChain(Find(CHAIN_BOOK_CYCLE)[0]) and not CanMergeChain(D[0])
      and CanSplitChain(C[0]) and not CanSplitChain(U[0]) and not CanSplitChain(Find(CHAIN_BOOK_CYCLE)[0]) and not CanSplitChain(D[0]), 'merge/split');
    C:= Find(CHAIN_BOOK_INTO_CYCLE);
    Offer:= ChainsToOffer(C, nil);
    Check('chains.text.offer.all', (Length(Offer) = 1) and (Offer[0].Kind = ckChain), IntToStr(Length(Offer)));
    Offer:= ChainsToOffer(C, ['CHAIN:TX>TA>TB']);
    Check('chains.text.offer.asked', Length(Offer) = 0, IntToStr(Length(Offer)) + ' ' + C[0].Key);
  finally
    Books.Free;
  end;
end;

procedure TestRuleChainsMarks;
var
  Books: TObjectList<TRuleBook>;
  Book : TRuleBook;
  C    : TArray<TRuleChain>;
  N    : Integer;
  Dup  : TRuleBook;
begin
  Books:= TObjectList<TRuleBook>.Create(True);
  try
    Book:= ChainMakeBook(Books, CHAIN_BOOK_CHAIN);
    C:= FindRuleChains(Book);
    N:= StaticChainMarks(Book);
    Check('chains.marks.added', (N = 2) and (Length(Book.Nodes[0].Marks) = 1) and (Length(Book.Nodes[2].Marks) = 1)
      and (Book.Nodes[0].Marks[0].Text = ChainMarkText(C[0], 0)) and (Book.Nodes[2].Marks[0].Text = ChainMarkText(C[0], 1))
      and Book.Nodes[0].Marks[0].IsWarning and not Book.Nodes[0].Marks[0].FromSyntax
      and (Length(Book.Nodes[1].Marks) = 0) and (Length(Book.Nodes[3].Marks) = 0), IntToStr(N));
    Check('chains.marks.idempotent', (StaticChainMarks(Book) = 0) and (Length(Book.Nodes[0].Marks) = 1) and (Length(Book.Nodes[2].Marks) = 1), 'second call');
    Book:= ChainMakeBook(Books, CHAIN_BOOK_CHAIN);
    AddStaticWarningMark(Book.Nodes[0], 'line 1: warning: a migrate warning');
    StaticChainMarks(Book);
    Check('chains.marks.after.migrate', (Length(Book.Nodes[0].Marks) = 2) and (Book.Nodes[0].Marks[0].Text = 'line 1: warning: a migrate warning'),
      IntToStr(Length(Book.Nodes[0].Marks)));
    // T6: a merge leaves the last stage block in the book; its old "chain ..." mark must not
    // survive the next StaticChainMarks (the chain is gone), and a non-chain mark stays.
    Book:= ChainMakeBook(Books, CHAIN_BOOK_CHAIN);
    StaticChainMarks(Book);
    AddStaticWarningMark(Book.Nodes[2], 'line 3: warning: an engine warning');
    C:= FindRuleChains(Book);
    ApplyChainMerge(Book, MergeChainPlan(Book, C[0]));
    StaticChainMarks(Book);
    N:= 0;
    for var LNode: TRuleNode in Book.Nodes do
      for var LMark: TRuleMark in LNode.Marks do
        if LMark.Text.StartsWith('chain ') then
          Inc(N);
    Check('chains.marks.merge.drops.stale', (Length(FindRuleChains(Book)) = 0) and (N = 0), IntToStr(N) + ' stale chain mark(s)');
    Check('chains.marks.merge.keeps.other', (Length(Book.Nodes[Book.Nodes.Count - 2].Marks) = 1)
      and (Book.Nodes[Book.Nodes.Count - 2].Marks[0].Text = 'line 3: warning: an engine warning'),
      IntToStr(Length(Book.Nodes[Book.Nodes.Count - 2].Marks)));
    // T6: "line N" in a mark moves when lines shift; the old text must be replaced, not kept beside the new one.
    Book:= ChainMakeBook(Books, CHAIN_BOOK_DUP);
    AddStaticWarningMark(Book.Nodes[2], 'duplicate From type TA: never applied -- line 9 wins; delete this block or merge its lines there');
    StaticChainMarks(Book);
    Check('chains.marks.replaces.shifted', (Length(Book.Nodes[2].Marks) = 1) and (Pos('line 1 wins', Book.Nodes[2].Marks[0].Text) > 0),
      IntToStr(Length(Book.Nodes[2].Marks)));
    Dup:= ChainMakeBook(Books, CHAIN_BOOK_FROMONLY);
    Check('chains.marks.hoist', AddStaticWarningMark(Dup.Nodes[0], 'w') and not AddStaticWarningMark(Dup.Nodes[0], 'w') and (Length(Dup.Nodes[0].Marks) = 1),
      IntToStr(Length(Dup.Nodes[0].Marks)));
  finally
    Books.Free;
  end;
end;

// ---- Task 2 (merge) block: TestRuleChainsMerge, filled by CHAIN-1 Task 2 ----
procedure TestRuleChainsMerge;
var
  Books: TObjectList<TRuleBook>;

  function J(const ALines: array of string): string;
  begin
    Result:= string.Join(CHAIN_CRLF, ALines);
  end;

  function Plan(const AText: string; AChainNo: Integer; out ABook: TRuleBook): TChainMerge;
  var
    LC: TArray<TRuleChain>;
  begin
    ABook:= ChainMakeBook(Books, AText);
    LC:= FindRuleChains(ABook);
    Result:= MergeChainPlan(ABook, LC[AChainNo]);
  end;

  function Has(const AM: TChainMerge; const ALine: string): Boolean;
  var
    LS: string;
  begin
    Result:= False;
    for LS in AM.NewLines do
      if LS = ALine then
        Exit(True);
  end;

  function PosOf(const AM: TChainMerge; const ALine: string): Integer;
  var
    LI: Integer;
  begin
    Result:= -1;
    for LI:= 0 to High(AM.NewLines) do
      if AM.NewLines[LI] = ALine then
        Exit(LI);
  end;

  function StartsAt(const AM: TChainMerge; const APrefix: string): Integer;
  var
    LI: Integer;
  begin
    Result:= -1;
    for LI:= 0 to High(AM.NewLines) do
      if AM.NewLines[LI].StartsWith(APrefix) then
        Exit(LI);
  end;

var
  Bk    : TRuleBook;
  M     : TChainMerge;
  MERGE_A: string;
  LI    : Integer;
  LText : string;
  LBefore: string;
begin
  Books:= TObjectList<TRuleBook>.Create(True);
  try
    MERGE_A:= J(['#convert TA -> TB, UnitB', '#link Caption <- Text', '#link Width <- W : IntToStr', '#link Color <- Col : ToColor',
      '#link Keep <- K', '#default Flag = True', '#default Gone = 1', '#ignore Old', '#migrate DoA -> DoB', '#tag t1', '',
      '#convert TB -> TC, UnitC', '#link Title <- Caption', '#link Width <- Width : StrToInt', '#link Colour <- Color',
      '#ignore Keep', '#ignore Gone', '#default Extra = 2', '#migrate DoB -> DoC, UnitC', '#warn Title "check"', '#tag t2',
      '#migrate X -> Y']);
    M:= Plan(MERGE_A, 0, Bk);
    Check('chains.merge.problem.none', M.Problem = '', M.Problem);
    Check('chains.merge.header', (Length(M.NewLines) > 1) and (M.NewLines[0] = '#convert TA -> TC, UnitC')
      and M.NewLines[1].StartsWith('#note chain merge: TA -> TB (line 1) + TB -> TC (line 12) = TA -> TC;'),
      IfThen(Length(M.NewLines) > 1, M.NewLines[0] + ' | ' + M.NewLines[1], 'short'));
    Check('chains.merge.link.plain', Has(M, '#link Title <- Text'), '');
    Check('chains.merge.link.one.cast', Has(M, '#link Colour <- Col : ToColor'), '');
    LI:= PosOf(M, '#link Width <- W');
    Check('chains.merge.link.two.casts', (LI > 0) and (M.NewLines[LI - 1] = '#note chain merge: casts IntToStr then StrToInt on W cannot be composed -- pick one'),
      IntToStr(LI));
    Check('chains.merge.link.ignored', (not Has(M, '#link Keep <- K')) and Has(M, '#ignore K'), '');
    Check('chains.merge.default.ignored', (not Has(M, '#default Gone = 1')) and (StartsAt(M, '#note') >= 0)
      and (PosOf(M, '#default Gone = 1') < 0) and (Pos('Gone', string.Join('|', M.NewLines)) > 0), '');
    Check('chains.merge.default.carried', Has(M, '#default Flag = True'), '');
    Check('chains.merge.default.q', Has(M, '#default Extra = 2'), '');
    Check('chains.merge.ignore.p', Has(M, '#ignore Old'), '');
    Check('chains.merge.migrate.composed', Has(M, '#migrate DoA -> DoC, UnitC') and (not Has(M, '#migrate DoB -> DoC, UnitC'))
      and Has(M, '#migrate X -> Y'), '');
    LI:= StartsAt(M, '#note chain merge: the lines below came from TB -> TC (line 12)');
    Check('chains.merge.q.rest', (LI >= 0) and (PosOf(M, '#warn Title "check"') > LI) and (not Has(M, '#tag t2')) and Has(M, '#tag t1'),
      IntToStr(LI));
    Check('chains.merge.counts', (M.Composed = 5) and (M.Carried = 2) and (M.Noted = 3),
      Format('%d/%d/%d', [M.Composed, M.Carried, M.Noted]));
    Check('chains.merge.range.non.last', (M.NodeIdx = 0) and (M.LastIdx = 10) and (M.NewLines[High(M.NewLines)] = ''),
      Format('%d..%d', [M.NodeIdx, M.LastIdx]));

    M:= Plan(J(['#convert TB -> TC', '#link a <- b', '#convert TA -> TB', '#link b <- c', '#migrate M -> N']), 0, Bk);
    Check('chains.merge.range.last.trailer', (M.Problem = '') and (M.NodeIdx = 2) and (M.LastIdx = 3), Format('%d..%d %s', [M.NodeIdx, M.LastIdx, M.Problem]));

    M:= Plan(MERGE_A, 0, Bk);
    LBefore:= Bk.SaveToString;
    LI:= ApplyChainMerge(Bk, M);
    Check('chains.merge.apply', (LI = 0) and (Bk.Nodes[0].Kind = rnkConvert) and (Bk.Nodes[0].FromType = 'TA')
      and (Bk.Nodes[0].ToType = 'TC') and (Bk.Nodes[0].Units = 'UnitC') and (Length(FindRuleChains(Bk)) = 0), IntToStr(LI));
    LText:= Bk.SaveToString;
    Check('chains.merge.apply.second.stage', LText.Contains('#convert TB -> TC, UnitC' + CHAIN_CRLF + '#link Title <- Caption' + CHAIN_CRLF + '#link Width <- Width : StrToInt'),
      '');
    Check('chains.merge.apply.roundtrip', LText = J(M.NewLines) + CHAIN_CRLF + Copy(LBefore, LBefore.IndexOf('#convert TB -> TC') + 1, MaxInt),
      '');

    M:= Plan(J(['#convert TA -> TB', '#link b <- a', '#convert TB -> TC', '#link c <- b', '#convert TC -> TD', '#link d <- c']), 0, Bk);
    Check('chains.merge.three.stages', (M.Problem = '') and (M.NewLines[0] = '#convert TA -> TD') and Has(M, '#link d <- a'), M.Problem);

    M:= Plan(CHAIN_BOOK_UNIT_SWAP, 0, Bk);
    Check('chains.merge.unit.swap', (Length(M.NewLines) = 1) and (M.NewLines[0] = '#useswap UnitA -> UnitC') and (M.NodeIdx = 0) and (M.LastIdx = 0),
      M.Problem);
    M:= Plan(CHAIN_BOOK_UNIT_HDR, 0, Bk);
    Check('chains.merge.unit.hdr', (Length(M.NewLines) = 1) and (M.NewLines[0] = '#convert TA -> TB, UnitC'), M.Problem);
    M:= Plan(CHAIN_BOOK_UNIT_USE, 0, Bk);
    Check('chains.merge.unit.use', (Length(M.NewLines) = 1) and (M.NewLines[0] = '#use UnitC'), M.Problem);

    M:= Plan(CHAIN_BOOK_CHAIN, 0, Bk);
    Bk.Nodes.Delete(2);
    LBefore:= Bk.SaveToString;
    M:= MergeChainPlan(Bk, FindRuleChains(ChainMakeBook(Books, CHAIN_BOOK_CHAIN))[0]);
    Check('chains.merge.refused', (M.Problem <> '') and (ApplyChainMerge(Bk, M) = -1) and (Bk.SaveToString = LBefore), M.Problem);
    M:= Plan(CHAIN_BOOK_CYCLE, 0, Bk);
    Check('chains.merge.refused.kind.cycle', M.Problem = 'only a chain or a unit chain can be merged', M.Problem);
    M:= Plan(CHAIN_BOOK_DUP, 0, Bk);
    Check('chains.merge.refused.kind.dup', M.Problem = 'only a chain or a unit chain can be merged', M.Problem);
  finally
    Books.Free;
  end;
end;

// ---- Task 3 (split) block: TestRuleChainsSplit, filled by CHAIN-1 Task 3 ----
procedure TestRuleChainsSplit;
const
  THREE = '#convert TA -> TB' + CHAIN_CRLF + '#link x <- y' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#link z <- x'
    + CHAIN_CRLF + '#convert TC -> TD' + CHAIN_CRLF + '#link w <- z';
  MAPPED = '#mapping M from E.TEnum to TC' + CHAIN_CRLF + '#convert TA -> TB' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#apply M';
var
  Books: TObjectList<TRuleBook>;
  Book : TRuleBook;
  P    : TChainSplit;

  function Plan(const AText: string): TChainSplit;
  begin
    Book:= ChainMakeBook(Books, AText);
    Result:= SplitChainPlan(Book, FindRuleChains(Book));
  end;

  // '[0,1];[2]' -- Stages as text.
  function StagesText(const ASplit: TChainSplit): string;
  var
    LI, LJ: Integer;
  begin
    Result:= '';
    for LI:= 0 to High(ASplit.Stages) do
    begin
      Result:= Result + IfThen(LI > 0, ';', '') + '[';
      for LJ:= 0 to High(ASplit.Stages[LI]) do
        Result:= Result + IfThen(LJ > 0, ',', '') + IntToStr(ASplit.Stages[LI][LJ]);
      Result:= Result + ']';
    end;
  end;

begin
  Books:= TObjectList<TRuleBook>.Create(True);
  try
    Check('chains.split.path', (StageBookPath('C:\x\Book.rules', 2) = 'C:\x\Book.stage2.rules')
      and EndsText('.stage3.rules', StageBookPath('C:\x\Book.rules', 3)), StageBookPath('C:\x\Book.rules', 2));
    P:= Plan(CHAIN_BOOK_CHAIN);
    Check('chains.split.stages.two', StagesText(P) = '[0];[2]', StagesText(P));
    P:= Plan(THREE);
    Check('chains.split.stages.three', StagesText(P) = '[0];[2];[4]', StagesText(P));
    P:= Plan(CHAIN_BOOK_SHARED);
    Check('chains.split.stages.shared', StagesText(P) = '[0,1];[2]', StagesText(P));
    P:= Plan(CHAIN_BOOK_INTO_CYCLE);
    Check('chains.split.cycle.stays', (Length(P.Stages) = 1) and (StagesText(P) = '[0,1,2]'), StagesText(P));
    P:= Plan(CHAIN_BOOK_DUP);
    Check('chains.split.dup.stays', StagesText(P) = '[0,2]', StagesText(P));
    P:= Plan(MAPPED);
    Check('chains.split.mappings', (StagesText(P) = '[1];[2]') and (Length(P.Mappings[0]) = 0) and (Length(P.Mappings[1]) = 1)
      and (P.Mappings[1][0] = 'M'), StagesText(P));

    Book:= ChainMakeBook(Books, '#depth 3' + CHAIN_CRLF + CHAIN_BOOK_CHAIN);
    Check('chains.split.text.depth', StartsText('#depth 3' + CHAIN_CRLF, StageBookText(Book, [3], nil)), StageBookText(Book, [3], nil));
    Book:= ChainMakeBook(Books, CHAIN_BOOK_CHAIN);
    Check('chains.split.text.blocks', StageBookText(Book, [2], nil) = '#convert TB -> TC' + CHAIN_CRLF + '#link z <- x' + CHAIN_CRLF,
      StageBookText(Book, [2], nil));
    Book:= ChainMakeBook(Books, '#depth 2' + CHAIN_CRLF + MAPPED);
    Check('chains.split.text.mappings',
      StageBookText(Book, [3], ['M']) = '#depth 2' + CHAIN_CRLF + '#mapping M from E.TEnum to TC' + CHAIN_CRLF
        + '#convert TB -> TC' + CHAIN_CRLF + '#apply M' + CHAIN_CRLF, StageBookText(Book, [3], ['M']));
    Book:= ChainMakeBook(Books, CHAIN_BOOK_CHAIN);
    Check('chains.split.remaining', RemainingBookText(Book, [2]) = '#convert TA -> TB' + CHAIN_CRLF + '#link x <- y' + CHAIN_CRLF,
      RemainingBookText(Book, [2]));
    Book:= ChainMakeBook(Books, CHAIN_BOOK_CHAIN + CHAIN_CRLF + '#migrate M -> N');
    Check('chains.split.remaining.trailer', EndsText('#migrate M -> N', Trim(RemainingBookText(Book, [2]))) and (Pos('TB -> TC', RemainingBookText(Book, [2])) = 0),
      RemainingBookText(Book, [2]));
    Book:= ChainMakeBook(Books, CHAIN_BOOK_CHAIN);
    Check('chains.split.roundtrip', TrimRight(RemainingBookText(Book, [2]) + StageBookText(Book, [2], nil)) = TrimRight(Book.SaveToString),
      RemainingBookText(Book, [2]) + StageBookText(Book, [2], nil));
    Check('chains.split.status', SplitStatusText('C:\x\Book.rules', ['C:\x\Book.stage2.rules'], 2, nil)
      = 'Split 2 block(s) into Book.stage2.rules -- convert with Book.rules first, then Book.stage2.rules (check both on the Convert tab, in that order)',
      SplitStatusText('C:\x\Book.rules', ['C:\x\Book.stage2.rules'], 2, nil));
    Check('chains.split.status.mappings', EndsText('; copied #mapping M1, M2 into the stage book',
      SplitStatusText('C:\x\Book.rules', ['C:\x\Book.stage2.rules'], 1, ['M1', 'M2'])), 'mapping tail');
  finally
    Books.Free;
  end;
end;

{ Task 4: the dialog's button gates, the session's asked set, the Merge status and
  the stage-book append text (pure decisions behind ConvRules.ChainForm / MainForm). }
procedure TestRuleChainsUi;
var
  Books : TObjectList<TRuleBook>;
  LChain: TArray<TRuleChain>;
  LCycle: TArray<TRuleChain>;
  LUnit : TArray<TRuleChain>;
  LDup  : TArray<TRuleChain>;
  LKeys : TArray<string>;
begin
  Books:= TObjectList<TRuleBook>.Create(True);
  try
    LChain:= FindRuleChains(ChainMakeBook(Books, CHAIN_BOOK_CHAIN));
    LCycle:= FindRuleChains(ChainMakeBook(Books, CHAIN_BOOK_CYCLE));
    LUnit := FindRuleChains(ChainMakeBook(Books, CHAIN_BOOK_UNIT_SWAP));
    LDup  := FindRuleChains(ChainMakeBook(Books, CHAIN_BOOK_DUP));
    Check('chains.ui.merge.enabled', CanMergeAll(LChain) and CanMergeAll(LUnit) and CanMergeAll(LChain + LUnit), 'chain / unit chain');
    Check('chains.ui.merge.disabled', (not CanMergeAll(nil)) and (not CanMergeAll(LChain + LCycle)) and (not CanMergeAll(LDup)), 'none / cycle / dup');
    Check('chains.ui.split.enabled', CanSplitAll(LChain), 'chain');
    Check('chains.ui.split.disabled', (not CanSplitAll(nil)) and (not CanSplitAll(LUnit)) and (not CanSplitAll(LChain + LCycle)), 'none / unit / cycle');
    LKeys:= ChainKeysAsked(nil, LChain + LCycle);
    Check('chains.ui.asked.add', (Length(LKeys) = 2) and (LKeys[0] = LChain[0].Key) and (LKeys[1] = LCycle[0].Key), string.Join('|', LKeys));
    LKeys:= ChainKeysAsked([UpperCase(LChain[0].Key)], LChain + LUnit);
    Check('chains.ui.asked.dedup', (Length(LKeys) = 2) and (LKeys[1] = LUnit[0].Key), string.Join('|', LKeys));
    Check('chains.ui.asked.offer', Length(ChainsToOffer(LChain + LUnit, ChainKeysAsked(nil, LChain + LUnit))) = 0, 'asked once');
    Check('chains.ui.merge.status', MergeStatusText(['TA -> TB -> TC'], nil) = 'Merged 1 chain(s): TA -> TB -> TC -- review the composed block, then Save',
      MergeStatusText(['TA -> TB -> TC'], nil));
    Check('chains.ui.merge.status.problems', MergeStatusText(['TA -> TB -> TC', 'TX -> TY -> TZ'], ['p1'])
      = 'Merged 2 chain(s): TA -> TB -> TC, TX -> TY -> TZ -- review the composed block, then Save; not merged: p1',
      MergeStatusText(['TA -> TB -> TC', 'TX -> TY -> TZ'], ['p1']));
    Check('chains.ui.merge.status.none', MergeStatusText(nil, ['p1', 'p2']) = 'Nothing merged: p1; p2', MergeStatusText(nil, ['p1', 'p2']));
    Check('chains.ui.append', StageAppendText('#depth 2' + CHAIN_CRLF + '#convert TX -> TY' + CHAIN_CRLF + '#link a <- b',
        '#depth 2' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#link z <- x' + CHAIN_CRLF)
      = '#depth 2' + CHAIN_CRLF + '#convert TX -> TY' + CHAIN_CRLF + '#link a <- b' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#link z <- x' + CHAIN_CRLF,
      StageAppendText('#depth 2' + CHAIN_CRLF + '#convert TX -> TY' + CHAIN_CRLF + '#link a <- b',
        '#depth 2' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#link z <- x' + CHAIN_CRLF));
    Check('chains.ui.append.mapping', StageAppendText('#convert TX -> TY' + CHAIN_CRLF,
        '#depth 2' + CHAIN_CRLF + '#mapping M from E.TEnum to TC' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#apply M' + CHAIN_CRLF)
      = '#convert TX -> TY' + CHAIN_CRLF + '#mapping M from E.TEnum to TC' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#apply M' + CHAIN_CRLF,
      StageAppendText('#convert TX -> TY' + CHAIN_CRLF,
        '#depth 2' + CHAIN_CRLF + '#mapping M from E.TEnum to TC' + CHAIN_CRLF + '#convert TB -> TC' + CHAIN_CRLF + '#apply M' + CHAIN_CRLF));
  finally
    Books.Free;
  end;
end;