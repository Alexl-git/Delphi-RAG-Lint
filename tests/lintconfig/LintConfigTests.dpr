program LintConfigTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Lint.Config in '..\..\src\lint\DRagLint.Lint.Config.pas',
  DRagLint.Lint.ConfigWriter in '..\..\src\lint\DRagLint.Lint.ConfigWriter.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

const
  CONFIG_JSON =
    '{'#10 +
    '  "disabled": ["magic-number"],'#10 +
    '  "enabled":  ["naming-pascalcase"],'#10 +
    '  "severity": { "object-leak": "error" },'#10 +
    '  "thresholds": { "too-many-parameters": 3, "cyclomatic-complexity": 99 },'#10 +
    '  "profiles": { "ci": { "disabled": ["deep-nesting"] } }'#10 +
    '}'#10;

procedure TestNaming;
var
  Cfg: TLintConfig;
  Path: string;
begin
  // 1. No config -> defaults match the repo conventions.
  Cfg:= TLintConfig.Load('', '');
  Check('naming default class prefix T', Cfg.Naming.ClassPrefix = 'T');
  Check('naming default field prefix F', Cfg.Naming.FieldPrefix = 'F');
  Check('naming default param prefix empty (off by default)', Cfg.Naming.ParamPrefix = '');
  Check('naming default method PascalCase', Cfg.Naming.MethodCase = 'PascalCase');

  // 2. Override: disable param prefix, change field prefix.
  Path:= TPath.Combine(TPath.GetTempPath, 'dl-naming.json');
  TFile.WriteAllText(Path,
    '{ "naming": { "param_prefix": "", "field_prefix": "Fld" } }', TEncoding.UTF8);
  try
    Cfg:= TLintConfig.Load(Path, '');
    Check('naming param prefix disabled (empty)', Cfg.Naming.ParamPrefix = '');
    Check('naming field prefix overridden', Cfg.Naming.FieldPrefix = 'Fld');
    Check('naming class prefix still default', Cfg.Naming.ClassPrefix = 'T');
  finally
    if TFile.Exists(Path) then TFile.Delete(Path);
  end;

  // 3. New v0.69 D3 fields: defaults + overrides.
  Cfg:= TLintConfig.Load('', '');
  Check('naming default keyword_case lowercase', Cfg.Naming.KeywordCase = 'lowercase');
  Check('naming default min_identifier_len 3', Cfg.Naming.MinIdentifierLen = 3);
  Check('naming default short_identifier_check off', Cfg.Naming.ShortIdentifierCheck = False);
  Check('naming default hungarian_prefixes nonempty', Length(Cfg.Naming.HungarianPrefixes) > 0);

  Path:= TPath.Combine(TPath.GetTempPath, 'dl-naming-d3.json');
  TFile.WriteAllText(Path,
    '{ "naming": { "keyword_case": "", "min_identifier_len": 5, ' +
    '"short_identifier_check": true, "hungarian_prefixes": ["foo","bar"] } }',
    TEncoding.UTF8);
  try
    Cfg:= TLintConfig.Load(Path, '');
    Check('naming keyword_case overridden empty', Cfg.Naming.KeywordCase = '');
    Check('naming min_identifier_len overridden 5', Cfg.Naming.MinIdentifierLen = 5);
    Check('naming short_identifier_check overridden true', Cfg.Naming.ShortIdentifierCheck = True);
    Check('naming hungarian_prefixes overridden len 2', Length(Cfg.Naming.HungarianPrefixes) = 2);
    Check('naming hungarian_prefixes first foo',
      (Length(Cfg.Naming.HungarianPrefixes) = 2) and (Cfg.Naming.HungarianPrefixes[0] = 'foo'));
  finally
    if TFile.Exists(Path) then TFile.Delete(Path);
  end;
end;

procedure TestConfig;
var
  Cfg: TLintConfig;
  Path: string;
