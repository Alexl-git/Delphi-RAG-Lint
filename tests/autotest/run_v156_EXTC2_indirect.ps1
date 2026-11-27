<#
  run_v156_EXTC2_indirect.ps1 -- 1.56 lane EXT-C2: indirect-call edges (table indirect_edges).

  Indexes tests\fixtures\v156-extc2 (three Pascal units + one .dfm) into a scratch DB and checks
  the rows DRagLint.Index.IndirectCalls derives, through `sql --json` (rows are POSITIONAL arrays;
  mapped onto columns[].name below). Every edge is named by QUALIFIED NAMES, never by id:
     caller (routine holding the call through the slot) -> target (routine that can run).

    M   method-pointer: `FOnChange:= HandleChange` + `FOnChange(Self)`; two bindings of one field
        give two edges; `GHook:= @PlainTarget` (unit variable) + `GHook(1)`; bind position and
        via_text are the binding site's.
    E   event: `FEmitter.OnChange:= HandleEvt` in ANOTHER unit reaches the call of the field behind
        the property (TEmitter.Fire); a library event (`Button2.OnClick:= Button1Click`) has no
        call site in the index and yields ONE row with ref_id / caller NULL.
    T   a FUNCTION name on the right-hand side is a binding only when the slot's type is
        procedural (`GCompare:= CmpAsc`); `GCount:= CountItems` is a paren-less call: no row,
        counted unproven.
    C   callback-arg: `RunCb(PlainOther)` / `RunCb(@PlainTarget)` reach the call of the parameter
        (`ACb(2)`) inside RunCb; a callee that only stores the parameter is no caller.
    P   propagation: a slot copied into another slot (`GHook:= ACb`, `RunCb(ACb)`) carries its
        bindings to the calls through that slot, over two hops; no stray no-call-site row.
    D   dfm-event: `OnClick = Button1Click` gives one row without call site, bound in the .dfm;
        an event of a component class of the index (TIndPanel.OnPing) reaches that class's call
        of the field behind the property.
    N   negatives: a slot that is only set to nil (FUnbound) has no edge; a routine that is never
        bound (NeverBound, NotAHandler, NotWired) is never a target; `FCount:= 0` is no binding;
        every ref_id is a `call` ref.
    R   a second index run over a touched unit REPLACES the table (same rows, no duplicates).
  Positive control: an engine without the pass leaves indirect_edges empty -> VACUITY and every
  M / E check FAIL (shown RED on the lane's stub build).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_EXTC2_indirect: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_EXTC2_indirect: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-extc2'
$work  = Join-Path $env:TEMP ('dl-v156-extc2-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name). A failed query returns an EMPTY array.
function Lane-Sql([string]$Db, [string]$Query) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query $Query --db $Db --json --limit 1000 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return }
  try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { return }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return $out.ToArray()
}
function Lane-Index([string]$Dir, [string]$Db, [string]$LogName) {
  $log = Join-Path $work $LogName
  $env:DRAGLINT_INDIRECT_LOG = '1'
  try { & { $ErrorActionPreference = 'Continue'; & $Exe index $Dir --db $Db *> $log } }
  finally { $env:DRAGLINT_INDIRECT_LOG = $null }
  return @{ rc = $LASTEXITCODE; log = (Get-Content -Raw $log) }
}
# Every edge as one object: kind, caller / target qualified names ('' = NULL), via, bind file /
# line / col, confidence, the kind + name + line of the call ref.
$edgeSql = @'
SELECT e.kind AS kind, COALESCE(c.qualified_name, '') AS caller, t.qualified_name AS target,
       e.via_text AS via, COALESCE(bf.path, '') AS bind_path, e.bind_line AS bind_line, e.bind_col AS bind_col,
       e.confidence AS confidence, COALESCE(r.kind, '') AS ref_kind, COALESCE(r.name_text, '') AS ref_name,
       COALESCE(r.start_line, 0) AS ref_line
