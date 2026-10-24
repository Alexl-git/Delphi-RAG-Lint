<#
  run_result_receiver_bind.ps1 -- a member access on the implicit `Result` of a
  function binds (backlog N-07, INBOX-result-receiver-member-write-unbound).

  THE DEFECT. `Result:= TDragLintJob.Create(...); Result.Streaming:= False;` --
  the `Streaming` ref stayed symbol_id NULL with no member_accesses row, so
  `usages` under-reported writes: TCallResolver.TypeReceiver had no rung for the
  receiver text `Result`, which has no symbol row of its own.

  THE FIX: TypeReceiver kind 9 types `Result` from the enclosing FUNCTION's
  declared return type (SignatureReturnType -> ResolveTypeNameToSymbol). A
  local or parameter named Result (legal only outside a function) still answers
  first, from its own declared type.

  WHAT THIS GUARD PINS
    POS-WRITE  Result.Streaming := ..  binds TJob.Streaming, member_accesses mode write
    POS-READ   if Result.Streaming     binds TJob.Streaming, mode read
    POS-CALL   Result.Start()          owns a call edge to TJob.Start
    NEG-LOCAL  a procedure's LOCAL `Result: TOtherJob` -- binds TOtherJob.Streaming,
               never TJob's (POSITIVE CONTROL: a by-name join of `Streaming`
               would pick either class)
    NEG-ANON / POS-AFTER-ANON   Result inside / after an anonymous method
    RCV-DUP-* / RCV-LATE        a local receiver is typed from the nearest
               in-scope same-name declaration, never the first or a later one
    PV-ANON-CALL / PV-OUTER-ADDR  the proc-value check types an anonymous
               method's Result from the anonymous method, not the routine

  Usage: pwsh -File tests\callresolve\run_result_receiver_bind.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\resultrecv')).Path
