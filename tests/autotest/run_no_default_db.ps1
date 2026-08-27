<#
  run_no_default_db.ps1 -- a verb with no resolvable database must FAIL LOUDLY,
  never silently adopt (or create) one in the current directory.

  Why this exists
  ---------------
  ParseArgs used to seed every run with

      Result.DbPath := TPath.Combine(GetCurrentDir, 'drag-lint.sqlite')

  a default retired when the _D-RAG layout landed. Two consequences, both
  measured on 2026-08-26:

    * `<repo>\drag-lint.sqlite` REGENERATED during session 40 -- 4 files, 46
      symbols, 126 refs, indexed from a temp fixture folder by a command run
      without --db. It is gitignored, so it was invisible rather than harmless,
      and it OPENS CLEANLY and reports a current schema while answering
      "not mine" for every question asked of it.
    * ~15 already-written `DbPath = ''` guards were DEAD CODE, because DbPath
      was never empty. Among them purge-locals, a DESTRUCTIVE verb whose
      "needs an explicit --db" refusal could not fire.

  TFile.Exists was already tried as the fix and changed nothing: a stray that
  EXISTS passes an existence test. Existence is not sufficiency.

  What is checked, and why each half is here
  ------------------------------------------
  A fix here could pass by making everything silent, so the controls matter as
  much as the assertions:

    1. a planted stray is NOT adopted -- exit 2, and the file is not even
       OPENED (mtime and length unchanged, which a migrate-on-open would move);
    2. `index <folder>` with no --db writes to the folder's own _D-RAG, and does
       NOT create one in the cwd;
    3. CONTROL: an explicit --db still answers -- the fix must not have worked
       by breaking database access generally;
    4. CONTROL: purge-locals with no --db now refuses -- a guard that was dead
       demonstrably fires.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RealDb  = "$PSScriptRoot\..\..\src\cli\_D-RAG\drag-lint.sqlite",
  [string]$WorkDir = "$env:TEMP\draglint_no_default_db"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host '== no default database in the cwd ==' -ForegroundColor Cyan
$Exe    = (Resolve-Path $Exe).Path
$RealDb = (Resolve-Path $RealDb).Path

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
@'
unit uDecoy;
interface
type
  TDecoy = class
    procedure DecoyMethod;
  end;
implementation
procedure TDecoy.DecoyMethod;
begin
end;
end.
'@ | Set-Content -LiteralPath (Join-Path $srcDir 'uDecoy.pas') -Encoding Ascii

function Run-In([string]$cwd, [string[]]$argv, [int]$timeoutSec = 90) {
  $o = Join-Path $WorkDir 'out.txt'; $e = Join-Path $WorkDir 'err.txt'
  $p = Start-Process $Exe -ArgumentList $argv -WorkingDirectory $cwd `
         -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit($timeoutSec * 1000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ Code = -1; Text = 'TIMEOUT' } }
  $t = ((Get-Content $o -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content $e -Raw -ErrorAction SilentlyContinue))
  return [pscustomobject]@{ Code = $p.ExitCode; Text = $t }
}

# --- plant a stray in the cwd ------------------------------------------------
$stray = Join-Path $WorkDir 'drag-lint.sqlite'
$plant = Run-In $WorkDir @('index', $srcDir, '--db', $stray)
Check 'a stray database could be planted (explicit --db still works)' `
  (Test-Path $stray) "exit=$($plant.Code)"
if (-not (Test-Path $stray)) { Write-Host 'FATAL: could not plant a stray'; exit 1 }
$before = Get-Item $stray

# --- 1. the stray must NOT be adopted ---------------------------------------
$q = Run-In $WorkDir @('query', '--name', 'DecoyMethod')
Check 'a verb with no resolvable --db exits non-zero' ($q.Code -ne 0) "exit=$($q.Code)"
# NOT asserted: that this prints a resolve-dbs hint. A consumer with no --db
# legitimately AUTO-SELECTS from the manifest (resolve-dbs from this very cwd
# lists every configured project DB), so demanding an error here would mean
# breaking that. The guarantee that matters is the next two checks: the stray is
# not among what it consults, and it is not the source of any answer.
$rd = Run-In $WorkDir @('resolve-dbs', '--platform', 'win64')
Check 'the stray is NOT among the databases a consumer would open' `
  (-not ($rd.Text -match [regex]::Escape($stray))) "resolve-dbs listed it"
Check 'it does NOT answer from the stray' `
  (-not ($q.Text -match 'DecoyMethod\s')) "output: $($q.Text.Trim())"
$after = Get-Item $stray
Check 'the stray was not even OPENED (length and mtime unchanged)' `
  (($before.Length -eq $after.Length) -and ($before.LastWriteTimeUtc -eq $after.LastWriteTimeUtc)) `
  "len $($before.Length)->$($after.Length)"

# --- 2. index with no --db goes to the target's own _D-RAG ------------------
$scan = Join-Path $WorkDir 'scanme'
New-Item -ItemType Directory -Force -Path $scan | Out-Null
Copy-Item (Join-Path $srcDir 'uDecoy.pas') (Join-Path $scan 'uDecoy.pas')
$cwd2 = Join-Path $WorkDir 'elsewhere'
New-Item -ItemType Directory -Force -Path $cwd2 | Out-Null
$null = Run-In $cwd2 @('index', $scan)
Check 'index with no --db wrote into the target folder _D-RAG' `
  (Test-Path (Join-Path $scan '_D-RAG')) "expected $scan\_D-RAG"
Check 'index with no --db did NOT create a database in the cwd' `
  (-not (Test-Path (Join-Path $cwd2 'drag-lint.sqlite'))) "cwd was $cwd2"

# --- 3. CONTROL: an explicit --db still answers -----------------------------
$ok = Run-In $WorkDir @('query', '--name', 'DecoyMethod', '--db', $stray)
Check 'control: an explicit --db still answers' `
  (($ok.Code -eq 0) -and ($ok.Text -match 'DecoyMethod')) "exit=$($ok.Code) output: $($ok.Text.Trim())"

# --- 4. CONTROL: a dead guard on a DESTRUCTIVE verb now fires ---------------
$pl = Run-In $WorkDir @('purge-locals')
Check 'control: purge-locals with no --db refuses (its guard was dead code)' `
  ($pl.Code -ne 0) "exit=$($pl.Code) output: $($pl.Text.Trim())"

Write-Host ''
if ($script:Failed) { Write-Host 'NO DEFAULT DB GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'NO DEFAULT DB GUARD: PASS' -ForegroundColor Green
exit 0
