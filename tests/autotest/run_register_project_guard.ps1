<#
  run_register_project_guard.ps1 -- a NEW project can be added to the manifest,
  and the two manifest copies never disagree about which projects exist.

  THE GAP (owner, live IDE, 2026-08-24). Opening a brand-new project and asking
  drag-lint to index it produced a dead end:

      drag-lint: no index section owns this project, so there is nothing to
      rebuild. ... Add a section for this project to the manifest (or check the
      manifest parses), then run this again.

  The refusal is CORRECT and this guard does not weaken it -- `--rebuild` clears
  a whole database, and resolving the target by folder prefix once emptied a
  SIBLING project's index and refilled it with the wrong compile closure. What
  was missing was any way to ACT on the message: DRagLint.Index.Manifest is
  read-only, so the engine had no writer and the plugin had no verb to call.

  WHAT THIS ASSERTS, and why each half is here rather than just "it worked once":

    DRY RUN BY DEFAULT. Registration edits config the whole machine reads. A
    verb that writes on being merely invoked is the wrong default, and the
    assertion that a bare run changes NOTHING is the one that pins it.

    EVERY COPY OR NONE. The manifest exists twice on a normal install -- beside
    the engine (dll-win64\) and beside the design-time BPL (dll-win32\) -- and
    each side loads the one next to itself. Updating one would leave the IDE and
    the CLI disagreeing about which projects exist: a silent split-brain, which
    is the failure shape this codebase keeps paying for. Byte-equality of the
    two copies is checked before AND after.

    REFUSING AN ALREADY-OWNED PROJECT. Registering a second owner would
    manufacture the exact ambiguity the IDE's reindex command exists to refuse.

    AND THEN IT ACTUALLY INDEXES. The point of registering is not a tidier JSON
    file; it is that `index --all --only <Section>` now builds a database. A
    guard that stopped at "the section was written" would pass for a
    registration that named the project in a way the indexer could not use.

  Everything happens on a COPY of the manifests in a scratch engine dir, so the
  real ones are never touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-register-project"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Sha($p) { (Get-FileHash $p -Algorithm SHA256).Hash }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# A scratch install: two sibling engine dirs, each with its own manifest copy,
# mirroring third_party\dll-win64\ + dll-win32\.
$Inst = Join-Path $WorkDir 'third_party'
$E64  = Join-Path $Inst 'dll-win64'
$E32  = Join-Path $Inst 'dll-win32'
New-Item -ItemType Directory $E64 | Out-Null
New-Item -ItemType Directory $E32 | Out-Null

$Proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory $Proj | Out-Null
WriteAnsi (Join-Path $Proj 'uThing.pas') @'
unit uThing;
interface
const
  Answer = 42;
implementation
end.
'@
WriteAnsi (Join-Path $Proj 'Thing.dpr') @'
program Thing;
uses
  uThing in 'uThing.pas';
begin
end.
'@
$ProjFile = Join-Path $Proj 'Thing.dpr'

# An OWNED project, so the refusal path has something real to refuse.
$Owned = Join-Path $WorkDir 'owned'
New-Item -ItemType Directory $Owned | Out-Null
WriteAnsi (Join-Path $Owned 'Owned.dpr') "program Owned;`nbegin`nend.`n"
$OwnedFile = Join-Path $Owned 'Owned.dpr'

$manifest = @"
{
  "_comment": "a key the reader does not model -- it must survive a write",
  "settings": { "defaultPlatform": "Win64" },
  "indexes": {
    "outDir": "$($WorkDir -replace '\\','\\')",
    "sections": [
      { "name": "AlreadyOwned", "include": ["$($OwnedFile -replace '\\','\\')"] }
    ]
  }
}
"@
WriteAnsi (Join-Path $E64 'drag-lint.json') $manifest
WriteAnsi (Join-Path $E32 'drag-lint.json') $manifest

