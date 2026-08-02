<#
  run_consumer_contract.ps1 -- the four consumer-facing contract items the
  conversion team asked for in INBOX 2.4, 2.6 and 2.8.

  All four are about a CONSUMER being able to trust what it gets back. None of
  them changes what is indexed; they change what is reachable and what is
  distinguishable.

  2.4a --exact suppresses the fuzzy fallback. Their report was that
       `--name TNotifyEvent` returned a local named `ANotifyEvent`, so every
       caller had to filter client-side and "take the first hit" was always
       wrong. match_kind (run_query_case_insensitive.ps1) labels such a row, but
       a consumer that never wants suggestions should not have to receive them.
       With --exact, zero rows means "no such symbol" and nothing else.

  2.4b --name accepts a QUALIFIED name. `--name Abcbtn.TabcButtonStyle` used to
       return [] exit 1, so a caller had to know which flag a given string
       wanted. A bare identifier cannot contain a dot, so a dotted --name is
       unambiguous -- and it is tried only after the bare lookup misses.

  2.6  ENUM MEMBERS are reachable. They were always indexed (kind='enum_value',
       qualified_name '<EnumQName>.<member>') but no query returned them:
       `query --qname <Enum>` gave only the enum, `hover` did not list them, and
       `surface` refused outright. The team parsed the declaration's source
       range to recover data the index already held. surface answers "what
       members does this type have?", so it now answers it for enums.

  2.8  --quiet suppresses the '(loaded defaults from ...)' banner. It is already
       on stderr and stdout alone is clean JSON, but their RunCapture MERGES the
       streams, which corrupts the JSON; they work around it with a
       balanced-bracket scan. THE STDOUT CHECK BELOW IS THE LOAD-BEARING ONE:
       --quiet must not be the only thing standing between a consumer and valid
       JSON, so stdout is asserted parseable in BOTH modes.

  Usage: pwsh -File tests/autotest/run_consumer_contract.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-consumer-contract"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $work 'ContractKit.pas') @'
unit ContractKit;

interface

type
  TAlignKind = (akLeft, akCenter, akRight);

  TWidget = class(TObject)
  private
    FAlign: TAlignKind;
  public
    property Align: TAlignKind read FAlign write FAlign;
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'contract.sqlite'
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Rows([string[]]$ExtraArgs) {
  $a = @('query') + $ExtraArgs + @('--db', $db, '--json')
  $raw = @(& $Exe @a 2>$null) | ForEach-Object { "$_" }
  $txt = ($raw -join "`n").Trim()
  if (-not $txt.StartsWith('[')) { return @() }
  return @($txt | ConvertFrom-Json)
}

# --- 2.4a --exact -------------------------------------------------------------
Write-Host ''
Write-Host '2.4a -- --exact suppresses the fuzzy fallback' -ForegroundColor Cyan
# A name close enough for the fuzzy fallback to answer, but not present.
$loose = Rows @('--name', 'TWidgetX')
Check 'without --exact, a near-miss DOES get a suggestion' ($loose.Count -gt 0) "rows=$($loose.Count)"
if ($loose.Count -gt 0) {
  Check 'and it is labelled match_kind=fuzzy' ($loose[0].match_kind -eq 'fuzzy') "match_kind=$($loose[0].match_kind)"
}
$strict = Rows @('--name', 'TWidgetX', '--exact')
Check 'with --exact, the same query returns NOTHING' ($strict.Count -eq 0) "rows=$($strict.Count)"

# --exact must not break a genuine hit -- otherwise it would "pass" by returning
# nothing for everything.
$stillFinds = Rows @('--name', 'TWidget', '--exact')
Check '--exact still returns a REAL hit' ($stillFinds.Count -eq 1) "rows=$($stillFinds.Count)"
if ($stillFinds.Count -eq 1) {
  Check 'and labels it match_kind=exact' ($stillFinds[0].match_kind -eq 'exact') "match_kind=$($stillFinds[0].match_kind)"
}

