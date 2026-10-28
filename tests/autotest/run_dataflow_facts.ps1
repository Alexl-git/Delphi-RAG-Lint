<#
  run_dataflow_facts.ps1 -- taint wave T1 (plan docs\superpowers\plans\
  2026-10-27-taint-interprocedural-plan.md sections 2, 3 and 9).

  Indexes tests\index\dataflow\uTaintProbe.pas (one routine per shape) plus a
  GENERATED uTaintBig.pas (a routine over the 2,000-block CFG cap, and one over
  the DF_ROW_CAP row cap) into a temp DB and asserts the data_flows rows the
  extractor (DRagLint.Index.DataFlowFacts) wrote:
    * every shape of section 9, POSITIVE and the no-row NEGATIVES (the
      flow-sensitive kill, literal-only, numeric-only, the `with` body);
    * the join: every 'arg' / 'write' row (and every src 'ref' row) lands on a
      refs row at the same (file_id, start_line, start_col);
    * reindexing the same (touched) file leaves the count unchanged (cascade);
    * `schema` lists data_flows;
    * a DB whose stored extractor fingerprint predates 1.26.0 re-parses and
      gets its rows.
  Sites are located by the { M-... } marker comments, never by line number.
  The data is read with python sqlite3 (named columns), not `sql --json`
  (whose rows are positional arrays -- a lesson this repo paid for).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dataflow-facts-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$py  = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { Write-Host 'FATAL: python not on PATH' -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$SrcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $SrcDir | Out-Null

$probe = Join-Path $SrcDir 'uTaintProbe.pas'
Copy-Item (Join-Path $PSScriptRoot '..\index\dataflow\uTaintProbe.pas') $probe

# ---- generated: a routine over the CFG block cap, a routine over the row cap ----
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("unit uTaintBig;`r`n`r`ninterface`r`n`r`nprocedure BigSink(const S: string);`r`nprocedure BigRoutine(C: Boolean; const A: string);`r`nprocedure CapRoutine(const A: string);`r`n`r`nimplementation`r`n`r`n")
[void]$sb.Append("procedure BigSink(const S: string);`r`nbegin`r`nend;`r`n`r`n")
[void]$sb.Append("procedure BigRoutine(C: Boolean; const A: string);`r`nvar`r`n  S: string;`r`nbegin`r`n  S:= A;`r`n")
for ($i = 0; $i -lt 1100; $i++) { [void]$sb.Append("  if C then S:= S + 'x';`r`n") }
[void]$sb.Append("  BigSink(S); { M-BIG }`r`nend;`r`n`r`n")
[void]$sb.Append("procedure CapRoutine(const A: string);`r`nbegin`r`n")
for ($i = 0; $i -lt 4100; $i++) { [void]$sb.Append("  BigSink(A);`r`n") }
[void]$sb.Append("end;`r`n`r`nend.`r`n")
[System.IO.File]::WriteAllText((Join-Path $SrcDir 'uTaintBig.pas'), $sb.ToString(), [System.Text.Encoding]::ASCII)

$db  = Join-Path $WorkDir 'dataflow.sqlite'
$out1 = (& $Exe index $SrcDir --db $db 2>&1 | Out-String)

$pyFile = Join-Path $WorkDir 'df.py'
@'
import sqlite3, sys, json
db, probe = sys.argv[1], sys.argv[2]
lines = open(probe, encoding='ascii').read().split('\n')
def line_of(m):
    hits = [i + 1 for i, l in enumerate(lines) if ('{ ' + m + ' }') in l]
    return hits[0] if hits else -1
c = sqlite3.connect(db)
c.row_factory = sqlite3.Row
has = c.execute("select count(*) from sqlite_master where type='table' and name='data_flows'").fetchone()[0]
out = {'has_table': has}
if not has:
    print(json.dumps(out)); sys.exit(0)
def rows(routine):
    q = ("select d.*, s.name as routine from data_flows d join symbols s on s.id = d.symbol_id "
         "where s.name = ? collate nocase or s.name like ? collate nocase")
    return [dict(r) for r in c.execute(q, (routine, '%.' + routine))]
routines = ['TrimParam','SinkParam','ViaLocal','Killed','Branch','Loop','LiteralOnly','Quoted',
            'NumericOnly','WithBody','ExitValue','SelfIndex','SetField','ReadField','SetGlobal',
            'GetName','UseOut','ListCarrier','ShellRecord','LambdaCapture','BigRoutine','CapRoutine',
            'ArgValueOnly','ArgRtlValue','ArgUnresolved','ArgTryGet','HardCast']
out['rows'] = {r: rows(r) for r in routines}
out['markers'] = {m: line_of(m) for m in ['M-TRIM','M-SINKPARAM','M-VIALOCAL-SRC','M-VIALOCAL-DST',
    'M-KILL-SRC','M-KILL-DST','M-BRANCH','M-LOOP','M-QUOTED','M-EXIT','M-SELFINDEX','M-SETFIELD',
    'M-READFIELD','M-SETGLOBAL','M-READGLOBAL','M-OUTPARAM','M-ARGOUT-CALL','M-ARGOUT-SINK',
    'M-LIST','M-SHELLREC','M-LAMBDA','M-ARGVAL-SINK','M-ARGRTL-SINK','M-ARGUNRES-CALL','M-ARGUNRES-SINK',
    'M-ARGTRY-CALL','M-ARGTRY-K','M-ARGTRY-V','M-G5WRITE','M-G5READ','M-G5SINK']}
out['total'] = c.execute('select count(*) from data_flows').fetchone()[0]
out['orphans'] = c.execute('select count(*) from data_flows d left join symbols s on s.id = d.symbol_id where s.id is null').fetchone()[0]
miss = c.execute("""select d.dst_kind, d.dst_line, d.dst_col, d.dst_name from data_flows d
  where d.dst_kind in ('arg','write') and not exists (select 1 from refs r where r.file_id = d.file_id
  and r.start_line = d.dst_line and r.start_col = d.dst_col)""").fetchall()
out['dst_join_miss'] = [list(m) for m in miss]
out['dst_join_total'] = c.execute("select count(*) from data_flows where dst_kind in ('arg','write')").fetchone()[0]
miss = c.execute("""select d.src_line, d.src_col, d.src_name from data_flows d
  where d.src_kind = 'ref' and not exists (select 1 from refs r where r.file_id = d.file_id
  and r.start_line = d.src_line and r.start_col = d.src_col)""").fetchall()
out['src_join_miss'] = [list(m) for m in miss]
out['src_join_total'] = c.execute("select count(*) from data_flows where src_kind = 'ref'").fetchone()[0]
print(json.dumps(out))
'@ | Set-Content $pyFile -Encoding ascii

function Read-Facts { (& python $pyFile $db $probe) -join "`n" | ConvertFrom-Json }
$r = Read-Facts
$Rw = $r.rows
$M = $r.markers
function Has($rs, [scriptblock]$p) { @($rs | Where-Object $p).Count -gt 0 }

Write-Host 'Table' -ForegroundColor Cyan
Check 'data_flows exists' ($r.has_table -eq 1)
if ($r.has_table -ne 1) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Check 'the index wrote rows at all (POSITIVE CONTROL for every no-row negative below)' ($r.total -gt 0) "total=$($r.total)"

Write-Host 'Shapes' -ForegroundColor Cyan
$t = $Rw.TrimParam
Check 'param -> Trim argument (direct)' (Has $t { $_.dst_kind -eq 'arg' -and $_.dst_name -eq 'Trim' -and $_.dst_index -eq 0 -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.via_local -eq 0 -and $_.cond -eq 0 })
Check 'Trim result -> Result (src ref at the Trim call)' (Has $t { $_.dst_kind -eq 'result' -and $_.src_kind -eq 'ref' -and $_.src_name -eq 'Trim' -and $_.src_line -eq $M.'M-TRIM' -and $_.via_local -eq 0 -and $_.cond -eq 0 })
Check 'TrimParam has exactly those 2 rows' (@($t).Count -eq 2) "rows=$(@($t).Count)"
$t = $Rw.SinkParam
Check 'param 1 (Q is 0) -> Q.SQL.Add argument' (Has $t { $_.dst_kind -eq 'arg' -and $_.dst_name -eq 'Add' -and $_.dst_receiver -eq 'Q.SQL' -and $_.src_kind -eq 'param' -and $_.src_index -eq 1 -and $_.via_local -eq 0 })
$t = $Rw.ViaLocal
Check 'S := Edit1.Text; Q.SQL.Text := S -> write row via local' (Has $t { $_.dst_kind -eq 'write' -and $_.dst_name -eq 'Text' -and $_.dst_receiver -eq 'Q.SQL' -and $_.dst_line -eq $M.'M-VIALOCAL-DST' -and $_.src_kind -eq 'ref' -and $_.src_name -eq 'Text' -and $_.src_line -eq $M.'M-VIALOCAL-SRC' -and $_.via_local -eq 1 -and $_.cond -eq 0 })
$t = $Rw.Killed
Check 'NEGATIVE: S := ''x'' kills the earlier source (flow-sensitive)' (-not (Has $t { $_.dst_line -eq $M.'M-KILL-DST' })) "rows at sink=$(@($t | ? { $_.dst_line -eq $M.'M-KILL-DST' }).Count)"
$t = @($Rw.Branch | Where-Object { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-BRANCH' })
Check 'branch: both A and B reach Sink, cond 1' ((Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 1 -and $_.cond -eq 1 -and $_.via_local -eq 1 }) -and (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 2 -and $_.cond -eq 1 })) "rows=$($t.Count)"
Check 'branch: the Boolean C reaches nothing' (-not (Has $t { $_.src_kind -eq 'param' -and $_.src_index -eq 0 }))
$t = $Rw.Loop
Check 'loop accumulation S := S + Lines[I] -> Sink, cond 1' (Has $t { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-LOOP' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.cond -eq 1 })
Check 'NEGATIVE: literal-only call emits nothing' (@($Rw.LiteralOnly).Count -eq 0) "rows=$(@($Rw.LiteralOnly).Count)"
Check 'QuotedStr(A) result IS a row (sanitising is the linter''s job)' (Has $Rw.Quoted { $_.dst_kind -eq 'result' -and $_.src_kind -eq 'ref' -and $_.src_name -eq 'QuotedStr' })
Check 'NEGATIVE: numeric-only routine emits nothing' (@($Rw.NumericOnly).Count -eq 0) "rows=$(@($Rw.NumericOnly).Count)"
Check 'NEGATIVE: a with body emits nothing' (@($Rw.WithBody).Count -eq 0) "rows=$(@($Rw.WithBody).Count)"
$t = $Rw.ExitValue
Check 'Exit(A) -> result at the Exit site, cond 1 (one path only)' (Has $t { $_.dst_kind -eq 'result' -and $_.dst_line -eq $M.'M-EXIT' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.cond -eq 1 })
Check 'method parameter indices exclude Self (B is 1)' (Has $Rw.SelfIndex { $_.dst_kind -eq 'arg' -and $_.src_kind -eq 'param' -and $_.src_index -eq 1 -and $_.src_name -eq 'B' })
Check 'field write FSql := A' (Has $Rw.SetField { $_.dst_kind -eq 'field' -and $_.dst_name -eq 'FSql' -and $_.dst_line -eq $M.'M-SETFIELD' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 })
Check 'field read Sink(FSql)' (Has $Rw.ReadField { $_.dst_kind -eq 'arg' -and $_.src_kind -eq 'field' -and $_.src_name -eq 'FSql' })
Check 'unit global write GConn := A' (Has $Rw.SetGlobal { $_.dst_kind -eq 'global' -and $_.dst_name -eq 'GConn' -and $_.src_kind -eq 'param' })
Check 'unit global read Sink(GConn)' (Has $Rw.SetGlobal { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-READGLOBAL' -and $_.src_kind -eq 'global' -and $_.src_name -eq 'GConn' })
Check 'out param S := ParamStr(1) -> outparam 0' (Has $Rw.GetName { $_.dst_kind -eq 'outparam' -and $_.dst_index -eq 0 -and $_.dst_name -eq 'S' -and $_.src_kind -eq 'ref' -and $_.src_name -eq 'ParamStr' })
Check 'argout: GetName(N); Sink(N)' (Has $Rw.UseOut { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-ARGOUT-SINK' -and $_.src_kind -eq 'argout' -and $_.src_index -eq 0 -and $_.src_name -eq 'GetName' -and $_.src_line -eq $M.'M-ARGOUT-CALL' })
Write-Host 'argout cut (lane ARGOUT): only var/out slots of a known callee, unresolved kept' -ForegroundColor Cyan
$t = @($Rw.ArgValueOnly | Where-Object { $_.dst_line -eq $M.'M-ARGVAL-SINK' })
Check 'ArgValueOnly: POSITIVE CONTROL -- the ParamStr ref reaches Sink(N)' (Has $t { $_.src_kind -eq 'ref' -and $_.src_name -eq 'ParamStr' }) "rows=$($t.Count)"
Check 'NEGATIVE: same-unit value param TrimParam(N) -> no argout at Sink(N)' (-not (Has $t { $_.src_kind -eq 'argout' })) "argout=$(@($t | ? { $_.src_kind -eq 'argout' }).Count)"
$t = @($Rw.ArgRtlValue | Where-Object { $_.dst_line -eq $M.'M-ARGRTL-SINK' })
Check 'ArgRtlValue: POSITIVE CONTROL -- the ParamStr ref reaches Sink(N)' (Has $t { $_.src_kind -eq 'ref' -and $_.src_name -eq 'ParamStr' }) "rows=$($t.Count)"
Check 'NEGATIVE: RTL value-only Trim(N) -> no argout at Sink(N)' (-not (Has $t { $_.src_kind -eq 'argout' })) "argout=$(@($t | ? { $_.src_kind -eq 'argout' }).Count)"
Check 'unresolved ExternalFill(N) KEEPS its argout row' (Has $Rw.ArgUnresolved { $_.dst_line -eq $M.'M-ARGUNRES-SINK' -and $_.src_kind -eq 'argout' -and $_.src_name -eq 'ExternalFill' -and $_.src_index -eq 0 -and $_.src_line -eq $M.'M-ARGUNRES-CALL' })
Check 'TryGetValue(K, V): argout at position 1 reaches Sink(V)' (Has $Rw.ArgTryGet { $_.dst_line -eq $M.'M-ARGTRY-V' -and $_.src_kind -eq 'argout' -and $_.src_name -eq 'TryGetValue' -and $_.src_index -eq 1 })
Check 'NEGATIVE: TryGetValue(K, V): no argout at position 0 for Sink(K)' (-not (Has $Rw.ArgTryGet { $_.dst_line -eq $M.'M-ARGTRY-K' -and $_.src_kind -eq 'argout' }))
Check 'ArgTryGet: POSITIVE CONTROL -- the ParamStr ref reaches Sink(K)' (Has $Rw.ArgTryGet { $_.dst_line -eq $M.'M-ARGTRY-K' -and $_.src_kind -eq 'ref' -and $_.src_name -eq 'ParamStr' })
Check 'container: L.Add(A); Sink(L.Text)' (Has $Rw.ListCarrier { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-LIST' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.via_local -eq 1 })
Check 'record member: Info.lpFile := PChar(A); ShellExecuteEx(@Info)' (Has $Rw.ShellRecord { $_.dst_kind -eq 'arg' -and $_.dst_name -eq 'ShellExecuteEx' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 })
Check 'record member write row Info.lpFile' (Has $Rw.ShellRecord { $_.dst_kind -eq 'write' -and $_.dst_name -eq 'lpFile' -and $_.dst_receiver -eq 'Info' -and $_.src_kind -eq 'param' })
Check 'G5 hard-cast write TEditStub(O).Text := A gives a write row' (Has $Rw.HardCast { $_.dst_kind -eq 'write' -and $_.dst_name -eq 'Text' -and $_.dst_line -eq $M.'M-G5WRITE' -and $_.src_kind -eq 'param' -and $_.src_index -eq 1 })
Check 'G5 hard-cast read X := TEditStub(O).Text gives a src ref row' (Has $Rw.HardCast { $_.src_kind -eq 'ref' -and $_.src_name -eq 'Text' -and $_.src_line -eq $M.'M-G5READ' })
Check 'G5 hard-cast read keeps the receiver (cast-call) ref: Sink(X) still gets the TEditStub ref (no recall loss vs. before G5)' (Has $Rw.HardCast { $_.dst_kind -eq 'arg' -and $_.dst_name -eq 'Sink' -and $_.dst_line -eq $M.'M-G5SINK' -and $_.src_kind -eq 'ref' -and $_.src_name -eq 'TEditStub' })
Check 'lambda body sees the captured local (cond 1)' (Has $Rw.LambdaCapture { $_.dst_kind -eq 'arg' -and $_.dst_line -eq $M.'M-LAMBDA' -and $_.src_kind -eq 'param' -and $_.src_index -eq 0 -and $_.cond -eq 1 })

Write-Host 'Fallback and cap' -ForegroundColor Cyan
Check 'over-cap routine takes the flow-insensitive fallback (note printed)' ($out1 -match 'data_flows: flow-insensitive fallback.*BigRoutine') ''
Check 'fallback rows exist and are all cond 1' ((@($Rw.BigRoutine).Count -gt 0) -and -not (Has $Rw.BigRoutine { $_.cond -ne 1 })) "rows=$(@($Rw.BigRoutine).Count)"
Check 'row cap: CapRoutine stops at 4000 rows (note printed)' ((@($Rw.CapRoutine).Count -eq 4000) -and ($out1 -match 'data_flows: row cap.*CapRoutine')) "rows=$(@($Rw.CapRoutine).Count)"

Write-Host 'Positions join refs' -ForegroundColor Cyan
Check 'every arg/write row lands on a refs row' ($r.dst_join_miss.Count -eq 0 -and $r.dst_join_total -gt 0) "total=$($r.dst_join_total) miss=$($r.dst_join_miss.Count) $(($r.dst_join_miss | Select-Object -First 5 | % { $_ -join ':' }) -join ' ')"
Check 'every src ref row lands on a refs row' ($r.src_join_miss.Count -eq 0 -and $r.src_join_total -gt 0) "total=$($r.src_join_total) miss=$($r.src_join_miss.Count) $(($r.src_join_miss | Select-Object -First 5 | % { $_ -join ':' }) -join ' ')"

Write-Host 'Invalidation' -ForegroundColor Cyan
$total1 = $r.total
Add-Content -LiteralPath $probe -Value "{ touched }" -Encoding ascii
& $Exe index $SrcDir --db $db 2>&1 | Out-Null
$r2 = Read-Facts
Check 'reindex of a touched file: count unchanged (cascade, no duplicates)' ($total1 -gt 0 -and $r2.total -eq $total1) "before=$total1 after=$($r2.total)"
Check 'no orphan rows' ($r2.orphans -eq 0) "orphans=$($r2.orphans)"
$schema = (& $Exe schema --db $db 2>&1 | Out-String)
Check '`schema` lists data_flows' ($schema -match 'data_flows')

Write-Host 'Pre-1.26 DB re-parses' -ForegroundColor Cyan
$fp = @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
keys = [r[0] for r in c.execute("select key from schema_meta where key like '%fingerprint%' and key not like 'resolver%'")]
for k in keys:
    v = c.execute('select value from schema_meta where key = ?', (k,)).fetchone()[0]
    c.execute('update schema_meta set value = ? where key = ?', (v.replace('1.26.0-alpha', '1.25.0-alpha'), k))
c.execute("update files set indexed_at_fingerprint = replace(indexed_at_fingerprint, '1.26.0-alpha', '1.25.0-alpha')")
c.execute('delete from data_flows')
c.commit()
print(len(keys), c.execute('select count(*) from data_flows').fetchone()[0])
'@
$fpFile = Join-Path $WorkDir 'fp.py'
$fp | Set-Content $fpFile -Encoding ascii
$fpOut = (& python $fpFile $db) -join ' '
& $Exe index $SrcDir --db $db 2>&1 | Out-Null
$r3 = Read-Facts
Check 'a DB stamped 1.25.0 (rows emptied) re-parses and gets its rows back' (($fpOut -match '^[1-9]\d* 0$') -and ($total1 -gt 0 -and $r3.total -eq $total1)) "fingerprint keys/rows after wipe=$fpOut, rows after index=$($r3.total) (expected $total1)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-dataflow-facts-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
