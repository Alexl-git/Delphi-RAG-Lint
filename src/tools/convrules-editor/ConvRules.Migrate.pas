unit ConvRules.Migrate;

{ A4 #migrate slice 1 -- the PURE decisions behind the editor's member migration: which
  block of the open book a Work list row's pair names, what one Migrate pick writes into
  it, the pre-check the editor shows before any run, the run's migrate note / report
  notes, and the marks put on the book's '#migrate' lines. The dialog
  (ConvRules.MigrateForm) and the host (ConvRules.MainForm) only display and collect.
  Spec: docs\superpowers\specs\2026-10-23-converter-migrate-slice1-design.md sections 5-9,
  owner rulings section 12a (D0 = B: built on engine 1.35.0-alpha, which fills from_type /
  to_type and sends pas_uses[].migrate_to, and no longer reports DL_NONE as an unresolved
  uses name -- so no editor workaround for G4 / G8 / G9 is here). }

interface

uses
  ConvRules.Model
  , ConvRules.WorkList
  , ConvRules.ConvertRun
  ;

const
  /// <summary>Run report Status column of a migrate-applied item.</summary>
  REPORT_STATUS_MIGRATE       = 'migrate';
  /// <summary>Run report Status column of a deliberate-break item.</summary>
  REPORT_STATUS_BREAK         = 'deliberate break';
  /// <summary>Run report Status column of a migrate-check item.</summary>
  REPORT_STATUS_MIGRATE_CHECK = 'migrate check';
  /// <summary>Pre-check text for a pick that lands before the first #convert (editor text;
  /// the engine stays silent there, contract G2c).</summary>
  MIGRATE_GLOBAL_TEXT = 'a #migrate before the first #convert is not a member migration (globals: slice 3)';

type
  /// <summary>What the Migrate dialog returns: one member and its replacement.</summary>
  TMigratePick = record
    /// <summary>The member being replaced.</summary>
    Old  : string;
    /// <summary>The rename target; ignored when Break (DL_NONE is written).</summary>
    New  : string;
    /// <summary>True = write DL_NONE, a deliberate break.</summary>
    Break: Boolean;
  end;

  /// <summary>How the open book answers a row's From -&gt; To pair.</summary>
  TMigrateBlockState = (mbFound, mbNone, mbAmbiguous);

  /// <summary>The #convert block a pick goes into.</summary>
  TMigrateBlock = record
    /// <summary>Found, none, or two headers for the pair.</summary>
    State    : TMigrateBlockState;
    /// <summary>The header's index in the book when mbFound; -1 otherwise.</summary>
    NodeIndex: Integer;
    /// <summary>The header node (borrowed) when mbFound; keep it, not the index, across an insert.</summary>
    Header   : TRuleNode;
    /// <summary>The header line as the book spells it when mbFound; '' otherwise.</summary>
    HeaderText: string;
    /// <summary>'' when found; else why nothing can be written.</summary>
    Reason   : string;
  end;

  /// <summary>What ApplyMigratePick did to the book.</summary>
  TMigrateOutcome = record
    /// <summary>True when a line was written or changed.</summary>
    Applied : Boolean;
    /// <summary>True when an existing member-form line for Old was changed in place.</summary>
    Replaced: Boolean;
    /// <summary>The written node (borrowed); nil when not applied.</summary>
    Node    : TRuleNode;
    /// <summary>1-based book line of Node after the edit; 0 when not applied.</summary>
    Line    : Integer;
    /// <summary>The replaced line before the edit; '' on an append.</summary>
    Before  : string;
    /// <summary>The line as written.</summary>
    After   : string;
    /// <summary>MigrateCheck's sentence for the pick; '' when clean. Never stops the write.</summary>
    Warning : string;
    /// <summary>Why nothing was written; '' when applied.</summary>
    Reason  : string;
  end;

/// <summary>Finds the #convert header of ABook whose From and To match AFrom / ATo by bare
/// type name (a qualified 'Vcl.X.TSrcBtn' header matches the row's 'TSrcBtn').</summary>
/// <param name="ABook">The open book; not owned.</param>
/// <param name="AFrom">The row's from_type.</param>
/// <param name="ATo">The row's to_type.</param>
/// <param name="ABookName">The book's file name, for the Reason text.</param>
/// <returns>mbFound with the header; mbNone 'no #convert F -> T block in B -- open the right
/// book'; mbAmbiguous 'two #convert F -> T blocks in B (lines 1, 3) -- fix the book by hand'.</returns>
function FindMigrateBlock(ABook: TRuleBook; const AFrom, ATo, ABookName: string): TMigrateBlock;

