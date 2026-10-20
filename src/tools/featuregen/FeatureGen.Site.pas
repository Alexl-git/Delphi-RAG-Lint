unit FeatureGen.Site;

{ The website set (spec 5.2): leaf pages features/<id>.md, the root pages index.md,
  cli.md, ide.md, whats-new.md, and index.json / wiki-map.json. }

interface

uses
  System.SysUtils
  , FeatureGen.Model
  , FeatureGen.SiteFormat
  , FeatureGen.Markdown
  , FeatureGen.Output
  , System.Generics.Collections
  ;

type
  /// <summary>The stored fingerprint of one site page: the hash of its text with the updated value blanked, and the version it was last changed in.</summary>
  TPageStamp = record
    Hash: string;
    Version: string;
  end;

  /// <summary>The per-page "updated" bookkeeping (spec Q6): features\generated\site-pages.json.</summary>
  /// <remarks>updated of a page is the stored version while the page text (updated blanked) hashes the same as last time,
  /// else the current product version. Kept out of manifest.json so that file stays identical to the PowerShell generator.
  /// Resolve is idempotent: it reads the loaded map and records into a separate new map, so GenerateSite's two passes agree.
  /// Not thread-safe.</remarks>
  TSitePages = class
  strict private
    FVersion: string;
    FOld: TDictionary<string, TPageStamp>;
    FNew: TDictionary<string, TPageStamp>;
  public
    /// <summary>Creates an empty map.</summary>
    /// <param name="pVersion">The current product version (DRAGLINT_VERSION) a changed or new page gets.</param>
    constructor Create(const pVersion: string);
    destructor Destroy; override;
    /// <summary>Loads the stored map, replacing any earlier one; a missing file is an empty map.</summary>
    /// <param name="pFile">Full path of site-pages.json.</param>
    /// <exception cref="EFeatureGen">The file is not a JSON object of {hash, version} objects.</exception>
    procedure LoadFromFile(const pFile: string);
    /// <summary>Settles the updated value of one page.</summary>
    /// <param name="pPath">Page path relative to the site root, with forward slashes (the map key).</param>
    /// <param name="pTokenText">The page text whose updated value is UPDATED_TOKEN.</param>
    /// <returns>The text with the token replaced by the page's version.</returns>
    function Resolve(const pPath, pTokenText: string): string;
    /// <summary>The map of the pages resolved so far, as canonical JSON.</summary>
    /// <returns>Keys sorted ordinally, 2-space indent, CRLF, ending in CRLF.</returns>
    function ToJson: string;
    /// <summary>The current product version.</summary>
    property Version: string read FVersion;
  end;

const
  /// <summary>Stands in for the updated value while a leaf is hashed (set when TSiteFormat.Version is non-empty).</summary>
  UPDATED_TOKEN = 'UPDATEDVERSIONTOKEN';

/// <summary>Renders the website leaf page of one entry.</summary>
/// <param name="pEntry">The entry.</param>
/// <param name="pFmt">Site format; pFmt.Help supplies the usage lines (nil: "drag-lint verb").</param>
/// <param name="pReg">Loaded registry: the wiki link map and the leaf order come from it.</param>
/// <param name="pRepo">Repo root; the wiki body is read from docs\wiki\&lt;WikiPage&gt;.md when that file exists.</param>
/// <param name="pImages">Receives the images the wiki body pulls in.</param>
/// <returns>The page text with LF line ends: front matter, title, summary, intro, How to run it, Where to click, Needs,
/// Details and the footer. When the wiki body has its own "Running it from the CLI" or "Usage" section, How to run it keeps
/// only the link to cli.md. A cli surface usage field replaces the --help line; flags render as a Flags table; pitfalls as a
/// Pitfalls list; steps as a numbered list under the surface bullet.</returns>
/// <exception cref="EFeatureGen">The wiki body holds raw HTML or a non-ASCII character, or a front matter key is unknown.</exception>
/// <remarks>updated is UPDATED_TOKEN when pFmt.Version is set (BuildSite then settles it per page, see TSitePages); otherwise verified.build, else LastVerifiedBuild, else Since. order is the group order times 1000 plus the 1-based place among the
/// site entries of the group (ordinal by id); index.json carries the same number.</remarks>
function RenderLeaf(const pEntry: TFeatureEntry; const pFmt: TSiteFormat; const pReg: TRegistry; const pRepo: string;
  out pImages: TArray<TImageRef>): string;

/// <summary>Writes the whole website set through the writer.</summary>
/// <param name="pRepo">Repo root (features\, docs\wiki\, docs\Images\).</param>
/// <param name="pFmt">Site format (ExcludedVerbs filled by LoadSiteFormat; Help may be nil).</param>
/// <param name="pWriter">Receives every file; the caller calls Finish.</param>
/// <exception cref="EFeatureGen">The writer root is non-empty and has no index.json (it would be wiped); an entry field or wiki body has raw HTML outside code or non-ASCII (entry id and field named), an entry names an unknown group, or CheckLinks finds a violation.
/// Nothing is written to the writer then: the set is first generated into a check-only writer.</exception>
/// <remarks>Writes index.md, index.json, cli.md, ide.md, whats-new.md, wiki-map.json, features/&lt;id&gt;.md and the images.</remarks>
procedure BuildSite(const pRepo: string; const pFmt: TSiteFormat; const pWriter: TOutputWriter); overload;

/// <summary>Writes the whole website set through the writer, with per-page updated values.</summary>
/// <param name="pRepo">Repo root.</param>
/// <param name="pFmt">Site format; its Version is overridden by pPages.Version.</param>
/// <param name="pWriter">Receives every file; the caller calls Finish.</param>
/// <param name="pPages">Loaded stored map (nil: as the three-argument overload). After the call it holds the map of this build; the caller writes pPages.ToJson.</param>
/// <exception cref="EFeatureGen">As the three-argument overload.</exception>
procedure BuildSite(const pRepo: string; const pFmt: TSiteFormat; const pWriter: TOutputWriter; const pPages: TSitePages); overload;

