# follow-cycle-plan.ps1 -- a MECHANICAL follower for `drag-lint cycles --plan` text.
# Parses Step 3 (new units) and Step 4 (edits) of ONE cycle and applies them verbatim.
# Refuses (exit 2) on: unparseable step, "Current text" mismatch, missing anchor.
# No judgement anywhere: if a step needs one, this script cannot do it.
# A trailing `(loaded defaults from ...)` line (stderr note captured with the plan) is ignored.
# -Root <dir> replaces the common directory prefix of the plan's absolute paths with <dir>, so a
# plan generated for one tree applies to a copy of it.
param(
  [Parameter(Mandatory)][string]$PlanFile,
  [int]$Cycle = 1,
  [switch]$DryRun,
  [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
$text = [IO.File]::ReadAllText($PlanFile)
$lines = @($text -split "`r?`n" | Where-Object { $_ -notmatch '^\(loaded defaults from ' })

# --- locate the cycle block
$start = -1; $end = $lines.Count
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match "^## Cycle (\d+):") {
    if ([int]$Matches[1] -eq $Cycle) { $start = $i }
    elseif ($start -ge 0) { $end = $i; break }
  }
}
if ($start -lt 0) { Write-Output "REFUSE: cycle $Cycle not in plan"; exit 2 }
$blk = $lines[$start..($end-1)]

function Read-Fence([string[]]$b, [ref]$idx) {
  # expects b[idx] to be a ``` opener; returns the fenced lines, idx moves past the closer
  if ($b[$idx.Value] -notmatch '^```') { throw "expected fence at block line $($idx.Value): $($b[$idx.Value])" }
  $out = New-Object System.Collections.Generic.List[string]
  $idx.Value++
  while ($idx.Value -lt $b.Count -and $b[$idx.Value] -notmatch '^```$') { $out.Add($b[$idx.Value]); $idx.Value++ }
  $idx.Value++
  return ,$out.ToArray()
}

$newUnits = @()   # @{Unit; Path; Text[]}
$edits = @()      # @{File; Path; Kind; First; Last; Anchor; Current[]; New[]}
$refusals = @()
$i = 0
$section = ''
while ($i -lt $blk.Count) {
  $l = $blk[$i]
  if ($l -match '^### Step 3') { $section = 'new'; $i++; continue }
  if ($l -match '^### Step 4') { $section = 'edit'; $i++; continue }
  if ($l -match '^### Checklist') { $section = 'done'; break }
  if ($section -eq 'new' -and $l -match '^#### `([^`]+)` -> `([^`]+)`$') {
    $u = $Matches[1]; $p = $Matches[2]; $i++
    $body = Read-Fence $blk ([ref]$i)
    $newUnits += @{Unit=$u; Path=$p; Text=$body}
    continue
  }
  if ($section -eq 'edit' -and $l -match '^#### `([^`]+)`  \(`([^`]+)`\)$') {
    $curFile = $Matches[1]; $curPath = $Matches[2]; $i++; continue
  }
  if ($section -eq 'edit' -and $l -match '^E(\d+)\. (.*)$') {
    $spec = $Matches[2]
    $i++
    if ($spec -match '^Replace lines? (\d+)(?:-(\d+))?\. Current text:$') {
      $f = [int]$Matches[1]; $t = if ($Matches[2]) { [int]$Matches[2] } else { $f }
      $cur = Read-Fence $blk ([ref]$i)
      if ($blk[$i] -ne 'New text:') { throw "expected 'New text:' at $i" }; $i++
      $new = Read-Fence $blk ([ref]$i)
      $edits += @{File=$curFile; Path=$curPath; Kind='replace'; First=$f; Last=$t; Current=$cur; New=$new}
    } elseif ($spec -match '^Delete lines? (\d+)(?:-(\d+))?\. Current text:$') {
      $f = [int]$Matches[1]; $t = if ($Matches[2]) { [int]$Matches[2] } else { $f }
      $cur = Read-Fence $blk ([ref]$i)
      $edits += @{File=$curFile; Path=$curPath; Kind='delete'; First=$f; Last=$t; Current=$cur; New=@()}
    } elseif ($spec -match '^After line (\d+) \(`(.*)`\), insert:$') {
      $f = [int]$Matches[1]; $anchor = $Matches[2]
      $new = Read-Fence $blk ([ref]$i)
      $edits += @{File=$curFile; Path=$curPath; Kind='insertAfter'; First=$f; Last=$f; Anchor=$anchor; Current=@(); New=$new}
    } else {
      $refusals += "unparseable edit step in $curFile : E$($Matches[1]) $spec"
    }
    continue
  }
  $i++
}

