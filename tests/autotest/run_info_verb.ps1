# run_info_verb.ps1 -- drag-lint info --json emits info/1 with the required self-info fields
# Usage: pwsh -File tests/autotest/run_info_verb.ps1 [-Exe <path>]
param(
  [string]$Exe = (Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe')
)
$ErrorActionPreference = 'Stop'
$exe = $Exe
$fail = 0
function Check($c,$m){ if(-not $c){Write-Host "FAIL: $m";$script:fail++}else{Write-Host "PASS: $m"} }

$json = & $exe info --json
$o = $json | ConvertFrom-Json
Check ($o.schema -eq 'info/1') 'schema is info/1'
Check ($o.name -eq 'drag-lint') 'name is drag-lint'
Check ($o.version -and $o.version.Length -ge 3) 'version present'
Check ($o.license -eq 'MIT') 'license is MIT'
Check ($o.build_date -match '^\d{4}-\d{2}-\d{2}') 'build_date looks like a date'
Check ($null -ne $o.tree_sitter) 'tree_sitter block present'

# --- K20: the grammar DLL must be identifiable from `info` alone ---------------
# `delphi13`/`dfm` are tree-sitter ABI numbers. They read 14 for every grammar at
# that ABI and do not move when a grammar is rebuilt, which is how a SIX-WEEK DLL
# drift produced a whole false bug report against a parser that was not the one
# running, and why T4c needed a parse-fixture harness instead of a version check.
# These fields are the ones that move. Asserted, not printed: a stamp nobody
# checks is the same as no stamp.
Check ($o.tree_sitter.dll_delphi13 -and $o.tree_sitter.dll_delphi13 -ne 'not loaded' -and $o.tree_sitter.dll_delphi13 -ne 'unknown') `
  'tree_sitter.dll_delphi13 names a loaded module'
Check ($o.tree_sitter.dll_dfm -and $o.tree_sitter.dll_dfm -ne 'not loaded' -and $o.tree_sitter.dll_dfm -ne 'unknown') `
  'tree_sitter.dll_dfm names a loaded module'
# Shape: '<path>  yyyy-mm-dd hh:mm:ss  N bytes'. The DATE and the SIZE are the
# whole point -- a stamp that carried only a path would be as inert as the ABI
# number it exists to replace.
foreach ($k in @('dll_delphi13','dll_dfm')) {
  $v = $o.tree_sitter.$k
  Check ($v -match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') "tree_sitter.$k carries an mtime"
  Check ($v -match '\s\d+ bytes$') "tree_sitter.$k carries a byte size"
  $p = ($v -split '\s\s')[0]
  Check (Test-Path -LiteralPath $p) "tree_sitter.$k path resolves to a real file ($p)"
}
Check ($o.tree_sitter.abi_note -match 'ABI') 'tree_sitter.abi_note says these numbers are ABI versions'
Check ($null -ne $o.capabilities) 'capabilities block present'
Check ($o.exe_path -and (Test-Path $o.exe_path)) 'exe_path resolves to a real file'
Check ($o.platform -eq 'Win64' -or $o.platform -eq 'Win32') 'platform is Win32|Win64'

# text form (no --json) must also work and not error
$txt = & $exe info
Check ($LASTEXITCODE -eq 0) 'info (text) exits 0'
Check ($txt -match 'MIT') 'text form mentions MIT'
# K20: the text form must LABEL the number as an ABI, not as a grammar version.
# The old label ('tree-sitter: delphi13 14') is what was misread for six weeks.
Check ((($txt -join "`n") -match 'tree-sitter ABI:') -and (($txt -join "`n") -match 'NOT a grammar version')) `
  'text form labels the tree-sitter number as an ABI version'
Check ((($txt -join "`n") -match '(?m)^\s+delphi13 dll:.*\d{4}-\d{2}-\d{2}.*bytes')) `
  'text form prints the delphi13 DLL stamp'

# --- 1.20.4 T3: `info --db` is honoured in TEXT mode too ------------------------
# Until 1.20.4 the per-index verdict block lived inside the --json branch only, so
# `info --db X` without --json printed the self-info block and silently dropped
# the question it was asked. The text form must name each --db path, carry the
# SAME verdict the JSON form computes (one routine, not two copies of the rule),
# and print the remedy line when the verdict owes one.
# The index is built with an explicit --db under TEMP, from a TEMP working dir,
# so no manifest-selected project DB can be written.
$wd = Join-Path $env:TEMP "draglint_info_verb_$PID"
try {
  if (Test-Path -LiteralPath $wd) { [IO.Directory]::Delete($wd, $true) }
  New-Item -ItemType Directory -Force -Path $wd | Out-Null
  $W = { param($p, $s) [IO.File]::WriteAllText($p, (($s -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }
  & $W (Join-Path $wd 'uA.pas') "unit uA;`ninterface`nprocedure Go;`nimplementation`nprocedure Go;`nbegin`nend;`nend.`n"
  & $W (Join-Path $wd 'App.dpr') "program App;`nuses`n  uA in 'uA.pas';`nbegin`nend.`n"
  $db      = Join-Path $wd 'App.sqlite'
  $missing = Join-Path $wd 'NoSuch.sqlite'
  Push-Location $wd
  try {
    & $exe index --project (Join-Path $wd 'App.dpr') --db $db 2>&1 | Out-Null
    Check (Test-Path -LiteralPath $db) 'FIXTURE: scratch index built with explicit --db'

    function JsonIdx([string[]]$dbs) {
      $a = @('info', '--json'); foreach ($d in $dbs) { $a += @('--db', $d) }
      $j = (& $exe @a 2>$null) -join "`n"
      $i = $j.IndexOf('{'); if ($i -lt 0) { return @() }
      return @(($j.Substring($i) | ConvertFrom-Json).indexes)
    }
    function TextOut([string[]]$dbs) {
      $a = @('info'); foreach ($d in $dbs) { $a += @('--db', $d) }
      return ((& $exe @a 2>$null) -join "`n")
    }

    # current + missing in ONE call: --db is repeatable in text mode as in JSON.
    $jr = JsonIdx @($db, $missing)
    $t  = TextOut @($db, $missing)
    Check ($LASTEXITCODE -eq 0) 'info --db (text) exits 0'
    Check (($jr.Count -eq 2) -and ($jr[0].verdict -eq 'current') -and ($jr[1].verdict -eq 'missing')) `
      "FIXTURE: JSON verdicts are current/missing (got '$($jr[0].verdict)'/'$($jr[1].verdict)')"
    Check ($t -match ('(?m)^index: ' + [regex]::Escape($db) + '  verdict: ' + [regex]::Escape([string]$jr[0].verdict) + '\s*$')) `
      "text names the built index with the JSON verdict '$($jr[0].verdict)'"
    Check ($t -match ('(?m)^index: ' + [regex]::Escape($missing) + '  verdict: ' + [regex]::Escape([string]$jr[1].verdict) + '\s*$')) `
      "text names the absent index with the JSON verdict '$($jr[1].verdict)'"
    Check ($t -notmatch '(?m)^\s+remedy:') 'text prints no remedy line when no verdict owes one'
    Check ((TextOut @()) -notmatch '(?m)^index: ') 'CONTROL: without --db the text form prints no index line'

    # A verdict that OWES a remedy: plant an OLDER resolver stamp (needs sqlite3).
    if (Get-Command python -ErrorAction SilentlyContinue) {
      $rfp = [string]$jr[0].resolver_fingerprint
      $py = Join-Path $wd 'exec.py'
      [IO.File]::WriteAllText($py, "import sqlite3,sys`nc=sqlite3.connect(sys.argv[1])`nc.execute(sys.argv[2])`nc.commit();c.close()`n", [Text.Encoding]::ASCII)
      $old = $rfp -replace '^r=[^;]+;', 'r=0.0.1-alpha;'
      & python $py $db "UPDATE schema_meta SET value='$old' WHERE key='resolver_fingerprint'" | Out-Null
      $jo = JsonIdx @($db)
      $to = TextOut @($db)
      Check (($jo.Count -eq 1) -and ($jo[0].verdict -eq 'resolve-owed') -and $jo[0].remedy) `
        "FIXTURE: planted older resolver stamp reads resolve-owed with a remedy (got '$($jo[0].verdict)')"
      Check ($to -match ('(?m)^index: ' + [regex]::Escape($db) + '  verdict: resolve-owed\s*$')) `
        'text carries the resolve-owed verdict'
      Check ($to -match ('(?m)^\s+remedy: ' + [regex]::Escape([string]$jo[0].remedy) + '\s*$')) `
        'text prints the SAME remedy the JSON form reports'
    } else {
      Write-Host 'SKIP: python not on PATH -- the remedy-line assertions need sqlite3'
    }
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $wd) { Remove-Item -LiteralPath $wd -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($fail){Write-Host "RESULT: FAIL ($fail)";exit 1}else{Write-Host 'RESULT: PASS';exit 0}
