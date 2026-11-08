<#
  run_bookmarks_strip_restore.ps1 -- E-BOOKMARKS phase 2 (wave 147 lane G2): the user-invoked
  `bookmarks-strip` / `bookmarks-restore` verbs over `// dl:bk` comment anchors.

  The guard that decides whether it ships (INBOX-bookmarks-as-comment-anchors.md):
    strip then restore MUST return every file BYTE-IDENTICAL to its original.
  Fixtures: a CRLF unit with a trailing anchor, an own-line anchor, a tagged anchor, a tag in a
  string literal (kept), a byte above 127 and an own-line anchor on a LAST line with no line
  break; a lone-LF unit in the same folder.
  Positive controls: strip must CHANGE the bytes (a do-nothing verb fails 'strip removed the
  anchors'); the relocation case must re-place by anchor text (a byte-copy of the old file fails
  it); an unplaceable anchor must leave the file untouched with exit 4.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-bkstrip-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
function Bytes($p) { [IO.File]::ReadAllBytes($p) }
function Same($a, $b) { [Convert]::ToBase64String($a) -eq [Convert]::ToBase64String($b) }
function Latin1 { [Text.Encoding]::GetEncoding(28591) }
function Put($p, $text) { [IO.File]::WriteAllBytes($p, (Latin1).GetBytes($text)) }
function Get($p) { (Latin1).GetString([IO.File]::ReadAllBytes($p)) }
function Json($o) { try { $o | Out-String | ConvertFrom-Json } catch { $null } }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$Exe = (Resolve-Path $Exe).Path
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null
try {
  $e9 = [string][char]0xE9
  $crlf = "unit uA;`r`n" +                                   # 1
          "interface`r`n" +                                  # 2
          "implementation`r`n" +                             # 3
          "procedure A;`r`n" +                               # 4
          "begin`r`n" +                                      # 5
          "  Foo;   // dl:bk3`r`n" +                         # 6  trailing user
          "  // dl:bk:A7K3QX -- check the lock order`r`n" +  # 7  own-line tagged
          "  Bar('caf$e9');`r`n" +                           # 8  byte > 127
          "  S := '// dl:bk4'; // dl:bk12@7f3a`r`n" +        # 9  string kept, trailing hash
          "end;`r`n" +                                       # 10
          "end.`r`n" +                                       # 11
          "// dl:bk9"                                        # 12 own-line, no line break
  $lf   = "unit uB;`nimplementation`n  X; // dl:bk1 free text`nend.`n"
  $dir = Join-Path $WorkDir 'src'
  [IO.Directory]::CreateDirectory($dir) | Out-Null
  $a = Join-Path $dir 'uA.pas'; $b = Join-Path $dir 'uB.pas'
  Put $a $crlf; Put $b $lf
  $origA = Bytes $a; $origB = Bytes $b
  $side = Join-Path $WorkDir 'bk.json'

  # 1. dry run writes nothing
  $j = Json (& $Exe bookmarks-strip --in $dir --output $side --json 2>&1); $code = $LASTEXITCODE
  Check 'dry run: exit 0' ($code -eq 0) "exit=$code"
  Check 'dry run: count 5 in 2 files, apply false' ($j -and $j.count -eq 5 -and $j.files -eq 2 -and $j.apply -eq $false) ("raw=" + ($j | ConvertTo-Json -Compress -Depth 4))
  Check 'dry run: no sidecar, sources unchanged' (-not (Test-Path $side) -and (Same (Bytes $a) $origA) -and (Same (Bytes $b) $origB))
  if ($j) {
    $r = @($j.bookmarks | ? { $_.file -like '*uA.pas' })
    Check 'dry run: modes trailing,line,trailing,line' ((($r | % { $_.mode }) -join ',') -eq 'trailing,line,trailing,line') ((($r | % { "$($_.line):$($_.mode)" }) -join ','))
  }

  # 2. strip --apply removes the anchors (positive control: the bytes must change)
  $j = Json (& $Exe bookmarks-strip --in $dir --output $side --apply --json 2>&1); $code = $LASTEXITCODE
  Check 'strip: exit 0, sidecar written' ($code -eq 0 -and (Test-Path $side)) "exit=$code"
  $sa = Get $a
  Check 'strip removed the anchors (only the string literal tag is left)' (-not (Same (Bytes $a) $origA) -and ([regex]::Matches($sa, 'dl:bk')).Count -eq 1) $sa
  Check 'strip: trailing anchor takes its blanks, own-line takes its line' ($sa -eq ("unit uA;`r`ninterface`r`nimplementation`r`nprocedure A;`r`nbegin`r`n  Foo;`r`n  Bar('caf$e9');`r`n  S := '// dl:bk4';`r`nend;`r`nend.`r`n"))
  Check 'strip: lone-LF unit keeps LF' ((Get $b) -eq "unit uB;`nimplementation`n  X;`nend.`n")

  # 3. an existing sidecar is never overwritten
  $null = & $Exe bookmarks-strip --in $dir --output $side --apply 2>&1
  Check 'strip: refuses an existing sidecar (exit 1)' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"
  $null = & $Exe bookmarks-strip --in $dir --apply 2>&1
  Check 'strip: --apply without --output is usage (exit 1)' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"

  # 4. restore dry run writes nothing; restore --apply is byte-identical
  $stripped = Bytes $a
  $null = & $Exe bookmarks-restore --from $side 2>&1
  Check 'restore dry run: exit 0, writes nothing' ($LASTEXITCODE -eq 0 -and (Same (Bytes $a) $stripped)) "exit=$LASTEXITCODE"
  $j = Json (& $Exe bookmarks-restore --from $side --apply --json 2>&1); $code = $LASTEXITCODE
  Check 'restore: exit 0, restored 5' ($code -eq 0 -and $j -and $j.restored -eq 5 -and $j.unplaced -eq 0) ("exit=$code raw=" + ($j | ConvertTo-Json -Compress -Depth 4))
  Check 'ROUND TRIP: CRLF unit byte-identical' (Same (Bytes $a) $origA)
  Check 'ROUND TRIP: LF unit byte-identical' (Same (Bytes $b) $origB)
  $j = Json (& $Exe bookmarks-restore --from $side --apply --json 2>&1)
  Check 'restore again: already 5, bytes unchanged' ($LASTEXITCODE -eq 0 -and $j.already -eq 5 -and (Same (Bytes $a) $origA)) "exit=$LASTEXITCODE"

  # 5. relocation: the file was edited after the strip (2 lines added at the top)
  [IO.File]::Delete($side)
  $null = & $Exe bookmarks-strip --in $a --output $side --apply 2>&1
  Put $a ("// added 1`r`n// added 2`r`n" + (Get $a))
  $j = Json (& $Exe bookmarks-restore --from $side --apply --json 2>&1); $code = $LASTEXITCODE
  Check 'relocate: exit 0, anchors re-placed by their lines' ($code -eq 0 -and (Get $a) -eq ("// added 1`r`n// added 2`r`n" + $crlf)) "exit=$code"
  if ($j) { Check 'relocate: reported lines are the new ones (8,9,11,14)' ((($j.bookmarks | % { $_.line }) -join ',') -eq '8,9,11,14') ((($j.bookmarks | % { $_.line }) -join ',')) }

  # 6. unplaceable: the anchor line is gone -> the file is left untouched, exit 4
  Put $a $crlf
  [IO.File]::Delete($side)
  $null = & $Exe bookmarks-strip --in $a --output $side --apply 2>&1
  $edited = (Get $a).Replace("  Foo;`r`n", '')
  Put $a $edited
  $j = Json (& $Exe bookmarks-restore --from $side --apply --json 2>&1); $code = $LASTEXITCODE
  Check 'unplaced: exit 4, file untouched' ($code -eq 4 -and (Get $a) -eq $edited) "exit=$code"
  if ($j) { Check 'unplaced: 1 unplaced, the rest held' ($j.unplaced -eq 1 -and @($j.bookmarks | ? { $_.status -eq 'held' }).Count -eq 3) ("raw=" + ($j | ConvertTo-Json -Compress -Depth 4)) }

  # 7. --name strips one code only; no hit exits 3; missing path 2; missing sidecar 2
  Put $a $crlf
  [IO.File]::Delete($side)
  $j = Json (& $Exe bookmarks-strip --in $a --name a7k3qx --output $side --apply --json 2>&1)
  Check '--name: only that anchor' ($LASTEXITCODE -eq 0 -and $j.count -eq 1 -and ([regex]::Matches((Get $a), 'dl:bk')).Count -eq 4) "exit=$LASTEXITCODE"
  $null = & $Exe bookmarks-strip --in $a --name 77 2>&1
  Check 'no hit exits 3' ($LASTEXITCODE -eq 3) "exit=$LASTEXITCODE"
  $null = & $Exe bookmarks-strip --in (Join-Path $WorkDir 'nope.pas') 2>&1
  Check 'missing path exits 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
  $null = & $Exe bookmarks-restore --from (Join-Path $WorkDir 'nope.json') 2>&1
  Check 'missing sidecar exits 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
  $null = & $Exe bookmarks-restore 2>&1
  Check 'restore without --from exits 1' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"
}
finally { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'run_bookmarks_strip_restore: FAILED'; exit 1 }
Write-Host 'run_bookmarks_strip_restore: OK'
