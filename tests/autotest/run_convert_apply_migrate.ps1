<#
  run_convert_apply_migrate.ps1 -- C18 member replacement, SLICE 1 (1.31.8):
  `#migrate Old -> New` and `#migrate Old -> DL_NONE` inside a `#convert` block.

  THE CONTRACT this guard pins (docs\superpowers\specs\2026-10-11-member-
  replacement-design.md, owner answers Q1/Q2/Q5):
    * RENAME: every BOUND access site of a converted instance -- a method call,
      an event assignment, a Self.<inst> receiver, a site after a non-ASCII
      character on the same line (byte -> char columns) -- has its member token
      rewritten Old -> New; items[] migrate-applied; pas_uses status mapped.
      An unconverted receiver of the same type (Other.Click) is untouched.
    * DL_NONE: each site's member-access expression is WRAPPED,
      `inst.Old` -> `DL_NONE(inst.Old)`, the old text kept (Q2); items[]
      deliberate-break; the applied unit FAILS to compile on exactly those
      lines while the rename unit compiles.
    * WITH: a member reached through `with inst do` is never rewritten -- a
      migrate-check warning names the with line.
    * IDEMPOTENT: a second run over the applied .pas (the .dfm restored so the
      instance converts again) makes no migrate edit; DL_NONE is not nested.
    * POSITIVE CONTROL: the same unit under a book without #migrate keeps every
      Click / OnClick site byte for byte.
    * `info --json` advertises capability migrate_members = true.

  Fixtures: tests\autotest\fixtures\migrate, COPIED to a $PID scratch folder and
  indexed there. Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_migrate_$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures\migrate\*') $WorkDir

function P([string]$n) { return (Join-Path $WorkDir $n) }
$Ansi = [Text.Encoding]::GetEncoding(1252)
function Text([string]$n) { return $Ansi.GetString([IO.File]::ReadAllBytes((P $n))) }

# a CP1252 e-acute (one char, two UTF-8 bytes in the index) BEFORE a site on its
# line: the fixture stays 7-bit ASCII, the scratch copy carries the byte
$mf = [IO.File]::ReadAllBytes((P 'MigForm.pas'))
$mfText = [Text.Encoding]::ASCII.GetString($mf).Replace('XE9X', [string][char]0xE9)
[IO.File]::WriteAllBytes((P 'MigForm.pas'), $Ansi.GetBytes($mfText))
$dfmOrig = @{}
foreach ($u in 'MigForm', 'CtlForm', 'DlForm', 'WithForm') { $dfmOrig[$u] = [IO.File]::ReadAllBytes((P "$u.dfm")) }

$db = P 'fx.sqlite'
function Reindex { & $Exe index $WorkDir --db $db 2>&1 | Out-Null }
Reindex
Check 'V the fixture index was built' (Test-Path $db)

function Apply([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe @(@('convert-apply', '--unit', (P $Unit), '--rules', (P $Rules), '--db', $db) + $Extra) 2>&1) -join "`n"
  $j = $null
  if ($Extra -contains 'json') { try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {} }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o; J = $j }
}
function Kinds($j, [string]$k) { if ($null -eq $j) { return @() }; return @($j.items | Where-Object { $_.kind -eq $k }) }

# ---- capability ------------------------------------------------------------
$info = $null; try { $info = ((& $Exe info --json 2>$null) -join "`n") | ConvertFrom-Json } catch {}
Check 'K1 info --json capabilities.migrate_members is the JSON literal true' (($null -ne $info) -and ($info.capabilities.migrate_members -is [bool]) -and $info.capabilities.migrate_members)

# ---- rename: dry run JSON -----------------------------------------------------
$r = Apply 'MigForm.pas' 'rename.rules' @('--format', 'json')
$ma = Kinds $r.J 'migrate-applied'
Check 'R1 rename dry run: exit 0, JSON parsed' (($r.Code -eq 0) -and ($null -ne $r.J)) $r.Out
Check 'R2 ... 4 migrate-applied items (Click x3 incl. Self. and the non-ASCII line, OnClick x1), field access_sites' `
  (($ma.Count -eq 4) -and (@($ma | Where-Object { $_.field -ne 'access_sites' }).Count -eq 0)) (($ma | ForEach-Object { "$($_.path)@$($_.line)" }) -join ', ')
Check 'R3 ... each carries instance btnTop, path = old member, value = new member, rule_line' `
  ((@($ma | Where-Object { ($_.instance -eq 'btnTop') -and ((($_.path -eq 'Click') -and ($_.value -eq 'Press')) -or (($_.path -eq 'OnClick') -and ($_.value -eq 'OnPress'))) -and ($_.rule_line -gt 0) }).Count) -eq 4) $r.Out
