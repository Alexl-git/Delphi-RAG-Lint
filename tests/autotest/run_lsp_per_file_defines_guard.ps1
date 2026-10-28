#Requires -Version 7
<#
  run_lsp_per_file_defines_guard.ps1 -- the LSP (and `lint`) preprocess EACH file with
  the define profile of ITS OWN project's active build (LSP C10 / A7-L, Task 3).

  Fixture: proj\App.dproj (marker Config=Debug, Debug defines MYFEATURE) + proj\_D-RAG\App.sqlite
  (built by `index --project`); proj\uUnit.pas is a member, other\uLoose.pas is not; both hold
  garbage inside {$IFNDEF MYFEATURE}. alt\Other.dproj (marker Release, no defines) is a second
  project used to prove an EXPLICIT --project wins over the auto-discovered owner (D3).
  The owner's D1 ruling (2026-10-26): the .dproj comes first, delphilsp.json only when the
  .dproj has no Config marker.

  Cases (rule parser-error, last publishDiagnostics per file):
    a  `lsp --db`: uUnit.pas -> 0, and parity with `lint --json --db`
    b  `lsp --db`: uLoose.pas -> >= 1, parity (POSITIVE CONTROL: built-ins, MYFEATURE off)
    c  with-statement stays on its line in (a)
    d  INVALIDATION in ONE session: marker -> Release, didSave -> >= 1; then a marker-less
       .dproj + App.delphilsp.json (-DMYFEATURE) -> didSave -> 0
    e  EXPLICIT --project alt\Other.dproj (lsp and lint): uUnit.pas -> >= 1 although the
       auto-discovered owner (App, Debug) would give 0
    g  `lint uLoose.pas --project App.dproj`: a file no --db contains gets the explicit
       project's ACTIVE build too (0), never its Release profile -- one profile per project
    f  `lsp --full-rules`: uUnit.pas -> 0, uLoose.pas -> >= 1 (the lint child inherits
       per-file defines through --db)

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-pfd-$PID"
)
$script:Failed = $false
$script:Proc = $null
try {
$ErrorActionPreference = 'Stop'
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
New-Item -ItemType Directory -Force "$WorkDir\proj\_D-RAG", "$WorkDir\other", "$WorkDir\alt" | Out-Null

# ---------- fixture ----------
function New-Dproj([string]$Path, [string]$Marker, [bool]$WithMarkers = $true, [bool]$Define = $true) {
  $mk = if ($WithMarkers) {
    "        <Config Condition=""'`$(Config)'==''"">$Marker</Config>`r`n        <Platform Condition=""'`$(Platform)'==''"">Win32</Platform>`r`n"
  } else { '' }
  $def = if ($Define) { 'MYFEATURE;$(DCC_Define)' } else { '$(DCC_Define)' }
  $t = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{11111111-2222-3333-4444-555555555555}</ProjectGuid>
$mk        <MainSource>App.dpr</MainSource>
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
        <DCC_Define>$def</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_2)'!=''">
    </PropertyGroup>
    <ItemGroup>
        <DCCReference Include="uUnit.pas"/>
    </ItemGroup>
</Project>
"@
  Write-Ascii $Path ($t -replace "`r?`n", "`r`n")
  [IO.File]::SetLastWriteTime($Path, (Get-Date).AddSeconds($script:Tick++))
}
$script:Tick = 0
$Dproj = "$WorkDir\proj\App.dproj"
New-Dproj $Dproj 'Debug'
New-Dproj "$WorkDir\alt\Other.dproj" 'Release' $true $false
Write-Ascii "$WorkDir\proj\App.dpr" "program App;`r`nuses uUnit in 'uUnit.pas';`r`nbegin`r`nend.`r`n"
function New-Body([string]$Unit) {
  $lines = @(
    "unit $Unit;", '', 'interface', '', 'function CurDir: string;', 'procedure Other(X: TObject);', '',
    'implementation', '', 'function CurDir: string;', 'begin',
    '{$IFNDEF MYFEATURE}', '  Result := := ) ;', '{$ENDIF}', "  Result := 'C:\';", 'end;', '',
    'procedure Other(X: TObject);', 'begin', '  X.Free;', '  X := nil;', '', '', '', '',
    '  with X do Free;', 'end;', '', 'end.'
  )
  return (($lines -join "`r`n") + "`r`n")
}
$Unit  = "$WorkDir\proj\uUnit.pas"
$Loose = "$WorkDir\other\uLoose.pas"
Write-Ascii $Unit  (New-Body 'uUnit')
Write-Ascii $Loose (New-Body 'uLoose')
$WithLine = ((Get-Content $Unit) | Select-String -SimpleMatch 'with X do Free').LineNumber
$Db = "$WorkDir\proj\_D-RAG\App.sqlite"
$idx = (& $Exe index --project $Dproj --db $Db 2>&1 | Out-String)
Check 'SETUP project index built' (($idx -match 'Files:\s*(\d+)') -and ([int]$Matches[1] -ge 2))

