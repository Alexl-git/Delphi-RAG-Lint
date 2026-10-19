unit FeatureGen.Site;

{ The website set (spec 5.2). This part: the leaf page features/<id>.md. }

interface

uses
  System.SysUtils
  , FeatureGen.Model
  , FeatureGen.SiteFormat
  , FeatureGen.Markdown
  ;

/// <summary>Renders the website leaf page of one entry.</summary>
/// <param name="pEntry">The entry.</param>
/// <param name="pFmt">Site format; pFmt.Help supplies the usage lines (nil: "drag-lint verb").</param>
/// <param name="pReg">Loaded registry: the wiki link map and the leaf order come from it.</param>
/// <param name="pRepo">Repo root; the wiki body is read from docs\wiki\&lt;WikiPage&gt;.md when that file exists.</param>
/// <param name="pImages">Receives the images the wiki body pulls in.</param>
/// <returns>The page text with LF line ends: front matter, title, summary, intro, How to run it, Where to click, Needs,
/// Details and the footer. When the wiki body has its own "Running it from the CLI" or "Usage" section, How to run it keeps
/// only the link to cli.md.</returns>
/// <exception cref="EFeatureGen">The wiki body holds raw HTML or a non-ASCII character, or a front matter key is unknown.</exception>
/// <remarks>updated is LastVerifiedBuild, else Since. order is 10 times the 1-based place among the included entries.</remarks>
function RenderLeaf(const pEntry: TFeatureEntry; const pFmt: TSiteFormat; const pReg: TRegistry; const pRepo: string;
  out pImages: TArray<TImageRef>): string;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , FeatureGen.Output
  ;

function YamlScalar(const pValue: string): string;
begin
  if (pValue = '') or (pValue <> Trim(pValue)) or (pValue.IndexOfAny([':', '"', '#', '\']) >= 0)
    or (Pos(pValue[1], '*&!|>''%@`[]{},?-') > 0) then
    Result := '"' + StringReplace(StringReplace(pValue, '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]) + '"'
  else
    Result := pValue;
end;

function LeafOrder(const pEntry: TFeatureEntry; const pFmt: TSiteFormat; const pReg: TRegistry): Integer;
var
  lE: TFeatureEntry;
begin
  Result := 10;
  for lE in pReg.Entries do
    if SiteIncludes(pFmt, lE.Status, lE.Audience) and (CompareStr(lE.Id, pEntry.Id) < 0) then
      Inc(Result, 10);
end;

function FrontMatter(const pEntry: TFeatureEntry; const pFmt: TSiteFormat; const pReg: TRegistry): string;
var
  lKey, lVal, lUpdated: string;
begin
  lUpdated := pEntry.LastVerifiedBuild;
  if lUpdated = '' then
    lUpdated := pEntry.Since;
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
      lVal := IntToStr(LeafOrder(pEntry, pFmt, pReg))
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
        lUsage := '';
        if pFmt.Help <> nil then
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

function WhereToClick(const pEntry: TFeatureEntry): string;
var
  lS: TSurface;
  lLine: string;
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
  if pEntry.WikiPage <> '' then
    lWikiFile := TPath.Combine(pRepo, 'docs\wiki\' + pEntry.WikiPage + '.md');
  if (lWikiFile <> '') and TFile.Exists(lWikiFile) then
  begin
    lMap := TWikiLinkMap.Create;
    try
      lMap.Load(pReg);
      lBody := TFile.ReadAllText(lWikiFile, TEncoding.UTF8);
      lHasCliSection := TRegEx.IsMatch(lBody, '(?im)^#{1,6}[ \t]+(Running it from the CLI|Usage)[ \t]*\r?$');
      lBody := TransformWikiBody(lBody, lMap, pEntry.Id, pImages, pFmt.FenceDefaultLang);
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
  Result := Result + HowToRun(pEntry, pFmt, lHasCliSection) + WhereToClick(pEntry);
  if Length(pEntry.Requires) > 0 then
  begin
    lNeeds := string.Join(', ', pEntry.Requires);
    Result := Result + '**Needs:** ' + lNeeds + #10#10;
  end;
  if lBody <> '' then
    Result := Result + '## Details'#10#10 + lBody + #10#10;
  Result := Result + '---'#10#10'[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)'#10;
end;

end.
