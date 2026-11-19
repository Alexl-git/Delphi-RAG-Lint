<#
  run_v152_FINDOC.ps1 -- 1.52 lane FINDOC: the DOCAPPLY (1.51.1) FOUND list,
  each item reproduced here before anything was changed.

  CASES
    * OWN-ALL   `document-all` honours the index's ownRoots / excludeRoots:
                a unit outside the declared roots is not written.
    * OWN-UNIT  `document --unit <third-party file>` refuses it the same way.
    * OWN-HATCH --document-third-party still opens both (escape hatch).
    * OWN-CTRL  the project's own unit IS documented by document-all, and
                `document --project` already skipped the vendored unit (the
                behaviour the other two entry points now share).
    * JSON-PURE `document --project --json` stdout is ONE JSON document even
                when the DOCU5 tamper rescan fires (an in-process DoIndex).
    * JSON-CTRL the rescan really fired (its WARN is on stderr) -- else
                JSON-PURE proves nothing.
    * QNAME     items 1+2 (TAstParseCache keyed on the path; --qname skips the
                batch cache release): the only in-process reindex on the
                --qname path is the D-2 stale-anchor retry, and it runs BEFORE
                anything is written, so the cached tree still matches the
                disk. Pinned as a guard; it PASSED on the base engine, so
                neither item was confirmed and neither was changed.
    * QNAME-CTRL the retry really reindexed and the apply really wrote.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "dl-v152-findoc-$PID")
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function New-Fixture([string]$Root) {
  # Root\app\  App.dpr, uApp.pas, _D-RAG\drag-lint-project.json (ownRoots ".")
  # Root\vendor\uVendor.pas   <- in the closure, OUTSIDE ownRoots
  $app    = Join-Path $Root 'app'
  $vendor = Join-Path $Root 'vendor'
  foreach ($d in @($app, $vendor, (Join-Path $app '_D-RAG'))) { New-Item -ItemType Directory $d -Force | Out-Null }
  Write-Ascii (Join-Path $vendor 'uVendor.pas') @(
    'unit uVendor;', 'interface',
    'function VendorLen(const AName: string): Integer;',
    'implementation',
    'function VendorLen(const AName: string): Integer;',
    'begin',
    '  if AName = '''' then Result := 0 else Result := Length(AName);',
    'end;',
    'end.')
  Write-Ascii (Join-Path $app 'uApp.pas') @(
    'unit uApp;', 'interface',
    '/// <summary>Checks a number.</summary>',
    'procedure CheckN(const N: Integer);',
    '/// <summary>Runs the app.</summary>',
    'function AppDo(const AName: string): Integer;',
    'implementation',
    'uses System.SysUtils, uVendor;',
    'procedure CheckN(const N: Integer);',
    'begin',
    "  if N > 100 then raise EArgumentException.Create('too big');",
    'end;',
    'function AppDo(const AName: string): Integer;',
    'begin',
    '  Result := VendorLen(AName);',
    '  CheckN(Result);',
    'end;',
    'end.')
  Write-Ascii (Join-Path $app 'App.dpr') @(
    'program App;', 'uses', "  uApp in 'uApp.pas',", "  uVendor in '..\vendor\uVendor.pas';",
    'begin', "  Writeln(AppDo('x'));", 'end.')
  Write-Ascii (Join-Path $app '_D-RAG\drag-lint-project.json') @('{ "ownRoots": ["."] }')
  $db = Join-Path $app '_D-RAG\App.sqlite'
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index --project (Join-Path $app 'App.dpr') --db $db 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ App = $app; Db = $db; Proj = (Join-Path $app 'App.dpr')
    Vendor = (Join-Path $vendor 'uVendor.pas'); Own = (Join-Path $app 'uApp.pas') }
}
function Run-Doc($Fx, [string[]]$DocArgs) {
  Push-Location $Fx.App
  try { & { $ErrorActionPreference = 'Continue'; & $Exe @DocArgs --db $Fx.Db --apply --no-backup 2>&1 | ForEach-Object { "$_" } } | Out-String }
  finally { Pop-Location }
}
function Has-Engine([string]$Path) { ([IO.File]::ReadAllText($Path)) -match 'drag-lint:auto' }

try {
  Write-Host 'ITEM 3: document-all / --unit honour ownRoots (DOCAPPLY FOUND 4)' -ForegroundColor Cyan
  $fx = New-Fixture (Join-Path $WorkDir 'own')
  $q = & { $ErrorActionPreference = 'Continue'; & $Exe query --name VendorLen --db $fx.Db 2>&1 | ForEach-Object { "$_" } } | Out-String
  Check 'setup: uVendor is indexed (excluding it is a real decision)' ($q -match 'VendorLen')
  $vBefore = [IO.File]::ReadAllText($fx.Vendor)

  $o0 = Run-Doc $fx @('document', '--project', $fx.Proj)
  Check 'OWN-CTRL document --project skips the vendored unit' (([IO.File]::ReadAllText($fx.Vendor)) -ceq $vBefore) (($o0 -split "`r?`n" | Where-Object { $_ -match 'third-party' } | Select-Object -First 1))

  $o1 = Run-Doc $fx @('document-all')
  Check 'OWN-ALL document-all leaves the vendored unit byte-identical' (([IO.File]::ReadAllText($fx.Vendor)) -ceq $vBefore) (($o1 -split "`r?`n" | Where-Object { $_ -match 'third-party|^doc: \d' } | Select-Object -First 2) -join ' | ')
  Check 'OWN-ALL document-all names the skipped root' ($o1 -match 'skipped third-party root')
  Check 'OWN-CTRL document-all still documents the own unit' (Has-Engine $fx.Own)

  [IO.File]::WriteAllText($fx.Vendor, $vBefore, [Text.Encoding]::ASCII)
  $o2 = Run-Doc $fx @('document', '--unit', $fx.Vendor)
  Check 'OWN-UNIT document --unit leaves the vendored unit byte-identical' (([IO.File]::ReadAllText($fx.Vendor)) -ceq $vBefore) (($o2 -split "`r?`n" | Where-Object { $_ -match 'third-party|^doc: \d' } | Select-Object -First 2) -join ' | ')
  Check 'OWN-UNIT names why' ($o2 -match 'third-party')

  [IO.File]::WriteAllText($fx.Vendor, $vBefore, [Text.Encoding]::ASCII)
  $null = Run-Doc $fx @('document', '--unit', $fx.Vendor, '--document-third-party')
  Check 'OWN-HATCH --unit --document-third-party writes the vendored unit' (Has-Engine $fx.Vendor)
  [IO.File]::WriteAllText($fx.Vendor, $vBefore, [Text.Encoding]::ASCII)
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index --project $fx.Proj --db $fx.Db 2>&1 | ForEach-Object { "$_" } }
  $null = Run-Doc $fx @('document-all', '--document-third-party')
  Check 'OWN-HATCH document-all --document-third-party writes the vendored unit' (Has-Engine $fx.Vendor)

  Write-Host ''
  Write-Host 'ITEM 4: document --project --json stdout is pure on a tamper rescan (DOCAPPLY FOUND 7)' -ForegroundColor Cyan
  $fx = New-Fixture (Join-Path $WorkDir 'json')
  # DOCU5 tamper: swap the CheckN declaration with its summary line -- same
  # bytes, same size -- and put the mtime back. The stamp says "unchanged",
  # the stored line of CheckN no longer holds its name -> rescan in-process.
  $lines = [IO.File]::ReadAllLines($fx.Own)
  $stamp = (Get-Item $fx.Own).LastWriteTimeUtc
  $i = [Array]::IndexOf($lines, 'procedure CheckN(const N: Integer);')
  $t = $lines[$i]; $lines[$i] = $lines[$i - 1]; $lines[$i - 1] = $t
  Write-Ascii $fx.Own $lines
  (Get-Item $fx.Own).LastWriteTimeUtc = $stamp
  $errFile = Join-Path $WorkDir 'json-stderr.txt'
  Push-Location $fx.App
  try { $out = & { $ErrorActionPreference = 'Continue'; & $Exe document --project $fx.Proj --db $fx.Db --json 2>$errFile } | Out-String }
  finally { Pop-Location }
  $err = [IO.File]::ReadAllText($errFile)
  Check 'JSON-CTRL the tamper rescan fired (WARN on stderr)' ($err -match 'disagree with the source text') ''
  $parsed = $null
  try { $parsed = $out | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }
  $junk = ($out -split "`r?`n" | Where-Object { $_ -match '^(stage:|Done\.|rule-cache:|Indexing|resolve:)' } | Measure-Object).Count
  Check 'JSON-PURE stdout parses as ONE JSON document' ($null -ne $parsed) "non-JSON index lines on stdout: $junk"

  Write-Host ''
  Write-Host 'ITEMS 1+2: --qname in-process reindex parses the text on disk (DOCAPPLY FOUND 1, 2)' -ForegroundColor Cyan
  # The only in-process reindex on the --qname path is the D-2 stale-anchor
  # retry. Make the index stale (a line inserted above the routines), document
  # one routine whose exception facts read this unit's tree, and check the
  # retry's reindex wrote real facts -- a stale cached tree writes cyclomatic 0
  # (the Y10 signature).
  $fx = New-Fixture (Join-Path $WorkDir 'qname')
  $qc = "select s.name, sf.cyclomatic from symbol_facts sf join symbols s on s.id = sf.symbol_id join files f on f.id = s.file_id where f.path like '%uApp.pas' and s.name in ('CheckN','AppDo') order by s.name"
  function Cyclo($F) {
    $j = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query $qc --db $F.Db --json 2>$null } | Out-String | ConvertFrom-Json
    ($j.rows | ForEach-Object { '{0}={1}' -f $_[0], $_[1] }) -join ','
  }
  $c0 = Cyclo $fx
  Check 'setup: plain index computes the complexity' ($c0 -match 'CheckN=[2-9]') $c0
  $txt = [IO.File]::ReadAllText($fx.Own)
  [IO.File]::WriteAllText($fx.Own, "{ shifted }`r`n" + $txt, [Text.Encoding]::ASCII)
  Push-Location $fx.App
  try { $o = & { $ErrorActionPreference = 'Continue'; & $Exe document --qname uApp.AppDo --db $fx.Db --apply --no-backup 2>&1 | ForEach-Object { "$_" } } | Out-String }
  finally { Pop-Location }
  Check 'QNAME-CTRL the D-2 retry reindexed in-process' ($o -match 'reindexing and retrying once') (($o -split "`r?`n" | Where-Object { $_ -match '^doc:' } | Select-Object -First 1))
  Check 'QNAME-CTRL the apply wrote the unit' (Has-Engine $fx.Own)
  $c1 = Cyclo $fx
  Check 'QNAME facts after the in-process retry match a plain index' ($c1 -eq $c0) "before=$c0 after=$c1"
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
