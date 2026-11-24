unit DRagLint.Lint.OwnFilter;

/// <summary>The ownership filter of a project lint-all: which files the project compiles are
/// third-party, why, and how many findings that kept out of the report.</summary>
/// <remarks>Built ON TOwnRoots (the project's declaration), not beside it: ownRoots / excludeRoots
/// decide first, and this unit adds the two INFERRED signals -- a vendored folder name, a library
/// path -- plus the lint-config keys own_paths and vendored_folders. An explicit exclusion beats an
/// explicit ownership, which beats an inferred signal; with no signal a file is OWN, so a shared
/// folder beside the project is never hidden because nobody declared it. TOwnRoots.IsOurs is
/// unchanged and stays the WRITE scope (document, --fix). Design:
/// docs\superpowers\specs\2026-11-24-ownfilter-design.md; guard: run_v154_OWNFILTER.ps1.
///
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

uses
  System.Generics.Collections,
  System.JSON,
  System.SysUtils,
  DRagLint.Project.OwnRoots,
  DRagLint.Lint.Config;

const
  /// <summary>Rule id of the note row a --json report ends with when something was skipped.</summary>
  THIRD_PARTY_SKIPPED_ROW = 'third-party-skipped';

type
  /// <summary>Why a file is left out of a project lint run.</summary>
  /// <remarks>srOwn = it is not left out. srExcludePaths is decided by the caller
  /// (TLintConfig.IsPathExcluded) and only counted here.</remarks>
  TSkipReason = (srOwn, srExcludePaths, srExcludeRoots, srOutsideOwnRoots, srVendoredFolder, srLibraryPath, srOutsideFixScope);

  /// <summary>The library folders the run knows, split by how sure they are.</summary>
  TLibraryScope = record
    /// <summary>Folders the index manifest declares as a library ("include" of its Library section).</summary>
    Declared: TArray<string>;
    /// <summary>The IDE's library paths (registry). Inferred: a unit the project file LISTS stays own.</summary>
    Registry: TArray<string>;
    /// <summary>The .pas file names the project file lists, lower case, without a folder.</summary>
    Listed: TArray<string>;
  end;

  /// <summary>Judges files of one lint run and counts what the judgement dropped.</summary>
  /// <remarks>Not thread-safe; one instance per run. Reference-counted, so it needs no Free.</remarks>
  IOwnFilter = interface
    ['{B8B0B9A0-5B6C-4C0B-9D64-2F6E0B7C1A54}']
    /// <summary>The reason AFilePath is left out, or srOwn.</summary>
    /// <param name="AFilePath">Absolute source path; '' (a run-level finding) is srOwn.</param>
    /// <returns>srOwn for every file when the project has no anchor or the run shows third-party code.</returns>
    function Judge(const AFilePath: string): TSkipReason;
    /// <summary>Counts a file the scan left out, or (AReason srOwn) one it admitted.</summary>
    /// <param name="AFilePath">The file.</param>
    /// <param name="AReason">srExcludePaths, or what Judge answered.</param>
    procedure NoteFile(const AFilePath: string; AReason: TSkipReason);
    /// <summary>Counts a project-wide finding that was dropped.</summary>
    /// <param name="AFilePath">Where the finding is located.</param>
    /// <param name="ARuleId">Its rule; counted only when TOwnFilterSetup.Counts says the run would report it.</param>
    /// <param name="AReason">srExcludePaths, or what Judge answered.</param>
    procedure NoteFinding(const AFilePath, ARuleId: string; AReason: TSkipReason);
    /// <summary>The skip block: totals, one line per reason, the rules of the dropped findings.</summary>
    /// <returns>nil when nothing was skipped.</returns>
    function SummaryLines: TArray<string>;
    /// <summary>The tail of the one-line summary, e.g. '; 3 third-party file(s) skipped'.</summary>
    /// <returns>'' when no third-party file was skipped.</returns>
    function SummarySuffix: string;
    /// <summary>The note row for a --json report.</summary>
    /// <returns>A new object the caller owns, or nil when no third-party file or finding was skipped.</returns>
    function JsonRow: TJSONObject;
    /// <summary>Files outside the project folder that were admitted because nothing marks them third-party.</summary>
    /// <returns>0 when the own roots are declared.</returns>
    function KeptOutside: Integer;
  end;

  /// <summary>What a lint run hands to the filter.</summary>
  TOwnFilterSetup = record
    /// <summary>The project's declaration (or its default).</summary>
    Own: TOwnRoots;
    /// <summary>The run's lint config (own_paths, vendored_folders).</summary>
    Cfg: TLintConfig;
    /// <summary>True = --lint-third-party: nothing is third-party.</summary>
    ShowAll: Boolean;
    /// <summary>True = a --fix run: an undeclared file outside the project folder is left out, because
    /// keeping it in a report is harmless and rewriting it is not.</summary>
    FixRun: Boolean;
    /// <summary>The library folders, asked for once and only when a file outside the project needs them.</summary>
    Libraries: TFunc<TLibraryScope>;
    /// <summary>True when the run reports this rule; nil = every rule counts.</summary>
    Counts: TFunc<string, Boolean>;
  end;

