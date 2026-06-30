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
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('lintconfig-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
