<#
  run_v152_TTFINISH_prepare_queries.ps1 -- 1.52 lane BK-TTFINISH U6: `repo gen-param-array
  --prepare-queries` (the IDE assistant's query preparation as a DFM + unit rewrite).
  Fixture project tests\fieldrepo\paramarray\prepproj (PrepDemo: uLoad = a SELECT TFDQuery with an
  update object, a schema adapter and persistent fields; stub classes, {$R *.dfm} compiles the DFM).
  Every case runs the real exe on a COPY under %TEMP%.
    control  : without --prepare-queries the SELECT query has no params -> no-block, exit 1, nothing written
    print    : --prepare-queries alone prints the block for the INSERT params, writes nothing
    plan     : --plan prints the .dfm and .pas diffs, writes nothing (hash check)
    apply    : --apply writes BOTH files through ONE compile gate; DFM stays 7-bit ASCII CRLF
    rollback : code that still uses a removed field -> the gate refuses, bytes identical (POSITIVE CONTROL)
  Needs RAD Studio (the gate builds the fixture, Win64). A missing exe / compiler is a FAIL, never a skip.
  RED before the change: the CLI rejected --prepare-queries ("Unknown argument", exit 3).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-genpa-prep-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  ok   $Name" } else { $script:Fail++; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixture = Join-Path $Repo 'tests\fieldrepo\paramarray\prepproj'

function New-Copy([string]$Name) {
  $d = Join-Path $WorkDir $Name
  [IO.Directory]::CreateDirectory($d) | Out-Null
  Copy-Item "$Fixture\*" $d -Recurse -Force
  return $d
}
function Run([string[]]$CliArgs) {
  $o = Join-Path $WorkDir 'o.txt'; $e = Join-Path $WorkDir 'e.txt'
  & { $ErrorActionPreference = 'Continue'; & $Exe @CliArgs > $o 2> $e }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}
function Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.FullName -notmatch '\\(Win64|Win32)\\|\.BCK|\.res$|\.identcache$' } | Sort-Object FullName |
    ForEach-Object { "$($_.Name):$((Get-FileHash $_.FullName -Algorithm SHA256).Hash)" }) -join ';'
}
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null

# control: the unprepared DFM has no parameterised query
$w = New-Copy 'control'
$h = Hash $w
$r = Run @('repo', 'gen-param-array', '--in', "$w\uLoad.pas", '--plan')
Check 'control: no --prepare-queries -> no-block, exit 1' (($r.Code -eq 1) -and ($r.Err -match 'no-block')) "exit $($r.Code) err [$($r.Err)]"
Check 'control: nothing written' ((Hash $w) -eq $h)

# print
$w = New-Copy 'print'
$h = Hash $w
$r = Run @('repo', 'gen-param-array', '--in', "$w\uLoad.pas", '--prepare-queries')
Check 'print: exit 0' ($r.Code -eq 0) "exit $($r.Code) err [$($r.Err)]"
Check 'print: block uses the INSERT params' ($r.Out -match 'parNEW_ID\s+= 0;' -and $r.Out -match 'parNEW_NAME\s+= 1;') $r.Out
Check 'print: preparation reported' ($r.Err -match 'prepare-queries: qryFOLDERS; renamed updFOLDERS -> ZZZupdFOLDERS, SA1 -> ZZZSA1; 2 persistent field') $r.Err
Check 'print: nothing written' ((Hash $w) -eq $h)

# plan
$w = New-Copy 'plan'
$h = Hash $w
$r = Run @('repo', 'gen-param-array', '--in', "$w\uLoad.pas", '--prepare-queries', '--plan')
Check 'plan: exit 0' ($r.Code -eq 0) "exit $($r.Code) err [$($r.Err)]"
Check 'plan: dfm diff' ($r.Out.Contains("--- a/uLoad.dfm") -and $r.Out.Contains("+    ObjectView = False") -and $r.Out.Contains("-    CachedUpdates = True") -and $r.Out.Contains("+  object ZZZupdFOLDERS: TFDUpdateSQL")) $r.Out
Check 'plan: pas diff' ($r.Out.Contains("--- a/uLoad.pas") -and $r.Out.Contains("-    qryFOLDERSID: TIntegerField;") -and $r.Out.Contains("+    ZZZSA1: TFDSchemaAdapter;") -and $r.Out.Contains("+{")) $r.Out
Check 'plan: nothing written' ((Hash $w) -eq $h)
$r = Run @('repo', 'gen-param-array', '--in', "$w\uLoad.pas", '--prepare-queries', '--plan', '--json')
$j = $null; try { $j = $r.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
Check 'plan --json: prepare object' (($null -ne $j) -and ($j.units[0].prepare.queries[0] -eq 'qryFOLDERS') -and (@($j.units[0].prepare.removed_fields).Count -eq 2)) $r.Out

# apply
$w = New-Copy 'apply'
$r = Run @('repo', 'gen-param-array', '--in', "$w\uLoad.pas", '--prepare-queries', '--apply', '--project', "$w\PrepDemo.dproj")
Check 'apply: exit 0' ($r.Code -eq 0) "exit $($r.Code) out [$($r.Out)] err [$($r.Err)]"
$dfm = [IO.File]::ReadAllText("$w\uLoad.dfm")
$pas = [IO.File]::ReadAllText("$w\uLoad.pas")
Check 'apply: dfm prepared' ($dfm.Contains("object ZZZupdFOLDERS: TFDUpdateSQL") -and $dfm.Contains("ParamData = <") -and -not $dfm.Contains("CachedUpdates") -and -not $dfm.Contains("qryFOLDERSID")) $dfm
Check 'apply: pas edited + block inserted' ((-not $pas.Contains("qryFOLDERSID: TIntegerField;")) -and $pas.Contains("ZZZupdFOLDERS: TFDUpdateSQL;") -and $pas.Contains("parNEW_ID")) $pas
$bytes = [IO.File]::ReadAllBytes("$w\uLoad.dfm")
$bad = @($bytes | Where-Object { $_ -gt 127 }).Count
Check 'apply: dfm 7-bit ASCII, CRLF only' (($bad -eq 0) -and -not ($dfm -match "[^`r]`n")) "non-ascii $bad"
Check 'apply: backups exist' ((@(Get-ChildItem $w -Filter '*.BCK*' -Recurse).Count) -ge 2) ((Get-ChildItem $w -Recurse -File | ForEach-Object Name) -join ',')

# rollback: a code use of a removed persistent field breaks the build -> the gate restores both files
$w = New-Copy 'rollback'
$p = "$w\uLoad.pas"
[IO.File]::WriteAllText($p, [IO.File]::ReadAllText($p).Replace("{`$R *.dfm}`r`n", "{`$R *.dfm}`r`n`r`nprocedure UseIt(pF: TfrmLoad);`r`nbegin`r`n  pF.qryFOLDERSID.Free;`r`nend;`r`n"), [Text.Encoding]::ASCII)
$h = Hash $w
$r = Run @('repo', 'gen-param-array', '--in', "$w\uLoad.pas", '--prepare-queries', '--apply', '--project', "$w\PrepDemo.dproj")
Check 'rollback: refused, exit 1' ($r.Code -eq 1) "exit $($r.Code) out [$($r.Out)] err [$($r.Err)]"
Check 'rollback: both files byte-identical' ((Hash $w) -eq $h)

Write-Host ("Summary: pass={0} fail={1}" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
