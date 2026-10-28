<#
  run_control_channel_guard.ps1 -- the maintenance control channel
  (docs\PLAN-maintenance-shutdown-channel.md, session 93 W3).

  WHAT IT PINS. An engine started in `lsp` mode listens on a per-user,
  per-session NAMED PIPE with an explicit DACL, and `drag-lint shutdown` can
  ask it to stand down: close every store, reply, exit 0 -- leaving NO -wal /
  -shm sidecar behind, which is the whole difference from TerminateProcess.
  The channel does one thing: `status` (describe yourself) and `shutdown`.
  Anything else is answered `unknown` and changes nothing.

  EVERY SAFETY REQUIREMENT OF THE PLAN IS AN ASSERTION HERE, with the way each
  can fail named in its Check:

    L   LISTENING (the fixture answers before the code does): the engine has
        answered `initialize` over stdio AND its pipe is enumerable in \\.\pipe
        before anything is asserted about a message. Without L, "it exited"
        passes against an engine that never started.
    N1  the pipe name carries THIS user's SID and THIS logon session id
    N2  the pipe's DACL grants exactly one trustee -- this user -- and names no
        Everyone / Users / Authenticated Users; POSITIVE CONTROL: the same
        reader, pointed at a pipe this script creates with an Everyone ACE,
        reports that ACE (else N2 is a reader that cannot see a bad DACL)
    T   no TCP listener belongs to the engine (Get-NetTCPConnection), and the
        unit's source names no socket API; POSITIVE CONTROL: the source scan
        finds a planted `listen(`
    U   a stray message is answered `unknown`; the engine still answers hover
        afterwards and is still running (the NEGATIVE of "a message stops it")
    G   NON-lsp engine: `serve --db` creates NO control pipe and the verb's
        --dry-run does not list it (the lsp-only gate, owner Q1 provisional)
    D   --dry-run: lists the engine, then the process is still alive and the
        database md5 is unchanged
    S   graceful: `drag-lint shutdown --db <x>` -> reply `exiting`, exit code
        0, no -wal / -shm left, md5 unchanged, audit line on the engine's
        stderr names the ASKING pid (the verb's own process id, known because
        this script launched it) and the audit file gained a line
    K   POSITIVE CONTROL for S's sidecar sentinel: a KILLED reader of the same
        fixture DOES leave -shm behind, so "no sidecar" is a real claim
    B   busy: an engine inside a handler (a large didOpen being linted) asked
        with a 1 ms deadline answers `busy<TAB>pid<TAB>textDocument/didOpen`,
        keeps running, finishes the request, and the db is byte-identical
    F1  --force with an engine that complies takes the GRACEFUL path: no
        ESCALATING line, exit 0
    F2  --force with a refusing (busy) engine escalates LOUDLY and only then
        kills; without --force the same busy engine is left running
    H   (F5, 2026-10-25) a host whose read WAS cancelled but which never finishes
        closing its stores gets the documented busy reply `stand-down started but
        not finished` once the store-close grace runs out -- before this fix the
        listener waited for FDone forever and the reply was unreachable. Test seams
        DRAGLINT_TEST_HANG_STORE_CLOSE_MS / DRAGLINT_TEST_STORE_CLOSE_GRACE_MS make it
        fast; POSITIVE CONTROL H-P: same seams, hang shorter than grace -> exiting

  RED FIRST against 1.12.0-alpha: the verb is unknown (exit 2) and no engine
  creates a pipe, so L, N*, U, D, S, B, F* fail; K and the positive controls
  pass, which is what makes the RED meaningful.

  A wait in this file is never a way to pass: every WaitUntil returns the
  predicate's LAST value and the Check asserts it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Unit    = "$PSScriptRoot\..\..\src\core\DRagLint.Core.ControlChannel.pas",
  [string]$CliPas  = "$PSScriptRoot\..\..\src\cli\DRagLint.CLI.pas",
  [string]$WorkDir = "$env:TEMP\drag-lint-control-channel-guard-$PID",
  [int]$BusyProcs  = 9000
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Engines = @()
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
# Opened with FileShare.ReadWrite: a live engine HOLDS the file, and Get-FileHash
# (share Read only) fails with "used by another process" -- which would read as
# a corrupted db rather than as the guard's own open mode.
function Md5([string]$Path) {
  $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
  try { $h = [System.Security.Cryptography.MD5]::Create(); return ([System.BitConverter]::ToString($h.ComputeHash($fs)) -replace '-', '') }
  finally { $fs.Dispose() }
}
function WriteAscii($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 12
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}
function Sidecars([string]$Db) {
  $r = @(); foreach ($s in '-wal', '-shm') { if (Test-Path -LiteralPath "$Db$s") { $r += $s } }
  return ($r -join ',')
}

