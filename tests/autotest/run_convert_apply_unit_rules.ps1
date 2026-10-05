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
    * #useswap with Old absent makes NO edit (controller ruling R4, 2026-09-30:
      a swap depends on Old); #use stays unconditional.
    * INVARIANT: no uses[] row without an edit that realises it.
    * a unit named both added and removed is KEPT (ADD wins, as the editor's
      ConvRules.Units.NormalizeUnitSets does).
    * an entry inside a {$IF...} region REFUSES the unit (exit 1, file untouched).
    * no sibling .dfm: a book with unit rules runs them (component part
      skipped, 'dfm: none'); a book without unit rules keeps today's exit 1.
    * apply/1 JSON: uses[] {action, unit, section, line, rule}, uses_removed,
      uses_added, component_part.
    * R26 (fix wave): a removal (#unuse, or #useswap's Old) of the unit that
      declares the From type of an instance left UNCONVERTED (skipped, or
      excluded by --only) refuses the unit: '<rule> would leave <N>
      unconverted instance(s) of <Type> -- unit not changed'.

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
# T2f: the refusal is uniform -- apply/1 refused (JSON bool) + reason, and one
# 'REFUSED: <reason>' text line carrying the same reason.
$j  = Json (Apply 'Ifdef.pas' 'swap.rules' @('--apply', '--no-backup', '--format', 'json')).Out
Check 'F6 json --apply: ok=false, refused is the JSON literal true, reason names the conditional region' `
  (($null -ne $j) -and (-not $j.ok) -and ($j.refused -is [bool]) -and ($j.refused -eq $true) -and ($j.reason -match 'conditional') -and `
   ($j.reason -eq $j.error)) ($j | ConvertTo-Json -Compress -Depth 3)
Check 'F7 text: exactly one line, "REFUSED: " + that same reason, and no ERROR: line' `
  (($null -ne $j) -and ($r.Out -match ('(?m)^REFUSED: ' + [regex]::Escape([string]$j.reason) + '\r?$')) -and `
   (@($r.Out -split "`n" | Where-Object { $_ -match '^REFUSED: ' }).Count -eq 1) -and -not ($r.Out -match '(?m)^ERROR:')) $r.Out
Check 'F8 the file is still unchanged after the json --apply' ((Hash 'Ifdef.pas') -eq $hF)
# the same refusal inside a MIXED book (#convert + unit rules, unit WITH a .dfm):
# the unit is refused whole, .pas and .dfm untouched.
$hMp = Hash 'MixIfdef.pas'; $hMd = Hash 'MixIfdef.dfm'
$r  = Apply 'MixIfdef.pas' 'mixifdef.rules' @('--apply', '--no-backup', '--format', 'json')
$j  = Json $r.Out
Check 'F9 mixed book, conditional #unuse entry: exit 1, ok=false, refused=true, reason names it' `
  (($r.Code -eq 1) -and ($null -ne $j) -and (-not $j.ok) -and ($j.refused -eq $true) -and ($j.reason -match 'conditional')) $r.Out
Check 'F10 ... MixIfdef.pas and MixIfdef.dfm are byte-identical' (((Hash 'MixIfdef.pas') -eq $hMp) -and ((Hash 'MixIfdef.dfm') -eq $hMd))
$r  = Apply 'MixIfdef.pas' 'mixifdef.rules' @('--apply', '--no-backup')
Check 'F11 ... text mode prints the REFUSED line' (($r.Code -eq 1) -and ($r.Out -match '(?m)^REFUSED: .*conditional')) $r.Out
# control: a unit rules-only SUCCESS carries refused=false and reason ''
$j  = Json (Apply 'NoOld.pas' 'swap.rules' @('--format', 'json')).Out
Check 'F12 control: success has refused=false (a [bool]) and reason ''''' `
  (($null -ne $j) -and $j.ok -and ($j.refused -is [bool]) -and ($j.refused -eq $false) -and ($j.reason -eq '')) ($j | ConvertTo-Json -Compress -Depth 3)

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

# ---- R4: Old absent -> the swap makes NO edit ------------------------------
$hN = Hash 'NoOld.pas'
$j  = Json (Apply 'NoOld.pas' 'swap.rules' @('--format', 'json')).Out
Check 'N1 swap on a unit without Old: dry run plans nothing (uses_added=0, edits_count=0)' `
  (($null -ne $j) -and $j.ok -and ($j.uses_added -eq 0) -and ($j.uses_removed -eq 0) -and ($j.edits_count -eq 0)) ($j | ConvertTo-Json -Compress -Depth 4)
$r = Apply 'NoOld.pas' 'swap.rules' @('--apply', '--no-backup')
Check 'N2 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'N3 the file is byte-identical' ((Hash 'NoOld.pas') -eq $hN)

# ---- #use on a unit with NO implementation uses creates the clause ---------
$r = Apply 'UseNew.pas' 'use.rules' @('--apply', '--no-backup')
$t = Text 'UseNew.pas'
Check 'U1 --apply exits 0' ($r.Code -eq 0) $r.Out
Check 'U2 an implementation uses clause is created holding the #use unit' `
  ($t.Contains("implementation$CRLF$CRLF" + "uses NewU1;$CRLF$CRLF" + "end.")) $t