FROM indirect_edges e
JOIN symbols t ON t.id = e.target_symbol_id
LEFT JOIN symbols c ON c.id = e.caller_symbol_id
LEFT JOIN refs r ON r.id = e.ref_id
LEFT JOIN files bf ON bf.id = e.bind_file_id
ORDER BY e.id
'@ -replace "\r?\n", ' '
function Lane-Edges([string]$Db) { return @(Lane-Sql $Db $edgeSql) }
function Edge-Key($e) { return "$($e.kind)|$($e.caller)|$($e.target)" }
# The edges of one kind / caller / target ('' caller = the no-call-site row).
function Find-Edge($Edges, [string]$Kind, [string]$Caller, [string]$Target) {
  return @($Edges | Where-Object { ($_.kind -eq $Kind) -and ($_.caller -eq $Caller) -and ($_.target -eq $Target) })
}

Write-Host "run_v156_EXTC2_indirect: engine $Exe" -ForegroundColor Cyan

$fx = Join-Path $work 'fx'; Copy-Item -Recurse $fxSrc $fx
$db = Join-Path $work 'fx.sqlite'
$r1 = Lane-Index $fx $db 'index-1.log'
$nFiles = @(Lane-Sql $db 'SELECT COUNT(*) AS n FROM files')
$edges  = Lane-Edges $db
Check 'VACUITY the fixture was indexed' (($r1.rc -eq 0) -and ($nFiles.Count -eq 1) -and ([int]$nFiles[0].n -ge 4)) "(rc $($r1.rc))"
Check 'VACUITY indirect_edges holds rows' ($edges.Count -gt 0) "($($edges.Count) rows)"
Check 'VACUITY the pass printed its counters line (DRAGLINT_INDIRECT_LOG=1)' ($r1.log -match '(?m)^indirect: method-pointer=\d+ event=\d+')

# ---- M: method pointers --------------------------------------------------------------
$m1 = Find-Edge $edges 'method-pointer' 'uIndA.TEmitter.Fire' 'uIndA.TEmitter.HandleChange'
Check 'M1 FOnChange:= HandleChange reaches the call FOnChange(Self) in Fire' ($m1.Count -eq 1) "($($m1.Count))"
if ($m1.Count -eq 1) {
  Check 'M1 the edge hangs on the call ref FOnChange, line 69' (($m1[0].ref_kind -eq 'call') -and ($m1[0].ref_name -eq 'FOnChange') -and ([int]$m1[0].ref_line -eq 69)) "($($m1[0].ref_kind) $($m1[0].ref_name) $($m1[0].ref_line))"
  Check 'M1 bind site = uIndA.pas 60:15, via FOnChange, resolved' (($m1[0].bind_path -like '*uIndA.pas') -and ([int]$m1[0].bind_line -eq 60) -and ([int]$m1[0].bind_col -eq 15) -and ($m1[0].via -eq 'FOnChange') -and ($m1[0].confidence -eq 'resolved')) "($($m1[0].bind_line):$($m1[0].bind_col) via=$($m1[0].via) $($m1[0].confidence))"
}
$m2a = Find-Edge $edges 'method-pointer' 'uIndA.TEmitter.FireIdle' 'uIndA.TEmitter.HandleIdleA'
$m2b = Find-Edge $edges 'method-pointer' 'uIndA.TEmitter.FireIdle' 'uIndA.TEmitter.HandleIdleB'
Check 'M2 two bindings of FOnIdle give two edges from FireIdle (HandleIdleA, Self.HandleIdleB)' (($m2a.Count -eq 1) -and ($m2b.Count -eq 1)) "($($m2a.Count), $($m2b.Count))"
$m3 = Find-Edge $edges 'method-pointer' 'uIndA.FirePlain' 'uIndA.PlainTarget'
Check 'M3 GHook:= @PlainTarget (unit variable) reaches GHook(1) in FirePlain' ($m3.Count -eq 1) "($($m3.Count))"
$m4 = @($edges | Where-Object { ($_.kind -eq 'method-pointer') -and ($_.caller -eq 'uIndA.TEmitter.Fire') })
Check 'M4 Fire has exactly ONE method-pointer edge (bindings of FOnIdle do not leak into FOnChange)' ($m4.Count -eq 1) "($($m4.Count))"