/// <summary>The editor's pre-check of a pick, the FIRST hit of: the engine's refusal of the
/// would-be line; a renaming or casting plain #link of the block (or before the first
/// header) already converting Old ('book line K already converts Old', the engine's
/// text); identity ('#migrate Old -> New renames nothing'); a header index below 0
/// (MIGRATE_GLOBAL_TEXT).</summary>
/// <param name="ABook">The book; not owned.</param>
/// <param name="AHeaderIdx">The target header's index; -1 = before the first header.</param>
/// <param name="APick">The pick.</param>
/// <returns>'' when clean. A warning only: the engine is the judge.</returns>
function MigrateCheck(ABook: TRuleBook; AHeaderIdx: Integer; const APick: TMigratePick): string;

/// <summary>Writes APick into the block: replaces the New of the block's member-form line
/// for Old (case-insensitive) or appends a new line at the block's end; never a second
/// member-form line for the same Old.</summary>
/// <param name="ABook">The book; owns any new node. The edit is Dirty and unsaved.</param>
/// <param name="ABlock">From FindMigrateBlock; not mbFound = nothing written.</param>
/// <param name="APick">The pick; a pick the engine would refuse is not written.</param>
/// <returns>See TMigrateOutcome.</returns>
function ApplyMigratePick(ABook: TRuleBook; const ABlock: TMigrateBlock; const APick: TMigratePick): TMigrateOutcome;

/// <summary>The status bar sentence after a pick.</summary>
/// <param name="ABookPath">The book's path; only its file name is shown.</param>
/// <param name="ABlock">The block the pick went to.</param>
/// <param name="AOutcome">ApplyMigratePick's answer.</param>
/// <returns>'Wrote L into H (line N of B) -- not saved: File > Save, then Convert again',
/// 'Changed L (line N of B) -- not saved: ...', either + '; check: W' when warned, or
/// 'Nothing written to B: R'.</returns>
function MigrateStatusText(const ABookPath: string; const ABlock: TMigrateBlock; const AOutcome: TMigrateOutcome): string;

/// <summary>The Members list cells of one '#migrate' line: Old (with any scope) | New |
/// 'rename' / 'DL_NONE' / 'legacy' | Note (the engine's refusal, then the node's marks).</summary>
/// <param name="ANode">A rnkMigrate node.</param>
/// <returns>Four cells.</returns>
function MembersRowText(ANode: TRuleNode): TArray<string>;

/// <summary>The node a post-run rule-level migrate-check names: the line ARuleLine when it
/// still is '#migrate AOld -> ANew', else the ONE '#migrate' line with that Old and New.</summary>
/// <param name="ABook">The open book; not owned.</param>
/// <param name="ARuleLine">The item's rule_line (1-based, as the run saw the book).</param>
/// <param name="AOld">The item's path.</param>
/// <param name="ANew">The item's value.</param>
/// <returns>The node index, or -1 (gone, or ambiguous).</returns>
function FindMigrateTarget(ABook: TRuleBook; ARuleLine: Integer; const AOld, ANew: string): Integer;

/// <summary>Adds a warning mark (FromSyntax False) to every member-form '#migrate' line the
/// pre-check speaks for: a #link already converting Old, an earlier member-form line of
/// the block for the same Old, identity, or a line before the first header.</summary>
/// <param name="ABook">The book; marks are session state, never written to the file.</param>
/// <returns>The number of marks added; a mark already on the node is not added twice.</returns>
/// <remarks>A legacy line gets none here: engine 1.35.0's convert-validate reports its
/// refusal itself (measured 2026-10-26), and the Save path marks that.</remarks>
function StaticMigrateMarks(ABook: TRuleBook): Integer;

/// <summary>Puts each rule-level (line 0) migrate-check item's text as a warning mark on the
/// open book's line it names (owner ruling D8 = B).</summary>
/// <param name="ABook">The open book; must be the book the run used.</param>
/// <param name="AChecks">TApplyRow.MigrateChecks of the run's rows for that book.</param>
/// <returns>The number of marks added; per-site items and repeats add none.</returns>
function AddMigrateCheckMarks(ABook: TRuleBook; const AChecks: TArray<TApplyItem>): Integer;

