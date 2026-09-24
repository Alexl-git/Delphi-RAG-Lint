<#
  run_config_rule_key_scope.ps1 -- a "rule" key in .drag-lint.json must not
  SILENTLY narrow a run, and must not narrow a whole-project run at all (L1).

  THE DEFECT. LoadConfigDefaults copied "rule" into AArgs.Rule for EVERY verb.
  A .drag-lint.json anywhere above the CWD that carried one turned every
  lint-all into a one-rule run whose report read as a nearly clean project, and
  nothing said so -- the only line that file ever produces is the generic
  "(loaded defaults from ...)" banner, which names no key.

  THE DECIDED SEMANTICS (documented at the key in DRagLint.CLI.pas):
    * `lint` -- the run is the file or folder the user named, so the key is a
      legitimate default. It is honoured AND announced on stderr.
    * every other verb, lint-all first -- a whole-project question. The key is
      IGNORED, and that is announced too. --rule is the one way to narrow it.
    * an explicit --rule on the command line wins, with no note.

  Positive controls: the fixture carries TWO findings of different rules, so a
  "narrowed" answer and a "not narrowed" answer are distinguishable, and the
  config file is proven to be FOUND (its note appears) before its absence of
  effect is asserted.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-config-rule-key"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, (($Body -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Run([string[]]$ArgList) {
  $o = Join-Path $WorkDir 'out.txt'
  $e = Join-Path $WorkDir 'err.txt'
  $quoted = $ArgList | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_ + '"' } else { $_ } }
  Start-Process -FilePath $Exe -ArgumentList $quoted -WorkingDirectory $WorkDir -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError $e | Out-Null
  return @{ Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory -Force (Join-Path $WorkDir '_D-RAG') | Out-Null

Write-Ascii (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  U1 in 'U1.pas';

begin
  Go;
end.
'@
$u1 = Join-Path $WorkDir 'U1.pas'
Write-Ascii $u1 @'
unit U1;

interface

procedure Go;

implementation

procedure Go;
var
  Idle: Integer;
begin
  try
    Writeln('x');
  except
    Writeln('failed');
  end;
end;

end.
'@
$db = Join-Path $WorkDir '_D-RAG\App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host "FATAL: no index" -ForegroundColor Red; exit 2 }

# Baseline with NO config: both rules fire, so narrowing is observable.
$base = Run @('lint', $u1)
Check 'CONTROL: without config, lint reports unused-local'  ($base.Out -match 'unused-local:') ''
Check 'CONTROL: without config, lint reports bare-except'   ($base.Out -match 'bare-except:') ''

# The config under test, in the CWD every run below uses.
[IO.File]::WriteAllText((Join-Path $WorkDir '.drag-lint.json'), '{ "rule": "unused-local" }', [Text.Encoding]::ASCII)

Write-Host ''
Write-Host 'lint-all: a whole-project run IGNORES the key, and says so' -ForegroundColor Cyan
$la = Run @('lint-all', '--db', $db, '--output', (Join-Path $WorkDir 'rep.txt'))
Check 'the config file was FOUND (its note is on stderr)' ($la.Err -match 'ignoring "rule": "unused-local"') 'if this fails the rest proves nothing'
Check 'lint-all still reports bare-except (NOT narrowed)'  ($la.Out -match 'bare-except:') 'RED = the defaults file narrowed a whole-project run'
Check 'lint-all still reports unused-local'                ($la.Out -match 'unused-local:') ''

Write-Host ''
Write-Host 'lint: the named run honours the key, and ANNOUNCES it' -ForegroundColor Cyan
$l1 = Run @('lint', $u1)
Check 'lint is narrowed to unused-local'            (($l1.Out -match 'unused-local:') -and -not ($l1.Out -match 'bare-except:')) ''
Check 'and says so on stderr, naming the file'      ($l1.Err -match 'narrowed to rule "unused-local" by the "rule" key in .*\.drag-lint\.json') 'RED = narrowed in silence'

Write-Host ''
Write-Host 'an explicit --rule wins, with no note' -ForegroundColor Cyan
$l2 = Run @('lint', $u1, '--rule', 'bare-except')
Check '--rule bare-except reports bare-except'        ($l2.Out -match 'bare-except:') ''
Check 'and not unused-local'                          (-not ($l2.Out -match 'unused-local:')) ''
Check 'and prints no rule-key note'                   (-not ($l2.Err -match '"rule" key|ignoring "rule"')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
