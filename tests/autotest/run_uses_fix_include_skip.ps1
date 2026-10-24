<#
  run_uses_fix_include_skip.ps1 -- N-06 T7: the uses EDITORS never edit an
  entry that lives in a {$I} include.

  Fixture tests\fixtures\includeuses:
    a. uses-fix HostM.pas: Leaf (interface, used only by the implementation) is
       in HostM.Intf.inc -> a `skipped:` line naming the include and both lines,
       JSON skipped_include[] + skipped_include_count 2 (every include row is\r\n       listed, System.SysUtils too), no move; --apply leaves
       HostM.pas and the .inc byte-identical.
    b. CONTROL: uses-fix HostN.pas (the same clause inlined) MOVES Leaf.
    c. find-unit --name ValueI --in HostL.pas: HostL's implementation clause is
       only in an include -> "No edit computed: refused: uses-in-include", exit 1;
       CONTROL: --in HostN.pas computes an edit (exit 0).
    d. create-enum-helper HostE.TColorE --tostring rtti (needs System.TypInfo, the
       implementation clause is in HostE.Impl.inc) -> action uses_in_include, no
       edits; CONTROL --tostring case builds, the bodies after the {$I} (line 13).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-fix-inc-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$iu = Join-Path $WorkDir 'includeuses'; Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\includeuses").Path $iu -Recurse
$proj = Join-Path $iu 'IncUsesX.dproj'
$db = Join-Path $WorkDir 'iu.sqlite'
function Run([string[]]$a) {
  Push-Location $WorkDir
  try { $o = & $Exe @a 2>&1 | ForEach-Object { "$_" } | Out-String; $rc = $LASTEXITCODE } finally { Pop-Location }
  return @{ Out = $o; Rc = $rc }
}
function Hash([string]$p) { (Get-FileHash $p -Algorithm SHA256).Hash }
$null = Run @('index', '--project', $proj, '--db', $db, '--library-db', 'none')

$hm = Join-Path $iu 'HostM.pas'; $hmi = Join-Path $iu 'HostM.Intf.inc'
$t = Run @('uses-fix', $hm, '--project', $proj, '--db', $db, '--platform', 'win64')
Check 'a: skipped: line names Leaf, the include line 2 and the {$I} at HostM.pas:9' ($t.Out.Contains('skipped: Leaf -- used from include HostM.Intf.inc:2 ({$I} at HostM.pas:9); uses-fix edits only the unit''s own uses clause.')) ($t.Out.Trim() -replace "`r?`n", ' | ')
Check 'a: no MOVED line' ($t.Out -notmatch 'MOVED') ''
$j = Run @('uses-fix', $hm, '--project', $proj, '--db', $db, '--platform', 'win64', '--format', 'json')
$o = $null; try { $o = ($j.Out.Substring($j.Out.IndexOf('{')) | ConvertFrom-Json) } catch { }
Check 'a: JSON skipped_include has Leaf' (($null -ne $o) -and (@($o.skipped_include | Where-Object { $_.unit -eq 'Leaf' -and $_.include_line -eq 2 -and $_.host_line -eq 9 }).Count -eq 1)) ''
Check 'a: JSON skipped_include_count 2 (Leaf and System.SysUtils, both in the include)' (($null -ne $o) -and ($o.skipped_include_count -eq 2)) "got $($o.skipped_include_count)"
$b1 = Hash $hm; $b2 = Hash $hmi
$null = Run @('uses-fix', $hm, '--project', $proj, '--db', $db, '--platform', 'win64', '--apply')
Check 'a: --apply leaves HostM.pas and HostM.Intf.inc byte-identical' (((Hash $hm) -eq $b1) -and ((Hash $hmi) -eq $b2)) ''

$n = Run @('uses-fix', (Join-Path $iu 'HostN.pas'), '--project', $proj, '--db', $db, '--platform', 'win64')
Check 'b: CONTROL: uses-fix HostN.pas MOVES Leaf' ($n.Out -match 'MOVED\s+Leaf') ($n.Out.Trim() -replace "`r?`n", ' | ')

$f1 = Run @('find-unit', '--name', 'ValueI', '--in', (Join-Path $iu 'HostL.pas'), '--db', $db)
Check 'c: find-unit into an include-only section refuses uses-in-include (exit 1)' (($f1.Rc -eq 1) -and ($f1.Out -match 'No edit computed: refused: uses-in-include')) ($f1.Out.Trim() -replace "`r?`n", ' | ')
$f2 = Run @('find-unit', '--name', 'ValueI', '--in', (Join-Path $iu 'HostN.pas'), '--db', $db)
Check 'c: CONTROL: find-unit --in HostN.pas computes an edit (exit 0)' ($f2.Rc -eq 0) ($f2.Out.Trim() -replace "`r?`n", ' | ')

$e1 = Run @('create-enum-helper', '--qname', 'HostE.TColorE', '--tostring', 'rtti', '--json', '--db', $db)
Check 'd: create-enum-helper rtti -> uses_in_include' ($e1.Out -match 'uses_in_include') ($e1.Out.Trim() -replace "`r?`n", ' | ')
$e2 = Run @('create-enum-helper', '--qname', 'HostE.TColorE', '--tostring', 'case', '--json', '--db', $db)
$eo = $null; try { $eo = ($e2.Out.Substring($e2.Out.IndexOf('{')) | ConvertFrom-Json) } catch { }
Check 'd: CONTROL: --tostring case builds' ($e2.Out -match '"built"') ($e2.Out.Substring(0, [Math]::Min(300, $e2.Out.Length)) -replace "`r?`n", ' ')
Check 'd: CONTROL: no edit lands on or before the {$I} line 13 in the implementation' (-not ($e2.Out -match '"line"\s*:\s*1[0-3]\b')) ''

if ($script:Failed) { Write-Host 'run_uses_fix_include_skip: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_uses_fix_include_skip: PASS' -ForegroundColor Green; exit 0