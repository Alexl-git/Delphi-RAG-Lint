<#
  run_uri_handler.ps1 -- drag-lint-open.exe, the GUI-subsystem draglint:// handler, refuses every
  hostile URI and accepts every good one with the exact IDE pipe payload.

  WHAT-IF ONLY. Every run sets DRAGLINT_URI_TEST_WHATIF=1 (validate and log a `whatif:` line; never
  the pipe, never a process) and DRAGLINT_URI_TEST_LOG=<scratch>\uri-handler.log -- the environment
  is the handler's only override channel (ruling SEC-R2: one argument, the URI, nothing else). So
  this guard never opens notepad, never writes to a running IDE and never writes the REAL
  %LOCALAPPDATA%\drag-lint\logs\uri-handler.log -- which it asserts, byte count before and after.

  Builds nothing: it expects src\tools\uri-handler\Win64\Debug\drag-lint-open.exe (the scratch
  build-open wrapper, or build\build_uri_handler.bat) and is a SETUP failure (exit 2) without it.

    UH-*        the UH-* table of tests\fixtures\T68_draglint_uri.dpr, row for row: exit code, the
                logged verdict (`rejected: <reason>` / `resolved:`) and the `whatif:` line's
                ok / reason / payload
    UH-NOARG    zero arguments, and UH-TWOARGS two: refused before the URI is looked at
    SEC-1       the handler run AS THE REGISTRY RUNS IT (`"<exe>" "%1"`, %1 substituted RAW) with an
                argument-injecting %1 (`..." -LogPath "<file>`): three arguments, refused, nothing
                written outside the sandboxed LOCALAPPDATA log folder
    UH-LOGCAP   a 30 KB URI (and a 30 KB URI plus an extra argument): no log line over 600 chars
    UH-GUI      the PE subsystem is WINDOWS_GUI (2): a browser click never flashes a console
    UH-REALLOG  the real uri-handler.log is unchanged
    PARITY-*    GOLDEN parity with the retired charts\src\Open-DragLintUri.ps1: the exe must give
                the verdict and payload the script gave on every row (frozen from its last green
                parity run, 2026-10-14: the row's own Ok / Payload). The exe is STRICTER BY DESIGN
                on a few rows (ruling R9: non-ASCII query keys refused); those rows are declared
                in $KnownStricter, where the script ACCEPTED -- exe refuses, script accepted. The
                exe must never accept a row the script refused. PARITY-SEC-1: the script refused
                the injected %1 with exit 2 (frozen), and so must the exe.

  Exit: 0 all PASS, 1 any FAIL, 2 setup.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\tools\uri-handler\Win64\Debug\drag-lint-open.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uri-handler-guard-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

. "$PSScriptRoot\lib\UriHandlerExe.ps1"
if (-not $PSBoundParameters.ContainsKey('Exe')) { [void](Initialize-UriHandlerExe -Path $Exe) }  # X-06: stage into a fresh worktree
if (-not (Test-Path -LiteralPath $Exe)) {
  Write-Host "SETUP: drag-lint-open.exe not found: $Exe" -ForegroundColor Red
  Write-Host '       build it (Win64 Debug) first; this guard builds nothing' -ForegroundColor Red
  exit 2
}
$Exe = (Resolve-Path -LiteralPath $Exe).ProviderPath
if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$log       = Join-Path $WorkDir 'uri-handler.log'
$realLog   = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'drag-lint\logs\uri-handler.log' } else { '' })
function Get-RealLogSize { if ($realLog -and (Test-Path -LiteralPath $realLog)) { (Get-Item -LiteralPath $realLog).Length } else { -1 } }
$realBefore = Get-RealLogSize
$keepEnv = @{ L = $env:LOCALAPPDATA; W = $env:DRAGLINT_URI_TEST_WHATIF; G = $env:DRAGLINT_URI_TEST_LOG; T = $env:DRAGLINT_URI_TEST_TIMEOUT }

