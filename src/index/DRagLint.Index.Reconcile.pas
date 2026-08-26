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
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , System  .Generics.Collections
  , DRagLint.Index   .Closure
  , DRagLint.Index   .Glob
  ;

type
  /// <summary>Identifies which reconcile set an item belongs to.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.Reconcile.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TReconcileKind = (rkMissing, rkExtra, rkStale);

  /// <summary>One item in a reconcile report.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.Index.Reconcile.TProjectReconciler.Analyze (DRagLint.Index.Reconcile.pas), DRagLint.Index.Reconcile.EditDpr (DRagLint.Index.Reconcile.pas), DRagLint.Index.Reconcile.EditDproj (DRagLint.Index.Reconcile.pas), DRagLint.Index.Reconcile.TProjectReconciler.Apply (DRagLint.Index.Reconcile.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Reconcile</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TReconcileItem = record
    /// <summary>Kind of finding: missing / extra / stale.</summary>
    Kind: TReconcileKind;
    /// <summary>Pascal unit name (without extension).</summary>
    UnitName: string;
    /// <summary>Absolute path to the .pas file.</summary>
    FilePath: string;
    /// <summary>Path relative to the project directory (backslash-separated).</summary>
    RelPath: string;
    /// <summary>Name of the unit that pulls this file in via uses.
    /// Empty for project-direct (.dpr/dproj seed) entries.
    /// '&lt;project&gt;' if seeded from the project member list.</summary>
    UsedBy: string;
  end;

  /// <summary>Output of TProjectReconciler.Analyze.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), declaration (DRagLint.Index.Reconcile.pas), DRagLint.Index.Reconcile.TProjectReconciler.Analyze (DRagLint.Index.Reconcile.pas), DRagLint.Index.Reconcile.TProjectReconciler.Apply (DRagLint.Index.Reconcile.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Reconcile</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TReconcileResult = record
    /// <summary>Files used (in closure) but not listed in .dpr/.dproj.</summary>
    Missing: TArray<TReconcileItem>;
    /// <summary>Files listed in .dpr/.dproj but never reached via uses.</summary>
    Extra: TArray<TReconcileItem>;
    /// <summary>Files in the closure whose base name matches a stale rule.</summary>
    Stale: TArray<TReconcileItem>;
    /// <summary>Project-owned compile closure -- absolute .pas paths, library-excluded.
    /// A snapshot of TClosureResult.Files as computed by Analyze; not filtered
    /// or transformed further.</summary>
    ClosureFiles: TArray<string>;
  end;

  /// <summary>Compares a Delphi project's stated member list against its actual
  /// compile closure and reports Missing / Extra / Stale units.</summary>
  /// <remarks>
  /// Not thread-safe; construct and use from a single thread.
  /// Owns nothing after construction (no resources to free).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProjectReconciler = class
    strict private
      FLibraryRoots: TArray<string>;
      FStaleGlobs  : TArray<string>;

      // Parse the .dpr uses clause; return absolute paths for each listed unit.
      // Uses the same logic as TClosureResolver.ParseDprUses but returns only
      // the file paths (we need the absolute-path set, not unit names).
      /// <summary><!-- drag-lint:auto -->Parse the .dpr uses clause; return absolute
      /// paths for each listed unit. Uses the same logic as TClosureResolver.ParseDprUses
      /// but returns only the file paths (we need the absolute-path set, not unit names).</summary>
      /// <param name="ADprPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AMembers"><!-- drag-lint:auto type -->TDictionary&lt;string, string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Reconcile.TProjectReconciler.Analyze (DRagLint.Index.Reconcile.pas)</para>
      /// <para>Calls: Copy, DRagLint.Index.Reconcile.TProjectReconciler.ResolveMember, LowerCase, Pos, SameText</para>
      /// <para>Complexity: 16 (cyclomatic, outer body), 95 lines (full implementation)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.ResolveMember"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Analyze"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Apply"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprojMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure CollectDprMembers(const ADprPath: string; AMembers: TDictionary<string, string>);

      // Parse the .dproj DCCReference ItemGroup; add absolute paths.
      /// <summary><!-- drag-lint:auto -->Parse the .dproj DCCReference ItemGroup; add
      /// absolute paths.</summary>
      /// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AMembers"><!-- drag-lint:auto type -->TDictionary&lt;string, string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Reconcile.TProjectReconciler.Analyze (DRagLint.Index.Reconcile.pas)</para>
      /// <para>Calls: DRagLint.Index.Reconcile.TProjectReconciler.ResolveMember, LowerCase</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.ResolveMember"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Analyze"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Apply"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure CollectDprojMembers(const ADprojPath: string; AMembers: TDictionary<string, string>);

      // Resolve a path token relative to ABaseDir.
      /// <summary><!-- drag-lint:auto -->Resolve a path token relative to ABaseDir.</summary>
      /// <param name="AToken"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ABaseDir"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '';
      /// TPath.GetFullPath(AToken); TPath.GetFullPath(TPath.Combine(ABaseDir, AToken)).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Reconcile.TProjectReconciler.CollectDprMembers (DRagLint.Index.Reconcile.pas), DRagLint.Index.Reconcile.TProjectReconciler.CollectDprojMembers (DRagLint.Index.Reconcile.pas)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Analyze"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Apply"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprojMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveMember(const AToken, ABaseDir: string): string;

      // Build a relative path from ABase to AFile (backslash sep).
      /// <summary><!-- drag-lint:auto -->Build a relative path from ABase to AFile
      /// (backslash sep).</summary>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ABase"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: Copy(NormFile,
      /// Length(NormBase) + 1, MaxInt); NormFile.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Reconcile.TProjectReconciler.Analyze (DRagLint.Index.Reconcile.pas), DRagLint.Index.Reconcile.TProjectReconciler.Apply (DRagLint.Index.Reconcile.pas)</para>
      /// <para>Calls: Copy, SameText</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Analyze"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Apply"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprojMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function MakeRelPath(const AFile, ABase: string): string;
    public
      /// <summary>Create a reconciler.
      /// ALibraryRoots: registry library folders used to exclude library files
      /// from the closure (pass TProjectResolver.ResolveLibraryPaths).
      /// AStaleGlobs: extra stale glob patterns (e.g. from manifest indexes.exclude)
      /// applied on top of the built-in heuristics.</summary>
      /// <param name="ALibraryRoots"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <param name="AStaleGlobs"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas)</para>
      /// <para>constructor</para>
      /// <para>Writes: FLibraryRoots, FStaleGlobs</para>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Analyze"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Apply"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprojMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.MakeRelPath"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ALibraryRoots, AStaleGlobs: TArray<string>);

      /// <summary>Read-only analysis: compare the .dpr/.dproj member list against
      /// the compile closure and return Missing / Extra / Stale sets.
      /// AProjectFile may be a .dpr or .dproj; the sibling file is auto-detected.</summary>
      /// <param name="AProjectFile">Absolute or relative path to .dpr or .dproj.</param>
      /// <returns>TReconcileResult with populated Missing, Extra, and Stale arrays.</returns>
      /// <exception cref="Exception"><!-- drag-lint:auto --></exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Index.Closure.TClosureResolver.Create, DRagLint.Index.Closure.TClosureResolver.Resolve, DRagLint.Index.Reconcile.IsStaleName, DRagLint.Index.Reconcile.TProjectReconciler.CollectDprMembers, DRagLint.Index.Reconcile.TProjectReconciler.CollectDprojMembers, DRagLint.Index.Reconcile.TProjectReconciler.MakeRelPath, LowerCase, SameText</para>
      /// <para>Complexity: 11 (cyclomatic, outer body), 125 lines (full implementation)</para>
      /// <para>Reads: FLibraryRoots, FStaleGlobs</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Resolve"/>
      /// <seealso cref="DRagLint.Index.Reconcile.IsStaleName"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprMembers"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprojMembers"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Analyze(const AProjectFile: string): TReconcileResult;

      /// <summary>Apply: add Missing units to .dpr uses clause and .dproj
      /// DCCReference ItemGroup after writing .bak backups.
      /// Backs up .dpr -> .dpr.bak and .dproj -> .dproj.bak before writing.
      /// Inserts only items that are Missing and not already present (idempotent).
      /// Extra and Stale entries are never removed.
      /// Re-running after Apply reports 0 Missing.</summary>
      /// <param name="AProjectFile">Path to .dpr or .dproj.</param>
      /// <param name="AResult">Result from a prior Analyze call.</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Index.Reconcile.EditDpr, DRagLint.Index.Reconcile.EditDproj, DRagLint.Index.Reconcile.TProjectReconciler.MakeRelPath, LowerCase</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Reconcile.EditDpr"/>
      /// <seealso cref="DRagLint.Index.Reconcile.EditDproj"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.MakeRelPath"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.Analyze"/>
      /// <seealso cref="DRagLint.Index.Reconcile.TProjectReconciler.CollectDprMembers"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Apply(const AProjectFile: string; const AResult: TReconcileResult);
  end;

