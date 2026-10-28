#Requires -Version 7
<#
  run_lsp_rename_guard.ps1 -- `textDocument/prepareRename` and
  `textDocument/rename` (B3; spec docs\superpowers\specs\2026-05-29-v024-rename-design.md).

  WHAT THIS PINS (each part is a positive control: a handler answering null,
  [] or a constant fails it):

    BOTH METHODS ARE ANSWERED (RED before B3: -32601) and `initialize`
    advertises renameProvider.prepareProvider = true.

    RENAME = a WorkspaceEdit {changes:{<uri>:TextEdit[]}} built by
    TRenameRefactoring.Build on the Calls.pas fixture of the spec:
    TWidget.Compute declared once, called 3 times, plus its implementation
    header -> 5 TextEdits in one uri (the spec's "4" predates the impl-header
    edit; the CLI `rename --kind symbol --json` on the same index is the
    cross-check and must give the same count). Each newText is the new name,
    each range covers exactly `Compute` (length 7) at a position computed here
    FROM THE FIXTURE TEXT -- the declaration edit is on the NAME token, not on
    the `function` keyword the symbol's StartCol points at.
    A case-only rename (COMPUTE) and a lower-case new name (calc) are NOT
    errors. A symbol with zero refs and no body (field FUnused) -> 1 edit.

    REFUSALS reply error -32803: a reserved word (message names "reserved"),
    an existing sibling (Init), a non-identifier, and a position on whitespace.

    READ-ONLY: the server writes no file -- the fixture bytes are unchanged
    after the session and no .bak appears (a server that called Apply fails).

    PREPARERENAME: on whitespace -> null; on a call of Compute -> range of
    that token + placeholder `Compute`.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-$PID"
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
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'Calls.pas'
WriteAnsi $file @'
unit Calls;

interface

type
  TWidget = class
  private
    FUnused: Integer;
  public
    procedure Init;
    function Compute(AValue: Integer): Integer;
  end;

implementation

procedure TWidget.Init;
begin
  Compute(10);
  Self.Compute(20);
end;

function TWidget.Compute(AValue: Integer): Integer;
var
  Tmp: Integer;
begin
  Tmp := AValue * 2;
  WriteLn('hi');
  Result := Tmp + Compute(0);
end;

end.
'@

$db = Join-Path $WorkDir 'calls.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)
$before = [System.IO.File]::ReadAllBytes($file)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern, [int]$from = 0) {
  for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } }
  return -1
}
# 0-based character of the WHOLE word $word on line $ln, searching from $from.
function ColOf([int]$ln, [string]$word, [int]$from = 0) {
  $m = [regex]::Match($lines[$ln].Substring($from), '\b' + $word + '\b')
  if ($m.Success) { return $from + $m.Index } else { return -1 }
}

$uri = 'file:///' + ($file -replace '\\', '/')
function Session([array]$reqs) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $id = 10
  foreach ($q in $reqs) {
    $id++
    $p = @{ textDocument=@{ uri=$uri }; position=@{ line=$q.line; character=$q.col } }
    if ($q.ContainsKey('raw')) { $p = @{} + $q.raw }
    if ($q.ContainsKey('newName')) { $p.newName = $q.newName }
    $m += Frame @{ jsonrpc='2.0'; id=$id; method=$q.method; params=$p }
  }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $r = @{ init = $null; res = @{}; err = @{} }
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 1) { $r.init = $o.result }
    if ($o.id -gt 10) {
      if ($null -ne $o.error) { $r.err[[int]$o.id] = $o.error }
      elseif ($o.PSObject.Properties.Name -contains 'result') { $r.res[[int]$o.id] = ,$o.result }
    }
  }
  return $r
}

$lDecl   = LineOf '^\s*function Compute\('
$lField  = LineOf '^\s*FUnused:'
$lCall1  = LineOf '^\s*Compute\(10\);'
$lCall2  = LineOf '^\s*Self\.Compute\(20\);'
$lHeader = LineOf '^function TWidget\.Compute\('
$lCall3  = LineOf 'Result := Tmp \+ Compute\(0\);'
$lBlank  = LineOf '^$' 1
$cDecl   = ColOf $lDecl 'Compute'
$want = @(
  "${lDecl}:$cDecl",
  "${lCall1}:$(ColOf $lCall1 'Compute')",
  "${lCall2}:$(ColOf $lCall2 'Compute')",
  "${lHeader}:$(ColOf $lHeader 'Compute' 10)",
  "${lCall3}:$(ColOf $lCall3 'Compute')"
) | Sort-Object

