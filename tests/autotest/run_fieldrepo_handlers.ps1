#Requires -Version 7.3
<#
  run_fieldrepo_handlers.ps1 -- TT-HANDLERS (1.54): `repo gen-handlers`, `repo gen-maxlen`, `repo renumber-regions`.

  PART 1  builds and runs tests\fieldrepo\HandlersTests.dpr (scanner, regions, renumbering, generated text).
  PART 2  gen-handlers on tests\fixtures\fieldrepo\handlers (TFDMemTable, OnCalcFields and the four TField events):
    G1  dry run writes nothing; G2 --apply; G3 the generated unit COMPILES (dcc32, dcc64) and RUNS with the right values
    G4  everything outside the regions is byte for byte the old unit (copies in comments and strings included)
    G5  a second run writes nothing; G6 a changed body rewrites its own region only, hand code behind it survives
    G7  a hand-edited region is refused (exit 1) and stays byte for byte, the other regions are still written
    G8  a region whose end marker is commented out: refused; G9 a unit that is not ASCII: refused, unchanged
    G10 no handler assigned = skipped, a shared handler = refused; G11 --json; G12 usage and missing files
    G13 a handler another event of the form names too: refused; G14 a unit that cannot be written: reported (text, json),
        exit 1, the next unit is still written, no temporary file; G15 one form named twice is planned once
  PART 3  gen-maxlen: M1 dry run, M2 apply + compile + run, M3 second run, M4 hand-edited, M5 not ASCII,
          M7 a table named twice = one unit, M8 two tables of one unit = refused
  PART 4  renumber-regions: N1 dry run, N2 apply (or refused while update-orm cannot read DLFR), N3 not ASCII
  A missing toolchain or exe is a FAIL, never a skip.
  Run: pwsh -File tests\autotest\run_fieldrepo_handlers.ps1 [-Exe <drag-lint.exe>] [-SkipUnit]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipUnit)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$ErrorActionPreference = 'Continue'
