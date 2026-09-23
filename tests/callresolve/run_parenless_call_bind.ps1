<#
  run_parenless_call_bind.ps1 -- a PARENLESS call binds (resolver 1.7.0-alpha).

  THE DEFECT (D1). Delphi lets a parameterless routine be called without
  parentheses. In STATEMENT position (`NextId;`) the parser records a `call`
  ref and it always resolved. In EXPRESSION position -- `Assert(NextId > 0)`,
  `N := NextId;`, `Consume(NextId)`, `N := Tick;` inside the class -- it records
  a `read` ref, and the calls stage never streamed `read` refs (only the enum
  stream did, for enum-value names). So those sites owned no call_edges row and
  every call-based consumer missed them: assert-with-side-effect, the purity
  callee walk, find-callers --resolved, the who-calls charts.
  Measured before the fix on ORM3 CLIENT (resolver 1.6.0-alpha): 1,715 unbound
  `read` refs named like a parameterless value-returning routine, 59 names.

  THE LAYER is the RESOLVER, not the extractor: the ref already exists with its
  name, position and enclosing routine; only the calls stage declined to look.

  WHAT THIS GUARD PINS
    check 1  fixture control: the statement-position call binds (green before)
    check 2  POS-*: six expression-position parenless calls each own exactly
             ONE certain call_edges row to the right routine, and refs.symbol_id
    check 3  POS-STMT: still exactly one edge (no twin from the new stream)
    check 4  NEG-*: eleven look-alikes stay unbound -- no edge, symbol_id NULL
    check 5  the calls-stage `parenless:` log line, every counter pinned
    check 6  SCOPED re-index: a new shadowing local UNBINDS the Driver sites
             (edges gone, symbol_id NULL) and leaves the class sites alone
    check 7  find-callers --resolved reports the parenless sites

  THE POSITIVE CONTROLS. Check 4 is what makes check 2 mean anything: a name
  join (bind every `read` ref whose name matches a function) turns check 2
  green AND check 4 red. Check 1 is the control on the FIXTURE -- if it ever
  reddens, the fixture broke, not the resolver.

  Every line number is READ FROM THE FIXTURE'S markers. `sql --json` rows are
  POSITIONAL arrays; Sql() maps them onto the column names.

  Usage: pwsh -File tests\callresolve\run_parenless_call_bind.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\parenless')).Path
$scratch = Join-Path C:\TEMP 'draglint_parenless_bind'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$use = Join-Path $scratch 'uParenlessUse.pas'
$db  = Join-Path $scratch 'parenless.sqlite'

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
# Every ref named ANAME on line ALINE of the use unit, with its edge (if any).
function RefsAt([int]$Line, [string]$Name) {
  return Sql ("SELECT r.id, r.kind, r.symbol_id, ce.target_symbol_id AS tid, ce.confidence AS conf, " +
              "t.name AS tname, t.qualified_name AS tq FROM refs r JOIN files f ON f.id = r.file_id " +
              "LEFT JOIN call_edges ce ON ce.ref_id = r.id LEFT JOIN symbols t ON t.id = ce.target_symbol_id " +
              "WHERE f.path LIKE '%uParenlessUse.pas' AND r.start_line = $Line AND r.name_text = '$Name'")
}