# ---- engine fixture: a real child with a LIVE stdin (a file stdin is EOF) ----
function Start-Engine([string[]]$ArgList, [string]$Tag, [hashtable]$EnvVars = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $script:WorkDir
  $psi.CreateNoWindow = $true
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $e = @{ Tag = $Tag; P = $p
          Out = (New-Object System.IO.MemoryStream); Err = (New-Object System.IO.MemoryStream)
          OutBuf = (New-Object byte[] 65536); ErrBuf = (New-Object byte[] 65536); OutTask = $null; ErrTask = $null }
  $e.OutTask = $p.StandardOutput.BaseStream.ReadAsync($e.OutBuf, 0, 65536)
  $e.ErrTask = $p.StandardError.BaseStream.ReadAsync($e.ErrBuf, 0, 65536)
  $script:Engines += $e
  return $e
}
function Pump($e) {
  foreach ($k in 'Out', 'Err') {
    $t = $e["${k}Task"]
    while ($null -ne $t -and $t.IsCompleted) {
      $n = 0; try { $n = $t.Result } catch { $n = 0 }
      if ($n -le 0) { $e["${k}Task"] = $null; break }
      $e[$k].Write($e["${k}Buf"], 0, $n)
      $stream = if ($k -eq 'Out') { $e.P.StandardOutput.BaseStream } else { $e.P.StandardError.BaseStream }
      $t = $stream.ReadAsync($e["${k}Buf"], 0, 65536)
      $e["${k}Task"] = $t
    }
  }
}
function OutText($e) { Pump $e; return [System.Text.Encoding]::UTF8.GetString($e.Out.ToArray()) }
function ErrText($e) { Pump $e; return [System.Text.Encoding]::UTF8.GetString($e.Err.ToArray()) }
function WaitUntil([scriptblock]$Pred, [int]$Ms) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $Ms) { if (& $Pred) { return $true }; Start-Sleep -Milliseconds 40 }
  return [bool](& $Pred)
}
function Send-Lsp($e, $obj) {
  $b = [System.Text.Encoding]::UTF8.GetBytes((Frame $obj))
  $e.P.StandardInput.BaseStream.Write($b, 0, $b.Length); $e.P.StandardInput.BaseStream.Flush()
}
function Stop-Engines {
  foreach ($e in $script:Engines) { try { if (-not $e.P.HasExited) { $e.P.Kill($true) } } catch { } }
}
# The pipe the engine ANNOUNCES on stderr. The full name is asserted separately.
function PipeLeafOf($e, [int]$Ms) {
  $null = WaitUntil { (ErrText $e) -match 'control channel listening on \\\\\.\\pipe\\(\S+)' } $Ms
  if ((ErrText $e) -match 'control channel listening on \\\\\.\\pipe\\(\S+)') { return $Matches[1] }
  return ''
}
function Send-Ctl([string]$Leaf, [string]$Msg, [int]$TimeoutMs = 3000) {
  $c = New-Object System.IO.Pipes.NamedPipeClientStream('.', $Leaf, [System.IO.Pipes.PipeDirection]::InOut)
  try {
    $c.Connect($TimeoutMs)
    $b = [System.Text.Encoding]::UTF8.GetBytes($Msg + "`n"); $c.Write($b, 0, $b.Length); $c.Flush()
    $ms = New-Object System.IO.MemoryStream; $buf = New-Object byte[] 4096
    while ($true) { $n = $c.Read($buf, 0, 4096); if ($n -le 0) { break }; $ms.Write($buf, 0, $n); if ($buf[$n - 1] -eq 10) { break } }
    return ([System.Text.Encoding]::UTF8.GetString($ms.ToArray())).TrimEnd("`r", "`n")
  } finally { $c.Dispose() }
}
function PipesInNamespace { return @([System.IO.Directory]::GetFiles('\\.\pipe\') | ForEach-Object { $_.Substring(9) }) }
# Runs the VERB as its own process so its pid is known (the audit line must name it).
function Invoke-Verb([string[]]$ArgList, [string]$Tag) {
  $o = Join-Path $script:WorkDir "$Tag-verb-out.txt"; $er = Join-Path $script:WorkDir "$Tag-verb-err.txt"
  $inF = Join-Path $script:WorkDir 'empty-stdin.txt'; if (-not (Test-Path $inF)) { [System.IO.File]::WriteAllText($inF, '') }
  $p = Start-Process -FilePath $script:Exe -ArgumentList $ArgList -WorkingDirectory $script:WorkDir -PassThru -NoNewWindow `
         -RedirectStandardInput $inF -RedirectStandardOutput $o -RedirectStandardError $er
  $pid0 = $p.Id
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { }; $p.WaitForExit() }
  return @{ Pid = $pid0; Exit = $p.ExitCode; Out = [System.IO.File]::ReadAllText($o); Err = [System.IO.File]::ReadAllText($er) }
}

# ---- DACL reader: GetSecurityInfo on a client handle, rendered as SDDL ------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PipeAclProbe {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr h);
  [DllImport("advapi32.dll")]
  static extern uint GetSecurityInfo(IntPtr h, int objType, uint info, IntPtr o, IntPtr g, IntPtr d, IntPtr s, out IntPtr sd);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
  static extern bool ConvertSecurityDescriptorToStringSecurityDescriptorW(IntPtr sd, uint rev, uint info, out IntPtr str, out uint len);
  public static string Sddl(string pipe) {
    IntPtr h = CreateFileW(pipe, 0x80000000u | 0x40000000u | 0x00020000u, 0, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (h == new IntPtr(-1)) throw new System.ComponentModel.Win32Exception();
    try {
      IntPtr sd; uint rc = GetSecurityInfo(h, 6, 4, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out sd);
      if (rc != 0) throw new System.ComponentModel.Win32Exception((int)rc);
      IntPtr s; uint n;
      if (!ConvertSecurityDescriptorToStringSecurityDescriptorW(sd, 1, 4, out s, out n)) throw new System.ComponentModel.Win32Exception();
      string r = Marshal.PtrToStringUni(s); LocalFree(s); LocalFree(sd); return r;
    } finally { CloseHandle(h); }
  }
}
'@

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
New-Item -ItemType Directory "$WorkDir\projsrc" | Out-Null
$mySid     = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mySession = (Get-Process -Id $PID).SessionId
$auditFile = Join-Path $env:LOCALAPPDATA 'drag-lint\control-channel-audit.log'

try {
# ---------------------------------------------------------------- fixture ---
$projText = @'
unit ProjUnit;

interface

type
  TProjectThing = class
  public
    procedure ProjectOwnMethod(ACount: Integer);
  end;

procedure DriveProject;

implementation

procedure TProjectThing.ProjectOwnMethod(ACount: Integer);
begin
end;

procedure DriveProject;
var
  PThing: TProjectThing;
begin
  PThing := TProjectThing.Create;
  PThing.ProjectOwnMethod(1);
end;

end.
'@
$projFile = Join-Path $WorkDir 'projsrc\ProjUnit.pas'
WriteAscii $projFile $projText
$projLines = $projText -split "`r?`n"
$declLine  = [Array]::FindIndex($projLines, [Predicate[string]]{ param($x) $x -like '*procedure TProjectThing.ProjectOwnMethod(*' })
$declCol   = $projLines[$declLine].IndexOf('.ProjectOwnMethod') + 3
$uri       = 'file:///' + ($projFile -replace '\\', '/')

$pristine = Join-Path $WorkDir 'pristine.sqlite'
$o0 = (& $Exe index "$WorkDir\projsrc" --db $pristine 2>&1 | Out-String)
Check 'V1 fixture index exits 0' ($LASTEXITCODE -eq 0) ($o0 -split "`r?`n" | Select-Object -Last 1)
Check 'V2 fixture is populated and WAL' ((Test-Path $pristine) -and ((Get-Item $pristine).Length -gt 4096)) ''

function HoverAnswers($e, [int]$Id) {
  Send-Lsp $e @{ jsonrpc = '2.0'; id = $Id; method = 'textDocument/hover'; params = @{ textDocument = @{ uri = $uri }; position = @{ line = $declLine; character = $declCol } } }
  return (WaitUntil { (OutText $e) -match ('"id":' + $Id + '[,}]') -and (OutText $e) -match 'ProjectOwnMethod' } 8000)
}
function Start-Lsp([string]$Db, [string]$Tag, [hashtable]$EnvVars = @{}) {
  $e = Start-Engine @('lsp', '--db', $Db) $Tag $EnvVars
  Send-Lsp $e @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  Send-Lsp $e @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  Send-Lsp $e @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = $uri; languageId = 'pascal'; version = 1; text = $projText } } }
  $e.Init = WaitUntil { (OutText $e) -match '"id":1[,}]' } 15000
  return $e
}

# ---- L / N1 / N2 / T: a listening lsp engine, correctly scoped ------------
Write-Host ''
Write-Host 'L/N/T: an lsp engine listens on a user+session-scoped pipe with an explicit DACL, and on no TCP port' -ForegroundColor Cyan
$c1 = Join-Path $WorkDir 'c1.sqlite'; Copy-Item $pristine $c1
$md5c1 = Md5 $c1
$A = Start-Lsp $c1 'A'
Check 'L1 engine A answered initialize over stdio (it is SERVING, not merely started)' $A.Init ("pid " + $A.P.Id)
$leafA = PipeLeafOf $A 5000
Check 'L2 engine A announced its control pipe on stderr' ($leafA -ne '') (($leafA) + ' | ' + ((ErrText $A) -split "`r?`n" | Select-Object -First 3) -join ' / ')
Check 'L3 the announced pipe is enumerable in \\.\pipe (it is LISTENING)' (($leafA -ne '') -and ((PipesInNamespace) -contains $leafA)) ''
$expectedLeaf = "drag-lint-ctl-$mySid-s$mySession-p$($A.P.Id)"
Check 'N1 pipe name = drag-lint-ctl-<this SID>-s<this session>-p<pid>' ($leafA -eq $expectedLeaf) "expected $expectedLeaf got $leafA"
$sddlA = ''
if ($leafA -ne '') { try { $sddlA = [PipeAclProbe]::Sddl("\\.\pipe\$leafA") } catch { $sddlA = "ERROR: $($_.Exception.Message)" } }
$aceCount = ([regex]::Matches($sddlA, '\(A;')).Count
Check 'N2a the DACL has exactly ONE allow ACE' ($aceCount -eq 1) $sddlA
Check 'N2b that ACE names THIS user''s SID' ($sddlA -match ([regex]::Escape(";;;$mySid)"))) ''
Check 'N2c the DACL names no Everyone / Users / Authenticated Users / NULL' (($sddlA -ne '') -and ($sddlA -notmatch ';;;(WD|BU|AU|S-1-1-0|S-1-5-11|S-1-5-32-545)\)') -and ($sddlA -match '^D:')) $sddlA
# N2 positive control: the reader sees an Everyone ACE when there is one.
$ctlLeaf = 'zz-ctl-guard-open-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$sddlCtl = ''
try {
  $sec = New-Object System.IO.Pipes.PipeSecurity
  $everyone = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
  $sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($everyone, [System.IO.Pipes.PipeAccessRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))
  $srv = [System.IO.Pipes.NamedPipeServerStreamAcl]::Create($ctlLeaf, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, 0, 0, $sec)
  $null = $srv.BeginWaitForConnection($null, $null)
  $sddlCtl = [PipeAclProbe]::Sddl("\\.\pipe\$ctlLeaf")
  $srv.Dispose()
} catch { $sddlCtl = "ERROR: $($_.Exception.Message)" }
Check 'N2 POSITIVE CONTROL: the DACL reader reports an Everyone ACE on a pipe that has one' ($sddlCtl -match ';;;(WD|S-1-1-0)\)') $sddlCtl
$tcp = @()
try { $tcp = @(Get-NetTCPConnection -OwningProcess $A.P.Id -State Listen -ErrorAction SilentlyContinue) } catch { $tcp = @() }
Check 'T1 engine A owns NO listening TCP socket' ($tcp.Count -eq 0) (($tcp | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" }) -join ' ')
$unitSrc = if (Test-Path $Unit) { [System.IO.File]::ReadAllText($Unit) } else { '' }
$sockRx = '(?i)\b(WinSock|WSAStartup|socket\(|bind\(|listen\(|accept\(|Indy|IdTCP)'
Check 'T2 the control-channel unit exists' ($unitSrc -ne '') $Unit
Check 'T3 the unit names no socket API' (($unitSrc -ne '') -and ($unitSrc -notmatch $sockRx)) ''
Check 'T3 POSITIVE CONTROL: the scan sees a planted listen(' (($unitSrc + "`n  listen(S, 5);") -match $sockRx) ''
Check 'T4 the unit builds its DACL from an explicit SDDL naming one trustee' ($unitSrc -match "D:P\(A;;GA;;;") ''
Check 'T5 CreateNamedPipe is handed the security attributes, not nil' (($unitSrc -match 'CreateNamedPipe\w*\(') -and ($unitSrc -notmatch '(?s)CreateNamedPipe\w*\([^;]*,\s*nil\s*\)')) ''
$cliSrc = if (Test-Path $CliPas) { [System.IO.File]::ReadAllText($CliPas) } else { '' }
$gateSites = ([regex]::Matches(($unitSrc + $cliSrc), 'ControlChannelEnabledFor')).Count
Check 'T6 the lsp-only gate function exists and is consulted from the CLI (ONE named place)' ($gateSites -ge 3) "sites=$gateSites"

# ---- U: a stray message changes nothing --------------------------------------
Write-Host ''
Write-Host 'U: a stray message is answered unknown and the engine carries on' -ForegroundColor Cyan
$ru = ''
if ($leafA -ne '') { try { $ru = Send-Ctl $leafA 'reindex-everything-now' } catch { $ru = "ERROR: $($_.Exception.Message)" } }
Check 'U1 reply is unknown<TAB>pid' ($ru -eq "unknown`t$($A.P.Id)") "got [$ru]"
Check 'U2 engine A still running after the stray message' (-not $A.P.HasExited) ''
Check 'U3 engine A still answers hover (a stray message stopped nothing)' (HoverAnswers $A 20) ''
$rs = ''
if ($leafA -ne '') { try { $rs = Send-Ctl $leafA 'status' } catch { $rs = "ERROR: $($_.Exception.Message)" } }
$rsF = $rs -split "`t"
Check 'U4 status names pid and the db it holds' (($rsF.Count -ge 5) -and ($rsF[0] -eq 'status') -and ($rsF[1] -eq "$($A.P.Id)") -and ($rsF[4..($rsF.Count-1)] -contains $c1)) "got [$rs]"

# ---- G: a non-lsp engine does not listen (the gate) --------------------------
Write-Host ''
Write-Host 'G: an engine NOT in lsp mode has no control pipe and is not listed' -ForegroundColor Cyan
$c2 = Join-Path $WorkDir 'c2.sqlite'; Copy-Item $pristine $c2
$Bsrv = Start-Engine @('serve', '--db', $c2) 'Bserve'
Start-Sleep -Milliseconds 1500
Check 'G0 the serve engine is running (fixture alive)' (-not $Bsrv.P.HasExited) ("pid " + $Bsrv.P.Id)
$leafB = "drag-lint-ctl-$mySid-s$mySession-p$($Bsrv.P.Id)"
Check 'G1 no control pipe exists for the serve engine' (-not ((PipesInNamespace) -contains $leafB)) $leafB

# ---- D: --dry-run lists and changes nothing ----------------------------------
Write-Host ''
Write-Host 'D: --dry-run lists engine A, does not list the serve engine, changes nothing' -ForegroundColor Cyan
$d = Invoke-Verb @('shutdown', '--dry-run') 'D'
Check 'D1 verb exits 0' ($d.Exit -eq 0) ("exit $($d.Exit): " + $d.Err)
Check 'D2 dry run lists engine A by pid' ($d.Out -match ('(?m)^\s*pid\s+' + $A.P.Id + '\b')) $d.Out
Check 'D3 dry run lists the db engine A holds' ($d.Out -match [regex]::Escape($c1)) ''
Check 'D4 dry run does NOT list the serve engine' ($d.Out -notmatch ('\b' + $Bsrv.P.Id + '\b')) ''
Check 'D5 dry run says it changed nothing' ($d.Out -match '(?i)dry run') ''
Check 'D6 engine A still running after the dry run' (-not $A.P.HasExited) ''
Check 'D7 engine A db md5 unchanged' ((Md5 $c1) -eq $md5c1) ''
$dOther = Invoke-Verb @('shutdown', '--dry-run', '--db', $c2) 'Dother'
Check 'D8 --db <other> selects nothing: engine A is NOT listed for a db it does not hold' (($dOther.Exit -eq 0) -and ($dOther.Out -notmatch ('\b' + $A.P.Id + '\b'))) $dOther.Out

# ---- K: positive control for the sidecar sentinel ----------------------------
Write-Host ''
Write-Host 'K: POSITIVE CONTROL -- a KILLED reader leaves -shm behind' -ForegroundColor Cyan
$c3 = Join-Path $WorkDir 'c3.sqlite'; Copy-Item $pristine $c3
$K = Start-Lsp $c3 'K'
Check 'K1 engine K answered initialize' $K.Init ''
$K.P.Kill($true); $K.P.WaitForExit()
Check 'K2 after TerminateProcess a sidecar remains (so S3 below can fail)' ((Sidecars $c3) -ne '') ("sidecars=" + (Sidecars $c3))

# ---- S: graceful stand-down via the verb -------------------------------------
Write-Host ''
Write-Host 'S: drag-lint shutdown --db <c1> -- exiting, exit 0, no sidecar, md5 unchanged, audited' -ForegroundColor Cyan
$auditBefore = if (Test-Path $auditFile) { @(Get-Content -LiteralPath $auditFile).Count } else { 0 }
$s = Invoke-Verb @('shutdown', '--db', $c1, '--wait', '15') 'S'
Check 'S1 verb exits 0' ($s.Exit -eq 0) ("exit $($s.Exit): " + $s.Out + $s.Err)
Check 'S2 verb reports engine A exiting and exited' (($s.Out -match ('pid\s+' + $A.P.Id + '\b.*exiting')) -and ($s.Out -match 'exited')) $s.Out
$exitedA = WaitUntil { $A.P.HasExited } 15000
Check 'S3 engine A process exited' $exitedA ''
Check 'S4 engine A exit code 0' ($exitedA -and ($A.P.ExitCode -eq 0)) ("code " + $(if ($exitedA) { $A.P.ExitCode } else { 'n/a' }))
Check 'S5 no -wal / -shm sidecar left behind (the difference from a kill)' ((Sidecars $c1) -eq '') ("sidecars=" + (Sidecars $c1))
Check 'S6 db md5 unchanged' ((Md5 $c1) -eq $md5c1) ''
$errA = ErrText $A
Check 'S7 audit line on the engine''s stderr names the ASKING pid (the verb''s process)' ($errA -match ('control channel:.*honoured.*asked by pid ' + $s.Pid + '\b')) (($errA -split "`r?`n" | Where-Object { $_ -match 'control channel' }) -join ' / ')
$auditAfter = if (Test-Path $auditFile) { @(Get-Content -LiteralPath $auditFile).Count } else { 0 }
$auditTail = if (Test-Path $auditFile) { @(Get-Content -LiteralPath $auditFile | Select-Object -Last 3) -join ' / ' } else { '' }
Check 'S8 the audit file gained a line naming engine A' (($auditAfter -gt $auditBefore) -and ($auditTail -match ('\b' + $A.P.Id + '\b'))) $auditTail
Check 'S9 the pipe is gone with the process' (-not ((PipesInNamespace) -contains $leafA)) ''
Check 'S10 the serve engine was left alone by --db' (-not $Bsrv.P.HasExited) ''

# ---- B: a busy engine refuses, says why, and is unchanged --------------------
Write-Host ''
Write-Host 'B: an engine inside a handler answers busy, keeps running, db byte-identical' -ForegroundColor Cyan
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("unit BigUnit;`n`ninterface`n`n")
for ($i = 0; $i -lt $BusyProcs; $i++) { [void]$sb.Append("procedure BusyProc$i(AValue: Integer);`n") }
[void]$sb.Append("`nimplementation`n`n")
for ($i = 0; $i -lt $BusyProcs; $i++) {
  [void]$sb.Append("procedure BusyProc$i(AValue: Integer);`nvar`n  LLocal: Integer;`nbegin`n  LLocal := AValue * 2;`n  if LLocal > 10 then LLocal := LLocal - 1;`nend;`n`n")
}
[void]$sb.Append("end.`n")
$bigText = $sb.ToString() -replace "`n", "`r`n"
$bigFile = Join-Path $WorkDir 'projsrc\BigUnit.pas'
WriteAscii $bigFile $bigText
$bigUri = 'file:///' + ($bigFile -replace '\\', '/')
$c4 = Join-Path $WorkDir 'c4.sqlite'; Copy-Item $pristine $c4
$md5c4 = Md5 $c4
$Bz = Start-Lsp $c4 'B'
Check 'B0 engine B answered initialize' $Bz.Init ''
$leafBz = PipeLeafOf $Bz 5000
Send-Lsp $Bz @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = $bigUri; languageId = 'pascal'; version = 1; text = $bigText } } }
Start-Sleep -Milliseconds 400
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$rb = ''
if ($leafBz -ne '') { try { $rb = Send-Ctl $leafBz "shutdown`t1" 10000 } catch { $rb = "ERROR: $($_.Exception.Message)" } }
$busyMs = $sw.ElapsedMilliseconds
Check 'B1 reply is busy<TAB>pid<TAB>textDocument/didOpen' ($rb -eq "busy`t$($Bz.P.Id)`ttextDocument/didOpen") "got [$rb] after $busyMs ms"
Check 'B2 engine B still running after the refusal' (-not $Bz.P.HasExited) ''
$diagDone = WaitUntil { (OutText $Bz) -match 'publishDiagnostics.*BigUnit' } 120000
Check 'B3 engine B finished the request it was busy with (diagnostics published)' $diagDone ''
Check 'B4 db md5 unchanged after the refusal' ((Md5 $c4) -eq $md5c4) ''
Check 'B5 stderr records the refusal with the reason' ((ErrText $Bz) -match 'control channel:.*REFUSED.*textDocument/didOpen') ''

# ---- F1: --force with a compliant engine takes the graceful path -------------
Write-Host ''
Write-Host 'F1: --force is NOT taken when the engine complies' -ForegroundColor Cyan
Check 'F1-0 engine B answers hover after its busy spell (fixture alive)' (HoverAnswers $Bz 30) ''
$f1 = Invoke-Verb @('shutdown', '--db', $c4, '--wait', '15', '--force') 'F1'
Check 'F1-1 verb exits 0' ($f1.Exit -eq 0) ($f1.Out + $f1.Err)
Check 'F1-2 no ESCALATING line -- graceful path taken first' ($f1.Out -notmatch 'ESCALAT') $f1.Out
Check 'F1-3 engine B exited 0' ((WaitUntil { $Bz.P.HasExited } 15000) -and ($Bz.P.ExitCode -eq 0)) ''
Check 'F1-4 no sidecar' ((Sidecars $c4) -eq '') ("sidecars=" + (Sidecars $c4))

# ---- F2: --force escalates ONLY after a refusal, and loudly ------------------
Write-Host ''
Write-Host 'F2: a refusing engine is left alone without --force, escalated loudly with it' -ForegroundColor Cyan
$c5 = Join-Path $WorkDir 'c5.sqlite'; Copy-Item $pristine $c5
$Fz = Start-Lsp $c5 'F'
Check 'F2-0 engine F answered initialize' $Fz.Init ''
$null = PipeLeafOf $Fz 5000
Send-Lsp $Fz @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = $bigUri; languageId = 'pascal'; version = 1; text = $bigText } } }
Start-Sleep -Milliseconds 400
$f2a = Invoke-Verb @('shutdown', '--db', $c5, '--wait', '0') 'F2a'
Check 'F2-1 without --force: verb reports BUSY and exits 1' (($f2a.Exit -eq 1) -and ($f2a.Out -match 'BUSY')) ("exit $($f2a.Exit): " + $f2a.Out)
Check 'F2-2 without --force: engine F still running' (-not $Fz.P.HasExited) ''
$f2b = Invoke-Verb @('shutdown', '--db', $c5, '--wait', '0', '--force') 'F2b'
Check 'F2-3 with --force: says ESCALATING (loudly, naming the refusal)' ($f2b.Out -match 'ESCALAT') $f2b.Out
Check 'F2-4 with --force: engine F is gone' (WaitUntil { $Fz.P.HasExited } 10000) ''
Check 'F2-5 the escalation was AFTER a graceful attempt (BUSY reported first in the same output)' (($f2b.Out -match 'BUSY') -and ($f2b.Out.IndexOf('BUSY') -lt $f2b.Out.IndexOf('ESCALAT'))) ''

