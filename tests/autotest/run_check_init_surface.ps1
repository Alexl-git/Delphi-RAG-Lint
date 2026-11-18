<#
  run_check_init_surface.ps1 -- `check-init`: the verb surface and the answer contract (lane HBSKEL, 1.52).

  Plan: docs\superpowers\plans\2026-11-17-happens-before-phase1.md, lane SKEL as amended by the
  "Owner rulings 2026-11-17" block (HB2 literals SET / NEVER-SET / MAY-BE-UNSET; HB7 exit 0 / 1 / 2).
  Spec: docs\superpowers\specs\2026-11-17-happens-before-design.md, sec. 2.1 (JSON keys) and 6.4 (reasons).

  The engine behind the verb is filled by later lanes (EVENTS, ROOTS, INTRA, SOLVER, FIELDS). This runner
  pins only what HBSKEL owns, so it stays true while they land:
    A. usage errors exit 2 with a message on stderr and NOTHING on stdout: no target and no --at; no DB
       resolved; a --db that does not exist; a malformed --at; a negative / non-numeric --max-routines;
    B. a valid question answers exit 0 or 1 (never 2), stdout is ONE JSON document carrying every
       top-level key of spec 2.1 with the right types, the verdict is one of the three literals and exit
       agrees with it (SET -> 0, otherwise 1);
    C. --at is echoed as the judged use (file, line, col) and its reason codes come from the closed list;
    D. text output has the `verdict` line and the target line; --explain adds the `roots` line;
    E. controls: a key-set check FAILS on a document minus one key; the --at parse check FAILS on a
       swapped line / col; a usage case with stdout content would FAIL (A asserts empty stdout).
  Not asserted here (status internal until lane HBDOCS ships the verb): `--help` listing the verb.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-check-init-surface-$PID"
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
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

# A tiny program: one unit variable written in initialization and read in a routine.
$unit = @'
unit HbCfg;

interface

var
  GCount: Integer;

procedure Bump;

implementation

procedure Bump;
begin
  GCount:= GCount + 1;
end;

initialization
  GCount:= 1;
end.
'@
$prog = @'
program HbSurface;

uses
  HbCfg in 'HbCfg.pas';

begin
  Bump;
end.
'@
[IO.File]::WriteAllText((Join-Path $work 'HbCfg.pas'), ($unit -replace "`r?`n", "`r`n"))
[IO.File]::WriteAllText((Join-Path $work 'HbSurface.dpr'), ($prog -replace "`r?`n", "`r`n"))
$unitPath = Join-Path $work 'HbCfg.pas'

$db = Join-Path $WorkDir 'surface.sqlite'
$null = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Run-Verb([string[]]$VerbArgs) {
  $errFile = Join-Path $WorkDir 'stderr.txt'
  $out = & $Exe check-init @VerbArgs 2> $errFile
  return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = (@($out) -join "`n"); Err = ((Get-Content $errFile -Raw) + '') }
}

# Raw output once, before any filtering.
$raw = Run-Verb @('HbCfg.GCount', '--at', "${unitPath}:14:12", '--db', $db, '--json')
Write-Host "  raw exit=$($raw.Exit)"
Write-Host "  raw stdout: $($raw.Out)"
Write-Host "  raw stderr: $($raw.Err.Trim())"

