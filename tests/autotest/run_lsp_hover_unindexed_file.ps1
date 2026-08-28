<#
  run_lsp_hover_unindexed_file.ps1 -- a hover in a file NO configured index
  contains must not be answered by the LIBRARY index.

  THE DEFECT THIS PINS (owner, live IDE, 2026-08-27):

  With DataCopy.dproj active and a loose file open, hovering `Apply` rendered

      Bde.DBTables.TDataSetUpdateObject.Apply

  Measured the same day: 0 hits for `Apply` in DataCopy's index, 192 in
  library-Win64, and the hovered file present in NEITHER. ComputeHover walks
  FStores and takes the FIRST STORE THAT HAS THE NAME, so the library answered
  for a program it has nothing to do with. The later call-site safety net
  (TTypeAtResolver.Resolve) anchors to the store that OWNS the hovered file --
  which is exactly the thing that does not exist here, so it cannot engage.

  Note the shape: the popup is CONFIDENT. There is no "not indexed" wording and
  no ambiguity marker, so the reader has no way to tell the answer came from a
  different program.

  THE FIX BEING PINNED: when no open store owns the hovered file, index THAT
  UNIT ALONE into an ephemeral store and PREPEND it for the request, so the
  owner-anchor has something to anchor to. Prepend, not replace -- the library
  stores stay behind it.

  CONTROLS (all four required; a guard asserting only "the wrong answer stopped"
  also passes with hover switched off entirely):

    PC1  a hover in an INDEXED file resolves to that file's own symbol. The
         owned path must be untouched by this change; run RED and it passes
         with the identical text, which is what "byte-identical before/after"
         means within one run.
    PC2  the loose file's own text is genuinely absent from both databases --
         the premise. If a future fixture change indexes it by accident the
         whole guard measures nothing.
    NC1  a name that exists ONLY in the library, hovered in the LOOSE file,
         must STILL resolve to the library symbol. This is the one that fails
         if the fix "works" by no longer consulting the library at all.
    NC2  stdout hygiene. TIndexer.ReportProgress writes '  <path> -> N symbols'
         to STDOUT, and stdout IS the LSP protocol channel. An ephemeral index
         built without suppressing that corrupts every reply that follows it.
         This case is the reason the fix cannot simply call IndexFile inline.

  RUN RED FIRST. Against a build without the ephemeral store, CASE 1 and CASE 2
  fail (they name the library symbol) while PC1, PC2, NC1 and NC2 all pass.
  That exact combination is the signature of a correct probe aimed at an
  unfixed engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-unindexed-guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:LastRaw = ''
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
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 12
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir           | Out-Null
New-Item -ItemType Directory "$WorkDir\libsrc"  | Out-Null
New-Item -ItemType Directory "$WorkDir\projsrc" | Out-Null
New-Item -ItemType Directory "$WorkDir\loose"   | Out-Null

# ---------------------------------------------------------------- fixtures --
# The stand-in for the RTL/VCL library index. It owns `Apply` -- the name the
# real defect collided on -- and `LibraryOnlyRoutine`, which NC1 uses to prove
# the library is still reachable after the fix.
WriteAnsi "$WorkDir\libsrc\FarAwayLib.pas" @'
unit FarAwayLib;

interface

type
  TFarAwayThing = class
  public
    procedure Apply(AUpdateKind: Integer);
  end;

procedure LibraryOnlyRoutine(AValue: Integer);

implementation

procedure TFarAwayThing.Apply(AUpdateKind: Integer);
begin
end;

procedure LibraryOnlyRoutine(AValue: Integer);
begin
end;

end.
'@

# The stand-in for the active project index. It deliberately does NOT declare
# `Apply`, exactly as DataCopy's index did not.
WriteAnsi "$WorkDir\projsrc\ProjUnit.pas" @'
unit ProjUnit;

interface

type
  TProjectThing = class
  public
    procedure ProjectOwnMethod(ACount: Integer);
  end;

implementation

procedure TProjectThing.ProjectOwnMethod(ACount: Integer);
begin
end;

end.
'@

