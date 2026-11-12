<#
  run_review_marker_comment_silenced_handler.ps1 -- a dl:ok empty-on-handler
  marker written on the `on ... do` line of an EMPTY handler must not be
  reported review-marker-unused (docs\INBOX-review-marker-unused-on-handler.md,
  wave 152b lane CLI).

  THE DEFECT
  ----------
      except // dl:ok try-except-swallowed -- ...
        on Exception do // dl:ok empty-on-handler -- see the except above
          ;
      end;
  WITH the marker: `review-marker-unused ... "empty-on-handler" no longer
  matches any finding on this line`. WITHOUT it: `[warning] empty-on-handler`.
  The rule (rules\empty-on-handler.scm) anchors on `do` being the handler's
  LAST child; a `//` comment between `do` and the `;` is a child too, so the
  marker comment itself stops the rule firing -- the comment-sensitive loop
  ApplyLineMarkers already breaks for empty-except / empty-case-branch, which
  the 2026-08-12 probe missed for empty-on-handler because it put the comment
  AFTER the `;`.

  CASES
  -----
    A  marker on `do` of an empty handler      -> no unused hint, no warning (RED on 1.50.0-alpha)
    B  control: same handler, no comment        -> [warning] empty-on-handler (the rule is live)
    C  control: marker on a line with no handler -> review-marker-unused still reported
    D  control: marker on `do` of a NON-empty handler -> review-marker-unused still reported
    E  control: a wrong @hash on a live finding  -> review-marker-stale still reported

  Run from any CWD, pwsh 7:
    pwsh -File tests\autotest\run_review_marker_comment_silenced_handler.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-rm-handler-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null

$src = @(
  'unit RmUnit;',
  '',
  'interface',
  '',
  'procedure CaseA;',
  'procedure CaseB;',
  'procedure CaseC;',
  'procedure CaseD;',
  '',
  'implementation',
  '',
  'uses',
  '  System.SysUtils;',
  '',
  'procedure CaseA;',
  'begin',
  '  try',
  '    Writeln(''a'');',
  '  except // dl:ok try-except-swallowed -- fixture',
  '    on Exception do // dl:ok empty-on-handler -- see the except above {A}',
  '      ;',
  '  end;',
  'end;',
  '',
  'procedure CaseB;',
  'begin',
  '  try',
  '    Writeln(''b'');',
  '  except // dl:ok try-except-swallowed@0bad -- wrong hash {E}',
  '    on Exception do',
  '      ;',
  '  end;',
  'end;',
  '',
  'procedure CaseC;',
  'var',
  '  X: Integer;',
  'begin',
  '  X := 1; // dl:ok empty-on-handler -- no handler on this line {C}',
  '  Writeln(X);',
  'end;',
  '',
  'procedure CaseD;',
  'begin',
  '  try',
  '    Writeln(''d'');',
  '  except',
  '    on Exception do // dl:ok empty-on-handler -- body is not empty {D}',
  '      Writeln(''handled'');',
  '  end;',
  'end;',
  '',
  'end.'
)
$dpr = @('program RmProj;', '', 'uses', '  RmUnit in ''RmUnit.pas'';', '', 'begin', '  CaseA;', 'end.')
[IO.File]::WriteAllText((Join-Path $Work 'RmUnit.pas'), (($src -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $Work 'RmProj.dpr'), (($dpr -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
function LineOf($tag) { for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i].Contains($tag)) { return $i + 1 } }; return -1 }
$LA = LineOf '{A}'; $LB = (LineOf "Writeln('b')") + 2; $LC = LineOf '{C}'; $LD = LineOf '{D}'; $LE = LineOf '{E}'

Push-Location $Work
try {
  $db = Join-Path $Work 'rm.sqlite'
  $null = & $Exe index --project (Join-Path $Work 'RmProj.dpr') --db $db 2>&1
  Check 'index exit 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $raw = (& $Exe lint (Join-Path $Work 'RmUnit.pas') --db $db --json 2>$null) -join "`n"
  $all = @()
  try { $all = @($raw | ConvertFrom-Json) } catch { Check 'lint --json parses' $false $raw.Substring(0, [Math]::Min(300, $raw.Length)) }
  Check 'lint returned findings (non-empty answer)' ($all.Count -gt 0) "count=$($all.Count)"
  function Has($rule, $line) { @($all | Where-Object { $_.rule -eq $rule -and $_.start_line -eq $line }).Count -gt 0 }

  Check "A: no review-marker-unused on the comment-silenced handler (line $LA)" (-not (Has 'review-marker-unused' $LA))
  Check "A: no empty-on-handler warning on line $LA" (-not (Has 'empty-on-handler' $LA))
  Check "B: control -- empty-on-handler fires on the bare handler (line $LB)" (Has 'empty-on-handler' $LB)
  Check "C: control -- marker with no handler still reported unused (line $LC)" (Has 'review-marker-unused' $LC)
  Check "D: control -- marker on a non-empty handler still reported unused (line $LD)" (Has 'review-marker-unused' $LD)
  Check "E: control -- wrong @hash on a live finding still stale (line $LE)" (Has 'review-marker-stale' $LE)
  if ($script:Failed) {
    Write-Host '--- findings ---'
    $all | ForEach-Object { Write-Host ("  {0}:{1} {2}" -f $_.start_line, $_.start_col, $_.rule) }
  }
} finally {
  Pop-Location
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
