# watch-lsp-launch.ps1
# The 64-bit-server failure produces NO error text -- Code Insight simply hangs forever.
# With no message to read, the decisive question is: does the IDE launch a server at all,
# and if so, WHICH ONE?
#
# Run this, THEN start the IDE with CodeInsightUse64BitBinary=True.
# It records every DelphiLSP.exe that appears, with path, bitness and parent.
#
# Usage: powershell -ExecutionPolicy Bypass -File watch-lsp-launch.ps1 [-Minutes 5]

param([int]$Minutes = 5)

$ErrorActionPreference = 'Continue'
$log = Join-Path $PSScriptRoot ("launch-watch-{0}.log" -f (Get-Date).ToString('yyyyMMdd-HHmmss'))

function Get-PEBitness([string]$p) {
    try {
        $fs = [IO.File]::OpenRead($p); $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C; $pe = $br.ReadInt32(); $fs.Position = $pe + 4
        $m = $br.ReadUInt16(); $br.Close()
        switch ($m) { 0x14c { 'x86' } 0x8664 { 'x64' } default { "0x{0:X}" -f $m } }
    } catch { '?' }
}

function Emit($msg) { $line = "{0}  {1}" -f (Get-Date).ToString('HH:mm:ss.fff'), $msg; $line; Add-Content -Path $log -Value $line }

Emit "watching for DelphiLSP.exe launches for $Minutes minute(s)"
Emit "START THE IDE NOW (with the 64-bit Code Insight box checked)"
Emit ""

$seen = @{}
$deadline = (Get-Date).AddMinutes($Minutes)
$sawAny = $false

while ((Get-Date) -lt $deadline) {
    $procs = Get-CimInstance Win32_Process -Filter "Name='DelphiLSP.exe' OR Name='bds.exe'" -ErrorAction SilentlyContinue
    foreach ($pr in $procs) {
        if ($seen.ContainsKey($pr.ProcessId)) { continue }
        $seen[$pr.ProcessId] = $true
        $exe = $pr.ExecutablePath
        $bits = if ($exe -and (Test-Path $exe)) { Get-PEBitness $exe } else { '?' }
        $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$($pr.ParentProcessId)" -ErrorAction SilentlyContinue).Name
        Emit ("NEW  {0,-14} pid={1,-7} {2,-4} parent={3}" -f $pr.Name, $pr.ProcessId, $bits, $parent)
        Emit ("     path: {0}" -f $exe)
        Emit ("     cmd : {0}" -f $pr.CommandLine)
        if ($pr.Name -eq 'DelphiLSP.exe') { $sawAny = $true }
    }
    Start-Sleep -Milliseconds 400
}

Emit ""
Emit "=========================== VERDICT ==========================="
if (-not $sawAny) {
    Emit "NO DelphiLSP.exe was ever launched."
    Emit "  -> The 32-bit IDE fails to START the 64-bit server (path resolution),"
    Emit "     then waits forever for a handshake from a process that does not exist."
    Emit "     This is the 'silent hang' explained. A shim named bin\DelphiLSP.exe"
    Emit "     -- which the IDE CAN always find -- fixes it outright."
} else {
    $paths = $seen.Keys | ForEach-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$_" -ErrorAction SilentlyContinue).ExecutablePath } | Where-Object { $_ -match 'DelphiLSP' } | Select-Object -Unique
    Emit "DelphiLSP.exe DID launch, from:"
    $paths | ForEach-Object { Emit "     $_" }
    Emit "  -> The server starts but the IDE still hangs => handshake/pipe problem,"
    Emit "     not path resolution. Capture the LSP log next (arm-lsp-diagnostic.ps1)."
}
Emit "log written: $log"
