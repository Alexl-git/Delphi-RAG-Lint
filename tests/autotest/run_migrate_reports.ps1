<#
  run_migrate_reports.ps1 -- `drag-lint migrate-reports` (1.56 QENG, lane QE-3): the old
  PowerShell-style COMMAND line of a saved report becomes the CLI-style one, and everything
  that is not unambiguous is LEFT ALONE and listed.

  One case per snapshot format of `compare --save`:
    txt  the report text: the only format that carries a COMMAND line. Old in, migrated out
         (ONLY that line changes: CRLF / LF line ends, a UTF-8 BOM and every other byte stay),
         plain and DocInsight form, and the left-alone list (legacy header, wrapped line, mixed
         styles, unknown argument, repeated argument, not a report, not UTF-8).
    csv  the forms CSV: carries no command line, so the old file comes out byte-identical and is
         reported current; a .csv that is no forms CSV is left alone.
    dot  the chart DOT: same -- byte-identical and current; a .dot that is no DOT is left alone.
  Each case asserts the four lists of --json EXACTLY (migrated / current / leftAlone / failed),
  so a file that silently moved to another list fails the case.

  Positive controls: a second run finds nothing to migrate and calls the migrated files
  'already in CLI style' (the engine's own DetectCommandStyle reads what was written);
  --dry-run reports the same lists and writes nothing; a missing path exits 1, no path exits 2.
  Needs no index and no project: the verb is pure file work.
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block.
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:fail = $false
$script:pass = 0
$script:bad = 0
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if($ok){ $script:pass++ } else { $script:fail=$true; $script:bad++ }
}
$Exe = (Resolve-Path $Exe).Path
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-migrate-reports-' + [guid]::NewGuid().ToString('N'))
$Utf8 = [Text.UTF8Encoding]::new($false)
$CRLF = "`r`n"

function Put([string]$Path, [string]$Text) {
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
  [IO.File]::WriteAllText($Path, $Text, $Utf8)
}
function Hex([string]$Path) { [BitConverter]::ToString([IO.File]::ReadAllBytes($Path)) }
function Invoke-Verb([string[]]$ArgList) {
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe 'migrate-reports' @ArgList 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Text = (@($out) -join "`n") }
}
# The four lists of --json as sorted leaf names. A run that printed no JSON gives four '<no json>'
# lists, so every list assertion fails loudly instead of comparing two empty sets.
function Lists([string]$JsonText) {
  $res = @{ migrated = '<no json>'; current = '<no json>'; leftAlone = '<no json>'; failed = '<no json>'; obj = $null }
  try { $o = $JsonText | ConvertFrom-Json -ErrorAction Stop | ForEach-Object { $_ } } catch { return $res }
  if ($null -eq $o -or $null -eq $o.PSObject.Properties['leftAlone']) { return $res }
  foreach ($k in 'migrated','current','leftAlone','failed') {
    $res[$k] = (@($o.$k | ForEach-Object { [IO.Path]::GetFileName($_.path) } | Sort-Object) -join ',')
  }
  $res.obj = $o
  $res
}
function Reason($Lists, [string]$Leaf) {
  if ($null -eq $Lists.obj) { return '<no json>' }
  $hit = @($Lists.obj.leftAlone | Where-Object { [IO.Path]::GetFileName($_.path) -eq $Leaf })
  if ($hit.Count -eq 1) { [string]$hit[0].reason } else { "<$($hit.Count) entries>" }
}

$Sentence = 'Who writes this field (drag-lint report who-writes) for Unit1.TForm1.FCount, asked on 2026-10-10 14:32, engine 1.27.0.'
$OldCmd   = 'COMMAND who-writes -Target "Unit1.TForm1.FCount" -Project "C:\P\App.dproj" -Depth 3'
$NewCmd   = 'COMMAND who-writes --target "Unit1.TForm1.FCount" --project "C:\P\App.dproj" --depth 3'
$Rows     = @('CHART who-writes Unit1.TForm1.FCount -- 1 write sites / 1 routines',
              '  TARGET Unit1.TForm1.FCount @Unit1.pas:12',
              '  TForm1.FormShow @Unit1.pas:40 -- a row that says -Target "x" and must stay as it is')
