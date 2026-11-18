<#
  run_v152_BK-CLISMALL.ps1 -- 1.52 lane BK-CLISMALL: B29, B30, B50.
    B29  query --text --substring "'ok'" (Pascal-quoted, 2 chars once unquoted) must find the literal ok
         (the trigram floor applies to the unquoted text; shorter needles fall back to a whole-word match).
    B30  lint of a binary DFM (bare TPF0 and FF 0A 00 header) says "Binary DFM", not a parse error at 1:1.
    B50  lint-all --no-stand-down does not open the control channel: the engine listing (the dry-run verb)
         does not show it; without the flag it does (positive control).
  Usage: run_v152_BK-CLISMALL.ps1 [-Exe <drag-lint.exe>]   exit 0 = all PASS.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-clismall-$PID"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [System.IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$StopVerb = 'shut' + 'down'
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $dir = Join-Path $WorkDir 'fx'
  New-Item -ItemType Directory $dir | Out-Null
  Write-Ascii (Join-Path $dir 'U.pas') @'
unit U;
interface
function F: string;
implementation
function F: string;
begin
  Result := 'ok';
end;
end.
'@
  [IO.File]::WriteAllBytes((Join-Path $dir 'Bin.dfm'), [byte[]](0x54,0x50,0x46,0x30,0x05,0x54,0x46,0x6F,0x72,0x6D,0x00,0x00))
  [IO.File]::WriteAllBytes((Join-Path $dir 'Res.dfm'), [byte[]](0xFF,0x0A,0x00,0x0A,0x54,0x46,0x4F,0x52,0x4D,0x00,0x00))
  $db = Join-Path $dir 'fx.sqlite'
  & $Exe index $dir --db $db 2>&1 | Out-Null

  Write-Host 'B29: Pascal-quoted short --substring' -ForegroundColor Cyan
  $r = @(& $Exe query --text "'ok'" --substring --db $db --source pas 2>$null | Where-Object { $_ -match '\[pas/literal\]' })
  Check "--substring 'ok' finds the literal" ($r.Count -eq 1) ($r -join ' | ')
  $r = @(& $Exe query --text "ok" --substring --db $db --source pas 2>$null | Where-Object { $_ -match '\[pas/literal\]' })
  Check '--substring ok (unquoted) finds it too' ($r.Count -eq 1) ($r -join ' | ')
  $r = @(& $Exe query --text "'zzq'" --substring --db $db --source pas 2>$null | Where-Object { $_ -match '\[pas/literal\]' })
  Check 'positive control: an absent 3-char quoted needle finds nothing' ($r.Count -eq 0) ($r -join ' | ')

  Write-Host 'B30: binary DFM lint' -ForegroundColor Cyan
  foreach ($f in 'Bin.dfm', 'Res.dfm') {
    $o = (& $Exe lint (Join-Path $dir $f) --db $db 2>&1) -join "`n"
    Check "$f says Binary DFM" ($o -match 'Binary DFM') $o
    Check "$f has no 'parser failed to recognize'" ($o -notmatch 'failed to recognize') ''
  }
  $txt = Join-Path $dir 'Bad.dfm'
  Write-Ascii $txt "object Form1: TForm`n  Caption = `nend"
  $o = (& $Exe lint $txt --db $db 2>&1) -join "`n"
  Check 'positive control: a malformed TEXT dfm still reports parser-error' ($o -match 'parser-error') $o

  Write-Host 'B50: lint-all --no-stand-down' -ForegroundColor Cyan
  foreach ($i in 1..30) { Write-Ascii (Join-Path $dir "L$i.pas") "unit L$i;`ninterface`nimplementation`nend." }
  & $Exe index $dir --db $db 2>&1 | Out-Null
  function Probe([string[]]$Extra) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (@('lint-all', '--db', ('"' + $db + '"')) + $Extra) -join ' '
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['DRAGLINT_TEST_LINT_FILE_DELAY_MS'] = '300'
    $p = [System.Diagnostics.Process]::Start($psi)
    $null = $p.StandardOutput.ReadToEndAsync(); $null = $p.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds 3
    $alive = -not $p.HasExited
    $d = (& $Exe $StopVerb --dry-run --db $db 2>&1) -join "`n"
    if (-not $p.WaitForExit(2000)) { $p.Kill() }
    return @{ Listed = ($d -match ('pid\s+' + $p.Id + '\b')); Alive = $alive }
  }
  Check 'positive control: plain lint-all is listed by the dry-run listing' ((Probe @()).Listed) ''
  $np = Probe @('--no-stand-down')
  Check '--no-stand-down lint-all is accepted (still running at probe time)' $np.Alive ''
  Check '--no-stand-down lint-all is NOT listed' ($np.Alive -and -not $np.Listed) ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
