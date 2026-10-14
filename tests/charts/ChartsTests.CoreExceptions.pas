unit ChartsTests.CoreExceptions;

(* Cases for DRagLint.Charts.Exceptions, ported from charts\src\Emit-Common.ps1. The
  synthetic cases are Test-ExceptionPathsHelpers.ps1's own (sections 3, 4, 5 and 7) with the
  answers the PS gives; the index-wide stats run against the FROZEN clone
  charts\scratch\db\CLIENT-Micronite2027.sqlite, values printed by the PS on 2026-10-13. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreExceptionsTests = class
  public
    [Test] procedure RefClassifierFallsBackToPreviousLine;
    [Test] procedure SourceRowsKinds;
    [Test] procedure TryScanNesting;
    [Test] procedure HandlerReraises;
    [Test] procedure WalkPerEdge;
    [Test] procedure NameFilterAndIndexStats;
  end;

implementation

uses
  System.SysUtils, System.Math, System.IOUtils, System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Charts.Index, DRagLint.Charts.Source, DRagLint.Charts.Exceptions;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLIENT_REL = 'charts\scratch\db\CLIENT-Micronite2027.sqlite';
  { Get-ExceptionIndexStats on CLIENT: Candidates|Raise|Handle|Dropped|Stale|RaiseRoutines|HandleRoutines|Files|FreshFiles }
  CLIENT_STATS = '428|168|177|74|9|120|101|75|73';
  POS_SCALE = 100000;
  SITE = 100001;
  DEPTH_FIVE = 5;
  DEPTH_TWO = 2;
  DEPTH_THREE = 3;
  DEPTH_DEEP = 50;
  NODE_THREE = 3;
  CAPPED_A = 7;
  CAPPED_B = 8;
  { the synthetic handler lines of section 5 }
  LINE_RERAISE = 6;
  LINE_OWN_VAR = 7;
  LINE_NEW_OBJ = 8;
  LINE_OTHER_VAR = 9;
  LINE_BARE_RERAISE = 11;
  LINE_BARE_SWALLOW = 12;
  { the skip span of the source-row case }
  SKIP_FROM = 2;
  SKIP_TO = 4;

function FindUp(const pRel: string): string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, pRel)) then
    Exit(TPath.Combine(Root, pRel));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, pRel)) then
      Exit(TPath.Combine(Dir, pRel));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function Ctx(const pBefore, pPrev: string; const pAfter: string = ' do'): TSourceContext;
begin
  Result:= Default(TSourceContext);
  Result.Token:= 'EFoo';
  Result.Before:= pBefore;
  Result.After:= pAfter;
  Result.PrevLine:= pPrev;
end;

procedure TCoreExceptionsTests.RefClassifierFallsBackToPreviousLine;
begin
  Assert.AreEqual('handle', ExceptionRefClass(Ctx('        E: ', 'except on'), 'type_use'), 'on / E: EFoo do');
  Assert.AreEqual('handle', ExceptionRefClass(Ctx('        ', 'except on'), 'type_use'), 'on / EFoo do');
  Assert.AreEqual('handle', ExceptionRefClass(Ctx('   ', 'except on E:'), 'type_use'), 'on E: / EFoo do');
  Assert.AreEqual('handle', ExceptionRefClass(Ctx('  on E: ', 'except'), 'type_use'), 'same line');
  Assert.AreEqual('other', ExceptionRefClass(Ctx('  X: ', 'Foo;'), 'type_use'), 'a label is not on');
  Assert.AreEqual('other', ExceptionRefClass(Ctx('  if E is ', 'begin'), 'type_use'), 'is-test');
  Assert.AreEqual('other', ExceptionRefClass(Ctx('  X: ', 'var'), 'type_use'), 'var decl');
  Assert.AreEqual('raise', ExceptionRefClass(Ctx('    ', '  raise', '.Create(''x'')'), 'read'), 'raise split');
  Assert.AreEqual('other', ExceptionRefClass(Ctx('  raise ', 'begin', ';'), 'read'), 'raise of a var');
  var S:= Ctx('', '');
  S.Stale:= True;
  Assert.AreEqual('stale', ExceptionRefClass(S, 'read'));
