<#
  run_comment_facts_fixture.ps1 -- wave 151 lane W1, acceptance (a): the
  comment_facts rows of tests\fixtures\comment-facts-151\src (every comment kind,
  `{$IFDEF}` / `(*$..*)` directives that are NOT comments, a comment inside
  generic args `TList<{x} Integer>`, `//` and `{` inside string literals, a
  nested `(* { } *)`, a Delphi 12 ''' multi-line string, trailing `///`, a dl:ok
  marker and a dl:bk bookmark) as the engine STORES them.

  Indexes the fixture into a TEMP DB and checks, through `sql --json` (rows are
  POSITIONAL arrays, mapped onto columns[].name):
    F1  the rows (ordinal, line, col, end_line, kind, anchor_kind, anchor
        symbol's qualified name, text) equal expected-comment-facts.tsv
    F2  offsets map back: the file's decoded text, Substring(start_offset,
        end_offset - start_offset) == text, on every row
    F3  col is 1-based UTF-8 bytes from the line start, line = the offset's line
    F4  every `///` row anchored next-declaration names a symbol that HAS a
        symbol_docs row (the doc attribution and the anchor agree)
    F5  no row starts with `{$` / `(*$` (directives are not comments) and no
        row lies inside a string literal (the two string sentinels)
  Positive control: -Exe <the 1.49.0-alpha base engine> -- F1..F4 FAIL (no rows).
  -Emit prints the actual TSV (to refresh the expected file after a REVIEWED change).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$Emit)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_comment_facts_fixture: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_comment_facts_fixture: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxRoot   = Join-Path $repo 'tests\fixtures\comment-facts-151'
$expected = Join-Path $fxRoot 'expected-comment-facts.tsv'
$work = Join-Path $env:TEMP ('dl-cf-fixture-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
$fx = Join-Path $work 'src'
Copy-Item -Recurse (Join-Path $fxRoot 'src') $fx
$db = Join-Path $work 'cf.sqlite'

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function Lane-Sql([string]$Db, [string]$Query) {
  $raw = & $Exe sql --query $Query --db $Db --json 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return }
  try { $j = ($raw -join "`n") | ConvertFrom-Json } catch { return }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return $out.ToArray()
}
function Esc([string]$S) { return $S.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t') }

Write-Host "run_comment_facts_fixture: engine $Exe" -ForegroundColor Cyan
& $Exe index $fx --db $db *> (Join-Path $work 'index.log')
$rc = $LASTEXITCODE
$rows = @(Lane-Sql $db @"
SELECT f.path AS path, c.ordinal, c.start_offset, c.end_offset, c.line, c.col, c.end_line, c.kind, c.text,
       c.anchor_kind, COALESCE(s.qualified_name, '') AS anchor, c.anchor_symbol_id AS anchor_id,
       (SELECT COUNT(*) FROM symbol_docs d WHERE d.symbol_id = c.anchor_symbol_id) AS anchor_docs
FROM comment_facts c JOIN files f ON f.id = c.file_id LEFT JOIN symbols s ON s.id = c.anchor_symbol_id
ORDER BY f.path, c.ordinal
"@)
Write-Host "  INFO  index rc $rc, comment_facts rows $($rows.Count)"

$actual = @($rows | ForEach-Object {
  @((Split-Path $_.path -Leaf), $_.ordinal, $_.line, $_.col, $_.end_line, $_.kind, $_.anchor_kind, $_.anchor, (Esc $_.text)) -join "`t"
})
if ($Emit) { $actual | ForEach-Object { Write-Output $_ } }

# ---- F1 ----------------------------------------------------------------------
$want = @(Get-Content $expected | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
$diff = @(Compare-Object $want $actual -SyncWindow 0)
Check 'F1 rows equal expected-comment-facts.tsv' (($rows.Count -gt 0) -and ($diff.Count -eq 0)) "(expected $($want.Count), got $($actual.Count), differing $($diff.Count))"
$diff | Select-Object -First 8 | ForEach-Object { Write-Host "        $($_.SideIndicator) $($_.InputObject)" }

# ---- F2 / F3 -------------------------------------------------------------------
$texts = @{}
$bad2 = 0; $bad3 = 0
foreach ($r in $rows) {
  if (-not $texts.ContainsKey($r.path)) { $texts[$r.path] = [IO.File]::ReadAllText($r.path, [Text.Encoding]::UTF8) }
  $t = $texts[$r.path]
  $s = [int]$r.start_offset; $e = [int]$r.end_offset
  if (($e -lt $s) -or ($e -gt $t.Length) -or ($t.Substring($s, $e - $s) -ne $r.text)) { $bad2++; Write-Host "        F2 row $($r.ordinal) [$s,$e)" }
  $ls = $t.LastIndexOfAny([char[]]"`r`n", [Math]::Max($s - 1, 0)) + 1
  if ($s -eq 0) { $ls = 0 }
  $line = 1 + ([regex]::Matches($t.Substring(0, $s), "`r`n|`r|`n")).Count
  $col = 1 + [Text.Encoding]::UTF8.GetByteCount($t.Substring($ls, $s - $ls))
  if (($line -ne [int]$r.line) -or ($col -ne [int]$r.col)) { $bad3++; Write-Host "        F3 row $($r.ordinal) want L$line C$col got L$($r.line) C$($r.col)" }
}
Check 'F2 every row maps back: text == Substring(start, end - start)' (($rows.Count -gt 0) -and ($bad2 -eq 0)) "($bad2 bad of $($rows.Count))"
Check 'F3 line / col (UTF-8 bytes) match the offset' (($rows.Count -gt 0) -and ($bad3 -eq 0)) "($bad3 bad)"

# ---- F4 ----------------------------------------------------------------------
$docRows = @($rows | Where-Object { $_.kind -eq '///' -and $_.anchor_kind -eq 'next-declaration' })
$undoc = @($docRows | Where-Object { [int]$_.anchor_docs -lt 1 })
Check 'F4 `///` next-declaration anchors carry a symbol_docs row' (($docRows.Count -ge 2) -and ($undoc.Count -eq 0)) "($($docRows.Count) rows, $($undoc.Count) without a doc row)"

# ---- F5 ----------------------------------------------------------------------
$dir = @($rows | Where-Object { $_.text -like '{$*' -or $_.text -like '(*$*' })
$inStr = @($rows | Where-Object { $_.text -like '*example.com*' -or $_.text -like '*still a string*' -or $_.text -like '*multi // line*' })
Check 'F5 no directive rows, no rows inside string literals' (($rows.Count -gt 0) -and ($dir.Count -eq 0) -and ($inStr.Count -eq 0)) "($($dir.Count) directive, $($inStr.Count) in-string)"

try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (scratch $work left: $($_.Exception.Message))" }
Write-Host ("run_comment_facts_fixture: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
