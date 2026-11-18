unit DRagLint.Lint.SharedScope;

{ SHARED-UNIT-SCOPE (1.41, owner ruling 2026-11-02: UNION). A unit compiled by several
  projects is judged by every project that lists it, not by the one DB a lint run opened.
  Spec: docs\superpowers\specs\2026-11-03-shared-unit-scope-design.md. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.Interfaces;

type
  /// <summary>Opens (or returns an already-open) read-only store for a project named by
  /// a manifest section or by a shared unit's `dl:shared` header.</summary>
  /// <param name="AProjectName">The project / manifest section name; case-insensitive.</param>
  /// <returns>An open store, or nil when the name resolves to no configured index or the
  /// index cannot be opened. nil means "could not check", never "not used there".</returns>
  /// <remarks>
  /// The caller owns the returned store's lifetime for the whole run.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.pas), declaration (DRagLint.Lint.ProjectRules.pas), DRagLint.CLI.MakeSiblingStoreResolver (DRagLint.CLI.pas), DRagLint.Lint.ProjectRules.CollectDependentProjectNotRecompiled (DRagLint.Lint.ProjectRules.pas), DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas) (+2 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSiblingStoreResolver = reference to function(const AProjectName: string): ISymbolStore;

  /// <summary>Lists every project section name of the manifest the run reads.</summary>
  /// <returns>Section names; empty when no manifest loads.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.pas), declaration (DRagLint.Lint.ProjectRules.pas), declaration (DRagLint.Lint.SharedScope.pas), DRagLint.CLI.MakeSiblingProjectLister (DRagLint.CLI.pas), DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas) (+1 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSiblingProjectLister = reference to function: TArray<string>;

  /// <summary>Does ASibling use the symbol under judgement?</summary>
  /// <param name="ASibling">An open store of a project that lists the unit.</param>
  /// <returns>True when the sibling's index shows a use.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.SharedScope.pas), DRagLint.Lint.SharedScope.TSharedScope.Judge (DRagLint.Lint.SharedScope.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSiblingUse = reference to function(const ASibling: ISymbolStore): Boolean;

  /// <summary>Verdict of TSharedScope.Judge.</summary>
  /// <remarks>
  /// svNotShared: no other project lists the unit -- judge from the own DB alone.
  /// svUsedElsewhere: a listing project uses it -- no finding. svUnusedEverywhere: every
  /// listing project was checked, fresh, and none uses it -- report. svUndecided: a listing
  /// project's index is missing, will not open or is stale -- do not report.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.SharedScope.pas), DRagLint.Lint.SharedScope.TSharedScope.Judge (DRagLint.Lint.SharedScope.pas), DRagLint.Lint.UnusedGlobal.CollectUnusedGlobal (DRagLint.Lint.UnusedGlobal.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSharedVerdict = (svNotShared, svUsedElsewhere, svUnusedEverywhere, svUndecided);

  /// <summary>Finds the projects that list a unit and asks each whether a symbol of it
  /// is used.</summary>
  /// <remarks>
  /// The listing set of a unit path P: every name on P's `dl:shared` header, plus every
  /// manifest section whose index holds a `files` row for P (a project index is its
  /// `.dproj` compile closure). The run's own store is excluded. A header-named project
  /// whose index is missing, will not open or is not fresh makes every verdict on P
  /// svUndecided; a manifest section that will not open is ignored (nothing says it lists
  /// P). A `.groupproj` peer with no index whose project file lists P (AddDiscoveredPeers) makes
  /// every verdict on P svUndecided too (1.52 BK-TAILS-ENG). LAZY: nothing is opened until the first Judge; the listing set, the self test and
  /// the freshness probe are cached per path / per project for the object's life.
  /// Not thread-safe; one per lint run.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.UnusedGlobal.pas) ?, DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas), DRagLint.Lint.UnusedGlobal.CollectUnusedGlobal (DRagLint.Lint.UnusedGlobal.pas) ?</para>
  /// <para>Used in units: DRagLint.Lint.ProjectRules, DRagLint.Lint.UnusedGlobal</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSharedScope = class
  private
    FStore   : ISymbolStore;
    FResolve : TSiblingStoreResolver;
    FLister  : TSiblingProjectLister;
    FNames   : TArray<string>;
    FNamesOk : Boolean;
    FListing : TDictionary<string, TArray<string>>;
    FWhyNot  : TDictionary<string, string>;
    FUsable  : TDictionary<string, Boolean>;
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->ISymbolStore -- Observed: nil;
    /// FResolve(Trim(AName)).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoExportObsidian (DRagLint.CLI.pas) ?, DRagLint.Lint.SharedScope.TSharedScope.Judge (DRagLint.Lint.SharedScope.pas), DRagLint.Lint.SharedScope.TSharedScope.ResolvePath (DRagLint.Lint.SharedScope.pas)</para>
    /// <para>Calls: FResolve, Trim</para>
    /// <para>Reads: FResolve</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Create"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Destroy"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsSelf"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsUsable"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Judge"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Open(const AName: string): ISymbolStore;
    /// <summary><!-- drag-lint:auto sum -->The run's own DB, reopened through the
    /// manifest. Cheap meta first; a match is confirmed by every own file path being
    /// present in the sibling (two DBs built in one second share a stamp).</summary>
    /// <param name="ASibling"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.SharedScope.TSharedScope.ResolvePath (DRagLint.Lint.SharedScope.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue</para>
    /// <para>Reads: FStore</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetMetaValue"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsSelf(const ASibling: ISymbolStore): Boolean;
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ASibling"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ProbeIndexFreshness(ASibling,
    /// 1).Verdict = fvFresh.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.SharedScope.TSharedScope.Judge (DRagLint.Lint.SharedScope.pas)</para>
    /// <para>Calls: DRagLint.Index.Freshness.ProbeIndexFreshness, LowerCase</para>
    /// <para>Reads: FUsable</para>
    /// <seealso cref="DRagLint.Index.Freshness.ProbeIndexFreshness"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Create"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Destroy"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsSelf"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Judge"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsUsable(const AName: string; const ASibling: ISymbolStore): Boolean;
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.SharedScope.TSharedScope.Judge (DRagLint.Lint.SharedScope.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Lint.SharedScope.TSharedScope.IsSelf, DRagLint.Lint.SharedScope.TSharedScope.Open, DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOf, FLister, Format, LowerCase, Trim</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 49 lines (full implementation)</para>
    /// <para>Reads: FLister, FNamesOk, FNames, FListing, FWhyNot   Writes: FNamesOk, FNames</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsSelf"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Open"/>
    /// <seealso cref="DRagLint.Lint.SharedUnit.TSharedUnit.ProjectsOf"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ResolvePath(const APath: string);
  public
    /// <summary>Binds the scope to the run's own store and the CLI's resolvers.</summary>
    /// <param name="AStore">The run's own project store.</param>
    /// <param name="AResolve">Opens a project's store by name; nil = no sibling can be opened.</param>
    /// <param name="ALister">Lists the manifest's section names; nil = header names only.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FStore, FResolve, FLister, FListing, FWhyNot, FUsable</para>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Destroy"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsSelf"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsUsable"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Judge"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Open"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AStore: ISymbolStore; const AResolve: TSiblingStoreResolver;
                       const ALister: TSiblingProjectLister);
    /// <summary>Frees the caches; the stores belong to the resolver's owner.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FUsable, FWhyNot, FListing</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Create"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsSelf"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsUsable"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Judge"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Open"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Judges one symbol of the unit at AUnitPath across the projects that list it.</summary>
    /// <param name="AUnitPath">The unit's path as the own store records it.</param>
    /// <param name="AUsed">Asked once per listing project, until one answers True.</param>
    /// <param name="AProjects">Out: the listing projects (comma-separated) for a message;
    /// for svUndecided, why no verdict was reached.</param>
    /// <returns>The verdict; see TSharedVerdict.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas), DRagLint.Lint.UnusedGlobal.CollectUnusedGlobal (DRagLint.Lint.UnusedGlobal.pas)</para>
    /// <para>Calls: AUsed, DRagLint.Lint.SharedScope.TSharedScope.IsUsable, DRagLint.Lint.SharedScope.TSharedScope.Open, DRagLint.Lint.SharedScope.TSharedScope.ResolvePath, Format, LowerCase</para>
    /// <para>Returns: svUndecided; svUnusedEverywhere</para>
    /// <para>Reads: FListing, FWhyNot</para>
    /// <para>Mutates: AProjects (out)</para>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.IsUsable"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Open"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.ResolvePath"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Create"/>
    /// <seealso cref="DRagLint.Lint.SharedScope.TSharedScope.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Judge(const AUnitPath: string; const AUsed: TSiblingUse; out AProjects: string): TSharedVerdict;
  end;

/// <summary>Records that the SHARED-UNIT-SCOPE verdict for a finding site was svUndecided, so
/// the finding was withheld and a dl:ok on that line cannot be judged.</summary>
/// <param name="AFile">The unit path as the own store records it.</param>
/// <param name="ALine">The line the finding would have been anchored on.</param>
/// <param name="ARule">The rule id that would have fired.</param>
/// <remarks>
/// Thread-safe. Process-wide; consulted by the review-marker-unused pass so a marker
/// whose finding was withheld for want of a fresh sibling index reads as "cannot judge", not
/// "suppresses nothing" (DLOK-UNDECIDED).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas), DRagLint.Lint.UnusedGlobal.CollectUnusedGlobal (DRagLint.Lint.UnusedGlobal.pas)</para>
/// <para>Calls: DRagLint.Lint.SharedScope.SiteKey</para>
/// <seealso cref="DRagLint.Lint.SharedScope.SiteKey"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure NoteUndecidedSite(const AFile: string; ALine: Integer; const ARule: string);

/// <summary>Was NoteUndecidedSite called for this site in this process?</summary>
/// <param name="AFile">A file path; compared after slash and case normalisation.</param>
/// <param name="ALine">The line.</param>
/// <param name="ARule">The rule id; case-insensitive.</param>
/// <returns>True when the site's shared-scope verdict was undecided.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Lint.SharedScope.SiteKey</para>
/// <para>Returns: GUndecided.ContainsKey(SiteKey(AFile, ALine, ARule))</para>
/// <seealso cref="DRagLint.Lint.SharedScope.SiteKey"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsUndecidedSite(const AFile: string; ALine: Integer; const ARule: string): Boolean;

/// <summary>B16 (1.52 BK-XPROJ): adds the sibling indexes a run can find WITHOUT a manifest
/// section, so a unit another project compiles is judged there too.</summary>
/// <param name="APrimaryDb">The run's --db ('' = the manifest picked it).</param>
/// <param name="AProjectPath">The run's --project ('' when none).</param>
/// <param name="AIsCopy">True when APrimaryDb is not a DB the manifest registers.</param>
/// <param name="ANameToDb">Lowercased project name -> DB path; an existing non-empty entry is
/// never replaced.</param>
/// <remarks>
/// Two sources. (a) COPY: --db is a copy outside any `_D-RAG` folder -- every other
/// `.sqlite` beside it is a candidate (a copy set keeps its peers together; v1511 F1 never
/// opens a real DB from a copy run, and neither does this). (b) REAL: --db sits in its
/// project's `_D-RAG` folder (or the run is not on a copy and names --project) -- every
/// `.groupproj` in the project folder or up to two parents lists peer `.dproj` files, each
/// one's index at `peer folder\_D-RAG\peer base name.sqlite` when that file exists. A
/// candidate is only a candidate: TSharedScope still keeps a peer only when its index holds
/// the unit's file, and judges only a fresh one. Reads directory listings and `.groupproj`
/// text; opens no store. Exceptions from the file system are swallowed per entry.
/// 1.52 BK-TAILS-ENG: a `.groupproj` peer whose index file does NOT exist is recorded as unindexed
/// (its `.dproj` DCCReference entries and `.dpr` / `.dpk` `in '...'` paths are read); TSharedScope.Judge
/// then answers svUndecided for every unit it lists and writes one stderr line per such peer.
/// 1.52 TAILS-ENG2: the same for every unit in a folder the unindexed peer searches (its own folder and
/// its `.dproj` DCC_UnitSearchPath) -- the peer may compile such a unit without listing it.
/// </remarks>
procedure AddDiscoveredPeers(const APrimaryDb, AProjectPath: string; AIsCopy: Boolean;
  const ANameToDb: TDictionary<string, string>);

implementation

uses
  System.IOUtils,
  System.RegularExpressions,
  DRagLint.Lint.SharedUnit,  { TSharedUnit.ProjectsOf -- the header-declared projects }
  DRagLint.Lint.ProjectChecks.Parse,  { ReadDCCReferences / FindSiblingProgramFile -- what an unindexed peer lists }
  DRagLint.Index.Closure,  { TClosureResolver.ProjectSearchPaths -- the folders an unindexed peer searches }
  DRagLint.Index.Freshness;  { ProbeIndexFreshness -- a stale sibling proves nothing }

const
  { 1.52 TAILS-ENG2: GUnindexedPeerOf key prefix of a FOLDER an unindexed peer searches (vs a listed file) }
  SEARCH_DIR_KEY = 'dir:';

var
  GUndecided: TDictionary<string, Boolean>;
  { 1.52 BK-TAILS-ENG: lowercased full unit path -> the .dproj of a .groupproj peer that LISTS the unit
    but has no index; rebuilt by every AddDiscoveredPeers. }
  GUnindexedPeerOf: TDictionary<string, string>;
  { lowercased .dproj -> its info line was written (once per process) }
  GPeerAnnounced: TDictionary<string, Boolean>;

function SiteKey(const AFile: string; ALine: Integer; const ARule: string): string;
var
  P: string;
begin
  P:= StringReplace(AFile, '/', '\', [rfReplaceAll]);
  if P <> '' then P:= ExpandFileName(P);
  Result:= LowerCase(P) + '|' + IntToStr(ALine) + '|' + LowerCase(ARule);
end;

procedure NoteUndecidedSite(const AFile: string; ALine: Integer; const ARule: string);
begin
  TMonitor.Enter(GUndecided);
  try
    GUndecided.AddOrSetValue(SiteKey(AFile, ALine, ARule), True);
  finally
    TMonitor.Exit(GUndecided);
  end;
end;

function IsUndecidedSite(const AFile: string; ALine: Integer; const ARule: string): Boolean;
begin
  TMonitor.Enter(GUndecided);
  try
    Result:= GUndecided.ContainsKey(SiteKey(AFile, ALine, ARule));
  finally
    TMonitor.Exit(GUndecided);
  end;
end;

const
  DRAG_DIR = '_D-RAG';
  GROUPPROJ_PARENT_LEVELS = 2;  { the project folder, its parent and grandparent }

procedure AddPeer(const ANameToDb: TDictionary<string, string>; const AName, ADb: string);
var
  Cur: string;
begin
  if (AName = '') or (ADb = '') then Exit;
  if ANameToDb.TryGetValue(LowerCase(AName), Cur) and (Cur <> '') then Exit;
  for var Known: string in ANameToDb.Values do  { a manifest section already opens this DB }
    if SameText(ExpandFileName(Known), ExpandFileName(ADb)) then Exit;
  ANameToDb.AddOrSetValue(LowerCase(AName), ADb);
end;

{ 1.52 BK-TAILS-ENG: records every unit the unindexed peer ADproj LISTS -- its .dproj DCCReference entries
  and its .dpr / .dpk `in '...'` paths -- so TSharedScope reads a verdict on such a unit as undecidable.
  1.52 TAILS-ENG2: also every folder it searches (its own folder + DCC_UnitSearchPath, via
  TClosureResolver.ProjectSearchPaths): a unit in one of them MAY be compiled by the peer unlisted, so it
  is undecidable too. Deliberately over-approximate (no closure walk without an index); not covered: a
  unit reached through a library path / IDE-global search path or an environment macro the .dproj parse
  does not expand. }
procedure NoteUnindexedPeer(const ADproj: string);
var
  Dir : string;
  Refs: TArray<string>;
  Prog: string;
begin
  Dir:= ExtractFilePath(ADproj);
  Prog:= '';
  try
    Refs:= ReadDCCReferences(ADproj);
    var ProgFile: string:= FindSiblingProgramFile(ADproj);
    if ProgFile <> '' then Prog:= StripPasCommentsKeepLayout(TFile.ReadAllText(ProgFile));
  except  // dl:ok try-except-swallowed@2bb3 -- an unreadable peer project lists nothing; the run judges as before
    on E: Exception do Exit;
  end;
  for var M: TMatch in TRegEx.Matches(Prog, '\bin\s+''([^'']+)''', [roIgnoreCase]) do
    Refs:= Refs + [M.Groups[1].Value];
  { 1.52 TAILS-ENG2: the folders the compiler searches for this peer -- its own folder and its
    DCC_UnitSearchPath. A unit there may be compiled by the peer without being listed. }
  var SearchDirs: TArray<string>:= TClosureResolver.ProjectSearchPaths(ADproj);
  TMonitor.Enter(GUnindexedPeerOf);
  try
    for var Ref: string in Refs do
    begin
      var Full: string:= LowerCase(ExpandFileName(TPath.Combine(Dir, Ref)));
      if not GUnindexedPeerOf.ContainsKey(Full) then GUnindexedPeerOf.Add(Full, ADproj);
    end;
    for var SDir: string in SearchDirs do
    begin
      var Key: string:= SEARCH_DIR_KEY + LowerCase(ExcludeTrailingPathDelimiter(ExpandFileName(TPath.Combine(Dir, SDir))));
      if not GUnindexedPeerOf.ContainsKey(Key) then GUnindexedPeerOf.Add(Key, ADproj);
    end;
  finally
    TMonitor.Exit(GUnindexedPeerOf);
  end;
end;

{ The .dproj of an unindexed peer that lists APath, or (1.52 TAILS-ENG2) whose search path holds its
  folder (AViaSearchPath); '' when none does. }
function UnindexedPeerListing(const APath: string; out AViaSearchPath: Boolean): string;
begin
  AViaSearchPath:= False;
  var Full: string:= LowerCase(ExpandFileName(StringReplace(APath, '/', '\', [rfReplaceAll])));
  TMonitor.Enter(GUnindexedPeerOf);
  try
    if GUnindexedPeerOf.TryGetValue(Full, Result) then Exit;
    AViaSearchPath:= GUnindexedPeerOf.TryGetValue(SEARCH_DIR_KEY + ExcludeTrailingPathDelimiter(ExtractFilePath(Full)), Result);
    if not AViaSearchPath then Result:= '';
  finally
    TMonitor.Exit(GUnindexedPeerOf);
  end;
end;

{ One stderr line per unindexed peer per process: which project could not be asked and how to fix it.
  Console processes only -- a GUI host has no ErrOutput to write to. }
procedure AnnounceUnindexedPeer(const ADproj: string);
begin
  TMonitor.Enter(GPeerAnnounced);
  try
    if GPeerAnnounced.ContainsKey(LowerCase(ADproj)) then Exit;
    GPeerAnnounced.Add(LowerCase(ADproj), True);
  finally
    TMonitor.Exit(GPeerAnnounced);
  end;
  if not IsConsole then Exit;
  try
    Writeln(ErrOutput, Format('drag-lint: cross-project: project %s (%s) lists units of this run but has no index -- ' +
      'unused-global / unused-public / member-could-be-private findings on those units are withheld as undecidable. ' +
      'Index it: drag-lint index --project "%s"', [ChangeFileExt(ExtractFileName(ADproj), ''), ADproj, ADproj]));
  except  // dl:ok try-except-swallowed@2bb3 -- an info line that cannot be written must not fail the lint run
    on E: Exception do Exit;
  end;
end;

procedure AddGroupPeers(const AGroupProj, AOwnBase, APrimary: string;
  const ANameToDb: TDictionary<string, string>);
var
  Text: string;
begin
  try
    Text:= TFile.ReadAllText(AGroupProj);
  except  // dl:ok try-except-swallowed@2bb3 -- an unreadable .groupproj names no peer; the run judges as before
    on E: Exception do Exit;
  end;
  for var M: TMatch in TRegEx.Matches(Text, '<Projects\s+Include="([^"]+)"', [roIgnoreCase]) do
  begin
    var Peer: string:= ExpandFileName(TPath.Combine(ExtractFilePath(AGroupProj), M.Groups[1].Value));
    if not SameText(ExtractFileExt(Peer), '.dproj') then Continue;
    var Base: string:= ChangeFileExt(ExtractFileName(Peer), '');
    if SameText(Base, AOwnBase) then Continue;
    var Db: string:= TPath.Combine(TPath.Combine(ExtractFilePath(Peer), DRAG_DIR), Base + '.sqlite');
    if SameText(Db, APrimary) then Continue;
    if not TFile.Exists(Db) then
    begin
      NoteUnindexedPeer(Peer);  { 1.52 BK-TAILS-ENG: no index to ask -- its units are undecidable }
      Continue;
    end;
    AddPeer(ANameToDb, Base, Db);
  end;
end;

{ The .groupproj files directly in ADir; empty when the folder cannot be listed. }
function GroupProjsIn(const ADir: string): TArray<string>;
begin
  try
    Result:= TDirectory.GetFiles(ADir, '*.groupproj');  // dl:ok taint-path-traversal@d6af -- ADir is the run's own --project / --db folder or a parent; only a listing is read
  except  { a folder that cannot be listed names no peer }
    on E: Exception do Result:= nil;
  end;
end;

procedure AddDiscoveredPeers(const APrimaryDb, AProjectPath: string; AIsCopy: Boolean;
  const ANameToDb: TDictionary<string, string>);
var
  Primary, DbDir, Dir, OwnBase: string;
  InDRag: Boolean;
begin
  TMonitor.Enter(GUnindexedPeerOf);  { 1.52 BK-TAILS-ENG: this run's unindexed peers only }
  try
    GUnindexedPeerOf.Clear;
  finally
    TMonitor.Exit(GUnindexedPeerOf);
  end;
  Primary:= if APrimaryDb = '' then '' else ExpandFileName(APrimaryDb);
  DbDir  := if Primary = '' then '' else ExcludeTrailingPathDelimiter(ExtractFilePath(Primary));
  InDRag := (DbDir <> '') and SameText(ExtractFileName(DbDir), DRAG_DIR);
  { (a) a copy set: the other DBs beside the copy }
  if AIsCopy and (DbDir <> '') and not InDRag and TDirectory.Exists(DbDir) then
    for var Db: string in TDirectory.GetFiles(DbDir, '*.sqlite') do  // dl:ok taint-path-traversal@398e -- DbDir is the folder of the run's own --db; only a listing is read
      if not SameText(Db, Primary) then AddPeer(ANameToDb, ChangeFileExt(ExtractFileName(Db), ''), Db);
  { (b) a real DB: the peers the project group lists }
  if AIsCopy and not InDRag then Exit;
  if AProjectPath <> '' then
  begin
    Dir    := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(AProjectPath)));
    OwnBase:= ChangeFileExt(ExtractFileName(AProjectPath), '');
  end
  else if InDRag then
  begin
    Dir    := ExtractFileDir(DbDir);
    OwnBase:= ChangeFileExt(ExtractFileName(Primary), '');
  end
  else Exit;
  for var Level: Integer:= 0 to GROUPPROJ_PARENT_LEVELS do
  begin
    if (Dir = '') or not TDirectory.Exists(Dir) then Break;
    for var G: string in GroupProjsIn(Dir) do
      AddGroupPeers(G, OwnBase, Primary, ANameToDb);
    var Up: string:= ExtractFileDir(Dir);
    if SameText(Up, Dir) then Break;
    Dir:= Up;
  end;
end;

const
  META_INDEXED_AT = 'indexed_at_unix';
  META_PROJECT_TAG = 'project_tag';

constructor TSharedScope.Create(const AStore: ISymbolStore; const AResolve: TSiblingStoreResolver;
  const ALister: TSiblingProjectLister);
begin
  inherited Create;
  FStore  := AStore;
  FResolve:= AResolve;
  FLister := ALister;
  FListing:= TDictionary<string, TArray<string>>.Create;
  FWhyNot := TDictionary<string, string>.Create;
  FUsable := TDictionary<string, Boolean>.Create;
end;

destructor TSharedScope.Destroy;
begin
  FUsable.Free;
  FWhyNot.Free;
  FListing.Free;
  inherited Destroy;
end;

function TSharedScope.Open(const AName: string): ISymbolStore;
begin
  Result:= nil;
  if (not Assigned(FResolve)) or (Trim(AName) = '') then Exit;
  try
    Result:= FResolve(Trim(AName));
  except  { a sibling index that will not open is "could not check" (nil), never an aborted lint run }
    on E: Exception do Result:= nil;
  end;
end;

{ The run's own DB, reopened through the manifest. Cheap meta first; a match is confirmed by
  every own file path being present in the sibling (two DBs built in one second share a stamp). }
function TSharedScope.IsSelf(const ASibling: ISymbolStore): Boolean;
var
  Ids: TArray<Int64>;
begin
  Result:= False;
  if (ASibling = nil) or (FStore = nil) then Exit;
  if (ASibling.GetMetaValue(META_INDEXED_AT) <> FStore.GetMetaValue(META_INDEXED_AT)) or
     (ASibling.GetMetaValue(META_PROJECT_TAG) <> FStore.GetMetaValue(META_PROJECT_TAG)) then Exit;
  Ids:= FStore.GetAllFileIds;
  if Length(Ids) <> Length(ASibling.GetAllFileIds) then Exit;
  for var Fid in Ids do
    if ASibling.FindFileIdByPath(FStore.GetFilePath(Fid)) <= 0 then Exit;
  Result:= True;
end;

function TSharedScope.IsUsable(const AName: string; const ASibling: ISymbolStore): Boolean;
begin
  if FUsable.TryGetValue(LowerCase(AName), Result) then Exit;
  Result:= ProbeIndexFreshness(ASibling, 1).Verdict = fvFresh;
  FUsable.Add(LowerCase(AName), Result);
end;

procedure TSharedScope.ResolvePath(const APath: string);
var
  Names: TList<string>;
  Seen : TDictionary<string, Boolean>;
  Why  : string;
  St   : ISymbolStore;
begin
  Names:= TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Why:= '';
    { 1. the header: a declared relationship, so an index that cannot answer blocks the verdict }
    for var N in TSharedUnit.ProjectsOf(APath) do
    begin
      if (Trim(N) = '') or Seen.ContainsKey(LowerCase(Trim(N))) then Continue;
      Seen.Add(LowerCase(Trim(N)), True);
      St:= Open(N);
      if St = nil then
      begin
        if Why = '' then Why:= Format('the index of %s (named on its dl:shared header) could not be opened', [Trim(N)]);
        Continue;
      end;
      if IsSelf(St) then Continue;
      Names.Add(Trim(N));
    end;
    { 2. the manifest: a section lists the unit when its index holds the file }
    if Assigned(FLister) and not FNamesOk then
    begin
      FNamesOk:= True;
      try
        FNames:= FLister();
      except  // dl:ok try-except-swallowed@5735 -- a manifest that will not load leaves the header as the only evidence, which is the pre-1.41 behaviour
        on E: Exception do FNames:= nil;
      end;
    end;
    for var N in FNames do
    begin
      if (Trim(N) = '') or Seen.ContainsKey(LowerCase(Trim(N))) then Continue;
      Seen.Add(LowerCase(Trim(N)), True);
      St:= Open(N);
      if (St = nil) or (St.FindFileIdByPath(APath) <= 0) or IsSelf(St) then Continue;
      { 1.52 BK-XPROJ: another DB of THIS project (an older copy beside a --db copy, the same
        folder indexed twice) is not a sibling project -- its stale answer must not withhold. }
      if (FStore <> nil) and SameText(St.GetMetaValue(META_PROJECT_TAG), FStore.GetMetaValue(META_PROJECT_TAG)) then Continue;
      Names.Add(Trim(N));
    end;
    { 3. 1.52 BK-TAILS-ENG: a .groupproj peer that lists the unit but has no index cannot be asked -- as
      undecidable as a header-named project whose index is missing (AddDiscoveredPeers records them). }
    if Why = '' then
    begin
      var ViaSearchPath: Boolean;
      var Peer: string:= UnindexedPeerListing(APath, ViaSearchPath);
      if Peer <> '' then
      begin
        Why:= Format('project %s %s but has no index (%s)', [ChangeFileExt(ExtractFileName(Peer), ''),
          (if ViaSearchPath then 'may compile the unit through its search path' else 'lists the unit'), Peer]);
        AnnounceUnindexedPeer(Peer);
      end;
    end;
    FListing.AddOrSetValue(LowerCase(APath), Names.ToArray);
    FWhyNot.AddOrSetValue(LowerCase(APath), Why);
  finally
    Seen.Free;
    Names.Free;
  end;
end;

function TSharedScope.Judge(const AUnitPath: string; const AUsed: TSiblingUse; out AProjects: string): TSharedVerdict;
var
  Listing: TArray<string>;
  Why    : string;
  St     : ISymbolStore;
begin
  AProjects:= '';
  if AUnitPath = '' then Exit(svNotShared);
  if not FListing.ContainsKey(LowerCase(AUnitPath)) then ResolvePath(AUnitPath);
  Listing:= FListing[LowerCase(AUnitPath)];
  Why:= FWhyNot[LowerCase(AUnitPath)];
  if Why <> '' then
  begin
    AProjects:= Why;
    Exit(svUndecided);
  end;
  if Length(Listing) = 0 then Exit(svNotShared);
  AProjects:= string.Join(', ', Listing);
  for var N in Listing do
  begin
    St:= Open(N);
    if (St = nil) or not IsUsable(N, St) then
    begin
      AProjects:= Format('the index of %s is missing or not fresh', [N]);
      Exit(svUndecided);
    end;
    if AUsed(St) then Exit(svUsedElsewhere);
  end;
  Result:= svUnusedEverywhere;
end;

initialization
  GUndecided:= TDictionary<string, Boolean>.Create;
  GUnindexedPeerOf:= TDictionary<string, string>.Create;
  GPeerAnnounced:= TDictionary<string, Boolean>.Create;

finalization
  GPeerAnnounced.Free;
  GUnindexedPeerOf.Free;
  GUndecided.Free;

end.
