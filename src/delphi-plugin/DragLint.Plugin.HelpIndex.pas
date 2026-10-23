unit DragLint.Plugin.HelpIndex;

{ The pure half of the IDE help line (spec docs\superpowers\specs\
  2026-10-23-ide-help-line-design.md, sections 3.1-3.3): help-root URL rules,
  the offline feature list (WWW\help\dl\index.json) and the matcher.
  No VCL, no ToolsAPI -- tests\autotest\run_plugin_help_line.ps1 builds it
  headless. }

interface

const
  /// <summary>The help root used when the setting is empty or missing: the
  /// public website.</summary>
  DL_DEFAULT_HELP_ROOT = 'https://www.delphi-rag-lint.com';

  /// <summary>Where the offline feature list sits below a root folder
  /// (engine dir, file: help root, or the repo root).</summary>
  DL_HELP_INDEX_REL = 'help\dl\index.json';

type
  /// <summary>One row of WWW\help\dl\index.json -- one published feature.</summary>
  /// <remarks>Menus / Context / Verb are optional in the file (CONVERTER's
  /// featuregen adds them); absent fields read as an empty array / ''.
  /// Unknown fields are ignored.</remarks>
  TDLHelpEntry = record
    Id      : string;
    Title   : string;
    Summary : string;
    Group   : string;
    FileName: string;
    /// <summary>The cli verb, '' when the feature has none.</summary>
    Verb    : string;
    /// <summary>Full ide-menu paths ("drag-lint &gt; ... &gt; Caption"), in entry order.</summary>
    Menus   : TArray<string>;
    /// <summary>Full ide-context paths, in entry order.</summary>
    Context : TArray<string>;
  end; // record

  /// <summary>The parsed offline feature list, with a cheap staleness check.</summary>
  /// <remarks>Not thread-safe; the help line uses it from the main thread only.
  /// A failed load never raises: Loaded is False, Entries is empty and
  /// LastError says why.</remarks>
  TDLHelpIndex = class
  private
    FEntries  : TArray<TDLHelpEntry>;
    FLoaded   : Boolean;
    FLastError: string;
    FFileName : string;
    FFileSize : Int64;
    FFileTime : TDateTime;
    function GetCount: Integer;
  public
    /// <summary>Parses an index.json file, replacing any previous content.</summary>
    /// <param name="pPath">Full path of the JSON file (UTF-8, a top-level array).</param>
    /// <returns>True when the file was read and parsed; False otherwise
    /// (Loaded = False, no rows, LastError non-empty).</returns>
    function LoadFromFile(const pPath: string): Boolean;
    /// <summary>Reloads the last loaded file when its size or mtime changed.</summary>
    /// <returns>True when a reload happened; False when unchanged or nothing
    /// was ever loaded.</returns>
    function ReloadIfChanged: Boolean;
    /// <summary>The rows, in file order.</summary>
    property Entries  : TArray<TDLHelpEntry> read FEntries;
    /// <summary>Number of rows.</summary>
    property Count    : Integer read GetCount;
    /// <summary>True after a successful LoadFromFile.</summary>
    property Loaded   : Boolean read FLoaded;
    /// <summary>Why the last load failed; '' after a success.</summary>
    property LastError: string read FLastError;
    /// <summary>The file last passed to LoadFromFile.</summary>
    property FileName : string read FFileName;
  end; // class

  /// <summary>One match of the help line, ready to show.</summary>
  TDLHelpHit = record
    /// <summary>Registry id -- what DLOpenHelp is called with.</summary>
    Id     : string;
    Title  : string;
    /// <summary>What the list shows (DLHelpDisplayText).</summary>
    Display: string;
    /// <summary>0 title starts with the query, 1 title contains it, 2 a menu or
    /// context caption contains it, 3 the id or verb contains it.</summary>
    Rank   : Integer;
  end; // record

const
  /// <summary>Most hits DLHelpMatch returns.</summary>
  DL_HELP_MAX_HITS = 12;

