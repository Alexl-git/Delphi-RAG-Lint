<#
  run_docs_manifest_roundtrip.ps1 -- Batch B Task 6: headless proxy for the
  IDE Linter Options page's docs.max_return_cases read/write contract.

  BACKGROUND: Batch B Task 3 added a Linter Options frame
  (DragLint.Plugin.OptionsFrames.pas, TDLLinterOptionsFrame) that reads and
  writes ONE manifest key -- docs.max_return_cases -- via direct JSON
  read-modify-write (WriteMaxReturnCases: parse existing file if present,
  reuse or create the "docs" object, RemovePair+AddPair "max_return_cases",
  re-serialise the WHOLE root so every OTHER top-level/docs.* key survives
  untouched). That frame code cannot be exercised headlessly (it needs a
  live IDE + open project via IOTAModuleServices). This test exercises the
  CLI's consumption of the SAME manifest key/shape as a headless proxy: if
  the CLI's manifest parsing of docs.max_return_cases regresses, the frame's
  contract (same key, same file shape, same DOTTED-local-vs-undotted-global
  distinction) has silently broken too.

  MANIFEST-FILENAME FACts (verified against src/index/DRagLint.Index.Manifest.pas):
  - TManifestIO.Load's LOCAL override is read ONLY from a DOTTED
    ".drag-lint.json", found by walking UP from the CURRENT WORKING
    DIRECTORY (~line 491). This is exactly what the frame's
    ManifestPathForWrite writes for the per-project case (project dir +
    ".drag-lint.json") -- see OptionsFrames.pas ManifestPathForWrite, which
    explicitly documents matching the CLI's local walk.
  - An UNDOTTED "drag-lint.json" is read ONLY as the GLOBAL config, and ONLY
    from the directory beside drag-lint.exe itself (~line 474). The frame
    also mirrors this for its no-project-open fallback.
  - Therefore the local fixture in THIS test uses a DOTTED ".drag-lint.json"
    dropped into a Push-Location'd work dir, mirroring run_doc_returns.ps1
    Scenario B exactly.

  NO MANIFEST-EMIT VERB EXISTS (checked before writing this test): grepping
  the CLI shows DRagLint.CLI.pas defines a ManifestToJson() function (~line
  930, delegating to TManifestIO.ToJson which DOES include the "docs" block)
  but it has ZERO call sites anywhere in the CLI -- dead code, not wired to
  any verb. The only reachable --json manifest dump is `index --all
  --dry-run --json`, which goes through PlanToJson (NOT ManifestToJson) and
  only embeds "settings"/"rootDir"/"indexes", never "docs". resolve-dbs
  --json only prints resolved DB paths. So there is no CLI-observable
  round-trip of the raw JSON text to assert "settings.sizeGuardMB survived
  the docs edit" against.

  Given that, this test's teeth are:
    1. CAP-EFFECT (the definitive, non-tautological assertion, mirroring
       run_doc_returns.ps1 Scenario B): a DOTTED .drag-lint.json with
       docs.max_return_cases=N causes `document` to emit EXACTLY N
       Observed: cases for a fixture function with MORE than N distinct
       return cases -- and that capped output DIFFERS from the default
       (uncapped) output. This proves the CLI actually reads
       docs.max_return_cases out of the DOTTED local file the frame writes
       into, using the frame's exact file shape.
    2. KEY-COEXISTENCE UNDER THE CAP: the SAME fixture manifest also carries
       an unrelated "settings" block (settings.sizeGuardMB) alongside
       "docs.max_return_cases" -- exactly the shape WriteMaxReturnCases
       produces when it read-modify-writes an existing manifest that
       already has other keys. The cap-effect assertion above is run
       against THIS combined-key manifest (not a docs-only one), proving
       the presence of an unrelated top-level key does not perturb
       max_return_cases parsing.
  Full BYTE-level key-preservation (i.e. "settings.sizeGuardMB unchanged in
  the file after a save") is NOT independently re-provable here because no
  verb echoes the manifest back; that half of the contract is verified by
  INSPECTION of the frame's own code (WriteMaxReturnCases: reuses the
  existing "docs" TJSONObject if present, RemovePair-before-AddPair only
  touches "max_return_cases", then Root.ToJSON re-serialises the WHOLE
  parsed root -- so sibling keys the parser did not touch are necessarily
  emitted verbatim). See OptionsFrames.pas lines ~552-602.

  This test does NOT fabricate an always-true assertion in place of that:
  the cap-effect check (item 1) is the teeth, and it is a real CLI behavior
  that fails if the manifest wiring regresses (proven via a throwaway
  wrong-cap manual run during development -- see task report).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-docs-roundtrip"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
