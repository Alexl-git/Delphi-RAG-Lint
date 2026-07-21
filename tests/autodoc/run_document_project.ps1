<#
  run_document_project.ps1 -- project-wide AutoDocument batch (`document --project`
  / `document-all`) + the `--stubs` opt-in.

  Uses fixtures\docproj\: main.dpr (uses unitA, unitB), unitA.pas (Alpha calls
  Beta -> both carry facts; Noop is a bare public proc with NO facts) and
  unitB.pas (TWidget.Compute calls unitA.Alpha -> Compute carries facts).

  Asserts:
    * `document --project main.dpr --apply` (facts-only default) documents the
      facts-backed decls in BOTH unitA (Alpha, Beta) and unitB (Compute) --
      project-wide scope resolved via the compile closure.
    * facts-only default: the bare Noop (no facts) is NOT documented (no TODO
      flood) -- no /// comment directly above 'procedure Noop;'.
    * `--stubs`: the same Noop NOW gets a managed (empty, no "TODO" text --
      ADP1) summary tag (opt-in differs from the facts-only default).
    * IDEMPOTENCY: a second `--project --apply` leaves every file BYTE-IDENTICAL.
    * `document-all --apply` (no --project) documents every indexed unit's public
      facts-backed decls.
    * `--json` reports aggregated declCount / docCount over the whole project.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath   = (Resolve-Path $Exe).Path
$fixDir    = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docproj')).Path

# Copy the whole fixture set into a fresh scratch dir so --apply never mutates
# the repo fixtures. Index the dir, then drive document --project / document-all.
$scratch = Join-Path C:\TEMP 'draglint_docproj'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*') $scratch -Force
$dpr = Join-Path $scratch 'main.dpr'
$uA  = Join-Path $scratch 'unitA.pas'
$uB  = Join-Path $scratch 'unitB.pas'
$db  = Join-Path $scratch 'docproj.sqlite'

function NoopHasDoc($file) {
  # True when a /// comment sits directly above 'procedure Noop;'.
  $lines = [IO.File]::ReadAllLines($file)
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'procedure\s+Noop;') { return ($i -ge 1 -and $lines[$i-1] -match '///') }
  }
  return $false
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- facts-only default: project-wide scope documents both units ---
  & $exePath document --project $dpr --db $db --apply 2>$null | Out-Null
  Check 'project apply: exit 0' ($LASTEXITCODE -eq 0)

  $srcA = [IO.File]::ReadAllText($uA)
  $srcB = [IO.File]::ReadAllText($uB)

  # Project-wide scope: BOTH units gained managed facts blocks.
  Check 'unitA got a managed facts block' ($srcA -match '<!-- drag-lint:auto BEGIN -->')
  Check 'unitB got a managed facts block' ($srcB -match '<!-- drag-lint:auto BEGIN -->')
  Check 'unitA: Alpha documented (Calls fact)' ($srcA -match '(?s)Calls:[^\r\n]*Beta.*?function\s+Alpha\(')
  Check 'unitB: Compute documented (Calls fact)' ($srcB -match '(?s)Calls:[^\r\n]*Alpha.*?function\s+Compute\(')

  # facts-only default: the bare Noop (no facts) is NOT documented (no TODO flood).
  Check 'facts-only default: Noop NOT documented' (-not (NoopHasDoc $uA))

  # --- idempotency: a second --project --apply leaves every file byte-identical ---
  $beforeA = [IO.File]::ReadAllBytes($uA); $beforeB = [IO.File]::ReadAllBytes($uB)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --project $dpr --db $db --apply 2>$null | Out-Null
  $afterA = [IO.File]::ReadAllBytes($uA); $afterB = [IO.File]::ReadAllBytes($uB)
  Check 'idempotent: unitA byte-identical on 2nd run' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeA,[byte[]]$afterA))
  Check 'idempotent: unitB byte-identical on 2nd run' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeB,[byte[]]$afterB))

  # --- --stubs opt-in: on a FRESH scratch, Noop NOW gets a managed summary ---
  $sStub = Join-Path C:\TEMP 'draglint_docproj_stubs'
  if (Test-Path $sStub) { Remove-Item $sStub -Recurse -Force }
  New-Item -ItemType Directory -Path $sStub | Out-Null
  Copy-Item (Join-Path $fixDir '*') $sStub -Force
  $dprS = Join-Path $sStub 'main.dpr'
  $uAS  = Join-Path $sStub 'unitA.pas'
  $dbS  = Join-Path $sStub 'docproj.sqlite'
  & $exePath index $sStub --db $dbS 2>$null | Out-Null
  & $exePath document --project $dprS --db $dbS --stubs --apply 2>$null | Out-Null
  Check 'stubs project apply: exit 0' ($LASTEXITCODE -eq 0)
  $srcAS = [IO.File]::ReadAllText($uAS)
  Check 'stubs opt-in: Noop NOW documented' (NoopHasDoc $uAS)
  Check 'stubs opt-in: Noop has an empty managed <summary> (no TODO text -- ADP1)' `
    ($srcAS -match '(?s)<summary></summary>.*?procedure\s+Noop;')
  Check 'stubs opt-in: no "TODO" text anywhere in unitA output' ($srcAS -cnotmatch 'TODO')

  # --- document-all (no --project) documents every indexed unit ---
  $sAll = Join-Path C:\TEMP 'draglint_docproj_all'
  if (Test-Path $sAll) { Remove-Item $sAll -Recurse -Force }
  New-Item -ItemType Directory -Path $sAll | Out-Null
  Copy-Item (Join-Path $fixDir '*') $sAll -Force
  $uAA = Join-Path $sAll 'unitA.pas'
  $uBA = Join-Path $sAll 'unitB.pas'
  $dbA = Join-Path $sAll 'docproj.sqlite'
  & $exePath index $sAll --db $dbA 2>$null | Out-Null
  & $exePath document-all --db $dbA --apply 2>$null | Out-Null
  Check 'document-all: exit 0' ($LASTEXITCODE -eq 0)
  Check 'document-all: unitA documented' ([IO.File]::ReadAllText($uAA) -match '<!-- drag-lint:auto BEGIN -->')
  Check 'document-all: unitB documented' ([IO.File]::ReadAllText($uBA) -match '<!-- drag-lint:auto BEGIN -->')

  # --- --json aggregates declCount / docCount over the whole project ---
  $sJson = Join-Path C:\TEMP 'draglint_docproj_json'
  if (Test-Path $sJson) { Remove-Item $sJson -Recurse -Force }
  New-Item -ItemType Directory -Path $sJson | Out-Null
  Copy-Item (Join-Path $fixDir '*') $sJson -Force
  $dprJ = Join-Path $sJson 'main.dpr'
  $dbJ  = Join-Path $sJson 'docproj.sqlite'
  & $exePath index $sJson --db $dbJ 2>$null | Out-Null
  $rj = & $exePath document --project $dprJ --db $dbJ --json 2>$null | Out-String
  $ecj = $LASTEXITCODE
  $oj = $null; try { $oj = ($rj | ConvertFrom-Json) } catch { $oj = $null }
  # Aggregated over unitA (Alpha, Beta, Noop) + unitB (TWidget, Compute) = 5 public
  # interface-section documentable decls; facts-only keeps Alpha, Beta, Compute = 3.
  Check 'json: exit 0'            ($ecj -eq 0)
  Check 'json: declCount = 5'     ($null -ne $oj -and [int]$oj.declCount -eq 5)
  Check 'json: docCount = 3'      ($null -ne $oj -and [int]$oj.docCount  -eq 3)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