/// <summary>The rule tree marker suffix of a block: '; N migrate' (N member-form lines).</summary>
/// <param name="ABook">The book; not owned.</param>
/// <param name="AHeaderIdx">The header's index.</param>
/// <returns>'' when N = 0.</returns>
function MigrateMarkerText(ABook: TRuleBook; AHeaderIdx: Integer): string;

/// <summary>The Work list Rule cell: the open book's member-form line for the row's pair
/// and member, '#migrate Old -> New (line N, unsaved)' or '(line N, saved)'.</summary>
/// <param name="ABook">The open book, or nil.</param>
/// <param name="ARow">The pas_uses row.</param>
/// <returns>'' when no book, no block for the pair, or no line for the member.</returns>
function RuleForRow(ABook: TRuleBook; const ARow: TPasUseRow): string;

/// <summary>The converted row's note part: '; migrate: A renamed, B deliberate break(s),
/// C to check', zero parts dropped.</summary>
/// <param name="ARow">The unit's apply/1 row.</param>
/// <returns>'' when all three are 0 (also on an engine without migrate_members).</returns>
function MigrateNote(const ARow: TApplyRow): string;

/// <summary>The run report's Note column of one migrate item.</summary>
/// <param name="AItem">A migrate-applied, deliberate-break or migrate-check item.</param>
/// <returns>'F:L inst.old -> new (#migrate line R)'; 'F:L DL_NONE(old) (#migrate line R)';
/// the engine's text for a check.</returns>
function MigrateReportNote(const AItem: TApplyItem): string;

/// <summary>The Preflight note for a book on an engine without migrate_members.</summary>
/// <param name="ABookName">The book's file name.</param>
/// <param name="ABookText">The book's text.</param>
/// <returns>'B: N member #migrate line(s) -- this engine does not apply them (needs
/// migrate_members)', counting member-form lines after the first header; '' when 0.</returns>
function MigrateBookNote(const ABookName, ABookText: string): string;

implementation

uses
  System.SysUtils
  , ConvRules.MigrateRules
  ;

const
  BLOCK_NONE_FMT      = 'no #convert %s -> %s block in %s -- open the right book';
  BLOCK_AMBIGUOUS_FMT = 'two #convert %s -> %s blocks in %s (lines %s) -- fix the book by hand';
  COVERED_FMT         = 'book line %d already converts %s';
  IDENTITY_FMT        = '#migrate %s -> %s renames nothing';
  NOT_SAVED           = ' -- not saved: File > Save, then Convert again';
  WROTE_FMT           = 'Wrote %s into %s (line %d of %s)';
  CHANGED_FMT         = 'Changed %s (line %d of %s)';
  CHECK_FMT           = '; check: %s';
  NOTHING_FMT         = 'Nothing written to %s: %s';
  KIND_RENAME         = 'rename';
  KIND_LEGACY         = 'legacy';
  NOTE_SEPARATOR      = '; ';
  MARKER_FMT          = '; %d migrate';
  RULE_FMT            = '%s (line %d, %s)';
  RULE_UNSAVED        = 'unsaved';
  RULE_SAVED          = 'saved';
  NOTE_PREFIX         = '; migrate: ';
  NOTE_RENAMED_FMT    = '%d renamed';
  NOTE_BREAKS_FMT     = '%d deliberate break(s)';
  NOTE_CHECKS_FMT     = '%d to check';
  REPORT_APPLIED_FMT  = '%s:%d %s.%s -> %s (#migrate line %d)';
  REPORT_BREAK_FMT    = '%s:%d DL_NONE(%s) (#migrate line %d)';
  BOOK_NOTE_FMT       = '%s: %d member #migrate line(s) -- this engine does not apply them (needs migrate_members)';

// The type name after its last dot ('Vcl.X.TSrcBtn' -> 'TSrcBtn').
function BareName(const AType: string): string;
begin
  Result:= Copy(AType, LastDelimiter('.', AType) + 1, MaxInt);
end;

// The New a pick writes: DL_NONE for a break, else the typed name.
function PickNew(const APick: TMigratePick): string;
begin
  Result:= if APick.Break then MIGRATE_DL_NONE else Trim(APick.New);
end;

function FindMigrateBlock(ABook: TRuleBook; const AFrom, ATo, ABookName: string): TMigrateBlock;
var
  LHits: TArray<Integer>;
  LLines: TArray<string>;
