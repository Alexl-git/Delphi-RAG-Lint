program VerifyIndexTests;
{$APPTYPE CONSOLE}
{ Pure tests of DRagLint.CLI.VerifyIndex (1.53.0 LSP1-VERB): location parsing, classification,
  skip checks, rate, rendering, sampling SQL. No process, no DB. Spec ACs in the comments;
  plan: docs\superpowers\plans\2026-11-20-verify-index.md Task 4. Built by
  tests\autotest\run_verify_index_tests.ps1. }
uses
  System.SysUtils,
  System.JSON,
  DRagLint.CLI.VerifyIndex;

var
  Failed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then Writeln('  [PASS] ', AName)
  else begin Writeln('  [FAIL] ', AName, '  ', ADetail); Inc(Failed); end;
end;

function Parse(const AJson: string): TArray<TVerifyLocation>;
var
  V: TJSONValue;
begin
  V:= TJSONObject.ParseJSONValue(AJson);
  try
    Result:= ParseDefinitionLocations(V);
  finally
    V.Free;
  end;
end;

function Loc(const APath: string; ALine: Integer): TVerifyLocation;
begin
  Result.Path:= APath;
  Result.Line:= ALine;
end;

function MakeRow: TVerifyRow;
begin
  Result:= Default(TVerifyRow);
  Result.RefId:= 7;
  Result.Kind:= 'call';
  Result.Name:= 'LibProc';
  Result.RefPath:= 'C:\p\Main.pas';
  Result.Line:= 10;
  Result.Col:= 5;
  Result.QName:= 'VerifyLib.LibProc';
  Result.SymPath:= 'C:\p\Lib.pas';
  Result.DeclLine:= 7;
  Result.DeclEnd:= 8;
  Result.ImplLine:= 40;
end;

var
  Locs  : TArray<TVerifyLocation>;
  R     : TVerifyRow;
  C     : TVerifyCounts;
  Opts  : TVerifyOptions;
  Doc   : TJSONObject;
  Rows  : TArray<TVerifyRow>;
  Sql   : string;
  Nul   : TJSONNull;