$reqs = @(
  @{ method='textDocument/prepareRename'; line=$lBlank; col=0 },                                       # 11
  @{ method='textDocument/prepareRename'; line=$lCall1; col=(ColOf $lCall1 'Compute') + 2 },           # 12
  @{ method='textDocument/rename'; line=$lDecl;  col=$cDecl; newName='Calc' },                         # 13
  @{ method='textDocument/rename'; line=$lDecl;  col=$cDecl; newName='COMPUTE' },                      # 14
  @{ method='textDocument/rename'; line=$lCall1; col=(ColOf $lCall1 'Compute'); newName='calc' },      # 15
  @{ method='textDocument/rename'; line=$lField; col=(ColOf $lField 'FUnused'); newName='FGone' },     # 16
  @{ method='textDocument/rename'; line=$lDecl;  col=$cDecl; newName='begin' },                        # 17
  @{ method='textDocument/rename'; line=$lDecl;  col=$cDecl; newName='Init' },                         # 18
  @{ method='textDocument/rename'; line=$lDecl;  col=$cDecl; newName='1bad' },                         # 19
  @{ method='textDocument/rename'; line=$lBlank; col=0; newName='Calc' },                              # 20
  @{ method='textDocument/rename'; raw=@{ textDocument='x'; position=@{ line=0; character=0 } }; newName='Calc' },   # 21
  @{ method='textDocument/rename'; raw=@{ textDocument=@{ uri=$uri }; position=5 }; newName='Calc' },                # 22
  @{ method='textDocument/rename'; raw=@{ textDocument=@{ uri=$uri } }; newName='Calc' },                           # 23
  @{ method='textDocument/prepareRename'; raw=@{ textDocument=7; position='p' } }                                   # 24
)
$r = Session $reqs
$caps = $r.init.capabilities
Check 'initialize advertises renameProvider.prepareProvider' ($caps.renameProvider.prepareProvider -eq $true)
Check 'the methods answered (not -32601)' ($r.res.ContainsKey(12) -and $r.res.ContainsKey(13)) $(if ($r.err.Count) { "errors=" + (($r.err.Values | ForEach-Object { $_.code }) -join ',') } else { '' })
if (-not $r.res.ContainsKey(13)) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }

Check 'prepareRename on whitespace answers null' ($r.res.ContainsKey(11) -and $null -eq $r.res[11][0] -and -not $r.err.ContainsKey(11))
$pr = $r.res[12][0]
Check 'prepareRename on Compute: placeholder Compute' ($pr.placeholder -ceq 'Compute') "got=$($pr.placeholder)"
Check 'prepareRename range is the Compute token' ($pr.range.start.line -eq $lCall1 -and $pr.range.start.character -eq (ColOf $lCall1 'Compute') -and $pr.range.end.character -eq ((ColOf $lCall1 'Compute') + 7)) "got=$($pr.range.start.line):$($pr.range.start.character)-$($pr.range.end.character)"

function EditsOf($we) {
  $names = @($we.changes.PSObject.Properties.Name)
  return @{ uris = $names; edits = @(foreach ($n in $names) { $we.changes.$n }) }
}
$cliJson = (& $Exe rename --kind symbol --name Calls.TWidget.Compute --to Calc --db $db --json 2>$null | Where-Object { $_.StartsWith('[') }) -join ''
$cliCount = @($cliJson | ConvertFrom-Json).Count

foreach ($case in @(@{ id=13; nn='Calc' }, @{ id=14; nn='COMPUTE' }, @{ id=15; nn='calc' })) {
  $e = EditsOf $r.res[$case.id][0]
  $nn = $case.nn
  Check "rename to $nn is not an error" (-not $r.err.ContainsKey($case.id)) $(if ($r.err.ContainsKey($case.id)) { $r.err[$case.id].message } else { '' })
  Check "rename to ${nn}: one uri, the fixture" ($e.uris.Count -eq 1 -and ([string]$e.uris[0]) -like 'file:*Calls.pas') "got=$($e.uris -join ',')"
  Check "rename to ${nn}: 5 TextEdits (= CLI rename --json count $cliCount)" ($e.edits.Count -eq 5 -and $cliCount -eq 5) "got=$($e.edits.Count)"
  Check "rename to ${nn}: every newText is $nn" (@($e.edits | Where-Object { $_.newText -cne $nn }).Count -eq 0)
  Check "rename to ${nn}: every range is one line, length 7" (@($e.edits | Where-Object { $_.range.start.line -ne $_.range.end.line -or ($_.range.end.character - $_.range.start.character) -ne 7 }).Count -eq 0)
  $got = @($e.edits | ForEach-Object { "$($_.range.start.line):$($_.range.start.character)" }) | Sort-Object
  Check "rename to ${nn}: positions = decl name token, 3 calls, impl header" (($got -join ',') -eq ($want -join ',')) "got=$($got -join ',') want=$($want -join ',')"
}