begin
  Result:= Default(TMigrateBlock);
  Result.NodeIndex:= -1;
  LHits:= nil;
  for var LIdx: Integer in ABook.ConvertHeaders do
    if SameText(BareName(ABook.Nodes[LIdx].FromType), BareName(AFrom)) and SameText(BareName(ABook.Nodes[LIdx].ToType), BareName(ATo)) then
      LHits:= LHits + [LIdx];
  if Length(LHits) = 0 then
  begin
    Result.State := mbNone;
    Result.Reason:= Format(BLOCK_NONE_FMT, [AFrom, ATo, ABookName]);
  end
  else if Length(LHits) = 1 then
  begin
    Result.State     := mbFound;
    Result.NodeIndex := LHits[0];
    Result.Header    := ABook.Nodes[LHits[0]];
    Result.HeaderText:= Result.Header.Emit;
  end
  else
  begin
    LLines:= nil;
    for var LIdx: Integer in LHits do
      LLines:= LLines + [IntToStr(LIdx + 1)];
    Result.State := mbAmbiguous;
    Result.Reason:= Format(BLOCK_AMBIGUOUS_FMT, [AFrom, ATo, ABookName, string.Join(', ', LLines)]);
  end;
end;

// True when the plain #link ANode already converts AOld: a cast, or a rename to a plain name.
function LinkConverts(ANode: TRuleNode; const AOld: string): Boolean;
begin
  Result:= (ANode.Kind = rnkLink) and SameText(ANode.LinkFrom, AOld)
    and ((ANode.Cast <> '') or (not SameText(ANode.LinkTo, AOld) and (Pos('.', ANode.LinkTo) = 0)));
end;

// The #link of the block AHeaderIdx, or before the first header, that converts AOld: its index, or -1.
function CoveringLink(ABook: TRuleBook; AHeaderIdx: Integer; const AOld: string): Integer;
begin
  for var I: Integer:= 0 to ABook.Nodes.Count - 1 do
  begin
    if ABook.Nodes[I].Kind = rnkConvert then
      Break;
    if LinkConverts(ABook.Nodes[I], AOld) then
      Exit(I);
  end;
  if AHeaderIdx >= 0 then
    for var LNode: TRuleNode in ABook.NodesInBlock(AHeaderIdx) do
      if LinkConverts(LNode, AOld) then
        Exit(ABook.Nodes.IndexOf(LNode));
  Result:= -1;
end;

function MigrateCheck(ABook: TRuleBook; AHeaderIdx: Integer; const APick: TMigratePick): string;
var
  LProbe: TRuleNode;
  LLink : Integer;
  LNew  : string;
begin
  LNew:= PickNew(APick);
  LProbe:= ABook.ParseLine(MigrateLineText(Trim(APick.Old), LNew));
  try
    Result:= MigrateRefusal(LProbe);
  finally
    LProbe.Free;
  end;
  if Result <> '' then
    Exit;
  LLink:= CoveringLink(ABook, AHeaderIdx, Trim(APick.Old));
  if LLink >= 0 then
    Exit(Format(COVERED_FMT, [LLink + 1, Trim(APick.Old)]));
  if SameText(Trim(APick.Old), LNew) then
    Exit(Format(IDENTITY_FMT, [Trim(APick.Old), LNew]));
  if AHeaderIdx < 0 then
    Exit(MIGRATE_GLOBAL_TEXT);
  Result:= '';
end;

function ApplyMigratePick(ABook: TRuleBook; const ABlock: TMigrateBlock; const APick: TMigratePick): TMigrateOutcome;
var
  LHdr  : Integer;
  LNode : TRuleNode;
  LProbe: TRuleNode;
  LNew  : string;
begin
  Result:= Default(TMigrateOutcome);
  if ABlock.State <> mbFound then
  begin
    Result.Reason:= ABlock.Reason;
    Exit;
  end;
  LNew:= PickNew(APick);
  LProbe:= ABook.ParseLine(MigrateLineText(Trim(APick.Old), LNew));
  try
    Result.Reason:= MigrateRefusal(LProbe);
  finally
    LProbe.Free;
  end;
  if Result.Reason <> '' then
    Exit;
  // Re-find the header by NODE: an insert above it since FindMigrateBlock shifts its index.
  LHdr:= if ABlock.Header <> nil then ABook.Nodes.IndexOf(ABlock.Header) else ABlock.NodeIndex;
  Result.Warning:= MigrateCheck(ABook, LHdr, APick);
  LNode:= FindMigrateInBlock(ABook, LHdr, Trim(APick.Old));
  if LNode <> nil then
  begin
    Result.Before  := LNode.Emit;
    SetMigrateNew(LNode, LNew);
    Result.Replaced:= True;
  end
  else
    LNode:= AddMigrate(ABook, LHdr, Trim(APick.Old), LNew);
  if LNode = nil then
  begin
    Result.Reason:= ABlock.Reason;
    Exit;
  end;
  Result.Applied:= True;
  Result.Node   := LNode;
  Result.After  := LNode.Emit;
  Result.Line   := ABook.Nodes.IndexOf(LNode) + 1;
