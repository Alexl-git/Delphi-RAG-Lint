<#
  run_qcli_142_guard.ps1 -- 1.42 lane qcli. Four find-callers / usages reader fixes, no extraction change.

  1 FC-QUALIFIED-HINT  plain `find-callers --name THost.Feed` answers 0 because refs.name_text holds the
                       BARE member name; the old hint pointed at `usages --name THost.Feed` (also wrong).
                       The hint must say "bare" and name the bare name, and must not recommend the dotted name.
  2 FC-GETTER-DEFAULT  plain `find-callers --name GetActive` (a property getter) stays 0 callers (kept
                       behaviour, owner default) but its hint must point at --resolved.
  3 USAGES-NO-MANIFEST `usages` with no --db never reads the manifest: exit 2, and the message must SAY so
                       (find-callers, by contrast, answers from the manifest).
  4 USAGES-DOUBLE-COUNT a qualified call `H.Feed(1)` stores a 'call' and a 'member-access' ref at one
                       position; usages counted it twice. Read-time fix: one entry per call site.

  Positive controls: --resolved still finds the getter's caller; the bare-name find-callers still finds the
  calls; two calls on ONE line (`H.Feed(3); H.Feed(4);`) stay two usages; a pure property read still counts;
  the store still holds BOTH refs at the qualified site (post-filter, not a store change).
  RED-check: run with -Exe pointing at a pre-fix engine; 1, 2, 3 and 4 fail, controls pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-qcli-$PID"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $src | Out-Null
$body = @'
unit uQ;

interface

type
  THost = class
  public
    procedure Feed(X: Integer);
  end;

  TObj = class
  private
    FActive: Boolean;
    function GetActive: Boolean;
  public
    property Active: Boolean read GetActive;
    property Raw: Boolean read FActive;
  end;

procedure Go;

implementation

procedure THost.Feed(X: Integer);
begin
end;

function TObj.GetActive: Boolean;
begin
  Result:= FActive;
end;

procedure Go;
var
  H: THost;
  O: TObj;
  B: Boolean;
begin
  H := THost.Create;
  O := TObj.Create;
  H.Feed(1);
  if O.Active then H.Feed(2);
  H.Feed(3); H.Feed(4);
  B := O.Raw;
end;

