<#
  run_grammar_dlls_stamp_guard.ps1 -- 151 GD: schema_meta grammar_dlls + `info` grammar_dlls_differ.
  2026-11-10: the 1.49 re-parse ran with the July DFM grammar (22016 B) under a HEAD that recorded
  v1.2.0, and `info` said current. Two private engine copies that differ ONLY in tree-sitter-dfm.dll's bytes:
    G1 index with A -> stored == loaded, differ false
    G2 POSITIVE CONTROL: info from B on A's index -> differ true, text names DIFFERS
    G3 incremental index with B does NOT relabel (stderr note; stamp still A's)
    G4 index --rebuild with B -> stamp = B, differ false from B
    G5 verdict unchanged by a difference (detection, not invalidation)
  pwsh 7.
#>
param([string]$Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'))
$ErrorActionPreference = 'Stop'
$fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') { if ($ok) { Write-Host "PASS $n" } else { Write-Host "FAIL $n $d"; $script:fail++ } }
$Exe = (Resolve-Path $Exe).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('gdl-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
  $src = Split-Path $Exe
  foreach ($e in 'A', 'B') {
    $d = Join-Path $tmp $e; [IO.Directory]::CreateDirectory($d) | Out-Null
    Copy-Item $Exe $d
    Get-ChildItem $src -Filter '*.dll' | Copy-Item -Destination $d
    if (Test-Path (Join-Path $src 'rules')) { Copy-Item (Join-Path $src 'rules') (Join-Path $d 'rules') -Recurse }
  }
  # B's dfm DLL = A's plus 16 trailing bytes: still loads (PE overlay), other content hash.
  $bd = Join-Path $tmp 'B\tree-sitter-dfm.dll'; $fs = [IO.File]::Open($bd, 'Append'); $fs.Write([byte[]](1..16), 0, 16); $fs.Close()
  $A = Join-Path $tmp 'A\drag-lint.exe'; $B = Join-Path $tmp 'B\drag-lint.exe'  # exe-freshness: absent -- per-run copies under $tmp, created above
  $fx = Join-Path $tmp 'fx'; [IO.Directory]::CreateDirectory($fx) | Out-Null
  [IO.File]::WriteAllText("$fx\U.pas", "unit U;`r`ninterface`r`nprocedure P;`r`nimplementation`r`nprocedure P;`r`nbegin`r`nend;`r`nend.`r`n")
  [IO.File]::WriteAllText("$fx\U.dfm", "object F: TForm`r`n  Caption = 'x'`r`nend`r`n")
  $db = Join-Path $tmp 'fx.sqlite'
  function Info($exe) { (& $exe info --json --db $db 2>$null | Out-String | ConvertFrom-Json).indexes[0] }

  & $A index $fx --db $db *> $null
  $ia = Info $A
  Check 'G1 stamp recorded and equals the loaded DLLs' ((-not [string]::IsNullOrEmpty($ia.grammar_dlls_stored)) -and ($ia.grammar_dlls_stored -eq $ia.grammar_dlls_loaded) -and (-not $ia.grammar_dlls_differ)) ($ia | ConvertTo-Json -Compress)
  Check 'G1 stamp names all three DLLs' ($ia.grammar_dlls_stored -match 'tree-sitter\.dll=\d+:[0-9a-f]{16};tree-sitter-delphi13\.dll=\d+:[0-9a-f]{16};tree-sitter-dfm\.dll=\d+:[0-9a-f]{16}$') $ia.grammar_dlls_stored

  $ib = Info $B
  Check 'G2 POSITIVE CONTROL: other dfm DLL -> differ true' ($ib.grammar_dlls_differ -eq $true) ($ib | ConvertTo-Json -Compress)
  $txt = & $B info --db $db 2>$null | Out-String
  Check 'G2 text names DIFFERS + rebuild remedy' (($txt -match 'grammar: DIFFERS') -and ($txt -match 'index --rebuild')) $txt
  Check 'G5 verdict not changed by the difference' ($ib.verdict -eq $ia.verdict) "$($ia.verdict) vs $($ib.verdict)"

  [IO.File]::AppendAllText("$fx\U.pas", "`r`n")
  $err = & $B index $fx --db $db 2>&1 | Out-String
  Check 'G3 incremental run with B notes the difference' ($err -match 'other tree-sitter DLLs') $err
  Check 'G3 incremental run does not relabel (stamp still A''s)' ((Info $A).grammar_dlls_differ -eq $false -and (Info $B).grammar_dlls_differ -eq $true)

  & $B index $fx --db $db --rebuild *> $null
  Check 'G4 --rebuild with B stamps B' ((Info $B).grammar_dlls_differ -eq $false -and (Info $A).grammar_dlls_differ -eq $true)
} finally {
  try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Host "note: scratch left at $tmp" }
}
if ($fail) { exit 1 }
Write-Host 'ALL PASS'