end;

function RowsText(const pRows: TArray<TExceptionSourceRow>): string;
begin
  var Parts: TArray<string>:= [];
  for var R in pRows do
    Parts:= Parts + [Format('%s/%d/%d/%s', [R.Kind, R.Line, R.Col, R.Text])];
  Result:= string.Join(' ', Parts);
end;

procedure TCoreExceptionsTests.SourceRowsKinds;
var
  L: TArray<string>;
begin
  L:= ['begin', '  raise;', '  raise E;', '  raise EFoo.Create(''x'');', '  raise MakeErr(1);',
    '  try X; except on E: Exception do ; end;', '  try Y; except', '  Log; end;', '  raise', '  end;',
    '  raise Foo (x);', '  raise Self.EBar . CreateFmt(1);'];
  Assert.AreEqual('reraise/2/3/raise raise-var/3/3/raise E raise-create/4/3/raise raise-other/5/3/raise ' +
    'on-except/6/10/except bare-except/7/10/except reraise/9/3/raise raise-other/11/3/raise raise-create/12/3/raise',
    RowsText(ExceptionSourceRowsIn(L, 1, Length(L), [])), 'raise Foo (x): the atomic whitespace refuses a raise-var');
  var Skip: TArray<TLineSpan>:= [TLineSpan.Make(SKIP_FROM, SKIP_TO)];
  Assert.AreEqual('raise-other/5/3/raise on-except/6/10/except bare-except/7/10/except reraise/9/3/raise ' +
    'raise-other/11/3/raise raise-create/12/3/raise', RowsText(ExceptionSourceRowsIn(L, 1, Length(L), Skip)));
end;

function BlocksText(const pTb: TTryBlocks): string;
begin
  var Sorted:= Copy(pTb.Blocks);
  TArray.Sort<TTryBlock>(Sorted, TComparer<TTryBlock>.Construct(
    function(const pA, pB: TTryBlock): Integer begin Result:= CompareValue(pA.TryPos, pB.TryPos); end));
  var Parts: TArray<string>:= [];
  for var B in Sorted do
    Parts:= Parts + [Format('%d/%s/%s/%d:%d', [B.TryPos div POS_SCALE,
      if B.ExceptPos <> 0 then IntToStr(B.ExceptPos div POS_SCALE) else '-',
      if B.FinallyPos <> 0 then IntToStr(B.FinallyPos div POS_SCALE) else '-', B.EndPos div POS_SCALE, Length(B.OnPos)])];
  Result:= BoolToStr(pTb.Decided, True) + '|' + string.Join(' ', Parts);
end;

function Scan(const pLines: TArray<string>): string;
begin
  Result:= BlocksText(TryBlocks(pLines, 1, Length(pLines)));
end;

procedure TCoreExceptionsTests.TryScanNesting;
begin
  Assert.AreEqual('True|3/-/10/12:0 4/6/-/9:2', Scan(['procedure X;', 'begin', '  try', '    try', '      A;', '    except',
    '      on E: EFoo do B;', '      on E: Exception do C;', '    end;', '  finally', '    D;', '  end;', 'end;']), 'nested try in try');
  Assert.AreEqual('True|5/5/-/5:0', Scan(['procedure X;', 'type TR = record case Integer of 0: (A: Integer); end;', 'begin',
    '  case Y of 1: Z; end;', '  try A; except B; end;', 'end;']), 'case and record');
  Assert.AreEqual('True|', Scan(['procedure X;', 'asm', '  MOV EAX, 1 { try }', 'end;']), 'asm body');
  Assert.AreEqual('False|', Scan(['procedure X;', 'begin', 'end;', 'end;']), 'unbalanced end');
  Assert.AreEqual('False|', Scan(['procedure X;', 'begin', '  finally', 'end;']), 'finally w/o try');
  Assert.AreEqual('True|3/3/-/3:0', Scan(['procedure X;', 'begin', '  try R.End := 1; except end;', 'end;']), 'dotted end');
  var Tb:= TryBlocks(['begin', 'end;', 'end;'], 1, DEPTH_THREE);
  Assert.AreEqual('an `end` at line 3 closes nothing', Tb.Reason);
