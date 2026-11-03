program SyntaxCountTests;
{$APPTYPE CONSOLE}

// GAP-SYNTAXQ: DRagLint.Query.SyntaxCount -- counts syntax features in the
// tree-sitter parse. Embedded fixtures carry each feature AND a decoy that
// must NOT count (not (X is T), not (a in S), '''' , a var section, IfThen).
// Needs the tree-sitter DLLs next to the exe (run_syntaxcount_unit_tests.ps1).

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  TreeSitterLib in '..\..\third_party\delphi-tree-sitter\TreeSitterLib.pas',
  TreeSitter in '..\..\third_party\delphi-tree-sitter\TreeSitter.pas',
  DRagLint.Diagnostics.ParseCache in '..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Query.SyntaxCount in '..\..\src\query\DRagLint.Query.SyntaxCount.pas';

const
  CFixture =
    'unit Fx;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure X;'#13#10 +
    'var a: Integer; o: TObject;'#13#10 +                       // 5: var SECTION, not inline
    'begin'#13#10 +
    '  a := if a > 1 then 2 else 3;'#13#10 +                     // 7: if-expr
    '  a := if a > 1 then (if a > 2 then 4 else 5) else 6;'#13#10 + // 8: if-expr x2
    '  a := IfThen(a > 1, 2, 3);'#13#10 +                        // 9: decoy
    '  if o is not TList then a := 1;'#13#10 +                   // 10: is-not
    '  if not (o is TList) then a := 1;'#13#10 +                 // 11: decoy
    '  if a not in [1, 2] then a := 2;'#13#10 +                  // 12: not-in
    '  if not (a in [1, 2]) then a := 2;'#13#10 +                // 13: decoy
    '  var b := 5;'#13#10 +                                      // 14: inline-var
    '  for var i := 0 to 2 do a := i;'#13#10 +                   // 15: inline-var
    '  var c: Integer;'#13#10 +                                  // 16: inline-var
    '  const k = 3;'#13#10 +                                     // 17: inline-const
    '  var f: TFunc<Integer> := function: Integer begin Result := 1; end;'#13#10 + // 18: inline-var + anon-method
    '  var s := '''''''#13#10 +                                  // 19: inline-var + multiline-string
    '    multi'#13#10 +
    '    ''''''; '#13#10 +
    '  s := '''''''';'#13#10 +                                   // 22: decoy (one quote char)
    'end;'#13#10 +
    'end.'#13#10;

var
  GPass, GFail: Integer;
  GDir: string;

procedure Check(const pName: string; pCond: Boolean);
begin
  if pCond then begin Inc(GPass); Writeln('PASS  ', pName); end
  else begin Inc(GFail); Writeln('FAIL  ', pName); end;
end;

function WriteFixture(const pName, pText: string): string;
begin
  Result:= TPath.Combine(GDir, pName);
  TFile.WriteAllText(Result, pText, TEncoding.ANSI);
end;

procedure TestNames;
var
  LSet: TSyntaxFeatures;
  LBad: string;
begin
  Check('name if-expr', SyntaxFeatureName(sfIfExpr) = 'if-expr');
  Check('name multiline-string', SyntaxFeatureName(sfMultilineString) = 'multiline-string');
  Check('since is-not = Delphi 13', SyntaxFeatureSince(sfIsNot) = 'Delphi 13');
  Check('parse all', TryParseSyntaxFeatures('all', LSet, LBad) and (LSet = [Low(TSyntaxFeature)..High(TSyntaxFeature)]));
  Check('parse empty = all', TryParseSyntaxFeatures('', LSet, LBad) and (LSet = [Low(TSyntaxFeature)..High(TSyntaxFeature)]));
  Check('parse two, any case', TryParseSyntaxFeatures('IS-NOT, if-expr', LSet, LBad) and (LSet = [sfIsNot, sfIfExpr]));
  Check('parse bogus fails', not TryParseSyntaxFeatures('if-expr,bogus', LSet, LBad) and (LBad = 'bogus') and (LSet = []));
end;

procedure TestCounts;
var
  LFile: string;
  R: TSyntaxCountReport;
begin
  LFile:= WriteFixture('Fx.pas', CFixture);
  R:= CountSyntaxFeatures([LFile], [Low(TSyntaxFeature)..High(TSyntaxFeature)], True);
  Check('scanned 1', R.FilesScanned = 1);
  Check('no parse errors', R.FilesWithParseErrors = 0);
  Check('if-expr = 3 (nested counts, IfThen does not)', R.Totals[sfIfExpr] = 3);
  Check('is-not = 1 (not (X is T) does not)', R.Totals[sfIsNot] = 1);
  Check('not-in = 1 (not (a in S) does not)', R.Totals[sfNotIn] = 1);
  Check('inline-var = 5 (var section does not)', R.Totals[sfInlineVar] = 5);
  Check('inline-const = 1', R.Totals[sfInlineConst] = 1);
  Check('anon-method = 1', R.Totals[sfAnonMethod] = 1);
  Check('multiline-string = 1 ('''''''' does not)', R.Totals[sfMultilineString] = 1);
  Check('one file row', (Length(R.Files) = 1) and SameText(R.Files[0].FilePath, LFile));
  Check('hits = sum of totals', Length(R.Hits) = 13);
  Check('is-not hit line 10', (function: Boolean
    var H: TSyntaxHit;
    begin
      Result:= False;
      for H in R.Hits do
        if H.Feature = sfIsNot then Exit((H.Line = 10) and (H.Col > 1));
    end)());
end;

procedure TestFilterAndMissing;
var
  LFile, LMissing: string;
  R: TSyntaxCountReport;
begin
  LFile:= TPath.Combine(GDir, 'Fx.pas');
  LMissing:= TPath.Combine(GDir, 'NoSuchUnit.pas');
  R:= CountSyntaxFeatures([LMissing, LFile], [sfIsNot], False);
  Check('filter: is-not only', (R.Totals[sfIsNot] = 1) and (R.Totals[sfIfExpr] = 0) and (R.Totals[sfInlineVar] = 0));
  Check('filter: no hits when not asked', Length(R.Hits) = 0);
  Check('missing file tallied, not raised', (R.FilesUnreadable = 1) and (R.FilesScanned = 1));
end;

procedure TestJson;
var
  R: TSyntaxCountReport;
  J: TJSONObject;
begin
  R:= CountSyntaxFeatures([TPath.Combine(GDir, 'Fx.pas')], [sfIfExpr, sfNotIn], True);
  J:= SyntaxCountToJson(R, True, True);
  try
    Check('json totals.if-expr = 3', (J.GetValue('totals') is TJSONObject) and
      (TJSONObject(J.GetValue('totals')).GetValue<Integer>('if-expr') = 3));
    Check('json totals has only selected', TJSONObject(J.GetValue('totals')).Count = 2);
    Check('json files_scanned = 1', J.GetValue<Integer>('files_scanned') = 1);
    Check('json hits = 4', (J.GetValue('hits') is TJSONArray) and (TJSONArray(J.GetValue('hits')).Count = 4));
    Check('json files[0].counts.not-in = 1',
      TJSONObject(TJSONObject(TJSONArray(J.GetValue('files')).Items[0]).GetValue('counts')).GetValue<Integer>('not-in') = 1);
  finally
    J.Free;
  end;
end;

begin
  GDir:= TPath.Combine(TPath.GetTempPath, 'syntaxcount_' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(GDir);
  try
    try
      TestNames;
      TestCounts;
      TestFilterAndMissing;
      TestJson;
    except
      on Ex: Exception do begin Writeln('EXCEPTION ', Ex.ClassName, ': ', Ex.Message); Inc(GFail); end;
    end;
  finally
    TDirectory.Delete(GDir, True);
  end;
  Writeln('');
  Writeln(Format('syntaxcount-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
