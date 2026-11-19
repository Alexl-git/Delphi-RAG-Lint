<#
run_v152_N3WIDE.ps1 -- Find Usages WIDTH must reach the LSP path (owner N3, 1.52).

The owner saw the IDE's Find Usages answer the SAME rows at Narrow and at Wide.
The IDE asks the running LSP server first (draglint/usages) and only spawns
`drag-lint usages` when no server answers. The CLI attaches the transitive-caller
`impact` group at width 'wide' OR 'very-wide'; the LSP handler attached it at
'very-wide' only, so 'wide' over the LSP returned exactly the narrow payload.

run_lsp_usages_guard.ps1 compares CLI and LSP at the DEFAULT width (narrow) only,
which is why the drift was never seen. This runner compares them at all three
widths, with a positive control: Compute has two callers, so at wide the impact
group MUST be non-empty -- a comparison of two empty impact arrays proves nothing.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-n3wide-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:failN = 0
function Check($n,$ok,$detail=''){
  if ($ok) { $script:pass++ } else { $script:failN++ }
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
}
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($obj) {
  $j = ($obj | ConvertTo-Json -Depth 12 -Compress)
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

try {
  $exePath = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null

  WriteAscii (Join-Path $WorkDir 'uLib.pas') @'
unit uLib;

interface

function Compute(const A: Integer): Integer;

implementation

function Compute(const A: Integer): Integer;
begin
  Result := A * 2;
end;

end.
'@
  WriteAscii (Join-Path $WorkDir 'uApp.pas') @'
unit uApp;

interface

procedure Run;
procedure RunTwice;
procedure Outer;

implementation

uses
  uLib;

procedure Run;
var
  N: Integer;
begin
  N := Compute(21);
end;

procedure RunTwice;
var
  N: Integer;
begin
  N := Compute(1) + Compute(2);
end;

procedure Outer;
begin
  Run;
end;

end.
'@

  $db = Join-Path $WorkDir 'app.sqlite'
  Push-Location C:\TEMP
  try {
    & { $ErrorActionPreference = 'Continue'; & $exePath index $WorkDir --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
    Check 'N3W-0 SANITY: the fixture index exists' (Test-Path $db)

    # One LSP session, three requests (ids 10/11/12 = narrow/wide/very-wide).
    $widths = @('narrow','wide','very-wide')
    $inF  = Join-Path $WorkDir 'in.txt'
    $outF = Join-Path $WorkDir 'out.txt'
    $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
    $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
    for ($i = 0; $i -lt $widths.Count; $i++) {
      $m += Frame @{ jsonrpc='2.0'; id=(10 + $i); method='draglint/usages'; params=@{ name='Compute'; width=$widths[$i] } }
    }
    $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
    [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.UTF8Encoding $false))
    Start-Process $exePath -ArgumentList @('lsp','--db',$db) -WorkingDirectory $WorkDir `
      -RedirectStandardInput $inF -RedirectStandardOutput $outF -NoNewWindow -Wait | Out-Null

    $lspById = @{}
    foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
      try { $o = $mm.Value.Trim() | ConvertFrom-Json | ForEach-Object { $_ } } catch { continue }
      if ($o.id -ge 10 -and $o.result) { $lspById[[int]$o.id] = $o.result }
    }

    for ($i = 0; $i -lt $widths.Count; $i++) {
      $w = $widths[$i]
      $cliRaw  = (& { $ErrorActionPreference = 'Continue'; & $exePath usages --name Compute --width $w --db $db --format json 2>$null } | Out-String)
      $cliJson = $cliRaw.Substring($cliRaw.IndexOf('{'))
      $cliJson = $cliJson.Substring(0, $cliJson.LastIndexOf('}') + 1)
      $cli = $cliJson | ConvertFrom-Json | ForEach-Object { $_ }
      $lsp = $lspById[10 + $i]

      $cliImp = @($cli.impact).Count
      Check "N3W-$w-a CLI impact count matches the width (narrow 0, else > 0)" `
        ($(if ($w -eq 'narrow') { $cliImp -eq 0 } else { $cliImp -gt 0 })) "cli impact=$cliImp"
      Check "N3W-$w-b LSP answered draglint/usages" ($null -ne $lsp)
      if ($null -ne $lsp) {
        $lspImp = @($lsp.impact).Count
        Check "N3W-$w-c LSP impact count matches the width (narrow 0, else > 0)" `
          ($(if ($w -eq 'narrow') { $lspImp -eq 0 } else { $lspImp -gt 0 })) "lsp impact=$lspImp"
        $cliNorm = ($cli | ConvertTo-Json -Depth 12 -Compress)
        $lspNorm = ($lsp | ConvertTo-Json -Depth 12 -Compress)
        Check "N3W-$w-d LSP payload EQUALS the CLI payload" ($cliNorm -eq $lspNorm) `
          $(if ($cliNorm -ne $lspNorm) { "CLI=$cliNorm  LSP=$lspNorm" } else { '' })
      }
    }

    # Wide must differ from narrow on BOTH paths (the owner's symptom, stated directly).
    if ($lspById.ContainsKey(10) -and $lspById.ContainsKey(11)) {
      $n = ($lspById[10].impact | ConvertTo-Json -Depth 6 -Compress)
      $wd = ($lspById[11].impact | ConvertTo-Json -Depth 6 -Compress)
      Check 'N3W-x LSP wide answer differs from LSP narrow answer' ($n -ne $wd)
    }
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("run_v152_N3WIDE: {0} passed, {1} failed" -f $script:pass, $script:failN)
if ($script:failN -gt 0) { exit 1 } else { exit 0 }