end;

procedure TCoreExceptionsTests.HandlerReraises;
var
  Syn: TArray<string>;

  function PosOf(pLine: Integer; const pTok: string): Integer;
  begin
    Result:= pLine * POS_SCALE + Syn[pLine - 1].IndexOf(pTok) + 1;
  end;

  function Verdict(pLine: Integer; const pTok: string; pBare: Boolean): string;
  var
    Blk: TTryBlock;
  begin
    var Tb:= TryBlocks(Syn, 1, Length(Syn));
    if not FindHandlerBlock(Tb, PosOf(pLine, pTok), Blk) then
      Exit('no block');
    Result:= BoolToStr(DRagLint.Charts.Exceptions.HandlerReraises(Syn, Blk, PosOf(pLine, pTok), pBare), True);
  end;

begin
  Syn:= ['procedure X;', 'begin', '  try', '    A;', '  except', '    on E: EFoo do begin Log; raise; end;',
    '    on F: EBar do raise F;', '    on G: EBaz do raise EQux.Create(1);', '    on H: EQuux do raise G;',
    '  end;', '  try B; except Log; raise; end;', '  try C; except Log; end;', 'end;'];
  Assert.AreEqual('True', Verdict(LINE_RERAISE, 'EFoo', False), 'raise; in begin..end');
  Assert.AreEqual('True', Verdict(LINE_OWN_VAR, 'EBar', False), 'raise of own variable');
  Assert.AreEqual('False', Verdict(LINE_NEW_OBJ, 'EBaz', False), 'raise of a NEW object');
  Assert.AreEqual('False', Verdict(LINE_OTHER_VAR, 'EQuux', False), 'raise of ANOTHER var');
  Assert.AreEqual('True', Verdict(LINE_BARE_RERAISE, 'except', True), 'bare except, raise;');
  Assert.AreEqual('False', Verdict(LINE_BARE_SWALLOW, 'except', True), 'bare except, swallows');
end;

{ Test-ExceptionPathsHelpers' SynWalk: nodes are ints, an edge 'caller<-callee', StopSet the
  edges whose caller catches; the whole result as one line. }
function SynWalk(const pEdges, pStopSet: TArray<string>; pDepth: Integer; const pUnfetched: TArray<Integer>;
  const pCapped: TArray<TPair<Integer, TArray<Integer>>>; const pHas: TArray<Integer>): string;
begin
  var G:= TExceptionGraph.Create;
  try
    for var E in pEdges do
    begin
      var P:= E.Split(['<-']);
      G.AddCaller(StrToInt(P[1]), StrToInt(P[0]), [SITE]);
      G.MarkFetched(StrToInt(P[1]));
      G.MarkFetched(StrToInt(P[0]));
    end;
    G.MarkFetched(1);
    for var U in pUnfetched do
      G.UnmarkFetched(U);
    for var C in pCapped do
      for var X in C.Value do
        G.AddCapped(C.Key, X);
    var Stops:= pStopSet;
    var Has:= pHas;
    var W:= InvokeExceptionWalk(1, G, pDepth, 'EX',
      function(pCaller, pCallee: Integer; const pSites: TArray<Int64>; const pType: string): TEdgeVerdict
      begin
        Result:= Default(TEdgeVerdict);
        Result.Stopped:= False;
        for var S in Stops do
          if S = Format('%d<-%d', [pCaller, pCallee]) then
            Result.Stopped:= True;
      end,
      function(const pIds: TArray<Integer>): TArray<Integer>
      begin
        Result:= [];
        for var I in pIds do
          for var H in Has do
            if H = I then
              Result:= Result + [I];
      end);
    var Stopped: TArray<string>:= [];
    for var E in W.Edges do
      if E.Verdict.Stopped then
        Stopped:= Stopped + [Format('%d<-%d', [E.Caller, E.Callee])];
    TArray.Sort<string>(Stopped);
    Result:= Format('stops=%s pass=%s esc=%s ends=%s cap=%s eval=%d nocaller=%s', [string.Join(',', Stopped),
      IntsText(W.Passing), IntsText(W.Escapes), IntsText(W.Ends), IntsText(W.Capped), W.Evaluated, BoolToStr(W.FocusNoCaller, True)]);
  finally
    G.Free;
  end;
