unit ChartsTests.Questions;

{ Cases for the ported chart questions (DRagLint.Charts.Q.*), each run in-process against
  its FROZEN clone under charts\scratch\db (never a live index; a missing clone passes with
  a note, as the other clone-backed fixtures do). Every expected value -- the emitter's
  counts, the sha256 of graph.dot, the answer lines -- was printed by the PowerShell
  question itself (Ask-Report.ps1 -Plain over New-DiagramArtifact.ps1 and the emitter) on
  2026-10-13 against the same clone (spec P3: the PS output is the reference). dot.exe runs:
  ResolveGraphvizDot finds it as the PS does. }

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.Question;

type
  /// <summary>Shared setup: the repo, a scratch bundle root, a question's arguments.</summary>
  TQuestionFixture = class
  protected
    FOutRoot: string;
    function Args(const pQuestion, pTarget, pCloneName: string; out pArgs: TQuestionArgs): Boolean;
    function Fields(const pChart: TChartResult): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
  end;

  [TestFixture]
  TTouchesTablesTests = class(TQuestionFixture)
  public
    [Test] procedure EmitterMatchesPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure ClientIndexIsRefused;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Hash, DRagLint.Charts.ReportHeader, DRagLint.Charts.Ask,
  DRagLint.Charts.Q.TouchesTables;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CHARTS_MARK = 'charts\src\Ask-Report.ps1';
  CLONE_DIR = 'charts\scratch\db';
  SERVER_CLONE = 'SERVER-MicroniteMW1Service.sqlite';
  CLIENT_CLONE = 'CLIENT-Micronite2027.sqlite';
  TT_TARGET = 'uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation';
  TT_FIELDS = 'Reads=5,Writes=5,Both=2,Distinct=8,Unresolved=0,IndexSqlSymbols=250,ClickTargets=11,Expected=11,AllClickable=true';
  TT_DOT_SHA = '01544eda433cfd8e44ad60c662e7f515dc54fe9561c4be0e4aa27d3b316b48b5';
  TT_ANCHORS = 11;
  TT_READS = 5;
  { the answer after the header sentence, with the BUNDLE line left out (it names the root) }
  TT_ANSWER =
    'COMMAND touches-tables -Target "uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation"|' +
    'INDEX <db>|' +
    'CHART touches-tables uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation -- 5 tables read / 5 tables written|' +
    '  TARGET uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation @uPipeSessionBuilder.pas:1381|' +
    '  COMPGRP (read) @uPipeSessionBuilder.pas:1600|' +
    '  DRA1 (read) @uPipeSessionBuilder.pas:1654|' +
    '  MSCLIST (read) @uPipeSessionBuilder.pas:1563|' +
    '  PROCPARO (read) @uPipeSessionBuilder.pas:1697|' +
    '  PROCPART (read) @uPipeSessionBuilder.pas:1700|' +
    '  DRA2 (written) @uPipeSessionBuilder.pas:1649|' +
    '  PROCPARO (written) @uPipeSessionBuilder.pas:1697|' +
    '  PROCPART (written) @uPipeSessionBuilder.pas:1700|' +
    '  TOOLASSG (written) @uPipeSessionBuilder.pas:1675|' +
    '  TOOLFLDR (written) @uPipeSessionBuilder.pas:1681';
  BUNDLE_LINE = 2;

function RepoRoot: string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, CHARTS_MARK)) then
    Exit(Root);
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, CHARTS_MARK)) then
      Exit(Dir);
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function FileSha(const pPath: string): string;
begin
  var H:= THashSHA2.Create(THashSHA2.TSHA2Version.SHA256); // dl:ok object-leak@2527 -- THashSHA2 is a record, not a class: nothing to free
  H.Update(TFile.ReadAllBytes(pPath));
  Result:= H.HashAsString;
end;

procedure TQuestionFixture.Setup;
begin
  FOutRoot:= TPath.Combine(TPath.GetTempPath, 'drag-lint-charts-q-' + TGUID.NewGuid.ToString);
end;