begin
  Path:= TPath.Combine(TPath.GetTempPath, 'dl-cfg-test.json');
  TFile.WriteAllText(Path, CONFIG_JSON, TEncoding.UTF8);
  try
    Cfg:= TLintConfig.Load(Path, '');

    // severity remap
    Check('severity remap object-leak->error',
      Cfg.ApplySeverity('object-leak', 'info') = 'error');
    Check('severity passthrough for unmapped',
      Cfg.ApplySeverity('use-after-free', 'warning') = 'warning');

    // disabled
    Check('disabled magic-number dropped', not Cfg.ShouldKeep('magic-number', False));
    Check('non-disabled kept', Cfg.ShouldKeep('object-leak', False));

    // default-disabled rule re-enabled by config "enabled"
    Check('off-by-default + in enabled -> kept',
      Cfg.ShouldKeep('naming-pascalcase', True));
    Check('off-by-default + NOT enabled -> dropped',
      not Cfg.ShouldKeep('some-other-off-rule', True));

    // thresholds
    Check('threshold override too-many-parameters=3',
      Cfg.ThresholdFor('too-many-parameters', 7) = 3);
    Check('threshold default when unset',
      Cfg.ThresholdFor('too-many-locals', 25) = 25);

    // Profile merge. The semantics are ASYMMETRIC, and deliberately so --
    // e2fcc49 (2026-07-01, "profiles override full config") made LIST fields
    // (disabled, enabled) replace the top-level list WHOLESALE, while MAP
    // fields (severity, thresholds, naming) update per key so base entries the
    // profile omits are inherited. 09e7fd2 walked severity back into the
    // per-key group. See TLintConfig.Load's own doc comment, which states this.
    // This block asserted the pre-e2fcc49 "lists merge" behaviour and had been
    // red ever since, unnoticed because nothing ran tests\lintconfig.
    Cfg:= TLintConfig.Load(Path, 'ci');
    Check('profile ci adds deep-nesting to disabled',
      not Cfg.ShouldKeep('deep-nesting', False));
    // LIST field: 'ci' lists only deep-nesting, so the top-level
    // disabled ["magic-number"] is gone and magic-number is kept again.
    Check('profile REPLACES top-level disabled list wholesale',
      Cfg.ShouldKeep('magic-number', False));
    // MAP fields: 'ci' mentions neither, so both base entries survive.
    Check('profile INHERITS top-level severity (map field, per-key)',
      Cfg.ApplySeverity('object-leak', 'info') = 'error');
    Check('profile INHERITS top-level thresholds (map field, per-key)',
      Cfg.ThresholdFor('too-many-parameters', 7) = 3);

    // --enable composition
    Cfg:= TLintConfig.Load(Path, '');
    Cfg.AddEnabled(['some-other-off-rule']);
    Check('AddEnabled re-includes off-by-default',
      Cfg.ShouldKeep('some-other-off-rule', True));

    // empty path => no-op config
    Cfg:= TLintConfig.Load('', '');
    Check('empty config keeps everything', Cfg.ShouldKeep('magic-number', False) = True);
    Check('empty config default threshold', Cfg.ThresholdFor('too-many-parameters', 7) = 7);
    Check('empty config severity passthrough', Cfg.ApplySeverity('object-leak', 'info') = 'info');
  finally
    if TFile.Exists(Path) then TFile.Delete(Path);
  end;
end;

procedure TestAutoFix;
var
  Cfg, Cfg2: TLintConfig;
  Path, Json: string;
begin
  Path:= TPath.Combine(TPath.GetTempPath, 'dl-autofix-test.json');
  TFile.WriteAllText(Path,
    '{ "autofix": ["redundant-cast"] }', TEncoding.UTF8);
  try
    // 1. load + read
    Cfg:= TLintConfig.Load(Path, '');
    Check('autofix redundant-cast is IsAutoFix=True', Cfg.IsAutoFix('redundant-cast'));
    Check('autofix self-assignment is IsAutoFix=False', not Cfg.IsAutoFix('self-assignment'));

    // 2. independence from enabled/disabled: autofix does not add to the
    // enabled list, and adding to enabled does not add to autofix.
    Check('autofix rule not in EnabledIds', Length(Cfg.EnabledIds) = 0);
    Cfg.AddEnabled(['redundant-cast']);
    Check('enabling autofix rule keeps IsAutoFix true', Cfg.IsAutoFix('redundant-cast'));
    Check('enabling a rule does not add it to autofix',
      not Cfg.IsAutoFix('some-newly-enabled-rule'));
    Cfg.AddDisabled(['redundant-cast']);
    Check('disabling an autofix rule keeps IsAutoFix true (independent)',
      Cfg.IsAutoFix('redundant-cast'));

    // 3. AddAutoFix + round-trip via writer
    Cfg2:= TLintConfig.Load(Path, '');
    Cfg2.AddAutoFix(['self-assignment']);
    Check('AddAutoFix adds without removing prior', Cfg2.IsAutoFix('redundant-cast'));
    Check('AddAutoFix adds new id', Cfg2.IsAutoFix('self-assignment'));

    Json:= TLintConfigWriter.ToJson(Cfg2);
    Check('serialized json contains autofix key', Pos('"autofix"', Json) > 0);
    Check('serialized json contains redundant-cast', Pos('redundant-cast', Json) > 0);
    Check('serialized json contains self-assignment', Pos('self-assignment', Json) > 0);

    TFile.WriteAllText(Path, Json, TEncoding.UTF8);
    Cfg2:= TLintConfig.Load(Path, '');
    Check('reload after round-trip: redundant-cast still autofix', Cfg2.IsAutoFix('redundant-cast'));
    Check('reload after round-trip: self-assignment still autofix', Cfg2.IsAutoFix('self-assignment'));
    Check('reload after round-trip: unrelated rule not autofix',
      not Cfg2.IsAutoFix('some-other-rule'));

    // 4. AutoFixIds returns both
    Check('AutoFixIds length 2', Length(Cfg2.AutoFixIds) = 2);
  finally
    if TFile.Exists(Path) then TFile.Delete(Path);
  end;
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestConfig;
    TestNaming;
    TestAutoFix;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('lintconfig-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
