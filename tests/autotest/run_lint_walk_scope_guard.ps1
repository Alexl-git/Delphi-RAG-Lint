<#
  run_lint_walk_scope_guard.ps1 -- `lint <dir> --fix` must not WRITE to files no
  project compiles, while `lint <file> --fix` must still fix any file it is
  pointed at.

  WHY THIS EXISTS
  ---------------
  `lint <dir>` is a DIRECTORY WALK: TLinter.LintFolder globs *.pas/*.dpr/*.dpk
  and lints whatever it finds. `lint-all` has TWO filters for exactly this
  (TOwnRoots, and --project which was added after 989 of 1414 findings turned out
  to come from source no project compiles). The per-file verb has neither.

  That was tolerable while `lint <dir>` only REPORTED -- a finding on a dead file
  is noise a human filters. It stopped being tolerable when the same verb grew
  `--fix --apply`, because the output became an EDIT.

  Measured on ORM3 CLIENT (2026-08-31): 200 files in the compile closure, 284
  .pas/.dpr on disk under CLIENT\, so 84 -- 30% -- outside it, among them
  `Blueprint4 - Copy.pas` and three `*_DELETE_SOON.pas`. A retired copy silently
  diverging from the original it was copied from is worse than leaving it alone.

  THE TWO HALVES, AND WHY BOTH ARE NEEDED
  ---------------------------------------
  Only the WALK is filtered. An explicit `lint <file>` is the user POINTING at
  something, and that path has to keep working on a file no index covers at all
  -- which is exactly what the IDE does when it lints an unsaved buffer through
  --stand-in-for. A guard that checked only the skip would pass against a build
  that had simply broken per-file autofix, so control 3 is not decoration.

  FINDINGS ARE NOT FILTERED, only edits. The reported count must be identical
  with and without the scoping, or a shipped number moved silently.

  HOW THE FIXTURE PUTS A FILE OUTSIDE THE CLOSURE: the manifest section targets
  a .dpr, which makes it a PROJECT section, and a project index is exactly the
  compile closure. OutOfClosure.pas sits in the same folder and is referenced by
  nobody, so the walk finds it and the index does not -- the real shape, not a
  simulation of it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-walkscope"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAscii([string]$Path, [string]$Text) {
  $t = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $t, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory (Join-Path $WorkDir 'src') | Out-Null

# A self-assignment in each: fixable, and its fix DELETES the line, so applying
# it to the wrong file is visible rather than subtle.
$unitBody = @'
unit {NAME};
interface
procedure Touch;
implementation
procedure Touch;
var X: Integer;
begin
  X := 1;
  X := X;
  Writeln(X);
end;
end.
'@
WriteAscii (Join-Path $WorkDir 'src\InClosure.pas')    ($unitBody -replace '\{NAME\}', 'InClosure')
WriteAscii (Join-Path $WorkDir 'src\OutOfClosure.pas') ($unitBody -replace '\{NAME\}', 'OutOfClosure')
WriteAscii (Join-Path $WorkDir 'src\Proj.dpr') @'
program Proj;
uses
  InClosure in 'InClosure.pas';
begin
  Touch;
end.
'@

$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecWalk", "db": "walk.sqlite", "include": ["src/Proj.dpr"] } ] }' + [char]10 +
  '}'
WriteAscii $manifest $mtext
$db = Join-Path $WorkDir 'out\walk.sqlite'

Push-Location C:\TEMP
try { & $Exe index --all --config $manifest --only SecWalk --jobs 1 2>&1 | Out-Null } finally { Pop-Location }
if (-not (Test-Path $db)) { Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }

# PRECONDITION. If both files landed in the index the fixture proves nothing --
# it would be testing a walk with nothing outside it.
Push-Location C:\TEMP
try { $idx = (& $Exe sql --query "SELECT path FROM files" --db $db 2>$null | Out-String) } finally { Pop-Location }
Check 'SETUP: InClosure.pas IS in the compile closure'     ($idx -match 'InClosure\.pas') ''
Check 'SETUP: OutOfClosure.pas is NOT in the closure' `
  (-not ($idx -match 'OutOfClosure\.pas')) `
  'if it were indexed, every assertion below would be vacuous'

function RunLint([string[]]$ExtraArgs, [string]$Tag) {
  $o = Join-Path $WorkDir "$Tag.out"
  $e = Join-Path $WorkDir "$Tag.err"
  $null = Start-Process -FilePath $Exe -ArgumentList $ExtraArgs -WorkingDirectory 'C:\TEMP' `
            -Wait -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  return [pscustomobject]@{
    Out = [System.IO.File]::ReadAllText($o)
    Err = [System.IO.File]::ReadAllText($e)
  }
}

Write-Host ''
Write-Host 'CONTROL 1 -- the WALK skips the out-of-closure file, and SAYS so' -ForegroundColor Cyan
$walk = RunLint @('lint', (Join-Path $WorkDir 'src'), '--db', $db, '--fix') 'walk'
Check 'WALK: an edit is still produced for the in-closure unit' `
  ($walk.Out -match 'InClosure\.pas') 'the filter must not disarm autofix entirely'
Check 'WALK: NO edit is produced for the out-of-closure unit' `
  (-not ($walk.Out -match '(?m)^File: .*OutOfClosure\.pas')) `
  'this is the whole point -- a walk must not write to code no project compiles'
Check 'WALK: the skip is REPORTED, not silent' `
  ($walk.Err -match 'were NOT rewritten') `
  'a silent skip is indistinguishable from a broken autofix'
Check 'WALK: and it names the file it skipped' `
  ($walk.Err -match 'skipped: .*OutOfClosure\.pas') ''

Write-Host ''
Write-Host 'CONTROL 2 -- REPORTING is untouched (no shipped count moved)' -ForegroundColor Cyan
# The scoping drops EDITS, never findings. Two independent proofs, because the
# first version of this control asserted the wrong STREAM: with --fix the output
# is the fix PLAN, not the per-finding listing, so it failed against a build that
# was behaving correctly.
#
# (a) the fixable COUNT still includes the out-of-closure file. Two findings
#     counted, one file edited -- which is precisely the intended asymmetry.
Check 'REPORT: the fixable count still counts BOTH files' `
  ($walk.Out -match '(?m)^autofix: 2 fixable finding') `
  ('a count of 1 would mean findings were filtered too: ' +
   (($walk.Out -split "`n" | Where-Object { $_ -match 'autofix:' }) -join ' '))
# (b) plain `lint <dir>` -- no --fix at all -- still reports both files.
$plain = RunLint @('lint', (Join-Path $WorkDir 'src'), '--db', $db) 'plain'
Check 'REPORT: a plain lint still reports the out-of-closure file' `
  ($plain.Out -match 'OutOfClosure\.pas:\d+:\d+') `
  'filtering findings would silently change a number people depend on'
Check 'REPORT: and reports the in-closure file too' `
  ($plain.Out -match 'InClosure\.pas:\d+:\d+') ''

Write-Host ''
Write-Host 'CONTROL 3 -- an EXPLICIT file target is NEVER filtered' -ForegroundColor Cyan
# Without this, a build that had simply broken per-file autofix would pass
# control 1. It is also the IDE's path: --stand-in-for lints a temp snapshot
# that no index can possibly contain.
$one = RunLint @('lint', (Join-Path $WorkDir 'src\OutOfClosure.pas'), '--db', $db, '--fix') 'one'
Check 'EXPLICIT: pointing at the very same file DOES offer the fix' `
  ($one.Out -match 'OutOfClosure\.pas') `
  'the user naming a file is a different act from the tool finding it'
Check 'EXPLICIT: and nothing is reported as skipped' `
  (-not ($one.Err -match 'were NOT rewritten')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
