<#
  run_convert_apply_unit_rules.ps1 -- convert-apply applies a rule book's UNIT
  rules (#unuse / #use / #useswap) to the unit being converted, and info --json
  advertises it as capabilities.apply_unit_rules = true (1.20.6-alpha).

  THE ASK (converter/editor team, INBOX-2026-09-29-converter-to-engine-apply-
  unit-rules). The rule parser has read the three directives since 1.14, but
  nothing on the convert-apply path consumed them: a book of #useswap lines
  (the owner's convrules\M2022Replace.rules) validated, ran, and changed
  nothing. The editor greys such a book out until the capability key is TRUE.

  THE CONTRACT this guard pins (the editor reads exactly this):
    * info --json exit 0; capabilities.apply_unit_rules is the JSON literal true.
    * per unit: remove Old, add each New once (case-insensitive, never a
      duplicate in either section), keep the section Old was in.
    * #use N adds into the IMPLEMENTATION uses (a clause is created if none).
    * #useswap with Old absent adds its News into the implementation uses.
    * a unit named both added and removed is KEPT (ADD wins, as the editor's
      ConvRules.Units.NormalizeUnitSets does).
    * an entry inside a {$IF...} region REFUSES the unit (exit 1, file untouched).
    * no sibling .dfm: a book with unit rules runs them (component part
      skipped, 'dfm: none'); a book without unit rules keeps today's exit 1.
    * apply/1 JSON: uses[] {action, unit, section, line, rule}, uses_removed,
      uses_added, component_part.

  Fixtures live in tests\autotest\fixtures\unitrules and are COPIED to a
  $PID scratch folder, indexed into a scratch --db there. Nothing shared is
  touched. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_unit_rules_$PID",
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
Copy-Item (Join-Path $PSScriptRoot 'fixtures\unitrules\*') $WorkDir

$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db)

function Run([string[]]$ArgList) {
  $o = (& $Exe @ArgList 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function P([string]$n) { return (Join-Path $WorkDir $n) }
function Book([string]$n) { return (Join-Path $WorkDir $n) }
function Text([string]$n) { return [IO.File]::ReadAllText((P $n)) }
function Hash([string]$n) { return (Get-FileHash (P $n)).Hash }
function Apply([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  return Run (@('convert-apply', '--unit', (P $Unit), '--rules', (Book $Rules), '--db', $db) + $Extra)
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
$CRLF = "`r`n"

# ---- (h) info --json advertises the capability as JSON true ----------------
$r = Run @('info', '--json')
$j = Json $r.Out
Check 'H1 info --json exits 0' ($r.Code -eq 0) $r.Out
Check 'H2 capabilities.apply_unit_rules is JSON true (a [bool], value $true)' `
  (($null -ne $j) -and ($j.capabilities.apply_unit_rules -is [bool]) -and ($j.capabilities.apply_unit_rules -eq $true)) `
  "capabilities = $(if ($j) { $j.capabilities | ConvertTo-Json -Compress } else { '<no json>' })"

# ---- (i) dry run: the plan is reported, nothing is written -----------------
$h0 = Hash 'SwapIntf.pas'
$r  = Apply 'SwapIntf.pas' 'swap.rules' @('--format', 'json')
$j  = Json $r.Out
Check 'I1 dry run (json) exits 0 on a unit with NO sibling .dfm' ($r.Code -eq 0) $r.Out
Check 'I2 dry run wrote nothing (hash unchanged)' ((Hash 'SwapIntf.pas') -eq $h0)
Check 'I3 json ok=true, uses_removed=1, uses_added=2' `
  (($null -ne $j) -and $j.ok -and ($j.uses_removed -eq 1) -and ($j.uses_added -eq 2)) $r.Out
$rm  = @($j.uses | Where-Object { $_.action -eq 'remove' })
$add = @($j.uses | Where-Object { $_.action -eq 'add' })
Check 'I4 uses[] remove entry: OldU, interface, line 6, rule text verbatim' `
  (($rm.Count -eq 1) -and ($rm[0].unit -eq 'OldU') -and ($rm[0].section -eq 'interface') -and `
   ($rm[0].line -eq 6) -and ($rm[0].rule -eq '#useswap OldU -> NewU1, NewU2')) ($j.uses | ConvertTo-Json -Compress)
Check 'I5 uses[] add entries: NewU1 then NewU2, both interface' `
  (($add.Count -eq 2) -and ($add[0].unit -eq 'NewU1') -and ($add[1].unit -eq 'NewU2') -and `
   (@($add | Where-Object { $_.section -ne 'interface' }).Count -eq 0)) ($j.uses | ConvertTo-Json -Compress)
Check 'I6 component_part says there was no .dfm' ($j.component_part -eq 'skipped-no-dfm') "component_part=$($j.component_part)"

$r = Apply 'SwapIntf.pas' 'swap.rules'
Check 'I7 text dry run prints one line per uses edit and dfm: none' `
  (($r.Out -match '(?m)^\s+remove OldU \(interface, line 6\) -- #useswap OldU -> NewU1, NewU2$') -and `
   ($r.Out -match '(?m)^\s+add NewU1 \(interface, line 6\)') -and ($r.Out -match '(?m)^\s+add NewU2 \(interface, line 6\)') -and `
   ($r.Out -match 'dfm: none')) $r.Out
Check 'I8 text dry run wrote nothing' ((Hash 'SwapIntf.pas') -eq $h0)

# ---- (a) Old in interface -> both News land in interface -------------------
$r = Apply 'SwapIntf.pas' 'swap.rules' @('--apply', '--no-backup')
$t = Text 'SwapIntf.pas'
Check 'A1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'A2 interface uses is KeepU, NewU1, NewU2 (Old gone, section kept)' `
  ($t.Contains("interface$CRLF$CRLF" + "uses$CRLF  KeepU, NewU1, NewU2;$CRLF")) $t
Check 'A3 implementation uses untouched' ($t.Contains("implementation$CRLF$CRLF" + "uses$CRLF  OtherU;$CRLF")) $t

# ---- (b) Old in implementation -> News land in implementation -------------
$r = Apply 'SwapImpl.pas' 'swap.rules' @('--apply', '--no-backup')
$t = Text 'SwapImpl.pas'
Check 'B1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'B2 implementation uses is OtherU, NewU1, NewU2' ($t.Contains("uses$CRLF  OtherU, NewU1, NewU2;$CRLF")) $t
Check 'B3 interface uses untouched' ($t.Contains("interface$CRLF$CRLF" + "uses$CRLF  KeepU;$CRLF")) $t

# ---- (c) New already in the OTHER section -> not added again ---------------
$r = Apply 'AlreadyHas.pas' 'swap.rules' @('--apply', '--no-backup')
$t = Text 'AlreadyHas.pas'
Check 'C1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'C2 interface uses is KeepU, NewU2 (Old removed, NewU1 NOT re-added)' ($t.Contains("uses$CRLF  KeepU, NewU2;$CRLF")) $t
Check 'C3 NewU1 appears exactly once in the file' (([regex]::Matches($t, '\bNewU1\b')).Count -eq 1) $t

# ---- (d) multi-line clause, a comment and an in '...' path -----------------
$r = Apply 'Multiline.pas' 'swap.rules' @('--apply', '--no-backup')
$t = Text 'Multiline.pas'
Check 'D1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'D2 interface clause keeps its layout and comments, drops the whole in-entry' `
  ($t.Contains("uses$CRLF  KeepU,     // keep me$CRLF  { the old one }$CRLF  OtherU, NewU1, NewU2;$CRLF")) $t
Check 'D3 implementation: the last entry went with its preceding comma' ($t.Contains("uses$CRLF  Keep2U;$CRLF")) $t
Check 'D4 no dangling comma anywhere (, ; / ,; / uses ;)' `
  (-not ($t -match ',\s*;') -and -not ($t -match '(?i)\buses\s*;') -and -not ($t -match "'OldU\.pas'")) $t

# ---- (e) removing the only entry removes the whole clause ------------------
$r = Apply 'LastEntry.pas' 'unuse.rules' @('--apply', '--no-backup')
$t = Text 'LastEntry.pas'
$want = "unit LastEntry;$CRLF$CRLF" + "interface$CRLF$CRLF" + "uses$CRLF  KeepU;$CRLF$CRLF" + `
        "implementation$CRLF$CRLF" + "const$CRLF  LAST_C = 2;$CRLF$CRLF" + "end."
Check 'E1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'E2 the implementation uses clause is gone whole, no blank-line pile-up' ($t -eq $want) "got:`n$t"

# ---- (f) Old inside {$IFDEF} -> refused, file unchanged --------------------
$hF = Hash 'Ifdef.pas'
$r  = Apply 'Ifdef.pas' 'swap.rules' @('--apply', '--no-backup')
Check 'F1 a conditional entry REFUSES the unit (exit 1)' ($r.Code -eq 1) $r.Out
Check 'F2 the refusal names the reason' ($r.Out -match '(?i)conditional') $r.Out
Check 'F3 the file is unchanged' ((Hash 'Ifdef.pas') -eq $hF)

# ---- an UNCONDITIONAL Old beside a conditional neighbour is removed safely --
# The comma Old takes is the one after {$ENDIF} (depth 0); the adds go after
# the last UNCONDITIONAL entry, so they exist whether FOO is defined or not.
$r = Apply 'IfdefNeighbour.pas' 'swap.rules' @('--apply', '--no-backup')
$t = Text 'IfdefNeighbour.pas'
Check 'F4 unconditional Old next to a {$IFDEF} entry: exit 0' ($r.Code -eq 0) $r.Out
Check 'F5 the directive pair is intact and the adds sit outside it' `
  ($t.Contains("uses$CRLF  KeepU, NewU1, NewU2 {`$IFDEF FOO}, OtherU{`$ENDIF};$CRLF")) $t
# ---- (g) no .dfm + a book WITHOUT unit rules keeps today's exit 1 ----------
$r = Apply 'NoOld.pas' 'convertonly.rules'
Check 'G1 #convert-only book on a unit with no .dfm: exit 1' ($r.Code -eq 1) $r.Out
Check 'G2 ... with the unchanged message' ($r.Out -match 'sibling \.dfm not found') $r.Out

# ---- Old absent -> the News go into the implementation uses (created) ------
$r = Apply 'NoOld.pas' 'swap.rules' @('--apply', '--no-backup')
$t = Text 'NoOld.pas'
Check 'N1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'N2 an implementation uses clause is created holding both News' `
  ($t.Contains("implementation$CRLF$CRLF" + "uses NewU1, NewU2;$CRLF$CRLF" + "end.")) $t
Check 'N3 interface untouched' ($t.Contains("uses$CRLF  KeepU;$CRLF")) $t

# ---- ADD wins: a unit both added and removed is kept, not duplicated -------
$hW = Hash 'AddWins.pas'
$r  = Apply 'AddWins.pas' 'addwins.rules' @('--format', 'json')
$j  = Json $r.Out
Check 'W1 ADD-wins book: exit 0, no uses edits (KeepU kept, OtherU already there)' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.uses_removed -eq 0) -and ($j.uses_added -eq 0)) $r.Out
Check 'W2 file unchanged' ((Hash 'AddWins.pas') -eq $hW)

# ---- mixed book (#convert + unit rules) on a unit WITH a .dfm --------------
$r = Apply 'MixForm.pas' 'mixed.rules' @('--apply', '--no-backup')
$t = Text 'MixForm.pas'
Check 'M1 mixed book: exit 0, the instance converted' (($r.Code -eq 0) -and ($r.Out -match '1 instance\(s\) converted')) $r.Out
Check 'M2 LibA swapped out, LibB present EXACTLY once (not added by both the block and the rule)' `
  ((([regex]::Matches($t, '\bLibB\b')).Count -eq 1) -and -not ($t -match '\bLibA\b') -and $t.Contains("uses$CRLF  Classes, LibB;$CRLF")) $t
Check 'M3 the declaration was retyped by the #convert block' ($t -match 'btnTop: TDstBtn;') $t

# ---- the backup path (default --apply) still works on a unit-rules-only run -
$r = Apply 'Keep2U.pas' 'swap.rules' @('--apply')
Check 'K1 default --apply (backup + provenance stamp) exits 0' ($r.Code -eq 0) $r.Out
Check 'K2 a .BCK backup was written' (@(Get-ChildItem $WorkDir -Filter 'Keep2U.pas.BCK*').Count -ge 1)

# ---- (j) the converted units compile against the stubs --------------------
[IO.File]::WriteAllText((P 'P.dpr'), (@(
  'program P;', '', 'uses', '  SwapIntf, SwapImpl, AlreadyHas, Multiline, LastEntry, NoOld, AddWins, Keep2U, IfdefNeighbour;', '',
  'begin', 'end.') -join $CRLF) + $CRLF, [Text.Encoding]::ASCII)
New-Item -ItemType Directory (P 'bin'), (P 'dcu') -Force | Out-Null
$bat = P 'compile.bat'; $log = P 'compile.log'
[IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$WorkDir`"",
  "dcc64 -Q -B -E`"$WorkDir\bin`" -NU`"$WorkDir\dcu`" P.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join $CRLF), [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
$cl = Get-Content $log -Raw -ErrorAction SilentlyContinue
$errLines = @(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' })
Check 'J1 every converted unit compiles with dcc64 (private -E/-NU)' (($cl -match 'BUILD_EXITCODE=0') -and ($errLines.Count -eq 0)) ($errLines -join ' | ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_unit_rules_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