$pu = @($r.J.pas_uses | Where-Object { $_.instance -eq 'btnTop' -and ($_.member -eq 'Click' -or $_.member -eq 'OnClick') })
Check 'R4 ... pas_uses Click and OnClick are status mapped' (($pu.Count -eq 2) -and (@($pu | Where-Object { $_.status -ne 'mapped' }).Count -eq 0)) (($pu | ForEach-Object { "$($_.member)=$($_.status)" }) -join ', ')
Check 'R5 ... no migrate-check and no deliberate-break' (((Kinds $r.J 'migrate-check').Count -eq 0) -and ((Kinds $r.J 'deliberate-break').Count -eq 0)) $r.Out

# ---- rename: --apply ----------------------------------------------------------
$r = Apply 'MigForm.pas' 'rename.rules' @('--apply', '--no-backup')
$t = Text 'MigForm.pas'
Check 'R6 rename --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'R7 ... btnTop.Press / Self.btnTop.Press / btnTop.OnPress written' `
  ($t.Contains("  btnTop.Press;`r`n  Self.btnTop.Press;`r`n  btnTop.OnPress := DoClick;`r`n")) $t
Check 'R8 ... the site after the CP1252 character renamed at the right column' ($t.Contains("Other.Caption := 'caf" + [char]0xE9 + "'; btnTop.Press;`r`n")) $t
Check 'R9 ... the unconverted receiver Other.Click is untouched' ($t.Contains("  Other.Click;`r`n")) $t
Check 'R10 ... no btnTop.Click / btnTop.OnClick left' (-not ($t -match 'btnTop\.(Click|OnClick)\b')) $t

# ---- idempotence: restore the .dfm (the instance converts again), re-run ------
$h1 = (Get-FileHash (P 'MigForm.pas')).Hash
[IO.File]::WriteAllBytes((P 'MigForm.dfm'), $dfmOrig['MigForm'])
Reindex
$r = Apply 'MigForm.pas' 'rename.rules' @('--format', 'json')
Check 'I1 second run (rename): no migrate-applied item' ((Kinds $r.J 'migrate-applied').Count -eq 0) $r.Out
$r = Apply 'MigForm.pas' 'rename.rules' @('--apply', '--no-backup')
$t2 = Text 'MigForm.pas'
Check 'I2 ... --apply leaves every Press/OnPress site as it was (no double rename)' (([regex]::Matches($t2, '\bPress\b')).Count -eq 3 -and ([regex]::Matches($t2, '\bOnPress\b')).Count -eq 1) $t2

# ---- positive control: the same code, a book with no #migrate ---------------
$r = Apply 'CtlForm.pas' 'control.rules' @('--format', 'json')
Check 'C1 control dry run: no migrate item of any kind' `
  (($r.Code -eq 0) -and ((Kinds $r.J 'migrate-applied').Count + (Kinds $r.J 'migrate-check').Count + (Kinds $r.J 'deliberate-break').Count -eq 0)) $r.Out
$r = Apply 'CtlForm.pas' 'control.rules' @('--apply', '--no-backup')
$t = Text 'CtlForm.pas'
Check 'C2 ... --apply keeps btnTop.Click / Self.btnTop.Click / btnTop.OnClick' `
  (($r.Code -eq 0) -and $t.Contains("  btnTop.Click;`r`n  Self.btnTop.Click;`r`n  btnTop.OnClick := DoClick;`r`n")) $t

# ---- DL_NONE ------------------------------------------------------------------
$r = Apply 'DlForm.pas' 'dlnone.rules' @('--format', 'json')
$db1 = Kinds $r.J 'deliberate-break'
Check 'D1 DL_NONE dry run: 2 deliberate-break items (Count, Hint), field todos, value DL_NONE' `
  (($db1.Count -eq 2) -and (@($db1 | Where-Object { $_.field -ne 'todos' -or $_.value -ne 'DL_NONE' }).Count -eq 0) -and `
   (@($db1 | ForEach-Object { $_.path } | Sort-Object) -join ',') -eq 'Count,Hint') $r.Out
