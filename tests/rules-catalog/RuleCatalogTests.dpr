program RuleCatalogTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  DRagLint.Lint.RuleCatalog in '..\..\src\lint\DRagLint.Lint.RuleCatalog.pas';
var
  GPass, GFail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;
function Find(const A: TArray<TRuleInfo>; const AId: string; out AInfo: TRuleInfo): Boolean;
var R: TRuleInfo;
begin
  Result:= False;
  for R in A do if R.Id = AId then begin AInfo:= R; Exit(True); end;
end;
procedure TestMerge;
const
  CanonicalBuckets: array[0..14] of string = (
    'bug-patterns','resource-lifetime','security','platform',
    'complexity','structure','naming','dead-code',
    'data-flow','firedac','project-wide','metrics','other','refactoring',
    'documentation'); { ADF milestone: missing-doc + doc-drift live in this bucket }
var
  Cat: TArray<TRuleInfo>;
  Info: TRuleInfo;
  Sum: TCatalogSummary;
  P: TPair<string, Integer>;
  NamingCount: Integer;
  AllValid: Boolean;
  R: TRuleInfo;
  BucketOk: Boolean;
  I: Integer;
  RulesDir: string;
begin
  { point at the repo rules/ dir -- resolved from EXE location (tests\rules-catalog) }
  RulesDir:= TPath.GetFullPath(
    TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\rules'));
  Cat:= TRuleCatalog.BuildCatalog(RulesDir, '');
  Check('catalog has >= 100 rules', Length(Cat) >= 100);

  { a known .scm rule is present, source scm, sensible category }
  Check('goto-statement present', Find(Cat, 'goto-statement', Info));
  Check('goto-statement source scm', Info.Source = 'scm');
  Check('goto-statement category structure', Info.Category = 'structure');

  { a known security .scm rule }
  Check('sql-injection-concat present + scm + security',
    Find(Cat, 'sql-injection-concat', Info) and (Info.Source = 'scm') and (Info.Category = 'security'));

  { built-in still wins dedup + keeps builtin source }
  Check('too-many-parameters still builtin after merge',
    Find(Cat, 'too-many-parameters', Info) and (Info.Source = 'builtin'));

  { summary: non-zero total + category count, naming bucket present }
  Sum:= TRuleCatalog.Summarize(Cat);
  Check('summary total matches length', Sum.Total = Length(Cat));
  Check('summary categories >= 8', Sum.Categories >= 8);
  NamingCount:= 0;
  for P in Sum.PerCategory do if P.Key = 'naming' then NamingCount:= P.Value;
  Check('summary naming count = 9', NamingCount = 9);

  { category filter returns only that category }
  Cat:= TRuleCatalog.BuildCatalog(RulesDir, 'naming');
  Check('category filter naming -> 9 rules', Length(Cat) = 9);
  for Info in Cat do
    if Info.Category <> 'naming' then begin Check('filtered all naming', False); Break; end;

  { every rule category is a canonical bucket }
  Cat:= TRuleCatalog.BuildCatalog(RulesDir, '');
  AllValid:= True;
  for R in Cat do
  begin
    BucketOk:= False;
    for I:= 0 to High(CanonicalBuckets) do
      if R.Category = CanonicalBuckets[I] then begin BucketOk:= True; Break; end;
    if not BucketOk then begin AllValid:= False; Break; end;
  end;
  Check('every category is a canonical bucket', AllValid);
end;

procedure TestRegistry;
var
  Reg: TArray<TRuleInfo>;
  Info: TRuleInfo;
  Ids: TDictionary<string, Boolean>;
  R: TRuleInfo;
  Dup: Boolean;
begin
  Reg:= TRuleCatalog.BuiltinRegistry;
  Check('registry has >= 55 built-ins', Length(Reg) >= 55);

  // representative: a parameterized complexity rule
  Check('too-many-parameters present', Find(Reg, 'too-many-parameters', Info));
  Check('too-many-parameters category complexity', Info.Category = 'complexity');
  Check('too-many-parameters severity info', Info.DefaultSeverity = 'info');
  Check('too-many-parameters source builtin', Info.Source = 'builtin');
  Check('too-many-parameters has threshold param',
    (Length(Info.Params) = 1) and (Info.Params[0].Name = 'threshold')
    and (Info.Params[0].ParamType = 'int') and (Info.Params[0].DefaultVal = '7'));

  // representative: a resource-lifetime warning
  Check('freeandnil-on-interface present', Find(Reg, 'freeandnil-on-interface', Info));
  Check('freeandnil-on-interface category resource-lifetime', Info.Category = 'resource-lifetime');
  Check('freeandnil-on-interface severity warning', Info.DefaultSeverity = 'warning');

  // representative: naming + default-disabled
  Check('reserved-word-casing present', Find(Reg, 'reserved-word-casing', Info));
  Check('reserved-word-casing category naming', Info.Category = 'naming');
  Check('reserved-word-casing default enabled', Info.DefaultEnabled = True);
  Check('hungarian-or-short-identifier default DISABLED', Find(Reg, 'hungarian-or-short-identifier', Info) and (Info.DefaultEnabled = False));
  Check('param-name-prefix default DISABLED', Find(Reg, 'param-name-prefix', Info) and (Info.DefaultEnabled = False));

  // representative: data-flow + dead-code + project-wide present
  Check('used-before-assignment is data-flow', Find(Reg, 'used-before-assignment', Info) and (Info.Category = 'data-flow'));
  Check('unused-parameter is dead-code', Find(Reg, 'unused-parameter', Info) and (Info.Category = 'dead-code'));
  Check('god-class is project-wide', Find(Reg, 'god-class', Info) and (Info.Category = 'project-wide'));

  // every entry has a non-empty id/category/severity and a valid category
  for R in Reg do
  begin
    if (R.Id = '') or (R.Category = '') or (R.DefaultSeverity = '') then
    begin Check('entry fully populated: ' + R.Id, False); Break; end;
  end;

  // no duplicate ids
  Ids:= TDictionary<string, Boolean>.Create;
  try
    Dup:= False;
    for R in Reg do
      if Ids.ContainsKey(R.Id) then begin Dup:= True; Break; end
      else Ids.Add(R.Id, True);
    Check('no duplicate built-in ids', not Dup);
  finally
    Ids.Free;
  end;
end;
begin
  GPass:= 0; GFail:= 0;
  try
    TestRegistry;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  try
    TestMerge;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('rulecatalog-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
