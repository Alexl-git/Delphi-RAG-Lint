<#
  run_v152_FUSCOPE_lsp_scope.ps1 -- 1.52 lane FUSCOPE: the LSP honours the Find Usages scope.

  textDocument/references defaults to scope symbol: the references of the declaration the
  position is BOUND to, not of every same-named object. The client setting
  dragLint.usagesScope switches it (project = the name answer of before). draglint/usages
  (the IDE panel's in-process query) takes "scope" + a position and answers like `usages --scope`.

  Fixture: TAlpha.Run and TBeta.Run in one project; A.Run called once, B.Run twice.
  P0 positive control: with usagesScope=project the references are all three calls, so the
  narrower symbol answer cannot pass on an empty reply.
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_fuscope_lsp-{0}" -f $PID)

function Put([string]$rel, [string]$text) {
  $p = Join-Path $scratch $rel
  [IO.Directory]::CreateDirectory((Split-Path $p)) | Out-Null
  [IO.File]::WriteAllText($p, ($text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
  return $p
}
function ClassUnit([string]$unit, [string]$cls) {
  return "unit $unit;`ninterface`ntype`n  $cls = class`n  public`n    procedure Run;`n  end;`nimplementation`nprocedure $cls.Run;`nbegin`nend;`nend.`n"
}
function Frame($obj) {
  $j = ($obj | ConvertTo-Json -Depth 12 -Compress)
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

Put 'one\uAlpha.pas' (ClassUnit 'uAlpha' 'TAlpha') | Out-Null
Put 'one\uBeta.pas'  (ClassUnit 'uBeta'  'TBeta')  | Out-Null
$mainText = "unit uMain;`ninterface`nuses uAlpha, uBeta;`nprocedure Go;`nimplementation`nprocedure Go;`nvar`n  A: TAlpha;`n  B: TBeta;`nbegin`n  A := TAlpha.Create;`n  B := TBeta.Create;`n  A.Run;`n  B.Run;`n  B.Run;`nend;`nend.`n"
$uMain = Put 'one\uMain.pas' $mainText
$lineA = [Array]::IndexOf(($mainText -split "`n"), '  A.Run;') + 1
$pOne = Put 'one\AppOne.dpr' "program AppOne;`nuses uAlpha in 'uAlpha.pas', uBeta in 'uBeta.pas', uMain in 'uMain.pas';`nbegin`nend.`n"
$db = Join-Path $scratch 'one\_D-RAG\AppOne.sqlite'
$o = & { $ErrorActionPreference = 'Continue'; & $exePath index --project $pOne --db $db 2>&1 | ForEach-Object { "$_" } }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $db)) { Write-Host "FATAL: fixture did not index: $($o | Select-Object -Last 2)" -ForegroundColor Red; exit 2 }

$uri = 'file:///' + ($uMain -replace '\\', '/')
$posA = @{ line = $lineA - 1; character = 4 }   # 0-based: 'Run' in '  A.Run;'
$m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
$m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/references'; params=@{ textDocument=@{ uri=$uri }; position=$posA; context=@{ includeDeclaration=$false } } }
$m += Frame @{ jsonrpc='2.0'; id=3; method='draglint/usages'; params=@{ name='Run'; file=$uMain; line=$lineA; col=5 } }
$m += Frame @{ jsonrpc='2.0'; id=4; method='draglint/usages'; params=@{ name='Run'; scope='project' } }
$m += Frame @{ jsonrpc='2.0'; method='workspace/didChangeConfiguration'; params=@{ settings=@{ dragLint=@{ usagesScope='project' } } } }
$m += Frame @{ jsonrpc='2.0'; id=5; method='textDocument/references'; params=@{ textDocument=@{ uri=$uri }; position=$posA; context=@{ includeDeclaration=$false } } }
$m += Frame @{ jsonrpc='2.0'; id=6; method='shutdown'; params=@{} }
$inF  = Join-Path $scratch 'in.txt'
$outF = Join-Path $scratch 'out.txt'
[IO.File]::WriteAllText($inF, $m, (New-Object Text.UTF8Encoding $false))
Start-Process $exePath -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $scratch -RedirectStandardInput $inF -RedirectStandardOutput $outF -NoNewWindow -Wait | Out-Null

$res = @{}
foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $r = $mm.Value.Trim() | ConvertFrom-Json | ForEach-Object { $_ } } catch { continue }
  if ($null -ne $r.id) { $res[[int]$r.id] = $r }
}
# distinct lines: the name answer lists a member call twice (call + member-access row), a pre-existing shape
function Lines($id) { return ((@($res[$id].result) | ForEach-Object { $_.range.start.line + 1 }) | Sort-Object -Unique) -join ',' }

$lA = "$lineA"; $all = "$lineA,$($lineA + 1),$($lineA + 2)"
Check 'P0 usagesScope=project: references = all three Run calls' ((Lines 5) -eq $all) "lines=$(Lines 5) want=$all"
Check 'L1 default (scope symbol): references at A.Run = the A.Run call only' ((Lines 2) -eq $lA) "lines=$(Lines 2) want=$lA"
$u3 = $res[3].result
Check 'L2 draglint/usages with a position: scope symbol, TAlpha.Run, 1 call' (($null -ne $u3) -and ($u3.scope -eq 'symbol') -and (((@($u3.declarations) | ForEach-Object { $_.qname }) -join ',') -eq 'uAlpha.TAlpha.Run') -and (@($u3.calls).Count -eq 1)) "result=$($u3 | ConvertTo-Json -Depth 4 -Compress)"
$u4 = $res[4].result
Check 'L3 draglint/usages scope project: 2 declarations, 3 calls' (($null -ne $u4) -and ($u4.scope -eq 'project') -and (@($u4.declarations).Count -eq 2) -and (@($u4.calls).Count -eq 3)) "result=$($u4 | ConvertTo-Json -Depth 4 -Compress)"

try { [IO.Directory]::Delete($scratch, $true) } catch { Write-Host "note: scratch left at $scratch" }
if ($script:fail) { Write-Host 'run_v152_FUSCOPE_lsp_scope: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_FUSCOPE_lsp_scope: PASS' -ForegroundColor Green
exit 0