# ---- H: read cancelled, stores never close -> busy after the grace (F5) -------
Write-Host ''
Write-Host 'H: a host that hangs closing its stores gets busy "stand-down started but not finished" within the grace' -ForegroundColor Cyan
$hangEnv = @{ DRAGLINT_TEST_HANG_STORE_CLOSE_MS = '9000'; DRAGLINT_TEST_STORE_CLOSE_GRACE_MS = '1500' }
$c6 = Join-Path $WorkDir 'c6.sqlite'; Copy-Item $pristine $c6
$Hz = Start-Lsp $c6 'H' $hangEnv
Check 'H0 engine H answered initialize' $Hz.Init ''
$leafHz = PipeLeafOf $Hz 5000
$null = WaitUntil { (OutText $Hz) -match 'publishDiagnostics' } 15000
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$rh = ''
if ($leafHz -ne '') { try { $rh = Send-Ctl $leafHz "shutdown`t5000" 10000 } catch { $rh = "ERROR: $($_.Exception.Message)" } }
$hangMs = $sw.ElapsedMilliseconds
Check 'H1 reply is busy<TAB>pid<TAB>stand-down started but not finished' ($rh -eq "busy`t$($Hz.P.Id)`tstand-down started but not finished") "got [$rh] after $hangMs ms"
Check 'H2 the reply came after the grace and before the hang ended (1500 <= ms < 7000)' (($hangMs -ge 1500) -and ($hangMs -lt 7000)) "$hangMs ms"
Check 'H3 stderr audits the unfinished stand-down' ((ErrText $Hz) -match 'control channel:.*read cancelled but the host has not closed its stores') ''
Check 'H4 engine H still exits once its store close returns' (WaitUntil { $Hz.P.HasExited } 30000) ''

