<#
run_v152_COLS.ps1 -- 1.52 COLS: the consumers of index columns after EXTGAPS2 made every .pas
index column a CHARACTER (UTF-16) column (tree-sitter still reports UTF-8 BYTE columns).

Every fixture is a BOM-less Windows-1252 file with non-ASCII characters EARLIER on the line
than the name under test (each e-acute: one character, two UTF-8 bytes).

  L  LSP: a client position is a UTF-16 column. IdentifierAtPosition (tree, bytes) and
     SelectSymbolAt / TTypeAtResolver (index + decoded text, characters) both get it right:
       L1 definition on `B.Foo` resolves TB.Foo (RED: the char column read as a byte column
          names the `}` of the comment -- no identifier, no answer)
       L2 rename on `B.Foo` renames TB.Foo, not TA.Foo (RED: the byte column handed to
          SelectSymbolAt missed the token; Symbols[0] = TA.Foo was renamed)
       L3 control: an ASCII line still resolves (definition on `A.Foo` -> TA.Foo)
  N  naming fix (method-pascalcase --fix --apply): the finding's column is the checker's
     tree-sitter BYTE column; the fixer reads the identifier and matches the store's
     CHARACTER column. RED: the identifier was read from the ANSI-decoded line at the byte
     column (`oIt;`), nothing renamed. Control: the ASCII method on the next line is renamed.
  U  unwith --plan on a with-site after non-ASCII text: the member is qualified (positive
     control for EXTGAPS2's char->byte map in LoadRowsOf on an ANSI file).

Usage: pwsh -File tests/autotest/run_v152_COLS.ps1 [-Exe <path>] [-LibraryDb <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe       = '',
  [string]$WorkDir   = "$env:TEMP\drag-lint-v152-cols-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$env:DRAGLINT_RENAME_TEST_UNGATED = '1'
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Fail++; Write-Host "  [FAIL] $Name  $Detail" -ForegroundColor Red }
}
$Cp1252 = [System.Text.Encoding]::GetEncoding(1252)
$Eacute = [string][char]0xE9
function WriteAnsi([string]$Path, [string]$Text) {
  [IO.File]::WriteAllBytes($Path, $Cp1252.GetBytes(($Text -replace "`r?`n", "`r`n").Replace('~', $Eacute)))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# ---------------------------------------------------------------- L: LSP
Write-Host '== L: LSP client columns are UTF-16; the tree wants bytes, the index characters' -ForegroundColor Cyan
$srcL = Join-Path $WorkDir 'lsp'; New-Item -ItemType Directory $srcL | Out-Null
$fileL = Join-Path $srcL 'uCols.pas'
WriteAnsi $fileL @'
unit uCols;

interface

type
  TA = class
    procedure Foo;
  end;
  TB = class
    procedure Foo;
  end;

implementation

procedure TA.Foo;
begin
end;

procedure TB.Foo;
begin
end;

procedure Driver;
var
  A: TA;
  B: TB;
begin
  A := TA.Create;
  B := TB.Create;
  { ~~~~ } B.Foo;
  A.Foo;
end;

end.
'@
$dbL = Join-Path $WorkDir 'lsp.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $srcL --db $dbL 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'L: fixture indexed' ($LASTEXITCODE -eq 0 -and (Test-Path $dbL))
$linesL = $Cp1252.GetString([IO.File]::ReadAllBytes($fileL)) -split "`r`n"
function LineOfL([string]$Pattern) { for ($i = 0; $i -lt $linesL.Count; $i++) { if ($linesL[$i] -match $Pattern) { return $i } }; return -1 }
$uriL = 'file:///' + ($fileL -replace '\\', '/')
function Session([array]$Reqs) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $id = 10
  foreach ($q in $Reqs) {
    $id++
    $p = @{ textDocument=@{ uri=$uriL }; position=@{ line=$q.line; character=$q.col } }
    if ($q.ContainsKey('newName')) { $p.newName = $q.newName }
    $m += Frame @{ jsonrpc='2.0'; id=$id; method=$q.method; params=$p }
  }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'
  [IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $dbL) -WorkingDirectory $WorkDir -RedirectStandardInput $inF `
    -RedirectStandardOutput $outF -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $r = @{ res = @{}; err = @{} }
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -gt 10) {
      if ($null -ne $o.error) { $r.err[[int]$o.id] = $o.error }
      elseif ($o.PSObject.Properties.Name -contains 'result') { $r.res[[int]$o.id] = ,$o.result }
    }
  }
  return $r
}
# every location line a definition answer names (definition answers EVERY same-named symbol, by design)
function DefLines($Res) {
  if ($null -eq $Res) { return @() }
  return @(@($Res[0]) | Where-Object { $null -ne $_ } | ForEach-Object {
    if ($_.PSObject.Properties.Name -contains 'targetRange') { [int]$_.targetRange.start.line } else { [int]$_.range.start.line } })
}
$lBFoo = LineOfL '\} B\.Foo;'
$lAFoo = LineOfL '^\s*A\.Foo;'
$cBFoo = $linesL[$lBFoo].IndexOf('Foo')
$cAFoo = $linesL[$lAFoo].IndexOf('Foo')
$lTADecl = LineOfL '^procedure TA\.Foo;'
$lTBDecl = LineOfL '^procedure TB\.Foo;'
$lTAIntf = 6; $lTBIntf = 9
$s = Session @(
  @{ method='textDocument/definition'; line=$lBFoo; col=($cBFoo + 1) },
  @{ method='textDocument/definition'; line=$lAFoo; col=($cAFoo + 1) },
  @{ method='textDocument/rename'; line=$lBFoo; col=($cBFoo + 1); newName='Bar' }
)
$d1 = @(DefLines $s.res[11])
Check 'L1: definition on B.Foo after four non-ASCII chars names Foo (TB.Foo among the answers)' (($d1 -contains $lTBIntf) -or ($d1 -contains $lTBDecl)) "got lines $($d1 -join ',') (TB: $lTBIntf/$lTBDecl, TA: $lTAIntf/$lTADecl)"
$d2 = @(DefLines $s.res[12])
Check 'L3: control -- definition on A.Foo (ASCII line) names Foo' (($d2 -contains $lTADecl) -or ($d2 -contains $lTAIntf)) "got lines $($d2 -join ',')"
$edits = @()
if ($s.res.ContainsKey(13) -and $null -ne $s.res[13][0]) {
  $edits = @($s.res[13][0].changes.PSObject.Properties | ForEach-Object { $_.Value } | ForEach-Object { $_ })
}
$editLines = @($edits | ForEach-Object { [int]$_.range.start.line })
Check 'L2: rename on B.Foo after non-ASCII chars renames TB.Foo (its decl lines + the call)' (
  ($editLines -contains $lTBIntf) -and ($editLines -contains $lTBDecl) -and ($editLines -contains $lBFoo) -and
  -not ($editLines -contains $lTAIntf) -and -not ($editLines -contains $lTADecl)) `
  "edit lines: $($editLines -join ',') err: $(if ($s.err.ContainsKey(13)) { $s.err[13].message })"
$callEdit = @($edits | Where-Object { $_.range.start.line -eq $lBFoo })
Check 'L2: the call-line edit sits on the UTF-16 column of Foo' ($callEdit.Count -eq 1 -and $callEdit[0].range.start.character -eq $cBFoo) "want $cBFoo got $(($callEdit | ForEach-Object { $_.range.start.character }) -join ',')"

# ---------------------------------------------------------------- N: naming fix
Write-Host '== N: method-pascalcase --fix on a declaration after non-ASCII text' -ForegroundColor Cyan
$srcN = Join-Path $WorkDir 'naming'; New-Item -ItemType Directory $srcN | Out-Null
$fileN = Join-Path $srcN 'uNam.pas'
WriteAnsi $fileN @'
unit uNam;

interface

type
  TNam = class
  public
    { caf~ } procedure doIt;
    procedure goOn;
  end;

implementation

procedure TNam.doIt;
begin
end;

procedure TNam.goOn;
begin
  doIt;
end;

end.
'@
$dbN = Join-Path $WorkDir 'naming.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $srcN --db $dbN 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'N: fixture indexed' ($LASTEXITCODE -eq 0)
$cfgN = Join-Path $WorkDir 'naming.json'
[IO.File]::WriteAllText($cfgN, '{ "autofix": ["method-pascalcase"] }')
$outN = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $dbN --config $cfgN --rule method-pascalcase --fix --apply --quiet 2>&1 | ForEach-Object { "$_" } }
$textN = $Cp1252.GetString([IO.File]::ReadAllBytes($fileN))
Check 'N1: the method after non-ASCII text is renamed (decl, impl header, call)' (
  ([regex]::Matches($textN, '\bDoIt\b')).Count -eq 3 -and -not ($textN -cmatch '\bdoIt\b')) "file now:`n$textN`nout: $($outN -join ' | ')"