/// <summary>True when the file's base name (including extension) matches a
/// built-in stale heuristic or any pattern in AExtraGlobs.
/// Built-in glob patterns (case-insensitive): *_OLD*, * - Copy*, *-Copy*,
/// *BACKUP*, *-bad*. Additionally detects a date-stamp suffix: underscore
/// followed by 8 digits (e.g. _20230828) via TRegEx (replaces the old
/// non-functional *_20######* glob -- TGlob treats # as a literal).
/// Matching uses TGlob.Matches + TRegEx on the base name only.</summary>
/// <param name="AFileName">Base file name (e.g. 'uFoo_OLD_20230828.pas').</param>
/// <param name="AExtraGlobs">Additional glob patterns (e.g. manifest excludes).</param>
/// <returns>True if the name looks stale.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Index.Reconcile.TProjectReconciler.Analyze (DRagLint.Index.Reconcile.pas)</para>
/// <para>Calls: DRagLint.Index.Glob.TGlob.Matches</para>
/// <para>Returns: False</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Index.Glob.TGlob.Matches"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsStaleName(const AFileName: string; const AExtraGlobs: TArray<string>): Boolean;

implementation

const
  // Built-in stale base-name glob patterns (case-insensitive via TGlob.Matches).
  // Note: date-stamp detection (_YYYYMMDD) is handled separately by TRegEx
  // in IsStaleName; the dead *_20######* glob has been removed.
  STALE_GLOBS: array[0..4] of string = ( '*_OLD*', '* - Copy*', '*-Copy*', '*BACKUP*', '*-bad*' );

  // --------------------------------------------------------------------------