/// <summary>Creates the filter of one lint run.</summary>
/// <param name="ASetup">The run's inputs, copied.</param>
/// <returns>A fresh filter with zero counts.</returns>
function MakeOwnFilter(const ASetup: TOwnFilterSetup): IOwnFilter;

/// <summary>The library folders of a project, split into declared and registry ones.</summary>
/// <param name="AAll">Every library root of the project's Delphi plus the manifest ones.</param>
/// <param name="ADeclared">The manifest Library section's "include" folders.</param>
/// <param name="AProjectFile">The .dproj / .dpr / .dpk; its listed units are read from it and its
/// sibling program file. When one cannot be read, the registry roots are dropped.</param>
/// <returns>The scope for TOwnFilterSetup.Libraries.</returns>
function MakeLibraryScope(const AAll, ADeclared: TArray<string>; const AProjectFile: string): TLibraryScope;

/// <summary>The folder names treated as vendored: the built-in ones plus "vendored_folders".</summary>
/// <param name="AConfigured">The config list; "-name" takes a name out.</param>
/// <returns>Lower-case names.</returns>
/// <remarks>"vendor" is deliberately not built in: in business code a vendor is a supplier.</remarks>
function VendoredFolderNames(const AConfigured: TArray<string>): TArray<string>;

implementation

uses
  System.Classes,
  System.Generics.Defaults,
  System.IOUtils,
  System.RegularExpressions,
  System.StrUtils,
  Winapi.Windows;

const
  VENDORED_DEFAULTS: array [0..6] of string =
    ('third_party', 'third-party', 'thirdparty', '3rdparty', '3rd_party', '3rd-party', 'vendored');
  REASON_CODES: array [TSkipReason] of string =
    ('own', 'exclude-paths', 'exclude-roots', 'outside-own-roots', 'vendored-folder', 'library-path', 'outside-fix-scope');
  MAX_RULES_NAMED = 10;

type
  TSkipCount = record
    Reason  : TSkipReason;
    Files   : Integer    ;
    Findings: Integer    ;
  end;

  TOwnFilter = class(TInterfacedObject, IOwnFilter)
  strict private
    FSetup      : TOwnFilterSetup                ;
    FNames      : TArray<string>                 ;
    FMemo       : TDictionary<string, TSkipReason>;
    FWhere      : TDictionary<string, string>    ; { file -> its group text }
    FGroups     : TDictionary<string, TSkipCount>; { group text -> counts }
    FRules      : TDictionary<string, Integer>   ;
    FFiles      : Integer;                         { third-party only, no exclude_paths }
    FFindings   : Integer;
    FKeptOutside: Integer;
    FLib        : TLibraryScope;
    FLibLoaded  : Boolean;
    function Classify(const APath: string; out AWhere: string): TSkipReason;
    function VendoredName(const APath: string): string;
    function LibraryRoot(const APath: string): string;
    function GroupText(const AFilePath: string; AReason: TSkipReason): string;
    procedure Bump(const AGroup: string; AReason: TSkipReason; AFiles, AFindings: Integer);
    function SortedGroups: TArray<string>;
    function SortedRules: TArray<string>;
  public
    constructor Create(const ASetup: TOwnFilterSetup);
    destructor Destroy; override;
    function Judge(const AFilePath: string): TSkipReason;
    procedure NoteFile(const AFilePath: string; AReason: TSkipReason);
    procedure NoteFinding(const AFilePath, ARuleId: string; AReason: TSkipReason);
    function SummaryLines: TArray<string>;
    function SummarySuffix: string;
    function JsonRow: TJSONObject;
    function KeptOutside: Integer;
  end;

