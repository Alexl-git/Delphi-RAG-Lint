<#
  run_convert_apply_target_freshness.ps1 -- convert-apply's freshness check covers
  the TARGET unit's own .pas and .dfm, not only the #convert From/To types
  (B-18, INBOX-2026-10-05-freshness-misses-edited-dfm, 1.31.7).

  THE DEFECT: CheckFreshness hashed only the files declaring the From/To types.
  A unit whose .dfm (or .pas) changed after indexing read "fresh": true, and an
  edit that kept the line count (Caption 'Hi' -> 'Ho') passed even the splice's
  span check -- --apply converted from a stale index, exit 0.

  THE CONTRACT this guard pins:
    D  .dfm edited in place after indexing: dry run json freshness.fresh=false,
       a reason naming Frm.dfm, refused=false (a preview still runs); text dry run
       prints the WARNING; --apply is REFUSED (exit 1, refused=true, reason
       "index is stale for <Frm.dfm> ... -- reindex"), .pas and .dfm untouched.
    P  .pas edited after indexing: the same, naming Frm.pas.
    F  positive control: an unedited unit is fresh (fresh=true, no reasons) and
       --apply converts.
    T  positive control: an edited From/To type unit (LibAB.pas) is still caught
       by the type check (fresh=false, --apply fails with the freshness error).

  Fixture written fresh under a $PID scratch folder with its own --db. Nothing
  shared is touched. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-convert-apply-target-fresh-$PID"
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
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$LibSrc = @'
unit LibAB;

interface

uses
  Classes;

