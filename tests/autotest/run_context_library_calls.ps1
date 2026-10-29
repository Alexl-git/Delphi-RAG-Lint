<#
  run_context_library_calls.ps1 -- item 4 / plan task C3.
  `context --task "modify <routine>"` prints ONE line `Library calls: N (top: a, b, c)`
  when the routine's body holds N calls whose refs.external_target is set (a project
  indexed with --library-db), and `--format json` carries `library_calls`
  {count, top}. A project indexed WITHOUT a library has no external_target, so the
  line is ABSENT (and json has no library_calls key). Positive control: the same
  routine on the library DB shows the line only where it must (count > 0).

  Fixture: tests\callresolve\fixtures\xtyped (xt_lib = library, xt_app + xt_app2 =
  project; routine Go in xt_app calls library members through typed receivers).
  Run from any CWD, pwsh 7. Touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_library_calls_$PID"
)
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $libDir = Join-Path $WorkDir 'lib'; $appDir = Join-Path $WorkDir 'app'
  New-Item -ItemType Directory -Path $libDir,$appDir -Force | Out-Null
  Copy-Item (Join-Path $fixDir 'xt_lib.pas') $libDir -Force
  Copy-Item (Join-Path $fixDir 'xt_app.pas'),(Join-Path $fixDir 'xt_app2.pas') $appDir -Force
  $libDb = Join-Path $WorkDir 'lib.sqlite'; $app = Join-Path $WorkDir 'app.sqlite'; $appx = Join-Path $WorkDir 'appx.sqlite'
  Push-Location C:\TEMP
  try {
    & $exePath index $libDir --db $libDb 2>&1 | Out-Null
    & $exePath index $appDir --db $app   2>&1 | Out-Null
    & $exePath index $appDir --db $appx --library-db $libDb 2>&1 | Out-Null
    Check 'indexes built' ((Test-Path $libDb) -and (Test-Path $app) -and (Test-Path $appx))

    # expected N = refs with external_target inside Go, counted straight from the DB
    $q = 'select r.name_text from refs r join symbols s on s.id = r.enclosing_symbol_id where s.qualified_name = ''xt_app.Go'' and r.kind = ''call'' and r.external_target is not null and r.external_target <> '''''
    $raw = (& $exePath sql --db $appx --json --limit 500 --query $q 2>$null) -join "`n"
    $rows = @((($raw.Substring($raw.IndexOf('{')) | ConvertFrom-Json).rows))
    $n = $rows.Count
    Check 'fixture precondition: Go has 6 external_target refs (plan C3)' ($n -eq 6) "got $n"

    $md = (& $exePath context --task 'modify Go' --db $appx 2>&1) -join "`n"
    Check 'appx: markdown has the Library calls line with N' ($md -match "(?m)^Library calls: $n \(top: [^)]+\)\s*$") ($md -split "`n" | Select-String 'Library calls' | Out-String)
    $js = (& $exePath context --task 'modify Go' --db $appx --format json 2>&1) -join "`n"
    $o  = $js.Substring($js.IndexOf('{')) | ConvertFrom-Json
    Check 'appx: json carries library_calls.count' ($o.library_calls.count -eq $n) "got $($o.library_calls.count)"
    Check 'appx: json library_calls.top is a non-empty list' (@($o.library_calls.top).Count -ge 1)

    $md2 = (& $exePath context --task 'modify Go' --db $app 2>&1) -join "`n"
    Check 'app (no library): the line is ABSENT' ($md2 -notmatch 'Library calls')
    Check 'app CONTROL: the bundle still resolved Go' ($md2 -match '(?i)\bGo\b')
    $js2 = (& $exePath context --task 'modify Go' --db $app --format json 2>&1) -join "`n"
    $o2  = $js2.Substring($js2.IndexOf('{')) | ConvertFrom-Json
    Check 'app (no library): json has no library_calls key' ($null -eq $o2.PSObject.Properties['library_calls'])
    # --- RSV-R2 (#8): the opt-in oracle. `app` carries NO stored external_target; with
    #     --library-db the receivers typed by name are bound against the library now.
    #     The oracle binds only receivers typed BY NAME (the same binding find-callees uses),
    #     so its count is what find-callees lists as "resolved now" (3 of Go's 6 here; the other
    #     3 were bound at index time through typed locals and are not visible without stored refs).
    $fc = (& $exePath find-callees --qname xt_app.Go --db $app --library-db $libDb 2>&1) -join "`n"
    $nOr = @($fc -split "`n" | Where-Object { $_ -match '\(library, resolved now\)' }).Count
    Check 'R2 precondition: find-callees binds some Go calls through the oracle' (($nOr -ge 1) -and ($nOr -lt $n)) "oracle=$nOr stored=$n"
    $mo = (& $exePath context --task 'modify Go' --db $app --library-db $libDb 2>&1) -join "`n"
    Check 'R2 app + --library-db: the Library calls line counts the oracle hits' ($mo -match "(?m)^Library calls: $nOr \(top: [^)]+\)\s*$") ($mo -split "`n" | Select-String 'Library calls' | Out-String)
    $jo = (& $exePath context --task 'modify Go' --db $app --library-db $libDb --format json 2>&1) -join "`n"
    $oo = $jo.Substring($jo.IndexOf('{')) | ConvertFrom-Json
    Check 'R2 app + --library-db: json library_calls.count' ($oo.library_calls.count -eq $nOr) "got $($oo.library_calls.count)"
    Check 'R2 app + --library-db: json library_calls.via is oracle' ($oo.library_calls.via -eq 'oracle') "got $($oo.library_calls.via)"
    Check 'R2 appx (stored external_target): json via is stored' ($o.library_calls.via -eq 'stored') "got $($o.library_calls.via)"
    $jx = (& $exePath context --task 'modify Go' --db $appx --library-db $libDb --format json 2>&1) -join "`n"
    $ox = $jx.Substring($jx.IndexOf('{')) | ConvertFrom-Json
    Check 'R2 appx + --library-db: stored refs are not double counted' ($ox.library_calls.count -eq $n) "got $($ox.library_calls.count)"
    $jn = (& $exePath context --task 'modify Go' --db $app --library-db none --format json 2>&1) -join "`n"
    $on = $jn.Substring($jn.IndexOf('{')) | ConvertFrom-Json
    Check 'R2 --library-db none: no oracle, no library_calls key' ($null -eq $on.PSObject.Properties['library_calls'])
  } finally { Pop-Location }
} finally { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } }
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