function FullPath(const APath: string): string;
begin
  Result:= ExpandFileName(StringReplace(APath, '/', '\', [rfReplaceAll]));
end;

{ The longest entry of ADirs that holds APath ('' = none), with a trailing delimiter, so
  "vendor" never holds "vendorX". }
function HoldingDir(const APath: string; const ADirs: TArray<string>): string;
begin
  Result:= '';
  for var D: string in ADirs do
  begin
    if D = '' then Continue;
    var Dir: string:= IncludeTrailingPathDelimiter(FullPath(D));
    if StartsText(Dir, APath) and (Length(Dir) > Length(Result)) then Result:= Dir;
  end;
end;

function VendoredFolderNames(const AConfigured: TArray<string>): TArray<string>;
begin
  Result:= nil;
  for var D: string in VENDORED_DEFAULTS do
    if not MatchText('-' + D, AConfigured) then Result:= Result + [D];
  for var C: string in AConfigured do
    if (Trim(C) <> '') and not C.StartsWith('-') then Result:= Result + [LowerCase(Trim(C))];
end;

{ The file's text, or False when it cannot be opened (a locked project file is no lint failure). }
function TryReadText(const AFile: string; out AText: string): Boolean;
var
  Handle: THandle;
  Bytes : TBytes ;
begin
  AText := '';
  Handle:= FileOpen(AFile, fmOpenRead or fmShareDenyNone);
  Result:= Handle <> INVALID_HANDLE_VALUE;
  if not Result then Exit;
  try
    SetLength(Bytes, FileSeek(Handle, 0, Ord(soEnd)));
    FileSeek(Handle, 0, Ord(soBeginning));
    FileRead(Handle, Bytes, Length(Bytes));
    AText:= TEncoding.ANSI.GetString(Bytes);
  finally
    FileClose(Handle);
  end;
end;

function MakeLibraryScope(const AAll, ADeclared: TArray<string>; const AProjectFile: string): TLibraryScope;
begin
  Result:= Default(TLibraryScope);
  Result.Declared:= ADeclared;
  for var R: string in AAll do
    if not MatchText(R, ADeclared) then Result.Registry:= Result.Registry + [R];
  if AProjectFile = '' then Exit;
  var Files: TArray<string>:= [AProjectFile];
  for var Ext: string in ['.dpr', '.dpk', '.dproj'] do
    if not SameText(ExtractFileExt(AProjectFile), Ext) then Files:= Files + [ChangeFileExt(AProjectFile, Ext)];
  for var F: string in Files do
  begin
    if not TFile.Exists(F) then Continue;
    var Text: string;
    { unreadable: what the project lists is unknown, so the inferred roots are no signal }
    if not TryReadText(F, Text) then Result.Registry:= nil;
    { `X in '..\a\X.pas'` in the program file, Include="..\a\X.pas" in the .dproj }
    for var M: TMatch in TRegEx.Matches(Text, '([^\\/''"<>|]+\.pas)[''"]', [roIgnoreCase]) do
      Result.Listed:= Result.Listed + [LowerCase(M.Groups[1].Value)];
  end;
end;

function MakeOwnFilter(const ASetup: TOwnFilterSetup): IOwnFilter;
begin
  Result:= TOwnFilter.Create(ASetup);
end;

constructor TOwnFilter.Create(const ASetup: TOwnFilterSetup);
begin
  inherited Create;
  FSetup := ASetup;
  FNames := VendoredFolderNames(ASetup.Cfg.VendoredFolders);
  FMemo  := TDictionary<string, TSkipReason>.Create(TIStringComparer.Ordinal);
  FWhere := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  FGroups:= TDictionary<string, TSkipCount>.Create;
  FRules := TDictionary<string, Integer>.Create;
end;

destructor TOwnFilter.Destroy;
begin
  FRules.Free;
  FGroups.Free;
  FWhere.Free;
  FMemo.Free;
  inherited;
end;

{ The vendored folder name on APath's way, or ''. A folder that holds the project itself says nothing
  (the project is developed there), nor does one at or above an own root that holds the file (the
  declaration is more specific than the name). }
function TOwnFilter.VendoredName(const APath: string): string;
begin
  Result:= '';
  var Anchor: string:= IncludeTrailingPathDelimiter(FullPath(FSetup.Own.Anchor));
  var Root  : string:= HoldingDir(APath, FSetup.Own.Roots);
  var Dir   : string:= ExtractFileDir(APath);
  while ExtractFileName(Dir) <> '' do
  begin
    if MatchText(ExtractFileName(Dir), FNames) and not StartsText(Dir + '\', Anchor) and not StartsText(Dir + '\', Root) then
      Exit(LowerCase(ExtractFileName(Dir)));
    Dir:= ExtractFileDir(Dir);
  end;
end;

{ The library root that holds APath, or ''. A root that also holds the project is no signal; a registry
  root yields to the project file listing the unit (COMMON on the IDE library path is still own). }
function TOwnFilter.LibraryRoot(const APath: string): string;
begin
  if not FLibLoaded then
  begin
    FLibLoaded:= True;
    if Assigned(FSetup.Libraries) then FLib:= FSetup.Libraries();
  end;
  var Anchor: string:= IncludeTrailingPathDelimiter(FullPath(FSetup.Own.Anchor));
  Result:= HoldingDir(APath, FLib.Declared);
  if (Result = '') and not MatchText(ExtractFileName(APath), FLib.Listed) then Result:= HoldingDir(APath, FLib.Registry);
  if (Result <> '') and StartsText(Result, Anchor) then Result:= '';
end;

{ The order is the contract (wiki page): explicit exclusion, explicit ownership, inferred signals, own. }
function TOwnFilter.Classify(const APath: string; out AWhere: string): TSkipReason;
var
  Excluded: string;
  Vendored: string;
  Lib     : string;
begin
  AWhere:= '';
  Result:= srOwn;
  Excluded:= HoldingDir(APath, FSetup.Own.ExcludeRoots);
  if Excluded <> '' then
  begin
    AWhere:= 'excludeRoots ' + ExcludeTrailingPathDelimiter(Excluded);
    Exit(srExcludeRoots);
  end;
  if TLintConfig.MatchesAnyGlob(APath, FSetup.Cfg.OwnPaths) then Exit;
  Vendored:= VendoredName(APath);
  if Vendored <> '' then
  begin
    AWhere:= Format('vendored folder ''%s''', [Vendored]);
    Exit(srVendoredFolder);
  end;
  if HoldingDir(APath, FSetup.Own.Roots) <> '' then Exit;
  Lib:= if FSetup.Own.Declared then '' else LibraryRoot(APath);
  if FSetup.Own.Declared then
  begin
    AWhere:= 'outside the declared ownRoots';
    Result:= srOutsideOwnRoots;
  end
  else if Lib <> '' then
  begin
    AWhere:= 'library path ' + ExcludeTrailingPathDelimiter(Lib);
    Result:= srLibraryPath;
  end
  else if FSetup.FixRun then
  begin
    AWhere:= 'outside the own roots (a --fix run writes only inside them)';
    Result:= srOutsideFixScope;
  end;
end;

function TOwnFilter.Judge(const AFilePath: string): TSkipReason;
begin
  Result:= srOwn;
  if (AFilePath = '') or FSetup.ShowAll or not FSetup.Own.Active then Exit;
  if FMemo.TryGetValue(AFilePath, Result) then Exit;
  var Where: string;
  Result:= Classify(FullPath(AFilePath), Where);
  FMemo.Add(AFilePath, Result);
  if Where <> '' then FWhere.AddOrSetValue(AFilePath, Where);
end;

function TOwnFilter.GroupText(const AFilePath: string; AReason: TSkipReason): string;
begin
  if not FWhere.TryGetValue(AFilePath, Result) then
    Result:= if AReason = srExcludePaths then 'exclude_paths' else REASON_CODES[AReason];
end;

procedure TOwnFilter.Bump(const AGroup: string; AReason: TSkipReason; AFiles, AFindings: Integer);
var
  C: TSkipCount;
begin
  if not FGroups.TryGetValue(AGroup, C) then C:= Default(TSkipCount);
  C.Reason:= AReason;
  Inc(C.Files, AFiles);
  Inc(C.Findings, AFindings);
  FGroups.AddOrSetValue(AGroup, C);
  if AReason = srExcludePaths then Exit;
  Inc(FFiles, AFiles);
  Inc(FFindings, AFindings);
end;

procedure TOwnFilter.NoteFile(const AFilePath: string; AReason: TSkipReason);
begin
  if AReason <> srOwn then Bump(GroupText(AFilePath, AReason), AReason, 1, 0)
  else if FSetup.Own.Active and not FSetup.ShowAll and not FSetup.Own.Declared and (HoldingDir(FullPath(AFilePath), FSetup.Own.Roots) = '') then
    Inc(FKeptOutside);
end;

procedure TOwnFilter.NoteFinding(const AFilePath, ARuleId: string; AReason: TSkipReason);
var
  N: Integer;
begin
  if (AReason = srOwn) or (Assigned(FSetup.Counts) and not FSetup.Counts(ARuleId)) then Exit;
  Bump(GroupText(AFilePath, AReason), AReason, 0, 1);
  if AReason = srExcludePaths then Exit;
  if not FRules.TryGetValue(ARuleId, N) then N:= 0;
  FRules.AddOrSetValue(ARuleId, N + 1);
end;

function TOwnFilter.KeptOutside: Integer;
begin
  Result:= FKeptOutside;
end;

function TOwnFilter.SortedGroups: TArray<string>;
begin
  Result:= FGroups.Keys.ToArray;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      Result:= FGroups[R].Files - FGroups[L].Files;
      if Result = 0 then Result:= CompareText(L, R);
    end));
end;

function TOwnFilter.SortedRules: TArray<string>;
begin
  Result:= FRules.Keys.ToArray;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      Result:= FRules[R] - FRules[L];
      if Result = 0 then Result:= CompareText(L, R);
    end));
