<#
  run_v152_FUSCOPE_usages_scope.ps1 -- 1.52 lane FUSCOPE (owner N3, 2026-11-17).

  Find Usages has FOUR scopes, the same words on every surface:
    symbol     -- the declaration the cursor / a qualified name is BOUND to, this project (DEFAULT)
    project    -- every object of that NAME in this project's index
    group      -- the name in every index of the project group (--group <x.groupproj>)
    everywhere -- the name in every index the manifest knows

  Fixture: project One has TAlpha.Run and TBeta.Run (two same-named methods in two units)
  and calls A.Run once, B.Run twice; project Two (in the group) has TGamma.Run; project
  Three (in the manifest, NOT in the group) has TDelta.Run. Each scope must return its own
  set. The manifest is a scratch file named by DRAGLINT_MANIFEST, so no real index is read.

  P0 is the positive control: `usages --name Run` (bare, no scope) still answers what it
  always did -- both of One's declarations -- so a broken fixture cannot pass the rest.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_fuscope-{0}" -f $PID)

function Put([string]$rel, [string]$text) {
  $p = Join-Path $scratch $rel
  [IO.Directory]::CreateDirectory((Split-Path $p)) | Out-Null
  [IO.File]::WriteAllText($p, ($text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
  return $p
}
function ClassUnit([string]$unit, [string]$cls) {
  return "unit $unit;`ninterface`ntype`n  $cls = class`n  public`n    procedure Run;`n  end;`nimplementation`nprocedure $cls.Run;`nbegin`nend;`nend.`n"
}
function Index([string]$proj, [string]$db) {
  $o = & $exePath index --project $proj --db $db 2>&1
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $db)) { Write-Host "FATAL: fixture $proj did not index: $($o | Select-Object -Last 2)" -ForegroundColor Red; exit 2 }
}
function Ask([string[]]$a) {
  $errFile = Join-Path $scratch 'stderr.txt'
  Push-Location $scratch
  $raw = (& $exePath usages @a --json 2>$errFile) -join "`n"
  $script:code = $LASTEXITCODE
  Pop-Location
  $script:err = [IO.File]::ReadAllText($errFile)
  $script:raw = $raw
  $script:j = $null
  $start = $raw.IndexOf('{')
  if ($start -ge 0) { try { $script:j = $raw.Substring($start) | ConvertFrom-Json } catch { $script:j = $null } }
}
function DeclQ() { if ($null -eq $j) { return '' }; return ((@($j.declarations) | ForEach-Object { $_.qname }) | Sort-Object) -join ',' }
function Calls() { if ($null -eq $j) { return -1 }; return @($j.calls).Count }

# ---- fixture -------------------------------------------------------------------
Put 'one\uAlpha.pas' (ClassUnit 'uAlpha' 'TAlpha') | Out-Null
Put 'one\uBeta.pas'  (ClassUnit 'uBeta'  'TBeta')  | Out-Null
$mainText = "unit uMain;`ninterface`nuses uAlpha, uBeta;`nprocedure Go;`nimplementation`nprocedure Go;`nvar`n  A: TAlpha;`n  B: TBeta;`nbegin`n  A := TAlpha.Create;`n  B := TBeta.Create;`n  A.Run;`n  B.Run;`n  B.Run;`nend;`nend.`n"
$uMain = Put 'one\uMain.pas' $mainText
$lines = $mainText -split "`n"
$lineA = [Array]::IndexOf($lines, '  A.Run;') + 1
$lineB = [Array]::IndexOf($lines, '  B.Run;') + 1
$colRun = 5   # 1-based column of 'Run' in '  A.Run;'
$pOne = Put 'one\AppOne.dpr' "program AppOne;`nuses uAlpha in 'uAlpha.pas', uBeta in 'uBeta.pas', uMain in 'uMain.pas';`nbegin`nend.`n"
Put 'two\uGamma.pas' (ClassUnit 'uGamma' 'TGamma') | Out-Null
$pTwo = Put 'two\AppTwo.dpr' "program AppTwo;`nuses uGamma in 'uGamma.pas';`nvar G: TGamma;`nbegin`n  G := TGamma.Create;`n  G.Run;`nend.`n"
Put 'three\uDelta.pas' (ClassUnit 'uDelta' 'TDelta') | Out-Null
$pThree = Put 'three\AppThree.dpr' "program AppThree;`nuses uDelta in 'uDelta.pas';`nbegin`nend.`n"
$dbOne   = Join-Path $scratch 'one\_D-RAG\AppOne.sqlite'
$dbTwo   = Join-Path $scratch 'two\_D-RAG\AppTwo.sqlite'
$dbThree = Join-Path $scratch 'three\_D-RAG\AppThree.sqlite'
Index $pOne $dbOne; Index $pTwo $dbTwo; Index $pThree $dbThree
$grp = Put 'grp\Both.groupproj' "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <ItemGroup>`n    <Projects Include=`"..\one\AppOne.dproj`">`n      <Dependencies/>`n    </Projects>`n    <Projects Include=`"..\two\AppTwo.dproj`">`n      <Dependencies/>`n    </Projects>`n  </ItemGroup>`n</Project>`n"
function Esc([string]$s) { $s -replace '\\', '\\' }
$manifest = Put 'manifest\drag-lint.json' ('{"settings":{"defaultPlatform":"Win64"},"indexes":{"outDir":"' + (Esc (Join-Path $scratch 'out')) + '","sections":[' +
  '{"name":"One","db":"' + (Esc $dbOne) + '","include":["' + (Esc $pOne) + '"]},' +
  '{"name":"Two","db":"' + (Esc $dbTwo) + '","include":["' + (Esc $pTwo) + '"]},' +
  '{"name":"Three","db":"' + (Esc $dbThree) + '","include":["' + (Esc $pThree) + '"]}]}}')
