<#
  run_doc_no_self_caller.ps1 -- Bug C regression: FindUnresolvedNameCallers
  (DRagLint.Storage.SQLite.pas) must NOT surface a class's OWN method-header
  self-reference as a "Called from:" caller.

  ROOT CAUSE (fixed by this test): a qualified implementation header like
  'procedure TThing.Add;' emits a type_use ref of name_text='TThing' whose
  enclosing_symbol_id is the method itself (TThing.Add). Before the fix,
  FindUnresolvedNameCallers(AName='TThing') name-matched that ref and
  returned TThing.Add as a spurious caller of the CLASS TThing -- EVERY
  class with an implemented method acquired this false fact.

  Fixture (single unit, uNoSelfCaller.pas):
    - TThing: a class with ONE implemented method, Add (no params/body work,
      just 'begin end;'). Its own qualified impl header
      'procedure TThing.Add;' is the spurious self-reference source.
    - UseThing: a top-level procedure OUTSIDE TThing that declares
      'T: TThing;' and calls 'T := TThing.Create; T.Add;' -- a GENUINE
      external reference to TThing (enclosing routine UseThing has no
      parent type), proving the fix does not overreach and still keeps
      real callers.

  Asserts (after `document --qname uNoSelfCaller.TThing --apply --no-backup`,
  reading the written file):
    1. exit 0.
    2. TThing acquires a managed block (it has a genuine 'Called from:'
       fact via UseThing, so facts-only does not skip it).
    3. The "Called from:" line is present and names UseThing (the real,
       external caller is KEPT).
    4. The "Called from:" line does NOT name TThing.Add (the class's own
       method -- a self-reference, never a meaningful caller).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-no-self-caller); a fresh
  copy + a TEMP db (never a real corpus db).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-no-self-caller"
)
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$FixtureBody = @'
unit uNoSelfCaller;
interface
type
  TThing = class
  public
    procedure Add;
  end;
procedure UseThing;
implementation
procedure TThing.Add;
begin
end;
procedure UseThing;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Add;
end;
end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$dir  = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
$file = Join-Path $dir 'uNoSelfCaller.pas'
$db   = Join-Path $dir 'fx.sqlite'
Write-Fixture $file

& $Exe index $dir --db $db 2>&1 | Out-Null
Push-Location $dir
try {
  & $Exe document --qname uNoSelfCaller.TThing --db $db --apply --no-backup 2>&1 | Out-Null
  $ec = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'document --qname exit 0' ($ec -eq 0) "ec=$ec"

$lines = [IO.File]::ReadAllLines($file)
$clsIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'TThing\s*=\s*class') { $clsIdx = $i; break } }
Check 'TThing class decl found' ($clsIdx -ge 0)

# Walk upward from the class decl collecting the contiguous '///' block
# directly above it (same scan-upward idiom run_doc_cheap_facts.ps1 uses).
$block = ''
if ($clsIdx -ge 1) {
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $clsIdx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $lines[$i])
  }
  $block = [string]::Join("`n", $blockLines.ToArray())
}

Write-Host 'TThing class block: genuine caller kept, self-reference excluded' -ForegroundColor Cyan
Check 'TThing has a managed block (AUTO_BEGIN)' ($block -match '<!-- drag-lint:auto BEGIN -->') $block
Check 'TThing has a "Called from:" line' ($block -match 'Called from:') $block
Check 'Called from: names UseThing (real external caller kept)' ($block -match 'Called from:.*UseThing') $block
Check 'Called from: does NOT name TThing.Add (own method, self-reference excluded)' `
  (-not ($block -match 'Called from:[^\r\n]*TThing\.Add\b')) $block

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
