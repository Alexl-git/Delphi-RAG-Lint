#Requires -Version 7
<#
  run_lsp_inlay_hint_guard.ps1 -- `textDocument/inlayHint` parameter names (B6).

  WHAT THIS PINS, and why each part is here rather than "it returned something":

    THE METHOD IS ANSWERED (RED before B6: -32601 method not found) and
    `initialize` advertises inlayHintProvider = true.

    THE HINTS ARE RIGHT (positive control). `Add(1, 2)` against
    `procedure Add(const pA, pB: Integer);` -> exactly two hints, labels 'pA:'
    and 'pB:', kind 2 (Parameter), paddingRight true, each AT its argument's
    column (computed here FROM THE FIXTURE TEXT). A handler returning [] or a
    constant fails this.

    AMBIGUITY IS SILENT: an overloaded `Dup` (two routines) called once gives
    no hint on that line; `Add(3)` (argument count 1, parameter count 2) gives
    no hint on that line.

    THE RANGE IS HONOURED: a range that covers only the interface section
    (no call) answers [].

    AN UNKNOWN FILE answers [] (not an error).

    EXPLICIT --db IS THE WHOLE UNIVERSE (S5, battery-138): the central context
    defaults name a library that ALSO declares a routine `Add`. `lsp --db
    hints.sqlite` must not join it -- if it did, `Add` would be ambiguous and
    every Add hint would vanish (measured: 0 hints on a machine whose real
    defaults name C:\Projects\.drag-lint\library-Win64.sqlite).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-inlay-$PID"
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

$file = Join-Path $src 'uHints.pas'
WriteAnsi $file @'
unit uHints;

interface

procedure Add(const pA, pB: Integer);
procedure Ref(const [ref] pR: Integer; pS: Integer);
procedure Dup(pX: Integer); overload;
procedure Dup(pX, pY: Integer); overload;
procedure Driver;

implementation

procedure Add(const pA, pB: Integer);
begin
end;

procedure Ref(const [ref] pR: Integer; pS: Integer);
begin
end;

procedure Dup(pX: Integer);
begin
end;

procedure Dup(pX, pY: Integer);
begin
end;

procedure Driver;
begin
  Add(1, 2);
  Dup(7);
  Add(3);
  Ref(5, 6);
end;

end.
'@

$db = Join-Path $WorkDir 'hints.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
# S5: a defaults file whose Win64 library declares a second `Add`.
$libSrc = Join-Path $WorkDir 'lib'; New-Item -ItemType Directory $libSrc | Out-Null
WriteAnsi (Join-Path $libSrc 'uLibAdd.pas') "unit uLibAdd;`r`ninterface`r`nprocedure Add(pOther: Integer);`r`nimplementation`r`nprocedure Add(pOther: Integer);`r`nbegin`r`nend;`r`nend.`r`n"
$libDb = Join-Path $WorkDir 'defaults-lib.sqlite'
& $Exe index $libSrc --db $libDb 2>&1 | Out-Null
$defaultsFile = Join-Path $WorkDir 'defaults.json'
[System.IO.File]::WriteAllText($defaultsFile, (@{ schema = 1; platform = 'Win64'; libraries = @{ Win64 = @{ libraryDb = $libDb } } } | ConvertTo-Json -Depth 5), (New-Object System.Text.ASCIIEncoding))
$env:DRAGLINT_CONTEXT_DEFAULTS = $defaultsFile
Check 'S5: defaults library built' (Test-Path $libDb)
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } }
  return -1
}

function Session([string]$uri, [int]$fromLine, [int]$toLine) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/inlayHint'; params=@{ textDocument=@{ uri=$uri }; range=@{ start=@{ line=$fromLine; character=0 }; end=@{ line=$toLine; character=0 } } } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $r = @{ init = $null; hints = $null; err = $null }
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 1) { $r.init = $o.result }
    if ($o.id -eq 2) {
      if ($null -ne $o.error) { $r.err = $o.error }
      else { $r.hints = ,@($o.result) }   # ,@() keeps an empty [] distinct from "no answer"
    }
  }
  return $r
}

