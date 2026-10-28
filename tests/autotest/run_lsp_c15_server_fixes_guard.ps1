#Requires -Version 7
<#
  run_lsp_c15_server_fixes_guard.ps1 -- LSP backlog C15: two TLSPServer fixes.

  (a) IdentifierAtPosition (behind definition / hover / references / rename) used
      to run its OWN raw tree-sitter parse, whose read callback copied the whole
      rest of the buffer per call. It now parses through
      DRagLint.LSP.SyntaxTree.ParseDelphiUtf8 (the C9 preprocessed, 64 KiB-chunk
      parse). SPEC on the C9 alternative-body fixture (Win64: MSWINDOWS on, POSIX
      off): textDocument/definition on the call Twice(3) AFTER the IFDEF block
      (line 31) resolves to Twice (declared line 7, defined line 11); on the
      active call Twice(1) (line 19) likewise (POSITIVE CONTROL: the lookup works
      at all). A static check pins that IdentifierAtPosition no longer builds its
      own TTSParser or copies a tail per read.
  (b) The --full-rules `lint` child is handed the server's explicit --project and
      --platform (only those, only when given). A stub child
      (FullRulesChildStub.cs, DRAGLINT_FULLRULES_CHILD_EXE) records its argv.
      SPEC: given -> forwarded with the same value (a path with a space survives
      as ONE argument); not given -> absent. POSITIVE CONTROL: the stub ran and
      its argv carries `lint`, the file, --json and the server's --db.

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-c15-$PID"
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
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null

