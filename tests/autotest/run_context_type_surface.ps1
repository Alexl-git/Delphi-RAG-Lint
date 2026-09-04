<#
  run_context_type_surface.ps1 -- `context --task "modify <Unit.TType>"` must
  emit the TYPE'S OWN class surface.

  THE DEFECT THIS PINS:
    TContextBundler.Build derived the surface qname by chopping everything after
    the last '.' -- correct for a METHOD (the owner is the class) and wrong for a
    TYPE, where it yields the UNIT. GetClassSurface('SomeUnit') returns nothing,
    so a type-shaped task got no `## Class surface` section at all.

    That is the one question a type-shaped task is asking -- "what members does
    this thing have?" -- and it was the one the bundle would not answer, while
    the same task aimed at any single METHOD of that type answered it fine. The
    reader's fallback is to open the whole unit, which is exactly the ~60x cost
    the context bundle exists to avoid.

  THE CONTROLS, and what each one rules out:
    * the method path still emits its owner's surface   -> the fix did not
      simply redirect every target to itself
    * a record gets its surface too                     -> not a class-only
      special case
    * a TOP-LEVEL ROUTINE gets NO class surface         -> the type branch did
      not start inventing a surface for the unit, which would put a whole unit's
      declarations into every bundle
    * an invented member name is absent from a surface  -> the substring match
      that carries the assertions is not vacuous

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-ctxtype-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== context bundle: a TYPE target gets its own class surface ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$srcDir = (Resolve-Path "$PSScriptRoot\fixtures\contexttype").Path

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$fixDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $fixDir | Out-Null
Copy-Item (Join-Path $srcDir '*.pas') $fixDir
$db      = Join-Path $WorkDir 'ctxtype.sqlite'
$errFile = Join-Path $WorkDir 'stderr.txt'

# A FOLDER target builds a Library-shaped DB, which is what a scratch fixture
# wants. Never point a folder target at a project DB -- it widens it, stickily.
& $Exe index $fixDir --db $db 2>$errFile | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "FATAL: indexing the fixture failed ($LASTEXITCODE)" -ForegroundColor Red
  Write-Host (Get-Content -LiteralPath $errFile -Raw)
  exit 1
}

# Returns the bundle split into its markdown sections, keyed by heading.
function Sections([string]$Task) {
  $out = (& $Exe context --task $Task --db $db --format markdown 2>$errFile) -join "`n"
  $map = @{}
  $cur = '<preamble>'
  foreach ($ln in ($out -split "`r?`n")) {
    if ($ln -match '^##\s+(.+?)\s*$') { $cur = $Matches[1]; $map[$cur] = @() ; continue }
    if (-not $map.ContainsKey($cur)) { $map[$cur] = @() }
    $map[$cur] += $ln
  }
  foreach ($k in @($map.Keys)) { $map[$k] = ($map[$k] -join "`n") }
  return $map
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- the defect: a CLASS target' -ForegroundColor Cyan
$cls = Sections 'modify uCtxType.TWidget'
Write-Host ("  sections: " + (($cls.Keys | Sort-Object) -join ', ')) -ForegroundColor DarkGray
Check 'a class target emits a Class surface section' ($cls.ContainsKey('Class surface')) `
  ("sections=[" + (($cls.Keys | Sort-Object) -join ',') + "]")
if ($cls.ContainsKey('Class surface')) {
  Check 'and the surface is the CLASS''s own members' `
    ($cls['Class surface'] -match 'Spin' -and $cls['Class surface'] -match 'Measure') `
    ("matched Spin=" + [bool]($cls['Class surface'] -match 'Spin') + " Measure=" + [bool]($cls['Class surface'] -match 'Measure'))
  Check 'CONTROL: an invented member is NOT in the surface (the match is not vacuous)' `
    ($cls['Class surface'] -notmatch 'ZzNotAMember') 'ZzNotAMember'
}
Check 'CONTROL: the rest of the bundle is still built (Impl slice present)' `
  ($cls.ContainsKey('Impl slice')) ("sections=[" + (($cls.Keys | Sort-Object) -join ',') + "]")

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- the path that already worked: a METHOD target' -ForegroundColor Cyan
$mth = Sections 'modify uCtxType.TWidget.Spin'
Write-Host ("  sections: " + (($mth.Keys | Sort-Object) -join ', ')) -ForegroundColor DarkGray
Check 'CONTROL: a method target still gets its OWNER''s surface' `
  ($mth.ContainsKey('Class surface') -and $mth['Class surface'] -match 'Measure') `
  ("has section=" + $mth.ContainsKey('Class surface'))

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- the same code path: a RECORD target' -ForegroundColor Cyan
$rec = Sections 'modify uCtxType.TPayload'
Write-Host ("  sections: " + (($rec.Keys | Sort-Object) -join ', ')) -ForegroundColor DarkGray
Check 'a record target emits its own surface too' `
  ($rec.ContainsKey('Class surface') -and $rec['Class surface'] -match 'Describe') `
  ("has section=" + $rec.ContainsKey('Class surface'))

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- the thing that must NOT have changed: a top-level routine' -ForegroundColor Cyan
$fun = Sections 'modify uCtxType.Helper'
Write-Host ("  sections: " + (($fun.Keys | Sort-Object) -join ', ')) -ForegroundColor DarkGray
# Chopping the last segment of `uCtxType.Helper` gives the UNIT. A unit has no
# class surface, and the fix must not have taught it to grow one -- that would
# stuff every routine's bundle with the unit's whole declaration list.
$funSurface = if ($fun.ContainsKey('Class surface')) { $fun['Class surface'].Trim() } else { '' }
Check 'CONTROL: a unit-level routine gets no class surface' ($funSurface -eq '') `
  ("surface=[" + ($funSurface -replace "`n", ' / ') + "]")

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
