#Requires -Version 7
<#
  run_lsp_c9_preprocess_guard.ps1 -- the LSP's own tree-sitter parse
  (DRagLint.LSP.SyntaxTree.ParseDelphiUtf8: semantic tokens, inlay hints) must
  parse the PREPROCESSED text, exactly as the LSP's lint does since C8
  (run_lsp_preprocess_guard.ps1).

  THE DEFECT THIS PINS (LSP backlog C9):
    C8 made publishDiagnostics lint the preprocessed text, but ParseDelphiUtf8
    still parsed the RAW bytes. A routine with {$IFDEF MSWINDOWS} / {$IFDEF POSIX}
    alternative bodies (the RTL's System.IOUtils.pas pattern) then got semantic
    tokens and parameter-name inlay hints INSIDE the branch the compiler never
    sees, from a tree whose second body is an ERROR node.

  THE SPEC, on one fixture (alternative bodies; Win64 built-ins: MSWINDOWS on,
  POSIX off):
    semantic tokens  no token on the INACTIVE body's lines (23-25); the ACTIVE
                     body's `begin` (line 18) keeps its keyword token (POSITIVE
                     CONTROL: tokens are still produced -- the fix is
                     preprocessing, not suppression); `begin` of Other after the
                     {$IFDEF} block keeps its line (29).
    inlay hints      `AValue:` on the active call (line 19) and on the call after
                     the block (line 31, its line kept); none on the inactive
                     call (line 24).
    documentSymbol   CurDir is listed exactly once, at its declaration (line 5,
                     columns 0-24). NOT a ParseDelphiUtf8 caller: the outline is
                     answered from the index, which already preprocesses (one
                     symbol per routine, the interface declaration's range) --
                     pinned so a regression on either side shows here.
    rename           renaming Twice edits lines 7, 11, 19, 31 and NEVER line 24.
                     DECISION (C9): text inside an inactive branch is not
                     renamed. The edit list comes from the index store, which
                     is built from preprocessed text, so the inactive call is
                     not a reference; a rename that later activates the branch
                     (another platform/define profile) needs a reindex under
                     that profile -- the same rule the CLI `rename` verb has.
  SETUP proves the fixture needs the preprocessor: `lsp --no-preprocess` DOES
  emit a token on the inactive body and a hint on the inactive call.

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-c9-$PID"
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

# ---------- fixture (line numbers are 1-based and load-bearing) ----------
$lines = @(
  'unit uPpC9;'                                # 1
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
$file = Join-Path $src 'uPpC9.pas'
[System.IO.File]::WriteAllText($file, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'c9.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host 'FATAL: fixture not indexed' -ForegroundColor Red; exit 2 }

# ---------- LSP plumbing ----------
function Frame($o) {
  $j = $o | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
$uri = 'file:///' + ($file -replace '\\', '/')
# One session; returns id -> result for ids > 10.
function LspSession([string[]]$Extra) {
  $td = @{ uri = $uri }
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/semanticTokens/full'; params=@{ textDocument=$td } }
  $m += Frame @{ jsonrpc='2.0'; id=12; method='textDocument/inlayHint'; params=@{ textDocument=$td; range=@{ start=@{ line=0; character=0 }; end=@{ line=40; character=0 } } } }
  $m += Frame @{ jsonrpc='2.0'; id=13; method='textDocument/documentSymbol'; params=@{ textDocument=$td } }
  $m += Frame @{ jsonrpc='2.0'; id=14; method='textDocument/rename'; params=@{ textDocument=$td; position=@{ line=10; character=9 }; newName='Double' } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; method='exit'; params=@{} }
  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList (@('lsp', '--db', $db) + $Extra) -WorkingDirectory $WorkDir `
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
# Decoded semantic tokens -> 1-based line numbers that carry at least one token.
function TokenLines($r) {
  $set = @{}
  if ($null -eq $r) { return $set }
  $data = @($r.data); $ln = 0
  for ($k = 0; $k + 4 -lt $data.Count; $k += 5) { $ln += [int]$data[$k]; $set[$ln + 1] = $true }
  return $set
}
function HintLines($r) { return ,@(@($r) | Where-Object { $null -ne $_ -and $_.label -match 'AValue' } | ForEach-Object { [int]$_.position.line + 1 }) }
function Flatten($syms) {
  foreach ($s in @($syms)) { if ($null -ne $s) { $s; if ($s.children) { Flatten $s.children } } }
}

Write-Host 'SETUP: the fixture needs the preprocessor (lsp --no-preprocess)' -ForegroundColor Cyan
$raw = LspSession @('--no-preprocess')
$rawTok = TokenLines $raw[11]
Check 'raw: a semantic token on the inactive body (23-25)' ($rawTok[23] -or $rawTok[24] -or $rawTok[25]) ("lines=" + (($rawTok.Keys | Sort-Object) -join ','))
$rawHint = HintLines $raw[12]
Check 'raw: an inlay hint on the inactive call (24)' ($rawHint -contains 24) ("hints=[" + ($rawHint -join ',') + "]")

Write-Host ''
Write-Host 'preprocessed (default lsp)' -ForegroundColor Cyan
$pp = LspSession @()
$tok = TokenLines $pp[11]
$td = "lines=" + (($tok.Keys | Sort-Object) -join ',')
Check 'semantic tokens: none on the inactive body (23-25)' (-not ($tok[23] -or $tok[24] -or $tok[25])) $td
Check 'semantic tokens: active begin (18) kept -- POSITIVE CONTROL' ([bool]$tok[18]) $td
Check 'semantic tokens: begin after the block keeps line 29' ([bool]$tok[29]) $td
$hint = HintLines $pp[12]
$hd = "hints=[" + ($hint -join ',') + "]"
Check 'inlay hints: exactly lines 19 and 31 (active + after the block), not 24' ((($hint | Sort-Object) -join ',') -eq '19,31') $hd

$flat = @(Flatten $pp[13])
$cur = @($flat | Where-Object { $_.name -eq 'CurDir' })
$cd = "CurDir at=[" + (($cur | ForEach-Object { '{0}:{1}-{2}' -f ([int]$_.range.start.line + 1), $_.range.start.character, $_.range.end.character }) -join ',') + "]"
Check 'documentSymbol: CurDir listed once, range line 5 col 0-24' ($cur.Count -eq 1 -and [int]$cur[0].range.start.line -eq 4 -and [int]$cur[0].range.start.character -eq 0 -and [int]$cur[0].range.end.character -eq 24) $cd

$edits = @()
$ren = $pp[14]
if ($null -ne $ren -and $null -ne $ren.changes) {
  foreach ($p in $ren.changes.PSObject.Properties) { $edits += @($p.Value | ForEach-Object { [int]$_.range.start.line + 1 }) }
}
if ($null -ne $ren -and $null -ne $ren.documentChanges) {
  foreach ($dc in @($ren.documentChanges)) { $edits += @($dc.edits | ForEach-Object { [int]$_.range.start.line + 1 }) }
}
$ed = "edits=[" + (($edits | Sort-Object) -join ',') + "]"
Check 'rename Twice: edits 7, 11, 19, 31 (POSITIVE CONTROL: it renames)' ((($edits | Sort-Object -Unique) -join ',') -eq '7,11,19,31') $ed
Check 'rename Twice: never edits the inactive branch (24)' ($edits -notcontains 24) $ed

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
