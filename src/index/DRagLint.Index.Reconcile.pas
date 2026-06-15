unit DRagLint.Index.Reconcile;

// Reconciler: compares the .dpr/.dproj member list against the actual compile
// closure and returns three disjoint sets:
//   Missing -- closure files not listed in .dpr/.dproj (will be added by Apply)
//   Extra   -- listed members not reached by the closure (reported only)
//   Stale   -- closure files whose base name matches a stale heuristic
//              (*_OLD*, *-Copy*, *BACKUP*, *-bad*, *_20######*, etc.)
//
// Analyze is read-only; Apply (Task 2) writes changes.
// Both methods accept a single project file (.dpr or .dproj); when a .dpr is
// given Analyze also reads the sibling .dproj if it exists, and vice-versa.

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  DRagLint.Index.Closure,
  DRagLint.Index.Glob;

type
  /// <summary>Identifies which reconcile set an item belongs to.</summary>
  TReconcileKind = (rkMissing, rkExtra, rkStale);

  /// <summary>One item in a reconcile report.</summary>
  TReconcileItem = record
    /// <summary>Kind of finding: missing / extra / stale.</summary>
    Kind:     TReconcileKind;
    /// <summary>Pascal unit name (without extension).</summary>
    UnitName: string;
    /// <summary>Absolute path to the .pas file.</summary>
    FilePath: string;
    /// <summary>Path relative to the project directory (backslash-separated).</summary>
    RelPath:  string;
    /// <summary>Name of the unit that pulls this file in via uses.
    /// Empty for project-direct (.dpr/dproj seed) entries.
    /// '&lt;project&gt;' if seeded from the project member list.</summary>
    UsedBy:   string;
  end;

  /// <summary>Output of TProjectReconciler.Analyze.</summary>
  TReconcileResult = record
    /// <summary>Files used (in closure) but not listed in .dpr/.dproj.</summary>
    Missing: TArray<TReconcileItem>;
    /// <summary>Files listed in .dpr/.dproj but never reached via uses.</summary>
    Extra:   TArray<TReconcileItem>;
    /// <summary>Files in the closure whose base name matches a stale rule.</summary>
    Stale:   TArray<TReconcileItem>;
  end;

  /// <summary>Compares a Delphi project's stated member list against its actual
  /// compile closure and reports Missing / Extra / Stale units.</summary>
  /// <remarks>Not thread-safe; construct and use from a single thread.
  /// Owns nothing after construction (no resources to free).</remarks>
  TProjectReconciler = class
  strict private
    FLibraryRoots: TArray<string>;
    FStaleGlobs:   TArray<string>;

    // Parse the .dpr uses clause; return absolute paths for each listed unit.
    // Uses the same logic as TClosureResolver.ParseDprUses but returns only
    // the file paths (we need the absolute-path set, not unit names).
    procedure CollectDprMembers(const ADprPath: string;
      AMembers: TDictionary<string, string>);

    // Parse the .dproj DCCReference ItemGroup; add absolute paths.
    procedure CollectDprojMembers(const ADprojPath: string;
      AMembers: TDictionary<string, string>);

    // Resolve a path token relative to ABaseDir.
    function ResolveMember(const AToken, ABaseDir: string): string;

    // Build a relative path from ABase to AFile (backslash sep).
    function MakeRelPath(const AFile, ABase: string): string;
  public
    /// <summary>Create a reconciler.
    /// ALibraryRoots: registry library folders used to exclude library files
    /// from the closure (pass TProjectResolver.ResolveLibraryPaths).
    /// AStaleGlobs: extra stale glob patterns (e.g. from manifest indexes.exclude)
    /// applied on top of the built-in heuristics.</summary>
    constructor Create(const ALibraryRoots, AStaleGlobs: TArray<string>);

    /// <summary>Read-only analysis: compare the .dpr/.dproj member list against
    /// the compile closure and return Missing / Extra / Stale sets.
    /// AProjectFile may be a .dpr or .dproj; the sibling file is auto-detected.</summary>
    /// <param name="AProjectFile">Absolute or relative path to .dpr or .dproj.</param>
    /// <returns>TReconcileResult with populated Missing, Extra, and Stale arrays.</returns>
    function Analyze(const AProjectFile: string): TReconcileResult;

    /// <summary>Apply: add Missing units to .dpr uses clause and .dproj
    /// DCCReference ItemGroup after writing .bak backups.
    /// NOT implemented in Task 1 -- raises an exception.</summary>
    /// <param name="AProjectFile">Path to .dpr or .dproj.</param>
    /// <param name="AResult">Result from a prior Analyze call.</param>
    /// <exception cref="Exception">Always raised: not yet implemented (Task 2).</exception>
    procedure Apply(const AProjectFile: string; const AResult: TReconcileResult);
  end;

