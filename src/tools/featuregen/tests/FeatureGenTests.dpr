program FeatureGenTests;

{ Self-contained console test runner for featuregen (no DUnitX). One PASS/FAIL
  line per case, a summary line, exit code 1 on any failure. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.IOUtils
  , System.Classes
  , System.JSON
  , FeatureGen.Json in '..\FeatureGen.Json.pas'
  , FeatureGen.Model in '..\FeatureGen.Model.pas'
  , FeatureGen.Output in '..\FeatureGen.Output.pas'
  , FeatureGen.Live in '..\FeatureGen.Live.pas'
  , FeatureGen.SiteFormat in '..\FeatureGen.SiteFormat.pas'
  , FeatureGen.Markdown in '..\FeatureGen.Markdown.pas'
  , FeatureGen.Site in '..\FeatureGen.Site.pas'
  ;

var
  GPass: Integer = 0;
  GFail: Integer = 0;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

{ Walks up from the exe dir to the first dir holding features\entries. }
function FindRepoRoot: string;
var
  lDir, lParent: string;
begin
  lDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  while lDir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(lDir, 'features\entries')) then
      Exit(lDir);
    lParent := ExtractFileDir(lDir);
    if lParent = lDir then
      Break;
    lDir := lParent;
  end;
  Result := '';
end;

function ReadAllBytesAsText(const pPath: string): string;
begin
  Result := TEncoding.ASCII.GetString(TFile.ReadAllBytes(pPath));
end;

procedure TestRoundTripRealEntries(const pRepo: string);
var
  lFiles: TArray<string>;
  lFile, lText, lBack: string;
  lOrder: TArray<string>;
  lVal: TJSONValue;
  lBad, lCount: Integer;
  lFirstBad: string;
begin
  lOrder := EntryKeyOrder(TPath.Combine(pRepo, 'features\schema\entry.schema.json'));
  lFiles := TDirectory.GetFiles(TPath.Combine(pRepo, 'features\entries'), '*.json');
  lBad := 0;
  lCount := 0;
  lFirstBad := '';
  for lFile in lFiles do
  begin
    Inc(lCount);
    lText := ReadAllBytesAsText(lFile);
    lVal := ReadJsonFile(lFile);
    try
      lBack := CanonicalJson(lVal, lOrder);
    finally
      lVal.Free;
    end;
    if lBack <> lText then
    begin
      Inc(lBad);
      if lFirstBad = '' then
        lFirstBad := ExtractFileName(lFile);
    end;
  end;
  Check('Json.RoundTripRealEntries', (lBad = 0) and (lCount > 0),
    Format('%d of %d differ, first: %s', [lBad, lCount, lFirstBad]));
end;

procedure TestLoadMini;
var
  lReg: TRegistry;
  lE: TArray<TFeatureEntry>;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\mini'));
    lE := lReg.Entries;
    Check('Model.LoadMini.count', Length(lE) = 3, IntToStr(Length(lE)));
    if Length(lE) = 3 then
    begin
      Check('Model.LoadMini.ordinal',
        (lE[0].Id = 'add-missing-units-to-uses-whole-unit') and (lE[1].Id = 'allow-this-message') and (lE[2].Id = 'outline'),
        lE[0].Id + ',' + lE[1].Id + ',' + lE[2].Id);
      Check('Model.LoadMini.groupTitle', (lE[0].GroupTitle = 'Compiler integration') and (lE[2].GroupTitle = 'Search and navigation'),
        lE[0].GroupTitle + '|' + lE[2].GroupTitle);
      Check('Model.LoadMini.missingOptional', (lE[2].Intro = '') and (lE[2].Notes = '') and (lE[2].LastVerifiedBuild = ''), lE[2].Intro);
      Check('Model.LoadMini.surfaces', (Length(lE[1].Surfaces) = 2) and (lE[1].Surfaces[0].Kind = 'ide-context')
        and (lE[1].Surfaces[0].Host = 'Structure form') and (lE[1].Surfaces[1].Verb = 'allow') and (lE[1].Surfaces[1].Path = ''));
    end;
  finally
    lReg.Free;
  end;
end;

procedure TestProp;
var
  lObj: TJSONValue;
begin
  lObj := TJSONObject.ParseJSONValue('{"a":"x","n":5,"b":true}');
  try
    Check('Json.Prop', (Prop(lObj, 'a') = 'x') and (Prop(lObj, 'n') = '5') and (Prop(lObj, 'b') = 'true') and (Prop(lObj, 'zz') = '') and (Prop(nil, 'a') = ''));
  finally
    lObj.Free;
  end;
end;

const
  SCRATCH = 'C:\TEMP\claude\featuregen-task2';

function FreshDir(const pName: string): string;
begin
  Result := TPath.Combine(SCRATCH, pName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  ForceDirectories(Result);
end;

function ReadBytesText(const pPath: string): string;
begin
  Result := TEncoding.ASCII.GetString(TFile.ReadAllBytes(pPath));
end;

procedure TestWriteOnlyWhenDifferent;
var
  lDir, lFile: string;
  lW: TOutputWriter;
  lR: TOutputResult;
  lOld, lNew: TDateTime;
  lR2: TOutputResult;
begin
  lDir := FreshDir('wowd');
  lFile := TPath.Combine(lDir, 'a\b.txt');
  lW := TOutputWriter.Create(lDir, False, False);
  try
    lW.Put('a\b.txt', 'one'#13#10'two'#13#10, 'ctx');
    lR := lW.Finish;
  finally
    lW.Free;
  end;
  Check('Output.WriteOnlyWhenDifferent.first', (Length(lR.Written) = 1) and TFile.Exists(lFile));
  lOld := EncodeDate(2001, 2, 3);
  TFile.SetLastWriteTime(lFile, lOld);
  lW := TOutputWriter.Create(lDir, False, False);
  try
    lW.Put('a\b.txt', 'one'#13#10'two'#13#10, 'ctx');
    lR2 := lW.Finish;
  finally
    lW.Free;
  end;
  lNew := TFile.GetLastWriteTime(lFile);
  Check('Output.WriteOnlyWhenDifferent', (lNew = lOld) and (Length(lR2.Written) = 0) and (Length(lR2.Changed) = 0),
    DateTimeToStr(lNew));
end;

procedure TestLfBecomesCrlf;
var
  lDir: string;
  lW: TOutputWriter;
begin
  lDir := FreshDir('crlf');
  lW := TOutputWriter.Create(lDir, False, False);
  try
    lW.Put('x.txt', 'a'#10'b'#13#10'c', 'ctx');
    lW.Finish;
  finally
    lW.Free;
  end;
  Check('Output.LfBecomesCrlf', ReadBytesText(TPath.Combine(lDir, 'x.txt')) = 'a'#13#10'b'#13#10'c',
    ReadBytesText(TPath.Combine(lDir, 'x.txt')));
end;

procedure TestNonAsciiRaisesWithContext;
var
  lW: TOutputWriter;
  lMsg: string;
begin
  lMsg := '';
  lW := TOutputWriter.Create(FreshDir('nonascii'), False, False);
  try
    try
      lW.Put('x.txt', 'ok'#10'bad ' + Char($00E9), 'entry foo field intro');
    except
      on E: EFeatureGen do
        lMsg := E.Message;
    end;
  finally
    lW.Free;
  end;
  Check('Output.NonAsciiRaisesWithContext', (Pos('entry foo field intro', lMsg) > 0) and (Pos('line 2', lMsg) > 0), lMsg);
end;

procedure TestCheckWritesNothing;
var
  lDir: string;
  lW: TOutputWriter;
  lR: TOutputResult;
begin
  lDir := FreshDir('check');
  TFile.WriteAllText(TPath.Combine(lDir, 'old.txt'), 'a'#13#10'b'#13#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lDir, 'stale.txt'), 's', TEncoding.ASCII);
  lW := TOutputWriter.Create(lDir, True, True);
  try
    lW.Put('old.txt', 'a'#13#10'c'#13#10, 'ctx');
    lW.Put('new.txt', 'n', 'ctx');
    lR := lW.Finish;
  finally
    lW.Free;
  end;
  Check('Output.CheckWritesNothing',
    (ReadBytesText(TPath.Combine(lDir, 'old.txt')) = 'a'#13#10'b'#13#10) and not TFile.Exists(TPath.Combine(lDir, 'new.txt'))
    and TFile.Exists(TPath.Combine(lDir, 'stale.txt')) and (Length(lR.Written) = 0) and (Length(lR.Removed) = 0)
    and (Length(lR.Changed) = 3), IntToStr(Length(lR.Changed)));
  Check('Output.CheckDiffHead', (Length(lR.Changed) > 0) and (Pos('first difference at line 2', lR.Changed[0]) > 0)
    and (Pos('-b', lR.Changed[0]) > 0) and (Pos('+c', lR.Changed[0]) > 0), lR.Changed[0]);
end;

procedure TestOwnedRootRemovesStale;
var
  lDir: string;
  lW: TOutputWriter;
  lR: TOutputResult;
begin
  lDir := FreshDir('owned');
  ForceDirectories(TPath.Combine(lDir, 'sub'));
  TFile.WriteAllText(TPath.Combine(lDir, 'sub\stale.txt'), 's', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lDir, 'keep.txt'), 'k', TEncoding.ASCII);
  lW := TOutputWriter.Create(lDir, False, True);
  try
    lW.Put('keep.txt', 'k', 'ctx');
    lR := lW.Finish;
  finally
    lW.Free;
  end;
  Check('Output.OwnedRootRemovesStale', not TFile.Exists(TPath.Combine(lDir, 'sub\stale.txt'))
    and TFile.Exists(TPath.Combine(lDir, 'keep.txt')) and (Length(lR.Removed) = 1) and (Length(lR.Written) = 0),
    IntToStr(Length(lR.Removed)));
end;

procedure TestNeverOutsideRoot;
var
  lDir: string;
  lW: TOutputWriter;
  lRaised, lRaisedAbs: Boolean;
begin
  lDir := FreshDir('outside');
  lRaised := False;
  lRaisedAbs := False;
  lW := TOutputWriter.Create(lDir, False, False);
  try
    try
      lW.Put('..\x.txt', 'x', 'ctx');
    except
      on EFeatureGen do
        lRaised := True;
    end;
    try
      lW.Put('C:\TEMP\claude\featuregen-task2\x.txt', 'x', 'ctx');
    except
      on EFeatureGen do
        lRaisedAbs := True;
    end;
  finally
    lW.Free;
  end;
  Check('Output.NeverOutsideRoot', lRaised and lRaisedAbs and not TFile.Exists(TPath.Combine(SCRATCH, 'x.txt')));
end;

procedure TestPutBinary;
var
  lDir, lSrc: string;
  lW: TOutputWriter;
begin
  lDir := FreshDir('bin');
  lSrc := TPath.Combine(lDir, 'src.bin');
  TFile.WriteAllBytes(lSrc, TBytes.Create(0, 200, 13, 10, 255));
  lW := TOutputWriter.Create(TPath.Combine(lDir, 'out'), False, False);
  try
    lW.PutBinary('i\p.bin', lSrc);
    lW.Finish;
  finally
    lW.Free;
  end;
  Check('Output.PutBinary', TFile.ReadAllBytes(TPath.Combine(lDir, 'out\i\p.bin'))[1] = 200);
end;
function MiniDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\mini');
end;

function NewMap: TWikiLinkMap;
begin
  Result := TWikiLinkMap.Create;
  Result.Add('ask', 'ask');
  Result.Add('Outline', 'outline');
end;

function RaisedMessage(const pMd: string; const pMap: TWikiLinkMap): string;
var
  lImg: TArray<TImageRef>;
begin
  Result := '';
  try
    TransformWikiBody(pMd, pMap, 'ask', lImg);
  except
    on E: EFeatureGen do
      Result := E.Message;
  end;
end;

procedure TestMarkdown;
var
  lMap: TWikiLinkMap;
  lImg: TArray<TImageRef>;
  lOut, lMsg: string;
begin
  lMap := NewMap;
  try
    lOut := TransformWikiBody('# ask'#10#10'## Flags'#10'text'#10'```'#10'# not a heading'#10'```'#10'```pascal'#10'x'#10'```'#10, lMap, 'ask', lImg);
    Check('Md.DemoteAndTagFences',
      (Pos('# ask', lOut) = 0) and (Pos('### Flags', lOut) > 0) and (Pos('```text'#10'# not a heading'#10'```'#10'```pascal', lOut) > 0),
      lOut);
    lOut := TransformWikiBody('see [[ask#flags]] and [[ask|the verb]] and [ask](ask.md#x) and [o](Outline) and `[[ask]]`', lMap, 'ask', lImg);
    Check('Md.LinkInSetKeepsAnchor',
      (Pos('[ask](ask.md#flags)', lOut) > 0) and (Pos('[the verb](ask.md)', lOut) > 0) and (Pos('[ask](ask.md#x)', lOut) > 0)
      and (Pos('[o](outline.md)', lOut) > 0) and (Pos('`[[ask]]`', lOut) > 0), lOut);
    lOut := TransformWikiBody('see [[Gone]] and [[Gone|that page]] and [t](Gone.md#a) and [e](https://x.org/a)', lMap, 'ask', lImg);
    Check('Md.LinkOutOfSetBecomesText', lOut = 'see Gone and that page and t and [e](https://x.org/a)', lOut);
    lOut := TransformWikiBody('![a](../Images/x.PNG) and ![b](../Images/y.svg)', lMap, 'ask', lImg);
    Check('Md.ImageCopiedAndRenamed',
      (lOut = '![a](img/ask-1.png) and ![b](img/ask-2.svg)') and (Length(lImg) = 2) and (lImg[0].Source = 'docs\Images\x.PNG')
      and (lImg[0].Target = 'img\ask-1.png') and (lImg[1].Target = 'img\ask-2.svg'), lOut);
    lMsg := RaisedMessage('fine'#10'ok'#10'a <b>bold</b> word'#10, lMap);
    Check('Md.RawHtmlFails', (Pos('ask', lMsg) > 0) and (Pos('line 3', lMsg) > 0), lMsg);
    lMsg := RaisedMessage('fine `<tag>` and'#10'```'#10'<b>'#10'```'#10, lMap);
    lOut := TransformWikiBody('see [`deps`](Outline) and [x `<b>`](Gone) and `<i>`', lMap, 'ask', lImg);
    Check('Md.LinkWithCodeSpanText', lOut = 'see [`deps`](outline.md) and x `<b>` and `<i>`', lOut);
    Check('Md.HtmlInCodeAllowed', lMsg = '', lMsg);
    lMsg := RaisedMessage('one'#10'caf' + Char($00E9), lMap);
    Check('Md.NonAsciiFails', (Pos('ask', lMsg) > 0) and (Pos('line 2', lMsg) > 0), lMsg);
  finally
    lMap.Free;
  end;
end;

const
  HELP_SNIPPET = 'drag-lint 1.0'#13#10'Commands:'#13#10'  drag-lint outline   --file <f>  [--db <d>]'#13#10
    + '  drag-lint query find-callers --name N'#13#10'  drag-lint outlines x'#13#10;

function MiniFormat(pHelp: TLiveHelp): TSiteFormat;
begin
  Result := Default(TSiteFormat);
  Result.Product := 'DL';
  Result.FrontMatterKeys := TArray<string>.Create('id', 'title', 'summary', 'product', 'group', 'order', 'since', 'status', 'updated');
  Result.IncludeStatuses := TArray<string>.Create('shipped', 'experimental');
  Result.ExcludeAudiences := TArray<string>.Create('agent');
  Result.FenceDefaultLang := 'text';
  Result.Help := pHelp;
end;

function EntryById(const pReg: TRegistry; const pId: string): TFeatureEntry;
var
  lE: TFeatureEntry;
begin
  Result := Default(TFeatureEntry);
  for lE in pReg.Entries do
    if lE.Id = pId then
      Result := lE;
end;

procedure TestLeaves;
var
  lReg: TRegistry;
  lHelp: TLiveHelp;
  lFmt: TSiteFormat;
  lImg: TArray<TImageRef>;
  lOut, lHow: string;
  lP: Integer;
  lE: TFeatureEntry;
begin
  lReg := TRegistry.Create;
  lHelp := TLiveHelp.Create;
  try
    lReg.Load(MiniDir);
    lHelp.LoadFromText(HELP_SNIPPET);
    Check('Live.UsageFor', (lHelp.UsageFor('outline') = 'drag-lint outline --file <f> [--db <d>]')
      and (lHelp.UsageFor('query find-callers') = 'drag-lint query find-callers --name N') and (lHelp.UsageFor('nope') = ''),
      lHelp.UsageFor('outline'));
    lFmt := MiniFormat(lHelp);
    lE := EntryById(lReg, 'outline');
    lOut := RenderLeaf(lE, lFmt, lReg, MiniDir, lImg);
    Check('Leaf.FrontMatterExact',
      lOut.StartsWith('---'#10'id: outline'#10'title: outline'#10'summary: Prints the file-scoped symbol outline for one Pascal unit'#10
        + 'product: DL'#10'group: search-navigation'#10'order: 20001'#10'since: 0.86.0-alpha'#10'status: shipped'#10'updated: 0.86.0-alpha'#10
        + '---'#10#10'# outline'#10#10'Prints the file-scoped symbol outline for one Pascal unit.'#10#10'## How to run it'#10),
      Copy(lOut, 1, 400));
    lFmt.ExcludeAudiences := TArray<string>.Create('both');
    lE := EntryById(lReg, 'outline');
    lOut := RenderLeaf(lE, lFmt, lReg, MiniDir, lImg);
    Check('Leaf.LinkToExcludedEntryIsPlainText', (Pos('allow-this-message.md', lOut) = 0) and (Pos('See Allow-this-message and', lOut) > 0), lOut);
    lFmt := MiniFormat(lHelp);
    lHelp.LoadFromText('  drag-lint ask-deps --target T'#10'  drag-lint ask   <q>  --x');
    Check('Live.UsageForNotHyphenSibling', lHelp.UsageFor('ask') = 'drag-lint ask <q> --x', lHelp.UsageFor('ask'));
    lHelp.LoadFromText(HELP_SNIPPET);
    lE := EntryById(lReg, 'add-missing-units-to-uses-whole-unit');
    lE.Title := 'Add: units';
    lOut := RenderLeaf(lE, lFmt, lReg, MiniDir, lImg);
    Check('Leaf.NoWikiPageStillRenders',
      (Pos('title: "Add: units"', lOut) > 0) and (Pos('## Details', lOut) = 0) and (Pos('## Where to click', lOut) > 0)
      and (Pos('* RAD Studio main menu: **drag-lint > Uses & Dependencies > Add Missing Units to uses (whole unit)...**', lOut) > 0)
      and (Pos('[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)', lOut) > 0)
      and (Pos('## How to run it', lOut) > 0) and (Pos('drag-lint check-unit', lOut) > 0), lOut);
    lE := EntryById(lReg, 'outline');
    lOut := RenderLeaf(lE, lFmt, lReg, MiniDir, lImg);
    lP := Pos('## Details', lOut);
    lHow := Copy(lOut, 1, lP);
    Check('Leaf.NoDuplicateUsageWhenWikiHasCliSection',
      (lP > 0) and (Pos('## How to run it', lHow) > 0) and (Pos('../cli.md#outline', lHow) > 0) and (Pos('--file', lHow) = 0)
      and (Pos('--file <path.pas>', Copy(lOut, lP, MaxInt)) > 0) and (Pos('[Allow-this-message](allow-this-message.md)', lOut) > 0)
      and (Pos('a page that is not on the site', lOut) > 0) and (Pos('Nowhere', lOut) = 0), lOut);
    lE.Surfaces[0].Example := 'drag-lint outline --file U.pas';
    lE.WikiPage := '';
    lOut := RenderLeaf(lE, lFmt, lReg, MiniDir, lImg);
    Check('Leaf.ExampleFencedWithText',
      (Pos('```text'#10'drag-lint outline --file <f> [--db <d>]'#10'```'#10#10'Example:'#10#10'```text'#10'drag-lint outline --file U.pas'#10'```'#10, lOut) > 0)
      and (Pos('Full flag list: [outline in the CLI reference](../cli.md#outline).', lOut) > 0), lOut);
  finally
    lHelp.Free;
    lReg.Free;
  end;
end;

procedure TestSiteFormatFile(const pRepo: string);
var
  lFmt: TSiteFormat;
begin
  lFmt := LoadSiteFormat(pRepo);
  Check('SiteFormat.Load', (lFmt.Root = 'WWW\help\dl') and (lFmt.Product = 'DL') and (Length(lFmt.FrontMatterKeys) = 9)
    and (lFmt.FenceDefaultLang = 'text') and (lFmt.ImageDir = 'features/img') and (lFmt.UndocumentedSource = 'tests\autotest\run_docs_sync_guard.ps1')
    and (lFmt.MicroniteIndex <> lFmt.MicroniteWhatsNew) and (Pos('https://www.htrmicronite.com', lFmt.MicroniteIndex) > 0)
    and (Pos('https://www.htrmicronite.com', lFmt.MicroniteWhatsNew) > 0) and SiteIncludes(lFmt, 'shipped', 'both')
    and not SiteIncludes(lFmt, 'internal', 'both') and not SiteIncludes(lFmt, 'shipped', 'agent'), lFmt.Root);
end;

procedure TestWikiLinkMapFromRegistry;
var
  lReg: TRegistry;
  lMap: TWikiLinkMap;
  lId: string;
begin
  lReg := TRegistry.Create;
  lMap := TWikiLinkMap.Create;
  try
    lReg.Load(MiniDir);
    lMap.Load(lReg, MiniFormat(nil));
    Check('Md.WikiLinkMapFromRegistry', lMap.TryGet('outline', lId) and (lId = 'outline') and lMap.TryGet('Allow-this-message', lId)
      and (lId = 'allow-this-message') and not lMap.TryGet('zzz', lId));
  finally
    lMap.Free;
    lReg.Free;
  end;
end;

{ ---- Task 4: the site set ---- }

const
  SITE_HELP = '  drag-lint ask   <q> [--db <d>]'#10'  drag-lint query find-callers --name N'#10'  drag-lint query text --t T'#10;

function SiteDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\site');
end;

function ReadSiteFile(const pRoot, pRel: string): string;
begin
  Result := ReadBytesText(TPath.Combine(pRoot, pRel.Replace('/', '\'))).Replace(#13#10, #10);
end;

{ Builds the fixture site into pOut. Returns the writer result. }
function BuildFixture(const pRepo, pOut: string; pCheck: Boolean; pHelp: TLiveHelp): TOutputResult;
var
  lFmt: TSiteFormat;
  lW: TOutputWriter;
begin
  lFmt := LoadSiteFormat(pRepo);
  lFmt.Help := pHelp;
  lW := TOutputWriter.Create(pOut, pCheck, True);
  try
    BuildSite(pRepo, lFmt, lW);
    Result := lW.Finish;
  finally
    lW.Free;
  end;
end;

function Occurrences(const pText, pSub: string): Integer;
var
  lP: Integer;
begin
  Result := 0;
  lP := Pos(pSub, pText);
  while lP > 0 do
  begin
    Inc(Result);
    lP := Pos(pSub, pText, lP + Length(pSub));
  end;
end;

procedure TestUndocumentedVerbs;
var
  lVerbs: TArray<string>;
  lTmp, lMsg: string;
  lFmt: TSiteFormat;
begin
  lVerbs := ReadUndocumentedVerbs(TPath.Combine(SiteDir, 'guard.ps1'));
  Check('Site.UndocumentedKeysRead', (Length(lVerbs) = 2) and (lVerbs[0] = 'selftest') and (lVerbs[1] = 'dump-thing'), IntToStr(Length(lVerbs)));
  lFmt := LoadSiteFormat(SiteDir);
  Check('Site.FormatLoadsExcludedVerbs', (Length(lFmt.ExcludedVerbs) = 2) and not SiteIncludes(lFmt, 'internal', ''));
  lTmp := FreshDir('noblock');
  TFile.WriteAllText(TPath.Combine(lTmp, 'g.ps1'), '$Other = 1'#13#10, TEncoding.ASCII);
  lMsg := '';
  try
    ReadUndocumentedVerbs(TPath.Combine(lTmp, 'g.ps1'));
  except
    on E: EFeatureGen do
      lMsg := E.Message;
  end;
  Check('Site.UndocumentedBlockMissingFails', Pos('UndocumentedOnPurpose', lMsg) > 0, lMsg);
  TFile.WriteAllText(TPath.Combine(lTmp, 'e.ps1'), '$UndocumentedOnPurpose = [ordered]@{'#13#10'}'#13#10, TEncoding.ASCII);
  lMsg := '';
  try
    ReadUndocumentedVerbs(TPath.Combine(lTmp, 'e.ps1'));
  except
    on E: EFeatureGen do
      lMsg := E.Message;
  end;
  Check('Site.UndocumentedEmptyBlockFails', Pos('UndocumentedOnPurpose', lMsg) > 0, lMsg);
end;

procedure TestSite;
var
  lHelp: TLiveHelp;
  lOutA, lOutB, lFile, lIndex, lJson, lCli, lIde, lNew, lMap, lAll, lRel, lLeaf, lSentI, lSentN: string;
  lRes: TOutputResult;
  lFmt: TSiteFormat;
  lIds, lOrders: TArray<string>;
  lId: string;
  lArr: TJSONArray;
  lVal: TJSONValue;
  lBad, lI: Integer;
  lFiles: TArray<string>;
  lSame: Boolean;
begin
  lHelp := TLiveHelp.Create;
  try
    lHelp.LoadFromText(SITE_HELP);
    lOutA := FreshDir('siteA');
    lOutB := FreshDir('siteB');
    BuildFixture(SiteDir, lOutA, False, lHelp);
    lIndex := ReadSiteFile(lOutA, 'index.md');
    lIds := TArray<string>.Create('ask', 'find-callers', 'find-text', 'fix-refactor', 'fix-uses');
    lBad := 0;
    for lId in lIds do
      if (Occurrences(lIndex, '](features/' + lId + '.md)') <> 1) or not TFile.Exists(TPath.Combine(lOutA, 'features\' + lId + '.md')) then
        Inc(lBad);
    Check('Site.IndexLinksEveryIncludedLeafOnce', (lBad = 0) and (Occurrences(lIndex, '](features/') = 5), lIndex);
    Check('Site.IndexGroupsTablesPipeEscaped', (Pos('## IDE group', lIndex) < Pos('## Search group', lIndex)) and (Pos('Empty group', lIndex) = 0)
      and (Pos('| Feature | What it does | Since |', lIndex) > 0) and (Pos('| [Find callers](features/find-callers.md) | Finds callers \| of a name | 0.86.0-alpha |', lIndex) > 0)
      and (Pos('| [Ask](features/ask.md) |', lIndex) < Pos('| [Find callers]', lIndex)), lIndex);

    lAll := '';
    for lFile in TDirectory.GetFiles(lOutA, '*', TSearchOption.soAllDirectories) do
      lAll := lAll + #10 + ReadBytesText(lFile);
    lCli := ReadSiteFile(lOutA, 'cli.md');
    Check('Site.InternalEntryAbsentEverywhere',
      not TFile.Exists(TPath.Combine(lOutA, 'features\internal-thing.md')) and not TFile.Exists(TPath.Combine(lOutA, 'features\selftest-thing.md'))
      and (Pos('internal-thing', lAll) = 0) and (Pos('selftest-thing', lAll) = 0) and (Pos('### hidden', lCli) = 0) and (Pos('### selftest', lCli) = 0)
      and (Pos('Selftest-thing', ReadSiteFile(lOutA, 'features/ask.md')) > 0), lAll);

    lJson := ReadSiteFile(lOutA, 'index.json');
    lVal := TJSONObject.ParseJSONValue(lJson);
    try
      lBad := 0;
      lArr := nil;
      if lVal is TJSONArray then
        lArr := TJSONArray(lVal);
      Check('Site.IndexJsonIsArrayOfFive', (lArr <> nil) and (lArr.Count = 5), lJson);
      if (lArr <> nil) and (lArr.Count = 5) then
      begin
        lOrders := TArray<string>.Create('10001', '10002', '20001', '20002', '20003');
        lIds := TArray<string>.Create('fix-refactor', 'fix-uses', 'ask', 'find-callers', 'find-text');
        for lI := 0 to 4 do
        begin
          lRel := lArr.Items[lI].GetValue<string>('file');
          lLeaf := ReadSiteFile(lOutA, lRel);
          if (lArr.Items[lI].GetValue<string>('id') <> lIds[lI]) or (lArr.Items[lI].GetValue<string>('order') <> lOrders[lI])
            or (lRel <> 'features/' + lIds[lI] + '.md') or (Pos(#10'order: ' + lOrders[lI] + #10, lLeaf) = 0)
            or (Pos(#10'title: ' + lArr.Items[lI].GetValue<string>('title') + #10, lLeaf) = 0)
            or (lArr.Items[lI].GetValue<string>('since') = '') or (lArr.Items[lI].GetValue<string>('group') = '')
            or (lArr.Items[lI].GetValue<string>('summary') = '') then
            Inc(lBad);
        end;
        Check('Site.IndexJsonMatchesFiles', lBad = 0, lJson);
      end;
    finally
      lVal.Free;
    end;

    lIde := ReadSiteFile(lOutA, 'ide.md');
    Check('Site.IdeTreeSameCaptionTwoParents',
      Pos('* drag-lint'#10'  * Refactor'#10'    * [Fix](features/fix-refactor.md)'#10'  * Uses'#10'    * [Fix](features/fix-uses.md)'#10, lIde) > 0, lIde);
    Check('Site.IdeTreeHasEveryLevel', (Occurrences(lIde, '* drag-lint'#10) = 1) and (Pos('  * Uses'#10, lIde) > 0) and (Pos('  * Refactor'#10, lIde) > 0)
      and (Occurrences(lIde, '[Fix](') = 2), lIde);

    lMap := ReadSiteFile(lOutA, 'wiki-map.json');
    Check('Site.WikiMapLowestId', lMap = '{'#10'  "Ask": "ask",'#10'  "Shared": "find-callers"'#10'}'#10, lMap);

    lNew := ReadSiteFile(lOutA, 'whats-new.md');
    Check('Site.WhatsNewDescendingNumericOrdinalBullets',
      (Pos('## 0.86.0-alpha', lNew) > 0) and (Pos('## 0.86.0-alpha', lNew) < Pos('## 0.50.0-alpha', lNew)) and (Pos('## 0.50.0-alpha', lNew) < Pos('## 0.9.0-alpha', lNew))
      and (Pos('[Find callers]', lNew) < Pos('[Fix uses]', lNew)) and (Pos('[Fix uses]', lNew) < Pos('## 0.50.0-alpha', lNew)), lNew);

    Check('Site.CliOneHeadingPerVerbWithUsageAndLeaves',
      (Occurrences(lCli, '### query'#10) = 1) and (Pos('### ask'#10, lCli) < Pos('### query'#10, lCli)) and (Pos('drag-lint ask <q> [--db <d>]', lCli) > 0)
      and (Pos('drag-lint query find-callers --name N', lCli) > 0) and (Pos('* [Find callers](features/find-callers.md)', lCli) > 0)
      and (Pos('* [Find text](features/find-text.md)', lCli) > 0) and (Pos('Described in [Ask](features/ask.md).', lCli) > 0), lCli);

    lFmt := LoadSiteFormat(SiteDir);
    lSentI := lFmt.MicroniteIndex;
    lSentN := lFmt.MicroniteWhatsNew;
    lBad := 0;
    for lFile in TDirectory.GetFiles(lOutA, '*', TSearchOption.soAllDirectories) do
    begin
      lRel := Copy(lFile, Length(lOutA) + 2, MaxInt).Replace('\', '/');
      if (Pos('htrmicronite', ReadBytesText(lFile)) > 0) <> ((lRel = 'index.md') or (lRel = 'whats-new.md')) then
        Inc(lBad);
    end;
    Check('Site.MicroniteOnlyInIndexAndWhatsNew', (lBad = 0) and (lSentI <> lSentN) and (Pos(lSentI, lIndex) > 0) and (Pos(lSentI, lIndex) < Pos('## ', lIndex))
      and (Pos(lSentN, lNew) > 0) and (Pos(lSentN, lNew) < Pos('## ', lNew)) and (Pos(lSentN, lIndex) = 0) and (Pos(lSentI, lNew) = 0),
      IntToStr(lBad));

    BuildFixture(SiteDir, lOutB, False, lHelp);
    lFiles := TDirectory.GetFiles(lOutA, '*', TSearchOption.soAllDirectories);
    lSame := Length(lFiles) = Length(TDirectory.GetFiles(lOutB, '*', TSearchOption.soAllDirectories));
    for lFile in lFiles do
    begin
      lRel := Copy(lFile, Length(lOutA) + 2, MaxInt);
      if not TFile.Exists(TPath.Combine(lOutB, lRel)) or (ReadBytesText(lFile) <> ReadBytesText(TPath.Combine(lOutB, lRel))) then
        lSame := False;
    end;
    lRes := BuildFixture(SiteDir, lOutA, False, lHelp);
    Check('Site.TwoBuildsByteIdentical', lSame and (Length(lFiles) > 8) and (Length(lRes.Written) = 0) and (Length(lRes.Changed) = 0), IntToStr(Length(lFiles)));
    lRes := BuildFixture(SiteDir, lOutA, True, lHelp);
    Check('Site.CheckModeCleanAfterBuild', Length(lRes.Changed) = 0);

    ForceDirectories(TPath.Combine(lOutA, 'features'));
    TFile.WriteAllText(TPath.Combine(lOutA, 'features\old-gone.md'), 'x', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(lOutA, 'junk.txt'), 'x', TEncoding.ASCII);
    lRes := BuildFixture(SiteDir, lOutA, True, lHelp);
    Check('Site.CheckModeReportsStaleWritesNothing', (Length(lRes.Changed) = 2) and TFile.Exists(TPath.Combine(lOutA, 'junk.txt')));
    lRes := BuildFixture(SiteDir, lOutA, False, lHelp);
    Check('Site.StaleFileRemoved', (Length(lRes.Removed) = 2) and not TFile.Exists(TPath.Combine(lOutA, 'features\old-gone.md'))
      and not TFile.Exists(TPath.Combine(lOutA, 'junk.txt')) and (Length(lRes.Written) = 0), IntToStr(Length(lRes.Removed)));
  finally
    lHelp.Free;
  end;
end;

procedure TestSiteDanglingLink;
var
  lRepo, lOut, lMsg, lPath, lTxt: string;
  lFmt: TSiteFormat;
  lW: TOutputWriter;
begin
  lRepo := TPath.Combine(SCRATCH, 'dangling-repo');
  if TDirectory.Exists(lRepo) then
    TDirectory.Delete(lRepo, True);
  TDirectory.Copy(SiteDir, lRepo);
  lPath := TPath.Combine(lRepo, 'features\entries\ask.json');
  lTxt := TFile.ReadAllText(lPath, TEncoding.ASCII);
  lTxt := lTxt.Replace('"summary": "Asks a question"', '"summary": "Asks a question", "intro": "See [gone](gone.md)."');
  TFile.WriteAllText(lPath, lTxt, TEncoding.ASCII);
  lOut := TPath.Combine(SCRATCH, 'dangling-out');
  if TDirectory.Exists(lOut) then
    TDirectory.Delete(lOut, True);
  lFmt := LoadSiteFormat(lRepo);
  lW := TOutputWriter.Create(lOut, False, True);
  try
    lMsg := '';
    try
      BuildSite(lRepo, lFmt, lW);
    except
      on E: EFeatureGen do
        lMsg := E.Message;
    end;
    Check('Site.DanglingLinkFails', (Pos('features/ask.md', lMsg) > 0) and (Pos('"gone.md"', lMsg) > 0) and (Pos('does not exist', lMsg) > 0)
      and not TDirectory.Exists(lOut), lMsg);
  finally
    lW.Free;
  end;
end;

procedure TestCheckLinks;
var
  lOut: string;
  lW: TOutputWriter;
  lBad: TArray<string>;
  lJoined: string;
begin
  lOut := FreshDir('checklinks');
  lW := TOutputWriter.Create(lOut, True, False);
  try
    lW.Put('a.md', '[ok](b.md) [ok2](sub/../b.md#frag) [anchor](#top) [miss](missing.md) [h](http://x.org/a) [s](https://ok.org/p) ![i](img/p.png)'#10
      + '[f](file:///c:/x.md) [d](C:\x\y.md) [bs](sub\b.md) [up](../x.md)'#10'```text'#10'[z](nope.md)'#10'```'#10'`[c](nope2.md)`'#10, 'ctx');
    lW.Put('b.md', 'b', 'ctx');
    lW.Put('sub/c.md', '[back](../b.md) [self](c.md) [bad](b.md)', 'ctx');
    lW.PutBinary('img/p.png', ParamStr(0));
    lBad := CheckLinks(lW);
    lJoined := string.Join('|', lBad);
    Check('Site.CheckLinksRules', (Length(lBad) = 7) and (Pos('a.md: link "missing.md"', lJoined) > 0) and (Pos('"http://x.org/a" -- external link is not https', lJoined) > 0)
      and (Pos('"file:///c:/x.md" -- local path', lJoined) > 0) and (Pos('"C:\x\y.md" -- local path', lJoined) > 0)
      and (Pos('"sub\b.md" -- local path', lJoined) > 0) and (Pos('"../x.md" -- leaves the site', lJoined) > 0)
      and (Pos('nope', lJoined) = 0) and (Pos('sub/c.md: link "b.md" -- target file does not exist', lJoined) > 0), lJoined);
  finally
    lW.Free;
  end;
end;

var
  lRepo: string;
begin
  try
    lRepo := FindRepoRoot;
    Check('Harness.RepoRootFound', lRepo <> '', ParamStr(0));
    if lRepo <> '' then
      TestRoundTripRealEntries(lRepo);
    TestProp;
    TestLoadMini;
    TestWriteOnlyWhenDifferent;
    TestLfBecomesCrlf;
    TestNonAsciiRaisesWithContext;
    TestCheckWritesNothing;
    TestOwnedRootRemovesStale;
    TestNeverOutsideRoot;
    TestPutBinary;
    TestMarkdown;
    TestWikiLinkMapFromRegistry;
    TestLeaves;
    TestUndocumentedVerbs;
    TestSite;
    TestSiteDanglingLink;
    TestCheckLinks;
    if lRepo <> '' then
      TestSiteFormatFile(lRepo);
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL EXCEPTION ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    Halt(1);
end.