# --- 2.4b --name accepts a qualified name -------------------------------------
Write-Host ''
Write-Host '2.4b -- --name accepts a qualified name' -ForegroundColor Cyan
$byQualified = Rows @('--name', 'ContractKit.TWidget')
Check '--name with a DOTTED value resolves' ($byQualified.Count -eq 1) "rows=$($byQualified.Count)"
if ($byQualified.Count -eq 1) {
  Check 'it is the right symbol' ($byQualified[0].qualified_name -eq 'ContractKit.TWidget') `
    "qname=$($byQualified[0].qualified_name)"
  Check 'and it is an EXACT match, not a fuzzy consolation' ($byQualified[0].match_kind -eq 'exact') `
    "match_kind=$($byQualified[0].match_kind)"
}
# The bare lookup must still win -- the qualified fallback is only tried on a miss.
$bare = Rows @('--name', 'TWidget')
Check 'a BARE name still resolves as before' ($bare.Count -eq 1) "rows=$($bare.Count)"

# --- 2.6 enum members are reachable -------------------------------------------
Write-Host ''
Write-Host '2.6 -- enum members are reachable without reading source' -ForegroundColor Cyan
$rawEnum = @(& $Exe surface --qname 'ContractKit.TAlignKind' --db $db --format json 2>$null) | ForEach-Object { "$_" }
$enumTxt = ($rawEnum -join "`n").Trim()
Check 'surface accepts an ENUM (no longer refuses)' ($enumTxt.StartsWith('{')) `
  $(if ($enumTxt.Length -gt 60) { $enumTxt.Substring(0, 60) } else { $enumTxt })
if ($enumTxt.StartsWith('{')) {
  $enum = $enumTxt | ConvertFrom-Json
  $names = @($enum.members | ForEach-Object { $_.name })
  Check 'all three members are returned' ($names.Count -eq 3) "members=$($names -join ',')"
  Check 'in DECLARATION order, with ordinals' `
    (($names -join ',') -ceq 'akLeft,akCenter,akRight') "order=$($names -join ',')"
  $ords = @($enum.members | ForEach-Object { $_.ordinal })
  Check 'ordinals are 0..N-1' (($ords -join ',') -eq '0,1,2') "ordinals=$($ords -join ',')"
  Check 'each member carries its qualified name' `
    ($enum.members[0].qualified_name -eq 'ContractKit.TAlignKind.akLeft') `
    "first=$($enum.members[0].qualified_name)"
}

# --- 2.8 --quiet, and stdout is ALWAYS clean ----------------------------------
Write-Host ''
Write-Host '2.8 -- --quiet, and stdout parseable either way' -ForegroundColor Cyan
$outF = Join-Path $WorkDir 'o.txt'; $errF = Join-Path $WorkDir 'e.txt'
function RunSplit([string[]]$A) {
  Start-Process $Exe -ArgumentList $A -RedirectStandardOutput $outF -RedirectStandardError $errF `
    -NoNewWindow -Wait | Out-Null
  return @{
    Out = [string]::Join("`n", @(Get-Content $outF -ErrorAction SilentlyContinue))
    Err = [string]::Join(' ',  @(Get-Content $errF -ErrorAction SilentlyContinue))
  }
}
# Run from a directory under a .drag-lint.json so the banner has a reason to fire.
Push-Location 'C:\Projects'
try {
  $loud  = RunSplit @('query', '--name', 'TWidget', '--db', $db, '--json')
  $quiet = RunSplit @('query', '--name', 'TWidget', '--db', $db, '--json', '--quiet')
} finally { Pop-Location }

Check 'without --quiet the banner IS emitted (de-vacuates the next check)' `
  ($loud.Err -match 'loaded defaults') "stderr='$($loud.Err)'"
Check 'with --quiet the banner is GONE' (-not ($quiet.Err -match 'loaded defaults')) `
  "stderr='$($quiet.Err)'"
# The point of the flag is JSON that survives a stream-merging consumer, so
# assert stdout is valid JSON in BOTH modes -- --quiet must be a convenience,
# never the only thing keeping stdout parseable.
foreach ($m in @(@{n='without --quiet'; v=$loud}, @{n='with --quiet'; v=$quiet})) {
  $ok = $false
  try { $null = $m.v.Out | ConvertFrom-Json; $ok = $true } catch { $ok = $false }
  Check "stdout alone is valid JSON $($m.n)" $ok
}

Write-Host ''
if ($script:Failed) { Write-Host 'CONSUMER CONTRACT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'CONSUMER CONTRACT: PASS' -ForegroundColor Green
exit 0
