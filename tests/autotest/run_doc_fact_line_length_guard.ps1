<#
  run_doc_fact_line_length_guard.ps1 -- the doc engine never writes a fact line
  the compiler rejects, and a stored one that is too long is drift (1.20.5,
  Task 3).

  WHY. dcc 37.0 rejects a source line with F2069 "Line too long (more than 1023
  characters)". MEASURED 2026-09-30 (dcc64 37.0, comment and code lines alike):
  the limit depends on WHERE the line sits. The compiler reads the file in 4 KB
  blocks; a line that crosses a block boundary fails at 1021 characters, a line
  inside one block compiles up to its end (4095 at offset 0). So 1020 is the
  only length that compiles wherever the line lands, and a longer line is a
  build that breaks when an edit ABOVE it moves it across a boundary. The
  inbound lists of a reconciliation block are uncapped by design, so they grow
  past that. Owner ruling 2026-09-29: break such a line at entry boundaries,
  ONLY when it is over DOC_FACT_MAX_COLS (1000); a line within it is written
  byte-identical to before.

  ARMS
    E1  a `dl:shared ProjA, ProjB` Shared.pas with `procedure Target;` and a
        caller unit of 200 routines C001..C200, each calling Target, in one
        .dpr. index + document --apply -> every line of Shared.pas <= 1000,
        and the folded `Called from:` list holds 200 entries (POSITIVE
        CONTROL: a capped or empty render would pass the length check).
    E2  the fixture compiles with dcc64 into a private dir: BUILD_EXITCODE=0,
        no F2069, no Error/Fatal.
    E4  fixed point: after a reindex a second document --apply leaves the file
        hash unchanged. (Run before E3, which rewrites the file.)
    E3  REVIEW FOCUS 1 -- a stored line ALREADY over the limit (written by
        1.20.4 or earlier). E1's wrapped `Called from:` range is replaced by
        ONE physical line with the same content; drift compares
        whitespace-collapsed text, so without the length rule it would call
        the block current and never rewrite it. lint --rule doc-drift reports
        it; --fix --fix-rule doc-drift --apply rewrites it so every line
        <= 1000; a second lint reports 0.
    E3b the boundary, width only: line 1 padded with blanks (collapsed away by
        the content compare) to exactly 1000 is current, to 1001 is drift.
    E5  every tracked *.pas / *.dpr / *.inc under src\ and tests\ has no line
        over 1020 characters (the measured position-independent limit).

  Explicit --db everywhere; nothing touches a real project database.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fact-line-length-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ownWorkDir = -not $PSBoundParameters.ContainsKey('WorkDir')
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
$Exe  = (Resolve-Path $Exe).Path
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path

$dllSrc = "$repo\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

# The limits this guard holds. FACT_MAX mirrors DOC_FACT_MAX_COLS in
# DRagLint.Doc.Regions; DCC_SAFE is the measured position-independent limit.
$FACT_MAX = 1000
$DCC_SAFE = 1020
$CALLERS  = 200

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force -LiteralPath $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$db     = Join-Path $WorkDir 'e.sqlite'
$shared = Join-Path $WorkDir 'Shared.pas'
$dpr    = Join-Path $WorkDir 'E.dpr'

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Run([string[]]$xs) { $o = & $Exe @xs 2>&1 | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
# stdout only: lint --json is a bare JSON array there, and its notes go to stderr.
function RunJson([string[]]$xs) { (& $Exe @xs 2>$null | Out-String) }
function LastLine([string]$s) { ($s.Trim() -split "`n" | Select-Object -Last 1) }
function MaxLineLen([string]$Path) {
  $m = 0; foreach ($l in [IO.File]::ReadAllLines($Path)) { if ($l.Length -gt $m) { $m = $l.Length } }; return $m
}
# The physical range [first, last] of the `Called from:` fact in $Lines.
function CalledFromRange([string[]]$Lines) {
  $f = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '<para>Called from:') { $f = $i; break } }
  if ($f -lt 0) { return @(-1, -1) }
  for ($j = $f; $j -lt $Lines.Count; $j++) { if ($Lines[$j] -match '</para>') { return @($f, $j) } }
  return @($f, -1)
}
# The LOGICAL `Called from:` fact: its physical lines, prefix stripped, joined by one blank.
function CalledFromLogical([string[]]$Lines) {
  $r = CalledFromRange $Lines
  if ($r[1] -lt 0) { return '' }
  $parts = @($Lines[$r[0]])
  for ($k = $r[0] + 1; $k -le $r[1]; $k++) { $parts += ($Lines[$k] -replace '^\s*///\s?', '') }
  return ($parts -join ' ')
}
function EntryCount([string]$Logical) {
  if ($Logical -notmatch 'Called from: (.*?)</para>') { return 0 }
  return @($Matches[1] -split ', ' | Where-Object { $_.Trim() -ne '' }).Count
}
function DriftFindings([string]$Json) {
  try { return ,@(ConvertFrom-Json $Json | Where-Object { $_.rule -eq 'doc-drift' }) } catch { return $null }
}

