unit ConvRules.UsesHarvest;

{ Pure harvest model behind the Unit Rules tab's Add source / drop / paste
  (spec docs\superpowers\specs\2026-09-28-unit-rules-harvest-and-missing-design.md).
  Everything here is pure except HarvestFiles, the one routine that reads the
  disk. The VCL form only renders what these return; ConvRulesModelTests.dpr
  pins every rule, because the form unit is outside its closure. }

interface

uses
  System.SysUtils
  , ConvRules.Platform
  ;

type
  /// <summary>One used unit found in a source.</summary>
  THarvestedUnit = record
    /// <summary>The unit name as written; dotted names are kept whole.</summary>
    UnitName: string;
    /// <summary>'interface' or 'implementation' for a .pas; '' for pasted text
    /// and for a .dpr's own uses clause.</summary>
    Section : string;
    /// <summary>The unit or project that uses it; PASTED_SOURCE for text.</summary>
    UsedBy  : string;
  end;

  /// <summary>One entry of a .dpr uses clause.</summary>
  TDprMember = record
    /// <summary>The unit name as written.</summary>
    UnitName: string;
    /// <summary>Absolute path from the entry's `in '...'` part; '' for a plain
    /// entry such as `Vcl.Forms`.</summary>
    FilePath: string;
  end;

  /// <summary>What the classifier needs from a destination .dproj, for ONE platform.</summary>
  TProjectSettings = record
    /// <summary>The .dproj's folder, no trailing delimiter.</summary>
    ProjectDir: string;
    /// <summary>Absolute path of the .dpr named by MainSource; '' when absent.</summary>
    MainSource: string;
    /// <summary>Absolute search-path folders, compiler order, de-duplicated.</summary>
    SearchPath: TArray<string>;
    /// <summary>Unit scope names, compiler order, de-duplicated.</summary>
    Scopes    : TArray<string>;
    /// <summary>Entries dropped because they hold an unexpanded $(...) macro.</summary>
    Skipped   : TArray<string>;
  end;

const
  /// <summary>UsedBy value for units that came from dropped or pasted text.</summary>
  PASTED_SOURCE = '(pasted)';

/// <summary>Used units named by a piece of dropped or pasted text.</summary>
/// <param name="AText">Any text. When it contains the keyword `uses` it is read
/// as Delphi source (comments, strings and `in '...'` handled by
/// ScanUsesClausesSectioned); otherwise it is split on commas, semicolons and
/// whitespace and only identifier-shaped tokens (dotted allowed) are kept.</param>
/// <returns>First occurrence wins, case-insensitively; Section is always '' and
/// UsedBy is PASTED_SOURCE.</returns>
function HarvestText(const AText: string): TArray<THarvestedUnit>;

/// <summary>The entries of a .dpr's uses clause, with `in` paths made absolute.</summary>
/// <param name="ADprText">The whole .dpr text.</param>
/// <param name="ADprDir">The .dpr's folder; relative `in` paths resolve against it.</param>
/// <returns>Source order, de-duplicated case-insensitively.</returns>
function ReadDprMembers(const ADprText, ADprDir: string): TArray<TDprMember>;

/// <summary>AExisting followed by the units of AAdded it does not already hold.</summary>
/// <param name="AExisting">The current list; its entries win on a name clash.</param>
/// <param name="AAdded">Units to merge in.</param>
/// <returns>The merged list; comparison is case-insensitive.</returns>
function MergeHarvest(const AExisting, AAdded: TArray<THarvestedUnit>): TArray<THarvestedUnit>;

/// <summary>AUnits without the entry named AName (case-insensitive).</summary>
/// <param name="AUnits">The list.</param>
/// <param name="AName">The unit to drop.</param>
/// <returns>A new array; AUnits is not modified.</returns>
function WithoutUnit(const AUnits: TArray<THarvestedUnit>; const AName: string): TArray<THarvestedUnit>;

/// <summary>Index of AName in AUnits, case-insensitive; -1 when absent.</summary>
/// <param name="AUnits">The list.</param>
/// <param name="AName">The unit name.</param>
/// <returns>The index, or -1.</returns>
function IndexOfUnit(const AUnits: TArray<THarvestedUnit>; const AName: string): Integer;

/// <summary>The Flag column text for a harvested unit.</summary>
/// <param name="AUnit">The harvested unit.</param>
/// <returns>'interface, U1' when a section is known, else just UsedBy.</returns>
function HarvestFlagText(const AUnit: THarvestedUnit): string;