function Frame($o) {
  $j = $o | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function ReadFrames([string]$out) {
  $res = @{}; $i = 0
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
function RunLspMsgs([string]$Tag, [string[]]$Msgs, [string[]]$LspArgs) {
  $dir = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $dir | Out-Null
  $in = Join-Path $dir 'in.txt'; $so = Join-Path $dir 'out.txt'; $se = Join-Path $dir 'err.txt'
  [IO.File]::WriteAllText($in, ($Msgs -join ''), (New-Object Text.UTF8Encoding($false)))
  # Start-Process joins ArgumentList with spaces: quote the items that hold one
  $a = @($LspArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
  $null = Start-Process $Exe -ArgumentList $a -WorkingDirectory $WorkDir `
    -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait -PassThru
  $out = if (Test-Path $so) { [IO.File]::ReadAllText($so) } else { '' }
  return @{ Out = $out; Frames = (ReadFrames $out) }
}

# ================= (a) IdentifierAtPosition parses the preprocessed text =================
$lines = @(
  'unit uC15;'                                 # 1
  ''                                           # 2
  'interface'                                  # 3
  ''                                           # 4
  'function CurDir: string;'                   # 5
  'procedure Other(X: TObject);'               # 6
  'function Twice(AValue: Integer): Integer;'  # 7
  ''                                           # 8
  'implementation'                             # 9
  ''                                           # 10
  'function Twice(AValue: Integer): Integer;'  # 11
  'begin'                                      # 12
  '  Result := AValue * 2;'                    # 13
  'end;'                                       # 14
  ''                                           # 15
  'function CurDir: string;'                   # 16
  '{$IFDEF MSWINDOWS}'                         # 17
  'begin'                                      # 18
  '  Twice(1);'                                # 19
  'end;'                                       # 20
  '{$ENDIF}'                                   # 21
  '{$IFDEF POSIX}'                             # 22
  'begin'                                      # 23
  '  Twice(2);'                                # 24
  'end;'                                       # 25
  '{$ENDIF}'                                   # 26
  ''                                           # 27
  'procedure Other(X: TObject);'               # 28
  'begin'                                      # 29
  '  X.Free;'                                  # 30
  '  Twice(3);'                                # 31
  'end;'                                       # 32
  ''                                           # 33
  'end.'                                       # 34
)
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $src | Out-Null
$file = Join-Path $src 'uC15.pas'
[IO.File]::WriteAllText($file, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'c15.sqlite'
$null = & $Exe index $src --db $db 2>&1
if (-not (Test-Path $db)) { Write-Host 'FATAL: fixture not indexed' -ForegroundColor Red; exit 2 }
$uri = 'file:///' + ($file -replace '\\', '/')
$td = @{ uri = $uri }

Write-Host '(a) definition after an IFDEF alternative-body block' -ForegroundColor Cyan
$m = @(
  (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
  (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
  (Frame @{ jsonrpc='2.0'; id=11; method='textDocument/definition'; params=@{ textDocument=$td; position=@{ line=18; character=4 } } })
  (Frame @{ jsonrpc='2.0'; id=12; method='textDocument/definition'; params=@{ textDocument=$td; position=@{ line=30; character=4 } } })
  (Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} })
  (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
)
$r = RunLspMsgs 'a' $m @('lsp', '--db', $db)
function DefLines($x) { return ,@(@($x) | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_.range.start.line + 1 } | Sort-Object -Unique) }
$d19 = DefLines $r.Frames[11]
$d31 = DefLines $r.Frames[12]
Check 'definition of Twice on the active call (line 19) finds line 7 or 11 -- POSITIVE CONTROL' (($d19 -contains 7) -or ($d19 -contains 11)) ("lines=[" + ($d19 -join ',') + "]")
Check 'definition of Twice on the call AFTER the IFDEF block (line 31) finds line 7 or 11' (($d31 -contains 7) -or ($d31 -contains 11)) ("lines=[" + ($d31 -join ',') + "]")

$srvPas = Join-Path $PSScriptRoot '..\..\src\lsp\DRagLint.LSP.Server.pas'
$srv = [IO.File]::ReadAllText($srvPas)
$mi = [regex]::Match($srv, 'function TLSPServer\.IdentifierAtPosition\(.*?\r?\nend; // function', 'Singleline')
Check 'static: the IdentifierAtPosition body was found' $mi.Success ''
Check 'static: IdentifierAtPosition parses through ParseDelphiUtf8' ($mi.Value -match 'ParseDelphiUtf8\(') ''
Check 'static: IdentifierAtPosition builds no TTSParser of its own' ($mi.Value -notmatch 'TTSParser') ''
Check 'static: IdentifierAtPosition has no tail-copy read callback' ($mi.Value -notmatch 'Remaining') ''

# ================= (b) --full-rules child gets --project / --platform =================
Write-Host '(b) --full-rules child argv' -ForegroundColor Cyan
$csc = @('Framework64', 'Framework') | ForEach-Object { Join-Path $env:WINDIR "Microsoft.NET\$_\v4.0.30319\csc.exe" } | Where-Object { Test-Path $_ } | Select-Object -First 1
$stubDir = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory -Force $stubDir | Out-Null
$stubExe = Join-Path $stubDir 'FullRulesChildStub.exe'
if ($csc) { $null = & $csc /nologo /out:$stubExe (Join-Path $PSScriptRoot 'fixtures\lsp\FullRulesChildStub.cs') 2>&1 }
Check 'SANITY: the stub child compiled' (Test-Path $stubExe) ('csc=' + $csc)
$projDir = Join-Path $WorkDir 'my proj'
New-Item -ItemType Directory -Force $projDir | Out-Null
$proj = Join-Path $projDir 'App.dproj'
$dproj = @('<?xml version="1.0" encoding="utf-8"?>', '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">', '</Project>') -join "`r`n"
[IO.File]::WriteAllText($proj, $dproj + "`r`n", [Text.Encoding]::ASCII)

function ChildArgv([string]$Tag, [string[]]$Extra) {
  $argvF = Join-Path $stubDir "$Tag.argv"
  $env:DRAGLINT_FULLRULES_CHILD_EXE = $stubExe
  $env:STUB_MODE = 'badjson'
  $env:STUB_ARGV_FILE = $argvF
  try {
    $m = @(
      (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
      (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
      (Frame @{ jsonrpc='2.0'; method='textDocument/didSave'; params=@{ textDocument=$td } })
      (Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} })
      (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
    )
    $null = RunLspMsgs $Tag $m (@('lsp', '--full-rules', '--db', $db) + $Extra)
  } finally {
    Remove-Item Env:DRAGLINT_FULLRULES_CHILD_EXE, Env:STUB_MODE, Env:STUB_ARGV_FILE -ErrorAction SilentlyContinue
  }
  if (Test-Path $argvF) { return ,@(Get-Content -LiteralPath $argvF) }
  return $null
}
function ArgAfter($av, [string]$flag) { $i = [array]::IndexOf($av, $flag); if ($i -ge 0 -and $i + 1 -lt $av.Count) { return $av[$i + 1] }; return $null }

$none = ChildArgv 'none' @()
Check 'none: the stub child ran -- POSITIVE CONTROL' ($null -ne $none) ''
if ($null -ne $none) {
  Check 'none: argv carries lint, the file, --json and the server --db -- POSITIVE CONTROL' (($none -contains 'lint') -and ($none -contains $file) -and ($none -contains '--json') -and ((ArgAfter $none '--db') -eq $db)) ($none -join ' | ')
  Check 'none: no --project forwarded' ($none -notcontains '--project') ''
  Check 'none: no --platform forwarded' ($none -notcontains '--platform') ''
}
$both = ChildArgv 'both' @('--project', $proj, '--platform', 'win32')
Check 'both: the stub child ran' ($null -ne $both) ''
if ($null -ne $both) {
  Check 'both: --project forwarded as ONE argument (path with a space)' ((ArgAfter $both '--project') -eq $proj) ($both -join ' | ')
  Check 'both: --platform win32 forwarded' ((ArgAfter $both '--platform') -eq 'win32') ''
  Check 'both: the base argv is intact' (($both -contains 'lint') -and ($both -contains '--json') -and ((ArgAfter $both '--db') -eq $db)) ''
}
$platOnly = ChildArgv 'plat' @('--platform', 'win32')
if ($null -ne $platOnly) {
  Check 'platform only: --platform forwarded' ((ArgAfter $platOnly '--platform') -eq 'win32') ($platOnly -join ' | ')
  Check 'platform only: no --project invented' ($platOnly -notcontains '--project') ''
} else { Check 'platform only: the stub child ran' $false '' }
$projOnly = ChildArgv 'proj' @('--project', $proj)
if ($null -ne $projOnly) {
  Check 'project only: --project forwarded' ((ArgAfter $projOnly '--project') -eq $proj) ($projOnly -join ' | ')
  Check 'project only: no --platform invented' ($projOnly -notcontains '--platform') ''
} else { Check 'project only: the stub child ran' $false '' }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