$env:DRAGLINT_MANIFEST = $manifest

# ---- P0 positive control: the pre-1.52 bare-name answer is unchanged --------------
Ask @('--name', 'Run', '--db', $dbOne)
Check 'P0 bare --name Run answers both of One''s declarations (unchanged)' (($code -eq 0) -and ((DeclQ) -eq 'uAlpha.TAlpha.Run,uBeta.TBeta.Run') -and ((Calls) -eq 3)) "exit=$code decls=$(DeclQ) calls=$(Calls) err=$err"
Check 'P1 bare name with no position reports the scope it answered: project' (($null -ne $j) -and ($j.scope -eq 'project')) "scope=$($j.scope) raw=$raw"

# ---- S: scope symbol (the default) -------------------------------------------------
Ask @('--in', $uMain, '--line', "$lineA", '--col', "$colRun", '--db', $dbOne)
Check 'S1 default at A.Run binds TAlpha.Run only' (($code -eq 0) -and ((DeclQ) -eq 'uAlpha.TAlpha.Run')) "exit=$code decls=$(DeclQ) err=$err"
Check 'S2 default at A.Run: one call, scope symbol' (((Calls) -eq 1) -and ($j.scope -eq 'symbol')) "calls=$(Calls) scope=$($j.scope)"
Ask @('--in', $uMain, '--line', "$lineB", '--col', "$colRun", '--db', $dbOne, '--scope', 'symbol')
Check 'S3 --scope symbol at B.Run binds TBeta.Run with its two calls' (((DeclQ) -eq 'uBeta.TBeta.Run') -and ((Calls) -eq 2)) "decls=$(DeclQ) calls=$(Calls) err=$err"
Ask @('--name', 'uAlpha.TAlpha.Run', '--db', $dbOne)
Check 'S4 a qualified --name is bound: scope symbol, TAlpha.Run only' (((DeclQ) -eq 'uAlpha.TAlpha.Run') -and ($j.scope -eq 'symbol') -and ((Calls) -eq 1)) "decls=$(DeclQ) scope=$($j.scope) calls=$(Calls)"

$uAlphaPath = Join-Path $scratch 'one\uAlpha.pas'
Ask @('--in', $uAlphaPath, '--line', '9', '--col', '18', '--db', $dbOne)
Check 'S5 on the implementation header of TAlpha.Run: bound to it, one call' (((DeclQ) -eq 'uAlpha.TAlpha.Run') -and ((Calls) -eq 1) -and ($j.scope -eq 'symbol')) "decls=$(DeclQ) calls=$(Calls) scope=$($j.scope) err=$err"