Write-Host ''
Write-Host 'H-S: after a store-close BUSY reply the engine exits promptly (W5-C: FReplied was never set -> teardown waited the 5 s reply join) and the audit grace is not integer-divided to 0 s' -ForegroundColor Cyan
$slowEnv = @{ DRAGLINT_TEST_HANG_STORE_CLOSE_MS = '3000'; DRAGLINT_TEST_STORE_CLOSE_GRACE_MS = '500' }
$c8 = Join-Path $WorkDir 'c8.sqlite'; Copy-Item $pristine $c8
$Hs = Start-Lsp $c8 'HS' $slowEnv
Check 'H-S0 engine HS answered initialize' $Hs.Init ''
$leafHs = PipeLeafOf $Hs 5000
$null = WaitUntil { (OutText $Hs) -match 'publishDiagnostics' } 15000
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$rs = ''
if ($leafHs -ne '') { try { $rs = Send-Ctl $leafHs "shutdown`t5000" 10000 } catch { $rs = "ERROR: $($_.Exception.Message)" } }
Check 'H-S1 reply is the busy "not finished" answer' ($rs -match '^busy\t' -and $rs -match 'not finished') "got [$rs]"
$null = WaitUntil { $Hs.P.HasExited } 30000
$hsMs = $sw.ElapsedMilliseconds
Check 'H-S2 engine HS exited promptly after its 3 s store close (< 8500 ms from the request; measured 6.1 s fixed, 11.2 s with the 5 s reply join)' ($Hs.P.HasExited -and ($hsMs -lt 8500)) "$hsMs ms"
Check 'H-S3 the audit names the grace in ms, not 0 s' ((ErrText $Hs) -match 'not closed its stores after 500 ms') ''

