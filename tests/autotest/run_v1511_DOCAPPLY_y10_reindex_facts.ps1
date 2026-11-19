<#
  run_v1511_DOCAPPLY_y10_reindex_facts.ps1 -- `document --apply --reindex` must
  leave the index's symbol_facts as a plain `index --project` would (1.51.1 Y10,
  docs\INBOX-yadf-fp-hunt-151.md DOC-10).

  THE DEFECT THIS PINS:
    DOC-10 saw autodoc oscillate between YADFSetup and YADFOT on the shared
    YADF.Options.pas: YADFSetup wrote `Touches:` / `Mutates:` / `Complexity:`
    lines, YADFOT removed them, forever. Traced on a scratch copy (lane REPORT):
    after YADFOT's `document --project --apply --reindex`, ALL 45 symbol_facts
    rows of YADF.Options.pas had cyclomatic 0 and no facts, while a plain
    `index --project` of the same tree computed them. The document pass parses
    the units it renders through TAstParseCache (process-global, keyed on the
    PATH only); the apply then rewrites those files and the --reindex that
    follows, in the SAME process, gets the PRE-EDIT tree back from the cache.
    No routine's ImplStartLine matches a defProc row any more, so every facts
    row is written empty -- and the next dry run renders a block without the
    facts the other project's index (correctly) holds.

  CASES
    * FACTS   after --apply --reindex, the documented unit's routines keep
              their cyclomatic complexity (routines with branches, > 1).
    * CONTROL the apply really edited (shifted) the unit -- else a stale tree
              would match by accident and FACTS proves nothing.
    * FIXED   a dry run right after reports nothing left to document.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "dl-v1511-y10-$PID")
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
  $app = Join-Path $WorkDir 'app'
  New-Item -ItemType Directory (Join-Path $app '_D-RAG') -Force | Out-Null
  Write-Ascii (Join-Path $app 'uLib.pas') @(
    'unit uLib;', 'interface',
    '/// <summary>Rejects a large number.</summary>',
    'procedure CheckN(const N: Integer);',
    '/// <summary>Classifies a number.</summary>',
    'function Classify(const N: Integer): string;',
    '/// <summary>Sums to N.</summary>',
    'function SumTo(const N: Integer): Integer;',
    'implementation',
    'uses System.SysUtils;',
    'procedure CheckN(const N: Integer);',
    'begin',
    "  if N > 100 then raise EArgumentException.Create('too big');",
    'end;',
    '{ The try..except makes the document pass read THIS file''s tree (exception',
    '  facts: TAstParseCache.Get on the caller''s unit) before the apply edits it. }',
    'function Classify(const N: Integer): string;',
    'begin',
    '  try',
    '    CheckN(N);',
    '  except',
    '    on E: EConvertError do Result := ''?'';',
    '  end;',
    '  if N < 0 then',
    "    Result := 'neg'",
    '  else if N = 0 then',
    "    Result := 'zero'",
    '  else if N < 10 then',
    "    Result := 'small'",
    '  else',
    "    Result := 'big';",
    'end;',
    'function SumTo(const N: Integer): Integer;',
    'var',
    '  I: Integer;',
    'begin',
    '  Result := 0;',
    '  for I := 1 to N do',
    '    if Odd(I) then',
    '      Inc(Result, I)',
    '    else',
    '      Dec(Result);',
    'end;',
    'end.')
  Write-Ascii (Join-Path $app 'uUse.pas') @(
    'unit uUse;', 'interface', 'procedure Run;', 'implementation', 'uses uLib;',
    'procedure Run;', 'begin', '  Writeln(Classify(SumTo(5)));', 'end;', 'end.')
  Write-Ascii (Join-Path $app 'App.dpr') @(
    'program App;', 'uses', "  uLib in 'uLib.pas',", "  uUse in 'uUse.pas';", 'begin', '  Run;', 'end.')
  $db   = Join-Path $app '_D-RAG\app.sqlite'
  $proj = Join-Path $app 'App.dpr'
  $lib  = Join-Path $app 'uLib.pas'
  $q    = "select s.name, sf.cyclomatic from symbol_facts sf join symbols s on s.id = sf.symbol_id join files f on f.id = s.file_id where f.path like '%uLib.pas' and s.name in ('Classify','SumTo') order by s.name"
  function Cyclo() {
    $j = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query $q --db $db --json 2>$null } | Out-String | ConvertFrom-Json
    ($j.rows | ForEach-Object { '{0}={1}' -f $_[0], $_[1] }) -join ','
  }

  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index --project $proj --db $db 2>&1 | ForEach-Object { "$_" } }
  Check 'setup: index built' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $c0 = Cyclo
  Check 'setup: plain index computes the complexity' (($c0 -match 'Classify=[2-9]') -and ($c0 -match 'SumTo=[2-9]')) $c0

  $before = [IO.File]::ReadAllText($lib)
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe document --project $proj --db $db --apply --reindex --no-backup 2>&1 | ForEach-Object { "$_" } } | Out-String
  Check 'setup: document --apply --reindex ran' ($LASTEXITCODE -eq 0) (($o -split "`r?`n" | Where-Object { $_ -match '^doc: \d' }) -join ' ')
  Check 'CONTROL the apply edited (shifted) uLib.pas' ([IO.File]::ReadAllText($lib) -ne $before) ''

  $c1 = Cyclo
  Check 'FACTS complexity survives the in-process --reindex' ($c1 -eq $c0) "before=$c0 after=$c1"

  $o = & { $ErrorActionPreference = 'Continue'; & $Exe document --project $proj --db $db 2>&1 | ForEach-Object { "$_" } } | Out-String
  Check 'FIXED a dry run right after has nothing to document' ($o -notmatch '(?m)^File:') (($o -split "`r?`n" | Where-Object { $_ -match '^doc: \d|^File:' }) -join ' ')
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