/// <summary>Absolute path of the .dpr a .dproj names in MainSource.</summary>
/// <param name="ADprojText">The .dproj XML text.</param>
/// <param name="ADprojDir">The .dproj's folder.</param>
/// <returns>The path, or '' when there is no MainSource element.</returns>
function MainSourceOf(const ADprojText, ADprojDir: string): string;

/// <summary>Search path, scope names and main source of a .dproj, for one platform.</summary>
/// <param name="ADprojText">The .dproj XML text.</param>
/// <param name="ADprojDir">The .dproj's folder; relative entries resolve against it.</param>
/// <param name="APlatform">cpWin32 or cpWin64; cpBoth reads Win64.</param>
/// <returns>The settings. Only the `'$(Base)'!=''` and `'$(Base_&lt;P&gt;)'!=''`
/// groups are read, in document order; `$(DCC_UnitSearchPath)` and
/// `$(DCC_Namespace)` in a value expand to the value accumulated so far.</returns>
/// <remarks>Build-configuration groups (Cfg_n) are NOT read -- a spec decision,
/// not an oversight. An entry still holding `$(` after expansion goes to Skipped.</remarks>
function ReadProjectSettings(const ADprojText, ADprojDir: string; APlatform: TConvPlatform): TProjectSettings;

/// <summary>The .dproj that owns a project index.</summary>
/// <param name="AProjectDb">A path like `C:\P\App\_D-RAG\App.sqlite`.</param>
/// <returns>`C:\P\App\App.dproj` when the DB sits in a `_D-RAG` folder, else ''.
/// Pure: existence is NOT checked.</returns>
function ProjectFileForDb(const AProjectDb: string): string;

/// <summary>Harvest the used units of source files.</summary>
/// <param name="APaths">.pas files (their uses clauses), .dpr files (the clause
/// plus every member file that exists), .dproj files (their MainSource .dpr).</param>
/// <param name="AErrors">One human-readable line per file that was skipped:
/// unreadable, wrong extension, missing MainSource, missing member.</param>
/// <returns>The merged harvest, first occurrence winning.</returns>
/// <remarks>Reads the disk. One level only: a used unit that is not a member
/// is listed but its own uses are not followed.</remarks>
function HarvestFiles(const APaths: TArray<string>; out AErrors: TArray<string>): TArray<THarvestedUnit>;

implementation

uses
  System.Generics.Collections
  , System.IOUtils
  , System.RegularExpressions
  , System.StrUtils
  , ConvRules.Usage
  ;

const
  IDENT_RE    = '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$';
  USES_RE     = '(^|[^A-Za-z0-9_.])uses($|[^A-Za-z0-9_])';
  DPR_IN_RE   = '([A-Za-z_][A-Za-z0-9_.]*)\s+in\s+''([^'']+)''';
  NOT_FOUND   = -1;

function MakeUnit(const AName, ASection, AUsedBy: string): THarvestedUnit;
begin
  Result.UnitName:= AName;
  Result.Section := ASection;
  Result.UsedBy  := AUsedBy;
end;

function IndexOfUnit(const AUnits: TArray<THarvestedUnit>; const AName: string): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(AUnits) do
    if SameText(AUnits[i].UnitName, AName) then
      Exit(i);
  Result:= NOT_FOUND;
end;

function MergeHarvest(const AExisting, AAdded: TArray<THarvestedUnit>): TArray<THarvestedUnit>;
var
  H: THarvestedUnit;
begin
  Result:= AExisting;
  for H in AAdded do
    if IndexOfUnit(Result, H.UnitName) = NOT_FOUND then
      Result:= Result + [H];
end;

function WithoutUnit(const AUnits: TArray<THarvestedUnit>; const AName: string): TArray<THarvestedUnit>;
var
  H: THarvestedUnit;
begin
  Result:= nil;
  for H in AUnits do
    if not SameText(H.UnitName, AName) then
      Result:= Result + [H];
end;

function HarvestFlagText(const AUnit: THarvestedUnit): string;
begin
  if AUnit.Section = '' then
    Result:= AUnit.UsedBy
  else
    Result:= AUnit.Section + ', ' + AUnit.UsedBy;
end;

{ .pas (or .dpr) text -> harvested units; AKeepSection False blanks the section
  for sources where interface/implementation means nothing. }
function HarvestPasText(const AText, AUsedBy: string; AKeepSection: Boolean): TArray<THarvestedUnit>;
var
  R: TUsedUnitRef;