Write-Host ''
Write-Host 'H-P: POSITIVE CONTROL -- same seams, hang shorter than the grace -> exiting (the FDone path)' -ForegroundColor Cyan
$okEnv = @{ DRAGLINT_TEST_HANG_STORE_CLOSE_MS = '1000'; DRAGLINT_TEST_STORE_CLOSE_GRACE_MS = '6000' }
$c7 = Join-Path $WorkDir 'c7.sqlite'; Copy-Item $pristine $c7
$Hp = Start-Lsp $c7 'HP' $okEnv
Check 'H-P0 engine HP answered initialize' $Hp.Init ''
$leafHp = PipeLeafOf $Hp 5000
$null = WaitUntil { (OutText $Hp) -match 'publishDiagnostics' } 15000
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$rp = ''
if ($leafHp -ne '') { try { $rp = Send-Ctl $leafHp "shutdown`t5000" 10000 } catch { $rp = "ERROR: $($_.Exception.Message)" } }
$hpMs = $sw.ElapsedMilliseconds
Check 'H-P1 reply is exiting<TAB>pid...' ($rp -match ('^exiting\t' + $Hp.P.Id + '\b')) "got [$rp] after $hpMs ms"
Check 'H-P2 the hang seam is live: the reply waited for it (>= 1000 ms)' ($hpMs -ge 1000) "$hpMs ms"
Check 'H-P3 engine HP exited 0' ((WaitUntil { $Hp.P.HasExited } 15000) -and ($Hp.P.ExitCode -eq 0)) ''
# ---- W (DEC-13): the long one-shot verbs (index, lint-all) listen and stand down cleanly ----
Write-Host ''
Write-Host 'W: index and lint-all open the control channel; shutdown stops them between files, cleanly, resumably' -ForegroundColor Cyan
$bigDir = Join-Path $WorkDir 'bigsrc'
New-Item -ItemType Directory -Force $bigDir | Out-Null
$nBig = 60
for ($i = 1; $i -le $nBig; $i++) {
  WriteAscii (Join-Path $bigDir ("BigUnit$i.pas")) ("unit BigUnit$i;`r`n`r`ninterface`r`n`r`nprocedure Big$i;`r`n`r`nimplementation`r`n`r`nprocedure Big$i;`r`nbegin`r`nend;`r`n`r`nend.`r`n")
}
function IntegrityOk([string]$Db) {
  # sqlite3's own PRAGMA integrity_check, through Python's stdlib (the sql verb refuses PRAGMA by design).
  try {
    $o = (& python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('PRAGMA integrity_check').fetchone()[0])" $Db 2>$null | Out-String).Trim()
  } catch { return $false }
  return ($o -eq 'ok')
}
function FilesIn([string]$Db) {
  $o = (& $script:Exe sql --query "SELECT count(*) AS n FROM files" --db $Db --json 2>$null | Out-String) -replace '\s', ''
  if ($o -match '"rows":\[\[(\d+)\]') { return [int]$Matches[1] }
  return -1
}$slowIdx = @{ DRAGLINT_TEST_INDEX_FILE_DELAY_MS = '200' }
$w1db = Join-Path $WorkDir 'w1.sqlite'
$W1 = Start-Engine @('index', $bigDir, '--db', $w1db) 'W1' $slowIdx
$leafW1 = PipeLeafOf $W1 15000
Check 'W1a index engine announces a control pipe (the gate widened beyond lsp/cycles)' ($leafW1 -ne '') $leafW1
$null = WaitUntil { (ErrText $W1) -match '\[\d+/\d+\]' } 20000
Check 'W1b index is mid-walk when asked (not finished)' (-not $W1.P.HasExited) ''
$wv = Invoke-Verb @('shutdown', '--db', $w1db, '--wait', '30') 'W1v'
Check 'W1c shutdown verb exits 0 and reports the index engine exiting' (($wv.Exit -eq 0) -and ($wv.Out -match ('pid\s+' + $W1.P.Id + '\b.*exiting'))) ($wv.Out + $wv.Err)
Check 'W1d index process exited by itself with the stand-down code 4 (not killed)' ((WaitUntil { $W1.P.HasExited } 30000) -and ($W1.P.ExitCode -eq 4)) ("code " + $(if ($W1.P.HasExited) { $W1.P.ExitCode } else { 'running' }))
Check 'W1e no -wal / -shm left behind' ((Sidecars $w1db) -eq '') ("sidecars=" + (Sidecars $w1db))
Check 'W1f database integrity_check ok' (IntegrityOk $w1db) ''
$partial = FilesIn $w1db
Check 'W1g stopped part-way: some files committed, not all' (($partial -gt 0) -and ($partial -lt $nBig)) "files=$partial of $nBig"
$re = Invoke-Verb @('index', $bigDir, '--db', $w1db) 'W1r'
Check 'W1h the same command resumes and exits 0' ($re.Exit -eq 0) ("exit $($re.Exit): " + ($re.Out -split "`r?`n" | Select-Object -Last 2) -join ' ')
Check 'W1i resumed index holds every file' ((FilesIn $w1db) -eq $nBig) ("files=" + (FilesIn $w1db))
Check 'W1j integrity_check ok after the resume' (IntegrityOk $w1db) ''

