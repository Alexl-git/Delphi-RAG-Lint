<#
  run_type_use_bind.ps1 -- a `type_use` ref binds to the type it names
  (backlog B-31, INBOX-charts-type-use-unbound).

  THE DEFECT. Not one `type_use` row carried a symbol_id (60,603 of 60,603 on
  ORM3 CLIENT, 41,944 on the self-index): `FViewModel: TCausFailViewModel;` had
  to be matched to its class BY NAME, so the charts round-trip graded every
  declared-type hop `[by name]`.

  THE FIX: a SEVENTH calls-stage stream (ResolveTypeUseRefs ->
  TCallResolver.ResolveTypeUse). Delphi's order, certain or nothing: the
  enclosing types and routines from the innermost out (a generic parameter of
  one of them declines; a nested type binds), the own unit's types, then
  exactly one TOP-LEVEL INTERFACE type of a used unit. Identity only.

  WHAT THIS GUARD PINS
    TU-*   seven type_use refs bind to the named type (own unit, used unit,
           nested type, heritage, generic argument)
    NEG-*  five stay NULL: a generic parameter (uTuLib declares a type T, so a
           by-name join binds it), two used units declaring the
           name, a used unit's IMPLEMENTATION-section type, a unit-qualified
           name (declined, not guessed), and a routine-LOCAL type the index
           does not list (positive control: the unit-level TLoc must not answer)
    the calls-stage `type-uses:` log line

  Usage: pwsh -File tests\callresolve\run_type_use_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\typeuses')).Path
$scratch = Join-Path C:\TEMP "draglint_type_use_bind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$use = Join-Path $scratch 'uTuUse.pas'
$db  = Join-Path $scratch 'typeuses.sqlite'

function Sql([string]$Query) {
  $raw = (& $exePath sql --db $db --json --limit 1000 --query $Query 2>$null) -join "`n"
  $b = $raw.IndexOf('{')
  if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
  $o = $raw.Substring($b) | ConvertFrom-Json
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += $h
  }
  return ,@($out)
}
function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $use -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
function TypeUseAt([string]$Marker, [string]$Name) {
  $line = LineOf $Marker
  return @(Sql ("SELECT r.id, r.symbol_id, t.qualified_name AS tq FROM refs r JOIN files f ON f.id = r.file_id " +
                "LEFT JOIN symbols t ON t.id = r.symbol_id WHERE f.path LIKE '%uTuUse.pas' AND r.kind = 'type_use' " +
                "AND r.start_line = $line AND r.name_text = '$Name'") | Where-Object { $_ })
}

$log = & $exePath index $scratch --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$pos = @(
  @('TU-HERITAGE',    'TBase',   'uTuUse.TBase'),
  @('TU-USED-UNIT',   'TShared', 'uTuLib.TShared'),
  @('TU-NESTED',      'TInner',  'uTuUse.TGen.TInner'),
  @('TU-UNIT-VAR',    'TBase',   'uTuUse.TBase'),
  @('TU-PARAM',       'TBase',   'uTuUse.TBase'),
  @('TU-GENERIC-ARG', 'TGen',    'uTuUse.TGen'),
  @('TU-GENERIC-ARG', 'TBase',   'uTuUse.TBase'),
  # review 2026-10-23: an ancestor's nested type is in scope before the used
  # units. Positive control: without the ancestor walk uTuLib.TNest answers.
  @('TU-INHERITED-NESTED', 'TNest', 'uTuUse.TBase2.TNest')
)
foreach ($p in $pos) {
  $r = @(TypeUseAt $p[0] $p[1])
  $got = if ($r.Count -eq 1) { [string]$r[0].tq } else { "rows=$($r.Count)" }
  Check "$($p[0]) binds $($p[1]) to $($p[2])" ($got -eq $p[2]) "got=$got"
}
foreach ($n in @(@('NEG-GENERIC', 'T'), @('NEG-AMBIGUOUS', 'TClash'), @('NEG-IMPL-SECTION', 'TImplOnly'),
                 @('NEG-QUALIFIED', 'TShared'), @('NEG-LOCAL-TYPE', 'TLoc'))) {
  $r = @(TypeUseAt $n[0] $n[1])
  Check "$($n[0]) $($n[1]) stays unbound" (($r.Count -eq 1) -and ($null -eq $r[0].symbol_id)) `
    ("rows=$($r.Count) tq=" + $(if ($r.Count) { $r[0].tq } else { '' }))
}

$line = @($log | Where-Object { "$_" -match 'type-uses: (\d+) of (\d+)' })
Check 'calls-stage type-uses: line present' ($line.Count -eq 1) "lines=$($line.Count)"

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  if ($scratch -and (Test-Path $scratch)) { [System.IO.Directory]::Delete($scratch, $true) }
}
