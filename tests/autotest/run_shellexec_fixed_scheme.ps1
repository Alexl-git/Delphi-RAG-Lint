<#
  run_shellexec_fixed_scheme.ps1 -- `unsafe-shellexecute` and the FIXED-SCHEME
  URI exemption.

  THE FALSE POSITIVE. The rule asked one syntactic question -- "is the command
  argument a literalString?" -- and answered `error` for everything else. That
  reported CWE-78 on the standard way to open a URL, including this, in
  drag-lint's own DoObsidian:

      Uri := 'obsidian://open?vault=' + TNetEncoding.URL.Encode(BaseName);
      ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);

  where the argument had ALREADY been hardened for this rule -- the encode call
  exists because of it -- and the finding fired anyway. A rule whose advice has
  been followed and which still fires teaches people to switch it off. It was
  the only `error` in the repo.

  THE PRINCIPLE, not a heuristic. CWE-78 is about the attacker choosing WHAT
  RUNS. With a hardcoded URI scheme the program is chosen by the OS registration
  for that scheme; the variable part lands in the path/query of a URI whose
  handler is already decided.

  `file:` IS EXCLUDED from the exemption and that is the whole reason this is
  scheme-aware rather than "starts with a literal" -- `file://` + user data lets
  the caller pick any file, and the program that runs is then chosen by that
  file's EXTENSION, which is exactly what the rule exists to catch.

  ONE ASSIGNMENT, ROUTINE-SCOPED. File-wide counting was tried first and is
  wrong in the direction that matters: `Uri` / `Cmd` / `S` are assigned once per
  routine in many routines, so a file-wide count is >1 everywhere and the
  exemption never applies to the code it was written for. Measured on this exact
  fixture -- five of six cases behaved and the one real-world shape did not.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

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

$W = Join-Path $env:TEMP 'drag-lint-shellexec-scheme'
if (Test-Path $W) { Remove-Item -Recurse -Force -LiteralPath $W }
New-Item -ItemType Directory $W | Out-Null
$fixture = Join-Path $W 'uShellScheme.pas'

$body = @'
unit uShellScheme;

interface

implementation

uses Winapi.Windows, Winapi.ShellAPI, System.NetEncoding;

procedure Safe_FixedScheme(const Name: string);
var Uri: string;
begin
  Uri := 'obsidian://open?vault=' + TNetEncoding.URL.Encode(Name);
  ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);
end;

procedure Safe_HttpsInline(const Q: string);
begin
  ShellExecute(0, 'open', PChar('https://example.com/?q=' + Q), nil, nil, SW_SHOWNORMAL);
end;

procedure Unsafe_FileScheme(const P: string);
var Uri: string;
begin
  Uri := 'file://' + P;
  ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);
end;

procedure Unsafe_BareVariable(const P: string);
begin
  ShellExecute(0, 'open', PChar(P), nil, nil, SW_SHOWNORMAL);
end;

procedure Unsafe_ExeConcat(const P: string);
var Cmd: string;
begin
  Cmd := 'cmd.exe /c ' + P;
  ShellExecute(0, 'open', PChar(Cmd), nil, nil, SW_SHOWNORMAL);
end;

procedure Unsafe_Reassigned(const P: string);
var Uri: string;
begin
  Uri := 'obsidian://open?vault=x';
  Uri := P;
  ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);
end;

end.
'@
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

# Resolve each ShellExecute line from the fixture so edits cannot decouple them.
$lines = [System.IO.File]::ReadAllLines($fixture)
function ShellLineIn([string]$ProcName) {
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match ("^procedure {0}\b" -f [regex]::Escape($ProcName))) { $start = $i; break }
  }
  if ($start -lt 0) { return -1 }
  for ($i = $start; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'ShellExecute\(') { return $i + 1 } }
  return -1
}
$lnSafeScheme  = ShellLineIn 'Safe_FixedScheme'
$lnSafeInline  = ShellLineIn 'Safe_HttpsInline'
$lnFileScheme  = ShellLineIn 'Unsafe_FileScheme'
$lnBareVar     = ShellLineIn 'Unsafe_BareVariable'
$lnExeConcat   = ShellLineIn 'Unsafe_ExeConcat'
$lnReassigned  = ShellLineIn 'Unsafe_Reassigned'
Check 'all six fixture call sites located' (
  @($lnSafeScheme,$lnSafeInline,$lnFileScheme,$lnBareVar,$lnExeConcat,$lnReassigned) -notcontains -1)

$fired = @()
foreach ($line in (& $Exe lint $fixture 2>$null)) {
  if ($line -match 'unsafe-shellexecute' -and $line -match ':(\d+):') { $fired += [int]$Matches[1] }
}
Write-Host ("  fired on lines: {0}" -f ($fired -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'A hardcoded non-file URI scheme MUST NOT fire' -ForegroundColor Cyan
Check "obsidian:// via a local (line $lnSafeScheme)" (-not ($fired -contains $lnSafeScheme)) `
  'the real DoObsidian shape -- routine-scoped single assignment'
Check "https:// concatenated inline (line $lnSafeInline)" (-not ($fired -contains $lnSafeInline))

Write-Host ''
Write-Host 'A runtime lpFile with NO command line is now SILENT (owner ruling 2026-08-27)' -ForegroundColor Cyan

# THIS SECTION USED TO REQUIRE THESE THREE TO FIRE, and the reasoning was:
# "everything that can still choose the program MUST fire" -- a runtime path can
# name an executable (CWE-73/427) even when no arguments are appended.
#
# That reasoning was never refuted. The owner overruled it on cost: there is NO
# AST difference between `PChar(FConfigService.DataFolder)` -- how every Delphi
# program opens a folder in Explorer -- and `PChar(P)`. The rule therefore fired
# `error` on the benign idiom everywhere, and a security rule that cries wolf on
# an everyday call is one people switch off. Per the standing standard, a large
# finding count IS the defect, and the fix belongs in the rule.
#
# WHAT IS GIVEN UP, recorded so nobody rediscovers it as a surprise: a
# ShellExecute that opens an attacker-controlled PATH with a plain verb and no
# parameters is no longer reported. What is NOT given up is on the next block --
# anything that can actually carry a command line.
Check "file:// + data (line $lnFileScheme) is now silent" (-not ($fired -contains $lnFileScheme)) `
  'a runtime path with nil lpParameters carries no command line'
Check "a bare variable (line $lnBareVar) is now silent"   (-not ($fired -contains $lnBareVar))
Check "reassigned after a safe value (line $lnReassigned) is now silent" (-not ($fired -contains $lnReassigned)) `
  'the scheme exemption no longer decides anything for lpFile'

Write-Host ''
Write-Host 'A COMMAND LINE still MUST fire -- this is the control on the block above' -ForegroundColor Cyan

# Without this the section above is satisfied by a rule that reports nothing at
# all. Unsafe_ExeConcat hides its arguments INSIDE lpFile (`cmd.exe /c ` + data),
# which is exactly the shape nil-lpParameters cannot vouch for, and it is the one
# case of the original four that survives the ruling.
Check "'cmd.exe /c ' + data (line $lnExeConcat) STILL fires" ($fired -contains $lnExeConcat) `
  'lpFile names an interpreter, so the arguments are inside it'
Write-Host ''
if ($script:Failed) { Write-Host 'run_shellexec_fixed_scheme: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_shellexec_fixed_scheme: OK' -ForegroundColor Green
exit 0
