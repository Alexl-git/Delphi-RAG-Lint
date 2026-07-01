<#
  run_store_tests.ps1 -- TDD harness for STORE-BACKED drag-lint rules.

  The file harness (tests\lint\run_lint_tests.ps1) runs `lint <file>` with NO
  --db, so store/graph/flow rules never fire. This sibling harness closes that
  gap: each case directory is INDEXED into a throwaway SQLite store, then the
  store-bearing check path is run against it.

  Layout -- one subdirectory per case under tests\lint-store\<case>\:
      <case>\*.pas          one or more units (the class/enum/uses spread)
      <case>\expected.txt   directives (format below)
      <case>\config.json    OPTIONAL -- passed via --config (for OFF-by-default
                            or thresholded store rules)
      <case>\case.json      OPTIONAL -- { "mode": "check-ast" | "lint-all",
                            "subject": "<file.pas>" }. Default mode = check-ast
                            over EVERY .pas in the case (aggregated); lint-all
                            runs the whole-project store path once.

  expected.txt directives (one per line; blank + #-comment lines ignored):
      <rule> <file>:<line>   a finding with this rule at file:line MUST be present
      <rule> <line>          shorthand when the case has a single subject .pas
      !<rule> <file>         NO finding with this rule may appear in <file>
      !<rule>                that rule must not fire anywhere in the case
      none                   the case must produce ZERO findings of ANY rule

  Usage:
    pwsh -File tests\lint-store\run_store_tests.ps1
    pwsh -File tests\lint-store\run_store_tests.ps1 -Filter abstract-*
#>
[CmdletBinding()]
param(
  [string]$Exe    = "third_party\dll-win64\drag-lint.exe",
  [string]$Rules  = "rules",
  [string]$Tests  = "tests\lint-store",
  [string]$Filter = "*"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo

$exePath = (Resolve-Path $Exe).Path
$exeDir  = Split-Path $exePath -Parent
$rulesSrc = (Resolve-Path $Rules).Path

# --- sync rules next to the exe (the exe resolves <exe-dir>\rules) ---
$rulesDst = Join-Path $exeDir "rules"
if (-not (Test-Path $rulesDst)) { New-Item -ItemType Directory -Path $rulesDst | Out-Null }
Copy-Item (Join-Path $rulesSrc "*.scm")  $rulesDst -Force
Copy-Item (Join-Path $rulesSrc "*.json") $rulesDst -Force
if (Test-Path (Join-Path $rulesSrc "builtin-symbols.txt")) {
  Copy-Item (Join-Path $rulesSrc "builtin-symbols.txt") $rulesDst -Force
}

# Slice the first JSON array out of the CLI output (a few preamble lines --
# FTS5 probe / loaded defaults -- precede the JSON).
function Parse-Findings($raw) {
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  if ($b -lt 0) { return @() }
  try {
    $r = ($txt.Substring($b) | ConvertFrom-Json)
    if ($null -eq $r) { return @() }
    return @($r)
  } catch { return @() }
}

$pass = 0; $fail = 0; $failed = @()

$cases = Get-ChildItem -Path $Tests -Directory | Where-Object { $_.Name -like $Filter }
foreach ($case in $cases) {
  $expFile = Join-Path $case.FullName "expected.txt"
  if (-not (Test-Path $expFile)) { continue }

  $cfgFile  = Join-Path $case.FullName "config.json"
  $caseFile = Join-Path $case.FullName "case.json"
  $mode = "check-ast"; $subject = $null
  if (Test-Path $caseFile) {
    try {
      $cj = Get-Content $caseFile -Raw | ConvertFrom-Json
      if ($cj.mode)    { $mode = $cj.mode }
      if ($cj.subject) { $subject = $cj.subject }
    } catch {}
  }

  # index the case dir into a throwaway store
  $db = Join-Path $env:TEMP ("lintstore_" + $case.Name + ".sqlite")
  if (Test-Path $db) { Remove-Item $db -Force }
  & $exePath index $case.FullName --db $db 2>$null | Out-Null

  # collect findings, each tagged with its owning .pas basename
  $findings = @()
  if ($mode -eq "lint-all") {
    $report = Join-Path $env:TEMP ("lintstore_" + $case.Name + ".report.txt")
    $args = @("lint-all","--db",$db,"--json")
    if (Test-Path $cfgFile) { $args += @("--config",$cfgFile) }
    $raw = & $exePath @args 2>$null
    foreach ($f in (Parse-Findings $raw)) {
      $fp = if ($f.file_path) { $f.file_path } else { $f.file }
      $fn = if ($fp) { Split-Path $fp -Leaf } else { "" }
      $findings += [pscustomobject]@{ rule=$f.rule; line=$f.start_line; file=$fn }
    }
  } else {
    $pasFiles = Get-ChildItem -Path (Join-Path $case.FullName "*.pas")
    if ($subject) { $pasFiles = $pasFiles | Where-Object { $_.Name -eq $subject } }
    foreach ($pas in $pasFiles) {
      $args = @("check-ast",$pas.FullName,"--db",$db,"--format","json")
      if (Test-Path $cfgFile) { $args += @("--config",$cfgFile) }
      $raw = & $exePath @args 2>$null
      foreach ($f in (Parse-Findings $raw)) {
        $findings += [pscustomobject]@{ rule=$f.rule; line=$f.start_line; file=$pas.Name }
      }
    }
  }

  # build lookup sets
  $actualTriples = @{}   # rule:file:line
  $actualRules   = @{}   # rule
  $actualRuleFile= @{}   # rule:file
  foreach ($f in $findings) {
    $actualTriples["$($f.rule):$($f.file):$($f.line)"] = $true
    $actualRules[$f.rule] = $true
    $actualRuleFile["$($f.rule):$($f.file)"] = $true
  }
  # single-subject shorthand: if exactly one .pas was checked, allow "<rule> <line>"
  $onlyFile = $null
  $distinctFiles = @($findings | ForEach-Object { $_.file } | Sort-Object -Unique)
  $pasInCase = @(Get-ChildItem -Path (Join-Path $case.FullName "*.pas"))
  if ($subject) { $onlyFile = $subject }
  elseif ($pasInCase.Count -eq 1) { $onlyFile = $pasInCase[0].Name }

  $problems = @()
  $directives = Get-Content $expFile | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }
  foreach ($d in $directives) {
    $t = $d.Trim()
    if ($t -eq "none") {
      if ($findings.Count -gt 0) {
        $problems += "expected NO findings, got $($findings.Count): " + (($findings | ForEach-Object { "$($_.rule):$($_.file):$($_.line)" }) -join ", ")
      }
      continue
    }
    $absent = $false
    if ($t.StartsWith("!")) { $absent = $true; $t = $t.Substring(1).Trim() }
    $parts = $t -split "\s+"
    $rid = $parts[0]
    $loc = if ($parts.Count -ge 2) { $parts[1] } else { "" }

    # loc may be "<file>:<line>", "<file>", or "<line>"
    $file = $null; $line = $null
    if ($loc -match '^(.+\.pas):(\d+)$') { $file = $Matches[1]; $line = $Matches[2] }
    elseif ($loc -match '^\d+$')         { $file = $onlyFile;   $line = $loc }
    elseif ($loc -ne "")                 { $file = $loc }        # rule + file only

    if ($absent) {
      if ($line) {
        if ($actualTriples.ContainsKey("${rid}:${file}:${line}")) { $problems += "rule '$rid' should NOT fire at ${file}:${line} but did" }
      } elseif ($file) {
        if ($actualRuleFile.ContainsKey("${rid}:${file}")) { $problems += "rule '$rid' should NOT fire in $file but did" }
      } else {
        if ($actualRules.ContainsKey($rid)) { $problems += "rule '$rid' should NOT fire but did" }
      }
    } else {
      if (-not $line) { $problems += "bad directive (need file:line): '$d'"; continue }
      if (-not $actualTriples.ContainsKey("${rid}:${file}:${line}")) {
        $problems += "missing expected '$rid' at ${file}:${line}"
      }
    }
  }

  if (Test-Path $db) { Remove-Item $db -Force }

  if ($problems.Count -eq 0) {
    $pass++
    Write-Host ("PASS  " + $case.Name)
  } else {
    $fail++
    $failed += $case.Name
    Write-Host ("FAIL  " + $case.Name) -ForegroundColor Red
    foreach ($p in $problems) { Write-Host ("        " + $p) -ForegroundColor Red }
    if ($findings.Count -gt 0) {
      Write-Host ("        actual: " + (($findings | ForEach-Object { "$($_.rule):$($_.file):$($_.line)" }) -join ", "))
    } else {
      Write-Host ("        actual: (none)")
    }
  }
}

Write-Host ""
Write-Host ("store-tests: $pass pass / $fail fail / " + ($pass + $fail) + " total")
if ($fail -gt 0) { exit 1 } else { exit 0 }
