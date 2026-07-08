<#
  run_rename_implheader.ps1 -- Batch D Task 2 (A): the standalone `rename`
  verb (TRenameRefactoring.Build, driven from the CLI's --qname/--apply
  path -- NOT lint-all --fix / NamingFix) must also rewrite a method's
  separate `implementation`-section header (`procedure TThing.DoIt;`), not
  just the interface declaration and call sites.

  This is the bug the task promotes a fix for: TRenameRefactoring.Build's
  declaration-site edit uses Sym.StartLine/StartCol (the INTERFACE decl),
  and its reference-sites loop only covers FindCallersByName rows (actual
  call sites) -- neither touches ImplStartLine, the impl header's own line.
  Before the fix: interface decl + call site rename correctly, but the impl
  header is left stale (still `TThing.DoIt`), which would not compile.

  FIXTURE (u1.pas): a class TThing with method DoIt declared in `interface`
  and defined (separately) in `implementation`, plus a call site in a
  second routine.

  Run: drag-lint rename --qname u1.TThing.DoIt --to DoItNow --db <db> --apply
  ASSERT:
    - interface decl   'procedure DoItNow;'      (was DoIt)
    - impl header       'procedure TThing.DoItNow;' (was TThing.DoIt)  <- the bug
    - call site         't.DoItNow;'              (was t.DoIt)
    - no stale 'DoIt' (case-sensitive, whole-token via negative regex) remains
      anywhere in the file.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-rename-implheader by default),
  mirrors run_deps_report.ps1 / run_naming_autofix.ps1 scaffolding.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-implheader"
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
# Absolutize so the exe path survives regardless of CWD (mirrors run_deps_report.ps1 / run_naming_autofix.ps1).
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# tree-sitter Win64 DLLs must sit beside the exe (mirrors run_naming_autofix.ps1).
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
$u1File = Join-Path $src 'u1.pas'
$db     = Join-Path $WorkDir 'rename.sqlite'

$Fixture = @'
unit u1;

interface

type
  TThing = class
  public
    procedure DoIt;
  end;

procedure UseIt;

implementation

procedure TThing.DoIt;
begin
end;

procedure UseIt;
var
  t: TThing;
begin
  t:= TThing.Create;
  try
    t.DoIt;
  finally
    t.Free;
  end;
end;

end.
'@
Write-Ascii $u1File $Fixture

Write-Host 'Indexing fixture' -ForegroundColor Cyan
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)
Check 'db built' (Test-Path $db)

Write-Host ''
Write-Host 'rename --qname u1.TThing.DoIt --to DoItNow --apply' -ForegroundColor Cyan
$out = & $Exe rename --qname u1.TThing.DoIt --to DoItNow --db $db --apply 2>&1
$exit = $LASTEXITCODE
Write-Host ($out -join "`n")
Check 'rename exits 0' ($exit -eq 0) "exit=$exit"

$after = Get-Content -Raw $u1File
# -cmatch/-cnotmatch: CASE-SENSITIVE (PowerShell's plain -match is
# case-insensitive by default, which would silently pass on a still-stale
# 'DoIt' impl header sharing letters with 'DoItNow').
Check 'interface declaration renamed to DoItNow'        ($after -cmatch 'procedure\s+DoItNow;')
Check 'implementation header renamed to TThing.DoItNow (the bug)' ($after -cmatch 'procedure\s+TThing\.DoItNow;')
Check 'call site renamed to t.DoItNow'                   ($after -cmatch 't\.DoItNow;')
Check 'no stale TThing.DoIt impl header remains'         (-not ($after -cmatch 'TThing\.DoIt;'))
Check 'no stale t.DoIt call site remains'                (-not ($after -cmatch 't\.DoIt;'))
Check 'no stale interface "procedure DoIt;" decl remains' (-not ($after -cmatch 'procedure\s+DoIt;'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