end;

function MigrateStatusText(const ABookPath: string; const ABlock: TMigrateBlock; const AOutcome: TMigrateOutcome): string;
var
  LBook: string;
begin
  LBook:= ExtractFileName(ABookPath);
  if not AOutcome.Applied then
    Exit(Format(NOTHING_FMT, [LBook, AOutcome.Reason]));
  if AOutcome.Replaced then
    Result:= Format(CHANGED_FMT, [AOutcome.After, AOutcome.Line, LBook])
  else
    Result:= Format(WROTE_FMT, [AOutcome.After, ABlock.HeaderText, AOutcome.Line, LBook]);
  Result:= Result + NOT_SAVED;
  if AOutcome.Warning <> '' then
    Result:= Result + Format(CHECK_FMT, [AOutcome.Warning]);
end;

function MembersRowText(ANode: TRuleNode): TArray<string>;
var
  LKind : string;
  LNotes: TArray<string>;
  LRefusal: string;
begin
  if IsDeliberateBreak(ANode) then
    LKind:= MIGRATE_DL_NONE
  else if IsMemberMigrate(ANode) then
    LKind:= KIND_RENAME
  else
    LKind:= KIND_LEGACY;
  LNotes:= nil;
  LRefusal:= MigrateRefusal(ANode);
  if LRefusal <> '' then
    LNotes:= LNotes + [LRefusal];
  for var LMark: TRuleMark in ANode.Marks do
    LNotes:= LNotes + [LMark.Text];
  Result:= [ANode.MigScope + ANode.MigOld, ANode.MigNew, LKind, string.Join(NOTE_SEPARATOR, LNotes)];
end;

function IsMigrateLine(ANode: TRuleNode; const AOld, ANew: string): Boolean;
begin
  Result:= (ANode.Kind = rnkMigrate) and SameText(ANode.MigOld, AOld) and SameText(ANode.MigNew, ANew);
end;

function FindMigrateTarget(ABook: TRuleBook; ARuleLine: Integer; const AOld, ANew: string): Integer;
begin
  if (ARuleLine >= 1) and (ARuleLine <= ABook.Nodes.Count) and IsMigrateLine(ABook.Nodes[ARuleLine - 1], AOld, ANew) then
    Exit(ARuleLine - 1);
  Result:= -1;
  for var I: Integer:= 0 to ABook.Nodes.Count - 1 do
    if IsMigrateLine(ABook.Nodes[I], AOld, ANew) then
    begin
      if Result >= 0 then
        Exit(-1);  // two lines: ambiguous, mark none
      Result:= I;
    end;
end;

// Adds a warning mark AText to ANode unless one with that text is there; True when added.
function AddWarningMark(ANode: TRuleNode; const AText: string): Boolean;
var
  LMark: TRuleMark;
begin
  for LMark in ANode.Marks do
    if LMark.Text = AText then
      Exit(False);
  LMark:= Default(TRuleMark);
  LMark.Text     := AText;
  LMark.IsWarning:= True;
  ANode.Marks:= ANode.Marks + [LMark];
  Result:= True;
end;

function StaticMigrateMarks(ABook: TRuleBook): Integer;
var
  LNode: TRuleNode;
  LHdr : Integer;
  LText: string;
  LPick: TMigratePick;
begin
  Result:= 0;
  for var I: Integer:= 0 to ABook.Nodes.Count - 1 do
  begin
    LNode:= ABook.Nodes[I];
    if not IsMemberMigrate(LNode) then
      Continue;
    LHdr:= HeaderIndexOfNode(ABook, LNode);
    LText:= '';
    // An earlier member-form line of the block for the same Old wins (the engine's rule).
    if LHdr >= 0 then
      for var J: Integer:= LHdr + 1 to I - 1 do
        if IsMemberMigrate(ABook.Nodes[J]) and SameText(ABook.Nodes[J].MigOld, LNode.MigOld) then
        begin
          LText:= Format(COVERED_FMT, [J + 1, LNode.MigOld]);
          Break;
        end;
    if LText = '' then
    begin
      LPick:= Default(TMigratePick);
      LPick.Old:= LNode.MigOld;
      LPick.New:= LNode.MigNew;
      LText:= MigrateCheck(ABook, LHdr, LPick);
    end;
    if (LText <> '') and AddWarningMark(LNode, LText) then
      Inc(Result);
  end;