function IsStaleName(const AFileName: string; const AExtraGlobs: TArray<string>): Boolean;
var
  BaseName: string;
  P       : string;
begin
  BaseName:= TPath.GetFileName(AFileName);
  for P in STALE_GLOBS do
    if TGlob.Matches(BaseName, P) then Exit(True);
  // Date-stamp heuristic: base name contains _ followed by 8 digits
  // (e.g. uData_20240101.pas).  TGlob does not support # as digit-class
  // so we use a regex here instead of the dead *_20######* glob.
  if TRegEx.IsMatch(BaseName, '_\d{8}', [roIgnoreCase]) then Exit(True);
  for P in AExtraGlobs do
    if TGlob.Matches(BaseName, P) then Exit(True);
  Result:= False;
end;

// --------------------------------------------------------------------------
{ TProjectReconciler }

constructor TProjectReconciler.Create(const ALibraryRoots, AStaleGlobs: TArray<string>);
begin
  inherited Create;
  FLibraryRoots:= ALibraryRoots;
  FStaleGlobs  := AStaleGlobs;
end;

function TProjectReconciler.ResolveMember(const AToken, ABaseDir: string): string;
begin
  if AToken = '' then
  begin
    Result:= '';
    Exit;
  end;
  if TPath.IsPathRooted(AToken) then Result:= TPath.GetFullPath(AToken)
  else Result:= TPath.GetFullPath(TPath.Combine(ABaseDir, AToken));
end;

function TProjectReconciler.MakeRelPath(const AFile, ABase: string): string;
var
  NormFile: string;
  NormBase: string;
