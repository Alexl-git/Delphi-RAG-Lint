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
#   1b. lane IDXRANGE2 (owner rulings C1/C2, 2026-11-17): parallel arrays are silent when the
#      other array's bound is proven within this one's (same SetLength count, static bounds,
#      same SetLength source, every local caller sizing the param array from the guarded count)
#      and a WARNING otherwise (a for loop over another array reports on the for line); an
#      unchecked index parameter is cleared when every local caller passes a proven in-range
#      value, and stays a hint when one does not, when the routine escapes as a value, or when
#      it is exported from the interface section;
#   1c. ORM3 batch 3 (2026-11-17): SetLength size expression with slack, wrong-order while one-past read,
#      the uINSPRSLT:5575 TP (second array after the loop), an Exit-capped Inc with local callers, an index
#      from a map lookup (hint), the one-Inc-per-for-trip count invariant;
#   3. default ON (C3): without any config the rule reports (positive control: the explicit
#      config gives the same set);
#   4. rules --json: default_enabled true, fixable true, fix_manual_only true, param exception_class;
#   4b. the fix is manual only (C3): a batch --fix --apply without --fix-rule leaves the file alone;
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
foreach ($l in 26, 38, 50, 60, 66, 161, 209, 242, 262, 284, 324, 358, 382, 412, 425, 468, 491, 517) { Assert "fires at line $l" ($lines -contains $l) }
foreach ($l in 74, 75, 83, 84, 91, 95, 96, 105, 107, 115, 118, 125, 128, 136, 137, 146, 147, 152, 154, 169, 174, 183, 184, 185, 193, 199, 200, 218, 219, 221, 222,
               234, 235, 252, 253, 273, 274, 294, 297, 306, 309, 344, 368,
               401, 403, 424, 433, 440, 461, 502, 507) {
  Assert "silent at line $l" (-not ($lines -contains $l))
}
$nExpected = 18
Assert "exactly $nExpected findings (got $($f.Count))" ($f.Count -eq $nExpected)
Assert "unproven parallel array is a warning on the for line" ((@($f | Where-Object { $_.start_line -eq 242 })[0].severity) -eq 'warning')
Assert "parallel message names the other bound" ((@($f | Where-Object { $_.start_line -eq 242 })[0].message) -match 'Names\.Count')
Assert "index from a map lookup is a hint (ORM3 uJobList:997)" ((@($f | Where-Object { $_.start_line -eq 491 })[0].severity) -eq 'hint')
Assert "bad local caller keeps the parameter hint" ((@($f | Where-Object { $_.start_line -eq 358 })[0].severity) -eq 'hint')
Assert "parameter case is a hint" ((@($f | Where-Object { $_.start_line -eq 66 })[0].severity) -eq 'hint')
Assert "write case is a warning" ((@($f | Where-Object { $_.start_line -eq 26 })[0].severity) -eq 'warning')
Assert "message names the access line" ((@($f | Where-Object { $_.start_line -eq 26 })[0].message) -match 'reaches A\[i\] at line 27')

# 3: default ON (no --rule, no config). Positive control: the explicit config gives the same count.
$dflt = Lint $fixture '' -NoNarrow
$onFull = Lint $fixture $cfgOn -NoNarrow
Assert "positive control: config enables it without --rule (got $($onFull.Count))" ($onFull.Count -eq $nExpected)
Assert "default ON: same findings without any config (got $($dflt.Count))" ($dflt.Count -eq $nExpected)

# 4: catalogue
$cat = (& $exe rules --json 2>$null | ConvertFrom-Json).rules | Where-Object { $_.id -eq $rule }
Assert "rules --json lists the rule" ($null -ne $cat)
Assert "default_enabled true" ($cat.default_enabled -eq $true)
Assert "fixable true" ($cat.fixable -eq $true)
Assert "fix_manual_only true" ($cat.fix_manual_only -eq $true)
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
  # 4b: a batch fix (no --fix-rule) never applies the manual-only guard; it says why on stderr
  $batchErr = (& $exe lint --in $pas --fix --config $cfg --apply --no-backup 2>&1) -join "`n"
  Assert "batch --fix leaves the manual-only guard out" (-not (([IO.File]::ReadAllText($pas)) -match 'InRange'))
  Assert "batch --fix names the manual-only rule" ($batchErr -match "manual only.*$rule")
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
  # 1b: an index parameter of a routine exported from the interface keeps its hint, local callers or not
  $exp = @(
    'unit ExpIdx;', '', 'interface', '', 'function PubAt(const D: TArray<Integer>; Idx: Integer): Integer;', '',
    'implementation', '', 'function PubAt(const D: TArray<Integer>; Idx: Integer): Integer;', 'begin',
    '  Result:= D[Idx];', 'end;', '', 'function SumPub(const D: TArray<Integer>): Integer;', 'var', '  k: Integer;',
    'begin', '  Result:= 0;', '  for k:= 0 to High(D) do', '    Result:= Result + PubAt(D, k);', 'end;', '', 'end.') -join "`r`n"
  $expPas = Join-Path $tmp 'ExpIdx.pas'
  [IO.File]::WriteAllText($expPas, $exp + "`r`n", [Text.Encoding]::ASCII)
  $ef = Lint $expPas ''
  Assert "exported routine keeps the parameter hint (got $($ef.Count))" (($ef.Count -eq 1) -and ($ef[0].start_line -eq 11) -and ($ef[0].severity -eq 'hint'))
  # 1b: an index parameter of a routine exported from the interface keeps its hint, local callers or not
  $exp = @(
    'unit ExpIdx;', '', 'interface', '', 'function PubAt(const D: TArray<Integer>; Idx: Integer): Integer;', '',
    'implementation', '', 'function PubAt(const D: TArray<Integer>; Idx: Integer): Integer;', 'begin',
    '  Result:= D[Idx];', 'end;', '', 'function SumPub(const D: TArray<Integer>): Integer;', 'var', '  k: Integer;',
    'begin', '  Result:= 0;', '  for k:= 0 to High(D) do', '    Result:= Result + PubAt(D, k);', 'end;', '', 'end.') -join "`r`n"
  $expPas = Join-Path $tmp 'ExpIdx.pas'
  [IO.File]::WriteAllText($expPas, $exp + "`r`n", [Text.Encoding]::ASCII)
  $ef = Lint $expPas ''
  Assert "exported routine keeps the parameter hint (got $($ef.Count))" (($ef.Count -eq 1) -and ($ef[0].start_line -eq 11) -and ($ef[0].severity -eq 'hint'))
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
