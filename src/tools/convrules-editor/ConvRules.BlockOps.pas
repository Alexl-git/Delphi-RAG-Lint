unit ConvRules.BlockOps;

{ Pure curation operations over block lists: select, delete, split out, copy out,
  and link-level merge PLANNING (PlanMerge). Applying a plan and composing files
  from it (ApplyMerge / Compose) is the next task.

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
/// -- is merged; non-link lines not already present are merged. An incoming block
/// with no counterpart is appended whole.</summary>
/// <returns>A plan; ATarget and AIncoming are copied into it unmodified.</returns>
function PlanMerge(const ATarget, AIncoming: TRuleBlocks): TMergePlan;

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

  function TargetHasLine(const ALine: string): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(TgtOther) do
      if SameText(Trim(TgtOther[k]), Trim(ALine)) then Exit(True);
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

end.