end.
'@
$srcFile = Join-Path $src 'uQ.pas'
[IO.File]::WriteAllText($srcFile, ($body -replace "`r?`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))
$db = Join-Path $WorkDir 'q.sqlite'
$code = Invoke-G8Index $Exe $src $db
Check 'fixture index built' (($code -eq 0) -and (Test-Path $db)) "exit=$code"
function Run($a) { $o = (& $Exe @a 2>&1 | ForEach-Object { "$_" }) -join "`n"; return @{ Out = $o; Code = $LASTEXITCODE } }
function LineOf($needle) { return ((Get-Content $srcFile) | Select-String -SimpleMatch $needle | Select-Object -First 1).LineNumber }

# 1 FC-QUALIFIED-HINT
$r = Run @('query', 'find-callers', '--name', 'THost.Feed', '--db', $db)
Check '1 qualified plain find-callers still answers 0 (exit 1)' ($r.Code -eq 1) "exit=$($r.Code)"
Check '1 the hint says the plain form wants the BARE name and names it' ($r.Out -match 'hint:.*bare.*Feed') ($r.Out -replace "`n", ' | ')
Check '1 the hint does not recommend usages with the dotted name' ($r.Out -notmatch 'usages --name THost\.Feed') ($r.Out -replace "`n", ' | ')
$r = Run @('query', 'find-callers', '--name', 'Feed', '--db', $db)
Check '1 CONTROL bare name finds the calls' (($r.Code -eq 0) -and ($r.Out -match '[1-9]\d* caller\(s\)')) ($r.Out -replace "`n", ' | ')
Check '1 CONTROL a bare-name hit prints no hint' ($r.Out -notmatch 'hint:') ($r.Out -replace "`n", ' | ')

# 2 FC-GETTER-DEFAULT
$r = Run @('query', 'find-callers', '--name', 'GetActive', '--db', $db)
# 146 int: since extractor 1.33 (b1, E-PARSER-NOREFS) the property's `read GetActive` is a property-spec REF, and the plain form is
# kind-blind (every site that names it), so it answers that one site. The owner default still holds: plain does not
# follow the property's readers -- uQ.Go stays a --resolved answer.
Check '2 plain find-callers on a getter answers only the property''s read specifier' (($r.Code -eq 0) -and ($r.Out -match '1 caller') -and ($r.Out -match 'read GetActive')) ($r.Out -replace "`n", ' | ')
Check '2 plain does not follow the property readers (owner default)' ($r.Out -notmatch 'uQ\.Go') ($r.Out -replace "`n", ' | ')
$r = Run @('query', 'find-callers', '--name', 'GetActive', '--resolved', '--db', $db)
Check '2 CONTROL --resolved finds the getter caller' (($r.Code -eq 0) -and ($r.Out -match 'uQ\.Go')) ($r.Out -replace "`n", ' | ')

# 3 USAGES-NO-MANIFEST
$bare = Join-Path $WorkDir 'bare'
New-Item -ItemType Directory -Force $bare | Out-Null
Copy-Item -LiteralPath $Exe -Destination $bare
Get-ChildItem -LiteralPath (Split-Path $Exe) -Filter '*.dll' | Copy-Item -Destination $bare
$bareExe = Join-Path $bare (Split-Path $Exe -Leaf)
$manifest = @{ indexes = @{ sections = @( @{ name = 'Fix'; include = @($src); db = $db } ) } } | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $bare 'drag-lint.json'), $manifest, (New-Object System.Text.ASCIIEncoding))
$cwd = Join-Path $WorkDir 'cwd'
New-Item -ItemType Directory -Force $cwd | Out-Null
Push-Location $cwd
try {
  $o = (& $bareExe usages --name Feed 2>&1 | ForEach-Object { "$_" }) -join "`n"; $c = $LASTEXITCODE
  Check '3 usages with a manifest beside the exe and no --db exits 2' ($c -eq 2) "exit=$c"
  Check '3 the message says usages does not read the manifest and asks for --db' (($o -match 'does not read the manifest') -and ($o -match '--db')) ($o -replace "`n", ' | ')
  $o = (& $bareExe query find-callers --name Feed 2>&1 | ForEach-Object { "$_" }) -join "`n"; $c = $LASTEXITCODE
  Check '3 CONTROL find-callers with the same manifest answers without --db' (($c -eq 0) -and ($o -match '[1-9]\d* caller\(s\)')) "exit=$c $($o -replace "`n", ' | ')"
} finally { Pop-Location }

# 4 USAGES-DOUBLE-COUNT
$r = Run @('usages', '--name', 'Feed', '--db', $db, '--json')
$j = $r.Out | ConvertFrom-Json
$all = @($j.calls) + @($j.reads)
$sites = @($all | ForEach-Object { "$($_.line):$($_.col)" })
Check '4 four H.Feed(..) call sites are four usages, not eight' ($all.Count -eq 4) "calls=$(@($j.calls).Count) reads=$(@($j.reads).Count)"
Check '4 no position is listed twice' ($sites.Count -eq @($sites | Sort-Object -Unique).Count) ($sites -join ',')
$lnTwo = LineOf 'H.Feed(3); H.Feed(4);'
Check "4 POSITIVE CONTROL two calls on one line (line $lnTwo) stay two usages" (@($sites | Where-Object { $_ -like "$lnTwo`:*" }).Count -eq 2) ($sites -join ',')
$r = Run @('usages', '--name', 'Raw', '--db', $db, '--json')
$j = $r.Out | ConvertFrom-Json
Check '4 POSITIVE CONTROL a plain property read still counts' ((@($j.reads).Count + @($j.calls).Count) -ge 1) ($r.Out -replace "`n", ' ')
$lnOne = LineOf '  H.Feed(1);'
$r = Run @('sql', '--query', "SELECT kind FROM refs WHERE name_text='Feed' AND start_line=$lnOne", '--db', $db, '--json')
Check '4 CONTROL the store still holds BOTH refs at the qualified site (read-time fix, no store change)' (([regex]::Matches($r.Out, 'member-access|"call"')).Count -ge 2) ($r.Out -replace "`n", ' ')

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'run_qcli_142_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_qcli_142_guard: PASS' -ForegroundColor Green
exit 0
