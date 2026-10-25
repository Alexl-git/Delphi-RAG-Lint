<#
  run_document_two_decls_one_line.ps1 -- N-17 / B-33 item 2.

  THE DEFECT (INBOX-2026-09-30-engine-followups-from-1.20.5.md item 2, re-measured
  2026-10-23 on 1.33.0-alpha). `TC = class class function Go(...): Integer; end;`
  puts TWO documentable declarations on ONE line. Both get a managed block anchored
  above that same line, so the first `document --apply` stacks them into ONE ///
  run; the second run plans `delete lines 6..13` twice and REFUSES ("overlapping
  delete ranges (an engine defect)"), and `lint-all --fix --apply` rewrites the
  shared run for Go alone -- silently deleting TC's remarks.

  CONTRACT. DocInsight cannot tell which declaration a comment above a shared line
  belongs to, so the documenter SKIPS such declarations with a clear note naming
  the line, writes nothing there, and never deletes a block it cannot attribute.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_doc_two_decls_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }

$tail = @"

implementation

class function TC.Go(const A: Integer): Integer;
begin
  if A > 0 then Result:= 1 else Result:= 0;
end;

end.
"@
$oneLine = "unit uTwo;`n`ninterface`n`ntype`n  TC = class class function Go(const A: Integer): Integer; end;`n  TD = class(TC) end;`n" + $tail
$twoLine = "unit uTwo;`n`ninterface`n`ntype`n  TC = class`n    class function Go(const A: Integer): Integer;`n  end;`n  TD = class(TC) end;`n" + $tail
# The shape a pre-fix `document --apply` left behind: TC's remarks and Go's
# param/returns stacked into one /// run above the shared line.
$stacked = "unit uTwo;`n`ninterface`n`ntype`n" +
  "  /// <remarks>`n  /// <!-- drag-lint:auto BEGIN -->`n  /// <para>Used by: declaration (uTwo.pas)</para>`n" +
  "  /// <para>Used in units: uTwo</para>`n  /// <!-- drag-lint:auto END -->`n  /// </remarks>`n" +
  "  /// <param name=`"A`"><!-- drag-lint:auto type -->const Integer</param>`n" +
  "  /// <returns><!-- drag-lint:auto -->Integer -- Observed: 1.</returns>`n" +
  "  TC = class class function Go(const A: Integer): Integer; end;`n  TD = class(TC) end;`n" + $tail

function Fixture([string]$Name, [string]$Text) {
  $d = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  $u = Join-Path $d 'uTwo.pas'
  Write-Ascii $u $Text
  $db = Join-Path $d 'fx.sqlite'
  & $exePath index $d --db $db 2>&1 | Out-Null
  return @{ Unit = $u; Db = $db }
}
function Doc($fx) {
  $o = (& $exePath document --unit $fx.Unit --db $fx.Db --apply --no-backup 2>&1) -join "`n"
  return @{ Out = $o; Code = $LASTEXITCODE }
}

# ---- P1 POSITIVE CONTROL: the same declarations on two lines ARE documented ---
$p = Fixture 'twoline' $twoLine
$before = [IO.File]::ReadAllText($p.Unit)
$r = Doc $p
Check 'P1 POSITIVE CONTROL split declarations get documented' `
      (([IO.File]::ReadAllText($p.Unit) -ne $before) -and ($r.Code -eq 0)) `
      "document wrote nothing on the split fixture (exit $($r.Code)) -- T1..T3 would prove nothing. $($r.Out)"

# ---- T1: undocumented one-line pair -> skipped with a note, nothing written ---
$a = Fixture 'oneline' $oneLine
$before = [IO.File]::ReadAllText($a.Unit)
$r = Doc $a
Check 'T1a an undocumented one-line pair is left unchanged' ([IO.File]::ReadAllText($a.Unit) -eq $before) `
      'document stacked two blocks above the shared line'
Check 'T1b the skip is reported, naming the line' ($r.Out -match 'one line' -and $r.Out -match 'uTwo\.pas:6') `
      "no skip note: $($r.Out)"

# ---- T2: the stacked leftover is not refused as an engine defect ---------------
$b = Fixture 'stacked' $stacked
$before = [IO.File]::ReadAllText($b.Unit)
$r = Doc $b
Check 'T2a document does not refuse with overlapping delete ranges' `
      (-not ($r.Out -match 'overlapping') -and $r.Code -eq 0) "exit $($r.Code): $($r.Out)"
Check 'T2b document leaves the stacked block alone' ([IO.File]::ReadAllText($b.Unit) -eq $before) 'the block was rewritten'

# ---- T4: doc-drift does not report a block no command can clear ----------------
$drift = @((& $exePath lint-all --db $b.Db --json 2>$null | ConvertFrom-Json) | Where-Object { $_.rule -eq 'doc-drift' })
Check 'T4 lint-all reports no doc-drift on the shared-line block' ($drift.Count -eq 0) `
      "doc-drift fired $($drift.Count)x at line(s) $(($drift | ForEach-Object start_line) -join ',') -- unclearable, document skips it"

# ---- T3: lint-all --fix --apply never deletes TC's remarks ---------------------
& $exePath lint-all --db $b.Db --fix --apply 2>&1 | Out-Null
Check 'T3 lint-all --fix --apply keeps the block it cannot attribute' `
      ([IO.File]::ReadAllText($b.Unit) -match 'Used in units: uTwo') `
      'doc-drift --fix rewrote the shared run for one declaration and deleted the other''s remarks'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_doc_two_decls_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
