<#
  run_bookmarks.ps1 -- E-BOOKMARKS (wave 146 lane g2): `drag-lint bookmarks`, the read-only
  list/find verb over `// dl:bk<N>` and `// dl:bk:<CODE> -- reason` comment anchors.

  Fixture shapes (each one a way a text match would answer wrong):
  * numbered and tagged anchors, with and without @hash and a reason;
  * the tag inside a STRING literal, inside brace and star-paren comments, and in the
    middle of a line comment's prose: none is a bookmark (first token of a // comment only);
  * a malformed tag (3-character DL code, dl:bk with no number): skipped;
  * --name finds by code (case-insensitive for tagged), exit 3 on no hit, 2 on a missing path.
  Positive control: the expected count of 4 FAILS if the verb is absent (RED on an old engine).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-bookmarks-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$Exe = (Resolve-Path $Exe).Path
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null
try {
  $lines = @(
    'unit uBk;',                                        # 1
    'interface',                                        # 2
    'implementation',                                   # 3
    'procedure A;',                                     # 4
    'begin',                                            # 5
    '  Foo; // dl:bk3',                                 # 6  user
    '  Bar; // dl:bk:A7K3QX -- check the lock order',   # 7  dl + reason
    '  Baz; // dl:bk12@7f3a',                           # 8  user + hash
    '  S := ''// dl:bk4'';',                            # 9  string: no
    '  { dl:bk5 }',                                     # 10 brace comment: no
    '  (* dl:bk6 *)',                                   # 11 star-paren: no
    '  Qux; // see dl:bk7 below',                       # 12 prose: no
    '  Q2; // dl:bk:AB -- short code',                  # 13 malformed: no
    '  Q3; // dl:bk',                                   # 14 no number: no
    '  Q4; //dl:bk:zz9y8x7w@beef -- tagged, lower case',# 15 dl, 8 chars
    'end;',
    'end.')
  $src = Join-Path $WorkDir 'uBk.pas'
  [IO.File]::WriteAllText($src, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

  $o = & $Exe bookmarks --in $src --json 2>&1
  $code = $LASTEXITCODE
  $rows = $null
  try { $rows = @($o | Out-String | ConvertFrom-Json) } catch { }
  Check 'list: exit 0' ($code -eq 0) "exit=$code"
  Check 'list: exactly 4 anchors (bare array, raw shape)' ($rows -and $rows.Count -eq 4) ("count=" + @($rows).Count + ' raw=' + (($o | Out-String).Trim().Substring(0, [Math]::Min(120, ($o | Out-String).Trim().Length))))
  if ($rows -and $rows.Count -eq 4) {
    Check 'line numbers 6,7,8,15' ((($rows | % { $_.line }) -join ',') -eq '6,7,8,15')
    Check 'kinds user,dl,user,dl' ((($rows | % { $_.kind }) -join ',') -eq 'user,dl,user,dl')
    Check 'tagged code + reason' ($rows[1].code -eq 'A7K3QX' -and $rows[1].reason -eq 'check the lock order')
    Check 'hash on numbered' ($rows[2].code -eq '12' -and $rows[2].hash -eq '7f3a')
  }

  $o = & $Exe bookmarks --in $src --name a7k3qx --json 2>&1
  $f = @($o | Out-String | ConvertFrom-Json)
  Check 'find: tagged code is case-insensitive, one hit at line 7' ($LASTEXITCODE -eq 0 -and $f.Count -eq 1 -and $f[0].line -eq 7)
  $null = & $Exe bookmarks --in $src --name 99 2>&1
  Check 'find: no hit exits 3' ($LASTEXITCODE -eq 3) "exit=$LASTEXITCODE"
  $null = & $Exe bookmarks --in (Join-Path $WorkDir 'nope.pas') 2>&1
  Check 'missing path exits 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
  $null = & $Exe bookmarks 2>&1
  Check 'no --in exits 1' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"
  $o = & $Exe bookmarks --in $WorkDir 2>&1 | Out-String
  Check 'directory scan lists text form' ($o -match 'uBk\.pas:6\s+user\s+3') ($o.Trim())

  $before = [IO.File]::ReadAllText($src)
  $null = & $Exe bookmarks --in $src 2>&1
  Check 'read-only: file bytes unchanged' ([IO.File]::ReadAllText($src) -eq $before)
}
finally { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'run_bookmarks: FAILED'; exit 1 }
Write-Host 'run_bookmarks: OK'