# ---------- minimal interactive LSP client ----------
function ToFrame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  $b = [System.Text.Encoding]::UTF8.GetBytes($j)
  return ,([System.Text.Encoding]::ASCII.GetBytes("Content-Length: $($b.Length)`r`n`r`n") + $b)
}
function Send($obj) { $f = ToFrame $obj; $script:Proc.StandardInput.BaseStream.Write($f, 0, $f.Length); $script:Proc.StandardInput.BaseStream.Flush() }
function ReadByteT {
  $buf = New-Object byte[] 1
  $t = $script:Proc.StandardOutput.BaseStream.ReadAsync($buf, 0, 1)
  if (-not $t.Wait(60000)) { throw 'LSP read timeout' }
  if ($t.Result -eq 0) { throw 'LSP stream closed' }
  return $buf[0]
}
function ReadFrameT {
  $hdr = ''
  while ($hdr -notmatch "\r\n\r\n$") { $hdr += [char](ReadByteT) }
  $len = [int]([regex]::Match($hdr, 'Content-Length:\s*(\d+)').Groups[1].Value)
  $body = New-Object byte[] $len
  for ($i = 0; $i -lt $len; $i++) { $body[$i] = ReadByteT }
  return ([System.Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json)
}
function Start-Lsp([string[]]$LspArgs) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (@('lsp') + $LspArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $psi.WorkingDirectory = $WorkDir
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $script:Proc = [System.Diagnostics.Process]::Start($psi)
  $script:Proc.StandardError.BaseStream.ReadAsync((New-Object byte[] 65536), 0, 65536) | Out-Null
  $script:NextId = 1
  Send @{ jsonrpc='2.0'; id=$script:NextId; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  Wait-Response $script:NextId | Out-Null
  Send @{ jsonrpc='2.0'; method='initialized'; params=@{} }
}
# Reads frames until the response with this id; returns the publishDiagnostics seen on the way.
function Wait-Response([int]$Id) {
  $pubs = @()
  while ($true) {
    $f = ReadFrameT
    if ($f.method -eq 'textDocument/publishDiagnostics') { $pubs += $f }
    elseif ($null -ne $f.id -and [int]$f.id -eq $Id -and -not $f.method) { return ,$pubs }
  }
}
function Uri([string]$p) { return 'file:///' + ($p -replace '\\', '/') }
# Open or save a file, then use a hover as a barrier; returns the parser-error lines last published
# FOR THAT FILE ('NO-PUBLISH' when none arrived). With the barrier waits for the lint child.
function Push([string]$File, [string]$Method) {
  $text = [System.IO.File]::ReadAllText($File)
  if ($Method -eq 'textDocument/didOpen') {
    Send @{ jsonrpc='2.0'; method=$Method; params=@{ textDocument=@{ uri=(Uri $File); languageId='pascal'; version=1; text=$text } } }
  } else {
    Send @{ jsonrpc='2.0'; method=$Method; params=@{ textDocument=@{ uri=(Uri $File) }; text=$text } }
  }
  $script:NextId++
  Send @{ jsonrpc='2.0'; id=$script:NextId; method='textDocument/hover'; params=@{ textDocument=@{ uri=(Uri $File) }; position=@{ line=0; character=1 } } }
  $pubs = @(Wait-Response $script:NextId | Where-Object { $_.params.uri -eq (Uri $File) })
  if ($pubs.Count -eq 0) { return ,@('NO-PUBLISH') }
  return ,@($pubs[-1].params.diagnostics | Where-Object { $_.code -eq 'parser-error' } | ForEach-Object { [int]$_.range.start.line + 1 })
}
function Stop-Lsp {
  try { $script:NextId++; Send @{ jsonrpc='2.0'; id=$script:NextId; method='shutdown'; params=@{} }; Send @{ jsonrpc='2.0'; method='exit'; params=@{} } } catch { }
  if ($script:Proc -and -not $script:Proc.WaitForExit(15000)) { $script:Proc.Kill() }
  $script:Proc = $null
}
function CliLines([string]$File, [string[]]$Extra = @()) {
  $raw = (& $Exe lint $File --json --db $Db @Extra 2>$null) -join "`n"
  $arr = @(); if ($raw.Trim()) { $arr = @($raw | ConvertFrom-Json) }
  return ,@($arr | Where-Object { $_.rule -eq 'parser-error' } | ForEach-Object { [int]$_.start_line })
}
function WithLines { param($File)
  $raw = (& $Exe lint $File --json --db $Db 2>$null) -join "`n"
  $arr = @(); if ($raw.Trim()) { $arr = @($raw | ConvertFrom-Json) }
  return ,@($arr | Where-Object { $_.rule -eq 'with-statement' } | ForEach-Object { [int]$_.start_line })
}

# ---------- a/b/c/d: one session, no --project ----------
Write-Host 'lsp --db (auto-discovered owner)' -ForegroundColor Cyan
Start-Lsp @('--db', $Db)
try {
  $a = Push $Unit 'textDocument/didOpen'
  $cliA = CliLines $Unit
  Check 'a uUnit.pas: 0 parser-error' (($a -join ',') -eq '') "lsp=[$($a -join ',')]"
  Check 'a parity with lint --json --db' (($a -join ',') -eq ($cliA -join ',')) "cli=[$($cliA -join ',')]"
  $b = Push $Loose 'textDocument/didOpen'
  $cliB = CliLines $Loose
  Check 'b uLoose.pas: >= 1 parser-error (POSITIVE CONTROL)' ($b.Count -ge 1 -and $b -notcontains 'NO-PUBLISH') "lsp=[$($b -join ',')]"
  Check 'b parity with lint --json --db' (($b -join ',') -eq ($cliB -join ',')) "cli=[$($cliB -join ',')]"
  $w = WithLines $Unit
  Check "c with-statement on line $WithLine" ($w -contains $WithLine) "lint=[$($w -join ',')]"
  # d: the .dproj changes under a running server
  New-Dproj $Dproj 'Release'
  $d1 = Push $Unit 'textDocument/didSave'
  Check 'd1 marker -> Release, didSave: >= 1 parser-error' ($d1.Count -ge 1 -and $d1 -notcontains 'NO-PUBLISH') "lsp=[$($d1 -join ',')]"
  New-Dproj $Dproj 'Release' $false
  Write-Ascii "$WorkDir\proj\App.delphilsp.json" '{"settings":{"project":"file:///x/App.dpr","dllname":"dcc64370.dll","dccOptions":"-$O- -DMYFEATURE;;FRAMEWORK_VCL -E.\\Win64\\Debug","projectFiles":[]}}'
  $d2 = Push $Unit 'textDocument/didSave'
  Check 'd2 marker-less .dproj + delphilsp.json -DMYFEATURE, didSave: 0' (($d2 -join ',') -eq '') "lsp=[$($d2 -join ',')]"
} finally { Stop-Lsp }

# restore the fixture
[IO.File]::Delete("$WorkDir\proj\App.delphilsp.json")
New-Dproj $Dproj 'Debug'

# ---------- e: explicit --project wins ----------
Write-Host 'explicit --project wins (D3)' -ForegroundColor Cyan
$Other = "$WorkDir\alt\Other.dproj"
Start-Lsp @('--db', $Db, '--project', $Other)
try {
  $e1 = Push $Unit 'textDocument/didOpen'
  Check 'e lsp --project Other.dproj: uUnit.pas >= 1 parser-error' ($e1.Count -ge 1 -and $e1 -notcontains 'NO-PUBLISH') "lsp=[$($e1 -join ',')]"
} finally { Stop-Lsp }
$e2 = CliLines $Unit @('--project', $Other)
Check 'e lint --project Other.dproj: uUnit.pas >= 1 parser-error' ($e2.Count -ge 1) "cli=[$($e2 -join ',')]"
$e3 = CliLines $Unit
Check 'e control: lint without --project: 0' ($e3.Count -eq 0) "cli=[$($e3 -join ',')]"
# g: ONE profile per explicit --project. A file the --db does not contain (uLoose.pas) gets the
# SAME active-build profile (App = Debug, MYFEATURE on) as a member does, never the project's
# Release profile. Control: (b) -- the same file without --project is >= 1.
$g1 = CliLines $Loose @('--project', $Dproj)
Check 'g lint uLoose.pas --project App.dproj (not a DB member): 0 parser-error' ($g1.Count -eq 0) "cli=[$($g1 -join ',')]"

# ---------- f: --full-rules ----------
Write-Host 'lsp --full-rules' -ForegroundColor Cyan
Start-Lsp @('--db', $Db, '--full-rules')
try {
  $f1 = Push $Unit 'textDocument/didOpen'
  Check 'f full-rules uUnit.pas: 0 parser-error' (($f1 -join ',') -eq '') "lsp=[$($f1 -join ',')]"
  $f2 = Push $Loose 'textDocument/didOpen'
  Check 'f full-rules uLoose.pas: >= 1 parser-error' ($f2.Count -ge 1 -and $f2 -notcontains 'NO-PUBLISH') "lsp=[$($f2 -join ',')]"
} finally { Stop-Lsp }
}
catch { Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red; $script:Failed = $true }
finally {
  try { if ($script:Proc -and -not $script:Proc.HasExited) { $script:Proc.Kill() } } catch { }
  try { if ($WorkDir -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { Write-Host 'run_lsp_per_file_defines_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lsp_per_file_defines_guard: PASS' -ForegroundColor Green
exit 0
