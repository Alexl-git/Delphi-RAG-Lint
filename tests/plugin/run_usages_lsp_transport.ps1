<#
  run_usages_lsp_transport.ps1 -- O-USAGESFORM: Find Usages asks the running server.

  1. Builds and runs UsagesQueryTests.dpr over the pure reader, feeding it an envelope a REAL engine
     sent over a real `lsp` session on a fixture index.
  2. Parity: every bucket of that reply has the row count `usages --json` gives for the same name;
     a server that answered differently would make the IDE form disagree with the CLI.
  3. Source anchors: the form asks the server first, falls back to the CLI on a timeout notice or an
     unreadable reply, cancels on supersede and on close, never spawns a server for itself.
  4. Positive control: the parity comparer fails on a doctored reply.
  The form itself runs only in a live IDE: live proof owed.

  RED BASELINE, measured 2026-11-06: the source anchors fail on the pre-fix form, which only spawned.

  Usage: pwsh -File tests\plugin\run_usages_lsp_transport.ps1 [-Exe <engine>]
#>
[CmdletBinding()]
param(
  [string]$Exe    = $(& "$PSScriptRoot\..\autotest\lib\DefaultEngineExe.ps1"),
  [string]$SrcDir = "$PSScriptRoot\..\..\src\delphi-plugin"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$work = Join-Path $env:TEMP "drag-lint-usages-lsp-$PID"
[void][IO.Directory]::CreateDirectory($work)
$lsp = $null
try {
  # ---- fixture index
  $src = Join-Path $work 'src'
  [void][IO.Directory]::CreateDirectory($src)
  $pas = @('unit UQ;','interface','type','  TUq = class','    FValue: Integer;','    procedure Touch;','  end;','implementation','procedure TUq.Touch;','begin','  FValue:= FValue + 1;','end;','end.') -join "`r`n"
  [IO.File]::WriteAllText((Join-Path $src 'UQ.pas'), $pas, [Text.Encoding]::ASCII)
  $db = Join-Path $work 'uq.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $name = 'FValue'
  $cli = (& $exePath usages --name $name --db $db --json 2>$null) -join "`n" | ConvertFrom-Json

  # ---- one real LSP session
  $psi = [Diagnostics.ProcessStartInfo]::new($exePath, "lsp --db `"$db`"")
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $lsp = [Diagnostics.Process]::Start($psi)
  $lsp.BeginErrorReadLine()
  $stream = $lsp.StandardOutput.BaseStream
  function Send-Rpc($obj) {
    $b = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 8))
    $h = [Text.Encoding]::ASCII.GetBytes("Content-Length: $($b.Length)`r`n`r`n")
    $lsp.StandardInput.BaseStream.Write($h, 0, $h.Length)
    $lsp.StandardInput.BaseStream.Write($b, 0, $b.Length)
    $lsp.StandardInput.BaseStream.Flush()
  }
  function Read-Reply([int]$id, [int]$ms) {
    # Bounded: a silent engine fails this guard instead of hanging it (the finally kills it).
    $deadline = [DateTime]::UtcNow.AddMilliseconds($ms)
    $one = New-Object byte[] 1
    function ReadBytes([byte[]]$buf, [int]$len) {
      $o = 0
      while ($o -lt $len) {
        $left = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($left -le 0) { return $false }
        $t = $stream.ReadAsync($buf, $o, $len - $o)
        if (-not $t.Wait($left)) { return $false }
        if ($t.Result -le 0) { return $false }
        $o += $t.Result
      }
      return $true
    }
    while ($true) {
      $head = New-Object Text.StringBuilder
      while (-not $head.ToString().EndsWith("`r`n`r`n")) {
        if (-not (ReadBytes $one 1)) { return '' }
        [void]$head.Append([char]$one[0])
      }
      $len = [int]([regex]::Match($head.ToString(), 'Content-Length:\s*(\d+)').Groups[1].Value)
      $buf = New-Object byte[] $len
      if (-not (ReadBytes $buf $len)) { return '' }
      $t = [Text.Encoding]::UTF8.GetString($buf)
      if ($t -match "`"id`"\s*:\s*$id\b") { return $t }
    }
  }
  Send-Rpc @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ capabilities = @{} } }
  $init = Read-Reply 1 30000
  Check 'the engine answers initialize' ($init -ne '')
  Send-Rpc @{ jsonrpc = '2.0'; id = 2; method = 'draglint/usages'; params = @{ name = $name; width = 'narrow' } }
  $reply = Read-Reply 2 30000
  Check 'the engine answers draglint/usages' ($reply -ne '')
  $replyFile = Join-Path $work 'reply.json'
  [IO.File]::WriteAllText($replyFile, $reply, [Text.UTF8Encoding]::new($false))

  # ---- parity
  $buckets = 'declarations','reads','writes','calls','types','attributes','events','raises','handles'
  function Parity($a, $b) {
    $bad = @()
    foreach ($k in $buckets) { if (@($a.$k).Count -ne @($b.$k).Count) { $bad += "$k=$(@($a.$k).Count)/$(@($b.$k).Count)" } }
    return ,$bad
  }
  $res = ($reply | ConvertFrom-Json).result
  $diff = Parity $res $cli
  Check 'parity: each bucket has the row count `usages --json` gives' ($diff.Count -eq 0) ($diff -join ' ')
  Check 'the fixture is not vacuous: FValue has a declaration, a read and a write' ((@($cli.declarations).Count -gt 0) -and (@($cli.reads).Count -gt 0) -and (@($cli.writes).Count -gt 0))
  $doctored = $reply | ConvertFrom-Json
  $doctored.result.reads = @()
  Check 'positive control: the comparer sees a doctored reply' ((Parity $doctored.result $cli).Count -gt 0)

  # ---- the pure reader, including the real envelope
  $dpr = (Resolve-Path "$PSScriptRoot\..\UsagesQueryTests.dpr").Path
  $dcu = Join-Path $work 'dcu'; [void][IO.Directory]::CreateDirectory($dcu)
  $bat = Join-Path $work 'build.bat'
  $lines = '@echo off', 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"', ('cd /d "{0}"' -f (Split-Path $dpr)), ('dcc64 -B -E"{0}" -N0"{1}" UsagesQueryTests.dpr' -f $work, $dcu), 'echo BUILD_EXITCODE=%ERRORLEVEL%'
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $log = Join-Path $work 'build.log'
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait
  Check 'UsagesQueryTests compiles' ((Get-Content $log -Raw) -match 'BUILD_EXITCODE=0')
  $out = & (Join-Path $work 'UsagesQueryTests.exe') --reply $replyFile $name 2>&1 | Out-String
  Write-Host $out.TrimEnd()
  Check 'the pure reader passes, real envelope included' (($LASTEXITCODE -eq 0) -and ($out -match '\d+ passed, 0 failed'))

  # ---- the form
  $form = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.UsagesForm.pas'))
  Check 'the form asks the server before it spawns' ($form -match "(?s)if TryLspQuery then Exit;\s+RunCliQuery;")
  Check 'it asks for draglint/usages' ($form -match "RequestAsync\('draglint/usages'")
  Check 'a late notice or an unreadable reply falls back to the CLI' ($form -match '(?s)LspAnswered.*?\(AStatus = lrsResult\) and UsagesFromReply\(AReply, Json\).*?RunCliQuery')
  Check 'a supersede cancels the request' ($form -match '(?s)procedure TDragLintUsagesForm\.RunQuery;.*?FRun\.Cancel;\s+CancelLspQuery;')
  Check 'closing cancels the request' ($form -match '(?s)procedure TDragLintUsagesForm\.FormClose.*?CancelLspQuery;')
  Check 'the destructor cancels the request' ($form -match '(?s)procedure TDragLintUsagesForm\.FormDestroy.*?CancelLspQuery;')
  Check 'the form never spawns a server' ($form -notmatch 'EnsureLspClient')
  # 148 XP3 item 4c: a request on a stopped or replaced client falls back to the CLI (no callback ever comes).
  Check 'a sent request arms the watchdog' ($form -match '(?s)FLspClient:= Client;\s+FLspWatch\.Enabled:= True;')
  Check 'an orphaned request falls back to the CLI' ($form -match '(?s)procedure TDragLintUsagesForm\.LspWatchTick.*?UsagesRequestOrphaned\(FLspId, FLspClient, Cur,.*?RunCliQuery;')
  $ed = [IO.File]::ReadAllText((Join-Path $SrcDir 'DragLint.Plugin.Editor.pas'))
  Check 'the Editor hands over the existing client, no spawn' ($ed -match 'GUsagesLspClient:= CurrentLspClient;')
} finally {
  if ($lsp -and -not $lsp.HasExited) { try { $lsp.Kill() } catch { } }
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'PASSED' -ForegroundColor Green