<#
  run_impact_all_projects.ps1 -- `impact --all-projects`: the blast radius over every
  manifest database, implementors included, with a row for each section that could
  not answer, so the answer is never silently short.

  Engine: DRagLint.Query.CrossImpact, wired into DoImpact (DRagLint.CLI.pas).

  FIXTURE (under $env:TEMP\draglint-xi-<guid>; an engine COPY with its own
  drag-lint.json, so the real manifest and the real DBs are never read):
    shared\uShared.pas  IShared.Ping + UseShared (calls Ping)
    A, B                compile uShared; TAImpl / TBImpl implement IShared and call it
    C                   the same shape, its DB never built: NOT INDEXED
    D                   no uShared; a local Ping of its own: by-name refs NOT counted
    BAD                 a DB file full of junk: UNREADABLE
    lib\uLibIntf.pas    ILibThing.Thing + LibCaller, library section only. Its own
                        caller must NOT count (the library answers declarations);
                        A's TLibImpl is found by the interface name.

  Positive controls: `complete` is proven both ways (false with the bad rows, true
  once they are repaired), and the old engine fails this script at the first check.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param([string]$EngineDir = "$PSScriptRoot\..\..\src\cli\Win64\Debug")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
function WriteAscii([string]$Path, [string[]]$Lines) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}

Write-Host '== impact --all-projects: every manifest DB, never silently short ==' -ForegroundColor Cyan
$EngineDir = (Resolve-Path $EngineDir).Path
$work = Join-Path $env:TEMP ('draglint-xi-' + [Guid]::NewGuid().ToString('N'))
$eng  = Join-Path $work 'eng'
New-Item -ItemType Directory -Force $eng | Out-Null
foreach ($f in 'drag-lint.exe', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'tree-sitter-dfm.dll', 'sqlite3.dll', 'casts.castlib') {
  if (Test-Path "$EngineDir\$f") { Copy-Item "$EngineDir\$f" "$eng\$f" }
}
$rulesSrc = if (Test-Path "$EngineDir\rules") { "$EngineDir\rules" } else { Join-Path $PSScriptRoot '..\..\rules' }
Copy-Item $rulesSrc "$eng\rules" -Recurse
$Exe = Join-Path $eng 'drag-lint.exe'

function Run([string[]]$CmdArgs) {
  Push-Location $work
  try {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $Exe @CmdArgs 2>$null | Out-String
    $script:LastExit = $LASTEXITCODE
    $ErrorActionPreference = $old
    $out
  } finally { Pop-Location }
}
function Json([string[]]$CmdArgs) {
  $raw = Run ($CmdArgs + @('--format', 'json'))
  try { $raw | ConvertFrom-Json } catch { $script:LastRaw = $raw; $null }
}
function Sec($Doc, [string]$Name) { if ($Doc) { @($Doc.sections | Where-Object { $_.name -eq $Name })[0] } else { $null } }
function ImplNames($Row) { if ($Row -and $Row.implementors) { @($Row.implementors | ForEach-Object { $_.qname }) -join ',' } else { '' } }
function Callers1($Row) { if ($Row -and $Row.levels -and @($Row.levels).Count -gt 0) { [int]@($Row.levels)[0].callers } else { 0 } }

