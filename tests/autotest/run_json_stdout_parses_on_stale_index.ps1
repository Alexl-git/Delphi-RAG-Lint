<#
  run_json_stdout_parses_on_stale_index.ps1 -- on a STALE index, every
  json-emitting verb's STDOUT must still be one parseable JSON document, and the
  object envelopes must SAY the index is stale (ENG-3,
  docs\INBOX-json-format-polluted-by-staleness-note.md).

  THE DEFECT. The staleness note ("drag-lint: note: N of M indexed file(s)
  changed since this index was built ...") was reported spliced INTO a
  reverse-calltree --format json document, which then failed ConvertFrom-Json
  far from the cause -- and a parser that swallowed the failure turned three
  measurements into a filed defect that did not exist.

  WHAT THIS ASSERTS, AND WHY PARSEABILITY RATHER THAN ABSENCE. A guard that
  greps stdout for "drag-lint:" passes on an EMPTY document. So each verb's
  stdout must be non-empty AND parse. The fixture's staleness is itself
  asserted (positive control): the note must appear on STDERR, or the index was
  never stale and nothing below proved anything.

  THE ENVELOPE HALF (option 2 of the note). Stripping a note throws away a true
  fact; the object envelopes of the verbs the note named now carry
  "stale": true and "stale_files": <n>, the way sql/1 carries "truncated", so a
  consumer can surface staleness deliberately. Asserted on exactly those
  verbs, and asserted FALSE on a fresh index so a constant `true` cannot pass.

  STDOUT IS CAPTURED ALONE, to a file, never merged with stderr: merging the two
  streams is the consumer-side way to get exactly the reported symptom, and a
  test that merged them would be testing its own plumbing.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-json-stale"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$fx = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory -Force (Join-Path $fx '_D-RAG') | Out-Null

Write-Ascii (Join-Path $fx 'App.dpr') @'
program App;

uses
  U1 in 'U1.pas';

begin
  Foo;
end.
'@
$u1 = Join-Path $fx 'U1.pas'
Write-Ascii $u1 @'
unit U1;

interface

type
  /// <summary>A thing.</summary>
  TThing = class
  public
    procedure Run;
  end;

procedure Foo;
procedure Bar;

implementation

procedure Bar;
begin
end;

procedure Foo;
begin
  Bar;
end;

procedure TThing.Run;
begin
  Foo;
end;

end.
'@
$db = Join-Path $fx '_D-RAG\App.sqlite'

# One run: stdout to a file (raw, alone), stderr to another.
function Run([string[]]$ArgList) {
  $o = Join-Path $WorkDir 'out.txt'
  $e = Join-Path $WorkDir 'err.txt'
  $quoted = $ArgList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
  $p = Start-Process -FilePath $Exe -ArgumentList $quoted -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e
  return @{ Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e); Code = $p.ExitCode }
}
function TryParse([string]$Text) {
  try { return @{ Ok = $true; Doc = ($Text | ConvertFrom-Json -Depth 100) } } catch { return @{ Ok = $false; Doc = $null; Why = $_.Exception.Message } }
}

& $Exe index --project (Join-Path $fx 'App.dpr') --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }

# Every json-emitting verb that reads an index, with arguments that give it a
# real answer on this fixture. 'env' = the object envelope must carry the
# stale/stale_files pair (the verbs the INBOX note named whose json is an object).
$verbs = @(
  @{ name = 'reverse-calltree'; env = $true;  args = @('reverse-calltree', '--qname', 'U1.Bar', '--format', 'json') },
  @{ name = 'butterfly';        env = $true;  args = @('butterfly', '--qname', 'U1.Foo', '--format', 'json') },
  @{ name = 'callgraph';        env = $true;  args = @('callgraph', '--qname', 'U1.Foo', '--json') },
  @{ name = 'sql';              env = $true;  args = @('sql', '--query', 'SELECT count(*) AS n FROM files', '--json') },
  @{ name = 'schema';           env = $true;  args = @('schema', '--format', 'json') },
  @{ name = 'deps-report';      env = $true;  args = @('deps-report', '--format', 'json') },
  @{ name = 'hover';            env = $false;  args = @('hover', '--qname', 'U1.Foo', '--format', 'json') },
  @{ name = 'query --name';     env = $false; args = @('query', '--name', 'Foo', '--json') },
  @{ name = 'find-callers';     env = $false; args = @('query', 'find-callers', '--name', 'Bar', '--json') },
  @{ name = 'query --text';     env = $false; args = @('query', '--text', 'thing', '--substring', '--json') },
  @{ name = 'outline';          env = $false; args = @('outline', '--file', $u1, '--format', 'json') },
  @{ name = 'info';             env = $false; args = @('info', '--json') },
  @{ name = 'context';          env = $false; args = @('context', '--task', 'modify U1.Foo', '--format', 'json') },
  @{ name = 'find-callees';     env = $false; args = @('find-callees', '--qname', 'U1.Foo', '--json') },
  @{ name = 'impact';           env = $false; args = @('impact', '--qname', 'U1.Bar', '--format', 'json') },
  @{ name = 'call-path';        env = $false; args = @('call-path', '--from', 'U1.Foo', '--to', 'U1.Bar', '--json') },
  @{ name = 'surface';          env = $false; args = @('surface', '--qname', 'U1.TThing', '--format', 'json') },
  @{ name = 'usages';           env = $false; args = @('usages', '--name', 'Bar', '--json') },
  @{ name = 'top';              env = $false; args = @('top', '--json') },
  @{ name = 'cycles';           env = $false; args = @('cycles', '--format', 'json') },
  @{ name = 'wiring';           env = $false; args = @('wiring', '--coverage', '--format', 'json') },
  @{ name = 'lint';             env = $false; args = @('lint', $u1, '--json') },
  @{ name = 'lint-all';         env = $false; args = @('lint-all', '--json', '--output', (Join-Path $WorkDir 'rep.txt')) }
)

function RunAll([string]$Label, [bool]$ExpectStale) {
  Write-Host ''
  Write-Host "$Label" -ForegroundColor Cyan
  foreach ($v in $verbs) {
    $r = Run ($v.args + @('--db', $db))
    $p = TryParse $r.Out
    Check ("{0}: stdout is non-empty" -f $v.name) ($r.Out.Trim().Length -gt 0) ("exit={0} stderr={1}" -f $r.Code, ($r.Err.Trim() -split "`n" | Select-Object -Last 1))
    Check ("{0}: stdout parses as ONE JSON document" -f $v.name) $p.Ok $p.Why
    if ($v.env -and $p.Ok) {
      $has = ($null -ne $p.Doc.PSObject.Properties['stale']) -and ($null -ne $p.Doc.PSObject.Properties['stale_files'])
      Check ("{0}: envelope carries stale + stale_files" -f $v.name) $has ''
      if ($has) {
        Check ("{0}: stale = {1}" -f $v.name, $ExpectStale) ($p.Doc.stale -eq $ExpectStale) ("got stale={0} stale_files={1}" -f $p.Doc.stale, $p.Doc.stale_files)
        Check ("{0}: stale_files agrees with stale" -f $v.name) (($p.Doc.stale_files -gt 0) -eq $ExpectStale) ("stale_files={0}" -f $p.Doc.stale_files)
      }
    }
  }
}

# ---- fresh: the envelope must say NOT stale (so a constant true cannot pass)
$fresh = Run @('reverse-calltree', '--qname', 'U1.Bar', '--format', 'json', '--db', $db)
Check 'CONTROL: a fresh index prints no staleness note' (-not ($fresh.Err -match 'changed since this index was built')) ''
RunAll 'FRESH index' $false

# ---- make it stale: a real CONTENT change to an indexed member
Start-Sleep -Milliseconds 1100
[IO.File]::AppendAllText($u1, "{ edited after indexing }`r`n", [Text.Encoding]::ASCII)
$stale = Run @('reverse-calltree', '--qname', 'U1.Bar', '--format', 'json', '--db', $db)
Check 'CONTROL: the edited index IS stale -- the note is on STDERR' ($stale.Err -match 'changed since this index was built') `
  'if this fails the fixture never went stale and every stale assertion below proves nothing'
Check 'CONTROL: and NOT on stdout' (-not ($stale.Out -match 'drag-lint: note')) ''
RunAll 'STALE index' $true

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