# lint-all: stops between files and reports partial
$slowLint = @{ DRAGLINT_TEST_LINT_FILE_DELAY_MS = '300' }
$W2 = Start-Engine @('lint-all', '--db', $w1db) 'W2' $slowLint
$leafW2 = PipeLeafOf $W2 20000
Check 'W2a lint-all announces a control pipe' ($leafW2 -ne '') $leafW2
$null = WaitUntil { (ErrText $W2) -match 'lint-all: \[\d+/\d+\]' } 20000
$wv2 = Invoke-Verb @('shutdown', '--db', $w1db, '--wait', '30') 'W2v'
Check 'W2b shutdown verb reports the lint-all engine exiting' (($wv2.Exit -eq 0) -and ($wv2.Out -match ('pid\s+' + $W2.P.Id + '\b.*exiting'))) ($wv2.Out + $wv2.Err)
Check 'W2c lint-all exited with the stand-down code 4' ((WaitUntil { $W2.P.HasExited } 30000) -and ($W2.P.ExitCode -eq 4)) ''
Check 'W2d stderr says PARTIAL' (WaitUntil { (ErrText $W2) -match 'PARTIAL' } 5000) ''
Check 'W2e database untouched by lint-all (integrity ok, no sidecar)' ((IntegrityOk $w1db) -and ((Sidecars $w1db) -eq '')) ''

