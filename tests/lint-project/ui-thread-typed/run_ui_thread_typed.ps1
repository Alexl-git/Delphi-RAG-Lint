<#
  run_ui_thread_typed.ps1 -- ui-access-in-thread-typed, the lint rule on the static type of the
  receiver: a reference reached from thread code whose receiver descends from a UI root.

  The rule is asserted line by line against markers in the fixture: a TRIGGER-UIT-* line fires,
  a CONTROL-UIT-* line stays silent, and nothing else fires. The fixture's "platform library"
  is the stub units in lib\, indexed into their own DB, so no real library index is opened.

  POSITIVE CONTROLS:
    * with a library that lacks the classes the closures end at TForm / TLabel: only the two
      globals answer, which proves every other finding comes from the indexed ancestry;
    * without the ref_types table (an index older than 1.44) it answers NOTHING;
    * a project that declares its own TControl and TTask answers NOTHING;
    * a plain lint-all has the rule OFF.
  On an engine without the rule every TRIGGER check fails: the RED this guard was written against.

  Usage: pwsh -File tests\lint-project\ui-thread-typed\run_ui_thread_typed.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_uit_$PID"
$Rule = 'ui-access-in-thread-typed'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function Findings([string[]]$Dbs, [string[]]$Extra = @('--rule', $Rule)) {
  $args2 = @(); foreach ($d in $Dbs) { $args2 += @('--db', $d) }
  return @((Parse-Findings (& $exePath lint-all @args2 --format json @Extra 2>$null)) | Where-Object { $_.rule -eq $Rule })
}
function Pos($F) { return '{0}:{1}' -f [IO.Path]::GetFileName($F.file_path), [int]$F.start_line }
function MarkerLines([string]$Dir, [string]$Prefix) {
  $hits = @(Select-String -Path (Join-Path $Dir '*.pas') -Pattern "// $Prefix(-[A-Z0-9-]+)?\s*$")
  return @($hits | ForEach-Object { '{0}:{1}' -f $_.Filename, $_.LineNumber } | Sort-Object)
}
try {
  foreach ($d in 'src', 'lib', 'own') {
    $to = Join-Path $scratch $d
    [void](New-Item -ItemType Directory -Force -Path $to)
    Copy-Item (Join-Path $PSScriptRoot "$d\*.pas") $to
  }
  $src = Join-Path $scratch 'src'
  $db  = Join-Path $scratch 'tt.sqlite'
  $lib = Join-Path $scratch 'lib.sqlite'
  $own = Join-Path $scratch 'own.sqlite'
  & $exePath index (Join-Path $scratch 'lib') --db $lib 2>&1 | Out-Null
  & $exePath index $src --db $db 2>&1 | Out-Null
  & $exePath index (Join-Path $scratch 'own') --db $own 2>&1 | Out-Null

  # positive-control: ui-access-in-thread-typed
  $found = @(Findings @($db, $lib))
  $got   = @($found | ForEach-Object { Pos $_ } | Sort-Object)
  $want  = @(MarkerLines $src 'TRIGGER-UIT')
  Check "$Rule fires on exactly the TRIGGER-UIT lines" (($got -join ',') -eq ($want -join ',')) "got [$($got -join ',')] want [$($want -join ',')]"
  Check 'the fixture has triggers and controls' (($want.Count -ge 15) -and (@(MarkerLines $src 'CONTROL-UIT').Count -ge 15)) "$($want.Count) trigger(s)"

  $hopTwo = @($found | Where-Object { (Pos $_) -eq @(MarkerLines $src 'TRIGGER-UIT-HOP-2')[0] })
  Check 'a call hop prints the whole path and the witness' (($hopTwo.Count -eq 1) -and ($hopTwo[0].message -match 'TTtWorker\.Execute -> TTtWorker\.Relay -> TTtForm\.TouchUi') -and ($hopTwo[0].message -match 'Label1\.Caption')) "$($hopTwo[0].message)"
  $hopFile = @($found | Where-Object { (Pos $_) -eq @(MarkerLines $src 'TRIGGER-UIT-HOP-1')[0] })
  Check 'a hop into another unit names the witness file' (($hopFile.Count -eq 1) -and ($hopFile[0].message -match 'uTtForm\.pas:\d+')) "$($hopFile[0].message)"
  $direct = @($found | Where-Object { (Pos $_) -eq @(MarkerLines $src 'TRIGGER-UIT-CAST')[0] })
  Check 'a direct finding names the type and the root' (($direct.Count -eq 1) -and ($direct[0].message -match 'TLabel') -and ($direct[0].message -match 'TControl')) "$($direct[0].message)"

  # A library that declares none of the classes (the own\ DB), so a real one is never resolved instead.
  $noLib = @(Findings @($db, $own) | ForEach-Object { Pos $_ } | Sort-Object)
  $names = @(MarkerLines $src 'TRIGGER-UIT-APPLICATION') + @(MarkerLines $src 'TRIGGER-UIT-SCREEN') | Sort-Object
  Check 'no ancestry in the library: only the Application and Screen globals answer' (($noLib -join ',') -eq ($names -join ',')) "got [$($noLib -join ',')] want [$($names -join ',')]"

  $ownHits = @(Findings @($own, $lib))
  Check 'a project TControl and TTask are not the VCL ones' ($ownHits.Count -eq 0) (($ownHits | ForEach-Object { Pos $_ }) -join ',')

  $plain = @((Parse-Findings (& $exePath lint-all --db $db --db $lib --format json 2>$null)) | Where-Object { $_.rule -eq $Rule })
  Check 'a plain lint-all: the rule ships OFF' ($plain.Count -eq 0) "$($plain.Count) finding(s)"
  $enabled = @(Findings @($db, $lib) @('--enable', $Rule))
  Check '--enable switches it on' ($enabled.Count -eq $want.Count) "$($enabled.Count) of $($want.Count)"

  $oneFile = Join-Path $src 'uTtThreads.pas'
  $one = @((Parse-Findings (& $exePath lint $oneFile --db $db --library-db $lib --format json --rule $Rule 2>$null)) | Where-Object { $_.rule -eq $Rule })
  $wantOne = @($want | Where-Object { $_ -like 'uTtThreads*' })
  Check 'lint <file> --rule answers that file only' (@($one | ForEach-Object { Pos $_ } | Sort-Object) -join ',' -eq ($wantOne -join ',')) "$($one.Count) of $($wantOne.Count)"

  $old = Join-Path $scratch 'old.sqlite'
  Copy-Item $db $old
  $py = Join-Path $scratch 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.commit()`nc.close()`n")
  python $py $old
  $tableGone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the control DB really has no ref_types' ($tableGone -match '\b0 row') $tableGone
  $oldHits = @(Findings @($old, $lib))
  Check 'no ref_types table (an index older than 1.44): the rule answers nothing' ($oldHits.Count -eq 0) "$($oldHits.Count) finding(s)"
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