Push-Location C:\TEMP
try {
  $log1 = (& $exePath index $scratch --db $db *>&1) -join "`n"

  # --- check 1: fixture control -------------------------------------------------
  $stmt = RefsAt (LineOf 'POS-STMT') 'NextId'
  $stmtCall = @($stmt | Where-Object { $_.kind -eq 'call' })
  Check 'check 1  fixture control: statement-position NextId; is a bound call ref' `
    (($stmtCall.Count -eq 1) -and ($stmtCall[0].tq -eq 'uParenlessLib.NextId'))

  # --- check 2: positives ---------------------------------------------------------
  $pos = @(
    @{ M = 'POS-ASSERT'; N = 'NextId'; Q = 'uParenlessLib.NextId' },
    @{ M = 'POS-ASSIGN'; N = 'NextId'; Q = 'uParenlessLib.NextId' },
    @{ M = 'POS-ARG';    N = 'NextId'; Q = 'uParenlessLib.NextId' },
    @{ M = 'POS-NESTED'; N = 'Local';  Q = 'Local' },
    @{ M = 'POS-METHOD'; N = 'Tick';   Q = 'TCounter.Tick' },
    @{ M = 'POS-SELF';   N = 'Tick';   Q = 'TCounter.Tick' })
  foreach ($p in $pos) {
    $rows = @(RefsAt (LineOf $p.M) $p.N | Where-Object { $_.kind -eq 'read' })
    $ok = ($rows.Count -eq 1) -and ($null -ne $rows[0].tid) -and
          ([string]$rows[0].tq).EndsWith($p.Q) -and ($rows[0].conf -eq 'certain') -and
          ($rows[0].symbol_id -eq $rows[0].tid)
    $det = if ($rows.Count -eq 1) { "tq=$($rows[0].tq) conf=$($rows[0].conf) sid=$($rows[0].symbol_id)" } else { "rows=$($rows.Count)" }
    Check ("check 2  {0}: read ref {1} owns one certain edge to ...{2}" -f $p.M, $p.N, $p.Q) $ok $det
  }

  # --- check 3: no twin on the statement call -------------------------------------
  $stmtEdges = @($stmt | Where-Object { $null -ne $_.tid })
  Check 'check 3  POS-STMT still owns exactly ONE edge (no twin from the new stream)' ($stmtEdges.Count -eq 1) "edges=$($stmtEdges.Count)"

  # --- check 4: negatives ---------------------------------------------------------
  $neg = @(
    @{ M = 'NEG-LOCAL';         N = 'NextId' },
    @{ M = 'NEG-PROCTYPED-VAR'; N = 'NextId' },
    @{ M = 'NEG-PROCVAR';       N = 'NextId' },
    @{ M = 'NEG-ADDR';          N = 'NextId' },
    @{ M = 'NEG-PROCARG';       N = 'NextId' },
    @{ M = 'NEG-PARAMS';        N = 'NextKey' },
    @{ M = 'NEG-OVERLOAD';      N = 'Pick' },
    @{ M = 'NEG-WITH';          N = 'NextId' },
    @{ M = 'NEG-FIELD';         N = 'NextId' },
    @{ M = 'NEG-PROPGETTER';    N = 'NextId' },
    @{ M = 'NEG-PROPERTY';      N = 'Total' })
  foreach ($n in $neg) {
    $rows = @(RefsAt (LineOf $n.M) $n.N)
    $bound = @($rows | Where-Object { ($null -ne $_.tid) -or ($null -ne $_.symbol_id) })
    Check ("check 4  {0}: {1} stays unbound" -f $n.M, $n.N) (($rows.Count -ge 1) -and ($bound.Count -eq 0)) "refs=$($rows.Count) bound=$($bound.Count)"
  }

  # --- check 5: the counters ------------------------------------------------------
  # 6 bound; declines: shadowed 4 (local, proc-typed local, field, property),
  # proc-value 3 (procedural var, @, procedural parameter), not-callable 2
  # (a function needing an argument, an overload set with such a member),
  # with-scope 1. 16 candidates in all.
  $m = [regex]::Match($log1, 'parenless: (\d+) of (\d+) bare read\(s\) bound as call\(s\); declined not-found (\d+), shadowed (\d+), not-callable (\d+), proc-value (\d+), with-scope (\d+), qualified (\d+), unreadable (\d+)')
  if ($m.Success) {
    $v = @(1..9 | ForEach-Object { [int]$m.Groups[$_].Value })
    Check 'check 5  parenless log line: bound 6 of 16; not-found 0, shadowed 4, not-callable 2, proc-value 3, with-scope 1, qualified 0, unreadable 0' `
      (($v[0] -eq 6) -and ($v[1] -eq 16) -and ($v[2] -eq 0) -and ($v[3] -eq 4) -and ($v[4] -eq 2) -and ($v[5] -eq 3) -and ($v[6] -eq 1) -and ($v[7] -eq 0) -and ($v[8] -eq 0)) `
      ($m.Value)
  } else {
    Check 'check 5  parenless log line present' $false 'no `parenless:` line in the index output'
  }

  # --- check 7: consumer reach (run before the mutation below) ---------------------
  # find-callers --resolved emits a `certain` row per resolved edge (its "line" is
  # the CALLER's declaration line, not the site) and a `callback` row per `read`
  # of the routine's name that no call covers. So: four certain Driver rows, the
  # three parenless Driver sites NOT ALSO listed as callbacks (the double listing
  # the new edges would otherwise cause), and the genuine callback passes --
  # procedural var, procedural parameter -- still listed (positive control).
  $fc = (& $exePath query find-callers --name NextId --resolved --db $db --json 2>$null) -join "`n"
  $fb = $fc.IndexOf('[')
  $fr = @(); if ($fb -ge 0) { $fr = @($fc.Substring($fb) | ConvertFrom-Json) }
  $certDriver = @($fr | Where-Object { $_.confidence -eq 'certain' -and $_.caller_qname -eq 'uParenlessUse.Driver' })
  $cbLines = @($fr | Where-Object { $_.confidence -eq 'callback' } | ForEach-Object { [int]$_.line })
  $dbl  = @(@((LineOf 'POS-ASSERT'), (LineOf 'POS-ASSIGN'), (LineOf 'POS-ARG')) | Where-Object { $cbLines -contains $_ })
  $keep = @(@((LineOf 'NEG-PROCVAR'), (LineOf 'NEG-PROCARG')) | Where-Object { $cbLines -notcontains $_ })
  Check 'check 7  find-callers --resolved NextId: 4 certain Driver rows, no parenless site double-listed as callback, real callbacks kept' `
    (($certDriver.Count -eq 4) -and ($dbl.Count -eq 0) -and ($keep.Count -eq 0)) `
    ("certain=$($certDriver.Count) doubleListed=$($dbl -join ',') lostCallbacks=$($keep -join ',')")

  # --- check 6: scoped re-index unbinds ------------------------------------------
  $txt = [IO.File]::ReadAllText($use)
  $mut = $txt.Replace("procedure Driver;`r`nvar`r`n  N: Integer;", "procedure Driver;`r`nvar`r`n  N, NextId: Integer;")
  if ($mut -eq $txt) { throw 'mutation anchor not found in uParenlessUse.pas' }
  [IO.File]::WriteAllText($use, $mut, [Text.Encoding]::ASCII)
  $log2 = (& $exePath index $scratch --db $db *>&1) -join "`n"
  $scoped = $log2 -match 'starting SCOPED pass'
  $after = @()
  foreach ($mk in 'POS-ASSERT', 'POS-ASSIGN', 'POS-ARG') {
    $after += @(RefsAt (LineOf $mk) 'NextId' | Where-Object { $_.kind -eq 'read' })
  }
  $still = @($after | Where-Object { ($null -ne $_.tid) -or ($null -ne $_.symbol_id) })
  $meth  = @(RefsAt (LineOf 'POS-METHOD') 'Tick' | Where-Object { $_.kind -eq 'read' -and $null -ne $_.tid })
  Check 'check 6  SCOPED re-index: a new shadowing local unbinds the three Driver reads; POS-METHOD keeps its edge' `
    ($scoped -and ($after.Count -eq 3) -and ($still.Count -eq 0) -and ($meth.Count -eq 1)) `
    ("scoped=$scoped reads=$($after.Count) stillBound=$($still.Count) methodEdge=$($meth.Count)")
}
finally {
  Pop-Location
}

if ($script:fail) { Write-Host 'FAIL  run_parenless_call_bind'; exit 1 }
Write-Host 'PASS  run_parenless_call_bind'
exit 0
