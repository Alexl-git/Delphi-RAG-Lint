<#
  run_convert_apply_migrate_type.ps1 -- 1.38 (owner ruling D2, 2026-10-28):
  `#migrate Old -> New[, Unit]` renames a TYPE / identifier in the .pas code,
  file-scope or inside a #convert block (INBOX converter-to-engine-migrate-type,
  Q1 MISSING).

  THE CONTRACT this guard pins:
    * RENAME: every bare identifier token Old in code (var / param / field /
      result types, a cast, `is` / `as`, a generic argument) becomes New;
      comments and string literals are untouched; items[] migrate-applied.
    * ENUM MEMBERS: a type migrate whose From and To are enums maps each
      member by the name AFTER the lowercase prefix (scoWait -> scnWait),
      never by ordinal; an explicit `#migrate scoBusy -> scnHourGlass` line
      overrides the name match (scnBusy). An unmatched member used in the
      .pas is a migrate-check warning and is left as written.
    * TARGET: New must resolve in the library or project index; one that does
      not is a migrate-check warning per site and no rename.
    * TRUST THE SOURCE: an Old that resolves nowhere (TGoneOld) is still
      renamed.
    * QUALIFIED: `Unit.Old` is a migrate-check warning, not rewritten.
    * USES: the unit declaring New is added (interface uses when a site is in
      the interface).
    * NEVER SILENT: every site of a #migrate identifier is an applied item or
      a warning.
    * The same rules inside the #convert block give the same plan.
    * POSITIVE CONTROL: the book without #migrate changes no Old token.
    * The applied unit compiles with dcc64 (CvLib, CvNew, CvUse).

  Fixtures: tests\autotest\fixtures\migrate_type, COPIED to a $PID scratch
  folder and indexed there. Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_migrate_type_$PID",
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
Copy-Item (Join-Path $PSScriptRoot 'fixtures\migrate_type\*') $WorkDir

