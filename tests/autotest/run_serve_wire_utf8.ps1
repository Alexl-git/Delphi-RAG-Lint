<#
  run_serve_wire_utf8.ps1 -- `serve` (the MCP stdio server) writes its JSON-RPC
  replies as UTF-8 bytes whatever --output-encoding says (PR #3, Jonathas Paiva).

  WHY. TMCPServer.SendRaw used to turn the reply's UTF-8 bytes into a string
  (StringOf) and System.Write it, so the text layer re-encoded it to the output
  mode: under --output-encoding utf16 (or "outputEncoding": "utf16" in
  .drag-lint.json) every reply went out as UTF-16LE and an MCP client, which
  frames stdio as UTF-8, read NUL bytes. It now writes the bytes with WriteFile on
  the stdout handle. Under ascii and utf8 the wire is unchanged: ToJSON already
  escapes every character above 127, so the reply is 7-bit ASCII.

  Checks (one request: an unknown method, which needs no database):
    S1  ascii: one LF-terminated line, 7-bit ASCII, a JSON-RPC error reply (-32601)
        -- the positive control: the reply the client must get
    S2  utf8 : byte-identical to S1
    S3  utf16: byte-identical to S1 (no NUL bytes) -- RED before the fix

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_servewire_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
[void][System.IO.Directory]::CreateDirectory($WorkDir)
$req = Join-Path $WorkDir 'req.json'
[System.IO.File]::WriteAllText($req, '{"jsonrpc":"2.0","id":7,"method":"no_such_method"}' + "`n", [System.Text.Encoding]::ASCII)

function Get-Wire([string]$Enc) {
  $out = Join-Path $WorkDir "out-$Enc.bin"
  $p = Start-Process -FilePath $exePath -ArgumentList @('serve', '--output-encoding', $Enc) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $req -RedirectStandardOutput $out -RedirectStandardError (Join-Path $WorkDir "err-$Enc.txt") `
    -NoNewWindow -PassThru
  if (-not $p.WaitForExit(30000)) { $p.Kill($true); throw "serve --output-encoding $Enc did not exit in 30 s" }
  , [System.IO.File]::ReadAllBytes($out)
}

$ascii = Get-Wire 'ascii'
$text  = [System.Text.Encoding]::ASCII.GetString($ascii)
$isAscii = -not ($ascii | Where-Object { $_ -ge 0x80 -or $_ -eq 0 })
$oneLine = ($ascii.Length -gt 1) -and ($ascii[-1] -eq 10) -and ($ascii[-2] -ne 13) -and (($ascii | Where-Object { $_ -eq 10 }).Count -eq 1)
$code = $null
try { $code = ($text | ConvertFrom-Json).error.code } catch { }
Check 'S1 ascii: one LF-terminated ASCII line, a JSON-RPC -32601 reply' ($isAscii -and $oneLine -and ($code -eq -32601)) "bytes=$($ascii.Length) text=$text"

foreach ($enc in 'utf8', 'utf16') {
  $w = Get-Wire $enc
  $same = ($w.Length -eq $ascii.Length) -and (-not (Compare-Object $w $ascii -SyncWindow 0))
  $nul = ($w | Where-Object { $_ -eq 0 }).Count
  Check ("S{0} {1}: the same UTF-8 bytes as ascii (no re-encoding)" -f @{ utf8 = 2; utf16 = 3 }[$enc], $enc) $same "bytes=$($w.Length) (ascii $($ascii.Length)), NUL bytes=$nul"
}
}
catch { Write-Host "[FAIL] harness: $_" -ForegroundColor Red; $fail = $true }
finally { if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) } }
if ($fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