# ---- R: scope project ----------------------------------------------------------------
Ask @('--in', $uMain, '--line', "$lineA", '--col', "$colRun", '--db', $dbOne, '--scope', 'project')
Check 'R1 --scope project at A.Run: every Run of One (2 decls, 3 calls)' (((DeclQ) -eq 'uAlpha.TAlpha.Run,uBeta.TBeta.Run') -and ((Calls) -eq 3) -and ($j.scope -eq 'project')) "decls=$(DeclQ) calls=$(Calls) scope=$($j.scope) err=$err"

# ---- G: scope group --------------------------------------------------------------------
Ask @('--name', 'Run', '--db', $dbOne, '--scope', 'group', '--group', $grp)
Check 'G1 --scope group: One + Two, not Three' (((DeclQ) -eq 'uAlpha.TAlpha.Run,uBeta.TBeta.Run,uGamma.TGamma.Run') -and ($j.scope -eq 'group')) "decls=$(DeclQ) scope=$($j.scope) err=$err"
Check 'G2 --scope group lists the two databases it read' (@($j.databases).Count -eq 2) "databases=$($j.databases -join ';')"

# ---- E: scope everywhere -----------------------------------------------------------------
Ask @('--name', 'Run', '--db', $dbOne, '--scope', 'everywhere')
Check 'E1 --scope everywhere: One + Two + Three' (((DeclQ) -eq 'uAlpha.TAlpha.Run,uBeta.TBeta.Run,uDelta.TDelta.Run,uGamma.TGamma.Run') -and ($j.scope -eq 'everywhere')) "decls=$(DeclQ) scope=$($j.scope) err=$err"

# ---- X: a bad scope word is a usage error --------------------------------------------------
Ask @('--name', 'Run', '--db', $dbOne, '--scope', 'galaxy')
Check 'X1 unknown scope: exit 2, names the four words' (($code -eq 2) -and (($raw + $err) -match 'symbol\|project\|group\|everywhere')) "exit=$code out=$raw err=$err"

# ---- M: the MCP find_usages tool, same scopes ------------------------------------------------
function Invoke-Serve([string[]]$Requests, [string]$Tag) {
  $in  = Join-Path $scratch "$Tag.in.jsonl"
  $out = Join-Path $scratch "$Tag.out.jsonl"
  $all = @('{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}') + $Requests
  [IO.File]::WriteAllText($in, (($all -join "`n") + "`n"), [Text.Encoding]::ASCII)
  $p = Start-Process $exePath -ArgumentList 'serve', '--db', "`"$dbOne`"" -WorkingDirectory $scratch `
         -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError (Join-Path $scratch "$Tag.err.txt") -NoNewWindow -PassThru
  if (-not $p.WaitForExit(60000)) { $p.Kill() }
  $replies = @{}
  foreach ($line in (Get-Content $out -ErrorAction SilentlyContinue)) {
    try { $r = $line | ConvertFrom-Json } catch { continue }
    if ($null -ne $r.id) { $replies[[string]$r.id] = $r }
  }
  $replies
}
function Call([int]$Id, [hashtable]$Arguments) { (@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = @{ name = 'find_usages'; arguments = $Arguments } } | ConvertTo-Json -Compress -Depth 6) }
function Text($Reply) { if ($Reply -and $Reply.result -and $Reply.result.content.Count -gt 0) { [string]$Reply.result.content[0].text } else { '' } }
$m = Invoke-Serve @((Call 1 @{ file = $uMain; line = $lineA; col = $colRun }), (Call 2 @{ name = 'Run'; scope = 'everywhere' })) 'mcp'
$t1 = Text $m['1']; $t2 = Text $m['2']
Check 'M1 MCP find_usages at A.Run: scope symbol bound to TAlpha.Run, one call row' (($t1 -match 'scope symbol \(uAlpha\.TAlpha\.Run\)') -and (([regex]::Matches($t1, '(?m)^calls ')).Count -eq 1)) "text=$t1"
Check 'M2 MCP find_usages scope everywhere: Delta (third project) is listed' (($t2 -match 'scope everywhere') -and ($t2 -match 'uDelta\.TDelta\.Run')) "text=$t2"

[Environment]::SetEnvironmentVariable('DRAGLINT_MANIFEST', $null)
try { [IO.Directory]::Delete($scratch, $true) } catch { Write-Host "note: scratch left at $scratch" }
if ($script:fail) { Write-Host 'run_v152_FUSCOPE_usages_scope: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_FUSCOPE_usages_scope: PASS' -ForegroundColor Green
exit 0
