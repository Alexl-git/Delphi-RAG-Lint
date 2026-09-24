<#
  run_write_refs_bind.ps1 -- a bare-identifier WRITE binds (defect D13,
  resolver 1.8.0-alpha).

  THE DEFECT. `X:= ...` with a bare identifier on the left records a `write`
  ref, and no resolve stream ever looked at one: 32,909 `write` rows on ORM3
  CLIENT at resolver 1.7.0-alpha, refs.symbol_id NULL on every one. Anything
  that answers "who writes this declaration?" by id -- lint-tree's by-id arm
  for a removed FIELD or PROPERTY above all -- saw none of the bare writes
  inside the owning class.

  THE FIX: a FOURTH calls-stage stream (ResolveWriteRefs ->
  TCallResolver.ResolveWriteRef) binding refs.symbol_id and NOTHING else --
  no call_edges row, no member_accesses row. Delphi's own lookup order, and
  certain-or-nothing: lexical scopes (locals and params of the routine and the
  routines around it), then the enclosing class and its ancestors (fields,
  properties, class vars), then the unit (both sections) and the interfaces of
  the units it uses. A `with` above the site, `Result`, a function's own name
  (its result), a routine name, two visible candidates and no candidate at all
  are declines, counted by reason on the `writes:` log line.

  WHAT THIS GUARD PINS
    check 1  W-*: twelve writes each bind refs.symbol_id to the named declaration
    check 2  NEG-*: five writes stay NULL (ambiguous, not found, with, Result,
             own name)
    check 3  no write ref owns a call_edges or member_accesses row
    check 4  the calls-stage `writes:` log line, every counter pinned
    check 5  SCOPED re-index: a second exported GShared in uWriteLib2 (a file
             the use unit does not change) UNBINDS W-USED-UNIT and leaves the
             other bindings alone

  THE POSITIVE CONTROLS. W-SHADOW-LOCAL (a local GOwn over the unit's GOwn)
  and NEG-AMBIGUOUS are what make check 1 mean anything: a name join binds the
  shadowed write to the WRONG GOwn and the ambiguous one to an arbitrary GClash.
  Every line number is read from the fixture's markers; `sql --json` rows are
  positional arrays, which Sql() maps onto column names.

  Usage: pwsh -File tests\callresolve\run_write_refs_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\writes')).Path
$scratch = Join-Path C:\TEMP 'draglint_write_refs_bind'
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$use = Join-Path $scratch 'uWriteUse.pas'
$db  = Join-Path $scratch 'writes.sqlite'

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
# The write ref named $Name on line $Line of the use unit, with what it binds to.
function WriteAt([int]$Line, [string]$Name) {
  return @(Sql ("SELECT r.id, r.symbol_id, t.qualified_name AS tq FROM refs r JOIN files f ON f.id = r.file_id " +
                "LEFT JOIN symbols t ON t.id = r.symbol_id WHERE f.path LIKE '%uWriteUse.pas' AND r.kind = 'write' " +
                "AND r.start_line = $Line AND r.name_text = '$Name'") | Where-Object { $_ })
}
$pos = @(
  @{ M = 'W-FIELD-SETTER';   N = 'FName';     Q = 'uWriteUse.TThing.FName' },
  @{ M = 'W-OUTER-LOCAL';    N = 'L';         Q = 'uWriteUse.TThing.Run.L' },
  @{ M = 'W-LOCAL';          N = 'L';         Q = 'uWriteUse.TThing.Run.L' },
  @{ M = 'W-PARAM';          N = 'AParam';    Q = 'uWriteUse.TThing.Run.AParam' },
  @{ M = 'W-OWN-FIELD';      N = 'FCount';    Q = 'uWriteUse.TThing.FCount' },
  @{ M = 'W-ANCESTOR-FIELD'; N = 'FBase';     Q = 'uWriteUse.TBase.FBase' },
  @{ M = 'W-PROPERTY';       N = 'Name';      Q = 'uWriteUse.TThing.Name' },
  @{ M = 'W-CLASS-VAR';      N = 'Instances'; Q = 'uWriteUse.TThing.Instances' },
  @{ M = 'W-SHADOW-LOCAL';   N = 'GOwn';      Q = 'uWriteUse.TThing.Run.GOwn' },
  @{ M = 'W-USED-UNIT';      N = 'GShared';   Q = 'uWriteLib.GShared' },
  @{ M = 'W-OWN-UNIT-IFACE'; N = 'GOwn';      Q = 'uWriteUse.GOwn' },
  @{ M = 'W-OWN-UNIT-IMPL';  N = 'GImpl';     Q = 'uWriteUse.GImpl' })
$neg = @(
  @{ M = 'NEG-AMBIGUOUS'; N = 'GClash' },
  @{ M = 'NEG-NOT-FOUND'; N = 'GUnknown' },
  @{ M = 'NEG-WITH';      N = 'FCount' },
  @{ M = 'NEG-RESULT';    N = 'Result' },
  @{ M = 'NEG-OWN-NAME';  N = 'Compute' })
function Check-Positives([string]$Tag, [string[]]$Skip) {
  foreach ($p in $pos) {
    if ($Skip -contains $p.M) { continue }
    $rows = WriteAt (LineOf $p.M) $p.N
    $ok = ($rows.Count -eq 1) -and ($rows[0].tq -eq $p.Q)
    $det = if ($rows.Count -eq 1) { "tq=$($rows[0].tq)" } else { "rows=$($rows.Count)" }
    Check ("{0}  {1}: write {2} binds to {3}" -f $Tag, $p.M, $p.N, $p.Q) $ok $det
  }
}

Push-Location C:\TEMP
try {
  $log1 = (& $exePath index $scratch --db $db *>&1) -join "`n"

  # --- check 1 / 2 ----------------------------------------------------------------
  Check-Positives 'check 1' @()
  foreach ($n in $neg) {
    $rows = WriteAt (LineOf $n.M) $n.N
    $ok = ($rows.Count -eq 1) -and ($null -eq $rows[0].symbol_id)
    $det = if ($rows.Count -eq 1) { "sid=$($rows[0].symbol_id) tq=$($rows[0].tq)" } else { "rows=$($rows.Count)" }
    Check ("check 2  {0}: write {1} stays unbound" -f $n.M, $n.N) $ok $det
  }

  # --- check 3: identity only -----------------------------------------------------
  $extra = @(Sql ("SELECT r.id FROM refs r WHERE r.kind = 'write' AND (EXISTS (SELECT 1 FROM call_edges ce WHERE ce.ref_id = r.id) " +
                  "OR EXISTS (SELECT 1 FROM member_accesses ma WHERE ma.ref_id = r.id))") | Where-Object { $_ })
  Check 'check 3  no write ref owns a call_edges or member_accesses row' ($extra.Count -eq 0) "rows=$($extra.Count)"

  # --- check 4: the log line ------------------------------------------------------
  $line = @($log1 -split "`n" | Where-Object { $_ -match 'calls\s+writes:' }) -join ' | '
  $want = 'writes: 12 of 17 write ref(s) bound; declined result 1, own-name 1, with-scope 1, ambiguous 1, not-found 1, routine 0, unreadable 0'
  Check 'check 4  the writes: log line pins every counter' ($line.Contains($want)) $line

  # --- check 5: scoped re-index ---------------------------------------------------
  $lib2 = Join-Path $scratch 'uWriteLib2.pas'
  $txt  = [System.IO.File]::ReadAllText($lib2)
  $txt  = $txt.Replace("  GClash: Integer;`r`n", "  GClash: Integer;`r`n  GShared: Integer;`r`n")
  [System.IO.File]::WriteAllText($lib2, $txt, [System.Text.Encoding]::ASCII)
  [System.IO.File]::SetLastWriteTimeUtc($lib2, (Get-Date).ToUniversalTime().AddSeconds(5))
  $log2 = (& $exePath index $scratch --db $db *>&1) -join "`n"
  Check 'check 5  the re-index ran a SCOPED pass' ($log2 -match 'starting SCOPED pass') ''
  $rows = WriteAt (LineOf 'W-USED-UNIT') 'GShared'
  Check 'check 5  W-USED-UNIT is now ambiguous and unbound' (($rows.Count -eq 1) -and ($null -eq $rows[0].symbol_id)) ("sid=" + $(if ($rows.Count -ge 1) { $rows[0].symbol_id } else { '<none>' }))
  Check-Positives 'check 5' @('W-USED-UNIT')
} finally {
  Pop-Location
}

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