/// <summary>Matches a half-remembered feature name against the feature list (spec 3.3).</summary>
/// <param name="pQuery">What the user typed; trimmed, case-insensitive.</param>
/// <param name="pEntries">The rows of a loaded TDLHelpIndex.</param>
/// <returns>At most DL_HELP_MAX_HITS hits ordered by Rank, then title
/// (case-insensitive); empty for an empty query. A row is a hit when the query
/// is a substring of its title, id, verb, or the LAST segment (caption) of
/// any menu or context path. The summary is never searched.</returns>
function DLHelpMatch(const pQuery: string; const pEntries: TArray<TDLHelpEntry>): TArray<TDLHelpHit>;

/// <summary>The text a hit shows in the help line's list.</summary>
/// <param name="pEntry">One feature row.</param>
/// <returns>"&lt;title&gt; - &lt;shortest menu path&gt;"; with no menu the shortest
/// context path; with neither "&lt;title&gt; - CLI: drag-lint &lt;verb&gt;"; else the title.</returns>
function DLHelpDisplayText(const pEntry: TDLHelpEntry): string;

/// <summary>Resolves a menu (or tab) caption to the registry id whose menu or
/// context path ends with that caption (spec 3.5 -- no table in code).</summary>
/// <param name="pCaption">A VCL caption; '&amp;' accelerators are ignored
/// ('&amp;&amp;' is a literal '&amp;').</param>
/// <param name="pEntries">The rows of a loaded TDLHelpIndex.</param>
/// <returns>The first matching id in file order (menus before context); ''
/// when no path ends with the caption.</returns>
function DLHelpIdForMenuCaption(const pCaption: string; const pEntries: TArray<TDLHelpEntry>): string;

/// <summary>The registry id F1 opens for a drag-lint dock tab (spec 3.5).</summary>
/// <param name="pTabCaption">The active tab's caption ('Call Graph', 'Uses &amp;&amp; Deps'...).</param>
/// <param name="pEntries">The rows of the loaded feature list; may be empty.</param>
/// <returns>DLHelpIdForMenuCaption first (a menu caption IS the link); else the
/// six dock tabs resolved with featuregen find on 2026-10-23 -- Structure:
/// show-structure, Search (no grep): symbol-search, Find Usages: find-usages,
/// Lint Options: drag-lint-project-rules, Uses &amp; Deps: uses-deps-tab, Call
/// Graph: call-graph-butterfly; else 'drag-lint' (the tool-window entry).</returns>
function DLHelpIdForDockTab(const pTabCaption: string; const pEntries: TArray<TDLHelpEntry>): string;

/// <summary>The URL DLOpenHelp opens for a registry id (spec 3.5).</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <param name="pFeatureId">Registry id.</param>
/// <param name="pIndex">The loaded feature list, or nil.</param>
/// <returns>The feature page; the all-features page instead when a LOADED list
/// does not carry the id (a feature without a page is never a soft 404). With no
/// list (nil, or not loaded) the feature page, unchecked.</returns>
function DLResolveHelpUrl(const pRoot, pFeatureId: string; const pIndex: TDLHelpIndex): string;

/// <summary>Finds the offline feature list (spec 3.2), first hit wins.</summary>
/// <param name="pEngineDir">Folder of the resolved drag-lint.exe; may be ''.</param>
/// <param name="pHelpRoot">The HelpRoot setting; only a file: root is probed.</param>
/// <param name="pBplDir">Folder of the plugin BPL; the dev checkout is probed
/// at &lt;pBplDir&gt;\..\..\WWW\help\dl\index.json.</param>
/// <returns>&lt;engine dir&gt;\help\dl\index.json, else &lt;file root&gt;\help\dl\index.json,
/// else the dev-tree path -- whichever exists first; '' when none exists.</returns>
function DLLocateHelpIndex(const pEngineDir, pHelpRoot, pBplDir: string): string;

