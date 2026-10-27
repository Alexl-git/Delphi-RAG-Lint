program SarifTests;

// TDD harness for DRagLint.Output.Sarif -- a pure JSON serializer, so it builds
// with a bare dcc64 against the dep-free SARIF + Core.Model units (no DB/FireDAC).

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Lint.Compliance in '..\..\src\lint\DRagLint.Lint.Compliance.pas',
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

function MkLookup: TSarifMetaLookup;
begin
  Result:=
    function(const ARuleId: string; out AMeta: TSarifRuleMeta): Boolean
    begin
      AMeta:= Default(TSarifRuleMeta);
      Result:= True;
      if ARuleId = 'hardcoded-credential' then
      begin
        AMeta.Title:= 'Credential-named variable assigned a literal'; AMeta.Category:= 'security';
        AMeta.Severity:= 'warning'; AMeta.Labels.Cwe:= ['CWE-798']; AMeta.Labels.Cert:= ['MSC41-C'];
      end
      else if ARuleId = 'type-name-prefix' then
      begin
        AMeta.Title:= 'Type name must carry the configured prefix'; AMeta.Category:= 'naming';
        AMeta.Severity:= 'info';
      end
      else Result:= False;
    end;
end;

function RuleOf(ADriver: TJSONObject; const AId: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result:= nil;
  for V in (ADriver.GetValue('rules') as TJSONArray) do
    if (V as TJSONObject).GetValue('id').Value = AId then Exit(V as TJSONObject);
end;

function HasTag(ATags: TJSONArray; const ATag: string): Boolean;
var
  T: TJSONValue;
begin
  Result:= False;
  for T in ATags do if T.Value = ATag then Exit(True);
end;

procedure TestTaxonomies;
var
  Findings: TArray<TLintFinding>;
  V: TJSONValue;
  Run, Driver, Hc, Tp, Rel, Tgt, Comp, Tax0: TJSONObject;
  Tags, Taxa, Rels, Taxs: TJSONArray;
  Txt: string;
begin
  Findings:= [
    MkFinding('hardcoded-credential', 'warning', 'C:\proj\A.pas', 5, 3, 'pw literal'),
    MkFinding('type-name-prefix'    , 'info'   , 'C:\proj\A.pas', 9, 1, 'prefix')
  ];
  Txt:= TSarifWriter.ToJson(Findings, '1.0', MkLookup());
  V:= TJSONObject.ParseJSONValue(Txt);
  Check('taxonomies: SARIF parses', V <> nil);
  if V = nil then Exit;
  try
    Run:= ((V as TJSONObject).GetValue('runs') as TJSONArray).Items[0] as TJSONObject;
    Driver:= (Run.GetValue('tool') as TJSONObject).GetValue('driver') as TJSONObject;
    Check('taxonomies: run.taxonomies is an array', Run.GetValue('taxonomies') is TJSONArray);
    Taxs:= Run.GetValue('taxonomies') as TJSONArray;
    Tax0:= Taxs.Items[0] as TJSONObject;
    Check('taxonomies: first is CWE by MITRE',
      (Tax0.GetValue('name').Value = 'CWE') and (Tax0.GetValue('organization').Value = 'MITRE'));
    Taxa:= Tax0.GetValue('taxa') as TJSONArray;
    Check('taxonomies: CWE taxa holds id 798',
      (Taxa.Count = 1) and ((Taxa.Items[0] as TJSONObject).GetValue('id').Value = '798'));
    Check('taxonomies: CERT present, MISRA absent (no MISRA id in the run)',
      (Taxs.Count = 2) and ((Taxs.Items[1] as TJSONObject).GetValue('name').Value = 'CERT'));

    Hc:= RuleOf(Driver, 'hardcoded-credential');
    Check('rule: name = id', Hc.GetValue('name').Value = 'hardcoded-credential');
    Check('rule: shortDescription.text = catalog title',
      ((Hc.GetValue('shortDescription') as TJSONObject).GetValue('text').Value) = 'Credential-named variable assigned a literal');
    Check('rule: defaultConfiguration.level = warning',
      ((Hc.GetValue('defaultConfiguration') as TJSONObject).GetValue('level').Value) = 'warning');
    Check('rule: security-severity 5.0 for a warning',
      ((Hc.GetValue('properties') as TJSONObject).GetValue('security-severity').Value) = '5.0');
    Tags:= (Hc.GetValue('properties') as TJSONObject).GetValue('tags') as TJSONArray;
    Check('tags: contain external/cwe/cwe-798', HasTag(Tags, 'external/cwe/cwe-798'));
    Check('tags: security category adds "security"', HasTag(Tags, 'security'));
    Check('tags: contain external/cert/MSC41-C', HasTag(Tags, 'external/cert/MSC41-C'));

    Rels:= Hc.GetValue('relationships') as TJSONArray;
    Check('relationships: CWE + CERT entries', (Rels <> nil) and (Rels.Count = 2));
    Rel:= Rels.Items[0] as TJSONObject;
    Tgt:= Rel.GetValue('target') as TJSONObject;
    Comp:= Tgt.GetValue('toolComponent') as TJSONObject;
    Check('relationship: target id is "798"', Tgt.GetValue('id').Value = '798');
    Check('relationship: toolComponent CWE index 0',
      (Comp.GetValue('name').Value = 'CWE') and ((Comp.GetValue('index') as TJSONNumber).AsInt = 0));
    Check('relationship: kinds = [relevant]',
      ((Rel.GetValue('kinds') as TJSONArray).Count = 1) and ((Rel.GetValue('kinds') as TJSONArray).Items[0].Value = 'relevant'));

    Tp:= RuleOf(Driver, 'type-name-prefix');
    Check('untagged rule: no relationships key', Tp.GetValue('relationships') = nil);
    Check('untagged rule: no security-severity',
      (Tp.GetValue('properties') as TJSONObject).GetValue('security-severity') = nil);
  finally
    V.Free;
  end;
end;

procedure TestNoLookupUnchanged;
var
  V: TJSONValue;
  Run: TJSONObject;
begin
  V:= TJSONObject.ParseJSONValue(TSarifWriter.ToJson([MkFinding('x', 'info', 'C:\a.pas', 1, 1, 'm')], '1.0'));
  try
    Run:= ((V as TJSONObject).GetValue('runs') as TJSONArray).Items[0] as TJSONObject;
    Check('no lookup: no taxonomies key (old output shape)', Run.GetValue('taxonomies') = nil);
  finally
    V.Free;
  end;
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestSarifShape;
    TestZeroCoordinateClamp;
    TestTaxonomies;
    TestNoLookupUnchanged;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('sarif-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