$j = $work.Replace('\', '\\')
WriteAscii "$work\shared\uShared.pas" @('unit uShared;', 'interface', 'type',
  "  IShared = interface ['{11111111-1111-1111-1111-111111111111}']", '    procedure Ping;', '  end;',
  'procedure UseShared(const pS: IShared);', 'implementation',
  'procedure UseShared(const pS: IShared);', 'begin', '  pS.Ping;', 'end;', 'end.')
foreach ($p in 'A', 'B', 'C') {
  $uses = if ($p -eq 'A') { 'uShared, uLibIntf' } else { 'uShared' }
  $lib  = if ($p -eq 'A') { @('  TLibImpl = class(TInterfacedObject, ILibThing)', '  public', '    procedure Thing;', '  end;') } else { @() }
  $libB = if ($p -eq 'A') { @('procedure TLibImpl.Thing;', 'begin', 'end;', 'procedure AThing(const pT: ILibThing);', 'begin', '  pT.Thing;', 'end;') } else { @() }
  WriteAscii "$work\$p\u$p.pas" (@("unit u$p;", 'interface', "uses $uses;", 'type',
    "  T${p}Impl = class(TInterfacedObject, IShared)", '  public', '    procedure Ping;', '  end;') + $lib +
    @("procedure Call$p;", 'implementation', "procedure T${p}Impl.Ping;", 'begin', 'end;') + $libB +
    @("procedure Call$p;", 'var', '  S: IShared;', 'begin', "  S:= T${p}Impl.Create;", '  S.Ping;', '  UseShared(S);', 'end;', 'end.'))
  WriteAscii "$work\$p\$p.dpr" @("program $p;", 'uses', "  uShared in '..\shared\uShared.pas',", "  u$p in 'u$p.pas';", 'begin', "  Call$p;", 'end.')
}
WriteAscii "$work\D\uD.pas" @('unit uD;', 'interface', 'procedure Ping;', 'procedure DoD;', 'implementation',
  'procedure Ping;', 'begin', 'end;', 'procedure DoD;', 'begin', '  Ping;', 'end;', 'end.')
WriteAscii "$work\D\D.dpr" @('program D;', 'uses', "  uD in 'uD.pas';", 'begin', '  DoD;', 'end.')
WriteAscii "$work\lib\uLibIntf.pas" @('unit uLibIntf;', 'interface', 'type',
  "  ILibThing = interface ['{22222222-2222-2222-2222-222222222222}']", '    procedure Thing;', '  end;',
  'procedure LibCaller(const pT: ILibThing);', 'implementation',
  'procedure LibCaller(const pT: ILibThing);', 'begin', '  pT.Thing;', 'end;', 'end.')

function Manifest([string[]]$Names) {
  $secs = @()
  foreach ($n in $Names) {
    if ($n -eq 'LIB') { $secs += "  { `"name`": `"LIB`", `"source`": `"registry-libraries`", `"platforms`": [`"Win64`"], `"include`": [`"$j\\lib`"], `"db`": `"$j\\LIB.sqlite`" }" }
    elseif ($n -eq 'BAD') { $secs += "  { `"name`": `"BAD`", `"include`": [`"$j\\D\\D.dpr`"], `"db`": `"$j\\BAD.sqlite`" }" }
    else { $secs += "  { `"name`": `"$n`", `"include`": [`"$j\\$n\\$n.dpr`"], `"db`": `"$j\\$n.sqlite`" }" }
  }
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [', ($secs -join ",`r`n"), ']}}')
}

try {
  Manifest @('A', 'B', 'C', 'D', 'BAD', 'LIB')
  foreach ($p in 'A', 'B', 'D') { $null = Run @('index', '--project', "$work\$p\$p.dpr", '--db', "$work\$p.sqlite") }
  $null = Run @('index', "$work\lib", '--db', "$work\LIB.sqlite")
  [IO.File]::WriteAllBytes("$work\BAD.sqlite", [byte[]](,0x5A * 4096))

  # ------------------------------------------------------------- interface method, declared in the projects
  $doc = Json @('impact', '--qname', 'uShared.IShared.Ping', '--all-projects')
  Check 'J1 --all-projects answers JSON with sections[]' ($null -ne $doc -and $doc.sections) ("exit=$script:LastExit raw=" + ([string]$script:LastRaw).Substring(0, [Math]::Min(120, ([string]$script:LastRaw).Length)))
  Check 'J2 exit 0: the target was found' ($script:LastExit -eq 0) "exit=$script:LastExit"
  $a = Sec $doc 'A'; $b = Sec $doc 'B'; $c = Sec $doc 'C'; $d = Sec $doc 'D'; $bad = Sec $doc 'BAD'; $l = Sec $doc 'LIB'
  Check 'A1 project A counts callers' ((Callers1 $a) -ge 1) ("callers=" + (Callers1 $a))
  Check 'A2 project B counts callers (a second DB was really asked)' ((Callers1 $b) -ge 1) ("callers=" + (Callers1 $b))
  Check 'A3 A lists its implementor' ((ImplNames $a) -match 'uA\.TAImpl\.Ping') (ImplNames $a)
  Check 'A4 B lists its implementor' ((ImplNames $b) -match 'uB\.TBImpl\.Ping') (ImplNames $b)
  Check 'A5 B does not list A''s implementor (each DB answers for itself)' ((ImplNames $b) -notmatch 'TAImpl') (ImplNames $b)
  Check 'C1 C, never built, is a not-indexed row' ($c -and $c.state -eq 'not-indexed') ([string]$c.state)
  Check 'C2 ... naming its database and the command that indexes it' ($c -and ($c.db -match 'C\.sqlite') -and ($c.repair -match 'index --all --only C\b')) ([string]$c.repair)
  Check 'C3 BAD, a junk file, is an unreadable row with a reason' ($bad -and $bad.state -eq 'unreadable' -and $bad.reason) ([string]$bad.state)
  Check 'C4 complete=false while a section did not answer' ($doc -and $doc.complete -eq $false) ([string]$doc.complete)
  Check 'D1 D cannot see the target: declared=false, no levels' ($d -and $d.target_declared -eq $false -and @($d.levels).Count -eq 0) ''
  Check 'D2 ... and its own Ping is counted as by-name, not added' ($d -and [int]$d.by_name_refs -ge 1) ("by_name_refs=" + $d.by_name_refs)
  Check 'L1 the library row carries no caller keys at all (authority rule)' ($l -and $null -eq $l.PSObject.Properties['levels'] -and $null -eq $l.PSObject.Properties['implementors']) ''
  Check 'L2 declarations come from the DBs that hold the unit' (@($doc.declarations | Where-Object { $_.section -eq 'A' }).Count -ge 1 -and @($doc.declarations | Where-Object { $_.section -eq 'LIB' }).Count -eq 0) ''

  # ------------------------------------------------------------- the interface type itself
  $doc = Json @('impact', '--qname', 'uShared.IShared', '--all-projects')
  Check 'T1 an interface TYPE lists the implementing classes per DB' (((ImplNames (Sec $doc 'A')) -match 'uA\.TAImpl') -and ((ImplNames (Sec $doc 'B')) -match 'uB\.TBImpl')) ((ImplNames (Sec $doc 'A')) + ' / ' + (ImplNames (Sec $doc 'B')))

  # ------------------------------------------------------------- declared only in the library
  $doc = Json @('impact', '--qname', 'uLibIntf.ILibThing.Thing', '--all-projects')
  $a = Sec $doc 'A'; $b = Sec $doc 'B'; $l = Sec $doc 'LIB'
  Check 'M1 the library answers the declaration' (@($doc.declarations | Where-Object { $_.section -eq 'LIB' -and $_.kind -eq 'library' }).Count -ge 1 -and $l.target_declared -eq $true) ''
  Check 'M2 the library''s own LibCaller is not counted' ($null -eq $l.PSObject.Properties['levels']) ''
  Check 'M3 project A, which sees it through the library, counts its caller' ((Callers1 $a) -ge 1 -and $a.target_declared -eq $false) ("callers=" + (Callers1 $a))
  Check 'M4 ... and finds its implementor by the interface name, tagged by-name' (@($a.implementors | Where-Object { $_.qname -match 'uA\.TLibImpl' -and $_.edge -eq 'by-name' }).Count -eq 1) (ImplNames $a)
  Check 'M5 B, which never names ILibThing, has no implementor' ((ImplNames $b) -eq '') (ImplNames $b)

  # ------------------------------------------------------------- not found, and the text form
  $doc = Json @('impact', '--qname', 'uNoSuch.TNope.Zap', '--all-projects')
  Check 'N1 a symbol nowhere: exit 1, found=false' ($script:LastExit -eq 1 -and $doc.found -eq $false) "exit=$script:LastExit"
  $txt = Run @('impact', '--qname', 'uShared.IShared.Ping', '--all-projects')
  Check 'X1 text names the unindexed project on its own line' ($txt -match '(?m)^\s+C \[project\] .*NOT INDEXED') ''
  Check 'X2 text ends in a coverage line saying INCOMPLETE' ($txt -match '(?m)^Coverage: \d+ of 6 .*INCOMPLETE') ''
  Check 'X3 text says what it cannot see' ($txt -match 'manifest does not name') ''
  Check 'X4 the unreadable row is on a line too' ($txt -match '(?m)^\s+BAD \[project\] .*UNREADABLE') ''
  Check 'X5 a section with nothing to say shares one line, and is still named' ($txt -match '(?m)^\s+no declaration, no reference: .*\bLIB\b') ''
  Check 'X6 ... while a section with an answer keeps its block' ($txt -match '(?m)^\s+A \[project\] ' -and $txt -match '(?m)^\s+Depth 1:') ''

  # ------------------------------------------------------------- refusal, and the plain verb stays as it was
  $null = Run @('impact', '--qname', 'uShared.IShared.Ping', '--all-projects', '--db', "$work\A.sqlite")
  Check 'R1 --all-projects with --db is refused, exit 2' ($script:LastExit -eq 2) "exit=$script:LastExit"
  $plain = Json @('impact', '--qname', 'uShared.IShared.Ping', '--db', "$work\A.sqlite")
  Check 'R2 without the flag: one DB, no sections key' ($plain -and $null -eq $plain.PSObject.Properties['sections'] -and $plain.levels) ''
  $doc = Json @('impact', '--qname', 'uShared.IShared.Ping', '--all-projects', '--depth', '0')
  Check 'R3 depth 0 returns nothing, exit 1, as the plain verb does' ($script:LastExit -eq 1) "exit=$script:LastExit"

  # ------------------------------------------------------------- a stale index is not authoritative
  [IO.File]::AppendAllText("$work\B\uB.pas", "// edited after indexing`r`n", [Text.Encoding]::ASCII)
  $future = (Get-Date).AddMinutes(5)
  [IO.File]::SetLastWriteTime("$work\B\uB.pas", $future)
  Manifest @('A', 'B', 'D', 'LIB')
  $doc = Json @('impact', '--qname', 'uShared.IShared.Ping', '--all-projects')
  Check 'S1 B, edited after indexing, answers but says stale_files' ((Sec $doc 'B').state -eq 'answered' -and [int](Sec $doc 'B').stale_files -ge 1) ("stale_files=" + (Sec $doc 'B').stale_files)
  Check 'S2 ... which alone makes complete=false, and names the repair' ($doc.complete -eq $false -and (Sec $doc 'B').repair -match '--only B\b') ([string](Sec $doc 'B').repair)

  # ------------------------------------------------------------- positive control: complete can be TRUE
  $null = Run @('index', '--project', "$work\B\B.dpr", '--db', "$work\B.sqlite")
  $null = Run @('index', '--project', "$work\C\C.dpr", '--db', "$work\C.sqlite")
  Manifest @('A', 'B', 'C', 'D', 'LIB')
  $doc = Json @('impact', '--qname', 'uShared.IShared.Ping', '--all-projects')
  Check 'P1 every section current: complete=true' ($doc.complete -eq $true) ([string]$doc.complete)
  Check 'P2 ... and C, now built, answers with its implementor' ((ImplNames (Sec $doc 'C')) -match 'uC\.TCImpl\.Ping') (ImplNames (Sec $doc 'C'))
  $txt = Run @('impact', '--qname', 'uShared.IShared.Ping', '--all-projects')
  Check 'P3 text: no INCOMPLETE and no NOT INDEXED' ($txt -notmatch 'INCOMPLETE' -and $txt -notmatch 'NOT INDEXED') ''

  # ------------------------------------------------------------- two sections, one database: one row, both named
  $secs = "  { `"name`": `"A`", `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$j\\A.sqlite`" },`r`n  { `"name`": `"A2`", `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$j\\A.sqlite`" }"
  WriteAscii "$eng\drag-lint.json" @('{ "indexes": { "sections": [', $secs, ']}}')
  $doc = Json @('impact', '--qname', 'uShared.IShared.Ping', '--all-projects')
  Check 'U1 two sections sharing a DB are one row naming both' (@($doc.sections).Count -eq 1 -and @($doc.sections)[0].name -eq 'A, A2') ([string]@($doc.sections)[0].name)

  # ------------------------------------------------------------- docs must not over-promise
  $root = Join-Path $PSScriptRoot '..\..'
  $pages = @('docs\wiki\Impact-Blast-Radius-symbol.md', 'features\entries\impact-blast-radius-symbol.json')
  foreach ($pg in $pages) {
    $t = [IO.File]::ReadAllText((Join-Path $root $pg))
    Check "W1 $pg documents --all-projects" ($t -match '--all-projects') ''
    Check "W2 $pg does not claim it is automatic" ($t -notmatch '(?i)(completely|fully|entirely)\s+automatic') ''
  }
} finally {
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (could not delete $work)" }
}
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'PASSED' -ForegroundColor Green
exit 0