# ---- the row table: T68_draglint_uri.dpr, case for case ------------------------------------------
# Non-ASCII characters as [char] codes: this file stays 7-bit ASCII. (Not named R / A: R is the
# alias of Invoke-History.)
$SUP1 = [string][char]0x00B9; $SUP2 = [string][char]0x00B2; $SUP3 = [string][char]0x00B3
$IDOT = [string][char]0x0130; $INODOT = [string][char]0x0131; $LONGS = [string][char]0x017F; $KELVIN = [string][char]0x212A
$NOT_LOCAL = 'not a local drive path (X:\...)'
function U([string] $File, [string] $Line = '1', [string] $Extra = '') { "draglint://open?file=$([uri]::EscapeDataString($File))&line=$Line$Extra" }
$rows = New-Object System.Collections.ArrayList
function Refused([string] $Id, [string] $Uri, [string] $Why) { [void]$rows.Add([pscustomobject]@{ Id = $Id; Argv = @($Uri); Ok = $false; Reason = $Why; Payload = '' }) }
function Accepted([string] $Id, [string] $Uri, [string] $Payload) { [void]$rows.Add([pscustomobject]@{ Id = $Id; Argv = @($Uri); Ok = $true; Reason = ''; Payload = $Payload }) }

Refused 'UH-UNC'          (U '\\host\share\x.pas')                 $NOT_LOCAL
Refused 'UH-WEBDAV'       (U '\\host@SSL\DavWWWRoot\x.hta')        $NOT_LOCAL
Refused 'UH-LONG'         (U '\\?\C:\Projects\x.pas')              $NOT_LOCAL
Refused 'UH-DEVICE'       (U '\\.\pipe\x.pas')                     $NOT_LOCAL
Refused 'UH-SLASH'        (U '//host/share/x.pas')                 $NOT_LOCAL
Refused 'UH-REL'          (U 'Blueprint4.pas')                     $NOT_LOCAL
Refused 'UH-ROOTED'       (U '\Projects\x.pas')                    $NOT_LOCAL
Refused 'UH-FWD'          (U 'C:/Projects/x.pas')                  $NOT_LOCAL
Refused 'UH-PY'           (U 'C:\Users\x\Downloads\x.py')          'extension ".py" is not a source file'
Refused 'UH-HTA'          (U 'C:\Users\x\Downloads\x.hta')         'extension ".hta" is not a source file'
Refused 'UH-EXE'          (U 'C:\Windows\System32\calc.exe')       'extension ".exe" is not a source file'
Refused 'UH-DPROJ'        (U 'C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj') 'extension ".dproj" is not a source file'
Refused 'UH-NOEXT'        (U 'C:\Projects\x')                      'extension "" is not a source file'
Refused 'UH-ADS'          (U 'C:\Projects\a.exe:b.pas')            'character ":" not allowed after the drive'
Refused 'UH-DEVNAME'      (U 'C:\Projects\CON.pas')                'reserved device name "CON"'
Refused 'UH-LF'           'draglint://open?file=C%3A%5Cx.pas%0AC%3A%5Cevil.pas%091&line=1' 'control character in file'
Refused 'UH-TAB'          'draglint://open?file=C%3A%5Cx.pas%095&line=1' 'control character in file'
Refused 'UH-LINELF'       'draglint://open?file=C%3A%5Cx.pas&line=1%0AC%3A%5Cevil.pas' 'control character in line'
Refused 'UH-COLTAB'       (U 'C:\Projects\x.pas' '1' '&col=%09')  'control character in col'
Refused 'UH-LINEABC'      (U 'C:\Projects\x.pas' 'abc')            'line is not a number'
Refused 'UH-LINENEG'      (U 'C:\Projects\x.pas' '-3')             'line is not a number'
Refused 'UH-LINE10'       (U 'C:\Projects\x.pas' '1234567890')     'line is not a number'
Refused 'UH-COL'          (U 'C:\Projects\x.pas' '1' '&col=x')    'col is not a number'
Refused 'UH-NOFILE'       'draglint://open?line=1'                 'no file= in uri'
Refused 'UH-NOQUERY'      'draglint://open'                        'no file= in uri'
Refused 'UH-SCHEME'       'file:///C:/x.pas'                       'not a draglint uri'
Refused 'UH-BLANK'        '   '                                    'no uri given'
Refused 'UH-DPK'          (U 'C:\Projects\x.dpk')                  'extension ".dpk" is not a source file'
Refused 'UH-TRAILDOT'     (U 'C:\Projects\x.hta.')                 'extension "." is not a source file'
Refused 'UH-TRAILSP'      (U 'C:\Projects\x.hta ')                 'extension ".hta " is not a source file'
Refused 'UH-SEGDOT'       (U 'C:\Projects\dir.\x.pas')             'a path segment ends in a dot or a space'
Refused 'UH-SEGSP'        (U 'C:\Projects\dir \x.pas')             'a path segment ends in a dot or a space'
Refused 'UH-STREAM'       (U 'C:\Projects\x.pas::$DATA')           'character ":" not allowed after the drive'
Refused 'UH-UDIGLINE'     (U 'C:\Projects\x.pas' '%D9%A1%D9%A2')   'line is not a number'
Refused 'UH-UDIGCOL'      (U 'C:\Projects\x.pas' '1' '&col=%D9%A1') 'col is not a number'
Refused 'UH-DUPFILE'      'draglint://open?file=C%3A%5CP%5Ca.pas&line=1&file=%5C%5Chost%5Cx.pas' 'duplicate file= in uri'
Refused 'UH-DUPFILE2'     'draglint://open?file=%5C%5Chost%5Cx.pas&line=1&file=C%3A%5CP%5Ca.pas' 'duplicate file= in uri'
Refused 'UH-DUPLINE'      'draglint://open?file=C%3A%5CP%5Ca.pas&line=1&line=2' 'duplicate line= in uri'
Refused 'UH-DUPCASE'      'draglint://open?file=C%3A%5CP%5Ca.pas&line=1&LINE=2' 'duplicate line= in uri'
Refused 'UH-KELVIN'       'draglint://open?file=%E2%84%AA%3A%5CP%5Cx.pas&line=1' $NOT_LOCAL
Refused 'UH-KELVIN-CODE'  (U ($KELVIN + ':\x.pas'))                $NOT_LOCAL
Refused 'UH-DOTTEDI'      'draglint://open?file=%C4%B0%3A%5CP%5Cx.pas&line=1' $NOT_LOCAL
Refused 'UH-COMSUP1'      (U ('C:\P\COM' + $SUP1 + '.pas'))        ('reserved device name "COM' + $SUP1 + '"')
Refused 'UH-COMSUP2'      (U ('C:\P\COM' + $SUP2 + '.pas'))        ('reserved device name "COM' + $SUP2 + '"')
Refused 'UH-LPTSUP3'      (U ('C:\P\lpt' + $SUP3 + '.pas'))        ('reserved device name "lpt' + $SUP3 + '"')
Refused 'UH-LPTSUP1'      (U ('C:\P\LPT' + $SUP1 + '\x.pas'))      ('reserved device name "LPT' + $SUP1 + '"')
Refused 'UH-COM1'         (U 'C:\P\COM1.pas')                      'reserved device name "COM1"'
Refused 'UH-LONGS'        (U ('C:\P\x.pa' + $LONGS))               ('extension ".pa' + $LONGS + '" is not a source file')
Refused 'UH-DEVMULTIDOT'  (U 'C:\P\CON.x.pas')                     'reserved device name "CON"'
Refused 'UH-DEVSPACE'     (U 'C:\P\NUL .pas')                      'reserved device name "NUL"'
Refused 'UH-COM0'         (U 'C:\P\COM0.pas')                      'reserved device name "COM0"'
Refused 'UH-LPT0'         (U 'C:\P\lpt0.pas')                      'reserved device name "lpt0"'
Refused 'UH-LPT0-DIR'     (U 'C:\P\LPT0\x.pas')                    'reserved device name "LPT0"'
Refused 'UH-DEVFOLD'      (U ('C:\P\CON' + $IDOT + 'N$.pas'))      ('reserved device name "CON' + $IDOT + 'N$"')
Refused 'UH-DEVFOLD-DIR'  (U ('C:\P\con' + $INODOT + 'n$\x.pas'))  ('reserved device name "con' + $INODOT + 'n$"')
Refused 'UH-KEY-NONASCII' ('draglint://open?file=C%3A%5CP%5Ca.pas&line=1&F' + $IDOT + 'LE=%5C%5Chost%5Cx.pas') 'non-ascii key in uri'
Refused 'UH-KEY-KELVIN'   ('draglint://open?' + $KELVIN + '=1&file=C%3A%5CP%5Ca.pas') 'non-ascii key in uri'