# THE LOOSE FILE. Indexed by nothing. It declares its OWN Apply, with a
# parameter name (ALooseArg) that appears nowhere else, so an assertion can tell
# the two apart without relying on the qualified name alone.
$looseText = @'
unit LooseUnit;

interface

type
  TLooseThing = class
  public
    procedure Apply(ALooseArg: Integer);
  end;

procedure DriveLoose;

implementation

uses
  FarAwayLib;

procedure TLooseThing.Apply(ALooseArg: Integer);
begin
end;

procedure DriveLoose;
var
  LThing: TLooseThing;
begin
  LThing := TLooseThing.Create;
  LThing.Apply(1);
  LibraryOnlyRoutine(2);
end;

end.
'@
$looseFile = Join-Path $WorkDir 'loose\LooseUnit.pas'
WriteAnsi $looseFile $looseText

$libDb  = Join-Path $WorkDir 'lib.sqlite'
$projDb = Join-Path $WorkDir 'proj.sqlite'
& $Exe index "$WorkDir\libsrc"  --db $libDb  2>&1 | Out-Null
& $Exe index "$WorkDir\projsrc" --db $projDb 2>&1 | Out-Null
Check 'built both fixture indexes' ((Test-Path $libDb) -and (Test-Path $projDb))

# ---- PC2: the premise -- the loose file is in NEITHER database ----
Write-Host ''
Write-Host 'PC2: PREMISE -- the loose unit is indexed by nothing' -ForegroundColor Cyan
$looseInLib  = (& $Exe query --name TLooseThing --db $libDb  --json 2>&1 | Out-String)
$looseInProj = (& $Exe query --name TLooseThing --db $projDb --json 2>&1 | Out-String)
Check 'TLooseThing absent from the library index' ($looseInLib  -notmatch '"name"\s*:\s*"TLooseThing"')
Check 'TLooseThing absent from the project index' ($looseInProj -notmatch '"name"\s*:\s*"TLooseThing"')
$applyInProj = (& $Exe query --name Apply --db $projDb --json 2>&1 | Out-String)
Check 'Apply absent from the project index (as in the real report)' ($applyInProj -notmatch '"name"\s*:\s*"Apply"')

# Positions are 0-based for LSP.
$looseLines = $looseText -split "`r?`n"
$callLine   = [Array]::FindIndex($looseLines, [Predicate[string]]{ param($x) $x -like '*LThing.Apply(1);*' })
$declLine   = [Array]::FindIndex($looseLines, [Predicate[string]]{ param($x) $x -like '*procedure TLooseThing.Apply(*' })
$libOnlyLn  = [Array]::FindIndex($looseLines, [Predicate[string]]{ param($x) $x -like '*LibraryOnlyRoutine(2);*' })
$callCol    = $looseLines[$callLine].IndexOf('Apply') + 2
$declCol    = $looseLines[$declLine].IndexOf('.Apply') + 3
$libOnlyCol = $looseLines[$libOnlyLn].IndexOf('LibraryOnlyRoutine') + 4
Check 'located all three probe positions' `
  (($callLine -ge 0) -and ($declLine -ge 0) -and ($libOnlyLn -ge 0)) `
  "call=$callLine decl=$declLine libonly=$libOnlyLn"

$projFile  = Join-Path $WorkDir 'projsrc\ProjUnit.pas'
$projText  = [System.IO.File]::ReadAllText($projFile)
$projLines = $projText -split "`r?`n"
$projLine  = [Array]::FindIndex($projLines, [Predicate[string]]{ param($x) $x -like '*procedure TProjectThing.ProjectOwnMethod(*' })
$projCol   = $projLines[$projLine].IndexOf('.ProjectOwnMethod') + 3

