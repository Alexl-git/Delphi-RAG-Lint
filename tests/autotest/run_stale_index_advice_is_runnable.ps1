<#
  run_stale_index_advice_is_runnable.ps1 -- the engine must not advise a command
  it refuses.

  WHY THIS EXISTS. 5e4d6c6 made a FOLDER target invalid against a PROJECT
  database (owner ruling: a folder target is valid only for a Library DB). The
  shared C:\Projects\CLAUDE.md, README.md and --help were all corrected in the
  same session. The engine's own RUNTIME ADVICE STRINGS were not, so:

    drag-lint query ... --db <projectDb>
      -> "Answers may be stale -- refresh with: drag-lint index <dir> --db <db>"
    drag-lint index <dir> --db <projectDb>
      -> "ERROR: refusing to index a FOLDER into a PROJECT database."   exit 2

  An operator who follows the advice gets an error. This fires on every stale
  read of every project database, which is the common case: a project index goes
  stale the moment a member unit is saved.

  The DOCS-IN-SYNC RULE covers --help, README.md and docs\AI-USAGE.md. It does
  not cover Writeln advice, which is why this drifted silently.

  WHAT IS ASSERTED
    A. POSITIVE CONTROL -- a folder into a project DB is still refused (exit 2).
       Without this the suite would pass against a build that simply deleted the
       refusal, which is the opposite of the fix.
    B. POSITIVE CONTROL -- a folder into a LIBRARY DB is still allowed. The fix
       must not become a blanket ban.
    C. --resolve-only is EXEMPT from the refusal. It skips the walk entirely
       (CLI.pas), so it cannot adopt loose files as scope: the harm the refusal
       prevents is structurally absent. MEASURED refused before the fix.
    D. The staleness note printed for a PROJECT db advises `index --project`,
       not the folder form.
    E. The staleness note printed for a LIBRARY db still advises the folder form.
    F. A single FILE target is allowed AND does not restamp the DB's scan_type.

  ON THE -wal SIDECAR. schema_meta.scan_type is written late and can live in the
  SQLite write-ahead log, so a DB copied WITHOUT its -wal/-shm sidecars silently
  reports no scan_type and is NOT refused. The first draft of this suite copied
  the .sqlite alone and its positive control did not fire. Copy the sidecars, or
  build the DB in place -- this suite does the latter.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$Exe = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-advice-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$src  = Join-Path $root 'src'
New-Item -ItemType Directory -Force -Path $src | Out-Null

# --- a two-unit project, plus a loose non-member unit in the same folder -----
$crlf = "`r`n"
function WriteAscii($path, $lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join $crlf) + $crlf), (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $src 'uAlpha.pas') @(
  'unit uAlpha;', 'interface', 'procedure AlphaGo;', 'implementation',
  'procedure AlphaGo; begin end;', 'end.')
WriteAscii (Join-Path $src 'uBeta.pas') @(
  'unit uBeta;', 'interface', 'procedure BetaGo;', 'implementation', 'uses uAlpha;',
  'procedure BetaGo; begin AlphaGo; end;', 'end.')
WriteAscii (Join-Path $src 'uLoose.pas') @(
  'unit uLoose;', 'interface', 'procedure LooseGo;', 'implementation',
  'procedure LooseGo; begin end;', 'end.')
WriteAscii (Join-Path $src 'Demo.dpr') @(
  'program Demo;', 'uses uAlpha in ''uAlpha.pas'', uBeta in ''uBeta.pas'';',
  'begin', '  BetaGo;', 'end.')

$projDb = Join-Path $root 'proj.sqlite'
$libDb  = Join-Path $root 'lib.sqlite'