$e = EditsOf $r.res[16][0]
Check 'rename of a zero-ref field: exactly 1 edit at its declaration' ($e.edits.Count -eq 1 -and $e.edits[0].range.start.line -eq $lField -and $e.edits[0].range.start.character -eq (ColOf $lField 'FUnused') -and $e.edits[0].newText -ceq 'FGone') "got=$($e.edits.Count)"

Check 'rename to begin: error -32803 naming reserved' ($r.err.ContainsKey(17) -and $r.err[17].code -eq -32803 -and $r.err[17].message -match 'reserved') $(if ($r.err.ContainsKey(17)) { $r.err[17].message } else { 'no error' })
Check 'rename to an existing sibling (Init): error -32803' ($r.err.ContainsKey(18) -and $r.err[18].code -eq -32803) $(if ($r.err.ContainsKey(18)) { $r.err[18].message } else { 'no error' })
Check 'rename to a non-identifier (1bad): error -32803' ($r.err.ContainsKey(19) -and $r.err[19].code -eq -32803) $(if ($r.err.ContainsKey(19)) { $r.err[19].message } else { 'no error' })
Check 'rename on whitespace: error -32803' ($r.err.ContainsKey(20) -and $r.err[20].code -eq -32803) $(if ($r.err.ContainsKey(20)) { $r.err[20].message } else { 'no error' })

# Malformed params must answer -32602 (rename) / null (prepareRename), never raise EInvalidCast.
foreach ($id in 21, 22, 23) {
  Check "rename with a non-object textDocument/position or none: error -32602 (id $id)" ($r.err.ContainsKey($id) -and $r.err[$id].code -eq -32602) $(if ($r.err.ContainsKey($id)) { $r.err[$id].message } else { 'no error' })
}
Check 'prepareRename with malformed params answers null' ($r.res.ContainsKey(24) -and $null -eq $r.res[24][0] -and -not $r.err.ContainsKey(24))

# The returned edits, applied back-to-front to the fixture text, give the renamed text.
$text = [System.IO.File]::ReadAllText($file)
$tl = $text -split "`r`n"
$e13 = EditsOf $r.res[13][0]
foreach ($ed in @($e13.edits | Sort-Object @{Expression={$_.range.start.line}; Descending=$true}, @{Expression={$_.range.start.character}; Descending=$true})) {
  $ln = $tl[$ed.range.start.line]
  $tl[$ed.range.start.line] = $ln.Substring(0, $ed.range.start.character) + $ed.newText + $ln.Substring($ed.range.end.character)
}
$applied = $tl -join "`r`n"
$expected = $text -creplace 'Compute', 'Calc'
Check 'applying the edits back-to-front yields the fixture with Compute renamed to Calc' ($applied -ceq $expected)

$after = [System.IO.File]::ReadAllBytes($file)
Check 'server wrote nothing: fixture bytes unchanged' ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after))
Check 'server wrote nothing: no .bak file' (@(Get-ChildItem $src -Filter '*.bak').Count -eq 0)

# STALE DECLARATION: shift the declaration sideways on disk after indexing (the whole line indented, so Build cannot snap off the keyword). The
# index still records the old name column; a forward scan would retarget it, so the whole rename must be refused.
$declOrig = [System.IO.File]::ReadAllText($file)
$declLines = [System.IO.File]::ReadAllLines($file)
$declLines[$lDecl] = $declLines[$lDecl] -replace '^(\s*function)', '    $1'
WriteAnsi $file ($declLines -join "`r`n")
$rs = Session @(@{ method='textDocument/rename'; line=$lCall1; col=(ColOf $lCall1 'Compute'); newName='Calc' })
Check 'rename after the declaration moved sideways on disk: refused -32803 "out of date"' ($rs.err.ContainsKey(11) -and $rs.err[11].code -eq -32803 -and $rs.err[11].message -match 'out of date') $(if ($rs.err.ContainsKey(11)) { $rs.err[11].message } else { 'no error' })
WriteAnsi $file $declOrig