begin
  NormFile:= TPath.GetFullPath(AFile);
  NormBase:= TPath.GetFullPath(ABase);
  if not NormBase.EndsWith('\') then NormBase:= NormBase + '\';
  if SameText(Copy(NormFile, 1, Length(NormBase)), NormBase) then Exit(Copy(NormFile, Length(NormBase) + 1, MaxInt));
  { NOT under the project folder -- so prefix-stripping cannot express it and
    this used to fall back to the ABSOLUTE path. That is not a cosmetic
    difference: --apply writes this straight into the .dpr and .dproj, both
    CHECKED IN, and all 101 existing entries here are relative. Applying it once
    put C:\Projects\Delphi-RAG-lint\... into both files, which breaks on any
    other machine or checkout location -- and drag-lint's own
    hardcoded-absolute-path rule promptly flagged the .dpr lines.

    ExtractRelativePath is the RTL answer and walks up with '..' properly. It
    returns the absolute path unchanged when the two are on different DRIVES,
    which is correct: there is no relative path across volumes. }
  Result:= ExtractRelativePath(NormBase, NormFile);
end;

procedure TProjectReconciler.CollectDprMembers(const ADprPath: string; AMembers: TDictionary<string, string>);
// Parse: uses <name> [in 'path'] [, ...] ;
// Returns: absolute path -> unit-name for each listed unit.
const
  PAT_ITEM = '([A-Za-z_][A-Za-z0-9_.]*)\s*(?:in\s*''([^'']*)''\s*)?';
var
  Content  : string          ;
  BaseDir  : string          ;
  UsesBlock: string          ;
  Stripped : string          ;
  ItemPat  : string          ;
  UsesPos  : Integer         ;
  SemiPos  : Integer         ;
  I        : Integer         ;
  Len      : Integer         ;
  InBrace  : Boolean         ;
  SB       : TStringBuilder  ;
  Matches  : TMatchCollection;
  M        : TMatch          ;
  UName    : string          ;
  UFile    : string          ;
  Resolved : string          ;
  FileName : string          ;
  Re       : TRegEx          ;
  UsesMatch: TMatch          ;
begin
  if not TFile.Exists(ADprPath) then Exit;
  BaseDir:= TPath.GetDirectoryName(TPath.GetFullPath(ADprPath));
  Content:= TFile.ReadAllText(ADprPath);

  Re:= TRegEx.Create('\buses\b', [roIgnoreCase]);
  UsesMatch:= Re.Match(Content);
  if not UsesMatch.Success then Exit;

  UsesPos:= UsesMatch.Index + UsesMatch.Length - 1;
  SemiPos:= Pos(';', Content, UsesPos);
  if SemiPos = 0 then Exit;

  UsesBlock:= Copy(Content, UsesPos + 1, SemiPos - UsesPos - 1);

  // Strip { } braces (compiler directives / form names) to avoid
  // picking up identifiers inside them.
  SB:= TStringBuilder.Create(Length(UsesBlock));
  try
    I:= 1;
    Len:= Length(UsesBlock);
    InBrace:= False;
    while I <= Len do
    begin
      if InBrace then
      begin
        if UsesBlock[I] = '}' then InBrace:= False;
        SB.Append(' ');
      end
      else
      begin
        if UsesBlock[I] = '{' then
        begin
          InBrace:= True;
          SB.Append(' ');
        end
        else SB.Append(UsesBlock[I]);
      end;
      Inc(I);
    end; // while
    Stripped:= SB.ToString;
  finally
    SB.Free;
  end; // try

  { Same collapse as TClosureResolver.ExtractUses, and for the same reason:
    whitespace around the dot of a qualified unit name is insignificant, and
    PAT_ITEM's identifier class stops at a space, so `DRagLint.Doc   .Batch`
    parses as two junk tokens instead of one unit. A .dpr is normally
    IDE-generated with conventional spacing, so this is robustness rather than
    an observed failure here -- but the two parsers are meant to agree (this
    one's header says it uses the same logic), and a hand-aligned .dpr must not
    make them disagree. Strings are already stripped above, so no `in '...'`
    path is touched. }
  Stripped:= TRegEx.Replace(Stripped, '\s*\.\s*', '.');

  ItemPat:= PAT_ITEM;
  Matches:= TRegEx.Matches(Stripped, ItemPat, [roIgnoreCase]);
  for M in Matches do
  begin
    UName:= M.Groups[1].Value.Trim;
    if (UName = '') or SameText(UName, 'in') then Continue;

    UFile:= '';
    if (M.Groups.Count > 2) and M.Groups[2].Success then UFile:= M.Groups[2].Value.Trim;

    if UFile <> '' then
    begin
      Resolved:= ResolveMember(UFile, BaseDir);
    end
    else
    begin
      // No `in 'path'` -- look for <UnitName>.pas in the project dir.
      FileName:= UName + '.pas';
      Resolved:= TPath.Combine(BaseDir, FileName);
      if TFile.Exists(Resolved) then Resolved:= TPath.GetFullPath(Resolved)
      else Resolved:= '';
    end;

    if (Resolved <> '') and TFile.Exists(Resolved) then AMembers.AddOrSetValue(LowerCase(Resolved), UName);
  end; // for
end; // procedure

procedure TProjectReconciler.CollectDprojMembers(const ADprojPath: string; AMembers: TDictionary<string, string>);
// Parse <DCCReference Include="some\path.pas"/>
var
  Content : string          ;
  BaseDir : string          ;
  Pat     : string          ;
  Matches : TMatchCollection;
  M       : TMatch          ;
  RefPath : string          ;
  Resolved: string          ;
begin
  if not TFile.Exists(ADprojPath) then Exit;
  BaseDir:= TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));
  Content:= TFile.ReadAllText(ADprojPath);

  Pat:= '<DCCReference\s+Include="([^"]+\.pas)"';
  Matches:= TRegEx.Matches(Content, Pat, [roIgnoreCase]);
  for M in Matches do
  begin
    RefPath:= M.Groups[1].Value;
    Resolved:= ResolveMember(RefPath, BaseDir);
    if (Resolved <> '') and TFile.Exists(Resolved) then AMembers.AddOrSetValue(LowerCase(Resolved), TPath.GetFileNameWithoutExtension(Resolved));
  end;