# The engine must run FROM the scratch dir, because it locates manifests
# relative to its own exe. Copy it plus the tree-sitter companions.
Get-ChildItem (Split-Path $Exe) -File | Where-Object { $_.Extension -in '.exe', '.dll' } |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $E64 $_.Name) -Force }
$ScratchExe = Join-Path $E64 'drag-lint.exe'
Check 'scratch engine staged' (Test-Path $ScratchExe)

$M64 = Join-Path $E64 'drag-lint.json'
$M32 = Join-Path $E32 'drag-lint.json'
$before64 = Sha $M64
Check 'the two manifest copies start identical' ((Sha $M64) -eq (Sha $M32))

# ---- DRY RUN BY DEFAULT ----------------------------------------------------
Write-Host ''
Write-Host 'DRY RUN: reports, and changes nothing' -ForegroundColor Cyan
$dry = & $ScratchExe register-project $ProjFile 2>&1 | Out-String
Check 'dry run names the section it would add' ($dry -match 'WOULD register section "Thing"') $($dry.Trim() -split "`n" | Select-Object -First 1)
Check 'dry run names BOTH manifest copies' (($dry -match 'dll-win64') -and ($dry -match 'dll-win32'))
Check 'dry run wrote NOTHING' (((Sha $M64) -eq $before64) -and ((Sha $M32) -eq $before64)) 'both copies unchanged'

# ---- REFUSAL ---------------------------------------------------------------
Write-Host ''
Write-Host 'REFUSAL: an already-owned project is not registered twice' -ForegroundColor Cyan
$own = & $ScratchExe register-project $OwnedFile --apply 2>&1 | Out-String
Check 'an owned project is reported as already registered' ($own -match 'already registered')
Check 'and it names the owning section' ($own -match 'AlreadyOwned')
Check 'and it wrote NOTHING even with --apply' (((Sha $M64) -eq $before64) -and ((Sha $M32) -eq $before64))

# ---- APPLY -----------------------------------------------------------------
Write-Host ''
Write-Host 'APPLY: every copy, or none' -ForegroundColor Cyan
$app = & $ScratchExe register-project $ProjFile --apply 2>&1 | Out-String
Check 'apply reports the section as registered' ($app -match 'registered section "Thing"')
Check 'BOTH copies changed' (((Sha $M64) -ne $before64) -and ((Sha $M32) -ne $before64))
Check 'and they are still byte-identical to each other' ((Sha $M64) -eq (Sha $M32)) 'a split manifest is the defect this guards'

$j = Get-Content $M64 -Raw | ConvertFrom-Json
Check 'the new section is present' (@($j.indexes.sections | Where-Object { $_.name -eq 'Thing' }).Count -eq 1)
Check 'the pre-existing section survived' (@($j.indexes.sections | Where-Object { $_.name -eq 'AlreadyOwned' }).Count -eq 1)
# The writer edits the JSON rather than re-serialising the parsed record. A
# round-trip through TIndexManifest would silently drop every key the reader
# does not model, which is a worse defect than the one being fixed.
Check 'a key the READER does not model survived the write' ($null -ne $j._comment) 'the _comment block'
Check 'settings survived the write' ($j.settings.defaultPlatform -eq 'Win64')

# ---- AND THEN IT ACTUALLY INDEXES ------------------------------------------
Write-Host ''
Write-Host 'THE POINT: the registered project can now be indexed' -ForegroundColor Cyan
& $ScratchExe index --all --only Thing 2>&1 | Out-Null
$db = Join-Path $Proj '_D-RAG\Thing.sqlite'
Check 'index --all --only <Section> built the database' (Test-Path $db) "db=$db"
if (Test-Path $db) {
  $q = & $ScratchExe query --name Answer --db $db --json 2>&1 | Out-String
  Check 'and the index answers a symbol from that project' ($q -match '"name"\s*:\s*"Answer"') 'const Answer'
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