# POSITIVE CONTROLS: lsp still stands down (S above), and a verb outside the gate still has no pipe (G above).
Write-Host 'W-P: POSITIVE CONTROL -- without the stand-down, the same slowed index completes with exit 0' -ForegroundColor Cyan
$w3db = Join-Path $WorkDir 'w3.sqlite'
$W3 = Start-Engine @('index', $bigDir, '--db', $w3db) 'W3' @{ DRAGLINT_TEST_INDEX_FILE_DELAY_MS = '20' }
# the engine's stdout/stderr pipes must be drained or a 64 KB pipe stalls it mid-run (that, not a stand-down, made this read 40 of 60)
Check 'W-P1 an unasked index completes, exit 0, every file present' ((WaitUntil { Pump $W3; $W3.P.HasExited } 120000) -and ($W3.P.ExitCode -eq 0) -and ((FilesIn $w3db) -eq $nBig)) ("files=" + (FilesIn $w3db))
Check 'W-P2 the pipe is gone with the process' (-not ((PipesInNamespace) -contains $leafW1)) ''

# ---- ST (DEC-13 owner addition): the stager asks through the channel first, kills last ----
Write-Host ''
Write-Host 'ST: build\stage-engine.ps1 stops a holder through the channel (nothing killed); an engine with no channel is the last-resort kill' -ForegroundColor Cyan
$stager = (Resolve-Path (Join-Path $PSScriptRoot '..\..\build\stage-engine.ps1')).Path
$exeDir = Split-Path -Parent $Exe
function Make-Target([string]$Name) {
  $d = Join-Path $WorkDir "stage-$Name"; New-Item -ItemType Directory -Force $d | Out-Null
  Copy-Item (Join-Path $exeDir '*.dll') $d -ErrorAction SilentlyContinue
  Copy-Item $Exe (Join-Path $d 'drag-lint.exe') -Force
  return (Join-Path $d 'drag-lint.exe')
}
function Start-FromTarget([string]$Target, [string[]]$ArgList, [string]$Tag, [hashtable]$EnvVars) {
  $saved = $script:Exe; $script:Exe = $Target
  try { return (Start-Engine $ArgList $Tag $EnvVars) } finally { $script:Exe = $saved }
}
# -StandDownScope names this run's own database, so the test never stands down the owner's real IDE engines.
function Run-Stager([string]$Target, [string]$Db) {
  $o = & pwsh -NoProfile -File $stager -FreshExe $Exe -Target $Target -TimeoutSec 40 -HoldSeconds 1 -StandDownWaitSec 30 -StandDownDb $Db 2>&1 | Out-String
  return @{ Exit = $LASTEXITCODE; Out = $o }
}
$stDb = Join-Path $WorkDir 'st1.sqlite'
$tgt1 = Make-Target 'idx'
$S1 = Start-FromTarget $tgt1 @('index', $bigDir, '--db', $stDb) 'ST1' $slowIdx
$null = PipeLeafOf $S1 15000
$null = WaitUntil { (ErrText $S1) -match '\[\d+/\d+\]' } 20000
Check 'ST1a an index run holds the target image' (-not $S1.P.HasExited) ''
$r1 = Run-Stager $tgt1 $stDb
Check 'ST1b stager exits 0 (staged) instead of REFUSING to stage over an index run' ($r1.Exit -eq 0) (($r1.Out -split "`r?`n" | Select-Object -Last 4) -join ' | ')
Check 'ST1c the index run stood down through the channel (exit 4), it was not killed' ((WaitUntil { $S1.P.HasExited } 30000) -and ($S1.P.ExitCode -eq 4)) ''
Check 'ST1d the stager reports nothing was killed' (($r1.Out -match 'nothing was killed') -and ($r1.Out -notmatch 'stopped PID')) ''
Check 'ST1e the target is the fresh build' ((Md5 $tgt1) -eq (Md5 $Exe)) ''
Check 'ST1f the interrupted index left a consistent database, no sidecar' ((IntegrityOk $stDb) -and ((Sidecars $stDb) -eq '')) ''

