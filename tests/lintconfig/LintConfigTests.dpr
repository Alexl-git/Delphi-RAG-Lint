program LintConfigTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Lint.Config in '..\..\src\lint\DRagLint.Lint.Config.pas';

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

    // profile merge
    Cfg:= TLintConfig.Load(Path, 'ci');
    Check('profile ci adds deep-nesting to disabled',
      not Cfg.ShouldKeep('deep-nesting', False));
    Check('profile keeps top-level disabled too',
      not Cfg.ShouldKeep('magic-number', False));

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

begin
  GPass:= 0; GFail:= 0;
  try
    TestConfig;
    TestNaming;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('lintconfig-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
