<#
  run_rename_other_paths.ps1 -- E-RENAME-OTHER-PATHS: the LSP rename and the lint --fix naming renames go through the
  proof `rename --apply` uses (DRagLint.Refactor.RenameProof), not the bare Build / BuildLocal edit sets.

  Each unsound rename here COMPILES or leaves a token nobody mentions, and the old paths wrote it:
    Width  -> a read inside an inactive {$IFDEF}: no ref, so Build leaves it behind  [no-ref-occurrence]
    x -> pX -> the routine already reads the GLOBAL pX: it would bind to the param   [capture-local]
    Height -> ClassName -> the library's TObject declares it: the new member hides it [new-name-in-library]

  POSITIVE CONTROLS: Height -> Tall / FHeight and y -> pY are renamed in the same runs, so a path that refuses everything
  fails; a proof handed no library refuses [no-library] instead of naming [new-name-in-library], so L2 and L3 also prove
  the LSP passes its library stores on. (No "no library" case: the LSP's context set finds the machine's platform library.)
  doIt -> DoIt keeps working over an inactive-branch token: a case-only rename cannot change a binding.
  RED on 1.44.1. Compiles nothing. Works under %TEMP%, from an engine COPY with its own manifest.
#>
[CmdletBinding()]
param([string]$EngineDir = "$PSScriptRoot\..\..\src\cli\Win64\Debug")
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }; $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $Name) -ForegroundColor $c
  if ($Ok) { $script:Passed++ } else { $script:FailCount++; if ($Detail) { Write-Host "      $Detail" -ForegroundColor DarkGray }; $script:Failed = $true }
}
function WriteAscii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
function Txt([string]$Path) { [IO.File]::ReadAllText($Path) }

$EngineDir = (Resolve-Path $EngineDir).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$work = Join-Path $env:TEMP ('draglint-renoth-' + [Guid]::NewGuid().ToString('N'))
$eng  = Join-Path $work 'eng'
New-Item -ItemType Directory -Force $eng | Out-Null
foreach ($f in 'drag-lint.exe', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll', 'casts.castlib') {
  if (Test-Path "$EngineDir\$f") { Copy-Item "$EngineDir\$f" "$eng\$f" }
}
Copy-Item (Join-Path $Repo 'rules') "$eng\rules" -Recurse
$Exe = Join-Path $eng 'drag-lint.exe'
function Run([string[]]$EngArgs) {
  Push-Location $work
  try { $o = ($null | & $Exe @EngArgs 2>&1 | Out-String) } finally { Pop-Location }
  return $o
}

# The miniature library: TObject's ClassName lives here and only here.
$libDir = Join-Path $work 'libsrc'; New-Item -ItemType Directory -Force $libDir | Out-Null
Copy-Item (Join-Path $Repo 'tests\fixtures\refactor\rename\libstub\LibStub.pas') $libDir
$Lib = Join-Path $work 'lib.sqlite'
$null = Run @('index', $libDir, '--db', $Lib, '--library-db', 'none')

$ShapeLines = @(
  'unit uShape;', '', 'interface', '', 'type', '  TShape = class', '  private', '    Width: Integer;', '    Height: Integer;', '  public',
  '    function GetW: Integer;', '    function GetH: Integer;', '    procedure doIt;', '  end;', '', 'var', '  pX: Integer;', '',
  'function UseCapture(x: Integer): Integer;', 'function UseClean(y: Integer): Integer;', '', 'implementation', '',
  'function TShape.GetW: Integer;', 'begin', '  {$IFDEF NEVER_DEFINED}', '  Result:= Width + 1;', '  {$ELSE}', '  Result:= Width;', '  {$ENDIF}', 'end;', '',
  'function TShape.GetH: Integer;', 'begin', '  Result:= Height;', 'end;', '',
  'procedure TShape.doIt;', 'begin', '  {$IFDEF NEVER_DEFINED}', '  doIt;', '  {$ENDIF}', 'end;', '',
  'function UseCapture(x: Integer): Integer;', 'begin', '  Result:= x + pX;', 'end;', '',
  'function UseClean(y: Integer): Integer;', 'begin', '  Result:= y;', 'end;', '', 'end.')