# ---- E: events -------------------------------------------------------------------------
$e1 = Find-Edge $edges 'event' 'uIndA.TEmitter.Fire' 'uIndB.TListener.HandleEvt'
Check 'E1 FEmitter.OnChange:= HandleEvt (other unit, through the property) reaches Fire' ($e1.Count -eq 1) "($($e1.Count))"
if ($e1.Count -eq 1) {
  Check 'E1 bind site = uIndB.pas line 54, via FEmitter.OnChange' (($e1[0].bind_path -like '*uIndB.pas') -and ([int]$e1[0].bind_line -eq 54) -and ($e1[0].via -eq 'FEmitter.OnChange')) "($($e1[0].bind_line) via=$($e1[0].via))"
}
$e2 = Find-Edge $edges 'event' '' 'uIndForm.TIndForm.Button1Click'
Check 'E2 Button2.OnClick:= Button1Click (library event): ONE row without call site' (($e2.Count -eq 1) -and ($e2[0].ref_kind -eq '') -and ($e2[0].via -eq 'Button2.OnClick')) "($($e2.Count))"

# ---- T: a FUNCTION is a binding only when the slot's type proves it ------------------------
$t1 = Find-Edge $edges 'method-pointer' 'uIndA.UseCompare' 'uIndA.CmpAsc'
Check 'T1 GCompare:= CmpAsc (function, slot typed `function(..)`) reaches GCompare(1, 2)' ($t1.Count -eq 1) "($($t1.Count))"
$t2 = @($edges | Where-Object { $_.target -eq 'uIndA.CountItems' })
Check 'T2 GCount:= CountItems (a paren-less CALL into an Integer) is no binding' ($t2.Count -eq 0) "($($t2.Count))"
Check 'T2 and it is counted unproven' ($r1.log -match '(?m)^indirect: .* unproven=1 ') ''

# ---- C: callback arguments ---------------------------------------------------------------
$c1 = Find-Edge $edges 'callback-arg' 'uIndB.RunCb' 'uIndA.PlainOther'
$c2 = Find-Edge $edges 'callback-arg' 'uIndB.RunCb' 'uIndA.PlainTarget'
Check 'C1 RunCb(PlainOther) reaches the call ACb(2) inside RunCb' ($c1.Count -eq 1) "($($c1.Count))"
$c2 = @($c2 | Where-Object { [int]$_.bind_line -eq 41 })
Check 'C2 RunCb(@PlainTarget) (line 41) reaches it too' ($c2.Count -eq 1) "($($c2.Count))"
if ($c1.Count -eq 1) {
  Check 'C1 the edge hangs on the call ref ACb (uIndB line 30), via ACb, bound at line 40' (($c1[0].ref_name -eq 'ACb') -and ([int]$c1[0].ref_line -eq 30) -and ($c1[0].via -eq 'ACb') -and ([int]$c1[0].bind_line -eq 40)) "($($c1[0].ref_name) $($c1[0].ref_line) via=$($c1[0].via) bind=$($c1[0].bind_line))"
}
$c3 = @($edges | Where-Object { $_.caller -eq 'uIndB.RunNoCall' })
Check 'C3 a callee that only stores its parameter (RunNoCall) is no caller' ($c3.Count -eq 0) "($($c3.Count))"

# ---- P: a slot copied into another slot --------------------------------------------------
$p1 = Find-Edge $edges 'callback-arg' 'uIndA.FirePlain' 'uIndA.PlainOther'
Check 'P1 RunNoCall(PlainOther) + `GHook:= ACb` inside RunNoCall reaches GHook(1) in FirePlain' (($p1.Count -eq 1) -and ($p1[0].ref_name -eq 'GHook') -and ($p1[0].via -eq 'ACb') -and ([int]$p1[0].bind_line -eq 65) -and ($p1[0].bind_path -like '*uIndB.pas')) "($($p1.Count))"
$p2 = @(Find-Edge $edges 'callback-arg' 'uIndB.RunCb' 'uIndA.PlainTarget' | Where-Object { [int]$_.bind_line -eq 75 })
Check 'P2 RelayCb(@PlainTarget) + RunCb(ACb) inside RelayCb (two hops) reaches ACb(2) in RunCb' (($p2.Count -eq 1) -and ($p2[0].ref_name -eq 'ACb') -and ([int]$p2[0].ref_line -eq 30)) "($($p2.Count))"
$p3 = @($edges | Where-Object { ($_.caller -eq '') -and ($_.target -in 'uIndA.PlainOther', 'uIndA.PlainTarget') })
Check 'P3 a binding that reaches a call through a copy has no extra no-call-site row' ($p3.Count -eq 0) "($($p3.Count))"
$p4 = @($edges | Where-Object { ($_.caller -eq 'uIndA.TEmitter.Fire') -and ($_.target -like 'uIndA.Plain*') })
Check 'P4 copies do not leak into unrelated slots (Fire runs no Plain* routine)' ($p4.Count -eq 0) "($($p4.Count))"

