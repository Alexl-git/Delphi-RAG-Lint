program FeatureGenTests;  // dl:ok unit-too-large@5ff0 -- REVIEWED 2026-10-19: the ported checks A-E live together because they share one context and one finding list; splitting is a later refactor

{ Self-contained console test runner for featuregen (no DUnitX). One PASS/FAIL
  line per case, a summary line, exit code 1 on any failure. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.IOUtils
  , System.Classes
  , System.JSON
  , Winapi.Windows
  , FeatureGen.Json in '..\FeatureGen.Json.pas'
  , FeatureGen.Model in '..\FeatureGen.Model.pas'
  , FeatureGen.Output in '..\FeatureGen.Output.pas'
  , FeatureGen.Live in '..\FeatureGen.Live.pas'
  , FeatureGen.SiteFormat in '..\FeatureGen.SiteFormat.pas'
  , FeatureGen.Markdown in '..\FeatureGen.Markdown.pas'
  , FeatureGen.Site in '..\FeatureGen.Site.pas'
  , FeatureGen.HelpImport in '..\FeatureGen.HelpImport.pas'
  , FeatureGen.HelpText in '..\FeatureGen.HelpText.pas'
  , FeatureGen.Wiki in '..\FeatureGen.Wiki.pas'
  , FeatureGen.DocsCheck in '..\FeatureGen.DocsCheck.pas'
  , FeatureGen.Check in '..\FeatureGen.Check.pas'  // dl:ok uses-global-census@b1db -- REVIEWED 2026-10-19: the test program names the checker constants it asserts on
  , FeatureGen.Audit in '..\FeatureGen.Audit.pas'
  , FeatureGen.Commands in '..\FeatureGen.Commands.pas'
  , System.Generics.Collections
  , System.Generics.Defaults
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
    Check('Model.LoadMini.count', Length(lE) = 4, IntToStr(Length(lE)));  // dl:ok magic-literal@84a8 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    if Length(lE) = 4 then  // dl:ok magic-literal@e223 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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

var
  { One folder per RUN (temp path + process id), created and removed by the main block, so two
    concurrent runs on this machine never delete each other's golden repo or running stub exe. }
  SCRATCH: string = '';

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
  lOld := EncodeDate(2001, 2, 3);  // dl:ok magic-literal@a68f -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
    DateTimeToStr(lNew));  // dl:ok locale-sensitive-conversion@d277 -- REVIEWED 2026-10-19: diagnostic text of a test failure only
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
      lW.Put('x.txt', 'ok'#10'bad ' + Char($00E9), 'entry foo field intro');  // dl:ok magic-literal@92a8 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
    (ReadBytesText(TPath.Combine(lDir, 'old.txt')) = 'a'#13#10'b'#13#10) and not TFile.Exists(TPath.Combine(lDir, 'new.txt'))  // dl:ok boolean-expression-complexity@267c -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
    and TFile.Exists(TPath.Combine(lDir, 'stale.txt')) and (Length(lR.Written) = 0) and (Length(lR.Removed) = 0)
    and (Length(lR.Changed) = 3), IntToStr(Length(lR.Changed)));  // dl:ok magic-literal@ac69 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
      lW.Put('C:\TEMP\claude\featuregen-task2\x.txt', 'x', 'ctx');  // dl:ok hardcoded-absolute-path@bd61 -- REVIEWED 2026-10-19: test harness: names the main-tree engine and a scratch folder under C:\TEMP\claude on purpose
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
  TFile.WriteAllBytes(lSrc, TBytes.Create(0, 200, 13, 10, 255));  // dl:ok large-magic-number@b123, magic-literal@b123 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
  lW := TOutputWriter.Create(TPath.Combine(lDir, 'out'), False, False);
  try
    lW.PutBinary('i\p.bin', lSrc);
    lW.Finish;
  finally
    lW.Free;
  end;
  Check('Output.PutBinary', TFile.ReadAllBytes(TPath.Combine(lDir, 'out\i\p.bin'))[1] = 200);  // dl:ok large-magic-number@0693, magic-literal@0693 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
    lMsg := RaisedMessage('one'#10'caf' + Char($00E9), lMap);  // dl:ok magic-literal@7a56 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
      Copy(lOut, 1, 400));  // dl:ok large-magic-number@26f3, magic-literal@26f3 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
      (Pos('title: "Add: units"', lOut) > 0) and (Pos('## Details', lOut) = 0) and (Pos('## Where to click', lOut) > 0)  // dl:ok boolean-expression-complexity@49fb -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
      and (Pos('* RAD Studio main menu: **drag-lint > Uses & Dependencies > Add Missing Units to uses (whole unit)...**', lOut) > 0)
      and (Pos('[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)', lOut) > 0)
      and (Pos('## How to run it', lOut) > 0) and (Pos('drag-lint check-unit', lOut) > 0), lOut);
    lE := EntryById(lReg, 'outline');
    lOut := RenderLeaf(lE, lFmt, lReg, MiniDir, lImg);
    lP := Pos('## Details', lOut);
    lHow := Copy(lOut, 1, lP);
    Check('Leaf.NoDuplicateUsageWhenWikiHasCliSection',
      (lP > 0) and (Pos('## How to run it', lHow) > 0) and (Pos('../cli.md#outline', lHow) > 0) and (Pos('--file', lHow) = 0)  // dl:ok boolean-expression-complexity@d745 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
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
  Check('SiteFormat.Load', (lFmt.Root = 'WWW\help\dl') and (lFmt.Product = 'DL') and (Length(lFmt.FrontMatterKeys) = 9)  // dl:ok boolean-expression-complexity@1cd4, magic-literal@1cd4 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare; test expectation: the literal is the asserted value
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

procedure TestSite;  // dl:ok too-many-locals@c367, cyclomatic-complexity@c5b1 -- REVIEWED 2026-10-19: one routine per ported check or command, kept 1:1 with the PowerShell original; one routine per ported check or command, kept 1:1 with the PowerShell original so the golden parity tests compare like with like
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
    Check('Site.IndexLinksEveryIncludedLeafOnce', (lBad = 0) and (Occurrences(lIndex, '](features/') = 5), lIndex);  // dl:ok magic-literal@3076 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    Check('Site.IndexGroupsTablesPipeEscaped', (Pos('## IDE group', lIndex) < Pos('## Search group', lIndex)) and (Pos('Empty group', lIndex) = 0)
      and (Pos('| Feature | What it does | Since |', lIndex) > 0) and (Pos('| [Find callers](features/find-callers.md) | Finds callers \| of a name | 0.86.0-alpha |', lIndex) > 0)
      and (Pos('| [Ask](features/ask.md) |', lIndex) < Pos('| [Find callers]', lIndex)), lIndex);

    lAll := '';
    for lFile in TDirectory.GetFiles(lOutA, '*', TSearchOption.soAllDirectories) do
      lAll := lAll + #10 + ReadBytesText(lFile);
    lCli := ReadSiteFile(lOutA, 'cli.md');
    Check('Site.InternalEntryAbsentEverywhere',
      not TFile.Exists(TPath.Combine(lOutA, 'features\internal-thing.md')) and not TFile.Exists(TPath.Combine(lOutA, 'features\selftest-thing.md'))  // dl:ok boolean-expression-complexity@cb9f -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
      and (Pos('internal-thing', lAll) = 0) and (Pos('selftest-thing', lAll) = 0) and (Pos('### hidden', lCli) = 0) and (Pos('### selftest', lCli) = 0)
      and (Pos('Selftest-thing', ReadSiteFile(lOutA, 'features/ask.md')) > 0), lAll);

    lJson := ReadSiteFile(lOutA, 'index.json');
    lVal := TJSONObject.ParseJSONValue(lJson);
    try
      lBad := 0;
      lArr := nil;
      if lVal is TJSONArray then
        lArr := TJSONArray(lVal);
      Check('Site.IndexJsonIsArrayOfFive', (lArr <> nil) and (lArr.Count = 5), lJson);  // dl:ok magic-literal@acd3 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
      if (lArr <> nil) and (lArr.Count = 5) then  // dl:ok magic-literal@e23b -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
      begin
        lOrders := TArray<string>.Create('10001', '10002', '20001', '20002', '20003');
        lIds := TArray<string>.Create('fix-refactor', 'fix-uses', 'ask', 'find-callers', 'find-text');
        for lI := 0 to 4 do  // dl:ok magic-literal@a366 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
        begin
          lRel := lArr.Items[lI].GetValue<string>('file');
          lLeaf := ReadSiteFile(lOutA, lRel);
          if (lArr.Items[lI].GetValue<string>('id') <> lIds[lI]) or (lArr.Items[lI].GetValue<string>('order') <> lOrders[lI])  // dl:ok boolean-expression-complexity@6b4c -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
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
      (Occurrences(lCli, '### query'#10) = 1) and (Pos('### ask'#10, lCli) < Pos('### query'#10, lCli)) and (Pos('drag-lint ask <q> [--db <d>]', lCli) > 0)  // dl:ok boolean-expression-complexity@4e44 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
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
    Check('Site.MicroniteOnlyInIndexAndWhatsNew', (lBad = 0) and (lSentI <> lSentN) and (Pos(lSentI, lIndex) > 0) and (Pos(lSentI, lIndex) < Pos('## ', lIndex))  // dl:ok boolean-expression-complexity@427c -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
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
    Check('Site.TwoBuildsByteIdentical', lSame and (Length(lFiles) > 8) and (Length(lRes.Written) = 0) and (Length(lRes.Changed) = 0), IntToStr(Length(lFiles)));  // dl:ok magic-literal@9994 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
  lRepo, lOut, lMsg, lLeaf, lAsk, lFile: string;
  lAll: Boolean;
  lCount: Integer;
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
      (Pos('title: Gen page', lLeaf) > 0) and (Pos('## Details', lLeaf) = 0) and (Pos('Use ', lLeaf) = 0)  // dl:ok boolean-expression-complexity@29c8 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
      and (Pos('"Features"', ReadSiteFile(lOut, 'wiki-map.json')) = 0) and (Pos('See Features now.', lAsk) > 0) and (Pos('gen-page.md', lAsk) = 0), lLeaf);
    lAll := True;
    lCount := 0;
    for lFile in TDirectory.GetFiles(TPath.Combine(lOut, 'features'), '*.md') do
    begin
      Inc(lCount);
      if Pos('[All features](../index.md)', ReadBytesText(lFile)) = 0 then
        lAll := False;
    end;
    Check('Site.EveryLeafLinksBackToIndex', lAll and (lCount > 1), IntToStr(lCount) + ' leaves');
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
      (Pos('![chart](img/ask-1.png)', lAsk) > 0) and (Pos('[SVG](img/ask-2.svg)', lAsk) > 0) and (Pos('[rel](img/ask-3.svg)', lAsk) > 0)  // dl:ok boolean-expression-complexity@93fb -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
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
    Check('Site.CheckLinksRules', (Length(lBad) = 7) and (Pos('a.md: link "missing.md"', lJoined) > 0) and (Pos('"http://x.org/a" -- external link is not https', lJoined) > 0)  // dl:ok boolean-expression-complexity@6791, magic-literal@6791 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare; test expectation: the literal is the asserted value
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
      (Length(lE.Surfaces) = 2) and (lE.Surfaces[0].Usage = 'drag-lint v2verb go --name <N> [--db <db>]')  // dl:ok boolean-expression-complexity@8e47 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
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
  Check('Json.V2KeyOrderCanonical', lBack = lText, Copy(lBack, 1, 200));  // dl:ok large-magic-number@c18a, magic-literal@c18a -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
  Check('Json.V2FixedOrdersFromScrambled', lBack = lText, Copy(lBack, 1, 200));  // dl:ok large-magic-number@027a, magic-literal@027a -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
      (lSurf.GetValue<string>('usage') = 'keep me') and not lU and (lF = 5) and (lP = 0)  // dl:ok boolean-expression-complexity@181b, magic-literal@181b -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare; test expectation: the literal is the asserted value
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

procedure TestSeedHelpBlocks;
const
  ENTRY_ALPHA = '{ "id": "alpha", "surfaces": [ { "type": "cli", "verb": "alpha" } ] }';
  ENTRY_FEATURE = '{ "id": "a-feature", "surfaces": [ { "type": "cli", "verb": "alpha" } ] }';
  ENTRY_BETA = '{ "id": "beta", "surfaces": [ { "type": "cli", "verb": "beta" } ] }';
  HELP_TEXT = 'Usage:'#10'  drag-lint alpha --x'#10'      alpha detail'#10'  drag-lint beta --y';
var
  lRepo, lEntries: string;
  lHelp: TLiveHelp;
  lCount: Integer;
  lAlpha, lFeature, lBeta: TJSONObject;

  function Surf(pObj: TJSONObject): TJSONObject;
  begin
    Result := (pObj.GetValue('surfaces') as TJSONArray).Items[0] as TJSONObject;
  end;

  function Load(const pName: string): TJSONObject;
  begin
    Result := TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(lEntries, pName), TEncoding.ASCII)) as TJSONObject;
  end;

begin
  lRepo := TPath.Combine(TPath.GetTempPath, 'fg-seedhelp-' + TGuid.NewGuid.ToString);
  lEntries := TPath.Combine(lRepo, 'features\entries');
  TDirectory.CreateDirectory(lEntries);
  TDirectory.CreateDirectory(TPath.Combine(lRepo, 'features\schema'));
  TFile.Copy(TPath.Combine(MiniDir, 'features\schema\entry.schema.json'), TPath.Combine(lRepo, 'features\schema\entry.schema.json'));
  TFile.WriteAllText(TPath.Combine(lEntries, 'a-feature.json'), ENTRY_FEATURE, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lEntries, 'alpha.json'), ENTRY_ALPHA, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lEntries, 'beta.json'), ENTRY_BETA, TEncoding.ASCII);
  lHelp := TLiveHelp.Create;
  try
    lHelp.LoadFromText(HELP_TEXT);
    lCount := SeedHelpBlocks(lRepo, lHelp, False, nil);
    lAlpha := Load('alpha.json');
    lFeature := Load('a-feature.json');
    lBeta := Load('beta.json');
    try
      Check('Seed.ClaimsTwoBlocks', lCount = 2, IntToStr(lCount));
      Check('Seed.NamedAfterVerbOwnsTheBlock',
        (Surf(lAlpha).GetValue('help') as TJSONArray).Count = 2, Surf(lAlpha).ToJSON);
      Check('Seed.SharedUsageLineGetsNoBlock',
        (Surf(lFeature).GetValue('help') = nil) and (Surf(lFeature).GetValue('helpOrder') = nil), Surf(lFeature).ToJSON);
      Check('Seed.BlocksFollowHelpOrder',
        (Surf(lAlpha).GetValue<Integer>('helpOrder', 0) = 1) and (Surf(lBeta).GetValue<Integer>('helpOrder', 0) = 2), Surf(lBeta).ToJSON);
      Check('Seed.LastBlockEndsAtTail', (Surf(lBeta).GetValue('help') as TJSONArray).Count = 1, Surf(lBeta).ToJSON);
    finally
      lAlpha.Free;
      lFeature.Free;
      lBeta.Free;
    end;
    lCount := SeedHelpBlocks(lRepo, lHelp, True, nil);
    Check('Seed.RerunIsStable', lCount = 2, IntToStr(lCount));
  finally
    lHelp.Free;
    TDirectory.Delete(lRepo, True);
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
  lCases[3] := TArray<string>.Create('"surfaces": [ { "type": "cli", "verb": "ask", "flags": [ { "name": "--a", "summary": "Takes <b> raw" } ] } ]', 'flags', 'raw HTML');  // dl:ok magic-literal@2e91 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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

{ ---- Task 7/8/11: golden parity. At the cut-over the PowerShell generator and guard were
  retired; the products they made for this repo (the seven wiki outputs, the finding sets of
  check A-E on the real and the seeded repo, the live-surface lines) were frozen as files
  under fixtures\golden, and the comparison helpers (CompareOutputTrees, CompareFindingSets)
  now read those. The golden files describe the repo as it was at 1.32.0-alpha WITHOUT
  featuregen's own registry entry, so GoldenRepo rebuilds exactly that tree. ---- }

const
  ENGINE_ENV = 'FEATUREGEN_TEST_ENGINE';
  MAIN_ENGINE_FALLBACK = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe';  // dl:ok hardcoded-absolute-path@7f58 -- REVIEWED 2026-10-20: last-resort fallback only (documented in MainEngine); the engine normally comes from FEATUREGEN_TEST_ENGINE
  GOLDEN_STUB_NAME = 'golden-engine-stub.exe';
  FROZEN_SCRATCH = 'C:\TEMP\claude\featuregen-task4\scratch';  // dl:ok hardcoded-absolute-path@8adf -- REVIEWED 2026-10-20: the scratch folder the golden check captures were written under; the live per-run folder is mapped onto it before comparing
  STUB_USAGE_EXIT = 2;
  FROZEN_SUFFIX = '.frozen';

{ The live engine the live-surface tests run: the file named by the environment variable
  FEATUREGEN_TEST_ENGINE when set, else the main-tree path MAIN_ENGINE_FALLBACK (the worktree's
  own third_party\dll-win64 copy can be stale, so it is not preferred). }
function MainEngine: string;
begin
  Result := GetEnvironmentVariable(ENGINE_ENV);
  if Result = '' then
    Result := MAIN_ENGINE_FALLBACK;
end;

var
  GGoldenRepo: string = '';
  GGoldenEngine: string = '';
  GGoldenLive: TLiveSurface = nil;

{ When this exe was copied to golden-engine-stub.exe it plays the engine of the frozen
  golden repo: `--help` and `rules --json` print the bytes frozen under fixtures\golden\engine
  (next to the stub), anything else exits 2. The parity tests never need the live engine. }
procedure RunGoldenEngineStub;
var
  lFile: string;
  lBytes: TBytes;
  lOut: THandleStream;
begin
  if (ParamCount >= 1) and (ParamStr(1) = '--help') then
    lFile := 'help.txt'
  else if (ParamCount >= 2) and (ParamStr(1) = 'rules') and (ParamStr(2) = '--json') then
    lFile := 'rules.json'
  else
    Halt(STUB_USAGE_EXIT);
  lBytes := TFile.ReadAllBytes(TPath.Combine(ExtractFilePath(ParamStr(0)), lFile));
  lOut := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
  try
    lOut.WriteBuffer(lBytes[0], Length(lBytes));
  finally
    lOut.Free;
  end;
end;

procedure CopyFileTo(const pRepo, pDst, pRel: string);
begin
  ForceDirectories(ExtractFilePath(TPath.Combine(pDst, pRel)));
  TFile.Copy(TPath.Combine(pRepo, pRel), TPath.Combine(pDst, pRel), True);
end;

function GoldenFile(const pRepo, pRel: string): string;
begin
  Result := TPath.Combine(pRepo, 'src\tools\featuregen\tests\fixtures\golden\' + pRel);
end;

function ProductVersionIn(const pRepo: string): string;
begin
  Result := TRegEx.Match(TFile.ReadAllText(TPath.Combine(pRepo, 'src\core\DRagLint.Core.Model.pas')),
    'DRAGLINT_VERSION\s*=\s*''([^'']+)''').Groups[1].Value;
end;

{ The engine of the frozen golden repo: a copy of this exe named GOLDEN_STUB_NAME (see
  RunGoldenEngineStub) beside the frozen `--help` and `rules --json` outputs. }
function GoldenEngine(const pRepo: string): string;
var
  lDir, lName: string;
begin
  if GGoldenEngine <> '' then
    Exit(GGoldenEngine);
  lDir := FreshDir('golden-engine');
  TFile.Copy(ParamStr(0), TPath.Combine(lDir, GOLDEN_STUB_NAME), True);
  for lName in ['help.txt', 'rules.json'] do
    TFile.Copy(GoldenFile(pRepo, 'engine\' + lName), TPath.Combine(lDir, lName), True);
  GGoldenEngine := TPath.Combine(lDir, GOLDEN_STUB_NAME);
  Result := GGoldenEngine;
end;

{ A scratch copy of the FROZEN inputs (fixtures\golden\repo: everything the generators read,
  as it was at the capture, without featuregen's own entry; .pas sources are stored with
  FROZEN_SUFFIX so no index walks them), with every generated output re-rendered by
  featuregen against the frozen engine outputs so that check D is clean on it. Nothing here
  reads the live repository, the live version or the live engine: the parity tests are a
  permanent regression pin. }
function GoldenRepo(const pRepo: string): string;
var
  lDst, lSrc, lFile, lRel: string;
  lW: TOutputWriter;
begin
  if GGoldenRepo <> '' then
    Exit(GGoldenRepo);
  lDst := FreshDir('golden-repo');
  lSrc := GoldenFile(pRepo, 'repo');
  for lFile in TDirectory.GetFiles(lSrc, '*', TSearchOption.soAllDirectories) do
  begin
    lRel := Copy(lFile, Length(lSrc) + 2, MaxInt);
    if lRel.EndsWith(FROZEN_SUFFIX) then
      lRel := Copy(lRel, 1, Length(lRel) - Length(FROZEN_SUFFIX));
    ForceDirectories(ExtractFilePath(TPath.Combine(lDst, lRel)));
    TFile.Copy(lFile, TPath.Combine(lDst, lRel), True);
  end;
  // README.md and docs\AI-USAGE.md as the PowerShell generator left them: check D quotes lines of them, so their prose is frozen too
  CopyFileTo(GoldenFile(pRepo, 'wiki'), lDst, 'README.md');
  CopyFileTo(GoldenFile(pRepo, 'wiki'), lDst, 'docs\AI-USAGE.md');
  lW := TOutputWriter.Create(lDst, False, False);
  try
    BuildWiki(lDst, lW, GoldenEngine(pRepo));
    lW.Finish;
  finally
    lW.Free;
  end;
  BuildSiteSet(lDst, GoldenEngine(pRepo), ProductVersionIn(lDst), False);
  GGoldenRepo := lDst;
  Result := lDst;
end;

{ The live surface of the frozen golden repo, harvested once with the frozen engine. }
function GoldenLive(const pRepo: string): TLiveSurface;
begin
  if GGoldenLive = nil then
  begin
    GGoldenLive := TLiveSurface.Create;
    try
      GGoldenLive.Harvest(GoldenRepo(pRepo), GoldenEngine(pRepo));
    except
      on Exception do
      begin
        FreeAndNil(GGoldenLive);
        raise;
      end;
    end;
  end;
  Result := GGoldenLive;
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

{ The text compared for one output. (1) The golden files were written by the PowerShell
  generator, whose footers named its own script; featuregen's name featuregen -- the one
  intentional difference. (2) README.md and docs\AI-USAGE.md are compared by their dl:registry
  blocks only: the generator writes nothing else in them, the rest is hand-written prose that
  changes without touching the generator. }
function Comparable(const pRel, pText: string): string;
var
  lM: TMatch;
begin
  Result := pText.Replace('Generated by `tools\build-feature-pages.ps1`', 'Generated by `featuregen build --all`');
  if SameText(pRel, 'README.md') or SameText(pRel, 'docs\AI-USAGE.md') then
  begin
    Result := '';
    for lM in TRegEx.Matches(pText, '<!-- dl:registry:begin (\S+) -->.*?<!-- dl:registry:end \1 -->', [roSingleLine]) do
      Result := Result + lM.Value + #10;
  end;
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
      else if Comparable(lRel, ReadBytesText(lA)) <> Comparable(lRel, ReadBytesText(lB)) then
        lList.Add(lRel + ': ' + FirstDifference(Comparable(lRel, ReadBytesText(lA)), Comparable(lRel, ReadBytesText(lB))));
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
  TFile.WriteAllBytes(lFile, TBytes.Create(Ord('a'), Ord('b'), $C3, $A9, 13, 10));  // dl:ok magic-literal@1672 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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
  lGold, lB, lCli, lMsg: string;
  lW: TOutputWriter;
  lBad, lDead: TArray<string>;
  lChecked: Integer;
begin
  lGold := GoldenRepo(pRepo);
  lB := FreshDir('wiki-parity-fg');
  lMsg := '';
  try
    lW := TOutputWriter.Create(lB, False, False);
    try
      BuildWiki(lGold, lW, GoldenEngine(pRepo));
      lW.Finish;
    finally
      lW.Free;
    end;
  except
    on E: Exception do
      lMsg := E.ClassName + ': ' + E.Message;
  end;
  lBad := CompareOutputTrees(GoldenFile(pRepo, 'wiki'), lB, WikiOutputPaths);
  Check('Parity.WikiOutputsEqualGolden', (lMsg = '') and (Length(lBad) = 0), lMsg + ' ' + string.Join(' | ', lBad));
  lCli := TPath.Combine(lB, 'features\generated\cli-reference.md');
  Check('Wiki.CliReferenceIsCliMdWithoutFrontMatter', TFile.Exists(lCli) and ReadBytesText(lCli).StartsWith('# CLI reference'#13#10#13#10)
    and (Pos('## Commands', ReadBytesText(lCli)) > 0), lCli);
  if TFile.Exists(lCli) then
  begin
    lDead := DeadRelativeLinks(ReadBytesText(lCli), TPath.Combine(lGold, 'features\generated'), lChecked);
    Check('Wiki.CliReferenceLinksResolveInRepo', (lChecked > 100) and (Length(lDead) = 0),  // dl:ok magic-literal@8726 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
      IntToStr(lChecked) + ' checked; dead: ' + string.Join(' | ', Copy(lDead, 0, 5)));  // dl:ok magic-literal@4e78 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
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

{ ---- Task 8/11: live harvest + checks A-E, compared with the frozen PowerShell products
  (fixtures\golden\live, fixtures\golden\check). ---- }
{ The Delphi harvest in the same "kind<TAB>value" shape as golden\live\live.txt. }
function LiveLines(const pLive: TLiveSurface): TArray<string>;
var
  lList: TList<string>;
  lS, lV: string;
  lQ: TReportQuestion;
  lK: string;
begin
  lList := TList<string>.Create;
  try
    for lS in pLive.HelpVerbs do lList.Add('help'#9 + lS);
    for lS in pLive.DispatchVerbs do lList.Add('dispatch'#9 + lS);
    for lV in pLive.SubVerbs do
      for lS in pLive.SubMap[lV] do
        lList.Add('sub'#9 + lV + ' ' + lS);
    for lS in pLive.Captions do lList.Add('caption'#9 + lS);
    for lS in pLive.DialogButtons do lList.Add('dialog'#9 + lS);
    for lS in pLive.AboutButtons do lList.Add('about'#9 + lS);
    for lV in pLive.ContextHosts do
      for lS in pLive.ContextCaptions[lV] do
        lList.Add('context'#9 + lV + '|' + lS);
    for lS in pLive.McpTools do lList.Add('mcp'#9 + lS);
    for lS in pLive.McpDispatch do lList.Add('mcp-dispatch'#9 + lS);
    for lQ in pLive.ReportQuestions do lList.Add('question'#9 + lQ.Id + '|' + lQ.Caption + '|' + lQ.Kind);
    lList.Add('question-count'#9 + IntToStr(pLive.ReportQuestionCount));
    for lK in pLive.GroupCaptions.Keys do lList.Add('group-caption'#9 + lK + '|' + pLive.GroupCaptions[lK]);
    for lS in pLive.ChartValidateSet do lList.Add('validateset'#9 + lS);
    for lS in pLive.EmitterFiles do lList.Add('emitter'#9 + lS);
    for lS in pLive.PackExes do lList.Add('pack'#9 + lS);
    lList.Add('rules-total'#9 + TJSONObject(TJSONObject(pLive.RuleCatalog).GetValue('summary')).GetValue('total').Value);
    lList.Add('version'#9 + pLive.ProductVersion + '|' + pLive.ExtractorVersion + '|' + pLive.ResolverVersion + '|' + pLive.SchemaVersion);
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

{ Set comparison (ordinal, order ignored, duplicates kept): items only in pExpected and only in pActual. }
procedure CompareFindingSets(const pExpected, pActual: TArray<string>; out pMissing, pExtra: TArray<string>);
var
  lA, lB: TList<string>;
  lS: string;
  lI: Integer;
begin
  lA := TList<string>.Create;
  lB := TList<string>.Create(pActual);
  try
    for lS in pExpected do
    begin
      lI := lB.IndexOf(lS);
      if lI >= 0 then
        lB.Delete(lI)
      else
        lA.Add(lS);
    end;
    pMissing := lA.ToArray;
    pExtra := lB.ToArray;
  finally
    lB.Free;
    lA.Free;
  end;
end;

function KindCounts(const pLines: TArray<string>): string;
var
  lCounts: TDictionary<string, Integer>;
  lS, lK: string;
  lKeys: TArray<string>;
begin
  lCounts := TDictionary<string, Integer>.Create;
  try
    for lS in pLines do
    begin
      lK := lS.Split([#9])[0];
      if lCounts.ContainsKey(lK) then
        lCounts[lK] := lCounts[lK] + 1
      else
        lCounts.Add(lK, 1);
    end;
    lKeys := lCounts.Keys.ToArray;
    TArray.Sort<string>(lKeys);
    Result := '';
    for lK in lKeys do
      Result := Result + lK + '=' + IntToStr(lCounts[lK]) + ' ';
  finally
    lCounts.Free;
  end;
end;

{ FG-M item 3: the caption-key vector SHARED with the engine (tests\MenuTreeTests.dpr
  TestCaptionKeyVector, spec 2026-10-23-code-built-menu-reader-design.md section 6). The
  rows are the same text on both sides so a divergence between DRagLint.MenuTree.MenuCaptionKey /
  MenuPathKey and featuregen's CaptionKey / MenuPathKey / MenuKey fails one of the two batteries. }
procedure TestCaptionKeyVector;

  procedure CheckEq(const pName, pWant, pGot: string);
  begin
    Check('KeyVector.' + pName, pWant = pGot, Format('want [%s] got [%s]', [pWant, pGot]));
  end;

begin
  CheckEq('key: && and ...', 'uses & deps tab -- review & apply fixes', CaptionKey('Uses && Deps Tab -- review && apply fixes...'));
  CheckEq('key: trailing ...', 'find usages', CaptionKey('Find Usages...'));
  CheckEq('key: plain', 'reports', CaptionKey('Reports'));
  CheckEq('key: trim ) only at the end', 'drag-lint (!', CaptionKey('drag-lint (!)'));
  CheckEq('key: quote chars and whitespace', 'a b c', CaptionKey('  `A`  *b*  "C" '));
  CheckEq('path key', 'fixture > tools > find usages', MenuPathKey('Fixture > Tools  > Find Usages...'));
  CheckEq('path key drops empty segments', 'a > b', MenuPathKey('A > ... > B'));
  // FeatureGen.Commands.MenuKey (implementation-private) delegates to MenuPathKey: one rule, no second copy to drift
end;

{ FG-M item 1: the menu-tree/1 document (drag-lint menu-tree --format json) flattened to
  full paths; external roots are left out, '&&' reduced, separators carry the parent's path. }
procedure TestParseMenuTreeJson;
const
  DOC = '{ "schema": "menu-tree/1", "engine": "x", "project": "p", "db": "d", "generated": "g",'
    + ' "roots": [ { "kind": "root", "caption": "drag-lint", "captionKey": "drag-lint", "source": "E.pas:1", "confidence": "certain",'
    + '   "children": [ { "kind": "item", "caption": "Full Compile Sweep", "captionKey": "full compile sweep", "handler": "E.InvokeSweep", "source": "E.pas:2", "confidence": "certain" },'
    + '                 { "kind": "separator", "source": "E.pas:3", "confidence": "certain" },'
    + '                 { "kind": "submenu", "caption": "Uses && Dependencies", "captionKey": "uses & dependencies", "source": "E.pas:4", "confidence": "certain",'
    + '                   "children": [ { "kind": "header", "caption": "This unit", "captionKey": "this unit", "source": "E.pas:5", "confidence": "certain" },'
    + '                                 { "kind": "item", "caption": "Find Usages...", "captionKey": "find usages", "handler": "E.InvokeFind", "source": "E.pas:6", "confidence": "derived" },'
    + '                                 { "kind": "dynamic", "caption": "<dynamic: X>", "captionKey": "<dynamic: x>", "source": "E.pas:7", "confidence": "unknown" } ] } ] } ],'
    + ' "external": [ { "kind": "external-root", "ident": "ToolWin", "source": "E.pas:8", "children": [ { "kind": "item", "caption": "drag-lint", "captionKey": "drag-lint", "source": "E.pas:9", "confidence": "certain" } ] } ],'
    + ' "notes": [ "dynamic caption at E.pas:7: X.Caption := Y" ] }';
  DOC_EXTRA = '{ "schema": "menu-tree/1", "engine": "x", "project": "p", "db": "d", "generated": "g", "futureTop": { "a": 1 },'
    + ' "roots": [ { "kind": "root", "caption": "drag-lint", "captionKey": "drag-lint", "ident": "mnuRoot", "identPath": "frmMain.mnuRoot", "form": "frmMain", "source": "E.pas:1", "confidence": "certain",'
    + '   "children": [ { "kind": "item", "caption": "Full Compile Sweep", "captionKey": "full compile sweep", "ident": "miSweep", "identPath": "frmMain.mnuRoot.miSweep", "form": "frmMain", "handler": "E.InvokeSweep", "source": "E.pas:2", "confidence": "certain" },'
    + '                 { "kind": "separator", "source": "E.pas:3", "confidence": "certain", "ident": "N1" },'
    + '                 { "kind": "submenu", "caption": "Uses && Dependencies", "captionKey": "uses & dependencies", "identPath": [ "x" ], "source": "E.pas:4", "confidence": "certain",'
    + '                   "children": [ { "kind": "header", "caption": "This unit", "captionKey": "this unit", "form": 7, "source": "E.pas:5", "confidence": "certain" },'
    + '                                 { "kind": "item", "caption": "Find Usages...", "captionKey": "find usages", "handler": "E.InvokeFind", "source": "E.pas:6", "confidence": "derived", "ident": null },'
    + '                                 { "kind": "dynamic", "caption": "<dynamic: X>", "captionKey": "<dynamic: x>", "source": "E.pas:7", "confidence": "unknown" } ] } ] } ],'
    + ' "external": [ { "kind": "external-root", "ident": "ToolWin", "identPath": "INTAServices.MainMenu.ToolWin", "source": "E.pas:8", "children": [ { "kind": "item", "caption": "drag-lint", "captionKey": "drag-lint", "source": "E.pas:9", "confidence": "certain" } ] } ],'
    + ' "notes": [ "dynamic caption at E.pas:7: X.Caption := Y" ] }';
var
  lNodes: TArray<TMenuNodeRow>;
  lNotes: TArray<string>;
  lLive: TLiveSurface;
  lRaised: Boolean;
  lShape: string;

  { kind:path per node, in order -- one string pins count, order, kinds, paths and the '&&' reduction }
  function Shape(const pRows: TArray<TMenuNodeRow>): string;
  var
    lRow: TMenuNodeRow;
    lParts: TArray<string>;
  begin
    lParts := nil;
    for lRow in pRows do
      lParts := lParts + [lRow.Kind + ':' + lRow.Path];
    Result := string.Join('|', lParts);
  end;

  function RowAt(const pPath: string): TMenuNodeRow;
  var
    lRow: TMenuNodeRow;
  begin
    Result := Default(TMenuNodeRow);
    for lRow in lNodes do
      if lRow.Path = pPath then
        Exit(lRow);
  end;

begin
  ParseMenuTreeJson(DOC, lNodes, lNotes);
  lShape := 'root:drag-lint|item:drag-lint > Full Compile Sweep|separator:drag-lint|submenu:drag-lint > Uses & Dependencies'
    + '|header:drag-lint > Uses & Dependencies > This unit|item:drag-lint > Uses & Dependencies > Find Usages...'
    + '|dynamic:drag-lint > Uses & Dependencies > <dynamic: X>';
  Check('ParseMenuTree.Shape', Shape(lNodes) = lShape, Shape(lNodes));
  Check('ParseMenuTree.LeafHandler', RowAt('drag-lint > Full Compile Sweep').Handler = 'E.InvokeSweep');
  Check('ParseMenuTree.NestedLeafConfidence', RowAt('drag-lint > Uses & Dependencies > Find Usages...').Confidence = 'derived');
  Check('ParseMenuTree.DynamicKind', RowAt('drag-lint > Uses & Dependencies > <dynamic: X>').Kind = MENU_KIND_DYNAMIC);
  Check('ParseMenuTree.Notes', string.Join('|', lNotes) = 'dynamic caption at E.pas:7: X.Caption := Y', string.Join('|', lNotes));
  lLive := TLiveSurface.Create;
  try
    lLive.MenuNodes := lNodes;
    Check('ParseMenuTree.LeavesAreItemsOnly', Shape(lLive.MenuLeaves) = 'item:drag-lint > Full Compile Sweep|item:drag-lint > Uses & Dependencies > Find Usages...', Shape(lLive.MenuLeaves));
    Check('ParseMenuTree.NoSourceMeansNoTree', not lLive.HasMenuTree);
    lLive.MenuSource := MENU_SOURCE_TREE;
    Check('ParseMenuTree.TreeSourceMeansTree', lLive.HasMenuTree);
  finally
    lLive.Free;
  end;
  lRaised := False;
  try
    ParseMenuTreeJson('{ "schema": "menu-drift/1", "roots": [] }', lNodes, lNotes);
  except
    on E: EFeatureGenLive do
      lRaised := Pos('menu-tree/1', E.Message) > 0;
  end;
  Check('ParseMenuTree.WrongSchemaRaises', lRaised);
  // fields a later engine adds (identPath on external roots; ident / identPath / form on --with-dfm
  // roots and leaves; an unknown top-level key) are ignored: same rows, same handler
  ParseMenuTreeJson(DOC_EXTRA, lNodes, lNotes);
  Check('ParseMenuTree.UnknownFieldsIgnored', (Shape(lNodes) = lShape)
    and (RowAt('drag-lint > Full Compile Sweep').Handler = 'E.InvokeSweep'), Shape(lNodes));
end;

procedure TestCompareFindingSetsPositiveControl;
var
  lMissing, lExtra: TArray<string>;
begin
  CompareFindingSets(['A: x', 'B: y', 'B: y'], ['B: y', 'C: z', 'A: x'], lMissing, lExtra);
  Check('Check.CompareFindingSetsCatchesDifferences', (Length(lMissing) = 1) and (lMissing[0] = 'B: y')
    and (Length(lExtra) = 1) and (lExtra[0] = 'C: z'), string.Join(' | ', lMissing) + ' // ' + string.Join(' | ', lExtra));
end;

var
  GLive: TLiveSurface = nil;

{ The shared real-repo surface, harvested once. GLive is set only after a harvest
  succeeded, so a failed harvest never leaves a half-filled surface for later tests. }
function SharedLiveFrom(const pRepo, pEngine: string): TLiveSurface;
var
  lLive: TLiveSurface;
begin
  if GLive = nil then
  begin
    lLive := TLiveSurface.Create;
    try
      lLive.Harvest(pRepo, pEngine);
    except  // dl:ok bare-except@ec5d -- REVIEWED 2026-10-19: cleanup-and-re-raise: frees the half-built result, then raises the original exception
      lLive.Free;
      raise;
    end;
    GLive := lLive;
  end;
  Result := GLive;
end;

function SharedLive(const pRepo: string): TLiveSurface;
begin
  Result := SharedLiveFrom(pRepo, MainEngine);
end;

procedure TestSharedLiveNotCachedOnFailure(const pRepo: string);
begin
  if GLive <> nil then
    Exit;
  try
    SharedLiveFrom(pRepo, TPath.Combine(SCRATCH, 'no-such-engine.exe'));
  except
    on E: EFeatureGenLive do
      Writeln('INFO expected harvest failure: ', E.Message);
  end;
  Check('Live.SharedLiveNotCachedAfterFailedHarvest', GLive = nil, 'a failed harvest left GLive set');
  FreeAndNil(GLive);
end;

{ Every TLiveSurface kind that is empty (or a version that is ''); none on a healthy tree. }
function EmptyLiveKinds(const pLive: TLiveSurface): TArray<string>;

  procedure Need(pOk: Boolean; const pKind: string);
  begin
    if not pOk then
      Result := Result + [pKind];
  end;

var
  lH: string;
  lHostsOk: Boolean;
  lTotal: TJSONValue;
begin
  Result := nil;
  Need(Length(pLive.HelpVerbs) > 0, 'HelpVerbs');
  Need(Length(pLive.DispatchVerbs) > 0, 'DispatchVerbs');
  Need(pLive.SubMap.Count > 0, 'SubMap');
  Need(Length(pLive.Captions) > 0, 'Captions');
  Need(Length(pLive.DialogButtons) > 0, 'DialogButtons');
  Need(Length(pLive.AboutButtons) > 0, 'AboutButtons');
  Need(Length(pLive.ContextHosts) > 0, 'ContextHosts');
  lHostsOk := Length(pLive.ContextHosts) > 0;
  for lH in pLive.ContextHosts do
    if not pLive.ContextCaptions.ContainsKey(lH) or (Length(pLive.ContextCaptions[lH]) = 0) then
      lHostsOk := False;
  Need(lHostsOk, 'ContextCaptions');
  Need(Length(pLive.McpTools) > 0, 'McpTools');
  Need(Length(pLive.McpDispatch) > 0, 'McpDispatch');
  lTotal := nil;
  if (pLive.RuleCatalog is TJSONObject) and (TJSONObject(pLive.RuleCatalog).GetValue('summary') is TJSONObject) then
    lTotal := TJSONObject(TJSONObject(pLive.RuleCatalog).GetValue('summary')).GetValue('total');
  Need((lTotal <> nil) and (StrToIntDef(lTotal.Value, 0) > 0), 'RuleCatalog');
  Need(Length(pLive.ReportQuestions) > 0, 'ReportQuestions');
  Need(pLive.ReportQuestionCount > 0, 'ReportQuestionCount');
  Need(pLive.GroupCaptions.Count > 0, 'GroupCaptions');
  Need(Length(pLive.ChartValidateSet) > 0, 'ChartValidateSet');
  Need(Length(pLive.EmitterFiles) > 0, 'EmitterFiles');
  Need(Length(pLive.PackExes) > 0, 'PackExes');
  Need(pLive.ProductVersion <> '', 'ProductVersion');
  Need(pLive.ExtractorVersion <> '', 'ExtractorVersion');
  Need(pLive.ResolverVersion <> '', 'ResolverVersion');
  Need(pLive.SchemaVersion <> '', 'SchemaVersion');
end;

procedure TestEmptyKindsPositiveControl;
var
  lLive: TLiveSurface;
  lEmpty: TArray<string>;
begin
  lLive := TLiveSurface.Create;
  try
    lEmpty := EmptyLiveKinds(lLive);
  finally
    lLive.Free;
  end;
  Check('Live.EmptyKindsCatchesEveryEmptyKind', Length(lEmpty) = 21, IntToStr(Length(lEmpty)) + ': ' + string.Join(' ', lEmpty));  // dl:ok large-magic-number@1259, magic-literal@1259 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
end;

procedure TestHarvestRaisesOnEmptySubMap(const pRepo: string);
var
  lDir, lMsg: string;
  lLive: TLiveSurface;
begin
  lDir := FreshDir('no-subs-repo');
  ForceDirectories(TPath.Combine(lDir, 'src\cli'));
  TFile.WriteAllText(TPath.Combine(lDir, 'src\cli\DRagLint.CLI.pas'),
    ReadBytesText(TPath.Combine(pRepo, 'src\cli\DRagLint.CLI.pas')).Replace('SubCommand', 'SubCmdZz'), TEncoding.ASCII);
  lMsg := '';
  lLive := TLiveSurface.Create;
  try
    try
      lLive.Harvest(lDir, MainEngine);
    except
      on E: Exception do
        lMsg := E.Message;
    end;
  finally
    lLive.Free;
  end;
  Check('Live.HarvestRaisesOnEmptySubMap', lMsg = 'live surface: 0 subcommands harvested from DRagLint.CLI.pas; expected > 0', lMsg);
end;

{ Health of the LIVE surface (not a golden comparison): '' when every kind of the real repo is
  non-empty, else a detail naming the cause. A harvest that raises (e.g. a stale plugin DB: menu-tree
  exits 3) yields the exception text, never an access violation. }
function LiveHealthDetail(const pRepo, pEngine: string): string;
var
  lMsg: string;
  lLive: TLiveSurface;
begin
  lMsg := '';
  lLive := nil;
  try
    lLive := SharedLiveFrom(pRepo, pEngine);
  except
    on E: Exception do
      lMsg := E.ClassName + ': ' + E.Message;
  end;
  if lLive = nil then
  begin
    Result := 'live harvest failed: ' + lMsg;
    if lMsg = '' then
      Result := 'live harvest returned no surface';
    Exit;
  end;
  Result := Trim(string.Join(' ', EmptyLiveKinds(lLive)));
  if Result <> '' then
    Result := 'empty live kinds: ' + Result;
end;

procedure TestHarvestFailureIsCleanFail;
var
  lDetail: string;
begin
  FreeAndNil(GLive);
  lDetail := LiveHealthDetail(ExtractFilePath(ParamStr(0)), TPath.Combine(SCRATCH, 'no-such-engine.exe'));
  Check('Live.HarvestFailureIsCleanFail', lDetail <> '', lDetail);
end;

procedure TestLiveHarvestParity(const pRepo: string);
var
  lFile: string;
  lPsLines, lMine, lMissing, lExtra: TArray<string>;
  lMsg: string;
begin
  lFile := GoldenFile(pRepo, 'live\live.txt');
  lMsg := '';
  lMine := nil;
  try
    lMine := LiveLines(GoldenLive(pRepo));
  except
    on E: Exception do
      lMsg := E.ClassName + ': ' + E.Message;
  end;
  Writeln('INFO live harvest of the frozen repo (Delphi): ', KindCounts(lMine));
  lPsLines := TFile.ReadAllLines(lFile, TEncoding.ASCII);
  CompareFindingSets(lPsLines, lMine, lMissing, lExtra);
  Check('Live.HarvestEqualsGolden', (lMsg = '') and (Length(lPsLines) > 100) and (Length(lMissing) = 0) and (Length(lExtra) = 0),  // dl:ok magic-literal@c059 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    lMsg + ' missing: ' + string.Join(' | ', Copy(lMissing, 0, 8)) + ' // extra: ' + string.Join(' | ', Copy(lExtra, 0, 8)));  // dl:ok magic-literal@8005 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
  Check('Live.HarvestEveryKindNonEmpty', LiveHealthDetail(pRepo, MainEngine) = '', LiveHealthDetail(pRepo, MainEngine));
end;
{ The "add this entry" template inside a B finding carries the date of the day it was
  rendered ("date": "2026-10-19"); the frozen golden was rendered on its capture day. The
  date is the one value that is not frozen, so both sides are compared with it scrubbed. }
function ScrubTodayDate(const pText: string): string;
begin
  Result := TRegEx.Replace(pText, '"date": "\d{4}-\d{2}-\d{2}"', '"date": "<today>"');
end;

{ The golden findings carry the PowerShell-era fix hints; the Task 11 hint texts name the
  featuregen commands instead. Everything else in a finding is compared verbatim. }
function ModernHints(const pText: string): string;
begin
  Result := pText.Replace('feature-registry.ps1 add -NewTeam', 'featuregen add --new-team')
    .Replace('tools\feature-registry.ps1 add -Id ', 'featuregen add --id ')
    .Replace('tools\feature-registry.ps1 move-menu', 'featuregen move-menu')
    .Replace('tools\feature-registry.ps1 normalise', 'featuregen normalise')
    .Replace('run tools\build-feature-pages.ps1', 'run featuregen build --all');
  Result := ScrubTodayDate(Result);
end;
function ReadGoldenCheck(const pFile: string; out pNotes: TArray<string>): TArray<string>;
var
  lV: TJSONValue;
  lA: TJSONValue;
  i: Integer;
begin
  Result := nil;
  pNotes := nil;
  if not TFile.Exists(pFile) then
    Exit;
  lV := TJSONObject.ParseJSONValue(TFile.ReadAllText(pFile, TEncoding.UTF8));
  try
    lA := TJSONObject(lV).GetValue('Failures');
    if lA is TJSONArray then
      for i := 0 to TJSONArray(lA).Count - 1 do
        Result := Result + [ModernHints(TJSONArray(lA).Items[i].Value)];
    lA := TJSONObject(lV).GetValue('Notes');
    if lA is TJSONArray then
      for i := 0 to TJSONArray(lA).Count - 1 do
        pNotes := pNotes + [ModernHints(TJSONArray(lA).Items[i].Value)];
  finally
    lV.Free;
  end;
end;

const
  // The finding classes featuregen reports and the PowerShell guard could not.
  // Each is kept OUT of the set comparison by an exact marker and its count is
  // ASSERTED against an independently computed expectation, so the exclusion can
  // never hide another difference.
  // (1) spec criterion 5: an unregistered MCP tool fails;
  MCP_ONLY_PREFIX = 'B: every MCP tool is registered -- ';
  // (2) nested schema violations (the PowerShell Test-Json drops them): an "A: "
  //     finding carrying FeatureGen.Check.NESTED_SCHEMA_MARK;
  // (3) Task 11: check D over the outputs the PowerShell generator did not own
  //     (cli-reference.md, the website set, site-pages.json);
  // (4) H-SYS 2026-10-26: the help-audit prose checks (A: G-1/G-2/G-3, C: G-4/G-6),
  //     each finding's first line ending in its "(G-n)" tag.
  PROSE_MARK = '\(G-[1-6]\)$';
  // The frozen golden repo's prose findings, reviewed 2026-10-26: 26 at check A (11 G-3 entry anchors that drift or
  // name a unit the frozen tree lacks, 7 G-3 wiki anchors, 1 G-1, 7 G-2), plus 2 G-6 at the full level.
  GOLDEN_PROSE_A = 26;
  GOLDEN_PROSE_FULL = 28;

{ True for a "D: " finding whose output is one of the three Task 11 additions. }
function IsNewDOutput(const pItem: string): Boolean;
begin
  Result := pItem.StartsWith('D: ') and (pItem.StartsWith('D: features\generated\cli-reference.md ')
    or pItem.StartsWith('D: features\generated\site-pages.json ') or pItem.StartsWith('D: src\cli\DRagLint.CLI.HelpText.pas ') or pItem.StartsWith('D: WWW\help\dl\'));
end;

{ Splits off the Delphi-only classes; returns the rest. }
function WithoutDelphiOnly(const pItems: TArray<string>; out pMcp, pNested, pNewD, pProse, pDocs: Integer): TArray<string>;
var
  lS: string;
begin
  Result := nil;
  pMcp := 0;
  pNested := 0;
  pNewD := 0;
  pProse := 0;
  pDocs := 0;
  for lS in pItems do
    if lS.StartsWith(MCP_ONLY_PREFIX) then
      Inc(pMcp)
    else if TRegEx.IsMatch(lS, '^C: C[123] ') then
      Inc(pDocs)
    else if lS.StartsWith('A: ') and (Pos(NESTED_SCHEMA_MARK, lS) > 0) then
      Inc(pNested)
    else if IsNewDOutput(lS) then
      Inc(pNewD)
    else if TRegEx.IsMatch(lS.Split([#10])[0], PROSE_MARK) then
      Inc(pProse)
    else
      Result := Result + [lS];
end;
{ The exclusion guard: an excluded count must equal a known, non-negative expectation. }
function ExclusionCountOk(pDropped, pExpected: Integer): Boolean;
begin
  Result := (pExpected >= 0) and (pDropped = pExpected);
end;

procedure TestExclusionCountPositiveControl;
begin
  Check('Check.ExclusionCountGuardCatchesMismatch', not ExclusionCountOk(15, 14) and not ExclusionCountOk(0, -1)  // dl:ok magic-literal@7ebc -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    and not ExclusionCountOk(3, -1) and ExclusionCountOk(15, 15) and ExclusionCountOk(0, 0));  // dl:ok magic-literal@ac8b -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
end;

{ Live MCP tools that no non-planned entry under pRepo\features\entries registers
  with an mcp surface: the count the MCP-only B class must have. Computed from the
  files, independently of FeatureGen.Check. }
function ExpectedMcpExclusions(const pRepo: string; const pTools: TArray<string>): Integer;
var
  lF, lT: string;
  lV, lS: TJSONValue;
  lA: TJSONValue;
  lReg: TList<string>;
  i: Integer;
begin
  lReg := TList<string>.Create;
  try
    for lF in TDirectory.GetFiles(TPath.Combine(pRepo, 'features\entries'), '*.json') do
    begin
      lV := ReadJsonFile(lF);
      try
        if SameText(Prop(lV, 'status'), 'planned') then
          Continue;
        lA := TJSONObject(lV).GetValue('surfaces');
        if lA is TJSONArray then
          for i := 0 to TJSONArray(lA).Count - 1 do
          begin
            lS := TJSONArray(lA).Items[i];
            if SameText(Prop(lS, 'type'), 'mcp') then
              lReg.Add(LowerCase(Prop(lS, 'tool')));
          end;
      finally
        lV.Free;
      end;
    end;
    Result := 0;
    for lT in pTools do
      if not lReg.Contains(LowerCase(lT)) then
        Inc(Result);
  finally
    lReg.Free;
  end;
end;

{ pRepo: the real repo (holds the golden files); pCheckRepo: the tree the check runs on (the
  golden repo, or a seeded copy of it). pMinFindings: the golden set must hold at least this
  many failures (a seeded repo). pMcpExpected / pNestedExpected: the exact size of each
  Delphi-only class; pNewDExpected: the exact number of check D findings on the outputs the
  PowerShell generator did not own (-1: any number above zero, a seeded tree). }
procedure TestCheckParity(const pRepo, pCheckRepo, pLevelName: string; pLevel: TCheckLevel; const pName: string;  // dl:ok too-many-parameters@8a65 -- REVIEWED 2026-10-26 (re-stamped: pProseExpected added): test helper: each parameter is one expected count of the parity comparison
  pMinFindings, pMcpExpected, pNestedExpected, pNewDExpected, pProseExpected, pDocsExpected: Integer);
var
  lFile, lMsg, lLine, lName: string;
  lPsFail, lPsNotes, lNotes, lMine, lCompared, lMissing, lExtra, lNMissing, lNExtra: TArray<string>;
  lFindings: TArray<TFinding>;
  lF: TFinding;
  lDropped, lNested, lNewD, lProse, lDocs: Integer;
  lNewDOk: Boolean;
begin
  lName := (if pName <> '' then pName else pLevelName);
  lFile := GoldenFile(pRepo, 'check\' + lName + '.json');
  lPsFail := ReadGoldenCheck(lFile, lPsNotes);
  lMsg := '';
  lMine := nil;
  lNotes := nil;
  try
    lFindings := RunCheckCommand(pCheckRepo, GoldenEngine(pRepo), pLevel, lNotes);
    for lF in lFindings do
      lMine := lMine + [ScrubTodayDate(FindingText(lF)).Replace(SCRATCH, FROZEN_SCRATCH)];
  except
    on E: Exception do
      lMsg := E.ClassName + ': ' + E.Message;
  end;
  lCompared := WithoutDelphiOnly(lMine, lDropped, lNested, lNewD, lProse, lDocs);
  CompareFindingSets(lPsFail, lCompared, lMissing, lExtra);
  CompareFindingSets(lPsNotes, lNotes, lNMissing, lNExtra);
  Writeln('INFO check ', lName, ': golden ', Length(lPsFail), ' failure(s) / ', Length(lPsNotes), ' note(s); featuregen ',
    Length(lMine), ' (', lDropped, ' Delphi-only MCP, expected ', pMcpExpected, '; ', lNested, ' nested schema, expected ',
    pNestedExpected, '; ', lNewD, ' D on new outputs, expected ', pNewDExpected, '; ', lProse, ' prose, expected ', pProseExpected,
    '; ', lDocs, ' docs C1-C3 (Delphi-only; not pinned when expected is -1: the count follows the live engine --help), expected ', pDocsExpected, ') / ', Length(lNotes));
  for lLine in lMine do
    Writeln('INFO   finding: ', lLine.Split([#10])[0]);
  for lLine in lNotes do
    Writeln('INFO   note: ', lLine);
  lNewDOk := (if pNewDExpected < 0 then lNewD > 0 else ExclusionCountOk(lNewD, pNewDExpected));
  Check('Check.ParityWithGolden.' + lName, (lMsg = '') and TFile.Exists(lFile) and (Length(lPsFail) >= pMinFindings)  // dl:ok boolean-expression-complexity@8137 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
    and ExclusionCountOk(lDropped, pMcpExpected) and ExclusionCountOk(lNested, pNestedExpected) and lNewDOk
    and ExclusionCountOk(lProse, pProseExpected) and ((pDocsExpected < 0) or ExclusionCountOk(lDocs, pDocsExpected))
    and (Length(lMissing) = 0) and (Length(lExtra) = 0) and (Length(lNMissing) = 0) and (Length(lNExtra) = 0),
    lMsg + ' missing: ' + string.Join(' | ', Copy(lMissing, 0, 5)) + ' // extra: ' + string.Join(' | ', Copy(lExtra, 0, 5))  // dl:ok magic-literal@51d8 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    + ' // notes missing: ' + string.Join(' | ', lNMissing) + ' // notes extra: ' + string.Join(' | ', lNExtra));
end;

procedure ReplaceInFile(const pFile, pOld, pNew: string);
var
  lT: string;
begin
  lT := ReadBytesText(pFile);
  if Pos(pOld, lT) = 0 then
    raise Exception.CreateFmt('seed anchor not found in %s: %s', [pFile, pOld]);  // dl:ok raise-bare-exception@47a3 -- REVIEWED 2026-10-19: test helper; the message is the diagnostic
  TFile.WriteAllText(pFile, lT.Replace(pOld, pNew), TEncoding.ASCII);
end;

{ A scratch copy of the golden repo with seeded faults, so the parity comparison runs on a
  NON-EMPTY golden set (the real repo has none). }
function SeededRepo(const pRepo: string): string;
var
  lDst, lRel: string;
begin
  lDst := FreshDir('seeded-repo');
  for lRel in ['features', 'docs\wiki', 'charts\src', 'tests\autotest\lib', 'WWW\help\dl', 'docs\Images'] do
    TDirectory.Copy(TPath.Combine(pRepo, lRel), TPath.Combine(lDst, lRel));
  for lRel in ['README.md', 'CHANGELOG.md', 'docs\AI-USAGE.md', 'build\pack-lint-release.ps1',
    'tests\autotest\run_docs_sync_guard.ps1',
    'src\cli\DRagLint.CLI.pas', 'src\mcp\DRagLint.MCP.Server.pas', 'src\core\DRagLint.Core.Model.pas',
    'src\storage\DRagLint.Storage.Schema.pas', 'src\delphi-plugin\DragLint.Plugin.Editor.pas',
    'src\delphi-plugin\DragLint.Plugin.AboutForm.pas', 'src\delphi-plugin\DragLint.Plugin.ReportText.pas',
    'src\delphi-plugin\DragLint.Plugin.StructureForm.pas', 'src\delphi-plugin\DragLint.Plugin.ProjectMenu.pas'] do
    CopyFileTo(pRepo, lDst, lRel);
  // A: summary period, unknown key (also non-canonical)
  ReplaceInFile(TPath.Combine(lDst, 'features\entries\ask.json'), '"audience": "both"', '"audience": "both", "zzKey": "x"');
  // C: dangling cli verb, mcp tool and menu leaf; A: since not a CHANGELOG version
  TFile.WriteAllText(TPath.Combine(lDst, 'features\entries\zz-dangling.json'),
    '{'#13#10'  "id": "zz-dangling",'#13#10'  "title": "Dangling probe",'#13#10'  "group": "maintenance",'#13#10
    + '  "owner": "CONVERTER",'#13#10'  "status": "shipped",'#13#10'  "since": "9.9.9",'#13#10
    + '  "summary": "A probe whose surfaces are all gone.",'#13#10'  "intro": "Probe.",'#13#10'  "wikiPage": "Hom",'#13#10
    // nested schema violation (a flags item without "name"): Delphi-only, 1 finding
    + '  "surfaces": [ { "type": "cli", "verb": "zz-gone", "flags": [ { "arg": "x" } ] },{ "type": "mcp", "tool": "zz_gone" }, { "type": "ide-menu", "path": "drag-lint > Zz Gone Away" } ],'#13#10
    + '  "audience": "both",'#13#10'  "related": ["ask", "zz-nope"],'#13#10
    + '  "lastVerified": { "date": "2026-01-01", "by": "probe", "build": "9.9.9" }'#13#10'}'#13#10, TEncoding.ASCII);
  // B: a --help verb loses its entry (and A: the seed backlog names a missing entry)
  TFile.Delete(TPath.Combine(lDst, 'features\entries\outline.json'));
  // B: a stale caption exemption
  ReplaceInFile(TPath.Combine(lDst, 'features\exemptions.json'), '"captions": {', '"captions": {'#13#10'    "Zz Stale Exemption": "probe",');
  // D: a hand edit of a generated page
  ReplaceInFile(TPath.Combine(lDst, 'docs\wiki\Quick-Help.md'), '## Declared, not harvested', '## Declared, not harvestec');
  Result := lDst;
end;

function HasFinding(const pFindings: TArray<TFinding>; pCheck: Char; const pPart: string): Boolean;
var
  lF: TFinding;
begin
  Result := False;
  for lF in pFindings do
    if (lF.Check = pCheck) and (Pos(pPart, lF.Text) > 0) then
      Exit(True);
end;

function FindingsNaming(const pFindings: TArray<TFinding>; const pPart: string): string;
var
  lF: TFinding;
begin
  Result := '';
  for lF in pFindings do
    if Pos(pPart, lF.Text) > 0 then
      Result := Result + FindingText(lF).Split([#10])[0] + ' | ';
end;

{ Task 11: check D covers EVERY generated output, and its hints name featuregen commands. }
procedure TestCheckDCoversAllOutputs(const pRepo: string);
var
  lDst, lText, lAll: string;
  lNotes: TArray<string>;
  lF: TArray<TFinding>;
  lFinding: TFinding;
  lClean, lJ: Integer;
begin
  lDst := TPath.Combine(FreshDir('d-all-outputs'), 'r');
  TDirectory.Copy(GoldenRepo(pRepo), lDst);
  lF := RunCheckCommand(lDst, GoldenEngine(pRepo), clFull, lNotes);
  lClean := 0;
  for lFinding in lF do
    if lFinding.Check = 'D' then
      Inc(lClean);
  Check('Check.DCleanOnRefreshedCopy', lClean = 0, IntToStr(lClean) + ' D finding(s) on a freshly rendered copy');
  for lJ := 0 to 2 do
    case lJ of
      0: TFile.AppendAllText(TPath.Combine(lDst, 'features\generated\cli-reference.md'), 'x', TEncoding.ASCII);  // dl:ok case-magic-numbers@f15e -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
      1: TFile.AppendAllText(TPath.Combine(lDst, 'WWW\help\dl\cli.md'), 'x', TEncoding.ASCII);  // dl:ok case-magic-numbers@89a8 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    else
      TFile.AppendAllText(TPath.Combine(lDst, 'features\generated\site-pages.json'), ' ', TEncoding.ASCII);
    end;
  TFile.WriteAllText(TPath.Combine(lDst, 'WWW\help\dl\zz-stale.md'), 'stale'#13#10, TEncoding.ASCII);
  lText := ReadBytesText(TPath.Combine(lDst, 'features\entries\ask.json'));
  TFile.WriteAllText(TPath.Combine(lDst, 'features\entries\ask.json'), lText.Replace(#13#10, #10), TEncoding.ASCII);
  lF := RunCheckCommand(lDst, GoldenEngine(pRepo), clFull, lNotes);
  lAll := '';
  for lFinding in lF do
    lAll := lAll + FindingText(lFinding) + #10;
  Check('Check.DFailsOnStaleCliReference', HasFinding(lF, 'D', 'features\generated\cli-reference.md differs'), lAll);
  Check('Check.DFailsOnStaleSiteFile', HasFinding(lF, 'D', 'WWW\help\dl\cli.md differs'), lAll);
  Check('Check.DFailsOnStaleSitePagesJson', HasFinding(lF, 'D', 'features\generated\site-pages.json differs'), lAll);
  Check('Check.DFailsOnStrayFileInSiteRoot', HasFinding(lF, 'D', 'WWW\help\dl\zz-stale.md differs'), lAll);
  Check('Check.HintsNameFeaturegen', HasFinding(lF, 'D', 'run featuregen build --all') and HasFinding(lF, 'A', 'run featuregen normalise')
    and (Pos('build-feature-pages', lAll) = 0) and (Pos('feature-registry.ps1', lAll) = 0), lAll);
end;
{ P7: the generated verb reference must be what the registry says; a stale unit on disk fails. }
function SameLf(const pA, pB: string): Boolean;
begin
  Result := pA.Replace(#13#10, #10) = pB.Replace(#13#10, #10);
end;

{ P7: no help prose is LOST. Every line of the frozen verb reference (hand-written 1.33.0 banner, re-frozen 2026-10-23 from the
  registry after deliberate edits: N-02 --rule, lsp C1/C4, cycles, PROGRESS, convert-apply) must appear in what the registry generates,
  verbatim and in the same order; NEW lines may be inserted anywhere (a new flag line, a new verb). A changed or dropped frozen line
  fails: a deliberate edit re-freezes that line in the fixture in the same commit. Golden data versus the registry render: no exe is
  read, so the result does not depend on which drag-lint.exe is deployed. Returns '' or the first problem. }
function FrozenBannerPrefixProblem(const pRepo: string): string;
var
  lReg: TRegistry;
  lGen: TArray<string>;
  lFrozen: TArray<string>;
  lI, lG, lFrom: Integer;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lGen := VerbReferenceLines(lReg);
  finally
    lReg.Free;
  end;
  lFrozen := TFile.ReadAllText(TPath.Combine(pRepo, 'src\tools\featuregen\tests\fixtures\help-verb-reference-1.33.0.txt'), TEncoding.ASCII)
    .Replace(#13#10, #10).TrimRight([#10]).Split([#10]);
  lG := 0;
  for lI := 0 to High(lFrozen) do
  begin
    lFrom := lG;
    while (lG <= High(lGen)) and (lGen[lG] <> lFrozen[lI]) do
      Inc(lG);
    if lG > High(lGen) then
      Exit(Format('frozen line %d changed or dropped (not found in order after generated line %d): [%s]', [lI + 1, lFrom, lFrozen[lI]]));
    Inc(lG);
  end;
  Result := '';
end;
{ Equal helpOrder must sort the same whatever the insertion order (TList.Sort is unstable): tiebreak is the entry id, ordinal. }
function SortedIds(const pRows: array of TRow): string;
var
  lList: TList<TRow>;
  lRow: TRow;
begin
  lList := TList<TRow>.Create;
  try
    lList.AddRange(pRows);
    lList.Sort(TComparer<TRow>.Construct(CompareRows));
    Result := '';
    for lRow in lList do
      Result := Result + lRow.Id + ';';
  finally
    lList.Free;
  end;
end;
procedure TestHelpOrderTiebreak;
var
  lA, lB, lC: TRow;
begin
  lA := Default(TRow);
  lA.Id := 'menu-tree';
  lA.Order := 96;
  lA.EntryIndex := 2;
  lB := lA;
  lB.Id := 'register-project';
  lB.EntryIndex := 1;
  lC := lA;
  lC.Id := 'Zeta';
  lC.EntryIndex := 0;
  Check('Help.EqualOrderTiebreakNotZero', CompareRows(lA, lB) <> 0, 'equal helpOrder must not compare equal');
  Check('Help.EqualOrderSameInEitherInsertionOrder', SortedIds([lA, lB, lC]) = SortedIds([lC, lB, lA]), SortedIds([lA, lB, lC]) + ' vs ' + SortedIds([lC, lB, lA]));
  Check('Help.EqualOrderIdIsOrdinal', SortedIds([lA, lB, lC]) = 'Zeta;menu-tree;register-project;', SortedIds([lA, lB, lC]));
end;
procedure TestHelpText(const pRepo: string);
var
  lReg: TRegistry;
  lGen, lDisk: string;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lGen := RenderHelpTextUnit(lReg);
  finally
    lReg.Free;
  end;
  lDisk := TFile.ReadAllText(TPath.Combine(pRepo, HELPTEXT_UNIT_PATH), TEncoding.ASCII);
  Check('Help.GeneratedUnitMatchesRegistry', SameLf(lGen, lDisk), 'run featuregen build --all');
  Check('Help.GeneratedUnitDetectsDrift', not SameLf(lGen, lDisk.Replace('drag-lint outline', 'drag-lint outlinX')), 'positive control');
  Check('Help.GeneratedUnitCarriesOutline', Pos('''  drag-lint outline  ', lGen) > 0, 'usage line of a known verb');
  { X-26: per-verb help (menu-tree --help) comes from the same registry lines; positive control = a verb with no block gets no branch. }
  Check('Help.PerVerbBranchForMenuTree', Pos('if pVerb = ''menu-tree'' then', lGen) > 0, 'WriteVerbHelp must carry a menu-tree branch');
  Check('Help.PerVerbBranchCarriesHelpLine', Pos('  drag-lint menu-drift --project', Copy(lGen, Pos('if pVerb = ''menu-drift'' then', lGen), MaxInt)) > 0, 'menu-drift branch carries its help line');
  Check('Help.PerVerbNoBranchWithoutBlock', Pos('if pVerb = ''zz-not-a-verb'' then', lGen) = 0, 'negative check: a verb with no help block gets no branch');
  Check('Help.FrozenBannerPreserved', FrozenBannerPrefixProblem(pRepo) = '', FrozenBannerPrefixProblem(pRepo)
    + ' (a deliberate help edit re-freezes that line in tests\fixtures\help-verb-reference-1.33.0.txt)');
  Check('Help.GeneratedUnitIsAscii', not TRegEx.IsMatch(lGen, '[^\x00-\x7F]'), 'non-ASCII in the generated unit');
  { FLAG lane: the alias policy (docs\CLI-FLAG-ALIASES.md) -- one generated "Flag aliases:" section, canonical-only verb lines. }
  Check('Help.FlagAliasesProcedure', Pos('procedure WriteFlagAliases;', lGen) > 0, 'WriteFlagAliases must be generated');
  Check('Help.FlagAliasesHeader', Pos('Writeln(''Flag aliases:'');', lGen) > 0, 'section header (the scanners stop the last verb block on it)');
  Check('Help.FlagAliasRowForOutput', TRegEx.IsMatch(lGen, 'Writeln\(''  --output +also: --out''\);'), 'row: --output also: --out');
  Check('Help.FlagAliasRowForIn', TRegEx.IsMatch(lGen, 'Writeln\(''  --in +also: --file''\);'), 'row: --in also: --file');
end;

{ FLAG lane: FlagAliasProblems -- the alias table is well-formed and no registry cli surface names an alias. }
procedure TestFlagAliasPolicy(const pRepo: string);
var
  lReg: TRegistry;
  lA: TArray<TFlagAlias>;
  lE: TArray<TFeatureEntry>;
  lP: TArray<string>;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    Check('Alias.TableLoaded', Length(lReg.FlagAliases) > 1, IntToStr(Length(lReg.FlagAliases)) + ' row(s) -- else the checks below are vacuous');
    lP := FlagAliasProblems(lReg.FlagAliases, lReg.Entries);
    Check('Alias.RegistryClean', Length(lP) = 0, string.Join(' | ', lP));
  finally
    lReg.Free;
  end;
  SetLength(lA, 1);
  lA[0].Canonical := '--zz-canon';
  lA[0].Aliases := ['--zz-short'];
  SetLength(lE, 1);
  lE[0].Id := 'zz-entry';
  SetLength(lE[0].Surfaces, 1);
  lE[0].Surfaces[0].Kind := 'cli';
  lE[0].Surfaces[0].Verb := 'zz-verb';
  lE[0].Surfaces[0].Usage := 'drag-lint zz-verb [--zz-canon <f>] [--zz-canonical-not-an-alias]';
  Check('Alias.ControlCleanSurfacePasses', Length(FlagAliasProblems(lA, lE)) = 0, string.Join(' | ', FlagAliasProblems(lA, lE)));
  lE[0].Surfaces[0].Help := ['  drag-lint zz-verb [--zz-short <f>]'];
  lP := FlagAliasProblems(lA, lE);
  Check('Alias.AliasOnHelpLineReported', (Length(lP) = 1) and (Pos('--zz-short', lP[0]) > 0) and (Pos('--zz-canon', lP[0]) > 0), string.Join(' | ', lP));
  lE[0].Surfaces[0].Help := nil;
  SetLength(lE[0].Surfaces[0].Flags, 1);
  lE[0].Surfaces[0].Flags[0].Name := '--zz-short';
  Check('Alias.AliasInFlagsReported', Length(FlagAliasProblems(lA, lE)) = 1, string.Join(' | ', FlagAliasProblems(lA, lE)));
  lE[0].Surfaces[0].Flags := nil;
  SetLength(lA, 2);
  lA[1].Canonical := '--zz-short';
  lA[1].Aliases := ['--zz-other'];
  Check('Alias.AliasThatIsAlsoCanonicalReported', Length(FlagAliasProblems(lA, lE)) = 1, string.Join(' | ', FlagAliasProblems(lA, lE)));
end;
{ Runs the full check with one extra live item; the live surface is restored after. }
procedure TestPositiveControls(const pRepo: string);
var
  lLive: TLiveSurface;
  lReg: TRegistry;
  lSaved: TArray<string>;
  lF: TArray<TFinding>;
  lNotes: TArray<string>;
begin
  lLive := SharedLive(pRepo);
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lSaved := lLive.HelpVerbs;
    lLive.HelpVerbs := lLive.HelpVerbs + ['zz-not-a-verb'];
    try
      lF := RunChecks(lReg, lLive, clFull, nil, True, lNotes);
    finally
      lLive.HelpVerbs := lSaved;
    end;
    { A verb only --help lists is NOT compared: a generated --help could never fail that comparison. }
    Check('Check.HelpOnlyVerbIsNotCompared', not HasFinding(lF, 'B', 'unregistered: ''zz-not-a-verb'''), FindingsNaming(lF, 'zz-'));
    { P7: B/C compare the registry with the DISPATCH table, never with --help (a generated --help cannot fail). }
    lSaved := lLive.DispatchVerbs;
    lLive.DispatchVerbs := lLive.DispatchVerbs + ['zz-dispatch-verb'];
    try
      lF := RunChecks(lReg, lLive, clFull, nil, True, lNotes);
    finally
      lLive.DispatchVerbs := lSaved;
    end;
    Check('Check.DispatchVerbUnregisteredFails', HasFinding(lF, 'B', 'unregistered: ''zz-dispatch-verb'''), FindingsNaming(lF, 'zz-'));
    lSaved := lLive.Captions;
    lLive.Captions := lLive.Captions + ['Zz Not A Real Menu Item'];
    try
      lF := RunChecks(lReg, lLive, clFull, nil, True, lNotes);
    finally
      lLive.Captions := lSaved;
    end;
    Check('Check.UnregisteredCaptionFails', HasFinding(lF, 'B', 'unregistered: ''Zz Not A Real Menu Item'''), FindingsNaming(lF, 'Zz'));
    lSaved := lLive.McpTools;
    lLive.McpTools := lLive.McpTools + ['zz_probe_tool'];
    try
      lF := RunChecks(lReg, lLive, clFull, nil, True, lNotes);
    finally
      lLive.McpTools := lSaved;
    end;
    Check('Check.UnregisteredMcpToolFails', HasFinding(lF, 'B', 'unregistered: ''zz_probe_tool'''), FindingsNaming(lF, 'zz_'));
  finally
    lReg.Free;
  end;
end;

function MenuRow(const pPath, pKind, pHandler: string): TMenuNodeRow;
begin
  Result.Path := pPath;
  Result.Kind := pKind;
  Result.Handler := pHandler;
  Result.Source := 'Zz.pas:1';
  Result.Confidence := 'certain';
  Result.Caption := pPath;
  if Pos(' > ', pPath) > 0 then
    Result.Caption := Copy(pPath, LastDelimiter('>', pPath) + 2, MaxInt);
end;

function MenuProbe(const pId, pPath: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(
    '{"id": "' + pId + '", "title": "Menu probe", "group": "maintenance", "owner": "CONVERTER", "status": "shipped",'
    + ' "since": "1.0.0", "summary": "A probe entry registered at a menu path",'
    + ' "intro": "Probe.", "wikiPage": "Home",'
    + ' "surfaces": [ { "type": "ide-menu", "path": "' + pPath + '" } ],'
    + ' "audience": "both", "lastVerified": { "date": "2026-10-19", "by": "test", "build": "1.0.0" } }') as TJSONObject;
end;

{ FG-M item 2: with the menu TREE present, checks B and C compare full PATHS, so a moved item
  fails -- a leaf-only comparison (the regex era) could not see it. The probe leaf is added
  to the flat Captions too, exactly what the regex harvest would have seen, so the only
  thing that can make these findings is the path comparison. }
procedure TestMenuPathChecks(const pRepo: string);
var
  lLive: TLiveSurface;
  lReg: TRegistry;
  lMoved, lRight: TJSONObject;
  lF: TArray<TFinding>;
  lNotes: TArray<string>;
  lSavedCaps: TArray<string>;
  lSavedNodes: TArray<TMenuNodeRow>;
  lSavedSource: string;
begin
  lLive := SharedLive(pRepo);
  lReg := TRegistry.Create;
  lMoved := MenuProbe('zz-menu-moved', 'drag-lint > Zz Probe Sub > Zz Probe Item');
  lRight := MenuProbe('zz-menu-right', 'drag-lint > Zz Other Sub > Zz Right Item');
  try
    lReg.Load(pRepo);
    lSavedCaps := lLive.Captions;
    lSavedNodes := lLive.MenuNodes;
    lSavedSource := lLive.MenuSource;
    lLive.MenuSource := MENU_SOURCE_TREE;
    lLive.MenuNodes := lLive.MenuNodes + [MenuRow('drag-lint > Zz Other Sub', 'submenu', ''),
      MenuRow('drag-lint > Zz Other Sub > Zz Probe Item', MENU_KIND_ITEM, 'Zz.Probe'),
      MenuRow('drag-lint > Zz Other Sub > Zz Right Item', MENU_KIND_ITEM, 'Zz.Right')];
    lLive.Captions := lLive.Captions + ['Zz Other Sub', 'Zz Probe Item', 'Zz Right Item'];
    try
      lF := RunChecks(lReg, lLive, clFull, [lMoved, lRight], True, lNotes);
    finally
      lLive.Captions := lSavedCaps;
      lLive.MenuNodes := lSavedNodes;
      lLive.MenuSource := lSavedSource;
    end;
    Check('Check.MovedMenuItemFailsC',
      HasFinding(lF, 'C', 'zz-menu-moved: ide-menu ''drag-lint > Zz Probe Sub > Zz Probe Item'' moved -- now at ''drag-lint > Zz Other Sub > Zz Probe Item'''),
      FindingsNaming(lF, 'zz-menu-moved'));
    Check('Check.UnregisteredMenuPathFailsB', HasFinding(lF, 'B', 'unregistered: ''drag-lint > Zz Other Sub > Zz Probe Item'''), FindingsNaming(lF, 'Zz Probe Item'));
    Check('Check.RegisteredMenuPathPasses', not HasFinding(lF, 'C', 'zz-menu-right') and not HasFinding(lF, 'B', 'Zz Right Item'), FindingsNaming(lF, 'Zz Right'));
    Check('Check.SubmenuIsNeverUnregistered', not HasFinding(lF, 'B', 'unregistered: ''drag-lint > Zz Other Sub'''), FindingsNaming(lF, 'Zz Other Sub'''));
  finally
    lRight.Free;
    lMoved.Free;
    lReg.Free;
  end;
end;

function PlannedProbe(const pStatus: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(
    '{"id": "zz-planned-probe", "title": "Planned probe", "group": "maintenance", "owner": "CONVERTER", "status": "' + pStatus + '",'
    + ' "since": "1.0.0", "summary": "A probe entry whose surfaces are not live yet",'
    + ' "intro": "Probe.", "wikiPage": "Home",'
    + ' "surfaces": [ { "type": "cli", "verb": "zz-planned-verb" }, { "type": "mcp", "tool": "zz_planned_tool" } ],'
    + ' "audience": "both", "lastVerified": { "date": "2026-10-19", "by": "test", "build": "1.0.0" } }') as TJSONObject;
end;

procedure TestPlannedSkipsLive(const pRepo: string);
var
  lLive: TLiveSurface;
  lReg: TRegistry;
  lE: TJSONObject;
  lF: TArray<TFinding>;
  lNotes: TArray<string>;
  lPlannedNote: Boolean;
  lN: string;
begin
  lLive := SharedLive(pRepo);
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lE := PlannedProbe('planned');
    try
      lF := RunChecks(lReg, lLive, clFull, [lE], True, lNotes);
    finally
      lE.Free;
    end;
    lPlannedNote := False;
    for lN in lNotes do
      if lN = 'planned, surfaces not checked: zz-planned-probe' then
        lPlannedNote := True;
    Check('Check.PlannedSkipsLive', lPlannedNote and not HasFinding(lF, 'C', 'zz-planned-probe'), FindingsNaming(lF, 'zz-planned'));
    lE := PlannedProbe('shipped');
    try
      lF := RunChecks(lReg, lLive, clFull, [lE], True, lNotes);
    finally
      lE.Free;
    end;
    Check('Check.ShippedProbeChecksLive', HasFinding(lF, 'C', 'zz-planned-probe: cli verb ''zz-planned-verb'' is not dispatched by the CLI')
      and HasFinding(lF, 'C', 'zz-planned-probe: mcp tool ''zz_planned_tool'' is not in HandleToolsList'), FindingsNaming(lF, 'zz-planned'));
  finally
    lReg.Free;
  end;
end;

procedure TestWellFormedCatchesBadEntry(const pRepo: string);
var
  lReg: TRegistry;
  lE: TJSONObject;
  lF: TArray<TFinding>;
  lNotes: TArray<string>;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lE := PlannedProbe('bogus');
    try
      lF := RunChecks(lReg, nil, clWellFormed, [lE], True, lNotes);
    finally
      lE.Free;
    end;
    Check('Check.WellFormedNeedsNoLiveAndCatchesBadStatus', HasFinding(lF, 'A', 'zz-planned-probe.json: schema: ')
      and HasFinding(lF, 'A', 'at ''/status'''), FindingsNaming(lF, 'zz-planned'));
  finally
    lReg.Free;
  end;
end;

{ ---- Task 9: registry edit commands (run on a scratch COPY of the repo's registry, never on features\) ---- }

function CmdRepo(const pRepo, pName: string): string;
var
  lRel: string;
begin
  Result := FreshDir(pName);
  for lRel in ['features', 'docs\wiki'] do
    TDirectory.Copy(TPath.Combine(pRepo, lRel), TPath.Combine(Result, lRel));
  // run_docs_sync_guard.ps1: LoadSiteFormat (audit) reads its $UndocumentedOnPurpose block
  for lRel in ['CHANGELOG.md', 'src\core\DRagLint.Core.Model.pas', 'src\delphi-plugin\DragLint.Plugin.ReportText.pas',
    'tests\autotest\run_docs_sync_guard.ps1'] do
    CopyFileTo(pRepo, Result, lRel);
end;

function RunCmd(const pVerb: string; const pArgs: TArray<string>; out pText: string): Integer;
var
  lSb: TStringBuilder;
begin
  lSb := TStringBuilder.Create;
  try
    Result := RunRegistryCommand(pVerb, pArgs, '',
      procedure(const pLine: string)
      begin
        lSb.AppendLine(pLine);
      end);
    pText := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

function AddProbeArgs(const pCopy: string; const pGroup: string = 'maintenance'; const pOwner: string = 'CONVERTER'): TArray<string>;
begin
  Result := ['--repo', pCopy, '--id', 'zz-probe', '--title', 'Probe entry', '--group', pGroup, '--owner', pOwner,
    '--summary', 'A probe entry for the edit command tests', '--intro', 'Probe intro.', '--wiki-page', 'Home',
    '--surface', 'cli:zz-verb/sub|zz-verb sub --x ;; shortcut:Ctrl+Alt+Z', '--related', 'outline,ask,outline',
    '--aliases', 'bb,aa,bb', '--by', 'tester'];
end;

procedure TestCmdAdd(const pRepo: string);
var
  lCopy, lOut, lFile, lRaw: string;
  lExit: Integer;
  lVal: TJSONValue;
  lReg: TRegistry;
  lF: TArray<TFinding>;
begin
  lCopy := CmdRepo(pRepo, 'cmd-add');
  lExit := RunCmd('add', AddProbeArgs(lCopy), lOut);
  lFile := TPath.Combine(lCopy, 'features\entries\zz-probe.json');
  Check('Cmd.AddWritesCanonical.exit', (lExit = 0) and TFile.Exists(lFile), IntToStr(lExit) + ' ' + lOut);
  if not TFile.Exists(lFile) then
    Exit;
  lRaw := ReadBytesText(lFile);
  lVal := ReadJsonFile(lFile);
  try
    Check('Cmd.AddWritesCanonical.bytes', lRaw = CanonicalJson(lVal, EntryKeyOrder(TPath.Combine(lCopy, 'features\schema\entry.schema.json'))), lRaw);
  finally
    lVal.Free;
  end;
  // CanonicalJson paths pinned through add: related / aliases deduped and sorted, surface keys in schema order,
  // defaults (status, audience, since, lastVerified) filled, unset optional keys absent.
  Check('Cmd.AddWritesCanonical.dedupeSorted', (Pos('"related": ["ask", "outline"]', lRaw) > 0) and (Pos('"aliases": ["aa", "bb"]', lRaw) > 0), lRaw);
  Check('Cmd.AddWritesCanonical.surfaceOrder', Pos('"type": "cli",'#13#10'      "verb": "zz-verb",'#13#10'      "sub": "sub",'#13#10'      "example": "zz-verb sub --x"', lRaw) > 0, lRaw);
  Check('Cmd.AddWritesCanonical.defaults', (Pos('"status": "shipped"', lRaw) > 0) and (Pos('"audience": "both"', lRaw) > 0)
    and (Pos('"by": "tester"', lRaw) > 0) and (Pos('"notes"', lRaw) = 0), lRaw);
  // Defect (H-ENG-D): add stamped the legacy lastVerified; it must write verified (the shipped-entry stamp).
  Check('Cmd.AddWritesVerifiedNotLegacy', (Pos('"verified": {', lRaw) > 0) and (Pos('"lastVerified"', lRaw) = 0), lRaw);
  lReg := TRegistry.Create;
  try
    lReg.Load(lCopy);
    lF := RunChecks(lReg, nil, clWellFormed);
    Check('Cmd.AddWritesCanonical.wellFormed', FindingsNaming(lF, 'zz-probe') = '', FindingsNaming(lF, 'zz-probe'));
  finally
    lReg.Free;
  end;
  lExit := RunCmd('add', AddProbeArgs(lCopy), lOut);
  Check('Cmd.AddRefusesExisting', (lExit = 1) and (Pos('already exists', lOut) > 0), lOut);
end;

procedure TestCmdAddRefusals(const pRepo: string);var
  lCopy, lOut: string;
  lExit: Integer;
  lArgs: TArray<string>;
begin
  lCopy := CmdRepo(pRepo, 'cmd-add-refuse');
  lArgs := AddProbeArgs(lCopy, 'maintenence');
  lExit := RunCmd('add', lArgs, lOut);
  Check('Cmd.AddRejectsUnknownGroup', (lExit = 1) and (Pos('nearest: maintenance', lOut) > 0)
    and not TFile.Exists(TPath.Combine(lCopy, 'features\entries\zz-probe.json')), IntToStr(lExit) + ' ' + lOut);
  lArgs := AddProbeArgs(lCopy, 'maintenance', 'CONVERTOR');
  lExit := RunCmd('add', lArgs, lOut);
  Check('Cmd.AddRejectsUnknownOwner', (lExit = 1) and (Pos('nearest: CONVERTER', lOut) > 0), IntToStr(lExit) + ' ' + lOut);
  lExit := RunCmd('add', AddProbeArgs(lCopy) + ['--title', 'Caf' + Char($E9)], lOut);  // dl:ok magic-literal@1287 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
  Check('Cmd.AddRefusesNonAscii', (lExit = 1) and (Pos('non-ASCII', lOut) > 0) and not TFile.Exists(TPath.Combine(lCopy, 'features\entries\zz-probe.json')), IntToStr(lExit) + ' ' + lOut);
  lExit := RunCmd('add', AddProbeArgs(lCopy) + ['--home-order', 'abc'], lOut);
  Check('Cmd.AddNonNumericHomeOrderIsUsageError', (lExit = 2) and not TFile.Exists(TPath.Combine(lCopy, 'features\entries\zz-probe.json')), IntToStr(lExit) + ' ' + lOut);
  lExit := RunCmd('add', ['--repo', lCopy, '--title', 'x'], lOut);
  Check('Cmd.AddNeedsId', (lExit = 1) and (Pos('--id is required', lOut) > 0), lOut);
  lExit := RunCmd('add', ['--repo', lCopy, '--bogus', 'x'], lOut);
  Check('Cmd.UnknownOptionIsUsageError', lExit = 2, lOut);
  lExit := RunCmd('add', ['--repo'], lOut);
  Check('Cmd.MissingValueIsUsageError', lExit = 2, lOut);
  // a new group + team are created atomically with the entry
  lArgs := AddProbeArgs(lCopy, 'zz-group', 'ZZTEAM');
  lExit := RunCmd('add', lArgs + ['--new-group', '--group-title', 'Zz group', '--group-summary', 'Probe group',
    '--new-team', '--team-title', 'Zz team', '--team-summary', 'Probe team'], lOut);
  Check('Cmd.AddNewGroupAndTeam', (lExit = 0) and (Pos('{ "id": "zz-group", "title": "Zz group", "order": ', ReadBytesText(TPath.Combine(lCopy, 'features\groups.json'))) > 0)
    and (Pos('{ "id": "ZZTEAM", "title": "Zz team", "order": ', ReadBytesText(TPath.Combine(lCopy, 'features\teams.json'))) > 0), lOut);
end;

procedure TestCmdUpdate(const pRepo: string);
var
  lCopy, lOut, lFile, lBefore, lRaw: string;
  lExit: Integer;
begin
  lCopy := CmdRepo(pRepo, 'cmd-update');
  RunCmd('add', AddProbeArgs(lCopy), lOut);
  lFile := TPath.Combine(lCopy, 'features\entries\zz-probe.json');
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'zz-probe', '--set', 'notes=hello ;; aliases=["zz","yy","zz"] ;; homeOrder=7'], lOut);
  lRaw := ReadBytesText(lFile);
  Check('Cmd.UpdateSetAndRemove.set', (lExit = 0) and (Pos('"notes": "hello"', lRaw) > 0) and (Pos('"aliases": ["yy", "zz"]', lRaw) > 0)
    and (Pos('"homeOrder": 7', lRaw) > 0), lOut + lRaw);
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'zz-probe', '--set', 'notes=keep ;; homeOrder='], lOut);
  lRaw := ReadBytesText(lFile);
  Check('Cmd.UpdateSetAndRemove.removeEmptyValue', (lExit = 0) and (Pos('"homeOrder"', lRaw) = 0) and (Pos('"notes": "keep"', lRaw) > 0), lOut + lRaw);
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'zz-probe', '--set', 'notes='], lOut);
  lRaw := ReadBytesText(lFile);
  Check('Cmd.UpdateSetAndRemove.remove', (lExit = 0) and (Pos('"notes"', lRaw) = 0), lOut + lRaw);
  lBefore := lRaw;
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'zz-probe', '--set', 'status=bogus'], lOut);
  Check('Cmd.UpdateRefusesInvalid', (lExit = 1) and (Pos('would not be valid; file untouched', lOut) > 0) and (ReadBytesText(lFile) = lBefore), lOut);
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'zz-nope', '--set', 'notes=x'], lOut);
  Check('Cmd.UpdateUnknownId', (lExit = 1) and (Pos('no entry', lOut) > 0), lOut);
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'zz-probe'], lOut);
  Check('Cmd.UpdateNeedsSet', (lExit = 1) and (Pos('--set field=value is required', lOut) > 0), lOut);
end;

procedure TestCmdUpdateNormalisesHandEdits(const pRepo: string);
var
  lCopy, lOut, lFile, lRaw: string;
  lExit: Integer;
begin
  // A hand-edited, non-canonical entry: empty string, unsorted + duplicated related. Any update re-writes it canonical,
  // which pins CanonicalJson's empty-drop and dedupe paths on input the real (already canonical) entries never exercise.
  lCopy := CmdRepo(pRepo, 'cmd-update-hand');
  lFile := TPath.Combine(lCopy, 'features\entries\outline.json');
  ReplaceInFile(lFile, '"audience": "both"', '"audience": "both", "notes": "", "related": ["ask", "about-and-status", "ask"]');
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'outline', '--set', 'notes=n'], lOut);
  lRaw := ReadBytesText(lFile);
  Check('Cmd.UpdateRewritesNonCanonical', (lExit = 0) and (Pos('"related": ["about-and-status", "ask"]', lRaw) > 0) and (Pos('"notes": "n"', lRaw) > 0), lOut + lRaw);
  ReplaceInFile(lFile, '"notes": "n"', '"notes": "", "pitfalls": []');
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'outline', '--set', 'homeOrder=3'], lOut);
  lRaw := ReadBytesText(lFile);
  Check('Cmd.UpdateDropsEmpty', (lExit = 0) and (Pos('"notes"', lRaw) = 0) and (Pos('"pitfalls"', lRaw) = 0) and (Pos('"homeOrder": 3', lRaw) > 0), lOut + lRaw);
end;

procedure TestCmdDeprecate(const pRepo: string);
var
  lCopy, lOut, lRaw: string;
  lExit: Integer;
begin
  lCopy := CmdRepo(pRepo, 'cmd-deprecate');
  RunCmd('add', AddProbeArgs(lCopy), lOut);
  lExit := RunCmd('deprecate', ['--repo', lCopy, '--id', 'zz-probe', '--superseded-by', 'outline', '--removed-in', '1.0.0'], lOut);
  lRaw := ReadBytesText(TPath.Combine(lCopy, 'features\entries\zz-probe.json'));
  Check('Cmd.DeprecateSetsFields', (lExit = 0) and (Pos('"status": "deprecated"', lRaw) > 0) and (Pos('"supersededBy": "outline"', lRaw) > 0)
    and (Pos('"removedIn": "1.0.0"', lRaw) > 0), lOut + lRaw);
  lExit := RunCmd('deprecate', ['--repo', lCopy], lOut);
  Check('Cmd.DeprecateNeedsId', (lExit = 1) and (Pos('--id is required', lOut) > 0), lOut);
end;

procedure TestCmdFindAndBlast(const pRepo: string);
var
  lCopy, lOut, lWith: string;
  lExit: Integer;
begin
  lCopy := CmdRepo(pRepo, 'cmd-find');
  lExit := RunCmd('find', ['--repo', lCopy, '--text', 'outline'], lOut);
  Check('Cmd.Find.hits', (lExit = 0) and (Pos('outline', lOut) > 0), lOut);
  lExit := RunCmd('find', ['--repo', lCopy, '--text', 'zz-no-such-thing-zz'], lOut);
  Check('Cmd.Find.noHitsExit1', lExit = 1, lOut);
  RunCmd('find', ['--repo', lCopy, '--text', 'unit-not-in-dpr'], lOut);
  Check('Cmd.FindIncludesChildrenFlag.without', Pos('rule.unit-not-in-dpr', lOut) = 0, lOut);
  lExit := RunCmd('find', ['--repo', lCopy, '--text', 'unit-not-in-dpr', '--include-children', '--engine', GoldenEngine(pRepo)], lWith);
  Check('Cmd.FindIncludesChildrenFlag.with', (lExit = 0) and (Pos('rule.unit-not-in-dpr', lWith) > 0), lWith);
  lExit := RunCmd('find', ['--repo', lCopy, '--text', 'x', '--json'], lOut);
  Check('Cmd.Find.json', (lExit = 0) and lOut.TrimLeft.StartsWith('[') and (Pos('"Id"', lOut) > 0), lOut);
  lExit := RunCmd('blast-radius', ['--repo', lCopy, '--menu-path', 'drag-lint > Reports'], lOut);
  Check('Cmd.BlastRadiusByMenuPath', (lExit = 0) and (Pos('ask', lOut) > 0) and (Pos('Forms for testers (CSV)...', lOut) > 0)
    and (Pos('(family chart-questions)', lOut) > 0), lOut);
  lExit := RunCmd('blast-radius', ['--repo', lCopy, '--menu-path', 'drag-lint > Zz No Such Node'], lOut);
  Check('Cmd.BlastRadiusNoHitsExit1', lExit = 1, lOut);
  lExit := RunCmd('blast-radius', ['--repo', lCopy, '--verb-name', 'outline'], lOut);
  Check('Cmd.BlastRadiusByVerb', (lExit = 0) and (Pos('cli outline', lOut) > 0), lOut);
  lExit := RunCmd('blast-radius', ['--repo', lCopy], lOut);
  Check('Cmd.BlastRadiusNeedsSelector', (lExit = 1) and (Pos('give --menu-path', lOut) > 0), lOut);
end;

procedure TestCmdMoveMenu(const pRepo: string);
var
  lCopy, lOut, lFam, lFamBefore, lAsk, lCsv: string;
  lExit: Integer;
begin
  lCopy := CmdRepo(pRepo, 'cmd-move');
  lFam := TPath.Combine(lCopy, 'features\families\chart-questions.json');
  lFamBefore := ReadBytesText(lFam);
  lExit := RunCmd('move-menu', ['--repo', lCopy, '--from', 'drag-lint > Reports', '--to', 'Elsewhere > X'], lOut);
  Check('Cmd.MoveMenuRefusesBadTarget', lExit = 1, lOut);
  lExit := RunCmd('move-menu', ['--repo', lCopy, '--from', 'drag-lint > Reports', '--to', 'drag-lint > Charts', '--what-if'], lOut);
  Check('Cmd.MoveMenuWhatIfWritesNothing', (lExit = 0) and (ReadBytesText(lFam) = lFamBefore)
    and (Pos('drag-lint > Reports"', ReadBytesText(TPath.Combine(lCopy, 'features\entries\ask.json'))) > 0), lOut);
  lExit := RunCmd('move-menu', ['--repo', lCopy, '--from', 'drag-lint > Reports', '--to', 'drag-lint > Charts'], lOut);
  lAsk := ReadBytesText(TPath.Combine(lCopy, 'features\entries\ask.json'));
  lCsv := ReadBytesText(TPath.Combine(lCopy, 'features\entries\generate-test-helper-csv.json'));
  Check('Cmd.MoveMenuRewritesAllLevels', (lExit = 0) and (Pos('"path": "drag-lint > Charts"', lAsk) > 0)
    and (Pos('"path": "drag-lint > Charts > Forms for testers (CSV)..."', lCsv) > 0) and (Pos('"path": "drag-lint > Reports', lCsv) = 0) and (Pos('"path": "drag-lint > Reports', lAsk) = 0), lOut + lCsv);
  Check('Cmd.MoveMenuRewritesFamilyInPlace', (Pos('"menuPrefix": "drag-lint > Charts"', ReadBytesText(lFam)) > 0)
    and (ReadBytesText(lFam).Replace('drag-lint > Charts', 'drag-lint > Reports') = lFamBefore), lOut);
  lExit := RunCmd('move-menu', ['--repo', lCopy, '--from', 'drag-lint > Zz Nothing', '--to', 'drag-lint > Q'], lOut);
  Check('Cmd.MoveMenuNothingToMove', (lExit = 1) and (Pos('nothing changed', lOut) > 0), lOut);
end;

procedure TestCmdNormalise(const pRepo: string);
var
  lCopy, lOut, lGroups: string;
  lExit: Integer;
begin
  lCopy := CmdRepo(pRepo, 'cmd-normalise');
  lExit := RunCmd('normalise', ['--repo', lCopy], lOut);
  Check('Cmd.NormaliseCanonicalTreeUnchanged', (lExit = 0) and (Pos('normalised 0 file(s)', lOut) > 0), lOut);
  lGroups := TPath.Combine(lCopy, 'features\groups.json');
  TFile.WriteAllText(lGroups, ReadBytesText(lGroups).Replace(' "order"', '  "order"'), TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\templates\Home.intro.md'),
    ReadBytesText(TPath.Combine(lCopy, 'features\templates\Home.intro.md')).Replace(#13#10, #10), TEncoding.ASCII);
  lExit := RunCmd('normalise', ['--repo', lCopy], lOut);
  Check('Cmd.NormaliseRepairs', (lExit = 0) and (Pos('normalised 2 file(s)', lOut) > 0) and (Pos('groups.json', lOut) > 0)
    and (Pos('Home.intro.md', lOut) > 0), lOut);
  RunCmd('normalise', ['--repo', lCopy], lOut);
  Check('Cmd.NormaliseIdempotent', Pos('normalised 0 file(s)', lOut) > 0, lOut);
end;

procedure TestCmdHomeOrderAndNull(const pRepo: string);
var
  lCopy, lOut, lFile, lBefore, lRaw: string;
  lExit: Integer;
begin
  lCopy := CmdRepo(pRepo, 'cmd-homeorder');
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'outline', '--set', 'homeOrder=3'], lOut);
  Check('Cmd.HomeOrder.setOnOutline', lExit = 0, lOut);
  lExit := RunCmd('add', AddProbeArgs(lCopy) + ['--home-order', '3'], lOut);
  Check('Cmd.AddRefusesDuplicateHomeOrder', (lExit = 1) and (Pos('homeOrder 3 is also used by outline', lOut) > 0)
    and not TFile.Exists(TPath.Combine(lCopy, 'features\entries\zz-probe.json')), IntToStr(lExit) + ' ' + lOut);
  RunCmd('add', AddProbeArgs(lCopy), lOut);
  lFile := TPath.Combine(lCopy, 'features\entries\zz-probe.json');
  lBefore := ReadBytesText(lFile);
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'zz-probe', '--set', 'homeOrder=3'], lOut);
  Check('Cmd.UpdateRefusesDuplicateHomeOrder', (lExit = 1) and (Pos('homeOrder 3 is also used by outline', lOut) > 0)
    and (ReadBytesText(lFile) = lBefore), IntToStr(lExit) + ' ' + lOut);
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'outline', '--set', 'homeOrder=3'], lOut);
  Check('Cmd.UpdateOwnHomeOrderIsNotADuplicate', lExit = 0, lOut);
  // null-drop: a null inside a surface is dropped from the written bytes
  lExit := RunCmd('update', ['--repo', lCopy, '--id', 'zz-probe', '--set', 'surfaces=[{"type":"cli","verb":"zzv","sub":null}]'], lOut);
  lRaw := ReadBytesText(lFile);
  Check('Cmd.UpdateDropsNull', (lExit = 0) and (Pos('"zzv"', lRaw) > 0) and (Pos('"sub"', lRaw) = 0) and (Pos('null', lRaw) = 0), IntToStr(lExit) + ' ' + lOut + lRaw);
end;

procedure TestCmdMoveMenuSibling(const pRepo: string);
var
  lCopy, lOut, lFile, lBefore: string;
  lExit: Integer;
begin
  lCopy := CmdRepo(pRepo, 'cmd-move-sibling');
  lExit := RunCmd('add', AddProbeArgs(lCopy) + ['--surface', 'ide-menu:drag-lint > Reports Extra > Leaf'], lOut);
  Check('Cmd.MoveMenuSibling.added', lExit = 0, lOut);
  lFile := TPath.Combine(lCopy, 'features\entries\zz-probe.json');
  lBefore := ReadBytesText(lFile);
  lExit := RunCmd('move-menu', ['--repo', lCopy, '--from', 'drag-lint > Reports', '--to', 'drag-lint > Charts'], lOut);
  Check('Cmd.MoveMenuLeavesPrefixSiblingAlone', (lExit = 0) and (ReadBytesText(lFile) = lBefore) and (Pos('zz-probe', lOut) = 0), lOut);
end;
{ ---- Task 10: audit, verify, per-page updated ---- }

function HasKind(const pFindings: TArray<TAuditFinding>; const pId, pKind: string): Boolean;
var
  lF: TAuditFinding;
begin
  Result := False;
  for lF in pFindings do
    if (lF.Id = pId) and (lF.Kind = pKind) then
      Exit(True);
end;

function AuditOf(const pRepo: string; pLive: TLiveSurface; pHelp: TLiveHelp; pToday: TDateTime): TArray<TAuditFinding>;
var
  lReg: TRegistry;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    Result := AuditRegistry(lReg, pRepo, pLive, pHelp, pToday);
  finally
    lReg.Free;
  end;
end;

procedure TestAuditThin;
var
  lCopy, lOut, lBody: string;
  lF: TArray<TAuditFinding>;
  lExit: Integer;
begin
  lCopy := CopySiteRepo('audit-thin');
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\entries\thin.json'),
    '{ "id": "thin", "title": "Thin", "group": "g-search", "owner": "ENGINE", "status": "shipped", "since": "0.1.0-alpha",'
    + ' "summary": "Thin one", "wikiPage": "Thin", "surfaces": [ { "type": "cli", "verb": "thin" } ], "audience": "both" }', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lCopy, 'docs\wiki\Thin.md'), 'Only a few words.', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\entries\fat.json'),
    '{ "id": "fat", "title": "Fat", "group": "g-search", "owner": "CHARTS", "status": "shipped", "since": "0.1.0-alpha",'
    + ' "summary": "Fat one", "wikiPage": "Fat", "surfaces": [ { "type": "cli", "verb": "fat" } ], "audience": "both" }', TEncoding.ASCII);
  lBody := StringOfChar('x', 250);  // dl:ok large-magic-number@c3f3, magic-literal@c3f3 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
  TFile.WriteAllText(TPath.Combine(lCopy, 'docs\wiki\Fat.md'), lBody, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\entries\intro.json'),
    '{ "id": "intro", "title": "Intro", "group": "g-search", "owner": "CHARTS", "status": "shipped", "since": "0.1.0-alpha",'
    + ' "summary": "Has intro", "intro": "A real introduction.", "wikiPage": "Missing-page", "surfaces": [ { "type": "cli", "verb": "intro" } ], "audience": "both" }', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\entries\gen-bare.json'),
    '{ "id": "gen-bare", "title": "Gen bare", "group": "g-search", "owner": "ENGINE", "status": "shipped", "since": "0.1.0-alpha",'
    + ' "summary": "Generated page, no intro", "wikiPage": "Features", "surfaces": [ { "type": "cli", "verb": "genbare" } ], "audience": "both" }', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\entries\gen-intro.json'),
    '{ "id": "gen-intro", "title": "Gen intro", "group": "g-search", "owner": "ENGINE", "status": "shipped", "since": "0.1.0-alpha",'
    + ' "summary": "Generated page, intro", "intro": "A real introduction.", "wikiPage": "Features", "surfaces": [ { "type": "cli", "verb": "genintro" } ], "audience": "both" }', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lCopy, 'docs\wiki\Features.md'), StringOfChar('y', 2000), TEncoding.ASCII);  // dl:ok large-magic-number@538e, magic-literal@538e -- REVIEWED 2026-10-20: test expectation: a body far over the thin limit, so only the generated-page rule can make the entry thin
  lF := AuditOf(lCopy, nil, nil, Date);
  Check('Audit.ThinWhenWikiPageIsGenerated', HasKind(lF, 'gen-bare', 'thin-leaf') and not HasKind(lF, 'gen-intro', 'thin-leaf')
    and not HasKind(lF, 'gen-bare', 'no-wiki-page'));
  Check('Audit.ThinEntryListed', HasKind(lF, 'thin', 'thin-leaf') and HasKind(lF, 'thin', 'no-usage') and HasKind(lF, 'thin', 'no-flags')
    and HasKind(lF, 'thin', 'no-questions') and not HasKind(lF, 'thin', 'no-wiki-page'));
  Check('Audit.ThinPositiveControls', not HasKind(lF, 'fat', 'thin-leaf') and not HasKind(lF, 'intro', 'thin-leaf')
    and HasKind(lF, 'intro', 'no-wiki-page') and not HasKind(lF, 'fat', 'no-wiki-page'));
  lExit := RunCmd('audit', ['--repo', lCopy, '--owner', 'ENGINE'], lOut);
  Check('Audit.CommandListsTabSeparatedAndFiltersOwner', (lExit = 0) and (Pos('thin'#9'ENGINE'#9'thin-leaf', lOut) > 0)
    and (Pos(#9'CHARTS'#9, lOut) = 0), lOut);
  lExit := RunCmd('audit', ['--repo', lCopy, '--json'], lOut);
  Check('Audit.CommandJson', (lExit = 0) and (Pos('{"id":"thin","owner":"ENGINE","kind":"thin-leaf"}', lOut) > 0), lOut);
  Check('Audit.NoAccessForCliOnlyEntry', HasKind(lF, 'gen-bare', 'no-access'));
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\entries\has-menu.json'),
    '{ "id": "has-menu", "title": "Has menu", "group": "g-search", "owner": "ENGINE", "status": "shipped", "since": "0.1.0-alpha",'
    + ' "summary": "Reachable from the IDE", "intro": "A real introduction.", "wikiPage": "Features", "surfaces": [ { "type": "ide-menu", "path": "drag-lint > Has menu" } ], "audience": "both" }', TEncoding.ASCII);
  lF := AuditOf(lCopy, nil, nil, Date);
  Check('Audit.NoAccessPositiveControl', not HasKind(lF, 'has-menu', 'no-access'));
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\entries\nf-marked.json'),
    '{ "id": "nf-marked", "title": "NF", "group": "g-search", "owner": "ENGINE", "status": "shipped", "since": "0.1.0-alpha",'
    + ' "summary": "No flags", "intro": "A real introduction.", "wikiPage": "Features", "surfaces": [ { "type": "cli", "verb": "nfmarked", "usage": "drag-lint nfmarked" } ], "audience": "both", "noFlags": true }', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\entries\nf-bare.json'),
    '{ "id": "nf-bare", "title": "NF", "group": "g-search", "owner": "ENGINE", "status": "shipped", "since": "0.1.0-alpha",'
    + ' "summary": "No flags", "intro": "A real introduction.", "wikiPage": "Features", "surfaces": [ { "type": "cli", "verb": "nfbare", "usage": "drag-lint nfbare" } ], "audience": "both" }', TEncoding.ASCII);
  lF := AuditOf(lCopy, nil, nil, Date);
  Check('Audit.NoFlagsMarkerSilencesNoFlags', not HasKind(lF, 'nf-marked', 'no-flags'));
  Check('Audit.NoFlagsMarkerNegativeControl', HasKind(lF, 'nf-bare', 'no-flags'));
end;

procedure TestCmdReviewAccess(const pRepo: string);
var
  lCopy, lOut, lRaw: string;
  lExit: Integer;
  lF: TArray<TAuditFinding>;
begin
  lCopy := CmdRepo(pRepo, 'cmd-review-access');
  RunCmd('add', AddProbeArgs(lCopy) + ['--status', 'shipped'], lOut);
  lF := AuditOf(lCopy, nil, nil, Date);
  Check('ReviewAccess.GapBeforeReview', HasKind(lF, 'zz-probe', 'no-access'), lOut);
  lExit := RunCmd('review-access', ['--repo', lCopy, '--id', 'zz-probe', '--access', 'cli-only', '--by', 'tester'], lOut);
  lF := AuditOf(lCopy, nil, nil, Date);
  lRaw := ReadBytesText(TPath.Combine(lCopy, 'features\entries\zz-probe.json'));
  Check('ReviewAccess.StampsAndClearsGap', (lExit = 0) and not HasKind(lF, 'zz-probe', 'no-access')
    and (Pos('"access": "cli-only"', lRaw) > 0) and (Pos('"accessReviewed": {', lRaw) > 0) and (Pos('"by": "tester"', lRaw) > 0), lOut + lRaw);
  lExit := RunCmd('review-access', ['--repo', lCopy, '--id', 'zz-probe', '--access', 'bogus', '--by', 'tester'], lOut);
  Check('ReviewAccess.RefusesUnknownValue', lExit <> 0, lOut);
  lExit := RunCmd('review-access', ['--repo', lCopy, '--id', 'zz-probe,zz-nope', '--access', 'repo-tooling', '--by', 'tester'], lOut);
  lRaw := ReadBytesText(TPath.Combine(lCopy, 'features\entries\zz-probe.json'));
  Check('ReviewAccess.UnknownIdChangesNothing', (lExit <> 0) and (Pos('"access": "cli-only"', lRaw) > 0), lOut);
end;

procedure TestAuditVerify(const pRepo: string);
const
  HELP_A = '  drag-lint outline --file <U.pas> [--db <d>]'#10'  drag-lint ask   <q> [--db <d>]'#10;
  HELP_B = '  drag-lint outline --file <U.pas> [--db <d>] [--new-flag]'#10'  drag-lint ask   <q> [--db <d>]'#10;
var
  lCopy, lOut, lFile, lRaw: string;
  lHelpA, lHelpB: TLiveHelp;
  lLive: TLiveSurface;
  lF: TArray<TAuditFinding>;
  lVal, lVer: TJSONValue;
  lReg: TRegistry;
  lE: TFeatureEntry;
  lExit: Integer;
  lHash: string;
begin
  lCopy := CmdRepo(pRepo, 'audit-verify');
  lHelpA := TLiveHelp.Create;
  lHelpB := TLiveHelp.Create;
  lLive := TLiveSurface.Create;
  try
    lHelpA.LoadFromText(HELP_A);
    lHelpB.LoadFromText(HELP_B);
    lLive.ProductVersion := '9.9.9-test';
    // 'ask' is verified against the REAL help in the live registry; re-stamp it against this test's help so only 'outline' changes.
    VerifyEntryWith(lCopy, 'ask', 'tester', '2026-10-19', lLive, lHelpA);
    lFile := VerifyEntryWith(lCopy, 'outline', 'tester', '2026-10-19', lLive, lHelpA);
    lVal := ReadJsonFile(lFile);
    try
      lVer := TJSONObject(lVal).GetValue('verified');
      lHash := Prop(lVer, 'surfaceHash');
      Check('Verify.RecordsHashAndBuild', (Prop(lVer, 'date') = '2026-10-19') and (Prop(lVer, 'by') = 'tester')
        and (Prop(lVer, 'build') = '9.9.9-test') and (Length(lHash) = 64) and TRegEx.IsMatch(lHash, '^[0-9a-f]{64}$'), lHash);  // dl:ok magic-literal@a37b -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    finally
      lVal.Free;
    end;
    lReg := TRegistry.Create;
    try
      lReg.Load(lCopy);
      for lE in lReg.Entries do
        if lE.Id = 'outline' then
          Check('Verify.HashMatchesSurfaceHash', (lE.VerifiedSurfaceHash = lHash)
            and (SurfaceHash(lE, lLive, lHelpA) = lHash) and (SurfaceHash(lE, lLive, lHelpB) <> lHash), lHash);
    finally
      lReg.Free;
    end;
    lRaw := ReadBytesText(lFile);
    lVal := ReadJsonFile(lFile);
    try
      Check('Verify.FileStaysCanonical', lRaw = CanonicalJson(lVal, EntryKeyOrder(TPath.Combine(lCopy, 'features\schema\entry.schema.json'))), lRaw);
    finally
      lVal.Free;
    end;
    lF := AuditOf(lCopy, lLive, lHelpA, EncodeDate(2026, 10, 20));  // dl:ok magic-literal@d4ab -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    Check('Audit.SurfaceUnchangedIsQuiet', not HasKind(lF, 'outline', 'surface-changed') and not HasKind(lF, 'outline', 'stale-verified'));
    lF := AuditOf(lCopy, lLive, lHelpB, EncodeDate(2026, 10, 20));  // dl:ok magic-literal@1874 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    Check('Audit.SurfaceChangedAfterVerify', HasKind(lF, 'outline', 'surface-changed') and not HasKind(lF, 'ask', 'surface-changed'));
    lF := AuditOf(lCopy, lLive, lHelpA, EncodeDate(2027, 1, 17));  // dl:ok magic-literal@7ef2 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    Check('Audit.StaleVerifiedBoundary.day90', not HasKind(lF, 'outline', 'stale-verified'));
    lF := AuditOf(lCopy, lLive, lHelpA, EncodeDate(2027, 1, 18));  // dl:ok magic-literal@d053 -- REVIEWED 2026-10-19: test expectation: the literal is the asserted value
    Check('Audit.StaleVerifiedBoundary.day91', HasKind(lF, 'outline', 'stale-verified'));
  finally
    lLive.Free;
    lHelpB.Free;
    lHelpA.Free;
  end;
  lExit := RunCmd('verify', ['--repo', lCopy, '--id', 'zz-nope', '--by', 'tester'], lOut);
  Check('Verify.RefusesUnknownId', (lExit = 1) and (Pos('no entry ''zz-nope''', lOut) > 0), IntToStr(lExit) + ' ' + lOut);
  lExit := RunCmd('verify', ['--repo', lCopy, '--id', 'outline'], lOut);
  Check('Verify.NeedsBy', (lExit = 1) and (Pos('--by is required', lOut) > 0), IntToStr(lExit) + ' ' + lOut);
  lExit := RunCmd('verify', ['--repo', lCopy, '--bogus', 'x'], lOut);
  Check('Verify.UnknownOptionIsUsageError', lExit = 2, lOut);
end;

function BuildWithPages(const pRepo, pOut: string; const pPages: TSitePages): TOutputResult;
var
  lFmt: TSiteFormat;
  lW: TOutputWriter;
  lHelp: TLiveHelp;
begin
  lHelp := TLiveHelp.Create;
  try
    lHelp.LoadFromText(SITE_HELP);
    lFmt := LoadSiteFormat(pRepo);
    lFmt.Help := lHelp;
    lW := TOutputWriter.Create(pOut, False, True);
    try
      BuildSite(pRepo, lFmt, lW, pPages);
      Result := lW.Finish;
    finally
      lW.Free;
    end;
  finally
    lHelp.Free;
  end;
end;

procedure TestSiteIndexFields;
var
  lRepo, lOut, lPath, lTxt, lJson, lMsg: string;
  lArr: TJSONArray;
  lVal, lAsk, lFix, lMenus: TJSONValue;
  lI: Integer;
begin
  lRepo := CopySiteRepo('index-fields-repo');
  lPath := TPath.Combine(lRepo, 'features\entries\ask.json');
  lTxt := TFile.ReadAllText(lPath, TEncoding.ASCII);
  lTxt := lTxt.Replace('"surfaces": [ { "type": "cli", "verb": "ask" } ]',
    '"surfaces": [ { "type": "cli", "verb": "ask" }, { "type": "ide-menu", "path": "drag-lint > Ask > One" },'
    + ' { "type": "ide-menu", "path": "drag-lint > Ask > Two" }, { "type": "ide-context", "host": "Editor", "caption": "Ask here" } ]');
  TFile.WriteAllText(lPath, lTxt, TEncoding.ASCII);
  lOut := TPath.Combine(SCRATCH, 'index-fields-out');
  lMsg := TryBuild(lRepo, lOut);
  Check('Site.IndexFieldsBuilds', lMsg = '', lMsg);
  lJson := ReadSiteFile(lOut, 'index.json');
  lVal := TJSONObject.ParseJSONValue(lJson);
  try
    lAsk := nil;
    lFix := nil;
    if lVal is TJSONArray then
    begin
      lArr := TJSONArray(lVal);
      for lI := 0 to lArr.Count - 1 do
        if lArr.Items[lI].GetValue<string>('id') = 'ask' then
          lAsk := lArr.Items[lI]
        else if lArr.Items[lI].GetValue<string>('id') = 'fix-refactor' then
          lFix := lArr.Items[lI];
    end;
    Check('Site.IndexFieldsEntryWithAll', (lAsk <> nil) and (lAsk.GetValue<string>('verb') = 'ask')
      and (lAsk.GetValue<TJSONArray>('menus').Count = 2) and (lAsk.GetValue<TJSONArray>('menus').Items[1].Value = 'drag-lint > Ask > Two')
      and (lAsk.GetValue<TJSONArray>('context').Count = 1) and (lAsk.GetValue<TJSONArray>('context').Items[0].Value = 'Editor > Ask here'), lJson);
    lMenus := nil;
    if lFix <> nil then
      lMenus := lFix.GetValue<TJSONArray>('menus');
    Check('Site.IndexFieldsEntryWithNone', (lFix <> nil) and (lFix.GetValue<string>('verb') = '') and (lMenus <> nil)
      and (TJSONArray(lMenus).Count = 1) and (lFix.GetValue<TJSONArray>('context').Count = 0), lJson);
    Check('Site.IndexFieldsAppendedAfterFile', Pos('"file": "features/ask.md",'#10'    "menus": [', lJson) > 0, lJson);
  finally
    lVal.Free;
  end;
end;

procedure TestSiteUpdated;
var
  lCopy, lOutA, lOutB, lOutC, lPagesFile, lJsonA, lJsonB: string;
  lP1, lP2, lP3: TSitePages;
begin
  lCopy := CopySiteRepo('site-updated');
  lPagesFile := TPath.Combine(lCopy, 'site-pages.json');
  lOutA := FreshDir('updA');
  lOutB := FreshDir('updB');
  lOutC := FreshDir('updC');
  lP1 := TSitePages.Create('1.0.0');
  lP2 := TSitePages.Create('2.0.0');
  lP3 := TSitePages.Create('3.0.0');
  try
    BuildWithPages(lCopy, lOutA, lP1);
    lJsonA := lP1.ToJson;
    TFile.WriteAllText(lPagesFile, lJsonA, TEncoding.ASCII);
    Check('Site.UpdatedFirstRunGetsCurrentVersion', (Pos(#10'updated: 1.0.0'#10, ReadSiteFile(lOutA, 'features/ask.md')) > 0)
      and (Pos('UPDATEDVERSIONTOKEN', ReadSiteFile(lOutA, 'features/ask.md')) = 0)
      and (Pos('"features/ask.md": {', lJsonA) > 0) and (Pos('"features/ask.md"', lJsonA) < Pos('"features/find-callers.md"', lJsonA)), lJsonA);
    lP2.LoadFromFile(lPagesFile);
    BuildWithPages(lCopy, lOutB, lP2);
    lJsonB := lP2.ToJson;
    Check('Site.UpdatedStableWhenPageUnchanged', (Pos(#10'updated: 1.0.0'#10, ReadSiteFile(lOutB, 'features/ask.md')) > 0)
      and (Pos('2.0.0', lJsonB) = 0) and (lJsonA = lJsonB)
      and (ReadSiteFile(lOutA, 'features/ask.md') = ReadSiteFile(lOutB, 'features/ask.md')), lJsonB);
    AppendText(TPath.Combine(lCopy, 'docs\wiki\Ask.md'), #13#10'More words about asking.'#13#10);
    lP3.LoadFromFile(lPagesFile);
    BuildWithPages(lCopy, lOutC, lP3);
    Check('Site.UpdatedBumpsWhenPageChanges', (Pos(#10'updated: 3.0.0'#10, ReadSiteFile(lOutC, 'features/ask.md')) > 0)
      and (Pos(#10'updated: 1.0.0'#10, ReadSiteFile(lOutC, 'features/find-callers.md')) > 0), lP3.ToJson);
  finally
    lP3.Free;
    lP2.Free;
    lP1.Free;
  end;
end;

{ ---- Fix round 1 (I2): assertions of the retired PowerShell runners that had no Delphi twin ---- }

function GoldenCopy(const pRepo, pName: string): string;
begin
  Result := TPath.Combine(FreshDir(pName), 'r');
  TDirectory.Copy(GoldenRepo(pRepo), Result);
end;

procedure RenderWikiInto(const pRepo, pOut: string);
var
  lW: TOutputWriter;
begin
  lW := TOutputWriter.Create(pOut, False, False);
  try
    BuildWiki(GoldenRepo(pRepo), lW, GoldenEngine(pRepo));
    lW.Finish;
  finally
    lW.Free;
  end;
end;

{ run_feature_registry_generate: byte-identical from the repo root and from a foreign CWD. }
procedure TestWikiCwdIndependent(const pRepo: string);
var
  lA, lB, lOld: string;
  lBad: TArray<string>;
begin
  lA := FreshDir('cwd-a');
  lB := FreshDir('cwd-b');
  lOld := GetCurrentDir;
  try
    RenderWikiInto(pRepo, lA);
    SetCurrentDir(FreshDir('cwd-foreign'));
    RenderWikiInto(pRepo, lB);
  finally
    SetCurrentDir(lOld);
  end;
  lBad := CompareOutputTrees(lA, lB, WikiOutputPaths);
  Check('Parity.WikiRenderIsCwdIndependent', (Length(WikiOutputPaths) > 0) and (Length(lBad) = 0), string.Join(' | ', lBad));
end;

{ run_feature_registry_generate: Update-MarkedBlock refuses a file without markers. }
procedure TestMarkedBlockNoMarkers;
var
  lMsg: string;
begin
  lMsg := '';
  try
    UpdateMarkedBlock('plain text, no markers at all'#13#10, 'x', 'new');
  except
    on E: Exception do
      lMsg := E.Message;
  end;
  Check('Wiki.MarkedBlockWithoutMarkersRaises', Pos('markers absent', lMsg) > 0, lMsg);
end;

{ run_feature_registry_canonical (lone CR), run_feature_registry_families (REPORT_QUESTION_COUNT,
  emitter SET both ways), on seeded copies of the frozen repo; each with an unseeded control. }
procedure TestSeededImporterAndFileChecks(const pRepo: string);
var
  lDst, lFile, lEngine, lAll: string;
  lF: TArray<TFinding>;
  lNotes: TArray<string>;
begin
  lEngine := GoldenEngine(pRepo);
  lDst := GoldenCopy(pRepo, 'seed-clean');
  lF := RunCheckCommand(lDst, lEngine, clFull, lNotes);
  Check('Seed.ControlCleanHasNoSeededFindings', (FindingsNaming(lF, 'lone CR') = '') and (FindingsNaming(lF, 'REPORT_QUESTION_COUNT') = '')
    and (FindingsNaming(lF, 'emitter set drift') = ''), FindingsNaming(lF, 'importer'));
  // a lone CR in a registry table file (Test-AsciiCrlfFile) is refused, naming the file and the line
  lDst := GoldenCopy(pRepo, 'seed-lone-cr');
  lFile := TPath.Combine(lDst, 'features\groups.json');
  TFile.WriteAllText(lFile, StringReplace(ReadBytesText(lFile), #13#10, #13#13#10, []), TEncoding.ASCII);
  lF := RunCheckCommand(lDst, lEngine, clWellFormed, lNotes);
  lAll := FindingsNaming(lF, 'lone CR at line 1');
  Check('Check.LoneCrRejectedNamingFileAndLine', (Pos('groups.json', lAll) > 0), lAll);
  // REPORT_QUESTION_COUNT must equal the catalog row count
  lDst := GoldenCopy(pRepo, 'seed-rqc');
  ReplaceInFile(TPath.Combine(lDst, 'src\delphi-plugin\DragLint.Plugin.ReportText.pas'), 'REPORT_QUESTION_COUNT = 26;', 'REPORT_QUESTION_COUNT = 27;');
  lF := RunCheckCommand(lDst, lEngine, clFull, lNotes);
  lAll := FindingsNaming(lF, 'REPORT_QUESTION_COUNT');
  Check('Check.ReportQuestionCountMismatchRejected', lAll <> '', lAll);
  // emitter set: on disk but no child names it
  lDst := GoldenCopy(pRepo, 'seed-emitter-unnamed');
  TFile.WriteAllText(TPath.Combine(lDst, 'charts\src\Emit-Zzextra.ps1'), '# probe'#13#10, TEncoding.ASCII);
  lF := RunCheckCommand(lDst, lEngine, clFull, lNotes);
  lAll := FindingsNaming(lF, 'emitter set drift');
  Check('Check.EmitterSetDriftOnDiskUnnamed', Pos('Emit-Zzextra.ps1', lAll) > 0, lAll);
  // emitter set: a child names a file that is not an Emit-*.ps1 on disk (and the real one goes unnamed)
  lDst := GoldenCopy(pRepo, 'seed-emitter-ghost');
  ReplaceInFile(TPath.Combine(lDst, 'features\families\chart-questions.json'), 'charts\\src\\Emit-RoundTrip.ps1', 'charts\\src\\New-DiagramArtifact.ps1');
  lF := RunCheckCommand(lDst, lEngine, clFull, lNotes);
  lAll := FindingsNaming(lF, 'emitter set drift');
  Check('Check.EmitterSetDriftNamedNotOnDisk', (Pos('New-DiagramArtifact.ps1', lAll) > 0) and (Pos('Emit-RoundTrip.ps1', lAll) > 0), lAll);
end;

{ run_feature_registry_families: a per-child since override is exempt from the CHANGELOG check; the family's own is not. }
procedure TestSinceOverride(const pRepo: string);
var
  lCtx: TCheckContext;
  lEntry: TJSONObject;
  lP: string;

  function ChangelogProblems(pOverride: Boolean): Integer;
  var
    lS: string;
  begin
    Result := 0;
    for lS in CheckEntry(lEntry, lCtx, 'ask', True, pOverride) do
      if Pos('CHANGELOG', lS) > 0 then
        Inc(Result);
  end;

begin
  lCtx := TCheckContext.Create(GoldenRepo(pRepo), nil);
  try
    lEntry := TJSONObject(TJSONObject.ParseJSONValue(ReadBytesText(TPath.Combine(GoldenRepo(pRepo), 'features\entries\ask.json'))));
    try
      lEntry.RemovePair('since').Free;
      lEntry.AddPair('since', '0.1.0');
      lP := IntToStr(ChangelogProblems(False)) + '/' + IntToStr(ChangelogProblems(True));
      Check('Check.ChildSinceNotInChangelogIsAProblem', ChangelogProblems(False) = 1, lP);
      Check('Check.ChildSinceOverrideIsExempt', ChangelogProblems(True) = 0, lP);
    finally
      lEntry.Free;
    end;
  finally
    lCtx.Free;
  end;
end;
{ ---- H-SYS (help audit 2026-10-26): prose checks G-1..G-4, G-6, the verified key, --set parsing ---- }

function JObj(const pJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(pJson) as TJSONObject;
end;

function ProbeEntry(const pSurfaces, pExtra: string): TJSONObject;
begin
  Result := JObj('{"id": "zz-prose", "status": "shipped", "surfaces": [' + pSurfaces + ']' + pExtra + '}');
end;

procedure TestIdeProse;
const
  MENU = '{"type": "ide-menu", "path": "drag-lint > Uses & Dependencies > Call Tree..."}';
  CLI = '{"type": "cli", "verb": "callgraph"}';
  ABOUT = '{"type": "ide-about", "caption": "Open Plugin Log"}';
  NO_IDE = '# x'#10#10'## Reaching it in the IDE'#10'No IDE surface -- this is a CLI-only feature.'#10#10'## What it needs'#10'No IDE surface here is fine.'#10;
var
  lE: TJSONObject;
  lP: TArray<string>;
begin
  lE := ProbeEntry(CLI + ',' + MENU, '');
  try
    lP := IdeProseProblems(lE, NO_IDE);
    Check('Prose.G1.NoIdeTextWithMenuSurfaceFails', (Length(lP) = 1) and (Pos('(G-1)', lP[0]) > 0), string.Join('|', lP));
    lP := IdeProseProblems(lE, '## Reaching it in the IDE'#10'No menu item calls this directly.'#10);
    Check('Prose.G1.NoMenuItemTextFails', Length(lP) = 1, string.Join('|', lP));
    lP := IdeProseProblems(lE, '## Reaching it in the IDE'#10'drag-lint > Uses & Dependencies > Call Tree...'#10);
    Check('Prose.G1.MenuPathTextPasses', Length(lP) = 0, string.Join('|', lP));
  finally
    lE.Free;
  end;
  lE := ProbeEntry(CLI, '');
  try
    lP := IdeProseProblems(lE, NO_IDE);
    Check('Prose.G1.NoIdeTextOnCliOnlyEntryPasses', Length(lP) = 0, string.Join('|', lP));
  finally
    lE.Free;
  end;
  lE := ProbeEntry(ABOUT, '');
  try
    lP := IdeProseProblems(lE, '## Reaching it in the IDE'#10'drag-lint > Open Plugin Log'#10);
    Check('Prose.G2.AboutButtonAsMenuPathFails', (Length(lP) = 1) and (Pos('(G-2)', lP[0]) > 0), string.Join('|', lP));
    lP := IdeProseProblems(lE, '## Reaching it in the IDE'#10'drag-lint About window, button Open Plugin Log.'#10);
    Check('Prose.G2.AboutWindowWordingPasses', Length(lP) = 0, string.Join('|', lP));
  finally
    lE.Free;
  end;
  Check('Prose.MarkdownSectionStopsAtNextHeading', MarkdownSection(NO_IDE, 'Reaching it in the IDE')
    = 'No IDE surface -- this is a CLI-only feature.'#10#10, MarkdownSection(NO_IDE, 'Reaching it in the IDE'));
  Check('Site.DropMarkdownSection', DropMarkdownSection(NO_IDE, 'Reaching it in the IDE')
    = '# x'#10#10'## What it needs'#10'No IDE surface here is fine.'#10, DropMarkdownSection(NO_IDE, 'Reaching it in the IDE'));
end;

procedure TestLineAnchors;
var
  lRepo: string;
  lE: TJSONObject;

  function Problems(const pNotes: string; const pWiki: string = ''): TArray<string>;
  begin
    lE := ProbeEntry('', ', "notes": "' + pNotes + '"');
    try
      Result := LineAnchorProblems(lE, lRepo, pWiki);
    finally
      lE.Free;
    end;
  end;

var
  lP: TArray<string>;
begin
  lRepo := FreshDir('anchors');
  ForceDirectories(TPath.Combine(lRepo, 'src\plugin'));
  TFile.WriteAllText(TPath.Combine(lRepo, 'src\plugin\Zz.Plugin.Editor.pas'),
    'unit Zz.Plugin.Editor;'#13#10'implementation'#13#10#13#10'procedure TZzEditor.CompileCheck;'#13#10'begin'#13#10
    + '  RunEngine(''compile-check'');'#13#10'end;'#13#10#13#10'function TZzEditor.Other: Integer;'#13#10'begin'#13#10'end;'#13#10'end.'#13#10);
  lP := Problems('issued by the plugin from Zz.Plugin.Editor.pas:6');
  Check('Anchor.G3.UnnamedRoutineIsDrift', (Length(lP) = 1) and (Pos('TZzEditor.CompileCheck', lP[0]) > 0), string.Join('|', lP));
  lP := Problems('issued by TZzEditor.CompileCheck (Zz.Plugin.Editor.pas:6)');
  Check('Anchor.G3.NamedRoutinePasses', Length(lP) = 0, string.Join('|', lP));
  lP := Problems('issued by TZzEditor.CompileCheck (Zz.Plugin.Editor.pas:11)');
  Check('Anchor.G3.MovedLineFails', (Length(lP) = 1) and (Pos('TZzEditor.Other', lP[0]) > 0), string.Join('|', lP));
  lP := Problems('issued by CompileCheck (Editor.pas:6)');
  Check('Anchor.G3.SuffixUnitNameResolves', Length(lP) = 0, string.Join('|', lP));
  lP := Problems('see Zz.Plugin.Editor.pas:999');
  Check('Anchor.G3.PastEndFails', (Length(lP) = 1) and (Pos('past the end', lP[0]) > 0), string.Join('|', lP));
  lP := Problems('see Nowhere.pas:12');
  Check('Anchor.G3.UnknownUnitFails', (Length(lP) = 1) and (Pos('names no unit', lP[0]) > 0), string.Join('|', lP));
  lP := Problems('no anchors', 'Sample output: @Blueprint4.ViewModel.pas:3553 -- in TFoo');
  Check('Anchor.G3.WikiSampleFromUserCodeIgnored', Length(lP) = 0, string.Join('|', lP));
  lP := Problems('no anchors', 'The plugin (Editor.pas:6) shells out.');
  Check('Anchor.G3.WikiAnchorIntoRepoJudged', Length(lP) = 1, string.Join('|', lP));
end;

procedure TestMenuProse;
var
  lNodes: TArray<TMenuNodeRow>;

  function Count(const pText: string): Integer;
  begin
    Result := Length(MenuProseProblems('zz', 'intro', pText, lNodes));
  end;

begin
  lNodes := [MenuRow('drag-lint', 'root', ''), MenuRow('drag-lint > Help', 'submenu', ''),
    MenuRow('drag-lint > Help > Effect Summary Legend', 'item', 'H'), MenuRow('drag-lint > About', 'item', 'A'),
    MenuRow('drag-lint > Find Usages...', 'item', 'F')];
  Check('Menu.G4.CaptionSuffixFails', Count('Choose drag-lint > Help > Effect Summary Legend (wiki)') = 1);
  Check('Menu.G4.MissingItemFails', Count('Choose **drag-lint > Help > Gone Item** now') = 1);
  Check('Menu.G4.TopLevelMissingFails', Count('drag-lint > Uninstall') = 1);
  Check('Menu.G4.LivePathPasses', Count('Choose **drag-lint > Help > Effect Summary Legend** now') = 0);
  Check('Menu.G4.AsideAfterCaptionPasses', Count('drag-lint > Find Usages... (Ctrl+Alt+F); it is served by the plugin') = 0);
  Check('Menu.G4.WrappedPathPasses', Count('Choose drag-lint >'#10'Help > Effect Summary Legend.') = 0);
  Check('Menu.G4.DialogBehindLeafPasses', Count('drag-lint > About > Open Plugin Log') = 0);
  Check('Menu.G4.HeadingEndsQuote', Count('drag-lint > Help'#10#10'## Next') = 0);
  // a path that does not start at the IDE menu (a Windows path) is not an IDE menu path
  Check('Menu.G4.WindowsPathPasses', Count('Windows Settings > Apps > drag-lint > Uninstall') = 0);
  Check('Menu.G4.WindowsPathInQuotesPasses', Count('Open "Settings > Apps > drag-lint > Uninstall" and remove it') = 0);
  // positive controls: a stale path that starts at the root still fails, also behind the ide-menu: prefix
  Check('Menu.G4.PrefixedStaleFails', Count('ide-menu:drag-lint > NoSuchItem') = 1);
  Check('Menu.G4.RootedStaleAfterWindowsPathFails', Count('Apps > drag-lint > Uninstall, then drag-lint > NoSuchItem') = 1);
end;

procedure TestRuleCounts;
var
  lCat: TJSONValue;

  function Count(const pText: string): Integer;
  begin
    Result := Length(RuleCountProblems('zz', 'intro', pText, lCat));
  end;

begin
  lCat := TJSONObject.ParseJSONValue('{"rules": [{"id": "a", "default_enabled": true, "fixable": true},'
    + ' {"id": "b", "default_enabled": false, "fixable": false}, {"id": "c", "default_enabled": true, "fixable": false}],'
    + ' "summary": {"total": 3, "categories": 2}}');
  try
    Check('Rules.G6.TrueCountsPass', Count('The catalog has 3 rules, 2 on by default, 1 of them fixable, across 2 categories; the full 3-rule list.') = 0);
    Check('Rules.G6.StaleTotalFails', Count('The catalog has 4 rules.') = 1);
    Check('Rules.G6.StaleHyphenTotalFails', Count('the full 190-rule catalog') = 1);
    Check('Rules.G6.StaleOnByDefaultFails', Count('160 on by default') = 1);
    Check('Rules.G6.StaleFixableFails', Count('23 fixable rules') = 1);
    Check('Rules.G6.StaleCategoriesFails', Count('across 16 categories') = 1);
    Check('Rules.G6.VersionIsNotACount', Count('the 1.26.6 rules above') = 0);
  finally
    lCat.Free;
  end;
end;

{ ---- ki-docscheck: C1-C4 docs-drift checks. Each has a RED fixture (the stale page) and a clean control. ---- }

const
  DOC_HELP = '  drag-lint ask <question>     --target <T> [--out-root <dir>]'#10
    + '                               [--plain]   one report question as text'#10
    + '  drag-lint index              --project <X.dproj> --db <db>'#10
    + #10
    + '  drag-lint query              --name X'#10
    + '  drag-lint query find-callers --name X --limit N'#10;

procedure TestDocsFlags;
var
  lBlocks: TVerbBlocks;

  function Count(const pText: string; const pVerbs: TArray<string> = nil): Integer;
  begin
    Result := Length(FlagProblems('zz', 'intro', pText, lBlocks, pVerbs));
  end;

begin
  lBlocks := HelpVerbBlocks(DOC_HELP);
  try
    Check('Docs.C1.StaleFlagFails', Count('Run `drag-lint ask --target T --outroot x` now.') = 1);
    Check('Docs.C1.RealFlagPasses', Count('Run `drag-lint ask --target T --out-root x` now.') = 0);
    Check('Docs.C1.ContinuationLineFlagPasses', Count('Run `drag-lint ask --target T --plain`.') = 0);
    Check('Docs.C1.OtherVerbsFlagFails', Count('Run `drag-lint ask --project P.dproj`.') = 1);
    Check('Docs.C1.SubcommandUsesVerbBlock', Count('`drag-lint query find-callers --name Bar --limit 5`') = 0);
    Check('Docs.C1.SubcommandStaleFails', Count('`drag-lint query find-callers --nam Bar`') = 1);
    Check('Docs.C1.FenceLineFails', Count('```'#10'drag-lint index --project P.dproj --dbb x'#10'```') = 1);
    Check('Docs.C1.FenceLinePasses', Count('```'#10'drag-lint index --project P.dproj --db x'#10'```') = 0);
    Check('Docs.C1.UnknownVerbNotJudged', Count('`drag-lint nosuchverb --whatever`') = 0);
    Check('Docs.C1.ProseOutsideBackticksNotJudged', Count('Never write drag-lint ask --outroot in prose') = 0);
    Check('Docs.C1.HelpFlagAlwaysOk', Count('`drag-lint ask --help`') = 0);
    Check('Docs.C1.WholeStringUsageFails', Count('drag-lint index --project X.dproj --stale') = 1);
    Check('Docs.C1.StandaloneStaleFlagFails', Count('| `--outroot <dir>` | where |', ['ask']) = 1);
    Check('Docs.C1.StandaloneRealFlagPasses', Count('| `--out-root <dir>` | where |', ['ask']) = 0);
    Check('Docs.C1.StandaloneWithoutPageVerbNotJudged', Count('| `--outroot <dir>` | where |') = 0);
  finally
    lBlocks.Free;
  end;
end;

procedure TestDocsPaths;
var
  lSrc: string;

  function Count(const pText: string): Integer;
  begin
    Result := Length(PathProblems('zz', 'page', pText, lSrc));
  end;

begin
  lSrc := FoldPathText('LOG = ''%LOCALAPPDATA%\drag-lint\logs\uri-handler.log''; ROOT = ''%TEMP%/drag-lint-reports'';');
  Check('Docs.C2.StalePathFails', Count('the log is `%LOCALAPPDATA%\drag-lint\uri-handler.log`; it logs') = 1);
  Check('Docs.C2.RealPathPasses', Count('the log is `%LOCALAPPDATA%\drag-lint\logs\uri-handler.log`; it logs') = 0);
  Check('Docs.C2.PlaceholderTailCut', Count('goes to `%TEMP%\drag-lint-reports\<question>-<target>\`') = 0);
  Check('Docs.C2.PartialSegmentDropped', Count('see %TEMP%\drag-lint-reports\compare-<q>.html') = 0);
  Check('Docs.C2.RenamedFolderFails', Count('see %TEMP%\drag-lint-output\x.html') = 1);
  Check('Docs.C2.NoEnvVarNotJudged', Count('see C:\Temp\nowhere.log') = 0);
end;

procedure TestDocsPhrases;
begin
  Check('Docs.C3.PlannedAndUntilThenFail', Length(PhraseProblems('zz', 'page', 'One verb, `ask`. Planned; until then the menu runs scripts.')) = 2);
  Check('Docs.C3.NotYetFails', Length(PhraseProblems('zz', 'page', 'This is not yet wired.')) = 1);
  Check('Docs.C3.ComingFails', Length(PhraseProblems('zz', 'page', 'Coming in the next release.')) = 1);
  Check('Docs.C3.ShippedProseClean', Length(PhraseProblems('zz', 'page', 'Shipped: drag-lint ask runs in-process. The incoming link and the upcoming list are words, not promises.')) = 0);
end;

procedure TestDocsStaleSource;
var
  lDates: TDictionary<string, string>;
  lSrc: TArray<string>;
begin
  lDates := ParseGitFileDates('@2026-10-10'#10'src/charts/DRagLint.Charts.Ask.pas'#10#10'@2026-08-01'#10'src/charts/DRagLint.Charts.Ask.pas'#10'src/core/Other.pas'#10);
  try
    lSrc := ConventionSources('ask', ['src/charts/draglint.charts.ask.pas', 'src/charts/draglint.charts.askverb.pas', 'src/core/other.pas']);
    Check('Docs.C4.ConventionPicksExactUnitOnly', (Length(lSrc) = 1) and (lSrc[0] = 'src/charts/draglint.charts.ask.pas'));
    Check('Docs.C4.NewestDateWins', lDates['src/charts/draglint.charts.ask.pas'] = '2026-10-10');
    Check('Docs.C4.SourceNewerThanVerifiedReported', SourceChangedAfter('2026-09-01', lSrc, lDates) = '2026-10-10');
    Check('Docs.C4.VerifiedAfterChangeClean', SourceChangedAfter('2026-10-20', lSrc, lDates) = '');
    Check('Docs.C4.UnchangedSourceClean', SourceChangedAfter('2026-01-01', ['src/core/none.pas'], lDates) = '');
  finally
    lDates.Free;
  end;
end;

function DocsProbe(const pIntroJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(
    '{"id": "zz-docs-probe", "title": "Docs probe", "group": "maintenance", "owner": "CONVERTER", "status": "shipped",'
    + ' "since": "1.0.0", "summary": "A probe entry whose prose is judged by the docs checks",'
    + ' "intro": "' + pIntroJson + '", "wikiPage": "Home",'
    + ' "surfaces": [ { "type": "cli", "verb": "ask" } ],'
    + ' "audience": "both", "lastVerified": { "date": "2026-10-19", "by": "test", "build": "1.0.0" } }') as TJSONObject;
end;

function DocsProbeFindings(const pRepo, pIntroJson: string; const pLive: TLiveSurface): TArray<TFinding>;
var
  lReg: TRegistry;
  lE: TJSONObject;
  lNotes: TArray<string>;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lE := DocsProbe(pIntroJson);
    try
      Result := RunChecks(lReg, pLive, clFull, [lE], True, lNotes);
    finally
      lE.Free;
    end;
  finally
    lReg.Free;
  end;
end;

{ End to end through check --level full: the stale probe fails C1/C2/C3 and is named; the clean probe is not;
  an allow row with a reason waives C1 for the probe and a row without a reason is itself a finding. }
procedure TestDocsChecksEndToEnd(const pRepo: string);
const
  STALE = 'Run `drag-lint ask --target T --outroot x`; the log is `%LOCALAPPDATA%\\drag-lint\\no-such-folder\\x.log`. Planned; until then use scripts.';
  CLEAN = 'Run `drag-lint ask --target T --out-root x` and read the answer.';
var
  lLive: TLiveSurface;
  lF: TArray<TFinding>;
  lScratch: string;
begin
  lLive := SharedLive(pRepo);
  lF := DocsProbeFindings(pRepo, STALE, lLive);
  Check('Docs.E2E.StaleFlagFails', HasFinding(lF, 'C', 'C1 zz-docs-probe'), FindingsNaming(lF, 'zz-docs-probe'));
  Check('Docs.E2E.StalePathFails', HasFinding(lF, 'C', 'C2 zz-docs-probe'), FindingsNaming(lF, 'zz-docs-probe'));
  Check('Docs.E2E.StalePhraseFails', HasFinding(lF, 'C', 'C3 zz-docs-probe'), FindingsNaming(lF, 'zz-docs-probe'));
  lF := DocsProbeFindings(pRepo, CLEAN, lLive);
  Check('Docs.E2E.CleanProbeNotNamed', not (HasFinding(lF, 'C', 'C1 zz-docs-probe') or HasFinding(lF, 'C', 'C2 zz-docs-probe')
    or HasFinding(lF, 'C', 'C3 zz-docs-probe')), FindingsNaming(lF, 'zz-docs-probe'));
  lScratch := CmdRepo(pRepo, 'docscheck-allow');
  TFile.WriteAllText(TPath.Combine(lScratch, 'features\docs-check.json'),
    '{ "allow": [ { "check": "C1", "where": "zz-docs-probe", "token": "--outroot", "why": "test waiver" } ] }'#10, TEncoding.ASCII);
  lF := DocsProbeFindings(lScratch, STALE, lLive);
  Check('Docs.E2E.AllowRowWaivesC1', not HasFinding(lF, 'C', 'C1 zz-docs-probe') and HasFinding(lF, 'C', 'C3 zz-docs-probe'), FindingsNaming(lF, 'zz-docs-probe'));
  TFile.WriteAllText(TPath.Combine(lScratch, 'features\docs-check.json'),
    '{ "allow": [ { "check": "C1", "where": "zz-docs-probe", "token": "--outroot", "why": "" } ] }'#10, TEncoding.ASCII);
  lF := DocsProbeFindings(lScratch, STALE, lLive);
  Check('Docs.E2E.AllowRowWithoutWhyIsAFinding', HasFinding(lF, 'A', 'has no "why"'), FindingsNaming(lF, 'docs-check'));
end;
{ Defect (H-SYS): featuregen verify writes "verified"; the seed backlog asked for "lastVerified", so no entry could
  ever leave it. A backlog entry with intro + verified + a real since must be reported as paid (RED before the
  fix); one whose stamps are removed stays owed (positive control). }
procedure TestBacklogReadsVerified(const pRepo: string);
var
  lCopy, lFile: string;
  lE: TJSONObject;
  lReg: TRegistry;
  lF: TArray<TFinding>;
  lNotes: TArray<string>;
begin
  lCopy := CmdRepo(pRepo, 'backlog-verified');
  lFile := TPath.Combine(lCopy, 'features\entries\butterfly.json');
  lE := JObj(ReadBytesText(lFile));
  try
    lE.RemovePair('verified').Free;
    lE.RemovePair('lastVerified').Free;
    TFile.WriteAllText(lFile, lE.ToJSON, TEncoding.ASCII);
  finally
    lE.Free;
  end;
  TFile.WriteAllText(TPath.Combine(lCopy, 'features\seed-backlog.json'),
    '{"deadline": "test", "teams": {"ENGINE": ["callgraph", "butterfly"]}}'#13#10, TEncoding.ASCII);
  Check('Backlog.FixtureHasVerifiedOnly', (Pos('"verified"', ReadBytesText(TPath.Combine(lCopy, 'features\entries\callgraph.json'))) > 0)
    and (Pos('"lastVerified"', ReadBytesText(TPath.Combine(lCopy, 'features\entries\callgraph.json'))) = 0));
  lReg := TRegistry.Create;
  try
    lReg.Load(lCopy);
    lF := RunChecks(lReg, SharedLive(pRepo), clFull, nil, True, lNotes);
  finally
    lReg.Free;
  end;
  Check('Backlog.VerifiedEntryIsPaid', HasFinding(lF, 'A', '''callgraph'' now has intro, verified and a real since'), FindingsNaming(lF, 'seed-backlog'));
  Check('Backlog.UnstampedEntryStaysOwed', not HasFinding(lF, 'A', '''butterfly'' now has') and (Pos('backlog: ENGINE 1 remaining', string.Join('|', lNotes)) > 0),
    string.Join('|', lNotes));
end;

procedure TestSetArgParsing;
var
  lA: TArray<string>;
begin
  lA := SplitCommandLine('featuregen.exe update --set "intro=He said \"hi\" there." --id x');
  Check('Args.BackslashQuoteIsALiteralQuote', (Length(lA) = 6) and (lA[3] = 'intro=He said "hi" there.'), string.Join('|', lA));  // dl:ok magic-literal@bc07 -- REVIEWED 2026-10-26: test expectation: the word count and index are the asserted values
  lA := SplitSetArgs(['intro=A x;;y z ;; summary=B']);
  Check('Args.SetSplitsOnlyBeforeAField', (Length(lA) = 2) and (lA[0] = 'intro=A x;;y z') and (lA[1] = 'summary=B'), string.Join('|', lA));
  lA := SplitSetArgs(['related=["a","b"] ;; homeOrder=3']);
  Check('Args.SetKeepsJsonValue', (Length(lA) = 2) and (lA[0] = 'related=["a","b"]'), string.Join('|', lA));
end;

procedure TestCommands(const pRepo: string);
begin
  TestAuditVerify(pRepo);
  TestCmdHomeOrderAndNull(pRepo);
  TestCmdMoveMenuSibling(pRepo);
  TestCmdAdd(pRepo);
  TestCmdReviewAccess(pRepo);
  TestCmdAddRefusals(pRepo);
  TestCmdUpdate(pRepo);
  TestCmdUpdateNormalisesHandEdits(pRepo);
  TestCmdDeprecate(pRepo);
  TestCmdFindAndBlast(pRepo);
  TestCmdMoveMenu(pRepo);
  TestCmdNormalise(pRepo);
end;
var
  lRepo, lSeeded, lGold: string;
begin
  if SameText(ExtractFileName(ParamStr(0)), GOLDEN_STUB_NAME) then
  begin
    RunGoldenEngineStub;
    Exit;
  end;
  SCRATCH := TPath.Combine(TPath.GetTempPath, 'featuregen-tests-' + IntToStr(GetCurrentProcessId));
  ForceDirectories(SCRATCH);
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
    TestSeedHelpBlocks;
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
    TestAuditThin;
    TestSiteIndexFields;
    TestSiteUpdated;
    if lRepo <> '' then
      TestSiteFormatFile(lRepo);
    TestReadAsciiStrict;
    if lRepo <> '' then
      TestDeadLinkPositiveControl(lRepo);
    if lRepo <> '' then
      TestWikiParity(lRepo);
    TestCaptionKeyVector;
    TestParseMenuTreeJson;
    TestCompareFindingSetsPositiveControl;
    TestEmptyKindsPositiveControl;
    TestExclusionCountPositiveControl;
    TestIdeProse;
    TestLineAnchors;
    TestMenuProse;
    TestRuleCounts;
    TestDocsFlags;
    TestDocsPaths;
    TestDocsPhrases;
    TestDocsStaleSource;
    TestSetArgParsing;
    if lRepo <> '' then
    begin
      TestSharedLiveNotCachedOnFailure(lRepo);
      TestHarvestFailureIsCleanFail;
      TestHarvestRaisesOnEmptySubMap(lRepo);
      TestLiveHarvestParity(lRepo);
      lGold := GoldenRepo(lRepo);
      TestCheckParity(lRepo, lGold, 'WellFormed', clWellFormed, 'WellFormed', 0, 0, 0, 0, GOLDEN_PROSE_A, 0);
      TestCheckParity(lRepo, lGold, 'Full', clFull, 'Full', 0, ExpectedMcpExclusions(lGold, GoldenLive(lRepo).McpTools), 0, 0, GOLDEN_PROSE_FULL, -1);
      lSeeded := SeededRepo(lGold);
      // the seeded copy carries the same MCP server source, so the live tool list is the same
      TestCheckParity(lRepo, lSeeded, 'WellFormed', clWellFormed, 'SeededWellFormed', 5, 0, 1, 0, GOLDEN_PROSE_A, 0);  // dl:ok magic-literal@8c3e -- REVIEWED 2026-10-26 (re-stamped: GOLDEN_PROSE_A argument added): test expectation: the literal is the asserted value
      TestCheckParity(lRepo, lSeeded, 'Full', clFull, 'SeededFull', 8, ExpectedMcpExclusions(lSeeded, GoldenLive(lRepo).McpTools), 1, -1, GOLDEN_PROSE_FULL, -1);  // dl:ok magic-literal@edb5 -- REVIEWED 2026-10-26 (re-stamped: GOLDEN_PROSE_FULL argument added): test expectation: the literal is the asserted value
      TestCheckDCoversAllOutputs(lRepo);
      TestWikiCwdIndependent(lRepo);
      TestMarkedBlockNoMarkers;
      TestSeededImporterAndFileChecks(lRepo);
      TestSinceOverride(lRepo);
      TestPositiveControls(lRepo);
      TestMenuPathChecks(lRepo);
      TestHelpText(lRepo);
      TestFlagAliasPolicy(lRepo);
      TestHelpOrderTiebreak;
      TestPlannedSkipsLive(lRepo);
      TestWellFormedCatchesBadEntry(lRepo);
      TestBacklogReadsVerified(lRepo);
      TestDocsChecksEndToEnd(lRepo);
      TestCommands(lRepo);
    end;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL EXCEPTION ', E.ClassName, ': ', E.Message);
    end;
  end;
  FreeAndNil(GLive);
  FreeAndNil(GGoldenLive);
  try
    TDirectory.Delete(SCRATCH, True);
  except
    on E: Exception do
      Writeln('INFO scratch folder not removed: ', SCRATCH, ' (', E.Message, ')');
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    Halt(1);
end.
 -- REVIEWED 2026-10-19: the ported checks A-E live together because they share one context and one finding list; splitting is a later refactor
