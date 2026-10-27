{ CHAIN-1 rule chains: pure decisions (detection, texts, keys, marks).
  Spec docs\superpowers\specs\2026-10-27-converter-chain1-design.md sections 4 and 5. }
unit ConvRules.RuleChains;

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , ConvRules.Model
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
function ChainRowText(const AChain: TRuleChain): string;  // dl:ok unused-public-symbol@0da8 -- REVIEWED 2026-10-27 consumer is ConvRules.MainForm / ChainForm in CHAIN-1 Task 4; the model tests already call it
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
function ChainStatusText(const AChains: TArray<TRuleChain>): string;  // dl:ok unused-public-symbol@1f26 -- REVIEWED 2026-10-27 consumer is ConvRules.MainForm / ChainForm in CHAIN-1 Task 4; the model tests already call it
/// <summary>The findings to offer now: those with CanMerge or CanSplit whose Key is not in AAsked (case-insensitive).</summary>
/// <param name="AChains">The findings.</param>
/// <param name="AAsked">Keys already offered this session.</param>
/// <returns>The findings still to offer.</returns>
function ChainsToOffer(const AChains: TArray<TRuleChain>; const AAsked: TArray<string>): TArray<TRuleChain>;  // dl:ok unused-public-symbol@2f32 -- REVIEWED 2026-10-27 consumer is ConvRules.MainForm / ChainForm in CHAIN-1 Task 4; the model tests already call it
/// <summary>Adds the warning mark of every finding to every node it involves (spec 5.2 M1); returns the number added; never adds a mark twice.</summary>
/// <param name="ABook">The book whose nodes get the session marks; not owned.</param>
/// <returns>The number of marks added.</returns>
function StaticChainMarks(ABook: TRuleBook): Integer;  // dl:ok unused-public-symbol@30de -- REVIEWED 2026-10-27 consumer is ConvRules.MainForm / ChainForm in CHAIN-1 Task 4; the model tests already call it

// ---- Task 2 (merge composition) goes here: TChainMerge, MergeChainPlan, ApplyChainMerge ----

// ---- Task 3 (split planning, stage-book text) goes here: TChainSplit, SplitChainPlan, StageBookPath ... ----

implementation

uses
  System.StrUtils
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

function StaticChainMarks(ABook: TRuleBook): Integer;
var
  LChain: TRuleChain;
  LI    : Integer;
begin
  Result:= 0;
  for LChain in FindRuleChains(ABook) do
    for LI:= 0 to High(LChain.Stages) do
      if AddStaticWarningMark(ABook.Nodes[LChain.Stages[LI].NodeIdx], ChainMarkText(LChain, LI)) then
        Inc(Result);
end;

end.