end;

function TOwnFilter.SummaryLines: TArray<string>;
begin
  Result:= nil;
  if (FFiles > 0) or (FFindings > 0) then
    Result:= [Format('lint-all: third-party: %d file(s) not scanned, %d project-wide finding(s) dropped (per-file rules did not run there); ' +
      '--lint-third-party shows them', [FFiles, FFindings])];
  for var G: string in SortedGroups do
    Result:= Result + [Format('          %s: %d file(s), %d finding(s)', [G, FGroups[G].Files, FGroups[G].Findings])];
  if FRules.Count = 0 then Exit;
  var Named: string:= '';
  var Ids: TArray<string>:= SortedRules;
  for var I: Integer:= 0 to High(Ids) do
    if I < MAX_RULES_NAMED then
      Named:= Named + (if I = 0 then '' else ', ') + Format('%s %d', [Ids[I], FRules[Ids[I]]]);
  if Length(Ids) > MAX_RULES_NAMED then Named:= Named + Format(', + %d more rule(s)', [Length(Ids) - MAX_RULES_NAMED]);
  Result:= Result + ['          dropped by rule: ' + Named];
end;

function TOwnFilter.SummarySuffix: string;
begin
  Result:= if FFiles = 0 then '' else Format('; %d third-party file(s) skipped', [FFiles]);