/// <summary>Renders the whole website set and features\generated\site-pages.json for a repository, or only compares them (check D, "build --check").</summary>
/// <param name="pRepo">Repository root.</param>
/// <param name="pEngine">Full path of drag-lint.exe (--help).</param>
/// <param name="pVersion">DRAGLINT_VERSION; a changed page is stamped with it.</param>
/// <param name="pCheck">True: write and remove nothing, report only.</param>
/// <returns>Written, Changed and Removed, every path repo-relative (the site root, or features\generated\site-pages.json).</returns>
/// <exception cref="EFeatureGen">The set cannot be generated (see BuildSite).</exception>
/// <remarks>Same behaviour as "featuregen build --site" with the default root.</remarks>
function BuildSiteSet(const pRepo, pEngine, pVersion: string; pCheck: Boolean): TOutputResult;

/// <summary>Checks every link of the Markdown files queued in the writer.</summary>
/// <param name="pWriter">Writer after the set was Put.</param>
/// <returns>One message per violation, naming the page and the link; empty when all is well.</returns>
/// <remarks>Violations: a relative target (path part) that is not among the files queued; an external link that is not https;
/// a local path (drive letter, backslash, file:). Links inside code fences and code spans are not links.</remarks>
function CheckLinks(const pWriter: TOutputWriter): TArray<string>;

/// <summary>The agent CLI reference (spec 5.3): the site cli.md text without its front matter,
/// with every link target rewritten for features\generated\cli-reference.md.</summary>
/// <param name="pFmt">Site format; its Help must be loaded (usage lines come from it).</param>
/// <param name="pReg">Loaded registry; only site-included entries are listed, as on the site.</param>
/// <param name="pRepo">Repository root; link targets are checked against it.</param>
/// <returns>LF text starting with '# CLI reference'. A leaf link features/&lt;id&gt;.md becomes
/// ../../docs/wiki/&lt;wikiPage&gt;.md when that page exists; https and #anchor links are kept; any
/// other link is kept only if it resolves from features\generated\, else it becomes its plain text.</returns>
function CliReferenceMd(const pFmt: TSiteFormat; const pReg: TRegistry; const pRepo: string): string;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , System.Generics.Defaults
  , System.Hash
  , System.JSON
  , FeatureGen.Json
  , FeatureGen.Live
  ;

function YamlScalar(const pValue: string): string; forward;

{ ---- TSitePages ---- }

constructor TSitePages.Create(const pVersion: string);
begin
  inherited Create;
  FVersion := pVersion;
  FOld := TDictionary<string, TPageStamp>.Create;
  FNew := TDictionary<string, TPageStamp>.Create;
end;

destructor TSitePages.Destroy;
begin
  FNew.Free;
  FOld.Free;
  inherited Destroy;
end;

procedure TSitePages.LoadFromFile(const pFile: string);
var
  lRoot: TJSONValue;
  lPair: TJSONPair;
  lStamp: TPageStamp;
begin
  FOld.Clear;
  FNew.Clear;
  if not TFile.Exists(pFile) then
    Exit;
  lRoot := ReadJsonFile(pFile);
  try
    if lRoot is not TJSONObject then
      raise EFeatureGen.CreateFmt('%s: expected a JSON object keyed by page path', [pFile]);
    for lPair in TJSONObject(lRoot) do
    begin
      lStamp.Hash := Prop(lPair.JsonValue, 'hash');
      lStamp.Version := Prop(lPair.JsonValue, 'version');
      if (lPair.JsonValue is not TJSONObject) or (lStamp.Hash = '') or (lStamp.Version = '') then
        raise EFeatureGen.CreateFmt('%s: page "%s" needs a hash and a version', [pFile, lPair.JsonString.Value]);
      FOld.AddOrSetValue(lPair.JsonString.Value, lStamp);
    end;
  finally
    lRoot.Free;
  end;
end;

function TSitePages.Resolve(const pPath, pTokenText: string): string;
var
  lStamp, lOld: TPageStamp;
begin
  lStamp.Hash := THashSHA2.GetHashString(pTokenText, SHA256);
  if FOld.TryGetValue(pPath, lOld) and (lOld.Hash = lStamp.Hash) then
    lStamp.Version := lOld.Version
  else
    lStamp.Version := FVersion;
  FNew.AddOrSetValue(pPath, lStamp);
  Result := pTokenText.Replace(UPDATED_TOKEN, YamlScalar(lStamp.Version));
end;

function TSitePages.ToJson: string;
var
  lKeys: TArray<string>;
  lKey: string;
  lRoot, lObj: TJSONObject;
begin
  lKeys := FNew.Keys.ToArray;
  TArray.Sort<string>(lKeys, TComparer<string>.Construct(
    function(const pA, pB: string): Integer
    begin
      Result := CompareStr(pA, pB);
    end));
  lRoot := TJSONObject.Create;
  try
    for lKey in lKeys do
    begin
      lObj := TJSONObject.Create;
      lObj.AddPair('hash', FNew[lKey].Hash);
      lObj.AddPair('version', FNew[lKey].Version);
      lRoot.AddPair(lKey, lObj);
    end;
    Result := CanonicalJson(lRoot, nil);
  finally
    lRoot.Free;
  end;
end;

