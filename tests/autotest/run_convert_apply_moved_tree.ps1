<#
  run_convert_apply_moved_tree.ps1 -- convert-apply on a source tree that was
  MOVED or COPIED after it was indexed (1.26.5-alpha).

  THE DEFECT (1.26.2 acceptance run): a copy of an r=1.11 DMTEST.sqlite, whose
  files table holds the ORIGINAL paths, was used against a copied source tree.
  convert-apply found the unit's symbols (FindSymbolsByFile resolves a path
  TOLERANTLY -- a unique basename is accepted), so the .dfm instances
  converted; but three other lookups asked for the file id by EXACT path and
  got none:
    * the stale-resolver refusal looked for "the --db that holds the unit",
      matched no DB, and was skipped -- exit 0 on an r=1.11 DB;
    * BuildApplyPlan's file id for the unit's references was 0, so every
      access site and creator site was silently skipped (access_sites 0);
    * FindInheritedCodeUses (C8 N2a) found no file and listed nothing.
  All of them now resolve the unit's file the way its symbols were found.

  THE CONTRACT this guard pins:
    M1 moved tree + r=1.11 stamp on the DB: REFUSED (exit 1), naming the DB.
    M2 positive control, the same moved tree on an up-to-date DB: converts,
       and its access site IS rewritten (refs found through the moved path).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_moved_tree_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$A = Join-Path $WorkDir 'indexed'
$B = Join-Path $WorkDir 'moved'
New-Item -ItemType Directory $A, $B | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $A 'LibA.pas') @'
unit LibA;

interface

uses
  System.Classes;

type
  TSrcA = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $A 'LibB.pas') @'
unit LibB;

interface

uses
  System.Classes;

type
  TDstB = class(TComponent)
  private
    FTitle: string;
  published
    property Title: string read FTitle write FTitle;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $A 'MovedDM.pas') @'
unit MovedDM;

interface

uses
  System.Classes, LibA;

type
  TMovedDM = class(TDataModule)
    mbtn: TSrcA;
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TMovedDM.Touch;
begin
  mbtn.Caption := 'moved';
end;

end.
'@
Write-Ascii (Join-Path $A 'MovedDM.dfm') @'
object MovedDM: TMovedDM
  object mbtn: TSrcA
    Caption = 'm'
  end
end
'@
Write-Ascii (Join-Path $WorkDir 'mv.rules') @'
#convert LibA.TSrcA -> LibB.TDstB, LibB
#link Title <- Caption
'@

$db = Join-Path $WorkDir 'fx.sqlite'
$idx = & $Exe index $A --db $db 2>&1
Check 'V the fixture index was built over the ORIGINAL folder' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"
# move the tree: the DB keeps the old paths
Copy-Item (Join-Path $A '*') $B
Remove-Item -Recurse -Force $A
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}

$py = 'C:\Python314\python.exe'
if (-not (Test-Path $py)) {
  Check 'M0 python (to age the resolver stamp of a DB copy) is available' $false "missing: $py"
} else {
  $old = Join-Path $WorkDir 'old.sqlite'
  Copy-Item $db $old
  & $py -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute(""UPDATE schema_meta SET value='r=1.11.0-alpha;schema=23' WHERE key='resolver_fingerprint'""); c.commit(); c.close()" $old
  $o = (& $Exe convert-apply --unit (Join-Path $B 'MovedDM.pas') --rules (Join-Path $WorkDir 'mv.rules') --db $old --format json 2>&1) -join "`n"; $code = $LASTEXITCODE
  $j = Json $o
  Check 'M1 moved tree, r=1.11 DB that stores OTHER paths: REFUSED (exit 1), the reason names that DB' `
    (($code -eq 1) -and ($null -ne $j) -and ($j.refused -eq $true) -and ($j.reason -match [regex]::Escape($old) + ': edges were derived by resolver 1\.11\.0-alpha')) $o
}
$o = (& $Exe convert-apply --unit (Join-Path $B 'MovedDM.pas') --rules (Join-Path $WorkDir 'mv.rules') --db $db --format json 2>&1) -join "`n"; $code = $LASTEXITCODE
$j = Json $o
Check 'M2 positive control, the same moved tree on an up-to-date DB: converts, and the access site IS rewritten (refs found)' `
  (($code -eq 0) -and ($null -ne $j) -and $j.ok -and (@($j.converted).Count -eq 1) -and (@($j.access_sites | Where-Object { $_ -match '^mbtn\.Caption -> mbtn\.Title' }).Count -eq 1) -and `
   ($j.access_sites_unverified -eq 0)) $o

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_moved_tree_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