end;

function TProjectReconciler.Analyze(const AProjectFile: string): TReconcileResult;
var
  ProjectAbs : string                      ;
  BaseDir    : string                      ;
  Ext        : string                      ;
  DprPath    : string                      ;
  DprojPath  : string                      ;
  Members    : TDictionary<string, string> ; // lowercase path -> unit name
  Closure    : TClosureResolver            ;
  CR         : TClosureResult              ;
  ClosureSet : TDictionary<string, Integer>; // lowercase path -> index in CR.Files
  LKey       : string                      ;
  I          : Integer                     ;
  Item       : TReconcileItem              ;
  MissingList: TList<TReconcileItem>       ;
  ExtraList  : TList<TReconcileItem>       ;
  StaleList  : TList<TReconcileItem>       ;
begin
  ProjectAbs:= TPath.GetFullPath(AProjectFile);
  if not TFile.Exists(ProjectAbs) then raise Exception.CreateFmt('Project file not found: %s', [ProjectAbs]);

  BaseDir:= TPath.GetDirectoryName(ProjectAbs);
  Ext:= LowerCase(TPath.GetExtension(ProjectAbs));

  // Determine .dpr and .dproj paths from whichever was given.
  if Ext = '.dpr' then
  begin
    DprPath:= ProjectAbs;
    DprojPath:= TPath.ChangeExtension(ProjectAbs, '.dproj');
  end
  else // .dproj
  begin
    DprojPath:= ProjectAbs;
    DprPath:= TPath.ChangeExtension(ProjectAbs, '.dpr');
  end;

  // ---- Step 1: resolve compile closure ------------------------------------
  Closure:= TClosureResolver.Create(FLibraryRoots);
  try
    CR:= Closure.Resolve(DprPath, []);
  finally
    Closure.Free;
  end;

  // Build closure index: lowercase-abs-path -> position in CR.Files.
  ClosureSet:= TDictionary<string, Integer>.Create;
  try
    for I:= 0 to High(CR.Files) do ClosureSet.AddOrSetValue(LowerCase(CR.Files[I]), I);

    // ---- Step 2: collect listed members ------------------------------------
    Members:= TDictionary<string, string>.Create;
    try
      CollectDprMembers  (DprPath  , Members);
      CollectDprojMembers(DprojPath, Members);

      MissingList:= TList<TReconcileItem>.Create;
      ExtraList  := TList<TReconcileItem>.Create;
      StaleList  := TList<TReconcileItem>.Create;
      try
        // ---- Step 3: Missing = closure files not in Members ----------------
        for I:= 0 to High(CR.Files) do
        begin
          LKey:= LowerCase(CR.Files[I]);
          if not Members.ContainsKey(LKey) then
          begin
            Item.Kind:= rkMissing;
            Item.UnitName:= TPath.GetFileNameWithoutExtension(CR.Files[I]);
            Item.FilePath:= CR.Files[I];
            Item.RelPath:= MakeRelPath(CR.Files[I], BaseDir);
            Item.UsedBy:= CR.UsedBy[I];
            if SameText(Item.UsedBy, '<project>') then Item.UsedBy:= '';
            MissingList.Add(Item);
          end;
        end;

        // ---- Step 4: Extra = Members not in ClosureSet ---------------------
        for var Pair in Members do
        begin
          if not ClosureSet.ContainsKey(Pair.Key) then
          begin
            Item.Kind:= rkExtra;
            Item.UnitName:= Pair.Value;
            Item.FilePath:= '';
            // Reconstruct abs path: the key is already lowercase; find original
            // by trying to look it up from disk (members are real files).
            // Since Members stores lowercase key, we need the original-case path.
            // Workaround: rebuild from the lower-case key via TPath.GetFullPath.
            // The casing may be wrong on case-preserving FS but that's fine for display.
            Item.FilePath:= TPath.GetFullPath(Pair.Key);
            Item.RelPath:= MakeRelPath(Item.FilePath, BaseDir);
            Item.UsedBy:= '';
            ExtraList.Add(Item);
          end;
        end; // for

        // ---- Step 5: Stale = closure files matching stale patterns ---------
        for I:= 0 to High(CR.Files) do
        begin
          if IsStaleName(TPath.GetFileName(CR.Files[I]), FStaleGlobs) then
          begin
            Item.Kind:= rkStale;
            Item.UnitName:= TPath.GetFileNameWithoutExtension(CR.Files[I]);
            Item.FilePath:= CR.Files[I];
            Item.RelPath:= MakeRelPath(CR.Files[I], BaseDir);
            Item.UsedBy:= CR.UsedBy[I];
            if SameText(Item.UsedBy, '<project>') then Item.UsedBy:= '';
            StaleList.Add(Item);
          end;
        end;

        Result.Missing:= MissingList.ToArray;
        Result.Extra  := ExtraList  .ToArray;
        Result.Stale  := StaleList  .ToArray;
        Result.ClosureFiles:= CR.Files;
      finally
        StaleList.Free;
        ExtraList.Free;
        MissingList.Free;
      end; // try
    finally
      Members.Free;
    end; // try
  finally
    ClosureSet.Free;
  end; // try
