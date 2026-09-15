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
  [string]$WorkDir = "$env:TEMP\drag-lint-control-channel-guard",
  [int]$BusyProcs  = 9000
)
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
function Start-Engine([string[]]$ArgList, [string]$Tag) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $script:WorkDir
  $psi.CreateNoWindow = $true
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
function Start-Lsp([string]$Db, [string]$Tag) {
  $e = Start-Engine @('lsp', '--db', $Db) $Tag
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

} finally {
  Stop-Engines
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