/// <summary>True when the file's base name (including extension) matches a
/// built-in stale heuristic or any pattern in AExtraGlobs.
/// Built-in patterns (case-insensitive): *_OLD*, * - Copy*, *-Copy*,
/// *BACKUP*, *-bad*, *_20######* (exactly six digits after _20).
/// Matching uses TGlob.Matches on the base name only.</summary>
/// <param name="AFileName">Base file name (e.g. 'uFoo_OLD_20230828.pas').</param>
/// <param name="AExtraGlobs">Additional glob patterns (e.g. manifest excludes).</param>
/// <returns>True if the name looks stale.</returns>
function IsStaleName(const AFileName: string;
  const AExtraGlobs: TArray<string>): Boolean;

implementation

const
  // Built-in stale base-name glob patterns (case-insensitive via TGlob.Matches).
  STALE_GLOBS: array[0..5] of string = (
    '*_OLD*',
    '* - Copy*',
    '*-Copy*',
    '*BACKUP*',
    '*-bad*',
    '*_20######*'
  );

// --------------------------------------------------------------------------

function IsStaleName(const AFileName: string;
  const AExtraGlobs: TArray<string>): Boolean;
var
  BaseName: string;
  P: string;
begin
  BaseName := TPath.GetFileName(AFileName);
  for P in STALE_GLOBS do
    if TGlob.Matches(BaseName, P) then
      Exit(True);
  for P in AExtraGlobs do
    if TGlob.Matches(BaseName, P) then
      Exit(True);
  Result := False;
end;

// --------------------------------------------------------------------------
{ TProjectReconciler }

constructor TProjectReconciler.Create(const ALibraryRoots,
  AStaleGlobs: TArray<string>);
begin
  inherited Create;
  FLibraryRoots := ALibraryRoots;
  FStaleGlobs   := AStaleGlobs;
end;

function TProjectReconciler.ResolveMember(const AToken,
  ABaseDir: string): string;
begin
  if AToken = '' then
  begin
    Result := '';
    Exit;
  end;
  if TPath.IsPathRooted(AToken) then
    Result := TPath.GetFullPath(AToken)
  else
    Result := TPath.GetFullPath(TPath.Combine(ABaseDir, AToken));
end;

function TProjectReconciler.MakeRelPath(const AFile, ABase: string): string;
var
  NormFile, NormBase: string;
begin
  NormFile := TPath.GetFullPath(AFile);
  NormBase := TPath.GetFullPath(ABase);
  if not NormBase.EndsWith('\') then
    NormBase := NormBase + '\';
  if SameText(Copy(NormFile, 1, Length(NormBase)), NormBase) then
    Result := Copy(NormFile, Length(NormBase) + 1, MaxInt)
  else
    Result := NormFile;
end;

procedure TProjectReconciler.CollectDprMembers(const ADprPath: string;
  AMembers: TDictionary<string, string>);
// Parse: uses <name> [in 'path'] [, ...] ;
// Returns: absolute path -> unit-name for each listed unit.
const
  PAT_ITEM = '([A-Za-z_][A-Za-z0-9_.]*)\s*(?:in\s*''([^'']*)''\s*)?';
var
  Content, BaseDir, UsesBlock, Stripped, ItemPat: string;
  UsesPos, SemiPos, I, Len: Integer;
  InBrace: Boolean;
  SB: TStringBuilder;
  Matches: TMatchCollection;
  M: TMatch;
  UName, UFile, Resolved, FileName: string;
  Re: TRegEx;
  UsesMatch: TMatch;
begin
  if not TFile.Exists(ADprPath) then Exit;
  BaseDir := TPath.GetDirectoryName(TPath.GetFullPath(ADprPath));
  Content := TFile.ReadAllText(ADprPath);

  Re := TRegEx.Create('\buses\b', [roIgnoreCase]);
  UsesMatch := Re.Match(Content);
  if not UsesMatch.Success then Exit;

  UsesPos := UsesMatch.Index + UsesMatch.Length - 1;
  SemiPos := Pos(';', Content, UsesPos);
  if SemiPos = 0 then Exit;

  UsesBlock := Copy(Content, UsesPos + 1, SemiPos - UsesPos - 1);

  // Strip { } braces (compiler directives / form names) to avoid
  // picking up identifiers inside them.
  SB := TStringBuilder.Create(Length(UsesBlock));
  try
    I := 1;
    Len := Length(UsesBlock);
    InBrace := False;
    while I <= Len do
    begin
      if InBrace then
      begin
        if UsesBlock[I] = '}' then InBrace := False;
        SB.Append(' ');
      end
      else
      begin
        if UsesBlock[I] = '{' then
        begin
          InBrace := True;
          SB.Append(' ');
        end
        else
          SB.Append(UsesBlock[I]);
      end;
      Inc(I);
    end;
    Stripped := SB.ToString;
  finally
    SB.Free;
  end;

  ItemPat := PAT_ITEM;
  Matches := TRegEx.Matches(Stripped, ItemPat, [roIgnoreCase]);
  for M in Matches do
  begin
    UName := M.Groups[1].Value.Trim;
    if (UName = '') or SameText(UName, 'in') then Continue;

    UFile := '';
    if (M.Groups.Count > 2) and M.Groups[2].Success then
      UFile := M.Groups[2].Value.Trim;

    if UFile <> '' then
    begin
      Resolved := ResolveMember(UFile, BaseDir);
    end
    else
    begin
      // No `in 'path'` -- look for <UnitName>.pas in the project dir.
      FileName := UName + '.pas';
      Resolved := TPath.Combine(BaseDir, FileName);
      if TFile.Exists(Resolved) then
        Resolved := TPath.GetFullPath(Resolved)
      else
        Resolved := '';
    end;

    if (Resolved <> '') and TFile.Exists(Resolved) then
      AMembers.AddOrSetValue(LowerCase(Resolved), UName);
  end;
end;

procedure TProjectReconciler.CollectDprojMembers(const ADprojPath: string;
  AMembers: TDictionary<string, string>);
// Parse <DCCReference Include="some\path.pas"/>
var
  Content, BaseDir: string;
  Pat: string;
  Matches: TMatchCollection;
  M: TMatch;
  RefPath, Resolved: string;
begin
  if not TFile.Exists(ADprojPath) then Exit;
  BaseDir := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));
  Content := TFile.ReadAllText(ADprojPath);

  Pat := '<DCCReference\s+Include="([^"]+\.pas)"';
  Matches := TRegEx.Matches(Content, Pat, [roIgnoreCase]);
  for M in Matches do
  begin
    RefPath := M.Groups[1].Value;
    Resolved := ResolveMember(RefPath, BaseDir);
    if (Resolved <> '') and TFile.Exists(Resolved) then
      AMembers.AddOrSetValue(LowerCase(Resolved),
        TPath.GetFileNameWithoutExtension(Resolved));
  end;
end;

function TProjectReconciler.Analyze(const AProjectFile: string): TReconcileResult;
var
  ProjectAbs, BaseDir, Ext, DprPath, DprojPath: string;
  Members: TDictionary<string, string>;  // lowercase path -> unit name
  Closure: TClosureResolver;
  CR: TClosureResult;
  ClosureSet: TDictionary<string, Integer>;  // lowercase path -> index in CR.Files
  LKey: string;
  I: Integer;
  Item: TReconcileItem;
  MissingList, ExtraList, StaleList: TList<TReconcileItem>;
