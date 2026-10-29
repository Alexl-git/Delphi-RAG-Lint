# run_taint_rules.ps1 -- taint wave lane T2 (2026-10-27): the three interprocedural taint
# rules (taint-sql-injection, taint-command-injection, taint-path-traversal) over the fixture
# project tests\lint-project\taint\ (plan docs\superpowers\plans\2026-10-27-taint-interprocedural-plan.md
# section 9).
#
# -Mode fixture (default until T1 is merged): index the fixture with any engine >= T0, then
#   INSERT the data_flows rows T1 is specified to emit (tests\lint-project\taint\fixture_rows.py,
#   python sqlite3 -- the run_purity_emit check-27 technique).
# -Mode real: the engine's own extractor (T1) fills data_flows; the same assertions must hold.
#
# Asserts: every positive by rule + file + line (+ severity for the weak drop), every negative
# (sanitised, parameterised, literal, re-assigned-before-sink, constant-only caller, a helper that
# only forwards its parameter), the cycle terminating with exactly one finding, `path` in --json
# (source first, sink last), `lint <file> --db` reporting the same sink as lint-all, the stale-
# index note on an index whose data_flows is empty (and its absence on a fresh one), and the POSITIVE CONTROL: with every built-in source
# disabled through a temp config the taint finding count is 0 (the guard can fail).
#
# Usage: pwsh -File tests\autotest\run_taint_rules.ps1 [-Exe <drag-lint.exe>] [-Mode fixture|real]
param([string]$Exe = '', [ValidateSet('fixture', 'real')][string]$Mode = 'fixture')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$fx      = Join-Path $repo 'tests\lint-project\taint'
$libFx   = Join-Path $repo 'tests\lint-project\taint-lib\lib'
$rowsPy  = Join-Path $fx 'fixture_rows.py'
$tmp     = Join-Path $env:TEMP "taint_rules_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$db      = Join-Path $tmp 'fx.sqlite'
$lib     = Join-Path $tmp 'lib.sqlite'
$empty   = Join-Path $tmp 'empty.json'
$noSrc   = Join-Path $tmp 'no-sources.json'
[IO.File]::WriteAllText($empty, '{}')

$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function TaintFindings([string[]]$CliArgs) {
  $raw = & $exePath @CliArgs 2>$null
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { try { $all = @($txt.Substring($b) | ConvertFrom-Json) } catch { $all = @() } }
  return ,@($all | Where-Object { $_.rule -like 'taint-*' })
}
function At($List, [string]$Rule, [string]$Unit, [int]$Line) {
  return ,@($List | Where-Object { $_.rule -eq $Rule -and (Split-Path $_.file_path -Leaf) -eq $Unit -and $_.start_line -eq $Line })
}
function InUnit($List, [string]$Unit) {
  return ,@($List | Where-Object { (Split-Path $_.file_path -Leaf) -eq $Unit })
}