# The server is given the SAME store order the IDE uses: project first, library
# second. The defect is not about ordering -- the project DB is already first
# and simply has no row for the name.
function Invoke-Hover([string]$File, [int]$Line0, [int]$Char0) {
  $uri  = 'file:///' + ($File -replace '\\', '/')
  $text = [System.IO.File]::ReadAllText($File)
  $msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen';
                    params = @{ textDocument = @{ uri = $uri; languageId = 'pascal'; version = 1; text = $text } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 2; method = 'textDocument/hover';
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $Line0; character = $Char0 } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'shutdown'; params = @{} }

  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'; $errF = Join-Path $WorkDir 'err.txt'
  [System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $projDb, '--db', $libDb) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF `
    -NoNewWindow -Wait | Out-Null

  $raw = [System.IO.File]::ReadAllText($outF)
  $script:LastRaw = $raw
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2) { if ($null -eq $o.result) { return '' } else { return [string]$o.result.contents.value } }
  }
  return '<NO REPLY>'
}

# ---- PC1: the owned path is untouched ----
Write-Host ''
Write-Host 'PC1: POSITIVE CONTROL -- hover in an INDEXED file' -ForegroundColor Cyan
$pc1 = Invoke-Hover $projFile $projLine $projCol
Check 'indexed-file hover resolves the project symbol' `
  ($pc1 -match 'ProjUnit\.TProjectThing\.ProjectOwnMethod') "got: [$pc1]"

# ---- CASE 1: the reported shape -- a call site in the loose file ----
Write-Host ''
Write-Host 'CASE 1: call site in the UNINDEXED file' -ForegroundColor Cyan
$c1 = Invoke-Hover $looseFile $callLine $callCol
Check 'does NOT name the far-away library class' `
  ($c1 -notmatch 'FarAwayLib\.TFarAwayThing\.Apply') "got: [$c1]"
Check 'names the loose unit own Apply' `
  ($c1 -match 'LooseUnit\.TLooseThing\.Apply') "got: [$c1]"
Check 'shows the loose parameter ALooseArg' ($c1 -match 'ALooseArg') "got: [$c1]"

# ---- NC2: stdout hygiene, checked on the very reply that builds the index ----
Write-Host ''
Write-Host 'NC2: NEGATIVE CONTROL -- the ephemeral index must not print to stdout' -ForegroundColor Cyan
Check 'no indexer progress line on the protocol channel' `
  ($script:LastRaw -notmatch '->\s+\d+\s+symbols') `
  'TIndexer.ReportProgress writes to stdout; stdout IS the LSP channel'
Check 'no SKIP/ERROR indexer line on the protocol channel' `
  ($script:LastRaw -notmatch '(?m)^\s+(SKIP|ERROR indexing) ')
Check 'the reply was still a parseable frame' ($c1 -ne '<NO REPLY>') "got: [$c1]"

# ---- CASE 2: the declaration in the loose file ----
Write-Host ''
Write-Host 'CASE 2: declaration in the UNINDEXED file' -ForegroundColor Cyan
$c2 = Invoke-Hover $looseFile $declLine $declCol
Check 'declaration hover does NOT name the library class' `
  ($c2 -notmatch 'FarAwayLib\.TFarAwayThing\.Apply') "got: [$c2]"
Check 'declaration hover names the loose Apply' `
  ($c2 -match 'LooseUnit\.TLooseThing\.Apply') "got: [$c2]"

# ---- NC1: the library must remain reachable from the loose file ----
Write-Host ''
Write-Host 'NC1: NEGATIVE CONTROL -- library-only name, hovered in the loose file' -ForegroundColor Cyan
$nc1 = Invoke-Hover $looseFile $libOnlyLn $libOnlyCol
Check 'library-only routine still resolves from an unindexed file' `
  ($nc1 -match 'FarAwayLib\.LibraryOnlyRoutine') "got: [$nc1]"

# ---- CASE 3: nothing was written into the user's source tree ----
Write-Host ''
Write-Host 'CASE 3: the loose file and its folder were not modified' -ForegroundColor Cyan
$after = [System.IO.File]::ReadAllText($looseFile)
Check 'loose source byte-identical after hovering' `
  ($after -eq (($looseText -replace "`r`n", "`n") -replace "`n", "`r`n"))
$strays = @(Get-ChildItem "$WorkDir\loose" -File | Where-Object { $_.Name -ne 'LooseUnit.pas' })
Check 'no ephemeral database dropped beside the user source' `
  ($strays.Count -eq 0) "found: $($strays.Name -join ',')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
