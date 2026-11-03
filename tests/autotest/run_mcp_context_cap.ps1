<#
  run_mcp_context_cap.ps1 -- MCP-CTX-CAP (1.42, owner ruling D9)
  The MCP tool get_context_bundle takes `max_body_tokens` (default 20000, as the CLI's
  --max-body-tokens; 0 = uncapped) and passes it to the bundler.

  CHECKS (fixture TBig, as run_context_type_body_cap.ps1):
    M1 max_body_tokens=350 engages the cap: json carries body_cap 350 and omitted_bodies
    M2 the tool schema advertises max_body_tokens
  CONTROLS:
    C1 no argument = the default 20000 cap, which this small type does not reach (no body_cap)
    C2 max_body_tokens=0 = uncapped (no body_cap)
  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_mcp_context_cap_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function Body([int]$Lines, [string]$Extra) {
  $b = "begin`n"
  if ($Extra) { $b += "  $Extra`n" }
  for ($i = 0; $i -lt $Lines; $i++) { $b += "  FX := FX + 1;`n" }
  return $b + "end;`n"
}
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
$impl = "procedure TBig.Helper;`n" + (Body 40 '') + "`n" +
        "procedure TBig.Alpha;`n"  + (Body 25 'Helper;') + "`n" +
        "procedure TBig.Beta;`n"   + (Body 25 'Helper;') + "`n" +
        "procedure TBig.Bulky;`n"  + (Body 100 '') + "`n"
Write-Ascii (Join-Path $src 'uCap.pas') @"
unit uCap;


interface

type
  TBig = class
  private
    FX: Integer;
  public
    procedure Helper;
    procedure Alpha;
    procedure Beta;
    procedure Bulky;
  end;

implementation

$impl
end.
"@
$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Call([string]$Name, [hashtable]$ToolArgs) {
  $req = Join-Path $WorkDir 'req.json'
  $msg = @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = $Name; arguments = $ToolArgs } } | ConvertTo-Json -Depth 6 -Compress
  Write-Ascii $req ($msg + "`n")
  $out = (Get-Content -Raw $req | & $exePath serve --db $db 2>$null) -join "`n"
  $line = @($out -split "`n" | Where-Object { $_ -match '"id":1' })[0]
  try { return ((ConvertFrom-Json -InputObject $line).result.content[0].text) } catch { return $out }
}
function Bundle([hashtable]$Extra) {
  $a = @{ qname = 'uCap.TBig' } + $Extra
  $t = Call 'get_context_bundle' $a
  try { return (ConvertFrom-Json -InputObject $t) } catch { return $null }
}

$m = Bundle @{ max_body_tokens = 350 }
Check 'M1 max_body_tokens=350 engages the cap (body_cap + omitted_bodies)' (($null -ne $m) -and ($m.body_cap -eq 350) -and (@($m.omitted_bodies).Count -ge 1)) ($m | ConvertTo-Json -Depth 3 -Compress)
$d = Bundle @{}
Check 'C1 CONTROL no argument = the 20000 default, not reached by this type (no body_cap)' (($null -ne $d) -and ($null -eq $d.body_cap)) ($d | ConvertTo-Json -Depth 3 -Compress)
$z = Bundle @{ max_body_tokens = 0 }
Check 'C2 CONTROL max_body_tokens=0 is uncapped (no body_cap)' (($null -ne $z) -and ($null -eq $z.body_cap)) ($z | ConvertTo-Json -Depth 3 -Compress)

$reqL = Join-Path $WorkDir 'list.json'
Write-Ascii $reqL ('{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' + "`n")
$lst = (Get-Content -Raw $reqL | & $exePath serve --db $db 2>$null) -join "`n"
Check 'M2 the tool schema advertises max_body_tokens' ($lst -match 'max_body_tokens') ($lst.Substring(0, [Math]::Min(200, $lst.Length)))

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_mcp_context_cap_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}