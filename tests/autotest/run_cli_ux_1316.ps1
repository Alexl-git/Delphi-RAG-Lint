<#
  run_cli_ux_1316.ps1 -- lane A of 1.31.6: B-26 banner, B-38 find-callers hint, B-25 compare --db help +
  quoted --command, the --fix --apply note.  pwsh -File tests\autotest\run_cli_ux_1316.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-cli-ux-1316-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
Copy-Item (Join-Path $Repo 'tests\fixtures\compare-verb\*') $Work
$Db = Join-Path $Work 't.sqlite'; $U = Join-Path $Work 'Unit1.pas'
function Run([string[]]$ArgList) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in $ArgList) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}
$null = Run @('index','--project',(Join-Path $Work 'Cmp.dproj'),'--db',$Db)

# B-26: banner names doc-drift only when --project-rules was NOT passed (positive control = without flag)
$a = Run @('lint',$U,'--db',$Db,'--project-rules')
$b = Run @('lint',$U,'--db',$Db)
Check 'B-26 control: without --project-rules the banner says pass --project-rules' ($b.Err -match 'pass\s+--project-rules')
Check 'B-26 with --project-rules the banner has a note but no stale doc-drift claim' (($a.Err -match 'project rules ran') -and ($a.Err -notmatch 'pass\s+--project-rules') -and ($a.Err -notmatch 'doc-drift/missing-doc \('))

# B-38: 0 callers -> hint to usages on stderr, stdout unchanged; control: a real caller prints no hint
$c = Run @('query','find-callers','--name','FName','--db',$Db)
Check 'B-38 0 callers: stdout has 0 caller(s), stderr hints usages' (($c.Out -match '0 caller\(s\)') -and ($c.Err -match 'usages --name FName'))
$d = Run @('query','find-callers','--name','TFoo','--db',$Db)
Check 'B-38 control: a name with callers prints no hint' (($d.Err -notmatch 'usages --name') -and ($d.Out -notmatch '0 caller'))

# --fix --apply note
$e = Run @('lint',$U,'--db',$Db,'--fix','--apply','--no-backup')
$f = Run @('lint',$U,'--db',$Db,'--fix','--apply','--no-backup','--project-rules')
Check 'fix-note: --fix --apply without --project-rules says doc fixes are skipped' ($e.Err -match 'fix --apply without --project-rules')
Check 'fix-note control: with --project-rules no such note' ($f.Err -notmatch 'fix --apply without --project-rules')

# B-25: --db in compare help; quoted --command round-trips (.NET sends \" for embedded quotes)
$h = Run @('--help')
Check 'B-25 --help compare lines list --db' ($h.Out -match '--old-db <old\.sqlite>\] \[--db ')
$old = Join-Path $Work 'x.txt'; 'x' | Set-Content $old
$q = Run @('compare','--old',$old,'--command','who-writes -Target "TFoo.FName" -Project "C:\P\A.dproj"','--format','json')
$q2 = Run @('compare','--old',$old,'--command','who-writes -Target TFoo.FName -Project C:\P\A.dproj','--format','json')
$msg = ($q.Out + $q.Err); $msg2 = ($q2.Out + $q2.Err)
Check 'B-25 control: unquoted --command reports the plain project path' ($msg2 -match 'not found: C:\\\\?P\\\\?A\.dproj')
Check 'B-25 quoted --command reports the same plain path (no stray backslashes)' (($msg -match 'not found: C:\\\\?P\\\\?A\.dproj') -and ($msg -notmatch '\\\\\\C:'))

[IO.Directory]::Delete($Work, $true)
if ($script:fail) { Write-Host 'run_cli_ux_1316: FAIL'; exit 1 }
Write-Host 'run_cli_ux_1316: PASS'