begin
  Result:= nil;
  for R in ScanUsesClausesSectioned(AText) do
    if AKeepSection then
      Result:= Result + [MakeUnit(R.UnitName, R.Section, AUsedBy)]
    else
      Result:= Result + [MakeUnit(R.UnitName, '', AUsedBy)];
end;

function HarvestText(const AText: string): TArray<THarvestedUnit>;
var
  Tok: string;
begin
  if TRegEx.IsMatch(AText, USES_RE, [roIgnoreCase]) then
    Exit(HarvestPasText(AText, PASTED_SOURCE, False));
  Result:= nil;
  for Tok in AText.Split([',', ';', ' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty) do
    if TRegEx.IsMatch(Tok, IDENT_RE) and (IndexOfUnit(Result, Tok) = NOT_FOUND) then
      Result:= Result + [MakeUnit(Tok, '', PASTED_SOURCE)];
end;

function ReadDprMembers(const ADprText, ADprDir: string): TArray<TDprMember>;
var
  Paths: TDictionary<string, string>;
  M    : TMatch;
  R    : TUsedUnitRef;
  D    : TDprMember;
  Rel  : string;
begin
  Result:= nil;
  Paths:= TDictionary<string, string>.Create;
  try
    for M in TRegEx.Matches(ADprText, DPR_IN_RE, [roIgnoreCase]) do
      if not Paths.ContainsKey(UpperCase(M.Groups[1].Value)) then
        Paths.Add(UpperCase(M.Groups[1].Value), M.Groups[2].Value);
    for R in ScanUsesClausesSectioned(ADprText) do
    begin
      D.UnitName:= R.UnitName;
      D.FilePath:= '';
      if Paths.TryGetValue(UpperCase(R.UnitName), Rel) then
        D.FilePath:= TPath.GetFullPath(TPath.Combine(ADprDir, Rel));
      Result:= Result + [D];
    end;
  finally
    Paths.Free;
  end;
end;

const
  GROUP_RE       = '<PropertyGroup\s+Condition="([^"]*)"\s*>(.*?)</PropertyGroup>';
  MAINSOURCE_RE  = '<MainSource>\s*([^<]+?)\s*</MainSource>';
  SEARCH_RE      = '<DCC_UnitSearchPath>(.*?)</DCC_UnitSearchPath>';
  NAMESPACE_RE   = '<DCC_Namespace>(.*?)</DCC_Namespace>';
  SEARCH_SELF    = '$(DCC_UnitSearchPath)';
  NAMESPACE_SELF = '$(DCC_Namespace)';
  BASE_COND      = '''$(base)''!=''''';
  PLAT_COND_FMT  = '''$(base_%s)''!=''''';
  MACRO_MARK     = '$(';
  EXT_PAS        = '.pas';
  EXT_DPR        = '.dpr';
  EXT_DPROJ      = '.dproj';
  DRAG_FOLDER    = '_D-RAG';

function MainSourceOf(const ADprojText, ADprojDir: string): string;
var
  M: TMatch;
begin
  M:= TRegEx.Match(ADprojText, MAINSOURCE_RE, [roIgnoreCase]);
  if M.Success then
    Result:= TPath.GetFullPath(TPath.Combine(ADprojDir, M.Groups[1].Value))
  else
    Result:= '';
end;

{ ';'-separated list -> trimmed, non-empty, de-duplicated (case-insensitive). }
function SplitList(const AValue: string): TArray<string>;
var
  S: string;
begin
  Result:= nil;
  for S in AValue.Split([';']) do
    if (Trim(S) <> '') and (IndexText(Trim(S), Result) = NOT_FOUND) then
      Result:= Result + [Trim(S)];
end;

function ReadProjectSettings(const ADprojText, ADprojDir: string; APlatform: TConvPlatform): TProjectSettings;
var
  PlatCond : string;
  SearchRaw: string;
  NsRaw    : string;
  Cond     : string;
  M        : TMatch;
  V        : TMatch;
  E        : string;
  Full     : string;
begin
  if APlatform = cpWin32 then
    PlatCond:= Format(PLAT_COND_FMT, ['win32'])
  else
    PlatCond:= Format(PLAT_COND_FMT, ['win64']);
  Result.ProjectDir:= ExcludeTrailingPathDelimiter(ADprojDir);
  Result.MainSource:= MainSourceOf(ADprojText, ADprojDir);
  Result.SearchPath:= nil;
  Result.Scopes    := nil;
  Result.Skipped   := nil;
  SearchRaw:= '';
  NsRaw    := '';
  for M in TRegEx.Matches(ADprojText, GROUP_RE, [roIgnoreCase, roSingleLine]) do
  begin
    Cond:= LowerCase(StringReplace(M.Groups[1].Value, ' ', '', [rfReplaceAll]));
    if (Cond <> BASE_COND) and (Cond <> PlatCond) then
      Continue;
    V:= TRegEx.Match(M.Groups[2].Value, SEARCH_RE, [roIgnoreCase, roSingleLine]);
    if V.Success then
      SearchRaw:= StringReplace(V.Groups[1].Value, SEARCH_SELF, SearchRaw, [rfReplaceAll, rfIgnoreCase]);
    V:= TRegEx.Match(M.Groups[2].Value, NAMESPACE_RE, [roIgnoreCase, roSingleLine]);
    if V.Success then
      NsRaw:= StringReplace(V.Groups[1].Value, NAMESPACE_SELF, NsRaw, [rfReplaceAll, rfIgnoreCase]);
  end;
  for E in SplitList(NsRaw) do
    if Pos(MACRO_MARK, E) > 0 then
      Result.Skipped:= Result.Skipped + [E]
    else
      Result.Scopes:= Result.Scopes + [E];
  for E in SplitList(SearchRaw) do
    if Pos(MACRO_MARK, E) > 0 then
      Result.Skipped:= Result.Skipped + [E]
    else
    begin
      Full:= ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ADprojDir, E)));
      if IndexText(Full, Result.SearchPath) = NOT_FOUND then
        Result.SearchPath:= Result.SearchPath + [Full];
    end;
