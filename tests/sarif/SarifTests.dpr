program SarifTests;

// TDD harness for DRagLint.Output.Sarif -- a pure JSON serializer, so it builds
// with a bare dcc64 against the dep-free SARIF + Core.Model units (no DB/FireDAC).

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Output.Sarif in '..\..\src\output\DRagLint.Output.Sarif.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function MkFinding(const ARule, ASeverity, AFile: string; ALine, ACol: Integer; const AMsg: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId  := ARule;
  Result.Severity:= ASeverity;
  Result.FilePath:= AFile;
  Result.StartLine:= ALine; Result.StartCol:= ACol;
  Result.EndLine  := ALine; Result.EndCol  := ACol + 3;
  Result.Message := AMsg;
end;

procedure TestSarifShape;
var
  Findings: TArray<TLintFinding>;
  Root, Run, Driver, Res0: TJSONObject;
  Runs, Rules, Results: TJSONArray;
  Txt: string;
  V: TJSONValue;
begin
  Findings:= [
    MkFinding('used-before-assignment', 'warning', 'C:\proj\A.pas', 10, 3, 'x used before set'),
    MkFinding('object-leak'           , 'info'   , 'C:\proj\A.pas', 20, 1, 'leak'),
    MkFinding('used-before-assignment', 'error'  , 'C:\proj\B.pas',  5, 7, 'y used before set')
  ];
  Txt:= TSarifWriter.ToJson(Findings, '0.66.0-alpha');

  V:= TJSONObject.ParseJSONValue(Txt);
  Check('SARIF parses as JSON', V <> nil);
  if V = nil then Exit;
  try
    Root:= V as TJSONObject;
    Check('version is 2.1.0', Root.GetValue('version').Value = '2.1.0');
    Check('has $schema', Root.GetValue('$schema') <> nil);

    Runs:= Root.GetValue('runs') as TJSONArray;
    Check('one run', Runs.Count = 1);
    Run:= Runs.Items[0] as TJSONObject;

    Driver:= ((Run.GetValue('tool') as TJSONObject).GetValue('driver')) as TJSONObject;
    Check('driver name', Driver.GetValue('name').Value = 'drag-lint');
    Check('driver version', Driver.GetValue('version').Value = '0.66.0-alpha');

    Rules:= Driver.GetValue('rules') as TJSONArray;
    Check('rules deduped to 2 distinct ids', Rules.Count = 2);

    Results:= Run.GetValue('results') as TJSONArray;
    Check('three results', Results.Count = 3);

    Res0:= Results.Items[0] as TJSONObject;
    Check('result0 ruleId', Res0.GetValue('ruleId').Value = 'used-before-assignment');
    Check('result0 level warning->warning', Res0.GetValue('level').Value = 'warning');
    Check('result1 level info->note',
      (Results.Items[1] as TJSONObject).GetValue('level').Value = 'note');
    Check('result2 level error->error',
      (Results.Items[2] as TJSONObject).GetValue('level').Value = 'error');

    var Region0: TJSONObject :=
      (((Res0.GetValue('locations') as TJSONArray).Items[0] as TJSONObject)
        .GetValue('physicalLocation') as TJSONObject).GetValue('region') as TJSONObject;
    Check('result0 region.startLine = 10',
      (Region0.GetValue('startLine') as TJSONNumber).AsInt = 10);
  finally
    V.Free;
  end;
end;

procedure TestZeroCoordinateClamp;
var
  Findings: TArray<TLintFinding>;
  F: TLintFinding;
  Root, Run, Res0, Region0: TJSONObject;
  Runs, Results: TJSONArray;
  Txt: string;
  V: TJSONValue;
begin
  F:= Default(TLintFinding);
  F.RuleId   := 'used-before-assignment';
  F.Severity := 'warning';
  F.FilePath := 'C:\proj\Z.pas';
  F.StartLine:= 0; F.StartCol:= 0;
  F.EndLine  := 0; F.EndCol  := 0;
  F.Message  := 'zero-coord test';
  Findings:= [F];
  Txt:= TSarifWriter.ToJson(Findings, '0.66.0-alpha');

  V:= TJSONObject.ParseJSONValue(Txt);
  Check('clamp: SARIF parses', V <> nil);
  if V = nil then Exit;
  try
    Root:= V as TJSONObject;
    Runs:= Root.GetValue('runs') as TJSONArray;
    Run := Runs.Items[0] as TJSONObject;
    Results:= Run.GetValue('results') as TJSONArray;
    Res0:= Results.Items[0] as TJSONObject;
    Region0:= (((Res0.GetValue('locations') as TJSONArray).Items[0] as TJSONObject)
      .GetValue('physicalLocation') as TJSONObject).GetValue('region') as TJSONObject;
    Check('clamp: startLine 0 -> 1',
      (Region0.GetValue('startLine') as TJSONNumber).AsInt = 1);
    Check('clamp: startColumn 0 -> 1',
      (Region0.GetValue('startColumn') as TJSONNumber).AsInt = 1);
  finally
    V.Free;
  end;
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestSarifShape;
    TestZeroCoordinateClamp;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('sarif-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
