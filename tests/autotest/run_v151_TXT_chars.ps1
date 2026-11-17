<#
  run_v151_TXT_chars.ps1 -- raw-byte text rules of lane TXT: bidi-control, invisible-char, control-char, file-header.
  Fixtures are generated as BYTES at run time (the repo's .pas/.dfm files are 7-bit ASCII, so a fixture with a
  bidi mark or a NUL cannot live in tests\lint). Every must-fire has a positive control: --disable <id> -> gone.
  Usage: pwsh -File tests\autotest\run_v151_TXT_chars.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("v151txt-" + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$db = Join-Path $work 'empty.sqlite'
$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok) {
  if ($ok) { $script:pass++; Write-Host "PASS  $name" } else { $script:fail++; Write-Host "FAIL  $name" }
}
function Asc([string]$s) { [Text.Encoding]::ASCII.GetBytes($s) }
function JoinB([byte[][]]$parts) { $m = New-Object IO.MemoryStream; foreach ($p in $parts) { $m.Write($p, 0, $p.Length) }; $m.ToArray() }
function Put([string]$name, [byte[]]$bytes) { $p = Join-Path $work $name; [IO.File]::WriteAllBytes($p, $bytes); $p }
function Lint([string]$file, [string[]]$extra = @()) {
  $out = & $exePath lint $file --json @extra 2>$null | Out-String
  $t = $out.Trim()
  if ($t.StartsWith('[')) { return @($t | ConvertFrom-Json) }
  return @()
}
function Has($f, [string]$id, [int]$line, [int]$col = 0) {
  @($f | Where-Object { $_.rule -eq $id -and $_.start_line -eq $line -and ($col -eq 0 -or $_.start_col -eq $col) }).Count -gt 0
}
function Count($f, [string]$id) { @($f | Where-Object { $_.rule -eq $id }).Count }
$head = "unit U;`r`ninterface`r`nimplementation`r`n"
$tail = "end.`r`n"
try {
  # raw JSON field names: print once so a wrong name cannot make every check vacuous
  $p0 = Put 'probe.pas' (JoinB @((Asc $head), (Asc "// TODO: x`r`n"), (Asc $tail)))
  $raw = (& $exePath lint $p0 --json --enable todo-comment 2>$null | Out-String)
  Write-Host ("probe raw[0..120]: " + $raw.Substring(0, [Math]::Min(120, $raw.Length)).Replace("`r", ' ').Replace("`n", ' '))
  Check 'probe: json carries rule/start_line' ((Has (Lint $p0 @('--enable','todo-comment')) 'todo-comment' 4))

  # bidi: U+202E (E2 80 AE) in a comment on line 4, col 4 ("// " then the mark)
  $bidi = Put 'bidi.pas' (JoinB @((Asc $head), (Asc '// '), [byte[]](0xE2,0x80,0xAE), (Asc "`r`n"), (Asc $tail)))
  $f = Lint $bidi
  # positive-control: bidi-control
  Check 'bidi-control fires at line 4 col 4' (Has $f 'bidi-control' 4 4)
  Check 'bidi-control: only that rule' ((Count $f 'invisible-char') -eq 0 -and (Count $f 'control-char') -eq 0)
  Check 'bidi-control: --disable removes it (positive control)' ((Count (Lint $bidi @('--disable','bidi-control')) 'bidi-control') -eq 0)
  # isolate U+2066 and mark U+200F too
  $bidi2 = Put 'bidi2.pas' (JoinB @((Asc $head), (Asc "// a"), [byte[]](0xE2,0x81,0xA6), [byte[]](0xE2,0x80,0x8F), (Asc "`r`n"), (Asc $tail)))
  Check 'bidi-control: 2 marks on one line = 2 findings' ((Count (Lint $bidi2) 'bidi-control') -eq 2)

  # invisible: U+200B in a string, col counts code points
  $inv = Put 'inv.pas' (JoinB @((Asc $head), (Asc "const C = 'a"), [byte[]](0xE2,0x80,0x8B), (Asc "b';`r`n"), (Asc $tail)))
  $f = Lint $inv
  # positive-control: invisible-char
  Check 'invisible-char fires at line 4 col 13' (Has $f 'invisible-char' 4 13)
  Check 'invisible-char: --disable removes it' ((Count (Lint $inv @('--disable','invisible-char')) 'invisible-char') -eq 0)
  # an ordinary accented letter is not invisible; a non-BOM FEFF mid-file is
  $acc = Put 'acc.pas' (JoinB @((Asc $head), (Asc "// caf"), [byte[]](0xC3,0xA9), (Asc "`r`n"), (Asc $tail)))
  $f = Lint $acc
  Check 'e-acute (valid UTF-8, no BOM) triggers none of the three' (((Count $f 'invisible-char') + (Count $f 'bidi-control') + (Count $f 'control-char')) -eq 0)
  $feff = Put 'feff.pas' (JoinB @([byte[]](0xEF,0xBB,0xBF), (Asc $head), (Asc '// x'), [byte[]](0xEF,0xBB,0xBF), (Asc "`r`n"), (Asc $tail)))
  $f = Lint $feff
  Check 'leading BOM is fine, a second FEFF is reported' ((Count $f 'invisible-char') -eq 1 -and (Has $f 'invisible-char' 4))

  # control: NUL inside a string
  $nul = Put 'nul.pas' (JoinB @((Asc $head), (Asc "const C = 'a"), [byte[]](0x00), (Asc "b';`r`n"), (Asc $tail)))
  $f = Lint $nul
  # positive-control: control-char
  Check 'control-char fires on NUL at line 4 col 13' (Has $f 'control-char' 4 13)
  Check 'control-char: --disable removes it' ((Count (Lint $nul @('--disable','control-char')) 'control-char') -eq 0)
  # form feed, tab and a trailing Ctrl-Z are tolerated
  $ok = Put 'ok.pas' (JoinB @((Asc $head), (Asc "`t// tab"), [byte[]](0x0C), (Asc "`r`n"), (Asc $tail), [byte[]](0x1A)))
  Check 'TAB, FF and a trailing Ctrl-Z are not control-char' ((Count (Lint $ok) 'control-char') -eq 0)
  $ctz = Put 'ctz.pas' (JoinB @((Asc $head), [byte[]](0x1A), (Asc "`r`n"), (Asc $tail)))
  Check 'a Ctrl-Z in the middle is control-char' (Has (Lint $ctz) 'control-char' 4)

  # invalid UTF-8: only reported when the file declares UTF-8 with a BOM
  $bad = Put 'bad.pas' (JoinB @([byte[]](0xEF,0xBB,0xBF), (Asc $head), (Asc '// x'), [byte[]](0xE9), (Asc "y`r`n"), (Asc $tail)))
  # 152 TESTS: hard assertion (was a comment-swallowed soft check, FOUND TXT-1): a UTF-8 BOM file with an invalid byte reports control-char.
  Check 'BOM + invalid byte E9 -> control-char line 4' (Has (Lint $bad) 'control-char' 4)
  $ansi = Put 'ansi.pas' (JoinB @((Asc $head), (Asc '// caf'), [byte[]](0xE9), (Asc "`r`n"), (Asc $tail)))
  Check 'no BOM, byte E9 = legacy ANSI -> no control-char' ((Count (Lint $ansi) 'control-char') -eq 0)
  # UTF-16 LE with BOM: NUL bytes are the encoding, not corruption
  $u16 = Put 'u16.pas' (JoinB @([byte[]](0xFF,0xFE), [Text.Encoding]::Unicode.GetBytes($head + "// plain`r`n" + $tail)))
  $f = Lint $u16
  Check 'UTF-16 LE file: no control-char' ((Count $f 'control-char') -eq 0)

  # sibling .dfm: text form scanned, binary form skipped
  $dp = Put 'frm.pas' (JoinB @((Asc $head), (Asc $tail)))
  $dd = Put 'frm.dfm' (JoinB @((Asc "object F: TForm`r`n  Caption = 'a"), [byte[]](0xE2,0x80,0xAE), (Asc "'`r`nend`r`n")))
  $f = Lint $dp
  Check 'bidi-control found in the sibling .dfm (line 2)' (@($f | Where-Object { $_.rule -eq 'bidi-control' -and $_.start_line -eq 2 -and ([string]$_.file_path).EndsWith('.dfm') }).Count -ge 0 -and (Has $f 'bidi-control' 2))
  $dd2 = Put 'frm.dfm' (JoinB @((Asc 'TPF0'), [byte[]](0x00,0x01,0x02), [byte[]](0xE2,0x80,0xAE)))
  Check 'binary .dfm (TPF0) is skipped' ((Count (Lint $dp) 'bidi-control') -eq 0)
  [IO.File]::Delete($dd2)

  # file-header: template file found by walking up from the unit
  $hd = Join-Path $work 'hdr'; [IO.Directory]::CreateDirectory((Join-Path $hd 'sub')) | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $hd 'drag-lint-header.txt'), (Asc "{ Acme Corp`r`n  Licence: internal }`r`n"))
  $good = Join-Path $hd 'sub\good.pas'
  [IO.File]::WriteAllBytes($good, (JoinB @((Asc "{ Acme Corp   `r`n  Licence: internal }`r`n"), (Asc $head), (Asc $tail))))
  $miss = Join-Path $hd 'sub\miss.pas'
  [IO.File]::WriteAllBytes($miss, (JoinB @((Asc $head), (Asc $tail))))
  $diff = Join-Path $hd 'sub\diff.pas'
  [IO.File]::WriteAllBytes($diff, (JoinB @((Asc "{ Acme Corp`r`n  Licence: public }`r`n"), (Asc $head), (Asc $tail))))
  Check 'file-header: matching header (trailing blanks ignored) is clean' ((Count (Lint $good @('--enable','file-header')) 'file-header') -eq 0)
  # positive-control: file-header
  Check 'file-header: missing header -> line 1' (Has (Lint $miss @('--enable','file-header')) 'file-header' 1)
  Check 'file-header: different second line -> line 2' (Has (Lint $diff @('--enable','file-header')) 'file-header' 2)
  Check 'file-header: --disable removes it (positive control)' ((Count (Lint $miss @('--enable','file-header','--disable','file-header')) 'file-header') -eq 0)
  Check 'file-header: OFF by default' ((Count (Lint $miss) 'file-header') -eq 0)
  Check 'file-header: no template file -> silent' ((Count (Lint $ok @('--enable','file-header')) 'file-header') -eq 0)
}
finally {
  [IO.Directory]::Delete($work, $true)
}
Write-Host "run_v151_TXT_chars: $pass pass / $fail fail"
exit ([int]($fail -gt 0))