end; // function

// --------------------------------------------------------------------------
// Apply helpers -- .dpr uses-clause edit
// --------------------------------------------------------------------------

// Return the lowercase unit name of a missing item: used to detect duplicates.
// Walk through existing text to see if a unit already appears in the clause.
function UnitAlreadyInClause(const AClause, AUnitName: string): Boolean;
var
  Re: TRegEx;
begin
  // Match the unit name as a word boundary followed optionally by `in '...'`.
  Re:= TRegEx.Create( '\b' + TRegEx.Escape(AUnitName) + '\b', [roIgnoreCase]);
  Result:= Re.IsMatch(AClause);
end;

// Build the insertion snippet: ,<CRLF>  <UnitName> in '<RelPath>'
function MakeUseEntry(const AUnitName, ARelPath: string): string;
begin
  Result:= ',' + #13#10 + '  ' + AUnitName + ' in ''' + ARelPath + '''';
end;

// BlankCommentsAndStrings: return a length-preserving copy of AText where
// all comment and string-literal content is replaced by spaces.  Handles
// {..} brace comments, (*...*) paren-star comments, // line comments, and
// single-quoted string literals ('' escape handled).  Uses the same algorithm
// as TClosureResolver.StripCommentsAndStrings; extracted here so EditDpr can
// locate positions in the blanked copy and apply them to the original text
// without any position shift (blank = same length as original).
function BlankCommentsAndStrings(const AText: string): string;
var
  I       : Integer       ;
  Len     : Integer       ;
  C       : Char          ;
  InBrace : Boolean       ;
  InParen : Boolean       ;
  InString: Boolean       ;
  SB      : TStringBuilder;