begin
  Writeln('VerifyIndexTests');
  // T1 (AC11)
  Nul:= TJSONNull.Create;
  try
    Check('T1 null -> 0 locations', Length(ParseDefinitionLocations(Nul)) = 0);
  finally
    Nul.Free;
  end;
  Check('T1b nil -> 0 locations', Length(ParseDefinitionLocations(nil)) = 0);
  // T2
  Locs:= Parse('{"uri":"file:///c%3A/p/Lib.pas","range":{"start":{"line":6,"character":0},"end":{"line":6,"character":3}}}');
  Check('T2 single Location', (Length(Locs) = 1) and (Locs[0].Line = 7) and SameText(Locs[0].Path, 'c:\p\Lib.pas'),
    'got ' + IntToStr(Length(Locs)));
  // T3
  Locs:= Parse('[{"uri":"file:///C:/a.pas","range":{"start":{"line":0,"character":0}}},{"uri":"file:///C:/b.pas","range":{"start":{"line":1,"character":0}}}]');
  Check('T3 Location[] of 2 in order', (Length(Locs) = 2) and (Locs[0].Line = 1) and (Locs[1].Line = 2) and SameText(Locs[1].Path, 'C:\b.pas'));
  // T4
  Locs:= Parse('[{"targetUri":"file:///C:/a.pas","targetRange":{"start":{"line":9,"character":0}},"targetSelectionRange":{"start":{"line":11,"character":0}}}]');
  Check('T4 LocationLink uses targetSelectionRange', (Length(Locs) = 1) and (Locs[0].Line = 12));
  Locs:= Parse('[{"targetUri":"file:///C:/a.pas","targetRange":{"start":{"line":9,"character":0}}}]');
  Check('T4b LocationLink falls back to targetRange', (Length(Locs) = 1) and (Locs[0].Line = 10));
  // T5 (AC8)
  Check('T5 empty array -> 0 locations', Length(Parse('[]')) = 0);

  R:= MakeRow;
  // T6 (AC5)
  Check('T6 same file (case + ..\ segment), line in decl range -> match',
    ClassifyLocations(R, [Loc('c:\P\x\..\LIB.pas', 8)]) = voMatch);
  // T7 (AC6)
  Check('T7 line = ImplLine -> match', ClassifyLocations(R, [Loc('C:\p\Lib.pas', 40)]) = voMatch);
  // T8 (AC7)
  Check('T8 same file, line outside both -> mismatch', ClassifyLocations(R, [Loc('C:\p\Lib.pas', 12)]) = voMismatch);
  // T9
  Check('T9 other file, same line -> mismatch', ClassifyLocations(R, [Loc('C:\p\Other.pas', 7)]) = voMismatch);
  // T10
  Check('T10 two locations, second matches -> match', ClassifyLocations(R, [Loc('C:\p\Other.pas', 7), Loc('C:\p\Lib.pas', 7)]) = voMatch);
  Check('T10b no locations -> empty', ClassifyLocations(R, nil) = voEmpty);

  // T11 (AC10)
  Check('T11 name at column -> ""', SkipReason(R, 'bbb LibProc;') = '');
  Check('T11 name moved -> moved', SkipReason(R, 'x LibProc;') = 'moved');
  Check('T11 non-ASCII before col -> non-ascii', SkipReason(R, 'a' + #$00E4 + 'b LibProc;') = 'non-ascii');
  Check('T11 non-ASCII after the name -> ""', SkipReason(R, 'bbb LibProc; // ' + #$00E4) = '');

  // T12 (AC14)
  C:= Default(TVerifyCounts);
  C.Match:= 180;
  C.Mismatch:= 3;
  Check('T12 rate = 3/183', Abs(MismatchRate(C) - 3 / 183) < 1E-9);
  Check('T12b rate 0 when match+mismatch = 0', MismatchRate(Default(TVerifyCounts)) = 0);
  // T13 (AC12)
  C.Empty:= 12;
  C.Skipped:= 5;
  Check('T13 summary line', SummaryLine('d.sqlite', 200, 1, C) =
    'verify-index: db=d.sqlite sample=200 seed=1 match=180 mismatch=3 empty=12 error=0 skipped=5 rate=1.6%',
    SummaryLine('d.sqlite', 200, 1, C));
  // T14
  R.Outcome:= voMismatch;
  R.Lsp:= [Loc('C:\p\Lib.pas', 12)];
  Check('T14 mismatch row line', RowLine(R) =
    'mismatch'#9'C:\p\Main.pas:10:5'#9'LibProc'#9'call'#9'dl=VerifyLib.LibProc @ C:\p\Lib.pas:7/40'#9'lsp=C:\p\Lib.pas:12',
    RowLine(R));
  // T15 (AC13)
  Opts:= Default(TVerifyOptions);
  Opts.DbPath:= 'd.sqlite';
  Opts.Sample:= 200;
  Opts.Seed:= 1;
  Rows:= [R];
  Doc:= ReportJson(Opts, 'x.exe', C, Rows);
  try
    Check('T15 json keys', (Doc.GetValue<string>('verb') = 'verify-index') and (Doc.GetValue<Integer>('counts.mismatch') = 3)
      and (Abs(Doc.GetValue<Double>('rate') - 0.0164) < 1E-4)
      and (Doc.GetValue<string>('rows[0].outcome') = 'mismatch') and (Doc.GetValue<Integer>('rows[0].dl.line') = 7),
      Doc.ToJSON);
  finally
    Doc.Free;
  end;
  // T16 (AC1-3)
  Sql:= VerifySampleSql(200, 3);
  Check('T16 sampling SQL', (Pos('LIMIT 200', Sql) > 0) and (Pos('3 * 2246822519', Sql) > 0)
    and (Pos('NOT IN (''local_var'',''param'')', Sql) > 0) and (Pos('inc_variant = 0', Sql) > 0), Sql);

  if Failed > 0 then
  begin
    Writeln(Failed, ' FAILED');
    Halt(1);
  end;
  Writeln('ALL PASS');
end.