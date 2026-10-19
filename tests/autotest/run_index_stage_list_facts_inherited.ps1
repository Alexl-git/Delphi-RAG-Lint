<#
  run_index_stage_list_facts_inherited.ps1 -- B-24: every path that re-parses
  files into an index runs the SAME post-walk link stages, facts-inherited
  included.

  MEASURED 2026-10-19 (fixture below, engine 1.31.6-alpha wave/1316):
    index --rebuild ................ WriteInherited writes_fields = "FOwn, FBaseField"
    index (incremental, edited) .... "FOwn, FBaseField"
    index --watch (edit mid-run) ... "FOwn, FBaseField"
    reconcile-project --db (heal) .. "FOwn"            <-- inherited field LOST
    ... then index (incremental) ... "FOwn"            <-- and it STAYS lost: the
        heal refreshed the files row, so the next index finds the file up to date
        and never re-parses it.
  Cause: DoReconcileProject's heal block carried its own copy of the stage list
  (uses-targets, ancestry, helpers, calls, purity) without facts-inherited. The
  fix is ONE routine (RunLinkStages) every index site calls; the source check
  below pins that there is one list, not four.

  Positive control: the incremental path on the same fixture produces the
  inherited field, so a fixture that cannot produce it fails the guard.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$repo    = (Resolve-Path "$PSScriptRoot\..\..").Path
$scratch = Join-Path C:\TEMP "draglint_stagelist_$PID"
try {
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$childV1 = @'
unit ifChild;
interface
uses ifXBase;
type
  TChild = class(TPlainBase)
  private
    FOwn: Integer;
  public
    procedure WriteInherited;
  end;
implementation
procedure TChild.WriteInherited;
begin
  FOwn := 1;
  FBaseField := 2;
end;
end.
'@
# V2 adds a routine: its presence after the heal proves the heal RE-PARSED.
$childV2 = @'
unit ifChild;
interface
uses ifXBase;
type
  TChild = class(TPlainBase)
  private
    FOwn: Integer;
  public
    procedure WriteInherited;
    procedure WriteAdded;
  end;
implementation
procedure TChild.WriteInherited;
begin
  FOwn := 1;
  FBaseField := 2;
end;
procedure TChild.WriteAdded;
begin
  FBaseField := 3;
end;
end.
'@

function New-Fixture([string]$Dir) {
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  Write-Ascii (Join-Path $Dir 'ifXBase.pas') @'
unit ifXBase;
interface
type
  TPlainBase = class
  protected
    FBaseField: Integer;
  end;
implementation
end.
'@
  Write-Ascii (Join-Path $Dir 'ifChild.pas') $childV1
  Write-Ascii (Join-Path $Dir 'Q.dpr') @'
program Q;
uses
  ifXBase in 'ifXBase.pas',
  ifChild in 'ifChild.pas';
begin
end.
'@
  Write-Ascii (Join-Path $Dir 'Q.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>Q.dpr</MainSource></PropertyGroup>
  <ItemGroup>
    <DCCReference Include="ifXBase.pas"/>
    <DCCReference Include="ifChild.pas"/>
  </ItemGroup>
</Project>
'@
}
function Edit-Child([string]$Dir) {
  $p = Join-Path $Dir 'ifChild.pas'
  Write-Ascii $p $childV2
  (Get-Item $p).LastWriteTime = (Get-Date).AddSeconds(5)
}
# `sql --json` rows are POSITIONAL arrays: take column 0 of the single row.
function Writes([string]$Db, [string]$QName) {
  $j = (& $exePath sql --db $Db --query "SELECT f.writes_fields FROM symbol_facts f JOIN symbols s ON s.id=f.symbol_id WHERE s.qualified_name='$QName'" --json 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($j)) { return '<no-output>' }
  try { $o = $j | ConvertFrom-Json } catch { return '<bad-json>' }
  $rows = @($o.rows)
  if ($rows.Count -ne 1) { return "<rows=$($rows.Count)>" }
  return [string](@($rows[0])[0])
}

Push-Location C:\TEMP
try {
  # POSITIVE CONTROL: incremental index after the same edit.
  $b = Join-Path $scratch 'B'; New-Fixture $b; $bdb = Join-Path $b 'b.sqlite'
  & $exePath index --project (Join-Path $b 'Q.dproj') --db $bdb *> (Join-Path $b 'log1.txt')
  Edit-Child $b
  & $exePath index --project (Join-Path $b 'Q.dproj') --db $bdb *> (Join-Path $b 'log2.txt')
  $wb = Writes $bdb 'ifChild.TChild.WriteInherited'
  $ab = Writes $bdb 'ifChild.TChild.WriteAdded'
  Check 'control: incremental index -> WriteInherited writes "FOwn, FBaseField"' ($wb -eq 'FOwn, FBaseField') "got=$wb"
  Check 'control: incremental index -> WriteAdded writes "FBaseField"' ($ab -eq 'FBaseField') "got=$ab"

  # --rebuild parity.
  $a = Join-Path $scratch 'A'; New-Fixture $a; Edit-Child $a; $adb = Join-Path $a 'a.sqlite'
  & $exePath index --project (Join-Path $a 'Q.dproj') --db $adb --rebuild *> (Join-Path $a 'log.txt')
  $wa = Writes $adb 'ifChild.TChild.WriteInherited'
  Check 'rebuild -> same facts as incremental' (($wa -eq $wb) -and ((Writes $adb 'ifChild.TChild.WriteAdded') -eq $ab)) "got=$wa"

  # THE BUG: reconcile-project --db heals an index-stale member.
  $d = Join-Path $scratch 'D'; New-Fixture $d; $ddb = Join-Path $d 'd.sqlite'
  & $exePath index --project (Join-Path $d 'Q.dproj') --db $ddb *> (Join-Path $d 'log1.txt')
  Edit-Child $d
  & $exePath reconcile-project (Join-Path $d 'Q.dproj') --db $ddb *> (Join-Path $d 'log2.txt')
  $ad = Writes $ddb 'ifChild.TChild.WriteAdded'
  Check 'reconcile --db heal re-parsed the edited member (WriteAdded has a facts row)' ($ad -notmatch '^<') "got=$ad"
  $wd = Writes $ddb 'ifChild.TChild.WriteInherited'
  Check 'B-24 reconcile --db heal -> WriteInherited keeps inherited FBaseField' ($wd -eq 'FOwn, FBaseField') "got=$wd"
  Check 'B-24 reconcile --db heal -> WriteAdded writes inherited FBaseField' ($ad -eq 'FBaseField') "got=$ad"
  & $exePath index --project (Join-Path $d 'Q.dproj') --db $ddb *> (Join-Path $d 'log3.txt')
  Check 'B-24 a following incremental index agrees (nothing left stale)' ((Writes $ddb 'ifChild.TChild.WriteInherited') -eq 'FOwn, FBaseField')
} finally { Pop-Location }

# ONE stage list: the four link stages are named in exactly one place in the CLI.
$cli = [System.IO.File]::ReadAllText((Join-Path $repo 'src\cli\DRagLint.CLI.pas'))
$nFacts = ([regex]::Matches($cli, "Stage\([^;]*'facts-inherited'")).Count
$nAnc   = ([regex]::Matches($cli, "Stage\([^;]*'ancestry'")).Count
Check 'one stage list: Stage(..''facts-inherited''..) occurs once in DRagLint.CLI.pas' ($nFacts -eq 1) "n=$nFacts"
Check 'one stage list: Stage(..''ancestry''..) occurs once in DRagLint.CLI.pas' ($nAnc -eq 1) "n=$nAnc"
} finally {
  if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