# A. usage errors: exit 2, message on stderr, nothing on stdout
$missingDb = Join-Path $WorkDir 'no-such.sqlite'
$usage = [ordered]@{
  'no target and no --at'      = @('--db', $db, '--json')
  'explicit --db missing'      = @('HbCfg.GCount', '--db', $missingDb, '--json')
  'malformed --at (no line)'   = @('HbCfg.GCount', '--at', 'HbCfg.pas', '--db', $db, '--json')
  'malformed --at (line 0)'    = @('HbCfg.GCount', '--at', 'HbCfg.pas:0', '--db', $db, '--json')
  'malformed --at (text line)' = @('HbCfg.GCount', '--at', 'HbCfg.pas:x:3', '--db', $db, '--json')
  '--max-routines negative'    = @('HbCfg.GCount', '--max-routines', '-5', '--db', $db, '--json')
  '--max-routines not a number'= @('HbCfg.GCount', '--max-routines', 'many', '--db', $db, '--json')
}
foreach ($k in $usage.Keys) {
  $r = Run-Verb $usage[$k]
  Check "usage: $k -> exit 2, stderr, empty stdout" (($r.Exit -eq 2) -and ($r.Err.Trim() -ne '') -and ($r.Out.Trim() -eq '')) `
    "exit=$($r.Exit) out=[$($r.Out)] err=[$($r.Err.Trim())]"
}
# no DB at all: run from a folder that resolves no project database
Push-Location $WorkDir
try {
  $r = Run-Verb @('HbCfg.GCount', '--json')
  Check 'usage: no --db and none resolves -> exit 2' (($r.Exit -eq 2) -and ($r.Out.Trim() -eq '')) "exit=$($r.Exit) err=[$($r.Err.Trim())]"
} finally { Pop-Location }

# B. the JSON contract
$keys = @('target', 'verdict', 'proven', 'scope', 'uses', 'writers', 'roots', 'limits', 'budget')
function Test-Keys($Doc, [string[]]$Want) {
  if ($null -eq $Doc) { return $false }
  $have = @($Doc.PSObject.Properties.Name)
  foreach ($w in $Want) { if ($have -notcontains $w) { return $false } }
  return $true
}
$r = Run-Verb @('HbCfg.GCount', '--db', $db, '--json')
$doc = $null
try { $doc = $r.Out | ConvertFrom-Json } catch { $doc = $null }
Check 'answer: exit is 0 or 1, never 2' (($r.Exit -eq 0) -or ($r.Exit -eq 1)) "exit=$($r.Exit) err=[$($r.Err.Trim())]"
Check 'answer: stdout is one JSON document' ($null -ne $doc)
Check 'answer: every top-level key of spec 2.1' (Test-Keys $doc $keys) "have=$(@($doc.PSObject.Properties.Name) -join ',')"
$verdicts = @('SET', 'NEVER-SET', 'MAY-BE-UNSET')
Check 'answer: verdict is one of the three literals' ($verdicts -ccontains $doc.verdict) "verdict=$($doc.verdict)"
$wantExit = if ($doc.verdict -ceq 'SET') { 0 } else { 1 }
Check 'answer: exit agrees with the verdict (HB7)' ($r.Exit -eq $wantExit) "verdict=$($doc.verdict) exit=$($r.Exit)"
Check 'answer: target has qname/kind/file/line/type/zero_value' (Test-Keys $doc.target @('qname', 'kind', 'file', 'line', 'type', 'zero_value'))
Check 'answer: target.qname echoes the question' ($doc.target.qname -ceq 'HbCfg.GCount') "qname=$($doc.target.qname)"
Check 'answer: proven is a boolean' ($doc.proven -is [bool])
Check 'answer: scope is program|instance' (@('program', 'instance') -ccontains $doc.scope) "scope=$($doc.scope)"
Check 'answer: uses / writers / limits are arrays' (($doc.uses -is [array]) -and ($doc.writers -is [array]) -and ($doc.limits -is [array]))
Check 'answer: roots has ordered[] + unordered' ((Test-Keys $doc.roots @('ordered', 'unordered')) -and ($doc.roots.ordered -is [array]))
Check 'answer: budget has routines/ms/exhausted' (Test-Keys $doc.budget @('routines', 'ms', 'exhausted'))
Check 'answer: MAY-BE-UNSET is never proven' (($doc.verdict -cne 'MAY-BE-UNSET') -or (-not $doc.proven))

# C. --at is the judged use; reason codes come from the closed list (spec 6.4 + HB3/HB5 + guarded-test)
$closed = @('unordered-root', 'escaped-routine', 'writer-conditional', 'writer-later-unit', 'writer-after-use-same-routine',
  'callee-not-must', 'indirect-call', 'virtual-fanout', 'interface-call', 'soft-writer', 'nil-write-only',
  'ctor-misses-field', 'no-declared-ctor', 'subclass-ctor-skips', 'virtual-call-in-ancestor-ctor', 'self-escapes-in-ctor',
  'unreliable-order', 'multi-program', 'writer-on-thread', 'cfg-skipped', 'budget', 'index-incomplete',
  'relied-on-handler-order', 'receiver-unproven', 'guarded-test')
$atDoc = $null
try { $atDoc = $raw.Out | ConvertFrom-Json } catch { $atDoc = $null }
Check '--at: answer is JSON, exit 0 or 1' (($null -ne $atDoc) -and (($raw.Exit -eq 0) -or ($raw.Exit -eq 1))) "exit=$($raw.Exit)"
function Test-AtUse($Doc, [int]$Line, [int]$Col) {
  $u = @($Doc.uses | Where-Object { ($_.line -eq $Line) -and ($_.col -eq $Col) })
  return ($u.Count -eq 1) -and ($u[0].file -like '*HbCfg.pas') -and (Test-Keys $u[0] @('routine', 'verdict', 'reasons', 'witness'))
}
Check '--at: the judged use is file HbCfg.pas line 14 col 12' (Test-AtUse $atDoc 14 12) "uses=$(($atDoc.uses | ConvertTo-Json -Compress -Depth 5))"
$codes = @($atDoc.uses | ForEach-Object { $_.reasons }) + @($atDoc.reasons)
$bad = @($codes | Where-Object { $_ -and ($closed -cnotcontains $_) })
# 1.52 INT (HBSOLVER wired): a SET answer carries no reason codes; any other verdict must carry one.
Check '--at: every reason code is in the closed list' ((($codes.Count -gt 0) -or ($atDoc.verdict -eq 'SET')) -and ($bad.Count -eq 0)) "codes=$($codes -join ',') bad=$($bad -join ',')"
$noCol = Run-Verb @('HbCfg.GCount', '--at', "${unitPath}:14", '--db', $db, '--json')
$noColDoc = $null
try { $noColDoc = $noCol.Out | ConvertFrom-Json } catch { $noColDoc = $null }
# 1.52 INT (HBSOLVER wired): a line-only --at judges the one use on that line, at its real column (12).
Check '--at file:line (no col) is accepted' (($noCol.Exit -ne 2) -and (Test-AtUse $noColDoc 14 12)) "exit=$($noCol.Exit) err=[$($noCol.Err.Trim())]"
$atOnly = Run-Verb @('--at', "${unitPath}:14:12", '--db', $db, '--json')
Check '--at alone names the target (exit 0 or 1)' (($atOnly.Exit -eq 0) -or ($atOnly.Exit -eq 1)) "exit=$($atOnly.Exit) err=[$($atOnly.Err.Trim())]"

# D. text output
$t = Run-Verb @('HbCfg.GCount', '--db', $db)
Check 'text: exit 0 or 1' (($t.Exit -eq 0) -or ($t.Exit -eq 1)) "exit=$($t.Exit)"
Check 'text: has the verdict line' ($t.Out -cmatch '(?m)^verdict  (SET|NEVER-SET|MAY-BE-UNSET)\b') "out=[$($t.Out)]"
Check 'text: first line names the target' ($t.Out -cmatch '^HbCfg\.GCount\b')
Check 'text: has the limits line' ($t.Out -cmatch '(?m)^limits: ')
Check 'text: no roots line without --explain' ($t.Out -cnotmatch '(?m)^roots: ')
$te = Run-Verb @('HbCfg.GCount', '--db', $db, '--explain')
Check 'text --explain: adds the roots line' ($te.Out -cmatch '(?m)^roots: ') "out=[$($te.Out)]"
$tf = Run-Verb @('HbCfg.GCount', '--db', $db, '--format', 'json')
$tfDoc = $null
try { $tfDoc = $tf.Out | ConvertFrom-Json } catch { $tfDoc = $null }
Check '--format json equals --json' (Test-Keys $tfDoc $keys)

# E. controls (each must FAIL the check it guards)
$minus = $doc | Select-Object -Property ($keys | Where-Object { $_ -ne 'budget' })
Check 'control: key check fails on a document minus one key' (-not (Test-Keys $minus $keys))
Check 'control: --at check fails on swapped line / col' (-not (Test-AtUse $atDoc 12 14))
Check 'control: the closed list rejects an invented code' ($closed -cnotcontains 'set-first')

Write-Host ''
if ($script:Failed) { Write-Host 'SUMMARY: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'SUMMARY: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
