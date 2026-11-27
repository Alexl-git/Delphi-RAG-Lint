<#
  run_v156_THRS_lock_sites.ps1 -- 1.56 lane THR-S: S6, the lock sites of a project
  (src\query\DRagLint.Query.LockSites.pas; read by G-05 lock-order-inversion and by lock-held-when).

  The fixture tests\fixtures\lock-sites\ls-basic\ is indexed into a private DB; the driver
  tests\fixtures\lock-sites\driver\LockSitesDriver.dpr (compiled here with dcc64) prints LockSitesJson.
  Every lock call of the fixture carries a `// SITE-<NAME>` marker. Per marker the runner asserts
  EXACTLY: the routine, op, kind, identity, exact, the lock (qualified name when the index resolves it,
  else the text as written) and the marker of the paired site ('-' = no partner).
  Further: the number of sites equals the number of cases (a call that is not a lock -- BeginUpdate on a
  string list, Enter / Release on a class that is no lock -- adds a site and fails this); the regions
  (nested, open); HeldAt at three positions; the selectors --file and --routine; two runs byte-identical;
  comparator control (a changed expectation is reported).

  Parameters: -Exe (engine that indexes the fixture), -Repo, -WorkDir, -SkipBuild.
#>
[CmdletBinding()]
param(
  [string]$Repo    = '',
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-thrs-$PID",
  [switch]$SkipBuild
)
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Failed = $true; $script:Fail++ }
}
Write-Host '== v156 THR-S lock sites ==' -ForegroundColor Cyan
if ($Exe -eq '') { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$FixRoot = Join-Path $Repo 'tests\fixtures\lock-sites'
$U = 'lsLocks.TBank'
$CS = 'critical-section'

# Case table: '<MARKER>' = '<routine>|<op>|<kind>|<identity>|<exact>|<lock>|<mate marker>'
$Cases = [ordered]@{
  'A1-ENTER'      = "$U.AThenB|enter|$CS|self-field|True|$U.FLockA|A1-LEAVE"
  'A1-B-ENTER'    = "$U.AThenB|enter|$CS|self-field|True|$U.FLockB|A1-B-LEAVE"
  'A1-B-LEAVE'    = "$U.AThenB|leave|$CS|self-field|True|$U.FLockB|A1-B-ENTER"
  'A1-LEAVE'      = "$U.AThenB|leave|$CS|self-field|True|$U.FLockA|A1-ENTER"
  'B1-ACQUIRE'    = "$U.BThenA|enter|$CS|self-field|True|$U.FLockB|B1-RELEASE"
  'B1-A-ACQUIRE'  = "$U.BThenA|enter|$CS|self-field|True|$U.FLockA|B1-A-RELEASE"
  'B1-A-RELEASE'  = "$U.BThenA|leave|$CS|self-field|True|$U.FLockA|B1-A-ACQUIRE"
  'B1-RELEASE'    = "$U.BThenA|leave|$CS|self-field|True|$U.FLockB|B1-ACQUIRE"
  'UNBAL-ENTER'   = "$U.Unbalanced|enter|$CS|self-field|True|$U.FLockA|-"
  'LOCAL-ENTER'   = "$U.LocalLock|enter|$CS|local|False|$U.LocalLock.L|LOCAL-LEAVE"
  'LOCAL-LEAVE'   = "$U.LocalLock|leave|$CS|local|False|$U.LocalLock.L|LOCAL-ENTER"
  'PARAM-ENTER'   = "$U.ParamLock|enter|$CS|param|False|$U.ParamLock.pLock|PARAM-LEAVE"
  'PARAM-LEAVE'   = "$U.ParamLock|leave|$CS|param|False|$U.ParamLock.pLock|PARAM-ENTER"
  'GLOBAL-ENTER'  = "$U.GlobalLock|enter|$CS|global|True|lsLocks.GLock|GLOBAL-LEAVE"
  'GLOBAL-LEAVE'  = "$U.GlobalLock|leave|$CS|global|True|lsLocks.GLock|GLOBAL-ENTER"
  'SELF-ENTER'    = "$U.ViaSelf|enter|$CS|self-field|True|$U.FLockA|SELF-LEAVE"
  'SELF-LEAVE'    = "$U.ViaSelf|leave|$CS|self-field|True|$U.FLockA|SELF-ENTER"
  'OTHER-ENTER'   = "$U.OtherObject|enter|$CS|other-field|False|$U.FLockA|OTHER-LEAVE"
  'OTHER-LEAVE'   = "$U.OtherObject|leave|$CS|other-field|False|$U.FLockA|OTHER-ENTER"
  'TRY-ENTER'     = "$U.TrySite|try-enter|$CS|self-field|True|$U.FLockA|TRY-LEAVE"
  'TRY-LEAVE'     = "$U.TrySite|leave|$CS|self-field|True|$U.FLockA|TRY-ENTER"
}

function Get-Markers([string]$Path) {
  $m = @{}
  $n = 0
  foreach ($line in [IO.File]::ReadAllLines($Path)) {
    $n++
    if ($line -match '//\s*((SITE|HELD|END)-[A-Z0-9-]+)\s*$') { $m[$Matches[1]] = $n }
  }
  return $m
}

# Flattens the driver document: one object per site, mate resolved to the mate's line.
function Get-Sites($Doc) {
  $out = @()
  foreach ($r in @($Doc.routines)) {
    $sites = @($r.sites)
    foreach ($s in $sites) {
      $mateLine = if ($s.mate -ge 0) { $sites[$s.mate].line } else { 0 }
      $lock = if ($s.lockSymbol) { $s.lockSymbol } else { $s.lock }
      $out += [pscustomobject]@{ Routine = $r.routine; Line = $s.line; Op = $s.op; Kind = $s.kind; Identity = $s.identity
        Exact = [string]$s.exact; Lock = $lock; MateLine = $mateLine; Key = $s.key }
    }
  }
  return ,$out
}

# '' when the site at the marker matches the expectation, else what differs.
function Compare-Site($Sites, $Markers, [string]$Marker, [string]$Expected) {
  $e = $Expected.Split('|')
  $line = $Markers["SITE-$Marker"]
  $hit = @($Sites | Where-Object { $_.Line -eq $line })
  if ($hit.Count -ne 1) { return "sites at line ${line}: $($hit.Count)" }
  $s = $hit[0]
  $mate = if ($e[6] -eq '-') { 0 } else { $Markers["SITE-$($e[6])"] }
  $got = "$($s.Routine)|$($s.Op)|$($s.Kind)|$($s.Identity)|$($s.Exact)|$($s.Lock)|$($s.MateLine)"
  $want = "$($e[0])|$($e[1])|$($e[2])|$($e[3])|$($e[4])|$($e[5])|$mate"
  if ($got -ceq $want) { return '' }
  return "got $got want $want"
}

function Get-Key($Sites, $Markers, [string]$Marker) {
  $hit = @($Sites | Where-Object { $_.Line -eq $Markers["SITE-$Marker"] })
  if ($hit.Count -eq 1) { return [string]$hit[0].Key }
  return ''
}

function Invoke-Driver([string[]]$DriverArgs) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $script:DriverExe @DriverArgs 2>$null }
  return (@($raw) -join "`n")
}

