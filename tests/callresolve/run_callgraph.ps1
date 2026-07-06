<#
  run_callgraph.ps1 -- TDD harness for D5 Task 11: `callgraph --qname X
  --direction callees|callers --depth N` prints an N-deep resolved call tree
  over call_edges. The CRITICAL assertion is that a CYCLE fixture TERMINATES
  (no infinite loop) -- global-visited cycle policy + depth cap.

  Fixtures:
    callchain.pas -- TChain.StepA -> TChainB.StepB -> TChainC.StepC ->
                     TChainD.StepD (a straight 4-deep chain).
    callcycle.pas -- TCyc.PingP -> TCyc.PongQ -> TCyc.PingP (a 2-hop Self cycle).

  callgraph --qname StepA --direction callees --depth 2 must include the
  depth-1 callee TChainB.StepB and the depth-2 callee TChainC.StepC, but NOT
  the depth-3 callee TChainD.StepD (depth cap).

  callgraph on the cycle must return promptly (bounded output, exit 0) -- a
  hang would fail the whole harness. We run it with a hard timeout.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath   = (Resolve-Path $Exe).Path
$chainFix  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\callchain.pas')).Path
$cycleFix  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\callcycle.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_callgraph'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item $chainFix (Join-Path $scratch 'callchain.pas') -Force
$db = Join-Path $scratch 'cg.sqlite'

# A SEPARATE dir/db for the cycle so it doesn't perturb the chain tree.
$cycScratch = Join-Path C:\TEMP 'draglint_callgraph_cycle'
if (Test-Path $cycScratch) { Remove-Item $cycScratch -Recurse -Force }
New-Item -ItemType Directory -Path $cycScratch | Out-Null
Copy-Item $cycleFix (Join-Path $cycScratch 'callcycle.pas') -Force
$cycDb = Join-Path $cycScratch 'cyc.sqlite'

Push-Location C:\TEMP
try {
  & $exePath index $scratch    --db $db    2>$null | Out-Null
  & $exePath index $cycScratch --db $cycDb 2>$null | Out-Null

  # --- callgraph --direction callees --depth 2 over the chain. ---
  $txt = & $exePath callgraph --qname StepA --direction callees --depth 2 --db $db 2>$null | Out-String
  $rc  = $LASTEXITCODE
  Check 'callgraph exit 0'                        ($rc -eq 0)
  Check 'tree root TChain.StepA present'          ($txt -match 'callchain\.TChain\.StepA')
  Check 'depth-1 callee TChainB.StepB present'    ($txt -match 'callchain\.TChainB\.StepB')
  Check 'depth-2 callee TChainC.StepC present'    ($txt -match 'callchain\.TChainC\.StepC')
  Check 'depth-3 callee TChainD.StepD ABSENT (depth cap)' (-not ($txt -match 'callchain\.TChainD\.StepD'))

  # --- depth 3 DOES reach StepD. ---
  $txt3 = & $exePath callgraph --qname StepA --direction callees --depth 3 --db $db 2>$null | Out-String
  Check 'depth-3 tree reaches TChainD.StepD'      ($txt3 -match 'callchain\.TChainD\.StepD')

  # --- callers direction: who reaches StepD (depth 3). ---
  $txtC = & $exePath callgraph --qname StepD --direction callers --depth 3 --db $db 2>$null | Out-String
  Check 'callers dir: StepC calls into StepD'     ($txtC -match 'callchain\.TChainC\.StepC')

  # --- json: nested tree. ---
  $jsonOut = & $exePath callgraph --qname StepA --direction callees --depth 2 --json --db $db 2>$null | Out-String
  $obj = $jsonOut | ConvertFrom-Json
  Check 'json root qname = TChain.StepA'          ($obj.qname -eq 'callchain.TChain.StepA')
  Check 'json root has 1 child'                   (@($obj.children).Count -eq 1)
  Check 'json child = TChainB.StepB'              ($obj.children[0].qname -eq 'callchain.TChainB.StepB')

  # --- CRITICAL: the CYCLE must terminate (bounded output, no hang). ---
  # Run with a hard timeout: a hang FAILS instead of blocking forever.
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName  = $exePath
  $psi.Arguments = "callgraph --qname PingP --direction callees --depth 10 --db `"$cycDb`""
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  # Read stdout to end FIRST (drains the pipe), then confirm exit within the cap.
  # A hung process never closes stdout, so ReadToEnd would block -- guard it with
  # an async read + a hard WaitForExit so a hang FAILS instead of blocking.
  $stdoutTask = $p.StandardOutput.ReadToEndAsync()
  $exited = $p.WaitForExit(15000)   # 15s hard cap
  if (-not $exited) { $p.Kill(); Check 'CYCLE terminates within 15s (no infinite loop)' $false }
  else {
    $cycOut = $stdoutTask.GetAwaiter().GetResult()
    Check 'CYCLE terminates within 15s (no infinite loop)' $true
    Check 'CYCLE output is bounded (< 200 lines)' (($cycOut -split "`n").Count -lt 200)
    Check 'CYCLE tree mentions PingP' ($cycOut -match 'callcycle\.TCyc\.PingP')
    Check 'CYCLE tree mentions PongQ' ($cycOut -match 'callcycle\.TCyc\.PongQ')
    Check 'CYCLE marks the back-edge as a cycle' ($cycOut -match '\(cycle\)|\(seen\)')
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
