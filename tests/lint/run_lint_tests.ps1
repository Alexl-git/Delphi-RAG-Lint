<#
  run_lint_tests.ps1 -- TDD harness for drag-lint lint rules (external .scm + built-ins).

  For each tests\lint\*.pas and *.dfm that has a sibling *.expected file, runs
  `drag-lint lint <file> --json` and checks the findings against expectations.
  (.dfm fixtures cover the DFM grammar path: valid forms must be clean, only a
  genuinely malformed DFM may surface a parser-error.)

  .expected format (one directive per line; blank lines and #-comments ignored):
      <rule-id> <line>      -> a finding with this rule id at this 1-based line MUST be present
      !<rule-id>            -> NO finding with this rule id may appear anywhere in the file
      none                  -> the file must produce ZERO findings of ANY rule (clean fixture)

  Before running, the script syncs repo rules\ into <exe-dir>\rules\ so the
  installed Win64 binary actually loads them (the exe resolves <exe-dir>\rules).

  Usage:
    pwsh -File tests\lint\run_lint_tests.ps1
    pwsh -File tests\lint\run_lint_tests.ps1 -Exe path\to\drag-lint.exe -Filter empty-*
#>
[CmdletBinding()]
param(
  [string]$Exe    = "third_party\dll-win64\drag-lint.exe",
  [string]$Rules  = "rules",
  [string]$Tests  = "tests\lint",
  [string]$Filter = "*"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo

$exePath = (Resolve-Path $Exe).Path
$exeDir  = Split-Path $exePath -Parent
$rulesSrc = (Resolve-Path $Rules).Path

# --- sync rules next to the exe (the deploy gap: exe loads <exe-dir>\rules) ---
$rulesDst = Join-Path $exeDir "rules"
if (-not (Test-Path $rulesDst)) { New-Item -ItemType Directory -Path $rulesDst | Out-Null }
Copy-Item (Join-Path $rulesSrc "*.scm")  $rulesDst -Force
Copy-Item (Join-Path $rulesSrc "*.json") $rulesDst -Force
if (Test-Path (Join-Path $rulesSrc "builtin-symbols.txt")) {
  Copy-Item (Join-Path $rulesSrc "builtin-symbols.txt") $rulesDst -Force
}

$pass = 0; $fail = 0; $failed = @()

$fixtures = Get-ChildItem -Path (Join-Path $Tests "*.pas"),(Join-Path $Tests "*.dfm") | Where-Object { $_.BaseName -like $Filter }
foreach ($pas in $fixtures) {
  # Prefer <file>.expected (full-name sibling) so .dfm companion files can have
  # their own expectations separate from the matching .pas fixture.
  $expFile = $pas.FullName + ".expected"
  if (-not (Test-Path $expFile)) { $expFile = [IO.Path]::ChangeExtension($pas.FullName, ".expected") }
  if (-not (Test-Path $expFile)) { continue }

  # Per-fixture config: if <fixture>.config.json exists, pass it via --config so
  # config-driven rules (param_prefix, keyword_case, short_identifier_check) can be
  # exercised. Without it the CLI uses built-in defaults.
  $cfgFile = [IO.Path]::ChangeExtension($pas.FullName, ".config.json")
  if (Test-Path $cfgFile) {
    $raw = & $exePath lint $pas.FullName --config $cfgFile --json 2>$null
  } else {
    $raw = & $exePath lint $pas.FullName --json 2>$null
  }
  $findings = @()
  try { $findings = ($raw | ConvertFrom-Json) } catch { $findings = @() }
  if ($null -eq $findings) { $findings = @() }

  # actual set of "rule:line" and the set of rule ids present
  $actualPairs = @{}
  $actualRules = @{}
  foreach ($f in $findings) {
    $actualPairs["$($f.rule):$($f.start_line)"] = $true
    $actualRules[$f.rule] = $true
  }

  $problems = @()
  $directives = Get-Content $expFile | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }
  foreach ($d in $directives) {
    $t = $d.Trim()
    if ($t -eq "none") {
      if ($findings.Count -gt 0) {
        $problems += "expected NO findings, got $($findings.Count): " + (($findings | ForEach-Object { "$($_.rule):$($_.start_line)" }) -join ", ")
      }
    }
    elseif ($t.StartsWith("!")) {
      $body = $t.Substring(1).Trim()
      $bparts = $body -split "\s+"
      if ($bparts.Count -ge 2) {
        # !<rule> <line>  -> that exact (rule,line) pair must be ABSENT
        $rid = $bparts[0]; $line = $bparts[1]
        if ($actualPairs.ContainsKey("${rid}:${line}")) { $problems += "rule '$rid' should NOT fire at line $line but did" }
      } else {
        # !<rule>  -> that rule must not fire anywhere
        $rid = $body
        if ($actualRules.ContainsKey($rid)) { $problems += "rule '$rid' should NOT fire but did" }
      }
    }
    else {
      $parts = $t -split "\s+"
      $rid = $parts[0]; $line = $parts[1]
      if (-not $actualPairs.ContainsKey("${rid}:${line}")) {
        $problems += "missing expected '$rid' at line $line"
      }
    }
  }

  if ($problems.Count -eq 0) {
    $pass++
    Write-Host ("PASS  " + $pas.Name)
  } else {
    $fail++
    $failed += $pas.Name
    Write-Host ("FAIL  " + $pas.Name) -ForegroundColor Red
    foreach ($p in $problems) { Write-Host ("        " + $p) -ForegroundColor Red }
    if ($findings.Count -gt 0) {
      Write-Host ("        actual: " + (($findings | ForEach-Object { "$($_.rule):$($_.start_line)" }) -join ", "))
    } else {
      Write-Host ("        actual: (none)")
    }
  }
}

Write-Host ""
Write-Host ("lint-tests: $pass pass / $fail fail / " + ($pass + $fail) + " total")
if ($fail -gt 0) { exit 1 } else { exit 0 }
