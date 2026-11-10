<#
  run_index_parse_errors_summary.ps1 -- 150 X3 (W1 step 4): the index section summary
  line must end with parse-errors=N, N = files parsed this run whose tree had
  ERROR/MISSING nodes. The index used to be silent on them.
  Fixture A: one clean unit -> parse-errors=0 (positive control: the field is present, not 'absent == 0').
  Fixture B: clean unit + one broken unit -> parse-errors=1.
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_parseerr_{0}' -f [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch | Out-Null
function Write-Ascii($p,$t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), (New-Object Text.UTF8Encoding($false))) }
function RunIdx([string]$Name,[string]$Src) {
  $out = Join-Path $scratch "out-$Name"; New-Item -ItemType Directory -Path $out | Out-Null
  $cfg = Join-Path $scratch "cfg-$Name.json"
  Write-Ascii $cfg ('{ "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 4096, "enginePath": "auto", "maxJobs": 1 }, "indexes": { "outDir": "' + ($out -replace '\\','\\') + '", "sections": [ { "name": "PE' + $Name + '", "db": "pe.sqlite", "include": ["' + ($Src -replace '\\','\\') + '"] } ] } }')
  $so = Join-Path $scratch "$Name.out.log"
  cmd /c "`"$exePath`" index --all --config `"$cfg`" --jobs 1 --rebuild > `"$so`" 2>&1" | Out-Null
  $txt = Get-Content -LiteralPath $so -Raw
  return @{ Text = $txt; Line = ($txt -split "`r?`n" | Where-Object { $_ -match '^===.* files=' } | Select-Object -First 1) }
}
$good = "unit uGood;`ninterface`ntype`n  TGood = class`n  public`n    procedure Work;`n  end;`nimplementation`nprocedure TGood.Work;`nbegin`nend;`nend.`n"
$bad  = "unit uBad;`ninterface`ntype`n  TBad = class`n  public`n    procedure Work(;`n  end;`nimplementation`nprocedure TBad.Work;`nbegin`n  if then ) end end;`nend.`n"
try {
  $a = Join-Path $scratch 'srcA'; New-Item -ItemType Directory -Path $a | Out-Null
  Write-Ascii (Join-Path $a 'uGood.pas') $good
  $ra = RunIdx 'A' $a
  Check 'A summary line found' ($null -ne $ra.Line) $ra.Text
  Check 'A clean fixture: parse-errors=0 (field present)' ($ra.Line -match '\] parse-errors=0 ===\s*$') $ra.Line
  $b = Join-Path $scratch 'srcB'; New-Item -ItemType Directory -Path $b | Out-Null
  Write-Ascii (Join-Path $b 'uGood.pas') $good
  Write-Ascii (Join-Path $b 'uBad.pas') $bad
  $rb = RunIdx 'B' $b
  Check 'B broken fixture sanity: parser reported a parse error diagnostic' ($rb.Text -match 'parse error \[') $rb.Text
  Check 'B broken fixture: parse-errors=1' ($rb.Line -match '\] parse-errors=1 ===\s*$') $rb.Line
  Check 'B field order kept: committed= precedes the timing bracket' ($rb.Line -match 'committed=\d+ \[[^\]]+\] parse-errors=') $rb.Line
} finally { [IO.Directory]::Delete($scratch, $true) }
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }