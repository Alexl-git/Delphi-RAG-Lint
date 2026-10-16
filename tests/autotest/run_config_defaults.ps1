<#
  run_config_defaults.ps1 -- the run defaults of a dotted .drag-lint.json
  ("rule", "watch", "docs") are keys of _D-RAG\config.json, and the CWD's
  .drag-lint.json stays out of a run anchored in a configured repository
  (E3b items 2 and 3, 2026-10-14).

  THE GAPS.
    2. config.json had no home for "rule", "watch" {"interval"} and the docs
       capture keys ("captureLooseComments", "allowBlankLineGap",
       "implPrecedence"), so a configured repository could not set them at all:
       E3a stops reading .drag-lint.json there.
    3. LoadConfigDefaults runs inside ParseArgs, before the run's anchor exists,
       so it looked for config.json above the CWD only. A run started OUTSIDE
       the repository with its path / --db / --project inside it still took a
       .drag-lint.json from the CWD -- while every other loader, anchored on the
       path, answered from config.json.

  SEMANTICS (the same as the dotted file's; flags still win):
    "rule"   narrows `lint` only, announced on stderr; other verbs ignore it with
             a note;
    "watch"  {"interval": N} turns `index` into the watch loop;
    "docs"   the three capture keys sit in config.json's "docs" object, beside
             the manifest's own docs knobs.
  db / project / path are NOT config.json defaults: its "projects" answer those.
  Outside a configured repository nothing changes.

  CASES (CWD is a scratch folder OUTSIDE the repository, holding a
  .drag-lint.json with "rule": "empty-except"):
    K   CONTROL: an unconfigured folder still takes the CWD's .drag-lint.json
    A   anchor in the repo, no "rule" in config.json -> the CWD file is NOT used <- FIX 3
    R1  "rule" in config.json narrows `lint`, naming config.json               <- FIX 2
    R2  and `lint-all` ignores it with a note naming config.json               <- FIX 2
    D   "docs": {"allowBlankLineGap": 0} -> B has no captured doc              <- FIX 2
    W   "watch": {"interval": 7} -> `index` ticks with interval=7s             <- FIX 2
  RED-CHECK: on the pre-fix exe A, R1, R2, D and W fail; K passes on both.
  Needs python (stdlib sqlite3) for D.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_cfg_defaults_$PID"
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

$py = 'C:\Python314\python.exe'
if (-not (Test-Path $py)) { $pyCmd = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1; if ($pyCmd) { $py = $pyCmd.Source } }
if (-not (Test-Path $py)) {
  Write-Host 'SKIP: run_config_defaults: no python found (C:\Python314, nor on PATH)' -ForegroundColor Yellow
  exit 77
}

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$root  = Join-Path $WorkDir 'repo'
$dhome = Join-Path $root '_D-RAG'
$cfg   = Join-Path $dhome 'config.json'
$cwd   = Join-Path $WorkDir 'outside'
$plain = Join-Path $WorkDir 'plain'

$sample = @'
unit sample;
interface
type
  TX = class
    // loose preceding doc
    procedure A;

    // loose doc with gap

    procedure B;
  end;
implementation
procedure TX.A;
begin
  try
  except
  end;
end;
procedure TX.B; begin end;
end.
'@
Write-Ascii (Join-Path $root 'src\sample.pas') $sample
Write-Ascii (Join-Path $plain 'sample.pas') $sample
Write-Ascii (Join-Path $cwd '.drag-lint.json') '{ "rule": "empty-except" }'

function Set-Config([string]$extra) {
  Write-Ascii $cfg ('{ "version": 1, "projects": []' + $extra + ' }')
}

function Run([string[]]$argv) {
  Push-Location $cwd
  try {
    $out = & $Exe @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
  } finally { Pop-Location }
}

$pyDoc = Join-Path $WorkDir 'doc.py'
[System.IO.File]::WriteAllText($pyDoc, @"
import sqlite3, sys
c = sqlite3.connect('file:%s?mode=ro' % sys.argv[1], uri=True)
for n, s in c.execute("SELECT s.name, COALESCE(d.summary,'') FROM symbols s LEFT JOIN symbol_docs d ON d.symbol_id = s.id WHERE s.name IN ('A','B') ORDER BY s.name"):
    print('%s|%s' % (n, s))
c.close()
"@, [System.Text.Encoding]::ASCII)

Write-Host ''
Write-Host 'run_config_defaults -- .drag-lint.json defaults in config.json, anchored like every other loader' -ForegroundColor Cyan

Write-Host ''
Write-Host 'K -- CONTROL: outside any configured repository the CWD .drag-lint.json still applies' -ForegroundColor Cyan
$k = Run @('lint', (Join-Path $plain 'sample.pas'))
Check 'K the CWD file narrows lint, as before' ($k.Text -match 'narrowed to rule "empty-except" by the "rule" key in .*\.drag-lint\.json') $k.Text

Write-Host ''
Write-Host 'A -- a run anchored in a configured repository does not take the CWD file' -ForegroundColor Cyan
Set-Config ''
$a = Run @('lint', (Join-Path $root 'src\sample.pas'))
Check 'A no narrowing from the CWD .drag-lint.json' (-not ($a.Text -match '\.drag-lint\.json')) $a.Text

Write-Host ''
Write-Host 'R1 -- "rule" in config.json narrows lint' -ForegroundColor Cyan
Set-Config ', "rule": "empty-except"'
$r1 = Run @('lint', (Join-Path $root 'src\sample.pas'))
Check 'R1 the note names config.json' ($r1.Text -match 'narrowed to rule "empty-except" by the "rule" key in .*_D-RAG\\config\.json') $r1.Text

Write-Host ''
Write-Host 'R2 -- and lint-all ignores it, saying so' -ForegroundColor Cyan
$db = Join-Path $dhome 'adhoc.sqlite'
Push-Location $cwd; try { & $Exe index (Join-Path $root 'src') --db $db 2>&1 | Out-Null } finally { Pop-Location }
$r2 = Run @('lint-all', '--db', $db)
Check 'R2 the ignore note names config.json' ($r2.Text -match 'ignoring "rule": "empty-except" in .*_D-RAG\\config\.json') $r2.Text

Write-Host ''
Write-Host 'D -- "docs": {"allowBlankLineGap": 0} reaches the indexer' -ForegroundColor Cyan
Set-Config ', "docs": { "captureLooseComments": true, "allowBlankLineGap": 0 }'
$dDb = Join-Path $dhome 'docs.sqlite'
Push-Location $cwd; try { & $Exe index (Join-Path $root 'src\sample.pas') --db $dDb 2>&1 | Out-Null } finally { Pop-Location }
$rows = (& $py $pyDoc $dDb 2>&1 | Out-String)
Check 'D A keeps its adjacent loose doc' ($rows -match '(?m)^A\|loose preceding doc') $rows
Check 'D B has NO doc (the gap of 0 is honoured)' ($rows -match '(?m)^B\|\s*$') $rows

Write-Host ''
Write-Host 'W -- "watch": {"interval": 7} turns index into the watch loop' -ForegroundColor Cyan
Set-Config ', "watch": { "interval": 7 }'
$wOut = Join-Path $WorkDir 'watch.out'
$wDb  = Join-Path $dhome 'watch.sqlite'
$p = Start-Process -FilePath $Exe -ArgumentList @('index', "`"$(Join-Path $root 'src\sample.pas')`"", '--db', "`"$wDb`"") `
       -WorkingDirectory $cwd -RedirectStandardOutput $wOut -RedirectStandardError (Join-Path $WorkDir 'watch.err') `
       -PassThru -WindowStyle Hidden
$ticked = $false
for ($t = 0; $t -lt 60 -and -not $p.HasExited; $t++) {
  Start-Sleep -Milliseconds 500
  if ((Test-Path $wOut) -and ((Get-Content $wOut -Raw -ErrorAction SilentlyContinue) -match 'interval=7s')) { $ticked = $true; break }
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $p.WaitForExit(5000) | Out-Null }
if (-not $ticked -and (Test-Path $wOut)) { $ticked = ((Get-Content $wOut -Raw) -match 'interval=7s') }
Check 'W index ticks with interval=7s' $ticked ((Get-Content $wOut -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up.
  foreach ($d23 in @("C:\TEMP\draglint_cfg_defaults_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
