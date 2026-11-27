# Guard for the wave v156 scaffold (lane FRAME, 1.56.0-alpha): the frame FRAME-1 / FRAME-2 laid for the 1.56
# sub-lanes. Catalog COUNTS are pinned by the older frame guards and by INT, not here.
#
# What it pins:
#   1. every v156 stub unit FRAME-1 created exists, declares the unit its file name says, and is listed in
#      BOTH drag-lint.dpr and drag-lint.dproj (the plugin stub: in the .dpk and the plugin .dproj).
#   2. the eight v156 rule lanes are BuildLanes rows of DRagLint.V151.Dispatch with all five hooks.
#   3. CLI.Repo dispatches the WIKIGEN / GCP-C units and names their sub-verbs in the unknown-sub-verb message.
#   4. CLI.pas wires `query --concept` to Query.ConceptRepo (TryRunConceptRepoQuery).
#   5. POSITIVE CONTROL (-NoSelfTest skips it): the same checks run on a deliberately broken copy in the temp
#      folder (one dproj entry, one dpr entry, one dispatch row, one stub file, one stub name, one CLI.Repo
#      line, the concept call, each broken in turn) and every break must be reported; a guard that cannot
#      fail proves nothing.
# Compile-in is checked at the project-file level (dpr + dproj); the Win64 build itself is the compile check.
param(
  [string]$Repo = "",
  [switch]$SkipPlugin,   # the plugin stub lives on FRAME-2's branch; skip it on a tree that does not carry it yet
  [switch]$NoSelfTest
)
$ErrorActionPreference = "Stop"
$repoRoot = if ($Repo -ne "") { (Resolve-Path $Repo).Path } else { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }

# unit file (relative to src\) and its project-file form
$ruleLanes = 'FACTA','MEMA','MEMB','OOA1','OOA2','OOB1','OOB2','THR'
$srcUnits = @()
foreach ($l in $ruleLanes + 'TAINTEXC') { $srcUnits += "lint\v156\DRagLint.V156.$l.pas"; $srcUnits += "lint\v156\DRagLint.V156.$l.Support.pas" }
foreach ($n in 'DataFlowExc','FieldLineage','IndirectCalls','RepoCopy') { $srcUnits += "index\DRagLint.Index.$n.pas" }
foreach ($n in 'LockSites','ConceptRepo') { $srcUnits += "query\DRagLint.Query.$n.pas" }
foreach ($n in 'GridCopy','FieldUsage','DfmReadInherit','WikiGen','ZipBackup','SqlBackup') { $srcUnits += "sql\DRagLint.FieldRepo.$n.pas" }
$cliUnits = 'RepoWiki','RepoGridCopy','MigrateReports'

# Returns the list of problems found under $root (empty = frame holds).
function Get-FrameProblems([string]$root, [bool]$skipPlugin) {
  $p = New-Object System.Collections.Generic.List[string]
  function Src($rel) { [IO.File]::ReadAllText((Join-Path $root $rel)) }
  $dpr = Src 'src\cli\drag-lint.dpr'
  $dproj = Src 'src\cli\drag-lint.dproj'
  # 1. units
  foreach ($u in $srcUnits) {
    $f = Join-Path $root "src\$u"
    if (-not (Test-Path $f)) { $p.Add("file:$u") }
    else {
      $name = [IO.Path]::GetFileNameWithoutExtension($u)
      if ([IO.File]::ReadAllText($f) -notmatch "(?m)^unit\s+$([regex]::Escape($name))\s*;") { $p.Add("unit-name:$u") }
    }
    if (-not $dpr.Contains("'..\$u'")) { $p.Add("dpr:$u") }
    if (-not $dproj.Contains("Include=""..\$u""")) { $p.Add("dproj:$u") }
  }
  foreach ($c in $cliUnits) {
    $f = "DRagLint.CLI.$c.pas"
    if (-not (Test-Path (Join-Path $root "src\cli\$f"))) { $p.Add("file:$f") }
    if (-not $dpr.Contains("'$f'")) { $p.Add("dpr:$f") }
    if (-not $dproj.Contains("Include=""$f""")) { $p.Add("dproj:$f") }
  }
  if (-not $skipPlugin) {
    $dlg = 'DragLint.Plugin.Cmd.GridCopy.pas'
    if (-not (Test-Path (Join-Path $root "src\delphi-plugin\$dlg"))) { $p.Add("file:$dlg") }
    if (-not (Src 'src\delphi-plugin\dclDragLintWizard.dpk').Contains("'$dlg'")) { $p.Add("dpk:$dlg") }
    if (-not (Src 'src\delphi-plugin\dclDragLintWizard.dproj').Contains("Include=""$dlg""")) { $p.Add("plugin-dproj:$dlg") }
  }
  # 2. one provider mechanism
  $disp = Src 'src\lint\v151\DRagLint.V151.Dispatch.pas'
  foreach ($l in $ruleLanes) {
    $c = "TV156${l}Rules"
    $hooks = "$c.Catalog, $c.CheckFile, $c.CheckDfm, $c.CheckRawBytes, $c.CheckProject)"
    if (-not ($disp.Contains("Lane('$l',") -and $disp.Contains($hooks) -and $disp -match "DRagLint\.V156\.$l\b")) { $p.Add("dispatch-row:$l") }
  }
  # 3. CLI.Repo dispatch
  $cliRepo = Src 'src\cli\DRagLint.CLI.Repo.pas'
  foreach ($x in @(@('IsRepoWikiSub(pSub)','RunRepoWikiVerb('), @('IsRepoGridCopySub(pSub)','RunRepoGridCopyVerb('))) {
    $hits = @($cliRepo -split "`r?`n" | Where-Object { $_.Contains($x[0]) -and $_.Contains($x[1]) })
    if ($hits.Count -ne 1) { $p.Add("cli-repo-dispatch:$($x[0]) x$($hits.Count)") }
  }
  if (-not $cliRepo.Contains('+ REPO_WIKI_SUBS + REPO_GRIDCOPY_SUBS')) { $p.Add('cli-repo-subs-message') }
  # 4. --concept wiring
  $cli = Src 'src\cli\DRagLint.CLI.pas'
  if (-not $cli.Contains('TryRunConceptRepoQuery(RepoQuery, RepoExit)')) { $p.Add('cli-concept-call') }
  if (-not $cli.Contains('DRagLint.Query.ConceptRepo')) { $p.Add('cli-concept-uses') }
  return ,$p
}