function YamlScalar(const pValue: string): string;
begin
  if (pValue = '') or (pValue <> Trim(pValue)) or (pValue.IndexOfAny([':', '"', '#', '\']) >= 0)
    or (Pos(pValue[1], '*&!|>''%@`[]{},?-') > 0) then
    Result := '"' + StringReplace(StringReplace(pValue, '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]) + '"'
  else
    Result := pValue;
end;

function GroupOrder(const pReg: TRegistry; const pGroup: string): Integer;
var
  lG: TNamedRow;
begin
  Result := 0;
  for lG in pReg.Groups do
    if lG.Id = pGroup then
      Result := lG.Order;
end;

function SiteOrder(const pEntry: TFeatureEntry; const pFmt: TSiteFormat; const pReg: TRegistry): Integer;
var
  lE: TFeatureEntry;
  lPlace: Integer;
begin
  lPlace := 1;
  for lE in pReg.Entries do
    if EntryOnSite(pFmt, lE) and (lE.Group = pEntry.Group) and (CompareStr(lE.Id, pEntry.Id) < 0) then
      Inc(lPlace);
  Result := GroupOrder(pReg, pEntry.Group) * 1000 + lPlace;
end;

function FrontMatter(const pEntry: TFeatureEntry; const pFmt: TSiteFormat; const pReg: TRegistry): string;
var
  lKey, lVal, lUpdated: string;
begin
  if pFmt.Version <> '' then
    lUpdated := UPDATED_TOKEN
  else
  begin
    lUpdated := pEntry.VerifiedBuild;
    if lUpdated = '' then
      lUpdated := pEntry.LastVerifiedBuild;
    if lUpdated = '' then
      lUpdated := pEntry.Since;
  end;
  Result := '---'#10;
  for lKey in pFmt.FrontMatterKeys do
  begin
    if lKey = 'id' then
      lVal := pEntry.Id
    else if lKey = 'title' then
      lVal := pEntry.Title
    else if lKey = 'summary' then
      lVal := pEntry.Summary
    else if lKey = 'product' then
      lVal := pFmt.Product
    else if lKey = 'group' then
      lVal := pEntry.Group
    else if lKey = 'order' then
      lVal := IntToStr(SiteOrder(pEntry, pFmt, pReg))
    else if lKey = 'since' then
      lVal := pEntry.Since
    else if lKey = 'status' then
      lVal := pEntry.Status
    else if lKey = 'updated' then
      lVal := lUpdated
    else
      raise EFeatureGen.CreateFmt('entry %s: unknown front matter key "%s" in site-format.json', [pEntry.Id, lKey]);
    if lVal <> '' then
      Result := Result + lKey + ': ' + YamlScalar(lVal) + #10;
  end;
  Result := Result + '---'#10;
end;

function VerbName(const pS: TSurface): string;
begin
  Result := pS.Verb;
  if pS.Sub <> '' then
    Result := Result + ' ' + pS.Sub;
end;

function TableCell(const pText: string): string;
begin
  Result := StringReplace(pText, '|', '\|', [rfReplaceAll]);
end;

function CodeCell(const pText: string): string;
begin
  if pText = '' then
    Result := ''
  else if Pos('`', pText) > 0 then
    Result := '`` ' + TableCell(pText) + ' ``'
  else
    Result := '`' + TableCell(pText) + '`';
end;

{ The Flags table of a flag list, ending in a blank line; '' for no flags. }
function FlagsTable(const pFlags: TArray<TFlag>): string;
var
  lF: TFlag;
begin
  Result := '';
  if Length(pFlags) = 0 then
    Exit;
  Result := '| Flag | Argument | Meaning | Default |'#10'| --- | --- | --- | --- |'#10;
  for lF in pFlags do
    Result := Result + '| ' + CodeCell(lF.Name) + ' | ' + CodeCell(lF.Arg) + ' | ' + TableCell(lF.Summary) + ' | '
      + CodeCell(lF.DefaultValue) + ' |'#10;
  Result := Result + #10;
end;

function HowToRun(const pEntry: TFeatureEntry; const pFmt: TSiteFormat; pLinkOnly: Boolean): string;
var
  lS: TSurface;
  lUsage: string;
begin
  Result := '';
  for lS in pEntry.Surfaces do
    if lS.Kind = 'cli' then
    begin
      if Result = '' then
        Result := '## How to run it'#10#10;
      if not pLinkOnly then
      begin
        lUsage := lS.Usage;
        if (lUsage = '') and (pFmt.Help <> nil) then
          lUsage := pFmt.Help.UsageFor(VerbName(lS));
        if lUsage = '' then
          lUsage := 'drag-lint ' + VerbName(lS);
        Result := Result + '```text'#10 + lUsage + #10'```'#10#10;
        if lS.Example <> '' then
          Result := Result + 'Example:'#10#10'```text'#10 + lS.Example + #10'```'#10#10;
      end;
      Result := Result + 'Full flag list: [' + lS.Verb + ' in the CLI reference](../cli.md#' + lS.Verb + ').'#10#10;
    end;
end;

function FlagsSection(const pEntry: TFeatureEntry): string;
var
  lS: TSurface;
  lF: TFlag;
  lAll: TArray<TFlag>;
begin
  SetLength(lAll, 0);
  for lS in pEntry.Surfaces do
    if lS.Kind = 'cli' then
      for lF in lS.Flags do
        lAll := lAll + [lF];
  Result := '';
  if Length(lAll) > 0 then
    Result := '## Flags'#10#10 + FlagsTable(lAll);
end;

function PitfallsSection(const pEntry: TFeatureEntry): string;
var
  lP: string;
begin
  Result := '';
  for lP in pEntry.Pitfalls do
    Result := Result + '* ' + lP + #10;
  if Result <> '' then
    Result := '## Pitfalls'#10#10 + Result + #10;
end;

function WhereToClick(const pEntry: TFeatureEntry): string;
var
  lS: TSurface;
  lLine: string;
  lI: Integer;
begin
  Result := '';
  for lS in pEntry.Surfaces do
  begin
    if lS.Kind = 'ide-menu' then
      lLine := '* RAD Studio main menu: **' + lS.Path + '**'
    else if lS.Kind = 'ide-context' then
      lLine := '* Right-click in the ' + lS.Host + ': **' + lS.Caption + '**'
    else if lS.Kind = 'ide-about' then
      lLine := '* drag-lint About window, button **' + lS.Caption + '**'
    else if lS.Kind = 'tool-window' then
      lLine := '* Tool window: **' + lS.Path + '**'
    else
      Continue;
    Result := Result + lLine + #10;
    for lI := 0 to High(lS.Steps) do
      Result := Result + '   ' + IntToStr(lI + 1) + '. ' + lS.Steps[lI] + #10;
  end;
  if Result <> '' then
    Result := '## Where to click'#10#10 + Result + #10;
end;

function RenderLeaf(const pEntry: TFeatureEntry; const pFmt: TSiteFormat; const pReg: TRegistry; const pRepo: string;
  out pImages: TArray<TImageRef>): string;
var
  lMap: TWikiLinkMap;
  lWikiFile, lBody, lSummary, lNeeds: string;
  lHasCliSection: Boolean;
begin
  SetLength(pImages, 0);
  lBody := '';
  lHasCliSection := False;
  lWikiFile := '';
  if (pEntry.WikiPage <> '') and not IsGeneratedWikiPage(pFmt, pEntry.WikiPage) then
    lWikiFile := TPath.Combine(pRepo, 'docs\wiki\' + pEntry.WikiPage + '.md');
  if (lWikiFile <> '') and TFile.Exists(lWikiFile) then
  begin
    lMap := TWikiLinkMap.Create;
    try
      lMap.Load(pReg, pFmt);
      lBody := TFile.ReadAllText(lWikiFile, TEncoding.UTF8);
      lHasCliSection := TRegEx.IsMatch(lBody, '(?im)^#{1,6}[ \t]+(Running it from the CLI|Usage)[ \t]*\r?$');
      lBody := TransformWikiBody(lBody, lMap, pEntry.Id, pImages, pFmt.FenceDefaultLang, pRepo);
    finally
      lMap.Free;
    end;
  end;
  lSummary := pEntry.Summary;
  if not TRegEx.IsMatch(lSummary, '[.!?]$') then
    lSummary := lSummary + '.';
  Result := FrontMatter(pEntry, pFmt, pReg) + #10'# ' + pEntry.Title + #10#10 + lSummary + #10#10;
  if pEntry.Intro <> '' then
    Result := Result + pEntry.Intro + #10#10;
  Result := Result + HowToRun(pEntry, pFmt, lHasCliSection) + FlagsSection(pEntry) + WhereToClick(pEntry);
  if Length(pEntry.Requires) > 0 then
  begin
    lNeeds := string.Join(', ', pEntry.Requires);
    Result := Result + '**Needs:** ' + lNeeds + #10#10;
  end;
  Result := Result + PitfallsSection(pEntry);
  if lBody <> '' then
    Result := Result + '## Details'#10#10 + lBody + #10#10;
  Result := Result + '---'#10#10'[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)'#10;
end;

{ ---- root pages ---- }

function Sentence(const pText: string): string;
begin
  Result := pText;
  if not TRegEx.IsMatch(Result, '[.!?]$') then
    Result := Result + '.';
end;

function RootFront(const pFmt: TSiteFormat; const pId, pTitle, pSummary: string): string;
var
  lKey, lVal: string;
begin
  Result := '---'#10;
  for lKey in pFmt.FrontMatterKeys do
  begin
    if lKey = 'id' then
      lVal := pId
    else if lKey = 'title' then
      lVal := pTitle
    else if lKey = 'summary' then
      lVal := pSummary
    else if lKey = 'product' then
      lVal := pFmt.Product
    else
      Continue;
    Result := Result + lKey + ': ' + YamlScalar(lVal) + #10;
  end;
  Result := Result + '---'#10#10;
end;

function CellText(const pText: string): string;
begin
  Result := pText.Replace('|', '\|');
end;

function LeafLink(const pEntry: TFeatureEntry; const pText: string): string;
begin
  Result := '[' + pText + '](features/' + pEntry.Id + '.md)';
end;

function JsonStr(const pText: string): string;
var
  lCh: Char;
begin
  Result := '"';
  for lCh in pText do
    case lCh of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9: Result := Result + '\t';
    else
      if lCh < ' ' then
        Result := Result + '\u' + IntToHex(Ord(lCh), 4)
      else
        Result := Result + lCh;
    end;
  Result := Result + '"';
end;

function IncludedEntries(const pFmt: TSiteFormat; const pReg: TRegistry): TArray<TFeatureEntry>;
var
  lE: TFeatureEntry;
  lList: TList<TFeatureEntry>;
begin
  lList := TList<TFeatureEntry>.Create;
  try
    for lE in pReg.Entries do
      if EntryOnSite(pFmt, lE) then
        lList.Add(lE);
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function IndexMd(const pFmt: TSiteFormat; const pReg: TRegistry; const pInc: TArray<TFeatureEntry>): string;
var
  lG: TNamedRow;
  lE: TFeatureEntry;
  lRows: string;
begin
  Result := RootFront(pFmt, 'index', 'drag-lint help', 'Every drag-lint feature, by group.')
    + '# drag-lint help'#10#10 + pFmt.MicroniteIndex + #10#10;
  for lG in pReg.Groups do
  begin
    lRows := '';
    for lE in pInc do
      if lE.Group = lG.Id then
        lRows := lRows + '| ' + LeafLink(lE, CellText(lE.Title)) + ' | ' + CellText(lE.Summary) + ' | ' + CellText(lE.Since) + ' |'#10;
    if lRows = '' then
      Continue;
    Result := Result + '## ' + lG.Title + #10#10;
    if lG.Summary <> '' then
      Result := Result + Sentence(lG.Summary) + #10#10;
    Result := Result + '| Feature | What it does | Since |'#10'| --- | --- | --- |'#10 + lRows + #10;
  end;
end;

function IndexJson(const pFmt: TSiteFormat; const pReg: TRegistry; const pInc: TArray<TFeatureEntry>): string;
var
  lG: TNamedRow;
  lE: TFeatureEntry;
  lItems: string;
begin
  lItems := '';
  for lG in pReg.Groups do
    for lE in pInc do
      if lE.Group = lG.Id then
      begin
        if lItems <> '' then
          lItems := lItems + ','#10;
        lItems := lItems + '  {'#10'    "id": ' + JsonStr(lE.Id) + ','#10'    "title": ' + JsonStr(lE.Title) + ','#10
          + '    "summary": ' + JsonStr(lE.Summary) + ','#10'    "group": ' + JsonStr(lE.Group) + ','#10
          + '    "order": ' + IntToStr(SiteOrder(lE, pFmt, pReg)) + ','#10'    "since": ' + JsonStr(lE.Since) + ','#10
          + '    "file": ' + JsonStr('features/' + lE.Id + '.md') + #10'  }';
      end;
  Result := '['#10 + lItems + #10']'#10;
end;

function CliMd(const pFmt: TSiteFormat; const pInc: TArray<TFeatureEntry>): string;
var
  lVerbs: TDictionary<string, TList<Integer>>;
  lKeys: TArray<string>;
  lE: TFeatureEntry;
  lS: TSurface;
  lI: Integer;
  lVerb, lUsage, lUsages, lSub: string;
  lSubs: TList<string>;
  lFlags: TList<TFlag>;
  lF: TFlag;
  lSeen: TList<string>;
begin
  lVerbs := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  try
    for lI := 0 to High(pInc) do
      for lS in pInc[lI].Surfaces do
        if (lS.Kind = 'cli') and (lS.Verb <> '') then
        begin
          if not lVerbs.ContainsKey(lS.Verb) then
            lVerbs.Add(lS.Verb, TList<Integer>.Create);
          if not lVerbs[lS.Verb].Contains(lI) then
            lVerbs[lS.Verb].Add(lI);
        end;
    lKeys := lVerbs.Keys.ToArray;
    TArray.Sort<string>(lKeys, TComparer<string>.Construct(
      function(const pA, pB: string): Integer
      begin
        Result := CompareStr(pA, pB);
      end));
    Result := RootFront(pFmt, 'cli', 'CLI reference', 'Every drag-lint command, with its usage and the feature that describes it.')
      + '# CLI reference'#10#10'Every drag-lint command, with its usage and the features that describe it.'#10#10'## Commands'#10#10;
    for lVerb in lKeys do
    begin
      lE := pInc[lVerbs[lVerb][0]];
      lUsages := '';
      lSubs := TList<string>.Create;
      try
        lSubs.Add('');
        for lI in lVerbs[lVerb] do
          for lS in pInc[lI].Surfaces do
            if (lS.Kind = 'cli') and (lS.Verb = lVerb) and (lS.Sub <> '') and not lSubs.Contains(lS.Sub) then
              lSubs.Add(lS.Sub);
        for lSub in lSubs do
        begin
          lUsage := '';
          for lI in lVerbs[lVerb] do
            for lS in pInc[lI].Surfaces do
              if (lUsage = '') and (lS.Kind = 'cli') and (lS.Verb = lVerb) and (lS.Sub = lSub) then
                lUsage := lS.Usage;
          if (lUsage = '') and (pFmt.Help <> nil) then
            lUsage := pFmt.Help.UsageFor(Trim(lVerb + ' ' + lSub));
          if (lUsage <> '') and (Pos(lUsage + #10, lUsages) = 0) then
            lUsages := lUsages + lUsage + #10;
        end;
      finally
        lSubs.Free;
      end;
      if lUsages = '' then
        lUsages := 'drag-lint ' + lVerb + #10;
      Result := Result + '### ' + lVerb + #10#10 + Sentence(lE.Summary) + #10#10'```text'#10 + lUsages + '```'#10#10;
      lFlags := TList<TFlag>.Create;
      lSeen := TList<string>.Create;
      try
        for lI in lVerbs[lVerb] do
          for lS in pInc[lI].Surfaces do
            if (lS.Kind = 'cli') and (lS.Verb = lVerb) then
              for lF in lS.Flags do
                if not lSeen.Contains(lF.Name) then
                begin
                  lSeen.Add(lF.Name);
                  lFlags.Add(lF);
                end;
        Result := Result + FlagsTable(lFlags.ToArray);
      finally
        lSeen.Free;
        lFlags.Free;
      end;
      if lVerbs[lVerb].Count = 1 then
        Result := Result + 'Described in ' + LeafLink(lE, lE.Title) + '.'#10#10
      else
      begin
        Result := Result + 'Described in:'#10#10;
        for lI in lVerbs[lVerb] do
          Result := Result + '* ' + LeafLink(pInc[lI], pInc[lI].Title) + #10;
        Result := Result + #10;
      end;
    end;
  finally
    lVerbs.Free;
  end;
end;

type
  TMenuItemRef = record
    Segs: TArray<string>;
    Entry: Integer;
  end;

procedure EmitMenuLevel(const pItems: TArray<TMenuItemRef>; pDepth: Integer; const pInc: TArray<TFeatureEntry>; var pOut: string);
var
  lNames: TList<string>;
  lItem: TMenuItemRef;
  lName: string;
  lSub: TList<TMenuItemRef>;
  lLinks: TList<Integer>;
  lI: Integer;
  lLine: string;
begin
  lNames := TList<string>.Create;
  try
    for lItem in pItems do
      if not lNames.Contains(lItem.Segs[pDepth]) then
        lNames.Add(lItem.Segs[pDepth]);
    lNames.Sort(TComparer<string>.Construct(
      function(const pA, pB: string): Integer
      begin
        Result := CompareStr(pA, pB);
      end));
    for lName in lNames do
    begin
      lSub := TList<TMenuItemRef>.Create;
      lLinks := TList<Integer>.Create;
      try
        for lItem in pItems do
          if lItem.Segs[pDepth] = lName then
          begin
            if Length(lItem.Segs) = pDepth + 1 then
            begin
              if not lLinks.Contains(lItem.Entry) then
                lLinks.Add(lItem.Entry);
            end
            else
              lSub.Add(lItem);
          end;
        lLinks.Sort;
        lLine := StringOfChar(' ', pDepth * 2) + '* ';
        if lLinks.Count = 0 then
          lLine := lLine + lName
        else if lLinks.Count = 1 then
          lLine := lLine + LeafLink(pInc[lLinks[0]], lName)
        else
        begin
          lLine := lLine + lName + ': ';
          for lI := 0 to lLinks.Count - 1 do
          begin
            if lI > 0 then
              lLine := lLine + ', ';
            lLine := lLine + LeafLink(pInc[lLinks[lI]], pInc[lLinks[lI]].Title);
          end;
        end;
        pOut := pOut + lLine + #10;
        if lSub.Count > 0 then
          EmitMenuLevel(lSub.ToArray, pDepth + 1, pInc, pOut);
      finally
        lLinks.Free;
        lSub.Free;
      end;
    end;
  finally
    lNames.Free;
  end;
end;

function IdeMd(const pFmt: TSiteFormat; const pInc: TArray<TFeatureEntry>): string;
var
  lItems: TList<TMenuItemRef>;
  lRef: TMenuItemRef;
  lS: TSurface;
  lI, lJ: Integer;
  lParts: TArray<string>;
  lTree: string;
begin
  lItems := TList<TMenuItemRef>.Create;
  try
    for lI := 0 to High(pInc) do
      for lS in pInc[lI].Surfaces do
        if (lS.Kind = 'ide-menu') and (lS.Path <> '') then
        begin
          lParts := lS.Path.Split(['>']);
          for lJ := 0 to High(lParts) do
            lParts[lJ] := Trim(lParts[lJ]);
          lRef.Segs := lParts;
          lRef.Entry := lI;
          lItems.Add(lRef);
        end;
    lTree := '';
    if lItems.Count > 0 then
      EmitMenuLevel(lItems.ToArray, 0, pInc, lTree);
  finally
    lItems.Free;
  end;
  Result := RootFront(pFmt, 'ide', 'IDE menus', 'The drag-lint menu tree in the RAD Studio IDE, every item linked to its feature.')
    + '# IDE menus'#10#10'The drag-lint menu tree in the RAD Studio IDE. Each item links to the feature it starts.'#10#10 + lTree;
end;

function VersionKey(const pSince: string): TArray<Integer>;
var
  lParts: TArray<string>;
  lI: Integer;
begin
  lParts := pSince.Split(['-'])[0].Split(['.']);
  SetLength(Result, Length(lParts));
  for lI := 0 to High(lParts) do
    Result[lI] := StrToIntDef(lParts[lI], 0);
end;

function CompareVersion(const pA, pB: string): Integer;
var
  lA, lB: TArray<Integer>;
  lI, lN: Integer;
begin
  lA := VersionKey(pA);
  lB := VersionKey(pB);
  lN := Length(lA);
  if Length(lB) > lN then
    lN := Length(lB);
  Result := 0;
  for lI := 0 to lN - 1 do
  begin
    if lI >= Length(lA) then
      Exit(-1);
    if lI >= Length(lB) then
      Exit(1);
    if lA[lI] <> lB[lI] then
      Exit(lA[lI] - lB[lI]);
  end;
  Result := CompareStr(pA, pB);
end;

function WhatsNewMd(const pFmt: TSiteFormat; const pInc: TArray<TFeatureEntry>): string;
var
  lSinces: TList<string>;
  lE: TFeatureEntry;
  lSince: string;
begin
  Result := RootFront(pFmt, 'whats-new', 'What''s new', 'Features grouped by the version that introduced them, newest first.')
    + '# What''s new'#10#10 + pFmt.MicroniteWhatsNew + #10#10;
  lSinces := TList<string>.Create;
  try
    for lE in pInc do
      if not lSinces.Contains(lE.Since) then
        lSinces.Add(lE.Since);
    lSinces.Sort(TComparer<string>.Construct(
      function(const pA, pB: string): Integer
      begin
        Result := CompareVersion(pB, pA);
      end));
    for lSince in lSinces do
    begin
      Result := Result + '## ' + lSince + #10#10;
      for lE in pInc do
        if lE.Since = lSince then
          Result := Result + '* ' + LeafLink(lE, lE.Title) + ' -- ' + Sentence(lE.Summary) + #10;
      Result := Result + #10;
    end;
  finally
    lSinces.Free;
  end;
end;

function WikiMapJson(const pFmt: TSiteFormat; const pInc: TArray<TFeatureEntry>): string;
var
  lMap: TDictionary<string, string>;
  lE: TFeatureEntry;
  lKeys: TArray<string>;
  lOld, lKey, lItems: string;
begin
  lMap := TDictionary<string, string>.Create;
  try
    for lE in pInc do
      if (lE.WikiPage <> '') and not IsGeneratedWikiPage(pFmt, lE.WikiPage) then
        if (not lMap.TryGetValue(lE.WikiPage, lOld)) or (CompareStr(lE.Id, lOld) < 0) then
          lMap.AddOrSetValue(lE.WikiPage, lE.Id);
    lKeys := lMap.Keys.ToArray;
    TArray.Sort<string>(lKeys, TComparer<string>.Construct(
      function(const pA, pB: string): Integer
      begin
        Result := CompareStr(pA, pB);
      end));
    lItems := '';
    for lKey in lKeys do
    begin
      if lItems <> '' then
        lItems := lItems + ','#10;
      lItems := lItems + '  ' + JsonStr(lKey) + ': ' + JsonStr(lMap[lKey]);
    end;
    Result := '{'#10 + lItems + #10'}'#10;
  finally
    lMap.Free;
  end;
end;

procedure CheckField(const pEntry: TFeatureEntry; const pField, pText: string; pCodeOnly: Boolean);
var
  lM: TMatch;
  lI: Integer;
begin
  for lI := 1 to Length(pText) do
    if pText[lI] > #127 then
      raise EFeatureGen.CreateFmt('entry %s, field %s: non-ASCII character U+%.4X', [pEntry.Id, pField, Ord(pText[lI])]);
  if pCodeOnly then
    Exit;
  lM := TRegEx.Match(TRegEx.Replace(pText, '`[^`]*`', ''), '<[a-zA-Z/][^>]*>');
  if lM.Success then
    raise EFeatureGen.CreateFmt('entry %s, field %s: raw HTML tag "%s" outside code (wrap it in backticks)', [pEntry.Id, pField, lM.Value]);
end;

{ The same raw-HTML and non-ASCII guard the wiki body gets, over every entry field a page renders. }
procedure CheckEntryText(const pEntry: TFeatureEntry);
var
  lS: TSurface;
  lR: string;
  lF: TFlag;
  lQ: TQuestion;
begin
  CheckField(pEntry, 'title', pEntry.Title, False);
  CheckField(pEntry, 'summary', pEntry.Summary, False);
  CheckField(pEntry, 'intro', pEntry.Intro, False);
  for lR in pEntry.Requires do
    CheckField(pEntry, 'requires', lR, False);
  for lS in pEntry.Surfaces do
  begin
    CheckField(pEntry, 'surfaces.path', lS.Path, False);
    CheckField(pEntry, 'surfaces.caption', lS.Caption, False);
    CheckField(pEntry, 'surfaces.host', lS.Host, False);
    CheckField(pEntry, 'surfaces.verb', lS.Verb, False);
    CheckField(pEntry, 'surfaces.example', lS.Example, True);
    CheckField(pEntry, 'surfaces.usage', lS.Usage, True);
    for lF in lS.Flags do
    begin
      CheckField(pEntry, 'surfaces.flags.name', lF.Name, True);
      CheckField(pEntry, 'surfaces.flags.arg', lF.Arg, True);
      CheckField(pEntry, 'surfaces.flags.summary', lF.Summary, False);
      CheckField(pEntry, 'surfaces.flags.default', lF.DefaultValue, True);
    end;
    for lR in lS.Steps do
      CheckField(pEntry, 'surfaces.steps', lR, False);
  end;
  for lR in pEntry.Pitfalls do
    CheckField(pEntry, 'pitfalls', lR, False);
  for lQ in pEntry.Questions do
  begin
    CheckField(pEntry, 'questions.ask', lQ.Ask, False);
    CheckField(pEntry, 'questions.command', lQ.Command, True);
  end;
end;

procedure GenerateSite(const pRepo: string; const pFmt: TSiteFormat; const pReg: TRegistry; const pW: TOutputWriter; const pPages: TSitePages);
var
  lLeaf: string;
  lInc: TArray<TFeatureEntry>;
  lE: TFeatureEntry;
  lImgs: TArray<TImageRef>;
  lImg: TImageRef;
  lG: TNamedRow;
  lKnown: Boolean;
begin
  lInc := IncludedEntries(pFmt, pReg);
  for lE in lInc do
  begin
    lKnown := False;
    for lG in pReg.Groups do
      if lG.Id = lE.Group then
        lKnown := True;
    if not lKnown then
      raise EFeatureGen.CreateFmt('entry %s: group "%s" is not in groups.json', [lE.Id, lE.Group]);
    CheckEntryText(lE);
    lLeaf := RenderLeaf(lE, pFmt, pReg, pRepo, lImgs);
    if pPages <> nil then
      lLeaf := pPages.Resolve('features/' + lE.Id + '.md', lLeaf);
    pW.Put('features/' + lE.Id + '.md', lLeaf, 'entry ' + lE.Id + ' (leaf)');
    for lImg in lImgs do
      pW.PutBinary('features\' + lImg.Target, TPath.Combine(pRepo, lImg.Source));
  end;
  pW.Put('index.md', IndexMd(pFmt, pReg, lInc), 'index.md');
  pW.Put('index.json', IndexJson(pFmt, pReg, lInc), 'index.json');
  pW.Put('cli.md', CliMd(pFmt, lInc), 'cli.md');
  pW.Put('ide.md', IdeMd(pFmt, lInc), 'ide.md');
  pW.Put('whats-new.md', WhatsNewMd(pFmt, lInc), 'whats-new.md');
  pW.Put('wiki-map.json', WikiMapJson(pFmt, lInc), 'wiki-map.json');
end;

{ One cli.md link target, re-aimed from features\generated\; '' = render as plain text. }
function CliReferenceTarget(const pTarget: string; const pReg: TRegistry; const pRepo: string): string;
const
  GEN_DIR = 'features\generated';
var
  lM: TMatch;
  lE: TFeatureEntry;
  lPath, lAnchor: string;
  lHash: Integer;
begin
  if pTarget.StartsWith('https://') or pTarget.StartsWith('http://') or pTarget.StartsWith('#') then
    Exit(pTarget);
  lM := TRegEx.Match(pTarget, '^features/([^/#]+)\.md(#.*)?$');
  if lM.Success then
  begin
    lAnchor := if lM.Groups.Count > 2 then lM.Groups[2].Value else '';
    for lE in pReg.Entries do
      if (lE.Id = lM.Groups[1].Value) and (lE.WikiPage <> '')
        and TFile.Exists(TPath.Combine(pRepo, 'docs\wiki\' + lE.WikiPage + '.md')) then
        Exit('../../docs/wiki/' + lE.WikiPage + '.md' + lAnchor);
    Exit('');
  end;
  lPath := pTarget;
  lHash := Pos('#', lPath);
  if lHash > 0 then
    lPath := Copy(lPath, 1, lHash - 1);
  if (lPath <> '') and TFile.Exists(TPath.GetFullPath(TPath.Combine(TPath.Combine(pRepo, GEN_DIR), lPath.Replace('/', '\')))) then
    Result := pTarget
  else
    Result := '';
end;

function CliReferenceMd(const pFmt: TSiteFormat; const pReg: TRegistry; const pRepo: string): string;
const
  FRONT_END = #10'---'#10#10;
  LINK_RE = '(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)';
var
  lMd, lTarget: string;
  lAt, lFrom: Integer;
  lM: TMatch;
  lSb: TStringBuilder;
begin
  lMd := CliMd(pFmt, IncludedEntries(pFmt, pReg));
  lAt := Pos(FRONT_END, lMd);
  if lMd.StartsWith('---'#10) and (lAt > 0) then
    lMd := Copy(lMd, lAt + Length(FRONT_END), MaxInt);
  lSb := TStringBuilder.Create;
  try
    lFrom := 1;
    for lM in TRegEx.Matches(lMd, LINK_RE) do
    begin
      lSb.Append(Copy(lMd, lFrom, lM.Index - lFrom));
      lTarget := CliReferenceTarget(lM.Groups[2].Value, pReg, pRepo);
      if lTarget <> '' then
        lSb.Append('[' + lM.Groups[1].Value + '](' + lTarget + ')')
      else
        lSb.Append(lM.Groups[1].Value);
      lFrom := lM.Index + lM.Length;
    end;
    lSb.Append(Copy(lMd, lFrom, MaxInt));
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

procedure BuildSite(const pRepo: string; const pFmt: TSiteFormat; const pWriter: TOutputWriter);
begin
  BuildSite(pRepo, pFmt, pWriter, nil);
end;

procedure BuildSite(const pRepo: string; const pFmt: TSiteFormat; const pWriter: TOutputWriter; const pPages: TSitePages);
var
  lReg: TRegistry;
  lProbe: TOutputWriter;
  lBad: TArray<string>;
  lFmt: TSiteFormat;
begin
  lFmt := pFmt;
  if pPages <> nil then
    lFmt.Version := pPages.Version;
  if TDirectory.Exists(pWriter.Root) and not TDirectory.IsEmpty(pWriter.Root) and not TFile.Exists(TPath.Combine(pWriter.Root, 'index.json')) then
    raise EFeatureGen.CreateFmt('refusing to use %s as the site root: it is not empty and has no index.json at its top level', [pWriter.Root]);
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lProbe := TOutputWriter.Create(pWriter.Root, True, False);
    try
      GenerateSite(pRepo, lFmt, lReg, lProbe, pPages);
      lBad := CheckLinks(lProbe);
    finally
      lProbe.Free;
    end;
    if Length(lBad) > 0 then
      raise EFeatureGen.Create('link check failed:'#13#10 + string.Join(#13#10, lBad));
    GenerateSite(pRepo, lFmt, lReg, pWriter, pPages);
  finally
    lReg.Free;
  end;
end;

{ ---- link check ---- }

function StripCode(const pText: string): string;
var
  lLine: string;
  lFence: Boolean;
begin
  Result := '';
  lFence := False;
  for lLine in pText.Split([#10]) do
  begin
    if lLine.TrimLeft.StartsWith('```') then
    begin
      lFence := not lFence;
      Continue;
    end;
    if not lFence then
      Result := Result + TRegEx.Replace(lLine, '`[^`]*`', '') + #10;
  end;
end;

function NormalisePath(const pPageDir, pTarget: string; out pOk: Boolean): string;
var
  lParts: TList<string>;
  lPart: string;
begin
  pOk := True;
  lParts := TList<string>.Create;
  try
    if pPageDir <> '' then
      for lPart in pPageDir.Split(['/']) do
        lParts.Add(lPart);
    for lPart in pTarget.Split(['/']) do
      if (lPart = '') or (lPart = '.') then
        Continue
      else if lPart = '..' then
      begin
        if lParts.Count = 0 then
          pOk := False
        else
          lParts.Delete(lParts.Count - 1);
      end
      else
        lParts.Add(lPart);
    Result := string.Join('/', lParts.ToArray);
  finally
    lParts.Free;
  end;
end;

function CheckLinks(const pWriter: TOutputWriter): TArray<string>;
var
  lFiles: TDictionary<string, Boolean>;
  lFile, lPage, lDir, lTarget, lPath, lResolved, lReason: string;
  lM: TMatch;
  lOk: Boolean;
  lBad: TList<string>;
  lSlash: Integer;
begin
  lFiles := TDictionary<string, Boolean>.Create;
  lBad := TList<string>.Create;
  try
    for lFile in pWriter.ProducedFiles do
      lFiles.AddOrSetValue(lFile.Replace('\', '/'), True);
    for lFile in pWriter.ProducedFiles do
    begin
      lPage := lFile.Replace('\', '/');
      if not lPage.EndsWith('.md') then
        Continue;
      lSlash := lPage.LastIndexOf('/');
      lDir := '';
      if lSlash >= 0 then
        lDir := Copy(lPage, 1, lSlash);
      for lM in TRegEx.Matches(StripCode(pWriter.TextOf(lFile)), '\]\(([^)\s]+)(?:\s+"[^"]*")?\)') do
      begin
        lTarget := lM.Groups[1].Value;
        lReason := '';
        if TRegEx.IsMatch(lTarget, '^[A-Za-z]:[\\/]') or lTarget.StartsWith('file:', True) or (Pos('\', lTarget) > 0) then
          lReason := 'local path'
        else if lTarget.StartsWith('https://') then
          Continue
        else if TRegEx.IsMatch(lTarget, '^([A-Za-z][A-Za-z0-9+.\-]*:|//)') then
          lReason := 'external link is not https'
        else if lTarget.StartsWith('#') then
          Continue
        else
        begin
          lPath := lTarget;
          if Pos('#', lPath) > 0 then
            lPath := Copy(lPath, 1, Pos('#', lPath) - 1);
          lResolved := NormalisePath(lDir, lPath, lOk);
          if not lOk then
            lReason := 'leaves the site'
          else if not lFiles.ContainsKey(lResolved) then
            lReason := 'target file does not exist';
        end;
        if lReason <> '' then
          lBad.Add(lPage + ': link "' + lTarget + '" -- ' + lReason);
      end;
    end;
    Result := lBad.ToArray;
  finally
    lBad.Free;
    lFiles.Free;
  end;
end;

function BuildSiteSet(const pRepo, pEngine, pVersion: string; pCheck: Boolean): TOutputResult;
var
  lFmt: TSiteFormat;
  lHelp: TLiveHelp;
  lPages: TSitePages;
  lWriter: TOutputWriter;
  lPagesRes: TOutputResult;
  lRoot, lGenerated, lItem: string;
  lList: TList<string>;
begin
  lFmt := LoadSiteFormat(pRepo);
  lRoot := lFmt.Root.TrimRight(['\']) + '\';
  lGenerated := 'features\generated\';
  lHelp := TLiveHelp.Create;
  lPages := TSitePages.Create(pVersion);
  try
    lHelp.Load(pEngine);
    lFmt.Help := lHelp;
    lPages.LoadFromFile(TPath.Combine(pRepo, lGenerated + 'site-pages.json'));
    lWriter := TOutputWriter.Create(TPath.Combine(pRepo, lFmt.Root), pCheck, True);
    try
      BuildSite(pRepo, lFmt, lWriter, lPages);
      Result := lWriter.Finish;
    finally
      lWriter.Free;
    end;
    lWriter := TOutputWriter.Create(TPath.Combine(pRepo, lGenerated.TrimRight(['\'])), pCheck, False);
    try
      lWriter.Put('site-pages.json', lPages.ToJson, 'site-pages.json');
      lPagesRes := lWriter.Finish;
    finally
      lWriter.Free;
    end;
  finally
    lPages.Free;
    lHelp.Free;
  end;
  lList := TList<string>.Create;
  try
    for lItem in Result.Written do
      lList.Add(lRoot + lItem);
    for lItem in lPagesRes.Written do
      lList.Add(lGenerated + lItem);
    Result.Written := lList.ToArray;
    lList.Clear;
    for lItem in Result.Changed do
      lList.Add(lRoot + lItem);
    for lItem in lPagesRes.Changed do
      lList.Add(lGenerated + lItem);
    Result.Changed := lList.ToArray;
    lList.Clear;
    for lItem in Result.Removed do
      lList.Add(lRoot + lItem);
    Result.Removed := lList.ToArray;
  finally
    lList.Free;
  end;
end;

end.