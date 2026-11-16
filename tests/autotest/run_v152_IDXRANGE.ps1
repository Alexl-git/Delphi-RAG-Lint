# Guard for index-possibly-out-of-range (1.52 lane IDXRANGE; spec
# docs\superpowers\specs\2026-11-16-index-possibly-out-of-range-design.md).
# Cases:
#   1. the lint fixture tests\lint\index-possibly-out-of-range.pas: every must-fire line
#      (plain write, Inc before access in a while, one-sided guard, subrange-typed index,
#      unguarded parameter = hint, unanchorable access) and every must-not line (for over
#      the bounds, while with Inc after the access, both-sides if, early Exit / raise,
#      dual-use variable, literal index, string, guarded parameter, a local alias of Length,
#      a short-circuit `and` guard, grow-on-demand SetLength, an if-expression guard, a later
#      write that cannot reach the access) plus the wrong-order TP
#      `while (A[i] = 0) and (i <= 8)`;
#   2. severity split: the parameter case is a hint, the write cases are warnings;
#   3. default OFF: without the config the rule reports nothing (positive control for 1:
#      the same file WITH the config must report, so the assertion can fail);
#   4. rules --json: default_enabled false, fixable true, param exception_class;
#   5. autofix on a temp copy: the guard line lands before the access with the statement's
#      indentation, System.Math / System.SysUtils join the uses clause, the unanchorable
#      access gets no edit, and a second lint + --fix finds nothing left to fix (idempotent);
#   6. params.index-possibly-out-of-range.exception_class reaches the fix text; a value that
#      is not a class name is a config error.
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$exe = (Resolve-Path $Exe).Path
$rule = 'index-possibly-out-of-range'
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}
function Lint([string]$path, [string]$cfg, [switch]$NoNarrow) {
  $a = if ($NoNarrow) { @('lint', $path, '--json') } else { @('lint', $path, '--rule', $rule, '--json') }
  if ($cfg) { $a += @('--config', $cfg) }
  $raw = & $exe @a 2>$null
  $r = @()
  try { $r = @($raw | ConvertFrom-Json) } catch { $r = @() }
  return ,@($r | Where-Object { $_ -and $_.rule -eq $rule })
}

$fixture = Join-Path $repo 'tests\lint\index-possibly-out-of-range.pas'
$cfgOn   = Join-Path $repo 'tests\lint\index-possibly-out-of-range.config.json'

# 1 + 2: fixture expectations
$f = Lint $fixture $cfgOn
$lines = @($f | ForEach-Object { [int]$_.start_line })
foreach ($l in 26, 38, 50, 60, 66, 161, 209) { Assert "fires at line $l" ($lines -contains $l) }
foreach ($l in 74, 75, 83, 84, 91, 95, 96, 105, 107, 115, 118, 125, 128, 136, 137, 146, 147, 152, 154, 169, 174, 183, 184, 185, 193, 199, 200, 218, 219, 221, 222) {
  Assert "silent at line $l" (-not ($lines -contains $l))
}
Assert "exactly 7 findings (got $($f.Count))" ($f.Count -eq 7)
Assert "parameter case is a hint" ((@($f | Where-Object { $_.start_line -eq 66 })[0].severity) -eq 'hint')
Assert "write case is a warning" ((@($f | Where-Object { $_.start_line -eq 26 })[0].severity) -eq 'warning')
Assert "message names the access line" ((@($f | Where-Object { $_.start_line -eq 26 })[0].message) -match 'reaches A\[i\] at line 27')

# 3: default OFF (no --rule: naming the rule enables it). Positive control: the same call WITH the config reports.
$off = Lint $fixture '' -NoNarrow
$onFull = Lint $fixture $cfgOn -NoNarrow
Assert "positive control: config enables it without --rule (got $($onFull.Count))" ($onFull.Count -eq 7)
Assert "default OFF: no finding without the config (got $($off.Count))" ($off.Count -eq 0)

