program MenuTreeTests;

{ Console tests for DRagLint.MenuTree (code-built menu reader) and
  DRagLint.MenuDrift. Run by tests\autotest\run_menu_tree_tests.ps1, which
  compiles this with dcc64 (search path read from src\cli\drag-lint.dproj) and
  passes the scratch fixture DB + fixture dir for the walker tests.
  Usage: MenuTreeTests.exe [<fixture.sqlite> <fixture dir> [<renamed.sqlite>]]
  Last line: "menutree-tests: N passed, M failed"; exit code 1 on any failure. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.StrUtils
  , DRagLint.MenuTree
  ;

var
  GPassed: Integer = 0;
  GFailed: Integer = 0;

procedure Check(const pName: string; pOk: Boolean; const pDetail: string = '');
begin
  if pOk then
  begin
    Inc(GPassed);
    Writeln('  PASS ', pName);
  end
  else
  begin
    Inc(GFailed);
    Writeln('  FAIL ', pName, ' ', pDetail);
  end;
end;

procedure CheckEq(const pName, pWant, pGot: string);
begin
  Check(pName, pWant = pGot, Format('want [%s] got [%s]', [pWant, pGot]));
end;

{ ---- Task 2: keys and the model ---- }

procedure TestCaptionKeyVector;
begin
  { The shared vector (spec 6): featuregen's FeatureGenTests carries the SAME
    four rows, so a divergence between the two CaptionKeys fails a battery. }
  CheckEq('key: && and ...', 'uses & deps tab -- review & apply fixes',
    MenuCaptionKey('Uses && Deps Tab -- review && apply fixes...'));
  CheckEq('key: trailing ...', 'find usages', MenuCaptionKey('Find Usages...'));
  CheckEq('key: plain', 'reports', MenuCaptionKey('Reports'));
  CheckEq('key: trim ) only at the end', 'drag-lint (!', MenuCaptionKey('drag-lint (!)'));
  CheckEq('key: quote chars and whitespace', 'a b c', MenuCaptionKey('  `A`  *b*  "C" '));
  CheckEq('path key', 'fixture > tools > find usages', MenuPathKey('Fixture > Tools  > Find Usages...'));
  CheckEq('path key drops empty segments', 'a > b', MenuPathKey('A > ... > B'));
end;

procedure TestToPaths;
var
  Tree: TMenuTree;
  Root, Sub, N: TMenuNode;
  Lines: TArray<string>;
begin
  Tree:= TMenuTree.Create;
  try
    Root:= Tree.AddRoot('Top', 'u.pas:1');
    N:= Root.AddChild(TMenuNode.Create(mnkItem, 'First...', 'u.pas:2'));
    N.Handler:= 'U.DoFirst';
    Root.AddChild(TMenuNode.Create(mnkSeparator, '-', 'u.pas:3'));
    Root.AddChild(TMenuNode.Create(mnkHeader, 'A Header', 'u.pas:4'));
    Sub:= Root.AddChild(TMenuNode.Create(mnkSubmenu, 'Sub && More', 'u.pas:5'));
    N:= Sub.AddChild(TMenuNode.Create(mnkItem, 'Second', 'u.pas:6'));
    N.Handler:= 'U.DoSecond';
    N.Confidence:= mcDerived;
    Lines:= Tree.ToPaths.Trim.Split([#13#10]);
    Check('ToPaths: two leaf lines', Length(Lines) = 2, Tree.ToPaths);
    if Length(Lines) = 2 then
    begin
      CheckEq('ToPaths line 1', 'Top > First...'#9'U.DoFirst'#9'u.pas:2'#9'certain', Lines[0]);
      CheckEq('ToPaths line 2', 'Top > Sub & More > Second'#9'U.DoSecond'#9'u.pas:6'#9'derived', Lines[1]);
    end;
    CheckEq('node key', 'sub & more', Sub.CaptionKey);
  finally
    Tree.Free;
  end;
end;

{ ---- Task 3/4: the walker on tests\fixtures\menutree ---- }

/// <summary>expected-paths.txt / ToPaths rows as 'path|handler|confidence'
/// ('## external' lines kept verbatim). ToPaths carries file:line as its third
/// column; the golden does not, so it is dropped here.</summary>
function PathRows(const pText: string; pHasSource: Boolean): TArray<string>;
var
  Line: string;
  C   : TArray<string>;
begin
  Result:= nil;
  for Line in pText.Replace(#13#10, #10).Split([#10]) do
  begin
    if Line.Trim = '' then Continue;
    if Line.StartsWith('## ') then begin Result:= Result + [Line.Trim]; Continue; end;
    C:= Line.Split([#9]);
    if pHasSource and (Length(C) = 4) then Result:= Result + [C[0] + '|' + C[1] + '|' + C[3]]
    else if (not pHasSource) and (Length(C) = 3) then Result:= Result + [C[0] + '|' + C[1] + '|' + C[2]]
    else Result:= Result + ['<malformed: ' + Line + '>'];
  end;
end;

procedure CheckRows(const pTag: string; const pWant, pGot: TArray<string>);
var
  I: Integer;
  W, G: string;
begin
  CheckEq(pTag + ': row count', IntToStr(Length(pWant)), IntToStr(Length(pGot)));
  for I:= 0 to High(pWant) do
  begin
    W:= pWant[I];
    if I <= High(pGot) then G:= pGot[I] else G:= '<no row>';
    CheckEq(Format('%s: row %d', [pTag, I + 1]), W, G);
  end;
end;

function FindChild(pNode: TMenuNode; const pCaption: string): TMenuNode;
var
  C: TMenuNode;
begin
  Result:= nil;
  if pNode = nil then Exit;
  for C in pNode.Children do
    if C.Caption = pCaption then Exit(C);
end;

function HasNote(pTree: TMenuTree; const pPart: string): Boolean;
var
  S: string;
begin
  Result:= False;
  for S in pTree.Notes do
    if Pos(pPart, S) > 0 then Exit(True);
end;

procedure TestWalkerRoot(const pDb, pProject: string);
var
  W   : TMenuWalker;
  Tree: TMenuTree;
  Root, Sub: TMenuNode;
  Seps: Integer;
  C   : TMenuNode;
begin
  W:= TMenuWalker.Create([pDb], pProject);
  try
    Tree:= W.Walk('MT.Builder.BuildMainMenu');
    try
      { if MainMenu <> nil then MainMenu.Items.Add(Root) else AddActionMenu(.., Root, ..): ONE root }
      CheckEq('root: one root for the two-branch if', '1', IntToStr(Tree.Roots.Count));
      if Tree.Roots.Count = 0 then Exit;
      Root:= Tree.Roots[0];
      CheckEq('root: caption', 'Fixture', Root.Caption);
      Sub:= FindChild(Root, 'Tools && Options');
      Check('inline-var submenu is a child of the root', Sub <> nil);
      if Sub <> nil then CheckEq('inline-var submenu kind', 'submenu', MenuKindName(Sub.Kind));
      Check('Format caption keeps the pattern', FindChild(Root, 'Find %s...') <> nil);
      Check('const-identifier caption evaluates', FindChild(Root, 'Export Everything') <> nil);
      Check('literal + literal caption evaluates', FindChild(Root, 'Direct Item') <> nil);
      if Root.Children.Count > 0 then CheckEq('Insert(0, X) puts X first', 'Direct Item', Root.Children[0].Caption);
      Seps:= 0;
      for C in Root.Children do if C.Kind = mnkSeparator then Inc(Seps);
      CheckEq('separator helper: two separators', '2', IntToStr(Seps));
      if Sub <> nil then
      begin
        C:= FindChild(Sub, 'Formatting');
        Check('header helper (Enabled := False) gives a header', (C <> nil) and (C.Kind = mnkHeader));
        C:= FindChild(Sub, 'Format Unit');
        Check('item helper: handler through the wrapper', (C <> nil) and (C.Handler = 'MT.Builder.DoFormat'),
          IfThen(C = nil, '<none>', C.Handler));
      end;
      Check('--root: only the one builder (no external roots)', Tree.External.Count = 0);
    finally
      Tree.Free;
    end;
  finally
    W.Free;
  end;
end;

procedure TestWalkerFull(const pDb, pProject, pFixtureDir: string);
var
  W   : TMenuWalker;
  Tree: TMenuTree;
  Ext : TMenuNode;
begin
  W:= TMenuWalker.Create([pDb], pProject);
  try
    Tree:= W.Walk;
    try
      CheckRows('golden', PathRows(TFile.ReadAllText(TPath.Combine(pFixtureDir, 'expected-paths.txt')), False),
        PathRows(Tree.ToPaths, True));
      Check('dynamic caption -> a note', HasNote(Tree, 'dynamic caption'));
      Check('unparented item -> a note, in no root', HasNote(Tree, 'Orphan Item'));
      Check('catalog: one header per case arm', (Tree.Roots.Count > 0)
        and (FindChild(FindChild(Tree.Roots[0], 'Catalog'), 'Basic Group') <> nil)
        and (FindChild(FindChild(Tree.Roots[0], 'Catalog'), 'Advanced Group') <> nil));
      Ext:= nil;
      if Tree.External.Count > 0 then Ext:= Tree.External[0];
      Check('DFM mnuTools children land under external-root mnuTools',
        (Ext <> nil) and (Ext.Ident = 'mnuTools') and (Ext.Children.Count = 2));
    finally
      Tree.Free;
    end;
  finally
    W.Free;
  end;
end;

procedure TestWalkerRenamed(const pDb, pProject, pFixtureDir: string);
var
  W   : TMenuWalker;
  Tree: TMenuTree;
begin
  { spec 11 control 4: AddItem renamed PutItem in a copy -- recognition is by
    BODY, so the tree is unchanged. A leaf-regex scraper goes blind here. }
  W:= TMenuWalker.Create([pDb], pProject);
  try
    Tree:= W.Walk;
    try
      CheckRows('renamed helper', PathRows(TFile.ReadAllText(TPath.Combine(pFixtureDir, 'expected-paths.txt')), False),
        PathRows(Tree.ToPaths, True));
    finally
      Tree.Free;
    end;
  finally
    W.Free;
  end;
end;

begin  try
    TestCaptionKeyVector;
    TestToPaths;
    if ParamCount >= 2 then
    begin
      TestWalkerRoot(ParamStr(1), TPath.Combine(ParamStr(2), 'MenuTreeFixture.dproj'));
      TestWalkerFull(ParamStr(1), TPath.Combine(ParamStr(2), 'MenuTreeFixture.dproj'), ParamStr(2));
    end
    else Check('walker tests need <db> <fixture dir>', False);
    if ParamCount >= 3 then
      TestWalkerRenamed(ParamStr(3), TPath.Combine(TPath.Combine(ExtractFilePath(ParamStr(3)), 'renamed'), 'MenuTreeFixture.dproj'), ParamStr(2));
  except
    on E: Exception do
    begin
      Inc(GFailed);
      Writeln('  FAIL unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('menutree-tests: %d passed, %d failed', [GPassed, GFailed]));
  if GFailed > 0 then ExitCode:= 1;
end.
