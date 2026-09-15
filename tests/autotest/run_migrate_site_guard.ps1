<#
  run_migrate_site_guard.ps1 -- `.Migrate` is unreachable from a verb that did
  not ask to write.

  WHY THIS EXISTS. `usages`, `typeat` and `deps-report`, handed an explicit
  `--db` at an old schema, MIGRATED that database in place (schema_version
  12 -> 22, 4 tables -> 31, 28 KB -> 320 KB, journal delete -> wal) and then
  answered from it: exit 0, nothing on either stream. The blast radius is the
  1.4 GB library index, rewritten wholesale under a write lock while the
  operator believes they ran a read -- and afterwards the evidence that it was
  ever stale is gone, so the staleness hazard C3 refuses becomes self-concealing
  (INBOX-read-verbs-migrate-the-db, 2026-09-14). CLI.pas states the policy
  itself, on LintLibraryDb: "never migrate someone else's gigabytes as a side
  effect of linting".

  WHAT IT ASSERTS. Every `.Migrate` call in src\cli\*.pas is attributed to the
  top-level routine that contains it, and that routine must be on the exemption
  list below, with a reason. The list is a RATCHET:

    a site in a routine NOT on the list        -> FAIL  (a new migrate-on-read)
    a listed routine with NO `.Migrate` left   -> FAIL  (stale entry: delete it,
                                                  so the list is a decision and
                                                  not an oversight)
    the three fixed verbs, named explicitly    -> FAIL if any of them migrates

  and a POSITIVE CONTROL: the same classifier is run over a synthetic unit that
  puts `.Migrate` back into DoUsages, and must flag it. Without that, every
  assertion above also passes against a classifier that finds nothing.

  THE EXEMPTION LIST IS NOT A WHITELIST OF GOOD BEHAVIOUR. `writes` entries
  migrate by contract -- the verb exists to write the index. `unaudited` entries
  carry the same read-shaped defect the three fixed verbs had, or have not been
  audited; they are listed so this guard is green for the work that IS done and
  red for the work that is undone AGAIN. Each fix removes its line. The list
  may only shrink.

  A TEXT SCAN CANNOT READ COMMENTS. A `.Migrate` inside a comment attributes to
  its routine like any other; if that routine is not listed the guard goes red,
  which is the conservative direction -- it can over-report, never under-report.

  Run from any CWD, pwsh 7. Runs no engine; pure source scan.
#>
[CmdletBinding()]
param(
  [string]$Repo = "$PSScriptRoot\..\.."
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

$repoPath = (Resolve-Path $Repo).Path
$cliDir   = Join-Path $repoPath 'src\cli'

# routine -> reason. Keys are the TOP-LEVEL routine names (column 0
# `function`/`procedure`); nested routines attribute to their enclosing one.
$exempt = [ordered]@{
  # -- writes by contract: the verb exists to build, repair or amend the index --
  'BuildPlanItem'         = 'writes: index plan item (index --all)'
  'DoIndex'               = 'writes: index'
  'IndexDictionary'       = 'writes: index --dictionary'
  'DoFbSnapshot'          = 'writes: snapshots Firebird metadata INTO --db'
  'DoSafeDelete'          = 'writes: same read-write path as index/rename'
  'DoRename'              = 'writes: rename'
  'DoPurgeLocals'         = 'writes: purge MUTATES (its own comment)'
  'DoLintAll'             = 'writes: findings into the project db (lint family)'
  'DoLintProject'         = 'writes: findings into the project db (lint family)'
  'DoExceptionsSync'      = 'writes: findings into the project db (lint family)'
  'DoRefreshFindings'     = 'writes: findings into the project db (lint family)'
  'DoCompileCheck'        = 'writes: TCompileChecker.InsertFindings'
  'DoReconcileProject'    = 'writes: reconcile-project --apply'
  'DoSelfTestRecreate'    = 'writes: self-test over its own fixture db'
  'DoTestStoreFreshness'  = 'writes: self-test over its own fixture db'
  'DoDocFactsSelfTest'    = 'writes: self-test over its own fixture db'
  # -- unaudited: read-shaped, migrates a caller-supplied path; same defect as --
  # -- the three fixed verbs. Fix one, delete its line.                        --
  'DoHover'               = 'unaudited: read-shaped, Create+Migrate on each --db'
  'DoWiring'              = 'unaudited: read-shaped, Create+Migrate on the first existing --db'
  'DoImpact'              = 'unaudited: read-shaped, Create+Migrate on --db'
  'DoSlice'               = 'unaudited: read-shaped, Create+Migrate on --db'
  'DoBenchContext'        = 'unaudited: read-shaped (benchmark), Create+Migrate on --db'
  'DoUsesReport'          = 'unaudited: read-shaped, Create+Migrate on each --db -- the deps-report twin'
  'DoGenerateDocs'        = 'unaudited: read-shaped, Create+Migrate on --db'
  'DoFindDeadCode'        = 'unaudited: read-shaped, Create+Migrate on --db'
  'DoCheckUnit'           = 'unaudited: read-shaped (--resolve-uses), Create+Migrate on --db'
  'DoCycles'              = 'unaudited: read-shaped, Create+Migrate on --db'
  'DoUsesAudit'           = 'unaudited: read-shaped, Create+Migrate on --db'
  'DoUsesFixSweep'        = 'unaudited: reads the db to edit SOURCE; Create+Migrate on --db'
  'DoUsesFix'             = 'unaudited: reads the db to edit SOURCE; Create+Migrate on --db'
  'DoGenerateTest'        = 'unaudited: read-shaped, Create+Migrate on --db'
  'DoCheckAst'            = 'unaudited: read-shaped, Create+Migrate on --db'
}

# The three verbs INBOX-read-verbs-migrate-the-db measured. Named here so the
# RED-before-fix output says which verb, not just "a site outside the list".
$fixed = @('DoUsages', 'DoTypeAt', 'DoDepsReport')

# Returns @{ Routine; Line; File } per `.Migrate` site in the given .pas text.
function Find-MigrateSites([string]$Path) {
  $lines = [IO.File]::ReadAllLines($Path)
  $cur   = '(before any routine)'
  $sites = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match '^(function|procedure)\s+([A-Za-z_][A-Za-z0-9_.]*)') { $cur = $Matches[2] }
    if ($l -match '\.Migrate\b') {
      $sites += [pscustomobject]@{ Routine = $cur; Line = ($i + 1); File = (Split-Path $Path -Leaf) }
    }
  }
  # Plain return, NOT `,$sites`: the comma wraps the array once more, and the
  # caller's @() then holds ONE element that is itself the list -- so .Count is
  # 1 and .Routine enumerates to "DoUsages DoIndex". Callers wrap in @() so an
  # empty or single-site result is still an array.
  return $sites
}

