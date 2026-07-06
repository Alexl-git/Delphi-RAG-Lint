<#
  run_emit_params.ps1 -- TDD harness for D5 Task 2: parser emits typed params.

  Fixture params.pas declares:
    procedure TThing.Handle(const AItem: TThing; ACount: Integer);
  Copies the fixture to a scratch dir under C:\TEMP, indexes it to a scratch db,
  then queries each formal parameter by name and asserts it was emitted as an
  skParam symbol carrying its declared type and parented to the routine:
    AItem  kind=param  type-text contains 'TThing'  qname=params.TThing.Handle.AItem
    ACount kind=param  type-text = 'Integer'        qname=params.TThing.Handle.ACount

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\params.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_emitparams'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'params.pas'
$db      = Join-Path $scratch 'params.sqlite'
Copy-Item $fixture $target -Force

# Query a symbol by name, return the first JSON object whose kind = 'param'
# (or $null when none). --json prints a JSON array of matched symbols.
function ParamSym([string]$name) {
  $j = & $exePath query --name $name --db $db --json 2>$null | Out-String
  $arr = $null; try { $arr = ($j | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -eq $arr) { return $null }
  foreach ($s in @($arr)) { if ($s.kind -eq 'param') { return $s } }
  return $null
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  $ai = ParamSym 'AItem'
  Check 'AItem emitted as kind=param'                 ($null -ne $ai)
  Check 'AItem type-text contains TThing'             ($null -ne $ai -and $ai.signature -match 'TThing')
  Check 'AItem parented to params.TThing.Handle'      ($null -ne $ai -and $ai.qualified_name -eq 'params.TThing.Handle.AItem')

  $ac = ParamSym 'ACount'
  Check 'ACount emitted as kind=param'                ($null -ne $ac)
  Check 'ACount type-text = Integer'                  ($null -ne $ac -and $ac.signature -match '^\s*Integer\s*$')
  Check 'ACount parented to params.TThing.Handle'     ($null -ne $ac -and $ac.qualified_name -eq 'params.TThing.Handle.ACount')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
