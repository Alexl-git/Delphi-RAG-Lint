<#
  151 Y2: the dfm_properties fact table (ST spec
  docs\superpowers\specs\2026-11-11-dfm-props-and-comment-facts.md) is FILLED by
  DRagLint.Parser.DFMProps.ExtractDfmPropertyRows, and forms-csv's three .dfm
  line-range readers (FormsMap DfmShownOnCreate / ReadCaption / ReadActionRef)
  answer from it.

  A  producer: tests\fixtures\dfm-props-151 indexed to a scratch DB; the rows of
     uP151Main.dfm (nested collection, multi-line '+' string, #nnn, a list, a set
     over two lines, a blob, an action ref) equal the hand-written
     expected-uP151Main.tsv. Generated non-ASCII forms (a BOM-less Windows-1252 and
     a UTF-8-BOM .dfm, written here so the repo stays ASCII) decode to the right
     Unicode text with UTF-8 byte columns; a #nnn above $FFFF becomes a surrogate
     pair; every row's object_ordinal names a dfm_objects row of its file.
  B  identity: forms-csv (and menu-tree --with-dfm --format paths where a project
     has .dfm menus) byte-identical between ON (the table, default) and OFF
     (DRAGLINT_NO_FILE_FACTS=1, the text readers) on every form fixture. ON1: the
     dfm-props-151 run reads the table (`[dfm-props] table`, DRAGLINT_DEBUG=1);
     OFF1: the OFF run never does.
  C  positive controls (prove the table is READ): one stored value is corrupted
     (same length, through the engine's own sqlite3.dll) and the ON forms-csv shows
     it while OFF does not -- C1 a Caption (ReadCaption), C2 the child form's
     Visible (DfmShownOnCreate), C3 a control's Action (ReadActionRef).
  D  STALE: a .dfm edited after the index is read from the text.
  E  ABS (-BaseExe): an index without the table (1.49 base engine) is answered by
     the text readers, identically.

  RED on the 1.49.0-alpha base / the ST-API stub: A fails (no table / no rows),
  C fails (the readers never touch the table).

  Usage: pwsh -File tests/autotest/run_dfm_properties_151.ps1 -Exe <drag-lint.exe> [-BaseExe <old exe>]
#>
[CmdletBinding()]
param(
  [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string] $BaseExe = '',
  [string] $WorkDir = "$env:TEMP\drag-lint-dfmprops151-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Passed++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
  else     { $script:Failed++; Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$fixRoot = (Resolve-Path "$PSScriptRoot\..\fixtures").Path

# ---- sqlite3.dll beside the engine, for the corruption controls (no python)
$sqliteDll = Join-Path (Split-Path $Exe -Parent) 'sqlite3.dll'
if (-not ('DlDfmProps151Sqlite' -as [type])) {
  Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class DlDfmProps151Sqlite {
  [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryW(string p);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_open(byte[] f, out IntPtr db);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr cb, IntPtr arg, IntPtr err);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_changes(IntPtr db);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
  static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }
  public static int Exec(string dll, string file, string sql) {
    LoadLibraryW(dll);
    IntPtr db; if (sqlite3_open(Z(file), out db) != 0) return -1;
    try { if (sqlite3_exec(db, Z(sql), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) != 0) return -2; return sqlite3_changes(db); }
    finally { sqlite3_close(db); }
  }
}
'@
}

# ---- helpers
function Esc([string]$S) {
  $sb = New-Object Text.StringBuilder
  foreach ($c in $S.ToCharArray()) {
    switch ([int]$c) {
      92 { [void]$sb.Append('\\') } 9 { [void]$sb.Append('\t') } 10 { [void]$sb.Append('\n') } 13 { [void]$sb.Append('\r') }
      default { if ([int]$c -gt 127) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) } else { [void]$sb.Append($c) } }
    }
  }
  $sb.ToString()
}
# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Sql([string]$Db, [string]$Query) {
  $raw = & $Exe sql --db $Db --query $Query --json 2>$null
  try { $doc = ($raw -join "`n") | ConvertFrom-Json } catch { return }  # no table (base engine): no rows
  if ($null -eq $doc -or $null -eq $doc.rows -or $null -eq $doc.columns) { return }
  $cols = @($doc.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = @()
  foreach ($r in @($doc.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out += [pscustomobject]$o
  }
  return $out  # unrolled: callers wrap the call in @()
}
function PropRows([string]$Db, [string]$FileLike) {
  Sql $Db ("SELECT p.ordinal, p.object_ordinal, p.parent, p.depth, p.name, p.value_text, p.value_kind, " +
           "p.start_line, p.start_col, p.end_line, p.end_col FROM dfm_properties p JOIN files f ON f.id = p.file_id " +
           "WHERE f.path LIKE '%$FileLike' ORDER BY p.ordinal")
}
function Run-Verb([string[]]$VerbArgs, [bool]$Off, [string]$Tag, [string]$UseExe = $Exe) {
  $o = Join-Path $WorkDir "$Tag-out.txt"
  $e = Join-Path $WorkDir "$Tag-err.txt"
  $env:DRAGLINT_DEBUG = '1'
  if ($Off) { $env:DRAGLINT_NO_FILE_FACTS = '1' } else { $env:DRAGLINT_NO_FILE_FACTS = $null }
  try {
    $p = Start-Process -FilePath $UseExe -ArgumentList $VerbArgs -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput $o -RedirectStandardError $e
  } finally {
    $env:DRAGLINT_DEBUG = $null
    $env:DRAGLINT_NO_FILE_FACTS = $null
  }
  $errText = if (Test-Path $e) { [IO.File]::ReadAllText($e) } else { '' }
  [pscustomobject]@{
    Code  = $p.ExitCode; Err = $errText; Out = $o
    Table = ([regex]::Matches($errText, '\[dfm-props\] table ')).Count
    Text  = ([regex]::Matches($errText, '\[dfm-props\] text ')).Count
  }
}
function CsvBody([string]$Path) {
  if (-not (Test-Path $Path)) { return '<no file>' }
  $t = [IO.File]::ReadAllText($Path)
  $i = $t.LastIndexOf('"# forms-csv algorithm')
  if ($i -lt 0) { return $t }
  return $t.Substring(0, $i)
}
function Forms-Csv([string]$Db, [string]$Proj, [bool]$Off, [string]$Tag, [string]$UseExe = $Exe) {
  $csv = Join-Path $WorkDir "$Tag.csv"
  $a = @('forms-csv', '--db', $Db, '--output', $csv)
  if ($Proj) { $a = @('forms-csv', '--project', $Proj, '--db', $Db, '--output', $csv) }
  $r = Run-Verb $a $Off $Tag $UseExe
  $r | Add-Member -NotePropertyName Body -NotePropertyValue (CsvBody $csv)
  $r
}
function Index-Dir([string]$Dir, [string]$Db, [string]$UseExe = $Exe) {
  New-Item -ItemType Directory -Force (Join-Path $Dir '_D-RAG') | Out-Null
  [IO.File]::WriteAllText((Join-Path $Dir '_D-RAG\drag-lint-project.json'), '{ "ownRoots": ["."] }')
  & $UseExe index $Dir --db $Db 2>&1 | Out-Null
  $LASTEXITCODE
}

# ---- A: producer
$px = Join-Path $WorkDir 'fx-dfm-props-151'
Copy-Item -LiteralPath (Join-Path $fixRoot 'dfm-props-151') -Destination $px -Recurse
$cp1252 = [Text.Encoding]::GetEncoding(1252)
$utf8bom = New-Object System.Text.UTF8Encoding($true)
$UUml = [string][char]0x00DC; $OUml = [string][char]0x00D6; $De = [string][char]0x0414
[IO.File]::WriteAllText((Join-Path $px 'uGenAnsi.dfm'), ("object frmGenAnsi: TfrmGenAnsi`r`n  Caption = '" + $UUml + "bernehmen'`r`n  Tag = 1`r`nend`r`n"), $cp1252)
[IO.File]::WriteAllText((Join-Path $px 'uGenBom.dfm'), ("object frmGenBom: TfrmGenBom`r`n  Caption = '" + $OUml + "ffnen " + $De + "a'`r`n  Hint = 'x'#128512`r`nend`r`n"), $utf8bom)
$pdb = Join-Path $WorkDir 'props.sqlite'
Check 'A0 index dfm-props-151 exits 0' ((Index-Dir $px $pdb) -eq 0)
$expected = @([IO.File]::ReadAllLines((Join-Path $px 'expected-uP151Main.tsv')) | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
$got = @()
try { $got = @(PropRows $pdb 'uP151Main.dfm' | ForEach-Object {
  ($_.ordinal, $_.object_ordinal, $_.parent, $_.depth, (Esc $_.name), (Esc $_.value_text), $_.value_kind,
   $_.start_line, $_.start_col, $_.end_line, $_.end_col) -join "`t" }) } catch { $got = @() }
Check 'A1 uP151Main.dfm row count = expected' ($got.Count -eq $expected.Count) "got=$($got.Count) expected=$($expected.Count)"
$firstDiff = ''
for ($i = 0; $i -lt [Math]::Max($got.Count, $expected.Count); $i++) {
  $g = if ($i -lt $got.Count) { $got[$i] } else { '<none>' }
  $x = if ($i -lt $expected.Count) { $expected[$i] } else { '<none>' }
  if ($g -cne $x) { $firstDiff = "row $i`n    got      [$g]`n    expected [$x]"; break }
}
Check 'A2 uP151Main.dfm rows equal expected-uP151Main.tsv' (($got.Count -gt 0) -and ($firstDiff -eq '')) $firstDiff
$ansi = @(PropRows $pdb 'uGenAnsi.dfm')
$bom  = @(PropRows $pdb 'uGenBom.dfm')
Check 'A3 Windows-1252 caption decoded, UTF-8 byte columns' (($ansi.Count -eq 2) -and ($ansi[0].value_text -ceq ($UUml + 'bernehmen')) -and ($ansi[0].end_col -eq 26)) "rows=$($ansi.Count) [$(if ($ansi.Count) { (Esc $ansi[0].value_text) + ' ' + $ansi[0].end_col })]"
Check 'A4 UTF-8-BOM caption decoded, UTF-8 byte columns' (($bom.Count -eq 2) -and ($bom[0].value_text -ceq ($OUml + 'ffnen ' + $De + 'a')) -and ($bom[0].end_col -eq 26) -and ($bom[0].start_line -eq 2)) "rows=$($bom.Count) [$(if ($bom.Count) { (Esc $bom[0].value_text) + ' ' + $bom[0].start_line + ':' + $bom[0].end_col })]"
Check 'A5 #nnn above $FFFF is a surrogate pair' (($bom.Count -eq 2) -and ($bom[1].value_text -ceq ('x' + [char]::ConvertFromUtf32(128512)))) "[$(if ($bom.Count -ge 2) { Esc $bom[1].value_text })]"
$orph = @(Sql $pdb ("SELECT COUNT(*) AS n FROM dfm_properties p WHERE p.object_ordinal >= 0 AND NOT EXISTS " +
                    "(SELECT 1 FROM dfm_objects o WHERE o.file_id = p.file_id AND o.ordinal = p.object_ordinal)"))
$own  = @(Sql $pdb ("SELECT o.name FROM dfm_properties p JOIN files f ON f.id = p.file_id JOIN dfm_objects o ON o.file_id = p.file_id " +
                    "AND o.ordinal = p.object_ordinal WHERE f.path LIKE '%uP151Main.dfm' AND p.name = 'Action' AND p.value_text = 'actDlg'"))
Check 'A6 every object_ordinal names a dfm_objects row; Action belongs to btnAct' (($orph.Count -eq 1) -and ($orph[0].n -eq 0) -and ($own.Count -eq 1) -and ($own[0].name -ceq 'btnAct')) "orphans=$(if ($orph.Count) { $orph[0].n }) owner=$(if ($own.Count) { $own[0].name })"

# ---- B: identity ON vs OFF on every form fixture
$fixtures = @('dfm-props-151', 'formsmap', 'formsmap-scrub', 'formsmap-v4', 'formsmap-v6', 'formsmap-v8', 'formsmap-v9', 'dispatch-forms', 'menutree', 'dfm-nonascii')
$propsOn = $null
foreach ($f in $fixtures) {
  if ($f -eq 'dfm-props-151') { $dir = $px; $db = $pdb }
  else {
    $dir = Join-Path $WorkDir "fx-$f"
    Copy-Item -LiteralPath (Join-Path $fixRoot $f) -Destination $dir -Recurse
    $db = Join-Path $WorkDir "$f.sqlite"
    Check "$f index exits 0" ((Index-Dir $dir $db) -eq 0)
  }
  $proj = @(Get-ChildItem $dir -Filter *.dproj | Select-Object -First 1 | ForEach-Object FullName)[0]
  $on  = Forms-Csv $db $proj $false "$f-on"
  $off = Forms-Csv $db $proj $true  "$f-off"
  Check "$f forms-csv exits 0 on both paths" (($on.Code -eq 0) -and ($off.Code -eq 0)) "on=$($on.Code) off=$($off.Code)"
  Check "$f ID forms-csv byte-identical ON vs OFF" ($on.Body -ceq $off.Body) "diff: $WorkDir\$f-on.csv vs $f-off.csv"
  Check "$f OFF1 the OFF run never reads dfm_properties" ($off.Table -eq 0) "table=$($off.Table)"
  if ($f -eq 'dfm-props-151') { $propsOn = $on; $propsOff = $off }
  if ($proj -and @(Get-ChildItem $dir -Filter *.dfm | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'TMainMenu|TdxBarManager|TPopupMenu' }).Count -gt 0) {
    $mOn  = Run-Verb @('menu-tree', '--project', $proj, '--db', $db, '--with-dfm', '--format', 'paths') $false "$f-mt-on"
    $mOff = Run-Verb @('menu-tree', '--project', $proj, '--db', $db, '--with-dfm', '--format', 'paths') $true  "$f-mt-off"
    $bOn = [IO.File]::ReadAllText($mOn.Out); $bOff = [IO.File]::ReadAllText($mOff.Out)
    Check "$f ID menu-tree --with-dfm --format paths byte-identical ON vs OFF" (($mOn.Code -eq $mOff.Code) -and ($bOn -ceq $bOff) -and ($bOn.Length -gt 0)) "code $($mOn.Code)/$($mOff.Code) len $($bOn.Length)/$($bOff.Length)"
  }
}
Check 'ON1 dfm-props-151 forms-csv reads dfm_properties' ($propsOn.Table -gt 0) "table=$($propsOn.Table) text=$($propsOn.Text)"
Check 'ON2 the fixture exercises all three readers on the table' ((@('ReadCaption', 'ReadActionRef', 'DfmShownOnCreate') | Where-Object { $propsOn.Err -notmatch "\[dfm-props\] table $_ " }).Count -eq 0) $propsOn.Err
Check 'ON3 baseline: the text-walk captions reach the csv (C1 / C3 can surface)' (($propsOn.Body -match 'Help route') -and ($propsOn.Body -match 'Second help')) ''

# ---- C: positive controls -- corrupt one stored value (same length) and the ON csv shows it
function Corrupt([string]$Tag, [string]$Where, [string]$NewValue) {
  $cdb = Join-Path $WorkDir "$Tag.sqlite"
  Copy-Item $pdb $cdb
  $n = [DlDfmProps151Sqlite]::Exec($sqliteDll, $cdb, ("UPDATE dfm_properties SET value_text = '$NewValue' WHERE " +
        "file_id = (SELECT id FROM files WHERE path LIKE '%$($Where.Split('|')[0])') AND " + $Where.Split('|')[1]))
  [pscustomobject]@{ Changed = $n; On = (Forms-Csv $cdb (Join-Path $px 'P151.dproj') $false "$Tag-on"); Off = (Forms-Csv $cdb (Join-Path $px 'P151.dproj') $true "$Tag-off") }
}
$c1 = Corrupt 'c1' "uP151Main.dfm|name = 'Caption' AND value_text = 'Help &route'" 'Help &xxxxx'
Check 'C1 a corrupted Caption row changes forms-csv (ReadCaption reads the table)' (($c1.Changed -eq 1) -and ($c1.On.Body -cne $c1.Off.Body) -and ($c1.Off.Body -ceq $propsOff.Body)) "changed=$($c1.Changed)"
$c2 = Corrupt 'c2' "uP151Child.dfm|name = 'Visible' AND depth = 0 AND object_ordinal = 0" 'Xrue'
Check 'C2 a corrupted Visible row changes forms-csv (DfmShownOnCreate reads the table)' (($c2.Changed -eq 1) -and ($c2.On.Body -cne $c2.Off.Body) -and ($c2.Off.Body -ceq $propsOff.Body)) "changed=$($c2.Changed)"
$c3 = Corrupt 'c3' "uP151Main.dfm|name = 'Action' AND value_text = 'actHelp2'" 'actChild'
Check 'C3 a corrupted Action row changes forms-csv (ReadActionRef reads the table)' (($c3.Changed -eq 1) -and ($c3.On.Body -cne $c3.Off.Body) -and ($c3.Off.Body -ceq $propsOff.Body)) "changed=$($c3.Changed)"

# ---- D: STALE -- an edited .dfm is read from the text
$mainDfm = Join-Path $px 'uP151Main.dfm'
[IO.File]::WriteAllText($mainDfm, [IO.File]::ReadAllText($mainDfm).Replace('Open &dialog via action', 'Open &dialog via act2on'), [Text.Encoding]::ASCII)
(Get-Item $mainDfm).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(5)
$sOn  = Forms-Csv $pdb (Join-Path $px 'P151.dproj') $false 'stale-on'
$sOff = Forms-Csv $pdb (Join-Path $px 'P151.dproj') $true  'stale-off'
Check 'D1 STALE edited .dfm read from the text' (@([regex]::Matches($sOn.Err, '\[dfm-props\] text \w+ [^\r\n]*uP151Main\.dfm')).Count -gt 0) $sOn.Err
Check 'D2 STALE output shows the edit and equals the text path' (($sOn.Body -match 'act2on') -and ($sOn.Body -ceq $sOff.Body))

# ---- E: ABS -- an index without dfm_properties falls back
if ($BaseExe -and (Test-Path $BaseExe)) {
  $absDir = Join-Path $WorkDir 'abs'
  Copy-Item -LiteralPath (Join-Path $fixRoot 'dfm-props-151') -Destination $absDir -Recurse
  $absDb = Join-Path $WorkDir 'abs.sqlite'
  Index-Dir $absDir $absDb $BaseExe | Out-Null
  $aOn  = Forms-Csv $absDb (Join-Path $absDir 'P151.dproj') $false 'abs-on'
  $aOff = Forms-Csv $absDb (Join-Path $absDir 'P151.dproj') $true  'abs-off'
  Check 'E1 ABS base-engine index never reads dfm_properties' (($aOn.Table -eq 0) -and ($aOn.Text -gt 0)) "table=$($aOn.Table) text=$($aOn.Text)"
  Check 'E2 ABS output identical to the text path' (($aOn.Code -eq 0) -and ($aOn.Body -ceq $aOff.Body))
}

Write-Host ("run_dfm_properties_151: {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -eq 0) { [IO.Directory]::Delete($WorkDir, $true); exit 0 }
Write-Host "work dir kept: $WorkDir"
exit 1
