unit ChartsTests.CoreTraceShim;

(* Cases for DRagLint.Charts.Trace.Shim, the round-trip condition shim and statement readers (a port
  of charts\src\Trace.Walk.ps1 Part 2; task-3-harvest.txt of the d1 ledger holds what the PowerShell
  printed for the same calls, and the PS output is the reference). The expectations are rows of
  text, one per PS call, so a regression names the row. The synthetic cases write the PS arrays to a
  temp .pas and strip it exactly as the PS did; the golden guards read the live ORM3 sources
  (C:\Projects\DB\ORM3), which are the files the indexed clones were built from -- a box without
  that tree passes them vacuously. The fresh-check (AC-14) is the Walk unit's, not tested here.
  Expected conditions are compared whole, never with Contains (ruling T4-R2).

  A guard row is  id|source|exit line|routine start|form|keyword|if line|block|condition|reason|exit arg
  where '*' in the if line, block, condition, reason or exit arg column means "not harvested, not checked". *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreTraceShimTests = class
  public
    [Test] procedure SyntheticGuards;
    [Test] procedure ShapesTheLineCountWalkMisread;
    [Test] procedure FixRoundOneNamedUnknowns;
    [Test] procedure TheTwelveGoldenGuardsAreQuotedVerbatim;
    [Test] procedure Guard3990BlockIsTheCancelBranch;
    [Test] procedure GoldenGuardSideCases;
    [Test] procedure Guard612QuotesFirstAndLastOfEleven;
    [Test] procedure EnclosingConditionAndChain;
    [Test] procedure GuardFailSpanAndConditionSpan;
    [Test] procedure StatementSpanReadsFiveInputs;
    [Test] procedure ReceiverAndRhsReaders;
    [Test] procedure AssignExpressionReaders;
    [Test] procedure LiteralSourceTextReadsTheToken;
    [Test] procedure OtherTableBranchReadsSevenConditions;
    [Test] procedure TraceTextHelpers;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, DRagLint.Charts.Source, DRagLint.Charts.Trace.Shim;

const
  VM_PAS = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas';  // dl:ok hardcoded-absolute-path@2e6b -- REVIEWED 2026-10-17: the live ORM3 source the indexed clones were built from; the test passes vacuously when the tree is absent, so the path is the fixture, not configuration
  GT_PAS = 'C:\Projects\DB\ORM3\SERVER\uGenericTableRoute.pas';  // dl:ok hardcoded-absolute-path@3ad1 -- REVIEWED 2026-10-17: the live ORM3 source the indexed clones were built from; the test passes vacuously when the tree is absent, so the path is the fixture, not configuration
  PS_PAS = 'C:\Projects\DB\ORM3\SERVER\uPipeSessionBuilder.pas';  // dl:ok hardcoded-absolute-path@0a16 -- REVIEWED 2026-10-17: the live ORM3 source the indexed clones were built from; the test passes vacuously when the tree is absent, so the path is the fixture, not configuration
  SKIP = '*';
  { guard row columns }
  C_ID = 0;
  C_SRC = 1;
  C_EXIT = 2;
  C_START = 3;
  C_FORM = 4;
  C_KW = 5;
  C_IF = 6;
  C_BLK = 7;
  C_COND = 8;
  C_REASON = 9;
  C_ARG = 10;
  { field columns of the small tables }
  FLD_C = 2;
  FLD_D = 3;
  FLD_E = 4;
  FLD_F = 5;
  FLD_G = 6;
  FLD_H = 7;
  FLD_I = 8;
  { lengths of the generated long texts }
  WORD_DEFAULT_CUT = 69;
  WORD_LONG = 80;
  STOP_LONG = 100;
  { the golden guards as the PS printed them (Test-RoundTripHelpers.ps1 section 4) }
  GUARDS: array[0..11] of string = (
    'G1|VM|3950|3948|inline|UNLESS|3950|3950-3950|FSuppressEvents||*',
    'G2|VM|3973|3960|inline|UNLESS|3973|3973-3973|FMTOperation.ChangeCount = 0||*',
    'G3|VM|3974|3960|inline|UNLESS|3974|3974-3974|not (Assigned(FConn) and FConn.Connected)||*',
    'G4|GT|415|389|block|UNLESS|411|412-416|TableName = ''''||*',
    'G5|GT|425|389|block|UNLESS|421|422-426|Length(StreamBytes) = 0||*',
    'G6|GT|435|389|block|UNLESS|431|432-436|not GDatasetsDef.GetTable(TableName, Def)||*',
    'G7|GT|451|389|except|UNLESS|446|446-453|Mem.LoadFromStream(MS, sfBinary) raises||*',
    'G8|GT|200|183|block|UNLESS|196|197-201|SQL = ''''||*',
    'G9|VM|1133|1123|inline|UNLESS|1133|1133-1133|not (Assigned(FConn) and FConn.Connected)||*',
    'G10|PS|530|502|block|UNLESS|525|526-531|not GDatasetsDef.GetTable(ATableName, Def)||*',
    'G11|PS|554|502|block|UNLESS|549|550-555|not TryBuildSafeWhere(WhereStr, Def, WhereSql, WhereVals)||*',
    'G12|VM|1140|1123|block|UNLESS|1137|1138-1141|(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspData)||*');
  GUARD_3990: array[0..0] of string = (
    'G3990|VM|4004|3960|block|UNLESS|3990|3991-4005|(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK)||*');
  GUARD_SIDE: array[0..1] of string = (
    'G3973|VM|3973|3960|inline|UNLESS|*|*|FMTOperation.ChangeCount = 0||True',
    'G193|GT|193|183|case|UNLESS|*|*|*||*');
  GUARD_612: array[0..0] of string = (
    'G612|PS|612|502|except|UNLESS|605|605-614|T0Open:= GetTickCount64 ... AThreadStorage.Transaction.Commit raises||*');
  { Test-RoundTripHelpers.ps1 section 4: $syn }
  SYN: array[0..15] of string = (
    'procedure P;', 'begin', '  if (A = 1) or', '     (B = 2) then', '  begin', '    Exit;', '  end;',
    '  if C then X else Exit;', '  try', '    Load(S);', '  except', '    on E: Exception do begin',
    '      Exit;', '    end;', '  end;', 'end;');
  SYN_ROWS: array[0..2] of string = (
    'S1|SYN|6|1|block|UNLESS|3|*|(A = 1) or (B = 2)||*',
    'S2|SYN|8|1|inline|WHEN|*|*|C||*',
    'S3|SYN|13|1|except|UNLESS|11|*|Load(S) raises||*');
  { $shp: a real .pas so comments and strings are stripped as in the corpus }
  SHAPES: array[0..46] of string = (
    'procedure P1;', 'begin', '  if (S = ''a  b'') or  // why', '     (T = 1) then', '  begin', '    Exit;', '  end;', 'end;',
    'procedure P2;', 'begin', '  if C then', '  begin', '    X;', '  end else begin', '    Exit;', '  end;', 'end;',
    'procedure P3;', 'begin', '  if D { note } then', '    Exit;', 'end;',
    'procedure P4;', 'begin', '  if S = ''"'' then Exit;', 'end;',
    'procedure P5;', 'begin', '  while X do begin', '    Exit;', '  end;', 'end;',
    'procedure P6;', 'begin', '  case K of', '    1: Exit;', '  end;', 'end;',
    'procedure P7;', 'begin', '  if A then Y;', '  Exit;', 'end;',
    'procedure P8;', 'begin', '  if S = ''a -- b'' then Exit;', 'end;');
  SHAPE_ROWS: array[0..7] of string = (
    'P1|SHP|6|1|block|UNLESS|3|5-7|(S = ''a  b'') or (T = 1)||*',
    'P2|SHP|15|9|block|WHEN|11|14-16|C||*',
    'P3|SHP|21|18|block|UNLESS|20|21-21|D||*',
    'P4|SHP|25|23|inline|UNLESS|25|25-25|S = ''"''||*',
    'P5|SHP|30|27|unknown||0|0-0||the Exit at :30 sits under a while statement, a shape the source shim does not read|*',
    'P6|SHP|36|33|unknown||0|0-0||the Exit at :36 sits in a case arm, a shape the source shim does not read|*',
    'P7|SHP|42|39|unknown||0|0-0||the Exit at :42 is not inside a branch, a shape the source shim does not read|*',
    'P8|SHP|46|44|unknown||0|0-0||the condition over the Exit at :46 carries '' -- '', which reads as its note -- a Form A condition cannot carry it verbatim|*');
  { $fx: fix round 1 of the PS review }
  FIXES: array[0..34] of string = (
    'procedure F1;', 'begin', '  if A then begin X; Exit; end else begin Y; Exit; end;', 'end;',
    'procedure F2;', 'begin', '  if A and { first line', '  don''t } B then', '    Exit;', 'end;',
    'procedure F3;', 'begin', '  if A and (* first', '  // *) B then', '    Exit;', 'end;',
    'procedure F4;', 'begin', '  {$IFDEF X} if A then {$ELSE} if B then {$ENDIF} Exit;', 'end;',
    'procedure F5;', 'begin', '{$IFDEF X}', '  if A then', '{$ELSE}', '  if B then', '{$ENDIF}', '    Exit;', 'end;',
    'procedure F6;', 'begin', '  if A and { c } B or', '     C then', '    Exit;', 'end;');
  FIX_ROWS: array[0..5] of string = (
    'F1|FIX|3|1|unknown||*|*||the Exit at :3 shares its line with another Exit, a shape the source shim does not read|*',
    'F2|FIX|9|5|unknown||*|*||the Exit at :9 has a condition that wraps a comment across lines, a shape the source shim does not read|*',
    'F3|FIX|15|11|unknown||*|*||the Exit at :15 has a condition that wraps a comment across lines, a shape the source shim does not read|*',
    'F4|FIX|19|17|unknown||*|*||the Exit at :19 sits under a conditional-compilation directive, a shape the source shim does not read|*',
    'F5|FIX|28|21|unknown||*|*||the Exit at :28 sits under a conditional-compilation directive, a shape the source shim does not read|*',
    'F6|FIX|34|30|block|UNLESS|*|*|A and { c } B or C||*');
  { enclosing statement: id|line|col|routine start|form|keyword|condition|if line|stmt line:col }
  ENC_ROWS: array[0..0] of string = (
    'E1|6|4|1|block|WHEN|(A = 1) or (B = 2)|3|3:2');
  { chain: id|line|col|routine start|the chain as form:keyword:condition joined by ' / ' }
  CHAIN_ROWS: array[0..0] of string = (
    'C1|13|6|1|except:WHEN:Load(S) raises');
  { fail span: source|exit line|expected  (keyword line:from-to, or none) }
  FAIL_SRC_WHEN: array[0..3] of string = ('procedure P;', 'begin', '  if A then Exit else X;', 'end;');
  FAIL_SRC_ELSE: array[0..3] of string = ('procedure P;', 'begin', '  if A then X else Exit;', 'end;');
  FAIL_ROWS: array[0..4] of string = (
    'SYN|6|UNLESS 4:13-17',
    'SYN|8|WHEN 8:14-24',
    'SYN|13|none',
    'WHEN|3|UNLESS 3:7-17',
    'ELSE|3|WHEN 3:14-24');
  { in condition: exit line|line|column|expected }
  INCOND_ROWS: array[0..6] of string = (
    '6|3|5|True', '6|3|3|False', '6|3|4|False', '6|4|15|False', '6|4|14|False', '6|6|1|False', '13|11|1|False');
  { statement spans: kind|line|col|last line|L1,C1,L2,C2,AssignLine,AssignCol }
  SPAN_ROWS: array[0..4] of string = (
    '1|1|2|1|1,2,1,7,1,3',
    '2|1|2|3|1,2,2,12,1,7',
    '3|1|2|1|1,2,1,22,1,13',
    '4|1|2|2|1,2,1,24,1,3',
    '5|2|4|3|2,4,3,2,2,5');
  { in the rhs of the kind-2 span: line|column|expected }
  RHS_ROWS: array[0..4] of string = ('2|3|True', '1|2|False', '1|8|True', '3|0|False', '2|9|True');
  { receiver start: text|member column|expected }
  RECV_ROWS: array[0..4] of string = (
    'X.Foo.Bar|6|0', 'Foo.Bar|4|0', 'Bar|0|-1', 'A . B|4|0', 'X.Y(1).Z|7|-1');
  { assign expression: raw line|column|expected }
  ASSIGN_ROWS: array[0..4] of string = (
    '  X:= 1;|3|1',
    '  if W <> '''' then SQL:= SQL + ''a;b'';|20|SQL + ''a;b''',
    '  X:= 1|3|',
    '  foo;|3|',
    '  X:= Y + ''z''; // c|3|Y + ''z''');
  { concat expression: raw line|expected }
  CONCAT_ROWS: array[0..4] of string = (
    '  SQL:= SQL + ''x'';|SQL + ''x''',
    '  SQL:= ''x'';|',
    '  SQL:= ''a+b'';|',
    '  X.Y:= A + B; Z;|A + B; Z',
    '  SQL:= A + B|');
  { literal source text: text|col|ecol|raw line|has raw|expected }
  LIT_ROWS: array[0..3] of string = (
    'abc|6|11|  X:= ''abc'';|1|''abc''',
    'ab|6|9|  X:= ''abc'';|1|''ab''',
    'it''s|1|3||0|''it''''s''',
    'a''b|6|12|  X:= ''a''''b'';|1|''a''''b''');
  { other-table branch: keyword|condition|anchor table|tables (comma list)|expected }
  OTHER_ROWS: array[0..6] of string = (
    'WHEN|TableName = ''FOO''|OPERAT|FOO,OPERAT|True',
    'WHEN|TableName = ''OPERAT''|OPERAT|FOO,OPERAT|False',
    'UNLESS|TableName = ''FOO''|OPERAT|FOO|False',
    'WHEN|''FOO'' = T|OPERAT|foo|True',
    'WHEN|(T = ''FOO'') or X|OPERAT|FOO|False',
    'WHEN|T <> ''FOO''|OPERAT|FOO|False',
    'WHEN|T = ''BAR''|OPERAT|FOO|False');
  { text helpers: input|max (empty: the default)|expected }
  WORD_ROWS: array[0..3] of string = (
    'X.Fields[0].DataSet [by name]||X.Fields[0].DataSet (by name]',
    'a  b -- c @d [e] "q" f; g||a b - c at d (e] ''q'' f, g',
    '  padded   text |8|padde...',
    '||');
  STOP_ROWS: array[0..3] of string = (
    'a  b -- c @d [e] f; g|a b - c at d (e) f, g',
    'lots   of  [x y] words [z|lots of (x y) words (z',
    'plain|plain',
    '|');
  NOTE_ROWS: array[0..2] of string = ('a; b; c|a, b, c', 'none|none', '|');
  { anchor file|reference file (empty: TraceAnchorText of the first)|line|expected }
  LOC_ROWS: array[0..3] of string = (
    'a\X.pas|b\x.PAS|5|:5', 'a\X.pas|a\Y.pas|7|Y.pas:7', 'X.pas|Z.pas|0|Z.pas:0', 'a\b\Foo.pas||12|Foo.pas:12');

function Fields(const pRow: string): TArray<string>;
begin
  Result:= pRow.Split(['|']);
end;

function Lines(const pArr: array of string): TArray<string>;
begin
  SetLength(Result, Length(pArr));
  for var I:= Low(pArr) to High(pArr) do
    Result[I]:= pArr[I];
end;

{ writes the PS array as the PS did (ASCII, CRLF, final break) and returns the raw and stripped line arrays }
procedure ReadBack(const pArr: array of string; const pName: string; out pRaw, pStripped: TArray<string>);
begin
  var Path:= TPath.Combine(TPath.GetTempPath, 'dl-shim-' + pName + '.pas');
  var Sb:= TStringBuilder.Create;
  try
    for var S in pArr do
      Sb.Append(S).Append(#13#10);
    TFile.WriteAllText(Path, Sb.ToString, TEncoding.ASCII);
  finally
    Sb.Free;
  end;
  var Rd:= TSourceReader.Create(nil);
  try
    pStripped:= Rd.StrippedSourceLines(Path);
    pRaw:= SplitLines(ReadLatin1(Path));
  finally
    Rd.Free;
  end;
end;

{ a golden source read through the reader's path hook; False when the ORM3 tree is absent }
function GoldenLines(const pPath: string; out pRaw, pStripped: TArray<string>): Boolean;
begin
  pRaw:= nil;
  pStripped:= nil;
  Result:= TFile.Exists(pPath);
  if not Result then
    Exit;
  var Rd:= TSourceReader.Create(nil);
  try
    pStripped:= Rd.StrippedSourceLines(Rd.ReadPath(pPath));
    pRaw:= SplitLines(ReadLatin1(Rd.ReadPath(pPath)));
  finally
    Rd.Free;
  end;
end;

{ the lines a source tag names; False when the golden tree is absent }
function SourceLines(const pTag: string; out pRaw, pStripped: TArray<string>): Boolean;
begin
  pRaw:= nil;
  pStripped:= nil;
  Result:= True;
  if pTag = 'SYN' then
  begin
    pRaw:= Lines(SYN);
    pStripped:= pRaw;
  end
  else if pTag = 'SHP' then
    ReadBack(SHAPES, 'shapes', pRaw, pStripped)
  else if pTag = 'FIX' then
    ReadBack(FIXES, 'fix1', pRaw, pStripped)
  else if pTag = 'VM' then
    Result:= GoldenLines(VM_PAS, pRaw, pStripped)
  else if pTag = 'GT' then
    Result:= GoldenLines(GT_PAS, pRaw, pStripped)
  else
    Result:= GoldenLines(PS_PAS, pRaw, pStripped);
end;

procedure Same(const pExpected, pActual, pRow: string);
begin
  if pExpected <> SKIP then
    Assert.AreEqual(pExpected, pActual, pRow);
end;

{ runs one guard row against the shim; the golden tree being absent skips it }
procedure CheckGuardRow(const pRow: string);
begin
  var F:= Fields(pRow);
  var Raw, Stripped: TArray<string>;
  if not SourceLines(F[C_SRC], Raw, Stripped) then
    Exit;
  var R:= GuardConditionFromLines(Raw, Stripped, StrToInt(F[C_EXIT]), StrToInt(F[C_START]));
  Assert.AreEqual(F[C_FORM], R.Form, pRow);
  Assert.AreEqual(F[C_KW], R.Keyword, pRow);
  Same(F[C_IF], IntToStr(R.IfLine), pRow);
  Same(F[C_BLK], IntToStr(R.BlockStart) + '-' + IntToStr(R.BlockEnd), pRow);
  Same(F[C_COND], R.Condition, pRow);
  Same(F[C_REASON], R.Reason, pRow);
  Same(F[C_ARG], R.ExitArg, pRow);
end;

procedure CheckRows(const pRows: array of string);
begin
  for var Row in pRows do
    CheckGuardRow(Row);
end;

function SpanSource(const pKind: string): TArray<string>;
begin
  if pKind = '1' then
    Result:= Lines(['  X:= 1;'])
  else if pKind = '2' then
    Result:= Lines(['  Q.SQL:= A +', '     B + ''x'';', '  Y;'])
  else if pKind = '3' then
    Result:= Lines(['  if W then Y:= (1;2) else Z:= 3;'])
  else if pKind = '4' then
    Result:= Lines(['  V:= if A then 1 else 2;', '  W;'])
  else
    Result:= Lines(['  begin', '    X:= 1', '  end;']);
end;

{ the stripped copy of a one-line snippet: string literals blanked column for column }
function Blank(const pRaw: string): string;
begin
  var InStr:= False;
  Result:= pRaw;
  for var I:= 1 to Length(pRaw) do
  begin
    if InStr then
      Result[I]:= ' ';
    if pRaw[I] = '''' then
    begin
      Result[I]:= ' ';
      InStr:= not InStr;
    end;
  end;
end;

function SpanText(const pSp: TStatementSpan): string;
begin
  Result:= Format('%d,%d,%d,%d,%d,%d', [pSp.L1, pSp.C1, pSp.L2, pSp.C2, pSp.AssignLine, pSp.AssignCol]);
end;

function ChainText(const pChain: TArray<TShimResult>): string;
begin
  var Items: TArray<string>:= [];
  for var E in pChain do
    Items:= Items + [E.Form + ':' + E.Keyword + ':' + E.Condition];
  Result:= string.Join(' / ', Items);
end;

procedure TCoreTraceShimTests.SyntheticGuards;
begin
  CheckRows(SYN_ROWS);
end;

procedure TCoreTraceShimTests.ShapesTheLineCountWalkMisread;
begin
  CheckRows(SHAPE_ROWS);
end;

procedure TCoreTraceShimTests.FixRoundOneNamedUnknowns;
begin
  CheckRows(FIX_ROWS);
end;

procedure TCoreTraceShimTests.TheTwelveGoldenGuardsAreQuotedVerbatim;
begin
  CheckRows(GUARDS);
  Assert.Pass;
end;

procedure TCoreTraceShimTests.Guard3990BlockIsTheCancelBranch;
begin
  CheckRows(GUARD_3990);
  Assert.Pass;
end;

procedure TCoreTraceShimTests.GoldenGuardSideCases;
begin
  CheckRows(GUARD_SIDE);
  Assert.Pass;
end;

procedure TCoreTraceShimTests.Guard612QuotesFirstAndLastOfEleven;
begin
  CheckRows(GUARD_612);
  Assert.Pass;
end;

procedure TCoreTraceShimTests.EnclosingConditionAndChain;
begin
  var Raw:= Lines(SYN);
  for var Row in ENC_ROWS do
  begin
    var F:= Fields(Row);
    var E:= EnclosingConditionFromLines(Raw, Raw, StrToInt(F[1]), StrToInt(F[FLD_C]), StrToInt(F[FLD_D]));
    Assert.AreEqual(F[FLD_E] + '|' + F[FLD_F] + '|' + F[FLD_G] + '|' + F[FLD_H] + '|' + F[FLD_I],
      Format('%s|%s|%s|%d|%d:%d', [E.Form, E.Keyword, E.Condition, E.IfLine, E.StmtLine, E.StmtCol]), Row);
  end;
  for var Row in CHAIN_ROWS do
  begin
    var F:= Fields(Row);
    var Line:= StrToInt(F[1]);
    var Col:= StrToInt(F[FLD_C]);
    var Start:= StrToInt(F[FLD_D]);
    Assert.AreEqual(F[FLD_E], ChainText(EnclosingChainFromLines(Raw, Raw, Line, Col, Start)), Row);
    { the tokens passed down give the same answer }
    Assert.AreEqual(F[FLD_E], ChainText(EnclosingChainFromLines(Raw, Raw, Line, Col, Start, ShimTokens(Raw, Start, Line))), Row);
  end;
end;

procedure TCoreTraceShimTests.GuardFailSpanAndConditionSpan;
begin
  for var Row in FAIL_ROWS do
  begin
    var F:= Fields(Row);
    var Raw:= Lines(SYN);
    if F[0] = 'WHEN' then
      Raw:= Lines(FAIL_SRC_WHEN)
    else if F[0] = 'ELSE' then
      Raw:= Lines(FAIL_SRC_ELSE);
    var G:= GuardConditionFromLines(Raw, Raw, StrToInt(F[1]), 1);
    var Got:= 'none';
    var Sp:= GuardFailSpan(G, Raw[G.CondL2 - 1]);
    if Sp.Found then
      Got:= Format('%s %d:%d-%d', [G.Keyword, Sp.Line, Sp.FromCol, Sp.ToCol]);
    Assert.AreEqual(F[FLD_C], Got, Row);
  end;
  { Test-InShimCondition: columns are 1-based }
  var Syn:= Lines(SYN);
  for var Row in INCOND_ROWS do
  begin
    var F:= Fields(Row);
    var G:= GuardConditionFromLines(Syn, Syn, StrToInt(F[0]), 1);
    Assert.AreEqual(F[FLD_D], BoolToStr(InShimCondition(G, StrToInt(F[1]), StrToInt(F[FLD_C])), True), Row);
  end;
end;

procedure TCoreTraceShimTests.StatementSpanReadsFiveInputs;
begin
  for var Row in SPAN_ROWS do
  begin
    var F:= Fields(Row);
    var Sp:= StatementSpan(SpanSource(F[0]), StrToInt(F[1]), StrToInt(F[FLD_C]), StrToInt(F[FLD_D]));
    Assert.AreEqual(F[FLD_E], SpanText(Sp), Row);
  end;
end;

procedure TCoreTraceShimTests.ReceiverAndRhsReaders;
begin
  var Src:= SpanSource('2');
  var Sp:= StatementSpan(Src, 1, 2, Length(Src));
  for var Row in RHS_ROWS do
  begin
    var F:= Fields(Row);
    Assert.AreEqual(F[FLD_C], BoolToStr(InStatementRhs(Sp, StrToInt(F[0]), StrToInt(F[1])), True), Row);
  end;
  for var Row in RECV_ROWS do
  begin
    var F:= Fields(Row);
    Assert.AreEqual(F[FLD_C], IntToStr(ReceiverStart(F[0], StrToInt(F[1]))), Row);
  end;
end;

procedure TCoreTraceShimTests.AssignExpressionReaders;
begin
  for var Row in ASSIGN_ROWS do
  begin
    var F:= Fields(Row);
    Assert.AreEqual(F[FLD_C], AssignExprAt(F[0], Blank(F[0]), StrToInt(F[1])), Row);
  end;
  for var Row in CONCAT_ROWS do
  begin
    var F:= Fields(Row);
    Assert.AreEqual(F[1], ConcatAssignExpr(F[0], Blank(F[0])), Row);
  end;
end;

procedure TCoreTraceShimTests.LiteralSourceTextReadsTheToken;
begin
  for var Row in LIT_ROWS do
  begin
    var F:= Fields(Row);
    Assert.AreEqual(F[FLD_F], LiteralSourceText(F[0], StrToInt(F[1]), StrToInt(F[FLD_C]), F[FLD_D], F[FLD_E] = '1'), Row);
  end;
end;

procedure TCoreTraceShimTests.OtherTableBranchReadsSevenConditions;
begin
  for var Row in OTHER_ROWS do
  begin
    var F:= Fields(Row);
    Assert.AreEqual(F[FLD_E], BoolToStr(OtherTableBranch(F[0], F[1], F[FLD_C], F[FLD_D].Split([','])), True), Row);
  end;
end;

procedure TCoreTraceShimTests.TraceTextHelpers;
begin
  for var Row in WORD_ROWS do
  begin
    var F:= Fields(Row);
    var Got:= TraceWord(F[0]);
    if F[1] <> '' then
      Got:= TraceWord(F[0], StrToInt(F[1]));
    Assert.AreEqual(F[FLD_C], Got, Row);
  end;
  Assert.AreEqual(StringOfChar('x', WORD_DEFAULT_CUT) + '...', TraceWord(StringOfChar('x', WORD_LONG)));
  for var Row in STOP_ROWS do
  begin
    var F:= Fields(Row);
    Assert.AreEqual(F[1], TraceStopText(F[0]), Row);
  end;
  Assert.AreEqual(StringOfChar('y', STOP_LONG), TraceStopText(StringOfChar('y', STOP_LONG)));
  for var Row in NOTE_ROWS do
  begin
    var F:= Fields(Row);
    Assert.AreEqual(F[1], TraceNoteText(F[0]), Row);
  end;
  for var Row in LOC_ROWS do
  begin
    var F:= Fields(Row);
    if F[1] = '' then
      Assert.AreEqual(F[FLD_D], TraceAnchorText(F[0], StrToInt(F[FLD_C])), Row)
    else
      Assert.AreEqual(F[FLD_D], TraceNoteLocator(F[0], F[1], StrToInt(F[FLD_C])), Row);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreTraceShimTests);

end.
