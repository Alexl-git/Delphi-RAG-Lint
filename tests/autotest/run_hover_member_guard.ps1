<#
  run_hover_member_guard.ps1 -- hovering a MEMBER reached through a variable
  must describe THAT member, and must keep describing it when the name is one
  the library declares dozens of times.

  THE REPORT THIS PINS (owner, 2026-08-18, live IDE on
  C:\Projects\DataCopy\EExtraExceptionInfo.pas:480):

      var S:= AExceptionInfo.Assign

  RAD Studio's own Help Insight described it correctly --
  "procedure TEurekaExceptionInfo.Assign(ASource: TPersistent) - EException.pas
  (3079)" with a Parameters section -- while drag-lint's popup showed only the
  lint finding for that line ("Local "s" is assigned but never read.") and no
  explanation of Assign at all.

  `Assign` is the hard case on purpose. It is not a rare name: TPersistent,
  TStrings, TGraphic, TCollection and hundreds of other library classes declare
  one, so a hover that resolves by NAME rather than by the LHS's declared TYPE
  has ~hundreds of equally-good wrong answers to choose from. Case 2 makes the
  fixture library carry decoy Assign methods for exactly that reason: a build
  that returns "an Assign" passes a naive assertion, so the assertions below
  check WHICH Assign came back (its owning type, and its parameter), never just
  that something came back.

  POSITIVE CONTROL: case 4 hovers a member whose name is unique in the fixture.
  If the guard ever goes green while case 4 is silently returning null, the
  harness itself is broken -- so case 4 failing is the signal that the probe,
  not the engine, needs fixing.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-member-guard"
)
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
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 10
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$libDir = Join-Path $WorkDir 'lib';   New-Item -ItemType Directory $libDir   | Out-Null
$appDir = Join-Path $WorkDir 'app';   New-Item -ItemType Directory $appDir   | Out-Null

# ---------------------------------------------------------------- fixtures --
# THolderBase.Assign is the one the hover must find. The three decoys share its
# name and differ in signature, so an answer can be checked for correctness and
# not merely for existence. They are declared BEFORE it so that any "first name
# match wins" implementation picks a decoy and the guard goes red.
WriteAnsi (Join-Path $libDir 'HoverLib.pas') @'
unit HoverLib;

interface

type
  TDecoyOne = class
  public
    procedure Assign(ADecoyOne: Integer);
  end;

  TDecoyTwo = class
  public
    procedure Assign(ADecoyTwo: string);
  end;

  TDecoyThree = class
  public
    procedure Assign(ADecoyThree: Boolean);
  end;

  TSourceThing = class
  public
    SourceMark: Integer;
  end;

  THolderBase = class
  public
    procedure Assign(ASource: TSourceThing);
  end;

  THolder = class(THolderBase)
  public
    procedure UniqueMemberNameZZ;
  end;

implementation

procedure TDecoyOne.Assign(ADecoyOne: Integer);
begin
end;

procedure TDecoyTwo.Assign(ADecoyTwo: string);
begin
end;

procedure TDecoyThree.Assign(ADecoyThree: Boolean);
begin
end;

procedure THolderBase.Assign(ASource: TSourceThing);
begin
end;

procedure THolder.UniqueMemberNameZZ;
begin
end;

end.
'@

# The editing shape from the report: the member sits MID-LINE with a semicolon
# after it, and the LHS is a local variable, not a type name.
WriteAnsi (Join-Path $appDir 'HoverApp.pas') @'
unit HoverApp;

interface

procedure UseHolder;

implementation

uses
  HoverLib;

procedure UseHolder;
var
  Holder: THolder;
  Src: TSourceThing;
begin
  Holder.Assign(Src);
  Holder.UniqueMemberNameZZ;
end;

end.
'@

$appFile = Join-Path $appDir 'HoverApp.pas'
$lines   = [System.IO.File]::ReadAllLines($appFile)

function LineIndexOf([string]$needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($needle)) { return $i } }
  return -1
}

