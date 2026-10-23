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

begin
  try
    TestCaptionKeyVector;
    TestToPaths;
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