type
  TSrcA = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TDstB = class(TPersistent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@
$FrmPas = @'
unit Frm;

interface

uses
  Classes, Forms, LibAB;

type
  TFrm = class(TForm)
    btn1: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
$FrmDfm = @'
object Frm: TFrm
  object btn1: TSrcA
    Caption = 'Hi'
  end
end
'@
$Rules = @'
#convert LibAB.TSrcA -> LibAB.TDstB, LibAB
#link Caption <- Caption
'@

function NewFixture([string]$Sub) {
  $d = Join-Path $WorkDir $Sub
  New-Item -ItemType Directory $d | Out-Null
  Write-Ascii (Join-Path $d 'LibAB.pas') $LibSrc
  Write-Ascii (Join-Path $d 'Frm.pas') $FrmPas
  Write-Ascii (Join-Path $d 'Frm.dfm') $FrmDfm
  Write-Ascii (Join-Path $d 'b.rules') $Rules
  $db = Join-Path $d 'fx.sqlite'
  $idx = & $Exe index $d --db $db 2>&1
  if (($LASTEXITCODE -ne 0) -or -not (Test-Path $db)) { Check "V $Sub fixture index built" $false ($idx -join ' | ') }
  return $d
}
function Run([string]$Dir, [string[]]$Extra) {
  $o = (& $Exe convert-apply --unit (Join-Path $Dir 'Frm.pas') --rules (Join-Path $Dir 'b.rules') --db (Join-Path $Dir 'fx.sqlite') @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Hashes([string]$Dir) { return ((Get-FileHash (Join-Path $Dir 'Frm.pas')).Hash + (Get-FileHash (Join-Path $Dir 'Frm.dfm')).Hash) }
function Edit([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  if (-not $t.Contains($Old)) { Check "V edit anchor present in $Path" $false $Old }
  [IO.File]::WriteAllText($Path, $t.Replace($Old, $New), [Text.Encoding]::ASCII)
}

function CheckStaleTarget([string]$Tag, [string]$Dir, [string]$Stale) {
  $Pat = 'index is stale for ' + [regex]::Escape($Stale) + '\b.* -- reindex'
  $r = Run $Dir @('--format', 'json')
  $j = Json $r.Out
  Check "$Tag`1 json dry run: freshness.fresh=false, a reason names $(Split-Path $Stale -Leaf), not refused" `
    (($null -ne $j) -and ($j.freshness.fresh -eq $false) -and (@($j.freshness.reasons | Where-Object { $_ -match $Pat }).Count -eq 1) -and ($j.refused -eq $false)) $r.Out
  $r = Run $Dir @()
  Check "$Tag`2 text dry run: WARNING freshness line + the reason" `
    (($r.Out -match '(?m)^WARNING: freshness guard failed') -and ($r.Out -match $Pat)) $r.Out
  $h = Hashes $Dir
  $r = Run $Dir @('--apply', '--no-backup', '--format', 'json')
  $j = Json $r.Out
  Check "$Tag`3 json --apply: exit 1, ok=false, refused=true, reason names $(Split-Path $Stale -Leaf)" `
    (($r.Code -eq 1) -and ($null -ne $j) -and (-not $j.ok) -and ($j.refused -eq $true) -and ($j.reason -match $Pat)) $r.Out
  $r = Run $Dir @('--apply', '--no-backup')
  Check "$Tag`4 text --apply: exit 1, one REFUSED line naming the file" `
    (($r.Code -eq 1) -and (@($r.Out -split "`n" | Where-Object { $_ -match ('^REFUSED: .*' + $Pat) }).Count -eq 1)) $r.Out
  Check "$Tag`5 .pas and .dfm byte-identical after both --apply runs" ((Hashes $Dir) -eq $h)
}

# ---- D: the unit's .dfm edited in place (same line count) --------------------
$d = NewFixture 'd'
Edit (Join-Path $d 'Frm.dfm') "Caption = 'Hi'" "Caption = 'Ho'"
CheckStaleTarget 'D' $d (Join-Path $d 'Frm.dfm')

# ---- P: the unit's .pas edited -----------------------------------------------
$d = NewFixture 'p'
Edit (Join-Path $d 'Frm.pas') "implementation`r`n" "implementation`r`n`r`n// edited after indexing`r`n"
CheckStaleTarget 'P' $d (Join-Path $d 'Frm.pas')

# ---- F: positive control -- unedited unit is fresh and converts --------------
$d = NewFixture 'f'
$r = Run $d @('--format', 'json')
$j = Json $r.Out
Check 'F1 fresh dry run: fresh=true, no reasons' `
  (($null -ne $j) -and ($j.freshness.fresh -eq $true) -and (@($j.freshness.reasons).Count -eq 0)) $r.Out
$r = Run $d @('--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'F2 fresh --apply: exit 0, ok=true, refused=false, converted' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and ($j.refused -eq $false) -and (@($j.converted).Count -eq 1)) $r.Out
Check 'F3 fresh: the .dfm now holds the To type' ([IO.File]::ReadAllText((Join-Path $d 'Frm.dfm')) -match 'TDstB')

# ---- T: positive control -- the type check still catches an edited type unit --
$d = NewFixture 't'
$lib = Join-Path $d 'LibAB.pas'
Edit $lib "implementation`r`n" "implementation`r`n`r`n// edited after indexing`r`n"
$r = Run $d @('--format', 'json')
$j = Json $r.Out
Check 'T1 type unit edited: fresh=false, a reason names LibAB.pas, none names Frm.*' `
  (($null -ne $j) -and ($j.freshness.fresh -eq $false) -and (@($j.freshness.reasons | Where-Object { $_ -match 'LibAB\.pas' }).Count -ge 1) -and `
   (@($j.freshness.reasons | Where-Object { $_ -match 'Frm\.(pas|dfm)' }).Count -eq 0)) $r.Out
$h = Hashes $d
$r = Run $d @('--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'T2 type unit edited --apply: exit 1, freshness error, files untouched' `
  (($r.Code -eq 1) -and ($null -ne $j) -and ($j.error -match 'freshness guard failed') -and ((Hashes $d) -eq $h)) $r.Out

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-convert-apply-target-fresh-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