$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

$real = Get-FrameProblems $repoRoot $SkipPlugin.IsPresent
Assert "the v156 frame holds: $($srcUnits.Count + $cliUnits.Count) engine units in dpr + dproj, 8 dispatch rows, CLI.Repo + --concept wiring ($($real -join ', '))" ($real.Count -eq 0)

if (-not $NoSelfTest) {
  # 5. positive control on a broken copy
  $work = Join-Path ([IO.Path]::GetTempPath()) ("dl-v156-frame-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
  try {
    function Fresh-Copy {
      if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
      $rels = @('src\cli\drag-lint.dpr','src\cli\drag-lint.dproj','src\cli\DRagLint.CLI.pas','src\cli\DRagLint.CLI.Repo.pas',
        'src\lint\v151\DRagLint.V151.Dispatch.pas','src\delphi-plugin\dclDragLintWizard.dpk','src\delphi-plugin\dclDragLintWizard.dproj',
        'src\delphi-plugin\DragLint.Plugin.Cmd.GridCopy.pas') + ($cliUnits | ForEach-Object { "src\cli\DRagLint.CLI.$_.pas" }) + ($srcUnits | ForEach-Object { "src\$_" })
      foreach ($r in $rels) {
        $s = Join-Path $repoRoot $r
        if (-not (Test-Path $s)) { continue }
        $d = Join-Path $work $r
        [void](New-Item -ItemType Directory -Force -Path (Split-Path $d))
        [IO.File]::Copy($s, $d, $true)
      }
    }
    function Edit-Copy($rel, [scriptblock]$fn) {
      $f = Join-Path $work $rel
      $t = [IO.File]::ReadAllText($f)
      $n = & $fn $t
      if ($n -ceq $t) { throw "positive control: the edit of $rel changed nothing" }
      [IO.File]::WriteAllText($f, $n, [Text.Encoding]::ASCII)
    }
    Fresh-Copy
    Assert 'control: the unbroken copy passes' ((Get-FrameProblems $work $SkipPlugin.IsPresent).Count -eq 0)
    $breaks = [ordered]@{
      'one dproj entry removed'     = { Edit-Copy 'src\cli\drag-lint.dproj' { param($t) ($t -split "`r?`n" | Where-Object { $_ -notmatch 'DRagLint\.Query\.LockSites\.pas' }) -join "`r`n" } }
      'one dpr entry removed'       = { Edit-Copy 'src\cli\drag-lint.dpr' { param($t) ($t -split "`r?`n" | Where-Object { $_ -notmatch 'DRagLint\.CLI\.RepoWiki' }) -join "`r`n" } }
      'one dispatch row removed'    = { Edit-Copy 'src\lint\v151\DRagLint.V151.Dispatch.pas' { param($t) ($t -split "`r?`n" | Where-Object { $_ -notmatch "Lane\('OOB2'," }) -join "`r`n" } }
      'one stub file deleted'       = { [IO.File]::Delete((Join-Path $work 'src\sql\DRagLint.FieldRepo.ZipBackup.pas')) }
      'one stub renamed inside'     = { Edit-Copy 'src\index\DRagLint.Index.RepoCopy.pas' { param($t) $t -replace '(?m)^unit\s+DRagLint\.Index\.RepoCopy', 'unit DRagLint.Index.RepoCopyX' } }
      'CLI.Repo dispatch line gone' = { Edit-Copy 'src\cli\DRagLint.CLI.Repo.pas' { param($t) ($t -split "`r?`n" | Where-Object { $_ -notmatch 'IsRepoGridCopySub\(pSub\) then Exit' }) -join "`r`n" } }
      '--concept call removed'      = { Edit-Copy 'src\cli\DRagLint.CLI.pas' { param($t) $t.Replace('TryRunConceptRepoQuery(RepoQuery, RepoExit)', 'False') } }
    }
    foreach ($k in $breaks.Keys) {
      Fresh-Copy
      & $breaks[$k]
      $pr = Get-FrameProblems $work $SkipPlugin.IsPresent
      Assert "control: '$k' makes the guard FAIL ($($pr -join ', '))" ($pr.Count -ge 1)
    }
  } finally { if (Test-Path $work) { [IO.Directory]::Delete($work, $true) } }
}

if ($fail -gt 0) { Write-Host "run_v156_frame_guard: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v156_frame_guard: all passed"
exit 0
