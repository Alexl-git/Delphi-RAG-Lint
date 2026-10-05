<#
  run_proptree_output_speed.ps1 -- proptree / convert-scaffold write their
  stdout document fast, byte-identical, and AFTER every stderr byte (engine
  1.20.6, task T2i).

  WHY. proptree wrote its document with Writeln through the RTL's 128-byte
  Text buffer, and Writeln does not flush a file or a pipe -- only a console.
  Two consequences, both measured 2026-09-30 on FireDAC.Comp.Client.TFDQuery
  (scratch library copy, --refs-as-leaves --no-write-back --json):
    * the document left in ~290,000 128-byte WriteFile calls: depth 5
      (101,063 nodes, 37 MB) took 80 s through the editor's own pipe drain
      (4 KB reads, a 40 ms wait whenever the pipe is momentarily empty) and
      514 s through a PowerShell Start-Process redirect, against a ~13 s
      tree build. The JSON DOM and Format(2) cost ~0.4 s -- the WRITE was it.
    * a stderr note sat in ErrOutput's 128-byte buffer until exit, so a caller
      that merges both streams into ONE pipe (the editor does) got the note
      split around the document: the head before the first '{', the tail
      after the last '}'.
  The fix (WriteStdoutDocument): flush ErrOutput, flush Output, write the
  whole document through a 1 MiB buffer, flush. Same RTL conversion, same
  bytes.

  ARMS
    m  (always) merged stream on a fixture whose index is STALE (its .pas is
       touched after indexing, so a freshness note goes to stderr): via
       `cmd /c "... > file 2>&1"`, the merged bytes are EXACTLY the stderr
       bytes followed by the stdout bytes of a separate-stream run -- proptree
       --json, proptree text, convert-scaffold; and the '{'..'}' slice parses
       with the full node count.
    p  (always) --progress-interval as the LAST argument (no value) exits 2 on
       proptree and convert-scaffold, naming the flag (T2e review minor 2).
    h  (always) --help says "whole seconds", never "decimal seconds" (T2e
       review minor 3).
    a  (-OldExe) byte-identity, differential: every run_proptree*.ps1 and
       run_convert_scaffold*.ps1 runner is run with -Exe pointing at a SHIM
       that runs each proptree / convert-scaffold call on BOTH engines and
       compares stdout by SHA256 (and the exit code); each proptree call is
       also run as json and text, each with no --min-visibility, public and
       published. The shim answers the runner with the new engine's bytes.
    r  (-OldExe -LibDb) byte-identity on the real library: Bde.DBTables.TQuery
       and FireDAC.Comp.Client.TFDQuery at --depth 3 and 4, json and text, and
       --min-visibility public / published at depth 3.
    b  (-LibDb) speed: TFDQuery --depth 5 --refs-as-leaves --no-write-back,
       --json and text, through an in-process replica of the editor's pipe
       drain (ConvRules.Engine.pas RunCaptureTimed); best of 2 < 60 s each.
    l  (-LibDb) merged stream on the real library: TFDQuery --depth 4 --json
       through the same replica; merged bytes == stderr ++ stdout of a
       separate run (the scratch library's stale-resolver note is the stderr
       note); the slice parses with the separate run's node count.
    c  (-LibDb, and -OldD5Json or -OldExe) TFDQuery --depth 5 --json, old vs
       new, by SHA256. Pass -OldD5Json <file> to reuse a kept old output.
    e  (always; fix round 1, ruling R18) the other JSON verbs the rules editor
       runs merged -- convert-apply (dry run and --apply), convert-reemit,
       info --json, query --name --json, outline --format json, sql --json --
       from a work dir holding a .drag-lint.json, so the "(loaded defaults
       ...)" banner is on stderr: merged == stderr ++ stdout, and the
       '{'..'}' (or '['..']') slice parses with the expected keys. With
       -OldExe also: stdout identical to the old engine (info masks exe_path,
       build_date and the two DLL lines).
    k  (always) stdout on a CONSOLE (a hidden window): proptree --json exits 0;
       the writer uses <= 32 KiB pieces there. A positive control only.

  RED 2026-10-04 (fix round 1), the ed5cdd4c build, no -OldExe / -LibDb:
  27 PASS / 7 FAIL -- the seven e "merged == stderr ++ stdout" checks (the
  banner landed AFTER the document on every verb). The e slice checks PASSED
  there: the banner carries no brace, so slicing survived -- they are positive
  controls. GREEN, same flags, the fix-round build: 34 PASS / 0 FAIL.

  RED 2026-09-30, the pre-T2i build (fa846fcb copy), -OldExe = itself:
  m and l FAIL (the stale-index / resolver note is split around the document:
  head before the first '{', tail after the last '}'); p FAILS (exit 3,
  Unknown argument); h FAILS ("decimal seconds"); b FAILS (json depth 5:
  71.8 s best of 2 through the editor drain): 8 PASS / 9 FAIL with -LibDb.
  GREEN 2026-09-30, the T2i build, with -OldExe -LibDb -OldD5Json: 21 PASS /
  0 FAIL -- a: 576 of 576 cases equal (80 proptree calls x 7 variants + 16
  convert-scaffold calls), r: 16 of 16, c: equal, b: json 14.4 s, text 12.7 s.
  Run from a NEUTRAL CWD, pwsh 7. Every engine run passes an explicit --db.
    pwsh -File tests\autotest\run_proptree_output_speed.ps1 [-Exe <engine>]
      [-OldExe <pre-T2i engine copy>] [-LibDb <scratch library-Win64.sqlite>]
      [-OldD5Json <old TFDQuery depth-5 json>]
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-outspeed-$PID",
  [string]$OldExe    = '',
  [string]$LibDb     = '',
  [string]$OldD5Json = '',
  [double]$LimitS    = 60
)
try {
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if ($OldExe) {
  if (-not (Test-Path $OldExe)) { Write-Host "FATAL: old exe not found: $OldExe" -ForegroundColor Red; exit 2 }
  $OldExe = (Resolve-Path $OldExe).Path
}
if ($LibDb -and -not (Test-Path $LibDb)) { Write-Host "FATAL: -LibDb not found: $LibDb" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
Write-Host ("engine : {0}" -f $Exe) -ForegroundColor Cyan
if ($OldExe) { Write-Host ("old    : {0}" -f $OldExe) -ForegroundColor Cyan }
if ($LibDb)  { Write-Host ("lib db : {0}" -f $LibDb) -ForegroundColor Cyan }

function P([string]$n) { return (Join-Path $WorkDir $n) }
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Sha([byte[]]$B) {
  $h = [System.Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($h.ComputeHash($B)) -replace '-', '') } finally { $h.Dispose() }
}
function SameBytes([byte[]]$A, [byte[]]$B) {
  if ($A.Length -ne $B.Length) { return $false }
  return ((Sha $A) -eq (Sha $B))
}
function Concat([byte[]]$A, [byte[]]$B) {
  $r = New-Object byte[] ($A.Length + $B.Length)
  [Array]::Copy($A, 0, $r, 0, $A.Length)
  [Array]::Copy($B, 0, $r, $A.Length, $B.Length)
  return ,$r
}
# Separate streams, raw bytes, via ProcessStartInfo (no PowerShell decoding).
function RunRaw([string]$E, [string[]]$A) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new($E)
  foreach ($x in $A) { $psi.ArgumentList.Add($x) }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $ms = [System.IO.MemoryStream]::new(); $es = [System.IO.MemoryStream]::new()
  $t = $p.StandardError.BaseStream.CopyToAsync($es)
  $p.StandardOutput.BaseStream.CopyTo($ms)
  $t.Wait(); $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $ms.ToArray(); Err = $es.ToArray() }
}
# Both streams into ONE file, the way cmd's 2>&1 shares a handle.
# cmd.exe gets its command line verbatim (ProcessStartInfo.Arguments), so the
# /s quoting is exactly what a user would type -- no PowerShell re-quoting.
function RunMergedCmd([string]$E, [string]$ArgLine, [string]$Tag) {
  $f = P "$Tag.merged"
  $psi = [System.Diagnostics.ProcessStartInfo]::new("$env:ComSpec")
  $psi.Arguments = '/s /c ""' + $E + '" ' + $ArgLine + ' > "' + $f + '" 2>&1"'
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.WaitForExit()
  return [System.IO.File]::ReadAllBytes($f)
}
function Ascii([byte[]]$B) { return [System.Text.Encoding]::ASCII.GetString($B) }
function SliceJson([string]$S) {
  $a = $S.IndexOf('{'); $b = $S.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($S.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}

# The editor's pipe drain, ConvRules.Engine.pas TEngineAdapter.RunCaptureTimed:
# ONE pipe for stdout AND stderr, 4 KB reads while PeekNamedPipe reports bytes,
# else a 40 ms wait on the process.
if (-not ('T2iEditorDrain' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class T2iEditorDrain
{
    [StructLayout(LayoutKind.Sequential)]
    struct SA { public int nLength; public IntPtr lpSecurityDescriptor; public bool bInheritHandle; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SI {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PI { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CreatePipe(out IntPtr r, out IntPtr w, ref SA sa, int size);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref SI si, out PI pi);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool PeekNamedPipe(IntPtr h, IntPtr buf, int size, IntPtr read, out uint avail, IntPtr left);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadFile(IntPtr h, byte[] buf, int n, out uint read, IntPtr ov);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    public static byte[] Run(string exe, string args, int timeoutMs, out int exitCode)
    {
        var sa = new SA { nLength = Marshal.SizeOf(typeof(SA)), bInheritHandle = true };
        IntPtr rp, wp;
        if (!CreatePipe(out rp, out wp, ref sa, 0)) throw new Exception("CreatePipe");
        var si = new SI(); si.cb = Marshal.SizeOf(typeof(SI)); si.dwFlags = 0x101; si.wShowWindow = 0;
        si.hStdOutput = wp; si.hStdError = wp; si.hStdInput = GetStdHandle(-10);
        PI pi;
        if (!CreateProcessW(null, new StringBuilder("\"" + exe + "\" " + args), IntPtr.Zero, IntPtr.Zero, true, 0x08000000, IntPtr.Zero, null, ref si, out pi))
            throw new Exception("CreateProcess " + Marshal.GetLastWin32Error());
        CloseHandle(wp);
        var ms = new System.IO.MemoryStream(); var buf = new byte[4096]; uint avail, read;
        long deadline = Environment.TickCount64 + timeoutMs;
        while (true) {
            if (PeekNamedPipe(rp, IntPtr.Zero, 0, IntPtr.Zero, out avail, IntPtr.Zero) && avail > 0) {
                if (!ReadFile(rp, buf, buf.Length, out read, IntPtr.Zero) || read == 0) break;
                ms.Write(buf, 0, (int)read); continue;
            }
            if (WaitForSingleObject(pi.hProcess, 40) == 0) {
                while (PeekNamedPipe(rp, IntPtr.Zero, 0, IntPtr.Zero, out avail, IntPtr.Zero) && avail > 0) {
                    if (!ReadFile(rp, buf, buf.Length, out read, IntPtr.Zero) || read == 0) break;
                    ms.Write(buf, 0, (int)read);
                }
                break;
            }
            if (Environment.TickCount64 >= deadline) { TerminateProcess(pi.hProcess, 0xFFFFFFFF); WaitForSingleObject(pi.hProcess, 2000); break; }
        }
        uint code; GetExitCodeProcess(pi.hProcess, out code); exitCode = (int)code;
        CloseHandle(pi.hProcess); CloseHandle(pi.hThread); CloseHandle(rp);
        return ms.ToArray();
    }
}
'@
}
function Drain([string]$E, [string]$ArgLine, [int]$TimeoutS = 900) {
  $ec = 0
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $b = [T2iEditorDrain]::Run($E, $ArgLine, $TimeoutS * 1000, [ref]$ec)
  $sw.Stop()
  return [pscustomobject]@{ Code = $ec; Bytes = $b; Secs = $sw.Elapsed.TotalSeconds }
}

# ---- fixture: a small tree, indexed, then made STALE --------------------------
$fx = P 'fx'
New-Item -ItemType Directory $fx | Out-Null
Write-Ascii (Join-Path $fx 'OutFix.pas') @'
unit OutFix;

interface

uses
  Classes;

type
  TLeafObj = class(TPersistent)
  private
    FV: Integer;
    FS: string;
  published
    property V: Integer read FV write FV default 3;
    property S: string read FS write FS;
  end;

  TMidObj = class(TPersistent)
  private
    FLeaf: TLeafObj;
    FW: Integer;
  public
    property PubW: Integer read FW write FW;
  published
    property Leaf: TLeafObj read FLeaf write FLeaf;
    property W: Integer read FW write FW;
  end;

  TSrcComp = class(TComponent)
  private
    FMid: TMidObj;
    FCaption: string;
  public
    PubField: Integer;
  published
    property Mid: TMidObj read FMid write FMid;
    property Caption: string read FCaption write FCaption;
  end;

  TDstComp = class(TComponent)
  private
    FMid: TMidObj;
    FCaption: string;
    FExtra: Integer;
  published
    property Mid: TMidObj read FMid write FMid;
    property Caption: string read FCaption write FCaption;
    property Extra: Integer read FExtra write FExtra;
  end;

implementation

end.
'@
$db = P 'fx.sqlite'
$null = & $Exe index $fx --db $db 2>&1
Check 'fixture: index built' (Test-Path $db) "db=$db"
# Make it stale: the freshness note goes to STDERR on every open from now on.
[System.IO.File]::AppendAllText((Join-Path $fx 'OutFix.pas'), "// touched after indexing`r`n")
(Get-Item (Join-Path $fx 'OutFix.pas')).LastWriteTime = (Get-Date).AddMinutes(10)

# ---- m: merged stream == stderr ++ stdout ------------------------------------
Write-Host ''
Write-Host 'm: merged stream (cmd 2>&1) -- every stderr byte before the document' -ForegroundColor Cyan
$cases = @(
  @{ Tag = 'm-json'; A = @('proptree', '--qname', 'OutFix.TSrcComp', '--json', '--no-write-back', '--db', $db); Json = $true },
  @{ Tag = 'm-text'; A = @('proptree', '--qname', 'OutFix.TSrcComp', '--no-write-back', '--db', $db); Json = $false },
  @{ Tag = 'm-scaf'; A = @('convert-scaffold', '--from', 'OutFix.TSrcComp', '--to', 'OutFix.TDstComp', '--db', $db); Json = $false }
)
foreach ($c in $cases) {
  $sep = RunRaw $Exe $c.A
  $argLine = ($c.A | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
  $mrg = RunMergedCmd $Exe $argLine $c.Tag
  $errTxt = Ascii $sep.Err
  Check "$($c.Tag): separate run exits 0 with a stderr note (the stale index)" `
    (($sep.Code -eq 0) -and ($errTxt -match 'changed since this index was built')) "exit=$($sep.Code) stderr=$($errTxt.Trim())"
  $want = Concat $sep.Err $sep.Out
  $tail = ((Ascii $mrg).TrimEnd() -split "`n" | Select-Object -Last 1)
  Check "$($c.Tag): merged bytes == stderr bytes ++ stdout bytes" (SameBytes $mrg $want) `
    ("merged={0} B, stderr+stdout={1} B; merged last line: [{2}]" -f $mrg.Length, $want.Length, $tail)
  if ($c.Json) {
    $tm = SliceJson (Ascii $mrg); $ts = SliceJson (Ascii $sep.Out)
    $nm = if ($tm) { @($tm.properties).Count } else { -1 }
    $ns = if ($ts) { @($ts.properties).Count } else { -2 }
    Check "$($c.Tag): first-'{'..last-'}' slice parses with the full node count" (($nm -eq $ns) -and ($ns -gt 0)) "merged=$nm separate=$ns"
  }
}

# ---- p: --progress-interval with no value ------------------------------------
Write-Host ''
Write-Host 'p: --progress-interval as the last argument -> exit 2' -ForegroundColor Cyan
foreach ($pa in @(@('proptree', '--qname', 'OutFix.TSrcComp', '--db', $db, '--progress-interval'),
                  @('convert-scaffold', '--from', 'OutFix.TSrcComp', '--to', 'OutFix.TDstComp', '--db', $db, '--progress-interval'))) {
  $r = RunRaw $Exe $pa
  $txt = (Ascii $r.Out) + (Ascii $r.Err)
  Check "$($pa[0]) ... --progress-interval (no value): exit 2 naming the flag" `
    (($r.Code -eq 2) -and ($txt -match '--progress-interval')) "exit=$($r.Code) out=$($txt.Trim())"
}

# ---- h: --help wording -----------------------------------------------------------
Write-Host ''
Write-Host 'h: --help says whole seconds' -ForegroundColor Cyan
$help = Ascii (RunRaw $Exe @('--help')).Out
Check '--help: "--progress-interval S (whole seconds"' ($help -match '--progress-interval S \(whole seconds') ''
Check '--help: no "decimal seconds"' (-not ($help -match 'decimal seconds')) ''

# ---- e: the other JSON verbs the editor runs merged (fix round 1, ruling R18) --
#     The work dir carries a .drag-lint.json, so every run from it writes the
#     "(loaded defaults ...)" banner to stderr -- the note the editor actually
#     sees. RED on ed5cdd4c: that banner sat in ErrOutput's buffer and landed
#     AFTER the document on all six verbs.
Write-Host ''
Write-Host 'e: merged stream on convert-apply / convert-reemit / info / query / outline / sql (R18)' -ForegroundColor Cyan
$ex = P 'ex'
New-Item -ItemType Directory $ex | Out-Null
Write-Ascii (Join-Path $ex 'EdFix.pas') @'
unit EdFix;

interface

uses
  Classes, OldUnit;

type
  TSrcComp = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TDstComp = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $ex 'u.rules') "#useswap OldUnit -> NewUnit`n"
Write-Ascii (Join-Path $ex 'r.rules') "#convert EdFix.TSrcComp -> EdFix.TDstComp`n#link Caption <- Caption`n"
Write-Ascii (Join-Path $ex 'blk.txt') "object S1: TSrcComp`n  Caption = 'x'`nend`n"
Write-Ascii (Join-Path $ex '.drag-lint.json') '{}'
$exDb = Join-Path $ex 'ex.sqlite'
$null = & $Exe index $ex --db $exDb 2>&1
# convert-apply --apply edits the unit: it runs on its own indexed copy, one per engine run.
function ApplyCopy([string]$Tag) {
  $dir = Join-Path $ex $Tag
  New-Item -ItemType Directory $dir -Force | Out-Null
  Copy-Item (Join-Path $ex 'EdFix.pas') $dir -Force
  $null = & $Exe index $dir --db (Join-Path $dir 'c.sqlite') 2>&1
  return (Join-Path $dir 'EdFix.pas')
}
function RunRawIn([string]$Cwd, [string]$E, [string[]]$A) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new($E)
  foreach ($x in $A) { $psi.ArgumentList.Add($x) }
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $Cwd
  $p = [System.Diagnostics.Process]::Start($psi)
  $ms = [System.IO.MemoryStream]::new(); $es = [System.IO.MemoryStream]::new()
  $t = $p.StandardError.BaseStream.CopyToAsync($es)
  $p.StandardOutput.BaseStream.CopyTo($ms); $t.Wait(); $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $ms.ToArray(); Err = $es.ToArray() }
}
function RunMergedIn([string]$Cwd, [string]$E, [string[]]$A) {
  $line = ($A | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
  $psi = [System.Diagnostics.ProcessStartInfo]::new("$env:ComSpec")
  $psi.Arguments = '/s /c ""' + $E + '" ' + $line + ' 2>&1"'
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.WorkingDirectory = $Cwd
  $p = [System.Diagnostics.Process]::Start($psi)
  $ms = [System.IO.MemoryStream]::new()
  $p.StandardOutput.BaseStream.CopyTo($ms); $p.WaitForExit()
  return ,$ms.ToArray()
}
function SliceBy([string]$S, [char]$Open, [char]$Close) {
  $a = $S.IndexOf($Open); $b = $S.LastIndexOf($Close)
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return (ConvertFrom-Json -InputObject $S.Substring($a, $b - $a + 1) -NoEnumerate) } catch { return $null }
}
$edCases = @(
  @{ N = 'convert-apply (dry run)'; Open = '{'; Close = '}'; A = { param($t) @('convert-apply', '--unit', (Join-Path $ex 'EdFix.pas'), '--rules', (Join-Path $ex 'u.rules'), '--db', $exDb, '--format', 'json') };
     Ok = { param($j) $j.schema -eq 'apply/1' -and $j.mode -eq 'dry-run' -and $j.ok -eq $true -and $j.uses_removed -eq 1 } },
  @{ N = 'convert-apply --apply'; Open = '{'; Close = '}'; A = { param($t) $u = ApplyCopy $t; @('convert-apply', '--unit', $u, '--rules', (Join-Path $ex 'u.rules'), '--db', (Join-Path (Split-Path $u) 'c.sqlite'), '--apply', '--no-backup', '--format', 'json') };
     Ok = { param($j) $j.schema -eq 'apply/1' -and $j.mode -ne 'dry-run' -and $null -ne $j.ok -and $null -ne $j.uses } },
  @{ N = 'convert-reemit'; Open = '{'; Close = '}'; A = { param($t) @('convert-reemit', '--from-block', (Join-Path $ex 'blk.txt'), '--rules', (Join-Path $ex 'r.rules'), '--from', 'EdFix.TSrcComp', '--to', 'EdFix.TDstComp', '--db', $exDb) };
     Ok = { param($j) $null -ne $j.report -and $null -ne $j.unreachable } },
  @{ N = 'info --json'; Open = '{'; Close = '}'; A = { param($t) @('info', '--json') };
     Ok = { param($j) $j.schema -eq 'info/1' -and $j.capabilities.progress_lines -eq $true } },
  @{ N = 'query --name --json'; Open = '['; Close = ']'; A = { param($t) @('query', '--name', 'TSrcComp', '--json', '--db', $exDb) };
     Ok = { param($j) @($j | Where-Object { $_.name -eq 'TSrcComp' }).Count -ge 1 } },
  @{ N = 'outline --format json'; Open = '['; Close = ']'; A = { param($t) @('outline', '--file', (Join-Path $ex 'EdFix.pas'), '--format', 'json', '--db', $exDb) };
     Ok = { param($j) @($j | Where-Object { $_.kind -eq 'class' }).Count -eq 2 } },
  @{ N = 'sql --json'; Open = '{'; Close = '}'; A = { param($t) @('sql', '--query', 'SELECT 1 AS n', '--db', $exDb, '--json') };
     Ok = { param($j) $null -ne $j.columns -and $null -ne $j.rows } }
)
$ci = 0
foreach ($c in $edCases) {
  $ci++
  $sep = RunRawIn $ex $Exe (& $c.A "s$ci")
  $mrg = RunMergedIn $ex $Exe (& $c.A "m$ci")
  $errTxt = Ascii $sep.Err
  Check "e $($c.N): separate run exits 0 and writes the banner to stderr" `
    (($sep.Code -eq 0) -and ($errTxt -match 'loaded defaults')) "exit=$($sep.Code) stderr=$($errTxt.Trim())"
  $tail = ((Ascii $mrg).TrimEnd() -split "`n" | Select-Object -Last 1)
  # The --apply case runs on per-run copies (s<i> / m<i>): the copy's directory
  # name is the only byte allowed to differ.
  $mt = (Ascii $mrg).Replace("\\m$ci\\", '\\RUN\\')
  $ct = (Ascii (Concat $sep.Err $sep.Out)).Replace("\\s$ci\\", '\\RUN\\')
  Check "e $($c.N): merged bytes == stderr bytes ++ stdout bytes" ($mt -ceq $ct) `
    ("merged={0} B, stderr+stdout={1} B; merged last line: [{2}]" -f $mrg.Length, ($sep.Err.Length + $sep.Out.Length), $tail)
  $j = SliceBy (Ascii $mrg) $c.Open $c.Close
  Check "e $($c.N): the '$($c.Open)'..'$($c.Close)' slice of the merged output parses with the expected keys" `
    (($null -ne $j) -and (& $c.Ok $j)) ''
  if ($OldExe) {
    $o = RunRawIn $ex $OldExe (& $c.A "o$ci")
    $n = RunRawIn $ex $Exe (& $c.A "n$ci")
    $os = Ascii $o.Out; $ns = Ascii $n.Out
    if ($c.N -like 'info*') {
      # info names its own exe, DLLs and build time: mask exactly those values.
      $mask = '"(exe_path|build_date|dll_delphi13|dll_dfm)":"(\\.|[^"\\])*"'
      $os = $os -replace $mask, '"$1":"*"'; $ns = $ns -replace $mask, '"$1":"*"'
    }
    if ($c.N -like 'convert-apply --apply*') {
      # the unit path differs per copy: compare with each run's own path removed.
      $os = $os.Replace((Join-Path $ex "o$ci").Replace('\', '\\'), '<dir>'); $ns = $ns.Replace((Join-Path $ex "n$ci").Replace('\', '\\'), '<dir>')
    }
    Check "e $($c.N): stdout identical to the old engine (exit $($n.Code) vs $($o.Code))" (($os -eq $ns) -and ($o.Code -eq $n.Code)) "old=$($o.Out.Length) B new=$($n.Out.Length) B"
  }
}

# ---- k: stdout is a CONSOLE -- written in <= 32 KiB pieces (fix round 1 minor) --
#     A hidden window still gets its own console, so stdout is a FILE_TYPE_CHAR
#     handle. A failed console WriteFile would surface as an I/O exception (exit
#     3); exit 0 is the check. Positive control only: a 1 MiB console write does
#     not fail on this Windows build, so this cannot go RED here.
Write-Host ''
Write-Host 'k: stdout on a console' -ForegroundColor Cyan
$kArgs = if ($LibDb) { @('proptree', '--qname', 'Bde.DBTables.TQuery', '--depth', '3', '--refs-as-leaves', '--no-write-back', '--json', '--db', $LibDb) }
         else { @('proptree', '--qname', 'OutFix.TSrcComp', '--json', '--no-write-back', '--db', $db) }
$pk = Start-Process -FilePath $Exe -ArgumentList $kArgs -WindowStyle Hidden -PassThru
$finK = $pk.WaitForExit(300000)
if (-not $finK) { try { $pk.Kill() } catch {} }
Check ("k: proptree --json to a console exits 0 ({0})" -f $(if ($LibDb) { 'TQuery depth 3, ~180 KB' } else { 'fixture' })) ($finK -and $pk.ExitCode -eq 0) "exit=$(if ($finK) { $pk.ExitCode } else { 'TIMEOUT' })"

# ---- a: differential shim over the existing runners ---------------------------
if ($OldExe) {
  Write-Host ''
  Write-Host 'a: byte-identity, every proptree / convert-scaffold call of the existing runners' -ForegroundColor Cyan
  $shimPs = P 'shim.ps1'; $shimCmd = P 'shim.cmd'; $shimLog = P 'shim.tsv'
  Write-Ascii $shimPs @'
$new = $env:DLT2I_NEW; $old = $env:DLT2I_OLD; $log = $env:DLT2I_LOG
$a = @($args | ForEach-Object { [string]$_ })
function RunRaw([string]$E, [string[]]$A) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new($E)
  foreach ($x in $A) { $psi.ArgumentList.Add($x) }
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $ms = [System.IO.MemoryStream]::new(); $es = [System.IO.MemoryStream]::new()
  $t = $p.StandardError.BaseStream.CopyToAsync($es)
  $p.StandardOutput.BaseStream.CopyTo($ms); $t.Wait(); $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $ms.ToArray(); Err = $es.ToArray() }
}
function Sha([byte[]]$B) { $h = [System.Security.Cryptography.SHA256]::Create(); try { [BitConverter]::ToString($h.ComputeHash($B)) -replace '-', '' } finally { $h.Dispose() } }
$verb = if ($a.Count -gt 0) { $a[0] } else { '' }
$variants = [System.Collections.Generic.List[object]]::new()
if ($verb -eq 'proptree' -or $verb -eq 'convert-scaffold') {
  $variants.Add(@{ Name = 'as-called'; A = $a })
  if ($verb -eq 'proptree') {
    $base = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $a.Count; $i++) {
      if ($a[$i] -eq '--json') { continue }
      if (($a[$i] -eq '--format' -or $a[$i] -eq '--min-visibility') -and $i + 1 -lt $a.Count) { $i++; continue }
      $base.Add($a[$i])
    }
    $seen = @{ (($a) -join "`u{1}") = 1 }
    foreach ($fmt in 'json', 'text') {
      foreach ($mv in '', 'public', 'published') {
        $v = [System.Collections.Generic.List[string]]::new($base)
        $v.Add('--format'); $v.Add($fmt)
        if ($mv) { $v.Add('--min-visibility'); $v.Add($mv) }
        $k = ($v -join "`u{1}")
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = 1
        $variants.Add(@{ Name = "$fmt/$(if ($mv) { $mv } else { 'all' })"; A = $v.ToArray() })
      }
    }
  }
}
$answer = $null
foreach ($v in $variants) {
  $o = RunRaw $old $v.A
  $n = RunRaw $new $v.A
  $line = @($verb, $v.Name, ((Sha $o.Out) -eq (Sha $n.Out)), ($o.Code -eq $n.Code), $n.Out.Length, $n.Code, ($v.A -join ' ')) -join "`t"
  [System.IO.File]::AppendAllText($log, $line + "`r`n")
  if ($null -eq $answer) { $answer = $n }
}
if ($null -eq $answer) { $answer = RunRaw $new $a }
$so = [Console]::OpenStandardOutput(); $so.Write($answer.Out, 0, $answer.Out.Length); $so.Flush()
$se = [Console]::OpenStandardError(); $se.Write($answer.Err, 0, $answer.Err.Length); $se.Flush()
exit $answer.Code
'@
  Write-Ascii $shimCmd "@pwsh -NoProfile -File `"$shimPs`" %*`r`n"
  $env:DLT2I_NEW = $Exe; $env:DLT2I_OLD = $OldExe; $env:DLT2I_LOG = $shimLog
  $runners = @(Get-ChildItem $PSScriptRoot -Filter 'run_proptree*.ps1') + @(Get-ChildItem $PSScriptRoot -Filter 'run_convert_scaffold*.ps1') |
    Where-Object { $_.Name -ne 'run_proptree_output_speed.ps1' } | Sort-Object Name
  foreach ($rn in $runners) {
    $before = if (Test-Path $shimLog) { @(Get-Content $shimLog).Count } else { 0 }
    $rw = P ("w-" + $rn.BaseName)
    $null = & pwsh -NoProfile -File $rn.FullName -Exe $shimCmd -WorkDir $rw *>&1
    $rc = $LASTEXITCODE
    $after = if (Test-Path $shimLog) { @(Get-Content $shimLog).Count } else { 0 }
    Write-Host ("      {0}: {1} compared case(s), runner exit {2} (informational)" -f $rn.Name, ($after - $before), $rc) -ForegroundColor DarkGray
  }
  Remove-Item Env:\DLT2I_NEW, Env:\DLT2I_OLD, Env:\DLT2I_LOG -ErrorAction SilentlyContinue
  $rows = if (Test-Path $shimLog) { @(Get-Content $shimLog | ForEach-Object { , ($_ -split "`t") }) } else { @() }
  $okRows = @($rows | Where-Object { $_[2] -eq 'True' -and $_[3] -eq 'True' })
  $bad = @($rows | Where-Object { -not ($_[2] -eq 'True' -and $_[3] -eq 'True') })
  $pt = @($rows | Where-Object { $_[0] -eq 'proptree' }).Count
  $sc = @($rows | Where-Object { $_[0] -eq 'convert-scaffold' }).Count
  Check ("a: compared cases > 0 (proptree {0}, convert-scaffold {1})" -f $pt, $sc) ($rows.Count -gt 0) "log=$shimLog"
  Check ("a: SHA256(stdout) and exit code equal, old vs new: {0} of {1}" -f $okRows.Count, $rows.Count) ($bad.Count -eq 0) `
    (($bad | Select-Object -First 5 | ForEach-Object { $_ -join ' | ' }) -join ' || ')
}

# ---- r: byte-identity on the real library --------------------------------------
if ($OldExe -and $LibDb) {
  Write-Host ''
  Write-Host 'r: byte-identity, TQuery / TFDQuery at depth 3 and 4 (scratch library)' -ForegroundColor Cyan
  $real = [System.Collections.Generic.List[object]]::new()
  foreach ($q in 'Bde.DBTables.TQuery', 'FireDAC.Comp.Client.TFDQuery') {
    foreach ($d in 3, 4) {
      foreach ($fmt in 'json', 'text') {
        $real.Add(@('proptree', '--qname', $q, '--depth', "$d", '--refs-as-leaves', '--no-write-back', '--format', $fmt, '--db', $LibDb))
        if ($d -eq 3) {
          foreach ($mv in 'public', 'published') {
            $real.Add(@('proptree', '--qname', $q, '--depth', "$d", '--refs-as-leaves', '--no-write-back', '--format', $fmt, '--min-visibility', $mv, '--db', $LibDb))
          }
        }
      }
    }
  }
  $same = 0
  foreach ($ra in $real) {
    $o = RunRaw $OldExe $ra; $n = RunRaw $Exe $ra
    $eq = ((Sha $o.Out) -eq (Sha $n.Out)) -and ($o.Code -eq $n.Code) -and ($n.Code -eq 0)
    if ($eq) { $same++ }
    Write-Host ("      {0} {1} B  {2}" -f $(if ($eq) { 'same' } else { 'DIFF' }), $n.Out.Length, ($ra[2..($ra.Count - 3)] -join ' ')) -ForegroundColor DarkGray
  }
  Check ("r: SHA256 equal, old vs new: {0} of {1}" -f $same, $real.Count) ($same -eq $real.Count) ''
}

# ---- b / l / c: the real library, depth 5 ----------------------------------------
if ($LibDb) {
  Write-Host ''
  Write-Host "b: speed, TFDQuery --depth 5 through the editor's pipe drain (best of 2, < $LimitS s)" -ForegroundColor Cyan
  $d5 = "proptree --qname FireDAC.Comp.Client.TFDQuery --depth 5 --refs-as-leaves --no-write-back --db `"$LibDb`""
  foreach ($mode in @(@{ N = 'json'; A = "$d5 --json" }, @{ N = 'text'; A = $d5 })) {
    $best = [double]::MaxValue; $codes = @()
    foreach ($i in 1, 2) {
      $r = Drain $Exe $mode.A
      $codes += $r.Code
      Write-Host ("      {0} run {1}: {2:n1} s, exit {3}, {4} B" -f $mode.N, $i, $r.Secs, $r.Code, $r.Bytes.Length) -ForegroundColor DarkGray
      if ($r.Code -eq 0 -and $r.Secs -lt $best) { $best = $r.Secs }
    }
    Check ("b: {0} depth 5 best of 2 = {1:n1} s < {2} s" -f $mode.N, $best, $LimitS) ($best -lt $LimitS) "exit codes: $($codes -join ',')"
  }

  Write-Host ''
  Write-Host 'l: merged stream on the real library (TFDQuery --depth 4 --json, editor drain)' -ForegroundColor Cyan
  $l4 = @('proptree', '--qname', 'FireDAC.Comp.Client.TFDQuery', '--depth', '4', '--refs-as-leaves', '--no-write-back', '--json', '--db', $LibDb)
  $sep = RunRaw $Exe $l4
  $mrg = Drain $Exe "proptree --qname FireDAC.Comp.Client.TFDQuery --depth 4 --refs-as-leaves --no-write-back --json --db `"$LibDb`""
  $errTxt = Ascii $sep.Err
  Check 'l: the separate run writes a stderr note (resolver / freshness)' ($errTxt -match 'resolver:|note:') "stderr=$($errTxt.Trim())"
  Check 'l: merged bytes == stderr bytes ++ stdout bytes' (SameBytes $mrg.Bytes (Concat $sep.Err $sep.Out)) `
    ("merged={0} B, stderr+stdout={1} B" -f $mrg.Bytes.Length, ($sep.Err.Length + $sep.Out.Length))
  $tm = SliceJson (Ascii $mrg.Bytes); $ts = SliceJson (Ascii $sep.Out)
  $nm = if ($tm) { @($tm.properties).Count } else { -1 }
  $ns = if ($ts) { @($ts.properties).Count } else { -2 }
  Check "l: slice parses with the full node count ($ns)" (($nm -eq $ns) -and ($ns -gt 0)) "merged=$nm separate=$ns"

  if ($OldD5Json -or $OldExe) {
    Write-Host ''
    Write-Host 'c: TFDQuery --depth 5 --json, old vs new, SHA256' -ForegroundColor Cyan
    $c5 = @('proptree', '--qname', 'FireDAC.Comp.Client.TFDQuery', '--depth', '5', '--refs-as-leaves', '--no-write-back', '--json', '--db', $LibDb)
    $oldSha = if ($OldD5Json) { (Get-FileHash $OldD5Json -Algorithm SHA256).Hash } else { Sha (RunRaw $OldExe $c5).Out }
    $n = RunRaw $Exe $c5
    $newSha = Sha $n.Out
    $tn = SliceJson (Ascii $n.Out)
    Check ("c: SHA256 equal (new {0} B, {1} nodes)" -f $n.Out.Length, $(if ($tn) { @($tn.properties).Count } else { '?' })) ($oldSha -eq $newSha) "old=$oldSha new=$newSha"
  }
} else {
  Write-Host ''
  Write-Host 'b / l / c / r: skipped (no -LibDb)' -ForegroundColor DarkYellow
}
if (-not $OldExe) { Write-Host 'a / r / c: skipped (no -OldExe)' -ForegroundColor DarkYellow }

Write-Host ''
Write-Host ("{0} PASS / {1} FAIL" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Failed) { 'Red' } else { 'Green' })
} finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
if ($script:Failed) { exit 1 } else { exit 0 }
