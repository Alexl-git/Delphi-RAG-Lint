<#
  run_library_ancestry_rules.ps1 -- the 1.45 F1 rules with a type whose ancestry is in the LIBRARY.

  WHY. The lanes' fixtures close every ancestry inside the project, and real code does not: most
  drops need TLabel, TStringList, TThread. A checker that hands nil to TExprTypeReader gets tdUnknown
  for all of them, keeps today's answer, and every fixture stays green. And lint-all read a named
  --library-db nowhere, so a run with the flag answered like a run without it.

  One family per checker that reads an ancestry. Three runs on one index:
    lint-all --library-db <lib>   exactly BOTH + LIB-ONLY lines
    lint-all --library-db none    exactly BOTH + LIB-SILENT lines (the control: the drop needs the store)
    lint <file> --rule R --library-db <lib>   the same as lint-all, so a --rule run opens the store too

  Plus the flag itself: a named library that does not exist is refused, exit 2.

  Usage: pwsh -File tests\autotest\run_library_ancestry_rules.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$tmp = Join-Path $env:TEMP "draglint_libanc_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$libSrc = Join-Path $tmp 'lib'
$prjSrc = Join-Path $tmp 'proj'
[void][IO.Directory]::CreateDirectory($libSrc)
[void][IO.Directory]::CreateDirectory($prjSrc)
Copy-Item (Join-Path $repo 'tests\lint-project\library-ancestry\lib\*.pas') $libSrc
Copy-Item (Join-Path $repo 'tests\lint-project\library-ancestry\proj\*.pas') $prjSrc
$unit = Join-Path $prjSrc 'uLibUse.pas'
$lib = Join-Path $tmp 'lib.sqlite'
$db = Join-Path $tmp 'proj.sqlite'
$cfg = Join-Path $tmp 'empty.json'
[IO.File]::WriteAllText($cfg, '{}')

$script:fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function Parse-Findings($Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { try { $all = @($txt.Substring($b) | ConvertFrom-Json) } catch { $all = @() } }
  return ,@($all)
}
function Lines($Findings, [string]$Rule) {
  $s = @($Findings | Where-Object { $_.rule -eq $Rule -and $_.file_path -like '*uLibUse*' } |
    ForEach-Object { [int]$_.start_line } | Sort-Object -Unique)
  return ($s -join ',')
}
function Markers([string]$Fam, [string[]]$Kinds) {
  $res = @()
  foreach ($k in $Kinds) {
    $res += @(Select-String -Path $unit -Pattern "// $k-$Fam\b" | ForEach-Object { [int]$_.LineNumber })
  }
  return ((@($res | Sort-Object -Unique)) -join ',')
}

# family -> rule. Each is one checker that takes its verdict from an ancestry.
$families = [ordered]@{
  DS     = 'dataset-open-without-close'         # AstChecks.CheckDatasetOpen
  LOCK   = 'wait-while-holding-lock'            # ConcurrencyChecks
  THREAD = 'exception-escapes-thread'           # ExceptionThreadChecks
  NET    = 'network-client-without-timeout'     # ExceptionThreadChecks / ConcurrencyChecks
  ENC    = 'default-encoding-io'                # DeadCodeChecks
  EXC    = 'exception-constructed-but-not-raised' # DeadCodeChecks
  SLEEP  = 'sleep-in-vcl'                       # .scm through ITypeOracle
  FBN    = 'field-by-name-in-loop'              # .scm through ITypeOracle
  DDL    = 'double-dictionary-lookup'           # ExprChecks through ITypeOracle
  UBA    = 'used-before-assignment'             # FlowChecks.TMethodArgModes
  UI     = 'ui-access-in-thread-typed'          # RefTypeRules, OFF by default
  MIX    = 'interface-object-mixing'            # AstChecks.CheckTypeAware, OFF by default
  CTOR   = 'constructor-call-on-instance'       # .scm, ITypeOracle.IsMetaclass
}

$enable = 'ui-access-in-thread-typed,default-encoding-io,interface-object-mixing'
Push-Location $tmp
try {
  & $exePath index $libSrc --db $lib 2>&1 | Out-Null
  & $exePath index $prjSrc --db $db --library-db $lib 2>&1 | Out-Null
  Check 'both indexes built' ((Test-Path $lib) -and (Test-Path $db))

  $common = @('--db', $db, '--json', '--quiet', '--config', $cfg, '--enable', $enable)
  $with = Parse-Findings (& $exePath lint-all @common --library-db $lib 2>$null)
  $none = Parse-Findings (& $exePath lint-all @common --library-db none 2>$null)
  Check 'lint-all with the library answered' ($with.Count -gt 0) 'no findings at all'
  Check 'lint-all with none answered' ($none.Count -gt 0) 'no findings at all'

  foreach ($fam in $families.Keys) {
    $rule = $families[$fam]
    $wantWith = Markers $fam @('BOTH', 'LIB-ONLY')
    $wantNone = Markers $fam @('BOTH', 'LIB-SILENT')
    $gotWith = Lines $with $rule
    $gotNone = Lines $none $rule
    Check "[$fam] $rule lint-all with library" ($gotWith -eq $wantWith) "want [$wantWith] got [$gotWith]"
    Check "[$fam] $rule lint-all --library-db none (control)" ($gotNone -eq $wantNone) "want [$wantNone] got [$gotNone]"
    Check "[$fam] the two runs differ" ($wantWith -ne $wantNone) 'fixture proves nothing'
    $one = Parse-Findings (& $exePath lint $unit --db $db --json --quiet --config $cfg --library-db $lib --rule $rule --enable $enable 2>$null)
    $gotOne = Lines $one $rule
    Check "[$fam] $rule lint <file> --rule with library" ($gotOne -eq $wantWith) "want [$wantWith] got [$gotOne]"
  }

  # The flag: a named library that is missing refuses.
  $missing = Join-Path $tmp 'no-such-library.sqlite'
  $err = & $exePath lint-all --db $db --library-db $missing --json --quiet --config $cfg 2>&1
  $code = $LASTEXITCODE
  Check 'a named library that does not exist refuses (exit 2)' ($code -eq 2) "exit $code"
  Check 'the refusal names the path' ((($err | Out-String)).Contains('no-such-library')) ($err | Out-String)
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Host "note: could not delete $tmp" }
}
if ($script:fail -gt 0) { Write-Host "FAILED: $script:fail"; exit 1 }
Write-Host 'ALL PASS'
exit 0
