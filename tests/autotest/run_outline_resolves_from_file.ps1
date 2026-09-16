<#
  run_outline_resolves_from_file.ps1 --
  `outline --file X` must resolve a database the same way `resolve-dbs --in X`
  does. Two verbs answering "which index covers this file" must not disagree.

  THE DEFECT (converter team, reported INDEPENDENTLY TWICE -- their own
  ConvRules.Usage.pas, and ORM3's COMMON\OBJECTS\iFOLDERS.PAS; reproduced here
  2026-09-16):

    resolve-dbs --in ...\iFOLDERS.PAS  -> three databases
    outline --file ...\iFOLDERS.PAS    -> "no project database resolves here"

  Both statements were about the same file at the same moment, and the second
  was the false one. It is the worse kind of false, because it names a REMEDY
  ("pass --db") for a condition that does not hold -- so the reader goes looking
  for a missing index instead of a resolution bug. That is what cost the
  converter team the time to report it twice.

  THE CAUSE. DoOutline resolved only through AArgs.DbPath, which is driven by
  --platform / the cwd / the manifest default and knows nothing about the file
  being read. `resolve-dbs --in` additionally runs a MEMBERSHIP PROBE: it asks
  each candidate index whether it actually contains the file. That probe is what
  finds a unit living outside its own .dproj's folder -- most of ORM3's
  COMMON\, and most of this repo, whose .dproj sits in src\cli and pulls in a
  dozen sibling folders. Outline had no such probe, so for those files it
  resolved nothing and said so confidently.

  THE FIX IS SHARED CODE, NOT A SECOND COPY. Both verbs now call
  ResolveReadDbsForFileWith. The manifest LOAD stays with each caller
  (`resolve-dbs` honours --config and must exit 2 on a bad one); only the
  ordering is shared. This guard asserts the AGREEMENT rather than the
  implementation, so it still fails if someone re-forks the logic.

  Run from any CWD, pwsh 7. Uses the repo's own configured index; SKIPS loudly
  when no manifest resolves here, because a machine with no configured index
  cannot answer the question either way.
#>
[CmdletBinding()]
param(
  [string]$Exe  = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Repo = "$PSScriptRoot\..\.."
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Skip($n,$why){ Write-Host ("[SKIP] {0}" -f $n) -ForegroundColor Yellow; Write-Host "      $why" -ForegroundColor DarkGray }

$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path $Repo).Path

# A unit that lives OUTSIDE the .dproj's own folder is the shape that broke:
# src\cli\drag-lint.dproj pulls in src\lsp\, so folder-based resolution alone
# never covered this file. Picking a same-folder unit would test nothing.
$target = Join-Path $Repo 'src\lsp\DRagLint.LSP.Server.pas'
if (-not (Test-Path $target)) { $target = Join-Path $Repo 'src\core\DRagLint.Core.Indexer.pas' }
Check 'V the probe target exists' (Test-Path $target) $target

# EVERY INVOCATION RUNS FROM A NEUTRAL CWD, and that is the whole test.
#
# The old resolution was driven by --platform / the CURRENT DIRECTORY / the
# manifest default. Run from inside the repo, the cwd alone can resolve this
# repo's own index, so `outline --file <a repo file>` would answer -- and this
# guard would pass against the unfixed build, proving nothing. Run from
# somewhere with no section of its own, cwd resolution yields nothing and the
# only thing that can find the database is the membership probe keyed on the
# FILE. That is exactly the situation the converter team hit: they were asking
# about ORM3 files from a different working directory.
$NeutralCwd = [IO.Path]::GetTempPath()
$tmpO = Join-Path $NeutralCwd ('dl_out_' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.txt')
$tmpE = "$tmpO.err"
function RunOut([string[]]$a) {
  $p = Start-Process -FilePath $script:Exe -ArgumentList $a -NoNewWindow -PassThru `
        -WorkingDirectory $script:NeutralCwd `
        -RedirectStandardOutput $script:tmpO -RedirectStandardError $script:tmpE
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { }; return @{ C = -1; O = '(timed out)' } }
  $o = ((Get-Content -LiteralPath $script:tmpO -Raw -ErrorAction SilentlyContinue) + '') +
       ((Get-Content -LiteralPath $script:tmpE -Raw -ErrorAction SilentlyContinue) + '')
  return @{ C = $p.ExitCode; O = $o }
}

$rd = RunOut @('resolve-dbs','--in',$target)
$rdPaths = @($rd.O -split "`n" | Where-Object { $_ -match '\.sqlite\s*$' })

if ($rdPaths.Count -eq 0) {
  Skip 'T1/T2 outline-vs-resolve-dbs agreement' `
       "resolve-dbs --in resolved NO database for $target on this machine, so there is nothing for outline to agree with. Not counted as a pass."
} else {
  Write-Host ("      [NOTE] resolve-dbs --in resolved {0} database(s)" -f $rdPaths.Count) -ForegroundColor DarkGray

  $ol = RunOut @('outline','--file',$target)

  # T1 is the defect itself: resolve-dbs found databases, so outline must not
  # claim none resolve.
  Check 'T1 outline does NOT claim "no project database resolves here" when resolve-dbs found one' `
        (-not ($ol.O -match 'no project database resolves here')) `
        ("resolve-dbs --in found $($rdPaths.Count) db(s) for the same file:`n" + $ol.O)

  Check 'T2 outline exits 0 and returns symbols for an indexed file' `
        (($ol.C -eq 0) -and ($ol.O -match '(?m)^\s*(unit|type|class|function|procedure|method)\b')) `
        ("exit=$($ol.C)`n" + $ol.O)
}

# ---- T3 DISCRIMINATION CONTROL ---------------------------------------------
# A file in NO index must still be REFUSED. Without this, T1 passes against a
# build where outline never reports a resolution failure at all -- which would
# turn a loud wrong answer into a silent empty one, the worse trade.
$ghost = Join-Path ([IO.Path]::GetTempPath()) ('draglint_outline_ghost_' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.pas')
[IO.File]::WriteAllText($ghost, "unit uGhost;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
try {
  $gh = RunOut @('outline','--file',$ghost)
  Check 'T3 DISCRIMINATION a file in no index is REFUSED, not answered with an empty outline' `
        ($gh.C -ne 0) `
        ("exit=$($gh.C) -- an unindexed file must not look like a file with no symbols:`n" + $gh.O)
} finally {
  try { Remove-Item -LiteralPath $ghost -Force -ErrorAction SilentlyContinue } catch { }
}

# ---- T4 an explicit --db is still an instruction ---------------------------
$selfDb = Join-Path $Repo 'src\cli\_D-RAG\drag-lint.sqlite'
if (Test-Path $selfDb) {
  $ex = RunOut @('outline','--file',$target,'--db',$selfDb)
  Check 'T4 an explicit --db is honoured unchanged' (($ex.C -eq 0) -and ($ex.O -match '(?m)^\s*(unit|type|class|function|procedure|method)\b')) `
        ("exit=$($ex.C)`n" + $ex.O)
} else {
  Skip 'T4 explicit --db' "self-index not built at $selfDb"
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
