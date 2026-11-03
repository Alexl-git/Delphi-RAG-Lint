unit ConvRules.AncestorOrder;

{ C8CHAIN (owner ruling Q5, 2026-10-28; Q-B 2026-11-03), the run-order half: given the
  listed units' analyses (ConvRules.Inheritance), the order Convert runs them in
  (strict ancestor-first), the blocking E7 question, and the blocking error for an
  ancestor chain that leaves the project index without reaching the platform library.
  PURE: the platform library comes in as a TLibraryClassCheck (the engine binder is
  ConvRules.InheritanceEngine.EngineLibraryClassCheck; a fake in the tests). }

interface

uses
  ConvRules.Inheritance
  ;

type
  /// <summary>How the platform library index answered "do you declare this class?".</summary>
  /// <remarks>laDeclared: one or more library files declare it (a library root: the walk
  /// stops there, nothing blocks). laAbsent: no library DB declares it. laFailed: a library
  /// DB could not be asked and none declared it; unknown, never read as declared.</remarks>
  TLibraryAnswer = (laDeclared, laAbsent, laFailed);

  /// <summary>Asks the platform library index whether it declares a class.</summary>
  /// <remarks>AClassName is a bare identifier (BareType). AError is set for laFailed only.</remarks>
  TLibraryClassCheck = reference to function(const AClassName: string; out AError: string): TLibraryAnswer;

  /// <summary>One class's library answer, as the Convert tab keeps it between the analysis
  /// (worker thread) and the Convert press (UI thread).</summary>
  TLibraryResult = record
    /// <summary>The bare class name asked.</summary>
    ClassName: string;
    /// <summary>The answer.</summary>
    Answer   : TLibraryAnswer;
    /// <summary>laFailed only: why; '' otherwise.</summary>
    Error    : string;
  end;

const
  /// <summary>The status after No to the E7 question (every engine).</summary>
  ORDER_CANCELLED_TEXT = 'Convert cancelled: nothing was run.';

/// <summary>PURE: AList in the order Convert runs it -- every listed unit after the listed
/// members of its AncestorChain (owner ruling Q5: strict ancestor-first). Stable: units with no
/// constraint between them keep their order, so an ancestor-first list is returned unchanged
/// (the 1.42 engine's own in-batch order then has nothing to move).</summary>
/// <param name="AList">The source list.</param>
/// <param name="AUnits">The listed units' analyses (any order; a unit without one has no constraint).</param>
/// <returns>A permutation of AList. Each pass takes the FIRST remaining unit whose listed
/// ancestors are all placed; a cycle cannot be ordered, so its units follow in list order --
/// nothing is dropped. Unlisted ancestors impose nothing.</returns>
function OrderAncestorFirst(const AList: TArray<string>; const AUnits: TArray<TUnitInheritance>): TArray<string>;

/// <summary>PURE: the blocking E7 question (replaces the warning with "anyway").</summary>
/// <param name="AWarnings">OrderWarnings' lines; not empty.</param>
/// <param name="AOrdered">OrderAncestorFirst's answer.</param>
/// <returns>'Some units are listed above an ancestor that is not converted yet:', the lines one
/// per line, a blank line, then 'Convert runs ancestors first: Base.pas, Mid.pas, Leaf.pas.
/// Reorder the list and run?' (file names, ', '-joined).</returns>
function OrderBlockText(const AWarnings, AOrdered: TArray<string>): string;

/// <summary>PURE: the distinct bare class names (BareType, first-seen order, case-insensitive)
/// where the listed units' ancestor chains left the project index -- the classes the platform
/// library must be asked about.</summary>
/// <param name="AUnits">The listed units' analyses.</param>
/// <returns>[] when no chain left the index.</returns>
function OutsideClassesOf(const AUnits: TArray<TUnitInheritance>): TArray<string>;

/// <summary>PURE: the blocking error for an ancestor chain that leaves the project index and
/// does not reach the platform library (owner ruling Q5-B, 2026-11-03: the ancestor must be in
/// the project; once it is, it is indexed).</summary>
/// <param name="AUnits">The listed units' analyses.</param>
/// <param name="AIsLibrary">Asked once per (unit, Outside class) with the class's BareType; must
/// not be nil.</param>
/// <returns>'' when every Outside class is laDeclared. Else 'Convert refused: an ancestor of a
/// listed unit is not in the project index.', one line per (unit, class) -- laAbsent:
/// '&lt;Unit.pas&gt; descends from &lt;TClass&gt;, whose unit is in no indexed project.';
/// laFailed: '&lt;Unit.pas&gt; descends from &lt;TClass&gt;, which is in no project index; the platform
/// library index could not be asked -- &lt;why&gt;.' -- a blank line, then the instruction to add
/// that unit to the project (.dproj/.dpr) and reindex. No "run anyway".</returns>
/// <remarks>A library that could not be asked blocks (unknown is never read as a library
/// root). No class-name list: a vendor class counts as a root only when the library declares it.</remarks>
function UnindexedBlockText(const AUnits: TArray<TUnitInheritance>; const AIsLibrary: TLibraryClassCheck): string;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , ConvRules.ConvertRun
  ;

