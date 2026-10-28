<#
  run_target_compiler_guard.ps1 -- the --target-compiler switch (two-way modernize, lane D0, 1.38).

  What it proves, against the exe under test:
    T1  tokens: product versions (13, 12, 10.4, XE7, "Delphi 11"), CompilerVersion numbers (36),
        an unknown token REFUSES (exit 2, names the accepted set), never guesses.
    T2  auto: from a temp .dproj's <ProjectVersion> (20.2 -> 36, 20.4 -> 37); an unmapped
        ProjectVersion and a missing .dproj both refuse.
    T3  `rules --json`: every row carries needs_compiler / compat_since / target_active; the
        root carries target_compiler; at 36 EXACTLY the ids with needs_compiler > 36 go inactive
        (computed from the catalog itself, then pinned against the section-2 table).
    T4  lint gating, BOTH directions (positive control): the modernize findings fire at the
        default target and are gone at 36; the per-entry gate drops nonminimal-bool's `not in`
        entry only; the stderr status line appears at 36 and not at 37.
    T5  config key target_compiler, a profile override, and the command line beating the config.
    T6  a compat_since sidecar (temp --rules-dir) is OFF at 37 and ON at 33; a modernize rule and
        its compat twin are never both active at any target 14..37.
    T7  (with -BaseExe) default target 37 is byte-identical to the pre-D0 exe: `lint --json` on
        every tests\lint fixture and `rules --json` minus the three new row keys and the root key.

  Usage: pwsh -File tests\autotest\run_target_compiler_guard.ps1 [-Exe <drag-lint.exe>] [-BaseExe <pre-D0 exe>]
  Exit 0 = all pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$BaseExe = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-target-compiler-$PID"
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$exePath = (Resolve-Path $Exe).Path
$script:pass = 0; $script:fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "[PASS] $Name" -ForegroundColor Green }
  else { $script:fail++; Write-Host "[FAIL] $Name" -ForegroundColor Red; if ($Detail) { Write-Host ("       " + $Detail) } }
}
function WriteAscii([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
# Runs the exe; returns @{ Out; Err; Code }.
function Run([string[]]$ArgList) {
  $errFile = Join-Path $WorkDir '_stderr.txt'
  $out = & $exePath @ArgList 2> $errFile | Out-String
  $code = $LASTEXITCODE
  $err = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { '' }
  return @{ Out = $out; Err = "$err"; Code = $code }
}
function RulesJson([string[]]$Extra) {
  $r = Run (@('rules', '--json') + $Extra)
  try { return ($r.Out | ConvertFrom-Json) } catch { return $null }
}
function LintPairs([string]$File, [string[]]$Extra) {
  $r = Run (@('lint', $File, '--json') + $Extra)
  $rows = @(); try { $rows = @($r.Out | ConvertFrom-Json) } catch { $rows = @() }
  return @{ Pairs = @($rows | ForEach-Object { "$($_.rule):$($_.start_line)" }); Err = $r.Err; Code = $r.Code }
}

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Push-Location $WorkDir
try {
  # ---- the probe unit (lines pinned below) ----
  $probe = Join-Path $WorkDir 'TcProbe.pas'
  WriteAscii $probe @'
unit TcProbe;

interface

implementation

uses Classes;

procedure P(O: TObject; A, B: Integer);
var
  X: Integer;
begin
  if not (O is TStrings) then
    Exit;
  if A > B then X := A else X := B;
  if not (A in [1, 2]) then
    Exit;
  if not (A = B) then
    Exit;
  if X = 0 then
    Exit;
end;

end.
'@

  # ---- T1 tokens ----
  foreach ($t in @(@('13', 37), @('37', 37), @('12', 36), @('12.2', 36), @('36', 36), @('Delphi 11', 35),
                   @('10.4', 34), @('10.3', 33), @('XE7', 28), @('xe2', 23), @('2009', 20), @('6', 14))) {
    $j = RulesJson @('--target-compiler', $t[0])
    $got = if ($j) { $j.target_compiler } else { '<no json>' }
    Check "T1 token '$($t[0])' -> $($t[1])" ($got -eq $t[1]) "got $got"
  }
  foreach ($bad in @('14.5', '5', '38', 'XE9', 'florence2')) {
    $r = Run @('rules', '--json', '--target-compiler', $bad)
    Check "T1 unknown token '$bad' refuses (exit 2 + accepted list)" (($r.Code -eq 2) -and ($r.Err -match 'unknown version') -and ($r.Err -match 'accepted:')) "exit $($r.Code): $($r.Err.Trim())"
  }

  # ---- T2 auto ----
  foreach ($pv in @(@('20.2', 36), @('20.4', 37), @('18.8', 33))) {
    $dp = Join-Path $WorkDir "auto$($pv[0]).dproj"
    WriteAscii $dp "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <ProjectVersion>$($pv[0])</ProjectVersion>`n  </PropertyGroup>`n</Project>`n"
    $j = RulesJson @('--target-compiler', 'auto', '--project', $dp)
    $got = if ($j) { $j.target_compiler } else { '<no json>' }
    Check "T2 auto ProjectVersion $($pv[0]) -> $($pv[1])" ($got -eq $pv[1]) "got $got"
  }
  $dpBad = Join-Path $WorkDir 'autobad.dproj'
  WriteAscii $dpBad "<Project><PropertyGroup><ProjectVersion>99.9</ProjectVersion></PropertyGroup></Project>`n"
  $r = Run @('rules', '--json', '--target-compiler', 'auto', '--project', $dpBad)
  Check 'T2 auto with an unmapped ProjectVersion refuses' (($r.Code -eq 2) -and ($r.Err -match '99\.9')) "exit $($r.Code): $($r.Err.Trim())"
  $r = Run @('rules', '--json', '--target-compiler', 'auto')
  Check 'T2 auto without a .dproj refuses' (($r.Code -eq 2) -and ($r.Err -match 'needs the owning \.dproj')) "exit $($r.Code): $($r.Err.Trim())"

  # ---- T3 rules --json ----
  $j37 = RulesJson @()
  $rows = @($j37.rules)
  Check 'T3 rules --json has rows' ($rows.Count -gt 100) "rows $($rows.Count)"
  $missing = @($rows | Where-Object { ($null -eq $_.needs_compiler) -or ($null -eq $_.compat_since) -or ($null -eq $_.target_active) })
  Check 'T3 every row carries needs_compiler / compat_since / target_active' ($missing.Count -eq 0) (($missing | Select-Object -First 5 | ForEach-Object id) -join ', ')
  Check 'T3 root target_compiler = 37 by default' ($j37.target_compiler -eq 37) "got $($j37.target_compiler)"
  $inactive37 = @($rows | Where-Object { $_.target_active -ne $_.default_enabled })
  Check 'T3 at 37 target_active == default_enabled on every row' ($inactive37.Count -eq 0) (($inactive37 | Select-Object -First 5 | ForEach-Object id) -join ', ')
  $j36 = RulesJson @('--target-compiler', '36')
  $want36 = @($rows | Where-Object { $_.needs_compiler -gt 36 } | ForEach-Object id | Sort-Object)
  $got36  = @($j36.rules | Where-Object { $_.default_enabled -and -not $_.target_active } | ForEach-Object id | Sort-Object)
  Check 'T3 at 36 exactly the needs_compiler>36 ids go inactive' (($want36.Count -ge 2) -and (($want36 -join ',') -eq ($got36 -join ','))) "want [$($want36 -join ',')] got [$($got36 -join ',')]"
  # section-2 table pin (plan 2026-10-28-two-way-modernize-downgrade-plan.md): rule-level needs_compiler
  $pin = @{ 'ifthen-to-if-expression' = 37; 'is-not-operator' = 37; 'unreadable-literal' = 35;
            'pos-for-contains' = 0; 'manual-inrange' = 14; 'nonminimal-bool' = 0 }
  foreach ($k in $pin.Keys) {
    $row = $rows | Where-Object { $_.id -eq $k } | Select-Object -First 1
    Check "T3 pin needs_compiler $k = $($pin[$k])" ($row -and ($row.needs_compiler -eq $pin[$k])) "got $($row.needs_compiler)"
  }

  # ---- T4 lint gating (both directions) ----
  $l37 = LintPairs $probe @()
  $l36 = LintPairs $probe @('--target-compiler', '36')
  foreach ($p in @('is-not-operator:13', 'ifthen-to-if-expression:15', 'nonminimal-bool:16', 'nonminimal-bool:18')) {
    Check "T4 positive control: $p fires at the default target" ($l37.Pairs -contains $p) ($l37.Pairs -join ' ')
  }
  foreach ($p in @('is-not-operator:13', 'ifthen-to-if-expression:15', 'nonminimal-bool:16')) {
    Check "T4 $p is silenced at 36" (($l36.Pairs.Count -gt 0) -and -not ($l36.Pairs -contains $p)) ($l36.Pairs -join ' ')
  }
  Check 'T4 nonminimal-bool:18 (= entry, any compiler) still fires at 36' ($l36.Pairs -contains 'nonminimal-bool:18') ($l36.Pairs -join ' ')
  Check 'T4 stderr status line at 36' ($l36.Err -match 'target-compiler: 36 \(Delphi 12\) -- \d+ modernize rule\(s\) gated, \d+ compat rule\(s\) on') $l36.Err.Trim()
  Check 'T4 no status line at the default target' (-not ($l37.Err -match 'target-compiler:')) $l37.Err.Trim()
  $l3 = LintPairs $probe @('--target-compiler', '37')
  Check 'T4 explicit 37 == default' ((($l3.Pairs | Sort-Object) -join ' ') -eq (($l37.Pairs | Sort-Object) -join ' ')) ''

  # ---- T5 config + profile + precedence ----
  $cfg = Join-Path $WorkDir 'cfg.json'
  WriteAscii $cfg '{ "target_compiler": "12", "profiles": { "modern": { "target_compiler": "13" } } }'
  $c1 = LintPairs $probe @('--config', $cfg)
  Check 'T5 config target_compiler 12 silences is-not-operator' (-not ($c1.Pairs -contains 'is-not-operator:13')) ($c1.Pairs -join ' ')
  $c2 = LintPairs $probe @('--config', $cfg, '--profile', 'modern')
  Check 'T5 profile override back to 13 reports it again' ($c2.Pairs -contains 'is-not-operator:13') ($c2.Pairs -join ' ')
  $c3 = LintPairs $probe @('--config', $cfg, '--target-compiler', '13')
  Check 'T5 the command line beats the config' ($c3.Pairs -contains 'is-not-operator:13') ($c3.Pairs -join ' ')
  $cfgBad = Join-Path $WorkDir 'cfgbad.json'
  WriteAscii $cfgBad '{ "target_compiler": "Delphi 99" }'
  $c4 = Run @('lint', $probe, '--json', '--config', $cfgBad)
  Check 'T5 an unknown config token refuses and names its source' (($c4.Code -eq 2) -and ($c4.Err -match 'config target_compiler')) "exit $($c4.Code): $($c4.Err.Trim())"

  # ---- T6 compat_since sidecar ----
  $rd = Join-Path $WorkDir 'rules'
  New-Item -ItemType Directory -Force $rd | Out-Null
  WriteAscii (Join-Path $rd 'zz-compat-probe.scm') "((exprBinary lhs: (_) operator: (kIs) rhs: (_)) @warn)`n"
  WriteAscii (Join-Path $rd 'zz-compat-probe.json') '{ "id": "zz-compat-probe", "category": "compat", "severity": "hint", "message": "probe", "warn_capture": "warn", "enabled": false, "compat_since": 34 }'
  $p37 = LintPairs $probe @('--rules-dir', $rd)
  $p33 = LintPairs $probe @('--rules-dir', $rd, '--target-compiler', '33')
  Check 'T6 compat_since 34 rule is OFF at 37' (-not ($p37.Pairs -contains 'zz-compat-probe:13')) ($p37.Pairs -join ' ')
  Check 'T6 compat_since 34 rule is ON at 33' ($p33.Pairs -contains 'zz-compat-probe:13') ($p33.Pairs -join ' ')
  $jr = RulesJson @('--rules-dir', $rd)
  $zr = $jr.rules | Where-Object { $_.id -eq 'zz-compat-probe' } | Select-Object -First 1
  Check 'T6 rules --json reads compat_since and the compat category' ($zr -and ($zr.compat_since -eq 34) -and ($zr.category -eq 'compat')) ($zr | ConvertTo-Json -Compress)
  # never both ON: is-not-operator (needs_compiler 37) beside a compat twin (compat_since 37)
  Copy-Item (Join-Path $repo 'rules\is-not-operator.scm'), (Join-Path $repo 'rules\is-not-operator.json') $rd
  WriteAscii (Join-Path $rd 'zz-compat-twin.scm') "((exprBinary lhs: (_) operator: (kIs) rhs: (_)) @warn)`n"
  WriteAscii (Join-Path $rd 'zz-compat-twin.json') '{ "id": "zz-compat-twin", "category": "compat", "severity": "hint", "message": "twin", "warn_capture": "warn", "enabled": false, "compat_since": 37 }'
  $both = @(); $neither = @()
  foreach ($t in @(14, 20, 24, 28, 33, 35, 36, 37)) {
    $jt = RulesJson @('--rules-dir', $rd, '--target-compiler', "$t")
    $m = ($jt.rules | Where-Object { $_.id -eq 'is-not-operator' }).target_active
    $c = ($jt.rules | Where-Object { $_.id -eq 'zz-compat-twin' }).target_active
    if ($m -and $c) { $both += "$t" }
    if (-not $m -and -not $c) { $neither += "$t" }
  }
  Check 'T6 a modernize rule and its compat twin are never both active (targets 14..37)' ($both.Count -eq 0) ("both at: " + ($both -join ' '))
  Check 'T6 ... and exactly one of the pair is active at every target' ($neither.Count -eq 0) ("neither at: " + ($neither -join ' '))
  # ---- T7 byte-identical at the default target ----
  if ($BaseExe) {
    $basePath = (Resolve-Path $BaseExe).Path
    $diffs = @()
    foreach ($f in @(Get-ChildItem (Join-Path $repo 'tests\lint') -Filter '*.pas' | Sort-Object Name)) {
      $cfgF = [IO.Path]::ChangeExtension($f.FullName, '.config.json')
      $xa = @('lint', $f.FullName, '--json'); if (Test-Path $cfgF) { $xa += @('--config', $cfgF) }
      $a = & $exePath @xa 2>$null | Out-String
      $b = & $basePath @xa 2>$null | Out-String
      if ($a -cne $b) { $diffs += $f.Name }
    }
    Check 'T7 lint --json on every tests\lint fixture is byte-identical to the base exe' ($diffs.Count -eq 0) ($diffs -join ', ')
    $strip = {
      param($js)
      $o = $js | ConvertFrom-Json
      foreach ($r in $o.rules) { foreach ($k in 'needs_compiler', 'compat_since', 'target_active') { $r.PSObject.Properties.Remove($k) } }
      $o.PSObject.Properties.Remove('target_compiler')
      $o | ConvertTo-Json -Depth 8 -Compress
    }
    $na = & $strip ((& $exePath rules --json 2>$null) | Out-String)
    $nb = & $strip ((& $basePath rules --json 2>$null) | Out-String)
    Check 'T7 rules --json minus the new keys is identical to the base exe' ($na -ceq $nb) ''
  } else { Write-Host 'SKIP T7: no -BaseExe' -ForegroundColor Yellow }
} finally {
  Pop-Location
  try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
}
Write-Host ("target-compiler guard: {0} pass / {1} fail" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
