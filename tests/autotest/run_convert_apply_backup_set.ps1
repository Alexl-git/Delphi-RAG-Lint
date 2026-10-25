<#
  run_convert_apply_backup_set.ps1 -- the .pas that convert-apply STAMPS is in
  the backup / pre-check / recovery set even when no edit touches it (deep
  review F7, docs\INBOX-2026-10-25-converter-to-engine-deep-review-dl.md).

  THE DEFECT. PerformApplyWrites collected the touched files from the edit set,
  pre-checked, backed up and recorded THOSE, and only afterwards added the unit
  .pas -- which PrependConvertComment then rewrites. A unit whose only edits are
  in the .dfm (here: a .dfm object with no field in the .pas) got its .pas
  rewritten with no .BCK, no recovery.txt line and a stamp reading
  "backup:  / <dfm.BCK1>"; a READ-ONLY .pas was found only after the .dfm had
  been written (rolled back, but with a .BCK and a recovery record left behind).

  WHAT THIS ASSERTS
    B1 --apply: exit 0, the .dfm converted (positive control: a real write)
    B2 OnlyDfm.pas.BCK1 exists and equals the ORIGINAL .pas bytes
    B3 recovery.txt maps OnlyDfm.pas -> OnlyDfm.pas.BCK1
    B4 the stamp's backup field names the .pas backup (not empty)
    B5 CONTROL the .dfm is still backed up and recorded
    R1 read-only .pas with backups: refused BEFORE any write -- exit 2,
       "read-only", both files byte-identical, NO .BCK, no recovery.txt
    R2 CONTROL read-only .pas under --no-backup: the .pas is not written (no
       stamp), so it is not pre-checked -- exit 0, .dfm converted, .pas intact

  RED-CHECK (2026-10-25, against 6511fe41): B2, B3, B4, R1 FAIL; B1, B5, R2 PASS.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_backup_set_$PID"
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

function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Fixture([string]$Dir) {
  if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir }
  New-Item -ItemType Directory $Dir | Out-Null
  Write-Ascii "$Dir\LibA.pas" "unit LibA;`ninterface`nuses System.Classes;`ntype`n  TSrcTable = class(TComponent)`n  private`n    FCaption: string;`n  published`n    property Caption: string read FCaption write FCaption;`n  end;`nimplementation`nend.`n"
  Write-Ascii "$Dir\LibB.pas" "unit LibB;`ninterface`nuses System.Classes;`ntype`n  TDstTable = class(TComponent)`n  private`n    FTitle: string;`n  published`n    property Title: string read FTitle write FTitle;`n  end;`nimplementation`nend.`n"
  # LibB is already used and the .dfm object has no field: every edit is in the .dfm
  Write-Ascii "$Dir\OnlyDfm.pas" "unit OnlyDfm;`n`ninterface`n`nuses`n  System.Classes, LibA, LibB;`n`ntype`n  TOnlyDfm = class(TDataModule)`n  end;`n`nimplementation`n`n{`$R *.dfm}`n`nend.`n"
  Write-Ascii "$Dir\OnlyDfm.dfm" "object OnlyDfm: TOnlyDfm`n  object tbl: TSrcTable`n    Caption = 't'`n  end`nend`n"
  Write-Ascii "$Dir\r.rules" "#convert LibA.TSrcTable -> LibB.TDstTable, LibB`n#link Title <- Caption`n"
  $o = & $Exe index $Dir --db "$Dir\fx.sqlite" 2>&1
  if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: fixture index failed: $($o -join ' | ')" -ForegroundColor Red; exit 2 }
}
function Apply([string]$Dir, [string[]]$Extra) {
  $o = (& $Exe convert-apply --unit "$Dir\OnlyDfm.pas" --rules "$Dir\r.rules" --db "$Dir\fx.sqlite" --apply @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function FHash([string]$p) { return (Get-FileHash $p).Hash }

# ---- B: a .dfm-only conversion with backups ----
$d = "$WorkDir\b"
Fixture $d
$pasOrig = FHash "$d\OnlyDfm.pas"
$r = Apply $d @()
Check 'B1 --apply: exit 0 and the .dfm converted' (($r.Code -eq 0) -and ((Get-Content "$d\OnlyDfm.dfm" -Raw) -match 'object tbl: TDstTable')) $r.Out
Check 'B2 OnlyDfm.pas.BCK1 exists and equals the original .pas' `
  ((Test-Path "$d\OnlyDfm.pas.BCK1") -and ((FHash "$d\OnlyDfm.pas.BCK1") -eq $pasOrig)) ((Get-ChildItem $d -Name) -join ', ')
$rec = if (Test-Path "$d\recovery.txt") { Get-Content "$d\recovery.txt" -Raw } else { '' }
Check 'B3 recovery.txt maps OnlyDfm.pas -> OnlyDfm.pas.BCK1' ($rec -match 'OnlyDfm\.pas -> \S*OnlyDfm\.pas\.BCK1') $rec
$stamp = (Get-Content "$d\OnlyDfm.pas" -TotalCount 2) -join "`n"
Check 'B4 the stamp''s backup field names the .pas backup' ($stamp -match '//   backup: \S*OnlyDfm\.pas\.BCK1 / \S*OnlyDfm\.dfm\.BCK1 ; rules: ') $stamp
Check 'B5 CONTROL the .dfm is backed up and recorded too' `
  ((Test-Path "$d\OnlyDfm.dfm.BCK1") -and ($rec -match 'OnlyDfm\.dfm -> \S*OnlyDfm\.dfm\.BCK1')) $rec

# ---- R: a read-only .pas ----
$d = "$WorkDir\r"
Fixture $d
$hp = FHash "$d\OnlyDfm.pas"; $hd = FHash "$d\OnlyDfm.dfm"
Set-ItemProperty "$d\OnlyDfm.pas" -Name IsReadOnly -Value $true
$r = Apply $d @()
Check 'R1 read-only .pas: refused before any write -- exit 2, both files intact, no .BCK, no recovery.txt' `
  (($r.Code -eq 2) -and ($r.Out -match 'read-only') -and ((FHash "$d\OnlyDfm.pas") -eq $hp) -and ((FHash "$d\OnlyDfm.dfm") -eq $hd) -and `
   (@(Get-ChildItem $d -Filter '*.BCK*').Count -eq 0) -and -not (Test-Path "$d\recovery.txt")) "exit=$($r.Code); $($r.Out); $((Get-ChildItem $d -Name) -join ', ')"
$d = "$WorkDir\n"   # fresh: a rolled-back R1 leaves the .dfm newer than its index
Fixture $d
$hp = FHash "$d\OnlyDfm.pas"
Set-ItemProperty "$d\OnlyDfm.pas" -Name IsReadOnly -Value $true
$r = Apply $d @('--no-backup')
Check 'R2 CONTROL read-only .pas under --no-backup: exit 0, .dfm converted, .pas untouched' `
  (($r.Code -eq 0) -and ((FHash "$d\OnlyDfm.pas") -eq $hp) -and ((Get-Content "$d\OnlyDfm.dfm" -Raw) -match 'object tbl: TDstTable')) "exit=$($r.Code); $($r.Out)"
Set-ItemProperty "$d\OnlyDfm.pas" -Name IsReadOnly -Value $false

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  Get-ChildItem $WorkDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
