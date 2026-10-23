<#
  run_document_qname_all_overloads.ps1 -- N-12 (INBOX-yadf-fp-layout-complexity-docs item 1).

  THE DEFECT (re-measured 2026-10-23 on 1.33.0-alpha). `document --qname uOv.Fmt`
  documented overload 1 only: TDocumenter.BuildFor took Syms[0] of the qualified
  name. Overloads share that name and there is no qname form for the second one
  (`Fmt/3` and `#2` are rejected), so a doc-drift finding on overload 2 could not
  be cleared with --qname while lint-all kept reporting it.

  CONTRACT. --qname documents EVERY overload that carries the name.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_doc_qname_overloads_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$unit = Join-Path $WorkDir 'uOv.pas'
$u = "unit uOv;`r`n`r`ninterface`r`n`r`nfunction Fmt(const S: string): string; overload;`r`n" +
     "function Fmt(const S: string; N: Integer; out R: string): string; overload;`r`n`r`nimplementation`r`n`r`n" +
     "function Fmt(const S: string): string;`r`nbegin`r`n  Result:= S;`r`nend;`r`n`r`n" +
     "function Fmt(const S: string; N: Integer; out R: string): string;`r`nbegin`r`n  R:= '';`r`n  Result:= Copy(S, 1, N);`r`nend;`r`n`r`nend.`r`n"
[IO.File]::WriteAllText($unit, $u, [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $WorkDir --db $db 2>&1 | Out-Null
$out = (& $exePath document --qname uOv.Fmt --db $db --apply --no-backup 2>&1) -join "`n"
$code = $LASTEXITCODE
$txt = [IO.File]::ReadAllText($unit)

Check 'P1 POSITIVE CONTROL overload 1 is documented' ($txt -match 'Overload 1 of 2') "exit $code`: $out"
Check 'T1 overload 2 is documented by the same --qname run' ($txt -match 'Overload 2 of 2') `
      'only the first overload got a block -- BuildFor still takes Syms[0]'
Check 'T2 overload 2 gets its own params (N, R)' (($txt -match 'name="N"') -and ($txt -match 'name="R"')) 'no <param> for N/R'
Check 'T3 the run exits 0' ($code -eq 0) "exit $code`: $out"

# A second run is a no-op: both blocks are current.
& $exePath index $WorkDir --db $db 2>&1 | Out-Null
$before = [IO.File]::ReadAllText($unit)
& $exePath document --qname uOv.Fmt --db $db --apply --no-backup 2>&1 | Out-Null
Check 'T4 a second --qname run changes nothing (idempotent)' ([IO.File]::ReadAllText($unit) -eq $before) 'second run rewrote the file'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_doc_qname_overloads_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
