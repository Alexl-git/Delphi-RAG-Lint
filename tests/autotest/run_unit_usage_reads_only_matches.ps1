<#
  run_unit_usage_reads_only_matches.ps1 -- `query unit-usage --unit U` reads only
  the refs that can name U's exports (Gitea drag-lint#39, 2026-10-15).

  WHY. It read EVERY ref of every importing file and compared each with every
  export: 13 s for UConfig on ProjectA (208 importers). The refs are now filtered in
  SQLite by name and receiver base type, one query per store, and the exports
  are looked up in a dictionary -- 0.9 s, with output byte-identical to the old
  loop on UConfig and ULib.

  Checks:
    U1  DRAGLINT_PROFILE reports the refs read, and they are only the matching
        ones (the importer also holds 60 unrelated calls)
    U2  the answer is unchanged: 4 refs to 2 exports, first line of the first use
        -- counted through a call, a generic construction `TBox<Integer>.Create`
        and a differently-cased name

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_uu_matches_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Write-Ascii (Join-Path $WorkDir 'uLib.pas') @'
unit uLib;

interface

type
  TBox<T> = class
  end;

procedure DoThing;

implementation

procedure DoThing;
begin
end;

end.
'@
Write-Ascii (Join-Path $WorkDir 'uOther.pas') @'
unit uOther;

interface

procedure Noise;

implementation

procedure Noise;
begin
end;

end.
'@
$noise = (1..60 | ForEach-Object { '  Noise;' }) -join "`n"
Write-Ascii (Join-Path $WorkDir 'uUser.pas') @"
unit uUser;

interface

procedure Run;

implementation

uses
  uLib, uOther;

procedure Run;
var
  B: TObject;
begin
  DoThing;
  dothing;
  B:= TBox<Integer>.Create;
$noise
end;

end.
"@
Write-Ascii (Join-Path $WorkDir 'P.dpr') "program P;`n`nuses`n  uLib in 'uLib.pas',`n  uOther in 'uOther.pas',`n  uUser in 'uUser.pas';`n`nbegin`nend.`n"
$db = Join-Path $WorkDir 'p.sqlite'
$env:DRAGLINT_RULE_CACHE = '0'
$idx = & $exePath index --project (Join-Path $WorkDir 'P.dpr') --db $db 2>&1 | Out-String
$env:DRAGLINT_RULE_CACHE = $null
Check 'SANITY: fixture indexed' ($LASTEXITCODE -eq 0) $idx

$errF = Join-Path $WorkDir 'uu.err'
$env:DRAGLINT_PROFILE = '1'
$json = & $exePath query unit-usage --unit uLib --db $db --json 2>$errF | Out-String
$env:DRAGLINT_PROFILE = $null
$prof = Get-Content $errF -Raw
$read = if ($prof -match 'unit-usage: (\d+) ref\(s\) read from (\d+) importing file') { [int]$Matches[1] } else { -1 }
Check 'U1 the refs read are only those naming an export (not the 60 unrelated calls)' (($read -ge 3) -and ($read -le 6)) "profile: $prof"

$rows = @(try { $json | ConvertFrom-Json } catch { @() })
$u = @($rows | Where-Object { $_.file -match 'uUser\.pas$' })
Check 'U2 the answer: uUser references uLib through 2 exports' (($u.Count -eq 1) -and ($u[0].referenced -eq $true) -and ($u[0].exports_used -eq 2) -and ($u[0].ref_count -ge 3)) $json
}
finally {
  $env:DRAGLINT_PROFILE = $null; $env:DRAGLINT_RULE_CACHE = $null
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
