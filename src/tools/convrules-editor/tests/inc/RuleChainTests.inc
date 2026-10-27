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
    Dup:= ChainMakeBook(Books, CHAIN_BOOK_FROMONLY);
    Check('chains.marks.hoist', AddStaticWarningMark(Dup.Nodes[0], 'w') and not AddStaticWarningMark(Dup.Nodes[0], 'w') and (Length(Dup.Nodes[0].Marks) = 1),
      IntToStr(Length(Dup.Nodes[0].Marks)));
  finally
    Books.Free;
  end;
end;

// ---- Task 2 (merge) block: TestRuleChainsMerge, filled by CHAIN-1 Task 2 ----
procedure TestRuleChainsMerge;
begin
end;

// ---- Task 3 (split) block: TestRuleChainsSplit, filled by CHAIN-1 Task 3 ----
procedure TestRuleChainsSplit;
begin
end;
