<#
  run_doc_returns_type_guard.ps1 -- an engine-written <returns> carries the
  declared TYPE as well as the observed values.

  THE ASK (owner, 2026-08-24): "Do we have a 'returns' section in the
  documentation where we list all possible values assigned to result? We need to
  list those too in the documentation section together with the type of the
  result."

  Half of it already existed. EmitEngineReturns is an EITHER/OR:

      mined cases present -> <returns><!-- drag-lint:auto -->Observed: 1; 2.</returns>
      none                -> <returns><!-- drag-lint:auto type -->Integer</returns>

  so the moment the miner found anything, the declared type was dropped -- the
  reader was told what came out and not what shape it is. Exactly backwards for
  the common case, since a function with several return sites is the one whose
  type you most want stated.

  WHY THE TYPE GOES FIRST. It is the CERTAIN fact -- it is declared in the
  source. The observed list is mined from `Result :=` sites and is a sample, not
  a proof: a case the miner cannot see is missing from it, and the cap can
  truncate it. Leading with the declaration and following with the sample says
  which is which without a sentence explaining it.

  CONTROLS, both of which have bitten this file's neighbours before:
    * a function with NO mined cases must still emit its bare type, on the
      `auto type` marker -- the branch this change must not disturb;
    * a HAND-WRITTEN <returns> must be left completely alone. The engine only
      ever fills a managed or empty tag, and a guard that only checked the
      generated shape would pass with the author's prose overwritten.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-returns-type"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uRet.pas'
WriteAnsi $file @'
unit uRet;

interface

function Classify(AValue: Integer): Integer;
function Nameless: string;
function Opaque(const AList: TObject): TObject;
/// <returns>The author said this himself and it must survive.</returns>
function HandWritten: Boolean;

implementation

function Classify(AValue: Integer): Integer;
begin
  if AValue < 0 then
    Result := -1
  else if AValue = 0 then
    Result := 0
  else
    Result := 1;
end;

function Nameless: string;
begin
  Result := 'fixed';
end;

function Opaque(const AList: TObject): TObject;
begin
  Result := AList;
end;

function HandWritten: Boolean;
begin
  Result := True;
end;

end.
'@

$db = Join-Path $WorkDir 'ret.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)
& $Exe document --unit $file --db $db --apply --no-backup 2>&1 | Out-Null

$lines = [System.IO.File]::ReadAllLines($file)
function ReturnsFor([string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return '<decl not found>' }
  for ($j = $idx - 1; $j -ge 0 -and $lines[$j].TrimStart() -match '^///'; $j--) {
    if ($lines[$j] -match '<returns>') { return $lines[$j].Trim() }
  }
  return '<no returns tag>'
}

Write-Host ''
Write-Host 'THE ASK: the type travels WITH the observed values' -ForegroundColor Cyan
$classify = ReturnsFor '^function Classify\(AValue: Integer\): Integer;'
Check 'Classify: the observed values are listed' ($classify -match 'Observed:') "got='$classify'"
Check 'Classify: the DECLARED TYPE is stated too' ($classify -match '\bInteger\b') "got='$classify'"
Check 'Classify: type comes before the observed sample' `
  ($classify -match 'Integer\b[^<]*Observed:') "got='$classify'"

$opaque = ReturnsFor '^function Opaque\(const AList: TObject\): TObject;'
Check 'Opaque: a class-typed return states its type as well' `
  (($opaque -match 'TObject') -and ($opaque -match 'Observed:')) "got='$opaque'"

Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan
# Nameless has exactly one mined case, so it exercises the SAME branch -- the
# point of it is that a single case is still a sample, not a substitute for the
# declared type.
$nameless = ReturnsFor '^function Nameless: string;'
Check 'CONTROL: a single mined case still states the type' `
  (($nameless -match '\bstring\b') -and ($nameless -match 'Observed:')) "got='$nameless'"

# The engine fills a managed or EMPTY tag only. If this ever reads anything but
# the author's sentence, the change has started overwriting prose.
$hand = ReturnsFor '^function HandWritten: Boolean;'
Check 'CONTROL: a hand-written <returns> is untouched' `
  ($hand -match 'The author said this himself and it must survive\.') "got='$hand'"
Check 'CONTROL: and it carries no engine marker' `
  ($hand -notmatch 'drag-lint:auto') "got='$hand'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