begin
  SB:= TStringBuilder.Create(Length(AText));
  try
    I:= 1;
    Len:= Length(AText);
    InBrace := False;
    InParen := False;
    InString:= False;
    while I <= Len do
    begin
      C:= AText[I];
      if InString then
      begin
        if C = '''' then
        begin
          if (I < Len) and (AText[I + 1] = '''') then
          begin
            SB.Append('  ');
            Inc(I, 2);
            Continue;
          end;
          InString:= False;
          SB.Append(' ');
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end; // if
      if InBrace then
      begin
        if C = '}' then
        begin
          InBrace:= False;
          SB.Append(' ');
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if InParen then
      begin
        if (C = '*') and (I < Len) and (AText[I + 1] = ')') then
        begin
          InParen:= False;
          SB.Append('  ');
          Inc(I, 2);
          Continue;
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end;
      // Not inside any comment or string.
      if C = '''' then
      begin
        InString:= True;
        SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if C = '{' then
      begin
        InBrace:= True;
        SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if (C = '(') and (I < Len) and (AText[I + 1] = '*') then
      begin
        InParen:= True;
        SB.Append('  ');
        Inc(I, 2);
        Continue;
      end;
      if (C = '/') and (I < Len) and (AText[I + 1] = '/') then
      begin
        while (I <= Len) and (AText[I] <> #10) do
        begin
          SB.Append(' ');
          Inc(I);
        end;
        Continue;
      end;
      SB.Append(C);
      Inc(I);
    end; // while
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

// Edit the .dpr: locate the first uses clause and append missing entries
// before the closing ';'.
// Uses a length-preserving blanked copy to find positions so that brace
// comments containing ';' (e.g. uMain in 'uMain.pas' {Form: TFoo; aux})
// do not fool the semicolon search.  Positions from the blanked copy are
// applied directly to the original content (same length -> same indexes).
procedure EditDpr(const ADprPath: string; const AMissing: TArray<TReconcileItem>);
var
  Content  : string        ;
  Blanked  : string        ;
  UsesBlock: string        ;
  Before   : string        ;
  After    : string        ;
  Re       : TRegEx        ;
  UsesMatch: TMatch        ;
  UsesPos  : Integer       ;
  SemiPos  : Integer       ;
  Item     : TReconcileItem;
  Additions: string        ;
begin
  if Length(AMissing) = 0 then Exit;
  Content:= TFile.ReadAllText(ADprPath);

  // Blank comments/strings first; all position searches work on the blanked
  // copy, then applied to the original (identical byte-length).
  Blanked:= BlankCommentsAndStrings(Content);

  // Find the first 'uses' keyword in the blanked copy.
  Re:= TRegEx.Create('\buses\b', [roIgnoreCase]);
  UsesMatch:= Re.Match(Blanked);
  if not UsesMatch.Success then Exit;

  // The character index (1-based) just after the 'uses' keyword.
  UsesPos:= UsesMatch.Index + UsesMatch.Length - 1; // 1-based end of 'uses'

  // Find the terminating ';' of the uses clause in the BLANKED copy.
  // This skips any semicolon that appears inside a brace comment or string.
  SemiPos:= Pos(';', Blanked, UsesPos + 1);
  if SemiPos = 0 then Exit;

  // Extract clause body from the ORIGINAL text for the idempotency guard
  // (positions are the same because blanking is length-preserving).
  UsesBlock:= Copy(Content, UsesPos + 1, SemiPos - UsesPos - 1);

  // Build additions string.
  Additions:= '';
  for Item in AMissing do
    if not UnitAlreadyInClause(UsesBlock, Item.UnitName) then Additions:= Additions + MakeUseEntry(Item.UnitName, Item.RelPath);

  if Additions = '' then Exit;

  { INSERT BEFORE THE LAST ENTRY, not before the ';'.

    A .dpr uses clause ends with the MAIN unit, and the clause order is the
    INITIALIZATION order, so the main unit belongs last -- everything it uses
    should have initialized before it. Splicing at the ';' appended after the
    main unit and quietly demoted it. Harmless the day it was found (neither
    added unit had an initialization section, checked) but that is luck, not
    design, and the cost of getting it wrong is a startup-order bug that
    reproduces nowhere else.

    The last ',' in the BLANKED clause is the start of that final entry, and
    blanking is length-preserving so the index applies to the original text.
    Additions already begins with ',', so splicing there yields
    "...prev, <new entries>, MainUnit;". A single-unit clause has no comma; then
    there is no last entry to protect and the old ';' position is correct. }
  var LastComma: Integer:= 0;
  for var K: Integer:= SemiPos - 1 downto UsesPos + 1 do
    if Blanked[K] = ',' then begin LastComma:= K; Break; end;

  var SplicePos: Integer;
  if LastComma > 0 then SplicePos:= LastComma else SplicePos:= SemiPos;

  // Splice into the ORIGINAL content at the positions found in the blanked copy.
  Before:= Copy(Content, 1, SplicePos - 1);
  After:= Copy(Content, SplicePos, MaxInt); // the ',' of the last entry, or the ';'
  Content:= Before + Additions + After;

  TFile.WriteAllText(ADprPath, Content);
end; // procedure

// --------------------------------------------------------------------------
// Apply helpers -- .dproj DCCReference ItemGroup edit
// --------------------------------------------------------------------------

// Return True if the .dproj already contains a DCCReference for this RelPath
// (case-insensitive file name comparison).
function RefAlreadyInDproj(const AContent, ARelPath: string): Boolean;
var
  Re: TRegEx;
begin
  Re:= TRegEx.Create( 'DCCReference\s+Include="' + TRegEx.Escape(ARelPath) + '"', [roIgnoreCase]);
  Result:= Re.IsMatch(AContent);
end;

// Edit the .dproj: insert DCCReference entries into the existing ItemGroup
// (the one already containing <DCCReference>), or create a new ItemGroup
// before </Project>.
procedure EditDproj(const ADprojPath: string; const AMissing: TArray<TReconcileItem>);
var
  Content   : string        ;
  Snippet   : string        ;
  GroupClose: string        ;
  ProjClose : string        ;
  InsertPos : Integer       ;
  Re        : TRegEx        ;
  M         : TMatch        ;
  Item      : TReconcileItem;
begin
  if Length(AMissing) = 0 then Exit;
  Content:= TFile.ReadAllText(ADprojPath);

  // Build the snippet of new <DCCReference> lines (one per missing item,
  // only those not already present).
  Snippet:= '';
  for Item in AMissing do
    if not RefAlreadyInDproj(Content, Item.RelPath) then Snippet:= Snippet + #13#10 + '    <DCCReference Include="' + Item.RelPath + '"/>';

  if Snippet = '' then Exit;

  // Case 1: an existing DCCReference ItemGroup exists.
  // Find </ItemGroup> that closes the group containing <DCCReference.
  Re:= TRegEx.Create( '<DCCReference[\s\S]*?</ItemGroup>', [roIgnoreCase, roMultiLine, roSingleLine]);
  M:= Re.Match(Content);
  if M.Success then
  begin
    // Insert just before the closing </ItemGroup> of that match.
    // M.Index + M.Length - 1 points at the last char of </ItemGroup>.
    // Find the position of </ItemGroup> within the match.
    GroupClose:= '</ItemGroup>';
    InsertPos:= M.Index + M.Length - Length(GroupClose);
    // Validate: the text at InsertPos should be the closing tag.
    if SameText(Copy(Content, InsertPos, Length(GroupClose)), GroupClose) then
    begin
      Content:= Copy(Content, 1, InsertPos - 1) + Snippet + #13#10 + '  ' + Copy(Content, InsertPos, MaxInt);
      TFile.WriteAllText(ADprojPath, Content);
      Exit;
    end;
  end; // if

  // Case 2: no existing DCCReference ItemGroup -- insert before </Project>.
  ProjClose:= '</Project>';
  InsertPos:= Pos(ProjClose, Content);
  if InsertPos > 0 then
  begin
    Content:= Copy(Content, 1, InsertPos - 1) + '  <ItemGroup>' + Snippet + #13#10 + '  </ItemGroup>' + #13#10 + Copy(Content, InsertPos, MaxInt);
    TFile.WriteAllText(ADprojPath, Content);
  end;
end; // procedure

// --------------------------------------------------------------------------

/// <summary>Apply: add Missing units to .dpr uses clause and .dproj
/// DCCReference ItemGroup after writing .bak backups.
/// Backs up .dpr->.dpr.bak and .dproj->.dproj.bak (overwrite).
/// Inserts only items that are Missing and not already present (idempotent).
/// Extra/Stale entries are never removed.</summary>
/// <param name="AProjectFile">Path to .dpr or .dproj.</param>
/// <param name="AResult">Result from a prior Analyze call.</param>
procedure TProjectReconciler.Apply(const AProjectFile: string; const AResult: TReconcileResult);
var
  ProjectAbs       : string                ;
  Ext              : string                ;
  DprPath          : string                ;
  DprojPath        : string                ;
  ProjectDir       : string                ;
  Item             : TReconcileItem        ;
  ProjectRelMissing: TArray<TReconcileItem>;
  I                : Integer               ;
begin
  if Length(AResult.Missing) = 0 then Exit;

  ProjectAbs:= TPath.GetFullPath(AProjectFile);
  Ext:= LowerCase(TPath.GetExtension(ProjectAbs));
  ProjectDir:= TPath.GetDirectoryName(ProjectAbs);

  if Ext = '.dpr' then
  begin
    DprPath:= ProjectAbs;
    DprojPath:= TPath.ChangeExtension(ProjectAbs, '.dproj');
  end
  else
  begin
    DprojPath:= ProjectAbs;
    DprPath:= TPath.ChangeExtension(ProjectAbs, '.dpr');
  end;

  // -- Backups (overwrite any existing .bak) ---------------------------------
  if TFile.Exists(DprPath  ) then TFile.Copy(DprPath  , DprPath   + '.bak', True);
  if TFile.Exists(DprojPath) then TFile.Copy(DprojPath, DprojPath + '.bak', True);

  // -- Rebuild Missing list with RelPath relative to project dir (backslash) -
  SetLength(ProjectRelMissing, Length(AResult.Missing));
  for I:= 0 to High(AResult.Missing) do
  begin
    Item:= AResult.Missing[I];
    // MakeRelPath already produces backslash-relative from project dir.
    Item.RelPath:= MakeRelPath(Item.FilePath, ProjectDir);
    ProjectRelMissing[I]:= Item;
  end;

  // -- Edit .dpr uses clause -------------------------------------------------
  if TFile.Exists(DprPath) then EditDpr(DprPath, ProjectRelMissing);

  // -- Edit .dproj DCCReference ItemGroup ------------------------------------
  if TFile.Exists(DprojPath) then EditDproj(DprojPath, ProjectRelMissing);
end; // procedure

end.