Push-Location $env:TEMP
try {
  & $exePath index $fx    --db $db  2>&1 | Out-Null
  & $exePath index $libFx --db $lib 2>&1 | Out-Null
  # lint-all takes its library store as a SECOND --db (SplitConsumerDbs); --library-db is the
  # lint <file> switch (LintLibraryDb). Either way never the machine's real library index.
  $common = @('--db', $db, '--db', $lib, '--json', '--quiet')

  # Stale index: since T1 the extractor FILLS data_flows, so a fresh index is no longer stale.
  # A real stale case is what every pre-1.26 DB looks like after Migrate -- the table exists
  # and is EMPTY -- so empty a COPY of the fresh index (python sqlite3). Positive control: the
  # fresh index itself must NOT print the note (else the note check could never fail).
  $staleNoteRx = 'taint: this index has no data_flows facts'
  $stale = Join-Path $tmp 'stale.sqlite'
  [IO.File]::Copy($db, $stale, $true)
  $emptyFlows = 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("DELETE FROM data_flows"); c.commit(); print(c.execute("SELECT COUNT(*) FROM data_flows").fetchone()[0])'
  $n = (& python -I -c $emptyFlows $stale 2>&1) -join ' '
  Check 'stale copy: data_flows emptied' ($n -eq '0') "python said: $n"
  $err = Join-Path $tmp 'stale.err'
  $raw = & $exePath lint-all --db $stale --db $lib --json --quiet --config $empty 2>$err
  $staleNote = (Get-Content $err -Raw) -match $staleNoteRx
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $pre = @(); if ($b -ge 0) { $pre = @($txt.Substring($b) | ConvertFrom-Json | Where-Object { $_.rule -like 'taint-*' }) }
  Check 'stale index: one note on stderr' $staleNote "expected `"$staleNoteRx`""
  Check 'stale index: no taint finding' ($pre.Count -eq 0) "got $($pre.Count)"
  $freshErr = Join-Path $tmp 'fresh.err'
  & $exePath lint-all @common --config $empty 2>$freshErr | Out-Null
  $freshNote = (Get-Content $freshErr -Raw) -match $staleNoteRx
  Check 'fresh index: no stale note (positive control)' (-not $freshNote) 'the note fired on an index the extractor filled'

  if ($Mode -eq 'fixture') {
    # fixture mode measures the HAND rows only: drop what the extractor wrote first
    $n = (& python -I -c $emptyFlows $db 2>&1) -join ' '
    Check 'fixture: extractor rows cleared' ($n -eq '0') "python said: $n"
    $n = (& python -I $rowsPy $db $fx taint 2>&1) -join ' '
    Check 'fixture rows inserted (python sqlite3)' ($n -eq '50') "fixture_rows.py said: $n"
    $n = (& python -I $rowsPy $lib $libFx minirtl 2>&1) -join ' '
    Check 'mini-library rows inserted' ($n -eq '3') "fixture_rows.py said: $n"
  }

  $f = TaintFindings (@('lint-all') + $common + @('--config', $empty))
  $f | ForEach-Object { Write-Host ("  {0} {1}:{2} [{3}] {4}" -f $_.rule, (Split-Path $_.file_path -Leaf), $_.start_line, $_.severity, $_.message) }

  # ---- positives (rule, unit, line[, severity]) ----
  $pos = @(
    @('taint-sql-injection',     'uDal.pas',     32, 'error'),    # Edit1.Text -> RunQuery -> DoExec -> ExecSQL (two hops)
    @('taint-sql-injection',     'uDal2.pas',    21, 'error'),    # ReadArg(Trim(ParamStr)) -> base TDalBase.Exec -> override TDal2.Exec -> SQL.Text
    @('taint-sql-injection',     'uCycle.pas',   29, 'error'),    # mutual recursion CycA <-> CycB
    @('taint-sql-injection',     'uWeak.pas',    20, 'warning'),  # bare edtName.Text: weak, one severity lower
    @('taint-sql-injection',     'uField.pas',   31, 'error'),    # field written in Load, spliced in Run
    @('taint-sql-injection',     'uField.pas',   36, 'error'),    # descendant TCfg2 reads the ancestor's field
    @('taint-sql-injection',     'uFieldUp.pas', 25, 'error'),    # mirror: descendant TChild writes it, ancestor TBase reads it
    @('taint-sql-injection',     'uList.pas',    19, 'error'),    # TStringList carrier: L.Add(src); ExecSQL(L.Text)
    @('taint-sql-injection',     'uList.pas',    21, 'error'),    # Q.SQL.Add(src)
    @('taint-sql-injection',     'uLambda.pas',  20, 'error'),    # captured local inside an anonymous method
    @('taint-command-injection', 'uOut.pas',     22, 'error'),    # out param GetName(out S) -> WinExec
    @('taint-command-injection', 'uShellEx.pas', 18, 'error'),    # record member Info.lpFile -> ShellExecuteEx(@Info)
    @('taint-command-injection', 'uCmd.pas',     18, 'error'),    # RunCmd(ParamStr(1)) -> CreateProcess
    @('taint-path-traversal',    'uGlobal.pas',  25, 'warning'),  # unit global written in InitPath -> DeleteFile
    @('taint-command-injection', 'uSelf.pas',    20, 'error'),    # SpawnSelf(ParamStr( 1 )) -> CreateProcess: the TP twin of RunSelf's ParamStr(0)
    @('taint-path-traversal',    'uSelf.pas',    40, 'warning'),  # GetEnvironmentVariable('MY_CACHE'): the TP twin of :35
    @('taint-path-traversal',    'uGlobal.pas',  28, 'warning')   # TFileStream.Create(GetEnvironmentVariable(..)): the TP twin of :30
  )
  foreach ($p in $pos) {
    $hit = At $f $p[0] $p[1] $p[2]
    Check ("hit  {0} {1}:{2}" -f $p[0], $p[1], $p[2]) ($hit.Count -ge 1) 'no finding'
    if ($hit.Count -ge 1) {
      Check ("  severity {0}:{1} = {2}" -f $p[1], $p[2], $p[3]) ($hit[0].severity -eq $p[3]) "got $($hit[0].severity)"
    }
  }
  $weak = At $f 'taint-sql-injection' 'uWeak.pas' 20
  Check 'weak finding says weak' ($weak.Count -ge 1 -and $weak[0].message -match ', weak\)') $(if ($weak.Count) { $weak[0].message })

  # ---- negatives ----
  Check 'no  uSafe.pas (QuotedStr, ParamByName binding, literal, re-assigned, StrToInt, constant-only caller, forwarding helper)' ((InUnit $f 'uSafe.pas').Count -eq 0) "got $((InUnit $f 'uSafe.pas').Count)"
  Check 'no  uList.pas:18 (L.Add on a plain TStringList is not a sink)' ((At $f 'taint-sql-injection' 'uList.pas' 18).Count -eq 0)
  Check 'no  uGlobal.pas:26 (ExtractFileName sanitises a path)' ((At $f 'taint-path-traversal' 'uGlobal.pas' 26).Count -eq 0)
  # TAINTFP 2026-10-27: ParamStr is not a CWE-22 source (taint-sources.json "categories")
  Check 'no  uGlobal.pas:30 (ParamStr names the whole path: not a path-traversal source)' ((At $f 'taint-path-traversal' 'uGlobal.pas' 30).Count -eq 0)
  Check 'no  uGlobal.pas:32 (ExpandFileName(ParamStr): same, through a propagator)' ((At $f 'taint-path-traversal' 'uGlobal.pas' 32).Count -eq 0)
  $self = At $f 'taint-command-injection' 'uSelf.pas' 20
  Check 'uSelf.pas:20 once, from RunArgOne only (ParamStr(0) is the module path: trusted_args)' ($self.Count -eq 1 -and @($self[0].path)[0].line -eq 30) $(if ($self.Count) { "$($self.Count) finding(s), first source line $(@($self[0].path)[0].line)" })
  Check "no  uSelf.pas:35 (GetEnvironmentVariable('LocalAppData') is an OS known folder: trusted_args)" ((At $f 'taint-path-traversal' 'uSelf.pas' 35).Count -eq 0)
  Check 'no  uInput.pas (sources only; reported at the sink)' ((InUnit $f 'uInput.pas').Count -eq 0)
  Check 'exactly one finding in uCycle.pas (the cycle terminates)' ((InUnit $f 'uCycle.pas').Count -eq 1) "got $((InUnit $f 'uCycle.pas').Count)"
  Check 'exactly one finding in uCmd.pas (RunCmdConst passes a literal)' ((InUnit $f 'uCmd.pas').Count -eq 1) "got $((InUnit $f 'uCmd.pas').Count)"
  Check 'total taint findings = 17' ($f.Count -eq 17) "got $($f.Count)"

  # ---- path ----
  $noPath = @($f | Where-Object { $null -eq $_.path -or @($_.path).Count -lt 2 })
  Check 'every taint finding carries path (>= 2 hops)' ($noPath.Count -eq 0) "$($noPath.Count) without"
  $bad = @($f | Where-Object { @($_.path)[0].note -notmatch '^source ' -or @($_.path)[-1].note -notmatch '^sink ' })
  Check 'path runs source first, sink last' ($bad.Count -eq 0) "$($bad.Count) malformed"
  $d2 = At $f 'taint-sql-injection' 'uDal2.pas' 21
  if ($d2.Count -ge 1) {
    $routines = @($d2[0].path | ForEach-Object { $_.routine })
    Check 'uDal2 path crosses ReadArg and RunArg' (($routines -contains 'uInput.ReadArg') -and ($routines -contains 'uDal.RunArg')) ($routines -join ' > ')
  }

  # ---- lint <file> --db reports the same sink as lint-all ----
  $one = TaintFindings @('lint', (Join-Path $fx 'uDal2.pas'), '--db', $db, '--library-db', $lib, '--json', '--config', $empty)
  Check 'lint uDal2.pas --db reports the lint-all sink (21)' ((At $one 'taint-sql-injection' 'uDal2.pas' 21).Count -eq 1) "got $($one.Count) taint findings"

  # ---- POSITIVE CONTROL: every built-in source disabled -> 0 ----
  $ids = @((Get-Content (Join-Path $repo 'rules\taint-sources.json') -Raw | ConvertFrom-Json).sources | ForEach-Object { $_.id })
  # the receiver-name heuristic is a source too (weak): switch it off with them
  $cfg = @{ taint = @{ disable = $ids; weak_receiver_regex = '' } } | ConvertTo-Json -Depth 4
  [IO.File]::WriteAllText($noSrc, $cfg)
  $none = TaintFindings (@('lint-all') + $common + @('--config', $noSrc))
  Check "positive control: $($ids.Count) sources + receiver heuristic disabled -> 0 taint findings" ($none.Count -eq 0) "got $($none.Count)"
  Check 'positive control is live (the same run without it found > 0)' ($f.Count -gt 0)
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($tmp, $true) } catch { }
}
if ($fail -eq 0) { Write-Host "run_taint_rules ($Mode): ALL PASS"; exit 0 }
Write-Host "run_taint_rules ($Mode): $fail FAILED"; exit 1
