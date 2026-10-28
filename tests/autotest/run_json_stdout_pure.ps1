<#
  run_json_stdout_pure.ps1 -- with --json, stdout carries ONLY the JSON document.

  CONVERTER report: `drag-lint lint <unit> --db <db> --json | ConvertFrom-Json`
  failed because a non-JSON note ("(loaded defaults from ...)") reached stdout.
  Contract: every note / progress / warning goes to stderr; stdout is one JSON
  document. This runs each JSON-capable verb on a tiny fixture that sits under a
  .drag-lint.json (so the defaults note fires) with ONLY stdout captured, and
  requires every non-empty stdout to parse with ConvertFrom-Json.

  Positive control: at least $MinParsed cases must produce a parsed document, so a
  verb that silently prints nothing cannot make the guard vacuous.

  Usage: pwsh -File tests\autotest\run_json_stdout_pure.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Exe) { $Exe = Join-Path $Root 'third_party\dll-win64\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FAIL exe not found: $Exe"; exit 2 }

$Work = Join-Path ([IO.Path]::GetTempPath()) ('jsonpure-' + [Guid]::NewGuid().ToString('N'))
$Sub = Join-Path $Work 'sub'
[void][IO.Directory]::CreateDirectory($Sub)
try {
  [IO.File]::WriteAllText((Join-Path $Work '.drag-lint.json'), "{`"defaults`":{}}`r`n")
  $src = "unit Foo;`r`ninterface`r`ntype TFoo = class`r`n procedure Bar;`r`nend;`r`nimplementation`r`nprocedure TFoo.Bar; begin end;`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $Sub 'Foo.pas'), $src)
  $dpr = "program P;`r`nuses Foo in 'Foo.pas';`r`nbegin end.`r`n"
  [IO.File]::WriteAllText((Join-Path $Sub 'P.dpr'), $dpr)
  $Db = Join-Path $Work 't.sqlite'
  Push-Location $Sub
  try { & $Exe index . --db $Db *> $null } finally { Pop-Location }

  $cases = @(
    @('lint', 'Foo.pas', '--db', $Db, '--json'),
    @('lint-all', '--db', $Db, '--json'),
    @('lint-project', '--db', $Db, '--json'),
    @('query', '--name', 'TFoo', '--db', $Db, '--json'),
    @('query', 'find-callers', '--name', 'Bar', '--db', $Db, '--json'),
    @('query', '--text', 'Foo', '--db', $Db, '--json'),
    @('rules', '--json'),
    @('find-unit', '--name', 'TFoo', '--in', 'Foo.pas', '--db', $Db, '--json'),
    @('context', '--task', 'modify TFoo.Bar', '--db', $Db, '--format', 'json'),
    @('resolve-dbs', '--in', 'Foo.pas', '--json'),
    @('usages', '--name', 'TFoo', '--db', $Db, '--json'),
    @('impact', '--qname', 'TFoo.Bar', '--db', $Db, '--format', 'json'),
    @('outline', '--in', 'Foo.pas', '--db', $Db, '--json'),
    @('find-callees', '--qname', 'TFoo.Bar', '--db', $Db, '--json'),
    @('info', '--db', $Db, '--json'),
    @('reconcile-project', 'P.dpr', '--json')
  )
  $fail = 0; $parsed = 0; $MinParsed = 8
  foreach ($c in $cases) {
    $out = Join-Path $Work 'out.txt'; $err = Join-Path $Work 'err.txt'
    Push-Location $Sub
    try { $p = Start-Process -FilePath $Exe -ArgumentList $c -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err }
    finally { Pop-Location }
    $text = [IO.File]::ReadAllText($out)
    $name = $c[0] + $(if ($c[1] -and $c[1] -notmatch '^-') { ' ' + $c[1] } else { '' })
    if ($text.Trim() -eq '') { Write-Host "SKIP $name (empty stdout, exit $($p.ExitCode))"; continue }
    try { [void]($text | ConvertFrom-Json); $parsed++; Write-Host "PASS $name" }
    catch { $fail++; $first = ($text -split "`r?`n")[0]; Write-Host "FAIL $name : stdout not pure JSON, first line: $first" }
  }
  # Merged-stream consumers (the converter's RunCapture, the editor) read stdout
  # and stderr as ONE pipe: the config-defaults banner must not be written under
  # --json / --format json|sarif (other stderr notes stay: they are stderr by contract).
  $merged = @(
    @('lint', 'Foo.pas', '--db', $Db, '--json'),
    @('lint-all', '--db', $Db, '--json'),
    @('lint-project', '--db', $Db, '--json'),
    @('query', '--name', 'TFoo', '--db', $Db, '--json'),
    @('rules', '--json'),
    @('lint', 'Foo.pas', '--db', $Db, '--format', 'sarif')
  )
  foreach ($c in $merged) {
    Push-Location $Sub
    try {
      $ErrorActionPreference = 'Continue'
      $text = (& $Exe @c 2>&1 | ForEach-Object { "$_" }) -join "`n"
      $ErrorActionPreference = 'Stop'
    } finally { Pop-Location }
    $name = 'merged ' + $c[0]
    if ($text -match 'loaded defaults from') { $fail++; Write-Host "FAIL $name : defaults banner written under a JSON mode" }
    else { $parsed++; Write-Host "PASS $name" }
  }
  if ($parsed -lt $MinParsed) { Write-Host "FAIL positive control: only $parsed documents parsed (need $MinParsed)"; $fail++ }
  Write-Host "json_stdout_pure: parsed=$parsed fail=$fail"
  exit ([int]($fail -gt 0))
} finally { [IO.Directory]::Delete($Work, $true) }