/// <summary>Normalises a help root as typed by the user into the stored form.</summary>
/// <param name="pRoot">An http(s) URL, a file:/// URL or a plain Windows folder;
/// may carry trailing slashes or surrounding blanks.</param>
/// <returns>DL_DEFAULT_HELP_ROOT for an empty value; a folder becomes
/// file:///C:/dir (forward slashes); trailing slashes are removed.</returns>
function DLNormaliseHelpRoot(const pRoot: string): string;

/// <summary>Builds the help page URL of one registry feature.</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <param name="pFeatureId">Registry id (features\entries\&lt;id&gt;.json); empty
/// gives the all-features URL.</param>
/// <returns>&lt;root&gt;/help/dl/features/&lt;id&gt;/ for a web root;
/// the same plus index.html for a file: root (the rendered site tree).</returns>
function DLHelpUrl(const pRoot, pFeatureId: string): string;

/// <summary>URL of the complete feature list: &lt;root&gt;/help/dl/ (plus
/// index.html for a file: root).</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <returns>The all-features URL.</returns>
function DLHelpAllUrl(const pRoot: string): string;

/// <summary>URL of the IDE menu tree page: &lt;root&gt;/help/dl/ide/ (plus
/// index.html for a file: root).</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <returns>The menu-tree URL.</returns>
function DLHelpIdeUrl(const pRoot: string): string;

/// <summary>The local folder behind a file: root (file:///C:/dl-help -> C:\dl-help).</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <returns>The Windows folder without a trailing backslash; '' for a web root.</returns>
function DLHelpRootFolder(const pRoot: string): string;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.JSON
  , System.DateUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  ;

const
  FILE_SCHEME = 'file:///';
  HELP_DL     = '/help/dl/';
  INDEX_HTML  = 'index.html';