# --- fixture ------------------------------------------------------------------
Write-Ascii $shared @'
unit Shared;   // dl:shared ProjA, ProjB

interface

procedure Target;

implementation

procedure Target;
begin
end;

end.
'@
$decls = (1..$CALLERS | ForEach-Object { 'procedure C{0:D3};' -f $_ }) -join "`n"
$impls = (1..$CALLERS | ForEach-Object { 'procedure C{0:D3}; begin Target; end;' -f $_ }) -join "`n"
Write-Ascii (Join-Path $WorkDir 'Caller.pas') "unit Caller;`n`ninterface`n`n$decls`n`nimplementation`n`nuses Shared;`n`n$impls`n`nend.`n"
Write-Ascii $dpr "program E;`n`n{`$APPTYPE CONSOLE}`n`nuses Shared in 'Shared.pas', Caller in 'Caller.pas';`n`nbegin`nend.`n"

Write-Host 'fact line length' -ForegroundColor Cyan

# ------------------------------------------------------------------ E1 --------
$r = Run @('index', '--project', $dpr, '--db', $db)
Check 'setup: fixture indexed' (($r.Code -eq 0) -and (Test-Path $db)) (LastLine $r.Out)
$r = Run @('document', '--unit', $shared, '--db', $db, '--apply', '--no-backup')
Check 'E1: document --apply ran' ($r.Code -eq 0) (LastLine $r.Out)
$lines = [IO.File]::ReadAllLines($shared)
$logical = CalledFromLogical $lines
$n = EntryCount $logical
Check "E1: POSITIVE CONTROL -- the folded Called from list holds $CALLERS entries" ($n -eq $CALLERS) "$n entries"
Check "E1: POSITIVE CONTROL -- the logical list is longer than $DCC_SAFE characters" ($logical.Length -gt $DCC_SAFE) "$($logical.Length) chars"
Check "E1: every line of Shared.pas is <= $FACT_MAX characters" ((MaxLineLen $shared) -le $FACT_MAX) "max $(MaxLineLen $shared)"
$rg = CalledFromRange $lines
Check 'E1: the list is written over more than one line' (($rg[1] -gt $rg[0]) -and ($rg[0] -ge 0)) "lines $($rg[0])..$($rg[1])"

