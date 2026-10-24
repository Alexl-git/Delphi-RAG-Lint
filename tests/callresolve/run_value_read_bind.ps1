<#
  run_value_read_bind.ps1 -- a bare READ of a local / parameter / const / var
  binds (backlog B-28, INBOX-2026-10-05-converter-to-engine-local-read-unresolved).

  THE DEFECT. `Label2:= 0; Tag:= Label2;` -- the write bound to the local since
  D13 (resolver 1.8.0-alpha), the READ on the next line stayed symbol_id NULL.
  No calls-stage stream looked at a bare `read` of a value: the enum stream
  binds enum values, the parenless stream routines, the member stream
  properties and fields. A reader asking "who reads this local / const?" by id
  saw nothing, and the converter's editor had to filter unresolved reads by name.

  THE FIX: a SIXTH calls-stage stream (ResolveValueReadRefs ->
  TCallResolver.ResolveBareValueRead) over the `read` refs the other streams
  left unbound. The SAME scope walk as a bare write (ResolveWriteRef): the
  `with` scope, the lexical levels, the enclosing class chain, the own unit,
  the used units' interfaces -- first scope that declares the name answers,
  certain or nothing. It binds refs.symbol_id ONLY to a local_var, param,
  const or var; a property / field is the member stream's (it writes the
  member_accesses row), a routine the parenless stream's.

  WHAT THIS GUARD PINS
    check 1  R-*: six reads bind to the named declaration
    check 2  NEG-*: seven reads stay unbound to a value (ambiguous, not found,
             a with target that cannot be typed, Result, a LOCAL const -- the
             extractor emits no symbol for one, so uValLib's LIMIT must not
             answer for it: 'unlisted') or bind to what
             another stream owns (field, routine)
    check 3  no value-read binding owns a call_edges or member_accesses row
    check 4  the calls-stage `value-reads:` log line is present and counts
  POSITIVE CONTROLS. R-SHADOW-LOCAL (a local GOwn over the unit's GOwn) and
  NEG-AMBIGUOUS (GClash in two used units): a name join binds the first to the
  WRONG GOwn and the second to an arbitrary GClash; NEG-LOCAL-CONST binds to
  uValLib.LIMIT without the routine-text check.

  Usage: pwsh -File tests\callresolve\run_value_read_bind.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\valuereads')).Path
$scratch = Join-Path C:\TEMP "draglint_value_read_bind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$use = Join-Path $scratch 'uValUse.pas'
$db  = Join-Path $scratch 'valuereads.sqlite'

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
# The read ref named $Name on the marker's line, with what it binds to.
function ReadAt([string]$Marker, [string]$Name) {
  $line = LineOf $Marker
  return @(Sql ("SELECT r.id, r.symbol_id, t.qualified_name AS tq, t.kind AS tk FROM refs r " +
                "JOIN files f ON f.id = r.file_id LEFT JOIN symbols t ON t.id = r.symbol_id " +
                "WHERE f.path LIKE '%uValUse.pas' AND r.kind = 'read' " +
                "AND r.start_line = $line AND r.name_text = '$Name'") | Where-Object { $_ })
}

$log = & $exePath index $scratch --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# check 1 -- positive bindings
$pos = @(
  @('R-LOCAL',        'L',        'uValUse.TVal.Run.L'),
  @('R-PARAM',        'AErr',     'uValUse.TVal.Run.AErr'),
  @('R-UNIT-CONST',   'CHECK_OK', 'uValUse.CHECK_OK'),
  @('R-USED-UNIT',    'GShared',  'uValLib.GShared'),
  @('R-SHADOW-LOCAL', 'GOwn',     'uValUse.TVal.Run.GOwn'),
  @('R-OUTER-LOCAL',  'L',        'uValUse.TVal.Run.L')
)
foreach ($p in $pos) {
  $r = @(ReadAt $p[0] $p[1])
  $got = if ($r.Count -eq 1) { [string]$r[0].tq } else { "rows=$($r.Count)" }
  Check "$($p[0]) binds $($p[1]) to $($p[2])" ($got -eq $p[2]) "got=$got"
}

# check 2 -- declines (or another stream's binding, never a value)
foreach ($n in @(@('NEG-AMBIGUOUS', 'GClash'), @('NEG-NOT-FOUND', 'GMissing'), @('NEG-WITH', 'L'), @('NEG-RESULT', 'Result'),
             @('NEG-LOCAL-CONST', 'LIMIT'))) {
  $r = @(ReadAt $n[0] $n[1])
  $ok = ($r.Count -eq 1) -and ($null -eq $r[0].symbol_id)
  Check "$($n[0]) $($n[1]) stays unbound" $ok ("rows=$($r.Count) tq=" + $(if ($r.Count) { $r[0].tq } else { '' }))
}
# check 2b (review 2026-10-23) -- the unlisted-declaration check runs for the
# levels INSIDE the one that declares the name: a nested routine's local const
# hides the outer routine's parameter; a mid-line `begin const X = ..` counts.
foreach ($n in @(@('NEG-INNER-CONST', 'AErr'), @('NEG-MIDLINE-CONST', 'CHECK_OK'))) {
  $r = @(ReadAt $n[0] $n[1])
  Check "$($n[0]) $($n[1]) stays unbound (unlisted)" (($r.Count -eq 1) -and ($null -eq $r[0].symbol_id)) `
    ("rows=$($r.Count) tq=" + $(if ($r.Count) { $r[0].tq } else { '' }))
}

# check 5 (review 2026-10-23) -- two same-name inline vars in one routine: a
# read or a write binds the NEAREST declaration at or before it whose block
# covers it, never the first. Positive control: a first-match lookup binds every
# DUP-SECOND / DUPW-SECOND ref to the FIRST declaration, and NEG-OUTSCOPE-Q to
# the Q of a block that already closed.
function DeclId([string]$Marker, [string]$Name) {
  $line = LineOf $Marker
  $d = @(Sql ("SELECT s.id FROM symbols s JOIN files f ON f.id = s.file_id WHERE f.path LIKE '%uValUse.pas' " +
              "AND s.kind = 'local_var' AND s.name = '$Name' AND s.start_line = $line") | Where-Object { $_ })
  if ($d.Count -ne 1) { throw "declaration $Name at '$Marker' found $($d.Count) times" }
  return [int64]$d[0].id
}
function RefAt([string]$Marker, [string]$Kind, [string]$Name) {
  $line = LineOf $Marker
  return @(Sql ("SELECT r.id, r.symbol_id FROM refs r JOIN files f ON f.id = r.file_id WHERE f.path LIKE '%uValUse.pas' " +
                "AND r.kind = '$Kind' AND r.start_line = $line AND r.name_text = '$Name'") | Where-Object { $_ })
}
$dup = @(
  @('DUP-FIRST-DECL',   'read',  'i', 'DUP-FIRST-DECL'),
  @('DUP-SECOND-READ',  'read',  'i', 'DUP-SECOND-DECL'),
  @('DUPW-FIRST-WRITE', 'write', 'K', 'DUPW-FIRST-DECL'),
  @('DUPW-FIRST-READ',  'read',  'K', 'DUPW-FIRST-DECL'),
  @('DUPW-SECOND-WRITE','write', 'K', 'DUPW-SECOND-DECL'),
  @('DUPW-SECOND-READ', 'read',  'K', 'DUPW-SECOND-DECL'),
  @('R-BEFORE-ANON-VAR','read',  'H', 'ANON-INLINE-DECL'),
  # an anonymous method's var section declared AFTER a read never answers it
  @('R-ANON-SECTION-VAR','read', 'H', 'ANON-SECTION-DECL'),
  @('R-INSCOPE-Q',      'read',  'Q', $null)
)
foreach ($p in $dup) {
  $want = if ($p[3]) { DeclId $p[3] $p[2] } else { [int64](@(Sql ("SELECT s.id FROM symbols s WHERE s.kind = 'local_var' AND s.name = 'Q'"))[0].id) }
  $r = @(RefAt $p[0] $p[1] $p[2])
  Check "$($p[0]) $($p[1]) $($p[2]) binds the nearest in-scope declaration" (($r.Count -eq 1) -and ([int64]$r[0].symbol_id -eq $want)) `
    ("rows=$($r.Count) got=$(if ($r.Count) { $r[0].symbol_id }) want=$want")
}
$r = @(RefAt 'NEG-OUTSCOPE-Q' 'read' 'Q')
Check 'NEG-OUTSCOPE-Q read of a closed block''s Q stays unbound (ambiguous)' (($r.Count -eq 1) -and ($null -eq $r[0].symbol_id)) `
  ("rows=$($r.Count) got=$(if ($r.Count) { $r[0].symbol_id })")

$r = @(ReadAt 'NEG-FIELD' 'FTotal')
Check 'NEG-FIELD FTotal is the member stream''s (bound to the field)' (($r.Count -eq 1) -and ($r[0].tk -eq 'field')) "tk=$(if ($r.Count) { $r[0].tk })"
$r = @(ReadAt 'NEG-ROUTINE' 'GetIt')
Check 'NEG-ROUTINE GetIt is never bound to a value' (($r.Count -eq 1) -and ($r[0].tk -notin @('local_var', 'param', 'const', 'var'))) "tk=$(if ($r.Count) { $r[0].tk })"

# check 3 -- identity only: no edge, no member access for a value-read binding
$extra = Sql ("SELECT COUNT(*) AS n FROM refs r JOIN symbols t ON t.id = r.symbol_id WHERE r.kind = 'read' " +
              "AND t.kind IN ('local_var','param','const','var') AND (r.id IN (SELECT ref_id FROM call_edges) " +
              "OR r.id IN (SELECT ref_id FROM member_accesses))")
Check 'no value-read binding owns a call_edges / member_accesses row' ([int]$extra[0].n -eq 0) "n=$($extra[0].n)"

# check 4 -- the log line
$line = @($log | Where-Object { "$_" -match 'value-reads: (\d+) of (\d+)' })
Check 'calls-stage value-reads: line present' ($line.Count -eq 1) "lines=$($line.Count)"
if ($line.Count -eq 1) {
  $null = "$($line[0])" -match 'value-reads: (\d+) of (\d+)'
  Check 'value-reads: bound >= 6 of the offered reads' ([int]$Matches[1] -ge 6) "$($line[0])"
}

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  if ($scratch -and (Test-Path $scratch)) { [System.IO.Directory]::Delete($scratch, $true) }
}