end;

function ProjectFileForDb(const AProjectDb: string): string;
var
  Dir: string;
begin
  Result:= '';
  if AProjectDb = '' then
    Exit;
  Dir:= ExtractFileDir(AProjectDb);
  if not SameText(ExtractFileName(Dir), DRAG_FOLDER) then
    Exit;
  Result:= TPath.Combine(ExtractFileDir(Dir), ChangeFileExt(ExtractFileName(AProjectDb), EXT_DPROJ));
end;

{ A .dpr: its own clause (UsedBy = project name, no section) plus each member
  file that exists. A member whose `in` file is missing is reported, not fatal. }
function HarvestDpr(const ADprPath: string; var AErrors: TArray<string>): TArray<THarvestedUnit>;
var
  Text: string;
  D   : TDprMember;
begin
  Text:= TFile.ReadAllText(ADprPath);
  Result:= HarvestPasText(Text, ChangeFileExt(ExtractFileName(ADprPath), ''), False);
  for D in ReadDprMembers(Text, ExtractFileDir(ADprPath)) do
  begin
    if D.FilePath = '' then
      Continue;
    if not TFile.Exists(D.FilePath) then
    begin
      AErrors:= AErrors + [Format('%s: member %s not found (%s)', [ExtractFileName(ADprPath), D.UnitName, D.FilePath])];
      Continue;
    end;
    Result:= MergeHarvest(Result, HarvestPasText(TFile.ReadAllText(D.FilePath), D.UnitName, True));
  end;
end;

function HarvestFiles(const APaths: TArray<string>; out AErrors: TArray<string>): TArray<THarvestedUnit>;
var
  P  : string;
  Ext: string;
  Dpr: string;
begin
  Result := nil;
  AErrors:= nil;
  for P in APaths do
  try
    Ext:= LowerCase(ExtractFileExt(P));
    if Ext = EXT_PAS then
      Result:= MergeHarvest(Result, HarvestPasText(TFile.ReadAllText(P), ChangeFileExt(ExtractFileName(P), ''), True))
    else if Ext = EXT_DPR then
      Result:= MergeHarvest(Result, HarvestDpr(P, AErrors))
    else if Ext = EXT_DPROJ then
    begin
      Dpr:= MainSourceOf(TFile.ReadAllText(P), ExtractFileDir(P));
      if (Dpr = '') or not TFile.Exists(Dpr) then
        AErrors:= AErrors + [Format('%s: no MainSource .dpr found', [ExtractFileName(P)])]
      else
        Result:= MergeHarvest(Result, HarvestDpr(Dpr, AErrors));
    end
    else
      AErrors:= AErrors + [Format('%s: not a .pas/.dpr/.dproj -- ignored', [ExtractFileName(P)])];
  except
    on E: Exception do
      AErrors:= AErrors + [Format('%s: %s', [ExtractFileName(P), E.Message])];
  end;
end;

end.
