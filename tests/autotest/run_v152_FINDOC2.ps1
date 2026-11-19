<#
  run_v152_FINDOC2.ps1 -- 1.52 lane FINDOC2: the doc-apply follow-ups left by
  FINDOC (INT #53). Every case was RED on the base engine before the fix.

  CASES
    * STALE-DRY   (a)+(d) `document --project` DRY RUN on an index whose fact
                  sources changed since indexing (a callee unit rewritten, no
                  reindex -- DOCAPPLY FOUND 3, FINDOC item 5): REPORTS it (a
                  WARN naming the file, exit 0, the preview still rendered),
                  it does not refuse and it does not stay silent.
    * STALE-JSON  the same dry run under --json: ONE JSON document carrying
                  "staleFactSources": N (and 0 on a fresh index -- control).
    * STALE-APPLY the same with --apply: REFUSED, exit 1, every file
                  byte-identical (a write would carry the shifted facts).
    * STALE-ALL   document-all --apply on the same stale index: refused too.
    * STALE-FIX   --apply --reindex on the same tree: reindexes first, exit 0,
                  and the written block cites the right exception (control:
                  the refusal is about staleness, not about the fixture).
    * REIDX-JSON  (b) `document --project --apply --reindex --json`: stdout is
                  ONE JSON document (the two "Reindexing" notes and the
                  in-process indexer's stage:/Done. lines are not on stdout).
    * D2-JSON     (c) the D-2 stale-anchor retry (`--qname ... --apply --json`
                  and `--unit ... --apply --json` on a shifted own file): stdout
                  is ONE JSON document; control: the retry fired (its line is on
                  stderr) and the unit was written.
    * TEXT-CTRL   text mode keeps the D-2 and --reindex lines on stdout.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "dl-v152-findoc2-$PID")
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0; $script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
}
function Write-Ascii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function New-Fixture([string]$Root) {
  # Root\App.dpr, uApp.pas (AppDo calls uCore.Raiser), uCore.pas (Raiser raises ECoreFail)
  New-Item -ItemType Directory (Join-Path $Root '_D-RAG') -Force | Out-Null
  Write-Ascii (Join-Path $Root 'uCore.pas') @(
    'unit uCore;', 'interface', 'uses System.SysUtils;', 'type',
    '  ECoreFail = class(Exception);',
    'procedure Raiser(const N: Integer);',
    'implementation',
    'procedure Raiser(const N: Integer);',
    'begin',
    "  if N > 1 then raise ECoreFail.Create('core');",
    'end;',
    'end.')
  Write-Ascii (Join-Path $Root 'uApp.pas') @(
    'unit uApp;', 'interface',
    '/// <summary>Runs the app.</summary>',
    'function AppDo(const N: Integer): Integer;',
    'implementation',
    'uses uCore;',
    'function AppDo(const N: Integer): Integer;',
    'begin',
    '  Raiser(N);',
    '  Result := N;',
    'end;',
    'end.')
  Write-Ascii (Join-Path $Root 'App.dpr') @(
    'program App;', 'uses', "  uCore in 'uCore.pas',", "  uApp in 'uApp.pas';",
    'begin', '  Writeln(AppDo(1));', 'end.')
  $db = Join-Path $Root '_D-RAG\App.sqlite'
  $null = & $Exe index --project (Join-Path $Root 'App.dpr') --db $db 2>&1
  [pscustomobject]@{ Root = $Root; Db = $db; Proj = (Join-Path $Root 'App.dpr')
    Core = (Join-Path $Root 'uCore.pas'); App = (Join-Path $Root 'uApp.pas') }
}
# Runs the exe in the fixture folder; stdout and stderr captured apart.
function Run($Fx, [string[]]$A) {
  $errFile = Join-Path $WorkDir ("err-{0}.txt" -f [guid]::NewGuid().ToString('N'))
  Push-Location $Fx.Root
  try { $out = & $Exe @A --db $Fx.Db 2>$errFile | Out-String; $code = $LASTEXITCODE }
  finally { Pop-Location }
  [pscustomobject]@{ Out = $out; Err = [IO.File]::ReadAllText($errFile); Code = $code }
}
function Parse-One([string]$Text) {
  try { return ($Text | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}
# Shift every line of a unit down: N comment lines right after 'implementation'.
function Shift-Impl([string]$Path, [int]$N) {
  $l = [Collections.Generic.List[string]]::new([IO.File]::ReadAllLines($Path))
  $i = $l.IndexOf('implementation')
  for ($k = 0; $k -lt $N; $k++) { $l.Insert($i + 1, "{ shifted $k }") }
  Write-Ascii $Path $l.ToArray()
}
function Snap($Fx) { ([IO.File]::ReadAllText($Fx.Core)) + '|' + ([IO.File]::ReadAllText($Fx.App)) }

New-Item -ItemType Directory $WorkDir -Force | Out-Null
try {
  Write-Host '(a)+(d) stale fact sources: dry run reports, --apply refuses' -ForegroundColor Cyan
  $fx = New-Fixture (Join-Path $WorkDir 'stale')
  $fresh = Run $fx @('document', '--project', $fx.Proj, '--json')
  $fj = Parse-One $fresh.Out
  Check 'STALE-JSON control: fresh index -> staleFactSources is 0' (($null -ne $fj) -and ($fj.PSObject.Properties.Name -contains 'staleFactSources') -and ($fj.staleFactSources -eq 0)) "out=$($fresh.Out.Trim())"
  $f0 = Run $fx @('document', '--project', $fx.Proj)
  Check 'STALE-DRY control: fresh preview cites ECoreFail' ($f0.Out -match 'ECoreFail') ''

  Shift-Impl $fx.Core 6
  $before = Snap $fx
  $d = Run $fx @('document', '--project', $fx.Proj)
  $all = $d.Out + $d.Err
  Check 'STALE-DRY exit 0 (report, not refuse)' ($d.Code -eq 0) "exit $($d.Code)"
  Check 'STALE-DRY names the stale fact source in a WARN' ($all -match 'WARN -- \d+ file\(s\) this run reads facts from changed since it was indexed[^\r\n]*uCore\.pas') (($all -split "`r?`n" | Where-Object { $_ -match 'WARN|REFUSED' } | Select-Object -First 1))
  Check 'STALE-DRY the preview is still rendered' ($d.Out -match 'pass --apply to write') ''
  Check 'STALE-DRY wrote nothing' ((Snap $fx) -ceq $before) ''

  $dj = Run $fx @('document', '--project', $fx.Proj, '--json')
  $p = Parse-One $dj.Out
  Check 'STALE-JSON stdout is ONE JSON document' ($null -ne $p) "out=$($dj.Out.Trim())"
  Check 'STALE-JSON staleFactSources >= 1' (($null -ne $p) -and ($p.staleFactSources -ge 1)) ''

  $a = Run $fx @('document', '--project', $fx.Proj, '--apply', '--no-backup')
  Check 'STALE-APPLY refused, exit 1' (($a.Code -eq 1) -and (($a.Out + $a.Err) -match 'REFUSED')) "exit $($a.Code)"
  Check 'STALE-APPLY every file byte-identical' ((Snap $fx) -ceq $before) ''

  $aa = Run $fx @('document-all', '--apply', '--no-backup')
  Check 'STALE-ALL document-all --apply refused, exit 1' (($aa.Code -eq 1) -and (($aa.Out + $aa.Err) -match 'REFUSED')) "exit $($aa.Code)"
  Check 'STALE-ALL every file byte-identical' ((Snap $fx) -ceq $before) ''

  $r = Run $fx @('document', '--project', $fx.Proj, '--apply', '--reindex', '--no-backup')
  Check 'STALE-FIX --apply --reindex: exit 0' ($r.Code -eq 0) "exit $($r.Code) $(($r.Out + $r.Err) -split "`r?`n" | Where-Object { $_ -match 'REFUSED' } | Select-Object -First 1)"
  Check 'STALE-FIX the written block cites ECoreFail' (([IO.File]::ReadAllText($fx.App)) -match 'cref="ECoreFail"') ''

  Write-Host ''
  Write-Host '(b) --apply --reindex --json: one JSON document' -ForegroundColor Cyan
  $fx = New-Fixture (Join-Path $WorkDir 'reidx')
  $b = Run $fx @('document', '--project', $fx.Proj, '--apply', '--reindex', '--json', '--no-backup')
  $bj = Parse-One $b.Out
  $junk = ($b.Out -split "`r?`n" | Where-Object { $_ -match '^(stage:|Done\.|rule-cache:|Reindexing|Indexing|resolve:)' } | Measure-Object).Count
  Check 'REIDX-JSON stdout parses as ONE JSON document' ($null -ne $bj) "non-JSON lines on stdout: $junk"
  Check 'REIDX-JSON control: the run applied' (($b.Code -eq 0) -and (([IO.File]::ReadAllText($fx.App)) -match 'drag-lint:auto')) "exit $($b.Code)"
  $fx = New-Fixture (Join-Path $WorkDir 'reidxt')
  $bt = Run $fx @('document', '--project', $fx.Proj, '--apply', '--reindex', '--no-backup')
  Check 'TEXT-CTRL text mode still prints the Reindexing notes on stdout' ($bt.Out -match 'Reindexing \(INCREMENTAL\)') ''

  Write-Host ''
  Write-Host '(c) D-2 stale-anchor retry under --json' -ForegroundColor Cyan
  foreach ($mode in @('qname', 'unit')) {
    $fx = New-Fixture (Join-Path $WorkDir "d2$mode")
    [IO.File]::WriteAllText($fx.App, "{ shifted }`r`n" + [IO.File]::ReadAllText($fx.App), [Text.Encoding]::ASCII)
    $sel = if ($mode -eq 'qname') { @('--qname', 'uApp.AppDo') } else { @('--unit', $fx.App) }
    $c = Run $fx (@('document') + $sel + @('--apply', '--json', '--no-backup'))
    $cj = Parse-One $c.Out
    Check "D2-JSON --$mode stdout parses as ONE JSON document" ($null -ne $cj) "out=$(($c.Out -split "`r?`n" | Select-Object -First 2) -join ' | ')"
    Check "D2-JSON --$mode control: the D-2 retry fired (stderr)" ($c.Err -match 'reindexing and retrying once') ''
    Check "D2-JSON --$mode control: the unit was written" (([IO.File]::ReadAllText($fx.App)) -match 'drag-lint:auto') "exit $($c.Code)"
  }
  $fx = New-Fixture (Join-Path $WorkDir 'd2text')
  [IO.File]::WriteAllText($fx.App, "{ shifted }`r`n" + [IO.File]::ReadAllText($fx.App), [Text.Encoding]::ASCII)
  $ct = Run $fx @('document', '--qname', 'uApp.AppDo', '--apply', '--no-backup')
  Check 'TEXT-CTRL text mode still prints the D-2 line on stdout' ($ct.Out -match 'reindexing and retrying once') ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("pass={0} fail={1}" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
