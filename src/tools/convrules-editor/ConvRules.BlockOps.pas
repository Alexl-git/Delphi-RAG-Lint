unit ConvRules.BlockOps;

{ Pure curation operations over block lists: select, delete, split out, copy out,
  and (from the next task) link-level merge and compose.

  Every operation moves the blocks' RAW TEXT, so a block that was merely moved is
  byte-identical to what it was in its old file -- comments, blank lines and
  unrecognised directives included. Nothing here touches the file system or VCL, so
  all of it is unit-tested against inline fixtures. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  ConvRules.BlockFile;

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

end.
