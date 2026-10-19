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
        + 'product: DL'#10'group: search-navigation'#10'order: 30'#10'since: 0.86.0-alpha'#10'status: shipped'#10'updated: 0.86.0-alpha'#10
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