end;

procedure TCoreExceptionsTests.WalkPerEdge;
begin
  Assert.AreEqual('stops=2<-1 pass=2,3,5 esc= ends=5 cap= eval=3 nocaller=False',
    SynWalk(['2<-1', '3<-1', '2<-3', '5<-2'], ['2<-1'], DEPTH_FIVE, [], [], []), 'catch on one edge, escape on another');
  Assert.AreEqual('stops=2<-1 pass= esc= ends= cap= eval=1 nocaller=False',
    SynWalk(['2<-1', '5<-2'], ['2<-1'], DEPTH_FIVE, [], [], []), 'catch everywhere stops the path');
  Assert.AreEqual('stops= pass=2,3 esc= ends= cap= eval=2 nocaller=False',
    SynWalk(['2<-1', '3<-2', '2<-3'], [], DEPTH_DEEP, [], [], []), 'cycle terminates');
  Assert.AreEqual('stops= pass=2,3 esc=3 ends= cap= eval=2 nocaller=False',
    SynWalk(['2<-1', '3<-2'], [], DEPTH_TWO, [NODE_THREE], [], [NODE_THREE]), 'depth bound escapes');
  Assert.AreEqual('stops= pass=2 esc= ends= cap=7,8 eval=1 nocaller=False',
    SynWalk(['2<-1'], [], DEPTH_FIVE, [], [TPair<Integer, TArray<Integer>>.Create(2, [CAPPED_A, CAPPED_B])], []), 'capped is not no-caller');
  Assert.AreEqual('stops= pass= esc= ends= cap= eval=0 nocaller=True', SynWalk([], [], DEPTH_THREE, [], [], []), 'focus without callers');
end;

procedure TCoreExceptionsTests.NameFilterAndIndexStats;
begin
  Assert.AreEqual('(r.name_text GLOB ''E[A-Z]*[a-z]*'' OR r.name_text = ''Exception'')', ExceptionNameSql('r.name_text'));
  var Db:= FindUp(CLIENT_REL);
  if Db = '' then
  begin
    Assert.Pass('clone missing');
    Exit;
  end;
  var Index:= TChartsIndex.Create(Db);
  var Reader:= TSourceReader.Create(Index);
  var Ex:= TExceptionIndex.Create(Index, Reader);
  try
    Assert.AreEqual('True/False/True/False/False/False', Format('%s/%s/%s/%s/%s/%s', [BoolToStr(Ex.IsExceptionTypeName('EFoo'), True),
      BoolToStr(Ex.IsExceptionTypeName('ERROR_SUCCESS'), True), BoolToStr(Ex.IsExceptionTypeName('Exception'), True),
      BoolToStr(Ex.IsExceptionTypeName('EOPart'), True), BoolToStr(Ex.IsExceptionTypeName('ET'), True),
      BoolToStr(Ex.IsExceptionTypeName('efoo'), True)]), 'case-sensitive pattern; a name declared only as a non-class is out');
    var S:= Ex.IndexStats;
    Assert.AreEqual(CLIENT_STATS, Format('%d|%d|%d|%d|%d|%d|%d|%d|%d', [S.Candidates, S.RaiseSites, S.HandleSites, S.Dropped, S.Stale,
      S.RaiseRoutines, S.HandleRoutines, S.Files, S.FreshFiles]));
  finally
    Ex.Free;
    Reader.Free;
    Index.Free;
  end;
end;

end.