# STALE INDEX: shift a call right on disk after indexing. The index still says col 2; a forward scan would
# silently retarget the later token, so the reference edit must be refused (-32803, "out of date").
$staleLines = [System.IO.File]::ReadAllLines($file)
$staleLines[$lCall1] = '  Inc(Tmp); ' + $staleLines[$lCall1].TrimStart()
WriteAnsi $file ($staleLines -join "`r`n")
$rs = Session @(@{ method='textDocument/rename'; line=$lDecl; col=$cDecl; newName='Calc' })
Check 'rename after a ref moved on disk: refused -32803 "out of date"' ($rs.err.ContainsKey(11) -and $rs.err[11].code -eq -32803 -and $rs.err[11].message -match 'out of date') $(if ($rs.err.ContainsKey(11)) { $rs.err[11].message } else { 'no error' })

# S7: a NON-ASCII character earlier on the line must not make rename refuse.
# The ANSI (cp1252) fixture has `{ caf<E9> } Foo(1);` -- the e-acute is ONE UTF-16
# column but TWO UTF-8 bytes, and IdentifierAtPosition counts BYTES. RED before
# S7: every edit on that line was refused "out of date".
$src2 = Join-Path $WorkDir 'src2'; New-Item -ItemType Directory $src2 | Out-Null
$file2 = Join-Path $src2 'uNon.pas'
$nonText = "unit uNon;`r`n`r`ninterface`r`n`r`nprocedure Foo(AValue: Integer);`r`n`r`nimplementation`r`n`r`nprocedure Foo(AValue: Integer);`r`nbegin`r`nend;`r`n`r`nprocedure Driver;`r`nbegin`r`n  { caf" + [char]0xE9 + " } Foo(1);`r`n  { caf" + [char]0xE9 + [char]0xE9 + [char]0xE9 + [char]0xE9 + " } Foo(2);`r`nend;`r`n`r`nend.`r`n"
[System.IO.File]::WriteAllBytes($file2, [System.Text.Encoding]::GetEncoding(1252).GetBytes($nonText))
$db = Join-Path $WorkDir 'non.sqlite'
& $Exe index $src2 --db $db 2>&1 | Out-Null
$uri = 'file:///' + ($file2 -replace '\\', '/')
$lines = [System.Text.Encoding]::GetEncoding(1252).GetString([System.IO.File]::ReadAllBytes($file2)) -split "`r`n"
$lNonCall = LineOf '\} Foo\(1\);'
$cNonCall = ColOf $lNonCall 'Foo'
$rn = Session @(@{ method='textDocument/rename'; line=$lNonCall; col=($cNonCall + 1); newName='Bar' })
$okN = $rn.res.ContainsKey(11) -and -not $rn.err.ContainsKey(11)
Check 'S7: rename succeeds when a non-ASCII char precedes the name on a call line' $okN $(if ($rn.err.ContainsKey(11)) { $rn.err[11].message } else { '' })
if ($okN) {
  $callEdit = @($rn.res[11][0].changes.PSObject.Properties | ForEach-Object { $_.Value } | ForEach-Object { $_ } | Where-Object { $_.range.start.line -eq $lNonCall })
  Check 'S7: the call-line edit is at the UTF-16 column of Foo' ($callEdit.Count -eq 1 -and $callEdit[0].range.start.character -eq $cNonCall) "want=$cNonCall got=$(($callEdit | ForEach-Object { $_.range.start.character }) -join ',')"
}

# S7 cursor half: the cursor on the LAST letter of Foo after FOUR non-ASCII chars on its line.
# The client column is UTF-16; the resolver wants a byte column. RED before: no symbol resolved.
$lNon2 = LineOf '\} Foo\(2\);'
$cLast = (ColOf $lNon2 'Foo') + 2
$r2 = Session @(
  @{ method='textDocument/prepareRename'; line=$lNon2; col=$cLast },
  @{ method='textDocument/rename'; line=$lNon2; col=$cLast; newName='Bar' }
)
Check 'S7: prepareRename with the cursor on the last letter after non-ASCII chars answers the Foo token' ($r2.res.ContainsKey(11) -and $null -ne $r2.res[11][0] -and $r2.res[11][0].placeholder -ceq 'Foo' -and $r2.res[11][0].range.start.character -eq (ColOf $lNon2 'Foo')) $(if ($r2.res.ContainsKey(11)) { ($r2.res[11][0] | ConvertTo-Json -Compress -Depth 4) } else { 'no reply' })
Check 'S7: rename with the cursor on the last letter after non-ASCII chars succeeds' ($r2.res.ContainsKey(12) -and -not $r2.err.ContainsKey(12)) $(if ($r2.err.ContainsKey(12)) { $r2.err[12].message } else { '' })
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