procedure TQuestionFixture.TearDown;
begin
  if TDirectory.Exists(FOutRoot) then
    TDirectory.Delete(FOutRoot, True);
end;

function TQuestionFixture.Args(const pQuestion, pTarget, pCloneName: string; out pArgs: TQuestionArgs): Boolean;
begin
  pArgs:= Default(TQuestionArgs);
  var Root:= RepoRoot;
  var Db:= if Root = '' then '' else TPath.Combine(TPath.Combine(Root, CLONE_DIR), pCloneName);
  Result:= (Db <> '') and TFile.Exists(Db);
  if not Result then
  begin
    Assert.Pass('clone missing: ' + pCloneName);
    Exit;
  end;
  pArgs.Question:= pQuestion;
  pArgs.Target:= pTarget;
  pArgs.DbPath:= Db;
  pArgs.OutRoot:= FOutRoot;
  pArgs.ChartsRoot:= TPath.Combine(Root, 'charts');
  pArgs.Cap:= DEFAULT_CAP;
  pArgs.Depth:= DEFAULT_DEPTH;
  pArgs.SurfaceCap:= DEFAULT_SURFACE_CAP;
  pArgs.MaxRows:= DEFAULT_MAX_ROWS;
  pArgs.Command.Question:= pQuestion;
  var A: TCommandArg;
  A.Name:= 'Target';
  A.Value:= pTarget;
  pArgs.Command.Args:= [A];
  pArgs.AskedOn:= Now;
  pArgs.EngineVersion:= 'test';
end;

function TQuestionFixture.Fields(const pChart: TChartResult): string;
begin
  var Parts: TArray<string>:= [];
  for var F in pChart.Fields do
    Parts:= Parts + [F.Name + '=' + F.Json];
  Result:= string.Join(',', Parts);
end;

{ ---- touches-tables ---- }

procedure TTouchesTablesTests.EmitterMatchesPowerShell;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(TOUCHES_TABLES_ID, TT_TARGET, SERVER_CLONE, A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(TOUCHES_TABLES_ID, E));
  var C:= E(A, FOutRoot);
  Assert.AreEqual(TT_FIELDS, Fields(C));
  Assert.AreEqual(Int64(TT_READS), C.LeftCount);
  Assert.AreEqual(TT_ANCHORS, C.Layout.Anchors);
  Assert.AreEqual(TT_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TTouchesTablesTests.AnswerMatchesPowerShell;
var
  A: TQuestionArgs;
begin
  if not Args(TOUCHES_TABLES_ID, TT_TARGET, SERVER_CLONE, A) then
    Exit;
  var Answer:= AskChartQuestion(A);
  Assert.AreEqual('Which tables this routine touches (drag-lint report touches-tables) for ' + TT_TARGET + ', asked on ' +
    FormatDateTime('yyyy"-"mm"-"dd hh":"nn', A.AskedOn) + ', engine test.', Answer.Lines[0]);
  Assert.AreEqual('BUNDLE ' + Answer.BundleDir, Answer.Lines[BUNDLE_LINE]);
  var Rest:= Copy(Answer.Lines, 1, MaxInt);
  Delete(Rest, BUNDLE_LINE - 1, 1);
  Assert.AreEqual(TT_ANSWER.Replace('<db>', A.DbPath), string.Join('|', Rest));
  for var F in ['graph.dot', 'graph.svg', 'graph.plain', 'graph.png', 'graph.pdf', 'meta.json', 'index.html', 'xref.txt'] do
    Assert.IsTrue(TFile.Exists(TPath.Combine(Answer.BundleDir, F)), F);
end;

procedure TTouchesTablesTests.ClientIndexIsRefused;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(TOUCHES_TABLES_ID, TT_TARGET, CLIENT_CLONE, A) then
    Exit;
  FindChartQuestion(TOUCHES_TABLES_ID, E);
  var Msg:= '';
  try
    E(A, FOutRoot);
  except
    on X: EChartsQuestion do Msg:= X.Message;
  end;
  Assert.StartsWith('touches-tables: this index has NO SQL facts at all (0 sql_reads, 0 sql_writes across ', Msg);
end;

end.
