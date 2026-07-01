program T65_profile_apply;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, DRagLint.Lint.Config;
var Pass, Fail: Integer;
procedure Check(ACond: Boolean; const AMsg: string);
begin if ACond then Inc(Pass) else begin Inc(Fail); Writeln('FAIL: ', AMsg); end; end;
var Tmp: string; Base, Prof: TLintConfig;
begin
  Pass:= 0; Fail:= 0;
  Tmp:= TPath.Combine(TPath.GetTempPath, 't65.json');
  TFile.WriteAllText(Tmp,
    '{'#10 +
    '  "disabled": ["magic-number"],'#10 +
    '  "severity": { "long-method": "warning", "deep-nesting": "error" },'#10 +
    '  "thresholds": { "deep-nesting": 5, "too-many-parameters": 7 },'#10 +
    '  "naming": { "param_prefix": "", "min_identifier_len": 3 },'#10 +
    '  "profiles": {'#10 +
    '    "strict": {'#10 +
    '      "disabled": ["float-equality-comparison"],'#10 +
    '      "severity": { "long-method": "error" },'#10 +
    '      "thresholds": { "deep-nesting": 2 },'#10 +
    '      "naming": { "param_prefix": "p", "short_identifier_check": "true" }'#10 +
    '    }'#10 +
    '  }'#10 +
    '}');
  { base (no profile) }
  Base:= TLintConfig.Load(Tmp, '');
  Check(not Base.IsEnabled('magic-number'), 'base disables magic-number');
  Check(Base.ApplySeverity('long-method', 'hint') = 'warning', 'base severity long-method=warning');
  Check(Base.ThresholdFor('deep-nesting', 99) = 5, 'base deep-nesting=5');
  Check(Base.ThresholdFor('too-many-parameters', 99) = 7, 'base tmp=7');
  Check(Base.Naming.ParamPrefix = '', 'base param_prefix empty');
  Check(Base.Naming.ShortIdentifierCheck = False, 'base short-check off');
  { profile "strict" overrides }
  Prof:= TLintConfig.Load(Tmp, 'strict');
  Check(not Prof.IsEnabled('float-equality-comparison'), 'profile disables float-eq');
  Check(Prof.IsEnabled('magic-number'), 'profile REPLACES disabled -> magic-number back on');
  Check(Prof.ApplySeverity('long-method', 'hint') = 'error', 'profile overrides long-method sev=error');
  Check(Prof.ApplySeverity('deep-nesting', 'hint') = 'error', 'base sev deep-nesting inherited by profile');
  Check(Prof.ThresholdFor('deep-nesting', 99) = 2, 'profile overrides deep-nesting=2');
  Check(Prof.ThresholdFor('too-many-parameters', 99) = 7, 'omitted threshold inherits base=7');
  Check(Prof.Naming.ParamPrefix = 'p', 'profile naming param_prefix=p');
  Check(Prof.Naming.ShortIdentifierCheck = True, 'profile short-check TRUE (string parsed)');
  Check(Prof.Naming.MinIdentifierLen = 3, 'omitted naming field inherits base=3');
  TFile.Delete(Tmp);
  Writeln(Format('t65: %d pass / %d fail', [Pass, Fail]));
end.