function StripTrailingSlashes(const pValue: string): string;
begin
  Result:= pValue;
  while (Result <> '') and CharInSet(Result[Length(Result)], ['/', '\']) do
    SetLength(Result, Length(Result) - 1);
end; // function

function DLNormaliseHelpRoot(const pRoot: string): string;
begin
  Result:= Trim(pRoot);
  if Result = '' then Exit(DL_DEFAULT_HELP_ROOT);
  if Result.StartsWith('http://', True) or Result.StartsWith('https://', True) then
    Exit(StripTrailingSlashes(Result));
  { A file: URL as typed, or a plain folder (C:\dir, \\server\share): one
    canonical file:/// form with forward slashes. }
  if Result.StartsWith('file:', True) then
  begin
    Result:= Result.Substring(Length('file:'));
    while Result.StartsWith('/') or Result.StartsWith('\') do Result:= Result.Substring(1);
  end; // if
  Result:= StripTrailingSlashes(Result.Replace('\', '/'));
  Result:= FILE_SCHEME + Result;
end; // function

function DLHelpRootFolder(const pRoot: string): string;
var
  Root: string;
begin
  Root:= DLNormaliseHelpRoot(pRoot);
  if not Root.StartsWith(FILE_SCHEME, True) then Exit('');
  Result:= Root.Substring(Length(FILE_SCHEME)).Replace('/', '\');
end; // function

{ <root>/help/dl/<pRel>; a file: root names the page file itself, because a
  browser does not resolve a folder URL to its index.html on disk. }
function HelpPageUrl(const pRoot, pRel: string): string;
var
  Root: string;
begin
  Root:= DLNormaliseHelpRoot(pRoot);
  Result:= Root + HELP_DL + pRel;
  if Root.StartsWith(FILE_SCHEME, True) then Result:= Result + INDEX_HTML;
end; // function

function DLHelpUrl(const pRoot, pFeatureId: string): string;
begin
  if Trim(pFeatureId) = '' then Exit(DLHelpAllUrl(pRoot));
  Result:= HelpPageUrl(pRoot, 'features/' + Trim(pFeatureId) + '/');
end; // function

function DLHelpAllUrl(const pRoot: string): string;
begin
  Result:= HelpPageUrl(pRoot, '');
end; // function

function DLHelpIdeUrl(const pRoot: string): string;
begin
  Result:= HelpPageUrl(pRoot, 'ide/');
end; // function

{ TDLHelpIndex }

function TDLHelpIndex.GetCount: Integer;
begin
  Result:= Length(FEntries);
end; // function

{ A JSON array of strings as a Delphi array; anything else -> empty. }
function StringArrayOf(const pObj: TJSONObject; const pName: string): TArray<string>;
var
  Value: TJSONValue;
  Arr  : TJSONArray;
begin
  Result:= nil;
  Value:= pObj.GetValue(pName);
  if not (Value is TJSONArray) then Exit;
  Arr:= TJSONArray(Value);
  SetLength(Result, Arr.Count);
  for var I:= 0 to Arr.Count - 1 do Result[I]:= Arr.Items[I].Value;
end; // function

function StringOf(const pObj: TJSONObject; const pName: string): string;
var
  Value: TJSONValue;
begin
  Value:= pObj.GetValue(pName);
  Result:= if Value is TJSONString then Value.Value else '';
end; // function

{ The file's size and last-write time, for ReloadIfChanged. }
procedure StatFile(const pPath: string; out pSize: Int64; out pTime: TDateTime);
begin
  pSize:= TFile.GetSize(pPath);
  pTime:= TFile.GetLastWriteTime(pPath);
end; // procedure

function TDLHelpIndex.LoadFromFile(const pPath: string): Boolean;
var
  Root : TJSONValue;
  Rows : TJSONArray;
  Entry: TDLHelpEntry;
  Count: Integer;
begin
  FFileName := pPath;
  FEntries  := nil;
  FLoaded   := False;
  FLastError:= '';
  FFileSize := -1;
  FFileTime := 0;
  try
    StatFile(pPath, FFileSize, FFileTime);
    Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pPath, TEncoding.UTF8));
    try
      if not (Root is TJSONArray) then
        raise EJSONException.Create('not a JSON array of feature rows');
      Rows:= TJSONArray(Root);
      SetLength(FEntries, Rows.Count);
      Count:= 0;
      for var Item in Rows do
      begin
        if not (Item is TJSONObject) then Continue;
        Entry:= Default(TDLHelpEntry);
        Entry.Id      := StringOf(TJSONObject(Item), 'id');
        Entry.Title   := StringOf(TJSONObject(Item), 'title');
        Entry.Summary := StringOf(TJSONObject(Item), 'summary');
        Entry.Group   := StringOf(TJSONObject(Item), 'group');
        Entry.FileName:= StringOf(TJSONObject(Item), 'file');
        Entry.Verb    := StringOf(TJSONObject(Item), 'verb');
        Entry.Menus   := StringArrayOf(TJSONObject(Item), 'menus');
        Entry.Context := StringArrayOf(TJSONObject(Item), 'context');
        if Entry.Id = '' then Continue;
        FEntries[Count]:= Entry;
        Inc(Count);
      end; // for
      SetLength(FEntries, Count);
      FLoaded:= True;
    finally
      Root.Free;
    end; // try
  except // dl:ok try-except-swallowed@9afe -- the documented contract: a bad file is LastError + Loaded=False, never an exception into the IDE
    on E: Exception do
    begin
      FEntries  := nil;
      FLastError:= E.Message;
      if FLastError = '' then FLastError:= E.ClassName;
    end; // on
  end; // try
  { ParseJSONValue answers nil -- not an exception -- for malformed text. }
  if not FLoaded and (FLastError = '') then FLastError:= 'malformed JSON: ' + pPath;
  Result:= FLoaded;
end; // function

function TDLHelpIndex.ReloadIfChanged: Boolean;
var
  Size: Int64;
  Time: TDateTime;
begin
  Result:= False;
  if (FFileName = '') or not FileExists(FFileName) then Exit;
  StatFile(FFileName, Size, Time);
  if (Size = FFileSize) and SameDateTime(Time, FFileTime) then Exit;
  LoadFromFile(FFileName);
  Result:= True;
end; // function

function DLLocateHelpIndex(const pEngineDir, pHelpRoot, pBplDir: string): string;
var
  Folder: string;
begin
  if pEngineDir <> '' then
  begin
    Result:= TPath.Combine(pEngineDir, DL_HELP_INDEX_REL);
    if FileExists(Result) then Exit;
  end; // if
  Folder:= DLHelpRootFolder(pHelpRoot);
  if Folder <> '' then
  begin
    Result:= TPath.Combine(Folder, DL_HELP_INDEX_REL);
    if FileExists(Result) then Exit;
  end; // if
  if pBplDir <> '' then
  begin
    { BPL in <repo>\third_party\dll-win32\ -> <repo>\WWW\help\dl\index.json }
    Result:= ExpandFileName(TPath.Combine(IncludeTrailingPathDelimiter(pBplDir) + '..\..\WWW', DL_HELP_INDEX_REL));
    if FileExists(Result) then Exit;
  end; // if
  Result:= '';
end; // function

const
  PATH_SEP = ' > ';
  RANK_TITLE_PREFIX = 0;
  RANK_TITLE        = 1;
  RANK_CAPTION      = 2;
  RANK_ID_VERB      = 3;
  RANK_NONE         = -1;

{ The last segment of "a > b > Caption". }
function LastSegment(const pPath: string): string;
var
  At: Integer;
begin
  At:= pPath.LastIndexOf(PATH_SEP);
  Result:= Trim(if At < 0 then pPath else pPath.Substring(At + Length(PATH_SEP)));
end; // function

function ShortestOf(const pPaths: TArray<string>): string;
begin
  Result:= '';
  for var P in pPaths do
    if (Result = '') or (Length(P) < Length(Result)) then Result:= P;
end; // function

function DLResolveHelpUrl(const pRoot, pFeatureId: string; const pIndex: TDLHelpIndex): string;
begin
  if (pIndex <> nil) and pIndex.Loaded then
  begin
    for var E in pIndex.Entries do
      if SameText(E.Id, Trim(pFeatureId)) then Exit(DLHelpUrl(pRoot, E.Id));
    Exit(DLHelpAllUrl(pRoot));
  end; // if
  Result:= DLHelpUrl(pRoot, pFeatureId);
end; // function

function DLHelpDisplayText(const pEntry: TDLHelpEntry): string;
var
  Path: string;
begin
  Path:= ShortestOf(pEntry.Menus);
  if Path = '' then Path:= ShortestOf(pEntry.Context);
  if Path <> '' then Exit(pEntry.Title + ' - ' + Path);
  if pEntry.Verb <> '' then Exit(pEntry.Title + ' - CLI: drag-lint ' + pEntry.Verb);
  Result:= pEntry.Title;
end; // function

function AnyCaptionContains(const pPaths: TArray<string>; const pLowerQuery: string): Boolean;
begin
  for var P in pPaths do
    if LastSegment(P).ToLower.Contains(pLowerQuery) then Exit(True);
  Result:= False;
end; // function

{ RANK_* for one row, RANK_NONE when it is not a hit. }
function RankOf(const pEntry: TDLHelpEntry; const pLowerQuery: string): Integer;
var
  Title: string;
begin
  Title:= pEntry.Title.ToLower;
  if Title.StartsWith(pLowerQuery) then Exit(RANK_TITLE_PREFIX);
  if Title.Contains(pLowerQuery) then Exit(RANK_TITLE);
  if AnyCaptionContains(pEntry.Menus, pLowerQuery) or AnyCaptionContains(pEntry.Context, pLowerQuery) then
    Exit(RANK_CAPTION);
  if pEntry.Id.ToLower.Contains(pLowerQuery) or pEntry.Verb.ToLower.Contains(pLowerQuery) then
    Exit(RANK_ID_VERB);
  Result:= RANK_NONE;
end; // function

function DLHelpMatch(const pQuery: string; const pEntries: TArray<TDLHelpEntry>): TArray<TDLHelpHit>;
var
  Query: string;
  Hits : TList<TDLHelpHit>;
  Hit  : TDLHelpHit;
begin
  Result:= nil;
  Query:= Trim(pQuery).ToLower;
  if Query = '' then Exit;
  Hits:= TList<TDLHelpHit>.Create;
  try
    for var E in pEntries do
    begin
      Hit.Rank:= RankOf(E, Query);
      if Hit.Rank = RANK_NONE then Continue;
      Hit.Id     := E.Id;
      Hit.Title  := E.Title;
      Hit.Display:= DLHelpDisplayText(E);
      Hits.Add(Hit);
    end; // for
    Hits.Sort(TComparer<TDLHelpHit>.Construct(
      function(const pLeft, pRight: TDLHelpHit): Integer
      begin
        Result:= pLeft.Rank - pRight.Rank;
        if Result = 0 then Result:= CompareText(pLeft.Title, pRight.Title);
      end));
    if Hits.Count > DL_HELP_MAX_HITS then Hits.Count:= DL_HELP_MAX_HITS;
    Result:= Hits.ToArray;
  finally
    Hits.Free;
  end; // try
end; // function

{ A VCL caption as plain text: '&' accelerators dropped, '&&' kept as '&'. }
function StripAccelerators(const pCaption: string): string;
const
  AMP_PLACEHOLDER = #1;
begin
  Result:= Trim(pCaption.Replace('&&', AMP_PLACEHOLDER).Replace('&', '').Replace(AMP_PLACEHOLDER, '&'));
end; // function

function CaptionIn(const pPaths: TArray<string>; const pCaption: string): Boolean;
begin
  for var P in pPaths do
    if SameText(LastSegment(P), pCaption) then Exit(True);
  Result:= False;
end; // function

function DLHelpIdForMenuCaption(const pCaption: string; const pEntries: TArray<TDLHelpEntry>): string;
var
  Caption: string;
begin
  Result:= '';
  Caption:= StripAccelerators(pCaption);
  if Caption = '' then Exit;
  for var E in pEntries do
    if CaptionIn(E.Menus, Caption) then Exit(E.Id);
  for var E in pEntries do
    if CaptionIn(E.Context, Caption) then Exit(E.Id);
end; // function

type
  TDockTabHelp = record
    Caption: string;
    Id     : string;
  end; // record

const
  { The six dock tabs, resolved with `featuregen find --text <caption>` on
    2026-10-23. Used only when no menu path ends with the tab's caption. }
  DOCK_TAB_HELP: array[0..5] of TDockTabHelp = (
    (Caption: 'Structure'       ; Id: 'show-structure'),
    (Caption: 'Search (no grep)'; Id: 'symbol-search'),
    (Caption: 'Find Usages'     ; Id: 'find-usages'),
    (Caption: 'Lint Options'    ; Id: 'drag-lint-project-rules'),
    (Caption: 'Uses & Deps'     ; Id: 'uses-deps-tab'),
    (Caption: 'Call Graph'      ; Id: 'call-graph-butterfly'));
  { The tool-window entry: the page for "the drag-lint dock" as a whole. }
  DOCK_FALLBACK_ID = 'drag-lint';

function DLHelpIdForDockTab(const pTabCaption: string; const pEntries: TArray<TDLHelpEntry>): string;
var
  Caption: string;
begin
  Result:= DLHelpIdForMenuCaption(pTabCaption, pEntries);
  if Result <> '' then Exit;
  Caption:= StripAccelerators(pTabCaption);
  for var Row in DOCK_TAB_HELP do
    if SameText(Row.Caption, Caption) then Exit(Row.Id);
  Result:= DOCK_FALLBACK_ID;
end; // function

end.