Check 'N2: control -- the ASCII-line method is renamed too' (([regex]::Matches($textN, '\bGoOn\b')).Count -eq 2) ''
Check 'N3: the non-ASCII comment survives byte for byte' ($textN.Contains("{ caf$Eacute }")) ''

# ---------------------------------------------------------------- U: unwith
Write-Host '== U: unwith --plan qualifies a with-member after non-ASCII text' -ForegroundColor Cyan
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP U: no platform library ($LibraryDb)" -ForegroundColor Yellow }
else {
  $srcU = Join-Path $WorkDir 'unwith'; New-Item -ItemType Directory $srcU | Out-Null
  $fileU = Join-Path $srcU 'uWith.pas'
  WriteAnsi $fileU @'
unit uWith;

interface

type
  TRec = record
    Alpha: Integer;
    Beta : Integer;
  end;

procedure Run(var R: TRec);

implementation

procedure Run(var R: TRec);
begin
  with R do
  begin
    { caf~~ } Alpha := 1;
    Beta := 2;
  end;
end;

end.
'@
  $dbU = Join-Path $WorkDir 'unwith.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $srcU --db $dbU 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $oU = & { $ErrorActionPreference = 'Continue'; & $Exe unwith --db $dbU --library-db $LibraryDb --in $fileU --plan --json 2>&1 | ForEach-Object { "$_" } }
  $jU = ($oU | Where-Object { $_ -like '{*' } | Select-Object -Last 1)
  $pU = $null; try { $pU = $jU | ConvertFrom-Json } catch { }
  $bU = @(if ($pU) { $pU.sites | ForEach-Object { $_.bindings } })
  Check 'U1: the with-site is a candidate (nothing refused)' ($null -ne $pU -and $pU.candidates -eq 1 -and $pU.refused -eq 0) "plan: $jU"
  Check 'U2: Alpha (after the non-ASCII comment) and Beta are both bound and prefixed' (
    @($bU | Where-Object { $_.name -eq 'Alpha' -and $_.prefixed -and $_.before -like 'uWith.TRec.Alpha*' }).Count -eq 1 -and
    @($bU | Where-Object { $_.name -eq 'Beta' -and $_.prefixed }).Count -eq 1) "plan: $jU"
}

Write-Host ''
Write-Host ("v152 COLS: {0} pass, {1} fail" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
exit $(if ($script:Fail) { 1 } else { 0 })
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