function Plain([string]$Cmd, [string]$Eol = $CRLF) { (@($Sentence, $Cmd) + $Rows -join $Eol) + $Eol }
function Doc([string[]]$CmdLines) {
  (@('/// <remarks>', "/// $Sentence") + $CmdLines + @('///', '/// Totals: 1 write sites / 1 routines.', '/// </remarks>') -join $CRLF) + $CRLF
}

try {
  # ---------------------------------------------------------------- case txt
  $T = Join-Path $Work 'txt'
  Put "$T\old.plain.txt"   (Plain $OldCmd)
  Put "$T\old.lf.txt"      (Plain $OldCmd "`n")
  Put "$T\old.doc.txt"     (Doc @("/// $OldCmd"))
  Put "$T\auto\old.path.txt" ((@('Path between two routines (drag-lint report path) for A.B -> C.D, asked on 2026-10-10 14:32, engine 1.27.0.',
                                 'COMMAND path -Target "A.B" -To "C.D" -Project "C:\P\App.dproj" -Depth 4', 'CHART path A.B -> C.D') -join $CRLF) + $CRLF)
  [void][IO.Directory]::CreateDirectory($T)
  [IO.File]::WriteAllText("$T\old.bom.txt", (Plain $OldCmd), [Text.UTF8Encoding]::new($true))
  Put "$T\current.txt"     (Plain $NewCmd)
  Put "$T\legacy.txt"      ((@('/// <remarks>', '/// Who writes this field (drag-lint report who-writes) for Unit1.TForm1.FCount,', '///   asked on 2026-10-06.', '///', '/// Totals: 1 write sites / 1 routines.', '/// </remarks>') -join $CRLF) + $CRLF)
  Put "$T\wrapped.txt"     (Doc @('/// COMMAND who-writes -Target "Unit1.TForm1.FCount"', '///   -Project "C:\P\App.dproj" -Depth 3'))
  Put "$T\mixed.txt"       (Plain 'COMMAND who-writes -Target "Unit1.TForm1.FCount" --project "C:\P\App.dproj"')
  Put "$T\unknown-arg.txt" (Plain 'COMMAND who-writes -Target "Unit1.TForm1.FCount" -Project "C:\P\App.dproj" -FooBar 3')
  Put "$T\repeated.txt"    (Plain 'COMMAND who-writes -Target "Unit1.TForm1.FCount" -Target "Unit1.TForm1.FOther" -Project "C:\P\App.dproj"')
  Put "$T\notes.txt"       ("Meeting notes${CRLF}COMMAND who-writes -Target ""X"" -Project ""P""${CRLF}")
  [IO.File]::WriteAllBytes("$T\latin1.txt", [byte[]](0x4E,0x6F,0x74,0x65,0x20,0xE9,0xFF,0x0D,0x0A))
  Put "$T\picture.svg"     '<svg/>'
  $left = 'latin1.txt,legacy.txt,mixed.txt,notes.txt,picture.svg,repeated.txt,unknown-arg.txt,wrapped.txt'
  $migr = 'old.bom.txt,old.doc.txt,old.lf.txt,old.path.txt,old.plain.txt'
  $before = @{}
  Get-ChildItem $T -Recurse -File | ForEach-Object { $before[$_.Name] = Hex $_.FullName }

  $r = Invoke-Verb @($T, '--dry-run', '--json')
  $l = Lists $r.Text
  Check 'txt dry-run: exit 0' ($r.Code -eq 0) "exit=$($r.Code)"
  Check 'txt dry-run: the migrated list' ($l.migrated -eq $migr) "got [$($l.migrated)]"
  Check 'txt dry-run: the left-alone list' ($l.leftAlone -eq $left) "got [$($l.leftAlone)]"
  $changed = @(Get-ChildItem $T -Recurse -File | Where-Object { $before[$_.Name] -ne (Hex $_.FullName) })
  Check 'txt dry-run: nothing is written' ($changed.Count -eq 0) "changed: $($changed.Name -join ',')"

  $r = Invoke-Verb @($T, '--json')
  $l = Lists $r.Text
  Check 'txt: exit 0 (a left-alone file is not an error)' ($r.Code -eq 0) "exit=$($r.Code) $($r.Text.Substring(0, [Math]::Min(200, $r.Text.Length)))"
  Check 'txt: the migrated list (plain, LF, BOM, DocInsight, the auto subfolder)' ($l.migrated -eq $migr) "got [$($l.migrated)]"
  Check 'txt: the current list' ($l.current -eq 'current.txt') "got [$($l.current)]"
  Check 'txt: the left-alone list' ($l.leftAlone -eq $left) "got [$($l.leftAlone)]"
  Check 'txt: nothing failed' ($l.failed -eq '') "got [$($l.failed)]"
  Check 'txt: plain report out = only the COMMAND line rewritten' ((Hex "$T\old.plain.txt") -eq [BitConverter]::ToString($Utf8.GetBytes((Plain $NewCmd)))) ''
  Check 'txt: LF line ends are kept' ((Hex "$T\old.lf.txt") -eq [BitConverter]::ToString($Utf8.GetBytes((Plain $NewCmd "`n")))) ''
  Check 'txt: the UTF-8 BOM is kept' ((Hex "$T\old.bom.txt") -eq ('EF-BB-BF-' + [BitConverter]::ToString($Utf8.GetBytes((Plain $NewCmd))))) ''
  Check 'txt: DocInsight report out keeps its /// prefix' ((Hex "$T\old.doc.txt") -eq [BitConverter]::ToString($Utf8.GetBytes((Doc @("/// $NewCmd"))))) ''
  Check 'txt: --to is written for the path question' ([IO.File]::ReadAllText("$T\auto\old.path.txt").Contains('COMMAND path --target "A.B" --to "C.D" --project "C:\P\App.dproj" --depth 4' + $CRLF)) ''
  $same = @($left.Split(',') + 'current.txt' | Where-Object { $before[$_] -ne (Hex (Join-Path $T $_)) })
  Check 'txt: every left-alone and current file is byte-identical' ($same.Count -eq 0) "changed: $($same -join ',')"
  Check 'txt reason: legacy header'    ((Reason $l 'legacy.txt')      -match 'legacy header') (Reason $l 'legacy.txt')
  Check 'txt reason: wrapped line'     ((Reason $l 'wrapped.txt')     -match 'wrapped')       (Reason $l 'wrapped.txt')
  Check 'txt reason: mixed styles'     ((Reason $l 'mixed.txt')       -match 'mixes')         (Reason $l 'mixed.txt')
  Check 'txt reason: unknown argument' ((Reason $l 'unknown-arg.txt') -match '-FooBar')       (Reason $l 'unknown-arg.txt')
  Check 'txt reason: repeated argument' ((Reason $l 'repeated.txt')   -match 'without loss')  (Reason $l 'repeated.txt')
  Check 'txt reason: not a report'     ((Reason $l 'notes.txt')       -match 'not a drag-lint report') (Reason $l 'notes.txt')
  Check 'txt reason: not UTF-8'        ((Reason $l 'latin1.txt')      -match 'not UTF-8')     (Reason $l 'latin1.txt')
  Check 'txt reason: not a snapshot format' ((Reason $l 'picture.svg') -match 'not a snapshot format') (Reason $l 'picture.svg')

  # positive control: the engine reads back what it wrote, and a second run changes nothing
  $after = @{}
  Get-ChildItem $T -Recurse -File | ForEach-Object { $after[$_.Name] = Hex $_.FullName }
  $r = Invoke-Verb @($T, '--json')
  $l = Lists $r.Text
  Check 'txt second run: nothing left to migrate' ($l.migrated -eq '') "got [$($l.migrated)]"
  Check 'txt second run: the migrated files are now current' ($l.current -eq "current.txt,$migr") "got [$($l.current)]"
  $changed = @(Get-ChildItem $T -Recurse -File | Where-Object { $after[$_.Name] -ne (Hex $_.FullName) })
  Check 'txt second run: nothing is written' ($changed.Count -eq 0) "changed: $($changed.Name -join ',')"

  # ---------------------------------------------------------------- case csv
  $C = Join-Path $Work 'csv'
  $FormsHeader = '#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes'
  Put "$C\forms--App--20261010-1432.csv" ($FormsHeader + $CRLF + '1,"TfrmA","UnitA","Main menu","File > Open","TMenuItem","miOpenClick","TfrmMain","yes","","","high","",""' + $CRLF)
  Put "$C\prices.csv" ("Item,Price${CRLF}Nut,3${CRLF}")
  $before = @{}
  Get-ChildItem $C -File | ForEach-Object { $before[$_.Name] = Hex $_.FullName }
  $r = Invoke-Verb @($C, '--json')
  $l = Lists $r.Text
  Check 'csv: exit 0' ($r.Code -eq 0) "exit=$($r.Code)"
  Check 'csv: nothing to migrate (a forms CSV carries no command line)' ($l.migrated -eq '') "got [$($l.migrated)]"
  Check 'csv: the forms CSV is current' ($l.current -eq 'forms--App--20261010-1432.csv') "got [$($l.current)]"
  Check 'csv: the left-alone list' ($l.leftAlone -eq 'prices.csv') "got [$($l.leftAlone)]"
  Check 'csv reason: not a forms CSV' ((Reason $l 'prices.csv') -match 'not a forms CSV') (Reason $l 'prices.csv')
  $changed = @(Get-ChildItem $C -File | Where-Object { $before[$_.Name] -ne (Hex $_.FullName) })
  Check 'csv: old in = same bytes out' ($changed.Count -eq 0) "changed: $($changed.Name -join ',')"

  # ---------------------------------------------------------------- case dot
  $G = Join-Path $Work 'dot'
  Put "$G\who-calls--Unit1.TForm1.Go--20261010-1432.dot" ("digraph G {${CRLF}  n1 [label=<<TABLE><TR><TD>-Target</TD></TR></TABLE>>];${CRLF}  n1 -> n2;${CRLF}}${CRLF}")
  Put "$G\todo.dot" ("Graph of things to do${CRLF}")
  $before = @{}
  Get-ChildItem $G -File | ForEach-Object { $before[$_.Name] = Hex $_.FullName }
  $r = Invoke-Verb @($G, '--json')
  $l = Lists $r.Text
  Check 'dot: exit 0' ($r.Code -eq 0) "exit=$($r.Code)"
  Check 'dot: nothing to migrate (a chart DOT carries no command line)' ($l.migrated -eq '') "got [$($l.migrated)]"
  Check 'dot: the chart DOT is current' ($l.current -eq 'who-calls--Unit1.TForm1.Go--20261010-1432.dot') "got [$($l.current)]"
  Check 'dot: the left-alone list' ($l.leftAlone -eq 'todo.dot') "got [$($l.leftAlone)]"
  Check 'dot reason: not a chart DOT' ((Reason $l 'todo.dot') -match 'not a chart DOT') (Reason $l 'todo.dot')
  $changed = @(Get-ChildItem $G -File | Where-Object { $before[$_.Name] -ne (Hex $_.FullName) })
  Check 'dot: old in = same bytes out' ($changed.Count -eq 0) "changed: $($changed.Name -join ',')"

  # ---------------------------------------------------------------- text output, single file, usage
  Put "$Work\one\old.txt" (Plain $OldCmd)
  $r = Invoke-Verb @("$Work\one\old.txt")
  Check 'text: a single file is migrated and both lines are shown' (($r.Code -eq 0) -and ($r.Text -match '(?m)^migrated: .*old\.txt \(line 2\)') -and $r.Text.Contains("  new: $NewCmd")) $r.Text
  Check 'text: the summary line counts' ($r.Text -match 'migrate-reports: 1 file\(s\): 1 migrated, 0 already current, 0 left alone, 0 failed') ''
  $r = Invoke-Verb @("$Work\csv")
  Check 'text: left-alone files are listed with the reason' ($r.Text -match '(?m)^left alone: .*prices\.csv -- not a forms CSV') $r.Text
  $r = Invoke-Verb @()
  Check 'usage: no path exits 2' ($r.Code -eq 2) "exit=$($r.Code)"
  $r = Invoke-Verb @("$Work\one", '--frobnicate')
  Check 'usage: an unknown option exits 2' ($r.Code -eq 2) "exit=$($r.Code)"
  $r = Invoke-Verb @("$Work\no-such-folder", '--json')
  $l = Lists $r.Text
  Check 'a missing path exits 1 and is listed as failed' (($r.Code -eq 1) -and ($l.failed -eq 'no-such-folder')) "exit=$($r.Code) failed=[$($l.failed)]"
  $r = Invoke-Verb @('--help')
  Check '--help exits 0 and names the flags' (($r.Code -eq 0) -and $r.Text.Contains('--dry-run') -and $r.Text.Contains('--json') -and $r.Text.Contains('--project')) "exit=$($r.Code)"
} finally {
  if (Test-Path -LiteralPath $Work) { [IO.Directory]::Delete($Work, $true) }
}
Write-Host ("run_migrate_reports: {0} passed, {1} failed" -f $script:pass, $script:bad)
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