function Get-Held([string]$Db, [string]$Routine, [int]$Line, [int]$Col) {
  $doc = (Invoke-Driver @('--db', $Db, '--routine', $Routine, '--held', "${Line}:${Col}")) | ConvertFrom-Json
  return (@($doc.held) -join ',')
}

try {
  if ((Test-Path -LiteralPath $WorkDir) -and -not $SkipBuild) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
  $script:DriverExe = Join-Path $WorkDir 'LockSitesDriver.exe'
  if (-not $SkipBuild) {
    $src = Join-Path $Repo 'src'
    $dirs = 'preprocess','core','context','diagnostics','doc','forms','index','lint','lsp','mcp','output','parser',
            'project','query','refactor','report','resolver','sql','storage','workspace','analysis','cli','charts'
    $paths = (@($dirs | ForEach-Object { Join-Path $src $_ }) + (Join-Path $Repo 'third_party\delphi-tree-sitter')) -join ';'
    $dpr = Join-Path $FixRoot 'driver\LockSitesDriver.dpr'
    $dcu = Join-Path $WorkDir 'dcu'
    New-Item -ItemType Directory -Path $dcu -Force | Out-Null
    $bat = Join-Path $WorkDir 'b.bat'
    $blog = Join-Path $WorkDir 'build.log'
    $q = [char]34
    $batText = "@echo off`r`ncall ${q}C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat${q}`r`n" +
      "cd /D ${q}$WorkDir${q}`r`n" +
      "dcc64 -B -Q -NU${q}$dcu${q} -E${q}$WorkDir${q} -U${q}$paths${q} -I${q}$paths${q} " +
      "-NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win " +
      "${q}$dpr${q}`r`necho BUILD_EXITCODE=%errorlevel%`r`n"
    [IO.File]::WriteAllText($bat, $batText, [Text.Encoding]::ASCII)
    $proc = Start-Process -FilePath cmd.exe -ArgumentList ('/c ' + $q + $q + $bat + $q + ' > ' + $q + $blog + $q + ' 2>&1' + $q) -NoNewWindow -PassThru
    try { $proc.PriorityClass = 'BelowNormal' } catch { Write-Verbose "priority not lowered: $_" }
    $proc.WaitForExit()
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match 'Error: |Fatal: ')) {
      Select-String -LiteralPath $blog -Pattern 'Error: |Fatal: ' | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
      Write-Host "V156 THR-S LOCK SITES: FAIL -- the driver did not build (log: $blog)" -ForegroundColor Red
      exit 1
    }
    foreach ($dll in 'sqlite3.dll','tree-sitter.dll','tree-sitter-delphi13.dll','tree-sitter-dfm.dll') {
      $from = Join-Path (Split-Path $Exe) $dll
      if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $WorkDir -Force }
    }
  }
  if (-not (Test-Path -LiteralPath $script:DriverExe)) { Write-Host "FATAL: driver not found: $script:DriverExe" -ForegroundColor Red; exit 2 }

  # Index a private copy of the fixture (never a real project DB).
  $fx = Join-Path $WorkDir 'fx\ls-basic'
  New-Item -ItemType Directory -Path $fx -Force | Out-Null
  Copy-Item -Path (Join-Path $FixRoot 'ls-basic\*') -Destination $fx -Force
  $db = Join-Path $WorkDir 'ls-basic.sqlite'
  if (Test-Path -LiteralPath $db) { [IO.File]::Delete($db) }
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db 2>&1 | ForEach-Object { "$_" } }
  Check 'index ls-basic (exit 0)' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $markers = Get-Markers (Join-Path $fx 'lsLocks.pas')

  $rawAll = Invoke-Driver @('--db', $db)
  Check 'driver exit 0 (project)' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $doc = $rawAll | ConvertFrom-Json
  $sites = Get-Sites $doc

  foreach ($k in $Cases.Keys) {
    $diff = Compare-Site $sites $markers $k $Cases[$k]
    Check "site $k" ($diff -eq '') $diff
  }
  Check 'no site beyond the cases' ($sites.Count -eq $Cases.Count) "sites=$($sites.Count) cases=$($Cases.Count)"
  Check 'NoLocks / NotLocks have no entry' ((@($doc.routines).Count -gt 0) -and (@($doc.routines | Where-Object { $_.routine -match 'NoLocks|NotLocks' }).Count -eq 0))

  # Exact keys: the same field gives the same key in two routines; another object's field does not.
  $keyA  = Get-Key $sites $markers 'A1-ENTER'
  $keyB  = Get-Key $sites $markers 'A1-B-ENTER'
  $keyBA = Get-Key $sites $markers 'B1-A-ACQUIRE'
  $keyO  = Get-Key $sites $markers 'OTHER-ENTER'
  Check 'FLockA: one key in AThenB and BThenA' (($keyA -ne '') -and ($keyA -ceq $keyBA)) "$keyA / $keyBA"
  Check 'FLockB: another key than FLockA' (($keyB -ne '') -and ($keyB -cne $keyA)) "$keyB"
  Check 'pOther.FLockA: another key than FLockA' (($keyO -ne '') -and ($keyO -cne $keyA)) "$keyO"

  # Regions.
  $regA = @(($doc.routines | Where-Object { $_.routine -eq "$U.AThenB" }).regions)
  Check 'AThenB: 2 regions' ($regA.Count -eq 2) "regions=$($regA.Count)"
  if ($regA.Count -eq 2) {
    Check 'AThenB: outer region enter..leave' (($regA[0].startLine -eq $markers['SITE-A1-ENTER']) -and ($regA[0].endLine -eq $markers['SITE-A1-LEAVE']) -and (-not $regA[0].open) -and $regA[0].exact) ($regA[0] | ConvertTo-Json -Compress)
    Check 'AThenB: inner region enter..leave' (($regA[1].startLine -eq $markers['SITE-A1-B-ENTER']) -and ($regA[1].endLine -eq $markers['SITE-A1-B-LEAVE']) -and (-not $regA[1].open)) ($regA[1] | ConvertTo-Json -Compress)
  }
  $regU = @(($doc.routines | Where-Object { $_.routine -eq "$U.Unbalanced" }).regions)
  Check 'Unbalanced: 1 open region to the end of the routine' (($regU.Count -eq 1) -and $regU[0].open -and ($regU[0].leave -eq -1) -and ($regU[0].endLine -eq $markers['END-UNBAL'])) ($regU | ConvertTo-Json -Compress)

  # HeldAt.
  $h = Get-Held $db "$U.AThenB" $markers['HELD-AB'] 7
  Check 'HeldAt inside both: FLockA then FLockB' (($keyA -ne '') -and ($h -ceq "$keyA,$keyB")) $h
  $h = Get-Held $db "$U.AThenB" $markers['HELD-NONE'] 3
  Check 'HeldAt before the first enter: none' ($h -eq '') $h
  $h = Get-Held $db "$U.Unbalanced" $markers['HELD-UNBAL'] 3
  Check 'HeldAt in an open region: FLockA' (($keyA -ne '') -and ($h -ceq $keyA)) $h

  # Selectors.
  $rawFile = Invoke-Driver @('--db', $db, '--file', 'lsLocks.pas')
  Check '--file equals the project answer (one file)' ($rawFile -ceq $rawAll)
  $one = (Invoke-Driver @('--db', $db, '--routine', "$U.AThenB")) | ConvertFrom-Json
  Check '--routine AThenB: 4 sites' ((@($one.routines).Count -eq 1) -and (@($one.routines[0].sites).Count -eq 4)) "sites=$(@($one.routines[0].sites).Count)"
  $none = (Invoke-Driver @('--db', $db, '--routine', "$U.NoLocks")) | ConvertFrom-Json
  Check '--routine NoLocks: 0 sites' ((@($none.routines).Count -eq 1) -and (@($none.routines[0].sites).Count -eq 0))

  # Determinism and comparator control.
  $rawAgain = Invoke-Driver @('--db', $db)
  Check 'two runs byte-identical' (($rawAgain -ceq $rawAll) -and ($sites.Count -gt 0)) "sites=$($sites.Count)"
  $first = @($Cases.Keys)[0]
  $changed = $Cases[$first] -replace '\|enter\|', '|leave|'
  Check 'control: a changed expectation is reported' ((Compare-Site $sites $markers $first $changed) -ne '')
}
catch {
  Write-Host "  [FAIL] exception: $_" -ForegroundColor Red
  $script:Failed = $true
  $script:Fail++
}
Write-Host ("V156 THR-S LOCK SITES: {0} pass, {1} fail" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Failed) { 'Red' } else { 'Green' })
if ($script:Failed) { exit 1 }
exit 0