Check 'U3 interface untouched' ($t.Contains("uses$CRLF  KeepU;$CRLF")) $t

# ---- I2: a whole-clause removal on a SHARED line is performed, not only reported
# The invariant first, on a dry run: a uses[] row always has an edit behind it.
foreach ($shape in @(@('TrailComment.pas','unuse.rules'), @('OneLine.pas','unuse.rules'), @('SwapPresent.pas','swap.rules'))) {
  $j = Json (Apply $shape[0] $shape[1] @('--format', 'json')).Out
  Check "V1 $($shape[0]): uses_removed=1 is backed by at least one edit (no phantom row)" `
    (($null -ne $j) -and $j.ok -and ($j.uses_removed -eq 1) -and ($j.edits_count -ge 1)) ($j | ConvertTo-Json -Compress -Depth 4)
}
$r = Apply 'TrailComment.pas' 'unuse.rules' @('--apply', '--no-backup')
$t = Text 'TrailComment.pas'
Check 'V2 clause with a trailing comment: exit 0, OldU gone, the comment kept' `
  (($r.Code -eq 0) -and -not ($t -match '\bOldU\b') -and $t.Contains("implementation$CRLF$CRLF // legacy$CRLF")) $t
$r = Apply 'OneLine.pas' 'unuse.rules' @('--apply', '--no-backup')
$t = Text 'OneLine.pas'
Check 'V3 "implementation uses OldU;" on one line: the clause goes, the keyword stays' `
  (($r.Code -eq 0) -and $t.Contains("implementation$CRLF$CRLF" + "end.") -and -not ($t -match '\bOldU\b')) $t
$r = Apply 'SwapPresent.pas' 'swap.rules' @('--apply', '--no-backup')
$t = Text 'SwapPresent.pas'
Check 'V4 swap whose News are all present: the Old-only clause is removed, nothing added' `
  (($r.Code -eq 0) -and -not ($t -match '\bOldU\b') -and (([regex]::Matches($t, '\bNewU1\b')).Count -eq 1) -and `
   $t.Contains("implementation$CRLF$CRLF // retired$CRLF"))  $t

# ---- I3: quote literals and a multi-line string before the uses clause -----
$r = Apply 'Quotes.pas' 'unuse.rules' @('--apply', '--no-backup')
$t = Text 'Quotes.pas'
Check "Q1 '''' / '''' + '''' / '''''' and a multi-line string holding 'implementation uses OldU;': exit 0" ($r.Code -eq 0) $r.Out
Check 'Q2 the REAL implementation clause lost OldU; the string content is untouched' `
  ($t.Contains("uses$CRLF  OtherU;$CRLF") -and $t.Contains("    implementation uses OldU;$CRLF")) $t

$r = Apply 'Quote1.pas' 'unuse.rules' @('--apply', '--no-backup')
$t = Text 'Quote1.pas'
Check "Q3 the reviewer's repro: const Q = '''''''' alone before the uses -- exit 0, OldU removed" (($r.Code -eq 0) -and $t.Contains("uses$CRLF  OtherU;$CRLF")) ($r.Out + $t)

# ---- lexer / layout shapes -------------------------------------------------
$r = Apply 'DotSpace.pas' 'dotunuse.rules' @('--apply', '--no-backup')
$t = Text 'DotSpace.pas'
Check 'S1 a space-padded dotted entry (Dot   .OldD) matches #unuse Dot.OldD and is removed' `
  (($r.Code -eq 0) -and $t.Contains("uses$CRLF  KeepU, OtherU;$CRLF")) $t
$r = Apply 'ParenComments.pas' 'swap.rules' @('--apply', '--no-backup')
$t = Text 'ParenComments.pas'
Check 'S2 (* *) comments between entries survive a removal (pinned exact text)' `
  (($r.Code -eq 0) -and $t.Contains("uses$CRLF  KeepU (* a *),  (* b *)OtherU, NewU1, NewU2;$CRLF")) $t
$hT = Hash 'Truncated.pas'
$r  = Apply 'Truncated.pas' 'unuse.rules' @('--apply', '--no-backup')
Check 'S3 a uses clause cut off at EOF is REFUSED (exit 1, "could not read"), file unchanged' `
  (($r.Code -eq 1) -and ($r.Out -match 'could not read the interface uses clause') -and ((Hash 'Truncated.pas') -eq $hT)) $r.Out

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

# ---- R26: a removal never takes away a unit an UNCONVERTED instance needs ---
# --only filters instances, never unit rules, so '#unuse LibA' with btnTwo left
# out would leave 'btnTwo: TSrcBtn' with LibA gone (E2003). The declaring unit
# comes from the index (LibA.pas declares TSrcBtn), not from the name.
$R26Unuse = '#unuse LibA would leave 1 unconverted instance(s) of TSrcBtn -- unit not changed'
$hRp = Hash 'R26Form.pas'; $hRd = Hash 'R26Form.dfm'
$r = Apply 'R26Form.pas' 'r26unuse.rules' @('--only', 'btnOne', '--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'R1 --only btnOne + #unuse LibA: exit 1, ok=false, refused=true, reason names the rule, count and type' `
  (($r.Code -eq 1) -and ($null -ne $j) -and (-not $j.ok) -and ($j.refused -eq $true) -and ($j.reason -eq $R26Unuse)) $r.Out
$r = Apply 'R26Form.pas' 'r26unuse.rules' @('--only', 'btnOne', '--apply', '--no-backup')
Check 'R2 text: one REFUSED line with the same reason, no ERROR: line' `
  (($r.Code -eq 1) -and ($r.Out -match ('(?m)^REFUSED: ' + [regex]::Escape($R26Unuse) + '\r?$')) -and -not ($r.Out -match '(?m)^ERROR:')) $r.Out
$r = Apply 'R26Form.pas' 'r26swap.rules' @('--only', 'btnOne', '--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'R3 --only btnOne + #useswap LibA -> LibB: refused, the reason spells the swap rule' `
  (($r.Code -eq 1) -and ($null -ne $j) -and ($j.refused -eq $true) -and `
   ($j.reason -eq '#useswap LibA -> LibB would leave 1 unconverted instance(s) of TSrcBtn -- unit not changed')) $r.Out
$r = Apply 'R26Form.pas' 'r26unuse.rules' @('--only', 'btnNone', '--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'R4 --only matching nothing (unit rules run alone, skipped-no-instances): refused for BOTH instances' `
  (($r.Code -eq 1) -and ($null -ne $j) -and ($j.refused -eq $true) -and `
   ($j.reason -eq '#unuse LibA would leave 2 unconverted instance(s) of TSrcBtn -- unit not changed')) $r.Out
Check 'R5 R26Form.pas and R26Form.dfm are byte-identical after R1-R4' (((Hash 'R26Form.pas') -eq $hRp) -and ((Hash 'R26Form.dfm') -eq $hRd))
$r = Apply 'R26Other.pas' 'r26other.rules' @('--only', 'btnOne', '--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
$t = Text 'R26Other.pas'
Check 'R6 an UNRELATED #unuse OldU beside an unconverted TSrcBtn still applies (OldU gone, LibA kept)' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and ($j.refused -eq $false) -and ($j.uses_removed -eq 1) -and `
   -not ($t -match '\bOldU\b') -and ($t -match '\bLibA\b') -and ($t -match 'btnTwo: TSrcBtn;')) $r.Out
$r = Apply 'R26Form.pas' 'r26unuse.rules' @('--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
$t = Text 'R26Form.pas'
Check 'R7 positive control: every instance converted, #unuse LibA applies (exit 0, LibA gone)' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and (@($j.converted).Count -eq 2) -and -not ($t -match '\bLibA\b') -and ($t -match '\bLibB\b')) $r.Out

# ---- the backup path (default --apply) still works on a unit-rules-only run -
$r = Apply 'Keep2U.pas' 'use.rules' @('--apply')
Check 'K1 default --apply (backup + provenance stamp) exits 0' ($r.Code -eq 0) $r.Out
Check 'K2 a .BCK backup was written' (@(Get-ChildItem $WorkDir -Filter 'Keep2U.pas.BCK*').Count -ge 1)

# ---- (j) the converted units compile against the stubs --------------------
[IO.File]::WriteAllText((P 'P.dpr'), (@(
  'program P;', '', 'uses', '  SwapIntf, SwapImpl, AlreadyHas, Multiline, LastEntry, NoOld, AddWins, Keep2U, IfdefNeighbour,', '  UseNew, TrailComment, OneLine, SwapPresent, Quotes, Quote1, DotSpace, ParenComments;', '',
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
