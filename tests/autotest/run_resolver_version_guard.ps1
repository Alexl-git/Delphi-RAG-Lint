<#
  run_resolver_version_guard.ps1 -- if you change how the index RESOLVES, you
  must bump DRAGLINT_RESOLVER_VERSION.

  WHY A SECOND STAMP. DRAGLINT_EXTRACTOR_VERSION answers "would this build PARSE
  a byte sequence differently?", and a bump costs a ~5 hour re-parse of every
  index. The resolve pass asks a different question -- "would this build DERIVE
  different edges from parses it already has?" -- and its remedy costs minutes,
  not hours. One stamp cannot answer both, and measured against real history it
  currently gets both wrong in opposite directions:

    src\index\DRagLint.Index.CallResolver.pas  INSIDE the extractor hash
        -> 19 commits each demanded a full re-parse for a re-resolve.
    src\storage\...  ResolveAncestry, ResolveCallTargets, GetTypeCandidates ...
        -> 42 resolve-write commits, one every 2.2 days, moved NOTHING.
           Indexes went silently stale.

  THE SURFACE IS SCOPED BY FUNCTION, NOT BY DIRECTORY, because no directory line
  separates the two questions -- half the resolve pass lives under src\index and
  half under src\storage. tests\resolver-surface.txt is the manifest, and it is
  reviewed rather than inferred: the churn probe that PRICED this problem used a
  name regex and says in its own source that it is "deliberately generous".

  WHAT COUNTS AS RESOLVE: the four writers and what they call.
    ResolveUnitUseTargets -> unit_uses.target_file_id
    ResolveAncestry       -> type_ancestors
    ResolveHelpers        -> type_helpers
    ResolveCallTargets    -> call_edges, refs.receiver_text/external_target

  DELIBERATE EXCLUSIONS, each with a reason, in the manifest file itself.
  ResolveLog and ResolveSecs are on the call list and are logging and timing --
  including them would bump the stamp for a changed log line, which is the
  over-billing this whole split exists to end.

  DRIFT CONTROL. A manifest cannot notice a callee added later, so this guard
  ALSO fails when a routine whose name matches the resolve vocabulary is in
  neither the manifest nor the reasoned exclusion list. The regex flags drift;
  it never defines the surface.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Repo = "$PSScriptRoot\..\..")

$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n,$ok,$detail=''){
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) `
    -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$Repo     = (Resolve-Path $Repo).Path
$manifest = Join-Path $Repo 'tests\resolver-surface.txt'
$baseline = Join-Path $Repo 'tests\resolver-version.baseline'
$modelPas = Join-Path $Repo 'src\core\DRagLint.Core.Model.pas'

# --- the declared resolver version ------------------------------------------
$m = Select-String -Path $modelPas -Pattern "DRAGLINT_RESOLVER_VERSION\s*=\s*'([^']+)'"
Check 'DRAGLINT_RESOLVER_VERSION is declared' ($null -ne $m) $modelPas
if ($null -eq $m) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$version = $m.Matches[0].Groups[1].Value

# --- span extraction ---------------------------------------------------------
# A top-level routine header starts in COLUMN 1. Interface declarations and
# nested routines are indented in this codebase, which is what separates the
# implementation body (the thing that can change behaviour) from its forward
# declaration. Verified against DRagLint.Storage.SQLite.pas before relying on it.
$HdrRx = [regex]'^(?i)(function|procedure|constructor|destructor)\s+([A-Za-z0-9_]+\.)?([A-Za-z0-9_]+)'

function Get-TopLevelRoutines([string]$Path) {
  $lines = [System.IO.File]::ReadAllLines($Path)
  $out = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $mm = $HdrRx.Match($lines[$i])
    if ($mm.Success) { $out.Add([pscustomobject]@{ Line = $i; Name = $mm.Groups[3].Value }) }
  }
  for ($k = 0; $k -lt $out.Count; $k++) {
    $end = if ($k + 1 -lt $out.Count) { $out[$k+1].Line - 1 } else { $lines.Count - 1 }
    $out[$k] | Add-Member -NotePropertyName End  -NotePropertyValue $end
    $out[$k] | Add-Member -NotePropertyName Text -NotePropertyValue ($lines[$out[$k].Line..$end] -join "`n")
  }
  ,$out
}