$tgt2 = Make-Target 'srv'
$stDb2 = Join-Path $WorkDir 'st2.sqlite'; Copy-Item $pristine $stDb2
$S2 = Start-FromTarget $tgt2 @('serve', '--db', $stDb2) 'ST2' @{}
Start-Sleep -Milliseconds 1500
Check 'ST2a a serve engine (no channel) holds the target image' (-not $S2.P.HasExited) ''
$r2 = Run-Stager $tgt2 $stDb2
Check 'ST2b LAST RESORT: with no channel to ask, the holder is stopped and staging succeeds' (($r2.Exit -eq 0) -and ($r2.Out -match 'stopped PID')) (($r2.Out -split "`r?`n" | Select-Object -Last 4) -join ' | ')
Check 'ST2c the serve engine is gone and the target is the fresh build' ((WaitUntil { $S2.P.HasExited } 15000) -and ((Md5 $tgt2) -eq (Md5 $Exe))) ''

$iss = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\installer\drag-lint.iss'))
Check 'ST3 the installer stops the old engine through the channel before installing (StopRunningEngines called from PrepareToInstall)' (($iss -match 'sh' + 'utdown --all --wait') -and ($iss -match '(?s)function PrepareToInstall.*?StopRunningEngines;')) ''

} finally {
  Stop-Engines
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-control-channel-guard-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
