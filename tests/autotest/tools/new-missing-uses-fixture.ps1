<#
  new-missing-uses-fixture.ps1 -- writes the PF2 (wave 150) 60-unit fixture project for
  unit-missing-from-uses and indexes it, then takes some uses entries out of the TEXT
  (the index keeps them) so the bound-ref path of the rule fires.

  Shape (deterministic, no randomness):
    System.pas                      -- stands in for the platform library (KnownUnit)
    uD00..uD09 (10 decl units)      -- each declares $Fns functions, a const, a type, an enum
    uU00..uU48 (49 user units)      -- each uses 4 decl units on ONE line and calls every
                                       function of each, reads the const, the type, the enum
  = 60 units. After the index, every user unit whose number is a multiple of 5 loses its
  third uses entry from the text (line count kept), so its refs to that unit are BOUND to a
  unit the text no longer uses -> findings. Many files share the same bound symbols, which
  is what the store-wide memo of TMissingUsesMemo saves.

  Output: <WorkDir>\src (sources), <WorkDir>\out\f.sqlite (index). Prints the DB path.
  pwsh 7; run from a NEUTRAL CWD.
#>
param(
  [Parameter(Mandatory)] [string]$Exe,
  [Parameter(Mandatory)] [string]$WorkDir,
  [int]$Fns = 40
)
$ErrorActionPreference = 'Stop'
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir -Force | Out-Null
function Write-Unit([string]$name, [string]$text) {
  [IO.File]::WriteAllText((Join-Path $srcDir $name), (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
Write-Unit 'System.pas' "unit System;`ninterface`nimplementation`nend.`n"
foreach ($d in 0..9) {
  $u = 'uD{0:D2}' -f $d
  $decl = New-Object Text.StringBuilder
  $impl = New-Object Text.StringBuilder
  foreach ($k in 0..($Fns - 1)) {
    [void]$decl.Append(("function F{0}_{1}: Integer;`n" -f $d, $k))
    [void]$impl.Append(("function F{0}_{1}: Integer;`nbegin`n  Result := {1};`nend;`n" -f $d, $k))
  }
  Write-Unit "$u.pas" ("unit $u;`ninterface`ntype`n  TK$d = class`n  end;`n  TE$d = (e$($d)a, e$($d)b);`nconst`n  C$d = $d;`n" +
    $decl.ToString() + "implementation`n" + $impl.ToString() + "end.`n")
}
$blanks = @()
foreach ($i in 0..48) {
  $u = 'uU{0:D2}' -f $i
  $ds = @(($i % 10), (($i + 1) % 10), (($i + 3) % 10), (($i + 7) % 10)) | Select-Object -Unique
  $body = New-Object Text.StringBuilder
  foreach ($d in $ds) {
    [void]$body.Append(("  X := X + C{0};`n  K{0} := nil;`n  E{0} := e{0}a;`n" -f $d))
    foreach ($k in 0..($Fns - 1)) { [void]$body.Append(("  X := X + F{0}_{1};`n" -f $d, $k)) }
  }
  $vars = ($ds | ForEach-Object { "  K$($_): TK$($_);`n  E$($_): TE$($_);`n" }) -join ''
  $uses = ($ds | ForEach-Object { 'uD{0:D2}' -f $_ }) -join ', '
  Write-Unit "$u.pas" ("unit $u;`ninterface`nfunction Run$i`: Integer;`nimplementation`nuses $uses;`nfunction Run$i`: Integer;`nvar`n  X: Integer;`n" +
    $vars + "begin`n  X := 0;`n" + $body.ToString() + "  Result := X;`nend;`nend.`n")
  if ($i % 5 -eq 0 -and $ds.Count -ge 3) { $blanks += , @("$u.pas", ('uD{0:D2}' -f $ds[2])) }
}
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
[IO.File]::WriteAllText($manifest, '{ "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 }, "indexes": { "outDir": "out", "sections": [ { "name": "SecMemo", "db": "f.sqlite", "include": ["src"] } ] } }', [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\f.sqlite'
Push-Location $WorkDir
try { & $Exe index --all --config $manifest --only SecMemo --jobs 1 2>&1 | Out-Null } finally { Pop-Location }
if (-not (Test-Path $db)) { throw "index did not produce $db" }
# take the entries out of the TEXT only: ', uDnn' -> '' keeps the line count
foreach ($b in $blanks) {
  $p = Join-Path $srcDir $b[0]
  $t = [IO.File]::ReadAllText($p)
  $from = ', ' + $b[1]
  if (-not $t.Contains($from)) { throw "$($b[0]) holds no '$from'" }
  [IO.File]::WriteAllText($p, $t.Replace($from, ''), [Text.Encoding]::ASCII)
}
$db
