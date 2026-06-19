unit DRagLint.Index.Coverage;

/// <summary>Classifies immediate child folders of a root directory against a
/// drag-lint manifest to show which folders are indexed, overlapping, excluded,
/// library-only, or unassigned.</summary>
/// <remarks>
/// Used by the visual configurator to display a per-folder coverage map and
/// by the selftest coverage CLI hook for headless verification.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , System.IOUtils
  , System.Classes
  , System  .Generics.Collections
  , DRagLint.Index   .Manifest
  , DRagLint.Index   .Plan
  , DRagLint.Index   .Glob
  , DRagLint.Project .Resolver
  ;

type
  /// <summary>Classification of a folder relative to the index manifest.</summary>
  TCoverageKind = (
    /// <summary>Folder is covered by exactly one non-library section.</summary>
    ckIndexed,
    /// <summary>Folder is covered by more than one non-library section (overlap).</summary>
    ckOverlap,
    /// <summary>Folder is excluded by a global, section, or built-in prune rule.</summary>
    ckExcluded,
    /// <summary>Folder is under a Delphi registry library root but not in any section.</summary>
    ckLibrary,
    /// <summary>Folder is not covered by any manifest section or library root.</summary>
    ckUnassigned);

  /// <summary>Coverage classification result for one immediate child folder.</summary>
  TCoverageItem = record
    /// <summary>Absolute path of the child folder.</summary>
    Folder: string;
    /// <summary>Classification of the folder relative to the manifest.</summary>
    Kind: TCoverageKind;
    /// <summary>Human-readable detail: section name(s), exclude rule, or empty.</summary>
    Detail: string;
  end;

  /// <summary>Classify each immediate child folder of ARoot by how AManifest
  /// covers it. Read-only (filesystem + manifest). AResolver supplies library
  /// roots.</summary>
  /// <param name="AManifest">Parsed manifest. RootDir must be set for relative
  /// include paths to resolve correctly.</param>
  /// <param name="ARoot">Absolute path of the directory whose immediate children
  /// are to be classified. Must exist.</param>
  /// <param name="AResolver">Project resolver used to query registry library roots.
  /// Caller owns and must not free until after this function returns.</param>
  /// <returns>Array of TCoverageItem, one per immediate child directory of ARoot,
  /// in filesystem enumeration order. Empty when ARoot has no child directories.</returns>
  /// <remarks>
  /// Classification order (first match wins):
  ///   1. ckIndexed  - child is under exactly one non-library section root.
  ///   2. ckOverlap  - child is under two or more non-library section roots.
  ///   3. ckExcluded - child leaf name matches a built-in prune name or any
  ///                   global or section exclude glob (TGlob.Matches on leaf).
  ///   4. ckLibrary  - child is under a Delphi registry library root.
  ///   5. ckUnassigned - none of the above.
  /// Not thread-safe; call from the owning thread only.
  /// </remarks>
function ComputeCoverage(const AManifest: TIndexManifest; const ARoot: string; AResolver: TProjectResolver): TArray<TCoverageItem>;

/// <summary>Return the lowercase display string for a TCoverageKind value.</summary>
/// <param name="K">The coverage kind to convert.</param>
/// <returns>'indexed', 'overlap', 'excluded', 'library', or 'unassigned'.</returns>
function CoverageKindStr(K: TCoverageKind): string;

implementation

{ ---------------------------------------------------------------------- }
{  Built-in prune patterns                                                 }
{ ---------------------------------------------------------------------- }

const { Exact leaf names (case-insensitive) that are always treated as excluded. }
  PRUNE_EXACT: array[0..6] of string = ( '__history', '__recovery', '.git', '.svn', '.hg', 'node_modules', '.vs' );

  { Glob patterns (applied via TGlob.Matches on the leaf name). }
  PRUNE_GLOB: array[0..0] of string = ( '*backup*' );

  { Returns True when ALeaf matches any built-in prune rule. }
function IsBuiltinPrune(const ALeaf: string): Boolean;
var
  I : Integer;
  Lo: string ;
begin
  Lo:= LowerCase(ALeaf);
  for I:= Low(PRUNE_EXACT) to High(PRUNE_EXACT) do
    if Lo = PRUNE_EXACT[I] then Exit(True);
  for I:= Low(PRUNE_GLOB) to High(PRUNE_GLOB) do
    if TGlob.Matches(ALeaf, PRUNE_GLOB[I]) then Exit(True);
  Result:= False;
end;

{ Normalize an absolute path to lowercase with a trailing path separator
  so that IsUnderRoot comparisons are prefix-safe. }
function NormPath(const APath: string): string;
begin
  Result:= LowerCase(IncludeTrailingPathDelimiter(APath));
end;

{ Returns True when AChildNorm is the same as or underneath ARootNorm.
  Both parameters must already be normalized (lowercase + trailing sep). }
function IsUnderRoot(const AChildNorm, ARootNorm: string): Boolean;
begin
  Result:= AChildNorm.StartsWith(ARootNorm);
end;

{ ---------------------------------------------------------------------- }
{  ComputeCoverage                                                         }
{ ---------------------------------------------------------------------- }

function ComputeCoverage(const AManifest: TIndexManifest; const ARoot: string; AResolver: TProjectResolver): TArray<TCoverageItem>;
var
  Plan          : TIndexPlan          ;
  LibRoots      : TArray<string>      ;
  Children      : TArray<string>      ;
  Results       : TList<TCoverageItem>;
  Child         : string              ;
  Leaf          : string              ;
  NormChild     : string              ;
  Item          : TCoverageItem       ;
  PS            : TPlanSection        ;
  Sec           : TIndexSection       ;
  SectionRoot   : string              ;
  I             : Integer             ;
  MatchedNames  : TStringList         ;
  MatchDetail   : string              ;
  LibRoot       : string              ;
  IsLib         : Boolean             ;
  ExcludeMatched: Boolean             ;
  ExcludeRule   : string              ;
  SectionEx     : TArray<string>      ;