# --- read the manifest -------------------------------------------------------
# Format, one per line:   <repo-relative path>::<RoutineName>      or  ::*
# '#' comments and blank lines ignored. EXCLUDE: lines beginning 'EXCLUDE '.
Check 'resolver surface manifest exists' (Test-Path $manifest) $manifest
if (-not (Test-Path $manifest)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$entries  = @()
$excludes = @()
foreach ($ln in Get-Content $manifest) {
  $t = $ln.Trim()
  if (-not $t -or $t.StartsWith('#')) { continue }
  if ($t -match '^EXCLUDE\s+(\S+)') { $excludes += $Matches[1].ToLower(); continue }
  $p, $r = $t -split '::', 2
  $entries += [pscustomobject]@{ Path = $p.Trim(); Routine = $r.Trim() }
}
Check 'manifest is non-empty' ($entries.Count -gt 5) "$($entries.Count) entry/entries"

# --- hash the surface --------------------------------------------------------
# Sorted by path then routine so the digest cannot depend on file order, and the
# PATH AND ROUTINE NAME are part of the identity -- moving a body between
# routines must move the hash.
$parts = New-Object System.Collections.Generic.List[string]
$missing = @()
foreach ($e in ($entries | Sort-Object Path, Routine)) {
  $full = Join-Path $Repo $e.Path
  if (-not (Test-Path $full)) { $missing += $e.Path; continue }
  if ($e.Routine -eq '*') {
    $parts.Add("$($e.Path)::*`n" + ([System.IO.File]::ReadAllText($full) -replace "`r`n","`n"))
  } else {
    $r = (Get-TopLevelRoutines $full) | Where-Object { $_.Name -ieq $e.Routine }
    if (-not $r) { $missing += "$($e.Path)::$($e.Routine)"; continue }
    foreach ($one in $r) { $parts.Add("$($e.Path)::$($e.Routine)`n" + $one.Text) }
  }
}
# A manifest entry that no longer resolves is a FAILURE, not a silent skip: a
# renamed routine would otherwise quietly leave the hashed surface and take its
# staleness protection with it.
Check 'every manifest entry resolves to real source' ($missing.Count -eq 0) `
  ($(if ($missing.Count) { $missing -join ', ' } else { 'all found' }))

$sha  = [System.Security.Cryptography.SHA256]::Create()
$hash = ([System.BitConverter]::ToString(
           $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))) -replace '-','').ToLower()
$current = "$version|$hash"

# --- DRIFT CONTROL: a resolve-ish routine that nobody classified -------------
$Vocab = [regex]'(?i)resolve|candidate|ancestry|inherit|calledge|call_edge|helper'
# Separators are normalised on BOTH sides. The manifest is written with forward
# slashes (it is read by humans and by git); the walk below builds Windows
# paths. Comparing them raw made every manifest entry read as unclassified --
# the check fired on 17 routines it had itself been given.
function NormPath([string]$P) { return ($P -replace '\\', '/').ToLower() }
$unclassified = @()
foreach ($f in @('src/storage/DRagLint.Storage.SQLite.pas')) {
  foreach ($r in (Get-TopLevelRoutines (Join-Path $Repo $f))) {
    if (-not $Vocab.IsMatch($r.Name)) { continue }
    $key = $r.Name.ToLower()
    $inManifest = @($entries | Where-Object {
      (NormPath $_.Path) -eq (NormPath $f) -and $_.Routine -ieq $r.Name
    }).Count -gt 0
    if (-not $inManifest -and ($excludes -notcontains $key)) { $unclassified += "$f::$($r.Name)" }
  }
}
Check 'no resolve-vocabulary routine is unclassified' ($unclassified.Count -eq 0) `
  ($(if ($unclassified.Count) { ($unclassified -join ', ') + '  -- add to the manifest, or EXCLUDE it with a reason' } else { 'manifest covers the vocabulary' }))

# --- baseline ----------------------------------------------------------------
# EXACTLY ONE ACTIVE LINE. run_extractor_version_guard.ps1's baseline was
# appended to rather than replaced on 2026-08-26, leaving two active lines; it
# reads only the first, so the stored version could never again equal the
# declared one and the guard returned "changed AND bumped" forever. It was
# structurally incapable of failing. This one asserts its own baseline's shape.
if (-not (Test-Path $baseline)) {
  Write-Host ''
  Write-Host 'no baseline yet -- create it with:' -ForegroundColor Yellow
  Write-Host "   $current"
  Check 'baseline exists' $false 'first run: write the line above into the baseline file'
} else {
  $active = @(Get-Content $baseline | Where-Object { $_ -and -not $_.Trim().StartsWith('#') })
  Check 'baseline carries exactly ONE active line' ($active.Count -eq 1) `
    "$($active.Count) found -- an appended line makes this guard permanently green"
  if ($active.Count -ge 1) {
    $sv, $sh = $active[0].Trim() -split '\|', 2
    if ($sh -eq $hash) {
      Check 'resolve surface unchanged' $true "version=$version"
    } elseif ($sv -ne $version) {
      Check 'resolve changed AND the version was bumped' $true "$sv -> $version"
      Write-Host "   update the baseline to:  $current" -ForegroundColor Yellow
    } else {
      Check 'resolve changed but DRAGLINT_RESOLVER_VERSION did NOT' $false `
        "still '$version' -- bump it, or every index keeps edges from the OLD resolver"
      Write-Host '   Remedy is cheap: bump, then `index --resolve-only` per DB.' -ForegroundColor Yellow
    }
  }
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
