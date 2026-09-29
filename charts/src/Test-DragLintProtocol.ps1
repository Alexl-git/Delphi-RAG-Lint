<#
  Test-DragLintProtocol.ps1 -- synthetic tests for the draglint:// handler and its registration.

  Launches nothing and writes nothing outside -OutDir: the handler runs only in WHAT-IF mode --
  set by the environment (DRAGLINT_URI_TEST_WHATIF=1, DRAGLINT_URI_TEST_LOG), because the handler
  takes exactly ONE argument, the URI (ruling SEC-R2) -- which validates and reports, never the pipe,
  never Test-Path, never a process; and the registration only in -DryRun mode (returns the value it
  WOULD write; no registry write, no file copy). The registry is only READ, before/after.

    UH-*   the handler's validation: hostile URIs refused with their reason (exit 2, one log line),
           good ones accepted with the exact pipe payload
    UH-FN  Test-DragLintTarget is reachable by dot-sourcing the handler (no side effects)
    SEC-1  the handler run AS THE REGISTRY RUNS IT (`-File <handler> "<%1>"`, raw command line) with an
           argument-injecting %1 (`..." -LogPath "<file>`): exit 2, the reason logged, no file written
           outside the sandbox log -- under pwsh 7 AND Windows PowerShell 5.1 (sandboxed LOCALAPPDATA)
    UH-PS5 the handler parses AND validates under Windows PowerShell 5.1 (the registration fallback)
    RG-*   Register-DragLintProtocol.ps1 -DryRun: interpreter preference, REG_EXPAND_SZ for the alias,
           the versioned MSIX path refused, a worktree handler refused without -Force, the value pinned
