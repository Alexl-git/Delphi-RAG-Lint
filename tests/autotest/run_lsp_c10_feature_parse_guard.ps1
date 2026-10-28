#Requires -Version 7
<#
  run_lsp_c10_feature_parse_guard.ps1 -- the LSP's own tree-sitter parse (semantic
  tokens, inlay hints; DRagLint.LSP.SyntaxTree.ParseDelphiUtf8) preprocesses each file with
  the define profile of ITS OWN project (LSP C10 / A7-L, Task 4; C9 made the parse
  preprocess at all).

  Fixture: proj\App.dproj (marker Config=Debug, Debug defines MYFEATURE) + its index; proj\uUnit.pas
  is a member, other\uLoose.pas is not. Both hold
      {$IFDEF MYFEATURE} begin Twice(1); end; {$ELSE} begin Twice(2); end; {$ENDIF}
  Lines: active-under-MYFEATURE body 18-20 (`begin` on 18, call on 19), {$ELSE} body 22-24
  (call on 23).

  Spec (via `lsp --db`, no didOpen needed):
    uUnit.pas   MYFEATURE on  -> NO semantic token on 22-24, the keyword token of `begin`
                                 on 18 is kept (POSITIVE CONTROL), inlay hint `AValue:` on 19
                                 and none on 23
    uLoose.pas  built-ins     -> the OPPOSITE branch is active: NO token on 18-20, a token on
                                 22 (per-file proof: same text, different project)
  SETUP: `lsp --no-preprocess` emits a token on the {$ELSE} body of uUnit.pas.

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-c10-fp-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force "$WorkDir\proj\_D-RAG", "$WorkDir\other" | Out-Null

$dproj = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{11111111-2222-3333-4444-555555555555}</ProjectGuid>
        <Config Condition="'`$(Config)'==''">Debug</Config>
        <Platform Condition="'`$(Platform)'==''">Win32</Platform>
        <MainSource>App.dpr</MainSource>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Base' or '`$(Base)'!=''">
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Debug' or '`$(Cfg_1)'!=''">
        <CfgParent>Base</CfgParent>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Release' or '`$(Cfg_2)'!=''">
        <CfgParent>Base</CfgParent>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_1)'!=''">
        <DCC_Define>MYFEATURE;`$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_2)'!=''">
    </PropertyGroup>
    <ItemGroup>
        <DCCReference Include="uUnit.pas"/>
    </ItemGroup>
</Project>
"@
Write-Ascii "$WorkDir\proj\App.dproj" ($dproj -replace "`r?`n", "`r`n")
Write-Ascii "$WorkDir\proj\App.dpr" "program App;`r`nuses uUnit in 'uUnit.pas';`r`nbegin`r`nend.`r`n"
function New-Body([string]$Unit) {
  $lines = @(
    "unit $Unit;", '', 'interface', '',                       # 1-4
    'function CurDir: string;',                                # 5
    'procedure Other(X: TObject);',                            # 6
    'function Twice(AValue: Integer): Integer;',               # 7
    '', 'implementation', '',                                  # 8-10
    'function Twice(AValue: Integer): Integer;',               # 11
    'begin', '  Result := AValue * 2;', 'end;', '',            # 12-15
    'function CurDir: string;',                                # 16
    '{$IFDEF MYFEATURE}',                                      # 17
    'begin', '  Twice(1);', 'end;',                            # 18-20
    '{$ELSE}',                                                 # 21
    'begin', '  Twice(2);', 'end;',                            # 22-24
    '{$ENDIF}', '',                                            # 25-26
    'procedure Other(X: TObject);', 'begin', '  X.Free;', 'end;', '', 'end.'
  )
  return (($lines -join "`r`n") + "`r`n")
}
$Unit  = "$WorkDir\proj\uUnit.pas"
$Loose = "$WorkDir\other\uLoose.pas"
Write-Ascii $Unit  (New-Body 'uUnit')
Write-Ascii $Loose (New-Body 'uLoose')
$Db = "$WorkDir\proj\_D-RAG\App.sqlite"
& $Exe index --project "$WorkDir\proj\App.dproj" --db $Db 2>&1 | Out-Null
Check 'SETUP project index built' (Test-Path $Db)