# ---- positive control: the classifier can see a migrate-on-read ------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('draglint_migrate_site_guard_' + [Guid]::NewGuid().ToString('N') + '.pas')
[IO.File]::WriteAllText($tmp, ("unit Synthetic;`r`ninterface`r`nimplementation`r`n" +
  "function DoUsages(const AArgs: TArgs): Integer;`r`nbegin`r`n  Store:= TSQLiteSymbolStore.Create(DbPath);`r`n  Store.Migrate;`r`nend;`r`n" +
  "function DoIndex(const AArgs: TArgs): Integer;`r`n  procedure Nested;`r`n  begin`r`n    Store.Migrate;`r`n  end;`r`nbegin`r`nend;`r`nend.`r`n"),
  [Text.Encoding]::ASCII)
try {
  $ctl = @(Find-MigrateSites $tmp)
  Check 'P1 POSITIVE CONTROL the classifier attributes a .Migrate to its top-level routine' `
        (($ctl.Count -eq 2) -and ($ctl[0].Routine -eq 'DoUsages') -and ($ctl[1].Routine -eq 'DoIndex')) `
        ("expected DoUsages + DoIndex (nested attributed to its parent), got: " + (($ctl | ForEach-Object { "$($_.Routine)@$($_.Line)" }) -join ', '))
  $ctlBad = @($ctl | Where-Object { $_.Routine -in $fixed })
  Check 'P2 POSITIVE CONTROL a .Migrate inside DoUsages IS flagged as a fixed verb regressing' ($ctlBad.Count -eq 1) `
        "the fixed-verb assertion below could not fail: control flagged $($ctlBad.Count) site(s)"
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

# ---- the scan --------------------------------------------------------------
$pas = @(Get-ChildItem -LiteralPath $cliDir -File -Filter '*.pas')
Check 'V src\cli holds .pas files to scan' ($pas.Count -gt 0) $cliDir

$all = @()
foreach ($f in $pas) { $all += @(Find-MigrateSites $f.FullName) }
Check 'V the scan found .Migrate sites at all (a zero here is a broken scan, not a clean tree)' ($all.Count -gt 0) ''

# T1: no site outside the list
$outside = @($all | Where-Object { -not $exempt.Contains($_.Routine) })
Check 'T1 every .Migrate site sits in a listed routine (no NEW migrate-on-read)' ($outside.Count -eq 0) `
      ("outside the exemption list: " + (($outside | ForEach-Object { "$($_.Routine) ($($_.File):$($_.Line))" }) -join ', ') +
       " -- a read verb goes through OpenReadOnlyStore + StaleDbRefusesRun; a writing verb is added to the list WITH a reason")

# T2: the three fixed verbs, by name (a subset of T1, spelled out)
$regressed = @($all | Where-Object { $_.Routine -in $fixed })
Check 'T2 usages / typeat / deps-report do not migrate (INBOX-read-verbs-migrate-the-db)' ($regressed.Count -eq 0) `
      ("migrating again: " + (($regressed | ForEach-Object { "$($_.Routine) ($($_.File):$($_.Line))" }) -join ', '))

# T3: no stale entry -- the list may only shrink, and it shrinks by hand
$present = @($all | ForEach-Object { $_.Routine } | Select-Object -Unique)
$stale   = @($exempt.Keys | Where-Object { $_ -notin $present })
Check 'T3 every listed routine still contains a .Migrate (a stale entry is deleted, not kept)' ($stale.Count -eq 0) `
      ("no longer migrate -- remove from the list: " + ($stale -join ', '))

# T4: the fixed verbs are not quietly re-admitted via the list
$readmitted = @($fixed | Where-Object { $exempt.Contains($_) })
Check 'T4 the fixed verbs are not on the exemption list' ($readmitted.Count -eq 0) ($readmitted -join ', ')

Write-Host ''
Write-Host ("sites: {0}   listed routines: {1}   writes: {2}   unaudited: {3}" -f $all.Count, $exempt.Count,
  @($exempt.Values | Where-Object { $_ -like 'writes:*' }).Count, @($exempt.Values | Where-Object { $_ -like 'unaudited:*' }).Count) -ForegroundColor DarkGray
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
