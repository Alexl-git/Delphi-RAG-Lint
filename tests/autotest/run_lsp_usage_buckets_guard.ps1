#Requires -Version 7
<#
  run_lsp_usage_buckets_guard.ps1 -- `draglint/usages` files raise / handle refs
  under their own `raises` / `handles` arrays, exactly as the CLI `usages` verb
  does (XT-RAISE, 1.36.0), instead of the catch-all `calls`.

  WHAT THIS PINS
    NON-VACUITY   the CLI itself reports >0 raises and >0 handles for the fixture
                  exception class, so "LSP agrees" cannot be two empties.
    THE FIX       the LSP's raises / handles hold those rows and `calls` holds
                  NONE of their (file, line, col) positions.
    POSITIVE CTRL an ordinary call (Boom, called from Guard) still lands in calls.
    NO DRIFT      the whole LSP payload equals the CLI payload, key for key.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-usage-buckets-$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}

WriteAscii (Join-Path $WorkDir 'uErr.pas') @'
unit uErr;

interface

uses
  System.SysUtils;

type
  EMyFail = class(Exception);

procedure Boom;
procedure Guard;

implementation

procedure Boom;
begin
  raise EMyFail.Create('x');
end;

procedure Guard;
begin
  try
    Boom;
  except
    on E: EMyFail do
      Writeln(E.Message);
  end;
end;

end.
'@

$db = Join-Path $WorkDir 'app.sqlite'
function Frame($obj) {
  $j = ($obj | ConvertTo-Json -Depth 12 -Compress)
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}
function CliUsages([string]$Name) {
  $raw = (& $exePath usages --name $Name --db $db --format json 2>$null | Out-String)
  $j = $raw.Substring($raw.IndexOf('{'))
  $j = $j.Substring(0, $j.LastIndexOf('}') + 1)
  return ($j | ConvertFrom-Json)
}
function Pos($r) { "$($r.file):$($r.line):$($r.col)" }

Push-Location C:\TEMP
try {
  & $exePath index $WorkDir --db $db 2>&1 | Out-Null
  Check '1. SANITY: the index exists' (Test-Path $db)

  $cliE = CliUsages 'EMyFail'
  $cliB = CliUsages 'Boom'
  Check '2. NON-VACUITY: CLI reports raises and handles for EMyFail' `
        ((@($cliE.raises).Count -gt 0) -and (@($cliE.handles).Count -gt 0)) `
        ("raises=$(@($cliE.raises).Count) handles=$(@($cliE.handles).Count) (an index from before XT-RAISE has neither)")

  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='draglint/usages'; params=@{ name='EMyFail' } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='draglint/usages'; params=@{ name='Boom' } }
  $m += Frame @{ jsonrpc='2.0'; id=4; method='shutdown'; params=@{} }
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.UTF8Encoding $false))
  Start-Process $exePath -ArgumentList @('lsp','--db',$db) -WorkingDirectory $WorkDir `
        -RedirectStandardInput $inF -RedirectStandardOutput $outF -NoNewWindow -Wait | Out-Null

  $lspE = $null; $lspB = $null
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2 -and $o.result) { $lspE = $o.result }
    if ($o.id -eq 3 -and $o.result) { $lspB = $o.result }
  }
  Check '3. draglint/usages answered' (($null -ne $lspE) -and ($null -ne $lspB))

  if (($null -ne $lspE) -and ($null -ne $lspB)) {
    $has = $lspE.PSObject.Properties.Name
    Check '4. the reply carries raises and handles keys' (('raises' -in $has) -and ('handles' -in $has))
    Check '5. LSP raises equal the CLI raises' `
          ((@($lspE.raises | ForEach-Object { Pos $_ }) -join '|') -eq (@($cliE.raises | ForEach-Object { Pos $_ }) -join '|'))
    Check '6. LSP handles equal the CLI handles' `
          ((@($lspE.handles | ForEach-Object { Pos $_ }) -join '|') -eq (@($cliE.handles | ForEach-Object { Pos $_ }) -join '|'))
    $moved = @(@($cliE.raises) + @($cliE.handles) | ForEach-Object { Pos $_ })
    $leak  = @(@($lspE.calls) | Where-Object { (Pos $_) -in $moved })
    Check '7. NO raise/handle row is filed under calls' ($leak.Count -eq 0) ("leaked=$($leak.Count)")
    Check '8. POSITIVE CONTROL: the ordinary call to Boom is still in calls' `
          ((@($lspB.calls).Count -gt 0) -and (@($cliB.calls).Count -eq @($lspB.calls).Count)) `
          ("lsp calls=$(@($lspB.calls).Count) cli calls=$(@($cliB.calls).Count)")
    Check '9. the whole payload equals the CLI payload (EMyFail)' `
          (($cliE | ConvertTo-Json -Depth 12 -Compress) -eq ($lspE | ConvertTo-Json -Depth 12 -Compress))
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-lsp-usage-buckets-$PID")) { if (Test-Path -LiteralPath $d) { [System.IO.Directory]::Delete($d, $true) } }
}
