<#
  run_doc_p2_complexity.ps1 -- Auto-Document Phase 2, Task 3: Complexity fact
  (cyclomatic + body LOC).

  Uses fixtures\docp2\complexity.pas:
    * ComplexFn(A, B, C: Integer): Integer -- mixes if/ifElse/for/case/and/or so
      its cyclomatic complexity is >= 10 (docs.complexity_min default) and also
      calls TrivialFn (giving TrivialFn a Called-from fact, so TrivialFn still
      gets a managed block of its own -- proving the Complexity line is
      SPECIFICALLY omitted by the threshold, not that the whole block is
      missing for unrelated reasons).
    * TrivialFn(A: Integer): Integer -- a single if/else (CC well under 10).

  Drives `index` -> `document --unit --apply` and asserts, from the file
  content:
    1. ComplexFn's managed block contains 'Complexity: N (cyclomatic), M lines'
       with N >= 10.
    2. TrivialFn's managed block EXISTS (AUTO_BEGIN present, via its
       Called-from fact) but contains NO 'Complexity:' line.
    3. Idempotency: reindex + a second --apply leaves the file byte-identical
       (same facts -> same deterministic render -> daUnchanged).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp2\complexity.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp2complexity'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'complexity.pas'
$db     = Join-Path $scratch 'docp2complexity.sqlite'
Copy-Item $fixture $target -Force

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern (the interface declaration -- always the earlier
# of the two textually-identical free-function decl/impl signature lines,
# since interface precedes implementation in a well-formed unit). '' if the
# declaration is not found.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return ($blockLines -join "`n")
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'document --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)

  # --- ComplexFn: Complexity line present, N >= 10 -------------------------
  $complexBlock = Get-DocBlockAbove $lines '^function ComplexFn\(A, B, C: Integer\): Integer;'
  Check 'ComplexFn decl found' ($null -ne $complexBlock)
  Check 'ComplexFn has a managed block (AUTO_BEGIN)' ($complexBlock -match '<!-- drag-lint:auto BEGIN -->')
  $m = [regex]::Match($complexBlock, 'Complexity: (\d+) \(cyclomatic\), (\d+) lines')
  Check 'ComplexFn has a Complexity: N (cyclomatic), M lines line' ($m.Success)
  if ($m.Success) {
    Check 'ComplexFn Complexity N >= 10 (docs.complexity_min default)' ([int]$m.Groups[1].Value -ge 10)
    Check 'ComplexFn Complexity M lines > 0' ([int]$m.Groups[2].Value -gt 0)
  }

  # --- TrivialFn: managed block exists (Called-from), but NO Complexity ----
  $trivialBlock = Get-DocBlockAbove $lines '^function TrivialFn\(A: Integer\): Integer;'
  Check 'TrivialFn decl found' ($null -ne $trivialBlock)
  Check 'TrivialFn has a managed block (Called-from: ComplexFn keeps it non-empty)' ($trivialBlock -match '<!-- drag-lint:auto BEGIN -->')
  Check 'TrivialFn block has NO Complexity line (CC below docs.complexity_min)' ($trivialBlock -notmatch 'Complexity:')

  # --- Idempotency: reindex (facts are index-time) + re-apply -> no change ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical after reindex + 2nd apply' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