# 0-based line, and a 0-based column sitting INSIDE the member identifier.
$assignLine = LineIndexOf 'Holder.Assign(Src);'
$assignCol  = $lines[$assignLine].IndexOf('Assign') + 3      # mid-identifier
$uniqLine   = LineIndexOf 'Holder.UniqueMemberNameZZ;'
$uniqCol    = $lines[$uniqLine].IndexOf('UniqueMemberNameZZ') + 5
Check 'located the "Holder.Assign(Src);" probe' ($assignLine -ge 0) "line0=$assignLine col0=$assignCol"
Check 'located the "Holder.UniqueMemberNameZZ;" probe' ($uniqLine -ge 0) "line0=$uniqLine col0=$uniqCol"
if ($assignLine -lt 0 -or $uniqLine -lt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

function Get-HoverValue([string[]]$Dbs, [int]$Line0, [int]$Char0) {
  $a = @('lsp'); foreach ($d in $Dbs) { $a += '--db'; $a += $d }
  $uri = 'file:///' + ($appFile -replace '\\', '/')
  $msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 2; method = 'textDocument/hover';
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $Line0; character = $Char0 } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'shutdown'; params = @{} }

  $inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'; $errF = Join-Path $WorkDir 'err.txt'
  [System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList $a -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF `
    -NoNewWindow -Wait | Out-Null

  $raw = [System.IO.File]::ReadAllText($outF)
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2) {
      if ($null -eq $o.result) { return '' }
      return [string]$o.result.contents.value
    }
  }
  return '<no-reply>'
}

# ---- case 1: single index holding everything ----
Write-Host ''
Write-Host 'CASE 1: member hover through a variable, one index' -ForegroundColor Cyan
$db1 = Join-Path $WorkDir 'both.sqlite'
& $Exe index $WorkDir --db $db1 2>&1 | Out-Null
Check 'built the combined index' (Test-Path $db1)

$h1 = Get-HoverValue @($db1) $assignLine $assignCol
Check 'hover returned something at all' ($h1 -ne '' -and $h1 -ne '<no-reply>') "got: [$h1]"
Check 'names the OWNING type THolderBase' ($h1 -match 'THolderBase') "got: [$h1]"
Check 'shows the real parameter ASource'  ($h1 -match 'ASource')     "got: [$h1]"
# The discriminating half: a decoy would also satisfy "mentions Assign".
Check 'did NOT resolve to a decoy Assign' `
  (($h1 -notmatch 'TDecoyOne') -and ($h1 -notmatch 'TDecoyTwo') -and ($h1 -notmatch 'TDecoyThree')) `
  "got: [$h1]"
Check 'did not report a decoy parameter' `
  (($h1 -notmatch 'ADecoyOne') -and ($h1 -notmatch 'ADecoyTwo') -and ($h1 -notmatch 'ADecoyThree')) `
  "got: [$h1]"

# ---- case 2: declaring type in a DIFFERENT index ----
# The real report had the variable in a project index and its class only in
# library-Win64.sqlite. Completion had this exact defect (single-store lookup);
# hover shares the resolver, so it is asserted here rather than assumed.
Write-Host ''
Write-Host 'CASE 2: declaring type in a SEPARATE index' -ForegroundColor Cyan
$dbL = Join-Path $WorkDir 'lib.sqlite'
$dbA = Join-Path $WorkDir 'app.sqlite'
& $Exe index $libDir --db $dbL 2>&1 | Out-Null
& $Exe index $appDir --db $dbA 2>&1 | Out-Null
Check 'built both split indexes' ((Test-Path $dbL) -and (Test-Path $dbA))
# app db FIRST -- the plugin orders project-then-library.
$h2 = Get-HoverValue @($dbA, $dbL) $assignLine $assignCol
Check 'cross-store hover returned something' ($h2 -ne '' -and $h2 -ne '<no-reply>') "got: [$h2]"
Check 'cross-store names THolderBase' ($h2 -match 'THolderBase') "got: [$h2]"
Check 'cross-store did NOT resolve to a decoy' `
  (($h2 -notmatch 'TDecoy')) "got: [$h2]"

# ---- case 3: the caret is mid-identifier, not at its start ----
# Hovering lands wherever the pointer is. Completion had an off-by-one that only
# showed up once the caret stopped sitting at end-of-line; the equivalent here is
# a caret in the middle of the name.
Write-Host ''
Write-Host 'CASE 3: caret at the START and at the END of the identifier' -ForegroundColor Cyan
$startCol = $lines[$assignLine].IndexOf('Assign')
$endCol   = $startCol + 'Assign'.Length - 1
$hStart = Get-HoverValue @($db1) $assignLine $startCol
$hEnd   = Get-HoverValue @($db1) $assignLine $endCol
Check 'hover at the first char resolves THolderBase' ($hStart -match 'THolderBase') "got: [$hStart]"
Check 'hover at the last char resolves THolderBase'  ($hEnd   -match 'THolderBase') "got: [$hEnd]"

# ---- case 4: POSITIVE CONTROL ----
# A member whose name is unique in the fixture. If this one fails, the probe is
# broken and every other result above is meaningless.
Write-Host ''
Write-Host 'CASE 4: POSITIVE CONTROL -- unambiguous member name' -ForegroundColor Cyan
$h4 = Get-HoverValue @($db1) $uniqLine $uniqCol
Check 'unique member hover returns content' ($h4 -ne '' -and $h4 -ne '<no-reply>') "got: [$h4]"
Check 'unique member names UniqueMemberNameZZ' ($h4 -match 'UniqueMemberNameZZ') "got: [$h4]"

# ---- case 5: NEGATIVE CONTROL ----
Write-Host ''
Write-Host 'CASE 5: NEGATIVE CONTROL -- whitespace resolves to nothing' -ForegroundColor Cyan
$blankCol = $lines[$assignLine].Length - 1
$h5 = Get-HoverValue @($db1) $assignLine $blankCol
Check 'hovering the trailing semicolon yields no symbol' `
  (($h5 -eq '') -or ($h5 -notmatch 'THolderBase')) "got: [$h5]"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
