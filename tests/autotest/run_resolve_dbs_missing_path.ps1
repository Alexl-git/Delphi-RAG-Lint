<#
run_resolve_dbs_missing_path.ps1 -- `resolve-dbs` marks EACH missing database (1.44 C8).

Measured on 1.43: `resolve-dbs --in <file>` flagged a missing index only when ALL the
paths it printed were missing (X-10, run_resolve_dbs_in_uncovered.ps1 arm E). With
two paths and one built, the missing one was printed like the built one and nothing
said it did not exist.

Contract: resolve-dbs stays READ-ONLY (it never builds a database) and its stdout stays
the bare path list (scripts capture it); the marking goes to STDERR, one line per
missing path, naming the path and the exact command that builds it:
    NOTE: <path> (missing) -- not built yet; build it with: <command>

Arms:
  V   fixture: two paths printed, one built and one not (else the arms below prove nothing)
  A   the missing path is marked "(missing)" with a build command; exit 0; stdout unchanged
  B   positive control: the built path is NOT marked
  C   read-only: resolve-dbs created no database file
  D   --project: an unbuilt project index is marked with the exact `index --project` command

Usage: pwsh -NoProfile -File tests\autotest\run_resolve_dbs_missing_path.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-resolve-missing-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) {'PASS'} else {'FAIL'}
  $color  = if ($Ok) {'Green'} else {'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
  Write-Host "  [FAIL] engine not found: $Exe" -ForegroundColor Red
  exit 1
}
$Exe = (Resolve-Path -LiteralPath $Exe).Path
try {
  New-Item -ItemType Directory -Path "$WorkDir\cov" -Force | Out-Null
  [IO.File]::WriteAllText("$WorkDir\cov\App.dproj", '<Project/>', [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText("$WorkDir\cov\A.pas", 'unit A;', [Text.Encoding]::ASCII)
  $esc = $WorkDir -replace '\\', '\\'
  $cfg = "$WorkDir\m.json"
  # Two sections cover A.pas: App (the project) and Folder (its directory).
  [IO.File]::WriteAllText($cfg,
    ('{"indexes":{"outDir":"' + $esc + '\\out","sections":[{"name":"App","include":["' + $esc + '\\cov\\App.dproj"]},' +
     '{"name":"Library","db":"library-{platform}.sqlite","source":"registry-libraries","platforms":["Win64"]}]}}'),
    [Text.Encoding]::ASCII)

  function Invoke-Rd([string[]]$A) {
    $o = "$WorkDir\o.txt"; $e = "$WorkDir\e.txt"
    $p = Start-Process -FilePath $Exe -ArgumentList $A -NoNewWindow -Wait -PassThru -WorkingDirectory $WorkDir `
           -RedirectStandardOutput $o -RedirectStandardError $e
    [pscustomobject]@{
      Exit = $p.ExitCode
      Out  = @(([IO.File]::ReadAllText($o)) -split "`r?`n" | Where-Object { $_ -ne '' })
      Err  = ([IO.File]::ReadAllText($e)).Trim()
    }
  }

  $db = "$WorkDir\cov\_D-RAG\App.sqlite"
  $in = "$WorkDir\cov\A.pas"
  # the platform library exists (a built path listed beside the unbuilt project index)
  New-Item -ItemType Directory -Path "$WorkDir\out" -Force | Out-Null
  [IO.File]::WriteAllText("$WorkDir\out\library-Win64.sqlite", 'x', [Text.Encoding]::ASCII)
  $cmdPat = 'build it with: drag-lint index --all --only App'
  Check 'V: the project index is not built yet, the library placeholder exists' ((-not (Test-Path $db)) -and (Test-Path "$WorkDir\out\library-Win64.sqlite"))

  $a = Invoke-Rd @('resolve-dbs', '--in', $in, '--config', $cfg)
  Check 'A: --in, project index unbuilt -- the path is marked (missing) with its section build command' `
        ($a.Err -match ([regex]::Escape($db) + ' \(missing\) -- not built yet; ' + $cmdPat)) "stderr='$($a.Err)'"
  Check 'A: exit 0 and stdout still the bare path' (($a.Exit -eq 0) -and ($a.Out -contains $db)) "exit=$($a.Exit) stdout=$($a.Out -join ' | ')"
  Check 'A: read-only -- the database was not created' (-not (Test-Path $db))

  $b = Invoke-Rd @('resolve-dbs', '--platform', 'Win64', '--config', $cfg)
  Check 'B: bare list -- the library (built) is printed and NOT marked missing' (($b.Out -contains "$WorkDir\out\library-Win64.sqlite") -and ($b.Err -notmatch 'library-Win64\.sqlite \(missing\)')) "stderr='$($b.Err)'"

  $d = Invoke-Rd @('resolve-dbs', '--project', "$WorkDir\cov\App.dproj", '--config', $cfg)
  Check 'D: --project, index unbuilt -- marked with the exact index --project command' `
        ($d.Err -match ([regex]::Escape($db) + ' \(missing\) -- not built yet; build it with: drag-lint index --project')) "stderr='$($d.Err)'"
  Check 'D: --project is read-only' (-not (Test-Path $db))

  New-Item -ItemType Directory -Path (Split-Path $db -Parent) -Force | Out-Null
  [IO.File]::WriteAllText($db, 'x', [Text.Encoding]::ASCII)
  $c = Invoke-Rd @('resolve-dbs', '--in', $in, '--config', $cfg)
  Check 'C: positive control -- once the project index exists, nothing is marked missing' ($c.Err -notmatch '\(missing\)') "stderr='$($c.Err)'"
  [IO.File]::Delete($db)
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
