unit ChartsTests.CoreDot;

{ Cases for DRagLint.Charts.Dot (row cluster, disclosure row, note row, the dot run),
  ported from charts\src\Emit-Common.ps1. The expected DOT text was printed by the
  PowerShell functions themselves for the same rows on 2026-10-13 (spec P3/P4). The
  layout case runs the real dot.exe that ResolveGraphvizDot finds on this machine. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreDotTests = class
  public
    [Test] procedure DisclosureRowKeepsMiddot;
    [Test] procedure RowClusterMatchesPowerShell;
    [Test] procedure RowClusterRefusesEmptyRow;
    [Test] procedure DotRunRefusesLongPath;
    [Test] procedure DotLayoutWritesFourOutputs;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, DRagLint.Charts.Dot, DRagLint.Charts.Tools;

const
  ROW_LINE = 12;
  INK_BLACK = '#000';
  POINT_NINE = 9;
  LONG_NAME = 280;

procedure TCoreDotTests.DisclosureRowKeepsMiddot;
begin
  var T:= TStringBuilder.Create;
  try
    AddDisclosureRow(T, 'a &#183; b & <c>');
    AddDisclosureRow(T, '   ');
    AddDisclosureRow(T, 'x', INK_BLACK, POINT_NINE);
    Assert.AreEqual('<TR><TD ALIGN="LEFT"><FONT COLOR="#8A94A6" POINT-SIZE="12">a &#183; b &amp; &lt;c&gt;</FONT></TD></TR>' +
      '<TR><TD ALIGN="LEFT"><FONT COLOR="#000" POINT-SIZE="9">x</FONT></TD></TR>', T.ToString);
  finally
    T.Free;
  end;
end;

procedure TCoreDotTests.RowClusterMatchesPowerShell;
var
  Ports: TArray<string>;
begin
  var Sb:= TStringBuilder.Create;
  try
    var Bare:= TDotRow.Anchored('Baz', 0, 'h2', '');
    Bare.Line:= '';   { PS $null line prints a bare ':' }
    Ports:= AddRowCluster(Sb, 'cluster_f', 'focus', 'A & B', '<sub>', [
      TDotRow.Anchored('TFoo<T>.Bar', ROW_LINE, 'draglint://open?file=a.pas&amp;line=12', 'uA.TFoo<T>.Bar & "x"', 'calls'),
      Bare, NoteRow('+2 more & <others>')], TClusterStyle.Make('#111', '#222', '#333'));
    Assert.AreEqual(
      '  subgraph cluster_f {'#13#10 +
      '    style="rounded,filled"; color="#111"; fillcolor="#222"; penwidth=2;'#13#10 +
      '    label=""; margin=10;'#13#10 +
      '    focus [label=<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5"><TR><TD ALIGN="LEFT" BGCOLOR="#333">' +
      '<FONT COLOR="#FFFFFF" FACE="Segoe UI" POINT-SIZE="14"><B> A &amp; B &#183; &lt;sub&gt; </B></FONT></TD></TR>' +
      '<TR><TD PORT="p1" ALIGN="LEFT" HREF="draglint://open?file=a.pas&amp;line=12" TITLE="uA.TFoo&lt;T&gt;.Bar &amp; &quot;x&quot;">' +
      '<FONT COLOR="#1F2933">TFoo&lt;T&gt;.Bar</FONT>  <FONT COLOR="#8A94A6" POINT-SIZE="12">:12</FONT>  ' +
      '<FONT COLOR="#8A94A6" POINT-SIZE="11">&#183; calls</FONT></TD></TR>' +
      '<TR><TD PORT="p2" ALIGN="LEFT" HREF="h2" TITLE=""><FONT COLOR="#1F2933">Baz</FONT>  <FONT COLOR="#8A94A6" POINT-SIZE="12">:</FONT></TD></TR>' +
      '<TR><TD PORT="p3" ALIGN="LEFT"><FONT COLOR="#8A94A6" POINT-SIZE="12">+2 more &amp; &lt;others&gt;</FONT></TD></TR></TABLE>>];'#13#10 +
      '  }'#13#10, Sb.ToString);
    Assert.AreEqual('focus:p1,focus:p2,focus:p3', string.Join(',', Ports), 'one port per row, in row order, notes included');
  finally
    Sb.Free;
  end;
end;

procedure TCoreDotTests.RowClusterRefusesEmptyRow;
begin
  var Sb:= TStringBuilder.Create;
  try
    Assert.WillRaiseWithMessage(
      procedure begin AddRowCluster(Sb, 'cl', 'n', 'T', '', [NoteRow('ok'), NoteRow(' ')], TClusterStyle.Make('', '', '')); end,
      EChartsDot, 'Add-RowCluster (cl): row 2 is empty -- did a , $array return get wrapped in @()?');
  finally
    Sb.Free;
  end;
end;

procedure TCoreDotTests.DotRunRefusesLongPath;
begin
  var Long:= TPath.Combine(TPath.GetTempPath, StringOfChar('x', LONG_NAME) + '.svg');
  Assert.WillRaise(procedure begin DotRun('dot.exe', 'a.dot', Long, 'a.plain', 'a.png', 'a.pdf'); end, EChartsDot);
end;

procedure TCoreDotTests.DotLayoutWritesFourOutputs;
var
  Msgs: TArray<string>;
begin
  var Dir:= TPath.Combine(TPath.GetTempPath, 'charts-dot-' + TGUID.NewGuid.ToString);
  try
    var Exe:= ResolveGraphvizDot('', DragLintSettingsPath, '', '', SHARED_DOT_DEFAULT);
    var L:= DotLayout(Exe, 'digraph G {'#10'  a [URL="draglint://open?file=a&amp;line=1"];'#10'  a -> b;'#10'}'#10, Dir, 'g', Msgs);
    Assert.IsTrue(FileExists(L.Svg) and FileExists(L.Plain) and FileExists(L.Png) and FileExists(L.Pdf), 'four outputs');
    Assert.AreEqual(1, L.Anchors, 'one URL node -> one <a>');
    var Written:= TFile.ReadAllBytes(L.Dot);
    Assert.AreEqual('digraph G {'#13#10, TEncoding.ASCII.GetString(Written, 0, Length('digraph G {'#13#10)), 'CRLF, no BOM');
  finally
    if DirectoryExists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

end.
