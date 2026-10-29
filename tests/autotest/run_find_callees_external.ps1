<#
  run_find_callees_external.ps1 -- item 4, lane C (spec 2026-10-28-untypable-receivers s.8).
  find-callees lists LIBRARY-bound callees after the resolved ones, marked "(library" in text and
  {"external": true, "via": "edge"|"oracle"} in --json:
    * via "edge"   : the project DB already holds refs.external_target (indexed with --library-db).
    * via "oracle" : the project DB was indexed WITHOUT a library; the library is named at read time
                     (a second --db, or --library-db) and TLibraryOracle binds the receiver's
                     refs.receiver_type_text now.
    * no library   : nothing external is listed; the text says "M external (library not open)".
  Sites (xt_app.Go): P1 S.Read, P2 S.Defs.Add, P6 LibApp.Base are library-bound; P4 A.Own is a normal
  resolved callee in every form. CONTROL: TOtherLib.Add (same member name, unrelated type) never appears.
  Needs the resolver lanes (receiver_type_text + external_target fill, oracle Bind) for the edge/oracle
  halves: it is RED until they are integrated. Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
$scratch = Join-Path C:\TEMP "draglint_fcext_$PID"
$want = @('xt_lib.TLibStream.Read','xt_lib.TLibDefs.Add','xt_lib.TLibBase.Base')   # P1, P2, P6

# find-callees --json is a bare array; library rows carry external=true.
function Callees([string[]]$CliArgs) {
  $raw = (& $exePath find-callees --qname xt_app.Go @CliArgs --json 2>$null) -join "`n"
  $b = $raw.IndexOf('['); if ($b -lt 0) { return ,@() }
  return ,@($raw.Substring($b) | ConvertFrom-Json)
}
function ExtRows($rows) { @($rows | Where-Object { $_.external -eq $true }) }
try {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
  $libDir = Join-Path $scratch 'lib'; $appDir = Join-Path $scratch 'app'
  New-Item -ItemType Directory -Path $libDir,$appDir -Force | Out-Null
  Copy-Item (Join-Path $fixDir 'xt_lib.pas') $libDir -Force
  Copy-Item (Join-Path $fixDir 'xt_app.pas'),(Join-Path $fixDir 'xt_app2.pas') $appDir -Force
  $libDb = Join-Path $scratch 'lib.sqlite'; $appDb = Join-Path $scratch 'app.sqlite'; $appxDb = Join-Path $scratch 'appx.sqlite'
  Push-Location C:\TEMP
  try {
    & $exePath index $libDir --db $libDb 2>$null | Out-Null
    Check 'library index built' ($LASTEXITCODE -eq 0)
    & $exePath index $appDir --db $appDb 2>$null | Out-Null
    Check 'app index built (no library)' ($LASTEXITCODE -eq 0)
    & $exePath index $appDir --db $appxDb --library-db $libDb 2>$null | Out-Null
    Check 'appx index built (--library-db)' ($LASTEXITCODE -eq 0)

    # ---- 1. stored edge: appx alone ----
    $a = Callees @('--db',$appxDb)
    $ext = ExtRows $a
    foreach ($q in $want) { Check "appx: $q listed via edge" (@($ext | Where-Object { $_.target_qname -ceq $q -and $_.via -eq 'edge' }).Count -gt 0) }
    Check 'appx: P4 xt_app.TAppStream.Own is a normal resolved callee' (@($a | Where-Object { $_.target_qname -ceq 'xt_app.TAppStream.Own' -and -not $_.external }).Count -gt 0)
    Check 'appx CONTROL: TOtherLib.Add never listed' (@($ext | Where-Object { $_.target_qname -like '*TOtherLib*' }).Count -eq 0)
    $t = (& $exePath find-callees --qname xt_app.Go --db $appxDb 2>&1 | Out-String)
    Check 'appx: text marks the library callee "(library"' (($t -match 'Read') -and ($t -match '\(library')) $t

    # ---- 2. oracle: app has no library, the library is named at read time ----
    foreach ($form in @(@('--db',$appDb,'--db',$libDb), @('--db',$appDb,'--library-db',$libDb))) {
      $o = Callees $form; $oe = ExtRows $o
      foreach ($q in $want) { Check "oracle [$($form[2])]: $q via oracle" (@($oe | Where-Object { $_.target_qname -ceq $q -and $_.via -eq 'oracle' }).Count -gt 0) }
      Check "oracle [$($form[2])]: P4 still a normal resolved callee" (@($o | Where-Object { $_.target_qname -ceq 'xt_app.TAppStream.Own' -and -not $_.external }).Count -gt 0)
      Check "oracle [$($form[2])] CONTROL: TOtherLib.Add never listed" (@($oe | Where-Object { $_.target_qname -like '*TOtherLib*' }).Count -eq 0)
    }
    $to = (& $exePath find-callees --qname xt_app.Go --db $appDb --db $libDb 2>&1 | Out-String)
    Check 'oracle: text marks "(library, resolved now)"' ($to -match '\(library, resolved now\)') $to

    # ---- 3. no library open: nothing external, and the text says what it could not see ----
    $n = Callees @('--db',$appDb)
    Check 'no library: no external rows' ((ExtRows $n).Count -eq 0)
    Check 'no library: P4 still a normal resolved callee' (@($n | Where-Object { $_.target_qname -ceq 'xt_app.TAppStream.Own' }).Count -gt 0)
    $tn = (& $exePath find-callees --qname xt_app.Go --db $appDb 2>&1 | Out-String)
    Check 'no library: text says "M external (library not open)" with M > 0' (($tn -match '(\d+) external \(library not open\)') -and ([int]$Matches[1] -gt 0)) $tn
    Check 'no library: text has no "(library," marker' ($tn -notmatch '\(library,')
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
