<#
  run_emit_params.ps1 -- TDD harness for D5 Task 2: parser emits typed params.

  Fixture params.pas (class TThing) exercises every param shape the parser must
  handle, so a future refactor of the identifier-loop or TypeTextOf cannot
  silently regress one of them:
    Handle(const AItem: TThing; ACount: Integer)   -- const modifier + plain
    Combine(A, B: TThing)                           -- GROUPED: two symbols, shared type
    Fill(var AList: TThing; out ACount: Integer)    -- var / out modifiers stripped
    Raw(var E)                                       -- UNTYPED var -> empty Signature

  Copies the fixture to a scratch dir under C:\TEMP, indexes it to a scratch db,
  then queries each formal parameter and asserts it was emitted as an skParam
  symbol carrying its declared type (Signature) and parented to its routine.

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

# Query a symbol by name and return the param whose qualified_name matches
# exactly ($null when none). Matching on qname disambiguates leaf-name
# collisions (ACount appears in both Handle and Fill). --json prints a JSON
# array of matched symbols.
function ParamByQName([string]$name, [string]$qname) {
  $j = & $exePath query --name $name --db $db --json 2>$null | Out-String
  $arr = $null; try { $arr = ($j | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -eq $arr) { return $null }
  foreach ($s in @($arr)) { if ($s.kind -eq 'param' -and $s.qualified_name -eq $qname) { return $s } }
  return $null
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- Handle: const modifier stripped + plain param ---
  $ai = ParamByQName 'AItem' 'params.TThing.Handle.AItem'
  Check 'Handle.AItem is param, type contains TThing'          ($null -ne $ai -and $ai.signature -match 'TThing')
  $ac = ParamByQName 'ACount' 'params.TThing.Handle.ACount'
  Check 'Handle.ACount is param, type = Integer'               ($null -ne $ac -and $ac.signature -match '^\s*Integer\s*$')

  # --- Combine: GROUPED A, B: TThing -> two symbols sharing the type ---
  $a = ParamByQName 'A' 'params.TThing.Combine.A'
  $b = ParamByQName 'B' 'params.TThing.Combine.B'
  Check 'Combine.A is param, type contains TThing'             ($null -ne $a -and $a.signature -match 'TThing')
  Check 'Combine.B is param, type contains TThing'             ($null -ne $b -and $b.signature -match 'TThing')
  Check 'grouped A,B share the same type text'                 ($null -ne $a -and $null -ne $b -and $a.signature -eq $b.signature)

  # --- Fill: var / out modifiers stripped to the bare type ---
  $al = ParamByQName 'AList' 'params.TThing.Fill.AList'
  Check 'Fill.AList is param, var stripped -> type = TThing'   ($null -ne $al -and $al.signature -match '^\s*TThing\s*$')
  $fc = ParamByQName 'ACount' 'params.TThing.Fill.ACount'
  Check 'Fill.ACount is param, out stripped -> type = Integer' ($null -ne $fc -and $fc.signature -match '^\s*Integer\s*$')

  # --- Raw: UNTYPED var -> still a symbol, empty Signature ---
  $e = ParamByQName 'E' 'params.TThing.Raw.E'
  Check 'Raw.E is param (untyped var still emitted)'           ($null -ne $e)
  Check 'Raw.E has EMPTY Signature (untyped)'                  ($null -ne $e -and $e.signature -eq '')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