Accepted 'UH-GOOD'         (U 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas' '681') 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas<TAB>681<LF>'
Accepted 'UH-GOOD-COL'     (U 'C:\P\a.pas' '12' '&col=5')          'C:\P\a.pas<TAB>12<TAB>5<LF>'
Accepted 'UH-LINE0'        (U 'C:\P\a.pas' '0')                     'C:\P\a.pas<TAB>1<LF>'
Accepted 'UH-NOLINE'       'draglint://open?file=C%3A%5CP%5Ca.pas'  'C:\P\a.pas<TAB>1<LF>'
Accepted 'UH-EMPTYLINE'    (U 'C:\P\a.pas' '')                      'C:\P\a.pas<TAB>1<LF>'
Accepted 'UH-SLASHEND'     ((U 'C:\P\a.pas' '3') + '/')             'C:\P\a.pas<TAB>3<LF>'
Accepted 'UH-TRIM'         (' ' + (U 'C:\P\a.pas' '3') + '//  ')    'C:\P\a.pas<TAB>3<LF>'
Accepted 'UH-CASE'         'DragLint://OPEN?FILE=C%3A%5CP%5Ca.pas&Line=4' 'C:\P\a.pas<TAB>4<LF>'
Accepted 'UH-HOSTJUNK'     'draglint://whatever?file=C%3A%5CP%5Ca.pas&line=2&junk&=x&z=' 'C:\P\a.pas<TAB>2<LF>'
Accepted 'UH-PLUS'         'draglint://open?file=C%3A%5CP%5Ca+b.pas&line=2' 'C:\P\a+b.pas<TAB>2<LF>'
Accepted 'UH-DECODE-ONCE'  'draglint://open?file=C%3A%5CP%5C%2541.pas&line=2' 'C:\P\%41.pas<TAB>2<LF>'
Accepted 'UH-BADUTF8'      'draglint://open?file=C%3A%5CP%5Cx%FF.pas&line=2' 'C:\P\x%FF.pas<TAB>2<LF>'
Accepted 'UH-EMPTYCOL'     (U 'C:\P\a.pas' '7' '&col=')            'C:\P\a.pas<TAB>7<LF>'
Accepted 'UH-GOOD-EXT-dfm' (U 'C:\P\a.dfm' '7')                     'C:\P\a.dfm<TAB>7<LF>'
Accepted 'UH-GOOD-EXT-dpr' (U 'C:\P\a.dpr' '7')                     'C:\P\a.dpr<TAB>7<LF>'
Accepted 'UH-GOOD-EXT-inc' (U 'C:\P\a.inc' '7')                     'C:\P\a.inc<TAB>7<LF>'
Accepted 'UH-GOOD-EXT-SQL' (U 'C:\DB\SQL\MS1.SQL' '7')              'C:\DB\SQL\MS1.SQL<TAB>7<LF>'
Accepted 'UH-GOOD-EXT-fmx' (U 'C:\P\a.fmx' '7')                     'C:\P\a.fmx<TAB>7<LF>'
Accepted 'UH-GOOD-EXT-PAS' (U 'C:\P\A.PAS' '7')                     'C:\P\A.PAS<TAB>7<LF>'
Accepted 'UH-KEY-PCT'      'draglint://open?file=C%3A%5CP%5Ca.pas&line=1&F%C4%B0LE=%5C%5Chost%5Cx.pas' 'C:\P\a.pas<TAB>1<LF>'
Accepted 'UH-NOTCON'       (U 'C:\P\Console.pas' '7')               'C:\P\Console.pas<TAB>7<LF>'

[void]$rows.Add([pscustomobject]@{ Id = 'UH-NOARG'; Argv = @(); Ok = $false; Reason = 'expected exactly one argument, the draglint:// uri (got 0)'; Payload = '' })
[void]$rows.Add([pscustomobject]@{ Id = 'UH-TWOARGS'; Argv = @((U 'C:\P\a.pas' '1'), 'second'); Ok = $false; Reason = 'expected exactly one argument, the draglint:// uri (got 2)'; Payload = '' })

# Rows where the exe refuses BY DESIGN what the script accepts (ruling R9), measured 2026-10-14 against
# the script under pwsh 7: a raw U+212A query key (the script ignores it as an unknown key) and a device
# name spelled with U+0131 dotless i (-match does not fold it onto I). UH-KEY-NONASCII is NOT here: the
# script's culture ToLower folds F<U+0130>LE onto file= and refuses it as a duplicate. Nothing else may differ.
$KnownStricter = @('UH-KEY-KELVIN', 'UH-DEVFOLD-DIR')

# ---- running the exe ----------------------------------------------------------------------------
# A GUI-subsystem exe is not waited for by `& exe`, so it is started through Process and waited on.
# The command line is built RAW (each argument in double quotes, as the registry's "%1" does), so
# the exe's own ParamStr split is what is tested; no row argument may itself contain a quote.
function Format-RawArgs([string[]] $Argv) {
  foreach ($a in $Argv) { if ($a.Contains('"')) { throw "row argument holds a double quote: $a" } }
  (@($Argv) | ForEach-Object { '"' + $_ + '"' }) -join ' '
}
function Get-LogLines([string] $Path) { if (Test-Path -LiteralPath $Path) { @([IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) } else { @() } }
function Invoke-Exe([string] $RawArgs, [string] $LogFile = $log) {
  $before = @(Get-LogLines $LogFile).Count
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe, $RawArgs)
  $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(20000)) { $p.Kill(); throw "drag-lint-open.exe did not exit in 20 s: $RawArgs" }
  $added = @(Get-LogLines $LogFile | Select-Object -Skip $before)
  [pscustomobject]@{ Exit = $p.ExitCode; Log = $added }
}
# the `whatif:` line, split: ok / reason / payload (separators already spelled <TAB> / <LF>)
$StampRx = '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d  '
function Get-WhatIf($Lines) {
  $w = @($Lines | Where-Object { $_ -match ($StampRx + 'whatif: ok=([01]) reason=(.*) payload=(.*)$') })
  if ($w.Count -ne 1) { return $null }
  $null = $w[0] -match ($StampRx + 'whatif: ok=([01]) reason=(.*) payload=(.*)$')
  [pscustomobject]@{ Ok = ($Matches[1] -eq '1'); Reason = $Matches[2]; Payload = $Matches[3] }
}