# A fresh project S around uShape.pas, plus the two-project shared unit of the owners case; the manifest lists them.
function New-Lab([string]$Name) {
  $root = Join-Path $work $Name
  New-Item -ItemType Directory -Force "$root\S", "$root\shared", "$root\A", "$root\B" | Out-Null
  WriteAscii "$root\S\uShape.pas" $ShapeLines
  WriteAscii "$root\S\S.dpr" @('program S;', '', 'uses', "  uShape in 'uShape.pas';", '', 'begin', 'end.')
  WriteAscii "$root\shared\uShared.pas" @('unit uShared;', '', 'interface', '', 'const', '  My_Const = 1;', '', 'implementation', '', 'end.')
  WriteAscii "$root\A\uA.pas" @('unit uA;', '', 'interface', '', 'uses', '  uShared;', '', 'function Get: Integer;', '', 'implementation', '', 'function Get: Integer;', 'begin', '  Result:= My_Const;', 'end;', '', 'end.')
  WriteAscii "$root\B\uB.pas" @('unit uB;', '', 'interface', '', 'uses', '  uShared;', '', 'function Get: Integer;', '', 'implementation', '', 'function Get: Integer;', 'begin', '  {$IFDEF NEVER_DEFINED}', '  Result:= My_Const + 1;', '  {$ELSE}', '  Result:= My_Const;', '  {$ENDIF}', 'end;', '', 'end.')
  foreach ($p in 'A', 'B') {
    WriteAscii "$root\$p\$p.dpr" @("program $p;", '', 'uses', "  uShared in '..\shared\uShared.pas',", "  u$p in 'u$p.pas';", '', 'begin', 'end.')
  }
  $j = $root -replace '\\', '\\'
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [',
    "  { `"name`": `"S`", `"include`": [`"$j\\S\\S.dpr`"], `"db`": `"$j\\S.sqlite`" },",
    "  { `"name`": `"A`", `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$j\\A.sqlite`" },",
    "  { `"name`": `"B`", `"include`": [`"$j\\B\\B.dpr`"], `"db`": `"$j\\B.sqlite`" }", ']}}')
  WriteAscii "$root\cfg.json" @('{ "naming": { "field_prefix": "F", "param_prefix": "p", "const_case": ["PascalCase"] } }')
  foreach ($p in 'S', 'A', 'B') { $null = Run @('index', '--project', "$root\$p\$p.dpr", '--db', "$root\$p.sqlite", '--library-db', 'none') }
  return $root
}

# --------------------------------------------------------------------------- LSP
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function Lsp([string]$Root, [string[]]$Dbs, [array]$Reqs) {
  $file = "$Root\S\uShape.pas"
  $lines = [IO.File]::ReadAllLines($file)
  $uri = 'file:///' + ($file -replace '\\', '/')
  $m  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $m += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $id = 10
  foreach ($q in $Reqs) {
    $id++
    $ln = 0; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $q.At) { $ln = $i; break } }
    $col = [regex]::Match($lines[$ln], '\b' + $q.Word + '\b').Index
    $m += Frame @{ jsonrpc = '2.0'; id = $id; method = 'textDocument/rename'; params = @{ textDocument = @{ uri = $uri }; position = @{ line = $ln; character = $col }; newName = $q.To } }
  }
  $m += Frame @{ jsonrpc = '2.0'; id = 2; method = 'shutdown'; params = @{} }
  $inF = "$Root\in.txt"; $outF = "$Root\out.txt"
  [IO.File]::WriteAllText($inF, $m, [Text.Encoding]::ASCII)
  $la = @('lsp'); foreach ($d in $Dbs) { $la += '--db'; $la += $d }
  Start-Process $Exe -ArgumentList $la -WorkingDirectory $work -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError "$Root\err.txt" -NoNewWindow -Wait | Out-Null
  $r = @{ res = @{}; err = @{} }
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -gt 10) {
      if ($null -ne $o.error) { $r.err[[int]$o.id] = $o.error.message }
      elseif ($o.PSObject.Properties.Name -contains 'result') { $r.res[[int]$o.id] = $o.result }
    }
  }
  return $r
}
function EditCount($We) { $n = 0; foreach ($p in $We.changes.PSObject.Properties) { $n += @($p.Value).Count }; return $n }