# Resolve $Exe to an ABSOLUTE path up front: the cap scenario Push-Location's
# into a fixture dir, which breaks a RELATIVE -Exe (it would no longer
# resolve from the new CWD). Absolutize once so every '& $Exe' works
# regardless of CWD (mirrors run_doc_returns.ps1's discipline).
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Fixture: Grab has 3 distinct mined return cases (True; False; rlines <> 0 --
# more than our cap of 2, so the cap must visibly TRUNCATE the enumeration).
$FixtureBody = @'
unit uRoundtrip;
interface
function Grab(const AWidth: Integer): Boolean;
implementation
function Grab(const AWidth: Integer): Boolean;
var rlines: Integer;
begin
  Result := True;
  Result := False;
  rlines := AWidth;
  Result := rlines <> 0;
end;
end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

function Get-ReturnsTag([string]$Text) {
  # Unary comma forces PowerShell to return the array as-is: without it, a
  # SINGLE-element array gets unwrapped back to a bare string when a function
  # returns it, silently turning $result[0] into a CHARACTER index instead of
  # the array element (a classic PS gotcha -- caught during dev via a failing
  # baseline assertion that made no sense until traced to this).
  , @([regex]::Matches($Text, '<returns>.*?</returns>') | ForEach-Object { $_.Value })
}

Write-Host 'Baseline: default cap (no manifest), all 3 mined cases present' -ForegroundColor Cyan
$dirBase = Join-Path $WorkDir 'baseline'
New-Item -ItemType Directory $dirBase | Out-Null
$fileBase = Join-Path $dirBase 'uRoundtrip.pas'
$dbBase   = Join-Path $dirBase 'baseline.sqlite'
Write-Fixture $fileBase
& $Exe index $dirBase --db $dbBase 2>&1 | Out-Null
& $Exe document --qname uRoundtrip.Grab --db $dbBase --apply --no-backup 2>&1 | Out-Null
$textBase = Get-Content $fileBase -Raw
$returnsBase = Get-ReturnsTag $textBase
Check 'baseline: exactly one <returns> tag' ($returnsBase.Count -eq 1) "count=$($returnsBase.Count)"
Check 'baseline (uncapped): all 3 cases observed' `
  ($returnsBase.Count -gt 0 -and $returnsBase[0] -match 'True' -and $returnsBase[0] -match 'False' -and $returnsBase[0] -match 'rlines') `
  $returnsBase[0]

Write-Host ''
Write-Host 'Cap-effect + key-coexistence: docs.max_return_cases=2 alongside an unrelated settings block, via DOTTED .drag-lint.json' -ForegroundColor Cyan
$dirCap = Join-Path $WorkDir 'cap'
New-Item -ItemType Directory $dirCap | Out-Null
$fileCap = Join-Path $dirCap 'uRoundtrip.pas'
$dbCap   = Join-Path $dirCap 'cap.sqlite'
Write-Fixture $fileCap

# The fixture manifest mirrors what TDLLinterOptionsFrame.WriteMaxReturnCases
# produces when it read-modify-writes a manifest that ALREADY has an
# unrelated top-level key: "settings" (sizeGuardMB) survives untouched
# alongside the "docs" block it edits. Placed as a DOTTED .drag-lint.json --
# TManifestIO.Load's LOCAL override slot (walked up from CWD), NOT the
# undotted global-beside-exe slot.
$cfgPath = Join-Path $dirCap '.drag-lint.json'
'{ "settings": { "sizeGuardMB": 1500 }, "docs": { "max_return_cases": 2 } }' |
  Set-Content $cfgPath -Encoding ascii
Check 'fixture .drag-lint.json is valid JSON' `
  ((Get-Content $cfgPath -Raw | ConvertFrom-Json) -ne $null)

& $Exe index $dirCap --db $dbCap 2>&1 | Out-Null
Push-Location $dirCap
try {
  & $Exe document --qname uRoundtrip.Grab --db $dbCap --apply --no-backup 2>&1 | Out-Null
} finally {
  Pop-Location
}
$textCap = Get-Content $fileCap -Raw
$returnsCap = Get-ReturnsTag $textCap

Check 'cap=2: exactly one <returns> tag' ($returnsCap.Count -eq 1) "count=$($returnsCap.Count)"
Check 'cap=2: Observed: present' ($returnsCap.Count -gt 0 -and $returnsCap[0] -match 'Observed:') $returnsCap[0]
Check 'cap=2: keeps first two cases (True, False)' `
  ($returnsCap.Count -gt 0 -and $returnsCap[0] -match 'True' -and $returnsCap[0] -match 'False') $returnsCap[0]
Check 'cap=2: drops third case (rlines is absent from the tag)' `
  ($returnsCap.Count -gt 0 -and -not ($returnsCap[0] -match 'rlines')) $returnsCap[0]
Check 'cap=2 <returns> DIFFERS from uncapped baseline (proves the manifest wire works, not a coincidence)' `
  ($returnsCap.Count -gt 0 -and $returnsBase.Count -gt 0 -and $returnsCap[0] -ne $returnsBase[0]) `
  "cap=$($returnsCap[0]) baseline=$($returnsBase[0])"
Check 'unrelated settings.sizeGuardMB key did not prevent docs.max_return_cases from being read (still capped, not defaulted to 20)' `
  ($returnsCap.Count -gt 0 -and -not ($returnsCap[0] -match 'rlines')) $returnsCap[0]

Write-Host ''
Write-Host 'NOTE: full byte-level key-preservation (settings.sizeGuardMB unchanged after' -ForegroundColor DarkYellow
Write-Host 'a save) has no CLI emit-verb to assert against -- ManifestToJson exists in' -ForegroundColor DarkYellow
Write-Host 'DRagLint.CLI.pas but has zero call sites (dead code); index --all --dry-run' -ForegroundColor DarkYellow
Write-Host '--json uses PlanToJson instead, which never surfaces "docs". That half of the' -ForegroundColor DarkYellow
Write-Host 'contract is verified by inspection of WriteMaxReturnCases (RemovePair+AddPair' -ForegroundColor DarkYellow
Write-Host 'targets ONLY max_return_cases; Root.ToJSON re-serialises the whole parsed root,' -ForegroundColor DarkYellow
Write-Host 'so untouched sibling keys are necessarily preserved verbatim).' -ForegroundColor DarkYellow

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