$env:DRAGLINT_URI_TEST_WHATIF = '1'
$env:DRAGLINT_URI_TEST_LOG    = $log
[Environment]::SetEnvironmentVariable('DRAGLINT_URI_TEST_TIMEOUT', $null, 'Process')

try {
Write-Host 'drag-lint-open.exe: the UH-* table (what-if) ...'
$exeVerdict = @{}
foreach ($row in $rows) {
  $r = Invoke-Exe (Format-RawArgs $row.Argv)
  $w = Get-WhatIf $r.Log
  $exeVerdict[$row.Id] = $w
  $wantExit = $(if ($row.Ok) { 0 } else { 2 })
  $stamped  = @($r.Log | Where-Object { $_ -notmatch $StampRx }).Count -eq 0
  $verdictLine = $(if ($row.Ok) { @($r.Log | Where-Object { $_ -match ($StampRx + 'resolved: file=') }).Count -eq 1 }
                   else { @($r.Log | Where-Object { ($_ -match $StampRx) -and ($_.Substring(21) -ceq ('rejected: ' + $row.Reason)) }).Count -eq 1 })
  $got  = $(if ($w) { "exit=$($r.Exit) ok=$([int]$w.Ok) reason=[$($w.Reason)] payload=[$($w.Payload)]" } else { "exit=$($r.Exit) (no single whatif line; log: $($r.Log -join ' | '))" })
  $want = "exit=$wantExit ok=$([int]$row.Ok) reason=[$($row.Reason)] payload=[$($row.Payload)]"
  Check $row.Id (($got -ceq $want) -and $verdictLine -and $stamped) $(if ($got -ceq $want -and $verdictLine -and $stamped) { '' } else { "want $want; got $got; verdict-line=$verdictLine stamped=$stamped" })
}

Write-Host 'drag-lint-open.exe: SEC-1 argument injection through the registered "%1" ...'
# The registry runs `"<exe>" "%1"` with %1 substituted RAW; a launcher that does not percent-encode
# `"` closes the quote and appends parameters. The child sees a sandboxed LOCALAPPDATA and no
# DRAGLINT_URI_TEST_LOG, so its FIXED log path lands in the sandbox -- the only file it may write.
$sb = Join-Path $WorkDir 'sandbox-SEC-1'; $lad = Join-Path $sb 'lad'; $evil = Join-Path $sb 'Startup\a.cmd'
New-Item -ItemType Directory -Force $lad | Out-Null
$inj = 'draglint://open?file=C%3A%5Cx.pas" -LogPath "' + $evil
$sbLog = Join-Path $lad 'drag-lint\logs\uri-handler.log'
try {
  $env:LOCALAPPDATA = $lad
  [Environment]::SetEnvironmentVariable('DRAGLINT_URI_TEST_LOG', $null, 'Process')
  $r = Invoke-Exe ('"' + $inj + '"') $sbLog
} finally {
  $env:LOCALAPPDATA = $keepEnv.L; $env:DRAGLINT_URI_TEST_LOG = $log
}
$written = @(Get-ChildItem $sb -Recurse -File | Where-Object { $_.FullName -ne $sbLog } | ForEach-Object { $_.FullName })
$sec1 = "exit=$($r.Exit) extra-files=$($written -join ',') startup-dir=$(Test-Path (Split-Path $evil))"
Check 'SEC-1' ($sec1 -ceq 'exit=2 extra-files= startup-dir=False') $sec1
$named = @($r.Log | Where-Object { $_ -like '*rejected: expected exactly one argument, the draglint:// uri (got 3)' }).Count -eq 1
Check 'SEC-1-LOG' $named 'the sandbox log names the reason (got 3)'

Write-Host 'drag-lint-open.exe: log lines capped for a 30 KB URI ...'
$big = 'draglint://open?file=' + ('a' * 30000)
$r1 = Invoke-Exe ('"' + $big + '"')
$r2 = Invoke-Exe ('"' + $big + '" "second"')
$added = @($r1.Log) + @($r2.Log)
$longest = ($added | Measure-Object -Property Length -Maximum).Maximum
$marked = @($added | Where-Object { $_ -match '\.\.\.\(\+\d+ chars\)' }).Count
$cap = "lines=$($added.Count) longest<=600=$($longest -le 600) marked=$marked exits=$($r1.Exit),$($r2.Exit)"
Check 'UH-LOGCAP' ($cap -ceq 'lines=6 longest<=600=True marked=2 exits=2,2') $cap

Write-Host 'drag-lint-open.exe: GUI subsystem ...'
$b = [IO.File]::ReadAllBytes($Exe)
$pe = [BitConverter]::ToInt32($b, 0x3C)
$subsystem = [BitConverter]::ToUInt16($b, $pe + 24 + 68)
Check 'UH-GUI' ($subsystem -eq 2) "PE optional-header Subsystem=$subsystem (2 = WINDOWS_GUI, 3 = console)"

Write-Host 'PARITY with the retired charts\src\Open-DragLintUri.ps1 (golden) ...'
# The script's verdict, frozen from its last green parity run (2026-10-14): the row's own Ok and
# Payload, except the $KnownStricter rows, which the script accepted.
foreach ($row in $rows) {
  $sOk  = [bool]($row.Ok -or ($KnownStricter -contains $row.Id))
  $sPay = $(if ($row.Ok) { $row.Payload } else { '' })
  $e = $exeVerdict[$row.Id]
  $eOk = [bool]($e -and $e.Ok); $ePay = $(if ($e) { $e.Payload } else { '' })
  if ($KnownStricter -contains $row.Id) {
    Check "PARITY-$($row.Id)" ((-not $eOk) -and $sOk) "known-stricter: exe ok=$eOk, script ok=$sOk (want exe refuses, script accepted)"
  } else {
    $same = ($eOk -eq $sOk) -and ($ePay -ceq $sPay)
    Check "PARITY-$($row.Id)" $same $(if ($same) { '' } else { "exe ok=$eOk payload=[$ePay]; script(golden) ok=$sOk payload=[$sPay]" })
  }
  if ($eOk -and -not $sOk) { Check "PARITY-NEVER-LOOSER-$($row.Id)" $false 'the exe accepted a row the script refused' }
}
# SEC-1: the script, run as its registration ran it, refused the injected %1 with exit 2 (frozen)
$ScriptSec1Exit = 2
Check 'PARITY-SEC-1' ($ScriptSec1Exit -eq 2 -and $r.Exit -ne 0) "script(golden) exit=$ScriptSec1Exit, exe exit=$($r.Exit) (both refuse)"
Check 'PARITY-SEC-1-NOFILE' (-not (Test-Path (Split-Path $evil))) 'nothing at the injected path'
$realAfter = Get-RealLogSize
Check 'UH-REALLOG' ($realAfter -eq $realBefore) "real uri-handler.log bytes before=$realBefore after=$realAfter (-1 = absent)"
} finally {
  $env:LOCALAPPDATA = $keepEnv.L
  foreach ($kv in @(@('DRAGLINT_URI_TEST_WHATIF', $keepEnv.W), @('DRAGLINT_URI_TEST_LOG', $keepEnv.G), @('DRAGLINT_URI_TEST_TIMEOUT', $keepEnv.T))) {
    [Environment]::SetEnvironmentVariable($kv[0], $kv[1], 'Process')
  }
}

if ($script:Failed) { Write-Host 'run_uri_handler: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_uri_handler: PASS' -ForegroundColor Green
if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
exit 0
