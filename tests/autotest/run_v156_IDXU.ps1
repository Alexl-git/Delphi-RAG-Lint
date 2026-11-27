<#
  run_v156_IDXU.ps1 -- lane IDX-U: outline lists REGION pairs, usages --width wide prints file:line:col sites,
  find-callers marks read/write and lists field write sites, sql keeps `&` literal.
  Builds a 1-unit fixture index in a temp dir and runs the engine given by -Exe (default: the worktree build).
  Positive control: the same fixture at narrow width must NOT print site rows (so the wide assertion can fail).
  Exit 0 only when every check passes.
#>
[CmdletBinding()]
param([string]$Repo = '', [string]$Exe = '')
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Exe) { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
$ErrorActionPreference = 'Stop'
$work = Join-Path $env:TEMP "drag-lint-v156-idxu-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$script:fail = 0
function Check($ok, $what) { if ($ok) { Write-Host "  ok   $what" } else { Write-Host "  FAIL $what" -ForegroundColor Red; $script:fail++ } }
try {
  if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "V156 IDXU: FAIL -- engine not found: $Exe" -ForegroundColor Red; exit 1 }
  $L = @('unit uIdxu;', '', 'interface', '', 'type', '  TFoo = class', '  private', '    fData: Integer;', '  public',
    '    procedure Run;', '    function Get: Integer;', '  end;', '', 'implementation', '',
    "{`$REGION 'DB-RAD 1 hash=aa11'}", 'procedure TFoo.Run;', 'begin', '  fData := 1;', '  fData := fData + 1;', 'end;', '{$ENDREGION}', '',
    "{`$REGION 'DB-RAD 2 hash=bb22'}", 'function TFoo.Get: Integer;', 'begin', '  Result := fData;', 'end;', '{$ENDREGION}', '', 'end.')
  $fx = Join-Path $work 'fx'; New-Item -ItemType Directory -Path $fx -Force | Out-Null
  $pas = Join-Path $fx 'uIdxu.pas'
  [IO.File]::WriteAllText($pas, (($L -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $db = Join-Path $work 'fx.sqlite'
  $ErrorActionPreference = 'Continue'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db *> (Join-Path $work 'index.log') | ForEach-Object { "$_" } }
  Check ($LASTEXITCODE -eq 0) 'fixture indexed'
  # 1 outline regions
  $o = (& { $ErrorActionPreference = 'Continue'; & $Exe outline --in $pas --db $db --json 2>$null | ForEach-Object { "$_" } } | Out-String | ConvertFrom-Json | ForEach-Object { $_ })
  $reg = @($o | Where-Object { $_.kind -eq 'region' })
  Check ($reg.Count -eq 2) "outline lists 2 region rows (got $($reg.Count))"
  if ($reg.Count -eq 2) {
    Check (($reg[0].line -eq 16) -and ($reg[0].end_line -eq 22) -and ($reg[0].name -eq 'DB-RAD 1 hash=aa11')) 'region 1 id and span 16-22'
    Check (($reg[1].line -eq 24) -and ($reg[1].end_line -eq 29)) 'region 2 span 24-29'
  }
  $t = (& { $ErrorActionPreference = 'Continue'; & $Exe outline --in $pas --db $db 2>$null | ForEach-Object { "$_" } } | Out-String)
  Check ($t -match 'region\s+DB-RAD 1 hash=aa11\s+16-22') 'text outline prints the region row'
  # 2 usages wide
  $j = (& { $ErrorActionPreference = 'Continue'; & $Exe usages --name fData --width wide --db $db --json 2>$null | ForEach-Object { "$_" } } | Out-String | ConvertFrom-Json | ForEach-Object { $_ })
  $want = $j.reads.Count + $j.writes.Count
  $w = (& { $ErrorActionPreference = 'Continue'; & $Exe usages --name fData --width wide --db $db 2>$null | ForEach-Object { "$_" } } | Out-String) -split "`r?`n"
  $sites = @($w | Where-Object { $_ -match '^\s+(reads|writes|calls)\s+\S+:\d+:\d+' })
  Check (($want -ge 4) -and ($sites.Count -eq $want)) "usages wide: $($sites.Count) site rows = json count $want"
  $n = (& { $ErrorActionPreference = 'Continue'; & $Exe usages --name fData --width narrow --db $db 2>$null | ForEach-Object { "$_" } } | Out-String) -split "`r?`n"
  Check (@($n | Where-Object { $_ -match '^\s+(reads|writes|calls)\s+\S+:\d+:\d+' }).Count -eq 0) 'control: narrow prints no site rows'
  # 3 find-callers read/write
  $fc = (& { $ErrorActionPreference = 'Continue'; & $Exe query find-callers --name fData --db $db 2>$null | ForEach-Object { "$_" } } | Out-String) -split "`r?`n"
  $wr = @($fc | Where-Object { $_ -match ':\d+:\d+\s+fData.*\[write\]' })
  $rd = @($fc | Where-Object { $_ -match ':\d+:\d+\s+fData.*\[read\]' })
  Check ($wr.Count -eq 2) "find-callers lists the 2 write sites marked [write] (got $($wr.Count))"
  Check ($rd.Count -eq 2) "find-callers marks the 2 read sites [read] (got $($rd.Count))"
  # 4 sql ampersand
  $q = (& { $ErrorActionPreference = 'Continue'; & $Exe sql --db $db --query "select '&a' as x" 2>$null | ForEach-Object { "$_" } } | Out-String)
  Check ($q -match '&a') 'sql --query keeps & literal'
  if ($script:fail -gt 0) { Write-Host "V156 IDXU: FAIL ($script:fail)" -ForegroundColor Red; exit 1 }
  Write-Host 'V156 IDXU: PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
}