function P([string]$n) { return (Join-Path $WorkDir $n) }
function Text([string]$n) { return [IO.File]::ReadAllText((P $n), [Text.Encoding]::ASCII) }
$orig = @{}
foreach ($f in 'CvUse.pas', 'CvUse.dfm', 'CvWarn.pas', 'CvWarn.dfm') { $orig[$f] = [IO.File]::ReadAllBytes((P $f)) }
function Restore { foreach ($k in $orig.Keys) { [IO.File]::WriteAllBytes((P $k), $orig[$k]) } }

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
function Tally($items) { return ((@($items | Group-Object path | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" })) -join ',') }

# applied sites per Old in CvUse: the enum type 9 (field, 2x decl, 2x impl, var,
# 2x generic arg, cast), scoWait 1, scoDefault 2, scoBusy 1, TOldThing 3, TGoneOld 1
$WantUse = 'scoBusy=1,scoDefault=2,scoWait=1,TGoneOld=1,TOldThing=3,TScreenCursorOld=9'

# ---- dry run: file-scope book -------------------------------------------------
$r = Apply 'CvUse.pas' 'type.rules' @('--format', 'json')
$ma = Kinds $r.J 'migrate-applied'
Check 'T1 file-scope dry run: exit 0, JSON parsed' (($r.Code -eq 0) -and ($null -ne $r.J)) $r.Out
Check 'T2 ... migrate-applied per Old (types, enum members by name, explicit override, cast/is/as, generic arg, unresolved From)' `
  ((Tally $ma) -eq $WantUse) (Tally $ma)
Check 'T3 ... scoBusy goes to the EXPLICIT scnHourGlass, never the name match scnBusy' `
  ((@($ma | Where-Object { $_.path -eq 'scoBusy' -and $_.value -eq 'scnHourGlass' }).Count -eq 1) -and (@($ma | Where-Object { $_.value -eq 'scnBusy' }).Count -eq 0)) (($ma | ForEach-Object { "$($_.path)->$($_.value)" }) -join ', ')
Check 'T4 ... scoWait / scoDefault go by name to scnWait / scnDefault' `
  ((@($ma | Where-Object { ($_.path -eq 'scoWait' -and $_.value -eq 'scnWait') -or ($_.path -eq 'scoDefault' -and $_.value -eq 'scnDefault') }).Count -eq 3)) (($ma | ForEach-Object { "$($_.path)->$($_.value)" }) -join ', ')
Check 'T5 ... every applied item has a line and the rule line' ((@($ma | Where-Object { $_.line -le 0 -or $_.rule_line -le 0 }).Count -eq 0) -and ($ma.Count -gt 0)) $r.Out
Check 'T6 ... no migrate-check on the clean unit' ((Kinds $r.J 'migrate-check').Count -eq 0) (((Kinds $r.J 'migrate-check') | ForEach-Object { $_.text }) -join ' | ')
$plan = Tally $ma

# ---- the same rules inside the #convert block --------------------------------
$r = Apply 'CvUse.pas' 'inblock.rules' @('--format', 'json')
$mb = Kinds $r.J 'migrate-applied'
Check 'B1 in-block book: the same migrate-applied plan as file scope' ((Tally $mb) -eq $plan) (Tally $mb)
Check 'B2 ... and no migrate-check (the old "uses units after a member #migrate" refusal is gone)' ((Kinds $r.J 'migrate-check').Count -eq 0) (((Kinds $r.J 'migrate-check') | ForEach-Object { $_.text }) -join ' | ')

# ---- positive control -----------------------------------------------------------
$r = Apply 'CvUse.pas' 'control.rules' @('--format', 'json')
Check 'C1 control dry run: no migrate item of any kind' (($r.Code -eq 0) -and ((Kinds $r.J 'migrate-applied').Count + (Kinds $r.J 'migrate-check').Count -eq 0)) $r.Out
$r = Apply 'CvUse.pas' 'control.rules' @('--apply', '--no-backup')
$t = Text 'CvUse.pas'
Check 'C2 ... --apply keeps every TScreenCursorOld / scoWait / TOldThing token' `
  (($r.Code -eq 0) -and ([regex]::Matches($t, '\bTScreenCursorOld\b').Count -eq 10) -and $t.Contains('  C:= scoWait;') -and $t.Contains('O is TOldThing')) $t
Restore; Reindex

# ---- apply ----------------------------------------------------------------------
$r = Apply 'CvUse.pas' 'type.rules' @('--apply', '--no-backup')
$t = Text 'CvUse.pas'
Check 'A1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'A2 ... field / param / result / var / generic / cast types renamed' `
  ($t.Contains('    FCur: TScreenCursorNew;') -and $t.Contains('    function Cur(P: TScreenCursorNew): TScreenCursorNew;') -and `
   $t.Contains('function TCvUse.Cur(P: TScreenCursorNew): TScreenCursorNew;') -and $t.Contains('  C: TScreenCursorNew;') -and `
   $t.Contains('  L: TList<TScreenCursorNew>;') -and $t.Contains('C:= TScreenCursorNew(1);') -and $t.Contains('L:= TList<TScreenCursorNew>.Create;')) $t
Check 'A3 ... enum literals: scnWait, scnDefault x2, scnHourGlass' `
  ($t.Contains('  C:= scnWait;') -and $t.Contains('if P = scnDefault then') -and $t.Contains('if P = scnHourGlass then C:= scnDefault;')) $t
Check 'A4 ... is / as / cast and the unresolved From TGoneOld renamed' `
  ($t.Contains('if O is TNewThing then Result:= (O as TNewThing).Tag + TNewThing(O).Tag') -and $t.Contains('  G: TNewThing;')) $t
Check 'A5 ... comment and string literal untouched' `
  ($t.Contains('{ TScreenCursorOld in a comment stays }') -and $t.Contains("S:= 'scoWait';") -and $t.Contains('// scoWait in a line comment stays')) $t
Check 'A6 ... no Old token left in code (only the comment one)' ([regex]::Matches($t, '\bTScreenCursorOld\b').Count -eq 1 -and -not ($t -match '\bTOldThing\b|\bTGoneOld\b')) $t
Check 'A7 ... CvNew added to the INTERFACE uses' ($t -match '(?s)interface\s+uses[^;]*\bCvNew\b[^;]*;.*implementation') $t
Check 'A8 ... the #convert field retype still happens' $t.Contains('    F: TNewField;') $t

# ---- idempotence ---------------------------------------------------------------
[IO.File]::WriteAllBytes((P 'CvUse.dfm'), $orig['CvUse.dfm'])
Reindex
$r = Apply 'CvUse.pas' 'type.rules' @('--format', 'json')
Check 'I1 second run: no migrate-applied item' (($r.Code -eq 0) -and ((Kinds $r.J 'migrate-applied').Count -eq 0)) $r.Out

# ---- warnings: unmatched member, unresolvable target, qualified ----------------
$r = Apply 'CvWarn.pas' 'type.rules' @('--format', 'json')
$mc = Kinds $r.J 'migrate-check'
$wl = (Text 'CvWarn.pas') -split "`r`n"
function LineOf([string]$s) { return 1 + [array]::IndexOf($wl, $s) }
Check 'W1 warn dry run: exit 0, JSON parsed' (($r.Code -eq 0) -and ($null -ne $r.J)) $r.Out
Check 'W2 ... unmatched enum member scoOther: a migrate-check on its line' `
  (@($mc | Where-Object { $_.path -eq 'scoOther' -and $_.line -eq (LineOf '  C:= scoOther;') -and $_.field -eq 'warnings' }).Count -eq 1) (($mc | ForEach-Object { "$($_.path)@$($_.line): $($_.text)" }) -join ' | ')
Check 'W3 ... unresolvable target TNoSuchType: a migrate-check on the TOldThing2 site' `
  (@($mc | Where-Object { $_.path -eq 'TOldThing2' -and $_.line -eq (LineOf '  T: TOldThing2;') -and $_.text -match 'TNoSuchType' }).Count -eq 1) (($mc | ForEach-Object { "$($_.path)@$($_.line): $($_.text)" }) -join ' | ')
Check 'W4 ... qualified CvLib.scoWait: a migrate-check, not rewritten' `
  (@($mc | Where-Object { $_.path -eq 'scoWait' -and $_.line -eq (LineOf '  C:= CvLib.scoWait;') }).Count -eq 1) (($mc | ForEach-Object { "$($_.path)@$($_.line): $($_.text)" }) -join ' | ')
Check 'W5 POSITIVE CONTROL: the var type in the same unit IS renamed (1 migrate-applied)' `
  ((Tally (Kinds $r.J 'migrate-applied')) -eq 'TScreenCursorOld=1') (Tally (Kinds $r.J 'migrate-applied'))
$r = Apply 'CvWarn.pas' 'type.rules' @('--apply', '--no-backup')
$t = Text 'CvWarn.pas'
Check 'W6 ... --apply leaves scoOther, TOldThing2 and CvLib.scoWait as written' `
  (($r.Code -eq 0) -and $t.Contains('  C:= scoOther;') -and $t.Contains('  T: TOldThing2;') -and $t.Contains('  C:= CvLib.scoWait;') -and $t.Contains('  C: TScreenCursorNew;')) $t

# ---- compile the applied clean unit -------------------------------------------
function Compile([string]$Prog, [string[]]$Units) {
  [IO.File]::WriteAllText((P "$Prog.dpr"), (@("program $Prog;", '', 'uses', ('  ' + ($Units -join ', ') + ';'), '', 'begin', 'end.') -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
  New-Item -ItemType Directory (P "bin_$Prog"), (P "dcu_$Prog") -Force | Out-Null
  $bat = P "compile_$Prog.bat"; $log = P "compile_$Prog.log"
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$WorkDir`"",
    "dcc64 -Q -B -NSSystem -E`"$WorkDir\bin_$Prog`" -NU`"$WorkDir\dcu_$Prog`" $Prog.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  return (Get-Content $log -Raw -ErrorAction SilentlyContinue)
}
$cl = Compile 'PT' @('CvLib', 'CvNew', 'CvUse')
$err = @(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' })
Check 'J1 the applied unit compiles with dcc64' (($cl -match 'BUILD_EXITCODE=0') -and ($err.Count -eq 0)) ($err -join ' | ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_migrate_type_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