$script:pass = 0
$script:fail = 0
function Check($n, $ok, $d = '') {
  if ($ok) { $script:pass++; Write-Host "[PASS] $n" -ForegroundColor Green } else { $script:fail++; Write-Host "[FAIL] $n $d" -ForegroundColor Red }
}
Write-Host '== repo gen-handlers / gen-maxlen / renumber-regions ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-handlers-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$ansi = [Text.Encoding]::GetEncoding(1252)
function Run([string[]]$a) {
  $o = & $Exe @a 2>&1
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function ReadText($f) { [IO.File]::ReadAllText($f, $ansi) }
function WriteText($f, $t) { [IO.File]::WriteAllText($f, $t, $ansi) }
function Hash($f) { (Get-FileHash -LiteralPath $f).Hash }
function Edit($f, $from, $to) {
  $t = ReadText $f
  if (-not $t.Contains($from)) { throw "Edit: '$from' is not in $f" }
  WriteText $f ($t.Replace($from, $to))
}
# the text with every real DLFR region of a hashed header removed (the marker lines must be whole lines)
function Outside($t) { [regex]::Replace($t, '(?m)^ *\{\$REGION ''DLFR \S+ hash=(?!0123456789abcdef)[0-9a-f]{16}''\}\r\n(?:(?!^ *\{\$ENDREGION).*\r\n)*^ *\{\$ENDREGION ''DLFR \S+''\}\r\n', '') }
function FieldRow($name, $kind = '', $body = @(), $len = '') {
  $l = @("[DL_FIELDS_INFO ORDERS|$name]", 'VISIBLE=true', 'TRIGGERED=false', 'BG_COLOR=false', 'FG_COLOR=false', 'UNIQUE_FLAG=false')
  if ($kind) { $l += "FIELD_KIND=$kind" }
  $l += @('PRIMARY_KEY=false', 'CUSTOM_TYPE=false', "ISCALCULATED=$(if ($kind -eq '2') { 'true' } else { 'false' })", 'ISLOOKUP=false', 'ISENUM=false')
  if ($body.Count) { $l += 'CALC_BODY:'; $l += @($body | ForEach-Object { " |$_" }) }
  if ($len) { $l += "CHAR_LENGTH=$len" }
  return $l + ''
}
function EventRow($name, $event, $body) { @("[DL_LAYOUT_EVENTS ORDERS|$name|Field|$event]", 'EVENT_CODE:') + @($body | ForEach-Object { " |$_" }) + '' }
# a repository made through the product's own text format
function NewRepo($name, $vat = '0.2', $noteLen = '40', $more = @()) {
  $empty = Join-Path $work "$name.empty.dlrepo"
  $bk = Join-Path $work "$name.txt"
  $null = Run @('repo', 'init', '--repo', $empty)
  $null = Run @('repo', 'backup', '--repo', $empty, '--output', $bk)
  $fields = @((FieldRow 'HANDY' '2' @('{{HANDY}}.AsInteger := 7;')), (FieldRow 'ID'), (FieldRow 'NOTE' '' @() $noteLen), (FieldRow 'PRICE'), (FieldRow 'QTY'),
    (FieldRow 'REFNO' '' @() '12'),
    (FieldRow 'TOTAL' '2' @('if {{QTY}}.IsNull or {{PRICE}}.IsNull then', '  {{TOTAL}}.Clear', 'else', '  {{TOTAL}}.AsFloat := {{QTY}}.AsInteger * {{PRICE}}.AsFloat;')),
    (FieldRow 'VAT' '2' @("{{VAT}}.AsFloat := {{TOTAL}}.AsFloat * $vat;")))
  $fields = @($more | ForEach-Object { , $_ }) + $fields
  $events = @((EventRow 'ID' 'OnGetText' @('Text := {{ID}}.AsString;')), (EventRow 'NOTE' 'OnGetText' @('var VOpen := ''<'';', 'Text := VOpen + {{NOTE}}.AsString + ''>'';')),
    (EventRow 'NOTE' 'OnSetText' @('{{NOTE}}.AsString := UpperCase(Text);')), (EventRow 'QTY' 'OnChange' @('{{NOTE}}.AsString := ''q'' + {{QTY}}.AsString;')),
    (EventRow 'QTY' 'OnValidate' @('if {{QTY}}.AsInteger < 0 then', '  raise Exception.Create(''negative'');')), (EventRow 'VAT' 'OnGetText' @('Text := {{VAT}}.AsString;')))
  $out = foreach ($l in [IO.File]::ReadAllLines($bk)) {
    if ($l -match '^#end DL_FIELDS_INFO 0$') { $fields | ForEach-Object { $_ }; "#end DL_FIELDS_INFO $($fields.Count)" }
    elseif ($l -match '^#end DL_LAYOUT_EVENTS 0$') { $events | ForEach-Object { $_ }; "#end DL_LAYOUT_EVENTS $($events.Count)" }
    elseif ($l -match '^#end DL_META (\d+)$') { '[DL_META schema_read_at_utc]', 'META_VALUE=2026-11-23T00:00:00Z', '', "#end DL_META $([int]$Matches[1] + 1)" }
    else { $l }
  }
  # DL_META rows are in key order
  $txt = ($out -join "`n") + "`n"
  $m = [regex]::Match($txt, '(?s)(\[DL_META schema_version\].*?\n\n)(\[DL_META schema_read_at_utc\].*?\n\n)')
  if ($m.Success) { $txt = $txt.Replace($m.Value, $m.Groups[2].Value + $m.Groups[1].Value) }
  [IO.File]::WriteAllText($bk, $txt)
  $rp = Join-Path $work "$name.dlrepo"
  $r = Run @('repo', 'restore', '--repo', $rp, '--in', $bk)
  if ($r.Code -ne 0) { throw "restore of $name failed: $($r.Out)" }
  return $rp
}
function Compile($dir, $dpr, $dcc) {
  $cb = Join-Path $dir "c_$dcc.bat"
  $clog = Join-Path $dir "c_$dcc.log"
  [IO.Directory]::CreateDirectory((Join-Path $dir "o_$dcc")) | Out-Null
  Set-Content -LiteralPath $cb -Encoding Ascii -Value @('@echo off', "call `"$rsvars`"", "cd /D `"$dir`"",
    "$dcc -B -NUo_$dcc -Eo_$dcc -NSSystem;Winapi;System.Win;Data;FireDAC $dpr", 'echo BUILD_EXITCODE=%errorlevel%')
  Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $cb + '" > "' + $clog + '" 2>&1"') -Wait -NoNewWindow
  $t = Get-Content -LiteralPath $clog -Raw
  $script:compileLog = ($t -split "`n" | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 5) -join ' '
  return ($t -match 'BUILD_EXITCODE=0') -and ($t -notmatch 'Error: [EF]\d+')
}
function ProbeOut($dir, $dpr, $dcc) {
  if (-not (Compile $dir $dpr $dcc)) { return "NOT COMPILED $script:compileLog" }
  return ((& (Join-Path $dir "o_$dcc\$([IO.Path]::GetFileNameWithoutExtension($dpr)).exe") 2>&1 | ForEach-Object { "$_" }) -join '|')
}
$fixDir = Join-Path $Repo 'tests\fixtures\fieldrepo\handlers'
function NewForm($name) {
  $d = Join-Path $work $name
  [IO.Directory]::CreateDirectory($d) | Out-Null
  foreach ($f in 'uGen.pas', 'uGen.dfm', 'HandlersProbe.dpr') { [IO.File]::Copy((Join-Path $fixDir $f), (Join-Path $d $f), $true) }
  return $d
}
function Gen($d, $rp, [string[]]$more) { Run (@('repo', 'gen-handlers', '--repo', $rp, '--dfm', (Join-Path $d 'uGen.dfm')) + $more) }
try {
  if (-not (Test-Path -LiteralPath $rsvars)) { throw 'rsvars.bat not found (no Delphi toolchain)' }
  # ---- part 1 ----
  if (-not $SkipUnit) {
    $bat = Join-Path $Repo 'build\_build_fieldrepo_handlers_tests_local.bat'
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $work + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    Check 'U0 the unit tests build' (($bl -match 'BUILD_EXITCODE=0') -and ($bl -notmatch 'Error: [EF]\d+')) $blog
    $u = (& (Join-Path $work 'HandlersTests.exe') 2>&1 | ForEach-Object { "$_" })
    $uc = $LASTEXITCODE
    $u | Where-Object { $_ -match '^FAIL' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $sum = ($u | Where-Object { $_ -match '^Summary: ' } | Select-Object -Last 1)
    Check "U1 unit tests ($sum)" (($uc -eq 0) -and ($sum -match 'pass=[1-9]\d* fail=0$')) $sum
  }
  # ---- part 2 ----
  $x = NewRepo 'x'
  $d = NewForm 'form'
  $pas = Join-Path $d 'uGen.pas'
  $old = ReadText $pas
  Check 'G0 control: the untouched fixture runs without generated values' ((ProbeOut $d 'HandlersProbe.dpr' 'dcc64') -eq 'change=|total= vat= handy=7|text=|set=|validate=none|null=TRUE|calls=TRUE') (ProbeOut $d 'HandlersProbe.dpr' 'dcc64')
  $r = Gen $d $x @()
  Check 'G1 dry run: 5 regions planned, nothing written' (($r.Out -match '5 inserted') -and ($r.Out -match 'dry run') -and ((ReadText $pas) -ceq $old)) $r.Out
  Check 'G10a a shared handler is refused and named (exit 1)' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED memOrdersID\.OnGetText \(SharedGetText\): .*more than one event')) $r.Out
  Check 'G10b an event without handler is skipped' ($r.Out -match 'skipped memOrdersVAT\.OnGetText .*assigns no OnGetText') $r.Out
  Check 'G10c code the handler holds by hand is not generated' ($r.Out -match 'HANDY: the handler holds the same code') $r.Out
  $r = Gen $d $x @('--apply')
  $new = ReadText $pas
  Check 'G2 --apply writes one unit' (($r.Out -match 'written: 1 units') -and ($new -cne $old)) $r.Out
  $want = 'change=q3|total=7.5 vat=1.5 handy=7|text=<q3>|set=ABC|validate=negative|null=TRUE|calls=TRUE'
  foreach ($dcc in 'dcc32', 'dcc64') { $got = ProbeOut $d 'HandlersProbe.dpr' $dcc; Check "G3 ${dcc}: the generated unit compiles and runs" ($got -ceq $want) "$got" }
  # inserted on the line of the end (NOTESetText, QTYChange): the end moved to its own line, so one line break is added
  $outside = (Outside $new).Replace("begin Inc(Calls); `r`nend;", 'begin Inc(Calls); end;').Replace("  comment } `r`nend;", '  comment } end;')
  Check 'G4 outside the regions every byte is kept' ($outside -ceq $old) 'differs'
  Check 'G4b the regions are the five expected ones' (([regex]::Matches($new, "(?m)^ *\{\`$REGION 'DLFR (memOrders\.OnCalcFields|memOrdersNOTE\.OnGetText|memOrdersNOTE\.OnSetText|memOrdersQTY\.OnValidate|memOrdersQTY\.OnChange) hash=(?!0123456789abcdef)")).Count -eq 5)
  Check 'G4c the copies in the comment and the string are there unchanged' (([regex]::Matches($new, 'hash=0123456789abcdef')).Count -eq 3)
  Check 'G4d 7-bit ASCII, CRLF only' ((@([IO.File]::ReadAllBytes($pas) | Where-Object { $_ -gt 127 }).Count -eq 0) -and ($new.Replace("`r`n", '') -notmatch "[\r\n]"))
  $h = Hash $pas
  $t0 = (Get-Item -LiteralPath $pas).LastWriteTimeUtc
  $r = Gen $d $x @('--apply')
  Check 'G5 a second run writes nothing' (($r.Out -match 'written: 0 units') -and ($r.Out -match '5 unchanged') -and ((Hash $pas) -eq $h) -and ((Get-Item -LiteralPath $pas).LastWriteTimeUtc -eq $t0)) $r.Out
  # G6: hand code behind the region, a new body
  Edit $pas "  {`$ENDREGION 'DLFR memOrders.OnCalcFields'}`r`nend;" "  {`$ENDREGION 'DLFR memOrders.OnCalcFields'}`r`n  if memOrdersHANDY.AsInteger = 0 then`r`n    Calls := 0;`r`nend;"
  $before = ReadText $pas
  $y = NewRepo 'y' '0.5'
  $r = Gen $d $y @('--apply')
  $after = ReadText $pas
  Check 'G6a one region updated, four unchanged' (($r.Out -match '1 updated') -and ($r.Out -match '4 unchanged') -and ($r.Out -match 'written: 1 units')) $r.Out
  Check 'G6b hand code around it survives' ((Outside $after) -ceq (Outside $before)) 'differs'
  $got = ProbeOut $d 'HandlersProbe.dpr' 'dcc64'
  Check 'G6c compiles and runs with the new body' ($got -ceq $want.Replace('vat=1.5', 'vat=3.75')) "$got"
  # G7: hand edit inside one region, both bodies change
  $e = NewForm 'edited'
  $epas = Join-Path $e 'uGen.pas'
  $null = Gen $e $x @('--apply')
  Edit $epas '* 0.2;' '* 0.3;'
  $m1 = [regex]::Match((ReadText $epas), "(?s)  \{\`$REGION 'DLFR memOrders\.OnCalcFields hash=(?!0123).*?ENDREGION 'DLFR memOrders\.OnCalcFields'\}").Value
  $r = Gen $e $y @('--apply')
  Check 'G7a a hand-edited region is refused and named' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED memOrders\.OnCalcFields .*hand-edited') -and ($m1.Length -gt 0) -and (ReadText $epas).Contains($m1)) $r.Out
  $z = NewRepo 'z' '0.3'
  $r = Gen $e $z @('--apply')
  Check 'G7b ... also when the repository now says the same' (($r.Out -match 'REFUSED memOrders\.OnCalcFields .*hand-edited') -and ($r.Out -match 'written: 0 units')) $r.Out
  Edit $epas "UpperCase(Text)" "LowerCase(Text)"
  $h = Hash $epas
  $r = Gen $e $x @('--apply')
  Check 'G7c two hand-edited regions, nothing else to do: file untouched' (($r.Out -match '3 refused') -and ((Hash $epas) -eq $h)) $r.Out
  $e2 = NewForm 'edited2'
  $e2pas = Join-Path $e2 'uGen.pas'
  $null = Gen $e2 $x @('--apply')
  $t = ReadText $e2pas
  $t = [regex]::Replace($t, "(?s)  \{\`$REGION 'DLFR memOrdersNOTE\.OnSetText.*?ENDREGION 'DLFR memOrdersNOTE\.OnSetText'\}\r\n", '').Replace("Text := VOpen +", "Text := '?' + VOpen +")
  WriteText $e2pas $t
  $r = Gen $e2 $x @('--apply')
  Check 'G7d beside a hand-edited region another one is still written' (($r.Out -match 'REFUSED memOrdersNOTE\.OnGetText') -and ($r.Out -match 'inserted memOrdersNOTE\.OnSetText') -and (ReadText $e2pas).Contains("'?' + VOpen")) $r.Out
  # G8
  $c = NewForm 'commented'
  $cpas = Join-Path $c 'uGen.pas'
  $null = Gen $c $x @('--apply')
  $t = ReadText $cpas
  $i = $t.LastIndexOf("  {`$ENDREGION 'DLFR memOrders.OnCalcFields'}")
  WriteText $cpas ($t.Substring(0, $i) + '//' + $t.Substring($i))
  $h = Hash $cpas
  $r = Gen $c $y @('--apply')
  Check 'G8 an end marker that is commented out: refused, file untouched' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED') -and ((Hash $cpas) -eq $h)) $r.Out
  # G9
  foreach ($case in @(@('ANSI', [byte[]](0xE9)), @('UTF-8', [byte[]](0xC3, 0xA9)))) {
    $n = NewForm "nonascii$($case[0])"
    $npas = Join-Path $n 'uGen.pas'
    Edit $npas '// hand' ('// hand ' + $ansi.GetString($case[1]))
    $h = Hash $npas
    $r = Gen $n $x @('--apply')
    Check "G9 $($case[0]) text in the unit: refused, not one byte changed" (($r.Code -eq 1) -and ($r.Out -match 'not 7-bit ASCII') -and ((Hash $npas) -eq $h)) $r.Out
  }
  $n = NewForm 'bom'
  $npas = Join-Path $n 'uGen.pas'
  [IO.File]::WriteAllBytes($npas, [byte[]](0xEF, 0xBB, 0xBF) + [IO.File]::ReadAllBytes($npas))
  $h = Hash $npas
  $r = Gen $n $x @('--apply')
  Check 'G9 a BOM: refused, unchanged' (($r.Code -eq 1) -and ((Hash $npas) -eq $h)) $r.Out
  # G11 / G12
  $r = Gen (NewForm 'json') $x @('--json')
  $j = $null
  try { $j = $r.Out | ConvertFrom-Json } catch { }
  Check 'G11 --json is one object with the same facts' (($null -ne $j) -and ($j.refused -eq 1) -and ($j.not_written -eq 0) -and ($j.units[0].written -eq $false) -and ($j.written -eq 0) -and (@($j.units[0].regions | Where-Object state -eq 'inserted').Count -eq 5)) $r.Out
  Check 'G12a no --dfm = 2' ((Run @('repo', 'gen-handlers', '--repo', $x)).Code -eq 2)
  Check 'G12b a missing repository = 1' ((Gen $d (Join-Path $work 'nope.dlrepo') @()).Code -eq 1)
  Check 'G12c an unknown dataset = 1' ((Gen $d $x @('--dataset', 'nope')).Code -eq 1)
  $n = NewForm 'nounit'
  [IO.File]::Delete((Join-Path $n 'uGen.pas'))
  Check 'G12d no unit beside the DFM = 1, none created' (((Gen $n $x @('--apply')).Code -eq 1) -and -not (Test-Path -LiteralPath (Join-Path $n 'uGen.pas')))
  $n = NewForm 'dry'
  $h = Hash (Join-Path $n 'uGen.pas')
  $r = Gen $n $x @('--apply', '--dry-run')
  Check 'G12e --dry-run wins over --apply' (((Hash (Join-Path $n 'uGen.pas')) -eq $h) -and ($r.Out -match 'dry run')) $r.Out
  # G13
  $n = NewForm 'multi'
  Edit (Join-Path $n 'uGen.dfm') '    OnCalcFields = memOrdersCalcFields' "    AfterScroll = memOrdersCalcFields`r`n    OnCalcFields = memOrdersCalcFields"
  $r = Gen $n $x @('--apply')
  Check 'G13 a handler that AfterScroll names too: refused, not filled' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED memOrders\.OnCalcFields \(memOrdersCalcFields\): .*more than one event') -and
    ((ReadText (Join-Path $n 'uGen.pas')) -notmatch 'DLFR memOrders\.OnCalcFields hash=(?!0123)')) $r.Out
  # G14
  function Two($a, $b, [string[]]$more) { Run (@('repo', 'gen-handlers', '--repo', $x, '--dfm', ((Join-Path $a 'uGen.dfm') + ';' + (Join-Path $b 'uGen.dfm'))) + $more) }
  foreach ($how in 'locked', 'readonly') {
    $a = NewForm "${how}A"
    $b = NewForm "${how}B"
    $apas = Join-Path $a 'uGen.pas'
    $h = Hash $apas
    $lock = $null
    if ($how -eq 'locked') { $lock = [IO.File]::Open($apas, 'Open', 'Read', 'Read') } else { [IO.File]::SetAttributes($apas, 'ReadOnly') }
    try {
      $r = Two $a $b @('--apply')
      Check "G14a ${how}: named as not written, the other one as written, exit 1" (($r.Code -eq 1) -and ($r.Out -match ('NOT WRITTEN ' + [regex]::Escape($apas) + ': ')) -and
        ($r.Out -match ('(?m)^  written ' + [regex]::Escape((Join-Path $b 'uGen.pas')))) -and ($r.Out -match 'written: 1 units, NOT WRITTEN: 1 units') -and ($r.Out -match '10 inserted')) $r.Out
      Check "G14b ${how}: it is as it was, the other one is done" (((Hash $apas) -eq $h) -and ((ReadText (Join-Path $b 'uGen.pas')) -ceq $new))
      Check "G14c ${how}: no temporary file is left" ((@(Get-ChildItem $a).Count -eq 3) -and (@(Get-ChildItem $b).Count -eq 3))
      $r = Two $a $b @('--apply', '--json')
      $j = $null
      try { $j = $r.Out | ConvertFrom-Json } catch { }
      Check "G14d ${how}: --json says the same" (($r.Code -eq 1) -and ($null -ne $j) -and ($j.not_written -eq 1) -and ($j.written -eq 0) -and ($j.units[0].error -ne '') -and ($j.units[1].error -eq '')) $r.Out
    }
    finally { if ($lock) { $lock.Dispose() } else { [IO.File]::SetAttributes($apas, 'Normal') } }
  }
  # G15
  $a = NewForm 'twice'
  $r = Two $a $a.ToUpper() @('--apply')
  Check 'G15 a form named twice is planned and written once' (($r.Out -match '(?m)^1 units, 1 to write, 0 unchanged, 5 inserted') -and ($r.Out -match 'written: 1 units') -and ((ReadText (Join-Path $a 'uGen.pas')) -ceq $new)) $r.Out

  # ---- part 3 ----
  $o = Join-Path $work 'orm'
  [IO.Directory]::CreateDirectory($o) | Out-Null
  $iu = Join-Path $o 'iORDERS.pas'
  [IO.File]::Copy((Join-Path $fixDir 'iORDERS.pas'), $iu)
  $iold = ReadText $iu
  function Len([string[]]$more, $rp = $x) { Run (@('repo', 'gen-maxlen', '--repo', $rp, '--code-dir', $o) + $more) }
  $r = Len @()
  Check 'M1 dry run; the hand-kept constant is noted' (($r.Code -eq 0) -and ((ReadText $iu) -ceq $iold) -and ($r.Out -match 'ORDERS_REFNO_MAXLEN is declared by hand as 11, the repository says 12') -and ($r.Out -match 'inserted 2a \(ORDERS\)')) $r.Out
  $r = Len @('--apply')
  $inew = ReadText $iu
  Check 'M2a written; outside the region every byte is kept' (($r.Code -eq 0) -and ($inew -cne $iold) -and ((Outside $inew) -ceq $iold)) $r.Out
  Set-Content -LiteralPath (Join-Path $o 'P.dpr') -Encoding Ascii -Value @('program P;', '{$APPTYPE CONSOLE}', 'uses iORDERS in ''iORDERS.pas'';', 'begin', '  Writeln(ORDERS_NOTE_MAXLEN, '' '', ORDERS_REFNO_MAXLEN);', 'end.')
  foreach ($dcc in 'dcc32', 'dcc64') { $got = ProbeOut $o 'P.dpr' $dcc; Check "M2b ${dcc}: the unit compiles, the constants are there" ($got -ceq '40 11') "$got" }
  $h = Hash $iu
  $r = Len @('--apply')
  Check 'M3 a second run writes nothing' (($r.Out -match 'written: 0 units') -and ((Hash $iu) -eq $h)) $r.Out
  $q = NewRepo 'q' '0.2' '50'
  $r = Len @('--apply') $q
  $got = ProbeOut $o 'P.dpr' 'dcc64'
  Check 'M3b a changed length: updated, compiles, outside kept' (($got -ceq '50 11') -and ((Outside (ReadText $iu)) -ceq $iold)) "$got $($r.Out)"
  Edit $iu 'NOTE_MAXLEN = 50' 'NOTE_MAXLEN = 51'
  $h = Hash $iu
  $r = Len @('--apply')
  Check 'M4 a hand-edited region is refused, unchanged' (($r.Code -eq 1) -and ($r.Out -match 'REFUSED 2a .*hand-edited') -and ((Hash $iu) -eq $h)) $r.Out
  WriteText $iu ($iold.Replace('Hand-kept', "Hand-k$([char]0xE9)pt"))
  $h = Hash $iu
  $r = Len @('--apply')
  Check 'M5 not ASCII: refused, unchanged' (($r.Code -eq 1) -and ($r.Out -match 'not 7-bit ASCII') -and ((Hash $iu) -eq $h)) $r.Out
  Check 'M6 no --code-dir = 2; a folder that is missing = 2; a named table without unit = 1' (((Run @('repo', 'gen-maxlen', '--repo', $x)).Code -eq 2) -and
    ((Run @('repo', 'gen-maxlen', '--repo', $x, '--code-dir', (Join-Path $work 'nope'))).Code -eq 2) -and ((Len @('--table', 'NOPE')).Code -eq 1))

  WriteText $iu $iold
  $r = Len @('--table', 'ORDERS,orders', '--apply')
  Check 'M7 a table named twice: one unit, written' (($r.Code -eq 0) -and ($r.Out -match '(?m)^1 units, 1 to write') -and ($r.Out -match 'written: 1 units') -and ((ReadText $iu) -ceq $inew)) $r.Out
  $ab = Join-Path $o 'iA_B.pas'
  WriteText $ab ($iold.Replace('iORDERS', 'iA_B'))
  $h = Hash $ab
  $two = NewRepo 'two' '0.2' '40' @((FieldRow 'F' '' @() '5').Replace('ORDERS', 'A$B'), (FieldRow 'F' '' @() '6').Replace('ORDERS', 'A_B'))
  foreach ($t in 'A$B,A_B', 'A_B') {
    $r = Len @('--table', $t, '--apply') $two
    Check "M8 ${t}: the unit of two tables is refused once, both are named, unchanged" (($r.Code -eq 1) -and ($r.Out -match 'REFUSED iA_B.pas: the unit belongs to more than one table: A\$B, A_B') -and
      ($r.Out -match '(?m)^1 units, 0 to write') -and ((Hash $ab) -eq $h)) $r.Out
  }
  [IO.File]::Delete($ab)

  # ---- part 4 ----
  WriteText $iu $iold
  function Renumber([string[]]$more) { Run (@('repo', 'renumber-regions', '--repo', $x, '--code-dir', $o) + $more) }
  $r = Renumber @()
  Check 'N1 dry run: one region of one unit, nothing written' (($r.Code -eq 0) -and ($r.Out -match 'updated 1 regions') -and ((ReadText $iu) -ceq $iold)) $r.Out
  $reads = $r.Out -notmatch 'does not read DLFR regions'
  $r = Renumber @('--apply')
  if ($reads) {
    $wanted = $iold.Replace("{`$REGION 'DB-RAD 2'}", "{`$REGION 'DLFR 2'}").Replace("{`$ENDREGION 'DB-RAD 2'}", "{`$ENDREGION 'DLFR 2'}")
    Check 'N2a renamed: exactly the two markers, the comment stays' (($r.Code -eq 0) -and ((ReadText $iu) -ceq $wanted)) $r.Out
    $h = Hash $iu
    $r = Renumber @('--apply')
    Check 'N2b a second run writes nothing' (($r.Code -eq 0) -and ($r.Out -match 'written: 0 units') -and ((Hash $iu) -eq $h)) $r.Out
    $r = Len @('--apply')
    $got = ProbeOut $o 'P.dpr' 'dcc64'
    Check 'N2c gen-maxlen finds the renamed section 2; compiles' ($got -ceq '40 11') "$got $($r.Out)"
  } else {
    Check 'N2 update-orm does not read DLFR yet: --apply is refused, nothing written' (($r.Code -eq 1) -and ((ReadText $iu) -ceq $iold)) $r.Out
  }
  WriteText $iu ($iold.Replace('Hand-kept', "Hand-k$([char]0xE9)pt"))
  $h = Hash $iu
  $r = Renumber @('--apply')
  Check 'N3 not ASCII: refused, unchanged' (($r.Code -eq 1) -and ($r.Out -match 'not 7-bit ASCII') -and ((Hash $iu) -eq $h)) $r.Out
  Check 'N4 neither --code-dir nor --in = 2' ((Run @('repo', 'renumber-regions', '--repo', $x)).Code -eq 2)
}
catch { $script:fail++; Write-Host "[FAIL] exception: $_ $($_.ScriptStackTrace)" -ForegroundColor Red }
finally { if ($script:fail -eq 0) { [IO.Directory]::Delete($work, $true) } else { Write-Host "kept: $work" } }
if ($script:fail -gt 0) { Write-Host "FIELDREPO HANDLERS: FAIL pass=$script:pass fail=$script:fail" -ForegroundColor Red; exit 1 }
Write-Host "FIELDREPO HANDLERS: PASS pass=$script:pass fail=0" -ForegroundColor Green
exit 0
