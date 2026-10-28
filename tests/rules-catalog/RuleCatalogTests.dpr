program RuleCatalogTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  DRagLint.Lint.Compliance in '..\..\src\lint\DRagLint.Lint.Compliance.pas',
  DRagLint.Lint.RuleCatalog in '..\..\src\lint\DRagLint.Lint.RuleCatalog.pas',
  DRagLint.Lint.TargetCompiler in '..\..\src\lint\DRagLint.Lint.TargetCompiler.pas';
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
  { A CLOSED vocabulary on purpose: a rule arriving with an invented category is
    exactly what this assertion is for, so the list is extended deliberately and
    annotated, never widened to make a red test green.
    2026-08-12: +'review-markers', for review-marker-stale / review-marker-unused.
    2026-10-27: +'policy', 'modernize' (clippy-parity wave).
    They are meta-rules ABOUT the suppression mechanism rather than about the code
    under analysis -- emitted by the central dl:ok filter, not by any checker --
    which is a genuinely different kind of thing from every other bucket here.
    Filing them under 'other' would have passed this test while hiding that. }
  CanonicalBuckets: array[0..18] of string = (
    'bug-patterns','resource-lifetime','security','platform',
    'complexity','structure','naming','dead-code',
    'data-flow','firedac','project-wide','metrics','other','refactoring',
    'documentation', { ADF milestone: missing-doc + doc-drift live in this bucket }
    'review-markers',
    'policy', 'modernize', { clippy-parity wave 2026-10-27: disallowed-* and index-loop-to-for-in }
    'compat' { 2026-10-28 two-way modernize: the downgrade rules (COMPAT_CATEGORY), 1.38.1 });
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

  { taint wave T2 (2026-10-27): the three store-backed taint rules are built-ins, security, ON }
  Check('taint-sql-injection builtin + security + error + ON',
    Find(Cat, 'taint-sql-injection', Info) and (Info.Source = 'builtin') and (Info.Category = 'security')
    and (Info.DefaultSeverity = 'error') and Info.DefaultEnabled);
  Check('taint-command-injection builtin + security + error + ON',
    Find(Cat, 'taint-command-injection', Info) and (Info.Source = 'builtin') and (Info.Category = 'security')
    and (Info.DefaultSeverity = 'error') and Info.DefaultEnabled);
  Check('taint-path-traversal builtin + security + warning + ON',
    Find(Cat, 'taint-path-traversal', Info) and (Info.Source = 'builtin') and (Info.Category = 'security')
    and (Info.DefaultSeverity = 'warning') and Info.DefaultEnabled);

  { built-in still wins dedup + keeps builtin source }
  Check('too-many-parameters still builtin after merge',
    Find(Cat, 'too-many-parameters', Info) and (Info.Source = 'builtin'));

  { summary: non-zero total + category count, naming bucket present }
  Sum:= TRuleCatalog.Summarize(Cat);
  Check('summary total matches length', Sum.Total = Length(Cat));
  Check('summary categories >= 8', Sum.Categories >= 8);
  NamingCount:= 0;
  for P in Sum.PerCategory do if P.Key = 'naming' then NamingCount:= P.Value;
  { 2026-08-12: 9 -> 10. local-field-prefix ("Local variable wears the
    field/param prefix") joined the naming bucket in 3fdefd9 when the naming
    rules were split. Verified against the live catalog before the number was
    changed -- the delta is exactly that one id.
    2026-10-16: 10 -> 11. confusable-identifier joined the naming bucket in
    40fd41b2; ce007d31 re-pinned the docrules count but missed this one.
    Verified against the live catalog (rules --json): the delta is that id. }
  Check('summary naming count = 13', NamingCount = 13);

  { category filter returns only that category }
  Cat:= TRuleCatalog.BuildCatalog(RulesDir, 'naming');
  Check('category filter naming -> 13 rules', Length(Cat) = 13);
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
procedure TestCompliance;
var
  Cat : TArray<TRuleInfo>;
  Info: TRuleInfo;
begin
  Cat:= TRuleCatalog.BuildCatalog(TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\rules')), '');
  Check('compliance.json is not read as a rule sidecar', not Find(Cat, 'compliance', Info) and not Find(Cat, 'abstract-method-instantiation-x', Info));
  Check('catalog loaded without a compliance error', TRuleCatalog.ComplianceError = '');
  Check('hardcoded-credential carries CWE-798', Find(Cat, 'hardcoded-credential', Info) and (Length(Info.Compliance.Cwe) > 0) and (Info.Compliance.Cwe[0] = 'CWE-798'));
  Check('type-name-prefix carries nothing', Find(Cat, 'type-name-prefix', Info) and Info.Compliance.IsEmpty);
  Check('weak ids are a subset of the rule ids', Find(Cat, 'wait-while-holding-lock', Info) and (Length(Info.Compliance.Weak) = 2) and (Info.Compliance.Suffix = ' [CWE-833 LCK09-J]'));
  Check('malformed id is rejected by the format check', not IsCweId('CWE-x') and IsCweId('CWE-476') and IsCertId('EXP34-C') and IsMisraId('MISRA-C-2012-R18.6'));
end;
procedure TestTargetCompiler;
var
  V  : Integer;
  Err: string;
  Cat: TArray<TRuleInfo>;
  Info: TRuleInfo;
  G  : TTargetRuleGate;
  function Tok(const AToken: string): Integer;
  var E: string;
  begin
    if not ParseCompilerToken(AToken, Result, E) then Result:= -1;
  end;
  function PV(const AValue: string): Integer;
  begin
    if not ProjectVersionToCompiler(AValue, Result) then Result:= -1;
  end;
begin
  { tokens: product versions, CompilerVersion numbers, code names, a Delphi prefix }
  Check('token 13 -> 37', Tok('13') = 37);
  Check('token 37 -> 37', Tok('37') = 37);
  Check('token 12.2 -> 36', Tok('12.2') = 36);
  Check('token Delphi 11 -> 35', Tok('Delphi 11') = 35);
  Check('token athens -> 36', Tok('athens') = 36);
  Check('token 10.4 -> 34', Tok('10.4') = 34);
  Check('token XE7 -> 28', Tok('XE7') = 28);
  Check('token 2009 -> 20', Tok('2009') = 20);
  Check('token 6 -> 14', Tok('6') = 14);
  Check('token 14 -> 14 (CompilerVersion)', Tok('14') = 14);
  Check('unknown tokens refuse (5, 38, 14.5, XE9, empty)',
    (Tok('5') = -1) and (Tok('38') = -1) and (Tok('14.5') = -1) and (Tok('XE9') = -1) and (Tok('') = -1));
  Check('a refusal names the accepted set', not ParseCompilerToken('nope', V, Err) and (Pos('accepted:', Err) > 0));
  { ProjectVersion table: 20.4 measured (Studio 37); the rest pinned from the release history }
  Check('ProjectVersion 20.4 -> 37', PV('20.4') = 37);
  Check('ProjectVersion 20.1 / 20.3 -> 36', (PV('20.1') = 36) and (PV('20.3') = 36));
  Check('ProjectVersion 19.5 -> 35', PV('19.5') = 35);
  Check('ProjectVersion 19.2 -> 34', PV('19.2') = 34);
  Check('ProjectVersion 18.8 -> 33', PV('18.8') = 33);
  Check('ProjectVersion 99.9 / empty refuse', (PV('99.9') = -1) and (PV('') = -1));
  { precedence: command line > config > context > default }
  Check('resolve: nothing -> 37', ResolveTargetCompiler('', '', '', '', V, Err) and (V = 37));
  Check('resolve: context only -> its value', ResolveTargetCompiler('', '', '12', '', V, Err) and (V = 36));
  Check('resolve: config beats context', ResolveTargetCompiler('', '11', '12', '', V, Err) and (V = 35));
  Check('resolve: command line beats config', ResolveTargetCompiler('10.3', '11', '12', '', V, Err) and (V = 33));
  Check('resolve: bad config token refuses and names its source',
    not ResolveTargetCompiler('', 'bogus', '', '', V, Err) and (Pos('config target_compiler', Err) > 0));
  Check('resolve: auto without a .dproj refuses', not ResolveTargetCompiler('auto', '', '', '', V, Err));
  { the gate }
  Check('gated: needs 37 at 36', IsGatedByTarget(37, 36));
  Check('not gated: needs 37 at 37, needs 0 at 14', not IsGatedByTarget(37, 37) and not IsGatedByTarget(0, 14));
  Check('compat on: since 37 at 36; off at 37; off for 0',
    IsCompatOnForTarget(37, 36) and not IsCompatOnForTarget(37, 37) and not IsCompatOnForTarget(0, 14));
  G:= TTargetRuleGate.Build(36, ['a', 'b', 'c'], [37, 0, 0], [0, 0, 37]);
  Check('gate at 36: drops a, forces c, leaves b', G.Drops('A') and G.ForcesOn('c') and not G.Drops('b') and not G.ForcesOn('b'));
  Check('gate active at 36, inactive at 37 and when zero', G.Active
    and not TTargetRuleGate.Build(37, ['a'], [37], [0]).Active and not Default(TTargetRuleGate).Active);
  { the catalog carries the keys }
  Cat:= TRuleCatalog.BuildCatalog(TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\rules')), '');
  Check('is-not-operator needs_compiler 37 (sidecar)', Find(Cat, 'is-not-operator', Info) and (Info.NeedsCompiler = 37) and (Info.CompatSince = 0));
  Check('unreadable-literal needs_compiler 35', Find(Cat, 'unreadable-literal', Info) and (Info.NeedsCompiler = 35));
  Check('nonminimal-bool rule-level needs_compiler 0 (its gate is per entry)', Find(Cat, 'nonminimal-bool', Info) and (Info.NeedsCompiler = 0));
  Check('a built-in defaults to 0 / 0', Find(Cat, 'too-many-parameters', Info) and (Info.NeedsCompiler = 0) and (Info.CompatSince = 0));
  Check('COMPAT_CATEGORY = compat', COMPAT_CATEGORY = 'compat');
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
  try
    TestTargetCompiler;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  try
    TestCompliance;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('rulecatalog-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