# ---- D: .dfm events ----------------------------------------------------------------------
$d1 = Find-Edge $edges 'dfm-event' '' 'uIndForm.TIndForm.Button1Click'
Check 'D1 OnClick = Button1Click in the .dfm: ONE row, no call site, bound in the .dfm, via Button1.OnClick' (($d1.Count -eq 1) -and ($d1[0].bind_path -like '*uIndForm.dfm') -and ([int]$d1[0].bind_line -eq 16) -and ($d1[0].via -eq 'Button1.OnClick') -and ($d1[0].confidence -eq 'resolved')) "($($d1.Count))"
$d2 = Find-Edge $edges 'dfm-event' '' 'uIndForm.TIndForm.FormCreate'
Check 'D2 OnCreate = FormCreate on the root object, via IndForm.OnCreate' (($d2.Count -eq 1) -and ($d2[0].via -eq 'IndForm.OnCreate')) "($($d2.Count))"
$d3 = Find-Edge $edges 'dfm-event' 'uIndForm.TIndPanel.Ping' 'uIndForm.TIndForm.PanelPing'
Check 'D3 OnPing = PanelPing on a component class OF THE INDEX reaches FOnPing(Self) in TIndPanel.Ping (by-name)' (($d3.Count -eq 1) -and ($d3[0].confidence -eq 'by-name') -and ($d3[0].ref_name -eq 'FOnPing')) "($($d3.Count))"

# ---- N: negatives ----------------------------------------------------------------------
$never = @($edges | Where-Object { $_.target -match '\.(NeverBound|NotAHandler|NotWired|Bind|Wire|Unwire)$' })
Check 'N1 a routine that is never bound is never a target' ($never.Count -eq 0) "($($never.Count))"
$unb = @($edges | Where-Object { $_.caller -eq 'uIndA.TEmitter.FireUnbound' })
Check 'N2 a slot only set to nil (FUnbound) has no edge' ($unb.Count -eq 0) "($($unb.Count))"
$badRef = @($edges | Where-Object { ($_.ref_kind -ne '') -and ($_.ref_kind -ne 'call') })
Check 'N3 every ref_id is a call ref' ($badRef.Count -eq 0) "($($badRef.Count))"
$badKind = @($edges | Where-Object { $_.kind -notin 'method-pointer', 'event', 'dfm-event', 'callback-arg' })
$badConf = @($edges | Where-Object { $_.confidence -notin 'resolved', 'by-name' })
Check 'N4 kind and confidence are the IE_KIND_* / IE_CONF_* values' (($badKind.Count -eq 0) -and ($badConf.Count -eq 0)) "($($badKind.Count), $($badConf.Count))"
$dup = @($edges | Group-Object { "$(Edge-Key $_)|$($_.bind_path)|$($_.bind_line)|$($_.bind_col)|$($_.ref_line)" } | Where-Object Count -gt 1)
Check 'N5 no duplicate rows' ($dup.Count -eq 0) "($($dup.Count))"

# ---- R: a second run replaces the table --------------------------------------------------
$before = ($edges | ForEach-Object { "$(Edge-Key $_)|$($_.bind_line)|$($_.ref_line)" } | Sort-Object) -join ';'
Add-Content -LiteralPath (Join-Path $fx 'uIndB.pas') -Value "`r`n{ touched }" -NoNewline
$r2 = Lane-Index $fx $db 'index-2.log'
$edges2 = Lane-Edges $db
$after = ($edges2 | ForEach-Object { "$(Edge-Key $_)|$($_.bind_line)|$($_.ref_line)" } | Sort-Object) -join ';'
Check 'R1 a second run over a touched unit leaves the same rows (replaced, not appended)' (($r2.rc -eq 0) -and ($edges2.Count -eq $edges.Count) -and ($edges.Count -gt 0) -and ($before -eq $after)) "($($edges.Count) -> $($edges2.Count))"

if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "scratch: $work" }
Write-Host ("run_v156_EXTC2_indirect: {0} pass, {1} fail" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