end;

function TOwnFilter.JsonRow: TJSONObject;
begin
  Result:= nil;
  if (FFiles = 0) and (FFindings = 0) then Exit;
  Result:= TJSONObject.Create;
  Result.AddPair('rule', THIRD_PARTY_SKIPPED_ROW);
  Result.AddPair('severity', 'info');
  Result.AddPair('file_path', FSetup.Own.Anchor);
  for var Pos: string in ['start_line', 'start_col', 'end_line', 'end_col'] do Result.AddPair(Pos, TJSONNumber.Create(0));
  Result.AddPair('message', Format('%d third-party file(s) not scanned, %d project-wide finding(s) dropped; --lint-third-party shows them',
    [FFiles, FFindings]));
  Result.AddPair('files_skipped', TJSONNumber.Create(FFiles));
  Result.AddPair('findings_dropped', TJSONNumber.Create(FFindings));
  Result.AddPair('show_with', '--lint-third-party');
  var Reasons: TJSONArray:= TJSONArray.Create;
  Result.AddPair('reasons', Reasons);
  for var G: string in SortedGroups do
  begin
    var O: TJSONObject:= TJSONObject.Create;
    Reasons.AddElement(O);
    O.AddPair('reason', REASON_CODES[FGroups[G].Reason]);
    O.AddPair('where', G);
    O.AddPair('files', TJSONNumber.Create(FGroups[G].Files));
    O.AddPair('findings', TJSONNumber.Create(FGroups[G].Findings));
  end;
  var Rules: TJSONObject:= TJSONObject.Create;
  Result.AddPair('rules', Rules);
  for var R: string in SortedRules do Rules.AddPair(R, TJSONNumber.Create(FRules[R]));
end;

end.