# 4: catalogue
$cat = (& $exe rules --json 2>$null | ConvertFrom-Json).rules | Where-Object { $_.id -eq $rule }
Assert "rules --json lists the rule" ($null -ne $cat)
Assert "default_enabled false" ($cat.default_enabled -eq $false)
Assert "fixable true" ($cat.fixable -eq $true)
Assert "param exception_class default EArgumentOutOfRangeException" ((@($cat.params | Where-Object { $_.name -eq 'exception_class' })[0].default) -eq 'EArgumentOutOfRangeException')

# 5 + 6: autofix on a temp copy
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('v152-idxrange-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $src = @(
    'unit FixIdx;', '', 'interface', '', 'implementation', '', 'uses', '  System.Classes;', '',
    'function Calc: Integer;', 'begin', '  Result:= 42;', 'end;', '',
    'procedure PlainCalc;', 'var', '  A: array[0..9] of Integer;', '  i: Integer;', 'begin',
    '  i:= Calc;', '  A[i]:= 1;', 'end;', '',
    'procedure NoAnchor(const D: TArray<Integer>; X: Boolean);', 'var', '  i: Integer;', 'begin',
    '  i:= Calc;', '  if X then D[i]:= 1;', 'end;', '', 'end.') -join "`r`n"
  $pas = Join-Path $tmp 'FixIdx.pas'
  [IO.File]::WriteAllText($pas, $src + "`r`n", [Text.Encoding]::ASCII)
  $cfg = Join-Path $tmp 'cfg.json'
  [IO.File]::WriteAllText($cfg, '{ "enabled": ["' + $rule + '"], "params": { "' + $rule + '": { "exception_class": "EMyIndexError" } } }', [Text.Encoding]::ASCII)
  $before = Lint $pas $cfg
  Assert "fix fixture: 2 findings before the fix (got $($before.Count))" ($before.Count -eq 2)
  & $exe lint --in $pas --fix --config $cfg --fix-rule $rule --apply --no-backup 2>$null | Out-Null
  $out = [IO.File]::ReadAllLines($pas)
  $guard = '  if not InRange(i, Low(A), High(A)) then raise EMyIndexError.CreateFmt(''A index %d outside %d..%d in PlainCalc'', [i, Low(A), High(A)]);'
  $gi = [Array]::IndexOf($out, $guard)
  Assert "guard line inserted with the configured class" ($gi -ge 0)
  Assert "guard line sits right before the access" (($gi -ge 0) -and ($out[$gi + 1] -eq '  A[i]:= 1;'))
  Assert "System.Math added to uses" (($out -match '^\s*System\.Math,').Count -eq 1)
  Assert "System.SysUtils added to uses" (($out -match '^\s*System\.SysUtils,').Count -eq 1)
  Assert "unanchorable access untouched" (($out -contains '  if X then D[i]:= 1;') -and (($out -match 'D index').Count -eq 0))
  $after = Lint $pas $cfg
  Assert "after the fix only the unanchorable finding is left (got $($after.Count))" (($after.Count -eq 1) -and ($after[0].message -match 'no autofix'))
  $again = (& $exe lint --in $pas --fix --config $cfg --fix-rule $rule 2>$null) -join "`n"
  Assert "second --fix has nothing to fix" ($again -match 'no fixable findings')
  $bad = Join-Path $tmp 'bad.json'
  [IO.File]::WriteAllText($bad, '{ "enabled": ["' + $rule + '"], "params": { "' + $rule + '": { "exception_class": "E Bad; x" } } }', [Text.Encoding]::ASCII)
  $errText = (& $exe lint $pas --config $bad --json 2>&1) -join "`n"
  Assert "invalid exception_class is a config error" ($errText -match 'exception_class must be a Pascal class name')
}
finally {
  [IO.Directory]::Delete($tmp, $true)
}

if ($fail -gt 0) { Write-Host "run_v152_IDXRANGE: $fail failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "run_v152_IDXRANGE: all passed"
exit 0