begin
  Result:= nil;

  { --- 1. Enumerate immediate child directories of ARoot --- }
  { Normalise ARoot first so child paths returned by GetDirectories are
    canonical absolute paths (no embedded '..') for reliable prefix matching. }
  var NormRoot: string;
  NormRoot:= ARoot;
  try
    NormRoot:= TPath.GetFullPath(NormRoot);
  except
    // keep as-is if GetFullPath fails
  end;

  if not TDirectory.Exists(NormRoot) then Exit;

  Children:= TDirectory.GetDirectories(NormRoot);
  if Length(Children) = 0 then Exit;

  { --- 2. Resolve the manifest into a concrete plan --- }
  Plan:= ResolvePlan(AManifest, nil, AResolver);

  { --- 3. Collect Delphi registry library roots (Win32+Win64) --- }
  LibRoots:= AResolver.ResolveLibraryPaths(False);

  { --- 4. Classify each immediate child folder --- }
  Results:= TList<TCoverageItem>.Create;
  try
    for Child in Children do
    begin
      { Resolve any '..' segments so the prefix-match against plan roots works. }
      var AbsChild: string;
      AbsChild:= Child;
      try
        AbsChild:= TPath.GetFullPath(Child);
      except
        // keep as-is
      end;
      Leaf:= TPath.GetFileName(AbsChild);
      NormChild:= NormPath(AbsChild);

      Item:= Default(TCoverageItem);
      Item.Folder:= AbsChild;

      { Step 1+2: which non-library plan sections have a root that covers this child? }
      MatchedNames:= TStringList.Create;
      try
        MatchedNames.CaseSensitive:= False;
        for PS in Plan.Items do
        begin
          if PS.Mode = smLibrary then Continue;
          for SectionRoot in PS.Roots do
          begin
            if IsUnderRoot(NormChild, NormPath(SectionRoot)) then
            begin
              if MatchedNames.IndexOf(PS.Name) < 0 then MatchedNames.Add(PS.Name);
              Break;
            end;
          end;
        end;

        if MatchedNames.Count = 1 then
        begin
          Item.Kind:= ckIndexed;
          Item.Detail:= MatchedNames[0];
          Results.Add(Item);
          Continue;
        end;

        if MatchedNames.Count > 1 then
        begin
          Item.Kind:= ckOverlap;
          MatchDetail:= '';
          for I:= 0 to MatchedNames.Count - 1 do
          begin
            if MatchDetail <> '' then MatchDetail:= MatchDetail + ',';
            MatchDetail:= MatchDetail + MatchedNames[I];
          end;
          Item.Detail:= MatchDetail;
          Results.Add(Item);
          Continue;
        end;
      finally
        MatchedNames.Free;
      end; // try

      { Step 3: excluded by built-in prune or manifest exclude globs? }
      ExcludeMatched:= False;
      ExcludeRule   := '';

      if IsBuiltinPrune(Leaf) then
      begin
        ExcludeMatched:= True;
        ExcludeRule:= 'built-in:' + LowerCase(Leaf);
      end;

      if not ExcludeMatched then
      begin
        for I:= 0 to High(AManifest.GlobalExclude) do
        begin
          if TGlob.Matches(Leaf, AManifest.GlobalExclude[I]) then
          begin
            ExcludeMatched:= True;
            ExcludeRule:= 'global:' + AManifest.GlobalExclude[I];
            Break;
          end;
        end;
      end;

      if not ExcludeMatched then
      begin
        for Sec in AManifest.Sections do
        begin
          if ExcludeMatched then Break;
          SectionEx:= Sec.Exclude;
          for I:= 0 to High(SectionEx) do
          begin
            if TGlob.Matches(Leaf, SectionEx[I]) then
            begin
              ExcludeMatched:= True;
              ExcludeRule:= 'section(' + Sec.Name + '):' + SectionEx[I];
              Break;
            end;
          end;
        end;
      end; // if

      if ExcludeMatched then
      begin
        Item.Kind  := ckExcluded;
        Item.Detail:= ExcludeRule;
        Results.Add(Item);
        Continue;
      end;

      { Step 4: under a Delphi registry library root? }
      IsLib:= False;
      for LibRoot in LibRoots do
      begin
        if IsUnderRoot(NormChild, NormPath(LibRoot)) then
        begin
          IsLib:= True;
          Break;
        end;
      end;

      if IsLib then
      begin
        Item.Kind  := ckLibrary;
        Item.Detail:= '';
        Results.Add(Item);
        Continue;
      end;

      { Step 5: unassigned }
      Item.Kind  := ckUnassigned;
      Item.Detail:= '';
      Results.Add(Item);
    end; // for

    Result:= Results.ToArray;
  finally
    Results.Free;
  end; // try
end; // function

{ ---------------------------------------------------------------------- }
{  CoverageKindStr                                                         }
{ ---------------------------------------------------------------------- }

function CoverageKindStr(K: TCoverageKind): string;
begin
  case K of
    ckIndexed : Result:= 'indexed';
    ckOverlap : Result:= 'overlap';
    ckExcluded: Result:= 'excluded';
    ckLibrary : Result:= 'library';
    else Result:= 'unassigned';
  end;
end;

end.
