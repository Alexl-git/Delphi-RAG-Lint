<#
  run_unit_usage_project_wide.ps1 -- `query unit-usage --unit U` with NO --in
  answers the REVERSE question: which files reference the unit at all.

  WHY IT EXISTS (gap G1 of DataCopy's 2026-09-02 grep-fallback audit)
  ------------------------------------------------------------------
  `unit-usage` answered one file at a time. The question that actually arises is
  project-wide -- "which units here reference X?" -- and answering it needed a
  shell loop over every file, "which is enough friction that grep wins". This
  suite pins the mode that removed the loop.

  THE BUG THIS FIXTURE IS SHAPED AROUND, because it is the one that really
  happened while building the feature
  ----------------------------------------------------------------------------
  ISymbolStore.FindUsersOfUnit keys on unit_uses.unit_name_norm, which is the
  lowercased TRAILING dotted segment -- 'lib', not 'a.lib'. The first build
  passed the full dotted name and got ZERO ROWS, which printed as

      0 of 0 importing file(s) reference it

  -- the most confidently wrong answer this verb can give, and one nothing would
  have flagged. The cure (normalise to the tail, then filter the rows on the
  FULL name) introduces its own hazard: A.Lib and B.Lib share the tail 'lib', so
  a query about one must not report importers of the other.

  So the fixture DELIBERATELY CONTAINS THAT COLLISION -- two units whose names
  normalise identically -- and asks about each in turn, requiring an EXACT file
  set both times. Without the filter both queries return both importers, so the
  two assertions cannot both pass by accident. A fixture without the collision
  would have tested nothing, which is this repo's commonest self-inflicted
  wound.

  THE OTHER CONTROLS
  ------------------
  * A file that imports the unit but references nothing must be reported as a
    DEAD IMPORT, not omitted -- that is the answer people want when deciding
    whether a unit can be deleted, and it is the same judgement the per-file
    mode already makes.
  * A file that does NOT import the unit must not appear at all. The candidate
    set is the uses graph; if that ever degenerated into "every file", this
    check catches it.
  * The two modes must AGREE file by file. A project-wide answer that disagreed
    with the per-file one would be worse than no answer.
  * An unknown unit must ERROR, not report "0 of 0". Fabricating a zero for a
    unit that is not indexed is indistinguishable from a true "nothing uses it".

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-unit-usage-wide"
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
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
foreach ($old in (Get-ChildItem -LiteralPath $WorkDir -File -ErrorAction SilentlyContinue)) {
  [System.IO.File]::Delete($old.FullName)
}
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# ------------------------------------------------------------------ fixture --
# A.Lib and B.Lib normalise to the SAME unit_name_norm ('lib'). That collision is
# the point; see the header.
Write-Ascii (Join-Path $WorkDir 'A.Lib.pas') @'
unit A.Lib;

interface

type
  TAlpha = class
  public
    procedure Ping;
  end;

procedure AlphaHelper;

implementation

procedure TAlpha.Ping;
begin
end;

procedure AlphaHelper;
begin
end;

end.
'@

Write-Ascii (Join-Path $WorkDir 'B.Lib.pas') @'
unit B.Lib;

interface

type
  TBeta = class
  public
    procedure Pong;
  end;

implementation

procedure TBeta.Pong;
begin
end;

end.
'@

# Imports A.Lib and really uses it (both exports).
Write-Ascii (Join-Path $WorkDir 'UsesAndRefs.pas') @'
unit UsesAndRefs;

interface

procedure Go;

implementation

uses
  A.Lib;

procedure Go;
var
  X: TAlpha;
begin
  X := TAlpha.Create;
  try
    X.Ping;
    AlphaHelper;
  finally
    X.Free;
  end;
end;

end.
'@

# Imports A.Lib and references nothing from it -- a DEAD IMPORT.
Write-Ascii (Join-Path $WorkDir 'UsesOnly.pas') @'
unit UsesOnly;

interface

procedure Idle;

implementation

uses
  A.Lib;

procedure Idle;
begin
end;

end.
'@

# Imports the COLLIDING unit only. Must never appear in an A.Lib answer.
Write-Ascii (Join-Path $WorkDir 'UsesOther.pas') @'
unit UsesOther;

interface

procedure Beta;

implementation

uses
  B.Lib;

procedure Beta;
var
  Y: TBeta;
begin
  Y := TBeta.Create;
  try
    Y.Pong;
  finally
    Y.Free;
  end;
end;

end.
'@

# Imports neither. Must never appear at all.
Write-Ascii (Join-Path $WorkDir 'NoUses.pas') @'
unit NoUses;

interface

procedure Alone;

implementation

procedure Alone;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'wide.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

function Wide([string]$UnitName) {
  $rows = @()
  foreach ($line in (& $Exe query unit-usage --unit $UnitName --db $db 2>&1)) {
    $t = "$line"
    if ($t -match '^\s{2}(\S.*?\.(?:pas|dpr))\s+uses\(([a-z]+)\)\s+(DEAD IMPORT|(\d+) ref)') {
      $rows += [pscustomobject]@{
        Name = [System.IO.Path]::GetFileName($Matches[1])
        Section = $Matches[2]
        Refs = $(if ($Matches[3] -eq 'DEAD IMPORT') { 0 } else { [int]$Matches[4] })
      }
    }
  }
  return ,@($rows)
}
function PerFileUsed([string]$File, [string]$UnitName) {
  foreach ($line in (& $Exe query unit-usage --in (Join-Path $WorkDir $File) --unit $UnitName --db $db 2>&1)) {
    if ("$line" -match '^(\d+) of (\d+) export\(s\) referenced') { return [int]$Matches[1] }
  }
  return -1
}

Write-Host ''
Write-Host 'THE FEATURE -- --unit with no --in answers project-wide' -ForegroundColor Cyan
$a = Wide 'A.Lib'
Write-Host ("  A.Lib importers: " + (($a | ForEach-Object { "$($_.Name)=$($_.Refs)" }) -join ', ')) -ForegroundColor DarkGray
Check 'the query returned rows at all' ($a.Count -gt 0) `
  'a zero here is the exact failure this suite was built after -- it reads as "nothing uses this unit"'

$aNames = @($a | ForEach-Object { $_.Name } | Sort-Object)
Check 'exactly the two A.Lib importers are listed' (
  ($aNames -join ',') -eq 'UsesAndRefs.pas,UsesOnly.pas') "got: $($aNames -join ', ')"

$refs = @($a | Where-Object { $_.Name -eq 'UsesAndRefs.pas' })
Check 'the real consumer is reported as referencing' (($refs.Count -eq 1) -and ($refs[0].Refs -gt 0)) `
  "refs=$(if ($refs.Count) { $refs[0].Refs } else { 'absent' })"

$dead = @($a | Where-Object { $_.Name -eq 'UsesOnly.pas' })
Check 'the importer that references nothing is a DEAD IMPORT' (($dead.Count -eq 1) -and ($dead[0].Refs -eq 0)) `
  'it must be REPORTED, not omitted -- that is the answer when deciding if a unit can go'

Write-Host ''
Write-Host 'POSITIVE CONTROL -- the candidate set is the USES GRAPH, not every file' -ForegroundColor Cyan
Check 'a file that imports nothing is absent' (-not ($aNames -contains 'NoUses.pas'))

Write-Host ''
Write-Host 'THE COLLISION -- A.Lib and B.Lib share the tail the index keys on' -ForegroundColor Cyan
# Both normalise to 'lib'. Without the full-name filter BOTH queries return BOTH
# importers, so these two assertions cannot both pass by accident.
Check 'an A.Lib query does not list the B.Lib importer' (-not ($aNames -contains 'UsesOther.pas')) `
  "A.Lib importers: $($aNames -join ', ')"
$b = Wide 'B.Lib'
$bNames = @($b | ForEach-Object { $_.Name } | Sort-Object)
Write-Host ("  B.Lib importers: " + ($bNames -join ', ')) -ForegroundColor DarkGray
Check 'a B.Lib query lists exactly its own importer' (($bNames -join ',') -eq 'UsesOther.pas') `
  "got: $($bNames -join ', ')"

Write-Host ''
Write-Host 'THE TWO MODES MUST AGREE, file by file' -ForegroundColor Cyan
foreach ($row in $a) {
  $n = PerFileUsed $row.Name 'A.Lib'
  Check "$($row.Name): per-file and project-wide agree" (
    (($n -gt 0) -eq ($row.Refs -gt 0)) -and ($n -ge 0)) `
    "per-file says $n export(s) referenced, project-wide says $($row.Refs) ref(s)"
}

