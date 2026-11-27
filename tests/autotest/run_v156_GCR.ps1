#Requires -Version 7.3
<#
  run_v156_GCR.ps1 -- lane GC-R (1.56 GRIDCOL2): `repo read-dfm` reads the in-place editor of a grid column
  (PropertiesClassName and the Properties.* lines) into DL_GRID_COLUMNS.PROPERTIES_CLASS_NAME / PROPERTIES (schema 5).

  Proven on bytes: the fixture DFM is read, the change set applied, and the STORED row (read back through `repo backup`)
  is compared with the lines cut from the DFM file itself.
    R1  dry run: the insert of each column names its class and its lines; a column without an editor names neither
    R2  --apply, then the stored rows: class, and PROPERTIES = the DFM lines (collection, string list, continued string,
        a trailing blank), first-line indentation removed; class without lines; lines without class; a banded column
    R3  a second read has no change
    R4  the DFM changes: one update per changed column value, nothing else; removed editor = NULL again
    R5  backup -> restore -> read: no change (the stored text survives the text backup)
    R6  a schema-4 repository: columns still stored, the editor is not, and the run says why
    R7  a binary DFM: the stored lines are those of its text form (needs Delphi's convert.exe)
  Run: pwsh -File tests\autotest\run_v156_GCR.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:Failed = 0
$script:Count = 0
function Check($n, $ok, $d = '') {
  $script:Count++
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed++ }
}
Write-Host '== repo read-dfm, grid column editor properties (1.56 GC-R) ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v156-gcr-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Dfm([string[]]$more, $dfm = $script:dfm, $r = $script:x) { Run (@('repo', 'read-dfm', '--repo', $r, '--dfm', $dfm, '--direction', 'dfm-to-repo') + $more) }
function Has($r, $text) { $r.Out.Contains($text) }
# one DL_GRID_COLUMNS record of a text backup as a name -> value table; a text column (NAME: + " |" lines) is decoded
function Stored($r, $key) {
  $bk = Join-Path $work ('bk-' + [guid]::NewGuid().ToString('N') + '.txt')
  $null = Run @('repo', 'backup', '--repo', $r, '--output', $bk)
  $t = [IO.File]::ReadAllText($bk)
  $head = "[DL_GRID_COLUMNS $key]`r`n"
  $i = $t.IndexOf($head)
  $row = @{}
  if ($i -lt 0) { return $row }
  $row['#found'] = '1'
  $name = ''
  foreach ($line in ($t.Substring($i + $head.Length) -split "`r`n")) {
    if (($line -eq '') -or $line.StartsWith('[') -or $line.StartsWith('#')) { break }
    if ($line.StartsWith(' |')) {
      $part = $line.Substring(2)
      $cr = $part.EndsWith('\r')
      if ($cr) { $part = $part.Substring(0, $part.Length - 2) }
      $row[$name] = $row[$name] + $part.Replace('\\', '\') + $(if ($cr) { "`r`n" } else { '' })
    }
    elseif ($line.EndsWith(':') -and ($line -notmatch '=')) { $name = $line.TrimEnd(':'); $row[$name] = '' }
    else { $p = $line.IndexOf('='); $row[$line.Substring(0, $p)] = $line.Substring($p + 1) }
  }
  $row
}
# the Properties.* lines of one column, cut from the DFM file: the bytes the repository has to hold
function DfmLines($file, $column) {
  $lines = [IO.File]::ReadAllText($file) -split "`r`n"
  $out = @(); $in = $false; $take = $false
  foreach ($l in $lines) {
    if ($l -match "^      object $column`: ") { $in = $true; continue }
    if (-not $in) { continue }
    if ($l -eq '      end') { break }
    if ($l -match '^        \S') { $take = $l.StartsWith('        Properties.') }
    if ($take) { $out += $l.Substring(8) }
  }
  $out -join "`r`n"
}
try {
  $fix = Join-Path $Repo 'tests\fixtures\v156\GCR'
  $script:dfm = Join-Path $work 'uEditors.dfm'
  [IO.File]::Copy((Join-Path $fix 'uEditors.dfm'), $script:dfm)
  $script:x = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $script:x)
  $wantStatus = DfmLines $script:dfm 'colStatus'
  $wantKind = DfmLines $script:dfm 'colKind'
  $wantPrice = DfmLines $script:dfm 'colPrice'
  Check 'R0 the fixture lines were cut: a collection, a string list, a continued string with its trailing blank' (($wantStatus -split "`r`n").Count -eq 12 -and $wantStatus.StartsWith('Properties.Alignment.Horz = taCenter') -and $wantStatus.EndsWith('Properties.OnChange = colStatusPropertiesChange') -and $wantKind.EndsWith("  'Two')") -and $wantPrice.StartsWith("Properties.DisplayFormat = `r`n  '#,##0.00") -and $wantPrice.EndsWith('Properties.Nullable = False')) "$wantStatus`n--`n$wantKind`n--`n$wantPrice"

  # ---- R1 dry run ----
  $r = Dfm @()
  Check 'R1a a column without an editor names neither' (($r.Code -eq 0) -and (Has $r "] insert DL_GRID_COLUMNS frmEditors|view1|colQty:  -> TABLE_NAME=ORDERS; FIELD_NAME=QTY; COLUMN_INDEX=0`n")) $r.Out
  Check 'R1b class and lines in the insert' (Has $r "] insert DL_GRID_COLUMNS frmEditors|view1|colKind:  -> TABLE_NAME=ORDERS; FIELD_NAME=KIND; COLUMN_INDEX=2; PROPERTIES_CLASS_NAME=TcxComboBoxProperties; PROPERTIES=Properties.DropDownListStyle = lsFixedList\r\nProperties.Items.Strings = (\r\n  'One'\r\n  'Two')`n") $r.Out
  Check 'R1c a class without lines; lines without a class' ((Has $r "] insert DL_GRID_COLUMNS frmEditors|view1|colDone:  -> TABLE_NAME=ORDERS; FIELD_NAME=DONE; COLUMN_INDEX=4; PROPERTIES_CLASS_NAME=TcxCheckBoxProperties`n") -and (Has $r "] insert DL_GRID_COLUMNS frmEditors|view1|colNote:  -> TABLE_NAME=ORDERS; FIELD_NAME=NOTE; COLUMN_INDEX=5; PROPERTIES=Properties.ReadOnly = True`n")) $r.Out
  Check 'R1d nothing written by a dry run' (-not (Stored $script:x 'frmEditors|view1|colKind').ContainsKey('#found'))

  # ---- R2 apply, the stored rows ----
  $r = Dfm @('--apply')
  Check 'R2a apply' (($r.Code -eq 0) -and (Has $r 'applied: ')) $r.Out
  $s = Stored $script:x 'frmEditors|view1|colStatus'
  Check 'R2b colStatus: class, and the collection lines as the DFM has them' (($s['PROPERTIES_CLASS_NAME'] -ceq 'TcxImageComboBoxProperties') -and ($s['PROPERTIES'] -ceq $wantStatus) -and ($s['PROPERTIES'].Contains("    Description = 'It'#39's closed'`r`n")) -and ($s['PROPERTIES'].Contains("`r`n  end>`r`n"))) ("[$($s['PROPERTIES'])]`n-- want --`n[$wantStatus]")
  $s = Stored $script:x 'frmEditors|view1|colKind'
  Check 'R2c colKind: the string list' (($s['PROPERTIES_CLASS_NAME'] -ceq 'TcxComboBoxProperties') -and ($s['PROPERTIES'] -ceq $wantKind)) ("[$($s['PROPERTIES'])]")
  $s = Stored $script:x 'frmEditors|view1|colPrice'
  Check 'R2d colPrice: a string continued over lines, the blank after "=" kept; Options.Editing is not an editor line' (($s['PROPERTIES_CLASS_NAME'] -ceq 'TcxCurrencyEditProperties') -and ($s['PROPERTIES'] -ceq $wantPrice) -and ($s['PROPERTIES'] -notmatch 'Options')) ("[$($s['PROPERTIES'])]`n-- want --`n[$wantPrice]")
  $s = Stored $script:x 'frmEditors|view1|colDone'
  Check 'R2e colDone: a class, PROPERTIES NULL' (($s['PROPERTIES_CLASS_NAME'] -ceq 'TcxCheckBoxProperties') -and -not $s.ContainsKey('PROPERTIES')) ($s | Out-String)
  $s = Stored $script:x 'frmEditors|view1|colNote'
  Check 'R2f colNote: lines, PROPERTIES_CLASS_NAME NULL' (($s['PROPERTIES'] -ceq 'Properties.ReadOnly = True') -and -not $s.ContainsKey('PROPERTIES_CLASS_NAME')) ($s | Out-String)
  $s = Stored $script:x 'frmEditors|view1|colQty'
  Check 'R2g colQty: no editor, both NULL' ($s.ContainsKey('#found') -and ($s['COLUMN_INDEX'] -eq '0') -and -not $s.ContainsKey('PROPERTIES') -and -not $s.ContainsKey('PROPERTIES_CLASS_NAME')) ($s | Out-String)
  $s = Stored $script:x 'frmEditors|band1|bandQty'
  Check 'R2h a banded column: stored too; Position.BandIndex is not an editor line' (($s['PROPERTIES_CLASS_NAME'] -ceq 'TcxSpinEditProperties') -and ($s['PROPERTIES'] -ceq 'Properties.MaxValue = 99.000000000000000000')) ($s | Out-String)

  # ---- R3 second read ----
  $r = Dfm @()
  Check 'R3 a second read has no change' (Has $r 'direction dfm-to-repo, 0 changes, 0 blocked, 0 unchecked') $r.Out

  # ---- R4 the DFM changes ----
  $t = [IO.File]::ReadAllText($script:dfm)
  $t2 = $t.Replace("            Description = 'Open'", "            Description = 'Opened'").Replace("        PropertiesClassName = 'TcxCheckBoxProperties'`r`n", '').Replace("        DataBinding.FieldName = 'Qty'`r`n        Width = 40", "        DataBinding.FieldName = 'Qty'`r`n        PropertiesClassName = 'TcxSpinEditProperties'`r`n        Properties.MinValue = 1.000000000000000000`r`n        Width = 40")
  Check 'R4_0 the DFM was edited in three places' (($t2 -cne $t) -and ($t2.Contains("'Opened'")) -and ($t2 -notmatch 'TcxCheckBoxProperties') -and ($t2.Contains('Properties.MinValue'))) ''
  [IO.File]::WriteAllText($script:dfm, $t2)
  $r = Dfm @()
  Check 'R4a four updates, nothing else' ((Has $r 'direction dfm-to-repo, 4 changes, 0 blocked, 0 unchecked') -and (Has $r "] update DL_GRID_COLUMNS frmEditors|view1|colQty PROPERTIES_CLASS_NAME:  -> TcxSpinEditProperties`n") -and (Has $r "] update DL_GRID_COLUMNS frmEditors|view1|colQty PROPERTIES:  -> Properties.MinValue = 1.000000000000000000`n") -and (Has $r "] update DL_GRID_COLUMNS frmEditors|view1|colDone PROPERTIES_CLASS_NAME: TcxCheckBoxProperties -> `n") -and ($r.Out -match "(?m)^\[\d+\] update DL_GRID_COLUMNS frmEditors\|view1\|colStatus PROPERTIES: Properties\.Alignment\.Horz = taCenter\\r\\n.*'Open'.* -> Properties\.Alignment\.Horz = taCenter\\r\\n.*'Opened'")) $r.Out
  $r = Dfm @('--apply')
  $s = Stored $script:x 'frmEditors|view1|colStatus'
  $d = Stored $script:x 'frmEditors|view1|colDone'
  $q = Stored $script:x 'frmEditors|view1|colQty'
  Check 'R4b applied: the stored rows follow the file' (($r.Code -eq 0) -and (Has $r 'applied: 4 changes') -and ($s['PROPERTIES'] -ceq (DfmLines $script:dfm 'colStatus')) -and ($s['PROPERTIES'].Contains("'Opened'")) -and $d.ContainsKey('#found') -and -not $d.ContainsKey('PROPERTIES_CLASS_NAME') -and ($q['PROPERTIES_CLASS_NAME'] -ceq 'TcxSpinEditProperties') -and ($q['PROPERTIES'] -ceq 'Properties.MinValue = 1.000000000000000000') -and ($q['COLUMN_INDEX'] -eq '0')) "$($r.Out)`n$($s | Out-String)$($d | Out-String)$($q | Out-String)"
  $r = Dfm @()
  Check 'R4c and then no change' (Has $r 'direction dfm-to-repo, 0 changes, 0 blocked, 0 unchecked') $r.Out

  # ---- R5 text backup round trip ----
  $bk = Join-Path $work 'round.txt'
  $y = Join-Path $work 'y.dlrepo'
  $null = Run @('repo', 'backup', '--repo', $script:x, '--output', $bk)
  $rr = Run @('repo', 'restore', '--repo', $y, '--in', $bk)
  $r = Dfm @() $script:dfm $y
  Check 'R5 backup -> restore -> read: no change' (($rr.Code -eq 0) -and (Has $r 'direction dfm-to-repo, 0 changes, 0 blocked, 0 unchecked')) "$($rr.Out)`n$($r.Out)"

  # ---- R7 a binary DFM ----
  $bin = Join-Path $work 'bin'
  [IO.Directory]::CreateDirectory($bin) | Out-Null
  $bdfm = Join-Path $bin 'uEditors.dfm'
  [IO.File]::Copy($script:dfm, $bdfm)
  $conv = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\convert.exe'
  $null = & { $ErrorActionPreference = 'Continue'; & $conv -b -i $bdfm 2>&1 | ForEach-Object { "$_" } }
  $first = [IO.File]::ReadAllBytes($bdfm)[0]
  $z = Join-Path $work 'z.dlrepo'
  $null = Run @('repo', 'init', '--repo', $z)
  $r = Dfm @('--apply') $bdfm $z
  $s = Stored $z 'frmEditors|view1|colStatus'
  $p = Stored $z 'frmEditors|view1|colPrice'
  Check 'R7 a binary DFM: the stored lines are those of its text form' (($first -in 0xFF, 0x54) -and ($r.Code -eq 0) -and ($s['PROPERTIES_CLASS_NAME'] -ceq 'TcxImageComboBoxProperties') -and ($s['PROPERTIES'] -ceq (DfmLines $script:dfm 'colStatus')) -and ($p['PROPERTIES'] -ceq $wantPrice)) "first byte $first`n$($r.Out)`n[$($s['PROPERTIES'])]`n[$($p['PROPERTIES'])]"
  # ---- R6 a schema-4 repository ----
  $v4 = Join-Path $work 'v4.dlrepo'
  $rr = Run @('repo', 'restore', '--repo', $v4, '--in', (Join-Path $Repo 'tests\fixtures\fieldrepo\xtable\xtable_v4.txt'))
  $r = Dfm @() $script:dfm $v4
  Check 'R6a schema 4: the columns are planned without the editor, and the run says why' (($rr.Code -eq 0) -and ($r.Code -eq 0) -and (Has $r "] insert DL_GRID_COLUMNS frmEditors|view1|colKind:  -> TABLE_NAME=ORDERS; FIELD_NAME=KIND; COLUMN_INDEX=2`n") -and ($r.Out -cnotmatch 'PROPERTIES') -and (Has $r 'warning: the repository is schema 4: the editor properties of 6 grid columns are not read (run repo migrate --apply)')) "$($rr.Out)`n$($r.Out)"
  $r = Dfm @('--apply') $script:dfm $v4
  Check 'R6b schema 4: apply works' (($r.Code -eq 0) -and (Has $r 'applied: ')) $r.Out
}
finally {
  if ($env:DL_KEEP_WORKDIR -ne '1') { try { [IO.Directory]::Delete($work, $true) } catch { } }
}
Write-Host ("{0} checks, {1} failed" -f $script:Count, $script:Failed) -ForegroundColor (@('Green','Red')[[int]($script:Failed -gt 0)])
exit ([int]($script:Failed -gt 0))