function Run([string[]]$xs) {
  $o = & $Exe @xs 2>&1 | Out-String
  [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}

# Build both databases IN PLACE (never copied -- see the -wal note above).
$r = Run @('index','--project',(Join-Path $src 'Demo.dpr'),'--db',$projDb)
Check 'setup: project DB built' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('index',$src,'--db',$libDb)
Check 'setup: library DB built' ($r.Code -eq 0) "exit $($r.Code)"

# NOTE ON HOW scan_type IS OBSERVED HERE. No verb prints schema_meta values, so
# the stamp is asserted BEHAVIOURALLY: assertion A (a folder is refused) is only
# possible when the stamp reads `project`, and assertion B (a folder is allowed)
# only when it does not. They are the scan_type checks, not merely uses of it.

# --- A. POSITIVE CONTROL: folder into a project DB is still refused ----------
$r = Run @('index',$src,'--db',$projDb)
Check 'A POSITIVE CONTROL: folder into a PROJECT db is refused' `
  (($r.Code -eq 2) -and ($r.Out -match 'refusing to index a FOLDER')) "exit $($r.Code)"

# --- B. POSITIVE CONTROL: folder into a library DB is still allowed ----------
$r = Run @('index',$src,'--db',$libDb)
Check 'B POSITIVE CONTROL: folder into a LIBRARY db is allowed' `
  (($r.Code -eq 0) -and ($r.Out -notmatch 'refusing to index a FOLDER')) "exit $($r.Code)"

# --- C. --resolve-only is exempt (RED before the fix: measured exit 2) -------
$r = Run @('index',$src,'--db',$projDb,'--resolve-only')
Check 'C --resolve-only into a PROJECT db is NOT refused' `
  (($r.Code -eq 0) -and ($r.Out -notmatch 'refusing to index a FOLDER')) "exit $($r.Code)"

# --- C2. the exemption must not COST the stamp --------------------------------
# A --resolve-only run walks nothing, so it establishes no scope and must not
# write scan_type. It took the FOLDER target's shape and restamped the project
# database as `library`, which silently disarmed the refusal -- the exemption
# above opened that path, and this assertion is what found it.
$r = Run @('index',$src,'--db',$projDb)
Check 'C2 scan_type SURVIVES a --resolve-only run (folder still refused)' `
  (($r.Code -eq 2) -and ($r.Out -match 'refusing to index a FOLDER')) "exit $($r.Code)"

# --- the staleness note: make a member stale, then read ---------------------
Start-Sleep -Milliseconds 1100
$alpha = Join-Path $src 'uAlpha.pas'
WriteAscii $alpha @('unit uAlpha;', 'interface', 'procedure AlphaGo;', 'procedure AlphaTwo;',
                    'implementation', 'procedure AlphaGo; begin end;',
                    'procedure AlphaTwo; begin end;', 'end.')

function StalenessNote($db) {
  $o = (Run @('query','--name','AlphaGo','--db',$db)).Out
  $line = ($o -split "`r?`n" | Where-Object { $_ -match 'Answers may be stale' }) -join ' '
  return $line
}
$pNote = StalenessNote $projDb
$lNote = StalenessNote $libDb
Check 'setup: a staleness note is emitted for the project db' ($pNote -ne '') $pNote
Check 'setup: a staleness note is emitted for the library db' ($lNote -ne '') $lNote

# --- D. project DB is advised the project form (RED: says "index <dir>") ----
Check 'D the PROJECT staleness note advises `index --project`' `
  ($pNote -match 'index --project') $pNote
Check 'D the PROJECT staleness note does NOT advise the folder form' `
  ($pNote -notmatch 'index <dir>') $pNote

# --- E. library DB keeps the folder form ------------------------------------
Check 'E the LIBRARY staleness note still advises the folder form' `
  ($lNote -match 'index <dir>') $lNote

# --- F. a single FILE target must not restamp the DB either -----------------
# `index <member.pas> --db <projectDb>` is the ordinary incremental move after
# editing a unit, and it is deliberately NOT refused -- it cannot widen a scope.
# But it is not project-scoped either, so it fell to the `library` arm of the
# stamp writer and restamped the project database as a library one, disarming
# the refusal exactly as the --resolve-only path did. Found by review, not by
# this suite, which is why it is now in it.
$r = Run @('index',(Join-Path $src 'uAlpha.pas'),'--db',$projDb)
Check 'F a single FILE target into a PROJECT db is allowed' `
  (($r.Code -eq 0) -and ($r.Out -notmatch 'refusing to index a FOLDER')) "exit $($r.Code)"
$r = Run @('index',$src,'--db',$projDb)
Check 'F2 scan_type SURVIVES a single-FILE index (folder still refused)' `
  (($r.Code -eq 2) -and ($r.Out -match 'refusing to index a FOLDER')) "exit $($r.Code)"

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
