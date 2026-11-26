#Requires -Version 7.3
<#
  run_v155_UPDORM.ps1 -- 1.55 UPDORM: `repo update-orm` and the regions it does not know (owner rulings 2026-11-26).

  A region named DB-RAD n / DLFR n whose id update-orm does not generate (DB-RAD 99) is hand code: it is kept
  byte for byte and the known regions of the unit are updated (1.53.1-1.54 refused the whole unit; TableTools
  emptied the region). A unit whose markers cannot be trusted is still REFUSED, and then the run exits 1 (Q9)
  while the other units are still written.
    U1  an unknown region beside a known one: exit 0, no REFUSED, the unknown region and every byte outside
        region 2 kept, region 2 regenerated
    U2  a second run writes nothing
    U3  one unit refused (a start marker without an end): exit 1, REFUSED named, that unit unchanged, the other
        unit still written
    U4  the same in a dry run: exit 1, nothing written
    U5  control: the refused unit removed, exit 0
  Run: pwsh -File tests\autotest\run_v155_UPDORM.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:pass = 0
$script:fail = 0
function Check($n, $ok, $d = '') {
  if ($ok) { $script:pass++; Write-Host "[PASS] $n" -ForegroundColor Green } else { $script:fail++; Write-Host "[FAIL] $n $d" -ForegroundColor Red }
}
Write-Host '== v155 UPDORM: repo update-orm keeps unknown regions, exits 1 on a refused unit ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v155-updorm-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$ansi = [Text.Encoding]::GetEncoding(1252)
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function ReadText($f) { [IO.File]::ReadAllText($f, $ansi) }
function WriteText($f, $t) { [IO.File]::WriteAllText($f, $t, $ansi) }
function Hash($f) { (Get-FileHash -LiteralPath $f).Hash }
# the text with the body of region 2 removed (the marker lines stay)
function Outside2($t) { [regex]::Replace($t, "(?s)(\{\`$REGION 'DB-RAD 2'\}\r\n).*?\r\n( *\{\`$ENDREGION 'DB-RAD 2'\})", '$1$2') }
try {
  # a repository with one data field, made through the product's own text format
  $empty = Join-Path $work 'r.empty.dlrepo'
  $bk = Join-Path $work 'r.txt'
  $null = Run @('repo', 'init', '--repo', $empty)
  $null = Run @('repo', 'backup', '--repo', $empty, '--output', $bk)
  $field = @('[DL_FIELDS_INFO ORDERS|AAA]', 'VISIBLE=true', 'TRIGGERED=false', 'BG_COLOR=false', 'FG_COLOR=false', 'UNIQUE_FLAG=false',
    'FIELD_KIND=1', 'PRIMARY_KEY=false', 'CUSTOM_TYPE=false', 'ISCALCULATED=false', 'ISLOOKUP=false', 'ISENUM=false', '')
  $out = foreach ($l in [IO.File]::ReadAllLines($bk)) {
    if ($l -match '^#end DL_FIELDS_INFO 0$') { $field; '#end DL_FIELDS_INFO 1' }
    elseif ($l -match '^#end DL_META (\d+)$') { '[DL_META schema_read_at_utc]', 'META_VALUE=2026-11-23T00:00:00Z', '', "#end DL_META $([int]$Matches[1] + 1)" }
    else { $l }
  }
  $txt = ($out -join "`n") + "`n"
  $m = [regex]::Match($txt, '(?s)(\[DL_META schema_version\].*?\n\n)(\[DL_META schema_read_at_utc\].*?\n\n)')
  if ($m.Success) { $txt = $txt.Replace($m.Value, $m.Groups[2].Value + $m.Groups[1].Value) }
  [IO.File]::WriteAllText($bk, $txt)
  $rp = Join-Path $work 'r.dlrepo'
  $r = Run @('repo', 'restore', '--repo', $rp, '--in', $bk)
  if ($r.Code -ne 0) { throw "restore failed: $($r.Out)" }

  $o = Join-Path $work 'orm'
  [IO.Directory]::CreateDirectory($o) | Out-Null
  $iu = Join-Path $o 'iORDERS.PAS'
  $uu = Join-Path $o 'uORDERS.PAS'
  $hand = "    {`$REGION 'DB-RAD 99'}`r`n    // hand code TableTools would have emptied`r`n    procedure Mine;`r`n    {`$ENDREGION 'DB-RAD 99'}`r`n"
  $iold = "unit iORDERS;`r`n`r`ninterface`r`n`r`ntype`r`n  ImcORDERS = interface`r`n    ['{7C0D8F0B-3B8C-4F3B-9D36-6B1C0B1F5A11}']`r`n" +
    "    {`$REGION 'DB-RAD 2'}`r`n    stale;`r`n    {`$ENDREGION 'DB-RAD 2'}`r`n" + $hand + "  end;`r`n`r`nimplementation`r`n`r`nend.`r`n"
  WriteText $iu $iold
  function Update([string[]]$more) { Run (@('repo', 'update-orm', '--repo', $rp, '--code-dir', $o, '--table', 'ORDERS', '--no-backup') + $more) }

  $r = Update @('--apply')
  $inew = ReadText $iu
  Check 'U1 an unknown region beside a known one: exit 0, no REFUSED, the unknown region kept, region 2 regenerated' (($r.Code -eq 0) -and
    ($r.Out -notmatch 'REFUSED') -and ($r.Out -match '1 changed') -and $inew.Contains($hand) -and ($inew -cne $iold) -and
    ((Outside2 $inew) -ceq (Outside2 $iold)) -and -not $inew.Contains('stale;')) $r.Out
  $h = Hash $iu
  $r = Update @('--apply')
  Check 'U2 a second run writes nothing' (($r.Code -eq 0) -and ($r.Out -match '1 unchanged') -and ((Hash $iu) -eq $h)) $r.Out

  WriteText $iu $iold
  $ubad = "unit uORDERS;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`n  {`$REGION 'DB-RAD 4'}`r`n  hand code with no end marker`r`n`r`nend.`r`n"
  WriteText $uu $ubad
  $hu = Hash $uu
  $r = Update @('--apply')
  Check 'U3 one unit refused: exit 1, REFUSED named, that unit unchanged, the other unit written' (($r.Code -eq 1) -and
    ($r.Out -match 'skipped .*uORDERS\.PAS: REFUSED.*without an end marker: DB-RAD 4') -and ((Hash $uu) -eq $hu) -and
    ((ReadText $iu) -ceq $inew) -and ($r.Out -match '1 written')) $r.Out
  WriteText $iu $iold
  $hi = Hash $iu
  $r = Update @()
  Check 'U4 dry run with a refused unit: exit 1, nothing written' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED') -and ((Hash $iu) -eq $hi) -and
    ((Hash $uu) -eq $hu)) $r.Out
  [IO.File]::Delete($uu)
  $r = Update @()
  Check 'U5 control: no refused unit, dry run exits 0' (($r.Code -eq 0) -and ($r.Out -notmatch 'REFUSED') -and ($r.Out -match '1 changed')) $r.Out
}
catch { $script:fail++; Write-Host "[FAIL] exception: $_ $($_.ScriptStackTrace)" -ForegroundColor Red }
finally { if ($script:fail -eq 0) { [IO.Directory]::Delete($work, $true) } else { Write-Host "kept: $work" } }
if ($script:fail -gt 0) { Write-Host "V155 UPDORM: FAIL pass=$script:pass fail=$script:fail" -ForegroundColor Red; exit 1 }
Write-Host "V155 UPDORM: PASS pass=$script:pass fail=0" -ForegroundColor Green
