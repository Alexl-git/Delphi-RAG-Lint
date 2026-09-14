<#
  run_lsp_codeaction_endtoend.ps1 --
  Actually drive the LSP server and ask it for a code action.

  WHY THIS EXISTS ALONGSIDE run_lsp_codeaction.ps1. That runner ships with the
  cherry/lsp-codeaction branch and asserts almost nothing about behaviour:

    * `Check 'BuildCodeActions implementation compiles' $true`  -- an assertion
      that CANNOT fail;
    * five regex greps over `.pas` SOURCE TEXT ("HandleCodeAction is wired in Run
      dispatch", "ReviewMarker import present in Completion"), which check that
      the code LOOKS right, not that it WORKS;
    * and its own header concedes "a full end-to-end LSP session test
      (client -> server -> response) is deferred".

  It would stay green if the handler returned null for every request, and green
  if the server never started. The converter team handed the branch over saying
  plainly that it was "compiled, not verified" and that "a passing compile says
  nothing about whether that test still asserts the right thing" -- the server
  had moved 529 commits underneath it. This runner is the missing half.

  WHAT IT ASSERTS, and why the negative control is the important one:
    E1  the server completes an LSP initialize handshake at all;
    E2  it advertises codeActionProvider in that handshake;
    E3  a drag-lint diagnostic in range yields a CodeAction carrying a
        WorkspaceEdit whose `changes` map names the file URI;
    E4  a diagnostic from ANOTHER source yields NO action.

  Without E4, a handler that returned an action for literally any request would
  pass E3 and look correct.

  NO TEST MAY HANG THE BATTERY. Every read is bounded by a deadline and the
  server process is killed in `finally`, because a stdio server that never
  answers would otherwise block the whole run rather than fail it.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_lsp_codeaction_e2e",
  [int]   $TimeoutMs = 20000
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

$unit = Join-Path $src 'uTarget.pas'
Write-Ascii $unit @'
unit uTarget;

interface

function Widen(AValue: Integer): Integer;

implementation

function Widen(AValue: Integer): Integer;
var
  Scratch: Integer;
begin
  if AValue > 0 then
    Scratch := AValue * 2;
  Result := Scratch;
end;

end.
'@

$db = Join-Path $WorkDir 'e2e.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null

# ---- LSP plumbing ----------------------------------------------------------
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName               = $exePath
$psi.Arguments              = "lsp --db `"$db`" --stdio"
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute        = $false
$psi.WorkingDirectory       = 'C:\TEMP'

$proc = $null
try {
  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdin  = $proc.StandardInput.BaseStream
  $stdout = $proc.StandardOutput.BaseStream

  $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
  $buffer   = [System.Collections.Generic.List[byte]]::new()

  function Send-Lsp($obj) {
    $json  = $obj | ConvertTo-Json -Depth 30 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $hdr   = [Text.Encoding]::ASCII.GetBytes("Content-Length: $($bytes.Length)`r`n`r`n")
    $stdin.Write($hdr, 0, $hdr.Length)
    $stdin.Write($bytes, 0, $bytes.Length)
    $stdin.Flush()
  }

  # Pulls bytes until one complete Content-Length framed message is available,
  # or the deadline passes. Returns $null on timeout rather than blocking.
  function Receive-Lsp {
    while ($true) {
      $text = [Text.Encoding]::UTF8.GetString($buffer.ToArray())
      $m = [regex]::Match($text, "Content-Length:\s*(\d+)\r?\n\r?\n")
      if ($m.Success) {
        $len        = [int]$m.Groups[1].Value
        $headerEnd  = [Text.Encoding]::UTF8.GetByteCount($text.Substring(0, $m.Index + $m.Length))
        if ($buffer.Count -ge $headerEnd + $len) {
          $body = [Text.Encoding]::UTF8.GetString($buffer.GetRange($headerEnd, $len).ToArray())
          $buffer.RemoveRange(0, $headerEnd + $len)
          return $body
        }
      }
      if ([DateTime]::UtcNow -gt $deadline) { return $null }
      if ($proc.HasExited -and $buffer.Count -eq 0) { return $null }
      $chunk = New-Object byte[] 8192
      $task  = $stdout.ReadAsync($chunk, 0, $chunk.Length)
      # The cast MUST wrap the whole expression. Written first as
      # `[int](...).TotalMilliseconds`, the cast bound to the parenthesised
      # TimeSpan, the property lookup on an int yielded $null, and $remain was
      # always 0 -- so this returned $null on the first pass and every read
      # "timed out" instantly against a server that was answering correctly.
      $remain = [int](($deadline - [DateTime]::UtcNow).TotalMilliseconds)
      if ($remain -lt 1) { return $null }
      if (-not $task.Wait([Math]::Min($remain, 2000))) { continue }
      $n = $task.Result
      if ($n -le 0) { return $null }
      # A PowerShell range slice yields Object[], which List[byte].AddRange
      # refuses; copy into a typed array instead.
      $slice = New-Object byte[] $n
      [Array]::Copy($chunk, 0, $slice, 0, $n)
      $buffer.AddRange($slice)
    }
  }

  # ---- E1/E2: handshake ----------------------------------------------------
  Send-Lsp @{
    jsonrpc = '2.0'; id = 1; method = 'initialize'
    params  = @{ processId = $PID; rootUri = $null; capabilities = @{} }
  }
  $initRaw = Receive-Lsp

  # NEVER ReadToEnd() a live process here. The first version put
  # $proc.StandardError.ReadToEnd() in this message; it is evaluated eagerly,
  # and it blocks until the process exits -- so the moment E1 failed, the runner
  # hung instead of failing, which is the one thing a test must never do.
  function Get-StderrSnippet {
    $b = New-Object byte[] 4096
    $t = $proc.StandardError.BaseStream.ReadAsync($b, 0, $b.Length)
    if ($t.Wait(1000) -and $t.Result -gt 0) { return [Text.Encoding]::UTF8.GetString($b, 0, $t.Result).Trim() }
    return '(nothing on stderr within 1s)'
  }

  Check 'E1 the server answers an LSP initialize handshake' ($null -ne $initRaw) `
        "no framed response within ${TimeoutMs}ms -- stderr: $(Get-StderrSnippet)"

  if ($null -ne $initRaw) {
    $init = $initRaw | ConvertFrom-Json
    Check 'E2 it advertises codeActionProvider' `
          ($true -eq $init.result.capabilities.codeActionProvider) `
          "capabilities.codeActionProvider = $($init.result.capabilities.codeActionProvider)"

    Send-Lsp @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }

    $uri = 'file:///' + ($unit -replace '\\','/')

    function Request-CodeAction($source) {
      Send-Lsp @{
        jsonrpc = '2.0'; id = 2; method = 'textDocument/codeAction'
        params  = @{
          textDocument = @{ uri = $uri }
          range        = @{ start = @{ line = 13; character = 0 }
                            end   = @{ line = 13; character = 20 } }
          context      = @{ diagnostics = @(
                              @{ range    = @{ start = @{ line = 13; character = 4 }
                                               end   = @{ line = 13; character = 20 } }
                                 severity = 2
                                 code     = 'uninitialized-local'
                                 source   = $source
                                 message  = 'Local "Scratch" may be read before assignment' }) }
        }
      }
      return Receive-Lsp
    }

    # ---- E3: a drag-lint diagnostic produces a real edit -------------------
    $raw = Request-CodeAction 'drag-lint'
    $ok3 = $false; $why3 = 'no response'
    if ($null -ne $raw) {
      $resp = $raw | ConvertFrom-Json
      $actions = @($resp.result)
      if ($actions.Count -gt 0 -and $null -ne $actions[0]) {
        $changes = $actions[0].edit.changes
        $names   = @()
        if ($null -ne $changes) { $names = @($changes.PSObject.Properties.Name) }
        $ok3  = ($names.Count -gt 0)
        $why3 = "action='$($actions[0].title)' changes keys=[$($names -join ', ')]"
      } else { $why3 = "result was empty: $raw" }
    }
    Check 'E3 a drag-lint diagnostic yields a CodeAction with a WorkspaceEdit' $ok3 $why3

    # ---- E4: THE NEGATIVE CONTROL -----------------------------------------
    # Without this, a handler that offered an action for anything would pass E3.
    $raw4 = Request-CodeAction 'some-other-linter'
    $ok4 = $false; $why4 = 'no response'
    if ($null -ne $raw4) {
      $resp4   = $raw4 | ConvertFrom-Json
      $actions4 = @($resp4.result | Where-Object { $null -ne $_ })
      $ok4  = ($actions4.Count -eq 0)
      $why4 = "expected no actions, got $($actions4.Count): $raw4"
    }
    Check 'E4 a diagnostic from another source yields NO action' $ok4 $why4
  }

  Send-Lsp @{ jsonrpc = '2.0'; id = 99; method = 'shutdown'; params = @{} } 2>$null
}
finally {
  if ($null -ne $proc -and -not $proc.HasExited) {
    try { $proc.Kill($true) } catch { }
  }
}

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
