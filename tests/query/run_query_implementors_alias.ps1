<#
  run_query_implementors_alias.ps1 -- `query implementors` is an alias of the `implementors` verb.

  DEFECT (wave 150 G7): the global verb table names `query implementors`, but the query
  dispatcher answered "ERROR: unknown query subcommand: implementors" (exit 2).
  FIX: DoQuery routes the subcommand to DoImplementors (--name accepted for --target).

  Asserts: alias stdout == top-level verb stdout (non-empty, names the implementing class),
  exit codes equal, --name form equal, and a misspelt subcommand still exits 2 (positive control:
  the alias check cannot pass by accepting every subcommand). Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_query_impl_alias_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
Write-Ascii (Join-Path $src 'uImpl.pas') @'
unit uImpl;

interface

type
  IShape = interface
    procedure Draw;
  end;

  TCircle = class(TInterfacedObject, IShape)
    procedure Draw;
  end;

implementation

procedure TCircle.Draw;
begin
end;

end.
'@
$db = Join-Path $WorkDir 'impl.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null

function Run([string[]]$ArgList) {
  $o = Join-Path $WorkDir 'o.txt'; $e = Join-Path $WorkDir 'e.txt'
  $p = Start-Process -FilePath $exePath -ArgumentList $ArgList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  return @{ Code = $p.ExitCode; Out = ((Get-Content -LiteralPath $o -Raw -ErrorAction SilentlyContinue) + '').Trim() }
}

Push-Location C:\TEMP
try {
  $top   = Run @('implementors','--target','IShape','--db',$db)
  Check 'VACUITY top-level verb names TCircle' (($top.Code -eq 0) -and ($top.Out -match 'TCircle')) "exit $($top.Code): $($top.Out)"
  $alias = Run @('query','implementors','--target','IShape','--db',$db)
  Check 'A1 query implementors --target -> exit 0' ($alias.Code -eq 0) "exit $($alias.Code): $($alias.Out)"
  Check 'A2 alias output identical to the verb' ($alias.Out -eq $top.Out) "alias: $($alias.Out)"
  $byName = Run @('query','implementors','--name','IShape','--db',$db)
  Check 'A3 query implementors --name == --target' (($byName.Code -eq 0) -and ($byName.Out -eq $top.Out)) "exit $($byName.Code): $($byName.Out)"
  $bad = Run @('query','implementorz','--target','IShape','--db',$db)
  Check 'A4 positive control: misspelt subcommand still exit 2' ($bad.Code -eq 2) "exit $($bad.Code)"
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d in @("C:\TEMP\draglint_query_impl_alias_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