end;

function AddMigrateCheckMarks(ABook: TRuleBook; const AChecks: TArray<TApplyItem>): Integer;
var
  LIdx: Integer;
begin
  Result:= 0;
  for var LItem: TApplyItem in AChecks do
  begin
    if (LItem.Line <> 0) or not SameText(LItem.Kind, APPLY_KIND_MIGRATE_CHECK) then
      Continue;
    LIdx:= FindMigrateTarget(ABook, LItem.RuleLine, LItem.Path, LItem.Value);
    if (LIdx >= 0) and AddWarningMark(ABook.Nodes[LIdx], LItem.Text) then
      Inc(Result);
  end;
end;

function MigrateMarkerText(ABook: TRuleBook; AHeaderIdx: Integer): string;
var
  LCount: Integer;
begin
  LCount:= 0;
  for var LNode: TRuleNode in MigratesForBlock(ABook, AHeaderIdx) do
    if IsMemberMigrate(LNode) then
      Inc(LCount);
  Result:= if LCount > 0 then Format(MARKER_FMT, [LCount]) else '';
end;

function RuleForRow(ABook: TRuleBook; const ARow: TPasUseRow): string;
var
  LBlock: TMigrateBlock;
  LNode : TRuleNode;
begin
  if (ABook = nil) or (ARow.Instance = '') then
    Exit('');
  LBlock:= FindMigrateBlock(ABook, ARow.FromType, ARow.ToType, '');
  if LBlock.State <> mbFound then
    Exit('');
  LNode:= FindMigrateInBlock(ABook, LBlock.NodeIndex, ARow.Member);
  if LNode = nil then
    Exit('');
  Result:= Format(RULE_FMT, [LNode.Emit, ABook.Nodes.IndexOf(LNode) + 1, if LNode.Dirty then RULE_UNSAVED else RULE_SAVED]);
end;

function MigrateNote(const ARow: TApplyRow): string;
var
  LParts: TArray<string>;
begin
  LParts:= nil;
  if Length(ARow.MigrateApplied) > 0 then
    LParts:= LParts + [Format(NOTE_RENAMED_FMT, [Length(ARow.MigrateApplied)])];
  if Length(ARow.DeliberateBreaks) > 0 then
    LParts:= LParts + [Format(NOTE_BREAKS_FMT, [Length(ARow.DeliberateBreaks)])];
  if Length(ARow.MigrateChecks) > 0 then
    LParts:= LParts + [Format(NOTE_CHECKS_FMT, [Length(ARow.MigrateChecks)])];
  Result:= if Length(LParts) > 0 then NOTE_PREFIX + string.Join(', ', LParts) else '';
end;

function MigrateReportNote(const AItem: TApplyItem): string;
begin
  if SameText(AItem.Kind, APPLY_KIND_MIGRATE_APPLIED) then
    Result:= Format(REPORT_APPLIED_FMT, [ExtractFileName(AItem.FileName), AItem.Line, AItem.Instance, AItem.OldValue, AItem.Value, AItem.RuleLine])
  else if SameText(AItem.Kind, APPLY_KIND_DELIBERATE_BREAK) then
    Result:= Format(REPORT_BREAK_FMT, [ExtractFileName(AItem.FileName), AItem.Line, AItem.OldValue, AItem.RuleLine])
  else
    Result:= AItem.Text;
end;

function MigrateBookNote(const ABookName, ABookText: string): string;
var
  LBook  : TRuleBook;
  LCount : Integer;
  LInside: Boolean;
begin
  LCount:= 0;
  LBook:= TRuleBook.Create;
  try
    LBook.LoadFromString(ABookText);
    LInside:= False;
    for var LNode: TRuleNode in LBook.Nodes do
    begin
      LInside:= LInside or (LNode.Kind = rnkConvert);
      if LInside and IsMemberMigrate(LNode) then
        Inc(LCount);
    end;
  finally
    LBook.Free;
  end;
  Result:= if LCount > 0 then Format(BOOK_NOTE_FMT, [ABookName, LCount]) else '';
end;

end.