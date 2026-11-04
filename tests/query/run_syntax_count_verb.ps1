<#
  run_syntax_count_verb.ps1 -- GAP-SYNTAXQ: the `syntax-count` verb.

  gaps.log 2026-10-30T06:32:46 (unsupported): "count D13-only syntax: ternary if,
  is not" -- query --text capped at 200 string/comment hits and could not see
  syntax, so a session fell back to Select-String. syntax-count counts the shapes
  in the tree-sitter parse, uncapped, read-only.

  S1 --in --json counts every feature of the fixture, decoys excluded
  S2 --feature filters the totals; --hits lists line:col
  S3 --db over a scratch index of the fixture folder gives the same totals
  S4 unknown --feature -> exit 2; no --db/--in -> exit 2
  S5 unknown flag -> exit 3 with error[unknown-flag]
  S6 text form names each feature and its first Delphi
  POSITIVE CONTROL: an engine without the verb fails S1 (unknown command, exit 2).
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_syntax_count_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Run([string[]]$a){ $o = & $Exe @a 2>&1; [pscustomobject]@{ Code=$LASTEXITCODE; Out=($o | ForEach-Object { "$_" }) } }

$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force (Join-Path $WorkDir 'src') | Out-Null
$fx = Join-Path $WorkDir 'src\Fx.pas'
$src = @(
  'unit Fx;', 'interface', 'implementation', 'procedure X;', 'var a: Integer; o: TObject;', 'begin',
  '  a := if a > 1 then 2 else 3;',
  '  a := IfThen(a > 1, 2, 3);',
  '  if o is not TList then a := 1;',
  '  if not (o is TList) then a := 1;',
  '  if a not in [1, 2] then a := 2;',
  '  if not (a in [1, 2]) then a := 2;',
  '  var b := 5;',
  '  const k = 3;',
  '  var f: TFunc<Integer> := function: Integer begin Result := 1; end;',
  "  var s := '''", '    multi', "    ''';",
  "  s := '''';",
  'end;', 'end.') -join "`r`n"
[IO.File]::WriteAllText($fx, $src + "`r`n", [Text.Encoding]::ASCII)
$want = @{ 'if-expr'=1; 'is-not'=1; 'not-in'=1; 'inline-var'=3; 'inline-const'=1; 'anon-method'=1; 'multiline-string'=1 }

Push-Location $WorkDir
try {
  # ---- S1 ----
  $r = Run @('syntax-count','--in',$fx,'--json')
  $j = $null; try { $j = ($r.Out | Where-Object { $_ -like '{*' } | Select-Object -First 1) | ConvertFrom-Json } catch {}
  Check 'S1 --in --json exits 0' ($r.Code -eq 0) ("exit $($r.Code): " + ($r.Out -join ' | '))
  $bad = @(); if ($j) { foreach ($k in $want.Keys) { if ($j.totals.$k -ne $want[$k]) { $bad += "$k=$($j.totals.$k) want $($want[$k])" } } } else { $bad += 'no JSON' }
  Check 'S1 totals per feature (decoys excluded)' ($bad.Count -eq 0) ($bad -join '; ')
  Check 'S1 files_scanned=1, no parse errors' ($j -and $j.files_scanned -eq 1 -and $j.files_with_parse_errors -eq 0) ''

  # ---- S2 ----
  $r = Run @('syntax-count','--in',$fx,'--feature','is-not,not-in','--hits','--json')
  $j2 = $null; try { $j2 = ($r.Out | Where-Object { $_ -like '{*' } | Select-Object -First 1) | ConvertFrom-Json } catch {}
  Check 'S2 --feature keeps only the named totals' ($j2 -and @($j2.totals.PSObject.Properties).Count -eq 2 -and $j2.totals.'is-not' -eq 1) ($r.Out -join ' | ')
  $isnot = @($j2.hits | Where-Object { $_.feature -eq 'is-not' })
  Check 'S2 --hits: is-not at line 9' ($isnot.Count -eq 1 -and $isnot[0].line -eq 9) (($j2.hits | ConvertTo-Json -Compress))

  # ---- S3 ----
  $db = Join-Path $WorkDir 'fx.sqlite'
  $null = & $Exe index (Join-Path $WorkDir 'src') --db $db 2>&1
  $r = Run @('syntax-count','--db',$db,'--json')
  $j3 = $null; try { $j3 = ($r.Out | Where-Object { $_ -like '{*' } | Select-Object -First 1) | ConvertFrom-Json } catch {}
  Check 'S3 --db reads the index file list (same totals)' ($r.Code -eq 0 -and $j3 -and $j3.files_scanned -eq 1 -and $j3.totals.'inline-var' -eq 3 -and $j3.totals.'if-expr' -eq 1) ("exit $($r.Code): " + ($r.Out -join ' | '))

  # ---- S4 ----
  $r = Run @('syntax-count','--in',$fx,'--feature','bogus')
  Check 'S4 unknown --feature -> exit 2' ($r.Code -eq 2 -and ($r.Out -join ' ') -match 'bogus') ("exit $($r.Code): " + ($r.Out -join ' | '))
  $r = Run @('syntax-count','--json')
  Check 'S4 no --db and no --in -> exit 2' ($r.Code -eq 2) ("exit $($r.Code)")

  # ---- S5 ----
  $r = Run @('syntax-count','--in',$fx,'--bogus-flag')
  Check 'S5 unknown flag -> exit 3, error[unknown-flag]' ($r.Code -eq 3 -and ($r.Out -join ' ') -match 'error\[unknown-flag\]') ("exit $($r.Code): " + ($r.Out -join ' | '))

  # ---- S6 ----
  $r = Run @('syntax-count','--in',$fx,'--per-file')
  $txt = $r.Out -join "`n"
  Check 'S6 text: is-not row with count 1 and Delphi 13' ($r.Code -eq 0 -and $txt -match '(?m)^\s+is-not\s+1\s+Delphi 13') $txt
  Check 'S6 text --per-file names the file' ($txt -match [regex]::Escape('Fx.pas') + '.*if-expr=1') $txt
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d in @("C:\TEMP\draglint_syntax_count_$PID")) { if (Test-Path -LiteralPath $d) { [IO.Directory]::Delete($d, $true) } }
}