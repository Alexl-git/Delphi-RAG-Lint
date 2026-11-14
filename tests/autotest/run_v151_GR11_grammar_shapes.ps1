<#
  run_v151_GR11_grammar_shapes.ps1 -- v151 GR11: the extractor reads the grammar v1.4.11 / v1.4.12 shapes.

  Fixtures: tests\index\v151-gr11\ (GR11CodePage.pas, GR11Labels.pas, GR11Orphan.pas, GR11IncHost.pas +
  GR11IncHeaders.inc). Every check runs under BOTH define states: state A = the fixtures as they are
  (GR11_ALT undefined), state B = the same files with {$DEFINE GR11_ALT} inserted after the unit line.
  Lines are located by text, never by number, so the inserted line cannot shift a check.

  Shapes (grammar):
    declStringCodePage  v1.4.11: `type AnsiString(1252)` / `type AnsiString(CP_X)` is ONE node
                        (base: identifier, codePage: literalNumber | identifier);
    numeric labels      v1.4.11: `label 99;`, `99:` and `goto 99` take a literalNumber (was an ERROR);
    classBodyOrphan     v1.4.11: `{$IFDEF X} TFoo = class(TOther); {$ELSE} TFoo = class(TBase) {$ENDIF}
                        protected ... end;` -- with X defined the members follow a complete short class;
    include-root header v1.4.12: `procedure P;` with no body at an include-file root is a declProc
                        (was an ERROR; the last header survived only through the extractor workaround).

  Checks (A and B unless noted):
    P1  no parse error in any fixture file (needs the v1.4.12 DLL beside the exe for the .inc);
    C1  each code-page type declaration emits a type_use ref to its base AnsiString;
    C2  a code-page given by a constant emits a read ref bound to that constant;
    C3  the code-page type's signature is its base type, as for `type AnsiString` without a code page;
    L1  the routine with numeric labels is extracted whole: qualified name, its parameter reads bound;
    L2  no stray `end` call ref (the v1.4.10 error-recovery artefact);
    L3  goto-statement fires on every `goto 99` / `goto Gr11Done` of the active branch (the lint tree
        sees the numeric target) -- POSITIVE CONTROL: it does NOT fire with --disable goto-statement;
    O1  B only: the orphan members belong to the class declared just before them
        (field TGr11Dock.FGr11A, method TGr11Dock.Gr11DockRun), never to the unit;
    O2  A: TGr11Dock is an ordinary class with heritage TGr11Base and its own members; the next class
        TGr11After is intact in A and B (heritage, method, bound refs);
    I1  the include's three bare headers are routine symbols.
  RED: C1-C3 and O1 fail on the 1.50.0 extractor with any grammar; P1 / L1 / L2 fail on v1.4.10;
  P1 for the .inc fails on v1.4.11.

  Usage: pwsh -File tests\autotest\run_v151_GR11_grammar_shapes.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$fxDir = Join-Path $Repo 'tests\index\v151-gr11'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Get-Line([string]$File, [string]$Text) {
  $hit = Select-String -Path $File -SimpleMatch -Pattern $Text | Select-Object -First 1
  if (-not $hit) { throw "fixture $File lost the line '$Text'" }
  return $hit.LineNumber
}
function Invoke-Sql([string]$Db, [string]$Query) {
  $txt = (& $exePath sql --db $Db --query $Query --json 2>$null) -join "`n"
  $doc = $txt | ConvertFrom-Json
  $cols = @($doc.columns | ForEach-Object { $_.name })
  $out = foreach ($r in @($doc.rows)) {
    $o = [ordered]@{}
    for ($k = 0; $k -lt $cols.Count; $k++) { $o[$cols[$k]] = $r[$k] }
    [pscustomobject]$o
  }
  return , @($out)
}
function Get-Findings([string]$Pas, [string]$Db, [string[]]$Extra) {
  $txt = (& $exePath lint $Pas --db $Db --library-db none @Extra --json 2>$null) -join "`n"
  if ($txt.Trim() -eq '') { return , @() }
  return , @($txt | ConvertFrom-Json)
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('gr11-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
try {
  foreach ($state in 'A', 'B') {
    $dir = Join-Path $tmp $state
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    foreach ($f in Get-ChildItem $fxDir -File) {
      $text = [IO.File]::ReadAllText($f.FullName)
      if ($state -eq 'B' -and $f.Extension -eq '.pas') {
        $i = $text.IndexOf("`r`n")
        $text = $text.Substring(0, $i + 2) + "{`$DEFINE GR11_ALT}`r`n" + $text.Substring($i + 2)
      }
      [IO.File]::WriteAllText((Join-Path $dir $f.Name), $text, [Text.Encoding]::ASCII)
    }
    $db = Join-Path $tmp "$state.sqlite"
    $log = (& $exePath index $dir --db $db --library-db none 2>&1) -join "`n"
    $tag = "[$state]"

    # P1
    $diag = @($log -split "`n" | Where-Object { $_ -match 'parse error' })
    Check "$tag P1 no parse error in any fixture file" ($diag.Count -eq 0) ($diag -join ' | ')

    # C1-C3
    $cp = Join-Path $dir 'GR11CodePage.pas'
    $ln1252 = Get-Line $cp 'TGr11Ansi1252 = type AnsiString(1252)'
    $lnNamed = Get-Line $cp 'TGr11AnsiNamed = type AnsiString(CP_GR11)'
    $lnAlt = Get-Line $cp ($(if ($state -eq 'B') { 'TGr11AnsiAlt = type AnsiString(65001)' } else { 'TGr11AnsiAlt = type AnsiString(1250)' }))
    $refs = Invoke-Sql $db "select r.kind, r.name_text, r.start_line, r.symbol_id, s.qualified_name from refs r join files f on f.id = r.file_id left join symbols s on s.id = r.symbol_id where f.path like '%GR11CodePage.pas'"
    foreach ($ln in $ln1252, $lnNamed, $lnAlt) {
      $hit = @($refs | Where-Object { $_.kind -eq 'type_use' -and $_.name_text -eq 'AnsiString' -and $_.start_line -eq $ln })
      Check "$tag C1 code-page type on line $ln refers to its base AnsiString" ($hit.Count -eq 1) ("refs on the line: " + (($refs | Where-Object { $_.start_line -eq $ln } | ForEach-Object { "$($_.kind):$($_.name_text)" }) -join ','))
    }
    $cpRef = @($refs | Where-Object { $_.kind -eq 'read' -and $_.name_text -eq 'CP_GR11' -and $_.start_line -eq $lnNamed })
    Check "$tag C2 code page given by a constant is a read of it" (($cpRef.Count -eq 1) -and ($cpRef[0].qualified_name -eq 'GR11CodePage.CP_GR11')) ($cpRef | ConvertTo-Json -Compress)
    $sig = Invoke-Sql $db "select name, signature from symbols where name in ('TGr11Ansi1252', 'TGr11AnsiNamed', 'TGr11AnsiAlt', 'TGr11Plain')"
    $bad = @($sig | Where-Object { $_.signature -ne 'AnsiString' })
    Check "$tag C3 code-page type signature is the base type" ($bad.Count -eq 0) (($bad | ForEach-Object { "$($_.name)=$($_.signature)" }) -join ',')

    # L1-L3
    $lb = Join-Path $dir 'GR11Labels.pas'
    $jump = Invoke-Sql $db "select qualified_name from symbols where name = 'Gr11Jump'"
    Check "$tag L1 Gr11Jump extracted once as GR11Labels.Gr11Jump" ((@($jump).Count -eq 1) -and ($jump[0].qualified_name -eq 'GR11Labels.Gr11Jump')) (($jump | ForEach-Object { $_.qualified_name }) -join ',')
    $pnLines = @((Get-Line $lb 'if pN > 0 then'), (Get-Line $lb 'Result := Result + pN'))
    $pn = Invoke-Sql $db "select r.start_line, r.symbol_id from refs r join files f on f.id = r.file_id where f.path like '%GR11Labels.pas' and r.kind = 'read' and r.name_text = 'pN'"
    $unbound = @($pn | Where-Object { ($pnLines -contains $_.start_line) -and ($null -eq $_.symbol_id) })
    $seen = @($pn | Where-Object { $pnLines -contains $_.start_line })
    Check "$tag L1 parameter reads around the numeric labels are bound" (($seen.Count -eq 2) -and ($unbound.Count -eq 0)) "seen=$($seen.Count) unbound=$($unbound.Count)"
    $endCall = Invoke-Sql $db "select r.start_line from refs r join files f on f.id = r.file_id where f.path like '%GR11Labels.pas' and r.name_text = 'end'"
    Check "$tag L2 no stray 'end' ref" (@($endCall).Count -eq 0)
    $gotoLines = @((Get-Line $lb 'goto 99;'))
    if ($state -eq 'B') { $gotoLines += (Get-Line $lb 'goto Gr11Done;') }
    $fl = Get-Findings $lb $db @('--rule', 'goto-statement')
    $gl = @($fl | Where-Object { $_.rule -eq 'goto-statement' } | ForEach-Object { [int]$_.start_line })
    $missing = @($gotoLines | Where-Object { $gl -notcontains $_ })
    Check "$tag L3 goto-statement fires on every active goto (numeric target included)" ($missing.Count -eq 0) ("fires at " + ($gl -join ',') + "; expected " + ($gotoLines -join ','))
    $off = Get-Findings $lb $db @('--rule', 'goto-statement', '--disable', 'goto-statement')
    Check "$tag L3 POSITIVE CONTROL: --disable goto-statement silences it" (@($off | Where-Object { $_.rule -eq 'goto-statement' }).Count -eq 0)

    # O1 / O2
    $os = Invoke-Sql $db "select s.kind, s.qualified_name, s.heritage from symbols s join files f on f.id = s.file_id where f.path like '%GR11Orphan.pas'"
    $q = @($os | ForEach-Object { $_.qualified_name })
    $dock = @($os | Where-Object { $_.qualified_name -eq 'GR11Orphan.TGr11Dock' })
    if ($state -eq 'B') {
      Check "$tag O1 orphan field belongs to TGr11Dock" (($q -contains 'GR11Orphan.TGr11Dock.FGr11A') -and ($q -notcontains 'GR11Orphan.FGr11A')) ($q -join ',')
      Check "$tag O1 orphan method belongs to TGr11Dock" (($q -contains 'GR11Orphan.TGr11Dock.Gr11DockRun') -and ($q -notcontains 'GR11Orphan.Gr11DockRun')) ($q -join ',')
      $m = @($os | Where-Object { $_.qualified_name -eq 'GR11Orphan.TGr11Dock.Gr11DockRun' })
      Check "$tag O1 orphan method is a method" (($m.Count -eq 1) -and ($m[0].kind -eq 'method')) ($m | ConvertTo-Json -Compress)
      Check "$tag O1 TGr11Dock keeps the THEN-branch heritage" (($dock.Count -eq 1) -and ($dock[0].heritage -eq 'TGr11Other')) ($dock | ConvertTo-Json -Compress)
    } else {
      Check "$tag O2 TGr11Dock is an ordinary class of TGr11Base with its members" (($dock.Count -eq 1) -and ($dock[0].heritage -eq 'TGr11Base') -and ($q -contains 'GR11Orphan.TGr11Dock.FGr11A') -and ($q -contains 'GR11Orphan.TGr11Dock.Gr11DockRun')) ($q -join ',')
    }
    $after = @($os | Where-Object { $_.qualified_name -eq 'GR11Orphan.TGr11After' })
    Check "$tag O2 the class after the orphan is intact" (($after.Count -eq 1) -and ($after[0].heritage -eq 'TGr11Base') -and ($q -contains 'GR11Orphan.TGr11After.Gr11AfterRun')) ($q -join ',')
    $or = Invoke-Sql $db "select r.symbol_id from refs r join files f on f.id = r.file_id where f.path like '%GR11Orphan.pas' and r.name_text = 'Gr11BaseRun' and r.kind = 'call'"
    Check "$tag O2 inherited call after the orphan is bound" ((@($or).Count -eq 1) -and ($null -ne $or[0].symbol_id))

    # I1
    $inc = Invoke-Sql $db "select s.name, s.kind from symbols s join files f on f.id = s.file_id where f.path like '%GR11IncHeaders.inc' and s.kind in ('procedure', 'function')"
    $names = @($inc | ForEach-Object { $_.name })
    Check "$tag I1 all three include-root headers are routines" (($names -contains 'Gr11IncFirst') -and ($names -contains 'Gr11IncSecond') -and ($names -contains 'Gr11IncLast')) ($names -join ',')
  }
} finally {
  try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Host "note: scratch left at $tmp" }
}
if ($script:Failed) { Write-Host 'run_v151_GR11_grammar_shapes: FAIL'; exit 1 }
Write-Host 'run_v151_GR11_grammar_shapes: PASS'