$scratch = Join-Path C:\TEMP "draglint_result_receiver_bind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$src = Join-Path $scratch 'uResRecv.pas'
$db  = Join-Path $scratch 'resultrecv.sqlite'

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
  $m = @(Select-String -LiteralPath $src -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
function At([string]$Marker, [string]$Kind, [string]$Name) {
  $line = LineOf $Marker
  return @(Sql ("SELECT r.id, s.qualified_name AS sq, ma.mode AS mode, t.qualified_name AS tq FROM refs r " +
                "LEFT JOIN symbols s ON s.id = r.symbol_id LEFT JOIN member_accesses ma ON ma.ref_id = r.id " +
                "LEFT JOIN call_edges ce ON ce.ref_id = r.id LEFT JOIN symbols t ON t.id = ce.target_symbol_id " +
                "WHERE r.kind = '$Kind' AND r.name_text = '$Name' AND r.start_line = $line") | Where-Object { $_ })
}
function Show($r) { ($r | ForEach-Object { "sq=$($_.sq) mode=$($_.mode) tq=$($_.tq)" }) -join '; ' }

$null = & $exePath index $scratch --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$r = At 'POS-WRITE' 'member-access' 'Streaming'
Check 'POS-WRITE Result.Streaming := binds TJob.Streaming, mode write' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' -and $_.mode -eq 'write' }).Count -eq 1) (Show $r)
$r = At 'POS-READ' 'member-access' 'Streaming'
Check 'POS-READ if Result.Streaming binds TJob.Streaming, mode read' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' -and $_.mode -eq 'read' }).Count -eq 1) (Show $r)
$r = At 'POS-CALL' 'call' 'Start'
Check 'POS-CALL Result.Start() has a call edge to TJob.Start' `
  (@($r | Where-Object { $_.tq -eq 'uResRecv.TJob.Start' }).Count -eq 1) (Show $r)
$r = At 'NEG-LOCAL' 'member-access' 'Streaming'
Check 'NEG-LOCAL a local Result: TOtherJob binds TOtherJob.Streaming, never TJob''s' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TOtherJob.Streaming' }).Count -eq 1 -and
   @($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' }).Count -eq 0) (Show $r)

# review 2026-10-23: inside an anonymous method `Result` is the anonymous
# method's, not the enclosing function's -- never typed from MakeWithAnon's
# return type. Positive control: before the fix NEG-ANON bound TJob.Streaming.
$r = At 'NEG-ANON' 'member-access' 'Streaming'
Check 'NEG-ANON Result inside an anonymous function never binds TJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' }).Count -eq 0) (Show $r)
$r = At 'POS-AFTER-ANON' 'member-access' 'Streaming'
Check 'POS-AFTER-ANON Result after the anonymous method closes still binds TJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' -and $_.mode -eq 'write' }).Count -eq 1) (Show $r)

# review 2026-10-23 (W5-res2): a LOCAL receiver is typed from the nearest
# same-name declaration at or before the site whose block covers it -- the rule
# value reads/writes use -- never from the first child of that name. Positive
# control: the first-match lookup declined both RCV-DUP-* (types differ) and
# typed RCV-LATE from the TOtherJob local declared AFTER it.
$r = At 'RCV-DUP-FIRST' 'member-access' 'Streaming'
Check 'RCV-DUP-FIRST J (first inline var, TJob) binds TJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' }).Count -eq 1) (Show $r)
$r = At 'RCV-DUP-SECOND' 'member-access' 'Streaming'
Check 'RCV-DUP-SECOND J (second inline var, TOtherJob) binds TOtherJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TOtherJob.Streaming' }).Count -eq 1) (Show $r)
$r = At 'RCV-LATE' 'member-access' 'Streaming'
Check 'RCV-LATE GPeer before the inline GPeer is declared never binds TOtherJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TOtherJob.Streaming' }).Count -eq 0) (Show $r)
$r = At 'RCV-INNER-LATE' 'member-access' 'Streaming'
Check 'RCV-INNER-LATE the inline GPeer: TOtherJob binds TOtherJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TOtherJob.Streaming' }).Count -eq 1) (Show $r)

# review 2026-10-23 (W5-res2): the proc-value check types `Result := GetNum`
# from the assignment target. Inside an anonymous method `Result` is ITS result
# (Integer here), so the parenless GetNum is a CALL there; outside it the
# enclosing MakeNumFn returns the procedural TNumFn, so GetNum is its address.
# Positive control: AssignedTypeText typed the anonymous Result as TNumFn and
# declined PV-ANON-CALL as a proc value (no edge).
function EdgesAt([string]$Marker, [string]$Name) {
  $line = LineOf $Marker
  return @(Sql ("SELECT t.qualified_name AS tq FROM refs r JOIN call_edges ce ON ce.ref_id = r.id " +
                "JOIN symbols t ON t.id = ce.target_symbol_id WHERE r.name_text = '$Name' AND r.start_line = $line") |
           Where-Object { $_ })
}
$r = EdgesAt 'PV-ANON-CALL' 'GetNum'
Check 'PV-ANON-CALL Result := GetNum inside an anonymous function: Integer is a call edge to GetNum' `
  (@($r | Where-Object { $_.tq -eq 'uResRecv.GetNum' }).Count -eq 1) "edges=$($r.Count)"
$r = EdgesAt 'PV-OUTER-ADDR' 'GetNum'
Check 'PV-OUTER-ADDR Result := GetNum in a function returning TNumFn is no call edge (address)' `
  ($r.Count -eq 0) "edges=$($r.Count)"

# review 2026-10-23 (W5-res2 fix 3): an anonymous method whose return type is
# textually the routine's types Result like the routine; NEG-ANON (TOtherJob in
# a TJob function) and PV-ANON-CALL (Integer in a TNumFn function) stay declined.
# Positive control: the any-anonymous-method decline left POS-ANON-SAME unbound
# and made PV-ANON-SAME-ADDR a call edge.
$r = At 'POS-ANON-SAME' 'member-access' 'Streaming'
Check 'POS-ANON-SAME Result inside an anonymous function: TJob in a TJob function binds TJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' -and $_.mode -eq 'write' }).Count -eq 1) (Show $r)
$r = EdgesAt 'PV-ANON-SAME-ADDR' 'GetNum'
Check 'PV-ANON-SAME-ADDR Result := GetNum inside an anonymous function: TNumFn is no call edge (address)' `
  ($r.Count -eq 0) "edges=$($r.Count)"

# B-35 lane R (W5-res2 residue): the comparison normalises unit qualification --
# `uResRecv.TJob` in a `TJob` function, or `TNumFn` in a `uResRecv.TNumFn`
# function, is the same type; a qualified OTHER type still declines.
# Positive control: text equality declined QUAL-POS-ANON and made
# QUAL-PV-ANON-ADDR a call edge.
$r = At 'QUAL-POS-ANON' 'member-access' 'Streaming'
Check 'QUAL-POS-ANON Result inside function: uResRecv.TJob in a TJob function binds TJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' -and $_.mode -eq 'write' }).Count -eq 1) (Show $r)
$r = EdgesAt 'QUAL-PV-ANON-ADDR' 'GetNum'
Check 'QUAL-PV-ANON-ADDR Result := GetNum inside function: TNumFn in a uResRecv.TNumFn function is no call edge (address)' `
  ($r.Count -eq 0) "edges=$($r.Count)"
$r = At 'QUAL-NEG-ANON' 'member-access' 'Streaming'
Check 'QUAL-NEG-ANON Result inside function: uResRecv.TOtherJob in a TJob function never binds TJob.Streaming' `
  (@($r | Where-Object { $_.sq -eq 'uResRecv.TJob.Streaming' }).Count -eq 0) (Show $r)
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  if ($scratch -and (Test-Path $scratch)) { [System.IO.Directory]::Delete($scratch, $true) }
}
