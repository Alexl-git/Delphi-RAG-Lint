<#
  run_quit_from_thread.ps1 -- quit-from-thread (OFF by default, 1.47 wave 148 lane PQ): thread code that
  calls PostQuitMessage, Application.Terminate, Halt or ExitProcess outside Synchronize/Queue.

  A TRIGGER-QF-* line fires, a CONTROL-QF-* line stays silent, and nothing else fires. The "platform
  library" is lib\uQfStubLib.pas, indexed into its own DB.

  POSITIVE CONTROLS:
    * on an engine without the rule every TRIGGER check fails (the RED this guard was written against);
    * a plain lint-all has the rule OFF; --enable turns it on, --disable keeps it off;
    * the rule needs the ref_types table: a DB without it answers nothing;
    * a project that declares its own TThread answers nothing;
    * a thread class nothing constructs is labelled "(class never constructed)" and is a hint,
      the constructed one keeps the warning.

  Usage: pwsh -File tests\lint-project\quit-from-thread\run_quit_from_thread.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_qf_$PID"
$Rule = 'quit-from-thread'
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
function Findings([string[]]$Dbs, [string[]]$Extra = @('--enable', $Rule)) {
  $args2 = @(); foreach ($d in $Dbs) { $args2 += @('--db', $d) }
  return @((Parse-Findings (& $exePath lint-all @args2 --format json @Extra 2>$null)) | Where-Object { $_.rule -eq $Rule })
}
function Pos($F) { return '{0}:{1}' -f [IO.Path]::GetFileName($F.file_path), [int]$F.start_line }
function MarkerLines([string]$Dir, [string]$Prefix) {
  $hits = @(Select-String -Path (Join-Path $Dir '*.pas') -Pattern "// $Prefix(-[A-Z0-9-]+)?\s*$")
  return @($hits | ForEach-Object { '{0}:{1}' -f $_.Filename, $_.LineNumber } | Sort-Object)
}
try {
  foreach ($d in 'src', 'lib') {
    $to = Join-Path $scratch $d
    [void](New-Item -ItemType Directory -Force -Path $to)
    Copy-Item (Join-Path $PSScriptRoot "$d\*.pas") $to
  }
  $own = Join-Path $scratch 'own'
  [void](New-Item -ItemType Directory -Force -Path $own)
  $src = Join-Path $scratch 'src'
  $db  = Join-Path $scratch 'qf.sqlite'
  $lib = Join-Path $scratch 'lib.sqlite'
  $ownDb = Join-Path $scratch 'own.sqlite'
  & $exePath index (Join-Path $scratch 'lib') --db $lib 2>&1 | Out-Null
  & $exePath index $src --db $db 2>&1 | Out-Null

  # positive-control: quit-from-thread
  $found = @(Findings @($db, $lib))
  $got   = @($found | ForEach-Object { Pos $_ } | Sort-Object)
  $want  = @(MarkerLines $src 'TRIGGER-QF')
  Check "$Rule fires on exactly the TRIGGER-QF lines" (($got -join ',') -eq ($want -join ',')) "got [$($got -join ',')] want [$($want -join ',')]"
  Check 'the fixture has triggers and controls' (($want.Count -ge 7) -and (@(MarkerLines $src 'CONTROL-QF').Count -ge 5)) "$($want.Count) trigger(s)"

  $post = @($found | Where-Object { (Pos $_) -eq @(MarkerLines $src 'TRIGGER-QF-POST')[0] })
  Check 'the message names the entry and the call' (($post.Count -eq 1) -and ($post[0].message -match 'TQfPoster\.Execute') -and ($post[0].message -match 'PostQuitMessage')) "$($post[0].message)"
  $unbuilt = @($found | Where-Object { (Pos $_) -eq @(MarkerLines $src 'TRIGGER-QF-UNBUILT')[0] })
  Check 'a never-constructed thread class: labelled and a hint' (($unbuilt.Count -eq 1) -and ($unbuilt[0].message -match '\(class never constructed\)$') -and ($unbuilt[0].severity -eq 'hint')) "$($unbuilt[0].severity): $($unbuilt[0].message)"
  Check 'a constructed thread class: a warning, no label' (($post.Count -eq 1) -and ($post[0].message -notmatch 'never constructed') -and ($post[0].severity -eq 'warning')) "$($post[0].severity)"

  $plain = @((Parse-Findings (& $exePath lint-all --db $db --db $lib --format json 2>$null)) | Where-Object { $_.rule -eq $Rule })
  Check 'a plain lint-all: the rule ships OFF' ($plain.Count -eq 0) "$($plain.Count) finding(s)"
  $dis = @((Parse-Findings (& $exePath lint-all --db $db --db $lib --format json --enable $Rule --disable $Rule 2>$null)) | Where-Object { $_.rule -eq $Rule })
  Check '--disable keeps it off' ($dis.Count -eq 0) "$($dis.Count) finding(s)"

  # A project that declares its own TThread is not the RTL's.
  Copy-Item (Join-Path $src 'uQfThreads.pas') $own
  [IO.File]::WriteAllText((Join-Path $own 'uQfOwnThread.pas'), "unit uQfOwnThread;`r`ninterface`r`ntype`r`n  TThread = class(TObject)`r`n  end;`r`n  TTask = class(TObject)`r`n  end;`r`nimplementation`r`nend.`r`n")
  & $exePath index $own --db $ownDb 2>&1 | Out-Null
  $ownHits = @(Findings @($ownDb))
  Check 'a project TThread and TTask are not the RTL ones (no library): nothing fires' ($ownHits.Count -eq 0) (($ownHits | ForEach-Object { Pos $_ }) -join ',')

  $old = Join-Path $scratch 'old.sqlite'
  Copy-Item $db $old
  $py = Join-Path $scratch 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.commit()`nc.close()`n")
  python $py $old
  $tableGone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the control DB really has no ref_types' ($tableGone -match '\b0 row') $tableGone
  $oldHits = @(Findings @($old, $lib))
  Check 'no ref_types table: the rule answers nothing' ($oldHits.Count -eq 0) "$($oldHits.Count) finding(s)"
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }