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
  , FeatureGen.HelpImport in '..\FeatureGen.HelpImport.pas'
  , FeatureGen.Wiki in '..\FeatureGen.Wiki.pas'
  , System.Generics.Collections
  , System.RegularExpressions
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
    Check('Model.LoadMini.count', Length(lE) = 4, IntToStr(Length(lE)));
    if Length(lE) = 4 then
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
  SCRATCH = 'C:\TEMP\claude\featuregen-task4\scratch';

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

function CopySiteRepo(const pName: string): string;
begin
  ForceDirectories(SCRATCH);
  Result := TPath.Combine(SCRATCH, pName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  TDirectory.Copy(SiteDir, Result);
end;

procedure AppendText(const pFile, pText: string);
begin
  TFile.WriteAllText(pFile, TFile.ReadAllText(pFile, TEncoding.ASCII) + pText, TEncoding.ASCII);
end;

{ Builds pRepo as a site into pOut; returns '' or the EFeatureGen message. }
function TryBuild(const pRepo, pOut: string): string;
var
  lFmt: TSiteFormat;
  lW: TOutputWriter;
begin
  Result := '';
  if TDirectory.Exists(pOut) then
    TDirectory.Delete(pOut, True);
  lFmt := LoadSiteFormat(pRepo);
  lW := TOutputWriter.Create(pOut, False, True);
  try
    try
      BuildSite(pRepo, lFmt, lW);
      lW.Finish;
    except
      on E: EFeatureGen do
        Result := E.Message;
    end;
  finally
    lW.Free;
  end;
end;

procedure TestGeneratedWikiPage;
var
  lRepo, lOut, lMsg, lLeaf, lAsk: string;
begin
  lRepo := CopySiteRepo('gen-repo');
  TFile.WriteAllText(TPath.Combine(lRepo, 'features\entries\gen-page.json'),
    '{ "id": "gen-page", "title": "Gen page", "group": "g-search", "owner": "ENGINE", "status": "shipped", "since": "0.9.0-alpha",'
    + ' "summary": "Lives on a generated page", "wikiPage": "Features", "surfaces": [ { "type": "cli", "verb": "genverb" } ], "audience": "both" }', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lRepo, 'docs\wiki\Features.md'), '# Features'#13#10#13#10'Use <file> here.'#13#10, TEncoding.ASCII);
  AppendText(TPath.Combine(lRepo, 'docs\wiki\Ask.md'), #13#10'See [[Features]] now.'#13#10);
  lOut := TPath.Combine(SCRATCH, 'gen-out');
  lMsg := TryBuild(lRepo, lOut);
  Check('Site.GeneratedWikiPageBuilds', lMsg = '', lMsg);
  if lMsg = '' then
  begin
    lLeaf := ReadSiteFile(lOut, 'features/gen-page.md');
    lAsk := ReadSiteFile(lOut, 'features/ask.md');
    Check('Site.GeneratedWikiPageLeafNoDetailsNoMapRow',
      (Pos('title: Gen page', lLeaf) > 0) and (Pos('## Details', lLeaf) = 0) and (Pos('Use ', lLeaf) = 0)
      and (Pos('"Features"', ReadSiteFile(lOut, 'wiki-map.json')) = 0) and (Pos('See Features now.', lAsk) > 0) and (Pos('gen-page.md', lAsk) = 0), lLeaf);
  end;
end;

procedure TestEntryTextGuard;
var
  lRepo, lPath, lMsg, lTxt: string;
begin
  lRepo := CopySiteRepo('entrytext-repo');
  lPath := TPath.Combine(lRepo, 'features\entries\ask.json');
  lTxt := TFile.ReadAllText(lPath, TEncoding.ASCII);
  TFile.WriteAllText(lPath, lTxt.Replace('"summary": "Asks a question"', '"summary": "Asks a question", "intro": "Run drag-lint ask <question> now and `<ok>` too."'), TEncoding.ASCII);
  lMsg := TryBuild(lRepo, TPath.Combine(SCRATCH, 'entrytext-out'));
  Check('Site.EntryIntroRawHtmlFailsNamingEntryAndField', (Pos('ask', lMsg) > 0) and (Pos('intro', lMsg) > 0) and (Pos('<question>', lMsg) > 0)
    and (Pos('<ok>', lMsg) = 0), lMsg);
  lRepo := CopySiteRepo('entrytext2-repo');
  lPath := TPath.Combine(lRepo, 'features\entries\ask.json');
  lTxt := TFile.ReadAllText(lPath, TEncoding.ASCII);
  TFile.WriteAllText(lPath, lTxt.Replace('"summary": "Asks a question"', '"summary": "Asks a question", "intro": "Run drag-lint ask `<question>` now."'), TEncoding.ASCII);
  lMsg := TryBuild(lRepo, TPath.Combine(SCRATCH, 'entrytext2-out'));
  Check('Site.EntryIntroPlaceholderInCodeBuilds', lMsg = '', lMsg);
end;

procedure TestOutDirRefusal;
var
  lDir, lMsg: string;
  lHelp: TLiveHelp;
begin
  lDir := FreshDir('refuse-out');
  TFile.WriteAllText(TPath.Combine(lDir, 'keep.txt'), 'precious', TEncoding.ASCII);
  lHelp := TLiveHelp.Create;
  try
    lMsg := '';
    try
      BuildFixture(SiteDir, lDir, False, lHelp);
    except
      on E: EFeatureGen do
        lMsg := E.Message;
    end;
  finally
    lHelp.Free;
  end;
  Check('Site.NonEmptyDirWithoutIndexJsonRefused', (Pos(lDir, lMsg) > 0) and (Pos('index.json', lMsg) > 0)
    and TFile.Exists(TPath.Combine(lDir, 'keep.txt')) and not TFile.Exists(TPath.Combine(lDir, 'index.md')), lMsg);
end;

procedure TestRemoteImages;
var
  lRepo, lOut, lMsg, lAsk: string;
begin
  lRepo := CopySiteRepo('img-repo');
  ForceDirectories(TPath.Combine(lRepo, 'docs\Images\charts'));
  TFile.WriteAllText(TPath.Combine(lRepo, 'docs\Images\charts\c1.png'), 'PNGDATA', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lRepo, 'docs\Images\charts\c1.svg'), 'SVGDATA', TEncoding.ASCII);
  AppendText(TPath.Combine(lRepo, 'docs\wiki\Ask.md'), #13#10'![chart](https://raw.githubusercontent.com/o/r/main/docs/Images/charts/c1.png)'#13#10
    + '[SVG](https://raw.githubusercontent.com/o/r/main/docs/Images/charts/c1.svg) [gh](https://github.com/o/r/issues/1) [rel](../Images/charts/c1.svg)'#13#10);
  lOut := TPath.Combine(SCRATCH, 'img-out');
  lMsg := TryBuild(lRepo, lOut);
  Check('Site.RemoteImageBuilds', lMsg = '', lMsg);
  if lMsg = '' then
  begin
    lAsk := ReadSiteFile(lOut, 'features/ask.md');
    Check('Site.RemoteChartImageCopiedAndRenamed',
      (Pos('![chart](img/ask-1.png)', lAsk) > 0) and (Pos('[SVG](img/ask-2.svg)', lAsk) > 0) and (Pos('[rel](img/ask-3.svg)', lAsk) > 0)
      and (ReadSiteFile(lOut, 'features/img/ask-1.png') = 'PNGDATA') and (ReadSiteFile(lOut, 'features/img/ask-2.svg') = 'SVGDATA')
      and (Pos('githubusercontent', lAsk) = 0), lAsk);
    Check('Site.GithubLinkBecomesPlainText', (Pos(' gh ', lAsk) > 0) and (Pos('github.com', lAsk) = 0), lAsk);
  end;
  lRepo := CopySiteRepo('img-missing-repo');
  AppendText(TPath.Combine(lRepo, 'docs\wiki\Ask.md'), #13#10'![x](https://raw.githubusercontent.com/o/r/main/docs/Images/charts/nope.png)'#13#10);
  lMsg := TryBuild(lRepo, TPath.Combine(SCRATCH, 'img-missing-out'));
  Check('Site.MissingImageFileFailsNamingPageAndLink', (Pos('"ask"', lMsg) > 0) and (Pos('nope.png', lMsg) > 0), lMsg);
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

{ ---- Task 5: schema v2 fields ---- }

const
  V2_HELP = '  drag-lint v2verb go --name WRONG-FROM-HELP'#10;

procedure TestModelV2;
var
  lReg: TRegistry;
  lE, lO: TFeatureEntry;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(MiniDir);
    lE := EntryById(lReg, 'v2-sample');
    lO := EntryById(lReg, 'outline');
    Check('Model.ReadsV2Fields',
      (Length(lE.Surfaces) = 2) and (lE.Surfaces[0].Usage = 'drag-lint v2verb go --name <N> [--db <db>]')
      and (Length(lE.Surfaces[0].Flags) = 2) and (lE.Surfaces[0].Flags[0].Name = '--name') and (lE.Surfaces[0].Flags[0].Arg = '<N>')
      and (lE.Surfaces[0].Flags[0].Summary = 'The bare member name') and (lE.Surfaces[0].Flags[0].DefaultValue = 'none')
      and (lE.Surfaces[0].Flags[1].DefaultValue = '<db>')
      and (Length(lE.Surfaces[1].Steps) = 2) and (lE.Surfaces[1].Steps[1] = 'Click V2 sample')
      and (Length(lE.Pitfalls) = 2) and (lE.Pitfalls[1] = 'Reindex after an edit')
      and (Length(lE.Questions) = 1) and (lE.Questions[0].Ask = 'Who calls Bar?') and (lE.Questions[0].Command = 'drag-lint v2verb go --name Bar')
      and (lE.HelpContext = 'v2-help-id') and (lO.HelpContext = 'outline')
      and (lE.VerifiedDate = '2026-10-19') and (lE.VerifiedBy = 'ENGINE') and (lE.VerifiedBuild = '1.32.0') and (lE.VerifiedSurfaceHash = 'abc123')
      and (Length(lO.Surfaces[0].Flags) = 0) and (lO.Surfaces[0].Usage = '') and (Length(lO.Pitfalls) = 0) and (lO.VerifiedBuild = ''),
      lE.HelpContext + '|' + lE.Surfaces[0].Usage);
  finally
    lReg.Free;
  end;
end;

procedure TestJsonV2;
var
  lFile, lText, lScrambled, lBack: string;
  lOrder: TArray<string>;
  lVal: TJSONValue;
begin
  lOrder := EntryKeyOrder(TPath.Combine(MiniDir, 'features\schema\entry.schema.json'));
  lFile := TPath.Combine(MiniDir, 'features\entries\v2-sample.json');
  lText := ReadAllBytesAsText(lFile);
  lVal := ReadJsonFile(lFile);
  try
    lBack := CanonicalJson(lVal, lOrder);
  finally
    lVal.Free;
  end;
  Check('Json.V2KeyOrderCanonical', lBack = lText, Copy(lBack, 1, 200));
  // the same entry with the v2 keys written in a wrong order: must come back byte-identical
  lScrambled := '{"verified": {"surfaceHash": "abc123", "build": "1.32.0", "by": "ENGINE", "date": "2026-10-19"}, "pitfalls": ["Pass the BARE member name; TFoo.Bar returns 0", "Reindex after an edit"], '
    + '"questions": [{"command": "drag-lint v2verb go --name Bar", "ask": "Who calls Bar?"}], "audience": "both", "surfaces": ['
    + '{"flags": [{"default": "none", "summary": "The bare member name", "arg": "<N>", "name": "--name"}, {"default": "<db>", "summary": "Index to read; a|b", "arg": "<db>", "name": "--db"}], '
    + '"usage": "drag-lint v2verb go --name <N> [--db <db>]", "example": "drag-lint v2verb go --name X", "sub": "go", "verb": "v2verb", "type": "cli"}, '
    + '{"steps": ["Open the Search menu", "Click V2 sample"], "path": "drag-lint > Search > V2 sample", "type": "ide-menu"}], '
    + '"helpContext": "v2-help-id", "summary": "Exercises every schema v2 field for the featuregen tests", "since": "0.86.0-alpha", "status": "shipped", "owner": "ENGINE", '
    + '"group": "search-navigation", "title": "Schema v2 sample", "id": "v2-sample"}';
  lVal := TJSONObject.ParseJSONValue(lScrambled, True, False);
  try
    lBack := CanonicalJson(lVal, lOrder);
  finally
    lVal.Free;
  end;
  Check('Json.V2FixedOrdersFromScrambled', lBack = lText, Copy(lBack, 1, 200));
end;

procedure TestEmptyArraysV2;
var
  lVal: TJSONValue;
  lBack: string;
begin
  lVal := TJSONObject.ParseJSONValue('{"id": "x-empty", "surfaces": [{"type": "cli", "verb": "x", "flags": []}, {"type": "ide-menu", "path": "drag-lint > X", "steps": []}], "pitfalls": []}', True, False);
  try
    lBack := CanonicalJson(lVal, TArray<string>.Create('id', 'surfaces', 'pitfalls'));
  finally
    lVal.Free;
  end;
  Check('Json.V2EmptySurfaceArraysKeptEntryEmptyDropped',
    (Pos('"flags": []', lBack) > 0) and (Pos('"steps": []', lBack) > 0) and (Pos('pitfalls', lBack) = 0), lBack);
end;

procedure TestLeafV2;
var
  lReg: TRegistry;
  lHelp: TLiveHelp;
  lFmt: TSiteFormat;
  lImg: TArray<TImageRef>;
  lOut: string;
  lE: TFeatureEntry;
begin
  lReg := TRegistry.Create;
  lHelp := TLiveHelp.Create;
  try
    lReg.Load(MiniDir);
    lHelp.LoadFromText(V2_HELP);
    lFmt := MiniFormat(lHelp);
    lE := EntryById(lReg, 'v2-sample');
    lOut := RenderLeaf(lE, lFmt, lReg, MiniDir, lImg);
    Check('Leaf.UsageFieldWinsOverHelp',
      (Pos('```text'#10'drag-lint v2verb go --name <N> [--db <db>]'#10'```', lOut) > 0) and (Pos('WRONG-FROM-HELP', lOut) = 0), lOut);
    Check('Leaf.FlagsTable',
      Pos('## Flags'#10#10'| Flag | Argument | Meaning | Default |'#10'| --- | --- | --- | --- |'#10
        + '| `--name` | `<N>` | The bare member name | `none` |'#10'| `--db` | `<db>` | Index to read; a\|b | `<db>` |'#10, lOut) > 0, lOut);
    Check('Leaf.PitfallsBullets',
      Pos('## Pitfalls'#10#10'* Pass the BARE member name; TFoo.Bar returns 0'#10'* Reindex after an edit'#10, lOut) > 0, lOut);
    Check('Leaf.StepsNumberedUnderSurface',
      Pos('* RAD Studio main menu: **drag-lint > Search > V2 sample**'#10'   1. Open the Search menu'#10'   2. Click V2 sample'#10, lOut) > 0, lOut);
    lE := EntryById(lReg, 'outline');
    lHelp.LoadFromText(HELP_SNIPPET);
    lOut := RenderLeaf(lE, lFmt, lReg, MiniDir, lImg);
    Check('Leaf.NoV2SectionsWhenAbsent', (Pos('## Flags', lOut) = 0) and (Pos('## Pitfalls', lOut) = 0), lOut);
  finally
    lHelp.Free;
    lReg.Free;
  end;
end;

procedure TestCliV2;
var
  lRepo, lOut, lCli: string;
  lHelp: TLiveHelp;
begin
  lRepo := CopySiteRepo('v2cli-repo');
  TFile.WriteAllText(TPath.Combine(lRepo, 'features\entries\v2cli.json'),
    '{ "id": "v2cli", "title": "V2 cli", "group": "g-search", "owner": "ENGINE", "status": "shipped", "since": "0.50.0-alpha", '
    + '"summary": "A verb with schema v2 flags", "audience": "both", "surfaces": [ { "type": "cli", "verb": "v2cli", '
    + '"usage": "drag-lint v2cli --x <n>", "flags": [ { "name": "--x", "arg": "<n>", "summary": "The x", "default": "1" }, { "name": "--db", "summary": "Db", "default": "<db>" }, { "name": "--t", "summary": "Tick", "default": "a`b" }, { "name": "--e", "summary": "Empty" } ] } ] }', TEncoding.ASCII);
  lHelp := TLiveHelp.Create;
  try
    lHelp.LoadFromText(SITE_HELP);
    lOut := FreshDir('v2cli-out');
    BuildFixture(lRepo, lOut, False, lHelp);
    lCli := ReadSiteFile(lOut, 'cli.md');
    Check('Cli.FlagsTable',
      (Pos('### v2cli'#10, lCli) > 0) and (Pos('```text'#10'drag-lint v2cli --x <n>'#10'```'#10#10'| Flag | Argument | Meaning | Default |'#10
        + '| --- | --- | --- | --- |'#10'| `--x` | `<n>` | The x | `1` |'#10'| `--db` |  | Db | `<db>` |'#10'| `--t` |  | Tick | `` a`b `` |'#10'| `--e` |  | Empty |  |'#10, lCli) > 0), lCli);
  finally
    lHelp.Free;
  end;
end;

function ImportRun(const pEntryJson: string; out pU: Boolean; out pF, pP: Integer): TJSONObject;
var
  lHelp: TLiveHelp;
begin
  Result := TJSONObject.ParseJSONValue(pEntryJson) as TJSONObject;
  lHelp := TLiveHelp.Create;
  try
    lHelp.LoadFromText(TFile.ReadAllText(TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\help-1.32.0.txt'), TEncoding.ASCII));
    ImportEntry(Result, lHelp, pU, pF, pP);
  finally
    lHelp.Free;
  end;
end;

function ImportFlagNames(pEntry: TJSONObject): string;
var
  lFlags: TJSONArray;
  lI: Integer;
begin
  Result := '';
  lFlags := ((pEntry.GetValue('surfaces') as TJSONArray).Items[0] as TJSONObject).GetValue('flags') as TJSONArray;
  if lFlags = nil then
    Exit;
  for lI := 0 to lFlags.Count - 1 do
    Result := Result + (lFlags.Items[lI] as TJSONObject).GetValue<string>('name') + ' ';
end;

procedure TestImport;
const
  CALLERS = '{ "id": "x", "surfaces": [ { "type": "cli", "verb": "query", "sub": "find-callers" } ] }';
var
  lE: TJSONObject;
  lU: Boolean;
  lF, lP: Integer;
  lSurf: TJSONObject;
  lPit: TJSONArray;
begin
  lE := ImportRun(CALLERS, lU, lF, lP);
  try
    lSurf := (lE.GetValue('surfaces') as TJSONArray).Items[0] as TJSONObject;
    Check('Import.ParsesFlagsBlock',
      lU and (Pos('drag-lint query find-callers --name', lSurf.GetValue<string>('usage')) = 1)
      and (ImportFlagNames(lE) = '--name --context --resolved --db --json '), ImportFlagNames(lE));
    Check('Import.FlagSummaryFromBlock',
      Pos('precise callers via resolved call_edges', lSurf.ToJSON) > 0, lSurf.ToJSON);
    lPit := lE.GetValue('pitfalls') as TJSONArray;
    Check('Import.PitfallFromCaret', (lPit <> nil) and (lP > 0) and (Pos('BARE member name', lPit.Items[0].Value) > 0),
      lE.ToJSON);
    Check('Import.NeverWritesVerified', lE.GetValue('verified') = nil);
  finally
    lE.Free;
  end;
  lE := ImportRun('{ "id": "x", "verified": { "date": "d", "by": "b", "build": "1", "surfaceHash": "h" }, '
    + '"surfaces": [ { "type": "cli", "verb": "query", "sub": "find-callers" } ] }', lU, lF, lP);
  try
    Check('Import.KeepsExistingVerified',
      lE.GetValue('verified').ToJSON = '{"date":"d","by":"b","build":"1","surfaceHash":"h"}', lE.GetValue('verified').ToJSON);
  finally
    lE.Free;
  end;
  lE := ImportRun('{ "id": "x", "pitfalls": [ "mine" ], "surfaces": [ { "type": "cli", "verb": "query", "sub": "find-callers", '
    + '"usage": "keep me" } ] }', lU, lF, lP);
  try
    lSurf := (lE.GetValue('surfaces') as TJSONArray).Items[0] as TJSONObject;
    Check('Import.FillsOnlyMissing',
      (lSurf.GetValue<string>('usage') = 'keep me') and not lU and (lF = 5) and (lP = 0)
      and ((lE.GetValue('pitfalls') as TJSONArray).Count = 1) and (ImportFlagNames(lE) = '--name --context --resolved --db --json '),
      lE.ToJSON);
  finally
    lE.Free;
  end;
  lE := ImportRun('{ "id": "x", "surfaces": [ { "type": "cli", "verb": "query", "sub": "find-callers", "flags": [ { "name": "--z" } ] } ] }',
    lU, lF, lP);
  try
    Check('Import.KeepsExistingFlags', lU and (lF = 0) and (ImportFlagNames(lE) = '--z '), ImportFlagNames(lE));
  finally
    lE.Free;
  end;
  lE := ImportRun('{ "id": "x", "surfaces": [ { "type": "cli", "verb": "no-such-verb" }, { "type": "ide-menu", "path": "a" } ] }',
    lU, lF, lP);
  try
    Check('Import.UnknownVerbUntouched', not lU and (lF = 0) and (lP = 0) and (lE.GetValue('pitfalls') = nil));
  finally
    lE.Free;
  end;
  lE := ImportRun('{ "id": "x", "surfaces": [ { "type": "cli", "verb": "query", "sub": "find" } ] }', lU, lF, lP);
  try
    Check('Import.PlaceholdersBackticked',
      Pos('`<k>`', lE.ToJSON) > 0, lE.ToJSON);
  finally
    lE.Free;
  end;
end;

procedure TestEntryTextGuardV2;
var
  lRepo, lMsg, lPath, lTxt: string;
  lCases: array[0..3] of TArray<string>;
  i: Integer;
begin
  lCases[0] := TArray<string>.Create('"pitfalls": ["Run <ask> now"]', 'pitfalls', 'raw HTML');
  lCases[1] := TArray<string>.Create('"questions": [ { "ask": "What <is> it?", "command": "x" } ]', 'questions', 'raw HTML');
  lCases[2] := TArray<string>.Create('"surfaces": [ { "type": "cli", "verb": "ask", "usage": "drag-lint ask \u00e9" } ]', 'usage', 'non-ASCII');
  lCases[3] := TArray<string>.Create('"surfaces": [ { "type": "cli", "verb": "ask", "flags": [ { "name": "--a", "summary": "Takes <b> raw" } ] } ]', 'flags', 'raw HTML');
  for i := 0 to High(lCases) do
  begin
    lRepo := CopySiteRepo('v2guard-repo' + IntToStr(i));
    lPath := TPath.Combine(lRepo, 'features\entries\ask.json');
    lTxt := TFile.ReadAllText(lPath, TEncoding.ASCII);
    if i < 2 then
      lTxt := lTxt.Replace('"audience": "both"', '"audience": "both", ' + lCases[i][0])
    else
      lTxt := lTxt.Replace('"surfaces": [ { "type": "cli", "verb": "ask" } ]', lCases[i][0]);
    TFile.WriteAllText(lPath, lTxt, TEncoding.ASCII);
    lMsg := TryBuild(lRepo, TPath.Combine(SCRATCH, 'v2guard-out' + IntToStr(i)));
    Check('Site.EntryTextGuardV2.' + lCases[i][1], (Pos('ask', lMsg) > 0) and (Pos(lCases[i][1], lMsg) > 0) and (Pos(lCases[i][2], lMsg) > 0), lMsg);
  end;
end;

{ ---- Task 7: wiki parity. The comparison (CompareOutputTrees) is separate from how
  the reference tree was produced (ProducePowerShellReference), so the reference can
  later become frozen golden files without touching the comparison. ---- }

const
  MAIN_ENGINE = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe';

function PwshExe: string;
begin
  Result := 'C:\Program Files\PowerShell\7\pwsh.exe';
  if not TFile.Exists(Result) then
    Result := FileSearch('pwsh.exe', GetEnvironmentVariable('PATH'));
end;

{ Reference producer: the PowerShell generator with its engine set to pEngine, into pOut. }
function ProducePowerShellReference(const pRepo, pEngine, pOut: string): string;
var
  lScript: string;
begin
  lScript := TPath.Combine(SCRATCH, 'run-ps-generator.ps1');
  TFile.WriteAllText(lScript,
    'param([string]$Repo, [string]$Engine, [string]$OutDir)'#13#10
    + '$ErrorActionPreference = ''Stop'''#13#10
    + 'Import-Module (Join-Path $Repo ''tools\FeatureRegistry.psm1'') -Force'#13#10
    + '$paths = Get-RegistryPaths -Repo $Repo'#13#10
    + '$paths.Exe = $Engine'#13#10
    + '$res = Invoke-RegistryGenerate -Paths $paths -OutDir $OutDir'#13#10
    + '"ps-generator: wrote $($res.Written.Count) of $($res.Outputs.Count)"'#13#10, TEncoding.ASCII);
  Result := RunCapture(PwshExe, '-NoProfile -ExecutionPolicy Bypass -File "' + lScript + '" -Repo "' + pRepo
    + '" -Engine "' + pEngine + '" -OutDir "' + pOut + '"');
end;

function ShowLine(const pLine: string): string;
begin
  Result := pLine.Replace(#13, '\r');
end;

{ First differing line of two texts, CR shown as \r. }
function FirstDifference(const pExpected, pActual: string): string;
var
  lA, lB: TArray<string>;
  i, lN: Integer;
begin
  lA := pExpected.Split([#10]);
  lB := pActual.Split([#10]);
  lN := Length(lA);
  if Length(lB) < lN then
    lN := Length(lB);
  for i := 0 to lN - 1 do
    if lA[i] <> lB[i] then
      Exit(Format('first difference at line %d: expected "%s" got "%s"', [i + 1, ShowLine(lA[i]), ShowLine(lB[i])]));
  Result := Format('expected %d lines (%d chars), got %d lines (%d chars)', [Length(lA), Length(pExpected), Length(lB), Length(pActual)]);
end;

{ Byte comparison of pFiles under two roots; one message per mismatching file. }
function CompareOutputTrees(const pExpectedRoot, pActualRoot: string; const pFiles: TArray<string>): TArray<string>;
var
  lRel, lA, lB: string;
  lList: TList<string>;
begin
  lList := TList<string>.Create;
  try
    for lRel in pFiles do
    begin
      lA := TPath.Combine(pExpectedRoot, lRel);
      lB := TPath.Combine(pActualRoot, lRel);
      if not TFile.Exists(lA) then
        lList.Add(lRel + ': reference missing')
      else if not TFile.Exists(lB) then
        lList.Add(lRel + ': not produced')
      else if ReadBytesText(lA) <> ReadBytesText(lB) then
        lList.Add(lRel + ': ' + FirstDifference(ReadBytesText(lA), ReadBytesText(lB)));
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

{ Every relative markdown link in pText whose target (anchor cut) is not an existing
  file under pBaseDir; https / http / # / mailto links are not checked. Also returns
  the number of relative links checked in pChecked. }
function DeadRelativeLinks(const pText, pBaseDir: string; out pChecked: Integer): TArray<string>;
var
  lM: TMatch;
  lTarget, lPath: string;
  lList: TList<string>;
begin
  pChecked := 0;
  lList := TList<string>.Create;
  try
    for lM in TRegEx.Matches(pText, '(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)') do
    begin
      lTarget := lM.Groups[2].Value;
      if lTarget.StartsWith('https://') or lTarget.StartsWith('http://') or lTarget.StartsWith('#') or lTarget.StartsWith('mailto:') then
        Continue;
      Inc(pChecked);
      lPath := lTarget;
      if Pos('#', lPath) > 0 then
        lPath := Copy(lPath, 1, Pos('#', lPath) - 1);
      if not TFile.Exists(TPath.GetFullPath(TPath.Combine(pBaseDir, lPath.Replace('/', '\')))) then
        lList.Add(lTarget);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

procedure TestDeadLinkPositiveControl(const pRepo: string);
var
  lDead: TArray<string>;
  lChecked: Integer;
begin
  lDead := DeadRelativeLinks('[a](../../docs/wiki/Home.md) [b](../../docs/wiki/No-Such-Page-xyz.md#x) [c](https://x.org/a) [d](#top)',
    TPath.Combine(pRepo, 'features\generated'), lChecked);
  Check('Wiki.DeadLinkCheckCatchesDeadLink', (lChecked = 2) and (Length(lDead) = 1) and (lDead[0] = '../../docs/wiki/No-Such-Page-xyz.md#x'),
    IntToStr(lChecked) + ' ' + string.Join(' | ', lDead));
end;

procedure TestReadAsciiStrict;
var
  lDir, lFile, lMsg: string;
begin
  lDir := FreshDir('ascii-strict');
  lFile := TPath.Combine(lDir, 'README.md');
  TFile.WriteAllBytes(lFile, TBytes.Create(Ord('a'), Ord('b'), $C3, $A9, 13, 10));
  lMsg := '';
  try
    ReadAsciiStrict(lFile);
  except
    on E: Exception do
      lMsg := E.Message;
  end;
  Check('Wiki.ReadAsciiStrictRaisesOnHighByte', (Pos(lFile, lMsg) > 0) and (Pos('offset 2', lMsg) > 0), lMsg);
  TFile.WriteAllText(lFile, 'plain'#13#10, TEncoding.ASCII);
  Check('Wiki.ReadAsciiStrictReadsAscii', ReadAsciiStrict(lFile) = 'plain'#13#10);
end;

procedure TestWikiParity(const pRepo: string);
var
  lA, lB, lPs, lCli, lMsg: string;
  lW: TOutputWriter;
  lBad, lDead: TArray<string>;
  lChecked: Integer;
begin
  if not TFile.Exists(MAIN_ENGINE) then
  begin
    Check('Parity.WikiOutputsEqualPowerShell', False, 'engine missing: ' + MAIN_ENGINE);
    Exit;
  end;
  lA := FreshDir('wiki-parity-ps');
  lB := FreshDir('wiki-parity-fg');
  lPs := ProducePowerShellReference(pRepo, MAIN_ENGINE, lA);
  lMsg := '';
  try
    lW := TOutputWriter.Create(lB, False, False);
    try
      BuildWiki(pRepo, lW, MAIN_ENGINE);
      lW.Finish;
    finally
      lW.Free;
    end;
  except
    on E: Exception do
      lMsg := E.ClassName + ': ' + E.Message;
  end;
  lBad := CompareOutputTrees(lA, lB, WikiOutputPaths);
  Check('Parity.WikiOutputsEqualPowerShell', (lMsg = '') and (Length(lBad) = 0) and (Pos('wrote 7 of 7', lPs) > 0),
    lMsg + ' [' + lPs.Trim + '] ' + string.Join(' | ', lBad));
  lCli := TPath.Combine(lB, 'features\generated\cli-reference.md');
  Check('Wiki.CliReferenceIsCliMdWithoutFrontMatter', TFile.Exists(lCli) and ReadBytesText(lCli).StartsWith('# CLI reference'#13#10#13#10)
    and (Pos('## Commands', ReadBytesText(lCli)) > 0), lCli);
  if TFile.Exists(lCli) then
  begin
    lDead := DeadRelativeLinks(ReadBytesText(lCli), TPath.Combine(pRepo, 'features\generated'), lChecked);
    Check('Wiki.CliReferenceLinksResolveInRepo', (lChecked > 100) and (Length(lDead) = 0),
      IntToStr(lChecked) + ' checked; dead: ' + string.Join(' | ', Copy(lDead, 0, 5)));
  end;
end;

procedure TestCompareOutputTreesPositiveControl;
var
  lA, lB: string;
  lBad: TArray<string>;
begin
  lA := FreshDir('cmp-a');
  lB := FreshDir('cmp-b');
  TFile.WriteAllText(TPath.Combine(lA, 'x.md'), 'one'#13#10'two'#13#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lB, 'x.md'), 'one'#13#10'twO'#13#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lA, 'y.md'), 'same', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lB, 'y.md'), 'same', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lA, 'z.md'), 'only in reference', TEncoding.ASCII);
  lBad := CompareOutputTrees(lA, lB, ['x.md', 'y.md', 'z.md']);
  Check('Parity.CompareOutputTreesCatchesDifferences', (Length(lBad) = 2) and (Pos('x.md: first difference at line 2', lBad[0]) > 0)
    and (lBad[1] = 'z.md: not produced'), string.Join(' | ', lBad));
end;

procedure TestMarkedBlock;
var
  lMsg: string;
begin
  Check('Wiki.MarkedBlockReplacesBody',
    UpdateMarkedBlock('a<!-- dl:registry:begin x -->'#13#10'old'#13#10'<!-- dl:registry:end x -->b', 'x', 'new'#13#10)
      = 'a<!-- dl:registry:begin x -->'#13#10'new'#13#10'<!-- dl:registry:end x -->b');
  lMsg := '';
  try
    UpdateMarkedBlock('<!-- dl:registry:end x --> <!-- dl:registry:begin x -->', 'x', 'new');
  except
    on E: Exception do
      lMsg := E.Message;
  end;
  Check('Wiki.MarkedBlockOutOfOrderRaises', Pos('markers absent', lMsg) > 0, lMsg);
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
    TestModelV2;
    TestJsonV2;
    TestEmptyArraysV2;
    TestLeafV2;
    TestCliV2;
    TestImport;
    TestEntryTextGuardV2;
    TestUndocumentedVerbs;
    TestSite;
    TestSiteDanglingLink;
    TestGeneratedWikiPage;
    TestRemoteImages;
    TestEntryTextGuard;
    TestOutDirRefusal;
    TestCheckLinks;
    TestMarkedBlock;
    TestCompareOutputTreesPositiveControl;
    if lRepo <> '' then
      TestSiteFormatFile(lRepo);
    TestReadAsciiStrict;
    if lRepo <> '' then
      TestDeadLinkPositiveControl(lRepo);
    if lRepo <> '' then
      TestWikiParity(lRepo);
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
