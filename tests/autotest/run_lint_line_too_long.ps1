<#
  run_lint_line_too_long.ps1 -- the `line-too-long` rule (owner ruling D3,
  2026-10-25: threshold 1020, ON by default, scoped by ownRoots like every rule).

  WHY 1020. dcc64 37.0 accepts a line of up to 1020 characters at ANY file
  offset; a line of 1021-4095 compiles or fails with F2069 depending on where it
  lands, so an edit ABOVE a long line can break the build without touching it
  (docs\INBOX-2026-09-30-line-too-long-rule-and-lint-note.md; bit twice since:
  9a1b2aca, c18bf3b2). 1020 is the only length that is safe everywhere.

  The fixtures are GENERATED into a temp folder, never committed: a 1021-char
  line in the tree would trip run_doc_fact_line_length_guard.ps1 (arm E5).

  Assertions
    A  POSITIVE CONTROL: a 1021-char code line -> exactly one finding, on its
       line, with NO --enable / --rule (the rule is on by default).
    B  NEGATIVE: a 1020-char line -> no finding (the limit itself is legal).
    C  any line, not only code: a 1021-char // comment line is reported.
    D  `--rule line-too-long` narrows to the rule and still finds it (the
       LINT_GATE_DEAD_CODE list in CLI.pas carries the id).
    E  `rules --json` lists it with default_enabled = true.
#>
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Fail++; Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red }
}

$Dir = Join-Path ([IO.Path]::GetTempPath()) ("dl-ltl-" + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Dir)

function New-Unit([string]$Name, [string]$Long) {
  $lines = @(
    "unit $Name;",
    '',
    'interface',
    '',
    'const',
    $Long,
    '',
    'implementation',
    '',
    'end.')
  $path = Join-Path $Dir "$Name.pas"
  [IO.File]::WriteAllText($path, ($lines -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
  return $path
}
# The long line is line 6 in every fixture.
function Code-Line([int]$Len) {
  $head = "  C1 = '"; $tail = "';"
  return $head + ('b' * ($Len - $head.Length - $tail.Length)) + $tail
}
function Lint-Rows([string]$Path, [string[]]$Extra = @()) {
  $raw = (& $Exe lint $Path --json @Extra 2>$null | Out-String)
  if ([string]::IsNullOrWhiteSpace($raw)) { return ,@() }
  try { $all = $raw | ConvertFrom-Json } catch { Write-Host "  (not JSON: $($raw.Trim()))"; return ,@() }
  return ,@($all | Where-Object { $_.rule -eq 'line-too-long' })
}

try {
  $l1021 = Code-Line 1021; $l1020 = Code-Line 1020
  Check 'SANITY fixture lengths 1021/1020' (($l1021.Length -eq 1021) -and ($l1020.Length -eq 1020))

  Write-Host '== A positive control: 1021 chars, default rule set'
  $rows = Lint-Rows (New-Unit 'LtlLong' $l1021)
  Check 'A: exactly one line-too-long finding' ($rows.Count -eq 1) "got $($rows.Count)"
  Check 'A: anchored on line 6' (($rows.Count -eq 1) -and ($rows[0].start_line -eq 6)) "got $($rows | ForEach-Object start_line)"
  Check 'A: message quotes 1021 and the 1020 limit' (($rows.Count -eq 1) -and ($rows[0].message -match '1021') -and ($rows[0].message -match '1020'))

  Write-Host '== B negative: exactly 1020 chars'
  $rows = Lint-Rows (New-Unit 'LtlEdge' $l1020)
  Check 'B: no finding at the limit' ($rows.Count -eq 0) "got $($rows.Count)"

  Write-Host '== C a comment line counts too'
  $rows = Lint-Rows (New-Unit 'LtlComment' ('  // ' + ('c' * 1016)))
  Check 'C: 1021-char comment line reported' (($rows.Count -eq 1) -and ($rows[0].start_line -eq 6)) "got $($rows.Count)"

  Write-Host '== D --rule narrows to it'
  $rows = Lint-Rows (Join-Path $Dir 'LtlLong.pas') @('--rule', 'line-too-long')
  Check 'D: --rule line-too-long still reports' ($rows.Count -eq 1) "got $($rows.Count)"

  Write-Host '== E catalogue'
  $cat = (& $Exe rules --json 2>$null | Out-String | ConvertFrom-Json).rules | Where-Object { $_.id -eq 'line-too-long' }
  Check 'E: rules --json lists line-too-long' ($null -ne $cat)
  Check 'E: default_enabled = true' (($null -ne $cat) -and ($cat.default_enabled -eq $true))
}
finally {
  try { [IO.Directory]::Delete($Dir, $true) } catch { }
}

Write-Host "$($script:Pass) PASS, $($script:Fail) FAIL"
if ($script:Fail -gt 0) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