const
  NAME_SEP        = ', ';
  ORDER_HEAD      = 'Some units are listed above an ancestor that is not converted yet:';
  ORDER_BLOCK_FMT = 'Convert runs ancestors first: %s. Reorder the list and run?';
  UNINDEXED_HEAD  = 'Convert refused: an ancestor of a listed unit is not in the project index.';
  UNINDEXED_FMT   = '%s descends from %s, whose unit is in no indexed project.';
  UNASKED_FMT     = '%s descends from %s, which is in no project index; the platform library index could not be asked -- %s.';
  UNINDEXED_TAIL  = 'Add that unit to the project (.dproj/.dpr), reindex, and press Convert again.';

// True when every listed ancestor of the unit APas (per its analysis in AUnits) is in APlaced.
function ListedAncestorsPlaced(const AList: TArray<string>; const AUnits: TArray<TUnitInheritance>; const APas: string;
  const APlaced: TArray<string>): Boolean;
begin
  for var LUnit: TUnitInheritance in AUnits do
    if SameText(ExpandFileName(LUnit.UnitPas), ExpandFileName(APas)) then
      for var LAnc: string in AncestorChain(LUnit) do
        if (PathIndex(LAnc, AList) >= 0) and (PathIndex(LAnc, APlaced) < 0) and not SameText(ExpandFileName(LAnc), ExpandFileName(APas)) then
          Exit(False);
  Result:= True;
end;

function OrderAncestorFirst(const AList: TArray<string>; const AUnits: TArray<TUnitInheritance>): TArray<string>;
var
  LTaken : TArray<Boolean>;
  LPicked: Integer;
begin
  Result:= nil;
  SetLength(LTaken, Length(AList));
  while Length(Result) < Length(AList) do
  begin
    LPicked:= -1;
    for var LIdx: Integer:= 0 to High(AList) do
      if not LTaken[LIdx] and ListedAncestorsPlaced(AList, AUnits, AList[LIdx], Result) then
      begin
        LPicked:= LIdx;
        Break;
      end;
    if LPicked < 0 then
    begin
      // a cycle cannot be ordered: the rest follows in list order, nothing is dropped
      for var LIdx: Integer:= 0 to High(AList) do
        if not LTaken[LIdx] then
          Result:= Result + [AList[LIdx]];
      Exit;
    end;
    LTaken[LPicked]:= True;
    Result:= Result + [AList[LPicked]];
  end;
end;

function OrderBlockText(const AWarnings, AOrdered: TArray<string>): string;
var
  LNames: TArray<string>;
begin
  LNames:= nil;
  for var LPas: string in AOrdered do
    LNames:= LNames + [ExtractFileName(LPas)];
  Result:= ORDER_HEAD + sLineBreak + string.Join(sLineBreak, AWarnings) + sLineBreak + sLineBreak
    + Format(ORDER_BLOCK_FMT, [string.Join(NAME_SEP, LNames)]);
end;

function OutsideClassesOf(const AUnits: TArray<TUnitInheritance>): TArray<string>;
begin
  Result:= nil;
  for var LUnit: TUnitInheritance in AUnits do
    for var LClass: string in LUnit.Outside do
      if not MatchText(BareType(LClass), Result) then
        Result:= Result + [BareType(LClass)];
end;

function UnindexedBlockText(const AUnits: TArray<TUnitInheritance>; const AIsLibrary: TLibraryClassCheck): string;
var
  LLines: TArray<string>;
  LError: string;
begin
  LLines:= nil;
  for var LUnit: TUnitInheritance in AUnits do
    for var LClass: string in LUnit.Outside do
      case AIsLibrary(BareType(LClass), LError) of
        laDeclared: ; // a library root: the chain ends there, nothing blocks
        laAbsent:
          LLines:= LLines + [Format(UNINDEXED_FMT, [ExtractFileName(LUnit.UnitPas), LClass])];
        laFailed:
          LLines:= LLines + [Format(UNASKED_FMT, [ExtractFileName(LUnit.UnitPas), LClass, LError])];
      end; // case
  if Length(LLines) = 0 then
    Exit('');
  Result:= UNINDEXED_HEAD + sLineBreak + string.Join(sLineBreak, LLines) + sLineBreak + sLineBreak + UNINDEXED_TAIL;
end;

end.