#>
[CmdletBinding()]
param(
  [string] $OutDir = (Join-Path $PSScriptRoot ('..\scratch\uri-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

$ErrorActionPreference = 'Stop'
$fail = New-Object System.Collections.ArrayList
function Fail([string] $code, [string] $msg) { [void]$fail.Add([pscustomobject]@{ Code = $code; Message = $msg }) }
function Chk([string] $code, $actual, $expected) { if ("$actual" -cne "$expected") { Fail $code "expected $expected, got $actual" } }
function Step([string] $code, [scriptblock] $body) { try { . $body } catch { Fail $code "unexpected error: $($_.Exception.Message)" } }

New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).ProviderPath
$H   = Join-Path $PSScriptRoot 'Open-DragLintUri.ps1'
$REG = Join-Path $PSScriptRoot 'Register-DragLintProtocol.ps1'
$log = Join-Path $OutDir 'uri-handler.log'

# what-if and the log path reach the handler ONLY through the environment (SEC-R2)
$env:DRAGLINT_URI_TEST_WHATIF = '1'
$env:DRAGLINT_URI_TEST_LOG    = $log

# one handler call: exit code, the returned object, and the log lines it added
function Invoke-Handler([string] $Uri) {
  $before = $(if (Test-Path $log) { @(Get-Content $log).Count } else { 0 })
  $o = & $H $Uri
  $code = $LASTEXITCODE
  $added = $(if (Test-Path $log) { @(Get-Content $log | Select-Object -Skip $before) } else { @() })
  [pscustomobject]@{ Exit = $code; Result = $o; Log = ($added -join ' | ') }
}
function U([string] $File, [string] $Line = '1', [string] $Extra = '') { "draglint://open?file=$([uri]::EscapeDataString($File))&line=$Line$Extra" }

Write-Host 'handler: hostile URIs ...'
$hostile = [ordered]@{
  'UH-UNC'      = @((U '\\host\share\x.pas'), 'network or device path')
  'UH-WEBDAV'   = @((U '\\host@SSL\DavWWWRoot\x.hta'), 'network or device path')
  'UH-LONG'     = @((U '\\?\C:\Projects\x.pas'), 'network or device path')
  'UH-DEVICE'   = @((U '\\.\pipe\x.pas'), 'network or device path')
  'UH-SLASH'    = @((U '//host/share/x.pas'), 'network or device path')
  'UH-REL'      = @((U 'Blueprint4.pas'), 'not a local drive path')
  'UH-ROOTED'   = @((U '\Projects\x.pas'), 'not a local drive path')
  'UH-FWD'      = @((U 'C:/Projects/x.pas'), 'not a local drive path')
  'UH-PY'       = @((U 'C:\Users\x\Downloads\x.py'), 'extension not allowed: .py')
  'UH-HTA'      = @((U 'C:\Users\x\Downloads\x.hta'), 'extension not allowed: .hta')
  'UH-EXE'      = @((U 'C:\Windows\System32\calc.exe'), 'extension not allowed: .exe')
  'UH-DPROJ'    = @((U 'C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj'), 'extension not allowed: .dproj')
  'UH-NOEXT'    = @((U 'C:\Projects\x'), 'extension not allowed: (none)')
  'UH-ADS'      = @((U 'C:\Projects\a.exe:b.pas'), 'illegal character in path')
  'UH-DEVNAME'  = @((U 'C:\Projects\CON.pas'), 'reserved device name')
  'UH-LF'       = @(('draglint://open?file=C%3A%5Cx.pas%0AC%3A%5Cevil.pas%091&line=1'), 'control character in file')
  'UH-TAB'      = @(('draglint://open?file=C%3A%5Cx.pas%095&line=1'), 'control character in file')
  'UH-LINELF'   = @(('draglint://open?file=C%3A%5Cx.pas&line=1%0AC%3A%5Cevil.pas'), 'control character in line')
  'UH-LINEABC'  = @((U 'C:\Projects\x.pas' 'abc'), 'line is not a number')
  'UH-LINENEG'  = @((U 'C:\Projects\x.pas' '-3'), 'line is not a number')
  'UH-COL'      = @((U 'C:\Projects\x.pas' '1' '&col=x'), 'col is not a number')
  'UH-NOFILE'   = @('draglint://open?line=1', 'no file= in uri')
  'UH-SCHEME'   = @('file:///C:/x.pas', 'not a draglint uri')
  # fix round 2: SEC-R3 drops .dpk (a link never makes the IDE load a package); T-2 cases; B-2 non-ASCII digits
  'UH-DPK'      = @((U 'C:\Projects\x.dpk'), 'extension not allowed: .dpk')
  'UH-TRAILDOT' = @((U 'C:\Projects\x.hta.'), 'trailing dot or space')
  'UH-TRAILSP'  = @((U 'C:\Projects\x.hta '), 'trailing dot or space')
  'UH-STREAM'   = @((U 'C:\Projects\x.pas::$DATA'), 'illegal character in path')
  'UH-UDIGLINE' = @((U 'C:\Projects\x.pas' '%D9%A1%D9%A2'), 'line is not a number')
  'UH-UDIGCOL'  = @((U 'C:\Projects\x.pas' '1' '&col=%D9%A1'), 'col is not a number')
  'UH-DUPFILE'  = @(('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&file=%5C%5Chost%5Cx.pas'), 'duplicate file= in uri')
  'UH-DUPFILE2' = @(('draglint://open?file=%5C%5Chost%5Cx.pas&line=1&file=C%3A%5CP%5Ca.pas'), 'duplicate file= in uri')
  'UH-DUPLINE'  = @(('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&line=2'), 'duplicate line= in uri')
}
foreach ($k in $hostile.Keys) {
  Step $k {
    $r = Invoke-Handler $hostile[$k][0]
    $why = $hostile[$k][1]
    Chk $k "$($r.Exit)|$($r.Result.Ok)|$($r.Result.Reason)" "2|False|$why"
    if ($r.Log -notlike "*rejected: $why*") { Fail $k "the log does not name the reason: $($r.Log)" }
  }
}

Write-Host 'handler: good URIs ...'
Step 'UH-GOOD' {
  $r = Invoke-Handler (U 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas' '681')
  Chk 'UH-GOOD' "$($r.Exit)|$($r.Result.Ok)|$($r.Result.Payload)" '0|True|C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas<TAB>681<LF>'
}
Step 'UH-GOOD-EXT' {
  foreach ($f in 'C:\P\a.dfm', 'C:\P\a.dpr', 'C:\P\a.inc', 'C:\DB\SQL\MS1.SQL', 'C:\P\a.fmx', 'C:\P\A.PAS') {
    $r = Invoke-Handler (U $f '7')
    if ($r.Exit -ne 0 -or -not $r.Result.Ok) { Fail 'UH-GOOD-EXT' "$f refused: $($r.Result.Reason)" }
  }
}
Step 'UH-GOOD-COL' {
  $r = Invoke-Handler (U 'C:\P\a.pas' '12' '&col=5')
  Chk 'UH-GOOD-COL' "$($r.Exit)|$($r.Result.Payload)" '0|C:\P\a.pas<TAB>12<TAB>5<LF>'
}
# a chart's focus row carries line=0 (the focus box has no single line): it opens at line 1, as before
Step 'UH-LINE0' {
  $r = Invoke-Handler (U 'C:\P\a.pas' '0')
  Chk 'UH-LINE0' "$($r.Exit)|$($r.Result.Line)" '0|1'
}
# the browser may append a trailing slash to the whole URI
Step 'UH-SLASHEND' {
  $r = Invoke-Handler ((U 'C:\P\a.pas' '3') + '/')
  Chk 'UH-SLASHEND' "$($r.Exit)|$($r.Result.Line)" '0|3'
}

Write-Host 'handler: the validation function and Windows PowerShell 5.1 ...'
Step 'UH-FN' {
  # in a child process: dot-sourcing a script that runs `exit` would end THIS one
  $j = & pwsh -NoProfile -Command ". '$H'; Test-DragLintTarget -File '\\host\share\x.pas' -Line '1' -Col '' | ConvertTo-Json -Compress" 2>&1
  $v = $(try { ($j -join '') | ConvertFrom-Json } catch { $null })
  Chk 'UH-FN' "$($v.Ok)|$($v.Reason)" 'False|network or device path'
}
Step 'UH-PS5' {
  $ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  foreach ($s in $H, $REG) {
    $n = & $ps5 -NoProfile -Command "`$e = `$null; [void][Management.Automation.Language.Parser]::ParseFile('$s', [ref]`$null, [ref]`$e); `$e.Count"
    Chk 'UH-PS5' "$([IO.Path]::GetFileName($s)) parse errors under 5.1: $n" "$([IO.Path]::GetFileName($s)) parse errors under 5.1: 0"
  }
  $o = & $ps5 -NoProfile -ExecutionPolicy Bypass -File $H (U 'C:\P\a.pas' '9')
  if ("$o" -notmatch 'C:\\P\\a\.pas<TAB>9<LF>') { Fail 'UH-PS5' "5.1 run did not validate a good uri: $o" }
}

Write-Host 'handler: SEC-1 argument injection through the registered "%1" (pwsh 7 and 5.1) ...'
# The registry runs `"<ps>" ... -File "<handler>" "%1"`, %1 substituted RAW. A launcher that does not
# percent-encode `"` can close the quote and append parameters. Reproduced on the raw command line.
foreach ($runner in @(@('SEC-1-PS7', 'pwsh'), @('SEC-1-PS51', (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')))) {
  Step $runner[0] {
    $sb = Join-Path $OutDir ("sandbox-" + $runner[0])
    $lad = Join-Path $sb 'lad'; $evil = Join-Path $sb 'Startup\a.cmd'
    New-Item -ItemType Directory -Force $lad | Out-Null
    $inj = 'draglint://open?file=x&z=&calc&" -LogPath "' + $evil
    $keep = @{ L = $env:LOCALAPPDATA; W = $env:DRAGLINT_URI_TEST_WHATIF; G = $env:DRAGLINT_URI_TEST_LOG }
    try {
      # the child sees a sandboxed LOCALAPPDATA (the handler's fixed log lands in it) and what-if
      $env:LOCALAPPDATA = $lad
      [Environment]::SetEnvironmentVariable('DRAGLINT_URI_TEST_LOG', $null, 'Process')
      $pr = Start-Process -FilePath $runner[1] -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $H + '" "' + $inj + '"') -Wait -PassThru -NoNewWindow `
             -RedirectStandardOutput (Join-Path $OutDir "$($runner[0]).out") -RedirectStandardError (Join-Path $OutDir "$($runner[0]).err")
    } finally {
      $env:LOCALAPPDATA = $keep.L; $env:DRAGLINT_URI_TEST_WHATIF = $keep.W; $env:DRAGLINT_URI_TEST_LOG = $keep.G
    }
    $sbLog = Join-Path $lad 'drag-lint\uri-handler.log'
    $written = @(Get-ChildItem $sb -Recurse -File | Where-Object { $_.FullName -ne $sbLog } | ForEach-Object { $_.FullName })
    Chk $runner[0] "exit=$($pr.ExitCode) extra-files=$($written -join ',') startup-dir=$(Test-Path (Split-Path $evil))" 'exit=2 extra-files= startup-dir=False'
    $lg = $(if (Test-Path $sbLog) { Get-Content $sbLog -Raw } else { '' })
    if ($lg -notlike '*rejected: expected exactly one argument, the draglint:// uri (got 3)*') { Fail $runner[0] "the sandbox log does not name the reason: $lg" }
  }
}

Write-Host 'registration: dry runs ...'
$cmdKey = 'HKCU:\Software\Classes\draglint\shell\open\command'
function Read-Reg { if (Test-Path $cmdKey) { (Get-Item $cmdKey).GetValue('', $null, 'DoNotExpandEnvironmentNames') } else { '(absent)' } }
# the REAL install path, before/after (T-1): absent, or the same hash
$realCopy = Join-Path $env:LOCALAPPDATA 'drag-lint\Open-DragLintUri.ps1'
function Read-Copy { if (Test-Path -LiteralPath $realCopy) { (Get-FileHash -LiteralPath $realCopy).Hash } else { '(absent)' } }
$regBefore = Read-Reg; $copyBefore = Read-Copy
$fake = Join-Path $OutDir 'roots'
# every dry run below except RG-PF names this sandbox as -InstallDir: a copy there is a write (T-1)
$sbInst = Join-Path $OutDir 'install'
Step 'RG-PF' {
  $d = & $REG -DryRun -Force
  $want = "`"$env:ProgramFiles\PowerShell\7\pwsh.exe`" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:LOCALAPPDATA\drag-lint\Open-DragLintUri.ps1`" `"%1`""
  Chk 'RG-PF' "$($d.Kind)|$($d.Command)" "String|$want"
  Chk 'RG-PF-SRC' "$($d.HandlerSource)|$($d.HandlerInstalled)" "$H|$env:LOCALAPPDATA\drag-lint\Open-DragLintUri.ps1"
}
Step 'RG-ALIAS' {
  New-Item -ItemType Directory -Force "$fake\pf-empty", "$fake\lad\Microsoft\WindowsApps" | Out-Null
  Set-Content "$fake\lad\Microsoft\WindowsApps\pwsh.exe" 'fake' -Encoding ascii
  $d = & $REG -DryRun -Force -ProgramFilesRoot "$fake\pf-empty" -LocalAppDataRoot "$fake\lad" -InstallDir $sbInst
  Chk 'RG-ALIAS' "$($d.Kind)|$($d.Interpreter)" 'ExpandString|%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe'
}
Step 'RG-PS51' {
  New-Item -ItemType Directory -Force "$fake\lad-empty" | Out-Null
  $d = & $REG -DryRun -Force -ProgramFilesRoot "$fake\pf-empty" -LocalAppDataRoot "$fake\lad-empty" -InstallDir $sbInst
  Chk 'RG-PS51' "$($d.Kind)|$($d.Interpreter)" "String|$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
}
Step 'RG-MSIX' {
  $threw = ''
  try { & $REG -DryRun -Force -Interpreter 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.6.0_x64__8wekyb3d8bbwe\pwsh.exe' | Out-Null } catch { $threw = $_.Exception.Message }
  if ($threw -notlike '*versioned*WindowsApps*') { Fail 'RG-MSIX' "the versioned MSIX interpreter was not refused: [$threw]" }
}
Step 'RG-WT' {
  $threw = ''
  try { & $REG -DryRun | Out-Null } catch { $threw = $_.Exception.Message }
  if ($threw -notlike '*worktree*-Force*') { Fail 'RG-WT' "a worktree handler was not refused without -Force: [$threw]" }
}
# B-1: -Unregister -DryRun REPORTS what it would remove and removes nothing
Step 'RG-UNREG-DRY' {
  $inst = Join-Path $sbInst 'Open-DragLintUri.ps1'
  New-Item -ItemType Directory -Force $sbInst | Out-Null
  Set-Content $inst 'installed' -Encoding ascii
  $d = & $REG -Unregister -DryRun -InstallDir $sbInst
  $keyNow = $(if (Test-Path 'HKCU:\Software\Classes\draglint') { 'HKCU:\Software\Classes\draglint' } else { '' })
  Chk 'RG-UNREG-DRY' "$($d.Action)|$($d.RemoveKey)|$($d.RemoveCopy)" "Unregister|$keyNow|$inst"
  if (-not (Test-Path $inst)) { Fail 'RG-UNREG-DRY' '-Unregister -DryRun deleted the installed copy' }
  [IO.File]::Delete($inst)
}
Step 'RG-NOWRITE' {
  Chk 'RG-NOWRITE' "$(Read-Reg)|$(Read-Copy)" "$regBefore|$copyBefore"
  $null = & $REG -DryRun -Force -InstallDir $sbInst
  if (Test-Path (Join-Path $sbInst 'Open-DragLintUri.ps1')) { Fail 'RG-NOWRITE' 'a dry run copied the handler into -InstallDir' }
}

[Environment]::SetEnvironmentVariable('DRAGLINT_URI_TEST_WHATIF', $null, 'Process'); [Environment]::SetEnvironmentVariable('DRAGLINT_URI_TEST_LOG', $null, 'Process')
if ($fail.Count -eq 0) { Write-Host '  PASS -- the handler refuses every hostile URI; the dry run writes nothing.' -ForegroundColor Green; exit 0 }
Write-Host "  FAIL -- $($fail.Count) problem(s):" -ForegroundColor Red
$fail | ForEach-Object { Write-Host ("    [{0}] {1}" -f $_.Code, $_.Message) }
exit 1
