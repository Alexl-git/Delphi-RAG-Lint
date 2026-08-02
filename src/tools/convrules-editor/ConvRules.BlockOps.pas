unit ConvRules.BlockOps;

{ Pure curation operations over block lists: select, delete, split out, copy out,
  link-level merge PLANNING (PlanMerge), applying a plan (ApplyMerge), and folding
  a whole working set into one file by precedence (Compose). The working set
  itself, file I/O, backups and the VCL form are built on top of this unit, not in it.

  Every operation moves the blocks' RAW TEXT, so a block that was merely moved is
  byte-identical to what it was in its old file -- comments, blank lines and
  unrecognised directives included. Nothing here touches the file system or VCL, so
  all of it is unit-tested against inline fixtures. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  ConvRules.BlockFile, ConvRules.Model;

/// <summary>PURE: the blocks at AIndexes, in ASCENDING index order regardless of
/// the order AIndexes were given in (the grid may report checks out of order).
/// Out-of-range indexes are ignored.</summary>
function SelectBlocks(const ABlocks: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: ABlocks minus the blocks at AIndexes, order otherwise preserved.</summary>
function DeleteBlocks(const ABlocks: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: move blocks out -- ARemaining is the source without them,
/// AMoved is the blocks themselves in their original relative order.</summary>
procedure SplitOut(const ASource: TRuleBlocks; const AIndexes: TArray<Integer>;
  out ARemaining, AMoved: TRuleBlocks);

/// <summary>PURE: the blocks to write elsewhere; the source is not modified.</summary>
function CopyOut(const ASource: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: the enablement rule for the Split / Copy / Delete commands --
/// they operate on a selection, so an empty selection disables them.</summary>
function CanOperateOn(const ASelected: TArray<Integer>): Boolean;

type
  /// <summary>One #link inside a block, with its verbatim source line.</summary>
  /// <remarks>Parsed with TRuleBook so the DSL grammar lives in exactly one place;
  /// Line is the ORIGINAL text and is what gets written, never a re-emission.</remarks>
  TBlockLink = record
    Line    : string;   // verbatim source line, no terminator
    LinkTo  : string;   // target path (left of '<-')
    LinkFrom: string;   // source path (right of '<-')
    Cast    : string;   // optional cast name ('' = identity)
  end;

  /// <summary>What the merger decided to do with one incoming line or block.</summary>
  TMergeAction = (
    maAppendBlock,    // incoming block has no counterpart -> append it whole
    maMergeLink,      // incoming #link is missing from the target -> append the line
    maMergeOther,     // incoming non-link line not already present -> append the line
    maSkipDuplicate,  // identical link already present -> do nothing
    maConflict        // target already linked from a different source (or cast)
  );

  /// <summary>One planned merge decision.</summary>
  TMergeItem = record
    Action          : TMergeAction;
    TargetBlockIdx  : Integer;   // index into TMergePlan.Target; -1 for maAppendBlock
    IncomingBlockIdx: Integer;   // index into TMergePlan.Incoming
    Line            : string;    // the incoming line, verbatim ('' for maAppendBlock)
    ToPath          : string;    // contested/merged target path ('' when n/a)
    ExistingLine    : string;    // maConflict: the target's current #link line
    ExistingFrom    : string;    // maConflict: its source path
    IncomingFrom    : string;    // maConflict: the incoming source path
  end;

  /// <summary>A merge worked out but NOT applied. Planning is pure and writes
  /// nothing, which is what lets a conflict be reported before either link is
  /// written (acceptance criterion 6).</summary>
  TMergePlan = record
    Target  : TRuleBlocks;
    Incoming: TRuleBlocks;
    Items   : TArray<TMergeItem>;
    /// <summary>How many items need a user decision.</summary>
    function ConflictCount: Integer;
  end;

/// <summary>PURE: the #link lines of one block, parsed via TRuleBook (read-only --
/// the model is never asked to re-emit).</summary>
function BlockLinks(const ABlock: TRuleBlock): TArray<TBlockLink>;

/// <summary>PURE: work out how AIncoming would fold into ATarget. Blocks are matched
/// by trimmed header, case-insensitively. Within a matched pair: an identical link
/// is skipped; a target already linked from a different source (or with a different
/// cast) is a CONFLICT; a new target -- including one fed by an already-used source
/// -- is merged; non-link lines not already present in the target are merged
/// verbatim, where "already present" is an EXACT match after trimming (case-
/// SENSITIVE -- non-link content is never deduped just because it differs only in
/// case). An incoming block with no counterpart is appended whole.</summary>
/// <returns>A plan; ATarget and AIncoming are copied into it unmodified.</returns>
/// <remarks>The case-SENSITIVE dedup of non-link lines is deliberate but it does
/// sit oddly in a DSL that is otherwise case-insensitive: '#Default X = 1' and
/// '#default X = 1' are not "identical", so a merge keeps BOTH and the engine then
/// sees the directive twice. The trade is intentional -- dropping a line the user
/// wrote is worse than keeping a near-duplicate they can see and delete.</remarks>
function PlanMerge(const ATarget, AIncoming: TRuleBlocks): TMergePlan;

type
  /// <summary>How one conflict is settled.</summary>
  TMergeResolution = (mrKeepExisting, mrTakeIncoming);

  /// <summary>One file of a working set, in composition order.</summary>
  TComposeInput = record
    Path  : string;
    Blocks: TRuleBlocks;
  end;

  /// <summary>What a composition did: a human-readable line per decision that was
  /// not a plain no-op, plus the two counts the status bar shows.</summary>
  TComposeReport = record
    Lines        : TArray<string>;
    ResolvedCount: Integer;   // collisions auto-resolved by precedence
    AppendedCount: Integer;   // whole blocks appended
  end;

/// <summary>PURE: apply a plan and return the merged block list. AResolutions is
/// indexed by CONFLICT ORDINAL (the i-th maConflict item in plan order); a missing
/// entry means mrKeepExisting. mrTakeIncoming replaces the existing #link line in
/// place, verbatim; every other write appends the incoming line verbatim to the end
/// of the matched block. The target blocks are never re-emitted.</summary>
function ApplyMerge(const APlan: TMergePlan;
  const AResolutions: TArray<TMergeResolution>): TRuleBlocks;

/// <summary>PURE: one report line per non-trivial decision, naming AIncomingName
/// (the file the blocks came from) so a composed report is readable.</summary>
function MergeReportLines(const APlan: TMergePlan;
  const AResolutions: TArray<TMergeResolution>;
  const AIncomingName: string): TArray<string>;

/// <summary>PURE: fold the working set into one file, top to bottom, with the merge
/// semantics above. Earlier files win: every collision is auto-resolved in favour of
/// the earlier file and listed in AReport (composing three large books must not mean
/// answering hundreds of prompts). Returns the composed file text.</summary>
function Compose(const AInputs: TArray<TComposeInput>;
  out AReport: TComposeReport): string;

/// <summary>PURE: the block, guaranteed to end with a line terminator. A file whose
/// last line had no EOL would otherwise glue itself onto whatever is appended after
/// it, producing '#link R <- S#convert X.T -> Y.T'.</summary>
function EnsureTrailingEol(const ABlock: TRuleBlock): TRuleBlock;

/// <summary>PURE: AFirst followed by ASecond, with AFirst's last block terminated so
/// the two never run together. Used when appending split-out blocks to an existing
/// file (a move, not a merge).</summary>
/// <remarks>AFirst is COPIED, not aliased: a dynamic array is a reference and an
/// element write does not copy-on-write, so returning AFirst itself would terminate
/// the caller's last block -- and callers hand in TWorkingSet.Item(i).Blocks, which
/// shares the working set's stored array.</remarks>
function ConcatBlocks(const AFirst, ASecond: TRuleBlocks): TRuleBlocks;

/// <summary>PURE: the headers of AIncoming that AExisting ALREADY has, matched the
/// way PlanMerge matches them (same Kind, trimmed header, case-insensitively).</summary>
/// <remarks>A split/copy APPENDS verbatim without merging, and its target dialog has
/// no overwrite prompt, so a duplicated header silently leaves the target holding two
/// blocks for one rule -- this is what the form warns from. Preamble blocks have no
/// header and are never reported.</remarks>
function DuplicateHeaders(const AExisting, AIncoming: TRuleBlocks): TArray<string>;

implementation

uses
  System.Generics.Defaults;

{ Ascending, de-duplicated copy of a selection. }
function NormalizeIndexes(const AIndexes: TArray<Integer>; ACount: Integer): TArray<Integer>;
var
  List: TList<Integer>;
  i   : Integer;
begin
  List := TList<Integer>.Create;
  try
    for i in AIndexes do
      if (i >= 0) and (i < ACount) and (List.IndexOf(i) < 0) then List.Add(i);
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function SelectBlocks(const ABlocks: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;
var
  Idx: TArray<Integer>;
  i  : Integer;
begin
  Idx := NormalizeIndexes(AIndexes, Length(ABlocks));
  SetLength(Result, Length(Idx));
  for i := 0 to High(Idx) do
    Result[i] := ABlocks[Idx[i]];
end;

function DeleteBlocks(const ABlocks: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;
var
  Idx : TArray<Integer>;
  List: TList<TRuleBlock>;
  i   : Integer;

  function Selected(AIndex: Integer): Boolean;
  var
    k: Integer;
  begin
    for k in Idx do
      if k = AIndex then Exit(True);
    Result := False;
  end;

begin
  Idx  := NormalizeIndexes(AIndexes, Length(ABlocks));
  List := TList<TRuleBlock>.Create;
  try
    for i := 0 to High(ABlocks) do
      if not Selected(i) then List.Add(ABlocks[i]);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure SplitOut(const ASource: TRuleBlocks; const AIndexes: TArray<Integer>;
  out ARemaining, AMoved: TRuleBlocks);
begin
  AMoved     := SelectBlocks(ASource, AIndexes);
  ARemaining := DeleteBlocks(ASource, AIndexes);
end;

function CopyOut(const ASource: TRuleBlocks;
  const AIndexes: TArray<Integer>): TRuleBlocks;
begin
  Result := SelectBlocks(ASource, AIndexes);
end;

function CanOperateOn(const ASelected: TArray<Integer>): Boolean;
begin
  Result := Length(ASelected) > 0;
end;

function TMergePlan.ConflictCount: Integer;
var
  It: TMergeItem;
begin
  Result := 0;
  for It in Items do
    if It.Action = maConflict then Inc(Result);
end;

function BlockLinks(const ABlock: TRuleBlock): TArray<TBlockLink>;
var
  Book: TRuleBook;
  List: TList<TBlockLink>;
  i   : Integer;
  L   : TBlockLink;
begin
  List := TList<TBlockLink>.Create;
  Book := TRuleBook.Create;
  try
    Book.LoadFromString(ABlock.RawText);
    for i := 0 to Book.Nodes.Count - 1 do
      if Book.Nodes[i].Kind = rnkLink then
      begin
        L.Line     := Book.Nodes[i].Raw;
        L.LinkTo   := Book.Nodes[i].LinkTo;
        L.LinkFrom := Book.Nodes[i].LinkFrom;
        L.Cast     := Book.Nodes[i].Cast;
        List.Add(L);
      end;
    Result := List.ToArray;
  finally
    Book.Free;
    List.Free;
  end;
end;

{ Every line of a block except its header, its #link lines and its blank lines --
  i.e. #default / #ignore / #note / comments / unknown directives. }
function BlockOtherLines(const ABlock: TRuleBlock): TArray<string>;
var
  Lines: TArray<TRawLine>;
  List : TList<string>;
  i, i0: Integer;
begin
  List  := TList<string>.Create;
  try
    Lines := SplitRawLines(ABlock.RawText);
    if ABlock.Kind = rbkPreamble then i0 := 0 else i0 := 1;   // skip the header line
    for i := i0 to High(Lines) do
      if (Trim(Lines[i].Text) <> '')
         and not SameText(FirstToken(Lines[i].Text), '#link') then
        List.Add(Lines[i].Text);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ Index of the target block whose trimmed header equals AHeader, or -1. }
function IndexOfHeader(const ABlocks: TRuleBlocks; const AHeader: string;
  AKind: TRuleBlockKind): Integer;
var
  i: Integer;
begin
  for i := 0 to High(ABlocks) do
    if (ABlocks[i].Kind = AKind) and SameText(Trim(ABlocks[i].Header), Trim(AHeader)) then
      Exit(i);
  Result := -1;
end;

function DuplicateHeaders(const AExisting, AIncoming: TRuleBlocks): TArray<string>;
var
  List: TList<string>;
  i   : Integer;
begin
  List := TList<string>.Create;
  try
    for i := 0 to High(AIncoming) do
      if (AIncoming[i].Kind <> rbkPreamble)
         and (IndexOfHeader(AExisting, AIncoming[i].Header, AIncoming[i].Kind) >= 0) then
        List.Add(Trim(AIncoming[i].Header));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function PlanMerge(const ATarget, AIncoming: TRuleBlocks): TMergePlan;
var
  Items : TList<TMergeItem>;
  bi, ti: Integer;
  TgtLinks, IncLinks: TArray<TBlockLink>;
  IncOther, TgtOther: TArray<string>;
  Item  : TMergeItem;
  L     : TBlockLink;
  S     : string;
  Existing: TBlockLink;

  function FindTargetLink(const AToPath: string; out AFound: TBlockLink): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(TgtLinks) do
      if SameText(TgtLinks[k].LinkTo, AToPath) then
      begin
        AFound := TgtLinks[k];
        Exit(True);
      end;
    Result := False;
  end;

  { EXACT match after trimming -- case-SENSITIVE. Non-#link content (comments,
    #default/#ignore/#note, unknown directives) is never silently deduped just
    because it differs only in case; only a truly identical line is skipped.
    CONSEQUENCE, in a DSL that is otherwise case-insensitive: '#Default X = 1' and
    '#default X = 1' both survive a merge and the engine sees the directive twice.
    Accepted -- see the <remarks> on PlanMerge; losing a line the user wrote would
    be the worse failure. }
  function TargetHasLine(const ALine: string): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(TgtOther) do
      if Trim(TgtOther[k]) = Trim(ALine) then Exit(True);
    Result := False;
  end;

begin
  Result.Target   := ATarget;
  Result.Incoming := AIncoming;
  Items := TList<TMergeItem>.Create;
  try
    for bi := 0 to High(AIncoming) do
    begin
      ti := IndexOfHeader(ATarget, AIncoming[bi].Header, AIncoming[bi].Kind);
      if ti < 0 then
      begin
        Item := Default(TMergeItem);
        Item.Action           := maAppendBlock;
        Item.TargetBlockIdx   := -1;
        Item.IncomingBlockIdx := bi;
        Items.Add(Item);
        Continue;
      end;

      TgtLinks := BlockLinks(ATarget[ti]);
      TgtOther := BlockOtherLines(ATarget[ti]);
      IncLinks := BlockLinks(AIncoming[bi]);
      IncOther := BlockOtherLines(AIncoming[bi]);

      for L in IncLinks do
      begin
        Item := Default(TMergeItem);
        Item.TargetBlockIdx   := ti;
        Item.IncomingBlockIdx := bi;
        Item.Line             := L.Line;
        Item.ToPath           := L.LinkTo;
        if not FindTargetLink(L.LinkTo, Existing) then
          Item.Action := maMergeLink                       // missing (incl. fan-out)
        else if SameText(Existing.LinkFrom, L.LinkFrom)
                and SameText(Existing.Cast, L.Cast) then
          Item.Action := maSkipDuplicate
        else
        begin
          Item.Action       := maConflict;
          Item.ExistingLine := Existing.Line;
          Item.ExistingFrom := Existing.LinkFrom;
          Item.IncomingFrom := L.LinkFrom;
        end;
        Items.Add(Item);
      end;

      for S in IncOther do
        if not TargetHasLine(S) then
        begin
          Item := Default(TMergeItem);
          Item.Action           := maMergeOther;
          Item.TargetBlockIdx   := ti;
          Item.IncomingBlockIdx := bi;
          Item.Line             := S;
          Items.Add(Item);
        end;
    end;
    Result.Items := Items.ToArray;
  finally
    Items.Free;
  end;
end;

{ Append whole lines to the end of a block, using the block's own terminator and
  first making sure the block ends with one.

  CALLER BEWARE -- "the end of the block" is literally the end of RawText. That is
  right for an rbkConvert/rbkPreamble block, which has no closing line, and WRONG for
  an rbkCast/rbkEnum block, whose RawText INCLUDES its 'end' line and any trailing
  blanks (see SplitCastLibBlocks): the appended line lands AFTER 'end', outside the
  block body, and nothing here can tell. That is why the curation form refuses a
  merge or a compose whose TARGET is a catalog -- see ConvRules.BlockFile's
  GrammarAcceptsMerge. Do not "fix" it by teaching this function to insert before
  'end': that is a feature with its own design questions (where among the body lines,
  what about trailing comments) and needs deciding, not guessing. }
function AppendLinesToBlock(const ABlock: TRuleBlock;
  const ALines: TArray<string>): TRuleBlock;
var
  Eol: string;
  S  : string;
begin
  Result := ABlock;
  if Length(ALines) = 0 then Exit;
  Eol := BlockEol(ABlock);
  if (Result.RawText <> '')
     and not (Result.RawText.EndsWith(#10) or Result.RawText.EndsWith(#13)) then
    Result.RawText := Result.RawText + Eol;
  for S in ALines do
  begin
    Result.RawText := Result.RawText + S + Eol;
    Inc(Result.EndLine);
  end;
end;

{ Replace the FIRST line equal to AOld with ANew, keeping every terminator. }
function ReplaceLineInBlock(const ABlock: TRuleBlock;
  const AOld, ANew: string): TRuleBlock;
var
  Lines: TArray<TRawLine>;
  i    : Integer;
  Done : Boolean;
begin
  Result := ABlock;
  Lines  := SplitRawLines(ABlock.RawText);
  Done   := False;
  Result.RawText := '';
  for i := 0 to High(Lines) do
  begin
    if (not Done) and (Lines[i].Text = AOld) then
    begin
      Result.RawText := Result.RawText + ANew + Lines[i].Eol;
      Done := True;
    end
    else
      Result.RawText := Result.RawText + Lines[i].Text + Lines[i].Eol;
  end;
end;

function EnsureTrailingEol(const ABlock: TRuleBlock): TRuleBlock;
begin
  Result := ABlock;
  if (Result.RawText <> '')
     and not (Result.RawText.EndsWith(#10) or Result.RawText.EndsWith(#13)) then
    Result.RawText := Result.RawText + BlockEol(Result);
end;

function ConcatBlocks(const AFirst, ASecond: TRuleBlocks): TRuleBlocks;
var
  i: Integer;
begin
  // Copy, never alias: the element write below would otherwise reach through into
  // AFirst itself (a dynamic array is a reference; only SetLength uniquifies).
  Result := Copy(AFirst);
  if Length(Result) > 0 then
    Result[High(Result)] := EnsureTrailingEol(Result[High(Result)]);
  for i := 0 to High(ASecond) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := ASecond[i];
  end;
end;

{ The resolution for the AConflictOrdinal-th conflict (default: keep existing). }
function ResolutionAt(const AResolutions: TArray<TMergeResolution>;
  AConflictOrdinal: Integer): TMergeResolution;
begin
  if (AConflictOrdinal >= 0) and (AConflictOrdinal <= High(AResolutions)) then
    Result := AResolutions[AConflictOrdinal]
  else
    Result := mrKeepExisting;
end;

function ApplyMerge(const APlan: TMergePlan;
  const AResolutions: TArray<TMergeResolution>): TRuleBlocks;
var
  Blocks : TList<TRuleBlock>;
  i, cOrd: Integer;
  It     : TMergeItem;
begin
  Blocks := TList<TRuleBlock>.Create;
  try
    for i := 0 to High(APlan.Target) do Blocks.Add(APlan.Target[i]);
    cOrd := 0;
    for i := 0 to High(APlan.Items) do
    begin
      It := APlan.Items[i];
      case It.Action of
        maAppendBlock:
          begin
            // terminate whatever is currently last, or the two blocks run together
            if Blocks.Count > 0 then
              Blocks[Blocks.Count - 1] := EnsureTrailingEol(Blocks[Blocks.Count - 1]);
            Blocks.Add(APlan.Incoming[It.IncomingBlockIdx]);
          end;
        maMergeLink, maMergeOther:
          Blocks[It.TargetBlockIdx] :=
            AppendLinesToBlock(Blocks[It.TargetBlockIdx], [It.Line]);
        maConflict:
          begin
            if ResolutionAt(AResolutions, cOrd) = mrTakeIncoming then
              Blocks[It.TargetBlockIdx] :=
                ReplaceLineInBlock(Blocks[It.TargetBlockIdx], It.ExistingLine, It.Line);
            Inc(cOrd);
          end;
        maSkipDuplicate: ; // nothing to do
      end;
    end;
    Result := Blocks.ToArray;
  finally
    Blocks.Free;
  end;
end;

function MergeReportLines(const APlan: TMergePlan;
  const AResolutions: TArray<TMergeResolution>;
  const AIncomingName: string): TArray<string>;
var
  List   : TList<string>;
  i, cOrd: Integer;
  It     : TMergeItem;
begin
  List := TList<string>.Create;
  try
    cOrd := 0;
    for i := 0 to High(APlan.Items) do
    begin
      It := APlan.Items[i];
      case It.Action of
        maAppendBlock:
          List.Add(Format('%s: appended block %s',
            [AIncomingName, Trim(APlan.Incoming[It.IncomingBlockIdx].Header)]));
        maMergeLink:
          List.Add(Format('%s: merged %s', [AIncomingName, Trim(It.Line)]));
        maMergeOther:
          List.Add(Format('%s: merged line %s', [AIncomingName, Trim(It.Line)]));
        maConflict:
          begin
            if ResolutionAt(AResolutions, cOrd) = mrTakeIncoming then
              List.Add(Format('%s: conflict on %s -- took incoming (%s <- %s), dropped (%s <- %s)',
                [AIncomingName, It.ToPath, It.ToPath, It.IncomingFrom, It.ToPath, It.ExistingFrom]))
            else
              List.Add(Format('%s: conflict on %s -- kept earlier (%s <- %s), dropped (%s <- %s)',
                [AIncomingName, It.ToPath, It.ToPath, It.ExistingFrom, It.ToPath, It.IncomingFrom]));
            Inc(cOrd);
          end;
        maSkipDuplicate: ; // a duplicate is a no-op, not worth a report line
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function Compose(const AInputs: TArray<TComposeInput>;
  out AReport: TComposeReport): string;
var
  Acc  : TRuleBlocks;
  Plan : TMergePlan;
  Lines: TList<string>;
  i, k : Integer;
  Name : string;
begin
  AReport := Default(TComposeReport);
  if Length(AInputs) = 0 then Exit('');
  Acc   := AInputs[0].Blocks;
  Lines := TList<string>.Create;
  try
    for i := 1 to High(AInputs) do
    begin
      Name := ExtractFileName(AInputs[i].Path);
      Plan := PlanMerge(Acc, AInputs[i].Blocks);
      for k := 0 to High(Plan.Items) do
        case Plan.Items[k].Action of
          maConflict:    Inc(AReport.ResolvedCount);
          maAppendBlock: Inc(AReport.AppendedCount);
        end;
      Lines.AddRange(MergeReportLines(Plan, nil, Name));   // nil = keep earlier
      Acc := ApplyMerge(Plan, nil);
    end;
    AReport.Lines := Lines.ToArray;
    Result := JoinBlocks(Acc);
  finally
    Lines.Free;
  end;
end;

end.
