<#
  run_rename_precise.ps1 -- lane 144 item 3: rename proves every occurrence, and every write passes the compile gate.

  A rename that compiles can still bind differently, and dcc cannot see it. So each sound case is proved three ways: the
  plan's edits, an --apply through the gate, and the program's stdout byte-identical to the untouched build. Each unsound
  case must refuse by name, exit 2, sources byte-identical.

  POSITIVE CONTROLS: pc1 and pc2 write the capture and the shadowing by hand: both COMPILE and print something else, so the
  stdout proof can fail and the refusals are needed. pc3: the gate's break seam rolls a sound rewrite back. r9: with no
  library open the same rename as c1 refuses, so c1's "other" really comes from the library facts.
  RED on 1.43.0-alpha: no --plan, no gate, E5 partial renames. Needs RAD Studio; SKIPs (exit 0) without it. Works under %TEMP%.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-precise-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailCount++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx   = Join-Path $Repo 'tests\fixtures\refactor\rename'
$Ascii = [Text.Encoding]::ASCII
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$script:N = 0

function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function Build-Lab([string]$Root) {
  $bat = "$Root.bld.bat"
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$RsVars`"`r`ncd /D `"$Root`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal PrecRen.dproj`r`nexit /b %ERRORLEVEL%`r`n", $Ascii)
  $p = Start-Process cmd.exe -ArgumentList "/c `"$bat`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$Root.bld.log" -RedirectStandardError "$Root.bld.err"
  return ($p.ExitCode -eq 0)
}
function Stdout-Of([string]$Root) {
  $x = Get-ChildItem $Root -Recurse -Filter PrecRen.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $x) { return '<no exe>' }
  return (& $x.FullName 2>&1 | Out-String)
}
# A fresh copy, indexed as a project with no library: every library member is an unbound ref.
function New-Lab {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  Copy-Item "$Fx\*.pas", "$Fx\*.dpr", "$Fx\*.dproj" $root
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'PrecRen.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'PrecRen.dproj'); Db = $db; Use = (Join-Path $root 'RnUse.pas'); Types = (Join-Path $root 'RnTypes.pas') }
}
function Plan($P, [string]$Q, [string]$To, [string]$Lib = $script:Lib) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $P.Db --library-db $Lib --plan --json 2>$null | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  return @{ Exit = $c; Json = $j; Out = $o; Kinds = @($j.refusals | ForEach-Object { $_.kind }) }
}
function Apply($P, [string]$Q, [string]$To, [string[]]$Extra = @(), [string]$Lib = $script:Lib) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $P.Db --library-db $Lib --project $P.Dproj --build-timeout 600 --apply --no-backup @Extra 2>&1 | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
  return @{ Exit = $c; Out = $o }
}
function Sound($Name, [string]$Q, [string]$To, [scriptblock]$Text) {
  $p = New-Lab
  $pl = Plan $p $Q $To
  Check "$Name plan: every occurrence decided" ($pl.Exit -eq 0 -and $pl.Json -and @($pl.Json.refusals).Count -eq 0) ($pl.Out)
  $a = Apply $p $Q $To
  Check "$Name apply: through the gate, exit 0" ($a.Exit -eq 0 -and $a.Out -match 'compile gate') $a.Out
  Check "$Name stdout identical to the untouched build" ((Stdout-Of $p.Root) -ceq $script:Expected) (Stdout-Of $p.Root)
  & $Text $p
}
function Refused($Name, [string]$Q, [string]$To, [string]$Kind, [string]$Lib = $script:Lib) {
  $p = New-Lab
  $h = Get-SrcHash $p.Root
  $pl = Plan $p $Q $To $Lib
  Check "$Name plan names [$Kind]" ($pl.Exit -eq 0 -and $pl.Kinds -contains $Kind) ($pl.Out)
  $a = Apply $p $Q $To @() $Lib
  Check "$Name apply exit 2 naming [$Kind]" ($a.Exit -eq 2 -and $a.Out -match [regex]::Escape("refused [$Kind]")) $a.Out
  Check "$Name sources byte-identical" ((Get-SrcHash $p.Root) -eq $h)
}
function Text-Of([string]$Path) { return [IO.File]::ReadAllText($Path, $Ascii) }
function Line-Of([string]$Path, [string]$Pattern) {
  $i = 0
  foreach ($l in ((Text-Of $Path) -split "`r`n")) { $i++; if ($l -match $Pattern) { return $i } }
  return 0
}
function Local-Rename($P, [int]$Line, [string]$To, [string[]]$Extra) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe rename --kind param --in $P.Use --line $Line --col 3 --to $To --project $P.Dproj --build-timeout 600 --apply --no-backup @Extra 2>&1 | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
  return @{ Exit = $c; Out = $o }
}

# The miniature library and the expected stdout.
$libDir = Join-Path $WorkDir 'lib'; New-Item -ItemType Directory -Force $libDir | Out-Null
Copy-Item "$Fx\libstub\LibStub.pas" $libDir
$script:Lib = Join-Path $WorkDir 'lib.sqlite'
Push-Location $WorkDir; try { $null | & $Exe index $libDir --db $script:Lib --library-db none *> "$script:Lib.log" } finally { Pop-Location }
$base = New-Lab
if (-not (Build-Lab $base.Root)) { Write-Host "FATAL: the untouched fixture does not build ($($base.Root).bld.log)" -ForegroundColor Red; exit 2 }
$script:Expected = Stdout-Of $base.Root
Check 'fixture runs and prints' ($script:Expected -match 'TKid\.Run' -and $script:Expected -match '300')

Write-Host 'ref_receivers: a whole pass and an incremental one agree' -ForegroundColor Cyan
function Rcv-Count($P) { $j = (& $Exe sql --db $P.Db --query 'select count(*) from ref_receivers' --json 2>$null | Out-String | ConvertFrom-Json); return [int]$j.rows[0][0] }
$rp = New-Lab
$before = Rcv-Count $rp
Check 'rcv the join writes rows' ($before -gt 0) "rows=$before"
[IO.File]::AppendAllText($rp.Use, "`r`n", $Ascii)
Push-Location $WorkDir; try { $null | & $Exe index --project $rp.Dproj --db $rp.Db --library-db none *> "$($rp.Db).log2" } finally { Pop-Location }
Check 'rcv an incremental re-emit of one file keeps the count' ((Rcv-Count $rp) -eq $before) "before=$before after=$(Rcv-Count $rp)"
Write-Host 'Same-named members: only the target edited, per token on one line' -ForegroundColor Cyan
Sound 'c1' 'RnTypes.TTwoA.Count' 'Tally' {
  param($p)
  $t = Text-Of $p.Use
  Check 'c1 one line: A and K edited, B and the bare global not' ($t -match "Writeln\(A\.Tally, ' ', B\.Count, ' ', K\.Tally, ' ', Count\);") $t
  Check 'c1 chain: A.Item edited, B.Other not' ($t -match 'A\.Item\.Tally \+ B\.Other\.Count') $t
  Check 'c1 library receivers untouched' ($t -match "Writeln\(L\.Count, ' ', IL\.Count\);") $t
  Check 'c1 bare inherited call in TKid edited' ((Text-Of $p.Types) -match 'Result:= Tally \+ Tally;') (Text-Of $p.Types)
  Check 'c1 local Count untouched' ($t -match 'Count:= 5;') $t
}
$c1p = New-Lab
$c1 = Plan $c1p 'RnTypes.TTwoA.Count' 'Tally'
Check 'c1 typed: L.Count and IL.Count decided by the receiver''s chain' ($c1.Json.typed -ge 2) $c1.Out

Write-Host 'With body: the member and the outer local of one name' -ForegroundColor Cyan
Sound 'c2' 'RnTypes.TRecX.Count' 'Tally' {
  param($p)
  $t = Text-Of $p.Use
  Check 'c2 the with on R edited' ($t -match 'with R do Total:= Tally \+ Size;') $t
  Check 'c2 the with on N (no such member) is the local: not edited' ($t -match 'with N do Total:= Count \+ Size;') $t
  Check 'c2 R.Count edited, local untouched' ($t -match 'R\.Tally:= 7;' -and $t -match 'Count:= 5;') $t
}

Write-Host 'Local rename: occurrences under a with are decided, not skipped' -ForegroundColor Cyan
$p = New-Lab
$a = Local-Rename $p (Line-Of $p.Use '^  Count: Integer;') 'Tally' @('--db', $p.Db)
$t = Text-Of $p.Use
Check 'c3 apply exit 0' ($a.Exit -eq 0) $a.Out
Check 'c3 with R: the member stays; with N: the local follows' ($t -match 'with R do Total:= Count \+ Size;' -and $t -match 'with N do Total:= Tally \+ Size;' -and $t -match 'Tally:= 5;') $t
Check 'c3 stdout identical' ((Stdout-Of $p.Root) -ceq $script:Expected) (Stdout-Of $p.Root)
$p = New-Lab; $h = Get-SrcHash $p.Root
$a = Local-Rename $p (Line-Of $p.Use '^  Count: Integer;') 'Tally' @()
Check 'c3b no --db: [with-needs-index], exit 2, bytes same' ($a.Exit -eq 2 -and $a.Out -match 'refused \[with-needs-index\]' -and (Get-SrcHash $p.Root) -eq $h) $a.Out
$p = New-Lab; $h = Get-SrcHash $p.Root
$a = Local-Rename $p (Line-Of $p.Use '^  Ghost: Integer;') 'Helper' @('--db', $p.Db)
Check 'c3c new local name already used: [capture-local], exit 2, bytes same' ($a.Exit -eq 2 -and $a.Out -match 'refused \[capture-local\]' -and (Get-SrcHash $p.Root) -eq $h) $a.Out

Write-Host 'Groups: all or nothing' -ForegroundColor Cyan
Sound 'c4' 'RnTypes.TTwoA.Run' 'Exec' {
  param($p)
  $x = Text-Of $p.Types
  Check 'c4 override and inherited follow; TTwoB.Run does not' ($x -match 'procedure TKid\.Exec;' -and $x -match 'inherited Exec;' -and $x -match 'procedure TTwoB\.Run;') $x
  Check 'c4 call sites' ((Text-Of $p.Use) -match 'A\.Exec; B\.Run; K\.Exec;') (Text-Of $p.Use)
}
Sound 'c5' 'RnTypes.IDoer.Act' 'Perform' {
  param($p)
  Check 'c5 the implementer follows' ((Text-Of $p.Types) -match 'function TDoer\.Perform: Integer;') (Text-Of $p.Types)
}
Sound 'c6' 'RnTypes.TOv.Go' 'Walk' {
  param($p)
  Check 'c6 both overloads' (([regex]::Matches((Text-Of $p.Types), 'function TOv\.Walk\(')).Count -eq 2) (Text-Of $p.Types)
}
Sound 'c7' 'RnTypes.TTwoA.FSize' 'FBulk' {
  param($p)
  Check 'c7 property read / write follow' ((Text-Of $p.Types) -match 'read FBulk write FBulk') (Text-Of $p.Types)
}
Refused 'r1' 'RnTypes.TKid.AfterConstruction' 'Born' 'override-of-library'

Write-Host 'What cannot be proved refuses' -ForegroundColor Cyan
# r2 was refused [receiver-untyped] until wave 146: `Xs[0].Kind` on a TList<TTwoB> now binds (run_rename_element_type.ps1).
Sound 'r2' 'RnTypes.TTwoB.Kind' 'Sort' { param($p) Check 'r2 the element read is rewritten' ((Text-Of $p.Use).Contains('Xs[0].Sort')) }
Refused 'r3' 'RnTypes.TTwoB.Capacity' 'Room' 'receiver-untyped'
Refused 'r4' 'RnTypes.TTwoB.Zeta' 'Theta' 'no-ref-occurrence'
Refused 'r5' 'RnTypes.TTwoA.Count' 'Helper' 'capture-bare'
Refused 'r6' 'RnTypes.Compute' 'Tally' 'shadowed-at-site'
Refused 'r7' 'RnTypes.TKid.Twice' 'Count' 'new-name-collides'
Refused 'r8' 'RnTypes.TTwoB.Run' 'Free' 'new-name-in-library'
Refused 'r9' 'RnTypes.TTwoA.Count' 'Tally' 'no-library' 'none'

Write-Host 'The gate' -ForegroundColor Cyan
$p = New-Lab; $h = Get-SrcHash $p.Root
Push-Location $WorkDir
try { $o = ($null | & $Exe rename --kind symbol --name RnTypes.TTwoA.Count --to Tally --db $p.Db --library-db $script:Lib --apply --no-backup 2>&1 | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
Check 'g1 no --project: [no-project], exit 2, bytes same' ($c -eq 2 -and $o -match 'refused \[no-project\]' -and (Get-SrcHash $p.Root) -eq $h) $o
$dr = Join-Path $p.Root '_D-RAG'; New-Item -ItemType Directory -Force $dr | Out-Null
$sibDb = Join-Path $dr 'PrecRen.sqlite'
Push-Location $WorkDir
try { $null | & $Exe index --project $p.Dproj --db $sibDb --library-db none *> "$sibDb.log"; $o = ($null | & $Exe rename --qname RnTypes.TTwoA.Count --to Tally --db $sibDb --library-db $script:Lib --no-backup 2>&1 | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
Check 'g4 the IDE''s form (--qname --db, no --project): the DB''s own project, through the gate' ($c -eq 0 -and $o -match 'compile gate' -and (Stdout-Of $p.Root) -ceq $script:Expected) $o
$p = New-Lab; $h = Get-SrcHash $p.Root
$a = Apply $p 'RnTypes.TTwoA.Count' 'Tally' @('--no-compile')
Check 'g2 --no-compile with --apply: [no-compile], exit 2, bytes same' ($a.Exit -eq 2 -and $a.Out -match 'refused \[no-compile\]' -and (Get-SrcHash $p.Root) -eq $h) $a.Out
$p = New-Lab; $h = Get-SrcHash $p.Root
$env:DRAGLINT_GATE_TEST_BREAK = '1'
try { $a = Apply $p 'RnTypes.TTwoA.Count' 'Tally' } finally { $env:DRAGLINT_GATE_TEST_BREAK = $null }
Check 'pc3 a build that fails after the write rolls back, exit 1, bytes same' ($a.Exit -eq 1 -and $a.Out -match '\[compile-error\]' -and (Get-SrcHash $p.Root) -eq $h) $a.Out
$p = New-Lab
# indexed clean, broken after: the census sees the same tokens; the baseline build must stop it.
[IO.File]::WriteAllText($p.Use, ((Text-Of $p.Use) -replace 'Result:= 300;', 'Result:= 300 +;'), $Ascii)
$h = Get-SrcHash $p.Root
$a = Apply $p 'RnTypes.TTwoA.Count' 'Tally'
Check 'g3 a project that does not build before: [dirty-baseline], exit 1, bytes same' ($a.Exit -eq 1 -and $a.Out -match '\[dirty-baseline\]' -and (Get-SrcHash $p.Root) -eq $h) $a.Out

Write-Host 'Positive controls: dcc does not catch these' -ForegroundColor Cyan
$p = New-Lab
$x = (Text-Of $p.Types) -replace '(TTwoA = class[\s\S]*?)function Count: Integer;', '$1function Helper: Integer;' -replace 'function TTwoA\.Count', 'function TTwoA.Helper' -replace 'Result:= Count \+ Count;', 'Result:= Helper + Helper;'
[IO.File]::WriteAllText($p.Types, $x, $Ascii)
$u = (Text-Of $p.Use) -replace "A\.Count, ' ', B\.Count, ' ', K\.Count", "A.Helper, ' ', B.Count, ' ', K.Helper" -replace 'A\.Item\.Count', 'A.Item.Helper'
[IO.File]::WriteAllText($p.Use, $u, $Ascii)
$b = Build-Lab $p.Root
Check 'pc1 the capture by hand COMPILES and prints something else' ($b -and (Stdout-Of $p.Root) -cne $script:Expected) "built=$b"
$p = New-Lab
$x = (Text-Of $p.Types) -replace 'function Compute: Integer;', 'function Tally: Integer;'
[IO.File]::WriteAllText($p.Types, $x, $Ascii)
[IO.File]::WriteAllText($p.Use, ((Text-Of $p.Use) -replace 'Writeln\(Compute, ', 'Writeln(Tally, '), $Ascii)
$b = Build-Lab $p.Root
Check 'pc2 the shadowing by hand COMPILES and prints something else' ($b -and (Stdout-Of $p.Root) -cne $script:Expected) "built=$b"

if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: $WorkDir not deleted" } }
Write-Host ("run_rename_precise: {0} pass, {1} fail" -f $script:Passed, $script:FailCount)
if ($script:Failed) { exit 1 }
exit 0