function Frame($o) {
  $j = $o | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function Uri([string]$p) { return 'file:///' + ($p -replace '\\', '/') }
# One batch session; ids: 11 tokens(uUnit) 12 hints(uUnit) 13 tokens(uLoose)
function LspSession([string[]]$Extra) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/semanticTokens/full'; params=@{ textDocument=@{ uri=(Uri $Unit) } } }
  $m += Frame @{ jsonrpc='2.0'; id=12; method='textDocument/inlayHint'; params=@{ textDocument=@{ uri=(Uri $Unit) }; range=@{ start=@{ line=0; character=0 }; end=@{ line=40; character=0 } } } }
  $m += Frame @{ jsonrpc='2.0'; id=13; method='textDocument/semanticTokens/full'; params=@{ textDocument=@{ uri=(Uri $Loose) } } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; method='exit'; params=@{} }
  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList (@('lsp', '--db', $Db) + $Extra) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $res = @{}
  $out = [System.IO.File]::ReadAllText($outF)
  $i = 0
  while ($true) {
    $mm = [regex]::Match($out.Substring($i), 'Content-Length:\s*(\d+)\r\n\r\n')
    if (-not $mm.Success) { break }
    $start = $i + $mm.Index + $mm.Length; $len = [int]$mm.Groups[1].Value
    if ($start + $len -gt $out.Length) { break }
    $o = $out.Substring($start, $len) | ConvertFrom-Json
    if ($null -ne $o.id -and [int]$o.id -gt 10) { $res[[int]$o.id] = $o.result }
    $i = $start + $len
  }
  return $res
}
function TokenLines($r) {
  $set = @{}
  if ($null -eq $r) { return $set }
  $data = @($r.data); $ln = 0
  for ($k = 0; $k + 4 -lt $data.Count; $k += 5) { $ln += [int]$data[$k]; $set[$ln + 1] = $true }
  return $set
}
function HintLines($r) { return ,@(@($r) | Where-Object { $null -ne $_ -and $_.label -match 'AValue' } | ForEach-Object { [int]$_.position.line + 1 }) }

Write-Host 'SETUP: the fixture needs the preprocessor' -ForegroundColor Cyan
$raw = LspSession @('--no-preprocess')
$rawTok = TokenLines $raw[13]
Check '--no-preprocess: uLoose gets tokens on the FIRST branch (18-20), as if MYFEATURE were on' ($rawTok.ContainsKey(19) -and -not $rawTok.ContainsKey(23))

Write-Host 'per-file defines for the LSP feature parse' -ForegroundColor Cyan
$r = LspSession @()
$tU = TokenLines $r[11]; $hU = HintLines $r[12]; $tL = TokenLines $r[13]
Check 'uUnit: tokens produced (begin on 18 kept - POSITIVE CONTROL)' ($tU.ContainsKey(18)) ("lines=" + (($tU.Keys | Sort-Object) -join ','))
Check 'uUnit: NO token on the inactive {$ELSE} body (22-24)' (-not ($tU.ContainsKey(22) -or $tU.ContainsKey(23) -or $tU.ContainsKey(24)))
Check 'uUnit: inlay hint AValue: on the active call (19)' ($hU -contains 19) ("hints=" + ($hU -join ','))
Check 'uUnit: no inlay hint on the inactive call (23)' ($hU -notcontains 23)
Check 'uLoose: NO token on lines 18-20 (the OPPOSITE branch is active)' (-not ($tL.ContainsKey(18) -or $tL.ContainsKey(19) -or $tL.ContainsKey(20))) ("lines=" + (($tL.Keys | Sort-Object) -join ','))
Check 'uLoose: a token on 22 (begin of the active {$ELSE} body)' ($tL.ContainsKey(22))
}
catch { Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red; $script:Failed = $true }
finally {
  try { if ($WorkDir -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { Write-Host 'run_lsp_c10_feature_parse_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lsp_c10_feature_parse_guard: PASS' -ForegroundColor Green
exit 0