Check 'D2 ... old_value is the wrapped text' ((@($db1 | Where-Object { $_.old_value -eq ('btnTop.' + $_.path) }).Count) -eq 2) $r.Out
$pu = @($r.J.pas_uses | Where-Object { $_.instance -eq 'btnTop' -and ($_.member -eq 'Count' -or $_.member -eq 'Hint') })
Check 'D3 ... pas_uses Count and Hint are status mapped' (($pu.Count -eq 2) -and (@($pu | Where-Object { $_.status -ne 'mapped' }).Count -eq 0)) (($pu | ForEach-Object { "$($_.member)=$($_.status)" }) -join ', ')
$r = Apply 'DlForm.pas' 'dlnone.rules' @('--apply', '--no-backup')
$t = Text 'DlForm.pas'
Check 'D4 ... --apply: N := DL_NONE(btnTop.Count); DL_NONE(btnTop.Hint) := ''h''; btnTop.Press;' `
  (($r.Code -eq 0) -and $t.Contains("  btnTop.Press;`r`n  N := DL_NONE(btnTop.Count);`r`n  DL_NONE(btnTop.Hint) := 'h';`r`n")) $t
[IO.File]::WriteAllBytes((P 'DlForm.dfm'), $dfmOrig['DlForm'])
Reindex
$r = Apply 'DlForm.pas' 'dlnone.rules' @('--format', 'json')
$db2 = Kinds $r.J 'deliberate-break'
Check 'I4 DL_NONE second run REACHES the marked sites (non-vacuous): 2 deliberate-break items saying already marked' `
  (($db2.Count -eq 2) -and (@($db2 | Where-Object { $_.text -match 'already DL_NONE-marked' }).Count -eq 2)) $r.Out
$r = Apply 'DlForm.pas' 'dlnone.rules' @('--apply', '--no-backup')
$t2 = Text 'DlForm.pas'
Check 'I3 DL_NONE second run: no DL_NONE(DL_NONE(...)), exactly 2 markers' `
  ((-not $t2.Contains('DL_NONE(DL_NONE(')) -and (([regex]::Matches($t2, 'DL_NONE\(')).Count -eq 2)) $t2

# ---- with block ----------------------------------------------------------------
$r = Apply 'WithForm.pas' 'rename.rules' @('--format', 'json')
$mc = Kinds $r.J 'migrate-check'
$withLine = 1 + [array]::IndexOf(((Text 'WithForm.pas') -split "`r`n"), '  with btnTop do')
Check 'W1 with block: a migrate-check warning on the with line, field warnings' `
  ((@($mc | Where-Object { $_.line -eq $withLine -and $_.field -eq 'warnings' -and $_.instance -eq 'btnTop' }).Count) -ge 1) (($mc | ForEach-Object { "$($_.line): $($_.text)" }) -join ' | ')
Check 'W2 ... the plain site below it is still renamed (1 migrate-applied)' ((Kinds $r.J 'migrate-applied').Count -eq 1) $r.Out
$r = Apply 'WithForm.pas' 'rename.rules' @('--apply', '--no-backup')
$t = Text 'WithForm.pas'
Check 'W3 ... --apply leaves the with body Click untouched' (($r.Code -eq 0) -and $t.Contains("  with btnTop do`r`n    Click;`r`n  btnTop.Press;`r`n")) $t

# ---- compile: rename + control compile; DL_NONE fails on exactly its lines ---
function Compile([string]$Prog, [string[]]$Units) {
  [IO.File]::WriteAllText((P "$Prog.dpr"), (@("program $Prog;", '', 'uses', ('  ' + ($Units -join ', ') + ';'), '', 'begin', 'end.') -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
  New-Item -ItemType Directory (P "bin_$Prog"), (P "dcu_$Prog") -Force | Out-Null
  $bat = P "compile_$Prog.bat"; $log = P "compile_$Prog.log"
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$WorkDir`"",
    "dcc64 -Q -B -NSSystem -E`"$WorkDir\bin_$Prog`" -NU`"$WorkDir\dcu_$Prog`" $Prog.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  return (Get-Content $log -Raw -ErrorAction SilentlyContinue)
}
$cl = Compile 'PR' @('MigForm')
$err = @(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' })
Check 'J1 the renamed unit compiles with dcc64 (the control does not: TDstBtn has no Click)' (($cl -match 'BUILD_EXITCODE=0') -and ($err.Count -eq 0)) ($err -join ' | ')

$cl = Compile 'PD' @('DlForm')
$dlLines = @(); $i = 0
foreach ($ln in ((Text 'DlForm.pas') -split "`r`n")) { $i++; if ($ln.Contains('DL_NONE(')) { $dlLines += $i } }
$errAt = @([regex]::Matches($cl, '(?m)DlForm\.pas\((\d+)\)\s*(?:Error|error)') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
Check 'J2 DL_NONE unit does NOT compile' (-not ($cl -match 'BUILD_EXITCODE=0')) $cl
Check 'J3 ... its errors are on exactly the DL_NONE lines' `
  ((($errAt -join ',') -eq ($dlLines -join ',')) -and ($dlLines.Count -eq 2) -and ($cl -match 'DL_NONE')) ("errors at [$($errAt -join ',')], markers at [$($dlLines -join ',')]")

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_migrate_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
