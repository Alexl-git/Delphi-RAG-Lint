<#
  run_v153_BUGS_config_indexed_project.ps1 -- `lint-all --db <copy>` uses the lint config of the INDEXED
  project (v153 lane BUGS; docs\INBOX-lint-all-db-copy-misses-project-config.md).

  A project index copied to a scratch folder has no drag-lint-lint.json at or above it, so the
  project's rulings were silently dropped. The index itself names its project: project_tag plus the
  indexed .dpr / .dpk row.

    C1  control: the original index in <project>\_D-RAG applies the config (magic-literal fires)
    C2  a copy at an unrelated folder, cwd unrelated: the same findings for the rule
    C3  the same copy with --project (project in a subfolder, config at the repo root above it)
    C4  control: an explicit --config still wins over the indexed project
    C5  control: a config beside the copy still wins (more specific than the index)
    C6  --json on the copy: one parseable document on stdout, no note on stderr
    C7  the project folder is gone: one stderr note names the places looked, once
    C8  the same under --json: no note
    C9  control: a folder-scan index (no project) without a config: no note
    C10 control: the project exists and has no config: no note
    C11 project settings (_D-RAG\drag-lint-project.json lint.config) also follow the indexed project
    C12 a package project (.dpk)

  Usage: pwsh -File tests\autotest\run_v153_BUGS_config_indexed_project.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$WorkDir = "$env:TEMP\draglint-v153-cfgidx-$PID")
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Fail = 0; $script:Pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Fail++; Write-Host "  [FAIL] $Name -- $Detail" -ForegroundColor Red }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Invoke-Dl([string[]]$Arguments) {
  $o = "$WorkDir\o.txt"; $e = "$WorkDir\e.txt"
  $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -WorkingDirectory "$WorkDir\cwd" `
         -RedirectStandardOutput $o -RedirectStandardError $e; $null = $p.Handle
  [pscustomobject]@{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}
function Magic([string]$Text) { return , @(($Text -split "`r?`n") | Where-Object { $_ -match ':\d+:\d+\s+\[\w+\]\s+magic-literal' } | Sort-Object) }
# The note's stable words; the positive control is C7.
$notePat = 'no drag-lint-lint\.json was found'
$src = "interface`nfunction Scale(AValue: Integer): Integer;`nimplementation`nfunction Scale(AValue: Integer): Integer;`nbegin`n  Result := AValue * 8675309;`nend;`nend.`n"
function New-Project([string]$Root, [string]$Ext = 'dpr') {
  New-Item -ItemType Directory -Path "$Root\app" -Force | Out-Null
  if ($Ext -eq 'dpr') { Write-Ascii "$Root\app\App.dpr" "program App;`nuses`n  M in 'M.pas';`nbegin`nend.`n" }
  else { Write-Ascii "$Root\app\App.dpk" "package App;`nrequires`n  rtl;`ncontains`n  M in 'M.pas';`nend.`n" }
  Write-Ascii "$Root\app\M.pas" ("unit M;`n" + $src)
  $null = Invoke-Dl @('index', '--project', "$Root\app\App.$Ext", '--db', "$Root\app\_D-RAG\App.sqlite")
}
function New-Copy([string]$Root, [string]$Name) {
  New-Item -ItemType Directory -Path "$WorkDir\copies\$Name" -Force | Out-Null
  [IO.File]::Copy("$Root\app\_D-RAG\App.sqlite", "$WorkDir\copies\$Name\p.sqlite")
  return "$WorkDir\copies\$Name\p.sqlite"
}
try {
  New-Item -ItemType Directory -Path "$WorkDir\cwd", "$WorkDir\copies" -Force | Out-Null
  New-Project "$WorkDir\repo"
  Write-Ascii "$WorkDir\repo\drag-lint-lint.json" '{ "enabled": ["magic-literal"] }'
  Write-Ascii "$WorkDir\other.json" '{ "disabled": ["magic-literal"] }'
  $db = New-Copy "$WorkDir\repo" 'c1'

  $c1 = Invoke-Dl @('lint-all', '--db', "$WorkDir\repo\app\_D-RAG\App.sqlite")
  $m1 = Magic $c1.Out
  Check 'C1 control: the original index applies the repo config' ($m1.Count -gt 0) "exit=$($c1.Exit) out=$($c1.Out)"
  $c2 = Invoke-Dl @('lint-all', '--db', $db)
  Check 'C2 a copy of the index applies the same config' (($m1.Count -gt 0) -and (((Magic $c2.Out) -join "`n") -eq ($m1 -join "`n"))) "exit=$($c2.Exit) got=$((Magic $c2.Out).Count) want=$($m1.Count)"
  $c3 = Invoke-Dl @('lint-all', '--db', $db, '--project', "$WorkDir\repo\app\App.dpr")
  Check 'C3 a copy + --project finds the config above the project' ((Magic $c3.Out).Count -gt 0) "exit=$($c3.Exit)"
  $c4 = Invoke-Dl @('lint-all', '--db', $db, '--config', "$WorkDir\other.json")
  Check 'C4 control: --config wins' (($c4.Out -match 'scanned') -and ((Magic $c4.Out).Count -eq 0)) "exit=$($c4.Exit) $($c4.Out)"
  $db5 = New-Copy "$WorkDir\repo" 'c5'
  [IO.File]::Copy("$WorkDir\other.json", "$WorkDir\copies\c5\drag-lint-lint.json")
  $c5 = Invoke-Dl @('lint-all', '--db', $db5)
  Check 'C5 control: a config beside the copy wins' (($c5.Out -match 'scanned') -and ((Magic $c5.Out).Count -eq 0)) "exit=$($c5.Exit)"
  $c6 = Invoke-Dl @('lint-all', '--db', $db, '--json')
  $j6 = @(); try { $j6 = @($c6.Out | ConvertFrom-Json) } catch { $j6 = @() }
  Check 'C6 --json on the copy: parseable, the rule is there, no note' (($j6.Count -gt 0) -and ($c6.Out -match '"magic-literal"') -and ($c6.Err -notmatch $notePat)) "err=[$($c6.Err)] out=$($c6.Out.Substring(0, [Math]::Min(300, $c6.Out.Length)))"

  # A project whose folder no longer exists (an index from another machine / a deleted checkout).
  New-Project "$WorkDir\gone"
  $db7 = New-Copy "$WorkDir\gone" 'c7'
  [IO.Directory]::Delete("$WorkDir\gone", $true)
  $c7 = Invoke-Dl @('lint-all', '--db', $db7)
  Check 'C7 project folder gone: one stderr note, naming --config and the DB folder' ((([regex]::Matches($c7.Err, $notePat)).Count -eq 1) -and ($c7.Err -match '--config') -and ($c7.Err.Contains("$WorkDir\copies\c7"))) "err=[$($c7.Err)]"
  $c8 = Invoke-Dl @('lint-all', '--db', $db7, '--json')
  Check 'C8 the same under --json: no note' (($c8.Err + $c8.Out) -notmatch $notePat) "err=[$($c8.Err)]"
  New-Item -ItemType Directory -Path "$WorkDir\folder" -Force | Out-Null
  Write-Ascii "$WorkDir\folder\N.pas" "unit N;`ninterface`nimplementation`nend.`n"
  $null = Invoke-Dl @('index', "$WorkDir\folder", '--db', "$WorkDir\copies\folder.sqlite")
  $c9 = Invoke-Dl @('lint-all', '--db', "$WorkDir\copies\folder.sqlite")
  Check 'C9 control: folder-scan index: no note' (($c9.Out -match 'scanned') -and (($c9.Err + $c9.Out) -notmatch $notePat)) "out=[$($c9.Out)] err=[$($c9.Err)]"
  New-Project "$WorkDir\bare"
  $db10 = New-Copy "$WorkDir\bare" 'c10'
  $c10 = Invoke-Dl @('lint-all', '--db', $db10)
  Check 'C10 control: project exists without a config: no note' (($c10.Out -match 'scanned') -and (($c10.Err + $c10.Out) -notmatch $notePat)) "err=[$($c10.Err)]"

  New-Project "$WorkDir\setproj"
  Write-Ascii "$WorkDir\setproj\app\rules.json" '{ "enabled": ["magic-literal"] }'
  Write-Ascii "$WorkDir\setproj\app\_D-RAG\drag-lint-project.json" '{ "lint": { "config": "rules.json" } }'
  $s0 = Invoke-Dl @('lint-all', '--db', "$WorkDir\setproj\app\_D-RAG\App.sqlite")
  $db11 = New-Copy "$WorkDir\setproj" 'c11'
  $c11 = Invoke-Dl @('lint-all', '--db', $db11)
  Check 'C11 control: the project setting lint.config applies to the original index' ((Magic $s0.Out).Count -gt 0) "err=$($s0.Err)"
  Check 'C11 the project setting lint.config follows the copy' ((Magic $c11.Out).Count -gt 0) "err=$($c11.Err)"

  New-Project "$WorkDir\pkg" 'dpk'
  Write-Ascii "$WorkDir\pkg\drag-lint-lint.json" '{ "enabled": ["magic-literal"] }'
  $p0 = Invoke-Dl @('lint-all', '--db', "$WorkDir\pkg\app\_D-RAG\App.sqlite")
  $db12 = New-Copy "$WorkDir\pkg" 'c12'
  $c12 = Invoke-Dl @('lint-all', '--db', $db12)
  Check 'C12 control: the package index applies the config' ((Magic $p0.Out).Count -gt 0) "out=$($p0.Out)"
  Check 'C12 a copy of a package index applies the config' ((Magic $c12.Out).Count -gt 0) "out=$($c12.Out) err=$($c12.Err)"
}
finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host "run_v153_BUGS_config_indexed_project: $script:Pass pass, $script:Fail fail"
exit $(if ($script:Fail) { 1 } else { 0 })
