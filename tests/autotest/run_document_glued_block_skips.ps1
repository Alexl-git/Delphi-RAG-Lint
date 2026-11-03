<#
  run_document_glued_block_skips.ps1 -- DOC-APPLY-GLUED (BACKLOG-2026-11-01).

  THE DEFECT. A /// block glued onto the end of the previous declaration's line
  (`procedure Alpha;  /// <summary>Beta...`) is scanned as a region that STARTS ON
  that code line. `document --qname Beta --apply` therefore planned
  `delete lines 9..11` beginning on Alpha's declaration. The write-guard refused
  it (nothing lost) but exited 3 with "defect, please report".

  CONTRACT. The documenter SKIPS a declaration whose doc block starts on a line
  that also holds code: it names the line on stderr, writes nothing, exits 0.
  The neighbour (Alpha, own block on its own lines) is still documented.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_doc_glued_apply_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$u = Join-Path $WorkDir 'uGlue.pas'
Write-Ascii $u @"
unit uGlue;

interface

type
  TStore = class
  public
    /// <summary>AlphaOwnDoc text.</summary>
    procedure Alpha;      /// <summary>BetaOwnDoc text,
    /// continued here.</summary>
    /// <param name="X">The x.</param>
    procedure Beta(X: Integer);
  end;

implementation

procedure TStore.Alpha;
begin
end;

procedure TStore.Beta(X: Integer);
begin
  Alpha;
end;

end.
"@
$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $WorkDir --db $db 2>&1 | Out-Null
$before = [IO.File]::ReadAllText($u)

$o = (& $exePath document --qname uGlue.TStore.Beta --db $db --apply --no-backup 2>&1) -join "`n"
$code = $LASTEXITCODE
Check 'T1 document Beta (glued block) exits 0, not the REFUSED defect exit' ($code -eq 0) "exit $code : $o"
Check 'T2 the skip is reported, naming the line' ($o -match 'skipped uGlue\.TStore\.Beta.*line 9') $o
Check 'T3 nothing was written for the glued declaration' ([IO.File]::ReadAllText($u) -eq $before) ''

$o2 = (& $exePath document --qname uGlue.TStore.Alpha --db $db --apply --no-backup 2>&1) -join "`n"
$after = [IO.File]::ReadAllText($u)
Check 'P1 POSITIVE CONTROL the neighbour with its own block is still documented' `
      (($LASTEXITCODE -eq 0) -and ($after -ne $before) -and ($after -match 'procedure Alpha;\s+/// <summary>BetaOwnDoc')) $o2
Check 'T4 the glued block and the code line survive' (($after -match 'BetaOwnDoc') -and ($after -match 'procedure Alpha;') -and ($after -match 'procedure Beta\(X: Integer\);')) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}