Write-Output ("parsed: {0} new unit(s), {1} edit(s), {2} refusal(s)" -f $newUnits.Count, $edits.Count, $refusals.Count)
$refusals | ForEach-Object { Write-Output "REFUSE: $_" }
if ($newUnits.Count -eq 0 -and $edits.Count -eq 0) { Write-Output "REFUSE: plan has no mechanical steps for cycle $Cycle"; exit 2 }

# --- -Root: swap the common directory prefix of all plan paths for $Root
if ($Root -ne '') {
  $allPaths = @(($newUnits | ForEach-Object { $_.Path }) + ($edits | ForEach-Object { $_.Path }) | Select-Object -Unique)
  $prefix = $null
  foreach ($p in $allPaths) {
    $d = [IO.Path]::GetDirectoryName($p)
    if ($null -eq $prefix) { $prefix = $d; continue }
    while ($prefix -ne '' -and -not ($d + '\').StartsWith($prefix + '\', [StringComparison]::OrdinalIgnoreCase)) {
      $prefix = [IO.Path]::GetDirectoryName($prefix); if ($null -eq $prefix) { $prefix = '' }
    }
  }
  $remap = { param($p) if ($prefix) { (Join-Path $Root $p.Substring($prefix.Length).TrimStart('\')) } else { $p } }
  foreach ($u in $newUnits) { $u.Path = & $remap $u.Path }
  foreach ($e in $edits) { $e.Path = & $remap $e.Path }
}

# --- verify every edit's anchor BEFORE writing anything (all or nothing)
$byPath = @{}
foreach ($e in $edits) {
  if (-not $byPath.ContainsKey($e.Path)) { $byPath[$e.Path] = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($e.Path)) }
}
$bad = 0
foreach ($e in $edits) {
  $src = [IO.File]::ReadAllLines($e.Path)   # original, for anchor checks
  if ($e.Kind -eq 'insertAfter') {
    $have = $src[$e.First-1].Trim()
    if ($have -ne $e.Anchor.Trim()) { Write-Output ("MISMATCH {0}:{1} anchor expected [{2}] found [{3}]" -f $e.File,$e.First,$e.Anchor,$have); $bad++ }
  } else {
    for ($k = 0; $k -lt $e.Current.Count; $k++) {
      $ln = $e.First - 1 + $k
      if ($ln -ge $src.Count -or $src[$ln] -ne $e.Current[$k]) { Write-Output ("MISMATCH {0}:{1} expected [{2}] found [{3}]" -f $e.File,($ln+1),$e.Current[$k],($(if ($ln -lt $src.Count) { $src[$ln] } else { '<EOF>' }))); $bad++ }
    }
    if ($e.Current.Count -ne ($e.Last - $e.First + 1)) { Write-Output ("MISMATCH {0}: {1} current lines for range {2}-{3}" -f $e.File,$e.Current.Count,$e.First,$e.Last); $bad++ }
  }
}
if ($bad -gt 0) { Write-Output "REFUSE: $bad anchor mismatch(es); nothing written"; exit 2 }
foreach ($u in $newUnits) { if (Test-Path $u.Path) { Write-Output "REFUSE: new unit exists: $($u.Path)"; exit 2 } }

if ($DryRun) { Write-Output "DRY RUN: all anchors match; would write $($newUnits.Count) new file(s) and edit $($byPath.Count) file(s)"; exit 0 }

# --- apply: edits in listed order (plan lists them bottom-to-top per file)
foreach ($e in $edits) {
  $buf = $byPath[$e.Path]
  switch ($e.Kind) {
    'replace'     { $buf.RemoveRange($e.First-1, $e.Last-$e.First+1); $buf.InsertRange($e.First-1, [string[]]$e.New) }
    'delete'      { $buf.RemoveRange($e.First-1, $e.Last-$e.First+1) }
    'insertAfter' { $buf.InsertRange($e.First, [string[]]$e.New) }
  }
  Write-Output ("applied {0} {1}:{2}-{3}" -f $e.Kind,$e.File,$e.First,$e.Last)
}
$ascii = [Text.Encoding]::ASCII
foreach ($p in $byPath.Keys) {
  $raw = [IO.File]::ReadAllBytes($p)
  $enc = if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { New-Object Text.UTF8Encoding($true) } else { [Text.Encoding]::Default }
  [IO.File]::WriteAllText($p, (($byPath[$p] -join "`r`n") + "`r`n"), $enc)
  Write-Output "wrote $p"
}
foreach ($u in $newUnits) {
  [IO.File]::WriteAllText($u.Path, (($u.Text -join "`r`n") + "`r`n"), $ascii)
  Write-Output "created $($u.Path)"
}
exit 0
