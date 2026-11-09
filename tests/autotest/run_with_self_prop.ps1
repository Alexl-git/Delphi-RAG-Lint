<#
  run_with_self_prop.ps1 -- backlog row WITH-SELF-PROP (lane 1.43 withself).

  `with Target do OwnProp := 1` inside a TMyForm method, where Target's type has
  an ancestor this index does not hold: the name stayed unbound, because the
  ancestor MAY declare it, and if it does the name means Target.OwnProp (the
  owner's `with` hiding bug class). That is unanswerable from the project index
  alone, so WITHOUT a library the sites must STAY unbound. WITH one, the resolver
  may ask it, and binds only when EVERY library type of the ancestor's name has a
  chain fully inside the library, no member and no helper of that name.

  Asserted on real resolver output (refs.symbol_id / call_edges), per site:
    * no library: fall-through sites unbound; complete-surface controls bound.
    * library: the fall-through sites bind to TMyForm's member (RED on the old
      engine: this is the positive control for the silences below).
    * library: every case the library cannot prove stays unbound -- the library
      declares it (direct and on a farther ancestor), chain leaves the library,
      ancestor nowhere, library helper, project helper on a library type, two
      library types of one leaf name, the TObject floor.
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n, $ok, $d = '') { Write-Host ("[{0}] {1} {2}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n, $d); if (-not $ok) { $script:fail = $true } }
$exePath = (Resolve-Path $Exe).Path
$fix = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\withself')).Path
$root = Join-Path C:\TEMP "draglint_withself_$PID"
New-Item -ItemType Directory -Path $root | Out-Null

function Get-Sites([string]$Db) {
  $q = "select e.name, r.name_text, r.kind, (select qualified_name from symbols where id = coalesce(ce.target_symbol_id, r.symbol_id)) " +
       "from refs r join symbols e on e.id = r.enclosing_symbol_id left join call_edges ce on ce.ref_id = r.id " +
       "where e.name like 'Site%' and r.kind in ('call','read','write') order by r.start_line, r.start_col"
  $raw = (& $exePath sql --db $Db --json --limit 500 --query $q 2>$null) -join "`n"
  $j = $raw.Substring($raw.IndexOf('{')) | ConvertFrom-Json
  $map = @{}
  foreach ($row in $j.rows) { $map[("{0}/{1}" -f $row[0], $row[1])] = [string]$row[3] }
  return $map
}

try {
  Push-Location C:\TEMP
  try {
    $lib = Join-Path $root 'lib.sqlite'; $off = Join-Path $root 'off.sqlite'; $on = Join-Path $root 'on.sqlite'
    & $exePath index (Join-Path $fix 'lib') --db $lib 2>&1 | Out-Null
    Check 'library fixture indexed' ($LASTEXITCODE -eq 0)
    & $exePath index (Join-Path $fix 'app') --db $off 2>&1 | Out-Null
    Check 'app indexed without a library' ($LASTEXITCODE -eq 0)
    $txt = & $exePath index (Join-Path $fix 'app') --db $on --library-db $lib 2>&1 | Out-String
    Check 'app indexed with the library' ($txt -match '\+ library-db')

    $noLib = Get-Sites $off; $withLib = Get-Sites $on
    Check 'shape: rows came back keyed by site/name' ($withLib.ContainsKey('SiteWrite/OwnProp') -and $noLib.ContainsKey('SiteWrite/OwnProp')) ("rows=" + $withLib.Count)

    # Since 1.47 (B1, E-USE-EDGES-PHASE2) a property WRITE binds its setter, as a read binds its getter.
    $binds = [ordered]@{
      'SiteCall/OwnCall' = 'TMyForm.OwnCall'; 'SiteWrite/OwnProp' = 'TMyForm.SetOwnProp'; 'SiteRead/OwnProp' = 'TMyForm.GetOwnProp'
      'SiteField/FOwnField' = 'TMyForm.FOwnField'; 'SiteReceiver/Go' = 'TGoer.Go'; 'SiteLayer/CompleteProp' = 'TCompleteTarget.CompleteProp'
    }
    foreach ($k in $binds.Keys) {
      Check "no library: $k stays unbound" ($noLib[$k] -eq '') "[$($noLib[$k])]"
      Check "library: $k binds $($binds[$k])" ($withLib[$k] -like "*$($binds[$k])") "[$($withLib[$k])]"
    }
    $controls = [ordered]@{
      'SiteDone/OwnProp' = 'TMyForm.SetOwnProp'; 'SiteSelf/OwnProp' = 'TMyForm.SetOwnProp'; 'SiteTarget/TargetProp' = 'TOpenTarget.TargetProp'
    }
    foreach ($k in $controls.Keys) {
      Check "control, no library: $k binds" ($noLib[$k] -like "*$($controls[$k])") "[$($noLib[$k])]"
      Check "control, library: $k binds" ($withLib[$k] -like "*$($controls[$k])") "[$($withLib[$k])]"
    }
    foreach ($k in 'SiteHidden/ShadowProp', 'SiteHiddenRoot/RootShadow', 'SiteLeaves/OwnProp', 'SiteUnknown/OwnProp',
      'SiteHelper/HelperCall', 'SiteTwice/TwiceCall', 'SiteProjHelper/ProjHelperCall', 'SiteFloor/Dispatch') {
      Check "library cannot prove it: $k stays unbound" ($withLib.ContainsKey($k) -and $withLib[$k] -eq '') "[$($withLib[$k])]"
    }
  } finally { Pop-Location }
} finally {
  [IO.Directory]::Delete($root, $true)
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }