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

/// <summary>True when the (normalised) root is a file: root -- an offline copy.</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <returns>True for file:/// roots and plain folders.</returns>
function DLIsFileHelpRoot(const pRoot: string): Boolean;

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

function DLIsFileHelpRoot(const pRoot: string): Boolean;
begin
  Result:= DLNormaliseHelpRoot(pRoot).StartsWith(FILE_SCHEME, True);
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

end.