$failedSetup = $false
try {
  Write-Host '== E-RENAME-OTHER-PATHS: the LSP rename and lint --fix naming renames are proved ==' -ForegroundColor Cyan
  $r0 = New-Lab 'lsp'
  $q = Run @('query', '--name', 'Width', '--db', "$r0\S.sqlite")
  Check 'F1 fixture indexed' ($q -match 'Width') $q
  $before = Txt "$r0\S\uShape.pas"

  Write-Host 'LSP' -ForegroundColor Cyan
  $r = Lsp $r0 @("$r0\S.sqlite", $Lib) @(
    @{ At = '^\s*Width: Integer'; Word = 'Width'; To = 'Breadth' },     # 11
    @{ At = '^\s*Height: Integer'; Word = 'Height'; To = 'Tall' },      # 12
    @{ At = '^\s*Height: Integer'; Word = 'Height'; To = 'ClassName' }, # 13
    @{ At = '^\s*Width: Integer'; Word = 'Width'; To = 'WIDTH' })       # 14
  Check 'L1 Width -> Breadth is refused, naming [no-ref-occurrence] (a token in an inactive branch)' ($r.err[11] -match 'no-ref-occurrence') "err=$($r.err[11]) res=$($r.res[11] | ConvertTo-Json -Compress -Depth 6)"
  Check 'L2 control: Height -> Tall answers its proved edits (decl + the one read)' ($null -ne $r.res[12] -and (EditCount $r.res[12]) -eq 2) "err=$($r.err[12]) res=$($r.res[12] | ConvertTo-Json -Compress -Depth 6)"
  Check 'L3 Height -> ClassName is refused, naming [new-name-in-library]' ($r.err[13] -match 'new-name-in-library') "err=$($r.err[13])"
  Check 'L4 case-only Width -> WIDTH is no refusal: it cannot change a binding' ($null -ne $r.res[14] -and (EditCount $r.res[14]) -ge 2) "err=$($r.err[14])"
  Check 'L6 the server wrote nothing' ((Txt "$r0\S\uShape.pas") -ceq $before)

  Write-Host 'lint --fix, single project' -ForegroundColor Cyan
  $r1 = New-Lab 'fieldfix'
  $o = Run @('lint-all', '--db', "$r1\S.sqlite", '--config', "$r1\cfg.json", '--library-db', $Lib, '--rule', 'field-name-prefix', '--fix', '--apply', '--quiet')
  $t = Txt "$r1\S\uShape.pas"
  Check 'N1 Width is left whole: the declaration and both reads keep the old name' ($t -cmatch '    Width: Integer;' -and $t -cmatch 'Result:= Width \+ 1;' -and $t -cmatch 'Result:= Width;') $t
  Check 'N2 the run names why: skipped (not-proved), [no-ref-occurrence]' ($o -match 'not-proved' -and $o -match 'no-ref-occurrence') $o
  Check 'N3 control: Height -> FHeight everywhere in the same run' ($t -cmatch '    FHeight: Integer;' -and $t -cmatch 'Result:= FHeight;' -and $t -cnotmatch '\bHeight\b') $t

  $r2 = New-Lab 'paramfix'
  $o = Run @('lint-all', '--db', "$r2\S.sqlite", '--config', "$r2\cfg.json", '--library-db', $Lib, '--rule', 'param-name-prefix', '--fix', '--apply', '--quiet')
  $t = Txt "$r2\S\uShape.pas"
  Check 'N4 x -> pX is refused: the routine reads the global pX, and it would compile' ($t -cmatch 'Result:= x \+ pX;' -and $t -cmatch 'UseCapture\(x: Integer\)') $t
  Check 'N5 the run names [capture-local]' ($o -match 'capture-local') $o
  Check 'N6 control: y -> pY in header, body and interface' ($t -cmatch 'Result:= pY;' -and ([regex]::Matches($t, 'UseClean\(pY: Integer\)')).Count -eq 2) $t

  $r3 = New-Lab 'casefix'
  $o = Run @('lint-all', '--db', "$r3\S.sqlite", '--config', "$r3\cfg.json", '--library-db', $Lib, '--rule', 'method-pascalcase', '--fix', '--apply', '--quiet')
  $t = Txt "$r3\S\uShape.pas"
  Check 'N7 doIt -> DoIt is written over the inactive-branch token: case only, nothing to prove' ($t -cmatch 'procedure DoIt;' -and $t -cmatch 'procedure TShape\.DoIt;') $o

  $r4 = New-Lab 'fixline'
  $h = Txt "$r4\S\uShape.pas"
  $o = Run @('lint', '--file', "$r4\S\uShape.pas", '--db', "$r4\S.sqlite", '--config', "$r4\cfg.json", '--library-db', $Lib, '--fix', '--fix-line', '8', '--fix-rule', 'field-name-prefix', '--apply')
  Check 'N8 --fix-line (the IDE''s single fix): refused with the reason, nothing written' ($o -match 'autofix: rename refused' -and $o -match 'no-ref-occurrence' -and (Txt "$r4\S\uShape.pas") -ceq $h) $o

  Write-Host 'lint --fix, a unit two projects own' -ForegroundColor Cyan
  $r5 = New-Lab 'owners'
  $hs = (Txt "$r5\shared\uShared.pas") + (Txt "$r5\A\uA.pas") + (Txt "$r5\B\uB.pas")
  $o = Run @('lint', '--file', "$r5\shared\uShared.pas", '--db', "$r5\A.sqlite", '--config', "$r5\cfg.json", '--library-db', $Lib, '--rule', 'const-casing', '--fix', '--apply')
  $now = (Txt "$r5\shared\uShared.pas") + (Txt "$r5\A\uA.pas") + (Txt "$r5\B\uB.pas")
  Check 'M1 the token in B''s inactive branch drops the rename in every project' ($now -ceq $hs) $o
  Check 'M2 the plan names project B and [no-ref-occurrence]' ($o -match 'dropped' -and $o -match 'project B: .*no-ref-occurrence') $o
  WriteAscii "$r5\B\uB.pas" @('unit uB;', '', 'interface', '', 'uses', '  uShared;', '', 'function Get: Integer;', '', 'implementation', '', 'function Get: Integer;', 'begin', '  Result:= My_Const;', 'end;', '', 'end.')
  $o = Run @('lint', '--file', "$r5\shared\uShared.pas", '--db', "$r5\A.sqlite", '--config', "$r5\cfg.json", '--library-db', $Lib, '--rule', 'const-casing', '--fix', '--apply')
  $t = (Txt "$r5\shared\uShared.pas") + (Txt "$r5\A\uA.pas") + (Txt "$r5\B\uB.pas")
  Check 'M3 control: with B clean the rename lands in the unit and both projects' ($t -cnotmatch 'My_Const' -and ([regex]::Matches($t, 'MyConst')).Count -eq 3) $o
} finally {
  Write-Host ("{0} passed, {1} failed" -f $script:Passed, $script:FailCount)
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: $work not deleted" }
}
if ($script:Failed) { exit 1 } else { exit 0 }
