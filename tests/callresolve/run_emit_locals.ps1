<#
  run_emit_locals.ps1 -- TDD harness for D5 Task 3: parser emits typed local vars.

  Fixture locals.pas (class TWorker, method Go) exercises the local-var shapes the
  parser must handle, so a future refactor of the var-section walk or TypeTextOf
  cannot silently regress one of them:
    L: TWorker      -- plainly-typed CLASS local (Task 5 resolves receiver L)
    N: Integer      -- scalar local
    X, Y: TWorker   -- GROUPED: two symbols sharing one type

  Copies the fixture to a scratch dir under C:\TEMP, indexes it to a scratch db,
  then queries each local var and asserts it was emitted as an skLocalVar symbol
  (kind 'local_var') carrying its declared type (Signature) and parented -- by
  qualified name -- to its routine (locals.TWorker.Go).

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\locals.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_emitlocals'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'locals.pas'
$db      = Join-Path $scratch 'locals.sqlite'
Copy-Item $fixture $target -Force

# Query a symbol by name and return the local var whose qualified_name matches
# exactly ($null when none). Matching on qname disambiguates leaf-name
# collisions across routines. --json prints a JSON array of matched symbols.
function LocalByQName([string]$name, [string]$qname) {
  $j = & $exePath query --name $name --db $db --json 2>$null | Out-String
  $arr = $null; try { $arr = ($j | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -eq $arr) { return $null }
  foreach ($s in @($arr)) { if ($s.kind -eq 'local_var' -and $s.qualified_name -eq $qname) { return $s } }
  return $null
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- L: plainly-typed CLASS local -> Signature = TWorker ---
  $l = LocalByQName 'L' 'locals.TWorker.Go.L'
  Check 'Go.L is local_var, type = TWorker'               ($null -ne $l -and $l.signature -match '^\s*TWorker\s*$')

  # --- N: scalar local -> Signature = Integer ---
  $n = LocalByQName 'N' 'locals.TWorker.Go.N'
  Check 'Go.N is local_var, type = Integer'               ($null -ne $n -and $n.signature -match '^\s*Integer\s*$')

  # --- X, Y: GROUPED -> two symbols sharing the type ---
  $x = LocalByQName 'X' 'locals.TWorker.Go.X'
  $y = LocalByQName 'Y' 'locals.TWorker.Go.Y'
  Check 'Go.X is local_var, type contains TWorker'        ($null -ne $x -and $x.signature -match 'TWorker')
  Check 'Go.Y is local_var, type contains TWorker'        ($null -ne $y -and $y.signature -match 'TWorker')
  Check 'grouped X,Y share the same type text'            ($null -ne $x -and $null -ne $y -and $x.signature -eq $y.signature)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