# ------------------------------------------------------------------ E2 --------
$bat = Join-Path $WorkDir 'compile.bat'
$log = Join-Path $WorkDir 'compile.log'
New-Item -ItemType Directory (Join-Path $WorkDir 'bin'), (Join-Path $WorkDir 'dcu') | Out-Null
$batLines = @(
  '@echo off'
  "call `"$RsVars`""
  "cd /d `"$WorkDir`""
  "dcc64 -Q -E`"$WorkDir\bin`" -NU`"$WorkDir\dcu`" E.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
)
[IO.File]::WriteAllText($bat, ($batLines -join "`r`n"), [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
$cl = Get-Content $log -Raw -ErrorAction SilentlyContinue
$errLines = @(($cl -split "`r?`n") | Where-Object { $_ -match 'F2069|Error|Fatal' })
Check 'E2: the documented fixture compiles (dcc64)' (($cl -match 'BUILD_EXITCODE=0') -and ($errLines.Count -eq 0)) ($errLines -join ' | ')

# ------------------------------------------------------------------ E4 --------
$null = Run @('index', '--project', $dpr, '--db', $db)
$h = (Get-FileHash $shared).Hash
$r = Run @('document', '--unit', $shared, '--db', $db, '--apply', '--no-backup')
Check 'E4: a second document --apply is a no-op' ((Get-FileHash $shared).Hash -eq $h) (LastLine $r.Out)

# ------------------------------------------------------------------ E3 --------
# The shape 1.20.4 wrote: the same content, one physical line.
$lines = [IO.File]::ReadAllLines($shared)
$rg = CalledFromRange $lines
if ($rg[1] -gt $rg[0]) {
  $one  = CalledFromLogical $lines
  $long = @()
  if ($rg[0] -gt 0) { $long += $lines[0..($rg[0] - 1)] }
  $long += $one
  if ($rg[1] -lt $lines.Count - 1) { $long += $lines[($rg[1] + 1)..($lines.Count - 1)] }
  Write-Ascii $shared (($long -join "`n") + "`n")
}
Check "E3: setup -- the stored list is ONE line over $DCC_SAFE characters" ((MaxLineLen $shared) -gt $DCC_SAFE) "max $(MaxLineLen $shared)"
$null = Run @('index', '--project', $dpr, '--db', $db)
$fs = DriftFindings (RunJson @('lint', $shared, '--db', $db, '--rule', 'doc-drift', '--project-rules', '--json'))
Check 'E3: lint --rule doc-drift reports the over-long stored line' (($null -ne $fs) -and ($fs.Count -ge 1)) ("{0} finding(s): {1}" -f @($fs).Count, ((@($fs) | ForEach-Object { $_.message }) -join ' | '))
$r = Run @('lint', '--file', $shared, '--db', $db, '--project-rules', '--fix', '--fix-rule', 'doc-drift', '--apply', '--no-backup')
Check "E3: --fix rewrites it so every line is <= $FACT_MAX" ((MaxLineLen $shared) -le $FACT_MAX) "max $(MaxLineLen $shared); $(LastLine $r.Out)"
Check "E3: the rewritten list still holds $CALLERS entries" ((EntryCount (CalledFromLogical ([IO.File]::ReadAllLines($shared)))) -eq $CALLERS) ''
$null = Run @('index', '--project', $dpr, '--db', $db)
$fs = DriftFindings (RunJson @('lint', $shared, '--db', $db, '--rule', 'doc-drift', '--project-rules', '--json'))
Check 'E3: a second lint --rule doc-drift reports 0' (($null -ne $fs) -and ($fs.Count -eq 0)) ("{0} finding(s)" -f @($fs).Count)

# ----------------------------------------------------------------- E3b -------
# The boundary, width only: blanks padded after the first ', ' of line 1 are
# collapsed away by the content compare, so only the physical width differs.
# Exactly DOC_FACT_MAX_COLS is current; one more character is drift.
function PadLine1([int]$Width) {
  $ls = [IO.File]::ReadAllLines($shared)
  $rg = CalledFromRange $ls
  $l1 = $ls[$rg[0]] -replace ',\s+', ', '
  $at = $l1.IndexOf(', ') + 2
  $ls[$rg[0]] = $l1.Substring(0, $at) + (' ' * ($Width - $l1.Length)) + $l1.Substring($at)
  Write-Ascii $shared (($ls -join "`n") + "`n")
  $null = Run @('index', '--project', $dpr, '--db', $db)
  return $ls[$rg[0]].Length
}
$w  = PadLine1 $FACT_MAX
$fs = DriftFindings (RunJson @('lint', $shared, '--db', $db, '--rule', 'doc-drift', '--project-rules', '--json'))
Check "E3b: a stored line of exactly $FACT_MAX characters is current" (($w -eq $FACT_MAX) -and ($null -ne $fs) -and ($fs.Count -eq 0)) "width $w, $(@($fs).Count) finding(s)"
$w  = PadLine1 ($FACT_MAX + 1)
$fs = DriftFindings (RunJson @('lint', $shared, '--db', $db, '--rule', 'doc-drift', '--project-rules', '--json'))
Check "E3b: a stored line of $($FACT_MAX + 1) characters is drift" (($w -eq $FACT_MAX + 1) -and ($null -ne $fs) -and ($fs.Count -eq 1)) "width $w, $(@($fs).Count) finding(s)"
# ------------------------------------------------------------------ E5 --------
# Tracked sources only (git ls-files): scratch and build output are not the
# product. No exclusions today; a fixture that is long ON PURPOSE is excluded
# BY NAME here, with its reason.
$exclude = @()
$tracked = @(git -C $repo ls-files -- 'src/*.pas' 'src/*.dpr' 'src/*.inc' 'tests/*.pas' 'tests/*.dpr' 'tests/*.inc')
$over = @()
foreach ($f in $tracked) {
  if ($exclude -contains $f) { continue }
  $i = 0
  foreach ($l in [IO.File]::ReadAllLines((Join-Path $repo $f))) {
    $i++
    if ($l.Length -gt $DCC_SAFE) { $over += ('{0}:{1} ({2} chars)' -f $f, $i, $l.Length) }
  }
}
Check "E5: POSITIVE CONTROL -- the tree scan saw the tracked sources" ($tracked.Count -gt 100) "$($tracked.Count) files"
Check "E5: no tracked source line is over $DCC_SAFE characters" ($over.Count -eq 0) ($over -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'run_doc_fact_line_length_guard: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_doc_fact_line_length_guard: OK' -ForegroundColor Green
exit 0
} finally {
  if ($ownWorkDir -and (Test-Path -LiteralPath $WorkDir)) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