begin
  ProjectAbs := TPath.GetFullPath(AProjectFile);
  if not TFile.Exists(ProjectAbs) then
    raise Exception.CreateFmt('Project file not found: %s', [ProjectAbs]);

  BaseDir := TPath.GetDirectoryName(ProjectAbs);
  Ext     := LowerCase(TPath.GetExtension(ProjectAbs));

  // Determine .dpr and .dproj paths from whichever was given.
  if Ext = '.dpr' then
  begin
    DprPath  := ProjectAbs;
    DprojPath := TPath.ChangeExtension(ProjectAbs, '.dproj');
  end
  else  // .dproj
  begin
    DprojPath := ProjectAbs;
    DprPath   := TPath.ChangeExtension(ProjectAbs, '.dpr');
  end;

  // ---- Step 1: resolve compile closure ------------------------------------
  Closure := TClosureResolver.Create(FLibraryRoots);
  try
    CR := Closure.Resolve(DprPath, []);
  finally
    Closure.Free;
  end;

  // Build closure index: lowercase-abs-path -> position in CR.Files.
  ClosureSet := TDictionary<string, Integer>.Create;
  try
    for I := 0 to High(CR.Files) do
      ClosureSet.AddOrSetValue(LowerCase(CR.Files[I]), I);

    // ---- Step 2: collect listed members ------------------------------------
    Members := TDictionary<string, string>.Create;
    try
      CollectDprMembers(DprPath, Members);
      CollectDprojMembers(DprojPath, Members);

      MissingList := TList<TReconcileItem>.Create;
      ExtraList   := TList<TReconcileItem>.Create;
      StaleList   := TList<TReconcileItem>.Create;
      try
        // ---- Step 3: Missing = closure files not in Members ----------------
        for I := 0 to High(CR.Files) do
        begin
          LKey := LowerCase(CR.Files[I]);
          if not Members.ContainsKey(LKey) then
          begin
            Item.Kind     := rkMissing;
            Item.UnitName := TPath.GetFileNameWithoutExtension(CR.Files[I]);
            Item.FilePath := CR.Files[I];
            Item.RelPath  := MakeRelPath(CR.Files[I], BaseDir);
            Item.UsedBy   := CR.UsedBy[I];
            if SameText(Item.UsedBy, '<project>') then
              Item.UsedBy := '';
            MissingList.Add(Item);
          end;
        end;

        // ---- Step 4: Extra = Members not in ClosureSet ---------------------
        for var Pair in Members do
        begin
          if not ClosureSet.ContainsKey(Pair.Key) then
          begin
            Item.Kind     := rkExtra;
            Item.UnitName := Pair.Value;
            Item.FilePath := '';
            // Reconstruct abs path: the key is already lowercase; find original
            // by trying to look it up from disk (members are real files).
            // Since Members stores lowercase key, we need the original-case path.
            // Workaround: rebuild from the lower-case key via TPath.GetFullPath.
            // The casing may be wrong on case-preserving FS but that's fine for display.
            Item.FilePath := TPath.GetFullPath(Pair.Key);
            Item.RelPath  := MakeRelPath(Item.FilePath, BaseDir);
            Item.UsedBy   := '';
            ExtraList.Add(Item);
          end;
        end;

        // ---- Step 5: Stale = closure files matching stale patterns ---------
        for I := 0 to High(CR.Files) do
        begin
          if IsStaleName(TPath.GetFileName(CR.Files[I]), FStaleGlobs) then
          begin
            Item.Kind     := rkStale;
            Item.UnitName := TPath.GetFileNameWithoutExtension(CR.Files[I]);
            Item.FilePath := CR.Files[I];
            Item.RelPath  := MakeRelPath(CR.Files[I], BaseDir);
            Item.UsedBy   := CR.UsedBy[I];
            if SameText(Item.UsedBy, '<project>') then
              Item.UsedBy := '';
            StaleList.Add(Item);
          end;
        end;

        Result.Missing := MissingList.ToArray;
        Result.Extra   := ExtraList.ToArray;
        Result.Stale   := StaleList.ToArray;
      finally
        StaleList.Free;
        ExtraList.Free;
        MissingList.Free;
      end;
    finally
      Members.Free;
    end;
  finally
    ClosureSet.Free;
  end;
end;

procedure TProjectReconciler.Apply(const AProjectFile: string;
  const AResult: TReconcileResult);
begin
  raise Exception.Create(
    'TProjectReconciler.Apply not yet implemented (Task 2)');
end;

end.