Write-Host ''
Write-Host 'AN UNKNOWN UNIT MUST ERROR, NOT REPORT ZERO USERS' -ForegroundColor Cyan
$out = (& $Exe query unit-usage --unit NoSuchUnitAtAll --db $db 2>&1 | Out-String)
$code = $LASTEXITCODE
Check 'it exits non-zero' ($code -ne 0) "exit=$code"
Check 'it says the unit is not indexed' ($out -match 'no interface-section symbols found') $out.Trim()
Check 'and it does NOT claim zero importers' (-not ($out -match 'importing file\(s\) reference it')) `
  'a fabricated 0 is indistinguishable from a true "nothing uses it"'

Write-Host ''
Write-Host 'JSON agrees with the text output' -ForegroundColor Cyan
$json = (& $Exe query unit-usage --unit A.Lib --db $db --json 2>&1 | Where-Object { "$_" -match '^\[' } | Select-Object -First 1)
$parsed = $null
try { $parsed = @($json | ConvertFrom-Json) } catch { }
Check '--json emits a parseable array' ($null -ne $parsed) "$json"
if ($null -ne $parsed) {
  Check '--json lists the same file count' ($parsed.Count -eq $a.Count) "json=$($parsed.Count) text=$($a.Count)"
  $jDead = @($parsed | Where-Object { $_.file -like '*UsesOnly.pas' })
  Check '--json marks the dead import referenced:false' (
    ($jDead.Count -eq 1) -and (-not $jDead[0].referenced) -and ($jDead[0].ref_count -eq 0))
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