$uri = 'file:///' + ($file -replace '\\', '/')
$r = Session $uri 0 $lines.Count
Check 'initialize advertises inlayHintProvider = true' ($r.init.capabilities.inlayHintProvider -eq $true) "caps=$($r.init.capabilities | ConvertTo-Json -Compress -Depth 3)"
Check 'the method answered (not -32601)' ($null -ne $r.hints) $(if ($r.err) { "error=$($r.err.code) $($r.err.message)" } else { '' })
if ($null -eq $r.hints) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }

$hints = @($r.hints[0])
$addLn = LineOf '^\s*Add\(1, 2\);'
$dupLn = LineOf '^\s*Dup\(7\);'
$badLn = LineOf '^\s*Add\(3\);'
$c1 = $lines[$addLn].IndexOf('1')
$c2 = $lines[$addLn].IndexOf('2')
Check 'exactly four hints in the whole file' ($hints.Count -eq 4) "got=$($hints.Count) $($hints | ConvertTo-Json -Compress -Depth 5)"
$h1 = @($hints | Where-Object { $_.position.line -eq $addLn -and $_.position.character -eq $c1 }) | Select-Object -First 1
$h2 = @($hints | Where-Object { $_.position.line -eq $addLn -and $_.position.character -eq $c2 }) | Select-Object -First 1
Check "hint 'pA:' at the first argument ($addLn,$c1)" ($null -ne $h1 -and $h1.label -eq 'pA:') "got=$($h1 | ConvertTo-Json -Compress)"
Check "hint 'pB:' at the second argument ($addLn,$c2)" ($null -ne $h2 -and $h2.label -eq 'pB:') "got=$($h2 | ConvertTo-Json -Compress)"
Check 'hints are kind 2 (Parameter) with paddingRight true' ($null -ne $h1 -and $null -ne $h2 -and $h1.kind -eq 2 -and $h2.kind -eq 2 -and $h1.paddingRight -eq $true -and $h2.paddingRight -eq $true)
Check 'overloaded Dup gives no hint' (-not (@($hints | Where-Object { $_.position.line -eq $dupLn }).Count))
Check 'wrong argument count gives no hint' (-not (@($hints | Where-Object { $_.position.line -eq $badLn }).Count))
$refLn = LineOf '^\s*Ref\(5, 6\);'
$rr = @($hints | Where-Object { $_.position.line -eq $refLn } | Sort-Object { $_.position.character })
Check "S4: 'const [ref] pR' is stripped to pR and pS (labels pR:, pS:)" ($rr.Count -eq 2 -and $rr[0].label -eq 'pR:' -and $rr[1].label -eq 'pS:') "got=$($rr | ConvertTo-Json -Compress -Depth 5)"

# S3: a viewport request must answer exactly the hints inside its range
# (the walk skips subtrees outside it; this pins that the skip loses nothing).
$rs = Session $uri $addLn ($addLn + 1)
Check 'S3: a one-line range answers only that line (the two Add hints)' ($null -ne $rs.hints -and @($rs.hints[0]).Count -eq 2 -and -not @($rs.hints[0] | Where-Object { $_.position.line -ne $addLn }).Count) "got=$(@($rs.hints[0]).Count)"
$rs2 = Session $uri $refLn ($refLn + 1)
Check 'S3: a range on the LAST call line still answers its hints' ($null -ne $rs2.hints -and @($rs2.hints[0]).Count -eq 2) "got=$(@($rs2.hints[0]).Count)"

$implLn = LineOf '^implementation'
$r2 = Session $uri 0 ($implLn - 1)
Check 'a range with no call answers []' ($null -ne $r2.hints -and @($r2.hints[0]).Count -eq 0 -and $null -eq $r2.err) "got=$(@($r2.hints[0]).Count)"

$r3 = Session 'file:///c%3A/no/such/dir/Nope.pas' 0 10
Check 'unknown URI answers [] (not an error)' ($null -ne $r3.hints -and @($r3.hints[0]).Count -eq 0 -and $null -eq $r3.err) $(if ($r3.err) { "error=$($r3.err.code)" } else { '' })

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  $env:DRAGLINT_CONTEXT_DEFAULTS = $null
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
